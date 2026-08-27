import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Minimal portable IPv4 value type (no Network.framework so the core
/// compiles for tests on any platform).
public struct IPv4Address: Sendable, Hashable, CustomStringConvertible {
    /// Network byte order packed into a UInt32 (a.b.c.d -> a<<24 | ...).
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Strict dotted-quad parsing (four decimal octets, no shorthand,
    /// no leading zeros).
    public init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.count <= 3,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  !(part.count > 1 && part.first == "0"),
                  let octet = UInt8(part)
            else { return nil }
            value = (value << 8) | UInt32(octet)
        }
        self.rawValue = value
    }

    public var octets: [UInt8] {
        [
            UInt8((rawValue >> 24) & 0xFF),
            UInt8((rawValue >> 16) & 0xFF),
            UInt8((rawValue >> 8) & 0xFF),
            UInt8(rawValue & 0xFF),
        ]
    }

    public var description: String {
        octets.map(String.init).joined(separator: ".")
    }

    /// True when this address falls within `prefix`/`bits`.
    public func isWithin(_ prefix: IPv4Address, bits: Int) -> Bool {
        guard (0...32).contains(bits) else { return false }
        guard bits > 0 else { return true }
        let mask: UInt32 = bits == 32 ? .max : ~(UInt32.max >> UInt32(bits))
        return (rawValue & mask) == (prefix.rawValue & mask)
    }
}

/// Minimal portable IPv6 value type backed by inet_pton.
public struct IPv6Address: Sendable, Hashable {
    /// 16 bytes, network byte order.
    public let bytes: [UInt8]

    public init?(bytes: [UInt8]) {
        guard bytes.count == 16 else { return nil }
        self.bytes = bytes
    }

    public init?(_ string: String) {
        // Zone identifiers (fe80::1%en0) are not valid Screenway destinations.
        guard !string.contains("%"), !string.isEmpty, string.isASCIIOnly else { return nil }
        var buffer = [UInt8](repeating: 0, count: 16)
        let parsed = string.withCString { cString in
            inet_pton(AF_INET6, cString, &buffer) == 1
        }
        guard parsed else { return nil }
        self.bytes = buffer
    }

    /// True when the first `bits` bits equal those of `prefix`.
    public func isWithin(_ prefix: IPv6Address, bits: Int) -> Bool {
        guard (0...128).contains(bits) else { return false }
        var remaining = bits
        for index in 0..<16 {
            if remaining <= 0 { return true }
            if remaining >= 8 {
                if bytes[index] != prefix.bytes[index] { return false }
                remaining -= 8
            } else {
                let mask: UInt8 = 0xFF << (8 - remaining)
                return (bytes[index] & mask) == (prefix.bytes[index] & mask)
            }
        }
        return true
    }
}

extension String {
    var isASCIIOnly: Bool {
        allSatisfy(\.isASCII)
    }
}
