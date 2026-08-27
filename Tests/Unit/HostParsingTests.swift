import Testing
@testable import Screenway

@Suite("Host parsing")
struct HostParsingTests {
    @Test("Machine name")
    func machineName() throws {
        let parsed = try HostParser.parse(HostFixtures.machineName)
        #expect(parsed.kind == .name("sequoia-mini"))
        #expect(parsed.port == nil)
    }

    @Test("Names are lowercased and whitespace is trimmed")
    func normalization() throws {
        let parsed = try HostParser.parse("  Sequoia-Mini \n")
        #expect(parsed.kind == .name("sequoia-mini"))
    }

    @Test("FQDN (*.ts.net)")
    func fqdn() throws {
        let parsed = try HostParser.parse(HostFixtures.fqdn)
        #expect(parsed.kind == .name("sequoia-mini.tailnet-1234.ts.net"))
        #expect(parsed.port == nil)
    }

    @Test("IPv4")
    func ipv4() throws {
        let parsed = try HostParser.parse(HostFixtures.tailscaleIPv4)
        #expect(parsed.kind == .ipv4(IPv4Address("100.101.102.103")!))
        #expect(parsed.port == nil)
    }

    @Test("Bare IPv6")
    func ipv6() throws {
        let parsed = try HostParser.parse(HostFixtures.tailscaleIPv6)
        guard case .ipv6(let address) = parsed.kind else {
            Issue.record("expected ipv6, got \(parsed.kind)")
            return
        }
        #expect(address == IPv6Address("fd7a:115c:a1e0:ab12::1"))
        #expect(parsed.port == nil)
    }

    @Test("name:port")
    func nameWithPort() throws {
        let parsed = try HostParser.parse(HostFixtures.nameWithPort)
        #expect(parsed.kind == .name("sequoia-mini"))
        #expect(parsed.port == 5901)
    }

    @Test("ipv4:port")
    func ipv4WithPort() throws {
        let parsed = try HostParser.parse(HostFixtures.ipv4WithPort)
        #expect(parsed.kind == .ipv4(IPv4Address("100.64.0.1")!))
        #expect(parsed.port == 5900)
    }

    @Test("[ipv6]:port")
    func ipv6WithPort() throws {
        let parsed = try HostParser.parse(HostFixtures.ipv6WithPort)
        #expect(parsed.kind == .ipv6(IPv6Address("fd7a:115c:a1e0::1")!))
        #expect(parsed.port == 5901)
    }

    @Test("Bracketed IPv6 without port")
    func bracketedIPv6NoPort() throws {
        let parsed = try HostParser.parse("[fd7a:115c:a1e0::1]")
        #expect(parsed.kind == .ipv6(IPv6Address("fd7a:115c:a1e0::1")!))
        #expect(parsed.port == nil)
    }

    @Test("Malformed inputs are rejected", arguments: HostFixtures.malformed)
    func malformed(input: String) {
        #expect(throws: (any Error).self) {
            try HostParser.parse(input)
        }
    }

    @Test("Unicode lookalike hostnames are rejected")
    func unicodeLookalike() {
        #expect(throws: HostParseError.nonASCIIHostname) {
            try HostParser.parse(HostFixtures.unicodeLookalike)
        }
        #expect(throws: HostParseError.nonASCIIHostname) {
            try HostParser.parse("m\u{0456}ni.ts.net") // Cyrillic "і"
        }
    }

    @Test("Port range is enforced")
    func portRange() throws {
        #expect(try HostParser.parse("mini:1").port == 1)
        #expect(try HostParser.parse("mini:65535").port == 65535)
        #expect(throws: HostParseError.invalidPort) {
            try HostParser.parse("mini:0")
        }
        #expect(throws: HostParseError.invalidPort) {
            try HostParser.parse("mini:65536")
        }
    }
}
