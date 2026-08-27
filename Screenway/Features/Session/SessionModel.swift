import Foundation
import CoreGraphics
import Observation

@MainActor
@Observable
final class SessionModel {
    private let client: any RFBClientProtocol
    private let profile: MacProfile
    private let repository: MacProfileRepository
    private var eventTask: Task<Void, Never>?
    private var credentialContinuation: CheckedContinuation<RFBCredentials?, Never>?

    let renderer = FramebufferRenderer()

    private(set) var statusLabel = "Finding Mac…"
    private(set) var isScreenReady = false
    private(set) var desktopName: String?
    private(set) var framebufferSize: CGSize?
    private(set) var failure: ScreenwayError?
    private(set) var hasEnded = false

    /// Minimal sign-in prompt shown when no password is stored for the
    /// profile. Functional, not polished (full credential UX is a later gate).
    var isPromptingForCredentials = false
    var promptUsername = ""
    var promptPassword = ""

    init(profile: MacProfile, client: any RFBClientProtocol, repository: MacProfileRepository) {
        self.profile = profile
        self.client = client
        self.repository = repository
    }

    static func label(for state: SessionState) -> String {
        switch state {
        case .disconnected: "Disconnected"
        case .resolving: "Finding Mac…"
        case .connecting: "Reaching Mac…"
        case .authenticating: "Signing in…"
        case .negotiating: "Preparing screen…"
        case .connected: "Waiting for screen…"
        case .reconnecting: "Reconnecting…"
        case .suspending: "Suspending…"
        case .failed: "Connection failed"
        }
    }

    func start() async {
        eventTask = Task { [client] in
            // The Task inherits this model's MainActor isolation.
            for await event in client.events {
                self.handle(event)
            }
        }
        do {
            try await client.connect(
                to: RFBEndpoint(
                    host: profile.host,
                    port: profile.vncPort,
                    allowLocalNetwork: profile.allowLocalNetwork
                )
            )
            guard let credentials = await obtainCredentials() else {
                await disconnect()
                return
            }
            try await client.authenticate(credentials)
            var updated = profile
            updated.lastConnectedAt = Date()
            updated.lastRemoteDesktopName = desktopName
            try? await repository.save(updated)
        } catch let error as ScreenwayError {
            failure = error
            statusLabel = error.code.title
        } catch {
            failure = ScreenwayError(.vncSessionEnded, detail: String(describing: error))
            statusLabel = ScreenwayErrorCode.vncSessionEnded.title
        }
    }

    func disconnect() async {
        await client.disconnect()
        eventTask?.cancel()
        eventTask = nil
        hasEnded = true
    }

    /// Sends one primary click (press + release) at the tapped view point,
    /// mapped through Fit scaling onto framebuffer coordinates.
    func sendPrimaryClick(atViewPoint point: CGPoint, viewSize: CGSize) async {
        guard let framebufferSize,
              let mapped = FramebufferFitMapper.framebufferPoint(
                fromViewPoint: point,
                framebufferSize: framebufferSize,
                viewBounds: viewSize
              )
        else { return }
        try? await client.sendPointerEvent(x: mapped.x, y: mapped.y, button: .left)
        try? await client.sendPointerEvent(x: mapped.x, y: mapped.y, button: .none)
    }

    /// Debug control proving the key path end to end: sends "a" down + up.
    /// The full software keyboard is Gate 4.
    func sendDebugKeyA() async {
        let keyCodeA: UInt32 = 0x61 // X11 keysym for lowercase 'a'.
        try? await client.sendKeyEvent(keyCode: keyCodeA, isDown: true)
        try? await client.sendKeyEvent(keyCode: keyCodeA, isDown: false)
    }

    func submitPromptedCredentials() {
        isPromptingForCredentials = false
        let credentials = RFBCredentials(
            mode: profile.vncAuthMode,
            username: promptUsername.isEmpty ? nil : promptUsername,
            password: promptPassword.isEmpty ? nil : promptPassword
        )
        promptPassword = ""
        credentialContinuation?.resume(returning: credentials)
        credentialContinuation = nil
    }

    func cancelCredentialPrompt() {
        isPromptingForCredentials = false
        promptPassword = ""
        credentialContinuation?.resume(returning: nil)
        credentialContinuation = nil
    }

    private func obtainCredentials() async -> RFBCredentials? {
        if let stored = await repository.storedVNCPassword(for: profile) {
            return RFBCredentials(
                mode: profile.vncAuthMode,
                username: profile.macUsername,
                password: stored
            )
        }
        promptUsername = profile.macUsername ?? ""
        isPromptingForCredentials = true
        return await withCheckedContinuation { continuation in
            credentialContinuation = continuation
        }
    }

    private func handle(_ event: RFBClientEvent) {
        switch event {
        case .stateChanged(let state):
            statusLabel = Self.label(for: state)
        case .framebufferGeometryChanged(let width, let height):
            framebufferSize = CGSize(width: width, height: height)
            renderer.resize(width: width, height: height)
        case .framebufferUpdated(let update):
            renderer.apply(update)
            isScreenReady = true
        case .desktopNameChanged(let name):
            desktopName = name
        case .clipboardTextReceived:
            break // Clipboard feature is a later gate.
        case .sessionEnded(let error):
            hasEnded = true
            if let error {
                failure = error
                statusLabel = error.code.title
            }
        }
    }
}
