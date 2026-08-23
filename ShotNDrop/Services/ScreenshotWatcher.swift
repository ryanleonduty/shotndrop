import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Injection points

public protocol MonotonicClock: Sendable {
    func now() -> Date
}

public struct SystemClock: MonotonicClock {
    public init() {}
    public func now() -> Date { Date() }
}

/// Snapshot of a single filesystem entry as needed for reconciliation.
public struct FolderEntry: Sendable, Hashable {
    public let url: URL
    public let standardizedPath: String
    public let creationDate: Date
    public let modificationDate: Date
    public let size: Int64
    public let resourceIdentifier: Data?
    public let isRegularFile: Bool
    public let contentType: UTType?

    public init(
        url: URL,
        standardizedPath: String,
        creationDate: Date,
        modificationDate: Date,
        size: Int64,
        resourceIdentifier: Data?,
        isRegularFile: Bool,
        contentType: UTType?
    ) {
        self.url = url
        self.standardizedPath = standardizedPath
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.size = size
        self.resourceIdentifier = resourceIdentifier
        self.isRegularFile = isRegularFile
        self.contentType = contentType
    }

    public var identity: ScreenshotIdentity {
        ScreenshotIdentity(
            resourceIdentifier: resourceIdentifier,
            standardizedPath: standardizedPath,
            creationDate: creationDate,
            size: size
        )
    }

    public var isImage: Bool {
        guard isRegularFile, let type = contentType else { return false }
        return type.conforms(to: .image)
    }
}

public protocol FolderEnumerator: Sendable {
    func shallowSnapshot(of folder: URL) throws -> [FolderEntry]
}

public protocol ImageReadinessProbe: Sendable {
    /// Returns true when the file at the given URL is a complete, decodable image.
    func isComplete(_ url: URL) -> Bool
}

/// Default enumerator using FileManager + URLResourceValues.
public struct DefaultFolderEnumerator: FolderEnumerator {
    public init() {}
    public func shallowSnapshot(of folder: URL) throws -> [FolderEntry] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .fileResourceIdentifierKey,
            .contentTypeKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        )
        return urls.compactMap { url -> FolderEntry? in
            let rv = try? url.resourceValues(forKeys: Set(keys))
            let resourceID: Data? = Self.dataIdentifier(for: url)
            return FolderEntry(
                url: url.standardizedFileURL,
                standardizedPath: url.standardizedFileURL.path,
                creationDate: rv?.creationDate ?? .distantPast,
                modificationDate: rv?.contentModificationDate ?? .distantPast,
                size: Int64(rv?.fileSize ?? 0),
                resourceIdentifier: resourceID,
                isRegularFile: rv?.isRegularFile ?? false,
                contentType: rv?.contentType
            )
        }
    }

    /// Encode fileResourceIdentifier into stable Data. Falls back to nil when unavailable.
    private static func dataIdentifier(for url: URL) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
              let id = values.fileResourceIdentifier
        else { return nil }
        // NSCopying — archive via NSKeyedArchiver where possible; nil otherwise.
        if let coded = try? NSKeyedArchiver.archivedData(withRootObject: id, requiringSecureCoding: false) {
            return coded
        }
        return nil
    }
}

/// Default readiness probe uses ImageIO. Considered complete when
/// CGImageSourceGetStatus == .statusComplete.
public struct DefaultImageReadinessProbe: ImageReadinessProbe {
    public init() {}
    public func isComplete(_ url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        let status = CGImageSourceGetStatus(src)
        return status == .statusComplete
    }
}

// MARK: - Watcher engine

/// A pending candidate waiting for `quietWindow` seconds of unchanged
/// metadata after an ImageIO-complete decode.
public struct PendingCandidate: Sendable, Equatable {
    public let entry: FolderEntry
    /// The last time this file was observed with these exact fields
    /// (size/modificationDate/creationDate). Reset whenever anything changes.
    public var stabilityAnchor: Date
    /// When it first entered the pending set. Used for the 5-minute expiry.
    public let admittedAt: Date
    /// The last time the readiness probe reported complete. If nil the
    /// file has not yet completed a decode.
    public var lastCompleteAt: Date?

    public init(
        entry: FolderEntry,
        stabilityAnchor: Date,
        admittedAt: Date,
        lastCompleteAt: Date? = nil
    ) {
        self.entry = entry
        self.stabilityAnchor = stabilityAnchor
        self.admittedAt = admittedAt
        self.lastCompleteAt = lastCompleteAt
    }
}

