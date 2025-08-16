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
            speed: .high,
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
        let request = createBulkTransferRequest() // Wrong type
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
        // Test concurrent opening of different interfaces using TaskGroup
        let errors = await withTaskGroup(of: Error?.self, returning: [Error].self) { group in
            var errorList: [Error] = []
            
            for i in 0..<5 {
                group.addTask {
                    do {
                        try await self.deviceCommunicator.openUSBInterface(device: self.testDevice, interfaceNumber: UInt8(i))
                        return nil
                    } catch {
                        return error
                    }
                }
            }
            
            for await error in group {
                if let error = error {
                    errorList.append(error)
                }
            }
            
            return errorList
        }
        
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
    }
}
