import Foundation
import AppKit

public enum WatchedFolderError: Error, Sendable {
    case userCancelled
    case notADirectory
    case bookmarkCreationFailed(underlying: Error)
    case bookmarkResolutionFailed(underlying: Error)
    case accessDenied
    case stale
}

/// Owns the user-selected folder URL, its security-scoped bookmark data and the
/// scoped-access lease. Read-only bookmark; never writes to the source folder.
@MainActor
public final class WatchedFolderAccess {
    private static let defaultsKey = "ShotNDrop.watchedFolderBookmark"

    private let defaults: UserDefaults
    private var scopedURL: URL?
    private var isAccessing: Bool = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var currentFolder: URL? { scopedURL }

    // MARK: - Onboarding

    /// Prompt the user to choose a folder. Returns the resolved scoped URL.
    /// Persists a read-only, security-scoped bookmark for future launches.
    public func promptForFolder() throws -> URL {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose the folder where macOS saves screenshots."
        panel.prompt = "Choose"

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            throw WatchedFolderError.userCancelled
        }
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            throw WatchedFolderError.notADirectory
        }
        try persistBookmark(for: url)
        try startScopedAccess(on: url)
        return url
    }

    /// Restore access from a previously saved bookmark. Refreshes stale
    /// bookmarks before retiring the existing lease so we never drop scope
    /// between two writes.
    public func restoreFromBookmark() throws -> URL {
        guard let data = defaults.data(forKey: Self.defaultsKey) else {
            throw WatchedFolderError.accessDenied
        }
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw WatchedFolderError.bookmarkResolutionFailed(underlying: error)
        }

        if isStale {
            // Refresh before releasing the previous lease.
            try persistBookmark(for: url)
        }
        try startScopedAccess(on: url)
        return url
    }

    /// Stop the currently active scoped-access lease, if any.
    public func stopScopedAccess() {
        if isAccessing, let url = scopedURL {
            url.stopAccessingSecurityScopedResource()
        }
        isAccessing = false
        scopedURL = nil
    }

    // MARK: - Private

    private func startScopedAccess(on url: URL) throws {
        // Release any previous lease first so we don't leak scope counts.
        stopScopedAccess()
        let ok = url.startAccessingSecurityScopedResource()
        guard ok else {
            throw WatchedFolderError.accessDenied
        }
        self.scopedURL = url
        self.isAccessing = true
    }

    private func persistBookmark(for url: URL) throws {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(data, forKey: Self.defaultsKey)
        } catch {
            throw WatchedFolderError.bookmarkCreationFailed(underlying: error)
        }
    }
}
