// USBRequestProcessorTests.swift
// Integration tests for USB request processors with end-to-end validation

import XCTest
@testable import USBIPDCore
@testable import Common
import Foundation

final class USBRequestProcessorTests: XCTestCase {
    
    // MARK: - Test Properties
    
    var submitProcessor: USBSubmitProcessor!
    var unlinkProcessor: USBUnlinkProcessor!
    var mockDeviceCommunicator: MockUSBDeviceCommunicator!
    var urbTracker: URBTracker!
    var testDevice: USBDevice!
    
    // MARK: - Test Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        mockDeviceCommunicator = MockUSBDeviceCommunicator()
        urbTracker = URBTracker()
        
        submitProcessor = USBSubmitProcessor(deviceCommunicator: mockDeviceCommunicator)
        unlinkProcessor = USBUnlinkProcessor(submitProcessor: submitProcessor)
        
        testDevice = createTestDevice()
        
        // Configure mock device communicator
        mockDeviceCommunicator.reset()
        mockDeviceCommunicator.setShouldSucceed(true)
    }
    
    override func tearDown() {
        submitProcessor = nil
        unlinkProcessor = nil
        mockDeviceCommunicator = nil
        urbTracker = nil
        testDevice = nil
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
    
    private func createUSBSubmitRequestData(
        seqnum: UInt32 = 1,
        devid: UInt32 = 1,
        direction: UInt32 = 1, // IN
        endpoint: UInt32 = 0x81,
        transferFlags: UInt32 = 0,
        bufferLength: UInt32 = 64,
        startFrame: UInt32 = 0,
        numberOfPackets: UInt32 = 0,
        interval: UInt32 = 0,
        setupPacket: Data = Data(count: 8),
        transferBuffer: Data? = nil
    ) throws -> Data {
        let request = USBIPSubmitRequest(
            seqnum: seqnum,
            devid: devid,
            direction: direction,
            ep: endpoint,
            transferFlags: transferFlags,
            transferBufferLength: bufferLength,
            startFrame: startFrame,
            numberOfPackets: numberOfPackets,
            interval: interval,
            setup: setupPacket,
            transferBuffer: transferBuffer
        )
        
        return try request.encode()
    }
    
    private func createUSBUnlinkRequestData(
        seqnum: UInt32 = 2,
        devid: UInt32 = 1,
        direction: UInt32 = 1,
        endpoint: UInt32 = 0x81,
        unlinkSeqnum: UInt32 = 1
    ) throws -> Data {
        let request = USBIPUnlinkRequest(
            seqnum: seqnum,
            devid: devid,
            direction: direction,
            ep: endpoint,
            unlinkSeqnum: unlinkSeqnum
        )
        
        return try request.encode()
    }
    
    // MARK: - USB SUBMIT Request Processing Tests
    
    func testProcessSubmitRequestControlTransferSuccess() async throws {
        // Configure mock for control transfer success
        let responseData = Data([0x12, 0x01, 0x00, 0x02, 0x09, 0x00, 0x00, 0x40]) // Device descriptor
        mockDeviceCommunicator.setControlTransferResponse(responseData)
        
        // Create control transfer request (GET_DESCRIPTOR)
        let setupPacket = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00])
        let requestData = try createUSBSubmitRequestData(
            seqnum: 123,
            devid: 1,
            direction: 1, // IN
            endpoint: 0x00,
            bufferLength: 18,
            setupPacket: setupPacket
        )
        
        // Process the request
        let responseData = try await submitProcessor.processSubmitRequest(requestData)
        
        // Decode and validate response
        let response = try USBIPSubmitResponse.decode(from: responseData)
        XCTAssertEqual(response.seqnum, 123)
        XCTAssertEqual(response.devid, 1)
        XCTAssertEqual(response.direction, 1)
        XCTAssertEqual(response.ep, 0x00)
        XCTAssertEqual(response.status, 0) // Success
        XCTAssertEqual(response.actualLength, UInt32(responseData.count))
        XCTAssertNotNil(response.transferBuffer)
    }
    
    func testProcessSubmitRequestBulkTransferOut() async throws {
        // Configure mock for bulk OUT transfer
        let transferData = Data(repeating: 0x42, count: 512)
        mockDeviceCommunicator.setBulkTransferResponse(Data(), actualLength: 512)
        
        // Create bulk OUT transfer request
        let requestData = try createUSBSubmitRequestData(
            seqnum: 456,
            devid: 1,
            direction: 0, // OUT
            endpoint: 0x02,
            bufferLength: 512,
            transferBuffer: transferData
        )
        
        // Process the request
        let responseData = try await submitProcessor.processSubmitRequest(requestData)
        
        // Decode and validate response
        let response = try USBIPSubmitResponse.decode(from: responseData)
        XCTAssertEqual(response.seqnum, 456)
        XCTAssertEqual(response.direction, 0)
        XCTAssertEqual(response.ep, 0x02)
        XCTAssertEqual(response.status, 0)
        XCTAssertEqual(response.actualLength, 512)
    }
    
    func testProcessSubmitRequestBulkTransferIn() async throws {
        // Configure mock for bulk IN transfer
        let responseData = Data(repeating: 0xCD, count: 256)
        mockDeviceCommunicator.setBulkTransferResponse(responseData)
        
        // Create bulk IN transfer request
        let requestData = try createUSBSubmitRequestData(
            seqnum: 789,
            devid: 1,
            direction: 1, // IN
            endpoint: 0x82,
            bufferLength: 256
        )
        
        // Process the request
        let responseDataEncoded = try await submitProcessor.processSubmitRequest(requestData)
        
        // Decode and validate response
        let response = try USBIPSubmitResponse.decode(from: responseDataEncoded)
        XCTAssertEqual(response.seqnum, 789)
        XCTAssertEqual(response.direction, 1)
        XCTAssertEqual(response.ep, 0x82)
        XCTAssertEqual(response.status, 0)
        XCTAssertEqual(response.actualLength, 256)
        XCTAssertEqual(response.transferBuffer, responseData)
    }
    
    func testProcessSubmitRequestInterruptTransfer() async throws {
        // Configure mock for interrupt transfer
        let responseData = Data([0x01, 0x02, 0x03, 0x04])
        mockDeviceCommunicator.setInterruptTransferResponse(responseData)
        
        // Create interrupt IN transfer request
        let requestData = try createUSBSubmitRequestData(
            seqnum: 101,
            devid: 1,
            direction: 1, // IN
            endpoint: 0x81,
            bufferLength: 8,
            interval: 10
        )
        
        // Process the request
        let responseDataEncoded = try await submitProcessor.processSubmitRequest(requestData)
        
        // Decode and validate response
        let response = try USBIPSubmitResponse.decode(from: responseDataEncoded)
        XCTAssertEqual(response.seqnum, 101)
        XCTAssertEqual(response.ep, 0x81)
        XCTAssertEqual(response.status, 0)
        XCTAssertEqual(response.actualLength, 4)
        XCTAssertEqual(response.transferBuffer, responseData)
    }
    
    func testProcessSubmitRequestIsochronousTransfer() async throws {
        // Configure mock for isochronous transfer
        let responseData = Data(repeating: 0xAB, count: 1024)
        mockDeviceCommunicator.setIsochronousTransferResponse(
            responseData,
            actualLength: 1024,
            errorCount: 0
        )
        
        // Create isochronous IN transfer request
        let requestData = try createUSBSubmitRequestData(
            seqnum: 202,
            devid: 1,
            direction: 1, // IN
            endpoint: 0x83,
            bufferLength: 1024,
            startFrame: 1000,
            numberOfPackets: 8
        )
        
        // Process the request
        let responseDataEncoded = try await submitProcessor.processSubmitRequest(requestData)
        
        // Decode and validate response
        let response = try USBIPSubmitResponse.decode(from: responseDataEncoded)
        XCTAssertEqual(response.seqnum, 202)
        XCTAssertEqual(response.ep, 0x83)
        XCTAssertEqual(response.status, 0)
        XCTAssertEqual(response.actualLength, 1024)
        XCTAssertEqual(response.startFrame, 1000)
        XCTAssertEqual(response.numberOfPackets, 8)
        XCTAssertEqual(response.errorCount, 0)
        XCTAssertEqual(response.transferBuffer, responseData)
    }
    
    // MARK: - USB SUBMIT Error Handling Tests
    
    func testProcessSubmitRequestTimeout() async throws {
        // Configure mock to simulate timeout
        mockDeviceCommunicator.simulateTimeout()
        
        let requestData = try createUSBSubmitRequestData(seqnum: 999)
        
        // Process the request
        let responseData = try await submitProcessor.processSubmitRequest(requestData)
        
        // Decode and validate error response
        let response = try USBIPSubmitResponse.decode(from: responseData)
        XCTAssertEqual(response.seqnum, 999)
        XCTAssertEqual(response.status, USBStatus.timeout.rawValue)
        XCTAssertEqual(response.actualLength, 0)
        XCTAssertNil(response.transferBuffer)
    }
    
    func testProcessSubmitRequestDeviceError() async throws {
        // Configure mock to simulate device error
        mockDeviceCommunicator.simulateDeviceDisconnection()
        
        let requestData = try createUSBSubmitRequestData(seqnum: 888)
        
        // Process the request
        let responseData = try await submitProcessor.processSubmitRequest(requestData)
        
        // Decode and validate error response
        let response = try USBIPSubmitResponse.decode(from: responseData)
        XCTAssertEqual(response.seqnum, 888)
        XCTAssertEqual(response.status, USBStatus.deviceGone.rawValue)
        XCTAssertEqual(response.actualLength, 0)
    }
    
    func testProcessSubmitRequestPartialTransfer() async throws {
        // Configure mock for partial transfer
        let partialData = Data(repeating: 0xEF, count: 100)
        mockDeviceCommunicator.setBulkTransferResponse(
            partialData,
            status: .shortPacket,
            actualLength: 100
        )
        
        let requestData = try createUSBSubmitRequestData(
            seqnum: 777,
            direction: 1, // IN
            endpoint: 0x82,
            bufferLength: 512 // Requested more than received
        )
        
        // Process the request
        let responseDataEncoded = try await submitProcessor.processSubmitRequest(requestData)
        
        // Decode and validate partial response
        let response = try USBIPSubmitResponse.decode(from: responseDataEncoded)
        XCTAssertEqual(response.seqnum, 777)
        XCTAssertEqual(response.status, USBStatus.shortPacket.rawValue)
        XCTAssertEqual(response.actualLength, 100)
        XCTAssertEqual(response.transferBuffer, partialData)
    }
    
    func testProcessSubmitRequestInvalidMessage() async throws {
        // Create invalid message data
        let invalidData = Data([0xFF, 0xFF, 0xFF, 0xFF])
        
        do {
            let _ = try await submitProcessor.processSubmitRequest(invalidData)
            XCTFail("Expected error for invalid message")
        } catch {
            // Expected error
            XCTAssertTrue(error is USBIPProtocolError)
        }
    }
    
    // MARK: - USB UNLINK Request Processing Tests
    
    func testProcessUnlinkRequestSuccess() async throws {
        // First, create and start a SUBMIT request
        let submitRequestData = try createUSBSubmitRequestData(seqnum: 123)
        
        // Start processing the submit request in background (don't await completion)
        let submitTask = Task {
            try await submitProcessor.processSubmitRequest(submitRequestData)
        }
        
        // Give it time to start processing
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Create and process UNLINK request
        let unlinkRequestData = try createUSBUnlinkRequestData(
            seqnum: 124,
            unlinkSeqnum: 123 // Cancel the submit request
        )
        
        let unlinkResponseData = try await unlinkProcessor.processUnlinkRequest(unlinkRequestData)
        
        // Decode and validate unlink response
        let response = try USBIPUnlinkResponse.decode(from: unlinkResponseData)
        XCTAssertEqual(response.seqnum, 124)
        XCTAssertEqual(response.devid, 1)
        XCTAssertEqual(response.direction, 1)
        XCTAssertEqual(response.ep, 0x81)
        
        // Clean up the submit task
        submitTask.cancel()
    }
    
    func testProcessUnlinkRequestNotFound() async throws {
        // Try to unlink a non-existent request
        let unlinkRequestData = try createUSBUnlinkRequestData(
            seqnum: 999,
            unlinkSeqnum: 888 // Non-existent request
        )
        
        let unlinkResponseData = try await unlinkProcessor.processUnlinkRequest(unlinkRequestData)
        
        // Decode and validate response
        let response = try USBIPUnlinkResponse.decode(from: unlinkResponseData)
        XCTAssertEqual(response.seqnum, 999)
        // Status should indicate request not found or already completed
        XCTAssertNotEqual(response.status, 0)
    }
    
    func testProcessUnlinkRequestInvalidMessage() async throws {
        // Create invalid message data
        let invalidData = Data([0xAA, 0xBB, 0xCC, 0xDD])
        
        do {
            let _ = try await unlinkProcessor.processUnlinkRequest(invalidData)
            XCTFail("Expected error for invalid message")
        } catch {
            // Expected error
            XCTAssertTrue(error is USBIPProtocolError)
        }
    }
    
    // MARK: - Concurrent Request Processing Tests
    
    func testConcurrentSubmitRequests() async throws {
        let requestCount = 10
        var tasks: [Task<Data, Error>] = []
        
        // Configure mock for success responses
        mockDeviceCommunicator.setBulkTransferResponse(Data(repeating: 0x55, count: 64))
        
        // Create multiple concurrent SUBMIT requests
        for i in 0..<requestCount {
            let requestData = try createUSBSubmitRequestData(
                seqnum: UInt32(i + 1),
                endpoint: UInt32(0x82),
                bufferLength: 64
            )
            
            let task = Task {
                try await submitProcessor.processSubmitRequest(requestData)
            }
            tasks.append(task)
        }
        
        // Wait for all requests to complete
        var successCount = 0
        var errorCount = 0
        
        for task in tasks {
            do {
                let responseData = try await task.value
                let response = try USBIPSubmitResponse.decode(from: responseData)
                XCTAssertEqual(response.status, 0) // Success
                successCount += 1
            } catch {
                errorCount += 1
            }
        }
        
        // Verify that most requests succeeded
        XCTAssertGreaterThan(successCount, requestCount / 2)
        XCTAssertLessThan(errorCount, requestCount / 2)
    }
    
    func testConcurrentRequestAndUnlinkOperations() async throws {
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = 4
        
        // Configure mock with some latency
        mockDeviceCommunicator.setOperationLatency(50) // 50ms
        mockDeviceCommunicator.setBulkTransferResponse(Data(repeating: 0x77, count: 32))
        
        // Start submit requests
        Task {
            do {
                let requestData = try createUSBSubmitRequestData(seqnum: 501, bufferLength: 32)
                let _ = try await submitProcessor.processSubmitRequest(requestData)
            } catch {
                // May be cancelled by unlink
            }
            expectation.fulfill()
        }
        
        Task {
            do {
                let requestData = try createUSBSubmitRequestData(seqnum: 502, bufferLength: 32)
                let _ = try await submitProcessor.processSubmitRequest(requestData)
            } catch {
                // May be cancelled by unlink
            }
            expectation.fulfill()
        }
        
        // Start unlink requests after a short delay
        Task {
            try await Task.sleep(nanoseconds: 25_000_000) // 25ms
            do {
                let unlinkData = try createUSBUnlinkRequestData(seqnum: 601, unlinkSeqnum: 501)
                let _ = try await unlinkProcessor.processUnlinkRequest(unlinkData)
            } catch {
                // Expected if request already completed
            }
            expectation.fulfill()
        }
        
        Task {
            try await Task.sleep(nanoseconds: 25_000_000) // 25ms
            do {
                let unlinkData = try createUSBUnlinkRequestData(seqnum: 602, unlinkSeqnum: 502)
                let _ = try await unlinkProcessor.processUnlinkRequest(unlinkData)
            } catch {
                // Expected if request already completed
            }
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    // MARK: - URB Lifecycle Management Tests
    
    func testURBTrackingLifecycle() async throws {
        // Test that URBs are properly tracked through their lifecycle
        let initialCount = urbTracker.pendingCount
        
        // Create a URB manually for tracking
        let urb = USBRequestBlock(
            seqnum: 1001,
            devid: 1,
            direction: .in,
            endpoint: 0x81,
            transferType: .bulk,
            transferFlags: 0,
            bufferLength: 128
        )
        
        // Add to tracker
        urbTracker.addPendingURB(urb)
        XCTAssertEqual(urbTracker.pendingCount, initialCount + 1)
        
        // Verify retrieval
        let retrievedURB = urbTracker.getPendingURB(1001)
        XCTAssertNotNil(retrievedURB)
        XCTAssertEqual(retrievedURB?.seqnum, 1001)
        
        // Remove from tracker
        let removedURB = urbTracker.removeCompletedURB(1001)
        XCTAssertNotNil(removedURB)
        XCTAssertEqual(removedURB?.seqnum, 1001)
        XCTAssertEqual(urbTracker.pendingCount, initialCount)
        
        // Verify removal
        let shouldBeNil = urbTracker.getPendingURB(1001)
        XCTAssertNil(shouldBeNil)
    }
    
    func testURBTrackingConcurrentAccess() async throws {
        let expectation = XCTestExpectation(description: "Concurrent URB operations")
        expectation.expectedFulfillmentCount = 10
        
        // Add URBs concurrently
        for i in 0..<5 {
            Task {
                let urb = USBRequestBlock(
                    seqnum: UInt32(2000 + i),
                    devid: 1,
                    direction: .out,
                    endpoint: 0x02,
                    transferType: .bulk,
                    transferFlags: 0,
                    bufferLength: 64
                )
                urbTracker.addPendingURB(urb)
                expectation.fulfill()
            }
        }
        
        // Remove URBs concurrently
        for i in 0..<5 {
            Task {
                // Small delay to allow addition
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms
                let _ = urbTracker.removeCompletedURB(UInt32(2000 + i))
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 3.0)
        
        // Verify final state consistency
        let finalSeqnums = urbTracker.getAllPendingSeqnums()
        let finalCount = urbTracker.pendingCount
        XCTAssertEqual(finalSeqnums.count, finalCount)
    }
    
    // MARK: - End-to-End Integration Tests
    
    func testCompleteUSBOperationFlow() async throws {
        // Configure mock for device descriptor request
        let deviceDescriptor = Data([
            0x12, 0x01, 0x00, 0x02, 0x09, 0x00, 0x00, 0x40,
            0x34, 0x12, 0x78, 0x56, 0x00, 0x01, 0x01, 0x02,
            0x03, 0x01
        ])
        mockDeviceCommunicator.setControlTransferResponse(deviceDescriptor)
        
        // Create GET_DESCRIPTOR control request
        let setupPacket = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00])
        let requestData = try createUSBSubmitRequestData(
            seqnum: 3001,
            devid: 1,
            direction: 1, // IN
            endpoint: 0x00,
            bufferLength: 18,
            setupPacket: setupPacket
        )
        
        // Process the complete operation
        let responseData = try await submitProcessor.processSubmitRequest(requestData)
        
        // Validate complete response
        let response = try USBIPSubmitResponse.decode(from: responseData)
        XCTAssertEqual(response.seqnum, 3001)
        XCTAssertEqual(response.devid, 1)
        XCTAssertEqual(response.direction, 1)
        XCTAssertEqual(response.ep, 0x00)
        XCTAssertEqual(response.status, 0)
        XCTAssertEqual(response.actualLength, UInt32(deviceDescriptor.count))
        
        // Verify descriptor content
        XCTAssertEqual(response.transferBuffer, deviceDescriptor)
        XCTAssertEqual(response.transferBuffer?[0], 0x12) // bLength
        XCTAssertEqual(response.transferBuffer?[1], 0x01) // bDescriptorType
    }
    
    func testCompleteUSBDataTransferFlow() async throws {
        let transferData = Data(0x00...0xFF) // 256 bytes of test data
        
        // Test OUT transfer followed by IN transfer
        mockDeviceCommunicator.setBulkTransferResponse(Data(), actualLength: 256) // OUT response
        
        // Create bulk OUT request
        let outRequestData = try createUSBSubmitRequestData(
            seqnum: 4001,
            direction: 0, // OUT
            endpoint: 0x02,
            bufferLength: 256,
            transferBuffer: transferData
        )
        
        // Process OUT transfer
        let outResponseData = try await submitProcessor.processSubmitRequest(outRequestData)
        let outResponse = try USBIPSubmitResponse.decode(from: outResponseData)
        
        XCTAssertEqual(outResponse.seqnum, 4001)
        XCTAssertEqual(outResponse.direction, 0)
        XCTAssertEqual(outResponse.status, 0)
        XCTAssertEqual(outResponse.actualLength, 256)
        
        // Configure for IN transfer
        let receivedData = Data((0x00...0xFF).reversed()) // Different data
        mockDeviceCommunicator.setBulkTransferResponse(receivedData)
        
        // Create bulk IN request
        let inRequestData = try createUSBSubmitRequestData(
            seqnum: 4002,
            direction: 1, // IN
            endpoint: 0x82,
            bufferLength: 256
        )
        
        // Process IN transfer
        let inResponseData = try await submitProcessor.processSubmitRequest(inRequestData)
        let inResponse = try USBIPSubmitResponse.decode(from: inResponseData)
        
        XCTAssertEqual(inResponse.seqnum, 4002)
        XCTAssertEqual(inResponse.direction, 1)
        XCTAssertEqual(inResponse.status, 0)
        XCTAssertEqual(inResponse.actualLength, 256)
        XCTAssertEqual(inResponse.transferBuffer, receivedData)
    }
    
    // MARK: - Error Recovery Tests
    
    func testErrorRecoveryAfterDeviceError() async throws {
        // First request fails due to device error
        mockDeviceCommunicator.simulateDeviceDisconnection()
        
        let failRequestData = try createUSBSubmitRequestData(seqnum: 5001)
        let failResponseData = try await submitProcessor.processSubmitRequest(failRequestData)
        let failResponse = try USBIPSubmitResponse.decode(from: failResponseData)
        
        XCTAssertNotEqual(failResponse.status, 0) // Should be error
        
        // Second request succeeds after recovery
        mockDeviceCommunicator.reset()
        mockDeviceCommunicator.setBulkTransferResponse(Data(repeating: 0x99, count: 32))
        
        let successRequestData = try createUSBSubmitRequestData(seqnum: 5002, bufferLength: 32)
        let successResponseData = try await submitProcessor.processSubmitRequest(successRequestData)
        let successResponse = try USBIPSubmitResponse.decode(from: successResponseData)
        
        XCTAssertEqual(successResponse.status, 0) // Should succeed
        XCTAssertEqual(successResponse.actualLength, 32)
    }
    
    func testProcessorStateConsistencyAfterErrors() async throws {
        // Test that processor state remains consistent after various error conditions
        
        // Generate multiple error conditions
        let errorConditions = [
            { self.mockDeviceCommunicator.simulateTimeout() },
            { self.mockDeviceCommunicator.simulateDeviceDisconnection() },
            { self.mockDeviceCommunicator.simulateEndpointStall() }
        ]
        
        for (index, setupError) in errorConditions.enumerated() {
            setupError()
            
            let requestData = try createUSBSubmitRequestData(seqnum: UInt32(6000 + index))
            let responseData = try await submitProcessor.processSubmitRequest(requestData)
            let response = try USBIPSubmitResponse.decode(from: responseData)
            
            // Verify error is reported correctly
            XCTAssertNotEqual(response.status, 0)
            
            // Reset for next test
            mockDeviceCommunicator.reset()
        }
        
        // Verify processor can still handle successful requests
        mockDeviceCommunicator.setBulkTransferResponse(Data(repeating: 0xAA, count: 16))
        let finalRequestData = try createUSBSubmitRequestData(seqnum: 6999, bufferLength: 16)
        let finalResponseData = try await submitProcessor.processSubmitRequest(finalRequestData)
        let finalResponse = try USBIPSubmitResponse.decode(from: finalResponseData)
        
        XCTAssertEqual(finalResponse.status, 0)
        XCTAssertEqual(finalResponse.actualLength, 16)
    }
}

