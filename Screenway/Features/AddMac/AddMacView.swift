import SwiftUI

/// Plain system form (Gate 1).
struct AddMacView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var model: AddMacModel?

    var body: some View {
        Group {
            if let model {
                form(model: model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Add Mac")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                let environment = appEnvironment
                model = AddMacModel(
                    repository: environment.profileRepository,
                    makeRFBClient: { environment.makeRFBClient() }
                )
            }
        }
    }

    @ViewBuilder
    private func form(model: AddMacModel) -> some View {
        @Bindable var model = model
        Form {
            Section("Mac") {
                TextField("Name", text: $model.name)
                TextField("Address (name, .ts.net, or 100.x)", text: $model.address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Screen port", text: $model.vncPortText)
                    .keyboardType(.numberPad)
            }

            Section("Sign-In") {
                Picker("Authentication", selection: $model.authMode) {
                    Text("Automatic").tag(VNCAuthMode.automatic)
                    Text("Mac login").tag(VNCAuthMode.macLogin)
                    Text("VNC password").tag(VNCAuthMode.vncPassword)
                }
                TextField("Mac user name", text: $model.macUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $model.password)
                Toggle("Remember password", isOn: $model.rememberPassword)
            }

            Section("Files") {
                Toggle("Enable files (SFTP)", isOn: $model.enableFiles)
                if model.enableFiles {
                    TextField("SSH user name", text: $model.sshUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("SSH port", text: $model.sshPortText)
                        .keyboardType(.numberPad)
                }
            }

            Section {
                Button {
                    Task { await model.testConnection() }
                } label: {
                    switch model.testResult {
                    case .idle:
                        Text("Test Connection")
                    case .testing:
                        HStack {
                            ProgressView()
                            Text("Testing…")
                        }
                    case .success:
                        Label("Connection OK", systemImage: "checkmark.circle")
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle")
                    }
                }
                .disabled(model.testResult == .testing)
            } footer: {
                if let validationMessage = model.validationMessage {
                    Text(validationMessage).foregroundStyle(.red)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        if await model.save() {
                            dismiss()
                        }
                    }
                }
                .disabled(!model.canSave)
            }
        }
    }
}
