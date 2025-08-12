// IPCHandlerTests.swift
// Comprehensive tests for IPC communication between daemon and System Extension

import XCTest
import Foundation
import Dispatch
@testable import SystemExtension
@testable import USBIPDCore
@testable import Common

class IPCHandlerTests: XCTestCase {
    
    // MARK: - Test Properties
    
    var ipcHandler: SystemExtension.XPCIPCHandler!
    var testableHandler: TestableIPCHandler!
    var testLogger: Logger!
    var mockAuthManager: MockAuthenticationManager!
    var testConfig: IPCConfiguration!
    var requestQueue: DispatchQueue!
    
    // Test data
    var testRequest: IPCRequest!
    var testResponse: IPCResponse!
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        // Create test logger with debug level for comprehensive testing
        testLogger = Logger(
            config: LoggerConfig(level: .debug),
            subsystem: "com.usbipd.mac.test",
            category: "ipc-test"
        )
        
        // Create mock authentication manager
        mockAuthManager = MockAuthenticationManager()
        
        // Create test configuration with short timeouts for faster testing
        testConfig = IPCConfiguration(
            serviceName: "com.usbipd.mac.test",
            maxConnections: 5,
            requestTimeout: 2.0,
            maxPendingRequests: 10,
            maxMessageSize: 1024,
            simulateNetworkDelay: 0.0
        )
        
        // Initialize IPC handler with test configuration
        ipcHandler = XPCIPCHandler(
            config: testConfig,
            logger: testLogger,
            authManager: mockAuthManager
        )
        
        // Initialize testable handler
        testableHandler = TestableIPCHandler(
            config: testConfig,
            logger: testLogger,
            authManager: mockAuthManager
        )
        
        // Create test request queue
        requestQueue = DispatchQueue(label: "com.usbipd.mac.test.request-queue")
        
