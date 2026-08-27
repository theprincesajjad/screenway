import Foundation

/// A user-entered destination, parsed and validated syntactically.
/// Reachability policy is a separate step (`TailscaleDestinationPolicy`).
public struct ParsedHost: Sendable, Equatable, Hashable {
    public enum Kind: Sendable, Equatable, Hashable {
        case ipv4(IPv4Address)
        case ipv6(IPv6Address)
        /// Machine name or FQDN, lowercased ASCII.
        case name(String)
    }

    public let kind: Kind
    /// Explicit port from `host:port` / `[ipv6]:port`, nil when absent.
    public let port: UInt16?
}

public enum HostParseError: Error, Sendable, Equatable {
    case empty
    case malformed
    case invalidPort
    /// Hostname contains non-ASCII characters (blocks Unicode lookalike
    /// spoofing such as Cyrillic "о" in place of Latin "o").
    case nonASCIIHostname
    case invalidHostname
}

public enum HostParser {
    /// Parses `raw` into a host (+ optional port). Accepted forms:
    /// machine name, FQDN, IPv4, bare IPv6, `name:port`, `ipv4:port`,
    /// `[ipv6]:port`.
    public static func parse(_ raw: String) throws -> ParsedHost {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HostParseError.empty }

        // Bracketed IPv6, optionally with port: [addr] or [addr]:port
        if trimmed.hasPrefix("[") {
            guard let closeIndex = trimmed.firstIndex(of: "]") else {
                throw HostParseError.malformed
            }
            let addressPart = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeIndex])
            guard let address = IPv6Address(addressPart) else {
                throw HostParseError.malformed
            }
            let remainder = trimmed[trimmed.index(after: closeIndex)...]
            if remainder.isEmpty {
                return ParsedHost(kind: .ipv6(address), port: nil)
            }
            guard remainder.hasPrefix(":") else { throw HostParseError.malformed }
            let port = try parsePort(String(remainder.dropFirst()))
            return ParsedHost(kind: .ipv6(address), port: port)
        }

        // Bare IPv6 (two or more colons, no brackets, no port).
        if trimmed.filter({ $0 == ":" }).count >= 2 {
            guard let address = IPv6Address(trimmed) else {
                throw HostParseError.malformed
            }
            return ParsedHost(kind: .ipv6(address), port: nil)
        }

        // Single colon: host:port
        var hostPart = trimmed
        var port: UInt16?
        if let colonIndex = trimmed.firstIndex(of: ":") {
            hostPart = String(trimmed[..<colonIndex])
            port = try parsePort(String(trimmed[trimmed.index(after: colonIndex)...]))
            guard !hostPart.isEmpty else { throw HostParseError.malformed }
        }

        if let ipv4 = IPv4Address(hostPart) {
            return ParsedHost(kind: .ipv4(ipv4), port: port)
        }

        let name = try validateHostname(hostPart)
        return ParsedHost(kind: .name(name), port: port)
    }

    private static func parsePort(_ string: String) throws -> UInt16 {
        guard !string.isEmpty,
              string.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = UInt16(string),
              value > 0
        else { throw HostParseError.invalidPort }
        return value
    }

    /// DNS-style validation: ASCII letters/digits/hyphens in dot-separated
    /// labels. Rejects non-ASCII outright (no IDN/punycode in Gate 1).
    private static func validateHostname(_ host: String) throws -> String {
        guard host.isASCIIOnly else { throw HostParseError.nonASCIIHostname }
        let lowered = host.lowercased()
        guard lowered.count <= 253, !lowered.hasPrefix("."), !lowered.hasSuffix(".") else {
            throw HostParseError.invalidHostname
        }
        let labels = lowered.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { throw HostParseError.invalidHostname }
        var allNumeric = true
        for label in labels {
            guard (1...63).contains(label.count),
                  label.first != "-", label.last != "-",
                  label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
            else { throw HostParseError.invalidHostname }
            if !label.allSatisfy(\.isNumber) { allNumeric = false }
        }
        // "1.2.3" etc. is a malformed IP, not a hostname.
        guard !allNumeric else { throw HostParseError.malformed }
        return lowered
    }
}
