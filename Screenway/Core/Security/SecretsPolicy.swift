import Foundation

/// Central place for security invariants. Gate 1 records the rules; Gate 2
/// enforcement points (keychain access control, ATS notes, host-key pinning)
/// hook in here.
public enum SecretsPolicy {
    /// Secrets (VNC/SSH passwords) live only in the keychain-backed
    /// `CredentialStore`, referenced from profiles by opaque credential ID.
    /// They are never written to SwiftData, UserDefaults, logs, or disk.
    public static let secretsInKeychainOnly = true

    /// SSH host keys are trust-on-first-use with a hard stop on mismatch
    /// (SSH-003). `acceptAnything`-style validation is forbidden in release.
    public static let allowsAcceptAnythingHostKeys = false
}
