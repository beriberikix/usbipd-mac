// IOKitDeviceDiscoveryMockTests.swift
// Tests for IOKitDeviceDiscovery using mock IOKit interface

import XCTest
import IOKit.usb
@testable import USBIPDCore
import Common

final class IOKitDeviceDiscoveryMockTests: XCTestCase {
    
    var mockIOKit: MockIOKitInterface!
    var deviceDiscovery: IOKitDeviceDiscovery!
    var logger: Logger!
    
    override func setUp() {
        super.setUp()
        mockIOKit = MockIOKitInterface()
        logger = Logger(
            config: LoggerConfig(level: .debug),
            subsystem: "com.usbipd.mac.test",
            category: "device-discovery-test"
        )
        deviceDiscovery = IOKitDeviceDiscovery(ioKit: mockIOKit, logger: logger)
    }
    
    override func tearDown() {
        deviceDiscovery = nil
        mockIOKit = nil
        logger = nil
        super.tearDown()
    }
    
    // MARK: - Basic Functionality Tests
    
    func testDiscoverDevicesWithNoDevices() throws {
        // Given: No mock devices
        mockIOKit.mockDevices = TestUSBDeviceFixtures.noDevices
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should return empty array
        XCTAssertEqual(devices.count, 0)
        
        // Verify IOKit calls were made
        XCTAssertEqual(mockIOKit.serviceMatchingCalls.count, 1)
        XCTAssertEqual(mockIOKit.serviceMatchingCalls.first, kIOUSBDeviceClassName)
        XCTAssertEqual(mockIOKit.serviceGetMatchingServicesCalls.count, 1)
        XCTAssertTrue(mockIOKit.iteratorNextCalls.count > 0)
    }
    
    func testDiscoverDevicesWithSingleDevice() throws {
        // Given: Single mock device
        mockIOKit.mockDevices = TestUSBDeviceFixtures.singleDevice
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should return one device
        XCTAssertEqual(devices.count, 1)
        
        let device = devices.first!
        let expectedDevice = TestUSBDeviceFixtures.expectedUSBDevice(from: TestUSBDeviceFixtures.appleMagicMouse)
        
        XCTAssertEqual(device.busID, expectedDevice.busID)
        XCTAssertEqual(device.deviceID, expectedDevice.deviceID)
        XCTAssertEqual(device.vendorID, expectedDevice.vendorID)
        XCTAssertEqual(device.productID, expectedDevice.productID)
        XCTAssertEqual(device.deviceClass, expectedDevice.deviceClass)
        XCTAssertEqual(device.deviceSubClass, expectedDevice.deviceSubClass)
        XCTAssertEqual(device.deviceProtocol, expectedDevice.deviceProtocol)
        XCTAssertEqual(device.speed, expectedDevice.speed)
        XCTAssertEqual(device.manufacturerString, expectedDevice.manufacturerString)
        XCTAssertEqual(device.productString, expectedDevice.productString)
        XCTAssertEqual(device.serialNumberString, expectedDevice.serialNumberString)
    }
    
