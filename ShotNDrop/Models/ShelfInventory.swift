import Foundation
import Combine

/// Session-only in-memory store of held items. Capacity 20, add-by-drop-only,
/// remove-on-drag-out, newest-first ordering. Every mutation is main-actor
/// isolated; every mutation republishes `didChange`.
@MainActor
public final class ShelfInventory: ObservableObject {
    public static let capacity: Int = 20

    public enum Status: Sendable, Equatable {
        case pending
        case ready(ShelfMediaPayload)
        case failed(FailureReason)
    }

    public enum FailureReason: Sendable, Equatable {
        case capacityExceeded
        case duplicate
        case copyFailed
        case unsupportedKind
        case emptySnapshot
    }

    public struct Slot: Sendable, Identifiable, Equatable {
        public let id: UUID
        public var status: Status
        public var reservedAt: Date

        public init(id: UUID = UUID(), status: Status, reservedAt: Date = Date()) {
            self.id = id
            self.status = status
            self.reservedAt = reservedAt
        }

        public var payload: ShelfMediaPayload? {
            if case let .ready(payload) = status { return payload }
            return nil
        }
    }

    @Published public private(set) var slots: [Slot] = []

    public let didChange = PassthroughSubject<Void, Never>()

    public init() {}

    public var isEmpty: Bool { slots.isEmpty }
    public var count: Int { slots.count }

    /// Newest-first list of resolved (`.ready`) payloads.
    public var readyPayloads: [ShelfMediaPayload] {
        slots.compactMap { $0.payload }
    }

    /// Reserves a `.pending` slot at the head (newest-first) if capacity allows.
    /// Returns the reserved id, or nil when at capacity (drop should be
    /// rejected as `.capacityExceeded`).
    @discardableResult
    public func reservePending() -> UUID? {
        guard slots.count < Self.capacity else { return nil }
        let slot = Slot(status: .pending)
        slots.insert(slot, at: 0)
        didChange.send()
        return slot.id
    }

    /// Resolves a previously reserved pending slot with a successful payload.
    /// Returns true when a slot with the id existed and was in `.pending`.
    @discardableResult
    public func resolve(id: UUID, with payload: ShelfMediaPayload) -> Bool {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return false }
        guard case .pending = slots[index].status else { return false }
        var slot = slots[index]
        slot.status = .ready(payload)
        slots[index] = slot
        didChange.send()
        return true
    }

    /// Marks a pending slot as failed and removes it after publishing so UIs
    /// can drive a rejection flash from the removal event.
    @discardableResult
    public func fail(id: UUID, reason: FailureReason) -> Bool {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return false }
        slots.remove(at: index)
        didChange.send()
        return true
    }

    public func containsDuplicate(fingerprint: ShelfMediaPayload.Fingerprint) -> Bool {
        for slot in slots {
            if case let .ready(payload) = slot.status,
               payload.fingerprint == fingerprint {
                return true
            }
        }
        return false
    }

    public func fingerprints() -> [ShelfMediaPayload.Fingerprint] {
        slots.compactMap { $0.payload?.fingerprint }
    }

    @discardableResult
    public func remove(id: UUID) -> ShelfMediaPayload? {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = slots[index].payload
        slots.remove(at: index)
        didChange.send()
        return removed
    }

    public func clear() {
        guard !slots.isEmpty else { return }
        slots.removeAll()
        didChange.send()
    }
}
