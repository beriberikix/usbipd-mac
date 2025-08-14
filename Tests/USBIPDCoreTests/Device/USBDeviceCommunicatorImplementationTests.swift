// USBDeviceCommunicatorImplementationTests.swift
// Integration tests for USBDeviceCommunicatorImplementation with System Extension scenarios

import XCTest
import Foundation
import IOKit
import IOKit.usb
import Common
@testable import USBIPDCore

/// Integration test suite for USBDeviceCommunicatorImplementation
/// Tests complete USB transfer workflows with device claiming and System Extension integration
class USBDeviceCommunicatorImplementationTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    var environmentConfig: TestEnvironmentConfig {
        return TestEnvironmentConfig.ci // Use CI config for integration testing
    }
    
    var requiredCapabilities: TestEnvironmentCapabilities {
        return [.networkAccess, .filesystemWrite] // Basic integration test capabilities
    }
    
    var testCategory: String {
        return "integration"
    }
    
    // MARK: - Test Properties
    
    private var communicator: USBDeviceCommunicatorImplementation!
    private var mockDeviceClaimManager: MockDeviceClaimManager!
    private var mockIOKitFactory: MockIOKitInterfaceFactory!
    private var testDevice: USBDevice!
    private var testDevice2: USBDevice!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        setUpTestSuite()
        
        // Set up mock dependencies
        mockDeviceClaimManager = MockDeviceClaimManager()
        mockIOKitFactory = MockIOKitInterfaceFactory()
        
        // Create test devices
        testDevice = createTestDevice(busID: "1-1", deviceID: "1.0", vendorID: 0x1234, productID: 0x5678)
        testDevice2 = createTestDevice(busID: "1-2", deviceID: "2.0", vendorID: 0xABCD, productID: 0xEF12)
        
        // Initialize communicator with mocks
        communicator = USBDeviceCommunicatorImplementation(
            deviceClaimManager: mockDeviceClaimManager,
            ioKitInterfaceFactory: mockIOKitFactory
        )
        
        // Set up default device claims
        try! mockDeviceClaimManager.claimDevice(testDevice)
        try! mockDeviceClaimManager.claimDevice(testDevice2)
    }
    
    override func tearDown() {
        // Clean up communicator
        if let communicator = communicator {
            // Close any open interfaces
            for device in [testDevice!, testDevice2!] {
                if communicator.isInterfaceOpen(device: device, interfaceNumber: 0) {
                    try? await communicator.closeUSBInterface(device: device, interfaceNumber: 0)
                }
            }
        }
        
        communicator = nil
        mockDeviceClaimManager = nil
        mockIOKitFactory = nil
        testDevice = nil
        testDevice2 = nil
        
        tearDownTestSuite()
        super.tearDown()
    }
    
    // MARK: - Interface Lifecycle Integration Tests
    
    func testUSBInterfaceOpenCloseLifecycle() async throws {
        // Test complete interface lifecycle
        let interfaceNumber: UInt8 = 0
        
        // Initially interface should be closed
        XCTAssertFalse(communicator.isInterfaceOpen(device: testDevice, interfaceNumber: interfaceNumber))
        
        // Open interface
        try await communicator.openUSBInterface(device: testDevice, interfaceNumber: interfaceNumber)
        
        // Interface should now be open
        XCTAssertTrue(communicator.isInterfaceOpen(device: testDevice, interfaceNumber: interfaceNumber))
        
        // Verify IOKit interface was created and opened
        let createdInterfaces = mockIOKitFactory.getCreatedInterfaces()
        XCTAssertEqual(createdInterfaces.count, 1)
        XCTAssertTrue(createdInterfaces[0].isOpen)
        
        // Close interface
        try await communicator.closeUSBInterface(device: testDevice, interfaceNumber: interfaceNumber)
        
        // Interface should be closed
        XCTAssertFalse(communicator.isInterfaceOpen(device: testDevice, interfaceNumber: interfaceNumber))
        XCTAssertFalse(createdInterfaces[0].isOpen)
    }
    
    func testMultipleInterfaceManagement() async throws {
        let device = testDevice!
        let interfaces: [UInt8] = [0, 1, 2]
        
        // Open multiple interfaces
        for interfaceNumber in interfaces {
            try await communicator.openUSBInterface(device: device, interfaceNumber: interfaceNumber)
            XCTAssertTrue(communicator.isInterfaceOpen(device: device, interfaceNumber: interfaceNumber))
        }
        
        // Verify all interfaces are tracked
        let createdInterfaces = mockIOKitFactory.getCreatedInterfaces()
        XCTAssertEqual(createdInterfaces.count, interfaces.count)
        
        // Close interfaces in different order
        for interfaceNumber in interfaces.reversed() {
            try await communicator.closeUSBInterface(device: device, interfaceNumber: interfaceNumber)
            XCTAssertFalse(communicator.isInterfaceOpen(device: device, interfaceNumber: interfaceNumber))
        }
        
        // All interfaces should be closed
        for interface in createdInterfaces {
            XCTAssertFalse(interface.isOpen)
        }
    }
    
    func testMultipleDeviceInterfaceManagement() async throws {
        let devices = [testDevice!, testDevice2!]
        let interfaceNumber: UInt8 = 0
        
        // Open interfaces for multiple devices
        for device in devices {
            try await communicator.openUSBInterface(device: device, interfaceNumber: interfaceNumber)
            XCTAssertTrue(communicator.isInterfaceOpen(device: device, interfaceNumber: interfaceNumber))
        }
        
        // Each device should have its own interface
        let createdInterfaces = mockIOKitFactory.getCreatedInterfaces()
        XCTAssertEqual(createdInterfaces.count, devices.count)
        
        // Close one device's interface
        try await communicator.closeUSBInterface(device: testDevice, interfaceNumber: interfaceNumber)
        XCTAssertFalse(communicator.isInterfaceOpen(device: testDevice, interfaceNumber: interfaceNumber))
        XCTAssertTrue(communicator.isInterfaceOpen(device: testDevice2, interfaceNumber: interfaceNumber))
        
        // Close remaining interface
        try await communicator.closeUSBInterface(device: testDevice2, interfaceNumber: interfaceNumber)
        XCTAssertFalse(communicator.isInterfaceOpen(device: testDevice2, interfaceNumber: interfaceNumber))
    }
    
    // MARK: - Device Claim Integration Tests
    
    func testDeviceClaimValidationIntegration() async throws {
        // Test with claimed device
        XCTAssertTrue(try communicator.validateDeviceClaim(device: testDevice))
        
        // Should be able to open interface for claimed device
        try await communicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        XCTAssertTrue(communicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0))
        
        // Release device claim
        try mockDeviceClaimManager.releaseDevice(testDevice)
        
        // Validation should now fail
        XCTAssertThrowsError(try communicator.validateDeviceClaim(device: testDevice)) { error in
            XCTAssertTrue(error is USBRequestError)
        }
        
        // Should not be able to open new interfaces for unclaimed device
        await XCTAssertThrowsError(try await communicator.openUSBInterface(device: testDevice, interfaceNumber: 1)) { error in
            XCTAssertTrue(error is USBRequestError)
        }
    }
    
    func testSystemExtensionDeviceClaimingIntegration() async throws {
        // This simulates System Extension claiming behavior
        let unclaimedDevice = createTestDevice(busID: "2-1", deviceID: "3.0", vendorID: 0x9999, productID: 0x8888)
        
        // Attempt to open interface without claiming should fail
        await XCTAssertThrowsError(try await communicator.openUSBInterface(device: unclaimedDevice, interfaceNumber: 0)) { error in
            if let usbError = error as? USBRequestError {
                XCTAssertTrue(usbError.localizedDescription.contains("not claimed") || usbError.localizedDescription.contains("device"))
            }
        }
        
        // Claim device through System Extension (simulated)
        try mockDeviceClaimManager.claimDevice(unclaimedDevice)
        
        // Now interface should open successfully
        try await communicator.openUSBInterface(device: unclaimedDevice, interfaceNumber: 0)
        XCTAssertTrue(communicator.isInterfaceOpen(device: unclaimedDevice, interfaceNumber: 0))
        
        // Clean up
        try await communicator.closeUSBInterface(device: unclaimedDevice, interfaceNumber: 0)
        try mockDeviceClaimManager.releaseDevice(unclaimedDevice)
    }
    
    // MARK: - USB Transfer Integration Tests
    
    func testControlTransferEndToEndWorkflow() async throws {
        // Open interface
        try await communicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        
        // Configure mock interface to return successful control transfer
        let mockInterface = mockIOKitFactory.getCreatedInterfaces().first!
        let expectedResponse = Data([0x12, 0x01, 0x00, 0x02, 0x09, 0x00, 0x00, 0x40])
        mockInterface.setControlTransferResponse(data: expectedResponse, status: .success)
        
        // Create control transfer request (GET_DESCRIPTOR)
        let setupPacket = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00])
        let request = USBRequestBlock(
            seqnum: 1,
            devid: 1,
            direction: .in,
            endpoint: 0x00,
            transferType: .control,
            transferFlags: 0,
            bufferLength: 18,
            setupPacket: setupPacket,
            transferBuffer: nil,
            timeout: 5000
        )
        
        // Execute control transfer
        let result = try await communicator.executeControlTransfer(device: testDevice, request: request)
        
        // Verify result
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.data, expectedResponse)
        XCTAssertEqual(result.actualLength, UInt32(expectedResponse.count))
        
        // Verify mock interface was used correctly
        XCTAssertTrue(mockInterface.wasOperationCalled("control_transfer"))
    }
    
    func testBulkTransferEndToEndWorkflow() async throws {
        // Open interface
        try await communicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        
        // Configure mock interface for bulk transfer
        let mockInterface = mockIOKitFactory.getCreatedInterfaces().first!
        let expectedResponse = Data(repeating: 0xAB, count: 512)
        mockInterface.setBulkTransferResponse(data: expectedResponse, status: .success)
        
        // Create bulk transfer request (IN)
        let request = USBRequestBlock(
            seqnum: 2,
            devid: 1,
            direction: .in,
            endpoint: 0x81,
            transferType: .bulk,
            transferFlags: 0,
            bufferLength: 512,
            transferBuffer: nil,
            timeout: 5000
        )
        
        // Execute bulk transfer
        let result = try await communicator.executeBulkTransfer(device: testDevice, request: request)
        
        // Verify result
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.data, expectedResponse)
        XCTAssertEqual(result.actualLength, UInt32(expectedResponse.count))
        
        // Verify mock interface was used correctly
        XCTAssertTrue(mockInterface.wasOperationCalled("bulk_transfer"))
    }
    
    func testInterruptTransferEndToEndWorkflow() async throws {
        // Open interface
        try await communicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        
        // Configure mock interface for interrupt transfer
        let mockInterface = mockIOKitFactory.getCreatedInterfaces().first!
        let expectedResponse = Data([0x01, 0x02, 0x03, 0x04])
        mockInterface.setInterruptTransferResponse(data: expectedResponse, status: .success)
        
        // Create interrupt transfer request (IN)
        let request = USBRequestBlock(
            seqnum: 3,
            devid: 1,
            direction: .in,
            endpoint: 0x83,
            transferType: .interrupt,
            transferFlags: 0,
            bufferLength: 64,
            transferBuffer: nil,
            timeout: 5000
        )
        
        // Execute interrupt transfer
        let result = try await communicator.executeInterruptTransfer(device: testDevice, request: request)
        
        // Verify result
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.data, expectedResponse)
        XCTAssertEqual(result.actualLength, UInt32(expectedResponse.count))
        
        // Verify mock interface was used correctly
        XCTAssertTrue(mockInterface.wasOperationCalled("interrupt_transfer"))
    }
    
    func testIsochronousTransferEndToEndWorkflow() async throws {
        // Open interface
        try await communicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        
        // Configure mock interface for isochronous transfer
        let mockInterface = mockIOKitFactory.getCreatedInterfaces().first!
        let expectedResponse = Data(repeating: 0xCD, count: 1024)
        mockInterface.setIsochronousTransferResponse(data: expectedResponse, status: .success, errorCount: 0)
        
        // Create isochronous transfer request (IN)
        let request = USBRequestBlock(
            seqnum: 4,
            devid: 1,
            direction: .in,
            endpoint: 0x85,
            transferType: .isochronous,
            transferFlags: 0,
            bufferLength: 1024,
            transferBuffer: nil,
            timeout: 5000,
            startFrame: 100,
            numberOfPackets: 8,
            interval: 1
        )
        
        // Execute isochronous transfer
        let result = try await communicator.executeIsochronousTransfer(device: testDevice, request: request)
        
        // Verify result
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.data, expectedResponse)
        XCTAssertEqual(result.actualLength, UInt32(expectedResponse.count))
        XCTAssertEqual(result.startFrame, 100)
        XCTAssertEqual(result.errorCount, 0)
        
        // Verify mock interface was used correctly
        XCTAssertTrue(mockInterface.wasOperationCalled("isochronous_transfer"))
    }
    
    // MARK: - Error Handling Integration Tests
    
    func testTransferWithUnclaimedDeviceError() async throws {
        // Release device claim
        try mockDeviceClaimManager.releaseDevice(testDevice)
        
        // Attempt to execute transfer without claiming should fail
        let request = createControlTransferRequest()
        
        await XCTAssertThrowsError(try await communicator.executeControlTransfer(device: testDevice, request: request)) { error in
            XCTAssertTrue(error is USBRequestError)
            if let usbError = error as? USBRequestError {
                XCTAssertTrue(usbError.localizedDescription.contains("not claimed"))
            }
        }
    }
    
    func testTransferWithClosedInterfaceError() async throws {
        // Attempt to execute transfer without opening interface
        let request = createControlTransferRequest()
        
        await XCTAssertThrowsError(try await communicator.executeControlTransfer(device: testDevice, request: request)) { error in
            XCTAssertTrue(error is USBRequestError)
        }
    }
    
    func testIOKitInterfaceCreationFailure() async throws {
        // Configure factory to fail interface creation
        mockIOKitFactory.shouldFailInterfaceCreation = true
        mockIOKitFactory.interfaceCreationError = USBRequestError.deviceNotAvailable
        
        // Attempt to open interface should fail
        await XCTAssertThrowsError(try await communicator.openUSBInterface(device: testDevice, interfaceNumber: 0)) { error in
            XCTAssertTrue(error is USBRequestError)
        }
        
        // Interface should not be marked as open
        XCTAssertFalse(communicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0))
    }
    
    func testIOKitInterfaceOpenFailure() async throws {
        // Configure mock interface to fail on open
        mockIOKitFactory.configureInterfaceFailure(.open, error: USBRequestError.deviceNotAvailable)
        
        // Attempt to open interface should fail
        await XCTAssertThrowsError(try await communicator.openUSBInterface(device: testDevice, interfaceNumber: 0)) { error in
            XCTAssertTrue(error is USBRequestError)
        }
        
        // Interface should not be marked as open
        XCTAssertFalse(communicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0))
    }
    
    func testTransferValidationFailures() async throws {
        // Open interface
        try await communicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        
        // Test invalid control transfer (missing setup packet)
        let invalidControlRequest = USBRequestBlock(
            seqnum: 1,
            devid: 1,
            direction: .in,
            endpoint: 0x00,
            transferType: .control,
            transferFlags: 0,
            bufferLength: 18,
            setupPacket: nil, // Missing setup packet
            transferBuffer: nil,
            timeout: 5000
        )
        
        await XCTAssertThrowsError(try await communicator.executeControlTransfer(device: testDevice, request: invalidControlRequest)) { error in
            XCTAssertTrue(error is USBRequestError)
        }
        
        // Test invalid bulk transfer (zero buffer length)
        let invalidBulkRequest = USBRequestBlock(
            seqnum: 2,
            devid: 1,
            direction: .in,
            endpoint: 0x81,
            transferType: .bulk,
            transferFlags: 0,
            bufferLength: 0, // Invalid buffer length
            transferBuffer: nil,
            timeout: 5000
        )
        
        await XCTAssertThrowsError(try await communicator.executeBulkTransfer(device: testDevice, request: invalidBulkRequest)) { error in
            XCTAssertTrue(error is USBRequestError)
        }
    }
    
    // MARK: - Concurrency Integration Tests
    
    func testConcurrentTransferOperations() async throws {
        // Open interface
        try await communicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        
        // Configure mock interface for different transfer types
        let mockInterface = mockIOKitFactory.getCreatedInterfaces().first!
        mockInterface.setControlTransferResponse(data: Data([0x01]), status: .success)
        mockInterface.setBulkTransferResponse(data: Data([0x02]), status: .success)
        mockInterface.setInterruptTransferResponse(data: Data([0x03]), status: .success)
        
        // Create different transfer requests
        let controlRequest = createControlTransferRequest(seqnum: 1)
        let bulkRequest = createBulkTransferRequest(seqnum: 2)
        let interruptRequest = createInterruptTransferRequest(seqnum: 3)
        
        // Execute transfers concurrently
        async let controlResult = communicator.executeControlTransfer(device: testDevice, request: controlRequest)
        async let bulkResult = communicator.executeBulkTransfer(device: testDevice, request: bulkRequest)
        async let interruptResult = communicator.executeInterruptTransfer(device: testDevice, request: interruptRequest)
        
        let results = try await [controlResult, bulkResult, interruptResult]
        
        // Verify all transfers succeeded
        for result in results {
            XCTAssertEqual(result.status, .success)
        }
        
        // Verify different data for each transfer type
        XCTAssertEqual(results[0].data, Data([0x01]))
        XCTAssertEqual(results[1].data, Data([0x02]))
        XCTAssertEqual(results[2].data, Data([0x03]))
    }
    
    func testConcurrentInterfaceOperations() async throws {
        let devices = [testDevice!, testDevice2!]
        
        // Open interfaces for multiple devices concurrently
        async let device1Open = communicator.openUSBInterface(device: devices[0], interfaceNumber: 0)
        async let device2Open = communicator.openUSBInterface(device: devices[1], interfaceNumber: 0)
        
        try await device1Open
        try await device2Open
        
        // Both interfaces should be open
        for device in devices {
            XCTAssertTrue(communicator.isInterfaceOpen(device: device, interfaceNumber: 0))
        }
        
        // Close interfaces concurrently
        async let device1Close = communicator.closeUSBInterface(device: devices[0], interfaceNumber: 0)
        async let device2Close = communicator.closeUSBInterface(device: devices[1], interfaceNumber: 0)
        
        try await device1Close
        try await device2Close
        
        // Both interfaces should be closed
        for device in devices {
            XCTAssertFalse(communicator.isInterfaceOpen(device: device, interfaceNumber: 0))
        }
    }
    
    // MARK: - System Extension Integration Scenarios
    
    func testSystemExtensionBindUnbindWorkflow() async throws {
        // Simulate System Extension bind workflow
        // 1. Device is discovered
        // 2. Device is bound (claimed) through System Extension
        // 3. Interface is opened for communication
        // 4. Transfers are executed
        // 5. Interface is closed
        // 6. Device is unbound (released)
        
        let workflowDevice = createTestDevice(busID: "3-1", deviceID: "4.0", vendorID: 0x2020, productID: 0x3030)
        
        // Step 1: Device discovered (simulated by creating test device)
        
        // Step 2: Bind device through System Extension (claim)
        try mockDeviceClaimManager.claimDevice(workflowDevice)
        XCTAssertTrue(try communicator.validateDeviceClaim(device: workflowDevice))
        
        // Step 3: Open interface
        try await communicator.openUSBInterface(device: workflowDevice, interfaceNumber: 0)
        XCTAssertTrue(communicator.isInterfaceOpen(device: workflowDevice, interfaceNumber: 0))
        
        // Step 4: Execute transfers
        let mockInterface = mockIOKitFactory.getCreatedInterfaces().last!
        mockInterface.setControlTransferResponse(data: Data([0xFF]), status: .success)
        
        let request = createControlTransferRequest()
        let result = try await communicator.executeControlTransfer(device: workflowDevice, request: request)
        XCTAssertEqual(result.status, .success)
        
        // Step 5: Close interface
        try await communicator.closeUSBInterface(device: workflowDevice, interfaceNumber: 0)
        XCTAssertFalse(communicator.isInterfaceOpen(device: workflowDevice, interfaceNumber: 0))
        
        // Step 6: Unbind device (release claim)
        try mockDeviceClaimManager.releaseDevice(workflowDevice)
        XCTAssertThrowsError(try communicator.validateDeviceClaim(device: workflowDevice))
    }
    
    func testSystemExtensionDeviceDisconnectionRecovery() async throws {
        // Simulate device disconnection during operation
        try await communicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        
        // Configure mock to simulate device disconnection
        let mockInterface = mockIOKitFactory.getCreatedInterfaces().first!
        mockInterface.simulateDeviceDisconnection()
        
        // Attempt transfer should fail with device disconnection error
        let request = createControlTransferRequest()
        
        await XCTAssertThrowsError(try await communicator.executeControlTransfer(device: testDevice, request: request)) { error in
            XCTAssertTrue(error is USBRequestError)
        }
        
        // System should handle gracefully and allow cleanup
        XCTAssertNoThrow(try await communicator.closeUSBInterface(device: testDevice, interfaceNumber: 0))
    }
    
    func testSystemExtensionMultipleDeviceManagement() async throws {
        // Test System Extension managing multiple devices simultaneously
        let managedDevices = [testDevice!, testDevice2!]
        let additionalDevice = createTestDevice(busID: "4-1", deviceID: "5.0", vendorID: 0x4040, productID: 0x5050)
        managedDevices.append(additionalDevice)
        
        // Claim all devices
        try mockDeviceClaimManager.claimDevice(additionalDevice)
        
        // Open interfaces for all devices
        for device in managedDevices {
            try await communicator.openUSBInterface(device: device, interfaceNumber: 0)
            XCTAssertTrue(communicator.isInterfaceOpen(device: device, interfaceNumber: 0))
        }
        
        // Verify all interfaces are managed independently
        XCTAssertEqual(mockIOKitFactory.getCreatedInterfaces().count, managedDevices.count)
        
        // Execute transfers on different devices
        for (index, device) in managedDevices.enumerated() {
            let mockInterface = mockIOKitFactory.getCreatedInterfaces()[index]
            mockInterface.setControlTransferResponse(data: Data([UInt8(index + 1)]), status: .success)
            
            let request = createControlTransferRequest()
            let result = try await communicator.executeControlTransfer(device: device, request: request)
            XCTAssertEqual(result.status, .success)
            XCTAssertEqual(result.data, Data([UInt8(index + 1)]))
        }
        
        // Clean up all devices
        for device in managedDevices {
            try await communicator.closeUSBInterface(device: device, interfaceNumber: 0)
            try mockDeviceClaimManager.releaseDevice(device)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestDevice(busID: String, deviceID: String, vendorID: UInt16, productID: UInt16) -> USBDevice {
        return USBDevice(
            busID: busID,
            deviceID: deviceID,
            vendorID: vendorID,
            productID: productID,
            deviceClass: 9,
            deviceSubClass: 0,
            deviceProtocol: 0,
            speed: .high,
            manufacturerString: "Test Manufacturer",
            productString: "Test Device \(vendorID):\(productID)",
            serialNumberString: "TEST\(vendorID)\(productID)"
        )
    }
    
    private func createControlTransferRequest(seqnum: UInt32 = 1, endpoint: UInt8 = 0x00) -> USBRequestBlock {
        let setupPacket = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00]) // GET_DESCRIPTOR
        
        return USBRequestBlock(
            seqnum: seqnum,
            devid: 1,
            direction: .in,
            endpoint: endpoint,
            transferType: .control,
            transferFlags: 0,
            bufferLength: 18,
            setupPacket: setupPacket,
            transferBuffer: nil,
            timeout: 5000
        )
    }
    
    private func createBulkTransferRequest(seqnum: UInt32 = 2, endpoint: UInt8 = 0x81) -> USBRequestBlock {
        return USBRequestBlock(
            seqnum: seqnum,
            devid: 1,
            direction: .in,
            endpoint: endpoint,
            transferType: .bulk,
            transferFlags: 0,
            bufferLength: 512,
            transferBuffer: nil,
            timeout: 5000
        )
    }
    
    private func createInterruptTransferRequest(seqnum: UInt32 = 3, endpoint: UInt8 = 0x83) -> USBRequestBlock {
        return USBRequestBlock(
            seqnum: seqnum,
            devid: 1,
            direction: .in,
            endpoint: endpoint,
            transferType: .interrupt,
            transferFlags: 0,
            bufferLength: 64,
            transferBuffer: nil,
            timeout: 5000
        )
    }
}

