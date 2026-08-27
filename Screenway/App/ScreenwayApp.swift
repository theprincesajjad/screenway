import SwiftUI

@main
struct ScreenwayApp: App {
    @State private var appEnvironment = AppEnvironment()
    @State private var lifecycleCoordinator = SceneLifecycleCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment)
                .environment(lifecycleCoordinator)
        }
        .onChange(of: scenePhase) { _, newPhase in
            lifecycleCoordinator.handlePhaseChange(newPhase)
        }
    }
}

/// Shows the one-time welcome screen on first launch, then the Macs list.
struct RootView: View {
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false

    var body: some View {
        if hasCompletedWelcome {
            MacsListView()
        } else {
            WelcomeView(onContinue: { hasCompletedWelcome = true })
        }
    }
}
