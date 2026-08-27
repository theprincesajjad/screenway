import Testing
@testable import Screenway

/// Resolver stub so gate tests never touch DNS.
private struct StubResolver: HostAddressResolver {
    let addresses: [ResolvedAddress]
    let failure: ScreenwayError?

    init(addresses: [ResolvedAddress] = [], failure: ScreenwayError? = nil) {
        self.addresses = addresses
        self.failure = failure
    }

    func resolve(host: String) async throws -> [ResolvedAddress] {
        if let failure { throw failure }
        return addresses
    }
}

@Suite("RFB destination gate")
struct RFBDestinationGateTests {
    @Test("Public internet (8.8.8.8) is blocked before any socket opens")
    func blocksPublicInternet() async {
        await #expect(throws: ScreenwayError.self) {
            _ = try await RFBDestinationGate.authorizedConnectHost(
                for: RFBEndpoint(host: "8.8.8.8"),
                resolver: StubResolver()
            )
        }
        do {
            _ = try await RFBDestinationGate.authorizedConnectHost(
                for: RFBEndpoint(host: "8.8.8.8"),
                resolver: StubResolver()
            )
        } catch let error as ScreenwayError {
            #expect(error.code == .netTailscaleRouteUnavailable)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("RFC1918 addresses are blocked by default", arguments: [
        "192.168.1.10", "10.0.0.5", "172.16.0.9",
    ])
    func blocksPrivateLANByDefault(host: String) async {
        do {
            _ = try await RFBDestinationGate.authorizedConnectHost(
                for: RFBEndpoint(host: host),
                resolver: StubResolver()
            )
            Issue.record("expected rejection for \(host)")
        } catch let error as ScreenwayError {
            #expect(error.code == .netTailscaleRouteUnavailable)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("RFC1918 is allowed only with the profile's allowLocalNetwork opt-in")
    func allowsLANWithOptIn() async throws {
        let host = try await RFBDestinationGate.authorizedConnectHost(
            for: RFBEndpoint(host: "192.168.1.10", allowLocalNetwork: true),
            resolver: StubResolver()
        )
        #expect(host == "192.168.1.10")
    }

    @Test("Tailscale CGNAT IPv4 and ULA IPv6 literals pass")
    func allowsTailscaleLiterals() async throws {
        let ipv4 = try await RFBDestinationGate.authorizedConnectHost(
            for: RFBEndpoint(host: "100.101.102.103"),
            resolver: StubResolver()
        )
        #expect(ipv4 == "100.101.102.103")

        let ipv6 = try await RFBDestinationGate.authorizedConnectHost(
            for: RFBEndpoint(host: "fd7a:115c:a1e0::1"),
            resolver: StubResolver()
        )
        #expect(ipv6 == "fd7a:115c:a1e0::1")
    }

    @Test("Names are pinned to a validated Tailscale address")
    func pinsNamesToResolvedAddress() async throws {
        let resolver = StubResolver(addresses: [.ipv4(IPv4Address("100.90.80.70")!)])
        let host = try await RFBDestinationGate.authorizedConnectHost(
            for: RFBEndpoint(host: "sequoia-mini.tail1234.ts.net"),
            resolver: resolver
        )
        #expect(host == "100.90.80.70")
    }

    @Test("A name resolving anywhere outside Tailscale is rejected")
    func rejectsNamesResolvingOutside() async {
        let resolver = StubResolver(addresses: [
            .ipv4(IPv4Address("100.90.80.70")!),
            .ipv4(IPv4Address("93.184.216.34")!), // one outside address poisons the name
        ])
        do {
            _ = try await RFBDestinationGate.authorizedConnectHost(
                for: RFBEndpoint(host: "evil.example.com"),
                resolver: resolver
            )
            Issue.record("expected rejection")
        } catch let error as ScreenwayError {
            #expect(error.code == .netTailscaleRouteUnavailable)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("An unresolvable name maps to NET-001")
    func unresolvedNameIsNET001() async {
        let resolver = StubResolver(failure: ScreenwayError(.netNameNotFound))
        do {
            _ = try await RFBDestinationGate.authorizedConnectHost(
                for: RFBEndpoint(host: "nonexistent-mac"),
                resolver: resolver
            )
            Issue.record("expected rejection")
        } catch let error as ScreenwayError {
            #expect(error.code == .netNameNotFound)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("Loopback stays rejected without the test seam")
    func loopbackRejectedInProduction() async {
        do {
            _ = try await RFBDestinationGate.authorizedConnectHost(
                for: RFBEndpoint(host: "127.0.0.1"),
                resolver: StubResolver()
            )
            Issue.record("expected rejection")
        } catch let error as ScreenwayError {
            #expect(error.code == .netTailscaleRouteUnavailable)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