// MARK: - Mock USB Device Communicator Protocol

protocol USBDeviceCommunicatorProtocol: AnyObject {
    func executeControlTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult
    func executeBulkTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult
    func executeInterruptTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult
    func executeIsochronousTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult
}

// MARK: - Mock Device Communicator for Testing

class MockUSBDeviceCommunicator: USBDeviceCommunicatorProtocol {
    
    // MARK: - Mock Configuration
    
    private var shouldSucceed = true
    private var operationLatency: UInt32 = 0
    private var simulatedError: Error?
    
    // Mock responses for different transfer types
    private var controlResponse: (data: Data, status: USBStatus, actualLength: UInt32)?
    private var bulkResponse: (data: Data, status: USBStatus, actualLength: UInt32)?
    private var interruptResponse: (data: Data, status: USBStatus, actualLength: UInt32)?
    private var isochronousResponse: (data: Data, status: USBStatus, actualLength: UInt32, errorCount: UInt32)?
    
    // MARK: - Configuration Methods
    
    func reset() {
        shouldSucceed = true
        operationLatency = 0
        simulatedError = nil
        controlResponse = nil
        bulkResponse = nil
        interruptResponse = nil
        isochronousResponse = nil
    }
    
    func setShouldSucceed(_ succeed: Bool) {
        shouldSucceed = succeed
    }
    
