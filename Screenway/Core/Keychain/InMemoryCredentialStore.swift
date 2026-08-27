import Foundation

/// Mock keychain for Gate 1 and tests. The real Keychain Services
/// implementation lands in Gate 2 behind the same protocol.
public actor InMemoryCredentialStore: CredentialStore {
    private var secrets: [String: String] = [:]

    public init() {}

    public func storeSecret(_ secret: String, for credentialID: String) async throws {
        secrets[credentialID] = secret
    }

    public func secret(for credentialID: String) async throws -> String? {
        secrets[credentialID]
    }

    public func deleteSecret(for credentialID: String) async throws {
        secrets[credentialID] = nil
    }

    public func allCredentialIDs() async -> [String] {
        Array(secrets.keys)
    }
}
