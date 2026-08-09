// BoundDeviceStoreTests.swift
// The bind list is state, kept apart from configuration and safe to write concurrently.

import XCTest
@testable import USBIPDCore
@testable import Common

final class BoundDeviceStoreTests: XCTestCase {

    private var path: String!
    private var store: BoundDeviceStore!

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "usbipd-bound-\(UUID().uuidString).json"
        store = BoundDeviceStore(path: path)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: path + ".lock")
        store = nil
        path = nil
        super.tearDown()
    }

    // MARK: - Basics

    /// Sharing is opt-in: a device nobody has bound is not offered. An earlier version
    /// treated an empty list as "allow everything", which meant a fresh install served
    /// every USB device on the machine to anything that could reach the port.
    func testNothingIsBoundInitially() {
        XCTAssertEqual(store.boundDevices(), [])
        XCTAssertFalse(store.isBound("1-1"))
    }

    func testBindAndUnbindRoundTrip() throws {
        XCTAssertTrue(try store.bind("1-1"))
        XCTAssertTrue(store.isBound("1-1"))

        XCTAssertTrue(try store.unbind("1-1"))
        XCTAssertFalse(store.isBound("1-1"))
    }

    func testBindingTwiceReportsNoChange() throws {
        XCTAssertTrue(try store.bind("1-1"))
        XCTAssertFalse(try store.bind("1-1"), "a second bind changes nothing")
        XCTAssertEqual(store.boundDevices(), ["1-1"])
    }

    func testUnbindingSomethingUnboundReportsNoChange() throws {
        XCTAssertFalse(try store.unbind("1-1"))
    }

    func testTheListSurvivesAnotherReader() throws {
        try store.bind("32-2.2")
        // A second instance is what the daemon is, relative to the CLI that wrote this.
        XCTAssertTrue(BoundDeviceStore(path: path).isBound("32-2.2"))
    }

    // MARK: - Isolation from configuration

    /// The point of the split. `bind` writing the configuration file meant sharing a USB
    /// device rewrote the port and log level too — and reset them outright whenever the
    /// configuration had failed to parse and the CLI had fallen back to defaults.
    func testBindDoesNotTouchTheConfigurationFile() throws {
        let configPath = NSTemporaryDirectory() + "usbipd-config-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: configPath) }

        let config = ServerConfig(port: 4242, logLevel: .debug)
        try config.save(to: configPath)
        let before = try Data(contentsOf: URL(fileURLWithPath: configPath))

        try store.bind("1-1")

        let after = try Data(contentsOf: URL(fileURLWithPath: configPath))
        XCTAssertEqual(before, after, "binding a device must not rewrite configuration")

        let reloaded = try ServerConfig.load(from: configPath)
        XCTAssertEqual(reloaded.port, 4242)
        XCTAssertEqual(reloaded.logLevel, .debug)
    }

    // MARK: - Concurrency

    /// Appending means read, add, write. Two commands doing that at once without a lock
    /// leave only one of the devices bound, because each writes a list built from what
    /// it read before the other's write landed.
    func testConcurrentBindsAllSurvive() {
        let count = 40
        DispatchQueue.concurrentPerform(iterations: count) { index in
            // A store per iteration: these stand in for separate `usbipd bind`
            // processes, which share nothing but the file and its lock.
            _ = try? BoundDeviceStore(path: self.path).bind("1-\(index)")
        }

        let bound = Set(store.boundDevices())
        XCTAssertEqual(bound.count, count, "a concurrent bind was lost")
        for index in 0..<count {
            XCTAssertTrue(bound.contains("1-\(index)"), "1-\(index) was lost")
        }
    }

    /// Removals race in the same way.
    func testConcurrentUnbindsAllApply() throws {
        for index in 0..<20 {
            try store.bind("1-\(index)")
        }

        DispatchQueue.concurrentPerform(iterations: 20) { index in
            _ = try? BoundDeviceStore(path: self.path).unbind("1-\(index)")
        }

        XCTAssertEqual(store.boundDevices(), [], "a concurrent unbind was lost")
    }

    // MARK: - Reading damaged or absent files

    func testAnAbsentFileMeansNothingIsBound() {
        XCTAssertEqual(BoundDeviceStore(path: NSTemporaryDirectory() + "no-such-\(UUID().uuidString).json")
            .boundDevices(), [])
    }

    /// Better to report nothing bound than to crash the daemon. Writes are atomic, so
    /// this can only come from something outside the tool damaging the file.
    func testAnUnreadableFileMeansNothingIsBound() throws {
        try "not json".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.boundDevices(), [])
    }

    /// And it can be repaired by binding again, rather than staying stuck.
    func testBindingRepairsAnUnreadableFile() throws {
        try "not json".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertTrue(try store.bind("1-1"))
        XCTAssertEqual(store.boundDevices(), ["1-1"])
    }
}
