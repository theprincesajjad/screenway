import SwiftUI

/// Saved Macs. System list + navigation only (Gate 1).
struct MacsListView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var model: MacsListModel?
    @State private var showingAddMac = false
    @State private var sessionProfile: MacProfile?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model: model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Macs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Mac", systemImage: "plus") {
                        showingAddMac = true
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink("Setup") {
                        SetupGuideView()
                    }
                }
            }
            .sheet(isPresented: $showingAddMac, onDismiss: { reload() }) {
                NavigationStack {
                    AddMacView()
                }
            }
            .navigationDestination(item: $sessionProfile) { profile in
                SessionView(profile: profile)
            }
        }
        .task {
            if model == nil {
                model = MacsListModel(repository: appEnvironment.profileRepository)
            }
            await model?.reload()
        }
    }

    @ViewBuilder
    private func content(model: MacsListModel) -> some View {
        if model.profiles.isEmpty {
            ContentUnavailableView {
                Label("No Macs Yet", systemImage: "desktopcomputer")
            } description: {
                Text("Add a Mac on your Tailscale network to connect to its screen.")
            } actions: {
                Button("Add a Mac") { showingAddMac = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                ForEach(model.profiles) { profile in
                    MacRow(profile: profile) {
                        sessionProfile = profile
                    }
                }
                .onDelete { offsets in
                    Task { await model.delete(at: offsets) }
                }
            }
        }
    }

    private func reload() {
        Task { await model?.reload() }
    }
}

private struct MacRow: View {
    let profile: MacProfile
    let onConnect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.headline)
                Text(profile.host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(lastConnectedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Connect", action: onConnect)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
    }

    private var lastConnectedText: String {
        if let lastConnectedAt = profile.lastConnectedAt {
            "Last connected \(lastConnectedAt.formatted(date: .abbreviated, time: .shortened))"
        } else {
            "Never connected"
        }
    }
}
