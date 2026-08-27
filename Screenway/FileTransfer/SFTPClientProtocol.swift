import Foundation

/// Where an SFTP (Remote Login) connection goes.
public struct SFTPEndpoint: Sendable, Equatable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16 = 22) {
        self.host = host
        self.port = port
    }
}

/// Credentials for SSH authentication. Passed transiently, stored only in
/// the keychain.
public struct SFTPCredentials: Sendable {
    public let username: String
    public let password: String?

    public init(username: String, password: String? = nil) {
        self.username = username
        self.password = password
    }
}

/// A remote directory entry.
public struct SFTPDirectoryEntry: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case file
        case directory
        case symlink
        case other
    }

    public let name: String
    public let path: String
    public let kind: Kind
    public let sizeBytes: Int64?
    public let modifiedAt: Date?

    public var id: String { path }

    public init(name: String, path: String, kind: Kind, sizeBytes: Int64? = nil, modifiedAt: Date? = nil) {
        self.name = name
        self.path = path
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
    }
}

/// Screenway-owned abstraction over the SFTP implementation.
/// UI and feature code depend on this protocol only — never on Citadel.
public protocol SFTPClientProtocol: Actor {
    var isConnected: Bool { get }

    /// Connects and authenticates. The host key presented by the Mac must be
    /// verified against `SSHHostKeyStore` — release builds never accept
    /// arbitrary host keys.
    func connect(
        to endpoint: SFTPEndpoint,
        credentials: SFTPCredentials,
        hostKeyStore: SSHHostKeyStore
    ) async throws

    func disconnect() async

    func listDirectory(at path: String) async throws -> [SFTPDirectoryEntry]

    /// Reads remote file contents. Gate 1 mocks only; chunked/resumable
    /// transfers with `TransferCheckpoint` are Gate 2+.
    func downloadFile(at path: String) async throws -> Data

    func uploadFile(data: Data, to path: String) async throws
}
