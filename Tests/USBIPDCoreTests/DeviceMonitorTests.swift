// DeviceMonitorTests.swift
// Tests for USB device monitoring

import XCTest
@testable import USBIPDCore

final class DeviceMonitorTests: XCTestCase {
    
    // MARK: - Mock Classes
    
    class MockDeviceDiscovery: DeviceDiscovery {
        var devices: [USBDevice] = []
        var onDeviceConnected: ((USBDevice) -> Void)?
        var onDeviceDisconnected: ((USBDevice) -> Void)?
        var notificationsStarted = false
        var notificationsStopped = false
        
        func discoverDevices() throws -> [USBDevice] {
            return devices
        }
        
        func getDevice(busID: String, deviceID: String) throws -> USBDevice? {
            return devices.first { $0.busID == busID && $0.deviceID == deviceID }
        }
        
        func startNotifications() throws {
            notificationsStarted = true
        }
        
        func stopNotifications() {
            notificationsStopped = true
        }
        
        func simulateDeviceConnected(_ device: USBDevice) {
            devices.append(device)
            onDeviceConnected?(device)
        }
        
        func simulateDeviceDisconnected(_ device: USBDevice) {
            devices.removeAll { $0.busID == device.busID && $0.deviceID == device.deviceID }
            onDeviceDisconnected?(device)
        }
    }
    
    // MARK: - Test Properties
    
    var mockDiscovery: MockDeviceDiscovery!
    var monitor: DeviceMonitor!
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        mockDiscovery = MockDeviceDiscovery()
        monitor = DeviceMonitor(deviceDiscovery: mockDiscovery)
    }
    
    override func tearDown() {
        monitor.stopMonitoring()
        monitor = nil
        mockDiscovery = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    func createTestDevice(busID: String = "1", deviceID: String = "2") -> USBDevice {
        return USBDevice(
            busID: busID,
            deviceID: deviceID,
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
    }
    
    // MARK: - Tests
    
    func testStartMonitoring() throws {
        // Prepare test devices
        let device1 = createTestDevice(busID: "1", deviceID: "1")
        let device2 = createTestDevice(busID: "1", deviceID: "2")
        mockDiscovery.devices = [device1, device2]
        
        // Start monitoring
        try monitor.startMonitoring()
        
        // Verify monitoring started
        XCTAssertTrue(monitor.isActive())
        XCTAssertTrue(mockDiscovery.notificationsStarted)
        
        // Verify known devices were loaded
        let knownDevices = monitor.getKnownDevices()
        XCTAssertEqual(knownDevices.count, 2)
        XCTAssertTrue(knownDevices.contains { $0.busID == "1" && $0.deviceID == "1" })
        XCTAssertTrue(knownDevices.contains { $0.busID == "1" && $0.deviceID == "2" })
    }
    
    func testStopMonitoring() throws {
        // Start monitoring
        try monitor.startMonitoring()
        XCTAssertTrue(monitor.isActive())
        
        // Stop monitoring
        monitor.stopMonitoring()
        
        // Verify monitoring stopped
        XCTAssertFalse(monitor.isActive())
        XCTAssertTrue(mockDiscovery.notificationsStopped)
        XCTAssertEqual(monitor.getKnownDevices().count, 0)
    }
    
    func testDeviceConnectedEvent() throws {
        // Set up event capture
        var capturedEvents: [DeviceMonitor.DeviceEvent] = []
        monitor.onDeviceEvent = { event in
            capturedEvents.append(event)
        }
        
        // Start monitoring with empty device list
        try monitor.startMonitoring()
        
        // Simulate device connection
        let device = createTestDevice()
        mockDiscovery.simulateDeviceConnected(device)
        
        // Verify event was captured
        XCTAssertEqual(capturedEvents.count, 1)
        XCTAssertEqual(capturedEvents[0].type, .connected)
        XCTAssertEqual(capturedEvents[0].device?.busID, "1")
        XCTAssertEqual(capturedEvents[0].device?.deviceID, "2")
        
        // Verify device is in known devices
        let knownDevices = monitor.getKnownDevices()
        XCTAssertEqual(knownDevices.count, 1)
        XCTAssertEqual(knownDevices[0].busID, "1")
        XCTAssertEqual(knownDevices[0].deviceID, "2")
    }
    
    func testDeviceDisconnectedEvent() throws {
        // Prepare test device
        let device = createTestDevice()
        mockDiscovery.devices = [device]
        
        // Set up event capture
        var capturedEvents: [DeviceMonitor.DeviceEvent] = []
        monitor.onDeviceEvent = { event in
            capturedEvents.append(event)
        }
        
        // Start monitoring with the device
        try monitor.startMonitoring()
        XCTAssertEqual(monitor.getKnownDevices().count, 1)
        
        // Simulate device disconnection
        mockDiscovery.simulateDeviceDisconnected(device)
        
        // Verify event was captured
        XCTAssertEqual(capturedEvents.count, 1)
        XCTAssertEqual(capturedEvents[0].type, .disconnected)
        XCTAssertEqual(capturedEvents[0].device?.busID, "1")
        XCTAssertEqual(capturedEvents[0].device?.deviceID, "2")
        
        // Verify device is removed from known devices
        XCTAssertEqual(monitor.getKnownDevices().count, 0)
    }
    
    func testMultipleDeviceEvents() throws {
        // Set up event capture
        var capturedEvents: [DeviceMonitor.DeviceEvent] = []
        monitor.onDeviceEvent = { event in
            capturedEvents.append(event)
        }
        
        // Start monitoring with empty device list
        try monitor.startMonitoring()
        
        // Simulate multiple device connections
        let device1 = createTestDevice(busID: "1", deviceID: "1")
        let device2 = createTestDevice(busID: "1", deviceID: "2")
        let device3 = createTestDevice(busID: "2", deviceID: "1")
        
        mockDiscovery.simulateDeviceConnected(device1)
        mockDiscovery.simulateDeviceConnected(device2)
        mockDiscovery.simulateDeviceConnected(device3)
        
        // Verify events were captured
        XCTAssertEqual(capturedEvents.count, 3)
        XCTAssertEqual(monitor.getKnownDevices().count, 3)
        
        // Simulate device disconnections
        mockDiscovery.simulateDeviceDisconnected(device1)
        mockDiscovery.simulateDeviceDisconnected(device3)
        
        // Verify events were captured
        XCTAssertEqual(capturedEvents.count, 5)
        XCTAssertEqual(monitor.getKnownDevices().count, 1)
        XCTAssertEqual(monitor.getKnownDevices()[0].busID, "1")
        XCTAssertEqual(monitor.getKnownDevices()[0].deviceID, "2")
    }
    
    func testStartMonitoringMultipleTimes() throws {
        // Start monitoring
        try monitor.startMonitoring()
        XCTAssertTrue(monitor.isActive())
        
        // Try to start again - should be safe
        try monitor.startMonitoring()
        XCTAssertTrue(monitor.isActive())
    }
    
    func testStopMonitoringMultipleTimes() throws {
        // Start monitoring
        try monitor.startMonitoring()
        XCTAssertTrue(monitor.isActive())
        
        // Stop monitoring
        monitor.stopMonitoring()
        XCTAssertFalse(monitor.isActive())
        
        // Try to stop again - should be safe
        monitor.stopMonitoring()
        XCTAssertFalse(monitor.isActive())
    }
}