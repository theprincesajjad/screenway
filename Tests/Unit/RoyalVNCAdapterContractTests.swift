import Foundation
import Testing
@testable import Screenway

#if canImport(Darwin)
import Darwin
#endif

/// Collects adapter events off the single-consumer stream so tests can poll.
private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [RFBClientEvent] = []

    func append(_ event: RFBClientEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [RFBClientEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    func contains(where predicate: (RFBClientEvent) -> Bool) -> Bool {
        snapshot().contains(where: predicate)
    }
}

/// Polls `condition` until it holds or the timeout elapses.
private func eventually(
    timeoutSeconds: Double = 10,
    _ condition: @Sendable () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}

private func collectEvents(of client: some RFBClientProtocol) -> (EventCollector, Task<Void, Never>) {
    let collector = EventCollector()
    let task = Task {
        for await event in client.events {
            collector.append(event)
        }
    }
    return (collector, task)
}

/// Contract tests against the production `RoyalVNCAdapter`. The loopback
/// cases use the internal test seam (policy override for 127.0.0.1 only) and
/// the `MiniRFBServer` fixture — no live Mac, no external network.
@Suite("RoyalVNCAdapter contract", .serialized)
struct RoyalVNCAdapterContractTests {
    @Test("The production adapter refuses public destinations before any socket")
    func policyBlocksPublicInternet() async {
        let adapter = RoyalVNCAdapter() // production init: no loopback seam
        do {
            try await adapter.connect(to: RFBEndpoint(host: "8.8.8.8"))
            Issue.record("expected policy rejection")
        } catch let error as ScreenwayError {
            #expect(error.code == .netTailscaleRouteUnavailable)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(await adapter.state == .failed)
    }

    @Test("The production adapter refuses RFC1918 destinations by default")
    func policyBlocksPrivateLAN() async {
        let adapter = RoyalVNCAdapter()
        do {
            try await adapter.connect(to: RFBEndpoint(host: "192.168.1.20"))
            Issue.record("expected policy rejection")
        } catch let error as ScreenwayError {
            #expect(error.code == .netTailscaleRouteUnavailable)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("authenticate before connect fails")
    func authenticateRequiresConnect() async {
        let adapter = RoyalVNCAdapter()
        await #expect(throws: (any Error).self) {
            try await adapter.authenticate(RFBCredentials(mode: .automatic, password: "pw"))
        }
    }

    @Test("Input requires a connected session")
    func inputRequiresConnection() async {
        let adapter = RoyalVNCAdapter()
        await #expect(throws: (any Error).self) {
            try await adapter.sendPointerEvent(x: 1, y: 1, button: .left)
        }
        await #expect(throws: (any Error).self) {
            try await adapter.sendKeyEvent(keyCode: 0x61, isDown: true)
        }
    }

#if canImport(Darwin)
    @Test("A refused VNC port maps to VNC-001", .timeLimit(.minutes(1)))
    func refusedPortIsVNC001() async {
        // Grab an ephemeral port and close the listener so connecting to it
        // is refused.
        let probe = MiniRFBServer(mode: .vncPassword)
        guard let probe else {
            Issue.record("could not start fixture listener")
            return
        }
        let closedPort = probe.port
        probe.stop()
        try? await Task.sleep(for: .milliseconds(100))

        let adapter = RoyalVNCAdapter(
            resolver: SystemHostAddressResolver(),
            allowingLoopbackForTesting: true
        )
        do {
            try await adapter.connect(to: RFBEndpoint(host: "127.0.0.1", port: closedPort))
            await adapter.disconnect()
            Issue.record("expected connection failure")
        } catch let error as ScreenwayError {
            #expect(error.code == .vncScreenSharingOff)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("An unauthenticated (security None) session is rejected with VNC-002", .timeLimit(.minutes(1)))
    func unauthenticatedSessionRejected() async {
        guard let server = MiniRFBServer(mode: .none) else {
            Issue.record("could not start fixture server")
            return
        }
        defer { server.stop() }

        let adapter = RoyalVNCAdapter(
            resolver: SystemHostAddressResolver(),
            allowingLoopbackForTesting: true
        )
        do {
            try await adapter.connect(to: RFBEndpoint(host: "127.0.0.1", port: server.port))
            await adapter.disconnect()
            Issue.record("expected rejection of the unauthenticated session")
        } catch let error as ScreenwayError {
            #expect(error.code == .vncSignInFailed)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(await adapter.state == .failed)
    }

    @Test("VNC-auth happy path: framebuffer pixels, pointer, key, clean disconnect", .timeLimit(.minutes(1)))
    func happyPath() async throws {
        guard let server = MiniRFBServer(mode: .vncPassword) else {
            Issue.record("could not start fixture server")
            return
        }
        defer { server.stop() }

        let adapter = RoyalVNCAdapter(
            resolver: SystemHostAddressResolver(),
            allowingLoopbackForTesting: true
        )
        let (collector, collectorTask) = collectEvents(of: adapter)
        defer { collectorTask.cancel() }

        // Connect stops at the credential request.
        try await adapter.connect(to: RFBEndpoint(host: "127.0.0.1", port: server.port))
        #expect(await adapter.state == .authenticating)

        // Authenticate with the VNC password fallback.
        try await adapter.authenticate(RFBCredentials(mode: .automatic, password: "fixture-pw"))
        #expect(await adapter.state == .connected)

        // The first framebuffer arrives with real pixel bytes and geometry.
        let sawGeometry = await eventually {
            collector.contains { event in
                if case .framebufferGeometryChanged(let width, let height) = event {
                    return width == MiniRFBServer.framebufferWidth && height == MiniRFBServer.framebufferHeight
                }
                return false
            }
        }
        #expect(sawGeometry)

        let sawPixels = await eventually {
            collector.contains { event in
                if case .framebufferUpdated(let update) = event, let pixels = update.pixels {
                    return pixels.format == .bgra8888
                        && update.width == MiniRFBServer.framebufferWidth
                        && update.height == MiniRFBServer.framebufferHeight
                        && pixels.data.count == update.width * update.height * 4
                }
                return false
            }
        }
        #expect(sawPixels)

        // One primary click (press + release) and one key (down + up).
        try await adapter.sendPointerEvent(x: 3, y: 2, button: .left)
        try await adapter.sendPointerEvent(x: 3, y: 2, button: .none)
        try await adapter.sendKeyEvent(keyCode: 0x61, isDown: true)
        try await adapter.sendKeyEvent(keyCode: 0x61, isDown: false)

        let sawClick = await eventually {
            let events = server.pointerEvents
            return events.contains { $0.buttonMask & 0x01 != 0 && $0.x == 3 && $0.y == 2 }
                && events.contains { $0.buttonMask == 0 }
        }
        #expect(sawClick)

        let sawKey = await eventually {
            let events = server.keyEvents
            return events.contains { $0.isDown && $0.keysym == 0x61 }
                && events.contains { !$0.isDown && $0.keysym == 0x61 }
        }
        #expect(sawKey)

        // Clean local disconnect: session ends without an error and the
        // server sees the connection close.
        await adapter.disconnect()
        #expect(await adapter.state == .disconnected)

        let sawCleanEnd = await eventually {
            collector.contains { event in
                if case .sessionEnded(let error) = event { return error == nil }
                return false
            }
        }
        #expect(sawCleanEnd)

        let serverSawClose = await eventually { server.clientDidDisconnect }
        #expect(serverSawClose)
    }

    @Test("Held inputs are released before the connection closes", .timeLimit(.minutes(1)))
    func disconnectReleasesHeldInputs() async throws {
        guard let server = MiniRFBServer(mode: .vncPassword) else {
            Issue.record("could not start fixture server")
            return
        }
        defer { server.stop() }

        let adapter = RoyalVNCAdapter(
            resolver: SystemHostAddressResolver(),
            allowingLoopbackForTesting: true
        )
        try await adapter.connect(to: RFBEndpoint(host: "127.0.0.1", port: server.port))
        try await adapter.authenticate(RFBCredentials(mode: .automatic, password: "fixture-pw"))

        // Hold a button and a key, then disconnect without releasing them.
        try await adapter.sendPointerEvent(x: 5, y: 5, button: .left)
        try await adapter.sendKeyEvent(keyCode: 0x61, isDown: true)
        await adapter.disconnect()

        let sawReleases = await eventually {
            server.pointerEvents.contains { $0.buttonMask == 0 }
                && server.keyEvents.contains { !$0.isDown && $0.keysym == 0x61 }
        }
        #expect(sawReleases)
    }
#endif
}
