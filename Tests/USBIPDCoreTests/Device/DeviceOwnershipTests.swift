// DeviceOwnershipTests.swift
// bind refuses devices something else owns, so the classification has to be right.

import XCTest
import IOKit
@testable import USBIPDCore
@testable import Common

final class DeviceOwnershipTests: XCTestCase {

    /// The mock hands out service ids starting at its own base value.
    private let deviceEntry: io_registry_entry_t = 2000
    private let interfaceEntry: io_registry_entry_t = 200
    private let driverEntry: io_registry_entry_t = 300

    /// A device node whose single interface has the given driver children.
    ///
    /// `opens` models what actually decides ownership: whether the interface can be
    /// claimed. A driver being attached does not settle it — IOUserSerial sits on every
    /// FTDI interface and opens anyway.
    private func inspector(interfaceDrivers: [String], opens: Bool = false) -> DeviceOwnershipInspector {
        let ioKit = MockIOKitInterface()
        ioKit.mockDevices = [MockUSBDevice(vendorID: 0x1366, productID: 0x0101)]

        ioKit.classNamesByEntry[deviceEntry] = "IOUSBHostDevice"
        ioKit.classNamesByEntry[interfaceEntry] = "IOUSBHostInterface"
        ioKit.childrenByEntry[deviceEntry] = [interfaceEntry]

        var children: [io_registry_entry_t] = []
        for (offset, name) in interfaceDrivers.enumerated() {
            let entry = driverEntry + io_registry_entry_t(offset)
            ioKit.classNamesByEntry[entry] = name
            children.append(entry)
        }
        ioKit.childrenByEntry[interfaceEntry] = children
        if !opens && !interfaceDrivers.isEmpty {
            ioKit.interfacesThatRefuseToOpen = [interfaceEntry]
        }

        return DeviceOwnershipInspector(ioKit: ioKit)
    }

    func testInterfaceWithNoDriverIsServable() {
        let ownership = inspector(interfaceDrivers: []).ownership(vendorID: 0x1366, productID: 0x0101)
        XCTAssertEqual(ownership, .unbound)
        XCTAssertTrue(ownership.isServable)
    }

    func testKernelDriverBlocks() {
        let ownership = inspector(interfaceDrivers: ["AppleUserHIDDevice"])
            .ownership(vendorID: 0x1366, productID: 0x0101)
        XCTAssertEqual(ownership, .kernelDriver(drivers: ["AppleUserHIDDevice"]))
        XCTAssertFalse(ownership.isServable)
    }

    /// A userspace holder blocks too, but the remedy is to quit the process rather
    /// than to obtain an entitlement, so it must not be reported as a kernel driver.
    func testUserspaceHolderIsReportedSeparately() {
        let ownership = inspector(interfaceDrivers: ["AppleUSBHostFrameworkInterfaceClient"])
            .ownership(vendorID: 0x1366, productID: 0x0101)
        XCTAssertEqual(ownership, .userspaceProcess(clients: ["AppleUSBHostFrameworkInterfaceClient"]))
    }

    /// A webcam has both: its audio control interface is kernel-owned while its video
    /// interfaces are held by the camera framework. The harder blocker decides.
    func testKernelDriverWinsOverUserspaceHolder() {
        let ownership = inspector(interfaceDrivers: ["AppleUSBHostFrameworkInterfaceClient", "AppleUSBAudioControlNub"])
            .ownership(vendorID: 0x1366, productID: 0x0101)
        XCTAssertEqual(ownership, .kernelDriver(drivers: ["AppleUSBAudioControlNub"]))
    }

    /// This one appears whenever any process opens the device, including this
    /// project's own probe. Treating it as an owner made a J-Link that opens
    /// perfectly well report as taken.
    func testDeviceLevelUserClientIsNotAnOwner() {
        let ownership = inspector(interfaceDrivers: ["AppleUSBHostDeviceUserClient"])
            .ownership(vendorID: 0x1366, productID: 0x0101)
        XCTAssertEqual(ownership, .unbound)
    }

    func testStructuralNodesAreNotOwners() {
        let ownership = inspector(interfaceDrivers: ["IOUSBHostInterface", "AppleUSBHostCompositeDevice"])
            .ownership(vendorID: 0x1366, productID: 0x0101)
        XCTAssertEqual(ownership, .unbound)
    }

    /// Absent evidence of an owner, refusing to bind would be worse than letting the
    /// attempt proceed and fail with a real error.
    func testUnknownDeviceIsTreatedAsServable() {
        let ownership = inspector(interfaceDrivers: ["AppleUserHIDDevice"])
            .ownership(vendorID: 0xDEAD, productID: 0xBEEF)
        XCTAssertEqual(ownership, .unbound)
    }
}

// MARK: - Ownership is decided by opening, not by driver name

extension DeviceOwnershipTests {

    /// The bug this replaced: FTDI and CP210x adapters carry IOUserSerial on every
    /// interface, which was read as "kernel driver, refuse". They open fine and serve
    /// real bulk traffic over USB/IP, so refusing them was wrong — and it was the
    /// category users asked for most.
    func testDriverThatDoesNotHoldTheInterfaceIsNotAnOwner() {
        let ownership = inspector(interfaceDrivers: ["IOUserSerial"], opens: true)
            .ownership(vendorID: 0x1366, productID: 0x0101)
        XCTAssertEqual(ownership, .unbound)
        XCTAssertTrue(ownership.isServable)
    }

    /// And the converse still holds: a driver that does hold the interface blocks it.
    func testDriverThatHoldsTheInterfaceBlocks() {
        let ownership = inspector(interfaceDrivers: ["AppleUserHIDDevice"], opens: false)
            .ownership(vendorID: 0x1366, productID: 0x0101)
        XCTAssertEqual(ownership, .kernelDriver(drivers: ["AppleUserHIDDevice"]))
        XCTAssertFalse(ownership.isServable)
    }
}
