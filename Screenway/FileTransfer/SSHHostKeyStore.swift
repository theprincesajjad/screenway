import Foundation

/// A Mac's remembered SSH host-key fingerprint (trust-on-first-use record).
public struct SSHHostKeyRecord: Codable, Sendable, Equatable {
    public let host: String
    public let port: UInt16
    /// e.g. "ssh-ed25519"
    public let keyType: String
    /// SHA-256 fingerprint, base64.
    public let fingerprint: String
    public let firstSeenAt: Date

    public init(host: String, port: UInt16, keyType: String, fingerprint: String, firstSeenAt: Date = Date()) {
        self.host = host
        self.port = port
        self.keyType = keyType
        self.fingerprint = fingerprint
        self.firstSeenAt = firstSeenAt
    }
}

public enum HostKeyVerdict: Sendable, Equatable {
    /// No record yet — caller must ask the user to confirm (TOFU), then `remember`.
    case unknownHost
    case trusted
    /// The stored fingerprint differs: surface SSH-003 and never connect silently.
    case mismatch(stored: SSHHostKeyRecord)
}

/// Remembered SSH host identities. Never "accept anything": a changed key is
/// always a hard stop (SSH-003, "Mac identity changed").
public actor SSHHostKeyStore {
    private var records: [String: SSHHostKeyRecord] = [:]

    public init() {}

    private static func key(host: String, port: UInt16) -> String {
        "\(host.lowercased()):\(port)"
    }

    public func verify(host: String, port: UInt16, keyType: String, fingerprint: String) -> HostKeyVerdict {
        guard let stored = records[Self.key(host: host, port: port)] else {
            return .unknownHost
        }
        if stored.keyType == keyType && stored.fingerprint == fingerprint {
            return .trusted
        }
        return .mismatch(stored: stored)
    }

    public func remember(_ record: SSHHostKeyRecord) {
        records[Self.key(host: record.host, port: record.port)] = record
    }

    public func forget(host: String, port: UInt16) {
        records[Self.key(host: host, port: port)] = nil
    }

    public func allRecords() -> [SSHHostKeyRecord] {
        Array(records.values)
    }
}
