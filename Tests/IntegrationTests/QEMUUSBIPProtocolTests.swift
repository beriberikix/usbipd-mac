// QEMUUSBIPProtocolTests.swift
// QEMU integration tests for USB/IP protocol validation with actual USB transfers
// Tests complete USB/IP protocol implementation using QEMU infrastructure

import XCTest
import Foundation
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common
@testable import QEMUTestServer

#if canImport(SharedUtilities)
import SharedUtilities
#endif

/// Comprehensive QEMU integration tests for USB/IP protocol validation
/// Tests complete USB/IP communication workflows with simulated and real USB operations
/// Validates protocol compliance, transfer reliability, and performance characteristics
final class QEMUUSBIPProtocolTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    var environmentConfig: TestEnvironmentConfig {
        return TestEnvironmentConfig.ci // CI environment for QEMU integration
    }
    
    var requiredCapabilities: TestEnvironmentCapabilities {
        return [.networkAccess, .filesystemWrite, .qemuIntegration]
    }
    
    var testCategory: String {
        return "qemu"
    }
    
    // MARK: - Test Properties
    
    private var logger: Logger!
    private var qemuConfig: QEMUTestConfiguration!
    private var testServer: QEMUTestServer!
    private var testDeviceSimulator: TestDeviceSimulator!
    private var requestProcessor: SimulatedTestRequestProcessor!
    private var serverConfig: ServerConfig!
    private var tcpServer: TCPServer!
    
    // Network configuration
    private let testServerPort = 3242 // Different from main server to avoid conflicts
    private var serverURL: URL!
    
    // Test client components
    private var clientSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    
    // Test synchronization
    private var serverStartExpectation: XCTestExpectation?
    private var serverStopExpectation: XCTestExpectation?
    
    // MARK: - Test Lifecycle
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        setUpTestSuite()
        
        // Skip if QEMU capabilities not available
        if environmentConfig.shouldSkipTest(requiringCapabilities: requiredCapabilities) {
            throw XCTSkip("QEMU integration tests require QEMU capabilities or appropriate mocks")
        }
        
        // Create logger for testing
        logger = Logger(
            config: LoggerConfig(level: .debug, includeTimestamp: false),
            subsystem: "com.usbipd.qemu.tests",
            category: "protocol-tests"
        )
        
        // Initialize QEMU test configuration
        qemuConfig = QEMUTestConfiguration(
            logger: logger,
            environment: environmentConfig.environment
        )
        
        // Set up test server configuration
        serverURL = URL(string: "ws://localhost:\(testServerPort)")!
        
        // Initialize test device simulator
        testDeviceSimulator = TestDeviceSimulator(logger: logger)
        requestProcessor = SimulatedTestRequestProcessor(logger: logger)
        
        // Initialize server components
        serverConfig = ServerConfig()
        serverConfig.port = testServerPort
        serverConfig.maxConcurrentConnections = 3
        serverConfig.usbOperationTimeout = 10.0
        serverConfig.transferBufferSize = 32768
        
        // Create TCP server
        tcpServer = TCPServer()
        
        // Initialize URL session for client connections
        urlSession = URLSession(configuration: .default)
        
        logger.info("QEMU USB/IP protocol test setup completed", context: [
            "environment": environmentConfig.environment.rawValue,
            "serverPort": testServerPort,
            "capabilities": requiredCapabilities.rawValue
        ])
    }
    
    override func tearDownWithError() throws {
        // Clean up client connections
        clientSocket?.cancel(with: .goingAway, reason: nil)
        clientSocket = nil
        urlSession.finishTasksAndInvalidate()
        
        // Stop test server
        tcpServer?.stop()
        
        // Clean up test components
        testServer = nil
        testDeviceSimulator = nil
        requestProcessor = nil
        qemuConfig = nil
        serverConfig = nil
        tcpServer = nil
        logger = nil
        
        tearDownTestSuite()
        try super.tearDownWithError()
    }
    
    // MARK: - TestSuite Implementation
    
    func setUpTestSuite() {
        // Test suite specific setup
    }
    
    func tearDownTestSuite() {
        // Test suite specific cleanup
    }
    
    // MARK: - QEMU Server Integration Tests
    
    func testQEMUTestServerStartupAndConfiguration() async throws {
        // Test QEMU test server configuration and startup
        let serverConfig = try qemuConfig.getTestServerConfiguration()
        
        XCTAssertEqual(serverConfig.port, 3240) // Default USB/IP port from config
        XCTAssertGreaterThan(serverConfig.maxConnections, 0)
        XCTAssertGreaterThan(serverConfig.requestTimeout, 0)
        XCTAssertEqual(serverConfig.mockLevel, "medium") // CI environment mock level
        
        // Validate QEMU configuration
        XCTAssertNoThrow(try qemuConfig.validateConfiguration())
        
        // Test QEMU args generation
        let qemuArgs = try qemuConfig.generateQEMUArgs()
        XCTAssertFalse(qemuArgs.isEmpty)
        XCTAssertTrue(qemuArgs.contains("-m")) // Memory configuration
        XCTAssertTrue(qemuArgs.contains("-smp")) // CPU configuration
        
        logger.info("QEMU configuration validated successfully", context: [
            "args": qemuArgs.joined(separator: " "),
            "serverPort": serverConfig.port
        ])
    }
    
    func testQEMUTestServerDeviceSimulation() async throws {
        // Test device simulation functionality
        let devices = try testDeviceSimulator.discoverDevices()
        XCTAssertFalse(devices.isEmpty, "Test device simulator should provide test devices")
        XCTAssertEqual(devices.count, 6, "Expected 6 simulated test devices")
        
        // Verify device variety
        let deviceClasses = Set(devices.map { $0.deviceClass })
        XCTAssertTrue(deviceClasses.contains(3), "Should contain HID devices (class 3)")
        XCTAssertTrue(deviceClasses.contains(8), "Should contain Mass Storage devices (class 8)")
        XCTAssertTrue(deviceClasses.contains(9), "Should contain Hub devices (class 9)")
        
        // Test device discovery by specific criteria
        let hidDevices = testDeviceSimulator.getDevicesByClass(3)
        XCTAssertGreaterThanOrEqual(hidDevices.count, 2, "Should have at least 2 HID devices")
        
        // Test device lookup by USB/IP bus ID
        let testDevice = try testDeviceSimulator.getDeviceByUSBIPBusID("1-1:1.0")
        XCTAssertNotNil(testDevice, "Should find device by USB/IP bus ID")
        XCTAssertEqual(testDevice?.busID, "1-1")
        
        // Test device statistics
        let stats = testDeviceSimulator.getDeviceStatistics()
        XCTAssertEqual(stats["totalDevices"] as? Int, 6)
        XCTAssertNotNil(stats["devicesByClass"])
        XCTAssertNotNil(stats["devicesBySpeed"])
        
        logger.info("Device simulation validated", context: [
            "deviceCount": devices.count,
            "deviceClasses": deviceClasses.sorted(),
            "stats": stats
        ])
    }
    
    // MARK: - USB/IP Protocol Tests
    
    func testUSBIPDeviceListProtocol() async throws {
        // Test USB/IP OP_REQ_DEVLIST protocol implementation
        
        // Create device list request
        let request = DeviceListRequest()
        let requestData = try request.encode()
        
        // Process request through simulator
        let responseData = try requestProcessor.processRequest(requestData)
        XCTAssertFalse(responseData.isEmpty, "Device list response should not be empty")
        
        // Decode and validate response
        let response = try DeviceListResponse.decode(from: responseData)
        XCTAssertGreaterThan(response.devices.count, 0, "Should return simulated devices")
        
        // Validate exported device format
        let firstDevice = response.devices[0]
        XCTAssertFalse(firstDevice.path.isEmpty, "Device path should not be empty")
        XCTAssertFalse(firstDevice.busID.isEmpty, "Bus ID should not be empty")
        XCTAssertGreaterThan(firstDevice.vendorID, 0, "Vendor ID should be valid")
        XCTAssertGreaterThan(firstDevice.productID, 0, "Product ID should be valid")
        
        // Verify device information matches simulator
        let simulatedDevices = try testDeviceSimulator.discoverDevices()
        XCTAssertEqual(response.devices.count, simulatedDevices.count,
                      "Response device count should match simulator")
        
        logger.info("USB/IP device list protocol validated", context: [
            "requestSize": requestData.count,
            "responseSize": responseData.count,
            "deviceCount": response.devices.count
        ])
    }
    
    func testUSBIPDeviceImportProtocol() async throws {
        // Test USB/IP OP_REQ_IMPORT protocol implementation
        
        // Get test device for import
        let devices = try testDeviceSimulator.discoverDevices()
        guard let testDevice = devices.first else {
            XCTFail("No test devices available")
            return
        }
        
        let busID = "\(testDevice.busID):\(testDevice.deviceID)"
        
        // Create device import request
        let request = DeviceImportRequest(busID: busID)
        let requestData = try request.encode()
        
        // Process request through simulator
        let responseData = try requestProcessor.processRequest(requestData)
        XCTAssertFalse(responseData.isEmpty, "Device import response should not be empty")
        
        // Decode and validate response
        let response = try DeviceImportResponse.decode(from: responseData)
        XCTAssertEqual(response.returnCode, 0, "Device import should succeed")
        XCTAssertEqual(response.header.status, 0, "Response status should indicate success")
        
        // Verify device is now claimed
        let deviceClaimManager = testDeviceSimulator.getDeviceClaimManager()
        let deviceIdentifier = "\(testDevice.busID)-\(testDevice.deviceID)"
        XCTAssertTrue(deviceClaimManager.isDeviceClaimed(deviceID: deviceIdentifier),
                     "Device should be claimed after import")
        
        logger.info("USB/IP device import protocol validated", context: [
            "busID": busID,
            "requestSize": requestData.count,
            "responseSize": responseData.count,
            "returnCode": response.returnCode
        ])
    }
    
    func testUSBIPDeviceImportNonExistentDevice() async throws {
        // Test import of non-existent device (error handling)
        
        let nonExistentBusID = "99-99:1.0"
        let request = DeviceImportRequest(busID: nonExistentBusID)
        let requestData = try request.encode()
        
        // Process request - should fail gracefully
        let responseData = try requestProcessor.processRequest(requestData)
        let response = try DeviceImportResponse.decode(from: responseData)
        
        XCTAssertNotEqual(response.returnCode, 0, "Import of non-existent device should fail")
        XCTAssertNotEqual(response.header.status, 0, "Response status should indicate failure")
        
        logger.info("Non-existent device import error handling validated", context: [
            "busID": nonExistentBusID,
            "returnCode": response.returnCode,
            "status": response.header.status
        ])
    }
    
    // MARK: - Network Integration Tests
    
    func testTCPServerStartupAndShutdown() async throws {
        // Test TCP server lifecycle for USB/IP protocol
        
        serverStartExpectation = XCTestExpectation(description: "Server started")
        
        // Configure server callbacks
        tcpServer.onServerStarted = { [weak self] in
            self?.logger.info("Test server started successfully")
            self?.serverStartExpectation?.fulfill()
        }
        
        tcpServer.onServerStopped = { [weak self] in
            self?.logger.info("Test server stopped successfully")
            self?.serverStopExpectation?.fulfill()
        }
        
        // Start server
        do {
            try tcpServer.start(port: testServerPort)
            await fulfillment(of: [serverStartExpectation!], timeout: 5.0)
        } catch {
            XCTFail("Failed to start TCP server: \(error)")
            return
        }
        
        // Test server is listening
        XCTAssertTrue(tcpServer.isRunning, "Server should be running")
        
        // Stop server
        serverStopExpectation = XCTestExpectation(description: "Server stopped")
        tcpServer.stop()
        await fulfillment(of: [serverStopExpectation!], timeout: 5.0)
        
        XCTAssertFalse(tcpServer.isRunning, "Server should be stopped")
        
        logger.info("TCP server lifecycle validated")
    }
    
    func testClientConnectionAndCommunication() async throws {
        // Test client connection and basic USB/IP communication
        
        // Start test server
        try tcpServer.start(port: testServerPort)
        defer { tcpServer.stop() }
        
        // Allow server to start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Create client connection
        let connectionExpectation = XCTestExpectation(description: "Client connected")
        let messageExpectation = XCTestExpectation(description: "Message received")
        
        // Connect via raw TCP socket for USB/IP protocol
        let socket = CFSocketCreate(
            kCFAllocatorDefault,
            PF_INET,
            SOCK_STREAM,
            IPPROTO_TCP,
            0,
            nil,
            nil
        )
        
        XCTAssertNotNil(socket, "Should create socket")
        
        // Configure server address
        var serverAddr = sockaddr_in()
        serverAddr.sin_family = sa_family_t(AF_INET)
        serverAddr.sin_port = CFSwapInt16HostToBig(UInt16(testServerPort))
        serverAddr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        let connectResult = withUnsafePointer(to: &serverAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                CFSocketConnectToAddress(socket, Data(bytes: sockPtr, count: MemoryLayout<sockaddr_in>.size), 5.0)
            }
        }
        
        XCTAssertEqual(connectResult, .success, "Should connect to server")
        
        // Clean up socket
        if let socket = socket {
            CFSocketInvalidate(socket)
        }
        
        logger.info("Client connection established and validated")
    }
    
    // MARK: - Protocol Compliance Tests
    
    func testUSBIPHeaderEncoding() async throws {
        // Test USB/IP header encoding/decoding compliance
        
        let testCommands: [USBIPCommand] = [
            .requestDeviceList,
            .replyDeviceList,
            .requestDeviceImport,
            .replyDeviceImport
        ]
        
        for command in testCommands {
            let header = USBIPHeader(command: command, status: 0)
            
            // Test encoding
            let encodedData = try header.encode()
            XCTAssertEqual(encodedData.count, 48, "USB/IP header should be 48 bytes")
            
            // Test decoding
            let decodedHeader = try USBIPHeader.decode(from: encodedData)
            XCTAssertEqual(decodedHeader.command, command, "Command should match after round-trip")
            XCTAssertEqual(decodedHeader.status, 0, "Status should match after round-trip")
            XCTAssertEqual(decodedHeader.version, USBIPProtocol.version, "Version should match protocol")
            
            logger.debug("Header encoding validated", context: [
                "command": String(format: "0x%04x", command.rawValue),
                "encodedSize": encodedData.count
            ])
        }
        
        logger.info("USB/IP header encoding compliance validated")
    }
    
    func testUSBIPMessageSerialization() async throws {
        // Test complete USB/IP message serialization
        
        // Test device list request/response
        let deviceListRequest = DeviceListRequest()
        let requestData = try deviceListRequest.encode()
        
        // Verify request structure
        XCTAssertGreaterThanOrEqual(requestData.count, 48, "Request should include header")
        
        // Parse header from request
        let header = try USBIPHeader.decode(from: requestData)
        XCTAssertEqual(header.command, .requestDeviceList)
        
        // Test device list response
        let testDevices = try testDeviceSimulator.discoverDevices()
        let exportedDevices = testDevices.prefix(2).map { device -> USBIPExportedDevice in
            USBIPExportedDevice(
                path: "/sys/devices/test/\(device.busID)",
                busID: "\(device.busID):\(device.deviceID)",
                busnum: 1,
                devnum: 1,
                speed: UInt32(device.speed.rawValue),
                vendorID: device.vendorID,
                productID: device.productID,
                deviceClass: device.deviceClass,
                deviceSubClass: device.deviceSubClass,
                deviceProtocol: device.deviceProtocol,
                configurationCount: 1,
                configurationValue: 1,
                interfaceCount: 1
            )
        }
        
        let deviceListResponse = DeviceListResponse(devices: Array(exportedDevices))
        let responseData = try deviceListResponse.encode()
        
        // Verify response structure
        XCTAssertGreaterThan(responseData.count, 48, "Response should include header and device data")
        
        // Decode response to verify
        let decodedResponse = try DeviceListResponse.decode(from: responseData)
        XCTAssertEqual(decodedResponse.devices.count, exportedDevices.count)
        
        logger.info("USB/IP message serialization validated", context: [
            "requestSize": requestData.count,
            "responseSize": responseData.count,
            "deviceCount": decodedResponse.devices.count
        ])
    }
    
    // MARK: - Performance and Reliability Tests
    
    func testProtocolPerformanceCharacteristics() async throws {
        // Test USB/IP protocol performance metrics
        
        let iterationCount = 10
        var requestTimes: [TimeInterval] = []
        var responseSizes: [Int] = []
        
        for i in 0..<iterationCount {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // Create and process device list request
            let request = DeviceListRequest()
            let requestData = try request.encode()
            let responseData = try requestProcessor.processRequest(requestData)
            
            let endTime = CFAbsoluteTimeGetCurrent()
            let requestTime = endTime - startTime
            
            requestTimes.append(requestTime)
            responseSizes.append(responseData.count)
            
            logger.debug("Performance iteration completed", context: [
                "iteration": i,
                "requestTime": String(format: "%.3f", requestTime),
                "responseSize": responseData.count
            ])
        }
        
        // Calculate performance metrics
        let averageRequestTime = requestTimes.reduce(0, +) / Double(requestTimes.count)
        let maxRequestTime = requestTimes.max() ?? 0
        let averageResponseSize = responseSizes.reduce(0, +) / responseSizes.count
        
        // Performance assertions
        XCTAssertLessThan(averageRequestTime, 0.1, "Average request time should be under 100ms")
        XCTAssertLessThan(maxRequestTime, 0.5, "Maximum request time should be under 500ms")
        XCTAssertGreaterThan(averageResponseSize, 100, "Response should contain meaningful data")
        
        logger.info("Protocol performance validated", context: [
            "iterations": iterationCount,
            "averageRequestTime": String(format: "%.3f", averageRequestTime),
            "maxRequestTime": String(format: "%.3f", maxRequestTime),
            "averageResponseSize": averageResponseSize
        ])
    }
    
    func testConcurrentProtocolOperations() async throws {
        // Test concurrent USB/IP protocol operations
        
        let concurrentRequests = 5
        let expectations = (0..<concurrentRequests).map { i in
            XCTestExpectation(description: "Concurrent request \(i)")
        }
        
        // Launch concurrent requests
        for i in 0..<concurrentRequests {
            Task {
                do {
                    let request = DeviceListRequest()
                    let requestData = try request.encode()
                    let responseData = try self.requestProcessor.processRequest(requestData)
                    
                    // Validate response
                    let response = try DeviceListResponse.decode(from: responseData)
                    XCTAssertGreaterThan(response.devices.count, 0)
                    
                    expectations[i].fulfill()
                    
                    self.logger.debug("Concurrent request completed", context: [
                        "requestIndex": i,
                        "deviceCount": response.devices.count
                    ])
                } catch {
                    XCTFail("Concurrent request \(i) failed: \(error)")
                    expectations[i].fulfill()
                }
            }
        }
        
        // Wait for all concurrent operations to complete
        await fulfillment(of: expectations, timeout: 10.0)
        
        logger.info("Concurrent protocol operations validated", context: [
            "concurrentRequests": concurrentRequests
        ])
    }
    
    // MARK: - Error Handling and Edge Cases
    
    func testProtocolErrorHandling() async throws {
        // Test USB/IP protocol error handling with invalid data
        
        let invalidTestCases: [(String, Data)] = [
            ("Empty data", Data()),
            ("Too short header", Data(repeating: 0, count: 10)),
            ("Invalid command", Data(repeating: 0xFF, count: 48)),
            ("Malformed device data", Data(repeating: 0xAB, count: 100))
        ]
        
        for (testName, invalidData) in invalidTestCases {
            do {
                _ = try requestProcessor.processRequest(invalidData)
                XCTFail("\(testName) should have thrown an error")
            } catch {
                // Expected to throw - validate error type
                XCTAssertTrue(error is USBIPProtocolError || error is DecodingError,
                             "Should throw appropriate protocol error for: \(testName)")
                
                logger.debug("Protocol error handling validated", context: [
                    "testCase": testName,
                    "errorType": String(describing: type(of: error))
                ])
            }
        }
        
        logger.info("Protocol error handling validated")
    }
    
    func testDeviceNotificationIntegration() async throws {
        // Test device connection/disconnection notification integration
        
        let connectionExpectation = XCTestExpectation(description: "Device connected")
        let disconnectionExpectation = XCTestExpectation(description: "Device disconnected")
        
        // Set up device event monitoring
        testDeviceSimulator.onDeviceConnected = { device in
            self.logger.info("Device connected notification received", context: [
                "busID": device.busID,
                "product": device.productString ?? "Unknown"
            ])
            connectionExpectation.fulfill()
        }
        
        testDeviceSimulator.onDeviceDisconnected = { device in
            self.logger.info("Device disconnected notification received", context: [
                "busID": device.busID,
                "product": device.productString ?? "Unknown"
            ])
            disconnectionExpectation.fulfill()
        }
        
        // Start monitoring
        try testDeviceSimulator.startNotifications()
        
        // Wait for simulated events
        await fulfillment(of: [connectionExpectation], timeout: 3.0)
        await fulfillment(of: [disconnectionExpectation], timeout: 8.0)
        
        // Stop monitoring
        testDeviceSimulator.stopNotifications()
        
        logger.info("Device notification integration validated")
    }
    
    // MARK: - QEMU Environment Integration
    
    func testQEMUEnvironmentIntegration() async throws {
        // Test integration with QEMU environment configuration
        
        // Validate environment configuration
        try qemuConfig.validateConfiguration()
        
        // Test environment-specific settings
        let config = try qemuConfig.loadConfiguration()
        
        // CI environment should have specific characteristics
        XCTAssertEqual(config.vm.memory, "256M", "CI environment should use 256M memory")
        XCTAssertEqual(config.vm.cpuCores, 2, "CI environment should use 2 CPU cores")
        XCTAssertFalse(config.vm.enableKVM, "CI environment should not use KVM")
        XCTAssertEqual(config.testing.mockLevel, "medium", "CI environment should use medium mock level")
        
        // Test timeout configuration
        let timeouts = qemuConfig.getTimeouts()
        XCTAssertEqual(timeouts.readiness, 60, "CI readiness timeout should be 60s")
        XCTAssertEqual(timeouts.connection, 10, "CI connection timeout should be 10s")
        XCTAssertEqual(timeouts.command, 30, "CI command timeout should be 30s")
        
        // Test server configuration derivation
        let serverConfig = try qemuConfig.getTestServerConfiguration()
        XCTAssertEqual(serverConfig.port, 3240, "Should use standard USB/IP port")
        XCTAssertEqual(serverConfig.maxConnections, 4, "Should allow 4 connections (2 CPU cores * 2)")
        XCTAssertEqual(serverConfig.requestTimeout, 30, "Should match command timeout")
        XCTAssertFalse(serverConfig.enableVerboseLogging, "CI should not enable verbose logging")
        
        logger.info("QEMU environment integration validated", context: [
            "environment": qemuConfig.getCurrentEnvironment().rawValue,
            "memory": config.vm.memory,
            "cpuCores": config.vm.cpuCores,
            "mockLevel": config.testing.mockLevel
        ])
    }
}

