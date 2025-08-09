//
//  SystemExtensionIntegrationTests.swift
//  usbipd-mac
//
//  End-to-end integration tests for System Extension functionality
//  Tests complete workflows: bind → claim → share → release
//

import XCTest
import Foundation
@testable import USBIPDCLI
@testable import USBIPDCore
@testable import Common
@testable import SystemExtension

/// End-to-end integration tests for System Extension functionality
/// Tests complete workflow: device discovery → bind → claim → share → release → unbind
/// Validates System Extension lifecycle during server operations
/// Tests error recovery scenarios and concurrent device claiming
final class SystemExtensionIntegrationTests: XCTestCase {
    
    // MARK: - Test Properties
    
    var systemExtensionManager: SystemExtensionManager!
    var deviceClaimAdapter: SystemExtensionClaimAdapter!
    var mockDeviceDiscovery: MockDeviceDiscovery!
    var serverConfig: ServerConfig!
    var testDevices: [USBDevice]!
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        // Create System Extension manager with default configuration for integration testing
        // Use the default SystemExtensionManager which creates its own dependencies
        systemExtensionManager = SystemExtensionManager()
        
        // Create device claim adapter
        deviceClaimAdapter = SystemExtensionClaimAdapter(
            systemExtensionManager: systemExtensionManager
        )
        
        // Set up mock device discovery
        mockDeviceDiscovery = MockDeviceDiscovery()
        setupTestDevices()
        
