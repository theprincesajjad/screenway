import SwiftUI
import Observation

/// Tracks scene phase so active sessions can move to `.suspending` when the
/// app backgrounds. Gate 1 records the phase; wiring it into live session
/// teardown/resume is Gate 2 work.
@MainActor
@Observable
public final class SceneLifecycleCoordinator {
    public private(set) var currentPhase: ScenePhase = .active

    public init() {}

    public func handlePhaseChange(_ newPhase: ScenePhase) {
        currentPhase = newPhase
    }
}
