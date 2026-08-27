import Foundation

#if canImport(RoyalVNCKit)
import RoyalVNCKit
#endif

/// Adapter that will bridge `RFBClientProtocol` onto RoyalVNCKit in Gate 2.
///
/// Gate 1 contract: this type compiles and the RoyalVNCKit dependency is
/// pinned, but the default `AppEnvironment` never instantiates it — the app
/// runs entirely on `MockRFBClient`. Every method throws until Gate 2 wires
/// the real connection. The kit import stays behind `canImport` so the
/// Screenway module never leaks RoyalVNCKit types into feature code.
public actor RoyalVNCAdapter: RFBClientProtocol {
    private var stateMachine = SessionStateMachine()
    private let eventContinuation: AsyncStream<RFBClientEvent>.Continuation
    public nonisolated let events: AsyncStream<RFBClientEvent>

    public var state: SessionState { stateMachine.state }

    public init() {
        var continuation: AsyncStream<RFBClientEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    public func connect(to endpoint: RFBEndpoint) async throws {
        throw ScreenwayError(.vncSessionEnded, detail: "RoyalVNCAdapter is not wired until Gate 2")
    }

    public func authenticate(_ credentials: RFBCredentials) async throws {
        throw ScreenwayError(.vncSessionEnded, detail: "RoyalVNCAdapter is not wired until Gate 2")
    }

    public func disconnect() async {
        stateMachine.transition(to: .disconnected)
    }

    public func sendPointerEvent(x: Int, y: Int, button: PointerButton) async throws {
        throw ScreenwayError(.vncSessionEnded, detail: "RoyalVNCAdapter is not wired until Gate 2")
    }

    public func sendKeyEvent(keyCode: UInt32, isDown: Bool) async throws {
        throw ScreenwayError(.vncSessionEnded, detail: "RoyalVNCAdapter is not wired until Gate 2")
    }

    public func sendClipboardText(_ text: String) async throws {
        throw ScreenwayError(.vncSessionEnded, detail: "RoyalVNCAdapter is not wired until Gate 2")
    }
}
