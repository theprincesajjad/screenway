import Foundation

/// Scripted SFTP client for the Gate 1 environment and tests.
/// Never opens a socket.
public actor MockSFTPClient: SFTPClientProtocol {
    private let scriptedConnectFailure: ScreenwayError?
    public private(set) var isConnected = false
    private var files: [String: Data]

    public init(
        scriptedConnectFailure: ScreenwayError? = nil,
        seededFiles: [String: Data] = [
            "/Users/mock/Documents/notes.txt": Data("Hello from the mock Mac\n".utf8)
        ]
    ) {
        self.scriptedConnectFailure = scriptedConnectFailure
        self.files = seededFiles
    }

    public func connect(
        to endpoint: SFTPEndpoint,
        credentials: SFTPCredentials,
        hostKeyStore: SSHHostKeyStore
    ) async throws {
        if let failure = scriptedConnectFailure {
            throw failure
        }
        // Mock identity: exercise the TOFU flow against the real store.
        let verdict = await hostKeyStore.verify(
            host: endpoint.host,
            port: endpoint.port,
            keyType: "ssh-ed25519",
            fingerprint: Self.mockFingerprint
        )
        switch verdict {
        case .mismatch:
            throw ScreenwayError(.sshHostIdentityChanged)
        case .unknownHost:
            await hostKeyStore.remember(
                SSHHostKeyRecord(
                    host: endpoint.host,
                    port: endpoint.port,
                    keyType: "ssh-ed25519",
                    fingerprint: Self.mockFingerprint
                )
            )
        case .trusted:
            break
        }
        isConnected = true
    }

    public static let mockFingerprint = "SHA256:mock-fingerprint-gate1"

    public func disconnect() async {
        isConnected = false
    }

    public func listDirectory(at path: String) async throws -> [SFTPDirectoryEntry] {
        try requireConnected()
        let normalized = path.hasSuffix("/") ? path : path + "/"
        return files.keys
            .filter { $0.hasPrefix(normalized) }
            .sorted()
            .map { filePath in
                SFTPDirectoryEntry(
                    name: String(filePath.split(separator: "/").last ?? ""),
                    path: filePath,
                    kind: .file,
                    sizeBytes: Int64(files[filePath]?.count ?? 0)
                )
            }
    }

    public func downloadFile(at path: String) async throws -> Data {
        try requireConnected()
        guard let data = files[path] else {
            throw ScreenwayError(.filePermissionDenied, detail: "mock: no such file \(path)")
        }
        return data
    }

    public func uploadFile(data: Data, to path: String) async throws {
        try requireConnected()
        files[path] = data
    }

    private func requireConnected() throws {
        guard isConnected else {
            throw ScreenwayError(.sshRemoteLoginOff, detail: "mock: not connected")
        }
    }
}
