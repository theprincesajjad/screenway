import SwiftUI

/// Minimal settings surface (Gate 1). Per-Mac options live on the profile;
/// app-wide preferences arrive with later gates.
struct SettingsView: View {
    var body: some View {
        List {
            Section("About") {
                LabeledContent("App", value: "Screenway")
                LabeledContent("Status", value: "Gate 1 (mock connections)")
            }
            Section {
                Text("Screenway connects directly through Tailscale. There is no Screenway account or cloud relay.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Tailscale is a trademark of Tailscale Inc. Screenway is not affiliated with or endorsed by Tailscale Inc.")
            }
        }
        .navigationTitle("Settings")
    }
}
