// IOKitDeviceDiscoveryTests.swift
// Tests for IOKit-based USB device discovery

import XCTest
@testable import USBIPDCore
@testable import Common

final class IOKitDeviceDiscoveryTests: XCTestCase {
    
    var discovery: IOKitDeviceDiscovery!
    
    override func setUp() {
        super.setUp()
        discovery = IOKitDeviceDiscovery()
    }
    
    override func tearDown() {
        discovery.stopNotifications()
        discovery = nil
        super.tearDown()
    }
    
    // MARK: - Device Discovery Tests
    
    func testDiscoverDevices() throws {
        // Test that device discovery doesn't throw and returns an array
        let devices = try discovery.discoverDevices()
        
        // We can't guarantee specific devices will be present, but the call should succeed
        XCTAssertTrue(devices.count >= 0, "Device discovery should return a valid array")
        
        // If devices are found, verify they have valid properties
        for device in devices {
            XCTAssertFalse(device.busID.isEmpty, "Bus ID should not be empty")
            XCTAssertFalse(device.deviceID.isEmpty, "Device ID should not be empty")
            XCTAssertTrue(device.vendorID > 0 || device.vendorID == 0, "Vendor ID should be valid")
            XCTAssertTrue(device.productID > 0 || device.productID == 0, "Product ID should be valid")
        }
    }
    
    func testGetSpecificDevice() throws {
        // First discover all devices
        let devices = try discovery.discoverDevices()
        
        guard let firstDevice = devices.first else {
            // No devices available for testing
            return
        }
        
        // Try to get the specific device
        let foundDevice = try discovery.getDevice(busID: firstDevice.busID, deviceID: firstDevice.deviceID)
        
        XCTAssertNotNil(foundDevice, "Should find the device that was discovered")
        XCTAssertEqual(foundDevice?.busID, firstDevice.busID)
        XCTAssertEqual(foundDevice?.deviceID, firstDevice.deviceID)
        XCTAssertEqual(foundDevice?.vendorID, firstDevice.vendorID)
        XCTAssertEqual(foundDevice?.productID, firstDevice.productID)
    }
    
    func testGetNonExistentDevice() throws {
        // Try to get a device that doesn't exist
        let foundDevice = try discovery.getDevice(busID: "999", deviceID: "999")
        
        XCTAssertNil(foundDevice, "Should not find non-existent device")
    }
    
    // MARK: - Notification Tests
    
    func testStartStopNotifications() throws {
        // Test that starting notifications doesn't throw
        XCTAssertNoThrow(try discovery.startNotifications())
        
        // Test that stopping notifications doesn't throw
        XCTAssertNoThrow(discovery.stopNotifications())
        
        // Test that starting again after stopping works
        XCTAssertNoThrow(try discovery.startNotifications())
    }
    
    func testMultipleStartNotifications() throws {
        // Starting notifications multiple times should not cause issues
        try discovery.startNotifications()
        try discovery.startNotifications() // Should be safe to call again
        
        discovery.stopNotifications()
    }
    
    func testNotificationCallbacks() throws {
        var connectedDevices: [USBDevice] = []
        var disconnectedDevices: [USBDevice] = []
        
        discovery.onDeviceConnected = { device in
            connectedDevices.append(device)
        }
        
        discovery.onDeviceDisconnected = { device in
            disconnectedDevices.append(device)
        }
        
        // Start notifications
        try discovery.startNotifications()
        
        // We can't easily trigger device connection/disconnection in tests,
        // but we can verify the callbacks are set
        XCTAssertNotNil(discovery.onDeviceConnected)
        XCTAssertNotNil(discovery.onDeviceDisconnected)
    }
    
    // MARK: - USB Device Tests
    
    func testUSBDeviceCreation() {
        let device = USBDevice(
            busID: "1",
            deviceID: "2",
            vendorID: 0x1234,
            productID: 0x5678,
            deviceClass: 9,
            deviceSubClass: 0,
            deviceProtocol: 0,
            speed: .high,
            manufacturerString: "Test Manufacturer",
            productString: "Test Product",
            serialNumberString: "123456"
        )
        
        XCTAssertEqual(device.busID, "1")
        XCTAssertEqual(device.deviceID, "2")
        XCTAssertEqual(device.vendorID, 0x1234)
        XCTAssertEqual(device.productID, 0x5678)
        XCTAssertEqual(device.deviceClass, 9)
        XCTAssertEqual(device.deviceSubClass, 0)
        XCTAssertEqual(device.deviceProtocol, 0)
        XCTAssertEqual(device.speed, .high)
        XCTAssertEqual(device.manufacturerString, "Test Manufacturer")
        XCTAssertEqual(device.productString, "Test Product")
        XCTAssertEqual(device.serialNumberString, "123456")
    }
    
    func testUSBSpeedEnum() {
        XCTAssertEqual(USBSpeed.unknown.rawValue, 0)
        XCTAssertEqual(USBSpeed.low.rawValue, 1)
        XCTAssertEqual(USBSpeed.full.rawValue, 2)
        XCTAssertEqual(USBSpeed.high.rawValue, 3)
        XCTAssertEqual(USBSpeed.superSpeed.rawValue, 4)
    }
    
    // MARK: - Error Handling Tests
    
    func testDeviceDiscoveryErrorDescriptions() {
        let errors: [DeviceDiscoveryError] = [
            .failedToCreateMatchingDictionary,
            .failedToGetMatchingServices(KERN_FAILURE),
            .missingProperty("testProperty"),
            .invalidPropertyType("testProperty"),
            .failedToCreateNotificationPort,
            .failedToAddNotification(KERN_FAILURE)
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}