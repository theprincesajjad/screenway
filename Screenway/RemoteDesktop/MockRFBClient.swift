import Foundation

/// Scripted RFB client used by the default Gate 1 environment and by tests.
/// Walks the real session state machine with configurable pacing and never
/// opens a socket.
public actor MockRFBClient: RFBClientProtocol {
    /// Seconds between simulated phases. UI uses the default; tests pass 0.
    private let stepDelay: TimeInterval
    /// When set, `authenticate` fails with this error.
    private let scriptedAuthenticationFailure: ScreenwayError?

    private var stateMachine: SessionStateMachine
    private let eventContinuation: AsyncStream<RFBClientEvent>.Continuation
    public nonisolated let events: AsyncStream<RFBClientEvent>

    public private(set) var sentClipboardTexts: [String] = []
    public private(set) var pointerEventCount = 0
    public private(set) var keyEventCount = 0

    public var state: SessionState { stateMachine.state }

    public init(
        stepDelay: TimeInterval = 0.4,
        scriptedAuthenticationFailure: ScreenwayError? = nil
    ) {
        self.stepDelay = stepDelay
        self.scriptedAuthenticationFailure = scriptedAuthenticationFailure
        self.stateMachine = SessionStateMachine()
        var continuation: AsyncStream<RFBClientEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    public func connect(to endpoint: RFBEndpoint) async throws {
        guard state == .disconnected || state == .failed else {
            throw ScreenwayError(.vncSessionEnded, detail: "connect called in state \(state.rawValue)")
        }
        try await advance(to: .resolving)
        try await advance(to: .connecting)
        try await advance(to: .authenticating)
    }

    public func authenticate(_ credentials: RFBCredentials) async throws {
        guard state == .authenticating else {
            throw ScreenwayError(.vncSessionEnded, detail: "authenticate called in state \(state.rawValue)")
        }
        if let failure = scriptedAuthenticationFailure {
            move(to: .failed)
            throw failure
        }
        try await advance(to: .negotiating)
        try await advance(to: .connected)
        // Brief "Waiting for screen…" window before the first framebuffer.
        if stepDelay > 0 {
            try await Task.sleep(for: .seconds(stepDelay))
        }
        eventContinuation.yield(.desktopNameChanged("Mock Mac"))
        eventContinuation.yield(.framebufferUpdated(FramebufferUpdate(x: 0, y: 0, width: 1920, height: 1080)))
    }

    public func disconnect() async {
        guard state != .disconnected else { return }
        move(to: .disconnected)
        eventContinuation.yield(.sessionEnded(nil))
    }

    public func sendPointerEvent(x: Int, y: Int, button: PointerButton) async throws {
        try requireConnected()
        pointerEventCount += 1
    }

    public func sendKeyEvent(keyCode: UInt32, isDown: Bool) async throws {
        try requireConnected()
        keyEventCount += 1
    }

    public func sendClipboardText(_ text: String) async throws {
        try requireConnected()
        guard !text.isEmpty else { throw ScreenwayError(.clipboardNoText) }
        sentClipboardTexts.append(text)
    }

    private func requireConnected() throws {
        guard state == .connected else {
            throw ScreenwayError(.vncSessionEnded, detail: "not connected")
        }
    }

    private func advance(to newState: SessionState) async throws {
        if stepDelay > 0 {
            try await Task.sleep(for: .seconds(stepDelay))
        }
        move(to: newState)
    }

    private func move(to newState: SessionState) {
        stateMachine.transition(to: newState)
        eventContinuation.yield(.stateChanged(stateMachine.state))
    }
}