public struct EngineDecision: Sendable, Equatable {
    public let accepted: [ScreenshotItem]
    public let pendingCount: Int

    public init(accepted: [ScreenshotItem], pendingCount: Int) {
        self.accepted = accepted
        self.pendingCount = pendingCount
    }
}

/// Pure reconciliation engine. Fully deterministic; no filesystem calls.
public struct WatcherEngine: Sendable {
    public static let quietWindow: TimeInterval = 0.5
    public static let pendingCap: Int = 64
    public static let pendingExpiry: TimeInterval = 5 * 60

    /// The cutover: any identity whose creationDate is >= this is a candidate.
    public let baselineStartedAt: Date

    /// Identities that have already been accepted in this session
    /// (dedupe across watcher recovery).
    public private(set) var acceptedIdentities: Set<ScreenshotIdentity> = []

    /// Currently pending candidates keyed by identity.
    public private(set) var pending: [ScreenshotIdentity: PendingCandidate] = [:]

    public init(baselineStartedAt: Date) {
        self.baselineStartedAt = baselineStartedAt
    }

    /// Reconcile a shallow snapshot at time `now` using `probe` to check
    /// ImageIO completion. Returns items ready to enqueue plus the pending count.
    public mutating func reconcile(
        snapshot: [FolderEntry],
        now: Date,
        probe: ImageReadinessProbe
    ) -> EngineDecision {
        // Prune long-pending entries first (5-minute expiry).
        pending = pending.filter { _, candidate in
            now.timeIntervalSince(candidate.admittedAt) < Self.pendingExpiry
        }

        // Remove pending entries that vanished from the snapshot.
        let snapshotIdentities = Set(snapshot.map(\.identity))
        pending = pending.filter { snapshotIdentities.contains($0.key) }

        var accepted: [ScreenshotItem] = []

        for entry in snapshot {
            guard entry.isImage else { continue }
            guard entry.creationDate >= baselineStartedAt else { continue }
            let identity = entry.identity
            if acceptedIdentities.contains(identity) { continue }

            if var existing = pending[identity] {
                // Metadata change resets the stability anchor.
                if existing.entry.size != entry.size
                    || existing.entry.modificationDate != entry.modificationDate
                    || existing.entry.creationDate != entry.creationDate {
                    existing = PendingCandidate(
                        entry: entry,
                        stabilityAnchor: now,
                        admittedAt: existing.admittedAt,
                        lastCompleteAt: nil
                    )
                    pending[identity] = existing
                    continue
                }
                // Update from the freshest URL/values.
                existing = PendingCandidate(
                    entry: entry,
                    stabilityAnchor: existing.stabilityAnchor,
                    admittedAt: existing.admittedAt,
                    lastCompleteAt: existing.lastCompleteAt
                )

                let complete = probe.isComplete(entry.url)
                if complete {
                    if existing.lastCompleteAt == nil {
                        existing.lastCompleteAt = now
                    }
                    // Ready when ImageIO-complete AND >=quietWindow seconds since
                    // metadata last changed AND the file has been complete for
                    // at least the quiet window as well.
                    let stableFor = now.timeIntervalSince(existing.stabilityAnchor)
                    let completeFor = existing.lastCompleteAt.map { now.timeIntervalSince($0) } ?? 0
                    if stableFor >= Self.quietWindow && completeFor >= 0 {
                        let item = ScreenshotItem(
                            identity: identity,
                            url: entry.url,
                            creationDate: entry.creationDate,
                            size: entry.size,
                            detectedAt: now
                        )
                        accepted.append(item)
                        acceptedIdentities.insert(identity)
                        pending.removeValue(forKey: identity)
                        continue
                    }
                } else {
                    // Incomplete probe resets the completion clock but not stability.
                    existing.lastCompleteAt = nil
                }
                pending[identity] = existing
            } else {
                guard pending.count < Self.pendingCap else { continue }
                pending[identity] = PendingCandidate(
                    entry: entry,
                    stabilityAnchor: now,
                    admittedAt: now,
                    lastCompleteAt: probe.isComplete(entry.url) ? now : nil
                )
            }
        }

        // Deterministic acceptance order: creationDate asc, then standardizedPath asc.
        accepted.sort { lhs, rhs in
            if lhs.creationDate != rhs.creationDate {
                return lhs.creationDate < rhs.creationDate
            }
            return lhs.identity.standardizedPath < rhs.identity.standardizedPath
        }

        return EngineDecision(accepted: accepted, pendingCount: pending.count)
    }

