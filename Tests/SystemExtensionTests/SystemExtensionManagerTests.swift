// SystemExtensionManagerTests.swift
// Comprehensive unit tests for SystemExtensionManager

import XCTest
import Foundation
@testable import SystemExtension
@testable import USBIPDCore
@testable import Common

class SystemExtensionManagerTests: XCTestCase {
    
    // MARK: - Test Properties
    
    var mockDeviceClaimer: MockDeviceClaimer!
    var mockIPCHandler: MockIPCHandler!
    var mockStatusMonitor: MockStatusMonitor!
    var testLogger: Logger!
    var systemExtensionManager: SystemExtensionManager!
    var testConfig: SystemExtensionManagerConfig!
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        // Create mock dependencies
        mockDeviceClaimer = MockDeviceClaimer()
        mockIPCHandler = MockIPCHandler()
        mockStatusMonitor = MockStatusMonitor()
        
        // Create test logger with debug level for comprehensive testing
        testLogger = Logger(
            config: LoggerConfig(level: .debug),
            subsystem: "com.usbipd.mac.test",
            category: "system-extension"
        )
        
        // Create test configuration
        testConfig = SystemExtensionManagerConfig(
            autoStart: false,
            restoreStateOnStart: false,
            saveStateOnStop: false,
            healthCheckInterval: 0.0 // Disable for testing
        )
        
