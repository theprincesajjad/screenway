import Foundation

#if canImport(RoyalVNCKit)
@preconcurrency import RoyalVNCKit
#endif
#if canImport(Network)
import Network
#endif

// MARK: - Kit-free support types

/// Screenway-owned mirror of the authentication mechanism the server picked.
/// Keeps RoyalVNCKit types out of everything but the bridge.
public enum RFBAuthenticationMethod: Sendable, Equatable {
    case vncPassword
    case ardUsernamePassword
    case ultraVNCMSLogonII
}

/// The concrete secret material handed back to the protocol engine.
public enum PreparedRFBCredential: Sendable, Equatable {
    case password(String)
    case usernamePassword(username: String, password: String)
}

/// Pure, testable mapping from Screenway credentials to what the server's
/// chosen mechanism needs. Returns nil when required material is missing —
/// the session then fails with VNC-002 instead of continuing unauthenticated.
public enum RFBCredentialPreparer {
    public static func prepare(
        _ credentials: RFBCredentials,
        for method: RFBAuthenticationMethod
    ) -> PreparedRFBCredential? {
        guard let password = credentials.password, !password.isEmpty else { return nil }
        switch method {
        case .vncPassword:
            return .password(password)
        case .ardUsernamePassword, .ultraVNCMSLogonII:
            guard let username = credentials.username, !username.isEmpty else { return nil }
            return .usernamePassword(username: username, password: password)
        }
    }
}

/// One credential request from the protocol engine, completable exactly once.
public final class PendingCredentialRequest: @unchecked Sendable {
    public let method: RFBAuthenticationMethod
    private let lock = NSLock()
    private var completion: ((PreparedRFBCredential?) -> Void)?

    init(method: RFBAuthenticationMethod, completion: @escaping (PreparedRFBCredential?) -> Void) {
        self.method = method
        self.completion = completion
    }

    func fulfill(_ credential: PreparedRFBCredential?) {
        lock.lock()
        let stored = completion
        completion = nil
        lock.unlock()
        stored?(credential)
    }
}

// MARK: - Adapter

