import Foundation

/// Screenway-owned classification of live-transport and protocol failures.
/// The RoyalVNCKit-touching bridge reduces kit errors to one of these; the
/// mapping to stable NET-*/VNC-* codes below is pure and unit-tested.
public enum RFBFailure: Sendable, Equatable {
    /// DNS lookup failed (NET-001).
    case nameResolution
    /// Route/host unreachable (NET-002).
    case unreachable
    /// Connect or read timed out (NET-003).
    case timedOut
    /// TCP connection refused on the VNC port (VNC-001).
    case connectionRefused
    /// Server rejected the credentials or offered no acceptable auth (VNC-002).
    case authenticationFailed
    /// Protocol/pixel-format negotiation failed, or the framebuffer was
    /// rejected by safety limits (VNC-003).
    case protocolError
    /// The server or network ended an established session (VNC-004).
    case sessionEnded

    public var screenwayError: ScreenwayError {
        switch self {
        case .nameResolution: ScreenwayError(.netNameNotFound)
        case .unreachable: ScreenwayError(.netTailscaleRouteUnavailable)
        case .timedOut: ScreenwayError(.netNoResponse)
        case .connectionRefused: ScreenwayError(.vncScreenSharingOff)
        case .authenticationFailed: ScreenwayError(.vncSignInFailed)
        case .protocolError: ScreenwayError(.vncFormatUnsupported)
        case .sessionEnded: ScreenwayError(.vncSessionEnded)
        }
    }

    public func error(detail: String?) -> ScreenwayError {
        ScreenwayError(screenwayError.code, detail: detail)
    }

    /// Maps a raw POSIX errno from the transport to a failure class.
    /// Returns nil for codes with no specific mapping (caller decides the
    /// phase-appropriate default).
    public static func fromPOSIXCode(_ code: Int32) -> RFBFailure? {
        switch code {
        case ECONNREFUSED: .connectionRefused
        case ETIMEDOUT: .timedOut
        case EHOSTUNREACH, ENETUNREACH, ENETDOWN, EHOSTDOWN: .unreachable
        case ECONNRESET, EPIPE, ECONNABORTED: .sessionEnded
        default: nil
        }
    }
}
