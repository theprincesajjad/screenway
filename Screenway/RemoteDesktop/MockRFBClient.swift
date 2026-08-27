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
        eventContinuation.yield(
            .framebufferGeometryChanged(width: Self.mockScreenWidth, height: Self.mockScreenHeight)
        )
        eventContinuation.yield(.framebufferUpdated(Self.mockFrame()))
    }

    static let mockScreenWidth = 320
    static let mockScreenHeight = 200

    /// A small BGRA gradient so the Metal renderer has real bytes to show in
    /// previews and UI tests without any network.
    static func mockFrame() -> FramebufferUpdate {
        let width = mockScreenWidth
        let height = mockScreenHeight
        var data = Data(count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                data[offset] = UInt8((x * 255) / max(width - 1, 1))      // blue
                data[offset + 1] = UInt8((y * 255) / max(height - 1, 1)) // green
                data[offset + 2] = 96                                     // red
                data[offset + 3] = 255                                    // alpha
            }
        }
        return FramebufferUpdate(
            x: 0, y: 0, width: width, height: height,
            pixels: FramebufferPixels(format: .bgra8888, bytesPerRow: width * 4, data: data)
        )
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
