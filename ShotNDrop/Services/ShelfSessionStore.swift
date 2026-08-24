import Foundation
import Darwin

/// Per-launch session store rooted at `NSTemporaryDirectory()`. Each launch
/// mints a `ShotNDropSession-<UUIDv4>/` directory and acquires a
/// `flock(LOCK_EX | LOCK_NB)` on its `.lock` file for the process lifetime.
/// At launch, sibling `ShotNDropSession-*` directories whose `.lock` cannot
/// be exclusively acquired are treated as live and left alone; ones that can
/// be locked are orphaned (crash or clean exit released the OS `flock`) and
/// removed.
///
/// Access to `FileManager` happens off the main actor via a serial dispatch
/// queue.
public final class ShelfSessionStore: @unchecked Sendable {
    public static let directoryPrefix: String = "ShotNDropSession-"
    public static let lockFileName: String = ".lock"

    public let rootDirectory: URL
    public let sessionDirectory: URL

    private let ioQueue = DispatchQueue(label: "com.shotndrop.session-store.io")
    private let fileManager: FileManager
    private let lockFD: Int32

    /// Creates the session-directory + lock, then sweeps siblings.
    /// `parentDirectory` defaults to `NSTemporaryDirectory()`; tests can
    /// override to isolate.
    public init(parentDirectory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let root = parentDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.rootDirectory = root

        let sessionName = "\(Self.directoryPrefix)\(UUID().uuidString)"
        let session = root.appendingPathComponent(sessionName, isDirectory: true)
        try fileManager.createDirectory(at: session, withIntermediateDirectories: true)
        self.sessionDirectory = session

        let lockURL = session.appendingPathComponent(Self.lockFileName)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            throw NSError(domain: "ShelfSessionStore", code: Int(errno),
                          userInfo: [NSLocalizedDescriptionKey: "Failed to open lock file at \(lockURL.path)"])
        }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            throw NSError(domain: "ShelfSessionStore", code: Int(errno),
                          userInfo: [NSLocalizedDescriptionKey: "Failed to acquire flock on \(lockURL.path)"])
        }
        self.lockFD = fd

        sweepUnlockedSiblings()
    }

    deinit {
        // Best-effort release; `clear()` is the authoritative teardown.
        flock(lockFD, LOCK_UN)
        close(lockFD)
    }

    /// Copies `bytes` to `<sessionDirectory>/<id>.<extension>` on the IO
    /// queue and returns the destination URL. Reuses an existing file with
    /// the same id when called with `overwrite: true`.
    public func write(
        bytes: Data,
        id: UUID,
        preferredExtension: String
    ) throws -> URL {
        let ext = preferredExtension.isEmpty ? "bin" : preferredExtension
        let destination = sessionDirectory.appendingPathComponent("\(id.uuidString).\(ext)")
        var writeError: Error?
        ioQueue.sync {
            do {
                try bytes.write(to: destination, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let writeError { throw writeError }
        return destination
    }

    public func remove(id: UUID) {
        ioQueue.sync {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: sessionDirectory,
                includingPropertiesForKeys: nil
            ) else { return }
            let prefix = id.uuidString
            for entry in entries where entry.lastPathComponent.hasPrefix(prefix) {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    /// Removes every file inside the session directory except the lock file
    /// itself. Intended for `CLEAR` — the lock (and thus this session's
    /// ownership) stays acquired.
    public func clearContents() {
        ioQueue.sync {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: sessionDirectory,
                includingPropertiesForKeys: nil
            ) else { return }
            for entry in entries where entry.lastPathComponent != Self.lockFileName {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    /// Releases the flock and removes the entire session directory. Call
    /// from `applicationWillTerminate:`.
    public func shutdown() {
        ioQueue.sync {
            flock(lockFD, LOCK_UN)
            close(lockFD)
            try? fileManager.removeItem(at: sessionDirectory)
        }
    }

    /// Attempts to remove sibling `ShotNDropSession-*` directories under the
    /// same root by testing their lock files with a non-blocking exclusive
    /// flock. A directory whose lock cannot be acquired belongs to a live
    /// process and is left alone.
    public func sweepUnlockedSiblings() {
        let root = rootDirectory
        let currentPath = sessionDirectory.standardizedFileURL.path
        let fm = fileManager
        ioQueue.sync {
            guard let contents = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) else { return }
            for entry in contents {
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir else { continue }
                guard entry.lastPathComponent.hasPrefix(Self.directoryPrefix) else { continue }
                if entry.standardizedFileURL.path == currentPath { continue }
                let siblingLock = entry.appendingPathComponent(Self.lockFileName)
                let fd = open(siblingLock.path, O_CREAT | O_RDWR, 0o644)
                if fd < 0 {
                    // If we cannot even open the lock file, be conservative and skip.
                    continue
                }
                if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                    // Acquired — nobody owns it — orphan. Remove directory.
                    flock(fd, LOCK_UN)
                    close(fd)
                    try? fm.removeItem(at: entry)
                } else {
                    // In use by a live sibling.
                    close(fd)
                }
            }
        }
    }
}