    /// Discard everything (used on watcher generation invalidation).
    public mutating func invalidate() {
        pending.removeAll()
        // acceptedIdentities is intentionally preserved through recovery so a
        // relaunch of the source does not re-enqueue the same item.
    }
}

// MARK: - Watcher

public enum WatcherStopReason: Sendable, Equatable {
    case userReconfigured
    case folderInvalid
    case shuttingDown
}

/// Live watcher that drives `WatcherEngine`. Isolated to its own dispatch queue.
public final class ScreenshotWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.shotndrop.watcher.serial")
    private let debounceInterval: TimeInterval = 0.2
    private let pollInterval: TimeInterval = 2.0

    private let clock: MonotonicClock
    private let enumerator: FolderEnumerator
    private let probe: ImageReadinessProbe

    private var folder: URL?
    private var descriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?
    private var debounceWorkItem: DispatchWorkItem?
    private var engine: WatcherEngine?
    private var generation: UInt64 = 0

    private let onAccepted: @MainActor @Sendable ([ScreenshotItem]) -> Void
    private let onStopped: @MainActor @Sendable (WatcherStopReason) -> Void

    public init(
        clock: MonotonicClock = SystemClock(),
        enumerator: FolderEnumerator = DefaultFolderEnumerator(),
        probe: ImageReadinessProbe = DefaultImageReadinessProbe(),
        onAccepted: @escaping @MainActor @Sendable ([ScreenshotItem]) -> Void,
        onStopped: @escaping @MainActor @Sendable (WatcherStopReason) -> Void
    ) {
        self.clock = clock
        self.enumerator = enumerator
        self.probe = probe
        self.onAccepted = onAccepted
        self.onStopped = onStopped
    }

    public func start(folder: URL) {
        queue.async { [weak self] in
            self?.stopLocked(reason: .userReconfigured, notify: false)
            self?.startLocked(folder: folder)
        }
    }

    public func stop() {
        queue.sync { [weak self] in
            self?.stopLocked(reason: .shuttingDown, notify: true)
        }
    }

    // MARK: - Serial helpers (must be called on `queue`)

    private func startLocked(folder: URL) {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            let reason: WatcherStopReason = .folderInvalid
            DispatchQueue.main.async { self.onStopped(reason) }
            return
        }
        self.folder = folder
        self.descriptor = fd
        self.generation &+= 1
        let gen = self.generation
        self.engine = WatcherEngine(baselineStartedAt: clock.now())

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .revoke, .link],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let mask = src.data
            if mask.contains(.rename) || mask.contains(.delete) || mask.contains(.revoke) {
                self.stopLocked(reason: .folderInvalid, notify: true)
                return
            }
            self.scheduleReconcile(generation: gen)
        }
        src.setCancelHandler { [weak self] in
            if let self, self.descriptor >= 0 {
                close(self.descriptor)
                self.descriptor = -1
            }
        }
        self.source = src
        src.resume()

        // Kick a periodic poll so pending candidates get re-examined even
        // when no vnode event arrives (paused writes).
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            self?.scheduleReconcile(generation: gen)
        }
        self.pollTimer = timer
        timer.resume()

        // Initial baseline reconciliation.
        scheduleReconcile(generation: gen)
    }

    private func stopLocked(reason: WatcherStopReason, notify: Bool) {
        generation &+= 1
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pollTimer?.cancel()
        pollTimer = nil
        source?.cancel()
        source = nil
        if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }
        engine = nil
        let folderWas = folder
        folder = nil
        if notify, folderWas != nil {
            DispatchQueue.main.async { self.onStopped(reason) }
        }
    }

    private func scheduleReconcile(generation gen: UInt64) {
        // Coalesce bursts: only one debounced reconcile in flight.
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.generation == gen else { return }
            self.performReconcile(generation: gen)
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func performReconcile(generation gen: UInt64) {
        guard generation == gen else { return }
        guard let folder, var engine else { return }
        let snapshot: [FolderEntry]
        do {
            snapshot = try enumerator.shallowSnapshot(of: folder)
        } catch {
            stopLocked(reason: .folderInvalid, notify: true)
            return
        }
        let decision = engine.reconcile(snapshot: snapshot, now: clock.now(), probe: probe)
        self.engine = engine
        if !decision.accepted.isEmpty {
            let items = decision.accepted
            DispatchQueue.main.async {
                self.onAccepted(items)
            }
        }
    }
}
