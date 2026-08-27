import Foundation

public enum CredentialStoreError: Error, Sendable, Equatable {
    case notFound
    case storageFailure(String)
}

/// Secret storage abstraction. Profiles reference secrets by opaque
/// credential ID; passwords never touch SwiftData or any profile store.
public protocol CredentialStore: Sendable {
    func storeSecret(_ secret: String, for credentialID: String) async throws
    func secret(for credentialID: String) async throws -> String?
    func deleteSecret(for credentialID: String) async throws
    func allCredentialIDs() async -> [String]
}
