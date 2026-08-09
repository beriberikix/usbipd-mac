// ControlSocket.swift
// The channel `bind` and `unbind` use to talk to a running daemon.

import Foundation
import Common

/// A request from the CLI to the daemon.
public struct ControlRequest: Codable {
    public enum Command: String, Codable {
        case bind
        case unbind
    }

    public let command: Command
    public let busid: String

    public init(command: Command, busid: String) {
        self.command = command
        self.busid = busid
    }
}

/// The daemon's answer.
public struct ControlResponse: Codable {
    /// Whether the daemon carried the request out.
    public let ok: Bool

    /// Whether anything actually changed — false when a device was already bound, or
    /// already absent. The distinction belongs to the caller's wording, not to whether
    /// the request succeeded.
    public let changed: Bool

    /// Present when `ok` is false.
    public let error: String?

    public init(ok: Bool, changed: Bool, error: String? = nil) {
        self.ok = ok
        self.changed = changed
        self.error = error
    }
}

/// Accepts control requests from the CLI on a Unix domain socket.
///
/// A Unix socket rather than the USB/IP port, deliberately. Port 3240 is exposed to the
/// network — that is its purpose — and a bind command reachable there would let any host
/// that can open a TCP connection to this machine share any USB device attached to it.
/// A socket in the user's own directory is reachable only by processes on this machine,
/// with the filesystem enforcing who may open it.
///
/// The daemon owning this state is what lets `bind` say what actually happened. Writing
/// the file and hoping the daemon noticed meant the command could only report that it
/// had written a file.
public final class ControlSocketServer {

    /// Handles one request and returns what to say back.
    public typealias Handler = (ControlRequest) -> ControlResponse

    private let path: String
    private let handler: Handler
    private let logger: Logger
    private var listener: FileHandle?
    private var descriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.usbipd.control-socket")
    private var source: DispatchSourceRead?

    public init(path: String = ControlSocketServer.defaultPath(), handler: @escaping Handler) {
        self.path = path
        self.handler = handler
        self.logger = Logger(subsystem: "com.usbipd.core", category: "control-socket")
    }

    /// `~/.usbipd/control.sock`, beside the state it manipulates.
    public static func defaultPath() -> String {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(ServerConfig.defaultConfigDirName)
        return directory.appendingPathComponent("control.sock").path
    }

    /// Begin listening. Throws if the socket cannot be created.
    public func start() throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // A socket file left by a daemon that did not shut down cleanly would make bind
        // fail to connect and, worse, make this one fail to listen. Removing it is safe:
        // a live daemon holds the descriptor, not the name.
        try? FileManager.default.removeItem(atPath: path)

        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw ServerError.initializationFailed("control socket: \(String(cString: strerror(errno)))")
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maxLength else {
            close(descriptor)
            throw ServerError.initializationFailed("control socket path is too long: \(path)")
        }
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { source in
                strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
                        source, maxLength - 1)
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, size) }
        }
        guard bound == 0 else {
            close(descriptor)
            throw ServerError.initializationFailed("control socket bind: \(String(cString: strerror(errno)))")
        }

        // Only this user may issue commands. The socket lives under the user's home
        // directory, but the mode says so explicitly rather than relying on that.
        chmod(path, 0o600)

        guard listen(descriptor, 8) == 0 else {
            close(descriptor)
            throw ServerError.initializationFailed("control socket listen: \(String(cString: strerror(errno)))")
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.resume()
        self.source = source

        logger.info("Control socket listening", context: ["path": path])
    }

    public func stop() {
        source?.cancel()
        source = nil
        if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    deinit {
        stop()
    }

    private func acceptOne() {
        let client = accept(descriptor, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }

        // Requests are one short line each, so a single read is enough. A caller that
        // sends nothing simply gets dropped.
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(client, &buffer, buffer.count)
        guard count > 0 else { return }

        let data = Data(buffer[0..<count])
        let response: ControlResponse
        if let request = try? JSONDecoder().decode(ControlRequest.self, from: data) {
            response = handler(request)
        } else {
            response = ControlResponse(ok: false, changed: false, error: "malformed control request")
        }

        if var encoded = try? JSONEncoder().encode(response) {
            encoded.append(0x0A)
            encoded.withUnsafeBytes { bytes in
                _ = write(client, bytes.baseAddress, bytes.count)
            }
        }
    }
}

/// Sends a control request to a running daemon.
public enum ControlSocketClient {

    /// Ask the daemon to carry out a command.
    ///
    /// Returns nil when no daemon is listening, which is not an error: `bind` before the
    /// daemon has ever been started is ordinary, and the caller falls back to writing
    /// the state itself.
    public static func send(_ request: ControlRequest,
                            to path: String = ControlSocketServer.defaultPath()) -> ControlResponse? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maxLength else { return nil }
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { source in
                strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
                        source, maxLength - 1)
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, size) }
        }
        guard connected == 0 else { return nil }

        // Don't hang the CLI if the daemon is wedged. A control request is a dictionary
        // update; anything slower than this is a daemon that cannot answer.
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        guard let encoded = try? JSONEncoder().encode(request) else { return nil }
        let written = encoded.withUnsafeBytes { bytes in
            write(descriptor, bytes.baseAddress, bytes.count)
        }
        guard written == encoded.count else { return nil }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(descriptor, &buffer, buffer.count)
        guard count > 0 else { return nil }

        return try? JSONDecoder().decode(ControlResponse.self, from: Data(buffer[0..<count]))
    }
}
