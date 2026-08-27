import Foundation

/// Direction of a file transfer relative to this device.
public enum TransferDirection: String, Codable, Sendable {
    case download
    case upload
}

/// Resumable-transfer bookmark. Gate 1 lands the type only; transfers are Gate 2+.
public struct TransferCheckpoint: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let profileID: UUID
    public let direction: TransferDirection
    public let remotePath: String
    public let localPath: String
    public let totalBytes: Int64
    public var transferredBytes: Int64
    /// Fingerprint of the source file (size + mtime hash) so a changed file
    /// restarts instead of resuming into corruption (FILE-003).
    public var sourceFingerprint: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        profileID: UUID,
        direction: TransferDirection,
        remotePath: String,
        localPath: String,
        totalBytes: Int64,
        transferredBytes: Int64 = 0,
        sourceFingerprint: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.direction = direction
        self.remotePath = remotePath
        self.localPath = localPath
        self.totalBytes = totalBytes
        self.transferredBytes = transferredBytes
        self.sourceFingerprint = sourceFingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
