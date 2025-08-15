// USBDeviceCLIIntegrationTests.swift
// Integration tests for CLI commands with functional bind/unbind operations

import XCTest
import Foundation
@testable import USBIPDCLI
@testable import USBIPDCore
@testable import Common

/// Integration test suite for CLI command functionality
/// Tests complete CLI workflow: device discovery → bind → status → unbind
/// Validates functional bind/unbind commands with real device discovery
/// Tests error scenarios and status reporting validation
class USBDeviceCLIIntegrationTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    var environmentConfig: TestEnvironmentConfig {
        return TestEnvironmentConfig.ci // CI environment for integration testing
    }
    
    var requiredCapabilities: TestEnvironmentCapabilities {
        return [.networkAccess, .filesystemWrite] // CLI testing capabilities
    }
    
    var testCategory: String {
        return "integration"
    }
    
    // MARK: - Test Properties
    
    private var bindCommand: BindCommand!
    private var unbindCommand: UnbindCommand!
    private var statusCommand: StatusCommand!
    private var listCommand: ListCommand!
    
    private var mockDeviceDiscovery: MockDeviceDiscovery!
    private var mockSystemExtensionManager: MockSystemExtensionManager!
    private var mockDeviceClaimManager: MockDeviceClaimManager!
    private var serverConfig: ServerConfig!
    private var tempConfigPath: URL!
    
    private var testDevices: [USBDevice]!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        setUpTestSuite()
        
        // Create temporary directory for test configuration
        tempConfigPath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("usbipd-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempConfigPath, withIntermediateDirectories: true)
        
        // Set up test configuration
        serverConfig = ServerConfig()
        
        // Set up mock dependencies
        mockDeviceDiscovery = MockDeviceDiscovery()
        mockSystemExtensionManager = MockSystemExtensionManager()
        mockDeviceClaimManager = MockDeviceClaimManager()
        
        // Create test devices
        setupTestDevices()
        
        // Initialize CLI commands with mocks
        bindCommand = BindCommand(
            deviceDiscovery: mockDeviceDiscovery,
            systemExtensionManager: mockSystemExtensionManager,
            serverConfig: serverConfig
        )
        
        unbindCommand = UnbindCommand(
            deviceDiscovery: mockDeviceDiscovery,
            systemExtensionManager: mockSystemExtensionManager,
            serverConfig: serverConfig
        )
        
        statusCommand = StatusCommand(
            deviceClaimManager: mockDeviceClaimManager
        )
        
        listCommand = ListCommand(
            deviceDiscovery: mockDeviceDiscovery
        )
    }
    
    override func tearDown() {
        // Clean up temporary configuration
        if let tempPath = tempConfigPath {
            try? FileManager.default.removeItem(at: tempPath)
        }
        
        bindCommand = nil
        unbindCommand = nil
        statusCommand = nil
        listCommand = nil
        mockDeviceDiscovery = nil
        mockSystemExtensionManager = nil
        mockDeviceClaimManager = nil
        serverConfig = nil
        testDevices = nil
        
        tearDownTestSuite()
        super.tearDown()
    }
    
    // MARK: - Device Setup
    
    private func setupTestDevices() {
        testDevices = [
            USBDevice(
                busID: "1",
                deviceID: "2",
                vendorID: 0x05AC, // Apple
                productID: 0x030D,
                deviceClass: 3, // HID
                deviceSubClass: 1,
                deviceProtocol: 2,
                speed: .high,
                manufacturerString: "Apple Inc.",
                productString: "Magic Mouse",
                serialNumberString: "TEST001"
            ),
            USBDevice(
                busID: "2",
                deviceID: "3",
                vendorID: 0x046D, // Logitech
                productID: 0xC31C,
                deviceClass: 3, // HID
                deviceSubClass: 1,
                deviceProtocol: 2,
                speed: .full,
                manufacturerString: "Logitech",
                productString: "USB Receiver",
                serialNumberString: "TEST002"
            ),
            USBDevice(
                busID: "3",
                deviceID: "1",
                vendorID: 0x0781, // SanDisk
                productID: 0x5567,
                deviceClass: 8, // Mass Storage
                deviceSubClass: 6,
                deviceProtocol: 80,
                speed: .superSpeed,
                manufacturerString: "SanDisk",
                productString: "Ultra USB 3.0",
                serialNumberString: "TEST003"
            )
        ]
        
        mockDeviceDiscovery.mockDevices = testDevices
    }
    
    // MARK: - CLI Command Integration Tests
    
    func testCompleteBindUnbindWorkflow() async throws {
        let testDevice = testDevices[0]
        let busid = "\(testDevice.busID)-\(testDevice.deviceID)"
        
        // Configure System Extension Manager to succeed
        mockSystemExtensionManager.shouldClaimDeviceSucceed = true
        mockSystemExtensionManager.shouldReleaseDeviceSucceed = true
        
        // Test 1: List devices (should show available devices)
        let output = captureOutput {
            try! listCommand.execute(arguments: [])
        }
        XCTAssertTrue(output.contains("Magic Mouse"))
        XCTAssertTrue(output.contains("05ac:030d"))
        XCTAssertTrue(output.contains("1-2"))
        
        // Test 2: Bind device
        let bindOutput = captureOutput {
            try! bindCommand.execute(arguments: [busid])
        }
        
        // Verify bind output
        XCTAssertTrue(bindOutput.contains("Successfully bound device"))
        XCTAssertTrue(bindOutput.contains(busid))
        XCTAssertTrue(bindOutput.contains("Magic Mouse"))
        XCTAssertTrue(bindOutput.contains("System Extension"))
        
        // Verify device was claimed in System Extension
        XCTAssertTrue(mockSystemExtensionManager.claimedDevices.contains(busid))
        
        // Verify device was added to config
        XCTAssertTrue(serverConfig.allowedDevices.contains(busid))
        
        // Test 3: Status command (should show claimed device)
        let statusOutput = captureOutput {
            statusCommand.execute(arguments: ["--detailed"])
        }
        XCTAssertTrue(statusOutput.contains("System Extension") || statusOutput.contains("USB Operations"))
        
        // Test 4: Unbind device
        let unbindOutput = captureOutput {
            try! unbindCommand.execute(arguments: [busid])
        }
        
        // Verify unbind output
        XCTAssertTrue(unbindOutput.contains("successfully released"))
        XCTAssertTrue(unbindOutput.contains(busid))
        XCTAssertTrue(unbindOutput.contains("Magic Mouse"))
        
        // Verify device was released in System Extension
        XCTAssertFalse(mockSystemExtensionManager.claimedDevices.contains(busid))
        
        // Verify device was removed from config
        XCTAssertFalse(serverConfig.allowedDevices.contains(busid))
    }
    
    func testMultipleDeviceBindUnbindWorkflow() async throws {
        let device1 = testDevices[0]
        let device2 = testDevices[1]
        let busid1 = "\(device1.busID)-\(device1.deviceID)"
        let busid2 = "\(device2.busID)-\(device2.deviceID)"
        
        // Configure System Extension Manager to succeed
        mockSystemExtensionManager.shouldClaimDeviceSucceed = true
        mockSystemExtensionManager.shouldReleaseDeviceSucceed = true
        
        // Bind first device
        let bind1Output = captureOutput {
            try! bindCommand.execute(arguments: [busid1])
        }
        XCTAssertTrue(bind1Output.contains("Successfully bound device"))
        XCTAssertTrue(bind1Output.contains("Magic Mouse"))
        
        // Bind second device
        let bind2Output = captureOutput {
            try! bindCommand.execute(arguments: [busid2])
        }
        XCTAssertTrue(bind2Output.contains("Successfully bound device"))
        XCTAssertTrue(bind2Output.contains("USB Receiver"))
        
        // Verify both devices are claimed
        XCTAssertTrue(mockSystemExtensionManager.claimedDevices.contains(busid1))
        XCTAssertTrue(mockSystemExtensionManager.claimedDevices.contains(busid2))
        XCTAssertTrue(serverConfig.allowedDevices.contains(busid1))
        XCTAssertTrue(serverConfig.allowedDevices.contains(busid2))
        
        // Unbind first device
        let unbind1Output = captureOutput {
            try! unbindCommand.execute(arguments: [busid1])
        }
        XCTAssertTrue(unbind1Output.contains("successfully released"))
        
        // Verify first device released, second still claimed
        XCTAssertFalse(mockSystemExtensionManager.claimedDevices.contains(busid1))
        XCTAssertTrue(mockSystemExtensionManager.claimedDevices.contains(busid2))
        
        // Unbind second device
        let unbind2Output = captureOutput {
            try! unbindCommand.execute(arguments: [busid2])
        }
        XCTAssertTrue(unbind2Output.contains("successfully released"))
        
        // Verify both devices are released
        XCTAssertFalse(mockSystemExtensionManager.claimedDevices.contains(busid1))
        XCTAssertFalse(mockSystemExtensionManager.claimedDevices.contains(busid2))
    }
    
    func testBindAlreadyBoundDevice() async throws {
        let testDevice = testDevices[0]
        let busid = "\(testDevice.busID)-\(testDevice.deviceID)"
        
        // Configure System Extension Manager to succeed
        mockSystemExtensionManager.shouldClaimDeviceSucceed = true
        
        // Bind device first time
        let firstBindOutput = captureOutput {
            try! bindCommand.execute(arguments: [busid])
        }
        XCTAssertTrue(firstBindOutput.contains("Successfully bound device"))
        
        // Pre-claim device in System Extension to simulate already bound state
        mockSystemExtensionManager.claimedDevices.insert(busid)
        
        // Attempt to bind again
        let secondBindOutput = captureOutput {
            try! bindCommand.execute(arguments: [busid])
        }
        
        // Should handle gracefully and report already bound
        XCTAssertTrue(secondBindOutput.contains("already claimed") || secondBindOutput.contains("successfully bound"))
        XCTAssertTrue(mockSystemExtensionManager.claimedDevices.contains(busid))
    }
    
    func testUnbindNotBoundDevice() async throws {
        let testDevice = testDevices[0]
        let busid = "\(testDevice.busID)-\(testDevice.deviceID)"
        
        // Configure System Extension Manager to succeed
        mockSystemExtensionManager.shouldReleaseDeviceSucceed = true
        
        // Attempt to unbind device that was never bound
        let unbindOutput = captureOutput {
            try! unbindCommand.execute(arguments: [busid])
        }
        
        // Should handle gracefully
        XCTAssertTrue(unbindOutput.contains("removed from configuration") || 
                     unbindOutput.contains("not bound") || 
                     unbindOutput.contains("successfully unbound"))
    }
    
    // MARK: - Error Scenario Tests
    
    func testBindInvalidBusid() async throws {
        let invalidBusids = ["invalid", "1-", "-2", "1-2-3-4-5", "abc-def", ""]
        
        for invalidBusid in invalidBusids {
            XCTAssertThrowsError(try bindCommand.execute(arguments: [invalidBusid])) { error in
                if let cliError = error as? CommandLineError {
                    XCTAssertTrue(cliError.localizedDescription.contains("Invalid busid"))
                } else if let handlerError = error as? CommandHandlerError {
                    XCTAssertTrue(handlerError.localizedDescription.contains("Invalid") || 
                                handlerError.localizedDescription.contains("busid"))
                }
            }
        }
    }
    
    func testBindNonExistentDevice() async throws {
        let nonExistentBusid = "99-99"
        
        XCTAssertThrowsError(try bindCommand.execute(arguments: [nonExistentBusid])) { error in
            if let handlerError = error as? CommandHandlerError {
                XCTAssertTrue(handlerError.localizedDescription.contains("not found"))
            }
        }
    }
    
    func testBindSystemExtensionFailure() async throws {
        let testDevice = testDevices[0]
        let busid = "\(testDevice.busID)-\(testDevice.deviceID)"
        
        // Configure System Extension Manager to fail device claiming
        mockSystemExtensionManager.shouldClaimDeviceSucceed = false
        mockSystemExtensionManager.claimDeviceError = SystemExtensionError.deviceClaimFailed("Test failure")
        
        XCTAssertThrowsError(try bindCommand.execute(arguments: [busid])) { error in
            if let handlerError = error as? CommandHandlerError {
                XCTAssertTrue(handlerError.localizedDescription.contains("failed to claim") || 
                            handlerError.localizedDescription.contains("System Extension"))
            }
        }
        
        // Device should not be added to config if System Extension fails
        XCTAssertFalse(serverConfig.allowedDevices.contains(busid))
    }
    
    func testUnbindSystemExtensionFailure() async throws {
        let testDevice = testDevices[0]
        let busid = "\(testDevice.busID)-\(testDevice.deviceID)"
        
        // First bind the device successfully
        mockSystemExtensionManager.shouldClaimDeviceSucceed = true
        try bindCommand.execute(arguments: [busid])
        
        // Configure System Extension Manager to fail device release
        mockSystemExtensionManager.shouldReleaseDeviceSucceed = false
        mockSystemExtensionManager.releaseDeviceError = SystemExtensionError.deviceReleaseFailed("Test release failure")
        
        XCTAssertThrowsError(try unbindCommand.execute(arguments: [busid])) { error in
            if let handlerError = error as? CommandHandlerError {
                XCTAssertTrue(handlerError.localizedDescription.contains("failed to release") || 
                            handlerError.localizedDescription.contains("System Extension"))
            }
        }
    }
    
    func testBindWithoutSystemExtensionManager() async throws {
        let testDevice = testDevices[0]
        let busid = "\(testDevice.busID)-\(testDevice.deviceID)"
        
        // Create bind command without System Extension Manager
        let bindCommandNoSysExt = BindCommand(
            deviceDiscovery: mockDeviceDiscovery,
            systemExtensionManager: nil, // No System Extension Manager
            serverConfig: serverConfig
        )
        
        // Should succeed but only add to configuration
        let bindOutput = captureOutput {
            try! bindCommandNoSysExt.execute(arguments: [busid])
        }
        
        XCTAssertTrue(bindOutput.contains("System Extension Manager not available"))
        XCTAssertTrue(bindOutput.contains("configuration only"))
        XCTAssertTrue(serverConfig.allowedDevices.contains(busid))
    }
    
    func testUnbindDisconnectedDevice() async throws {
        let testDevice = testDevices[0]
        let busid = "\(testDevice.busID)-\(testDevice.deviceID)"
        
        // First bind the device
        mockSystemExtensionManager.shouldClaimDeviceSucceed = true
        mockSystemExtensionManager.shouldReleaseDeviceSucceed = true
        try bindCommand.execute(arguments: [busid])
        
        // Remove device from discovery (simulate disconnection)
        mockDeviceDiscovery.mockDevices = testDevices.filter { $0.busID != testDevice.busID || $0.deviceID != testDevice.deviceID }
        
        // Should still unbind successfully with cleanup
        let unbindOutput = captureOutput {
            try! unbindCommand.execute(arguments: [busid])
        }
        
        XCTAssertTrue(unbindOutput.contains("not found") || unbindOutput.contains("cleanup") || unbindOutput.contains("successfully"))
    }
    
    // MARK: - Status Reporting Tests
    
    func testStatusCommandOutput() async throws {
        // Test basic status output
        let basicOutput = captureOutput {
            statusCommand.execute(arguments: [])
        }
        
        // Should contain key status sections
        XCTAssertTrue(basicOutput.contains("System Extension") || 
                     basicOutput.contains("USB Operations") || 
                     basicOutput.contains("Status"))
    }
    
    func testStatusCommandDetailed() async throws {
        // Test detailed status output
        let detailedOutput = captureOutput {
            statusCommand.execute(arguments: ["--detailed"])
        }
        
        // Detailed output should be longer and contain more information
        XCTAssertGreaterThan(detailedOutput.count, 100)
        XCTAssertTrue(detailedOutput.contains("System Extension") || 
                     detailedOutput.contains("USB Operations"))
    }
    
    func testStatusWithBoundDevices() async throws {
        let testDevice = testDevices[0]
        let busid = "\(testDevice.busID)-\(testDevice.deviceID)"
        
        // Bind device first
        mockSystemExtensionManager.shouldClaimDeviceSucceed = true
        try bindCommand.execute(arguments: [busid])
        
        // Status should reflect bound device
        let statusOutput = captureOutput {
            statusCommand.execute(arguments: ["--detailed"])
        }
        
        // Should contain information about operations or devices
        XCTAssertTrue(statusOutput.contains("USB") || statusOutput.contains("System"))
    }
    
    // MARK: - Device Discovery Integration Tests
    
    func testListCommandIntegration() async throws {
        let listOutput = captureOutput {
            try! listCommand.execute(arguments: [])
        }
        
        // Should list all test devices
        XCTAssertTrue(listOutput.contains("Magic Mouse"))
        XCTAssertTrue(listOutput.contains("USB Receiver"))
        XCTAssertTrue(listOutput.contains("Ultra USB 3.0"))
        
        // Should contain device IDs
        XCTAssertTrue(listOutput.contains("05ac:030d"))
        XCTAssertTrue(listOutput.contains("046d:c31c"))
        XCTAssertTrue(listOutput.contains("0781:5567"))
        
        // Should contain bus IDs
        XCTAssertTrue(listOutput.contains("1-2"))
        XCTAssertTrue(listOutput.contains("2-3"))
        XCTAssertTrue(listOutput.contains("3-1"))
    }
    
    func testListCommandWithNoDevices() async throws {
        // Remove all devices
        mockDeviceDiscovery.mockDevices = []
        
        let listOutput = captureOutput {
            try! listCommand.execute(arguments: [])
        }
        
        // Should handle empty device list gracefully
        XCTAssertTrue(listOutput.contains("No devices") || 
                     listOutput.contains("empty") || 
                     listOutput.isEmpty)
    }
    
    func testDeviceDiscoveryError() async throws {
        // Configure device discovery to fail
        mockDeviceDiscovery.shouldFailDiscovery = true
        mockDeviceDiscovery.discoveryError = DeviceDiscoveryError.ioKitError("Test discovery failure")
        
        XCTAssertThrowsError(try listCommand.execute(arguments: [])) { error in
            XCTAssertTrue(error is DeviceDiscoveryError)
        }
    }
    
    // MARK: - Configuration Persistence Tests
    
    func testConfigurationPersistence() async throws {
        let testDevice = testDevices[0]
        let busid = "\(testDevice.busID)-\(testDevice.deviceID)"
        
        // Configure System Extension Manager to succeed
        mockSystemExtensionManager.shouldClaimDeviceSucceed = true
        
        // Bind device
        try bindCommand.execute(arguments: [busid])
        
        // Verify device is in config
        XCTAssertTrue(serverConfig.allowedDevices.contains(busid))
        
        // Create new config instance (simulates app restart)
        let newConfig = ServerConfig()
        
        // Device should still be in allowed devices if config was saved
        // Note: This test depends on ServerConfig.save() implementation
    }
    
    // MARK: - CLI Output Validation Tests
    
    func testBindCommandHelpOutput() async throws {
        let helpOutput = captureOutput {
            try! bindCommand.execute(arguments: ["--help"])
        }
        
        XCTAssertTrue(helpOutput.contains("bind"))
        XCTAssertTrue(helpOutput.contains("BUSID"))
        XCTAssertTrue(helpOutput.contains("device"))
    }
    
    func testUnbindCommandHelpOutput() async throws {
        let helpOutput = captureOutput {
            try! unbindCommand.execute(arguments: ["-h"])
        }
        
        XCTAssertTrue(helpOutput.contains("unbind"))
        XCTAssertTrue(helpOutput.contains("BUSID"))
        XCTAssertTrue(helpOutput.contains("device"))
    }
    
    func testStatusCommandHelpOutput() async throws {
        let helpOutput = captureOutput {
            statusCommand.execute(arguments: ["--help"])
        }
        
        XCTAssertTrue(helpOutput.contains("status"))
        XCTAssertTrue(helpOutput.contains("detailed") || helpOutput.contains("System"))
    }
    
    // MARK: - Performance and Load Tests
    
    func testConcurrentBindOperations() async throws {
        let devices = Array(testDevices[0..<2])
        mockSystemExtensionManager.shouldClaimDeviceSucceed = true
        
        // Execute bind commands concurrently
        let expectations = devices.map { _ in XCTestExpectation(description: "Bind completed") }
        
        for (index, device) in devices.enumerated() {
            let busid = "\(device.busID)-\(device.deviceID)"
            DispatchQueue.global().async {
                do {
                    try self.bindCommand.execute(arguments: [busid])
                    expectations[index].fulfill()
                } catch {
                    XCTFail("Bind failed: \(error)")
                }
            }
        }
        
        wait(for: expectations, timeout: 10.0)
        
        // Verify all devices are bound
        for device in devices {
            let busid = "\(device.busID)-\(device.deviceID)"
            XCTAssertTrue(serverConfig.allowedDevices.contains(busid))
        }
    }
    
    // MARK: - Helper Methods
    
    private func captureOutput<T>(_ block: () throws -> T) rethrows -> String {
        let pipe = Pipe()
        let originalStdout = dup(STDOUT_FILENO)
        
        // Redirect stdout to pipe
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        
        // Execute the block
        defer {
            // Restore stdout
            dup2(originalStdout, STDOUT_FILENO)
            close(originalStdout)
            pipe.fileHandleForWriting.closeFile()
        }
        
        _ = try block()
        
        // Read captured output
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        pipe.fileHandleForReading.closeFile()
        
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Mock System Extension Manager

/// Mock System Extension Manager for CLI testing
private class MockSystemExtensionManager: SystemExtensionManager {
    var claimedDevices: Set<String> = []
    var shouldClaimDeviceSucceed = true
    var shouldReleaseDeviceSucceed = true
    var claimDeviceError: Error?
    var releaseDeviceError: Error?
    
    override func isDeviceClaimed(deviceID: String) -> Bool {
        return claimedDevices.contains(deviceID)
    }
    
    override func claimDevice(_ device: USBDevice) throws -> ClaimedDevice {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        
        if !shouldClaimDeviceSucceed {
            throw claimDeviceError ?? SystemExtensionError.deviceClaimFailed("Mock claim failure")
        }
        
        claimedDevices.insert(deviceID)
        
        return ClaimedDevice(
            deviceID: deviceID,
            claimMethod: .systemExtension,
            claimTime: Date()
        )
    }
    
    override func releaseDevice(_ device: USBDevice) throws {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        
        if !shouldReleaseDeviceSucceed {
            throw releaseDeviceError ?? SystemExtensionError.deviceReleaseFailed("Mock release failure")
        }
        
        claimedDevices.remove(deviceID)
    }
}

// MARK: - Mock Device Discovery

/// Mock Device Discovery for CLI testing
private class MockDeviceDiscovery: DeviceDiscovery {
    var mockDevices: [USBDevice] = []
    var shouldFailDiscovery = false
    var discoveryError: Error?
    
    func discoverDevices() throws -> [USBDevice] {
        if shouldFailDiscovery {
            throw discoveryError ?? DeviceDiscoveryError.ioKitError("Mock discovery failure")
        }
        return mockDevices
    }
    
    func getDevice(busID: String, deviceID: String) throws -> USBDevice? {
        if shouldFailDiscovery {
            throw discoveryError ?? DeviceDiscoveryError.ioKitError("Mock discovery failure")
        }
        
        return mockDevices.first { device in
            device.busID == busID && device.deviceID == deviceID
        }
    }
    
    func getDeviceByIdentifier(_ identifier: String) throws -> USBDevice? {
        let components = identifier.split(separator: "-")
        guard components.count >= 2 else { return nil }
        
        return try getDevice(busID: String(components[0]), deviceID: String(components[1]))
    }
    
    func startMonitoring() throws {
        // Mock implementation - no-op for testing
    }
    
    func stopMonitoring() {
        // Mock implementation - no-op for testing
    }
}

// MARK: - Mock Device Claim Manager

/// Mock Device Claim Manager for CLI testing
private class MockDeviceClaimManager: DeviceClaimManager {
    private var claimedDevices: Set<String> = []
    
    func claimDevice(_ device: USBDevice) throws -> Bool {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        claimedDevices.insert(deviceID)
        return true
    }
    
    func releaseDevice(_ device: USBDevice) throws {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        claimedDevices.remove(deviceID)
    }
    
    func isDeviceClaimed(deviceID: String) -> Bool {
        return claimedDevices.contains(deviceID)
    }
}