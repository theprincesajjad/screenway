import SwiftUI

/// Plain-text setup steps. No custom illustrations (Gate 1).
struct SetupGuideView: View {
    private static let steps: [(title: String, detail: String)] = [
        (
            "Install Tailscale on your Mac",
            "Download Tailscale from tailscale.com, sign in, and make sure the Mac shows as connected."
        ),
        (
            "Install Tailscale on this device",
            "Install the Tailscale app from the App Store and sign in to the same tailnet."
        ),
        (
            "Turn on Screen Sharing on the Mac",
            "System Settings > General > Sharing > Screen Sharing. Note the Mac's user name."
        ),
        (
            "Optional: turn on Remote Login for files",
            "System Settings > General > Sharing > Remote Login. This enables SFTP file access."
        ),
        (
            "Find the Mac's Tailscale address",
            "In the Tailscale menu on the Mac, copy the machine name (like my-mac.tailnet-name.ts.net) or its 100.x address."
        ),
        (
            "Add the Mac in Screenway",
            "Tap Add a Mac, enter the name and address, and connect."
        ),
    ]

    var body: some View {
        List {
            Section {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(index + 1). \(step.title)")
                            .font(.headline)
                        Text(step.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("Tailscale is a trademark of Tailscale Inc. Screenway is not affiliated with or endorsed by Tailscale Inc.")
            }
        }
        .navigationTitle("Setup Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}
