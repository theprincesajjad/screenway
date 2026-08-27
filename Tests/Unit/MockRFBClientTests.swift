import Testing
@testable import Screenway

@Suite("Mock RFB client")
struct MockRFBClientTests {
    @Test("Connect walks the state machine to authenticating")
    func connect() async throws {
        let client = MockRFBClient(stepDelay: 0)
        try await client.connect(to: RFBEndpoint(host: "sequoia-mini", port: 5900))
        #expect(await client.state == .authenticating)
    }

    @Test("Authenticate reaches connected and emits a framebuffer")
    func authenticate() async throws {
        let client = MockRFBClient(stepDelay: 0)
        try await client.connect(to: RFBEndpoint(host: "sequoia-mini"))
        try await client.authenticate(RFBCredentials(mode: .automatic))
        #expect(await client.state == .connected)

        var sawConnected = false
        var sawFramebuffer = false
        for await event in client.events {
            switch event {
            case .stateChanged(.connected): sawConnected = true
            case .framebufferUpdated: sawFramebuffer = true
            default: break
            }
            if sawConnected && sawFramebuffer { break }
        }
        #expect(sawConnected)
        #expect(sawFramebuffer)
    }

    @Test("Disconnect returns to disconnected and ends the session")
    func disconnect() async throws {
        let client = MockRFBClient(stepDelay: 0)
        try await client.connect(to: RFBEndpoint(host: "sequoia-mini"))
        try await client.authenticate(RFBCredentials(mode: .automatic))
        await client.disconnect()
        #expect(await client.state == .disconnected)

        var sawSessionEnded = false
        for await event in client.events {
            if case .sessionEnded = event {
                sawSessionEnded = true
                break
            }
        }
        #expect(sawSessionEnded)
    }

    @Test("Scripted authentication failure surfaces VNC-002 and fails the session")
    func authFailure() async throws {
        let client = MockRFBClient(
            stepDelay: 0,
            scriptedAuthenticationFailure: ScreenwayError(.vncSignInFailed)
        )
        try await client.connect(to: RFBEndpoint(host: "sequoia-mini"))
        await #expect(throws: ScreenwayError(.vncSignInFailed)) {
            try await client.authenticate(RFBCredentials(mode: .macLogin))
        }
        #expect(await client.state == .failed)
    }

    @Test("Input and clipboard require a connected session")
    func requiresConnection() async {
        let client = MockRFBClient(stepDelay: 0)
        await #expect(throws: (any Error).self) {
            try await client.sendClipboardText("hello")
        }
        await #expect(throws: (any Error).self) {
            try await client.sendPointerEvent(x: 1, y: 1, button: .left)
        }
    }

    @Test("Empty clipboard text raises CLIP-001")
    func emptyClipboard() async throws {
        let client = MockRFBClient(stepDelay: 0)
        try await client.connect(to: RFBEndpoint(host: "sequoia-mini"))
        try await client.authenticate(RFBCredentials(mode: .automatic))
        await #expect(throws: ScreenwayError(.clipboardNoText)) {
            try await client.sendClipboardText("")
        }
        try await client.sendClipboardText("hello")
        #expect(await client.sentClipboardTexts == ["hello"])
    }
}
