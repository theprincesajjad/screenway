import Foundation

#if canImport(Citadel)
import Citadel
#endif

/// Adapter that will bridge `SFTPClientProtocol` onto Citadel in Gate 2.
///
/// Gate 1 contract: this type compiles and the Citadel dependency is pinned,
/// but the default `AppEnvironment` never instantiates it — the app runs
/// entirely on `MockSFTPClient`. Host-key validation will go through
/// `SSHHostKeyStore`; `acceptAnything`-style validators are forbidden in
/// release paths.
public actor CitadelSFTPAdapter: SFTPClientProtocol {
    public private(set) var isConnected = false

    public init() {}

    public func connect(
        to endpoint: SFTPEndpoint,
        credentials: SFTPCredentials,
        hostKeyStore: SSHHostKeyStore
    ) async throws {
        throw ScreenwayError(.sshRemoteLoginOff, detail: "CitadelSFTPAdapter is not wired until Gate 2")
    }

    public func disconnect() async {
        isConnected = false
    }

    public func listDirectory(at path: String) async throws -> [SFTPDirectoryEntry] {
        throw ScreenwayError(.sshRemoteLoginOff, detail: "CitadelSFTPAdapter is not wired until Gate 2")
    }

    public func downloadFile(at path: String) async throws -> Data {
        throw ScreenwayError(.sshRemoteLoginOff, detail: "CitadelSFTPAdapter is not wired until Gate 2")
    }

    public func uploadFile(data: Data, to path: String) async throws {
        throw ScreenwayError(.sshRemoteLoginOff, detail: "CitadelSFTPAdapter is not wired until Gate 2")
    }
}
