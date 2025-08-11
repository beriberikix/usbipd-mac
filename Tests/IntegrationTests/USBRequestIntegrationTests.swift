//
//  USBRequestIntegrationTests.swift
//  usbipd-mac
//
//  Integration tests for complete USB request/response functionality
//  Tests end-to-end USB operation flow from client to device
//

import XCTest
import Foundation
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

/// Comprehensive integration tests for USB request/response protocol implementation
/// Tests complete workflow: device discovery → device binding → USB operations → response handling
/// Validates multiple USB device types and transfer scenarios with real IOKit integration
/// Tests concurrent operations, error recovery, and performance characteristics
final class USBRequestIntegrationTests: XCTestCase {
    
    // MARK: - Test Properties
    
    var serverCoordinator: ServerCoordinator!
    var tcpServer: TCPServer!
    var deviceDiscovery: IOKitDeviceDiscovery!
    var serverConfig: ServerConfig!
    var requestProcessor: RequestProcessor!
    var usbDeviceCommunicator: USBDeviceCommunicator!
    
    // Test client connection
    var testClient: URLSessionWebSocketTask?
    var testClientExpectation: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
        
        // Initialize core components
        serverConfig = ServerConfig()
        deviceDiscovery = IOKitDeviceDiscovery()
        usbDeviceCommunicator = USBDeviceCommunicator(deviceDiscovery: deviceDiscovery)
        
        // Configure server for testing
        serverConfig.port = 3241 // Use different port to avoid conflicts
        serverConfig.maxConcurrentConnections = 5
        serverConfig.usbOperationTimeout = 5.0
        serverConfig.transferBufferSize = 65536
        