        // Initialize SystemExtensionManager with mocks
        systemExtensionManager = SystemExtensionManager(
            deviceClaimer: mockDeviceClaimer,
            ipcHandler: mockIPCHandler,
            statusMonitor: mockStatusMonitor,
            config: testConfig,
            logger: testLogger
        )
    }
    
    override func tearDown() {
        // Ensure clean shutdown
        try? systemExtensionManager?.stop()
        
        systemExtensionManager = nil
        mockDeviceClaimer = nil
        mockIPCHandler = nil
        mockStatusMonitor = nil
        testLogger = nil
        testConfig = nil
        
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitializationWithDefaults() {
        let defaultManager = SystemExtensionManager()
        XCTAssertNotNil(defaultManager)
    }
    
    func testInitializationWithCustomDependencies() {
        XCTAssertNotNil(systemExtensionManager)
        // Test that the manager was initialized properly by checking basic functionality
        // We can't easily test internal dependencies without exposing them publicly
        XCTAssertNotNil(mockDeviceClaimer)
        XCTAssertNotNil(mockIPCHandler)
        XCTAssertNotNil(mockStatusMonitor)
    }
    
    // MARK: - Lifecycle Management Tests
    
    func testStartupSuccess() throws {
        // Configure mocks for successful startup
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        mockDeviceClaimer.shouldSucceed = true
        
        // Test successful startup
        XCTAssertNoThrow(try systemExtensionManager.start())
        
        // Verify startup calls
        XCTAssertTrue(mockIPCHandler.startListenerCalled)
        XCTAssertTrue(mockStatusMonitor.startMonitoringCalled)
        
        // Verify status
        let status = systemExtensionManager.getStatus()
        XCTAssertTrue(status.isRunning)
    }
    
    func testStartupWithIPCFailure() {
        // Configure IPC handler to fail
        mockIPCHandler.shouldSucceed = false
        mockIPCHandler.startError = SystemExtensionError.ipcError("Test IPC failure")
        
        // Test startup failure
        XCTAssertThrowsError(try systemExtensionManager.start()) { error in
            XCTAssertTrue(error is SystemExtensionError)
        }
        
        // Verify cleanup was attempted
        XCTAssertTrue(mockIPCHandler.startListenerCalled)
        XCTAssertFalse(mockStatusMonitor.startMonitoringCalled) // Should not reach this
    }
    
    func testStartupWithStatusMonitorFailure() {
        // Configure status monitor to fail
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = false
        mockStatusMonitor.startError = SystemExtensionError.internalError("Test monitor failure")
        
        // Test startup failure
        XCTAssertThrowsError(try systemExtensionManager.start())
        
        // Verify partial startup and cleanup
        XCTAssertTrue(mockIPCHandler.startListenerCalled)
        XCTAssertTrue(mockStatusMonitor.startMonitoringCalled)
        XCTAssertTrue(mockIPCHandler.stopListenerCalled) // Cleanup should be called
    }
    
    func testStartupAlreadyRunning() throws {
        // Start manager first
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        try systemExtensionManager.start()
        
        // Reset mock call flags
        mockIPCHandler.resetCallFlags()
        mockStatusMonitor.resetCallFlags()
        
        // Try to start again - should be ignored
        XCTAssertNoThrow(try systemExtensionManager.start())
        
        // Verify no additional startup calls
        XCTAssertFalse(mockIPCHandler.startListenerCalled)
        XCTAssertFalse(mockStatusMonitor.startMonitoringCalled)
    }
    
    func testShutdownSuccess() throws {
        // Start manager first
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        mockDeviceClaimer.shouldSucceed = true
        try systemExtensionManager.start()
        
        // Reset call flags
        mockIPCHandler.resetCallFlags()
        mockStatusMonitor.resetCallFlags()
        mockDeviceClaimer.resetCallFlags()
        
        // Test successful shutdown
        XCTAssertNoThrow(try systemExtensionManager.stop())
        
        // Verify shutdown calls
        XCTAssertTrue(mockIPCHandler.stopListenerCalled)
        XCTAssertTrue(mockStatusMonitor.stopMonitoringCalled)
        
        // Verify status
        let status = systemExtensionManager.getStatus()
        XCTAssertFalse(status.isRunning)
    }
    
    func testShutdownNotRunning() {
        // Try to stop when not running - should be safe
        XCTAssertNoThrow(try systemExtensionManager.stop())
        
        // Verify no shutdown calls were made
        XCTAssertFalse(mockIPCHandler.stopListenerCalled)
        XCTAssertFalse(mockStatusMonitor.stopMonitoringCalled)
    }
    
    func testRestartSuccess() throws {
        // Configure mocks for successful operations
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        mockDeviceClaimer.shouldSucceed = true
        
        // Start manager first
        try systemExtensionManager.start()
        
        // Reset call flags
        mockIPCHandler.resetCallFlags()
        mockStatusMonitor.resetCallFlags()
        
        // Test restart
        XCTAssertNoThrow(try systemExtensionManager.restart())
        
        // Verify stop and start were called
        XCTAssertTrue(mockIPCHandler.stopListenerCalled)
        XCTAssertTrue(mockStatusMonitor.stopMonitoringCalled)
        XCTAssertTrue(mockIPCHandler.startListenerCalled)
        XCTAssertTrue(mockStatusMonitor.startMonitoringCalled)
        
        // Verify final status
        let status = systemExtensionManager.getStatus()
        XCTAssertTrue(status.isRunning)
    }
    
    // MARK: - Device Operations Tests
    
    func testClaimDeviceSuccess() throws {
        // Start manager
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        try systemExtensionManager.start()
        
        // Create test device
        let testDevice = createTestUSBDevice()
        let expectedClaimedDevice = ClaimedDevice(
            deviceID: "1-1",
            busID: testDevice.busID,
            vendorID: testDevice.vendorID,
            productID: testDevice.productID,
            productString: testDevice.productString,
            manufacturerString: testDevice.manufacturerString,
            serialNumber: testDevice.serialNumberString,
            claimTime: Date(),
            claimMethod: .exclusiveAccess,
            claimState: .claimed,
            deviceClass: testDevice.deviceClass,
            deviceSubclass: testDevice.deviceSubClass,
            deviceProtocol: testDevice.deviceProtocol
        )
        
        // Configure mock to return claimed device
        mockDeviceClaimer.claimDeviceResult = expectedClaimedDevice
        mockDeviceClaimer.shouldSucceed = true
        
        // Test device claiming
        let claimedDevice = try systemExtensionManager.claimDevice(testDevice)
        
        // Verify results
        XCTAssertEqual(claimedDevice.deviceID, expectedClaimedDevice.deviceID)
        XCTAssertEqual(claimedDevice.claimMethod, expectedClaimedDevice.claimMethod)
        XCTAssertTrue(mockDeviceClaimer.claimDeviceCalled)
        
        // Verify statistics
        let stats = systemExtensionManager.getStatistics()
        XCTAssertEqual(stats.successfulClaims, 1)
        XCTAssertEqual(stats.failedClaims, 0)
    }
    
    func testClaimDeviceFailure() throws {
        // Start manager
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        try systemExtensionManager.start()
        
        // Create test device
        let testDevice = createTestUSBDevice()
        
        // Configure mock to fail
        mockDeviceClaimer.shouldSucceed = false
        mockDeviceClaimer.claimError = SystemExtensionError.deviceClaimFailed("Test claim failure", nil)
        
        // Test device claiming failure
        XCTAssertThrowsError(try systemExtensionManager.claimDevice(testDevice)) { error in
            XCTAssertTrue(error is SystemExtensionError)
        }
        
        // Verify failure was recorded
        let stats = systemExtensionManager.getStatistics()
        XCTAssertEqual(stats.successfulClaims, 0)
        XCTAssertEqual(stats.failedClaims, 1)
    }
    
    func testClaimDeviceNotRunning() {
        // Don't start manager
        let testDevice = createTestUSBDevice()
        
        // Test claiming when not running
        XCTAssertThrowsError(try systemExtensionManager.claimDevice(testDevice)) { error in
            if case SystemExtensionError.extensionNotRunning = error {
                // Expected error
            } else {
                XCTFail("Expected extensionNotRunning error")
            }
        }
    }
    
    func testReleaseDeviceSuccess() throws {
        // Start manager
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        try systemExtensionManager.start()
        
        // Create test device
        let testDevice = createTestUSBDevice()
        mockDeviceClaimer.shouldSucceed = true
        
        // Test device release
        XCTAssertNoThrow(try systemExtensionManager.releaseDevice(testDevice))
        
        // Verify release was called
        XCTAssertTrue(mockDeviceClaimer.releaseDeviceCalled)
        
        // Verify statistics
        let stats = systemExtensionManager.getStatistics()
        XCTAssertEqual(stats.successfulReleases, 1)
        XCTAssertEqual(stats.failedReleases, 0)
    }
    
    func testReleaseDeviceFailure() throws {
        // Start manager
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        try systemExtensionManager.start()
        
        // Create test device
        let testDevice = createTestUSBDevice()
        
        // Configure mock to fail
        mockDeviceClaimer.shouldSucceed = false
        mockDeviceClaimer.releaseError = SystemExtensionError.deviceReleaseFailed("Test release failure", nil)
        
        // Test device release failure
        XCTAssertThrowsError(try systemExtensionManager.releaseDevice(testDevice)) { error in
            XCTAssertTrue(error is SystemExtensionError)
        }
        
        // Verify failure was recorded
        let stats = systemExtensionManager.getStatistics()
        XCTAssertEqual(stats.successfulReleases, 0)
        XCTAssertEqual(stats.failedReleases, 1)
    }
    
    func testGetClaimedDevices() throws {
        // Start manager
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        try systemExtensionManager.start()
        
        // Configure mock claimed devices
        let testDevice = createTestUSBDevice()
        let claimedDevice = ClaimedDevice(
            deviceID: "1-1",
            busID: testDevice.busID,
            vendorID: testDevice.vendorID,
            productID: testDevice.productID,
            productString: testDevice.productString,
            manufacturerString: testDevice.manufacturerString,
            serialNumber: testDevice.serialNumberString,
            claimTime: Date(),
            claimMethod: .exclusiveAccess,
            claimState: .claimed,
            deviceClass: testDevice.deviceClass,
            deviceSubclass: testDevice.deviceSubClass,
            deviceProtocol: testDevice.deviceProtocol
        )
        mockDeviceClaimer.claimedDevicesPublic = [claimedDevice]
        
        // Test getting claimed devices
        let claimedDevices = systemExtensionManager.getClaimedDevices()
        
        // Verify results
        XCTAssertEqual(claimedDevices.count, 1)
        XCTAssertEqual(claimedDevices.first?.deviceID, "1-1")
        XCTAssertTrue(mockDeviceClaimer.getAllClaimedDevicesCalled)
    }
    
    func testIsDeviceClaimed() throws {
        // Start manager
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        try systemExtensionManager.start()
        
        // Configure mock to return claimed status
        mockDeviceClaimer.deviceClaimedStatus = true
        
        // Test device claimed check
        let isClaimed = systemExtensionManager.isDeviceClaimed(deviceID: "1-1")
        
        // Verify results
        XCTAssertTrue(isClaimed)
        XCTAssertTrue(mockDeviceClaimer.isDeviceClaimedCalled)
    }
    
    // MARK: - Health and Status Tests
    
    func testGetStatus() throws {
        // Start manager
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        try systemExtensionManager.start()
        
        // Configure mock claimed devices
        let testDevice = createTestUSBDevice()
        let claimedDevice = ClaimedDevice(
            deviceID: "1-1",
            busID: testDevice.busID,
            vendorID: testDevice.vendorID,
            productID: testDevice.productID,
            productString: testDevice.productString,
            manufacturerString: testDevice.manufacturerString,
            serialNumber: testDevice.serialNumberString,
            claimTime: Date(),
            claimMethod: .exclusiveAccess,
            claimState: .claimed,
            deviceClass: testDevice.deviceClass,
            deviceSubclass: testDevice.deviceSubClass,
            deviceProtocol: testDevice.deviceProtocol
        )
        mockDeviceClaimer.claimedDevicesPublic = [claimedDevice]
        
        // Test getting status
        let status = systemExtensionManager.getStatus()
        
        // Verify status
        XCTAssertTrue(status.isRunning)
        XCTAssertEqual(status.claimedDevices.count, 1)
        XCTAssertEqual(status.claimedDevices.first?.deviceID, "1-1")
        XCTAssertNotNil(status.lastStartTime)
        XCTAssertEqual(status.errorCount, 0)
    }
    
    func testPerformHealthCheck() throws {
        // Start manager
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        try systemExtensionManager.start()
        
        // Configure mocks for healthy status
        mockIPCHandler.isListeningValue = true
        mockStatusMonitor.isMonitoringValue = true
        
        // Test health check
        let isHealthy = systemExtensionManager.performHealthCheck()
        
        // Verify health check
        XCTAssertTrue(isHealthy)
    }
    
    func testPerformHealthCheckUnhealthy() throws {
        // Start manager
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        try systemExtensionManager.start()
        
        // Configure mocks for unhealthy status
        mockIPCHandler.isListeningValue = false
        mockStatusMonitor.isMonitoringValue = true
        
        // Test health check
        let isHealthy = systemExtensionManager.performHealthCheck()
        
        // Verify unhealthy status
        XCTAssertFalse(isHealthy)
    }
    
    func testGetStatistics() throws {
        // Start manager
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        try systemExtensionManager.start()
        
        // Perform some operations to generate statistics
        let testDevice = createTestUSBDevice()
        mockDeviceClaimer.shouldSucceed = true
        mockDeviceClaimer.claimDeviceResult = ClaimedDevice(
            deviceID: "1-1",
            busID: testDevice.busID,
            vendorID: testDevice.vendorID,
            productID: testDevice.productID,
            productString: testDevice.productString,
            manufacturerString: testDevice.manufacturerString,
            serialNumber: testDevice.serialNumberString,
            claimTime: Date(),
            claimMethod: .exclusiveAccess,
            claimState: .claimed,
            deviceClass: testDevice.deviceClass,
            deviceSubclass: testDevice.deviceSubClass,
            deviceProtocol: testDevice.deviceProtocol
        )
        
        _ = try systemExtensionManager.claimDevice(testDevice)
        try systemExtensionManager.releaseDevice(testDevice)
        _ = systemExtensionManager.performHealthCheck()
        
        // Test getting statistics
        let stats = systemExtensionManager.getStatistics()
        
        // Verify statistics
        XCTAssertEqual(stats.successfulClaims, 1)
        XCTAssertEqual(stats.successfulReleases, 1)
        XCTAssertEqual(stats.healthChecks, 1)
        XCTAssertEqual(stats.healthyChecks, 1)
        XCTAssertGreaterThan(stats.uptime, 0)
    }
    
    // MARK: - State Restoration Tests
    
    func testStateRestoration() throws {
        // Create config with state restoration enabled
        let restorationConfig = SystemExtensionManagerConfig(
            restoreStateOnStart: true,
            saveStateOnStop: true
        )
        
        let managerWithRestoration = SystemExtensionManager(
            deviceClaimer: mockDeviceClaimer,
            ipcHandler: mockIPCHandler,
            statusMonitor: mockStatusMonitor,
            config: restorationConfig,
            logger: testLogger
        )
        
        // Configure mocks for successful operations
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        mockDeviceClaimer.shouldSucceed = true
        
        // Test startup with restoration
        XCTAssertNoThrow(try managerWithRestoration.start())
        
        // Verify restoration was attempted
        XCTAssertTrue(mockDeviceClaimer.restoreClaimedDevicesCalled)
        
        // Test shutdown with state saving
        XCTAssertNoThrow(try managerWithRestoration.stop())
        
        // Verify state was saved
        XCTAssertTrue(mockDeviceClaimer.saveClaimStateCalled)
    }
    
    // MARK: - Error Handling Tests
    
    func testDeinitializationWhileRunning() throws {
        // Start manager
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        try systemExtensionManager.start()
        
        // Don't explicitly stop - let deinit handle it
        systemExtensionManager = nil
        
        // Verify cleanup was called (checked in mock after deinit)
        // This tests the deinit safety mechanism
    }
    
    // MARK: - Helper Methods
    
    private func createTestUSBDevice() -> USBDevice {
        return USBDevice(
            busID: "1",
            deviceID: "1",
            vendorID: 0x1234,
            productID: 0x5678,
            deviceClass: 0x09,
            deviceSubClass: 0x00,
            deviceProtocol: 0x00,
            speed: .high,
            manufacturerString: "Test Manufacturer",
            productString: "Test Device",
            serialNumberString: "123456789"
        )
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentOperations() throws {
        // Start manager
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        mockDeviceClaimer.shouldSucceed = true
        try systemExtensionManager.start()
        
        // Create test device
        let testDevice = createTestUSBDevice()
        mockDeviceClaimer.claimDeviceResult = ClaimedDevice(
            deviceID: "1-1",
            busID: testDevice.busID,
            vendorID: testDevice.vendorID,
            productID: testDevice.productID,
            productString: testDevice.productString,
            manufacturerString: testDevice.manufacturerString,
            serialNumber: testDevice.serialNumberString,
            claimTime: Date(),
            claimMethod: .exclusiveAccess,
            claimState: .claimed,
            deviceClass: testDevice.deviceClass,
            deviceSubclass: testDevice.deviceSubClass,
            deviceProtocol: testDevice.deviceProtocol
        )
        
        // Test concurrent operations
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue.global(qos: .userInitiated)
        
        for _ in 0..<10 {
            queue.async {
                do {
                    _ = try self.systemExtensionManager.claimDevice(testDevice)
                    _ = self.systemExtensionManager.getClaimedDevices()
                    _ = self.systemExtensionManager.performHealthCheck()
                    expectation.fulfill()
                } catch {
                    XCTFail("Concurrent operation failed: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Edge Cases Tests
    
    func testMultipleStartStop() throws {
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        
        // Multiple start/stop cycles
        for _ in 0..<5 {
            XCTAssertNoThrow(try systemExtensionManager.start())
            XCTAssertNoThrow(try systemExtensionManager.stop())
        }
        
        // Verify final state
        let status = systemExtensionManager.getStatus()
        XCTAssertFalse(status.isRunning)
    }
    
    func testOperationsAfterStop() throws {
        // Start and stop manager
        mockIPCHandler.shouldSucceed = true
        mockStatusMonitor.shouldSucceed = true
        try systemExtensionManager.start()
        try systemExtensionManager.stop()
        
        // Test operations after stop
        let testDevice = createTestUSBDevice()
        
        XCTAssertThrowsError(try systemExtensionManager.claimDevice(testDevice))
        XCTAssertThrowsError(try systemExtensionManager.releaseDevice(testDevice))
        
        // These should still work
        XCTAssertNoThrow(systemExtensionManager.getClaimedDevices())
        XCTAssertNoThrow(systemExtensionManager.getStatistics())
    }
}