/// Live `RFBClientProtocol` implementation on top of RoyalVNCKit 1.1.0.
///
/// Bridging notes:
/// - RoyalVNCKit's `VNCConnection` runs the entire RFB handshake itself and
///   asks for credentials through a delegate callback mid-handshake. This
///   adapter maps that onto the Screenway two-step contract: `connect(to:)`
///   returns once the server asks for credentials (state `.authenticating`),
///   and `authenticate(_:)` fulfills the kit's pending request and waits for
///   the handshake to finish.
/// - Unauthenticated sessions are rejected: if the kit reports "connected"
///   before ever asking for a credential (server offered security type None),
///   the adapter disconnects and fails with VNC-002.
/// - The destination policy runs (and names are resolved + pinned to a
///   validated address) before any socket opens.
/// - Framebuffer pixels are copied out of the kit's BGRA surface per dirty
///   rect and forwarded as Screenway-owned `FramebufferUpdate` values; a
///   guarded allocator refuses surfaces above `FramebufferLimits`.
public actor RoyalVNCAdapter: RFBClientProtocol {
    private var stateMachine = SessionStateMachine()
    private let eventContinuation: AsyncStream<RFBClientEvent>.Continuation
    public nonisolated let events: AsyncStream<RFBClientEvent>

    private let resolver: any HostAddressResolver
    /// Test seam for adapter-contract tests against a loopback fixture
    /// server. Never true in production (see `init()`).
    private let allowsLoopbackForTesting: Bool

    public var state: SessionState { stateMachine.state }

    public init() {
        self.init(resolver: SystemHostAddressResolver(), allowingLoopbackForTesting: false)
    }

    init(resolver: any HostAddressResolver, allowingLoopbackForTesting: Bool = false) {
        self.resolver = resolver
        self.allowsLoopbackForTesting = allowingLoopbackForTesting
        var continuation: AsyncStream<RFBClientEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

#if canImport(RoyalVNCKit)
    private var connection: VNCConnection?
    private var bridge: RoyalVNCConnectionBridge?
    private var pendingCredentialRequest: PendingCredentialRequest?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var authContinuation: CheckedContinuation<Void, Error>?
    private var hasEnded = false
    private var framebufferWidth = 0
    private var framebufferHeight = 0
    private var heldKeys: Set<UInt32> = []
    private var heldButtons: Set<HeldButton> = []
    private var lastPointerX: UInt16 = 0
    private var lastPointerY: UInt16 = 0

    private enum HeldButton: Hashable {
        case left
        case right
    }

    // MARK: Connect

    public func connect(to endpoint: RFBEndpoint) async throws {
        guard state == .disconnected || state == .failed else {
            throw ScreenwayError(.vncSessionEnded, detail: "connect called in state \(state.rawValue)")
        }
        move(to: .resolving)

        let connectHost: String
        do {
            connectHost = try await RFBDestinationGate.authorizedConnectHost(
                for: endpoint,
                resolver: resolver,
                allowingLoopback: allowsLoopbackForTesting
            )
        } catch let error as ScreenwayError {
            move(to: .failed)
            throw error
        }

        move(to: .connecting)

        let settings = VNCConnection.Settings(
            isDebugLoggingEnabled: false,
            hostname: connectHost,
            port: endpoint.port,
            isShared: true,
            isScalingEnabled: false,
            useDisplayLink: false,
            inputMode: .forwardKeyboardShortcutsIfNotInUseLocally,
            isClipboardRedirectionEnabled: false,
            colorDepth: .depth24Bit,
            frameEncodings: [.tight, .zrle, .zlib, .hextile, .coRRE, .rre]
        )
        let bridge = RoyalVNCConnectionBridge(owner: self, continuation: eventContinuation)
        let connection = VNCConnection(
            settings: settings,
            framebufferAllocator: GuardedFramebufferAllocator()
        )
        connection.delegate = bridge
        self.connection = connection
        self.bridge = bridge
        self.hasEnded = false

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectContinuation = continuation
            connection.connect()
        }
    }

    // MARK: Authenticate

    public func authenticate(_ credentials: RFBCredentials) async throws {
        guard state == .authenticating, let request = pendingCredentialRequest else {
            throw ScreenwayError(.vncSessionEnded, detail: "authenticate called in state \(state.rawValue)")
        }
        pendingCredentialRequest = nil
        move(to: .negotiating)

        let prepared = RFBCredentialPreparer.prepare(credentials, for: request.method)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.authContinuation = continuation
            // A nil credential makes the kit fail the handshake with an
            // authentication error, which maps to VNC-002 below.
            request.fulfill(prepared)
        }
    }

    // MARK: Disconnect

    public func disconnect() async {
        guard connection != nil || state != .disconnected else { return }
        pendingCredentialRequest?.fulfill(nil)
        pendingCredentialRequest = nil

        if let connection {
            if state == .connected, !heldKeys.isEmpty || !heldButtons.isEmpty {
                releaseHeldInputs(on: connection)
                // The kit flushes input through an async send queue; give the
                // release events a moment to reach the wire before closing.
                try? await Task.sleep(for: .milliseconds(200))
            }
            connection.disconnect()
        }
        finishSession(error: nil)
        failPendingContinuations(with: ScreenwayError(.vncSessionEnded, detail: "disconnected locally"))
        connection = nil
        bridge = nil
    }

    // MARK: Input

    public func sendPointerEvent(x: Int, y: Int, button: PointerButton) async throws {
        guard state == .connected, let connection else {
            throw ScreenwayError(.vncSessionEnded, detail: "not connected")
        }
        let clampedX = clamp(x, upTo: framebufferWidth)
        let clampedY = clamp(y, upTo: framebufferHeight)
        lastPointerX = clampedX
        lastPointerY = clampedY

        switch button {
        case .left:
            heldButtons.insert(.left)
            connection.mouseButtonDown(.left, x: clampedX, y: clampedY)
        case .right:
            heldButtons.insert(.right)
            connection.mouseButtonDown(.right, x: clampedX, y: clampedY)
        case .none:
            if heldButtons.isEmpty {
                connection.mouseMove(x: clampedX, y: clampedY)
            } else {
                if heldButtons.contains(.left) {
                    connection.mouseButtonUp(.left, x: clampedX, y: clampedY)
                }
                if heldButtons.contains(.right) {
                    connection.mouseButtonUp(.right, x: clampedX, y: clampedY)
                }
                heldButtons.removeAll()
            }
        case .scroll(let deltaX, let deltaY):
            if deltaY != 0 {
                connection.mouseWheel(deltaY > 0 ? .up : .down, x: clampedX, y: clampedY, steps: UInt32(min(abs(deltaY), 16)))
            }
            if deltaX != 0 {
                connection.mouseWheel(deltaX > 0 ? .left : .right, x: clampedX, y: clampedY, steps: UInt32(min(abs(deltaX), 16)))
            }
        }
    }

    public func sendKeyEvent(keyCode: UInt32, isDown: Bool) async throws {
        guard state == .connected, let connection else {
            throw ScreenwayError(.vncSessionEnded, detail: "not connected")
        }
        if isDown {
            heldKeys.insert(keyCode)
            connection.keyDown(VNCKeyCode(keyCode))
        } else {
            heldKeys.remove(keyCode)
            connection.keyUp(VNCKeyCode(keyCode))
        }
    }

    public func sendClipboardText(_ text: String) async throws {
        // RoyalVNCKit 1.1.0 exposes no direct client-cut-text API (its
        // clipboard support monitors the system pasteboard). Clipboard is a
        // later gate; the Gate 2 slice does not offer this path in the UI.
        throw ScreenwayError(.clipboardPasteRejected, detail: "Clipboard redirection is not part of the Gate 2 slice")
    }

    // MARK: Bridge callbacks (internal)

    func kitDidRequestCredential(_ request: PendingCredentialRequest) {
        guard state == .connecting, connectContinuation != nil else {
            // Unexpected re-authentication mid-session; refuse.
            request.fulfill(nil)
            return
        }
        pendingCredentialRequest = request
        move(to: .authenticating)
        resumeConnect(.success(()))
    }

    func kitDidConnect() {
        if connectContinuation != nil {
            // Handshake completed without the server ever asking for a
            // credential: the server allowed an unauthenticated session.
            // Screenway rejects those outright.
            connection?.disconnect()
            move(to: .failed)
            let error = ScreenwayError(
                .vncSignInFailed,
                detail: "Server allowed an unauthenticated session; Screenway requires authentication"
            )
            resumeConnect(.failure(error))
            return
        }
        if authContinuation != nil {
            move(to: .connected)
            resumeAuth(.success(()))
        }
    }

    func kitDidDisconnect(_ mapped: ScreenwayError?) {
        if connectContinuation != nil {
            move(to: .failed)
            resumeConnect(.failure(mapped ?? ScreenwayError(.vncSessionEnded)))
            return
        }
        if authContinuation != nil {
            move(to: .failed)
            resumeAuth(.failure(mapped ?? ScreenwayError(.vncSignInFailed)))
            return
        }
        finishSession(error: mapped)
    }

    func kitFramebufferGeometryChanged(width: Int, height: Int) {
        guard FramebufferLimits.isValidSurface(width: width, height: height, bytesPerPixel: 4) else {
            // Geometry outside the safety caps (the byte cap is separately
            // enforced pre-allocation by GuardedFramebufferAllocator).
            let error = RFBFailure.protocolError.error(
                detail: "Framebuffer \(width)x\(height) exceeds safety limits"
            )
            connection?.disconnect()
            if connectContinuation != nil {
                move(to: .failed)
                resumeConnect(.failure(error))
            } else if authContinuation != nil {
                move(to: .failed)
                resumeAuth(.failure(error))
            } else {
                finishSession(error: error)
            }
            return
        }
        framebufferWidth = width
        framebufferHeight = height
        eventContinuation.yield(.framebufferGeometryChanged(width: width, height: height))
    }

    // MARK: Private

    private func move(to newState: SessionState) {
        guard newState != stateMachine.state else { return }
        stateMachine.transition(to: newState)
        eventContinuation.yield(.stateChanged(stateMachine.state))
    }

    private func finishSession(error: ScreenwayError?) {
        guard !hasEnded else { return }
        hasEnded = true
        if state != .disconnected, state != .failed {
            move(to: error == nil ? .disconnected : .failed)
        }
        heldKeys.removeAll()
        heldButtons.removeAll()
        eventContinuation.yield(.sessionEnded(error))
    }

    private func failPendingContinuations(with error: ScreenwayError) {
        resumeConnect(.failure(error))
        resumeAuth(.failure(error))
    }

    private func resumeConnect(_ result: Result<Void, Error>) {
        guard let continuation = connectContinuation else { return }
        connectContinuation = nil
        continuation.resume(with: result)
    }

    private func resumeAuth(_ result: Result<Void, Error>) {
        guard let continuation = authContinuation else { return }
        authContinuation = nil
        continuation.resume(with: result)
    }

    private func releaseHeldInputs(on connection: VNCConnection) {
        if heldButtons.contains(.left) {
            connection.mouseButtonUp(.left, x: lastPointerX, y: lastPointerY)
        }
        if heldButtons.contains(.right) {
            connection.mouseButtonUp(.right, x: lastPointerX, y: lastPointerY)
        }
        heldButtons.removeAll()
        for keyCode in heldKeys {
            connection.keyUp(VNCKeyCode(keyCode))
        }
        heldKeys.removeAll()
    }

    private func clamp(_ value: Int, upTo limit: Int) -> UInt16 {
        let upperBound = limit > 0 ? min(limit - 1, Int(UInt16.max)) : Int(UInt16.max)
        return UInt16(min(max(value, 0), upperBound))
    }

