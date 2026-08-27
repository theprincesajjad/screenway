import Foundation

/// Stable, user-facing error codes. The raw values and the title/action copy
/// are contract-tested; do not change them without updating the tests and docs.
public enum ScreenwayErrorCode: String, Codable, Sendable, CaseIterable {
    case netNameNotFound = "NET-001"
    case netTailscaleRouteUnavailable = "NET-002"
    case netNoResponse = "NET-003"
    case vncScreenSharingOff = "VNC-001"
    case vncSignInFailed = "VNC-002"
    case vncFormatUnsupported = "VNC-003"
    case vncSessionEnded = "VNC-004"
    case sshRemoteLoginOff = "SSH-001"
    case sshSignInFailed = "SSH-002"
    case sshHostIdentityChanged = "SSH-003"
    case fileNotEnoughSpace = "FILE-001"
    case filePermissionDenied = "FILE-002"
    case fileChanged = "FILE-003"
    case clipboardNoText = "CLIP-001"
    case clipboardPasteRejected = "CLIP-002"

    public var title: String {
        switch self {
        case .netNameNotFound: "Mac name not found"
        case .netTailscaleRouteUnavailable: "Tailscale route unavailable"
        case .netNoResponse: "Mac did not respond"
        case .vncScreenSharingOff: "Screen Sharing is off"
        case .vncSignInFailed: "Sign-in failed"
        case .vncFormatUnsupported: "Screen format unsupported"
        case .vncSessionEnded: "Session ended"
        case .sshRemoteLoginOff: "Remote Login is off"
        case .sshSignInFailed: "SSH sign-in failed"
        case .sshHostIdentityChanged: "Mac identity changed"
        case .fileNotEnoughSpace: "Not enough space"
        case .filePermissionDenied: "Permission denied"
        case .fileChanged: "File changed"
        case .clipboardNoText: "Clipboard has no text"
        case .clipboardPasteRejected: "Mac rejected paste"
        }
    }

    public var reason: String {
        switch self {
        case .netNameNotFound:
            "The address could not be resolved to a Tailscale device."
        case .netTailscaleRouteUnavailable:
            "The address is not reachable through your Tailscale network."
        case .netNoResponse:
            "The Mac was found but did not answer on the expected port."
        case .vncScreenSharingOff:
            "The Mac refused the Screen Sharing connection. Screen Sharing may be turned off in System Settings."
        case .vncSignInFailed:
            "The Mac rejected the user name or password for Screen Sharing."
        case .vncFormatUnsupported:
            "The Mac offered a screen format Screenway could not negotiate."
        case .vncSessionEnded:
            "The Mac ended the session or the connection was lost."
        case .sshRemoteLoginOff:
            "The Mac refused the file connection. Remote Login may be turned off in System Settings."
        case .sshSignInFailed:
            "The Mac rejected the user name or password for file access."
        case .sshHostIdentityChanged:
            "The Mac's SSH identity does not match the one saved for this profile."
        case .fileNotEnoughSpace:
            "There is not enough free space to finish this transfer."
        case .filePermissionDenied:
            "The Mac does not allow access to this folder for the signed-in user."
        case .fileChanged:
            "The file changed on the other side while the transfer was paused."
        case .clipboardNoText:
            "Only text can be sent to the Mac clipboard right now."
        case .clipboardPasteRejected:
            "The Mac did not accept the pasted text."
        }
    }

    public var action: String {
        switch self {
        case .netNameNotFound: "Edit Address"
        case .netTailscaleRouteUnavailable: "Check Tailscale"
        case .netNoResponse: "Try Again"
        case .vncScreenSharingOff: "View Setup Steps"
        case .vncSignInFailed: "Edit Sign-In"
        case .vncFormatUnsupported: "Retry in Compatibility Mode"
        case .vncSessionEnded: "Reconnect"
        case .sshRemoteLoginOff: "View File Setup"
        case .sshSignInFailed: "Edit File Sign-In"
        case .sshHostIdentityChanged: "Review Mac Identity"
        case .fileNotEnoughSpace: "Manage Storage"
        case .filePermissionDenied: "Choose Another Folder"
        case .fileChanged: "Restart Transfer"
        case .clipboardNoText: "Dismiss"
        case .clipboardPasteRejected: "Type Instead"
        }
    }
}

/// Error type carried through adapters and surfaced to the UI.
public struct ScreenwayError: Error, Sendable, Equatable {
    public let code: ScreenwayErrorCode
    /// Optional non-user-facing technical detail for diagnostics.
    public let detail: String?

    public init(_ code: ScreenwayErrorCode, detail: String? = nil) {
        self.code = code
        self.detail = detail
    }
}

extension ScreenwayError: LocalizedError {
    public var errorDescription: String? { code.title }
    public var failureReason: String? { code.reason }
    public var recoverySuggestion: String? { code.action }
}
