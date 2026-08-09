// ControlSocketTests.swift
// The channel bind and unbind use to reach a running daemon.

import XCTest
@testable import USBIPDCore
@testable import Common

final class ControlSocketTests: XCTestCase {

    private var path: String!
    private var server: ControlSocketServer?

    override func setUp() {
        super.setUp()
        // Short, because a Unix socket path has to fit in sun_path (104 bytes here) and
        // the system temporary directory is already long.
        path = "/tmp/usbipd-ctl-\(UUID().uuidString.prefix(8)).sock"
    }

    override func tearDown() {
        server?.stop()
        server = nil
        try? FileManager.default.removeItem(atPath: path)
        path = nil
        super.tearDown()
    }

    /// Start a server that records what it was asked and answers as told.
    private func startServer(answering response: ControlResponse = ControlResponse(ok: true, changed: true),
                             recording seen: @escaping (ControlRequest) -> Void = { _ in }) throws {
        let server = ControlSocketServer(path: path) { request in
            seen(request)
            return response
        }
        try server.start()
        self.server = server
    }

    // MARK: - Round trip

    func testBindRequestReachesTheHandler() throws {
        let received = expectation(description: "the handler saw the request")
        var command: ControlRequest.Command?
        var busid: String?

        try startServer { request in
            command = request.command
            busid = request.busid
            received.fulfill()
        }

        let response = ControlSocketClient.send(ControlRequest(command: .bind, busid: "32-2.2"), to: path)

        wait(for: [received], timeout: 5.0)
        XCTAssertEqual(command, .bind)
        XCTAssertEqual(busid, "32-2.2")
        XCTAssertEqual(response?.ok, true)
        XCTAssertEqual(response?.changed, true)
    }

    func testUnbindRequestRoundTrips() throws {
        try startServer(answering: ControlResponse(ok: true, changed: false))
        let response = ControlSocketClient.send(ControlRequest(command: .unbind, busid: "1-1"), to: path)
        XCTAssertEqual(response?.ok, true)
        XCTAssertEqual(response?.changed, false, "an unbind of something unbound changes nothing")
    }

    /// A refusal has to survive the round trip, or the CLI cannot report it.
    func testFailureCarriesItsReason() throws {
        try startServer(answering: ControlResponse(ok: false, changed: false, error: "device is on fire"))
        let response = ControlSocketClient.send(ControlRequest(command: .bind, busid: "1-1"), to: path)
        XCTAssertEqual(response?.ok, false)
        XCTAssertEqual(response?.error, "device is on fire")
    }

    // MARK: - No daemon

    /// Not an error. Binding before the daemon has ever run is ordinary, and the CLI
    /// falls back to writing the state itself — so nil has to mean "nobody listening"
    /// rather than "something went wrong".
    func testSendingToNothingReturnsNil() {
        let response = ControlSocketClient.send(
            ControlRequest(command: .bind, busid: "1-1"),
            to: "/tmp/usbipd-ctl-absent-\(UUID().uuidString.prefix(8)).sock")
        XCTAssertNil(response)
    }

    /// A daemon that died without cleaning up leaves the socket file behind. Starting
    /// again must reclaim the name rather than fail to listen.
    func testAStaleSocketFileDoesNotPreventListening() throws {
        FileManager.default.createFile(atPath: path, contents: Data("stale".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        try startServer()
        let response = ControlSocketClient.send(ControlRequest(command: .bind, busid: "1-1"), to: path)
        XCTAssertEqual(response?.ok, true)
    }

    // MARK: - Reachability

    /// The reason this is a Unix socket and not a command on port 3240.
    ///
    /// The USB/IP port is exposed to the network — that is its purpose. A bind command
    /// reachable there would let any host that can open a TCP connection to this machine
    /// share any USB device attached to it. This asserts the socket is a filesystem
    /// object, which is what confines it to processes on this machine.
    func testTheControlSocketIsAFilesystemObjectNotAPort() throws {
        try startServer()

        var status = stat()
        XCTAssertEqual(stat(path, &status), 0, "the control endpoint should exist as a file")
        XCTAssertEqual(status.st_mode & S_IFMT, S_IFSOCK, "it should be a socket file")

        // And only its owner may talk to it.
        XCTAssertEqual(status.st_mode & 0o777, 0o600, "the socket must not be group- or world-accessible")
    }

    /// Garbage must not take the listener down; the next caller still gets served.
    func testMalformedInputIsRejectedAndTheServerSurvives() throws {
        try startServer()

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { source in
                strncpy(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self), source, 100)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, size) }
        }
        XCTAssertEqual(connected, 0)
        _ = "not json at all".withCString { write(descriptor, $0, 15) }
        var buffer = [UInt8](repeating: 0, count: 1024)
        let count = read(descriptor, &buffer, buffer.count)
        close(descriptor)

        XCTAssertGreaterThan(count, 0, "a malformed request should still be answered")
        let response = try JSONDecoder().decode(ControlResponse.self, from: Data(buffer[0..<count]))
        XCTAssertFalse(response.ok)

        // Still serving.
        XCTAssertEqual(ControlSocketClient.send(ControlRequest(command: .bind, busid: "1-1"), to: path)?.ok, true)
    }

    // MARK: - Against the real store

    /// The wiring the daemon actually uses: a request in, the persisted list changed.
    func testRequestsMutateTheBoundDeviceStore() throws {
        let storePath = "/tmp/usbipd-store-\(UUID().uuidString.prefix(8)).json"
        defer {
            try? FileManager.default.removeItem(atPath: storePath)
            try? FileManager.default.removeItem(atPath: storePath + ".lock")
        }
        let store = BoundDeviceStore(path: storePath)

        let server = ControlSocketServer(path: path) { request in
            do {
                let changed: Bool
                switch request.command {
                case .bind: changed = try store.bind(request.busid)
                case .unbind: changed = try store.unbind(request.busid)
                }
                return ControlResponse(ok: true, changed: changed)
            } catch {
                return ControlResponse(ok: false, changed: false, error: error.localizedDescription)
            }
        }
        try server.start()
        self.server = server

        XCTAssertEqual(ControlSocketClient.send(ControlRequest(command: .bind, busid: "32-2.2"), to: path)?.changed, true)
        XCTAssertTrue(store.isBound("32-2.2"))

        XCTAssertEqual(ControlSocketClient.send(ControlRequest(command: .bind, busid: "32-2.2"), to: path)?.changed, false,
                       "binding twice changes nothing")

        XCTAssertEqual(ControlSocketClient.send(ControlRequest(command: .unbind, busid: "32-2.2"), to: path)?.changed, true)
        XCTAssertFalse(store.isBound("32-2.2"))
    }
}
