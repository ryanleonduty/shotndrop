import Foundation

public struct ScreenshotIdentity: Hashable, Sendable {
    public let resourceIdentifier: Data?
    public let standardizedPath: String
    public let creationDate: Date
    public let size: Int64

    public init(resourceIdentifier: Data?, standardizedPath: String, creationDate: Date, size: Int64) {
        self.resourceIdentifier = resourceIdentifier
        self.standardizedPath = standardizedPath
        self.creationDate = creationDate
        self.size = size
    }

    // Two identities are equal when both carry the same fileResourceIdentifier;
    // if either side lacks one, fall back to the (path, creationDate, size) fingerprint.
    public static func == (lhs: ScreenshotIdentity, rhs: ScreenshotIdentity) -> Bool {
        if let l = lhs.resourceIdentifier, let r = rhs.resourceIdentifier {
            return l == r
        }
        return lhs.standardizedPath == rhs.standardizedPath
            && lhs.creationDate == rhs.creationDate
            && lhs.size == rhs.size
    }

    public func hash(into hasher: inout Hasher) {
        if let rid = resourceIdentifier {
            hasher.combine(rid)
        } else {
            hasher.combine(standardizedPath)
            hasher.combine(creationDate)
            hasher.combine(size)
        }
    }
}

public struct ScreenshotItem: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let identity: ScreenshotIdentity
    public let url: URL
    public let creationDate: Date
    public let size: Int64
    public let detectedAt: Date

    public init(
        id: UUID = UUID(),
        identity: ScreenshotIdentity,
        url: URL,
        creationDate: Date,
        size: Int64,
        detectedAt: Date
    ) {
        self.id = id
        self.identity = identity
        self.url = url
        self.creationDate = creationDate
        self.size = size
        self.detectedAt = detectedAt
    }

    public func isExpired(now: Date, ttl: TimeInterval) -> Bool {
        return now.timeIntervalSince(detectedAt) >= ttl
    }
}

public enum RestoreOutcome: Sendable, Equatable {
    case restored(ScreenshotItem)
    case evictedForRestore(evicted: ScreenshotItem, restored: ScreenshotItem)
    case none                    // last-closed slot empty
    case expired                 // last-closed present but TTL exceeded — slot consumed
    case unavailable             // caller reported identity mismatch / missing — slot consumed
}

public enum InsertOutcome: Sendable, Equatable {
    case inserted(ScreenshotItem)
    case duplicate(existing: ScreenshotItem)
    case overflowEvicted(inserted: ScreenshotItem, evicted: ScreenshotItem)
}

@MainActor
public final class ScreenshotQueue {
    public static let capacity: Int = 20
    public static let ttl: TimeInterval = 60 * 60 * 24 // 24h

    public private(set) var items: [ScreenshotItem] = []
    public private(set) var lastClosed: ScreenshotItem?

    public init() {}

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }

    // Deterministic ordering: creationDate asc, then standardizedPath asc.
    static func sortKey(_ item: ScreenshotItem) -> (Date, String) {
        return (item.creationDate, item.identity.standardizedPath)
    }

    private func sortInPlace() {
        items.sort { lhs, rhs in
            let l = Self.sortKey(lhs)
            let r = Self.sortKey(rhs)
            if l.0 != r.0 { return l.0 < r.0 }
            return l.1 < r.1
        }
    }

    /// Insert a candidate. Returns a description of what happened.
    @discardableResult
    public func insert(_ candidate: ScreenshotItem) -> InsertOutcome {
        if let existing = items.first(where: { $0.identity == candidate.identity }) {
            return .duplicate(existing: existing)
        }
        items.append(candidate)
        sortInPlace()
        if items.count > Self.capacity {
            // Evict oldest (index 0) after sort — creation-order eviction.
            let evicted = items.removeFirst()
            return .overflowEvicted(inserted: candidate, evicted: evicted)
        }
        return .inserted(candidate)
    }

    /// Close the item with a given id. Moves it into the last-closed slot,
    /// evicting whatever was there. Returns the closed item if any.
    @discardableResult
    public func close(id: UUID) -> ScreenshotItem? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let item = items.remove(at: idx)
        lastClosed = item
        return item
    }

    /// Restore the last-closed item. Caller passes `now` and a validator that
    /// re-checks identity/type/availability just-in-time. The validator returns
    /// `true` when the source is still usable, `false` on missing/mismatch.
    @discardableResult
    public func restoreLastClosed(
        now: Date,
        validator: (ScreenshotItem) -> Bool
    ) -> RestoreOutcome {
        guard let candidate = lastClosed else { return .none }
        if candidate.isExpired(now: now, ttl: Self.ttl) {
            lastClosed = nil
            return .expired
        }
        if !validator(candidate) {
            lastClosed = nil
            return .unavailable
        }
        // Consume the slot on success.
        lastClosed = nil
        if items.count >= Self.capacity {
            // Evict oldest active item.
            sortInPlace()
            let evicted = items.removeFirst()
            items.append(candidate)
            sortInPlace()
            return .evictedForRestore(evicted: evicted, restored: candidate)
        }
        items.append(candidate)
        sortInPlace()
        return .restored(candidate)
    }

    /// Prune expired items in the active queue. Returns removed items.
    @discardableResult
    public func pruneExpired(now: Date) -> [ScreenshotItem] {
        var removed: [ScreenshotItem] = []
        items.removeAll { item in
            if item.isExpired(now: now, ttl: Self.ttl) {
                removed.append(item)
                return true
            }
            return false
        }
        if let lc = lastClosed, lc.isExpired(now: now, ttl: Self.ttl) {
            lastClosed = nil
        }
        return removed
    }

    /// Remove a specific item (e.g. its source disappeared). Does not touch the file.
    @discardableResult
    public func removeUnavailable(id: UUID) -> ScreenshotItem? {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: idx)
    }

    /// Clear the queue and the last-closed slot; source files are never touched.
    public func clear() {
        items.removeAll()
        lastClosed = nil
    }
}