// MARK: - Mock Device Claim Manager

/// Mock device claim manager for testing
private class MockDeviceClaimManager: DeviceClaimManager {
    private var claimedDevices: Set<String> = []
    private let lock = NSLock()
    
    func claimDevice(_ device: USBDevice) throws -> Bool {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        lock.lock()
        defer { lock.unlock() }
        
        claimedDevices.insert(deviceID)
        return true
    }
    
    func releaseDevice(_ device: USBDevice) throws {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        lock.lock()
        defer { lock.unlock() }
        
        claimedDevices.remove(deviceID)
    }
    
    func isDeviceClaimed(deviceID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        return claimedDevices.contains(deviceID)
    }
}

// MARK: - Mock IOKit Interface Factory

/// Mock IOKit interface factory for testing
private class MockIOKitInterfaceFactory: IOKitInterfaceFactory {
    private var createdInterfaces: [MockIOKitUSBInterfaceWrapper] = []
    private let lock = NSLock()
    
    // Configuration for testing
    var shouldFailInterfaceCreation = false
    var interfaceCreationError: Error = USBRequestError.deviceNotAvailable
    var interfaceFailureMode: InterfaceOperation?
    var interfaceFailureError: Error = USBRequestError.deviceNotAvailable
    
    enum InterfaceOperation {
        case open
        case close
    }
    
