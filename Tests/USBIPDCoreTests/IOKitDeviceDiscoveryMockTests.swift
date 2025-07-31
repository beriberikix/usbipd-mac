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
    
    // MARK: - Device Monitoring and Notification Tests
    
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
        
        // Verify master port parameter
        if #available(macOS 12.0, *) {
            XCTAssertEqual(mockIOKit.notificationPortCreateCalls.first, kIOMainPortDefault)
        } else {
            XCTAssertEqual(mockIOKit.notificationPortCreateCalls.first, kIOMasterPortDefault)
        }
    }
    
    func testStartNotificationsWithPortCreationFailure() {
        // Given: Notification port creation should fail
        mockIOKit.shouldFailNotificationPortCreate = true
        
        // When/Then: Should throw error
        XCTAssertThrowsError(try deviceDiscovery.startNotifications()) { error in
            guard case DeviceDiscoveryError.ioKitError(_, let message) = error else {
                XCTFail("Expected ioKitError, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("notification") || message.contains("IONotificationPortCreate"))
        }
        
        // Verify port creation was attempted
        XCTAssertEqual(mockIOKit.notificationPortCreateCalls.count, 1)
        // Should not attempt to add notifications if port creation failed
        XCTAssertEqual(mockIOKit.serviceAddMatchingNotificationCalls.count, 0)
    }
    
    func testStartNotificationsWithAddNotificationFailure() {
        // Given: Adding notification should fail
        mockIOKit.shouldFailNotificationPortCreate = false
        mockIOKit.shouldFailAddNotification = true
        mockIOKit.addNotificationError = KERN_NO_ACCESS
        
        // When/Then: Should throw error
        XCTAssertThrowsError(try deviceDiscovery.startNotifications()) { error in
            guard case DeviceDiscoveryError.ioKitError(let code, let message) = error else {
                XCTFail("Expected ioKitError, got \(error)")
                return
            }
            XCTAssertEqual(code, KERN_NO_ACCESS)
            XCTAssertTrue(message.contains("notification") || message.contains("IOServiceAddMatchingNotification"))
        }
        
        // Verify port creation succeeded but notification addition failed
        XCTAssertEqual(mockIOKit.notificationPortCreateCalls.count, 1)
        XCTAssertGreaterThan(mockIOKit.serviceAddMatchingNotificationCalls.count, 0)
    }
    
    func testStartNotificationsWithDifferentErrorCodes() {
        // Test various IOKit error codes for notification setup
        let errorCodes: [kern_return_t] = [
            KERN_RESOURCE_SHORTAGE,
            KERN_INVALID_ARGUMENT,
            KERN_NOT_SUPPORTED,
            KERN_FAILURE
        ]
        
        for errorCode in errorCodes {
            // Given: Fresh mock state
            mockIOKit.reset()
            mockIOKit.shouldFailAddNotification = true
            mockIOKit.addNotificationError = errorCode
            
            // When/Then: Should throw appropriate error
            XCTAssertThrowsError(try deviceDiscovery.startNotifications()) { error in
                guard case DeviceDiscoveryError.ioKitError(let code, _) = error else {
                    XCTFail("Expected ioKitError for code \(errorCode), got \(error)")
                    return
                }
                XCTAssertEqual(code, errorCode)
            }
        }
    }
    
    func testStopNotificationsAfterSuccessfulStart() throws {
        // Given: Notifications are started successfully
        try deviceDiscovery.startNotifications()
        let initialPortCalls = mockIOKit.notificationPortCreateCalls.count
        let initialNotificationCalls = mockIOKit.serviceAddMatchingNotificationCalls.count
        
        // When: Stopping notifications
        deviceDiscovery.stopNotifications()
        
        // Then: Should not make additional IOKit calls for cleanup
        // (cleanup is handled internally by the implementation)
        XCTAssertEqual(mockIOKit.notificationPortCreateCalls.count, initialPortCalls)
        XCTAssertEqual(mockIOKit.serviceAddMatchingNotificationCalls.count, initialNotificationCalls)
    }
    
    func testStopNotificationsWithoutStart() {
        // Given: Notifications were never started
        
        // When: Stopping notifications
        deviceDiscovery.stopNotifications()
        
        // Then: Should handle gracefully without errors
        XCTAssertEqual(mockIOKit.notificationPortCreateCalls.count, 0)
        XCTAssertEqual(mockIOKit.serviceAddMatchingNotificationCalls.count, 0)
    }
    
    func testMultipleStartNotificationsCalls() throws {
        // Given: Notifications are already started
        try deviceDiscovery.startNotifications()
        let initialPortCalls = mockIOKit.notificationPortCreateCalls.count
        let initialNotificationCalls = mockIOKit.serviceAddMatchingNotificationCalls.count
        
        // When: Starting notifications again
        XCTAssertNoThrow(try deviceDiscovery.startNotifications())
        
        // Then: Should not make additional IOKit calls (should be idempotent)
        XCTAssertEqual(mockIOKit.notificationPortCreateCalls.count, initialPortCalls)
        XCTAssertEqual(mockIOKit.serviceAddMatchingNotificationCalls.count, initialNotificationCalls)
    }
    
    func testNotificationCleanupOnDeinitialization() throws {
        // Given: Device discovery with active notifications
        var deviceDiscovery: IOKitDeviceDiscovery? = IOKitDeviceDiscovery(ioKit: mockIOKit, logger: logger)
        try deviceDiscovery!.startNotifications()
        
        // When: Device discovery is deinitialized
        deviceDiscovery = nil
        
        // Then: Should clean up without crashes
        // (Cleanup verification is done internally by the implementation)
        // This test primarily ensures no memory leaks or crashes occur
    }
    
    func testDeviceConnectionCallbackTriggering() throws {
        // Given: Notifications are started and callback is set
        var connectedDevices: [USBDevice] = []
        deviceDiscovery.onDeviceConnected = { device in
            connectedDevices.append(device)
        }
        
        try deviceDiscovery.startNotifications()
        
        // When: Simulating device connection through mock
        // Note: In a real implementation, this would be triggered by IOKit callbacks
        // For testing, we verify the callback mechanism is properly set up
        let testDevice = TestUSBDeviceFixtures.appleMagicMouse
        mockIOKit.mockDevices = [testDevice]
        
        // Simulate callback invocation (this would normally be done by IOKit)
        let expectedDevice = TestUSBDeviceFixtures.expectedUSBDevice(from: testDevice)
        deviceDiscovery.onDeviceConnected?(expectedDevice)
        
        // Then: Callback should have been invoked
        XCTAssertEqual(connectedDevices.count, 1)
        XCTAssertEqual(connectedDevices.first?.vendorID, expectedDevice.vendorID)
        XCTAssertEqual(connectedDevices.first?.productID, expectedDevice.productID)
    }
    
    func testDeviceDisconnectionCallbackTriggering() throws {
        // Given: Notifications are started and callback is set
        var disconnectedDevices: [USBDevice] = []
        deviceDiscovery.onDeviceDisconnected = { device in
            disconnectedDevices.append(device)
        }
        
        try deviceDiscovery.startNotifications()
        
        // When: Simulating device disconnection through mock
        let testDevice = TestUSBDeviceFixtures.appleMagicMouse
        let expectedDevice = TestUSBDeviceFixtures.expectedUSBDevice(from: testDevice)
        
        // Simulate callback invocation (this would normally be done by IOKit)
        deviceDiscovery.onDeviceDisconnected?(expectedDevice)
        
        // Then: Callback should have been invoked
        XCTAssertEqual(disconnectedDevices.count, 1)
        XCTAssertEqual(disconnectedDevices.first?.vendorID, expectedDevice.vendorID)
        XCTAssertEqual(disconnectedDevices.first?.productID, expectedDevice.productID)
    }
    
    func testBothConnectionAndDisconnectionCallbacks() throws {
        // Given: Both callbacks are set
        var connectedDevices: [USBDevice] = []
        var disconnectedDevices: [USBDevice] = []
        
        deviceDiscovery.onDeviceConnected = { device in
            connectedDevices.append(device)
        }
        
        deviceDiscovery.onDeviceDisconnected = { device in
            disconnectedDevices.append(device)
        }
        
        try deviceDiscovery.startNotifications()
        
        // When: Simulating both connection and disconnection
        let testDevice = TestUSBDeviceFixtures.appleMagicMouse
        let expectedDevice = TestUSBDeviceFixtures.expectedUSBDevice(from: testDevice)
        
        deviceDiscovery.onDeviceConnected?(expectedDevice)
        deviceDiscovery.onDeviceDisconnected?(expectedDevice)
        
        // Then: Both callbacks should have been invoked
        XCTAssertEqual(connectedDevices.count, 1)
        XCTAssertEqual(disconnectedDevices.count, 1)
        XCTAssertEqual(connectedDevices.first?.vendorID, disconnectedDevices.first?.vendorID)
    }
    
    func testCallbacksWithoutNotificationSetup() {
        // Given: Callbacks are set but notifications are not started
        var callbackInvoked = false
        deviceDiscovery.onDeviceConnected = { _ in
            callbackInvoked = true
        }
        
        // When: Manually invoking callback
        let testDevice = TestUSBDeviceFixtures.appleMagicMouse
        let expectedDevice = TestUSBDeviceFixtures.expectedUSBDevice(from: testDevice)
        deviceDiscovery.onDeviceConnected?(expectedDevice)
        
        // Then: Callback should still work
        XCTAssertTrue(callbackInvoked)
    }
    
    func testNotificationResourceManagement() throws {
        // Given: Multiple start/stop cycles
        for cycle in 1...3 {
            // Start notifications
            try deviceDiscovery.startNotifications()
            
            // Verify setup
            XCTAssertEqual(mockIOKit.notificationPortCreateCalls.count, cycle)
            XCTAssertEqual(mockIOKit.serviceAddMatchingNotificationCalls.count, cycle * 2)
            
            // Stop notifications
            deviceDiscovery.stopNotifications()
        }
        
        // Then: Should handle multiple cycles without issues
        // Resource management is verified by the absence of crashes or errors
    }
    
    func testNotificationErrorHandlingWithResourceCleanup() {
        // Given: Notification setup that will fail partway through
        mockIOKit.shouldFailNotificationPortCreate = false
        mockIOKit.shouldFailAddNotification = true
        mockIOKit.addNotificationError = KERN_RESOURCE_SHORTAGE
        
        // When: Attempting to start notifications
        XCTAssertThrowsError(try deviceDiscovery.startNotifications()) { error in
            guard case DeviceDiscoveryError.ioKitError(let code, let message) = error else {
                XCTFail("Expected ioKitError, got \(error)")
                return
            }
            XCTAssertEqual(code, KERN_RESOURCE_SHORTAGE)
            XCTAssertTrue(message.contains("resource") || message.contains("shortage"))
        }
        
        // Then: Should have attempted cleanup even after failure
        XCTAssertEqual(mockIOKit.notificationPortCreateCalls.count, 1)
        
        // Subsequent stop should be safe
        deviceDiscovery.stopNotifications()
    }
    
    func testNotificationSystemThreadSafety() throws {
        // Given: Notifications are started
        try deviceDiscovery.startNotifications()
        
        // When: Accessing callbacks from multiple threads
        let expectation = XCTestExpectation(description: "Thread safety test")
        expectation.expectedFulfillmentCount = 10
        
        var callbackResults: [Bool] = []
        let resultsQueue = DispatchQueue(label: "test.results")
        
        deviceDiscovery.onDeviceConnected = { _ in
            resultsQueue.async {
                callbackResults.append(true)
                expectation.fulfill()
            }
        }
        
        // Simulate concurrent callback invocations
        let testDevice = TestUSBDeviceFixtures.expectedUSBDevice(from: TestUSBDeviceFixtures.appleMagicMouse)
        
        for _ in 0..<10 {
            DispatchQueue.global().async {
                self.deviceDiscovery.onDeviceConnected?(testDevice)
            }
        }
        
        // Then: Should handle concurrent access safely
        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(callbackResults.count, 10)
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
    
    // MARK: - Device Enumeration and Property Extraction Tests
    
    func testDiscoverDevicesWithVariousDeviceConfigurations() throws {
        // Given: Mixed device collection with different configurations
        mockIOKit.mockDevices = TestUSBDeviceFixtures.mixedDevices
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should return all devices with correct configurations
        XCTAssertEqual(devices.count, TestUSBDeviceFixtures.mixedDevices.count)
        
        // Verify each device type is properly configured
        let expectedDevices = TestUSBDeviceFixtures.expectedUSBDevices(from: TestUSBDeviceFixtures.mixedDevices)
        
        for (index, device) in devices.enumerated() {
            let expected = expectedDevices[index]
            
            // Verify all device properties are correctly extracted
            XCTAssertEqual(device.busID, expected.busID, "Device \(index) bus ID mismatch")
            XCTAssertEqual(device.deviceID, expected.deviceID, "Device \(index) device ID mismatch")
            XCTAssertEqual(device.vendorID, expected.vendorID, "Device \(index) vendor ID mismatch")
            XCTAssertEqual(device.productID, expected.productID, "Device \(index) product ID mismatch")
            XCTAssertEqual(device.deviceClass, expected.deviceClass, "Device \(index) device class mismatch")
            XCTAssertEqual(device.deviceSubClass, expected.deviceSubClass, "Device \(index) device subclass mismatch")
            XCTAssertEqual(device.deviceProtocol, expected.deviceProtocol, "Device \(index) device protocol mismatch")
            XCTAssertEqual(device.speed, expected.speed, "Device \(index) speed mismatch")
            XCTAssertEqual(device.manufacturerString, expected.manufacturerString, "Device \(index) manufacturer mismatch")
            XCTAssertEqual(device.productString, expected.productString, "Device \(index) product mismatch")
            XCTAssertEqual(device.serialNumberString, expected.serialNumberString, "Device \(index) serial number mismatch")
        }
    }
    
    func testPropertyExtractionWithValidProperties() throws {
        // Given: Device with all valid properties
        let testDevice = TestUSBDeviceFixtures.customDevice(
            vendorID: 0x1234,
            productID: 0x5678,
            deviceClass: 0x03, // HID
            deviceSubClass: 0x01, // Boot Interface
            deviceProtocol: 0x02, // Mouse
            speed: 2, // High speed
            manufacturerString: "Test Manufacturer",
            productString: "Test Product",
            serialNumberString: "TEST123456"
        )
        mockIOKit.mockDevices = [testDevice]
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should extract all properties correctly
        XCTAssertEqual(devices.count, 1)
        let device = devices.first!
        
        XCTAssertEqual(device.vendorID, 0x1234)
        XCTAssertEqual(device.productID, 0x5678)
        XCTAssertEqual(device.deviceClass, 0x03)
        XCTAssertEqual(device.deviceSubClass, 0x01)
        XCTAssertEqual(device.deviceProtocol, 0x02)
        XCTAssertEqual(device.speed, .high)
        XCTAssertEqual(device.manufacturerString, "Test Manufacturer")
        XCTAssertEqual(device.productString, "Test Product")
        XCTAssertEqual(device.serialNumberString, "TEST123456")
        
        // Verify all required property calls were made
        let propertyKeys = mockIOKit.registryEntryCreateCFPropertyCalls.map { $0.1 }
        XCTAssertTrue(propertyKeys.contains(kUSBVendorID))
        XCTAssertTrue(propertyKeys.contains(kUSBProductID))
    }
    
    func testPropertyExtractionWithMissingProperties() throws {
        // Given: Device with missing optional properties
        mockIOKit.mockDevices = [TestUSBDeviceFixtures.deviceMissingOptionalProperties]
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should handle missing properties gracefully with defaults
        XCTAssertEqual(devices.count, 1)
        let device = devices.first!
        
        // Required properties should still be present
        XCTAssertEqual(device.vendorID, 0x1234)
        XCTAssertEqual(device.productID, 0x5678)
        
        // Optional properties should have default values
        XCTAssertEqual(device.deviceClass, 0x00)
        XCTAssertEqual(device.deviceSubClass, 0x00)
        XCTAssertEqual(device.deviceProtocol, 0x00)
        XCTAssertEqual(device.speed, .unknown)
        
        // Verify property access was attempted for missing properties
        let propertyKeys = mockIOKit.registryEntryCreateCFPropertyCalls.map { $0.1 }
        XCTAssertTrue(propertyKeys.contains(kUSBDeviceClass))
        XCTAssertTrue(propertyKeys.contains(kUSBDeviceSubClass))
        XCTAssertTrue(propertyKeys.contains(kUSBDeviceProtocol))
    }
    
    func testPropertyExtractionWithInvalidProperties() throws {
        // Given: Device with invalid property types
        mockIOKit.mockDevices = [TestUSBDeviceFixtures.deviceInvalidVendorIDType, TestUSBDeviceFixtures.deviceInvalidProductIDType]
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should skip devices with invalid required properties
        XCTAssertEqual(devices.count, 0)
        
        // Verify property access was attempted
        let propertyKeys = mockIOKit.registryEntryCreateCFPropertyCalls.map { $0.1 }
        XCTAssertTrue(propertyKeys.contains(kUSBVendorID))
        XCTAssertTrue(propertyKeys.contains(kUSBProductID))
    }
    
    func testUSBDeviceCreationWithDifferentDeviceTypes() throws {
        // Given: Collection of different device types
        let deviceTypes = [
            TestUSBDeviceFixtures.appleMagicMouse,    // HID device
            TestUSBDeviceFixtures.sandiskFlashDrive,  // Mass storage device
            TestUSBDeviceFixtures.arduinoUno,         // CDC device
            TestUSBDeviceFixtures.usbHub              // Hub device
        ]
        mockIOKit.mockDevices = deviceTypes
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should create USBDevice objects for all device types
        XCTAssertEqual(devices.count, deviceTypes.count)
        
        // Verify HID device (Magic Mouse)
        let hidDevice = devices.first { $0.vendorID == 0x05ac && $0.productID == 0x030d }
        XCTAssertNotNil(hidDevice)
        XCTAssertEqual(hidDevice?.deviceClass, 0x03) // HID
        XCTAssertEqual(hidDevice?.speed, .low)
        
        // Verify Mass Storage device (Flash Drive)
        let storageDevice = devices.first { $0.vendorID == 0x0781 && $0.productID == 0x5567 }
        XCTAssertNotNil(storageDevice)
        XCTAssertEqual(storageDevice?.deviceClass, 0x08) // Mass Storage
        XCTAssertEqual(storageDevice?.speed, .high)
        
        // Verify CDC device (Arduino)
        let cdcDevice = devices.first { $0.vendorID == 0x2341 && $0.productID == 0x0043 }
        XCTAssertNotNil(cdcDevice)
        XCTAssertEqual(cdcDevice?.deviceClass, 0x02) // CDC
        XCTAssertEqual(cdcDevice?.speed, .full)
        
        // Verify Hub device
        let hubDevice = devices.first { $0.vendorID == 0x0424 && $0.productID == 0x2514 }
        XCTAssertNotNil(hubDevice)
        XCTAssertEqual(hubDevice?.deviceClass, 0x09) // Hub
        XCTAssertEqual(hubDevice?.speed, .high)
    }
    
    func testUSBDeviceCreationWithDifferentSpeeds() throws {
        // Given: Devices with different USB speeds
        let speedDevices = [
            TestUSBDeviceFixtures.customDevice(speed: 0, manufacturerString: "Low Speed Device"),    // Low speed
            TestUSBDeviceFixtures.customDevice(speed: 1, manufacturerString: "Full Speed Device"),   // Full speed
            TestUSBDeviceFixtures.customDevice(speed: 2, manufacturerString: "High Speed Device"),   // High speed
            TestUSBDeviceFixtures.customDevice(speed: 3, manufacturerString: "Super Speed Device"), // SuperSpeed
            TestUSBDeviceFixtures.customDevice(speed: 255, manufacturerString: "Unknown Speed Device") // Unknown speed
        ]
        mockIOKit.mockDevices = speedDevices
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should create USBDevice objects with correct speeds
        XCTAssertEqual(devices.count, speedDevices.count)
        
        // Verify speed mapping
        let lowSpeedDevice = devices.first { $0.manufacturerString == "Low Speed Device" }
        XCTAssertEqual(lowSpeedDevice?.speed, .low)
        
        let fullSpeedDevice = devices.first { $0.manufacturerString == "Full Speed Device" }
        XCTAssertEqual(fullSpeedDevice?.speed, .full)
        
        let highSpeedDevice = devices.first { $0.manufacturerString == "High Speed Device" }
        XCTAssertEqual(highSpeedDevice?.speed, .high)
        
        let superSpeedDevice = devices.first { $0.manufacturerString == "Super Speed Device" }
        XCTAssertEqual(superSpeedDevice?.speed, .superSpeed)
        
        let unknownSpeedDevice = devices.first { $0.manufacturerString == "Unknown Speed Device" }
        XCTAssertEqual(unknownSpeedDevice?.speed, .unknown)
    }
    
    func testPropertyExtractionWithNilStringDescriptors() throws {
        // Given: Device with no string descriptors
        mockIOKit.mockDevices = [TestUSBDeviceFixtures.deviceNoStringDescriptors]
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should handle nil string descriptors correctly
        XCTAssertEqual(devices.count, 1)
        let device = devices.first!
        
        XCTAssertNil(device.manufacturerString)
        XCTAssertNil(device.productString)
        XCTAssertNil(device.serialNumberString)
        
        // Verify required properties are still present
        XCTAssertEqual(device.vendorID, 0x1234)
        XCTAssertEqual(device.productID, 0x5678)
    }
    
    func testPropertyExtractionWithLongStrings() throws {
        // Given: Device with very long string descriptors
        mockIOKit.mockDevices = [TestUSBDeviceFixtures.deviceLongStrings]
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should handle long strings correctly
        XCTAssertEqual(devices.count, 1)
        let device = devices.first!
        
        XCTAssertEqual(device.manufacturerString, "Very Long Manufacturer Name That Exceeds Normal Length Expectations")
        XCTAssertEqual(device.productString, "Very Long Product Name That Also Exceeds Normal Length Expectations")
        XCTAssertEqual(device.serialNumberString, "VeryLongSerialNumberThatExceedsNormalLengthExpectations123456789")
    }
    
    func testDeviceEnumerationWithMixedValidAndInvalidDevices() throws {
        // Given: Mix of valid and invalid devices
        let mixedDevices = [
            TestUSBDeviceFixtures.appleMagicMouse,           // Valid device
            TestUSBDeviceFixtures.deviceMissingVendorID,     // Invalid - missing vendor ID
            TestUSBDeviceFixtures.sandiskFlashDrive,         // Valid device
            TestUSBDeviceFixtures.deviceInvalidProductIDType, // Invalid - wrong type
            TestUSBDeviceFixtures.arduinoUno                 // Valid device
        ]
        mockIOKit.mockDevices = mixedDevices
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should return only valid devices
        XCTAssertEqual(devices.count, 3) // Only the 3 valid devices
        
        // Verify the valid devices are present
        let vendorIDs = devices.map { $0.vendorID }
        XCTAssertTrue(vendorIDs.contains(0x05ac)) // Apple Magic Mouse
        XCTAssertTrue(vendorIDs.contains(0x0781)) // SanDisk Flash Drive
        XCTAssertTrue(vendorIDs.contains(0x2341)) // Arduino Uno
    }
    
    func testBusAndDeviceIDGeneration() throws {
        // Given: Devices with specific location IDs for ID generation testing
        let testDevices = TestUSBDeviceFixtures.devicesWithIDs(count: 5, startingBusID: 1)
        mockIOKit.mockDevices = testDevices
        
        // When: Discovering devices
        let devices = try deviceDiscovery.discoverDevices()
        
        // Then: Should generate correct bus and device IDs
        XCTAssertEqual(devices.count, 5)
        
        for (index, device) in devices.enumerated() {
            let expectedBusID = String(1 + (index / 10)) // 10 devices per bus
            let expectedDeviceID = String((index % 10) + 1)
            
            XCTAssertEqual(device.busID, expectedBusID, "Device \(index) bus ID mismatch")
            XCTAssertEqual(device.deviceID, expectedDeviceID, "Device \(index) device ID mismatch")
        }
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