    func setOperationLatency(_ latency: UInt32) {
        operationLatency = latency
    }
    
    func setControlTransferResponse(_ data: Data, status: USBStatus = .success, actualLength: UInt32? = nil) {
        controlResponse = (data, status, actualLength ?? UInt32(data.count))
    }
    
    func setBulkTransferResponse(_ data: Data, status: USBStatus = .success, actualLength: UInt32? = nil) {
        bulkResponse = (data, status, actualLength ?? UInt32(data.count))
    }
    
    func setInterruptTransferResponse(_ data: Data, status: USBStatus = .success, actualLength: UInt32? = nil) {
        interruptResponse = (data, status, actualLength ?? UInt32(data.count))
    }
    
    func setIsochronousTransferResponse(
        _ data: Data,
        status: USBStatus = .success,
        actualLength: UInt32? = nil,
        errorCount: UInt32 = 0
    ) {
        isochronousResponse = (data, status, actualLength ?? UInt32(data.count), errorCount)
    }
    
    func simulateTimeout() {
        simulatedError = USBRequestError.timeout
        shouldSucceed = false
    }
    
    func simulateDeviceDisconnection() {
        simulatedError = USBRequestError.deviceNotAvailable
        shouldSucceed = false
    }
    
    func simulateEndpointStall() {
        simulatedError = USBRequestError.invalidParameters
        shouldSucceed = false
    }
    