#else
    public func connect(to endpoint: RFBEndpoint) async throws {
        throw ScreenwayError(.vncSessionEnded, detail: "RoyalVNCKit is unavailable on this platform")
    }

    public func authenticate(_ credentials: RFBCredentials) async throws {
        throw ScreenwayError(.vncSessionEnded, detail: "RoyalVNCKit is unavailable on this platform")
    }

    public func disconnect() async {}

    public func sendPointerEvent(x: Int, y: Int, button: PointerButton) async throws {
        throw ScreenwayError(.vncSessionEnded, detail: "RoyalVNCKit is unavailable on this platform")
    }

    public func sendKeyEvent(keyCode: UInt32, isDown: Bool) async throws {
        throw ScreenwayError(.vncSessionEnded, detail: "RoyalVNCKit is unavailable on this platform")
    }

    public func sendClipboardText(_ text: String) async throws {
        throw ScreenwayError(.clipboardPasteRejected, detail: "RoyalVNCKit is unavailable on this platform")
    }
#endif
}

#if canImport(RoyalVNCKit)

// MARK: - Guarded allocator

/// Framebuffer allocator that enforces `FramebufferLimits.maxDecodedBytes`
/// *before* allocating. Mirrors the kit's malloc allocator otherwise.
final class GuardedFramebufferAllocator: VNCFramebufferAllocator, @unchecked Sendable {
    private let bufferLock = NSLock()

