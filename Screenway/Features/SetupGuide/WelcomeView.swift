import SwiftUI

/// First-launch screen. Plain system UI by design (Gate 1).
struct WelcomeView: View {
    let onContinue: () -> Void
    @State private var showingSetupGuide = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Control your Mac privately.")
                .font(.title)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text("Screenway connects directly through Tailscale. There is no Screenway account or cloud relay.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Add a Mac") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            Button("Setup guide") {
                showingSetupGuide = true
            }
        }
        .padding()
        .sheet(isPresented: $showingSetupGuide) {
            NavigationStack {
                SetupGuideView()
            }
        }
    }
}
