// QEMUTestServerTests.swift
// Unit tests for QEMU Test Server functionality
// Tests USB/IP server functionality and device simulation with protocol validation and error handling

import XCTest
import Foundation
import Network
@testable import Common
@testable import USBIPDCore
@testable import QEMUTestServer

/// Test suite for QEMU Test Server functionality
final class QEMUTestServerTests: XCTestCase {
    
    // MARK: - Test Infrastructure
    
    private var logger: Logger!
    private var testConfiguration: QEMUTestConfiguration!
    private var deviceSimulator: TestDeviceSimulator!
    private var requestProcessor: SimulatedTestRequestProcessor!
    private var serverConfig: TestServerConfiguration!
    private var tempDirectory: URL!
    private var originalWorkingDirectory: String!
    
    // TestSuite protocol requirements - temporarily disabled
    // public let environmentConfig: TestEnvironmentConfig = TestEnvironmentDetector.createConfigurationForCurrentEnvironment()
    // public let requiredCapabilities: TestEnvironmentCapabilities = [.networkAccess, .filesystemWrite]
    // public let testCategory: String = "qemu"
    
    // MARK: - Test Lifecycle
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Validate environment before running tests - temporarily disabled
        // try validateEnvironment()
        
        // Skip if environment doesn't support this test suite - temporarily disabled 
        // guard shouldRunInCurrentEnvironment() else {
        //     throw XCTSkip("QEMU Test Server tests require network and filesystem access")
        // }
        
        // Create logger for testing
        logger = Logger(
            config: LoggerConfig(level: .debug, includeTimestamp: false),
            subsystem: "com.usbipd.qemu.tests",
            category: "test-server"
        )
        
        // Create test configuration
        testConfiguration = QEMUTestConfiguration(
            logger: logger,
            environment: environmentConfig.environment
        )
        
        // Get server configuration
        serverConfig = try testConfiguration.getTestServerConfiguration()
        
        // Create device simulator
        deviceSimulator = TestDeviceSimulator(logger: logger)
        
        // Create request processor
        requestProcessor = SimulatedTestRequestProcessor(logger: logger)
        
        // Set up temporary directory for test artifacts
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("qemu-server-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Store and set working directory
        originalWorkingDirectory = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tempDirectory.path)
        
