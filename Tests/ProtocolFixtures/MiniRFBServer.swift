import Foundation

#if canImport(Darwin)
import Darwin

/// A minimal RFB 3.8 server on 127.0.0.1 used by adapter-contract tests, so
/// CI never needs a live Mac. Supports two security modes:
/// - `.vncPassword`: offers classic VNC auth (type 2) and accepts any
///   response (the fixture verifies the wire flow, not DES).
/// - `.none`: offers security type None — the adapter must reject the
///   resulting unauthenticated session.
///
/// After a successful handshake it answers the first framebuffer-update
/// request with one raw-encoded full-frame rect (16x8, 32bpp) and records
/// every pointer/key client message it receives.
final class MiniRFBServer: @unchecked Sendable {
    enum SecurityMode {
        case none
        case vncPassword
    }

    struct PointerEvent: Equatable {
        let buttonMask: UInt8
        let x: UInt16
        let y: UInt16
    }

    struct KeyEvent: Equatable {
        let isDown: Bool
        let keysym: UInt32
    }

    static let framebufferWidth = 16
    static let framebufferHeight = 8
    static let desktopName = "fixture-mac"

    let port: UInt16

    private let mode: SecurityMode
    private let listenerFD: Int32
    private let lock = NSLock()
    private var clientFD: Int32 = -1
    private var _pointerEvents: [PointerEvent] = []
    private var _keyEvents: [KeyEvent] = []
    private var _clientDidDisconnect = false
    private var thread: Thread?

    var pointerEvents: [PointerEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _pointerEvents
    }

    var keyEvents: [KeyEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _keyEvents
    }