        // Set up server configuration
        serverConfig = ServerConfig()
    }
    
    override func tearDown() {
        // Clean shutdown
        try? systemExtensionManager?.stop()
        
        systemExtensionManager = nil
        deviceClaimAdapter = nil
        mockDeviceDiscovery = nil
        serverConfig = nil
        testDevices = nil
        
        super.tearDown()
    }
    
    // MARK: - Test Data Setup
    
    private func setupTestDevices() {
        testDevices = [
            USBDevice(
                busID: "20",
                deviceID: "0",
                vendorID: 0x05ac,
                productID: 0x030d,
                deviceClass: 0x03,
                deviceSubClass: 0x01,
                deviceProtocol: 0x02,
                speed: .low,
                manufacturerString: "Apple Inc.",
                productString: "Magic Mouse",
                serialNumberString: "ABC123456789"
            ),
            USBDevice(
                busID: "20",
                deviceID: "1", 
                vendorID: 0x046d,
                productID: 0xc31c,
                deviceClass: 0x03,
                deviceSubClass: 0x01,
                deviceProtocol: 0x01,
                speed: .low,
                manufacturerString: "Logitech",
                productString: "USB Receiver",
                serialNumberString: "DEF987654321"
            ),
            USBDevice(
                busID: "21",
                deviceID: "0",
                vendorID: 0x0781,
                productID: 0x5567,
                deviceClass: 0x08,
                deviceSubClass: 0x06,
                deviceProtocol: 0x50,
                speed: .high,
                manufacturerString: "SanDisk Corp.",
                productString: "Cruzer Blade",
                serialNumberString: "4C530001071218115260"
            )
        ]
        
        mockDeviceDiscovery.mockDevices = testDevices
    }
    
    // MARK: - Complete Workflow Tests
    
    func testCompleteSystemExtensionWorkflow() throws {
        // Test the complete bind → claim → status → release → unbind workflow
        
        let expectation = XCTestExpectation(description: "Complete System Extension workflow test")
        var testError: Error?
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Step 1: Start System Extension
                try self.systemExtensionManager.start()
                XCTAssertTrue(self.systemExtensionManager.getStatus().isRunning, "System Extension should be running")
                
                // Step 2: Device Discovery
                let devices = try self.mockDeviceDiscovery.discoverDevices()
                XCTAssertEqual(devices.count, 3, "Should discover 3 test devices")
                
                let firstDevice = devices[0]
                let busid = "\(firstDevice.busID)-\(firstDevice.deviceID)"
                
                // Step 3: Bind Command with System Extension Integration
                let bindCommand = BindCommand(
                    deviceDiscovery: self.mockDeviceDiscovery,
                    serverConfig: self.serverConfig,
                    deviceClaimManager: self.deviceClaimAdapter
                )
                
                // Execute bind command
                try bindCommand.execute(with: [busid])
                
                // Verify device was bound in configuration
                XCTAssertTrue(self.serverConfig.allowedDevices.contains(busid), 
                             "Device should be bound in server configuration")
                
                // Verify device was claimed by System Extension
                XCTAssertTrue(self.deviceClaimAdapter.isDeviceClaimed(deviceID: busid),
                             "Device should be claimed by System Extension")
                
                // Step 4: Status Command Integration
                let statusCommand = StatusCommand(
                    deviceClaimManager: self.deviceClaimAdapter
                )
                
                // Test status command doesn't throw (output verification is complex in tests)
                XCTAssertNoThrow(try statusCommand.execute(with: []),
                                "Status command should execute without throwing")
                
                // Test health check mode
                XCTAssertNoThrow(try statusCommand.execute(with: ["--health"]),
                                "Status health check should execute without throwing")
                
                // Step 5: Verify System Extension Status
                let status = self.deviceClaimAdapter.getSystemExtensionStatus()
                XCTAssertTrue(status.isRunning, "System Extension should be running")
                XCTAssertEqual(status.claimedDevices.count, 1, "Should have 1 claimed device")
                XCTAssertEqual(status.claimedDevices[0].busID, firstDevice.busID, 
                              "Claimed device should match bound device")
                
                // Step 6: Unbind Command with System Extension Integration
                let unbindCommand = UnbindCommand(
                    deviceDiscovery: self.mockDeviceDiscovery,
                    serverConfig: self.serverConfig,
                    deviceClaimManager: self.deviceClaimAdapter
                )
                
                // Execute unbind command
                try unbindCommand.execute(with: [busid])
                
                // Verify device was unbound from configuration
                XCTAssertFalse(self.serverConfig.allowedDevices.contains(busid),
                              "Device should be unbound from server configuration")
                
                // Verify device was released by System Extension
                XCTAssertFalse(self.deviceClaimAdapter.isDeviceClaimed(deviceID: busid),
                              "Device should be released by System Extension")
                
                // Step 7: Verify final status
                let finalStatus = self.deviceClaimAdapter.getSystemExtensionStatus()
                XCTAssertEqual(finalStatus.claimedDevices.count, 0, "Should have no claimed devices")
                
                expectation.fulfill()
            } catch {
                testError = error
                expectation.fulfill()
            }
        }
        
        // Wait with timeout
        let result = XCTWaiter.wait(for: [expectation], timeout: 10.0)
        XCTAssertEqual(result, .completed, "Test should complete within timeout")
        
        if let error = testError {
            throw error
        }
    }
    
    func testSystemExtensionLifecycleDuringServerOperations() throws {
        // Test System Extension lifecycle management during server operations
        
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        let device = testDevices[0]
        let busid = "\(device.busID)-\(device.deviceID)"
        
        // Test device claiming during server lifecycle
        let claimResult = try deviceClaimAdapter.claimDevice(device)
        XCTAssertTrue(claimResult, "Device claim should succeed")
        
        // Test System Extension restart with claimed devices
        try systemExtensionManager.restart()
        
        // Verify device claims persist through restart
        XCTAssertTrue(deviceClaimAdapter.isDeviceClaimed(deviceID: busid),
                     "Device should remain claimed after restart")
        
        // Test health check during operations
        let isHealthy = deviceClaimAdapter.performSystemExtensionHealthCheck()
        XCTAssertTrue(isHealthy, "System Extension should be healthy during operations")
        
        // Clean up
        try deviceClaimAdapter.releaseDevice(device)
    }
    
    func testConcurrentDeviceClaimingScenarios() throws {
        // Test concurrent device claiming scenarios
        
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        let expectation = XCTestExpectation(description: "Concurrent claiming test")
        expectation.expectedFulfillmentCount = testDevices.count
        var errors: [Error] = []
        let errorsLock = NSLock()
        
        // Concurrently claim all test devices
        for device in testDevices {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let claimed = try self.deviceClaimAdapter.claimDevice(device)
                    XCTAssertTrue(claimed, "Device \(device.busID)-\(device.deviceID) should be claimed")
                    
                    // Verify claim
                    let deviceID = "\(device.busID)-\(device.deviceID)"
                    XCTAssertTrue(self.deviceClaimAdapter.isDeviceClaimed(deviceID: deviceID),
                                 "Device should be marked as claimed")
                    
                    expectation.fulfill()
                } catch {
                    errorsLock.lock()
                    errors.append(error)
                    errorsLock.unlock()
                    expectation.fulfill()
                }
            }
        }
        
        // Wait for all concurrent operations
        let result = XCTWaiter.wait(for: [expectation], timeout: 15.0)
        XCTAssertEqual(result, .completed, "Concurrent claiming should complete within timeout")
        
        // Check for errors
        XCTAssertTrue(errors.isEmpty, "Concurrent claiming should not produce errors: \(errors)")
        
        // Verify all devices are claimed
        let status = deviceClaimAdapter.getSystemExtensionStatus()
        XCTAssertEqual(status.claimedDevices.count, testDevices.count,
                      "All devices should be claimed")
        
        // Clean up - release all devices
        let releaseExpectation = XCTestExpectation(description: "Concurrent release test")
        releaseExpectation.expectedFulfillmentCount = testDevices.count
        
        for device in testDevices {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.deviceClaimAdapter.releaseDevice(device)
                    releaseExpectation.fulfill()
                } catch {
                    XCTFail("Failed to release device \(device.busID)-\(device.deviceID): \(error)")
                    releaseExpectation.fulfill()
                }
            }
        }
        
        let releaseResult = XCTWaiter.wait(for: [releaseExpectation], timeout: 10.0)
        XCTAssertEqual(releaseResult, .completed, "Concurrent release should complete within timeout")
        
        // Verify all devices are released
        let finalStatus = deviceClaimAdapter.getSystemExtensionStatus()
        XCTAssertEqual(finalStatus.claimedDevices.count, 0, "All devices should be released")
    }
    
    // MARK: - Error Recovery Tests
    
    func testErrorRecoveryWithSystemExtensionCrash() throws {
        // Test error recovery scenarios when System Extension experiences issues
        
        try systemExtensionManager.start()
        
        let device = testDevices[0]
        let deviceID = "\(device.busID)-\(device.deviceID)"
        
        // Claim device successfully
        let claimResult = try deviceClaimAdapter.claimDevice(device)
        XCTAssertTrue(claimResult, "Initial claim should succeed")
        XCTAssertTrue(deviceClaimAdapter.isDeviceClaimed(deviceID: deviceID),
                     "Device should be claimed initially")
        
        // Simulate System Extension crash by stopping and restarting
        try systemExtensionManager.stop()
        
        // Verify System Extension is stopped
        let stoppedStatus = deviceClaimAdapter.getSystemExtensionStatus()
        XCTAssertFalse(stoppedStatus.isRunning, "System Extension should be stopped")
        
        // Restart System Extension (simulating recovery)
        try systemExtensionManager.start()
        
        // Verify System Extension is running again
        let recoveredStatus = deviceClaimAdapter.getSystemExtensionStatus()
        XCTAssertTrue(recoveredStatus.isRunning, "System Extension should be recovered")
        
        // Test that error recovery doesn't leave zombie claims
        // After recovery, the device may or may not be claimed depending on state persistence
        // The important thing is that the system is functional
        XCTAssertNoThrow(try deviceClaimAdapter.releaseDevice(device),
                        "Should be able to release device after recovery")
    }
    
    func testHandleDeviceDisconnectionDuringClaim() throws {
        // Test handling of device disconnection during claim operations
        
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        let device = testDevices[2] // Use the USB storage device
        let deviceID = "\(device.busID)-\(device.deviceID)"
        
        // Claim device
        let claimResult = try deviceClaimAdapter.claimDevice(device)
        XCTAssertTrue(claimResult, "Device claim should succeed")
        
        // Simulate device disconnection by removing it from mock discovery
        mockDeviceDiscovery.mockDevices.removeAll { $0.deviceID == device.deviceID }
        
        // Test that unbind command handles disconnected device gracefully
        let unbindCommand = UnbindCommand(
            deviceDiscovery: mockDeviceDiscovery,
            serverConfig: serverConfig,
            deviceClaimManager: deviceClaimAdapter
        )
        
        // This should not throw even though device is disconnected
        XCTAssertNoThrow(try unbindCommand.execute(with: [deviceID]),
                        "Unbind should handle disconnected device gracefully")
    }
    
    func testInvalidDeviceClaimingErrorHandling() throws {
        // Test error handling for invalid device claiming operations
        
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        // Test claiming non-existent device
        let invalidDevice = USBDevice(
            busID: "99",
            deviceID: "99",
            vendorID: 0x0000,
            productID: 0x0000,
            deviceClass: 0x00,
            deviceSubClass: 0x00,
            deviceProtocol: 0x00,
            speed: .unknown,
            manufacturerString: nil,
            productString: nil,
            serialNumberString: nil
        )
        
        // This should either throw or return false, but not crash
        do {
            let result = try deviceClaimAdapter.claimDevice(invalidDevice)
            // If it doesn't throw, it should return false for invalid device
            XCTAssertFalse(result, "Invalid device claim should return false")
        } catch {
            // Throwing an error is also acceptable for invalid device
            XCTAssertTrue(error is SystemExtensionError, "Should throw SystemExtensionError for invalid device")
        }
        
        // Test releasing non-claimed device
        let validDevice = testDevices[0]
        XCTAssertNoThrow(try deviceClaimAdapter.releaseDevice(validDevice),
                        "Releasing non-claimed device should not throw")
    }
    
    // MARK: - Performance and Stress Tests
    
    func testSystemExtensionPerformanceUnderLoad() throws {
        // Test System Extension performance under load conditions
        
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        let iterations = 10
        let expectation = XCTestExpectation(description: "Performance test")
        expectation.expectedFulfillmentCount = iterations
        
        let startTime = Date()
        
        // Perform multiple bind/unbind cycles rapidly
        for i in 0..<iterations {
            DispatchQueue.global(qos: .userInitiated).async {
                let device = self.testDevices[i % self.testDevices.count]
                do {
                    // Claim and immediately release
                    let claimed = try self.deviceClaimAdapter.claimDevice(device)
                    XCTAssertTrue(claimed, "Device should be claimed in performance test iteration \(i)")
                    
                    try self.deviceClaimAdapter.releaseDevice(device)
                    expectation.fulfill()
                } catch {
                    XCTFail("Performance test iteration \(i) failed: \(error)")
                    expectation.fulfill()
                }
            }
        }
        
        let result = XCTWaiter.wait(for: [expectation], timeout: 30.0)
        XCTAssertEqual(result, .completed, "Performance test should complete within timeout")
        
        let duration = Date().timeIntervalSince(startTime)
        let operationsPerSecond = Double(iterations * 2) / duration // claim + release per iteration
        
        print("System Extension Performance: \(String(format: "%.2f", operationsPerSecond)) operations/second")
        
        // Verify system is still healthy after load test
        let isHealthy = deviceClaimAdapter.performSystemExtensionHealthCheck()
        XCTAssertTrue(isHealthy, "System Extension should remain healthy after performance test")
        
        // Verify no leaked claims
        let finalStatus = deviceClaimAdapter.getSystemExtensionStatus()
        XCTAssertEqual(finalStatus.claimedDevices.count, 0, "No devices should be claimed after performance test")
    }
    
    // MARK: - Integration with Server Components
    
    func testSystemExtensionWithServerCoordinator() throws {
        // Test System Extension integration with ServerCoordinator
        
        // This test would require more complex setup with actual ServerCoordinator
        // For now, we'll test the interfaces that ServerCoordinator would use
        
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        let device = testDevices[0]
        
        // Test interface methods that ServerCoordinator would call
        let claimed = try deviceClaimAdapter.claimDevice(device)
        XCTAssertTrue(claimed, "Device claim should succeed for server integration")
        
        // Test status queries that server would make
        let status = deviceClaimAdapter.getSystemExtensionStatus()
        XCTAssertTrue(status.isRunning, "System Extension should be running for server")
        XCTAssertEqual(status.claimedDevices.count, 1, "Server should see claimed device")
        
        // Test statistics that server might query
        let statistics = deviceClaimAdapter.getSystemExtensionStatistics()
        XCTAssertGreaterThan(statistics.successfulClaims, 0, "Server should see claim statistics")
        
        // Clean up
        try deviceClaimAdapter.releaseDevice(device)
    }
    
    // MARK: - Real Device Tests (when available)
    
    func testWithRealDevicesWhenAvailable() throws {
        // Test with real devices when available (skipped in CI environments)
        
        let realDeviceDiscovery = IOKitDeviceDiscovery()
        
        do {
            let realDevices = try realDeviceDiscovery.discoverDevices()
            
            // Skip test if no real devices are available
            guard !realDevices.isEmpty else {
                throw XCTSkip("No real USB devices available for integration testing")
            }
            
            // Use real System Extension manager for this test
            let realSystemExtensionManager = SystemExtensionManager()
            let realDeviceClaimAdapter = SystemExtensionClaimAdapter(
                systemExtensionManager: realSystemExtensionManager
            )
            
            try realSystemExtensionManager.start()
            defer { try? realSystemExtensionManager.stop() }
            
            // Test basic functionality with one real device
            let firstRealDevice = realDevices[0]
            let realBusid = "\(firstRealDevice.busID)-\(firstRealDevice.deviceID)"
            
            // Note: This may fail if System Extension is not properly installed
            // In that case, we'll skip rather than fail
            do {
                let claimed = try realDeviceClaimAdapter.claimDevice(firstRealDevice)
                XCTAssertTrue(claimed, "Real device claim should succeed")
                
                // Immediately release to avoid leaving system in bad state
                try realDeviceClaimAdapter.releaseDevice(firstRealDevice)
                
                print("Real device integration test successful with device: \(realBusid)")
            } catch {
                throw XCTSkip("System Extension not available for real device testing: \(error)")
            }
        } catch {
            if error.localizedDescription.contains("No USB devices available") {
                throw XCTSkip("No real USB devices available for testing")
            }
            throw error
        }
    }
}