import Foundation

/// Non-secret profile persistence. Gate 1 ships the in-memory implementation;
/// a SwiftData-backed store can replace it later behind the same protocol.
/// Secrets are never stored here (see `CredentialStore`).
public protocol MacProfileStore: Sendable {
    func allProfiles() async -> [MacProfile]
    func profile(id: UUID) async -> MacProfile?
    func upsert(_ profile: MacProfile) async
    func remove(id: UUID) async
}

public actor InMemoryMacProfileStore: MacProfileStore {
    private var profiles: [UUID: MacProfile] = [:]

    public init(seed: [MacProfile] = []) {
        for profile in seed {
            profiles[profile.id] = profile
        }
    }

    public func allProfiles() async -> [MacProfile] {
        profiles.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func profile(id: UUID) async -> MacProfile? {
        profiles[id]
    }

    public func upsert(_ profile: MacProfile) async {
        profiles[profile.id] = profile
    }

    public func remove(id: UUID) async {
        profiles[id] = nil
    }
}