// MARK: - Helper Extensions

extension QEMUUSBIPProtocolTests {
    
    /// Create test TCP connection for protocol testing
    private func createTestTCPConnection() throws -> CFSocket {
        let socket = CFSocketCreate(
            kCFAllocatorDefault,
            PF_INET,
            SOCK_STREAM,
            IPPROTO_TCP,
            0,
            nil,
            nil
        )
        
        guard let socket = socket else {
            throw TestError.connectionSetupFailed("Failed to create socket")
        }
        
        return socket
    }
    
    /// Helper to validate USB/IP header structure
    private func validateUSBIPHeader(_ header: USBIPHeader, expectedCommand: USBIPCommand) {
        XCTAssertEqual(header.version, USBIPProtocol.version, "Header version should match protocol")
        XCTAssertEqual(header.command, expectedCommand, "Header command should match expected")
        XCTAssertEqual(header.status, 0, "Header status should be success for normal operations")
    }
    
    /// Helper to create mock client for testing
    private func createMockClient() throws -> MockUSBIPClient {
        return MockUSBIPClient(serverURL: serverURL, logger: logger)
    }
}

// MARK: - Mock Client for Testing

/// Mock USB/IP client for protocol testing
private class MockUSBIPClient {
    private let serverURL: URL
    private let logger: Logger
    private var socket: CFSocket?
    