    func allocate(size: Int) throws -> UnsafeMutableRawPointer {
        guard size > 0, size <= FramebufferLimits.maxDecodedBytes else {
            throw ScreenwayError(
                .vncFormatUnsupported,
                detail: "Refused framebuffer allocation of \(size) bytes (cap \(FramebufferLimits.maxDecodedBytes))"
            )
        }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<UInt8>.alignment)
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        return buffer
    }

    func deallocate(buffer: UnsafeMutableRawPointer) {
        buffer.deallocate()
    }

    func lockReadOnly() { bufferLock.lock() }
    func unlockReadOnly() { bufferLock.unlock() }
    func lockReadWrite() { bufferLock.lock() }
    func unlockReadWrite() { bufferLock.unlock() }
}

// MARK: - Delegate bridge

/// The only type that touches RoyalVNCKit callbacks. Copies pixel bytes out
/// synchronously (so dirty rects are applied in wire order) and forwards
/// lifecycle changes into the adapter actor.
final class RoyalVNCConnectionBridge: NSObject, VNCConnectionDelegate, @unchecked Sendable {
    private weak var owner: RoyalVNCAdapter?
    private let continuation: AsyncStream<RFBClientEvent>.Continuation

    init(owner: RoyalVNCAdapter, continuation: AsyncStream<RFBClientEvent>.Continuation) {
        self.owner = owner
        self.continuation = continuation
    }

