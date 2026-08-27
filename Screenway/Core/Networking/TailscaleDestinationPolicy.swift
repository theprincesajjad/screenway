import Foundation

/// An address a hostname resolved to.
public enum ResolvedAddress: Sendable, Equatable, Hashable {
    case ipv4(IPv4Address)
    case ipv6(IPv6Address)
}

/// Why a destination was rejected.
public enum DestinationRejection: String, Sendable, Equatable {
    case loopback
    case linkLocal
    case privateLAN
    case publicInternet
    case reservedRange
    /// A name cannot be approved until it resolves (NET-001 / NET-002 territory).
    case unresolvedName
    /// The name resolved, but at least one address is outside Tailscale.
    case resolvedOutsideTailscale
}

/// Policy outcome for a candidate destination.
public enum DestinationDecision: Sendable, Equatable {
    /// Address is inside Tailscale's CGNAT IPv4 range or Tailscale ULA IPv6 /48.
    case allowedTailscale
    /// Ordinary private-LAN address explicitly opted into via the profile's
    /// `allowLocalNetwork` flag. Gate 1 never connects to these; the decision
    /// exists so the policy is complete and testable.
    case allowedLocalNetwork
    case rejected(DestinationRejection)
}

/// Screenway only connects across the user's Tailscale network.
/// IPv4 100.64.0.0/10 (CGNAT, used by Tailscale) and
/// IPv6 fd7a:115c:a1e0::/48 (Tailscale ULA) are allowed directly.
/// Names — machine names and *.ts.net — are allowed only once every
/// resolved address falls inside those ranges.
public enum TailscaleDestinationPolicy {
    static let tailscaleIPv4Prefix = IPv4Address("100.64.0.0")!
    static let tailscaleIPv4Bits = 10
    static let tailscaleIPv6Prefix = IPv6Address("fd7a:115c:a1e0::")!
    static let tailscaleIPv6Bits = 48

    public static func evaluate(
        host: ParsedHost.Kind,
        resolvedAddresses: [ResolvedAddress] = [],
        allowLocalNetwork: Bool = false
    ) -> DestinationDecision {
        switch host {
        case .ipv4(let address):
            return evaluate(ipv4: address, allowLocalNetwork: allowLocalNetwork)
        case .ipv6(let address):
            return evaluate(ipv6: address, allowLocalNetwork: allowLocalNetwork)
        case .name:
            guard !resolvedAddresses.isEmpty else {
                return .rejected(.unresolvedName)
            }
            // Every resolved address must be a Tailscale address; a single
            // outside address rejects the name (defense against DNS games).
            for resolved in resolvedAddresses {
                let decision: DestinationDecision =
                    switch resolved {
                    case .ipv4(let address): evaluate(ipv4: address, allowLocalNetwork: false)
                    case .ipv6(let address): evaluate(ipv6: address, allowLocalNetwork: false)
                    }
                guard decision == .allowedTailscale else {
                    return .rejected(.resolvedOutsideTailscale)
                }
            }
            return .allowedTailscale
        }
    }

    private static func evaluate(ipv4 address: IPv4Address, allowLocalNetwork: Bool) -> DestinationDecision {
        if address.isWithin(IPv4Address("127.0.0.0")!, bits: 8) {
            return .rejected(.loopback)
        }
        if address.isWithin(tailscaleIPv4Prefix, bits: tailscaleIPv4Bits) {
            return .allowedTailscale
        }
        if address.isWithin(IPv4Address("169.254.0.0")!, bits: 16) {
            return .rejected(.linkLocal)
        }
        let isPrivateLAN =
            address.isWithin(IPv4Address("10.0.0.0")!, bits: 8)
            || address.isWithin(IPv4Address("172.16.0.0")!, bits: 12)
            || address.isWithin(IPv4Address("192.168.0.0")!, bits: 16)
        if isPrivateLAN {
            return allowLocalNetwork ? .allowedLocalNetwork : .rejected(.privateLAN)
        }
        let isReserved =
            address.isWithin(IPv4Address("0.0.0.0")!, bits: 8)
            || address.isWithin(IPv4Address("224.0.0.0")!, bits: 4)   // multicast
            || address.isWithin(IPv4Address("240.0.0.0")!, bits: 4)   // reserved + broadcast
        if isReserved {
            return .rejected(.reservedRange)
        }
        return .rejected(.publicInternet)
    }

    private static func evaluate(ipv6 address: IPv6Address, allowLocalNetwork: Bool) -> DestinationDecision {
        if address == IPv6Address("::1")! {
            return .rejected(.loopback)
        }
        if address.isWithin(tailscaleIPv6Prefix, bits: tailscaleIPv6Bits) {
            return .allowedTailscale
        }
        if address.isWithin(IPv6Address("fe80::")!, bits: 10) {
            return .rejected(.linkLocal)
        }
        if address == IPv6Address("::")! {
            return .rejected(.reservedRange)
        }
        // Non-Tailscale unique-local space behaves like ordinary private LAN.
        if address.isWithin(IPv6Address("fc00::")!, bits: 7) {
            return allowLocalNetwork ? .allowedLocalNetwork : .rejected(.privateLAN)
        }
        if address.isWithin(IPv6Address("ff00::")!, bits: 8) {
            return .rejected(.reservedRange)
        }
        return .rejected(.publicInternet)
    }
}