    func createIOKitUSBInterface(device: USBDevice, interfaceNumber: UInt8) throws -> IOKitUSBInterface {
        lock.lock()
        defer { lock.unlock() }
        
        if shouldFailInterfaceCreation {
            throw interfaceCreationError
        }
        
        let wrapper = MockIOKitUSBInterfaceWrapper(device: device, interfaceNumber: interfaceNumber)
        
        // Configure failure mode if set
        if let failureMode = interfaceFailureMode {
            wrapper.configureFailure(failureMode, error: interfaceFailureError)
        }
        
        createdInterfaces.append(wrapper)
        return wrapper
    }
    
    func getCreatedInterfaces() -> [MockIOKitUSBInterfaceWrapper] {
        lock.lock()
        defer { lock.unlock() }
        
        return Array(createdInterfaces)
    }
    
    func configureInterfaceFailure(_ operation: InterfaceOperation, error: Error) {
        self.interfaceFailureMode = operation
        self.interfaceFailureError = error
    }
    
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        createdInterfaces.removeAll()
        shouldFailInterfaceCreation = false
        interfaceFailureMode = nil
    }
}

// MARK: - Mock IOKit USB Interface Wrapper

/// Wrapper for MockIOKitUSBInterface that conforms to IOKitUSBInterface protocol
private class MockIOKitUSBInterfaceWrapper: IOKitUSBInterface {
    private let mockInterface: MockIOKitUSBInterface
    private var failureMode: MockIOKitInterfaceFactory.InterfaceOperation?
    private var failureError: Error?
    
