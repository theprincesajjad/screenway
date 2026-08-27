import SwiftUI

/// Live session screen: connection-state labels, then the Metal framebuffer.
/// A tap sends one primary click at the mapped coordinate; a bottom-bar
/// button proves the key path ("a"). Deliberately functional, not polished.
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
            if let model, model.isScreenReady {
                ToolbarItem(placement: .bottomBar) {
                    Button("Send key (a)") {
                        Task { await model.sendDebugKeyA() }
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
        @Bindable var model = model
        Group {
            if let failure = model.failure {
                ContentUnavailableView {
                    Label(failure.code.title, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure.code.reason)
                } actions: {
                    Button(failure.code.action) { dismiss() }
                }
            } else if model.isScreenReady {
                GeometryReader { proxy in
                    RemoteFramebufferView(renderer: model.renderer)
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { location in
                            Task {
                                await model.sendPrimaryClick(atViewPoint: location, viewSize: proxy.size)
                            }
                        }
                }
                .background(Color.black)
                .ignoresSafeArea(edges: .bottom)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(model.statusLabel)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Sign in to \(profile.displayName)", isPresented: $model.isPromptingForCredentials) {
            TextField("Mac user name", text: $model.promptUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $model.promptPassword)
            Button("Connect") { model.submitPromptedCredentials() }
            Button("Cancel", role: .cancel) {
                model.cancelCredentialPrompt()
                dismiss()
            }
        } message: {
            Text("Enter the account used for Screen Sharing on this Mac.")
        }
    }
}