    func testDiscoverDevicesWithMultipleDevices() throws {
        // Given: Multiple mock devices
        mockIOKit.mockDevices = TestUSBDeviceFixtures.standardDevices
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should return all devices
        XCTAssertEqual(devices.count, TestUSBDeviceFixtures.standardDevices.count)
        
        // Verify each device was properly converted
        let expectedDevices = TestUSBDeviceFixtures.expectedUSBDevices(from: TestUSBDeviceFixtures.standardDevices)
        
        for (index, device) in devices.enumerated() {
            let expected = expectedDevices[index]
            XCTAssertEqual(device.vendorID, expected.vendorID, "Device \(index) vendor ID mismatch")
            XCTAssertEqual(device.productID, expected.productID, "Device \(index) product ID mismatch")
            XCTAssertEqual(device.manufacturerString, expected.manufacturerString, "Device \(index) manufacturer mismatch")
            XCTAssertEqual(device.productString, expected.productString, "Device \(index) product mismatch")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testDiscoverDevicesWithServiceMatchingFailure() {
        // Given: Service matching should fail
        mockIOKit.shouldFailServiceMatching = true
        
        // When/Then: Should throw error
        XCTAssertThrowsError(try deviceDiscovery.discoverDevices()) { error in
            guard case DeviceDiscoveryError.failedToCreateMatchingDictionary = error else {
                XCTFail("Expected failedToCreateMatchingDictionary error, got \(error)")
                return
            }
        }
    }
    
    func testDiscoverDevicesWithGetMatchingServicesFailure() {
        // Given: Getting matching services should fail
        mockIOKit.shouldFailGetMatchingServices = true
        mockIOKit.getMatchingServicesError = KERN_NO_ACCESS
        
        // When/Then: Should throw error
        XCTAssertThrowsError(try deviceDiscovery.discoverDevices()) { error in
            guard case DeviceDiscoveryError.ioKitError(let code, _) = error else {
                XCTFail("Expected ioKitError, got \(error)")
                return
            }
            XCTAssertEqual(code, KERN_NO_ACCESS)
        }
    }
    
    func testDiscoverDevicesWithMissingVendorID() throws {
        // Given: Device with missing vendor ID
        mockIOKit.mockDevices = [TestUSBDeviceFixtures.deviceMissingVendorID]
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should skip the device and return empty array
        XCTAssertEqual(devices.count, 0)
        
        // Verify property access was attempted
        XCTAssertTrue(mockIOKit.registryEntryCreateCFPropertyCalls.contains { $0.1 == kUSBVendorID })
    }
    
    func testDiscoverDevicesWithMissingProductID() throws {
        // Given: Device with missing product ID
        mockIOKit.mockDevices = [TestUSBDeviceFixtures.deviceMissingProductID]
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should skip the device and return empty array
        XCTAssertEqual(devices.count, 0)
        
        // Verify property access was attempted
        XCTAssertTrue(mockIOKit.registryEntryCreateCFPropertyCalls.contains { $0.1 == kUSBProductID })
    }
    
    func testDiscoverDevicesWithInvalidVendorIDType() throws {
        // Given: Device with invalid vendor ID type
        mockIOKit.mockDevices = [TestUSBDeviceFixtures.deviceInvalidVendorIDType]
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should skip the device and return empty array
        XCTAssertEqual(devices.count, 0)
    }
    
    func testDiscoverDevicesWithMissingOptionalProperties() throws {
        // Given: Device with missing optional properties
        mockIOKit.mockDevices = [TestUSBDeviceFixtures.deviceMissingOptionalProperties]
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should still return the device with default values
        XCTAssertEqual(devices.count, 1)
        
        let device = devices.first!
        XCTAssertEqual(device.deviceClass, 0x00) // Default value
        XCTAssertEqual(device.deviceSubClass, 0x00) // Default value
        XCTAssertEqual(device.deviceProtocol, 0x00) // Default value
        XCTAssertEqual(device.speed, .unknown) // Default value
    }
    
    // MARK: - Device Lookup Tests
    
    func testGetDeviceWithValidIDs() throws {
        // Given: Mock devices with known IDs
        mockIOKit.mockDevices = TestUSBDeviceFixtures.standardDevices
        
        // When: Looking up a specific device
        let expectedDevice = TestUSBDeviceFixtures.expectedUSBDevice(from: TestUSBDeviceFixtures.appleMagicMouse)
        let device = try deviceDiscovery.getDevice(busID: expectedDevice.busID, deviceID: expectedDevice.deviceID)
        
        // Then: Should return the correct device
        XCTAssertNotNil(device)
        XCTAssertEqual(device?.busID, expectedDevice.busID)
        XCTAssertEqual(device?.deviceID, expectedDevice.deviceID)
        XCTAssertEqual(device?.vendorID, expectedDevice.vendorID)
        XCTAssertEqual(device?.productID, expectedDevice.productID)
    }
    
    func testGetDeviceWithInvalidIDs() throws {
        // Given: Mock devices
        mockIOKit.mockDevices = TestUSBDeviceFixtures.standardDevices
        
        // When: Looking up a non-existent device
        let device = try deviceDiscovery.getDevice(busID: "999", deviceID: "999")
        
        // Then: Should return nil
        XCTAssertNil(device)
    }
    
    func testGetDeviceWithEmptyIDs() throws {
        // Given: Mock devices
        mockIOKit.mockDevices = TestUSBDeviceFixtures.standardDevices
        
        // When: Looking up with empty IDs
        let device1 = try deviceDiscovery.getDevice(busID: "", deviceID: "1")
        let device2 = try deviceDiscovery.getDevice(busID: "1", deviceID: "")
        
        // Then: Should return nil for both
        XCTAssertNil(device1)
        XCTAssertNil(device2)
    }
    
    // MARK: - Notification System Tests
    
    func testStartNotificationsSuccess() throws {
        // Given: Mock setup for successful notifications
        mockIOKit.shouldFailNotificationPortCreate = false
        mockIOKit.shouldFailAddNotification = false
        
        // When: Starting notifications
        XCTAssertNoThrow(try deviceDiscovery.startNotifications())
        
        // Then: Should have made the correct IOKit calls
        XCTAssertEqual(mockIOKit.notificationPortCreateCalls.count, 1)
        XCTAssertEqual(mockIOKit.serviceAddMatchingNotificationCalls.count, 2) // Added and removed
        
        // Verify notification types
        let notificationTypes = mockIOKit.serviceAddMatchingNotificationCalls.map { $0.1 }
        XCTAssertTrue(notificationTypes.contains(kIOFirstMatchNotification))
        XCTAssertTrue(notificationTypes.contains(kIOTerminatedNotification))
    }
    
    func testStartNotificationsWithPortCreationFailure() {
        // Given: Notification port creation should fail
        mockIOKit.shouldFailNotificationPortCreate = true
        
        // When/Then: Should throw error
        XCTAssertThrowsError(try deviceDiscovery.startNotifications()) { error in
            guard case DeviceDiscoveryError.ioKitError(_, _) = error else {
                XCTFail("Expected ioKitError, got \(error)")
                return
            }
        }
    }
    
    func testStartNotificationsWithAddNotificationFailure() {
        // Given: Adding notification should fail
        mockIOKit.shouldFailNotificationPortCreate = false
        mockIOKit.shouldFailAddNotification = true
        mockIOKit.addNotificationError = KERN_NO_ACCESS
        
        // When/Then: Should throw error
        XCTAssertThrowsError(try deviceDiscovery.startNotifications()) { error in
            guard case DeviceDiscoveryError.ioKitError(let code, _) = error else {
                XCTFail("Expected ioKitError, got \(error)")
                return
            }
            XCTAssertEqual(code, KERN_NO_ACCESS)
        }
    }
    
    func testStopNotifications() throws {
        // Given: Notifications are started
        try deviceDiscovery.startNotifications()
        mockIOKit.reset() // Clear call history
        
        // When: Stopping notifications
        deviceDiscovery.stopNotifications()
        
        // Then: Should clean up properly (verified by no crashes)
        // The actual cleanup verification is done internally by the implementation
    }
    
    // MARK: - Edge Case Tests
    
    func testDiscoverDevicesWithLargeDeviceCollection() throws {
        // Given: Large collection of devices
        mockIOKit.mockDevices = TestUSBDeviceFixtures.largeDeviceCollection
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should handle all devices
        XCTAssertEqual(devices.count, TestUSBDeviceFixtures.largeDeviceCollection.count)
        
        // Verify performance is reasonable (should complete quickly)
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = try deviceDiscovery.discoverDevices()
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        
        XCTAssertLessThan(duration, 1.0, "Device discovery should complete within 1 second")
    }
    
    func testDiscoverDevicesWithSpecialCharacters() throws {
        // Given: Device with special characters
        mockIOKit.mockDevices = [TestUSBDeviceFixtures.deviceSpecialCharacters]
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should handle special characters properly
        XCTAssertEqual(devices.count, 1)
        
        let device = devices.first!
        XCTAssertEqual(device.manufacturerString, "Manufacturer™ & Co. (Special)")
        XCTAssertEqual(device.productString, "Product® with Ümlauts & Spëcial Chars")
        XCTAssertEqual(device.serialNumberString, "SN-123/456_789@ABC")
    }
    
    func testDiscoverDevicesWithZeroValues() throws {
        // Given: Device with zero values
        mockIOKit.mockDevices = [TestUSBDeviceFixtures.deviceZeroValues]
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should handle zero values properly
        XCTAssertEqual(devices.count, 1)
        
        let device = devices.first!
        XCTAssertEqual(device.vendorID, 0x0000)
        XCTAssertEqual(device.productID, 0x0000)
        XCTAssertEqual(device.deviceClass, 0x00)
        XCTAssertEqual(device.speed, .unknown)
    }
    
    func testDiscoverDevicesWithMaxValues() throws {
        // Given: Device with maximum values
        mockIOKit.mockDevices = [TestUSBDeviceFixtures.deviceMaxValues]
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should handle maximum values properly
        XCTAssertEqual(devices.count, 1)
        
        let device = devices.first!
        XCTAssertEqual(device.vendorID, 0xFFFF)
        XCTAssertEqual(device.productID, 0xFFFF)
        XCTAssertEqual(device.deviceClass, 0xFF)
        XCTAssertEqual(device.speed, .superSpeed)
    }
    
    // MARK: - Mock Verification Tests
    
    func testMockCallVerification() throws {
        // Given: Mock devices
        mockIOKit.mockDevices = TestUSBDeviceFixtures.standardDevices
        
        // When: Discovering devices
        _ = try deviceDiscovery.discoverDevices()
        
        // Then: Verify all expected IOKit calls were made
        XCTAssertEqual(mockIOKit.serviceMatchingCalls.count, 1)
        XCTAssertEqual(mockIOKit.serviceGetMatchingServicesCalls.count, 1)
        XCTAssertTrue(mockIOKit.iteratorNextCalls.count > 0)
        XCTAssertTrue(mockIOKit.objectReleaseCalls.count > 0)
        XCTAssertTrue(mockIOKit.registryEntryCreateCFPropertyCalls.count > 0)
        
        // Verify property access for each device
        let expectedPropertyCalls = TestUSBDeviceFixtures.standardDevices.count * 2 // At least VID and PID for each device
        XCTAssertGreaterThanOrEqual(mockIOKit.registryEntryCreateCFPropertyCalls.count, expectedPropertyCalls)
    }
    
    func testMockReset() throws {
        // Given: Mock with some state
        mockIOKit.mockDevices = TestUSBDeviceFixtures.standardDevices
        _ = try deviceDiscovery.discoverDevices()
        
        // Verify state exists
        XCTAssertGreaterThan(mockIOKit.serviceMatchingCalls.count, 0)
        
        // When: Resetting mock
        mockIOKit.reset()
        
        // Then: All state should be cleared
        XCTAssertEqual(mockIOKit.mockDevices.count, 0)
        XCTAssertEqual(mockIOKit.serviceMatchingCalls.count, 0)
        XCTAssertEqual(mockIOKit.serviceGetMatchingServicesCalls.count, 0)
        XCTAssertEqual(mockIOKit.iteratorNextCalls.count, 0)
        XCTAssertEqual(mockIOKit.objectReleaseCalls.count, 0)
        XCTAssertEqual(mockIOKit.registryEntryCreateCFPropertyCalls.count, 0)
        XCTAssertFalse(mockIOKit.shouldFailServiceMatching)
        XCTAssertFalse(mockIOKit.shouldFailGetMatchingServices)
    }
}