    var isOpen: Bool {
        return mockInterface.isOpen
    }
    
    init(device: USBDevice, interfaceNumber: UInt8) {
        self.mockInterface = MockIOKitUSBInterface(device: device, interfaceNumber: interfaceNumber)
    }
    
    func configureFailure(_ operation: MockIOKitInterfaceFactory.InterfaceOperation, error: Error) {
        self.failureMode = operation
        self.failureError = error
    }
    
    func open() throws {
        if failureMode == .open, let error = failureError {
            throw error
        }
        try mockInterface.open()
    }
    
    func close() throws {
        if failureMode == .close, let error = failureError {
            throw error
        }
        try mockInterface.close()
    }
    
    func executeControlTransfer(endpoint: UInt8, setupPacket: Data, transferBuffer: Data?, timeout: UInt32) async throws -> USBTransferResult {
        return try await mockInterface.executeControlTransfer(
            endpoint: endpoint,
            setupPacket: setupPacket,
            transferBuffer: transferBuffer,
            timeout: timeout
        )
    }
    
    func executeBulkTransfer(endpoint: UInt8, data: Data?, bufferLength: UInt32, timeout: UInt32) async throws -> USBTransferResult {
        return try await mockInterface.executeBulkTransfer(
            endpoint: endpoint,
            data: data,
            bufferLength: bufferLength,
            timeout: timeout
        )
    }
    