    func connection(_ connection: VNCConnection, stateDidChange connectionState: VNCConnection.ConnectionState) {
        let owner = owner
        switch connectionState.status {
        case .connecting, .disconnecting:
            break
        case .connected:
            Task { await owner?.kitDidConnect() }
        case .disconnected:
            let mapped = Self.mapKitError(connectionState.error)
            Task { await owner?.kitDidDisconnect(mapped) }
        @unknown default:
            break
        }
    }

    func connection(
        _ connection: VNCConnection,
        credentialFor authenticationType: VNCAuthenticationType,
        completion: @escaping (VNCCredential?) -> Void
    ) {
        let method: RFBAuthenticationMethod
        switch authenticationType {
        case .vnc:
            method = .vncPassword
        case .appleRemoteDesktop:
            method = .ardUsernamePassword
        case .ultraVNCMSLogonII:
            method = .ultraVNCMSLogonII
        @unknown default:
            method = .vncPassword
        }
        let request = PendingCredentialRequest(method: method) { prepared in
            switch prepared {
            case .password(let password):
                completion(VNCPasswordCredential(password: password))
            case .usernamePassword(let username, let password):
                completion(VNCUsernamePasswordCredential(username: username, password: password))
            case nil:
                completion(nil)
            }
        }
        let owner = owner
        Task { await owner?.kitDidRequestCredential(request) }
    }

    func connection(_ connection: VNCConnection, didCreateFramebuffer framebuffer: VNCFramebuffer) {
        notifyGeometry(of: framebuffer)
    }

    func connection(_ connection: VNCConnection, didResizeFramebuffer framebuffer: VNCFramebuffer) {
        notifyGeometry(of: framebuffer)
    }

    func connection(
        _ connection: VNCConnection,
        didUpdateFramebuffer framebuffer: VNCFramebuffer,
        x: UInt16, y: UInt16,
        width: UInt16, height: UInt16
    ) {
        guard let update = Self.dirtyRectUpdate(from: framebuffer, x: x, y: y, width: width, height: height) else {
            return
        }
        continuation.yield(.framebufferUpdated(update))
    }

    func connection(_ connection: VNCConnection, didUpdateCursor cursor: VNCCursor) {
        // Remote cursor rendering is a later gate.
    }

    private func notifyGeometry(of framebuffer: VNCFramebuffer) {
        let width = Int(framebuffer.size.width)
        let height = Int(framebuffer.size.height)
        let owner = owner
        Task { await owner?.kitFramebufferGeometryChanged(width: width, height: height) }
    }