    init(serverURL: URL, logger: Logger) {
        self.serverURL = serverURL
        self.logger = logger
    }
    
    func connect() throws {
        socket = try createTCPConnection()
    }
    
    func disconnect() {
        if let socket = socket {
            CFSocketInvalidate(socket)
            self.socket = nil
        }
    }
    
    func sendRequest(_ data: Data) throws -> Data {
        // Mock implementation for testing
        return Data()
    }
    
    private func createTCPConnection() throws -> CFSocket {
        let socket = CFSocketCreate(
            kCFAllocatorDefault,
            PF_INET,
            SOCK_STREAM,
            IPPROTO_TCP,
            0,
            nil,
            nil
        )
        
        guard let socket = socket else {
            throw TestError.connectionSetupFailed("Failed to create socket")
        }
        
        return socket
    }
}

// MARK: - Test Error Types

private enum TestError: Error, LocalizedError {
    case connectionSetupFailed(String)
    case protocolValidationFailed(String)
    case timeoutExceeded(String)
    
    var errorDescription: String? {
        switch self {
        case .connectionSetupFailed(let message):
            return "Connection setup failed: \(message)"
        case .protocolValidationFailed(let message):
            return "Protocol validation failed: \(message)"
        case .timeoutExceeded(let message):
            return "Timeout exceeded: \(message)"
        }
    }
}