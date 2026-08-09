// USBIPDeviceIdentityTests.swift
// A devid must name the device it was issued for, including behind a hub.

import XCTest
@testable import USBIPDCore
@testable import Common

final class USBIPDeviceIdentityTests: XCTestCase {

    private func device(
        busID: String,
        deviceID: String,
        vendorID: UInt16 = 0x1234,
        productID: UInt16 = 0x5678
    ) -> USBDevice {
        return USBDevice(
            busID: busID,
            deviceID: deviceID,
            vendorID: vendorID,
            productID: productID,
            deviceClass: 0,
            deviceSubClass: 0,
            deviceProtocol: 0,
            speed: .high,
            manufacturerString: nil,
            productString: nil,
            serialNumberString: nil
        )
    }

    // MARK: - Packing a port path

    func testSingleTierPathPacksToItself() {
        XCTAssertEqual(USBIPDeviceIdentity.devnum(forPortPath: "2"), 0x2)
    }

    /// The case that was broken. Only the final port used to survive, so a device two
    /// tiers down was indistinguishable from one directly on the bus.
    func testNestedPathPacksEveryTier() {
        XCTAssertEqual(USBIPDeviceIdentity.devnum(forPortPath: "2.2"), 0x22)
        XCTAssertEqual(USBIPDeviceIdentity.devnum(forPortPath: "2.1.3"), 0x213)
        XCTAssertEqual(USBIPDeviceIdentity.devnum(forPortPath: "2.1.1.2"), 0x2112)
    }

    /// Distinctness is the whole point: these three all ended as 2 before.
    func testPathsThatSharedALastPortNowDiffer() {
        let packed = ["2", "1.2", "2.1.2"].map { USBIPDeviceIdentity.devnum(forPortPath: $0) }
        XCTAssertEqual(Set(packed).count, 3, "paths ending in the same port must not collide")
    }

    /// A nibble per tier holds four tiers and ports up to fifteen. Beyond that the
    /// encoding cannot tell the truth, and returning a wrong-but-plausible number is
    /// what caused the original bug — so it refuses instead.
    func testUnrepresentablePathsAreRefused() {
        XCTAssertNil(USBIPDeviceIdentity.devnum(forPortPath: "1.2.3.4.5"))
        XCTAssertNil(USBIPDeviceIdentity.devnum(forPortPath: "16"))
        XCTAssertNil(USBIPDeviceIdentity.devnum(forPortPath: ""))
        XCTAssertNil(USBIPDeviceIdentity.devnum(forPortPath: "x"))
    }

    // MARK: - Unpacking

    func testPortPathRoundTrips() {
        for path in ["2", "2.2", "2.1.3", "2.1.1.2", "15.15"] {
            guard let packed = USBIPDeviceIdentity.devnum(forPortPath: path) else {
                return XCTFail("\(path) should be representable")
            }
            XCTAssertEqual(USBIPDeviceIdentity.portPath(forDevnum: packed), path)
        }
    }

    // MARK: - devid

    func testDevidCombinesBusAndPortPath() {
        XCTAssertEqual(USBIPDeviceIdentity.devid(for: device(busID: "32", deviceID: "2.2")), 0x0020_0022)
    }

    // MARK: - Resolving a devid back to a device

    /// The failure this whole type exists to prevent. A CP2102N at 32-2.2 sits below a
    /// hub at 32-2; the old encoding gave both devid 0x200002, so importing the bridge
    /// handed back an identifier that resolved to the hub. macOS owns hubs, so the
    /// first transfer died on kIOReturnExclusiveAccess.
    func testDeviceBehindAHubResolvesToItselfAndNotTheHub() {
        let hub = device(busID: "32", deviceID: "2", vendorID: 0x17EF, productID: 0x3080)
        let bridge = device(busID: "32", deviceID: "2.2", vendorID: 0x10C4, productID: 0xEA60)
        let attached = [hub, bridge]

        guard let bridgeDevid = USBIPDeviceIdentity.devid(for: bridge) else {
            return XCTFail("the bridge should have a devid")
        }
        let resolved = USBIPDeviceIdentity.device(forDevid: bridgeDevid, among: attached)
        XCTAssertEqual(resolved?.deviceID, "2.2")
        XCTAssertEqual(resolved?.productID, 0xEA60)

        guard let hubDevid = USBIPDeviceIdentity.devid(for: hub) else {
            return XCTFail("the hub should have a devid")
        }
        XCTAssertNotEqual(hubDevid, bridgeDevid)
        XCTAssertEqual(USBIPDeviceIdentity.device(forDevid: hubDevid, among: attached)?.deviceID, "2")
    }

    /// Every device attached to a real dock must map to a distinct devid, or one of
    /// them silently takes another's traffic.
    func testAllDevicesOnARealDockGetDistinctDevids() {
        // Taken from `usbipd list` on the machine where the bug was found.
        let paths = ["4", "2", "4.1", "2.5", "2.1", "2.3", "2.1.3", "4.1.2", "2.1.1", "2.1.1.2", "2.2", "1"]
        let devids = paths.compactMap { USBIPDeviceIdentity.devid(for: device(busID: "32", deviceID: $0)) }

        XCTAssertEqual(devids.count, paths.count, "every path on this dock should be representable")
        XCTAssertEqual(Set(devids).count, paths.count, "two devices share a devid")
    }

    /// A devid for something no longer plugged in must resolve to nothing rather than
    /// to whatever now occupies that port.
    func testUnknownDevidResolvesToNothing() {
        let attached = [device(busID: "32", deviceID: "2.2")]
        XCTAssertNil(USBIPDeviceIdentity.device(forDevid: 0x0020_0099, among: attached))
    }
}
