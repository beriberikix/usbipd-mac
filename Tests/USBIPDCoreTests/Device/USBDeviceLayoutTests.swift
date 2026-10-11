// USBDeviceLayoutTests.swift
// Locating a device, finding each endpoint's owner, and spotting the standard requests
// the server answers itself.

import XCTest
@testable import USBIPDCore

final class USBDeviceLayoutTests: XCTestCase {

    // MARK: - Location

    /// The busids `usbipd list` prints for a FreeWili 2 behind its on-board hub, and the
    /// locationIDs IOKit reports for the same devices.
    func testBusidMapsBackToTheLocationItCameFrom() {
        XCTAssertEqual(USBDeviceLocation.locationID(busID: "2", deviceID: "1.1"), 0x0211_0000)
        XCTAssertEqual(USBDeviceLocation.locationID(busID: "2", deviceID: "1.4"), 0x0214_0000)
        XCTAssertEqual(USBDeviceLocation.locationID(busID: "2", deviceID: "1"), 0x0210_0000)
        XCTAssertEqual(USBDeviceLocation.locationID(busID: "32", deviceID: "2.1.3"), 0x2021_3000)
    }

    /// A root-hub device has no port path; discovery prints its device part as "0".
    func testRootDeviceHasNoPortPath() {
        XCTAssertEqual(USBDeviceLocation.locationID(busID: "1", deviceID: "0"), 0x0100_0000)
    }

    func testMalformedBusidsAreRejectedRatherThanGuessed() {
        XCTAssertNil(USBDeviceLocation.locationID(busID: "x", deviceID: "1"))
        XCTAssertNil(USBDeviceLocation.locationID(busID: "256", deviceID: "1"))
        XCTAssertNil(USBDeviceLocation.locationID(busID: "2", deviceID: "16"))
        XCTAssertNil(USBDeviceLocation.locationID(busID: "2", deviceID: "0.1"))
        XCTAssertNil(USBDeviceLocation.locationID(busID: "2", deviceID: "1.2.3.4.5.6.7"))
    }

    // MARK: - Endpoint owners

    /// A CDC-ACM port: a control interface with an interrupt IN, joined by an IAD to a
    /// data interface with two bulk endpoints — the shape of the FreeWili 2's "Board CDC".
    private let cdcConfiguration: [UInt8] = [
        0x09, 0x02, 0x4B, 0x00, 0x02, 0x01, 0x00, 0x80, 0x32, // configuration
        0x08, 0x0B, 0x00, 0x02, 0x02, 0x02, 0x00, 0x00,       // interface association
        0x09, 0x04, 0x00, 0x00, 0x01, 0x02, 0x02, 0x00, 0x04, // interface 0, CDC control
        0x05, 0x24, 0x00, 0x20, 0x01,                         // CDC header (class-specific)
        0x05, 0x24, 0x01, 0x00, 0x01,                         // call management
        0x04, 0x24, 0x02, 0x02,                               // ACM
        0x05, 0x24, 0x06, 0x00, 0x01,                         // union
        0x07, 0x05, 0x81, 0x03, 0x08, 0x00, 0x10,             // EP 0x81 interrupt IN
        0x09, 0x04, 0x01, 0x00, 0x02, 0x0A, 0x00, 0x00, 0x00, // interface 1, CDC data
        0x07, 0x05, 0x02, 0x02, 0x40, 0x00, 0x00,             // EP 0x02 bulk OUT
        0x07, 0x05, 0x82, 0x02, 0x40, 0x00, 0x00              // EP 0x82 bulk IN
    ]

    /// The notification endpoint belongs to the control interface — the one macOS keeps —
    /// and the class-specific descriptors between them must not confuse the walk.
    func testEachEndpointIsAttributedToItsOwnInterface() {
        let owners = USBConfigurationLayout.endpoints(in: cdcConfiguration)

        XCTAssertEqual(owners[0x81], USBEndpointOwner(interfaceNumber: 0, transferType: 3))
        XCTAssertEqual(owners[0x02], USBEndpointOwner(interfaceNumber: 1, transferType: 2))
        XCTAssertEqual(owners[0x82], USBEndpointOwner(interfaceNumber: 1, transferType: 2))
        XCTAssertEqual(owners.count, 3)
    }

    /// A descriptor cut short must stop the walk, not read past the end.
    func testTruncatedDescriptorStopsCleanly() {
        let truncated = Array(cdcConfiguration.prefix(cdcConfiguration.count - 3))
        let owners = USBConfigurationLayout.endpoints(in: truncated)

        XCTAssertEqual(owners[0x81]?.interfaceNumber, 0)
        XCTAssertEqual(owners[0x02]?.interfaceNumber, 1)
        XCTAssertNil(owners[0x82])
    }

    /// A zero length would never advance the walk.
    func testZeroLengthDescriptorDoesNotLoop() {
        XCTAssertTrue(USBConfigurationLayout.endpoints(in: [0x09, 0x02, 0x00, 0x00, 0x00, 0x00]).isEmpty)
    }

    // MARK: - Standard requests

    func testSetConfigurationIsRecognised() {
        XCTAssertEqual(
            USBStandardRequest(setupPacket: [0x00, 0x09, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00]),
            .setConfiguration(1))
    }

    func testSetInterfaceCarriesInterfaceAndAlternate() {
        XCTAssertEqual(
            USBStandardRequest(setupPacket: [0x01, 0x0B, 0x01, 0x00, 0x03, 0x00, 0x00, 0x00]),
            .setInterface(interface: 3, alternate: 1))
    }

    func testClearEndpointHaltCarriesTheEndpoint() {
        XCTAssertEqual(
            USBStandardRequest(setupPacket: [0x02, 0x01, 0x00, 0x00, 0x82, 0x00, 0x00, 0x00]),
            .clearEndpointHalt(endpoint: 0x82))
    }

    /// Class requests — SET_LINE_CODING, SET_CONTROL_LINE_STATE — go to the device as
    /// they are. They are what makes a served serial port usable.
    func testClassRequestsAreForwarded() {
        XCTAssertEqual(
            USBStandardRequest(setupPacket: [0x21, 0x20, 0x00, 0x00, 0x00, 0x00, 0x07, 0x00]),
            .other)
        XCTAssertEqual(
            USBStandardRequest(setupPacket: [0x21, 0x22, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00]),
            .other)
    }

    /// CLEAR_FEATURE for anything but ENDPOINT_HALT is not intercepted.
    func testOtherFeatureClearsAreForwarded() {
        XCTAssertEqual(
            USBStandardRequest(setupPacket: [0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00]),
            .other)
    }
}
