import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Resolves a hostname into concrete addresses so the destination policy can
/// be enforced before any socket opens. Injectable so tests never touch DNS.
public protocol HostAddressResolver: Sendable {
    /// Resolves `host` to all its addresses. Throws `ScreenwayError` with
    /// code NET-001 when the name does not resolve.
    func resolve(host: String) async throws -> [ResolvedAddress]
}

/// getaddrinfo-backed resolver. Runs the blocking lookup off the caller.
public struct SystemHostAddressResolver: HostAddressResolver {
    public init() {}

    public func resolve(host: String) async throws -> [ResolvedAddress] {
        let resolved = await Task.detached(priority: .userInitiated) { () -> [ResolvedAddress] in
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            var results: UnsafeMutablePointer<addrinfo>?
            let status = host.withCString { getaddrinfo($0, nil, &hints, &results) }
            defer { if results != nil { freeaddrinfo(results) } }
            guard status == 0 else { return [] }

            var addresses: [ResolvedAddress] = []
            var cursor = results
            while let info = cursor {
                if let sockaddrPointer = info.pointee.ai_addr {
                    switch info.pointee.ai_family {
                    case AF_INET:
                        let value = sockaddrPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                            UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                        }
                        addresses.append(.ipv4(IPv4Address(rawValue: value)))
                    case AF_INET6:
                        let bytes = sockaddrPointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                            withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }
                        }
                        if let address = IPv6Address(bytes: bytes) {
                            addresses.append(.ipv6(address))
                        }
                    default:
                        break
                    }
                }
                cursor = info.pointee.ai_next
            }
            return addresses
        }.value

        guard !resolved.isEmpty else {
            throw ScreenwayError(.netNameNotFound, detail: "DNS lookup for \(host) returned no addresses")
        }
        return resolved
    }
}

/// Enforces `TailscaleDestinationPolicy` before the live adapter opens a
/// socket, and pins name-based destinations to a validated resolved address
/// (closing the DNS re-resolution gap between policy check and connect).
public enum RFBDestinationGate {
    /// Validates the endpoint and returns the exact host string the socket
    /// may connect to: an IP literal for names, or the literal itself.
    ///
    /// - `allowingLoopback` is an internal test seam so adapter-contract
    ///   tests can run a fixture RFB server on 127.0.0.1. Production callers
    ///   never set it; the policy itself is untouched.
    public static func authorizedConnectHost(
        for endpoint: RFBEndpoint,
        resolver: any HostAddressResolver,
        allowingLoopback: Bool = false
    ) async throws -> String {
        let parsed: ParsedHost
        do {
            parsed = try HostParser.parse(endpoint.host)
        } catch {
            throw ScreenwayError(.netNameNotFound, detail: "Unparseable destination: \(endpoint.host)")
        }

        switch parsed.kind {
        case .ipv4(let address):
            try requireAllowed(
                TailscaleDestinationPolicy.evaluate(
                    host: .ipv4(address),
                    allowLocalNetwork: endpoint.allowLocalNetwork
                ),
                host: endpoint.host,
                allowingLoopback: allowingLoopback
            )
            return address.description

        case .ipv6(let address):
            try requireAllowed(
                TailscaleDestinationPolicy.evaluate(
                    host: .ipv6(address),
                    allowLocalNetwork: endpoint.allowLocalNetwork
                ),
                host: endpoint.host,
                allowingLoopback: allowingLoopback
            )
            return ipv6Literal(address)

        case .name(let name):
            let addresses = try await resolver.resolve(host: name)
            try requireAllowed(
                TailscaleDestinationPolicy.evaluate(host: .name(name), resolvedAddresses: addresses),
                host: endpoint.host,
                allowingLoopback: false
            )
            // Pin the connection to a validated address (IPv4 preferred).
            for resolved in addresses {
                if case .ipv4(let address) = resolved { return address.description }
            }
            if case .ipv6(let address) = addresses[0] { return ipv6Literal(address) }
            throw ScreenwayError(.netNameNotFound, detail: "No usable address for \(name)")
        }
    }

    private static func requireAllowed(
        _ decision: DestinationDecision,
        host: String,
        allowingLoopback: Bool
    ) throws {
        switch decision {
        case .allowedTailscale, .allowedLocalNetwork:
            return
        case .rejected(.loopback) where allowingLoopback:
            // Test seam only; see `authorizedConnectHost` doc.
            return
        case .rejected(.unresolvedName):
            throw ScreenwayError(.netNameNotFound, detail: "\(host) did not resolve")
        case .rejected(let reason):
            throw ScreenwayError(
                .netTailscaleRouteUnavailable,
                detail: "Destination \(host) rejected by policy (\(reason.rawValue))"
            )
        }
    }

    private static func ipv6Literal(_ address: IPv6Address) -> String {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let formatted = address.bytes.withUnsafeBytes { rawBytes -> String? in
            guard let base = rawBytes.baseAddress else { return nil }
            guard inet_ntop(AF_INET6, base, &buffer, socklen_t(buffer.count)) != nil else { return nil }
            let octets = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
            return String(decoding: octets, as: UTF8.self)
        }
        // inet_ntop cannot fail for 16 valid bytes; fall back defensively.
        return formatted ?? address.bytes.map { String(format: "%02x", $0) }.joined()
    }
}
