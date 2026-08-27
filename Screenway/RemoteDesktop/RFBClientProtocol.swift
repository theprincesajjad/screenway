import Foundation

/// Where an RFB (Screen Sharing) connection goes.
public struct RFBEndpoint: Sendable, Equatable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16 = 5900) {
        self.host = host
        self.port = port
    }
}

/// Credentials for RFB authentication. Secrets are passed transiently and
/// never persisted outside the keychain.
public struct RFBCredentials: Sendable {
    public let mode: VNCAuthMode
    public let username: String?
    public let password: String?

    public init(mode: VNCAuthMode, username: String? = nil, password: String? = nil) {
        self.mode = mode
        self.username = username
        self.password = password
    }
}

/// A rectangle of framebuffer pixels that changed. Gate 1 carries metadata
/// only; pixel payloads arrive with the real adapter in Gate 2.
public struct FramebufferUpdate: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum PointerButton: Sendable, Equatable {
    case none
    case left
    case right
    case scroll(deltaX: Int, deltaY: Int)
}

/// Events emitted by an RFB client over its lifetime.
public enum RFBClientEvent: Sendable {
    case stateChanged(SessionState)
    case framebufferUpdated(FramebufferUpdate)
    case desktopNameChanged(String)
    case clipboardTextReceived(String)
    case sessionEnded(ScreenwayError?)
}

/// Screenway-owned abstraction over the RFB/VNC implementation.
/// UI and feature code depend on this protocol only — never on RoyalVNCKit.
public protocol RFBClientProtocol: Actor {
    /// Stream of client events. One consumer (the session model) is expected.
    nonisolated var events: AsyncStream<RFBClientEvent> { get }

    var state: SessionState { get }

    func connect(to endpoint: RFBEndpoint) async throws
    func authenticate(_ credentials: RFBCredentials) async throws
    func disconnect() async

    func sendPointerEvent(x: Int, y: Int, button: PointerButton) async throws
    func sendKeyEvent(keyCode: UInt32, isDown: Bool) async throws
    func sendClipboardText(_ text: String) async throws
}