    var clientDidDisconnect: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _clientDidDisconnect
    }

    init?(mode: SecurityMode) {
        self.mode = mode

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var noSigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0 // Ephemeral; read the assigned port below.
        address.sin_addr.s_addr = UInt32(bigEndian: 0x7F00_0001) // 127.0.0.1
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(fd, 1) == 0 else {
            close(fd)
            return nil
        }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else {
            close(fd)
            return nil
        }

        self.listenerFD = fd
        self.port = UInt16(bigEndian: assigned.sin_port)

        let thread = Thread { [weak self] in
            self?.run()
        }
        thread.name = "MiniRFBServer"
        self.thread = thread
        thread.start()
    }

    deinit {
        stop()
    }

    private var stopped = false

    func stop() {
        lock.lock()
        let client = clientFD
        clientFD = -1
        let alreadyStopped = stopped
        stopped = true
        lock.unlock()
        if client >= 0 { close(client) }
        if !alreadyStopped { close(listenerFD) }
    }

    // MARK: - Protocol

    private func run() {
        let client = accept(listenerFD, nil, nil)
        guard client >= 0 else { return }
        var noSigpipe: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
        lock.lock()
        clientFD = client
        lock.unlock()

        do {
            try handshake(client)
            try messageLoop(client)
        } catch {
            // Client went away or sent something unexpected; either way the
            // session is over for fixture purposes.
        }
        lock.lock()
        _clientDidDisconnect = true
        if clientFD == client { clientFD = -1 }
        lock.unlock()
        close(client)
    }

    private func handshake(_ fd: Int32) throws {
        try sendAll(fd, Array("RFB 003.008\n".utf8))
        _ = try receiveExactly(fd, count: 12) // client protocol version

        switch mode {
        case .none:
            try sendAll(fd, [1, 1]) // one security type: None
            _ = try receiveExactly(fd, count: 1)
        case .vncPassword:
            try sendAll(fd, [1, 2]) // one security type: VNC authentication
            _ = try receiveExactly(fd, count: 1)
            try sendAll(fd, [UInt8](repeating: 0x5C, count: 16)) // challenge
            _ = try receiveExactly(fd, count: 16) // DES response (accepted blindly)
        }

        try sendAll(fd, [0, 0, 0, 0]) // SecurityResult: OK
        _ = try receiveExactly(fd, count: 1) // ClientInit

        try sendAll(fd, serverInitMessage())
    }

    private func serverInitMessage() -> [UInt8] {
        var message: [UInt8] = []
        message.append(contentsOf: bigEndian16(UInt16(Self.framebufferWidth)))
        message.append(contentsOf: bigEndian16(UInt16(Self.framebufferHeight)))
        // Server-native pixel format: 32bpp truecolor, little-endian,
        // shifts R16/G8/B0 (the client forces its own format afterwards).
        message.append(32) // bits per pixel
        message.append(24) // depth
        message.append(0)  // big endian
        message.append(1)  // true color
        message.append(contentsOf: bigEndian16(255)) // red max
        message.append(contentsOf: bigEndian16(255)) // green max
        message.append(contentsOf: bigEndian16(255)) // blue max
        message.append(16) // red shift
        message.append(8)  // green shift
        message.append(0)  // blue shift
        message.append(contentsOf: [0, 0, 0]) // padding
        let name = Array(Self.desktopName.utf8)
        message.append(contentsOf: bigEndian32(UInt32(name.count)))
        message.append(contentsOf: name)
        return message
    }

    private func messageLoop(_ fd: Int32) throws {
        var clientBytesPerPixel = 4
        var didSendFramebuffer = false

        while true {
            let messageType = try receiveExactly(fd, count: 1)[0]
            switch messageType {
            case 0: // SetPixelFormat
                let body = try receiveExactly(fd, count: 19)
                clientBytesPerPixel = Int(body[3]) / 8 // padding(3) then bits-per-pixel
                if clientBytesPerPixel < 1 || clientBytesPerPixel > 4 { clientBytesPerPixel = 4 }
            case 2: // SetEncodings
                _ = try receiveExactly(fd, count: 1)
                let countBytes = try receiveExactly(fd, count: 2)
                let count = Int(countBytes[0]) << 8 | Int(countBytes[1])
                _ = try receiveExactly(fd, count: 4 * count)
            case 3: // FramebufferUpdateRequest
                _ = try receiveExactly(fd, count: 9)
                if !didSendFramebuffer {
                    didSendFramebuffer = true
                    try sendAll(fd, framebufferUpdateMessage(bytesPerPixel: clientBytesPerPixel))
                }
            case 4: // KeyEvent
                let body = try receiveExactly(fd, count: 7)
                let keysym = UInt32(body[3]) << 24 | UInt32(body[4]) << 16 | UInt32(body[5]) << 8 | UInt32(body[6])
                lock.lock()
                _keyEvents.append(KeyEvent(isDown: body[0] != 0, keysym: keysym))
                lock.unlock()
            case 5: // PointerEvent
                let body = try receiveExactly(fd, count: 5)
                let x = UInt16(body[1]) << 8 | UInt16(body[2])
                let y = UInt16(body[3]) << 8 | UInt16(body[4])
                lock.lock()
                _pointerEvents.append(PointerEvent(buttonMask: body[0], x: x, y: y))
                lock.unlock()
            case 6: // ClientCutText
                _ = try receiveExactly(fd, count: 3)
                let lengthBytes = try receiveExactly(fd, count: 4)
                let length = Int(lengthBytes[0]) << 24 | Int(lengthBytes[1]) << 16 | Int(lengthBytes[2]) << 8 | Int(lengthBytes[3])
                _ = try receiveExactly(fd, count: length)
            case 150: // EnableContinuousUpdates
                _ = try receiveExactly(fd, count: 9)
            default:
                throw FixtureError.unexpectedMessage(messageType)
            }
        }
    }

    private func framebufferUpdateMessage(bytesPerPixel: Int) -> [UInt8] {
        var message: [UInt8] = [0, 0] // FramebufferUpdate + padding
        message.append(contentsOf: bigEndian16(1)) // one rectangle
        message.append(contentsOf: bigEndian16(0)) // x
        message.append(contentsOf: bigEndian16(0)) // y
        message.append(contentsOf: bigEndian16(UInt16(Self.framebufferWidth)))
        message.append(contentsOf: bigEndian16(UInt16(Self.framebufferHeight)))
        message.append(contentsOf: bigEndian32(0)) // raw encoding
        let pixelCount = Self.framebufferWidth * Self.framebufferHeight
        for index in 0..<pixelCount {
            // Recognizable ramp so renderer-side bytes are non-trivial.
            for byteIndex in 0..<bytesPerPixel {
                message.append(UInt8((index + byteIndex) % 251))
            }
        }
        return message
    }

    // MARK: - Socket plumbing

    private enum FixtureError: Error {
        case closed
        case unexpectedMessage(UInt8)
    }

    private func sendAll(_ fd: Int32, _ bytes: [UInt8]) throws {
        var sent = 0
        while sent < bytes.count {
            let result = bytes.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return send(fd, base + sent, bytes.count - sent, 0)
            }
            guard result > 0 else { throw FixtureError.closed }
            sent += result
        }
    }

    private func receiveExactly(_ fd: Int32, count: Int) throws -> [UInt8] {
        guard count >= 0 else { throw FixtureError.closed }
        var buffer = [UInt8](repeating: 0, count: count)
        var received = 0
        while received < count {
            let result = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return recv(fd, base + received, count - received, 0)
            }
            guard result > 0 else { throw FixtureError.closed }
            received += result
        }
        return buffer
    }

    private func bigEndian16(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    private func bigEndian32(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }
}

#endif