        // Call TestSuite setup
        setUpTestSuite()
    }
    
    override func tearDownWithError() throws {
        // Call TestSuite teardown
        tearDownTestSuite()
        
        // Restore working directory
        if let originalDir = originalWorkingDirectory {
            FileManager.default.changeCurrentDirectoryPath(originalDir)
        }
        
        // Clean up temporary directory
        if let tempDir = tempDirectory, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Clean up test resources
        requestProcessor = nil
        deviceSimulator = nil
        serverConfig = nil
        testConfiguration = nil
        logger = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - TestSuite Implementation
    
    func setUpTestSuite() {
        // Ensure device simulator notifications are started for testing
        do {
            try deviceSimulator.startNotifications()
        } catch {
            logger?.warning("Failed to start device notifications", context: [
                "error": error.localizedDescription
            ])
        }
    }
    
    func tearDownTestSuite() {
        // Stop device simulator notifications
        deviceSimulator?.stopNotifications()
    }
    
    // MARK: - Device Simulator Tests
    
    func testDeviceSimulatorInitialization() throws {
        XCTAssertNotNil(deviceSimulator)
        
        // Test device discovery
        let devices = try deviceSimulator.discoverDevices()
        XCTAssertFalse(devices.isEmpty, "Device simulator should provide test devices")
        XCTAssertGreaterThanOrEqual(devices.count, 5, "Should have at least 5 test devices")
        
        // Verify device variety
        let deviceClasses = Set(devices.map { $0.deviceClass })
        XCTAssertGreaterThanOrEqual(deviceClasses.count, 3, "Should have devices from multiple classes")
        
        // Check for expected device types
        let hasHIDDevice = devices.contains { $0.deviceClass == 3 } // HID
        let hasMassStorageDevice = devices.contains { $0.deviceClass == 8 } // Mass Storage
        let hasHubDevice = devices.contains { $0.deviceClass == 9 } // Hub
        
        XCTAssertTrue(hasHIDDevice, "Should have HID devices")
        XCTAssertTrue(hasMassStorageDevice, "Should have Mass Storage devices")
        XCTAssertTrue(hasHubDevice, "Should have Hub devices")
    }
    
    func testDeviceSimulatorDeviceRetrieval() throws {
        let devices = try deviceSimulator.discoverDevices()
        guard let firstDevice = devices.first else {
            XCTFail("No test devices available")
            return
        }
        
        // Test retrieving specific device
        let retrievedDevice = try deviceSimulator.getDevice(
            busID: firstDevice.busID,
            deviceID: firstDevice.deviceID
        )
        
        XCTAssertNotNil(retrievedDevice)
        XCTAssertEqual(retrievedDevice?.busID, firstDevice.busID)
        XCTAssertEqual(retrievedDevice?.deviceID, firstDevice.deviceID)
        XCTAssertEqual(retrievedDevice?.vendorID, firstDevice.vendorID)
        XCTAssertEqual(retrievedDevice?.productID, firstDevice.productID)
    }
    
    func testDeviceSimulatorInvalidDeviceRetrieval() throws {
        // Test retrieving non-existent device
        let nonExistentDevice = try deviceSimulator.getDevice(
            busID: "99-99",
            deviceID: "99.0"
        )
        
        XCTAssertNil(nonExistentDevice, "Should return nil for non-existent device")
    }
    
    func testDeviceSimulatorUSBIPBusIDFormat() throws {
        let devices = try deviceSimulator.discoverDevices()
        guard let firstDevice = devices.first else {
            XCTFail("No test devices available")
            return
        }
        
        // Test USB/IP bus ID format retrieval
        let usbipBusID = "\(firstDevice.busID):\(firstDevice.deviceID)"
        let retrievedDevice = try deviceSimulator.getDeviceByUSBIPBusID(usbipBusID)
        
        XCTAssertNotNil(retrievedDevice)
        XCTAssertEqual(retrievedDevice?.busID, firstDevice.busID)
        XCTAssertEqual(retrievedDevice?.deviceID, firstDevice.deviceID)
    }
    
    func testDeviceSimulatorInvalidUSBIPBusIDFormat() throws {
        // Test invalid USB/IP bus ID format
        XCTAssertThrowsError(try deviceSimulator.getDeviceByUSBIPBusID("invalid-format")) { error in
            XCTAssertTrue(error is DeviceError)
            if let deviceError = error as? DeviceError {
                switch deviceError {
                case .deviceNotFound(let message):
                    XCTAssertTrue(message.contains("Invalid busID format"))
                default:
                    XCTFail("Expected deviceNotFound error with invalid format message")
                }
            }
        }
    }
    
    func testDeviceSimulatorDevicesByClass() throws {
        let devices = try deviceSimulator.discoverDevices()
        guard !devices.isEmpty else {
            XCTFail("No test devices available")
            return
        }
        
        // Test filtering devices by class
        let hidDevices = deviceSimulator.getDevicesByClass(3) // HID class
        XCTAssertFalse(hidDevices.isEmpty, "Should find HID devices")
        
        // Verify all returned devices are HID
        for device in hidDevices {
            XCTAssertEqual(device.deviceClass, 3, "All devices should be HID class")
        }
        
        // Test non-existent device class
        let nonExistentDevices = deviceSimulator.getDevicesByClass(255)
        XCTAssertTrue(nonExistentDevices.isEmpty, "Should return empty array for non-existent class")
    }
    
    func testDeviceSimulatorStatistics() throws {
        let stats = deviceSimulator.getDeviceStatistics()
        
        // Verify statistics structure
        XCTAssertNotNil(stats["totalDevices"] as? Int)
        XCTAssertNotNil(stats["devicesByClass"] as? [UInt8: Int])
        XCTAssertNotNil(stats["devicesBySpeed"] as? [USBSpeed: Int])
        XCTAssertNotNil(stats["isMonitoring"] as? Bool)
        
        let totalDevices = stats["totalDevices"] as! Int
        XCTAssertGreaterThan(totalDevices, 0, "Should have test devices")
        
        let isMonitoring = stats["isMonitoring"] as! Bool
        XCTAssertTrue(isMonitoring, "Should be monitoring after setup")
    }
    
    // MARK: - Request Processor Tests
    
    func testRequestProcessorInitialization() throws {
        XCTAssertNotNil(requestProcessor)
        
        // Verify simulator integration
        let simulator = requestProcessor.getSimulator()
        XCTAssertNotNil(simulator)
        
        let devices = try simulator.discoverDevices()
        XCTAssertFalse(devices.isEmpty, "Request processor should have access to simulated devices")
    }
    
    func testRequestProcessorDeviceListRequest() throws {
        // Create device list request
        let request = DeviceListRequest()
        let requestData = try request.encode()
        
        // Process request
        let responseData = try requestProcessor.processRequest(requestData)
        XCTAssertFalse(responseData.isEmpty, "Response should not be empty")
        
        // Decode and verify response
        let response = try DeviceListResponse.decode(from: responseData)
        XCTAssertFalse(response.devices.isEmpty, "Response should contain devices")
        
        // Verify response structure
        for device in response.devices {
            XCTAssertFalse(device.path.isEmpty, "Device path should not be empty")
            XCTAssertFalse(device.busID.isEmpty, "Bus ID should not be empty")
            XCTAssertGreaterThan(device.vendorID, 0, "Vendor ID should be valid")
            XCTAssertGreaterThan(device.productID, 0, "Product ID should be valid")
            XCTAssertGreaterThan(device.deviceClass, 0, "Device class should be valid")
        }
    }
    
    func testRequestProcessorDeviceImportRequestSuccess() throws {
        // Get a device to import
        let devices = try deviceSimulator.discoverDevices()
        guard let testDevice = devices.first else {
            XCTFail("No test devices available")
            return
        }
        
        // Create device import request
        let busID = "\(testDevice.busID):\(testDevice.deviceID)"
        let request = DeviceImportRequest(busID: busID)
        let requestData = try request.encode()
        
        // Process request
        let responseData = try requestProcessor.processRequest(requestData)
        XCTAssertFalse(responseData.isEmpty, "Response should not be empty")
        
        // Decode and verify response
        let response = try DeviceImportResponse.decode(from: responseData)
        XCTAssertEqual(response.returnCode, 0, "Import should succeed")
        XCTAssertEqual(response.header.status, 0, "Header status should indicate success")
    }
    
    func testRequestProcessorDeviceImportRequestFailure() throws {
        // Create device import request for non-existent device
        let request = DeviceImportRequest(busID: "99-99:99.0")
        let requestData = try request.encode()
        
        // Process request
        let responseData = try requestProcessor.processRequest(requestData)
        XCTAssertFalse(responseData.isEmpty, "Response should not be empty")
        
        // Decode and verify error response
        let response = try DeviceImportResponse.decode(from: responseData)
        XCTAssertNotEqual(response.returnCode, 0, "Import should fail for non-existent device")
        XCTAssertNotEqual(response.header.status, 0, "Header status should indicate failure")
    }
    
    func testRequestProcessorInvalidRequestLength() throws {
        // Create data that's too short to be a valid request
        let invalidData = Data([0x01, 0x02, 0x03])
        
        XCTAssertThrowsError(try requestProcessor.processRequest(invalidData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if let protocolError = error as? USBIPProtocolError {
                switch protocolError {
                case .invalidDataLength:
                    break // Expected error
                default:
                    XCTFail("Expected invalidDataLength error, got \(protocolError)")
                }
            }
        }
    }
    
    func testRequestProcessorUnsupportedCommand() throws {
        // Create header with unsupported command
        let header = USBIPHeader(command: .submitRequest, status: 0)
        let headerData = try header.encode()
        
        XCTAssertThrowsError(try requestProcessor.processRequest(headerData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if let protocolError = error as? USBIPProtocolError {
                switch protocolError {
                case .unsupportedCommand(let command):
                    XCTAssertEqual(command, USBIPProtocol.Command.submitRequest.rawValue)
                default:
                    XCTFail("Expected unsupportedCommand error, got \(protocolError)")
                }
            }
        }
    }
    
    // MARK: - Protocol Validation Tests
    
    func testUSBIPHeaderEncoding() throws {
        let header = USBIPHeader(command: .requestDeviceList, status: 0)
        let encodedData = try header.encode()
        
        XCTAssertFalse(encodedData.isEmpty, "Encoded header should not be empty")
        XCTAssertGreaterThanOrEqual(encodedData.count, 8, "Header should be at least 8 bytes")
        
        // Decode and verify
        let decodedHeader = try USBIPHeader.decode(from: encodedData)
        XCTAssertEqual(decodedHeader.command, header.command)
        XCTAssertEqual(decodedHeader.status, header.status)
    }
    
    func testDeviceListRequestEncoding() throws {
        let request = DeviceListRequest()
        let encodedData = try request.encode()
        
        XCTAssertFalse(encodedData.isEmpty, "Encoded request should not be empty")
        
        // Decode and verify
        let decodedRequest = try DeviceListRequest.decode(from: encodedData)
        XCTAssertEqual(decodedRequest.header.command, .requestDeviceList)
    }
    
    func testDeviceImportRequestEncoding() throws {
        let busID = "1-1:1.0"
        let request = DeviceImportRequest(busID: busID)
        let encodedData = try request.encode()
        
        XCTAssertFalse(encodedData.isEmpty, "Encoded request should not be empty")
        
        // Decode and verify
        let decodedRequest = try DeviceImportRequest.decode(from: encodedData)
        XCTAssertEqual(decodedRequest.busID, busID)
        XCTAssertEqual(decodedRequest.header.command, .requestDeviceImport)
    }
    
    func testDeviceListResponseEncoding() throws {
        // Create test exported device
        let exportedDevice = USBIPExportedDevice(
            path: "/sys/devices/test/1-1:1.0",
            busID: "1-1:1.0",
            busnum: 1,
            devnum: 1,
            speed: 2,
            vendorID: 0x046D,
            productID: 0xC077,
            deviceClass: 3,
            deviceSubClass: 1,
            deviceProtocol: 2,
            configurationCount: 1,
            configurationValue: 1,
            interfaceCount: 1
        )
        
        let response = DeviceListResponse(devices: [exportedDevice])
        let encodedData = try response.encode()
        
        XCTAssertFalse(encodedData.isEmpty, "Encoded response should not be empty")
        
        // Decode and verify
        let decodedResponse = try DeviceListResponse.decode(from: encodedData)
        XCTAssertEqual(decodedResponse.devices.count, 1)
        
        let device = decodedResponse.devices[0]
        XCTAssertEqual(device.busID, exportedDevice.busID)
        XCTAssertEqual(device.vendorID, exportedDevice.vendorID)
        XCTAssertEqual(device.productID, exportedDevice.productID)
    }
    
    func testDeviceImportResponseEncoding() throws {
        let response = DeviceImportResponse(returnCode: 0)
        let encodedData = try response.encode()
        
        XCTAssertFalse(encodedData.isEmpty, "Encoded response should not be empty")
        
        // Decode and verify
        let decodedResponse = try DeviceImportResponse.decode(from: encodedData)
        XCTAssertEqual(decodedResponse.returnCode, 0)
        XCTAssertEqual(decodedResponse.header.command, .replyDeviceImport)
    }
    
    // MARK: - Error Handling Tests
    
    func testRequestProcessorWithCorruptedData() throws {
        // Create corrupted data that looks like a valid header but has wrong content
        var corruptedData = Data(repeating: 0xFF, count: 20)
        corruptedData[0...3] = Data([0x00, 0x01, 0x11, 0x05]) // Valid version but invalid command
        
        XCTAssertThrowsError(try requestProcessor.processRequest(corruptedData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
        }
    }
    
    func testDeviceSimulatorWithInvalidNotifications() throws {
        // Test stopping notifications that aren't started
        deviceSimulator.stopNotifications() // Should not crash
        
        // Test starting notifications multiple times
        try deviceSimulator.startNotifications()
        try deviceSimulator.startNotifications() // Should handle gracefully
        
        // Cleanup
        deviceSimulator.stopNotifications()
    }
    
    func testRequestProcessorDeviceClaimFailure() throws {
        // This test would require more complex mocking to simulate claim manager failures
        // For now, we test the basic flow and ensure no crashes occur
        let devices = try deviceSimulator.discoverDevices()
        guard let testDevice = devices.first else {
            XCTFail("No test devices available")
            return
        }
        
        // Import device multiple times - second import should still work (device already claimed)
        let busID = "\(testDevice.busID):\(testDevice.deviceID)"
        let request = DeviceImportRequest(busID: busID)
        let requestData = try request.encode()
        
        // First import
        let firstResponse = try requestProcessor.processRequest(requestData)
        let firstDecoded = try DeviceImportResponse.decode(from: firstResponse)
        XCTAssertEqual(firstDecoded.returnCode, 0)
        
        // Second import (device already claimed)
        let secondResponse = try requestProcessor.processRequest(requestData)
        let secondDecoded = try DeviceImportResponse.decode(from: secondResponse)
        XCTAssertEqual(secondDecoded.returnCode, 0) // Mock claim manager allows re-claiming
    }
    
    // MARK: - Performance Tests
    
    func testDeviceDiscoveryPerformance() throws {
        let timeout = environmentConfig.timeout(for: testCategory)
        
        measure {
            do {
                _ = try deviceSimulator.discoverDevices()
            } catch {
                XCTFail("Device discovery failed: \(error)")
            }
        }
    }
    
    func testRequestProcessingPerformance() throws {
        // Create device list request
        let request = DeviceListRequest()
        let requestData = try request.encode()
        
        measure {
            do {
                _ = try requestProcessor.processRequest(requestData)
            } catch {
                XCTFail("Request processing failed: \(error)")
            }
        }
    }
    
    func testMultipleDeviceImportPerformance() throws {
        let devices = try deviceSimulator.discoverDevices()
        let testDevices = Array(devices.prefix(3)) // Test with first 3 devices
        
        measure {
            for device in testDevices {
                do {
                    let busID = "\(device.busID):\(device.deviceID)"
                    let request = DeviceImportRequest(busID: busID)
                    let requestData = try request.encode()
                    _ = try requestProcessor.processRequest(requestData)
                } catch {
                    XCTFail("Device import failed: \(error)")
                }
            }
        }
    }
    
    // MARK: - Integration Tests
    
    func testEndToEndDeviceListWorkflow() throws {
        // Test complete workflow: discover -> list request -> response -> decode
        
        // 1. Discover devices using simulator
        let simulatedDevices = try deviceSimulator.discoverDevices()
        XCTAssertFalse(simulatedDevices.isEmpty)
        
        // 2. Create and process device list request
        let request = DeviceListRequest()
        let requestData = try request.encode()
        let responseData = try requestProcessor.processRequest(requestData)
        
        // 3. Decode response and verify it matches simulated devices
        let response = try DeviceListResponse.decode(from: responseData)
        XCTAssertEqual(response.devices.count, simulatedDevices.count)
        
        // 4. Verify device details match
        for (exportedDevice, simulatedDevice) in zip(response.devices, simulatedDevices) {
            XCTAssertTrue(exportedDevice.busID.contains(simulatedDevice.busID))
            XCTAssertEqual(exportedDevice.vendorID, simulatedDevice.vendorID)
            XCTAssertEqual(exportedDevice.productID, simulatedDevice.productID)
            XCTAssertEqual(exportedDevice.deviceClass, simulatedDevice.deviceClass)
        }
    }
    
    func testEndToEndDeviceImportWorkflow() throws {
        // Test complete workflow: discover -> select device -> import request -> response
        
        // 1. Get available devices
        let devices = try deviceSimulator.discoverDevices()
        guard let targetDevice = devices.first else {
            XCTFail("No devices available for import test")
            return
        }
        
        // 2. Create import request
        let busID = "\(targetDevice.busID):\(targetDevice.deviceID)"
        let importRequest = DeviceImportRequest(busID: busID)
        let requestData = try importRequest.encode()
        
        // 3. Process import request
        let responseData = try requestProcessor.processRequest(requestData)
        let importResponse = try DeviceImportResponse.decode(from: responseData)
        
        // 4. Verify successful import
        XCTAssertEqual(importResponse.returnCode, 0, "Device import should succeed")
        XCTAssertEqual(importResponse.header.command, .replyDeviceImport)
        XCTAssertEqual(importResponse.header.status, 0)
    }
    
    func testConfigurationIntegration() throws {
        // Test that server configuration integrates properly with test components
        XCTAssertNotNil(serverConfig)
        XCTAssertGreaterThan(serverConfig.port, 1024)
        XCTAssertLessThan(serverConfig.port, 65536)
        XCTAssertGreaterThan(serverConfig.maxConnections, 0)
        XCTAssertGreaterThan(serverConfig.requestTimeout, 0)
        XCTAssertGreaterThan(serverConfig.maxTestDuration, 0)
        
        // Test configuration matches environment
        switch environmentConfig.environment {
        case .development:
            XCTAssertTrue(serverConfig.enableVerboseLogging)
            XCTAssertEqual(serverConfig.mockLevel, "high")
        case .ci:
            XCTAssertFalse(serverConfig.enableVerboseLogging)
            XCTAssertEqual(serverConfig.mockLevel, "medium")
        case .production:
            XCTAssertFalse(serverConfig.enableVerboseLogging)
            XCTAssertEqual(serverConfig.mockLevel, "low")
        }
    }
}

// MARK: - Additional Test Data Structures

/// Mock device claim manager for testing
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
    
    func getClaimedDevices() -> [String] {
        return Array(claimedDevices)
    }
    
    func releaseAllDevices() throws {
        claimedDevices.removeAll()
    }
}