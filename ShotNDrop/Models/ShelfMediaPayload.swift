import Foundation
import CryptoKit

/// Immutable value describing one held item in the shelf inventory. All fields
/// are snapshotted after the async copy completes; the payload is not
/// observable until the copy resolves. `Fingerprint` is `(byteCount,
/// first-4KB-SHA256, last-4KB-SHA256)` — full-file hashing is prohibited to
/// keep duplicate detection off the hot path.
public struct ShelfMediaPayload: Sendable, Equatable, Identifiable {
    public struct Fingerprint: Sendable, Equatable, Hashable {
        public let byteCount: Int
        public let firstChunkHash: Data
        public let lastChunkHash: Data

        public init(byteCount: Int, firstChunkHash: Data, lastChunkHash: Data) {
            self.byteCount = byteCount
            self.firstChunkHash = firstChunkHash
            self.lastChunkHash = lastChunkHash
        }

        static let chunkSize: Int = 4 * 1024

        public static func compute(from bytes: Data) -> Fingerprint {
            let count = bytes.count
            if count <= Self.chunkSize * 2 {
                let hash = Data(SHA256.hash(data: bytes))
                return Fingerprint(byteCount: count, firstChunkHash: hash, lastChunkHash: hash)
            }
            let firstChunk = bytes.prefix(Self.chunkSize)
            let lastChunk = bytes.suffix(Self.chunkSize)
            return Fingerprint(
                byteCount: count,
                firstChunkHash: Data(SHA256.hash(data: firstChunk)),
                lastChunkHash: Data(SHA256.hash(data: lastChunk))
            )
        }
    }

    public struct Dimensions: Sendable, Equatable, Hashable {
        public let width: Int
        public let height: Int
        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    public let id: UUID
    public let kind: ShelfMediaKind
    public let sessionStoreURL: URL
    public let originalFilename: String
    public let capturedAt: Date
    public let sizeBytes: Int
    public let dimensions: Dimensions?
    public let fingerprint: Fingerprint
    public let utiIdentifier: String

    public init(
        id: UUID = UUID(),
        kind: ShelfMediaKind,
        sessionStoreURL: URL,
        originalFilename: String,
        capturedAt: Date,
        sizeBytes: Int,
        dimensions: Dimensions?,
        fingerprint: Fingerprint,
        utiIdentifier: String
    ) {
        self.id = id
        self.kind = kind
        self.sessionStoreURL = sessionStoreURL
        self.originalFilename = originalFilename
        self.capturedAt = capturedAt
        self.sizeBytes = sizeBytes
        self.dimensions = dimensions
        self.fingerprint = fingerprint
        self.utiIdentifier = utiIdentifier
    }
}

extension ShelfMediaPayload {
    /// Exposes the reserved video-payload shape for Phase 3 tests without
    /// shipping the video ingest path.
    public static func _forTestingOnlyVideo(
        id: UUID = UUID(),
        sessionStoreURL: URL,
        originalFilename: String = "test.mov",
        capturedAt: Date = Date(),
        sizeBytes: Int = 0,
        dimensions: Dimensions? = nil,
        fingerprint: Fingerprint = Fingerprint(byteCount: 0, firstChunkHash: Data(), lastChunkHash: Data()),
        utiIdentifier: String = "public.movie"
    ) -> ShelfMediaPayload {
        ShelfMediaPayload(
            id: id,
            kind: .video,
            sessionStoreURL: sessionStoreURL,
            originalFilename: originalFilename,
            capturedAt: capturedAt,
            sizeBytes: sizeBytes,
            dimensions: dimensions,
            fingerprint: fingerprint,
            utiIdentifier: utiIdentifier
        )
    }
}
