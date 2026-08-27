import Foundation
import Testing
@testable import Screenway

@Suite("Profile repository")
struct ProfileRepositoryTests {
    private func makeRepository() -> (MacProfileRepository, InMemoryCredentialStore, InMemoryMacProfileStore) {
        let credentials = InMemoryCredentialStore()
        let store = InMemoryMacProfileStore()
        let repository = MacProfileRepository(profileStore: store, credentialStore: credentials)
        return (repository, credentials, store)
    }

    private func sampleProfile(remember: Bool = true, withSFTP: Bool = true) -> MacProfile {
        MacProfile(
            displayName: "Studio",
            host: "studio.tailnet-1234.ts.net",
            macUsername: "casey",
            rememberVNCCredential: remember,
            sftp: withSFTP
                ? SFTPProfile(enabled: true, username: "casey", port: 22, rememberCredential: remember)
                : nil
        )
    }

    @Test("Saving with remembered passwords stores secrets by credential ID")
    func saveStoresSecrets() async throws {
        let (repository, credentials, _) = makeRepository()
        try await repository.save(sampleProfile(), vncPassword: "vnc-secret", sftpPassword: "ssh-secret")

        let saved = try #require(await repository.allProfiles().first)
        let vncID = try #require(saved.vncCredentialID)
        let sftpID = try #require(saved.sftp?.credentialID)
        #expect(try await credentials.secret(for: vncID) == "vnc-secret")
        #expect(try await credentials.secret(for: sftpID) == "ssh-secret")
    }

    @Test("The persisted profile never contains the password itself")
    func profileHasNoSecrets() async throws {
        let (repository, _, store) = makeRepository()
        try await repository.save(sampleProfile(), vncPassword: "vnc-secret", sftpPassword: "ssh-secret")

        let saved = try #require(await store.allProfiles().first)
        let encoded = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
        #expect(!encoded.contains("vnc-secret"))
        #expect(!encoded.contains("ssh-secret"))
    }

    @Test("Deleting a profile deletes its associated credentials")
    func deleteCascades() async throws {
        let (repository, credentials, _) = makeRepository()
        try await repository.save(sampleProfile(), vncPassword: "vnc-secret", sftpPassword: "ssh-secret")
        let saved = try #require(await repository.allProfiles().first)

        try await repository.delete(id: saved.id)

        #expect(await repository.allProfiles().isEmpty)
        #expect(await credentials.allCredentialIDs().isEmpty)
    }

    @Test("Turning off remember-password removes the stored secret")
    func forgetOnSave() async throws {
        let (repository, credentials, _) = makeRepository()
        try await repository.save(sampleProfile(), vncPassword: "vnc-secret", sftpPassword: "ssh-secret")
        var saved = try #require(await repository.allProfiles().first)

        saved.rememberVNCCredential = false
        saved.sftp?.rememberCredential = false
        try await repository.save(saved)

        let resaved = try #require(await repository.allProfiles().first)
        #expect(resaved.vncCredentialID == nil)
        #expect(resaved.sftp?.credentialID == nil)
        #expect(await credentials.allCredentialIDs().isEmpty)
    }

    @Test("Deleting a missing profile is a no-op")
    func deleteMissing() async throws {
        let (repository, _, _) = makeRepository()
        try await repository.delete(id: UUID())
        #expect(await repository.allProfiles().isEmpty)
    }
}