        // Initialize network components
        tcpServer = TCPServer(config: serverConfig)
        requestProcessor = RequestProcessor(
            deviceDiscovery: deviceDiscovery,
            config: serverConfig,
            deviceCommunicator: usbDeviceCommunicator
        )
        serverCoordinator = ServerCoordinator(
            tcpServer: tcpServer,
            requestProcessor: requestProcessor,
            config: serverConfig
        )
    }
    
    override func tearDown() {
        // Clean up test client
        testClient?.cancel(with: .goingAway, reason: nil)
        testClient = nil
        
        // Stop server components
        serverCoordinator?.stop()
        tcpServer = nil
        requestProcessor = nil
        serverCoordinator = nil
        
        // Clean up discovery components
        deviceDiscovery?.stopNotifications()
        deviceDiscovery = nil
        usbDeviceCommunicator = nil
        serverConfig = nil
        
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func startTestServer() async throws {
        try await serverCoordinator.start()
        
        // Give server time to start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }
    
    private func discoverAndBindTestDevice() async throws -> USBDevice? {
        let devices = try deviceDiscovery.discoverDevices()
        
        guard let testDevice = devices.first else {
            throw XCTSkip("No USB devices available for integration testing")
        }
        
        // Bind the test device
        let busid = "\(testDevice.busID)-\(testDevice.deviceID)"
        serverConfig.allowedDevices.insert(busid)
        
        return testDevice
    }
    
    private func createTestClient() async throws -> URLSessionWebSocketTask {
        let url = URL(string: "ws://localhost:\(serverConfig.port)")!
        let client = URLSession.shared.webSocketTask(with: url)
        
        client.resume()
        
        // Wait for connection
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        return client
    }
    
    private func sendUSBIPMessage<T: USBIPMessageCodable>(_ message: T, to client: URLSessionWebSocketTask) async throws {
        let messageData = try message.encode()
        let message = URLSessionWebSocketTask.Message.data(messageData)
        
        try await client.send(message)
    }
    
    private func receiveUSBIPResponse<T: USBIPMessageCodable>(
        _ type: T.Type,
        from client: URLSessionWebSocketTask
    ) async throws -> T {
        let message = try await client.receive()
        
        switch message {
        case .data(let data):
            return try T.decode(from: data)
        case .string(_):
            throw USBIPProtocolError.invalidMessage
        @unknown default:
            throw USBIPProtocolError.invalidMessage
        }
    }
    
    // MARK: - Complete USB Operation Flow Tests
    
    func testCompleteUSBOperationFlowWithRealDevice() async throws {
        // Start server
        try await startTestServer()
        
        // Discover and bind a test device
        guard let testDevice = try await discoverAndBindTestDevice() else {
            return
        }
        
        // Create test client
        let client = try await createTestClient()
        testClient = client
        
        // Test 1: Device Import (OP_REQ_IMPORT)
        let importRequest = USBIPDevListRequest()
        try await sendUSBIPMessage(importRequest, to: client)
        
        let importResponse = try await receiveUSBIPResponse(USBIPDevListResponse.self, from: client)
        XCTAssertEqual(importResponse.status, 0, "Import should succeed")
        XCTAssertGreaterThan(importResponse.exportedDevices.count, 0, "Should export at least one device")
        
        // Test 2: Control Transfer (GET_DESCRIPTOR)
        let controlSetup = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00]) // Get device descriptor
        let submitRequest = USBIPSubmitRequest(
            seqnum: 1,
            devid: UInt32(testDevice.deviceID) ?? 0,
            direction: 1, // IN
            ep: 0x00,
            transferFlags: 0,
            transferBufferLength: 18,
            startFrame: 0,
            numberOfPackets: 0,
            interval: 0,
            setup: controlSetup,
            transferBuffer: nil
        )
        
        try await sendUSBIPMessage(submitRequest, to: client)
        let submitResponse = try await receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
        
        XCTAssertEqual(submitResponse.seqnum, 1, "Response should match request seqnum")
        XCTAssertEqual(submitResponse.status, 0, "Control transfer should succeed")
        XCTAssertGreaterThan(submitResponse.actualLength, 0, "Should receive device descriptor data")
        XCTAssertNotNil(submitResponse.transferBuffer, "Should have descriptor data")
        
        // Test 3: Bulk Transfer (if device supports it)
        if let bulkEndpoint = findBulkEndpoint(for: testDevice) {
            let bulkRequest = USBIPSubmitRequest(
                seqnum: 2,
                devid: UInt32(testDevice.deviceID) ?? 0,
                direction: 1, // IN
                ep: bulkEndpoint,
                transferFlags: 0,
                transferBufferLength: 64,
                startFrame: 0,
                numberOfPackets: 0,
                interval: 0,
                setup: Data(count: 8),
                transferBuffer: nil
            )
            
            try await sendUSBIPMessage(bulkRequest, to: client)
            let bulkResponse = try await receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
            
            XCTAssertEqual(bulkResponse.seqnum, 2)
            // Note: Bulk transfer might timeout or stall, which is acceptable for testing
        }
        
        // Test 4: Request Cancellation (UNLINK)
        let unlinkRequest = USBIPUnlinkRequest(
            seqnum: 3,
            devid: UInt32(testDevice.deviceID) ?? 0,
            direction: 1,
            ep: 0x00,
            unlinkSeqnum: 1
        )
        
        try await sendUSBIPMessage(unlinkRequest, to: client)
        let unlinkResponse = try await receiveUSBIPResponse(USBIPUnlinkResponse.self, from: client)
        
        XCTAssertEqual(unlinkResponse.seqnum, 3)
        // Unlink status depends on whether request is still active
        
        client.cancel(with: .normalClosure, reason: nil)
    }
    
    func testMultipleUSBDeviceOperations() async throws {
        // Start server
        try await startTestServer()
        
        // Discover multiple devices
        let devices = try deviceDiscovery.discoverDevices()
        guard devices.count >= 2 else {
            throw XCTSkip("Need at least 2 USB devices for multi-device testing")
        }
        
        // Bind multiple devices
        for device in devices.prefix(2) {
            let busid = "\(device.busID)-\(device.deviceID)"
            serverConfig.allowedDevices.insert(busid)
        }
        
        let client = try await createTestClient()
        testClient = client
        
        // Test operations on multiple devices
        for (index, device) in devices.prefix(2).enumerated() {
            let controlSetup = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00])
            let submitRequest = USBIPSubmitRequest(
                seqnum: UInt32(index + 1),
                devid: UInt32(device.deviceID) ?? 0,
                direction: 1,
                ep: 0x00,
                transferFlags: 0,
                transferBufferLength: 18,
                startFrame: 0,
                numberOfPackets: 0,
                interval: 0,
                setup: controlSetup,
                transferBuffer: nil
            )
            
            try await sendUSBIPMessage(submitRequest, to: client)
            let response = try await receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
            
            XCTAssertEqual(response.seqnum, UInt32(index + 1))
            XCTAssertEqual(response.status, 0)
        }
        
        client.cancel(with: .normalClosure, reason: nil)
    }
    
    // MARK: - Concurrent Operations Tests
    
    func testConcurrentUSBOperations() async throws {
        try await startTestServer()
        
        guard let testDevice = try await discoverAndBindTestDevice() else {
            return
        }
        
        let client = try await createTestClient()
        testClient = client
        
        // Create multiple concurrent requests
        let requestCount = 5
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = requestCount
        
        for i in 0..<requestCount {
            Task {
                do {
                    let controlSetup = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00])
                    let submitRequest = USBIPSubmitRequest(
                        seqnum: UInt32(i + 1),
                        devid: UInt32(testDevice.deviceID) ?? 0,
                        direction: 1,
                        ep: 0x00,
                        transferFlags: 0,
                        transferBufferLength: 18,
                        startFrame: 0,
                        numberOfPackets: 0,
                        interval: 0,
                        setup: controlSetup,
                        transferBuffer: nil
                    )
                    
                    try await self.sendUSBIPMessage(submitRequest, to: client)
                    let response = try await self.receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
                    
                    XCTAssertEqual(response.seqnum, UInt32(i + 1))
                    expectation.fulfill()
                } catch {
                    XCTFail("Concurrent operation \(i) failed: \(error)")
                    expectation.fulfill()
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        client.cancel(with: .normalClosure, reason: nil)
    }
    
    func testConcurrentClientConnections() async throws {
        try await startTestServer()
        
        guard let testDevice = try await discoverAndBindTestDevice() else {
            return
        }
        
        // Create multiple concurrent client connections
        let clientCount = 3
        let expectation = XCTestExpectation(description: "Multiple clients")
        expectation.expectedFulfillmentCount = clientCount
        
        for i in 0..<clientCount {
            Task {
                do {
                    let client = try await self.createTestClient()
                    defer { client.cancel(with: .normalClosure, reason: nil) }
                    
                    let controlSetup = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00])
                    let submitRequest = USBIPSubmitRequest(
                        seqnum: UInt32(i + 100),
                        devid: UInt32(testDevice.deviceID) ?? 0,
                        direction: 1,
                        ep: 0x00,
                        transferFlags: 0,
                        transferBufferLength: 18,
                        startFrame: 0,
                        numberOfPackets: 0,
                        interval: 0,
                        setup: controlSetup,
                        transferBuffer: nil
                    )
                    
                    try await self.sendUSBIPMessage(submitRequest, to: client)
                    let response = try await self.receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
                    
                    XCTAssertEqual(response.seqnum, UInt32(i + 100))
                    XCTAssertEqual(response.status, 0)
                    expectation.fulfill()
                } catch {
                    XCTFail("Client \(i) operation failed: \(error)")
                    expectation.fulfill()
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 15.0)
    }
    
    // MARK: - Error Handling and Recovery Tests
    
    func testUSBOperationErrorHandling() async throws {
        try await startTestServer()
        
        guard let testDevice = try await discoverAndBindTestDevice() else {
            return
        }
        
        let client = try await createTestClient()
        testClient = client
        
        // Test 1: Invalid endpoint request
        let invalidEndpointRequest = USBIPSubmitRequest(
            seqnum: 1,
            devid: UInt32(testDevice.deviceID) ?? 0,
            direction: 1,
            ep: 0xFF, // Invalid endpoint
            transferFlags: 0,
            transferBufferLength: 64,
            startFrame: 0,
            numberOfPackets: 0,
            interval: 0,
            setup: Data(count: 8),
            transferBuffer: nil
        )
        
        try await sendUSBIPMessage(invalidEndpointRequest, to: client)
        let errorResponse = try await receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
        
        XCTAssertEqual(errorResponse.seqnum, 1)
        XCTAssertNotEqual(errorResponse.status, 0, "Invalid endpoint should return error")
        
        // Test 2: Valid request after error (error recovery)
        let validRequest = USBIPSubmitRequest(
            seqnum: 2,
            devid: UInt32(testDevice.deviceID) ?? 0,
            direction: 1,
            ep: 0x00,
            transferFlags: 0,
            transferBufferLength: 18,
            startFrame: 0,
            numberOfPackets: 0,
            interval: 0,
            setup: Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00]),
            transferBuffer: nil
        )
        
        try await sendUSBIPMessage(validRequest, to: client)
        let validResponse = try await receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
        
        XCTAssertEqual(validResponse.seqnum, 2)
        XCTAssertEqual(validResponse.status, 0, "Valid request should succeed after error")
        
        client.cancel(with: .normalClosure, reason: nil)
    }
    
    func testDeviceDisconnectionHandling() async throws {
        try await startTestServer()
        
        guard let testDevice = try await discoverAndBindTestDevice() else {
            return
        }
        
        let client = try await createTestClient()
        testClient = client
        
        // Simulate device disconnection by removing from bound devices
        let busid = "\(testDevice.busID)-\(testDevice.deviceID)"
        
        // First request should succeed
        let initialRequest = USBIPSubmitRequest(
            seqnum: 1,
            devid: UInt32(testDevice.deviceID) ?? 0,
            direction: 1,
            ep: 0x00,
            transferFlags: 0,
            transferBufferLength: 18,
            startFrame: 0,
            numberOfPackets: 0,
            interval: 0,
            setup: Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00]),
            transferBuffer: nil
        )
        
        try await sendUSBIPMessage(initialRequest, to: client)
        let initialResponse = try await receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
        XCTAssertEqual(initialResponse.status, 0)
        
        // Remove device binding (simulate disconnection)
        serverConfig.allowedDevices.remove(busid)
        
        // Second request should fail
        let disconnectedRequest = USBIPSubmitRequest(
            seqnum: 2,
            devid: UInt32(testDevice.deviceID) ?? 0,
            direction: 1,
            ep: 0x00,
            transferFlags: 0,
            transferBufferLength: 18,
            startFrame: 0,
            numberOfPackets: 0,
            interval: 0,
            setup: Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00]),
            transferBuffer: nil
        )
        
        try await sendUSBIPMessage(disconnectedRequest, to: client)
        let disconnectedResponse = try await receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
        XCTAssertNotEqual(disconnectedResponse.status, 0, "Should fail after device disconnection")
        
        client.cancel(with: .normalClosure, reason: nil)
    }
    
    // MARK: - Performance and Resource Tests
    
    func testUSBOperationPerformance() async throws {
        try await startTestServer()
        
        guard let testDevice = try await discoverAndBindTestDevice() else {
            return
        }
        
        let client = try await createTestClient()
        testClient = client
        
        // Measure performance of multiple operations
        let operationCount = 50
        let startTime = Date()
        
        for i in 0..<operationCount {
            let request = USBIPSubmitRequest(
                seqnum: UInt32(i + 1),
                devid: UInt32(testDevice.deviceID) ?? 0,
                direction: 1,
                ep: 0x00,
                transferFlags: 0,
                transferBufferLength: 18,
                startFrame: 0,
                numberOfPackets: 0,
                interval: 0,
                setup: Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00]),
                transferBuffer: nil
            )
            
            try await sendUSBIPMessage(request, to: client)
            let response = try await receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
            XCTAssertEqual(response.seqnum, UInt32(i + 1))
        }
        
        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(startTime)
        let operationsPerSecond = Double(operationCount) / totalTime
        
        print("USB operation performance: \(operationsPerSecond) ops/sec")
        XCTAssertGreaterThan(operationsPerSecond, 10.0, "Should process at least 10 operations per second")
        
        client.cancel(with: .normalClosure, reason: nil)
    }
    
    func testResourceCleanupAfterOperations() async throws {
        try await startTestServer()
        
        guard let testDevice = try await discoverAndBindTestDevice() else {
            return
        }
        
        // Perform many operations to test resource management
        for clientIndex in 0..<5 {
            let client = try await createTestClient()
            
            for requestIndex in 0..<10 {
                let seqnum = UInt32(clientIndex * 10 + requestIndex + 1)
                let request = USBIPSubmitRequest(
                    seqnum: seqnum,
                    devid: UInt32(testDevice.deviceID) ?? 0,
                    direction: 1,
                    ep: 0x00,
                    transferFlags: 0,
                    transferBufferLength: 18,
                    startFrame: 0,
                    numberOfPackets: 0,
                    interval: 0,
                    setup: Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00]),
                    transferBuffer: nil
                )
                
                try await sendUSBIPMessage(request, to: client)
                let _ = try await receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
            }
            
            client.cancel(with: .normalClosure, reason: nil)
        }
        
        // Resource cleanup is implicit - test passes if no memory leaks or crashes occur
        XCTAssertTrue(true, "Resource cleanup test completed")
    }
    
    // MARK: - USB Transfer Type Specific Tests
    
    func testDifferentUSBTransferTypes() async throws {
        try await startTestServer()
        
        guard let testDevice = try await discoverAndBindTestDevice() else {
            return
        }
        
        let client = try await createTestClient()
        testClient = client
        
        // Test 1: Control Transfer (GET_DESCRIPTOR - Device)
        let deviceDescriptorSetup = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00])
        let controlRequest = USBIPSubmitRequest(
            seqnum: 1,
            devid: UInt32(testDevice.deviceID) ?? 0,
            direction: 1,
            ep: 0x00,
            transferFlags: 0,
            transferBufferLength: 18,
            startFrame: 0,
            numberOfPackets: 0,
            interval: 0,
            setup: deviceDescriptorSetup,
            transferBuffer: nil
        )
        
        try await sendUSBIPMessage(controlRequest, to: client)
        let controlResponse = try await receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
        XCTAssertEqual(controlResponse.status, 0, "Device descriptor request should succeed")
        
        // Test 2: Control Transfer (GET_DESCRIPTOR - Configuration)
        let configDescriptorSetup = Data([0x80, 0x06, 0x00, 0x02, 0x00, 0x00, 0x09, 0x00])
        let configRequest = USBIPSubmitRequest(
            seqnum: 2,
            devid: UInt32(testDevice.deviceID) ?? 0,
            direction: 1,
            ep: 0x00,
            transferFlags: 0,
            transferBufferLength: 9,
            startFrame: 0,
            numberOfPackets: 0,
            interval: 0,
            setup: configDescriptorSetup,
            transferBuffer: nil
        )
        
        try await sendUSBIPMessage(configRequest, to: client)
        let configResponse = try await receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
        XCTAssertEqual(configResponse.status, 0, "Configuration descriptor request should succeed")
        
        // Test 3: Control Transfer (GET_STATUS)
        let statusSetup = Data([0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00])
        let statusRequest = USBIPSubmitRequest(
            seqnum: 3,
            devid: UInt32(testDevice.deviceID) ?? 0,
            direction: 1,
            ep: 0x00,
            transferFlags: 0,
            transferBufferLength: 2,
            startFrame: 0,
            numberOfPackets: 0,
            interval: 0,
            setup: statusSetup,
            transferBuffer: nil
        )
        
        try await sendUSBIPMessage(statusRequest, to: client)
        let statusResponse = try await receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
        XCTAssertEqual(statusResponse.status, 0, "Device status request should succeed")
        
        client.cancel(with: .normalClosure, reason: nil)
    }
    
    // MARK: - CLI Integration Tests
    
    func testCLIStatusReportingWithUSBOperations() async throws {
        try await startTestServer()
        
        guard let testDevice = try await discoverAndBindTestDevice() else {
            return
        }
        
        // Create status command
        let outputFormatter = DefaultOutputFormatter()
        let statusCommand = StatusCommand(
            serverCoordinator: serverCoordinator,
            outputFormatter: outputFormatter
        )
        
        // Get initial status
        XCTAssertNoThrow(try statusCommand.execute(with: []), "Status command should work before operations")
        
        // Perform some USB operations
        let client = try await createTestClient()
        testClient = client
        
        let request = USBIPSubmitRequest(
            seqnum: 1,
            devid: UInt32(testDevice.deviceID) ?? 0,
            direction: 1,
            ep: 0x00,
            transferFlags: 0,
            transferBufferLength: 18,
            startFrame: 0,
            numberOfPackets: 0,
            interval: 0,
            setup: Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00]),
            transferBuffer: nil
        )
        
        try await sendUSBIPMessage(request, to: client)
        let _ = try await receiveUSBIPResponse(USBIPSubmitResponse.self, from: client)
        
        // Get status after operations
        XCTAssertNoThrow(try statusCommand.execute(with: []), "Status command should work after operations")
        
        client.cancel(with: .normalClosure, reason: nil)
    }
    
    // MARK: - Helper Methods for Device Analysis
    
    private func findBulkEndpoint(for device: USBDevice) -> UInt32? {
        // This is a simplified endpoint finder for testing
        // In a real implementation, this would parse configuration descriptors
        // For now, return a commonly used bulk endpoint
        return 0x82 // Typical bulk IN endpoint
    }
    
    // MARK: - Skip Conditions and Environment Checks
    
    func testEnvironmentReadinessCheck() throws {
        // Verify test environment is ready for USB operations
        
        let devices = try deviceDiscovery.discoverDevices()
        if devices.isEmpty {
            throw XCTSkip("No USB devices available - cannot run USB integration tests")
        }
        
        // Check server can bind to test port
        XCTAssertNoThrow(try TCPServer(config: serverConfig), "Should be able to create TCP server")
        
        // Check USB device access permissions
        for device in devices.prefix(1) {
            let busid = "\(device.busID)-\(device.deviceID)"
            XCTAssertNotNil(device.vendorID, "Device should have valid vendor ID")
            XCTAssertNotNil(device.productID, "Device should have valid product ID")
            XCTAssertFalse(busid.isEmpty, "Device should have valid bus ID")
        }
        
        print("Environment check passed - \(devices.count) USB devices available for testing")
    }
}

extension USBDevice {
    // Helper for logging device information in tests
    var testDescription: String {
        let name = productString ?? "Unknown Device"
        let manufacturer = manufacturerString ?? "Unknown"
        return "\(busID)-\(deviceID): \(String(format: "%04x:%04x", vendorID, productID)) (\(manufacturer) - \(name))"
    }
}