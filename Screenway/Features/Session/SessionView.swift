import SwiftUI

/// Mock session screen: connection-state labels, then a plain placeholder.
/// No Metal, no gesture handling — that is Gate 2.
struct SessionView: View {
    let profile: MacProfile
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var model: SessionModel?

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Disconnect") {
                    Task {
                        await model?.disconnect()
                        dismiss()
                    }
                }
            }
        }
        .task {
            guard model == nil else { return }
            let newModel = SessionModel(
                profile: profile,
                client: appEnvironment.makeRFBClient(),
                repository: appEnvironment.profileRepository
            )
            model = newModel
            await newModel.start()
        }
    }

    @ViewBuilder
    private func content(model: SessionModel) -> some View {
        if let failure = model.failure {
            ContentUnavailableView {
                Label(failure.code.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure.code.reason)
            } actions: {
                Button(failure.code.action) { dismiss() }
            }
        } else if model.isScreenReady {
            ZStack {
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                VStack(spacing: 8) {
                    Image(systemName: "display")
                        .font(.largeTitle)
                    Text("Remote screen (mock)")
                    if let desktopName = model.desktopName {
                        Text(desktopName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text(model.statusLabel)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
