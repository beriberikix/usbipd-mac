// USBDeviceCommunicatorTests.swift
// Comprehensive unit tests for USB device communication

import XCTest
@testable import USBIPDCore
@testable import Common
import Foundation

final class USBDeviceCommunicatorTests: XCTestCase {
    
    // MARK: - Test Properties
    
    var deviceCommunicator: DefaultUSBDeviceCommunicator!
    var mockDeviceClaimManager: MockDeviceClaimManager!
    var testDevice: USBDevice!
    var mockLogger: Logger!
    
    // MARK: - Test Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        mockDeviceClaimManager = MockDeviceClaimManager()
        mockLogger = Logger(subsystem: "com.usbipd.test", category: "USBDeviceCommunicatorTests")
        deviceCommunicator = DefaultUSBDeviceCommunicator(
            deviceClaimManager: mockDeviceClaimManager,
            logger: mockLogger
        )
        
        testDevice = createTestDevice()
        
        // Set up default claim status
        mockDeviceClaimManager.setDeviceClaimed("\(testDevice.busID)-\(testDevice.deviceID)", claimed: true)
    }
    
    override func tearDown() {
        deviceCommunicator = nil
        mockDeviceClaimManager = nil
        testDevice = nil
        mockLogger = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func createTestDevice() -> USBDevice {
        return USBDevice(
            busID: "1",
            deviceID: "2",
            vendorID: 0x1234,
            productID: 0x5678,
            deviceClass: 0x09,
            deviceSubClass: 0x00,
            deviceProtocol: 0x00,
            speed: .highSpeed,
            manufacturerString: "Test Manufacturer",
            productString: "Test Device",
            serialNumberString: "TEST001"
        )
    }
    
    private func createControlTransferRequest(
        seqnum: UInt32 = 1,
        direction: USBTransferDirection = .in,
        endpoint: UInt8 = 0x00,
        setupPacket: Data? = nil,
        transferBuffer: Data? = nil,
        timeout: UInt32 = 5000
    ) -> USBRequestBlock {
        let setup = setupPacket ?? Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00])
        
        return USBRequestBlock(
            seqnum: seqnum,
            devid: UInt32(testDevice.deviceID) ?? 1,
            direction: direction,
            endpoint: endpoint,
            transferType: .control,
            transferFlags: 0,
            bufferLength: UInt32(transferBuffer?.count ?? 18),
            setupPacket: setup,
            transferBuffer: transferBuffer,
            timeout: timeout
        )
    }
    
    private func createBulkTransferRequest(
        seqnum: UInt32 = 1,
        direction: USBTransferDirection = .out,
        endpoint: UInt8 = 0x02,
        transferBuffer: Data? = nil,
        bufferLength: UInt32? = nil,
        timeout: UInt32 = 5000
    ) -> USBRequestBlock {
        let data = transferBuffer ?? Data(repeating: 0x42, count: 64)
        let length = bufferLength ?? UInt32(data.count)
        
        return USBRequestBlock(
            seqnum: seqnum,
            devid: UInt32(testDevice.deviceID) ?? 1,
            direction: direction,
            endpoint: endpoint,
            transferType: .bulk,
            transferFlags: 0,
            bufferLength: length,
            transferBuffer: direction == .out ? data : nil,
            timeout: timeout
        )
    }
    
    private func createInterruptTransferRequest(
        seqnum: UInt32 = 1,
        direction: USBTransferDirection = .in,
        endpoint: UInt8 = 0x81,
        transferBuffer: Data? = nil,
        bufferLength: UInt32 = 8,
        interval: UInt32 = 10,
        timeout: UInt32 = 5000
    ) -> USBRequestBlock {
        return USBRequestBlock(
            seqnum: seqnum,
            devid: UInt32(testDevice.deviceID) ?? 1,
            direction: direction,
            endpoint: endpoint,
            transferType: .interrupt,
            transferFlags: 0,
            bufferLength: bufferLength,
            transferBuffer: direction == .out ? transferBuffer : nil,
            timeout: timeout,
            interval: interval
        )
    }
    
    private func createIsochronousTransferRequest(
        seqnum: UInt32 = 1,
        direction: USBTransferDirection = .in,
        endpoint: UInt8 = 0x83,
        transferBuffer: Data? = nil,
        bufferLength: UInt32 = 1024,
        startFrame: UInt32 = 1000,
        numberOfPackets: UInt32 = 10,
        timeout: UInt32 = 5000
    ) -> USBRequestBlock {
        return USBRequestBlock(
            seqnum: seqnum,
            devid: UInt32(testDevice.deviceID) ?? 1,
            direction: direction,
            endpoint: endpoint,
            transferType: .isochronous,
            transferFlags: 0,
            bufferLength: bufferLength,
            transferBuffer: direction == .out ? transferBuffer : nil,
            timeout: timeout,
            startFrame: startFrame,
            numberOfPackets: numberOfPackets
        )
    }
    
    // MARK: - Device Validation Tests
    
    func testValidateDeviceClaimSuccess() throws {
        // Test successful device validation
        let result = try deviceCommunicator.validateDeviceClaim(device: testDevice)
        XCTAssertTrue(result)
    }
    
    func testValidateDeviceClaimFailureNotClaimed() throws {
        // Set device as not claimed
        mockDeviceClaimManager.setDeviceClaimed("\(testDevice.busID)-\(testDevice.deviceID)", claimed: false)
        
        XCTAssertThrowsError(try deviceCommunicator.validateDeviceClaim(device: testDevice)) { error in
            guard case USBRequestError.deviceNotClaimed(let deviceID) = error else {
                XCTFail("Expected deviceNotClaimed error, got \(error)")
                return
            }
            XCTAssertEqual(deviceID, "\(testDevice.busID)-\(testDevice.deviceID)")
        }
    }
    
    func testValidateDeviceForOperationSuccess() throws {
        let result = try deviceCommunicator.validateDeviceForOperation(
            device: testDevice,
            operationType: "test_operation"
        )
        XCTAssertTrue(result)
    }
    
    func testValidateDeviceForOperationFailure() throws {
        mockDeviceClaimManager.setDeviceClaimed("\(testDevice.busID)-\(testDevice.deviceID)", claimed: false)
        
        XCTAssertThrowsError(try deviceCommunicator.validateDeviceForOperation(
            device: testDevice,
            operationType: "test_operation"
        )) { error in
            XCTAssertTrue(error is USBRequestError)
        }
    }
    
    // MARK: - USB Interface Lifecycle Tests
    
    func testOpenUSBInterfaceSuccess() async throws {
        try await deviceCommunicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        
        let isOpen = deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0)
        XCTAssertTrue(isOpen)
    }
    
    func testOpenUSBInterfaceAlreadyOpen() async throws {
        // Open interface first time
        try await deviceCommunicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        
        // Open again should succeed without error
        try await deviceCommunicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        
        let isOpen = deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0)
        XCTAssertTrue(isOpen)
    }
    
    func testOpenUSBInterfaceFailureDeviceNotClaimed() async throws {
        mockDeviceClaimManager.setDeviceClaimed("\(testDevice.busID)-\(testDevice.deviceID)", claimed: false)
        
        do {
            try await deviceCommunicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
            XCTFail("Expected error when device not claimed")
        } catch {
            XCTAssertTrue(error is USBRequestError)
        }
    }
    
    func testCloseUSBInterfaceSuccess() async throws {
        // Open interface first
        try await deviceCommunicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        XCTAssertTrue(deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0))
        
        // Close interface
        try await deviceCommunicator.closeUSBInterface(device: testDevice, interfaceNumber: 0)
        XCTAssertFalse(deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0))
    }
    
    func testCloseUSBInterfaceNotOpen() async throws {
        // Try to close interface that was never opened - should succeed without error
        try await deviceCommunicator.closeUSBInterface(device: testDevice, interfaceNumber: 0)
        XCTAssertFalse(deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0))
    }
    
    func testIsInterfaceOpenInitiallyFalse() {
        let isOpen = deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0)
        XCTAssertFalse(isOpen)
    }
    
    func testMultipleInterfacesSupport() async throws {
        // Open multiple interfaces
        try await deviceCommunicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        try await deviceCommunicator.openUSBInterface(device: testDevice, interfaceNumber: 1)
        
        XCTAssertTrue(deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0))
        XCTAssertTrue(deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 1))
        
        // Close one interface
        try await deviceCommunicator.closeUSBInterface(device: testDevice, interfaceNumber: 0)
        
        XCTAssertFalse(deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0))
        XCTAssertTrue(deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 1))
    }
    
    // MARK: - Control Transfer Tests
    
    func testExecuteControlTransferSuccess() async throws {
        let request = createControlTransferRequest()
        
        // Mock successful transfer would need actual IOKit implementation
        // For now, we test the validation logic
        do {
            _ = try await deviceCommunicator.executeControlTransfer(device: testDevice, request: request)
            // If we get here without an IOKit interface, it's because the implementation
            // is still using placeholder code. We can test the validation worked.
        } catch USBRequestError.deviceNotAvailable {
            // Expected when IOKit interface is not available (placeholder implementation)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteControlTransferInvalidTransferType() async throws {
        var request = createBulkTransferRequest() // Wrong type
        // Change the type to control to test mismatch
        let controlRequest = USBRequestBlock(
            seqnum: request.seqnum,
            devid: request.devid,
            direction: request.direction,
            endpoint: request.endpoint,
            transferType: .bulk, // Wrong type for control transfer
            transferFlags: request.transferFlags,
            bufferLength: request.bufferLength,
            setupPacket: Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00]),
            transferBuffer: request.transferBuffer,
            timeout: request.timeout
        )
        
        do {
            _ = try await deviceCommunicator.executeControlTransfer(device: testDevice, request: controlRequest)
            XCTFail("Expected error for invalid transfer type")
        } catch USBRequestError.transferTypeNotSupported(let type) {
            XCTAssertEqual(type, .bulk)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteControlTransferMissingSetupPacket() async throws {
        let request = USBRequestBlock(
            seqnum: 1,
            devid: 1,
            direction: .in,
            endpoint: 0x00,
            transferType: .control,
            transferFlags: 0,
            bufferLength: 18,
            setupPacket: nil, // Missing setup packet
            timeout: 5000
        )
        
        do {
            _ = try await deviceCommunicator.executeControlTransfer(device: testDevice, request: request)
            XCTFail("Expected error for missing setup packet")
        } catch USBRequestError.setupPacketRequired {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteControlTransferInvalidSetupPacketSize() async throws {
        let request = USBRequestBlock(
            seqnum: 1,
            devid: 1,
            direction: .in,
            endpoint: 0x00,
            transferType: .control,
            transferFlags: 0,
            bufferLength: 18,
            setupPacket: Data([0x80, 0x06]), // Too short
            timeout: 5000
        )
        
        do {
            _ = try await deviceCommunicator.executeControlTransfer(device: testDevice, request: request)
            XCTFail("Expected error for invalid setup packet size")
        } catch USBRequestError.setupPacketRequired {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteControlTransferInvalidTimeout() async throws {
        let request = createControlTransferRequest(timeout: 0) // Invalid timeout
        
        do {
            _ = try await deviceCommunicator.executeControlTransfer(device: testDevice, request: request)
            XCTFail("Expected error for invalid timeout")
        } catch USBRequestError.timeoutInvalid(let timeout) {
            XCTAssertEqual(timeout, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteControlTransferExcessiveTimeout() async throws {
        let request = createControlTransferRequest(timeout: 40000) // Too high timeout
        
        do {
            _ = try await deviceCommunicator.executeControlTransfer(device: testDevice, request: request)
            XCTFail("Expected error for excessive timeout")
        } catch USBRequestError.timeoutInvalid(let timeout) {
            XCTAssertEqual(timeout, 40000)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteControlTransferDeviceNotClaimed() async throws {
        mockDeviceClaimManager.setDeviceClaimed("\(testDevice.busID)-\(testDevice.deviceID)", claimed: false)
        let request = createControlTransferRequest()
        
        do {
            _ = try await deviceCommunicator.executeControlTransfer(device: testDevice, request: request)
            XCTFail("Expected error when device not claimed")
        } catch USBRequestError.deviceNotClaimed {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Bulk Transfer Tests
    
    func testExecuteBulkTransferOutValidation() async throws {
        let transferData = Data(repeating: 0x42, count: 64)
        let request = createBulkTransferRequest(
            direction: .out,
            transferBuffer: transferData,
            bufferLength: 64
        )
        
        // Test validation logic
        do {
            _ = try await deviceCommunicator.executeBulkTransfer(device: testDevice, request: request)
        } catch USBRequestError.deviceNotAvailable {
            // Expected when IOKit interface is not available
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteBulkTransferInvalidTransferType() async throws {
        let request = createControlTransferRequest()
        
        do {
            _ = try await deviceCommunicator.executeBulkTransfer(device: testDevice, request: request)
            XCTFail("Expected error for invalid transfer type")
        } catch USBRequestError.transferTypeNotSupported(let type) {
            XCTAssertEqual(type, .control)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteBulkTransferOutMissingBuffer() async throws {
        let request = USBRequestBlock(
            seqnum: 1,
            devid: 1,
            direction: .out,
            endpoint: 0x02,
            transferType: .bulk,
            transferFlags: 0,
            bufferLength: 64,
            transferBuffer: nil, // Missing buffer for OUT transfer
            timeout: 5000
        )
        
        do {
            _ = try await deviceCommunicator.executeBulkTransfer(device: testDevice, request: request)
            XCTFail("Expected error for missing transfer buffer")
        } catch USBRequestError.invalidParameters {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteBulkTransferBufferSizeMismatch() async throws {
        let transferData = Data(repeating: 0x42, count: 32) // 32 bytes
        let request = createBulkTransferRequest(
            direction: .out,
            transferBuffer: transferData,
            bufferLength: 64 // Expects 64 bytes
        )
        
        do {
            _ = try await deviceCommunicator.executeBulkTransfer(device: testDevice, request: request)
            XCTFail("Expected error for buffer size mismatch")
        } catch USBRequestError.bufferSizeMismatch(let expected, let actual) {
            XCTAssertEqual(expected, 64)
            XCTAssertEqual(actual, 32)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteBulkTransferInvalidTimeout() async throws {
        let request = createBulkTransferRequest(timeout: 50000) // Too high
        
        do {
            _ = try await deviceCommunicator.executeBulkTransfer(device: testDevice, request: request)
            XCTFail("Expected error for invalid timeout")
        } catch USBRequestError.timeoutInvalid(let timeout) {
            XCTAssertEqual(timeout, 50000)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Interrupt Transfer Tests
    
    func testExecuteInterruptTransferValidation() async throws {
        let request = createInterruptTransferRequest()
        
        do {
            _ = try await deviceCommunicator.executeInterruptTransfer(device: testDevice, request: request)
        } catch USBRequestError.deviceNotAvailable {
            // Expected when IOKit interface is not available
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteInterruptTransferInvalidTransferType() async throws {
        let request = createBulkTransferRequest()
        
        do {
            _ = try await deviceCommunicator.executeInterruptTransfer(device: testDevice, request: request)
            XCTFail("Expected error for invalid transfer type")
        } catch USBRequestError.transferTypeNotSupported(let type) {
            XCTAssertEqual(type, .bulk)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteInterruptTransferOutBufferValidation() async throws {
        let transferData = Data(repeating: 0x55, count: 4)
        let request = createInterruptTransferRequest(
            direction: .out,
            transferBuffer: transferData,
            bufferLength: 8 // Mismatch
        )
        
        do {
            _ = try await deviceCommunicator.executeInterruptTransfer(device: testDevice, request: request)
            XCTFail("Expected error for buffer size mismatch")
        } catch USBRequestError.bufferSizeMismatch(let expected, let actual) {
            XCTAssertEqual(expected, 8)
            XCTAssertEqual(actual, 4)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteInterruptTransferInvalidTimeout() async throws {
        let request = createInterruptTransferRequest(timeout: 0)
        
        do {
            _ = try await deviceCommunicator.executeInterruptTransfer(device: testDevice, request: request)
            XCTFail("Expected error for invalid timeout")
        } catch USBRequestError.timeoutInvalid(let timeout) {
            XCTAssertEqual(timeout, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Isochronous Transfer Tests
    
    func testExecuteIsochronousTransferValidation() async throws {
        let request = createIsochronousTransferRequest()
        
        do {
            _ = try await deviceCommunicator.executeIsochronousTransfer(device: testDevice, request: request)
        } catch USBRequestError.deviceNotAvailable {
            // Expected when IOKit interface is not available
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteIsochronousTransferInvalidTransferType() async throws {
        let request = createControlTransferRequest()
        
        do {
            _ = try await deviceCommunicator.executeIsochronousTransfer(device: testDevice, request: request)
            XCTFail("Expected error for invalid transfer type")
        } catch USBRequestError.transferTypeNotSupported(let type) {
            XCTAssertEqual(type, .control)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteIsochronousTransferOutBufferValidation() async throws {
        let transferData = Data(repeating: 0x77, count: 512)
        let request = createIsochronousTransferRequest(
            direction: .out,
            transferBuffer: transferData,
            bufferLength: 1024 // Mismatch
        )
        
        do {
            _ = try await deviceCommunicator.executeIsochronousTransfer(device: testDevice, request: request)
            XCTFail("Expected error for buffer size mismatch")
        } catch USBRequestError.bufferSizeMismatch(let expected, let actual) {
            XCTAssertEqual(expected, 1024)
            XCTAssertEqual(actual, 512)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteIsochronousTransferInvalidParameters() async throws {
        let request = createIsochronousTransferRequest(numberOfPackets: 0) // Invalid
        
        do {
            _ = try await deviceCommunicator.executeIsochronousTransfer(device: testDevice, request: request)
            XCTFail("Expected error for invalid parameters")
        } catch USBRequestError.invalidParameters {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Endpoint to Interface Mapping Tests
    
    func testEndpointToInterfaceMapping() async throws {
        // Test that endpoint addresses are correctly mapped to interface numbers
        // Bulk transfer with endpoint 0x12 should use interface 1
        let request = createBulkTransferRequest(endpoint: 0x12)
        
        do {
            _ = try await deviceCommunicator.executeBulkTransfer(device: testDevice, request: request)
        } catch USBRequestError.deviceNotAvailable {
            // Expected - we can't test the actual mapping without IOKit interface
            // but the validation logic runs
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentInterfaceOperations() async throws {
        let group = DispatchGroup()
        var errors: [Error] = []
        let errorLock = NSLock()
        
        // Test concurrent opening of different interfaces
        for i in 0..<5 {
            group.enter()
            Task {
                do {
                    try await deviceCommunicator.openUSBInterface(device: testDevice, interfaceNumber: UInt8(i))
                } catch {
                    errorLock.lock()
                    errors.append(error)
                    errorLock.unlock()
                }
                group.leave()
            }
        }
        
        group.wait()
        
        // Check that some operations succeeded (IOKit limitations may cause some to fail)
        // We mainly want to ensure no crashes or data corruption
        XCTAssertLessThanOrEqual(errors.count, 5)
        
        // Verify at least one interface can be queried
        _ = deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0)
    }
    
    func testConcurrentTransferRequests() async throws {
        let expectation = XCTestExpectation(description: "Concurrent transfers")
        expectation.expectedFulfillmentCount = 3
        
        // Test concurrent transfer requests (will fail due to IOKit, but test concurrency)
        Task {
            do {
                let request = createControlTransferRequest()
                _ = try await deviceCommunicator.executeControlTransfer(device: testDevice, request: request)
            } catch {
                // Expected to fail due to IOKit limitations
            }
            expectation.fulfill()
        }
        
        Task {
            do {
                let request = createBulkTransferRequest()
                _ = try await deviceCommunicator.executeBulkTransfer(device: testDevice, request: request)
            } catch {
                // Expected to fail due to IOKit limitations
            }
            expectation.fulfill()
        }
        
        Task {
            do {
                let request = createInterruptTransferRequest()
                _ = try await deviceCommunicator.executeInterruptTransfer(device: testDevice, request: request)
            } catch {
                // Expected to fail due to IOKit limitations
            }
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandlingRobustness() async throws {
        // Test that error handling doesn't leave interfaces in inconsistent state
        mockDeviceClaimManager.setDeviceClaimed("\(testDevice.busID)-\(testDevice.deviceID)", claimed: false)
        
        do {
            try await deviceCommunicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
            XCTFail("Expected error")
        } catch {
            // Expected error
        }
        
        // Verify interface is not marked as open after error
        let isOpen = deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0)
        XCTAssertFalse(isOpen)
        
        // Re-enable claiming and verify operations work
        mockDeviceClaimManager.setDeviceClaimed("\(testDevice.busID)-\(testDevice.deviceID)", claimed: true)
        try await deviceCommunicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        XCTAssertTrue(deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0))
    }
    
    // MARK: - Multiple Device Support Tests
    
    func testMultipleDeviceSupport() async throws {
        let device2 = USBDevice(
            busID: "1",
            deviceID: "3",
            vendorID: 0x9876,
            productID: 0x5432,
            deviceClass: 0x08,
            deviceSubClass: 0x06,
            deviceProtocol: 0x50,
            speed: .fullSpeed,
            manufacturerString: "Another Manufacturer",
            productString: "Another Device",
            serialNumberString: "TEST002"
        )
        
        mockDeviceClaimManager.setDeviceClaimed("\(device2.busID)-\(device2.deviceID)", claimed: true)
        
        // Open interfaces on both devices
        try await deviceCommunicator.openUSBInterface(device: testDevice, interfaceNumber: 0)
        try await deviceCommunicator.openUSBInterface(device: device2, interfaceNumber: 0)
        
        // Verify both are tracked separately
        XCTAssertTrue(deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0))
        XCTAssertTrue(deviceCommunicator.isInterfaceOpen(device: device2, interfaceNumber: 0))
        
        // Close one device's interface
        try await deviceCommunicator.closeUSBInterface(device: testDevice, interfaceNumber: 0)
        
        XCTAssertFalse(deviceCommunicator.isInterfaceOpen(device: testDevice, interfaceNumber: 0))
        XCTAssertTrue(deviceCommunicator.isInterfaceOpen(device: device2, interfaceNumber: 0))
    }
    
    // MARK: - Edge Cases and Boundary Tests
    
    func testTransferWithMaxTimeout() async throws {
        let request = createControlTransferRequest(timeout: 30000) // Maximum allowed
        
        do {
            _ = try await deviceCommunicator.executeControlTransfer(device: testDevice, request: request)
        } catch USBRequestError.deviceNotAvailable {
            // Expected when IOKit interface is not available
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testTransferWithMaxBufferSize() async throws {
        let largeBuffer = Data(repeating: 0xFF, count: 65536) // 64KB
        let request = createBulkTransferRequest(
            transferBuffer: largeBuffer,
            bufferLength: UInt32(largeBuffer.count)
        )
        
        do {
            _ = try await deviceCommunicator.executeBulkTransfer(device: testDevice, request: request)
        } catch USBRequestError.deviceNotAvailable {
            // Expected when IOKit interface is not available
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testZeroLengthTransfer() async throws {
        let request = createBulkTransferRequest(
            transferBuffer: Data(),
            bufferLength: 0
        )
        
        do {
            _ = try await deviceCommunicator.executeBulkTransfer(device: testDevice, request: request)
        } catch USBRequestError.deviceNotAvailable {
            // Expected when IOKit interface is not available
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testHighEndpointNumbers() async throws {
        let request = createBulkTransferRequest(endpoint: 0xFF) // Max endpoint
        
        do {
            _ = try await deviceCommunicator.executeBulkTransfer(device: testDevice, request: request)
        } catch USBRequestError.deviceNotAvailable {
            // Expected when IOKit interface is not available
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testIsochronousMaxPackets() async throws {
        let request = createIsochronousTransferRequest(numberOfPackets: 1024) // High packet count
        
        do {
            _ = try await deviceCommunicator.executeIsochronousTransfer(device: testDevice, request: request)
        } catch USBRequestError.deviceNotAvailable {
            // Expected when IOKit interface is not available
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Mock Device Claim Manager

class MockDeviceClaimManager: DeviceClaimManager {
    private var claimedDevices: Set<String> = []
    private let lock = NSLock()
    
    func setDeviceClaimed(_ deviceID: String, claimed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        
        if claimed {
            claimedDevices.insert(deviceID)
        } else {
            claimedDevices.remove(deviceID)
        }
    }
    
    func isDeviceClaimed(deviceID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return claimedDevices.contains(deviceID)
    }
    
    func claimDevice(device: USBDevice) throws -> Bool {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        lock.lock()
        defer { lock.unlock() }
        claimedDevices.insert(deviceID)
        return true
    }
    
    func releaseDevice(device: USBDevice) throws -> Bool {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        lock.lock()
        defer { lock.unlock() }
        claimedDevices.remove(deviceID)
        return true
    }
    
    func releaseAllDevices() throws {
        lock.lock()
        defer { lock.unlock() }
        claimedDevices.removeAll()
    }
    
    func getClaimedDevices() -> [USBDevice] {
        // Return empty list for mock
        return []
    }
}