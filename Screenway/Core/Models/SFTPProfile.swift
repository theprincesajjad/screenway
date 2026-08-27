import Foundation

/// Optional file-access (SFTP over SSH, macOS Remote Login) settings for a Mac.
/// Non-secret only: the SSH password/key secret lives in the keychain,
/// referenced by `credentialID`.
public struct SFTPProfile: Codable, Sendable, Equatable, Hashable {
    public var enabled: Bool
    public var username: String
    public var port: UInt16
    public var credentialID: String?
    public var rememberCredential: Bool

    public init(
        enabled: Bool = false,
        username: String = "",
        port: UInt16 = 22,
        credentialID: String? = nil,
        rememberCredential: Bool = false
    ) {
        self.enabled = enabled
        self.username = username
        self.port = port
        self.credentialID = credentialID
        self.rememberCredential = rememberCredential
    }
}
