import Testing
@testable import Screenway

@Suite("Session state machine")
struct SessionStateMachineTests {
    @Test("Happy path: disconnected through connected")
    func happyPath() {
        var machine = SessionStateMachine()
        #expect(machine.state == .disconnected)
        for next in [SessionState.resolving, .connecting, .authenticating, .negotiating, .connected] {
            let moved = machine.transition(to: next)
            #expect(moved)
            #expect(machine.state == next)
        }
    }

    @Test("Reconnect and suspend cycles are legal")
    func reconnectAndSuspend() {
        var machine = SessionStateMachine(initialState: .connected)
        for next in [SessionState.reconnecting, .connected, .suspending, .reconnecting, .connecting, .authenticating] {
            let moved = machine.transition(to: next)
            #expect(moved, "expected legal transition to \(next)")
        }
    }

    @Test("Failure and retry are legal")
    func failureAndRetry() {
        var machine = SessionStateMachine(initialState: .connecting)
        for next in [SessionState.failed, .connecting, .failed, .disconnected] {
            let moved = machine.transition(to: next)
            #expect(moved, "expected legal transition to \(next)")
        }
    }

    @Test("User cancel is legal from every in-flight phase", arguments: [
        SessionState.resolving, .connecting, .authenticating, .negotiating, .connected,
    ])
    func cancelIsLegal(from state: SessionState) {
        var machine = SessionStateMachine(initialState: state)
        let moved = machine.transition(to: .disconnected)
        #expect(moved)
    }

    @Test("Illegal transitions are rejected", arguments: [
        (SessionState.disconnected, SessionState.connected),
        (.disconnected, .authenticating),
        (.disconnected, .negotiating),
        (.disconnected, .failed),
        (.resolving, .negotiating),
        (.resolving, .connected),
        (.connecting, .connected),
        (.connecting, .resolving),
        (.authenticating, .connected),
        (.negotiating, .authenticating),
        (.connected, .resolving),
        (.connected, .connecting),
        (.suspending, .resolving),
        (.failed, .connected),
        (.failed, .negotiating),
    ])
    func illegalTransitions(from: SessionState, to: SessionState) {
        #expect(!SessionStateMachine.isLegal(from: from, to: to))
    }

    @Test("Self-transitions are illegal", arguments: SessionState.allCases)
    func selfTransitionsIllegal(state: SessionState) {
        #expect(!SessionStateMachine.isLegal(from: state, to: state))
    }

    @Test("An illegal transition reports and falls back to a safe disconnect")
    func illegalFallsBackToDisconnect() async {
        // Confined to avoid shared mutable state in a Sendable closure.
        final class Recorder: @unchecked Sendable {
            var recorded: (SessionState, SessionState)?
        }
        let recorder = Recorder()
        var machine = SessionStateMachine(
            initialState: .connected,
            onIllegalTransition: { from, to in recorder.recorded = (from, to) }
        )
        let result = machine.transition(to: .resolving)
        #expect(!result)
        #expect(machine.state == .disconnected)
        #expect(recorder.recorded?.0 == .connected)
        #expect(recorder.recorded?.1 == .resolving)
    }
}