    func executeInterruptTransfer(endpoint: UInt8, data: Data?, bufferLength: UInt32, timeout: UInt32) async throws -> USBTransferResult {
        return try await mockInterface.executeInterruptTransfer(
            endpoint: endpoint,
            data: data,
            bufferLength: bufferLength,
            timeout: timeout
        )
    }
    
    func executeIsochronousTransfer(endpoint: UInt8, data: Data?, bufferLength: UInt32, startFrame: UInt32, numberOfPackets: UInt32) async throws -> USBTransferResult {
        return try await mockInterface.executeIsochronousTransfer(
            endpoint: endpoint,
            data: data,
            bufferLength: bufferLength,
            startFrame: startFrame,
            numberOfPackets: numberOfPackets
        )
    }
    
    // Forward mock interface configuration methods
    func setControlTransferResponse(data: Data?, status: USBIPDCore.USBStatus, actualLength: UInt32? = nil) {
        mockInterface.setControlTransferResponse(data: data, status: status, actualLength: actualLength)
    }
    
    func setBulkTransferResponse(data: Data?, status: USBIPDCore.USBStatus, actualLength: UInt32? = nil) {
        mockInterface.setBulkTransferResponse(data: data, status: status, actualLength: actualLength)
    }
    
    func setInterruptTransferResponse(data: Data?, status: USBIPDCore.USBStatus, actualLength: UInt32? = nil) {
        mockInterface.setInterruptTransferResponse(data: data, status: status, actualLength: actualLength)
    }
    
    func setIsochronousTransferResponse(data: Data?, status: USBIPDCore.USBStatus, actualLength: UInt32? = nil, errorCount: UInt32 = 0) {
        mockInterface.setIsochronousTransferResponse(data: data, status: status, actualLength: actualLength, errorCount: errorCount)
    }
    
    func wasOperationCalled(_ operation: String) -> Bool {
        return mockInterface.wasOperationCalled(operation)
    }
    
    func simulateDeviceDisconnection() {
        mockInterface.simulateDeviceDisconnection()
    }
}

// MARK: - IOKit Interface Factory Protocol

/// Protocol for creating IOKit USB interfaces (for dependency injection)
protocol IOKitInterfaceFactory {
    func createIOKitUSBInterface(device: USBDevice, interfaceNumber: UInt8) throws -> IOKitUSBInterface
}

/// Default IOKit interface factory that creates real IOKit interfaces
private class DefaultIOKitInterfaceFactory: IOKitInterfaceFactory {
    func createIOKitUSBInterface(device: USBDevice, interfaceNumber: UInt8) throws -> IOKitUSBInterface {
        return try IOKitUSBInterface(device: device, interfaceNumber: interfaceNumber)
    }
}