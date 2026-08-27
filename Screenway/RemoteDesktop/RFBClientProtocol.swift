import Foundation

/// Where an RFB (Screen Sharing) connection goes.
public struct RFBEndpoint: Sendable, Equatable {
    public let host: String
    public let port: UInt16
    /// Mirrors `MacProfile.allowLocalNetwork`: opt-in for ordinary
    /// RFC1918/ULA destinations. Tailscale addresses are always allowed;
    /// public internet never is.
    public let allowLocalNetwork: Bool

    public init(host: String, port: UInt16 = 5900, allowLocalNetwork: Bool = false) {
        self.host = host
        self.port = port
        self.allowLocalNetwork = allowLocalNetwork
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

/// Pixel encoding of a framebuffer payload handed to the renderer.
/// Conversion from whatever the wire carried happens inside the adapter;
/// feature code only ever sees these Screenway-owned formats.
public enum FramebufferPixelFormat: Sendable, Equatable {
    /// 4 bytes per pixel, memory order B,G,R,A (matches `MTLPixelFormat.bgra8Unorm`).
    case bgra8888

    public var bytesPerPixel: Int {
        switch self {
        case .bgra8888: 4
        }
    }
}

/// The decoded pixel bytes for one dirty rectangle.
public struct FramebufferPixels: Sendable, Equatable {
    public let format: FramebufferPixelFormat
    /// Stride of `data` in bytes (row length of the rectangle, tightly packed).
    public let bytesPerRow: Int
    public let data: Data

    public init(format: FramebufferPixelFormat, bytesPerRow: Int, data: Data) {
        self.format = format
        self.bytesPerRow = bytesPerRow
        self.data = data
    }
}

/// A rectangle of framebuffer pixels that changed. `pixels` is nil for
/// metadata-only updates (mock clients); the live adapter always attaches
/// the decoded bytes for the rectangle.
public struct FramebufferUpdate: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public let pixels: FramebufferPixels?

    public init(x: Int, y: Int, width: Int, height: Int, pixels: FramebufferPixels? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.pixels = pixels
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
    /// The remote framebuffer was created or resized. The renderer sizes its
    /// texture from this; subsequent `framebufferUpdated` rects fall inside it.
    case framebufferGeometryChanged(width: Int, height: Int)
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
