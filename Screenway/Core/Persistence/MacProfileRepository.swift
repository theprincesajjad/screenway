import Foundation

/// Coordinates the profile store and the credential store so lifecycle rules
/// hold: deleting a profile always deletes its associated secrets.
public actor MacProfileRepository {
    private let profileStore: any MacProfileStore
    private let credentialStore: any CredentialStore

    public init(profileStore: any MacProfileStore, credentialStore: any CredentialStore) {
        self.profileStore = profileStore
        self.credentialStore = credentialStore
    }

    public func allProfiles() async -> [MacProfile] {
        await profileStore.allProfiles()
    }

    public func profile(id: UUID) async -> MacProfile? {
        await profileStore.profile(id: id)
    }

    /// Saves the non-secret profile, and stores/clears secrets keyed by the
    /// profile's credential IDs.
    public func save(
        _ profile: MacProfile,
        vncPassword: String? = nil,
        sftpPassword: String? = nil
    ) async throws {
        var toSave = profile
        toSave.updatedAt = Date()

        if let vncPassword, toSave.rememberVNCCredential {
            let credentialID = toSave.vncCredentialID ?? "vnc-\(toSave.id.uuidString)"
            toSave.vncCredentialID = credentialID
            try await credentialStore.storeSecret(vncPassword, for: credentialID)
        } else if !toSave.rememberVNCCredential, let staleID = toSave.vncCredentialID {
            try await credentialStore.deleteSecret(for: staleID)
            toSave.vncCredentialID = nil
        }

        if var sftp = toSave.sftp {
            if let sftpPassword, sftp.rememberCredential {
                let credentialID = sftp.credentialID ?? "sftp-\(toSave.id.uuidString)"
                sftp.credentialID = credentialID
                try await credentialStore.storeSecret(sftpPassword, for: credentialID)
            } else if !sftp.rememberCredential, let staleID = sftp.credentialID {
                try await credentialStore.deleteSecret(for: staleID)
                sftp.credentialID = nil
            }
            toSave.sftp = sftp
        }

        await profileStore.upsert(toSave)
    }

    /// Deletes the profile and every secret it references.
    public func delete(id: UUID) async throws {
        guard let profile = await profileStore.profile(id: id) else { return }
        if let vncCredentialID = profile.vncCredentialID {
            try await credentialStore.deleteSecret(for: vncCredentialID)
        }
        if let sftpCredentialID = profile.sftp?.credentialID {
            try await credentialStore.deleteSecret(for: sftpCredentialID)
        }
        await profileStore.remove(id: id)
    }
}
