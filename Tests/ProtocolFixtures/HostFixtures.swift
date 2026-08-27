import Foundation

/// Shared destination-string fixtures used by parsing and policy tests.
/// Kept separate so future protocol-conformance suites reuse the same corpus.
enum HostFixtures {
    static let machineName = "sequoia-mini"
    static let fqdn = "sequoia-mini.tailnet-1234.ts.net"
    static let tailscaleIPv4 = "100.101.102.103"
    static let tailscaleIPv6 = "fd7a:115c:a1e0:ab12::1"
    static let nameWithPort = "sequoia-mini:5901"
    static let ipv4WithPort = "100.64.0.1:5900"
    static let ipv6WithPort = "[fd7a:115c:a1e0::1]:5901"

    /// Cyrillic "о" (U+043E) in place of Latin "o" — must be rejected.
    static let unicodeLookalike = "sequ\u{043E}ia-mini"

    static let malformed: [String] = [
        "",
        "   ",
        ":5900",
        "mini:",
        "mini:0",
        "mini:65536",
        "mini:port",
        "mini:59:00",
        "[fd7a::1",
        "[fd7a::1]x",
        "[not-an-ip]:22",
        "1.2.3",
        "1.2.3.4.5",
        "300.1.2.3",
        "01.2.3.4",
        "a..b",
        "-dash.example",
        "dash-.example",
        "under_score",
        "fe80::1%en0",
    ]
}
