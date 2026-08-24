import Foundation

/// Media types the shelf can hold. `.video` is reserved for a future plan;
/// production ingest paths must reject it. A dedicated `_forTestingOnly`
/// factory on `ShelfMediaPayload` exposes the video shape for row tests
/// without shipping the ingest path (Phase 3 tests use it).
public enum ShelfMediaKind: String, Sendable, Codable, CaseIterable {
    case image
    case video
}
