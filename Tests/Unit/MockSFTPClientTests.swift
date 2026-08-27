import Foundation
import Testing
@testable import Screenway

@Suite("Mock SFTP client and host-key store")
struct MockSFTPClientTests {
    @Test("First connection records the host key (trust on first use)")
    func tofu() async throws {
        let client = MockSFTPClient()
        let store = SSHHostKeyStore()
        try await client.connect(
            to: SFTPEndpoint(host: "studio.ts.net", port: 22),
            credentials: SFTPCredentials(username: "casey"),
            hostKeyStore: store
        )
        #expect(await client.isConnected)
        let records = await store.allRecords()
        #expect(records.count == 1)
        #expect(records.first?.fingerprint == MockSFTPClient.mockFingerprint)
    }

    @Test("A changed host key is a hard stop (SSH-003)")
    func hostKeyMismatch() async throws {
        let client = MockSFTPClient()
        let store = SSHHostKeyStore()
        await store.remember(
            SSHHostKeyRecord(
                host: "studio.ts.net",
                port: 22,
                keyType: "ssh-ed25519",
                fingerprint: "SHA256:some-other-key"
            )
        )
        await #expect(throws: ScreenwayError(.sshHostIdentityChanged)) {
            try await client.connect(
                to: SFTPEndpoint(host: "studio.ts.net", port: 22),
                credentials: SFTPCredentials(username: "casey"),
                hostKeyStore: store
            )
        }
        #expect(await !client.isConnected)
    }

    @Test("File operations require a connection")
    func requiresConnection() async {
        let client = MockSFTPClient()
        await #expect(throws: ScreenwayError(.sshRemoteLoginOff, detail: "mock: not connected")) {
            _ = try await client.listDirectory(at: "/Users/mock")
        }
    }

    @Test("Seeded mock files round-trip")
    func mockFiles() async throws {
        let client = MockSFTPClient()
        let store = SSHHostKeyStore()
        try await client.connect(
            to: SFTPEndpoint(host: "studio.ts.net"),
            credentials: SFTPCredentials(username: "casey"),
            hostKeyStore: store
        )
        let entries = try await client.listDirectory(at: "/Users/mock/Documents")
        #expect(entries.map(\.name) == ["notes.txt"])
        try await client.uploadFile(data: Data("new".utf8), to: "/Users/mock/Documents/new.txt")
        let data = try await client.downloadFile(at: "/Users/mock/Documents/new.txt")
        #expect(String(decoding: data, as: UTF8.self) == "new")
    }
}