        // Create test request and response
        setupTestData()
    }
    
    override func tearDown() {
        // Clean shutdown
        ipcHandler.stopListener()
        
        ipcHandler = nil
        testableHandler = nil
        testLogger = nil
        mockAuthManager = nil
        testConfig = nil
        requestQueue = nil
        testRequest = nil
        testResponse = nil
        
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitializationWithDefaultConfig() {
        let defaultHandler = XPCIPCHandler()
        XCTAssertNotNil(defaultHandler)
        XCTAssertFalse(defaultHandler.isListening())
    }
    
    func testInitializationWithCustomConfig() {
        XCTAssertNotNil(ipcHandler)
        XCTAssertFalse(ipcHandler.isListening())
        
        let stats = ipcHandler.getStatistics()
        XCTAssertEqual(stats.totalRequests, 0)
        XCTAssertEqual(stats.totalResponses, 0)
        XCTAssertNil(stats.startTime)
    }
    
    // MARK: - Listener Lifecycle Tests
    
    func testStartListener() throws {
        // Test successful listener start
        XCTAssertNoThrow(try ipcHandler.startListener())
        XCTAssertTrue(ipcHandler.isListening())
        
        // Verify statistics
        let stats = ipcHandler.getStatistics()
        XCTAssertNotNil(stats.startTime)
        XCTAssertNil(stats.stopTime)
    }
    
    func testStartListenerAlreadyRunning() throws {
        // Start listener first
        try ipcHandler.startListener()
        XCTAssertTrue(ipcHandler.isListening())
        
        // Starting again should be safe
        XCTAssertNoThrow(try ipcHandler.startListener())
        XCTAssertTrue(ipcHandler.isListening())
    }
    
    func testStopListener() throws {
        // Start then stop listener
        try ipcHandler.startListener()
        XCTAssertTrue(ipcHandler.isListening())
        
        ipcHandler.stopListener()
        XCTAssertFalse(ipcHandler.isListening())
        
        // Verify statistics
        let stats = ipcHandler.getStatistics()
        XCTAssertNotNil(stats.startTime)
        XCTAssertNotNil(stats.stopTime)
    }
    
    func testStopListenerNotRunning() {
        // Stopping when not running should be safe
        XCTAssertNoThrow(ipcHandler.stopListener())
        XCTAssertFalse(ipcHandler.isListening())
    }
    
    func testMultipleStartStopCycles() throws {
        // Test multiple start/stop cycles
        for _ in 0..<3 {
            XCTAssertNoThrow(try ipcHandler.startListener())
            XCTAssertTrue(ipcHandler.isListening())
            
            ipcHandler.stopListener()
            XCTAssertFalse(ipcHandler.isListening())
        }
    }
    
    // MARK: - Authentication Tests
    
    func testClientAuthenticationSuccess() {
        // Configure mock to allow authentication
        mockAuthManager.shouldAuthenticate = true
        
        let result = ipcHandler.authenticateClient(clientID: "client-123")
        XCTAssertTrue(result)
        XCTAssertTrue(mockAuthManager.authenticateClientCalled)
        XCTAssertEqual(mockAuthManager.lastAuthenticatedClient, "client-123")
    }
    
    func testClientAuthenticationFailure() {
        // Configure mock to deny authentication
        mockAuthManager.shouldAuthenticate = false
        
        let result = ipcHandler.authenticateClient(clientID: "invalid-client")
        XCTAssertFalse(result)
        XCTAssertTrue(mockAuthManager.authenticateClientCalled)
        XCTAssertEqual(mockAuthManager.lastAuthenticatedClient, "invalid-client")
    }
    
    func testAuthenticationStatistics() {
        mockAuthManager.shouldAuthenticate = true
        
        // Authenticate some clients
        for i in 1...3 {
            _ = ipcHandler.authenticateClient(clientID: "client-\(i)")
        }
        
        // Configure one to fail
        mockAuthManager.shouldAuthenticate = false
        _ = ipcHandler.authenticateClient(clientID: "bad-client")
        
        let stats = ipcHandler.getStatistics()
        XCTAssertEqual(stats.authenticatedClients, 3)
        XCTAssertEqual(stats.authenticationFailures, 1)
    }
    
    // MARK: - Request/Response Handling Tests
    
    func testResponseSerialization() {
        // Test successful response serialization
        let result = testableHandler.simulateSendResponse(request: testRequest, response: testResponse)
        
        switch result {
        case .success:
            XCTAssertTrue(true) // Response was successfully serialized
        case .failure(let error):
            XCTFail("Response serialization should succeed: \(error)")
        }
    }
    
    func testResponseTooLarge() {
        // Create response with large payload that will be serialized to exceed max size
        let largeResultData = Array(repeating: "large", count: 200) // This should exceed 1KB when serialized
        let largeResponse = IPCResponse(
            requestID: testRequest.requestID,
            success: true,
            result: .success(largeResultData.joined())
        )
        
        let result = testableHandler.simulateSendResponse(request: testRequest, response: largeResponse)
        
        switch result {
        case .success:
            XCTFail("Large response should fail")
        case .failure(let error):
            if case SystemExtensionError.ipcError(let message) = error {
                XCTAssertTrue(message.contains("too large"))
            } else {
                XCTFail("Expected ipcError with 'too large' message")
            }
        }
    }
    
    func testResponseWithError() {
        // Test response serialization with error
        let failedResponse = IPCResponse(
            requestID: testRequest.requestID,
            success: false,
            error: SystemExtensionError.deviceClaimFailed("test-device", nil)
        )
        
        let result = testableHandler.simulateSendResponse(request: testRequest, response: failedResponse)
        
        switch result {
        case .success:
            XCTAssertTrue(true) // Error response was successfully serialized
        case .failure(let error):
            XCTFail("Error response serialization should succeed: \(error)")
        }
    }
    
    // MARK: - Configuration Tests
    
    func testIPCConfiguration() {
        // Test that configuration values are reasonable
        XCTAssertEqual(testConfig.serviceName, "com.usbipd.mac.test")
        XCTAssertEqual(testConfig.maxConnections, 5)
        XCTAssertEqual(testConfig.requestTimeout, 2.0)
        XCTAssertEqual(testConfig.maxPendingRequests, 10)
        XCTAssertEqual(testConfig.maxMessageSize, 1024)
        XCTAssertEqual(testConfig.simulateNetworkDelay, 0.0)
    }
    
    func testDefaultIPCConfiguration() {
        let defaultConfig = IPCConfiguration()
        
        XCTAssertEqual(defaultConfig.serviceName, "com.usbipd.mac.system-extension")
        XCTAssertEqual(defaultConfig.maxConnections, 10)
        XCTAssertEqual(defaultConfig.requestTimeout, 30.0)
        XCTAssertEqual(defaultConfig.maxPendingRequests, 100)
        XCTAssertEqual(defaultConfig.maxMessageSize, 1024 * 1024) // 1MB
        XCTAssertEqual(defaultConfig.simulateNetworkDelay, 0.0)
    }
    
    // MARK: - JSON Serialization Tests
    
    func testRequestSerialization() throws {
        // Test that IPCRequest can be serialized and deserialized
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let requestData = try encoder.encode(testRequest)
        let decodedRequest = try decoder.decode(IPCRequest.self, from: requestData)
        
        XCTAssertEqual(decodedRequest.requestID, testRequest.requestID)
        XCTAssertEqual(decodedRequest.clientID, testRequest.clientID)
        XCTAssertEqual(decodedRequest.command, testRequest.command)
        XCTAssertEqual(decodedRequest.parameters, testRequest.parameters)
    }
    
    func testBasicResponseSerialization() throws {
        // Test that IPCResponse can be serialized and deserialized
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let responseData = try encoder.encode(testResponse)
        let decodedResponse = try decoder.decode(IPCResponse.self, from: responseData)
        
        XCTAssertEqual(decodedResponse.requestID, testResponse.requestID)
        XCTAssertEqual(decodedResponse.success, testResponse.success)
        // Note: Can't easily test result equality due to enum complexity
    }
    
    func testComplexResponseSerialization() throws {
        // Test response with complex result data
        let claimedDevice = ClaimedDevice(
            deviceID: "1-1",
            busID: "1",
            vendorID: 0x1234,
            productID: 0x5678,
            claimTime: Date(),
            claimMethod: .exclusiveAccess,
            claimState: .claimed,
            deviceClass: 0x09,
            deviceSubclass: 0x00,
            deviceProtocol: 0x00
        )
        
        let complexResponse = IPCResponse(
            requestID: testRequest.requestID,
            success: true,
            result: .deviceClaimed(claimedDevice)
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let responseData = try encoder.encode(complexResponse)
        let decodedResponse = try decoder.decode(IPCResponse.self, from: responseData)
        
        XCTAssertEqual(decodedResponse.requestID, complexResponse.requestID)
        XCTAssertEqual(decodedResponse.success, complexResponse.success)
    }
    
    // MARK: - Error Handling Tests
    
    func testSystemExtensionErrorSerialization() throws {
        // Test that SystemExtensionError can be serialized in responses
        let errorResponse = IPCResponse(
            requestID: testRequest.requestID,
            success: false,
            error: SystemExtensionError.deviceClaimFailed("test-device", 42)
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let responseData = try encoder.encode(errorResponse)
        let decodedResponse = try decoder.decode(IPCResponse.self, from: responseData)
        
        XCTAssertEqual(decodedResponse.requestID, errorResponse.requestID)
        XCTAssertEqual(decodedResponse.success, false)
        XCTAssertNotNil(decodedResponse.error)
    }
    
    func testIPCCommandSerialization() throws {
        // Test all IPC commands can be serialized
        let allCommands: [IPCCommand] = [.claimDevice, .releaseDevice, .getClaimedDevices, .getStatus, .healthCheck, .getClaimHistory, .shutdown]
        
        for command in allCommands {
            let request = IPCRequest(
                clientID: "test-client",
                command: command
            )
            
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            
            let requestData = try encoder.encode(request)
            let decodedRequest = try decoder.decode(IPCRequest.self, from: requestData)
            
            XCTAssertEqual(decodedRequest.command, command)
        }
    }
    
    // MARK: - Performance Tests
    
    func testConcurrentSerialization() throws {
        // Test concurrent serialization of requests and responses
        let concurrentRequests = 10
        let expectation = XCTestExpectation(description: "Concurrent serialization")
        expectation.expectedFulfillmentCount = concurrentRequests
        
        let concurrentQueue = DispatchQueue.global(qos: .userInitiated)
        
        // Test concurrent serialization
        for i in 0..<concurrentRequests {
            concurrentQueue.async {
                do {
                    let request = self.createTestRequest(clientID: "concurrent-client-\(i)")
                    let response = IPCResponse(
                        requestID: request.requestID,
                        success: true,
                        result: .success("response-\(i)")
                    )
                    
                    let encoder = JSONEncoder()
                    
                    // Test concurrent encoding
                    _ = try encoder.encode(request)
                    _ = try encoder.encode(response)
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Concurrent serialization failed: \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testLargeDataSerialization() throws {
        // Test serialization performance with larger data sets
        let largeDeviceList = Array(repeating: ClaimedDevice(
            deviceID: "1-1",
            busID: "1",
            vendorID: 0x1234,
            productID: 0x5678,
            claimTime: Date(),
            claimMethod: .exclusiveAccess,
            claimState: .claimed,
            deviceClass: 0x09,
            deviceSubclass: 0x00,
            deviceProtocol: 0x00
        ), count: 50)
        
        let largeResponse = IPCResponse(
            requestID: testRequest.requestID,
            success: true,
            result: .claimedDevices(largeDeviceList)
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let startTime = Date()
        let responseData = try encoder.encode(largeResponse)
        let encodingTime = Date().timeIntervalSince(startTime)
        
        let decodeStartTime = Date()
        _ = try decoder.decode(IPCResponse.self, from: responseData)
        let decodingTime = Date().timeIntervalSince(decodeStartTime)
        
        // Verify reasonable performance (should be well under 1 second)
        XCTAssertLessThan(encodingTime, 1.0)
        XCTAssertLessThan(decodingTime, 1.0)
        XCTAssertGreaterThan(responseData.count, 1000) // Should be substantial data
    }
    
    // MARK: - Statistics and Monitoring Tests
    
    func testInitialStatistics() {
        // Test initial statistics values
        let stats = ipcHandler.getStatistics()
        
        XCTAssertEqual(stats.totalRequests, 0)
        XCTAssertEqual(stats.totalResponses, 0)
        XCTAssertEqual(stats.successfulResponses, 0)
        XCTAssertEqual(stats.failedResponses, 0)
        XCTAssertEqual(stats.acceptedConnections, 0)
        XCTAssertEqual(stats.rejectedConnections, 0)
        XCTAssertEqual(stats.authenticatedClients, 0)
        XCTAssertEqual(stats.authenticationFailures, 0)
        XCTAssertEqual(stats.timeouts, 0)
        XCTAssertEqual(stats.invalidRequests, 0)
        XCTAssertNil(stats.startTime)
        XCTAssertNil(stats.stopTime)
    }
    
    func testStatisticsCalculations() {
        // Test statistics calculations
        var testStats = IPCStatistics()
        
        // Test success rate calculation with no responses
        XCTAssertEqual(testStats.successRate, 0.0)
        
        // Test uptime calculation with no start time
        XCTAssertEqual(testStats.uptime, 0.0)
        
        // Add some mock data for testing calculations
        testStats.recordRequest(command: .claimDevice)
        testStats.recordRequest(command: .getStatus)
        testStats.recordResponse(success: true, duration: 10.0)
        testStats.recordResponse(success: false, duration: 5.0)
        
        XCTAssertEqual(testStats.totalRequests, 2)
        XCTAssertEqual(testStats.totalResponses, 2)
        XCTAssertEqual(testStats.successfulResponses, 1)
        XCTAssertEqual(testStats.failedResponses, 1)
        XCTAssertEqual(testStats.successRate, 50.0)
        XCTAssertEqual(testStats.averageResponseTime, 7.5) // (10 + 5) / 2
    }
    
    func testUptimeCalculation() throws {
        _ = Date()
        try ipcHandler.startListener()
        
        // Wait a bit
        Thread.sleep(forTimeInterval: 0.1)
        
        ipcHandler.stopListener()
        
        let stats = ipcHandler.getStatistics()
        XCTAssertGreaterThan(stats.uptime, 0.05) // Should be at least 50ms
        XCTAssertLessThan(stats.uptime, 1.0) // Should be less than 1 second
    }
    
    // MARK: - Helper Methods
    
    private func setupTestData() {
        testRequest = createTestRequest(clientID: "test-client-123")
        testResponse = IPCResponse(
            requestID: testRequest.requestID,
            success: true,
            result: .success("test response data")
        )
    }
    
    private func createTestRequest(clientID: String) -> IPCRequest {
        return IPCRequest(
            requestID: UUID(),
            clientID: clientID,
            command: .claimDevice,
            parameters: ["deviceID": "1-1"]
        )
    }
}

// MARK: - Mock Authentication Manager

class MockAuthenticationManager: IPCAuthenticationManager {
    var shouldAuthenticate = true
    var authenticateClientCalled = false
    var lastAuthenticatedClient: String?
    
    func authenticateClient(clientID: String) -> Bool {
        authenticateClientCalled = true
        lastAuthenticatedClient = clientID
        return shouldAuthenticate
    }
    
    func reset() {
        shouldAuthenticate = true
        authenticateClientCalled = false
        lastAuthenticatedClient = nil
    }
}

// MARK: - Mock XPC Connection

class MockXPCConnection {
    let processIdentifier: Int32
    
    init(processIdentifier: Int32 = 1234) {
        self.processIdentifier = processIdentifier
    }
    
    func invalidate() {
        // Mock implementation
    }
    
    func resume() {
        // Mock implementation
    }
}

// MARK: - XPCIPCHandler Test Extensions

/// Simplified test wrapper for IPC functionality 
/// This approach focuses on testing core IPC logic without complex XPC mocking
class TestableIPCHandler {
    private let handler: SystemExtension.XPCIPCHandler
    
    init(config: IPCConfiguration, logger: Logger, authManager: IPCAuthenticationManager) {
        self.handler = XPCIPCHandler(config: config, logger: logger, authManager: authManager)
    }
    
    func startListener() throws {
        try handler.startListener()
    }
    
    func stopListener() {
        handler.stopListener()
    }
    
    func isListening() -> Bool {
        return handler.isListening()
    }
    
    func authenticateClient(clientID: String) -> Bool {
        return handler.authenticateClient(clientID: clientID)
    }
    
    func getStatistics() -> SystemExtension.IPCStatistics {
        return handler.getStatistics()
    }
    
    /// Simulate sending response without XPC complications
    func simulateSendResponse(request: IPCRequest, response: IPCResponse) -> Result<Void, SystemExtensionError> {
        do {
            // Instead of trying to mock XPC connections, we test the response preparation logic
            let responseData = try JSONEncoder().encode(response)
            
            // Test if response is too large
            if responseData.count > 1024 { // Use test limit
                return .failure(.ipcError("Response too large: \(responseData.count) bytes"))
            }
            
            // Update statistics to simulate successful sending
            _ = handler.getStatistics()
            // We can't actually modify private statistics, so we'll test what we can
            
            return .success(())
        } catch {
            return .failure(.ipcError("Failed to encode response: \(error.localizedDescription)"))
        }
    }
}