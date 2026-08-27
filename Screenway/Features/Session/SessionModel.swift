import Foundation
import Observation

@MainActor
@Observable
final class SessionModel {
    private let client: any RFBClientProtocol
    private let profile: MacProfile
    private let repository: MacProfileRepository
    private var eventTask: Task<Void, Never>?

    private(set) var statusLabel = "Finding Mac…"
    private(set) var isScreenReady = false
    private(set) var desktopName: String?
    private(set) var failure: ScreenwayError?
    private(set) var hasEnded = false

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
            for await event in client.events {
                await self.handle(event)
            }
        }
        do {
            try await client.connect(to: RFBEndpoint(host: profile.host, port: profile.vncPort))
            try await client.authenticate(
                RFBCredentials(
                    mode: profile.vncAuthMode,
                    username: profile.macUsername,
                    password: nil // Gate 1 mock ignores secrets; Gate 2 loads from keychain.
                )
            )
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

    private func handle(_ event: RFBClientEvent) {
        switch event {
        case .stateChanged(let state):
            statusLabel = Self.label(for: state)
        case .framebufferUpdated:
            isScreenReady = true
        case .desktopNameChanged(let name):
            desktopName = name
        case .clipboardTextReceived:
            break // Clipboard feature is Gate 2.
        case .sessionEnded(let error):
            hasEnded = true
            if let error {
                failure = error
                statusLabel = error.code.title
            }
        }
    }
}
