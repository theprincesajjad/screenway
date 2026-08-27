import Testing
@testable import Screenway

@Suite("Tailscale destination policy")
struct TailscalePolicyTests {
    private func decideIPv4(_ string: String, allowLAN: Bool = false) -> DestinationDecision {
        TailscaleDestinationPolicy.evaluate(
            host: .ipv4(IPv4Address(string)!),
            allowLocalNetwork: allowLAN
        )
    }

    private func decideIPv6(_ string: String, allowLAN: Bool = false) -> DestinationDecision {
        TailscaleDestinationPolicy.evaluate(
            host: .ipv6(IPv6Address(string)!),
            allowLocalNetwork: allowLAN
        )
    }

    @Test("Tailscale CGNAT IPv4 range 100.64.0.0/10 is allowed", arguments: [
        "100.64.0.0", "100.64.0.1", "100.101.102.103", "100.127.255.255",
    ])
    func tailscaleIPv4Allowed(address: String) {
        #expect(decideIPv4(address) == .allowedTailscale)
    }

    @Test("IPv4 just outside 100.64.0.0/10 is public", arguments: [
        "100.63.255.255", "100.128.0.0",
    ])
    func cgnatBoundary(address: String) {
        #expect(decideIPv4(address) == .rejected(.publicInternet))
    }

    @Test("Tailscale ULA IPv6 fd7a:115c:a1e0::/48 is allowed", arguments: [
        "fd7a:115c:a1e0::1", "fd7a:115c:a1e0:ab12:4843:cd96:6263:1234", "fd7a:115c:a1e0:ffff::1",
    ])
    func tailscaleIPv6Allowed(address: String) {
        #expect(decideIPv6(address) == .allowedTailscale)
    }

    @Test("IPv6 outside the Tailscale /48 is not Tailscale")
    func ipv6Boundary() {
        // Still ULA space, so it counts as private LAN, not Tailscale.
        #expect(decideIPv6("fd7a:115c:a1e1::1") == .rejected(.privateLAN))
        #expect(decideIPv6("fd00::1") == .rejected(.privateLAN))
    }

    @Test("Loopback is always rejected")
    func loopback() {
        #expect(decideIPv4("127.0.0.1") == .rejected(.loopback))
        #expect(decideIPv4("127.200.1.1") == .rejected(.loopback))
        #expect(decideIPv6("::1") == .rejected(.loopback))
        #expect(decideIPv4("127.0.0.1", allowLAN: true) == .rejected(.loopback))
    }

    @Test("Link-local is always rejected")
    func linkLocal() {
        #expect(decideIPv4("169.254.1.1") == .rejected(.linkLocal))
        #expect(decideIPv6("fe80::1") == .rejected(.linkLocal))
        #expect(decideIPv4("169.254.1.1", allowLAN: true) == .rejected(.linkLocal))
    }

    @Test("Ordinary private LAN is rejected by default", arguments: [
        "10.0.0.5", "172.16.0.9", "172.31.255.255", "192.168.1.10",
    ])
    func privateLANRejected(address: String) {
        #expect(decideIPv4(address) == .rejected(.privateLAN))
    }

    @Test("allowLocalNetwork flips private LAN to the flag-gated decision")
    func privateLANFlag() {
        #expect(decideIPv4("192.168.1.10", allowLAN: true) == .allowedLocalNetwork)
        #expect(decideIPv4("10.0.0.5", allowLAN: true) == .allowedLocalNetwork)
        #expect(decideIPv6("fd00::1", allowLAN: true) == .allowedLocalNetwork)
    }

    @Test("Public internet is rejected", arguments: [
        "8.8.8.8", "1.1.1.1", "172.32.0.1", "203.0.113.7",
    ])
    func publicRejected(address: String) {
        #expect(decideIPv4(address) == .rejected(.publicInternet))
        #expect(decideIPv4(address, allowLAN: true) == .rejected(.publicInternet))
    }

    @Test("Public IPv6 is rejected")
    func publicIPv6Rejected() {
        #expect(decideIPv6("2606:4700::1111") == .rejected(.publicInternet))
    }

    @Test("Reserved ranges are rejected")
    func reservedRejected() {
        #expect(decideIPv4("0.0.0.1") == .rejected(.reservedRange))
        #expect(decideIPv4("224.0.0.1") == .rejected(.reservedRange))
        #expect(decideIPv4("255.255.255.255") == .rejected(.reservedRange))
        #expect(decideIPv6("::") == .rejected(.reservedRange))
        #expect(decideIPv6("ff02::1") == .rejected(.reservedRange))
    }

    @Test("Names require resolution before approval")
    func unresolvedName() {
        let decision = TailscaleDestinationPolicy.evaluate(host: .name("sequoia-mini.ts.net"))
        #expect(decision == .rejected(.unresolvedName))
    }

    @Test("Names resolving to Tailscale addresses are allowed")
    func resolvedNameAllowed() {
        let decision = TailscaleDestinationPolicy.evaluate(
            host: .name("sequoia-mini.tailnet-1234.ts.net"),
            resolvedAddresses: [
                .ipv4(IPv4Address("100.64.0.5")!),
                .ipv6(IPv6Address("fd7a:115c:a1e0::5")!),
            ]
        )
        #expect(decision == .allowedTailscale)
    }

    @Test("A single non-Tailscale resolution rejects the whole name")
    func mixedResolutionRejected() {
        let decision = TailscaleDestinationPolicy.evaluate(
            host: .name("sequoia-mini.ts.net"),
            resolvedAddresses: [
                .ipv4(IPv4Address("100.64.0.5")!),
                .ipv4(IPv4Address("8.8.8.8")!),
            ]
        )
        #expect(decision == .rejected(.resolvedOutsideTailscale))
    }

    @Test("Names never get the local-network exemption")
    func nameLANRejected() {
        let decision = TailscaleDestinationPolicy.evaluate(
            host: .name("my-mac.local-ish"),
            resolvedAddresses: [.ipv4(IPv4Address("192.168.1.20")!)],
            allowLocalNetwork: true
        )
        #expect(decision == .rejected(.resolvedOutsideTailscale))
    }
}