    // MARK: - Protocol Implementation
    
    func executeControlTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        if operationLatency > 0 {
            try await Task.sleep(nanoseconds: UInt64(operationLatency) * 1_000_000)
        }
        
        if !shouldSucceed, let error = simulatedError {
            throw error
        }
        
        if let response = controlResponse {
            return USBTransferResult(
                status: response.status,
                actualLength: response.actualLength,
                data: response.data,
                completionTime: Date().timeIntervalSince1970
            )
        }
        
        return USBTransferResult(
            status: .success,
            actualLength: 0,
            completionTime: Date().timeIntervalSince1970
        )
    }
    
    func executeBulkTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        if operationLatency > 0 {
            try await Task.sleep(nanoseconds: UInt64(operationLatency) * 1_000_000)
        }
        
        if !shouldSucceed, let error = simulatedError {
            throw error
        }
        
        if let response = bulkResponse {
            return USBTransferResult(
                status: response.status,
                actualLength: response.actualLength,
                data: response.data,
                completionTime: Date().timeIntervalSince1970
            )
        }
        
        return USBTransferResult(
            status: .success,
            actualLength: request.bufferLength,
            completionTime: Date().timeIntervalSince1970
        )
    }
    
    func executeInterruptTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        if operationLatency > 0 {
            try await Task.sleep(nanoseconds: UInt64(operationLatency) * 1_000_000)
        }
        
        if !shouldSucceed, let error = simulatedError {
            throw error
        }
        
        if let response = interruptResponse {
            return USBTransferResult(
                status: response.status,
                actualLength: response.actualLength,
                data: response.data,
                completionTime: Date().timeIntervalSince1970
            )
        }
        
        return USBTransferResult(
            status: .success,
            actualLength: request.bufferLength,
            completionTime: Date().timeIntervalSince1970
        )
    }
    
    func executeIsochronousTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        if operationLatency > 0 {
            try await Task.sleep(nanoseconds: UInt64(operationLatency) * 1_000_000)
        }
        
        if !shouldSucceed, let error = simulatedError {
            throw error
        }
        
        if let response = isochronousResponse {
            return USBTransferResult(
                status: response.status,
                actualLength: response.actualLength,
                errorCount: response.errorCount,
                data: response.data,
                completionTime: Date().timeIntervalSince1970,
                startFrame: request.startFrame
            )
        }
        
        return USBTransferResult(
            status: .success,
            actualLength: request.bufferLength,
            errorCount: 0,
            completionTime: Date().timeIntervalSince1970,
            startFrame: request.startFrame
        )
    }
}