    /// Copies one dirty rect out of the kit's BGRA surface. Validates all
    /// geometry against `FramebufferLimits` before touching memory.
    static func dirtyRectUpdate(
        from framebuffer: VNCFramebuffer,
        x: UInt16, y: UInt16,
        width: UInt16, height: UInt16
    ) -> FramebufferUpdate? {
        let surfaceWidth = Int(framebuffer.size.width)
        let surfaceHeight = Int(framebuffer.size.height)
        let rectX = Int(x)
        let rectY = Int(y)
        let rectWidth = Int(width)
        let rectHeight = Int(height)
        let bytesPerPixel = 4

        guard FramebufferLimits.isValidSurface(width: surfaceWidth, height: surfaceHeight, bytesPerPixel: bytesPerPixel),
              FramebufferLimits.isValidRect(
                x: rectX, y: rectY, width: rectWidth, height: rectHeight,
                surfaceWidth: surfaceWidth, surfaceHeight: surfaceHeight
              ),
              framebuffer.surfaceByteCount == surfaceWidth * surfaceHeight * bytesPerPixel
        else { return nil }

        let surfaceStride = surfaceWidth * bytesPerPixel
        let rowBytes = rectWidth * bytesPerPixel
        var data = Data(count: rowBytes * rectHeight)

        framebuffer.allocator.lockReadOnly()
        let source = framebuffer.surfaceAddress
        data.withUnsafeMutableBytes { destination in
            guard let destinationBase = destination.baseAddress else { return }
            for row in 0..<rectHeight {
                let sourceOffset = (rectY + row) * surfaceStride + rectX * bytesPerPixel
                memcpy(destinationBase + row * rowBytes, source + sourceOffset, rowBytes)
            }
        }
        framebuffer.allocator.unlockReadOnly()

        return FramebufferUpdate(
            x: rectX, y: rectY, width: rectWidth, height: rectHeight,
            pixels: FramebufferPixels(format: .bgra8888, bytesPerRow: rowBytes, data: data)
        )
    }

    // MARK: Error mapping

    /// Maps a kit failure to the stable Screenway error codes:
    /// DNS → NET-001, unreachable → NET-002, timeout → NET-003,
    /// refused → VNC-001, auth → VNC-002, protocol/format → VNC-003,
    /// closed → VNC-004.
    static func mapKitError(_ error: Error?) -> ScreenwayError? {
        guard let error else { return nil }
        if let screenwayError = error as? ScreenwayError {
            return screenwayError
        }
        guard let vncError = error as? VNCError else {
            return ScreenwayError(.vncSessionEnded, detail: String(describing: error))
        }
        switch vncError {
        case .authentication(let underlying):
            return RFBFailure.authenticationFailed.error(detail: String(describing: underlying))
        case .protocol(let underlying):
            return RFBFailure.protocolError.error(detail: String(describing: underlying))
        case .connection(let underlying):
            switch underlying {
            case .cancelled, .closed:
                return RFBFailure.sessionEnded.error(detail: String(describing: underlying))
            case .notReady:
                return RFBFailure.timedOut.error(detail: "connection not ready")
            case .closedDuringHandshake(let phase, let handshakeError):
                if let handshakeError, let transport = mapTransportError(handshakeError) {
                    return transport
                }
                // The framebuffer-cap refusal surfaces here (ServerInit throws).
                if let handshakeError, let screenwayError = handshakeError as? ScreenwayError {
                    return screenwayError
                }
                return RFBFailure.sessionEnded.error(detail: "closed during \(phase)")
            case .failed(let transportError):
                if let transportError, let transport = mapTransportError(transportError) {
                    return transport
                }
                return RFBFailure.timedOut.error(detail: transportError.map { String(describing: $0) })
            @unknown default:
                return RFBFailure.sessionEnded.error(detail: String(describing: underlying))
            }
        @unknown default:
            return RFBFailure.sessionEnded.error(detail: String(describing: vncError))
        }
    }

    static func mapTransportError(_ error: Error) -> ScreenwayError? {
        if let screenwayError = error as? ScreenwayError {
            return screenwayError
        }
#if canImport(Network)
        // if-case matching (not an exhaustive switch) so newer SDKs adding
        // NWError cases neither warn nor break the build.
        if let nwError = error as? NWError {
            if case .dns = nwError {
                return RFBFailure.nameResolution.error(detail: String(describing: nwError))
            }
            if case .posix(let code) = nwError {
                return RFBFailure.fromPOSIXCode(code.rawValue)?.error(detail: String(describing: nwError))
            }
            if case .tls = nwError {
                return RFBFailure.protocolError.error(detail: String(describing: nwError))
            }
            return nil
        }
#endif
        let posixCode = Int32((error as NSError).domain == NSPOSIXErrorDomain ? (error as NSError).code : -1)
        if posixCode >= 0, let failure = RFBFailure.fromPOSIXCode(posixCode) {
            return failure.error(detail: String(describing: error))
        }
        return nil
    }
}

#endif
