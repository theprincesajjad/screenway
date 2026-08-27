import Foundation

/// Lifecycle of a remote-desktop session.
public enum SessionState: String, Sendable, CaseIterable, Codable {
    case disconnected
    case resolving
    case connecting
    case authenticating
    case negotiating
    case connected
    case reconnecting
    case suspending
    case failed
}

/// Pure transition table + guard. Illegal transitions assert in debug builds
/// and collapse to a safe `.disconnected` in release builds.
public struct SessionStateMachine: Sendable {
    public typealias IllegalTransitionHandler = @Sendable (SessionState, SessionState) -> Void

    public private(set) var state: SessionState
    private let onIllegalTransition: IllegalTransitionHandler?

    /// - Parameter onIllegalTransition: test seam; when nil, an illegal
    ///   transition raises `assertionFailure` (debug-only crash).
    public init(
        initialState: SessionState = .disconnected,
        onIllegalTransition: IllegalTransitionHandler? = nil
    ) {
        self.state = initialState
        self.onIllegalTransition = onIllegalTransition
    }

    private static let legalTransitions: [SessionState: Set<SessionState>] = [
        .disconnected: [.resolving, .connecting],
        .resolving: [.connecting, .failed, .disconnected],
        .connecting: [.authenticating, .failed, .disconnected],
        .authenticating: [.negotiating, .failed, .disconnected],
        .negotiating: [.connected, .failed, .disconnected],
        .connected: [.reconnecting, .suspending, .disconnected, .failed],
        .reconnecting: [.resolving, .connecting, .connected, .failed, .disconnected],
        .suspending: [.reconnecting, .connected, .disconnected, .failed],
        .failed: [.resolving, .connecting, .disconnected],
    ]

    public static func isLegal(from: SessionState, to: SessionState) -> Bool {
        legalTransitions[from]?.contains(to) ?? false
    }

    /// Attempts the transition. Returns false (after asserting in debug and
    /// forcing a safe disconnect) when the transition is illegal.
    @discardableResult
    public mutating func transition(to newState: SessionState) -> Bool {
        guard Self.isLegal(from: state, to: newState) else {
            if let onIllegalTransition {
                onIllegalTransition(state, newState)
            } else {
                assertionFailure("Illegal session transition \(state.rawValue) -> \(newState.rawValue)")
            }
            state = .disconnected
            return false
        }
        state = newState
        return true
    }
}
