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
    fileprivate var mockDeviceDiscovery: StubDeviceDiscovery!
    var testDevice: USBDevice!
    
    // MARK: - Test Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        mockDeviceCommunicator = MockUSBDeviceCommunicator()
        testDevice = createTestDevice()

        // The processor resolves a submitted devid to a real device through discovery.
        // Without this the lookup fails and every transfer returns ENODEV.
        mockDeviceDiscovery = StubDeviceDiscovery(device: testDevice)

        submitProcessor = USBSubmitProcessor(
            deviceCommunicator: mockDeviceCommunicator,
            deviceDiscovery: mockDeviceDiscovery
        )
        unlinkProcessor = USBUnlinkProcessor(submitProcessor: submitProcessor)
        
        // Configure mock device communicator
        mockDeviceCommunicator.reset()
        mockDeviceCommunicator.setShouldSucceed(true)
    }
    
    override func tearDown() {
        submitProcessor = nil
        unlinkProcessor = nil
        mockDeviceCommunicator = nil
        mockDeviceDiscovery = nil
        testDevice = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    /// The devid a client is handed for `createTestDevice()`: bus 1, hub port path "2".
    ///
    /// These tests used to submit devid 1 against a device on bus 1 at port 2, and pass,
    /// because the stub discovery returned that device for any lookup at all. Nothing
    /// checked that the identifier on the wire named the device the transfer reached —
    /// which is exactly the mistake that let a device behind a hub resolve to the hub.
    static let testDevid: UInt32 = (1 << 16) | 0x2

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
    
    private func createUSBSubmitRequestData(
        seqnum: UInt32 = 1,
        devid: UInt32 = USBRequestProcessorTests.testDevid,
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
        devid: UInt32 = USBRequestProcessorTests.testDevid,
        direction: UInt32 = 1,
        endpoint: UInt32 = 0x81,
        unlinkSeqnum: UInt32 = 1
    ) throws -> Data {
        let request = USBIPUnlinkRequest(
            seqnum: seqnum,
            unlinkSeqnum: unlinkSeqnum,
            devid: devid,
            direction: direction,
            ep: endpoint
        )
        
        return try request.encode()
    }
    
    // MARK: - USB SUBMIT Request Processing Tests
    
    func testProcessSubmitRequestControlTransferSuccess() async throws {
        // Configure mock for control transfer success
        let mockResponseData = Data([0x12, 0x01, 0x00, 0x02, 0x09, 0x00, 0x00, 0x40]) // Device descriptor
        mockDeviceCommunicator.setControlTransferResponse(mockResponseData)
        
        // Create control transfer request (GET_DESCRIPTOR)
        let setupPacket = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00])
        let requestData = try createUSBSubmitRequestData(
            seqnum: 123,
            devid: USBRequestProcessorTests.testDevid,
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
        XCTAssertEqual(response.devid, USBRequestProcessorTests.testDevid)
        XCTAssertEqual(response.direction, 1)
        XCTAssertEqual(response.ep, 0x00)
        XCTAssertEqual(response.status, 0) // Success
        // actualLength is the USB payload length, not the size of the encoded
        // message — comparing it to responseData.count compared 8 against 56.
        XCTAssertNotNil(response.transferBuffer)
        XCTAssertEqual(response.actualLength, UInt32(response.transferBuffer?.count ?? 0))
    }
    
    func testProcessSubmitRequestBulkTransferOut() async throws {
        // Configure mock for bulk OUT transfer
        let transferData = Data(repeating: 0x42, count: 512)
        mockDeviceCommunicator.setBulkTransferResponse(Data(), actualLength: 512)
        
        // Create bulk OUT transfer request
        let requestData = try createUSBSubmitRequestData(
            seqnum: 456,
            devid: USBRequestProcessorTests.testDevid,
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
            devid: USBRequestProcessorTests.testDevid,
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

        // The device decides the transfer type; CMD_SUBMIT does not carry one. A
        // non-zero interval used to imply interrupt, which misroutes bulk endpoints
        // that declare a bInterval — most of them.
        mockDeviceCommunicator.setEndpointTransferType(.interrupt, for: 0x81)
        
        // Create interrupt IN transfer request
        let requestData = try createUSBSubmitRequestData(
            seqnum: 101,
            devid: USBRequestProcessorTests.testDevid,
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
            devid: USBRequestProcessorTests.testDevid,
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
            _ = try await submitProcessor.processSubmitRequest(invalidData)
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
        XCTAssertEqual(response.devid, USBRequestProcessorTests.testDevid)
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

        // Nothing to cancel means the URB had already completed, and completing is
        // exactly what it did — it sent its own RET_SUBMIT. So this is a bare
        // acknowledgement carrying 0, not an error.
        //
        // The status is the URB's completion status and the client copies it onto the
        // transfer. The -2 (ENOENT) asserted here before would have been stamped onto a
        // transfer that had in fact succeeded.
        XCTAssertEqual(response.status, 0)
    }

    /// The failure this whole path exists to prevent. probe-rs posts a read on the
    /// CMSIS-DAP IN endpoint, cancels it a millisecond later, and then sends its first
    /// command. The cancelled read used to keep running, collect the reply meant for the
    /// command, and deliver it under a sequence number the client had already retired —
    /// which the client reports as "Error in the USB access".
    func testCancelledRequestDrawsNoSubmitReply() async throws {
        // Hold the transfer open long enough to cancel it while it is running.
        mockDeviceCommunicator.setOperationLatency(300)

        let seqnum: UInt32 = 4242
        let requestData = try createUSBSubmitRequestData(
            seqnum: seqnum,
            direction: 1, // IN
            endpoint: 0x81,
            bufferLength: 64
        )

        let submission = Task { try await self.submitProcessor.processSubmitRequest(requestData) }

        // Poll rather than sleep a fixed amount: what matters is that the sequence
        // number becomes cancellable at all, which is the race the reservation fixes.
        var didCancel = false
        for _ in 0..<100 where !didCancel {
            try await Task.sleep(nanoseconds: 5_000_000)
            didCancel = await submitProcessor.cancelURB(devid: USBRequestProcessorTests.testDevid, seqnum: seqnum)
        }
        XCTAssertTrue(didCancel, "a request that is still running should be cancellable")

        let response = try await submission.value
        XCTAssertTrue(response.isEmpty, "a cancelled request must not also send a RET_SUBMIT")
    }

    /// The converse, so the check above cannot pass by suppressing everything.
    func testUncancelledRequestStillReplies() async throws {
        let requestData = try createUSBSubmitRequestData(seqnum: 4243, direction: 1, endpoint: 0x81)
        let response = try await submitProcessor.processSubmitRequest(requestData)
        XCTAssertFalse(response.isEmpty, "an ordinary request must still be answered")
    }

    func testUnknownSequenceNumberIsNotCancellable() async throws {
        let cancelled = await submitProcessor.cancelURB(devid: USBRequestProcessorTests.testDevid, seqnum: 999_999)
        XCTAssertFalse(cancelled, "a sequence number never submitted should not be cancellable")
    }
    
    func testProcessUnlinkRequestInvalidMessage() async throws {
        // Create invalid message data
        let invalidData = Data([0xAA, 0xBB, 0xCC, 0xDD])
        
        do {
            _ = try await unlinkProcessor.processUnlinkRequest(invalidData)
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
                _ = try await submitProcessor.processSubmitRequest(requestData)
            } catch {
                // May be cancelled by unlink
            }
            expectation.fulfill()
        }
        
        Task {
            do {
                let requestData = try createUSBSubmitRequestData(seqnum: 502, bufferLength: 32)
                _ = try await submitProcessor.processSubmitRequest(requestData)
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
                _ = try await unlinkProcessor.processUnlinkRequest(unlinkData)
            } catch {
                // Expected if request already completed
            }
            expectation.fulfill()
        }
        
        Task {
            try await Task.sleep(nanoseconds: 25_000_000) // 25ms
            do {
                let unlinkData = try createUSBUnlinkRequestData(seqnum: 602, unlinkSeqnum: 502)
                _ = try await unlinkProcessor.processUnlinkRequest(unlinkData)
            } catch {
                // Expected if request already completed
            }
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
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
            devid: USBRequestProcessorTests.testDevid,
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
        XCTAssertEqual(response.devid, USBRequestProcessorTests.testDevid)
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

    // MARK: - Two clients do not share a sequence-number space

    /// USB/IP numbers requests per connection, and the Linux client opens one connection
    /// per attached device — so every client starts again at 1. Tracking by bare
    /// sequence number put them all in one namespace, and a second client's first
    /// request was rejected as a duplicate of the first client's. Attaching two devices
    /// from a single machine was enough to trigger it: five of ten concurrent transfers
    /// failed against real hardware.
    func testTwoDevicesMayUseTheSameSequenceNumber() async throws {
        // Two attached devices, so both devids resolve to something real.
        let other = USBDevice(
            busID: "2", deviceID: "3",
            vendorID: 0x4321, productID: 0x8765,
            deviceClass: 0x00, deviceSubClass: 0x00, deviceProtocol: 0x00,
            speed: .high,
            manufacturerString: nil, productString: nil, serialNumberString: nil
        )
        let processor = USBSubmitProcessor(
            deviceCommunicator: mockDeviceCommunicator,
            deviceDiscovery: StubDeviceDiscovery(devices: [testDevice, other])
        )

        let first = USBRequestProcessorTests.testDevid
        let second = (2 << 16) | UInt32(0x3)

        let firstRequest = try createUSBSubmitRequestData(seqnum: 1, devid: first, endpoint: 0x00)
        let secondRequest = try createUSBSubmitRequestData(seqnum: 1, devid: second, endpoint: 0x00)

        let firstResponse = try USBIPSubmitResponse.decode(
            from: try await processor.processSubmitRequest(firstRequest))
        let secondResponse = try USBIPSubmitResponse.decode(
            from: try await processor.processSubmitRequest(secondRequest))

        XCTAssertEqual(firstResponse.status, 0)
        XCTAssertEqual(secondResponse.status, 0, "a second device reusing seqnum 1 must not look like a duplicate")
    }

    /// A genuine duplicate — same device, same sequence number, still outstanding — is
    /// still refused. And it is refused with a reply: the rejection used to be thrown
    /// past the error-response path, so ServerCoordinator logged it, sent nothing, and
    /// the client waited forever for an answer that was never coming.
    func testDuplicateOnOneDeviceIsRefusedWithAReply() async throws {
        mockDeviceCommunicator.setOperationLatency(300)

        let requestData = try createUSBSubmitRequestData(seqnum: 77, endpoint: 0x00)
        let inFlight = Task { try await self.submitProcessor.processSubmitRequest(requestData) }

        // Let the first request claim the sequence number before repeating it.
        try await Task.sleep(nanoseconds: 50_000_000)

        let duplicate = try await submitProcessor.processSubmitRequest(requestData)
        XCTAssertFalse(duplicate.isEmpty, "a duplicate must be answered, not met with silence")

        let response = try USBIPSubmitResponse.decode(from: duplicate)
        XCTAssertEqual(response.seqnum, 77)
        XCTAssertNotEqual(response.status, 0, "a duplicate must report an error")

        _ = try await inFlight.value
    }
}

private final class StubDeviceDiscovery: DeviceDiscovery {
    private let devices: [USBDevice]
    private var device: USBDevice { devices[0] }

    var onDeviceConnected: ((USBDevice) -> Void)?
    var onDeviceDisconnected: ((USBDevice) -> Void)?

    init(device: USBDevice) {
        self.devices = [device]
    }

    init(devices: [USBDevice]) {
        self.devices = devices
    }

    func discoverDevices() throws -> [USBDevice] {
        return devices
    }

    func getDevice(busID: String, deviceID: String) throws -> USBDevice? {
        return device
    }

    func startNotifications() throws {}

    func stopNotifications() {}
}
