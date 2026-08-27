import Foundation

/// How Screenway authenticates the Screen Sharing (VNC/RFB) session.
public enum VNCAuthMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Try the best available mechanism the Mac offers.
    case automatic
    /// macOS user-account sign-in (Screen Sharing "Mac login").
    case macLogin
    /// Legacy VNC password ("VNC viewers may control screen with password").
    case vncPassword

    public var id: String { rawValue }
}

/// How touch input is translated into pointer events.
public enum InputMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case trackpad
    case directTouch

    public var id: String { rawValue }
}

/// How the remote framebuffer is scaled on the device screen.
public enum ScaleMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case fit
    case fill
    case actualPixels

    public var id: String { rawValue }
}

/// Encoding-quality preference for the remote desktop stream.
public enum QualityMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case automatic
    case sharp
    case balanced
    case lowData

    public var id: String { rawValue }
}

/// A saved Mac. Non-secret only: credential secrets live in the keychain,
/// referenced by `vncCredentialID` / `SFTPProfile.credentialID`.
public struct MacProfile: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public var displayName: String
    public var host: String
    public var vncPort: UInt16
    public var vncAuthMode: VNCAuthMode
    public var macUsername: String?
    public var vncCredentialID: String?
    public var rememberVNCCredential: Bool
    public var inputMode: InputMode
    public var scaleMode: ScaleMode
    public var qualityMode: QualityMode
    public var viewOnly: Bool
    public var allowLocalNetwork: Bool
    public var sftp: SFTPProfile?
    public var lastRemoteDesktopName: String?
    public var lastResolvedAddress: String?
    public var lastConnectedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        host: String,
        vncPort: UInt16 = 5900,
        vncAuthMode: VNCAuthMode = .automatic,
        macUsername: String? = nil,
        vncCredentialID: String? = nil,
        rememberVNCCredential: Bool = false,
        inputMode: InputMode = .trackpad,
        scaleMode: ScaleMode = .fit,
        qualityMode: QualityMode = .automatic,
        viewOnly: Bool = false,
        allowLocalNetwork: Bool = false,
        sftp: SFTPProfile? = nil,
        lastRemoteDesktopName: String? = nil,
        lastResolvedAddress: String? = nil,
        lastConnectedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.vncPort = vncPort
        self.vncAuthMode = vncAuthMode
        self.macUsername = macUsername
        self.vncCredentialID = vncCredentialID
        self.rememberVNCCredential = rememberVNCCredential
        self.inputMode = inputMode
        self.scaleMode = scaleMode
        self.qualityMode = qualityMode
        self.viewOnly = viewOnly
        self.allowLocalNetwork = allowLocalNetwork
        self.sftp = sftp
        self.lastRemoteDesktopName = lastRemoteDesktopName
        self.lastResolvedAddress = lastResolvedAddress
        self.lastConnectedAt = lastConnectedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
