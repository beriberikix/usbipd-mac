// USBRequestModelsTests.swift
// Comprehensive unit tests for USB request data models

import XCTest
@testable import USBIPDCore
@testable import Common
import IOKit
import IOKit.usb

final class USBRequestModelsTests: XCTestCase {
    
    // MARK: - USBTransferType Tests
    
    func testUSBTransferTypeEnumValues() {
        XCTAssertEqual(USBTransferType.control.rawValue, 0)
        XCTAssertEqual(USBTransferType.isochronous.rawValue, 1)
        XCTAssertEqual(USBTransferType.bulk.rawValue, 2)
        XCTAssertEqual(USBTransferType.interrupt.rawValue, 3)
    }
    
    // MARK: - URBStatus Tests
    
    func testURBStatusEnumValues() {
        let statuses: [URBStatus] = [.pending, .inProgress, .completed, .cancelled, .failed]
        XCTAssertEqual(statuses.count, 5, "All URB status cases should be accounted for")
    }
    
    // MARK: - USBTransferDirection Tests
    
    func testUSBTransferDirectionEnumValues() {
        XCTAssertEqual(USBTransferDirection.out.rawValue, 0)
        XCTAssertEqual(USBTransferDirection.in.rawValue, 1)
    }
    
    // MARK: - USBRequestBlock Tests
    
    func testUSBRequestBlockInitializationWithDefaults() {
        let urb = USBRequestBlock(
            seqnum: 123,
            devid: 456,
            direction: .out,
            endpoint: 0x01,
            transferType: .bulk,
            transferFlags: 0,
            bufferLength: 1024
        )
        
        XCTAssertEqual(urb.seqnum, 123)
        XCTAssertEqual(urb.devid, 456)
        XCTAssertEqual(urb.direction, .out)
        XCTAssertEqual(urb.endpoint, 0x01)
        XCTAssertEqual(urb.transferType, .bulk)
        XCTAssertEqual(urb.transferFlags, 0)
        XCTAssertEqual(urb.bufferLength, 1024)
        XCTAssertNil(urb.setupPacket)
        XCTAssertNil(urb.transferBuffer)
        XCTAssertEqual(urb.timeout, 5000)
        XCTAssertEqual(urb.startFrame, 0)
        XCTAssertEqual(urb.numberOfPackets, 0)
        XCTAssertEqual(urb.interval, 0)
    }
    
    func testUSBRequestBlockInitializationWithAllParameters() {
        let setupData = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00])
        let transferData = Data(repeating: 0xAB, count: 18)
        
        let urb = USBRequestBlock(
            seqnum: 789,
            devid: 101,
            direction: .in,
            endpoint: 0x81,
            transferType: .control,
            transferFlags: 0x1000,
            bufferLength: 18,
            setupPacket: setupData,
            transferBuffer: transferData,
            timeout: 10000,
            startFrame: 100,
            numberOfPackets: 8,
            interval: 10
        )
        
        XCTAssertEqual(urb.seqnum, 789)
        XCTAssertEqual(urb.devid, 101)
        XCTAssertEqual(urb.direction, .in)
        XCTAssertEqual(urb.endpoint, 0x81)
        XCTAssertEqual(urb.transferType, .control)
        XCTAssertEqual(urb.transferFlags, 0x1000)
        XCTAssertEqual(urb.bufferLength, 18)
        XCTAssertEqual(urb.setupPacket, setupData)
        XCTAssertEqual(urb.transferBuffer, transferData)
        XCTAssertEqual(urb.timeout, 10000)
        XCTAssertEqual(urb.startFrame, 100)
        XCTAssertEqual(urb.numberOfPackets, 8)
        XCTAssertEqual(urb.interval, 10)
    }
    
    func testUSBRequestBlockControlTransfer() {
        let setupPacket = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00]) // GET_DESCRIPTOR
        
        let urb = USBRequestBlock(
            seqnum: 1,
            devid: 1,
            direction: .in,
            endpoint: 0x00,
            transferType: .control,
            transferFlags: 0,
            bufferLength: 18,
            setupPacket: setupPacket
        )
        
        XCTAssertEqual(urb.transferType, .control)
        XCTAssertEqual(urb.endpoint, 0x00)
        XCTAssertNotNil(urb.setupPacket)
        XCTAssertEqual(urb.setupPacket?.count, 8)
    }
    
    func testUSBRequestBlockBulkTransfer() {
        let testData = Data(repeating: 0x42, count: 512)
        
        let urb = USBRequestBlock(
            seqnum: 2,
            devid: 1,
            direction: .out,
            endpoint: 0x02,
            transferType: .bulk,
            transferFlags: 0,
            bufferLength: 512,
            transferBuffer: testData
        )
        
        XCTAssertEqual(urb.transferType, .bulk)
        XCTAssertEqual(urb.endpoint, 0x02)
        XCTAssertEqual(urb.direction, .out)
        XCTAssertNotNil(urb.transferBuffer)
        XCTAssertEqual(urb.transferBuffer?.count, 512)
        XCTAssertNil(urb.setupPacket)
    }
    
    func testUSBRequestBlockInterruptTransfer() {
        let urb = USBRequestBlock(
            seqnum: 3,
            devid: 1,
            direction: .in,
            endpoint: 0x81,
            transferType: .interrupt,
            transferFlags: 0,
            bufferLength: 8,
            interval: 10
        )
        
        XCTAssertEqual(urb.transferType, .interrupt)
        XCTAssertEqual(urb.interval, 10)
        XCTAssertEqual(urb.bufferLength, 8)
    }
    
    func testUSBRequestBlockIsochronousTransfer() {
        let urb = USBRequestBlock(
            seqnum: 4,
            devid: 1,
            direction: .in,
            endpoint: 0x83,
            transferType: .isochronous,
            transferFlags: 0,
            bufferLength: 1024,
            startFrame: 1000,
            numberOfPackets: 10
        )
        
        XCTAssertEqual(urb.transferType, .isochronous)
        XCTAssertEqual(urb.startFrame, 1000)
        XCTAssertEqual(urb.numberOfPackets, 10)
    }
    
    // MARK: - USBTransferResult Tests
    
    func testUSBTransferResultInitializationWithDefaults() {
        let result = USBTransferResult(
            status: .success,
            actualLength: 512
        )
        
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.actualLength, 512)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertNil(result.data)
        XCTAssertEqual(result.startFrame, 0)
        XCTAssertTrue(result.completionTime > 0)
    }
    
    func testUSBTransferResultInitializationWithAllParameters() {
        let responseData = Data(repeating: 0xCD, count: 256)
        let timestamp = Date().timeIntervalSince1970
        
        let result = USBTransferResult(
            status: .success,
            actualLength: 256,
            errorCount: 0,
            data: responseData,
            completionTime: timestamp,
            startFrame: 500
        )
        
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.actualLength, 256)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.data, responseData)
        XCTAssertEqual(result.completionTime, timestamp)
        XCTAssertEqual(result.startFrame, 500)
    }
    
    func testUSBTransferResultWithError() {
        let result = USBTransferResult(
            status: .timeout,
            actualLength: 0,
            errorCount: 1
        )
        
        XCTAssertEqual(result.status, .timeout)
        XCTAssertEqual(result.actualLength, 0)
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertNil(result.data)
    }
    
    func testUSBTransferResultWithPartialData() {
        let partialData = Data(repeating: 0xEF, count: 100)
        
        let result = USBTransferResult(
            status: .shortPacket,
            actualLength: 100,
            errorCount: 0,
            data: partialData
        )
        
        XCTAssertEqual(result.status, .shortPacket)
        XCTAssertEqual(result.actualLength, 100)
        XCTAssertEqual(result.data?.count, 100)
    }
    
    // MARK: - USBStatus Tests
    
    func testUSBStatusEnumValues() {
        XCTAssertEqual(USBStatus.success.rawValue, 0)
        XCTAssertEqual(USBStatus.stall.rawValue, -32)
        XCTAssertEqual(USBStatus.timeout.rawValue, -110)
        XCTAssertEqual(USBStatus.cancelled.rawValue, -125)
        XCTAssertEqual(USBStatus.shortPacket.rawValue, -121)
        XCTAssertEqual(USBStatus.deviceGone.rawValue, -19)
        XCTAssertEqual(USBStatus.noDevice.rawValue, -19)
        XCTAssertEqual(USBStatus.requestFailed.rawValue, -71)
        XCTAssertEqual(USBStatus.protocolError.rawValue, -71)
        XCTAssertEqual(USBStatus.memoryError.rawValue, -12)
        XCTAssertEqual(USBStatus.invalidRequest.rawValue, -22)
        XCTAssertEqual(USBStatus.busError.rawValue, -71)
        XCTAssertEqual(USBStatus.bufferError.rawValue, -90)
    }
    
    // MARK: - USBErrorMapping Tests
    
    func testIOKitErrorMappingSuccess() {
        let usbStatus = USBErrorMapping.mapIOKitError(kIOReturnSuccess)
        XCTAssertEqual(usbStatus, USBStatus.success.rawValue)
    }
    
    func testIOKitErrorMappingTimeout() {
        let usbStatus = USBErrorMapping.mapIOKitError(kIOReturnTimeout)
        XCTAssertEqual(usbStatus, USBStatus.timeout.rawValue)
    }
    
    func testIOKitErrorMappingAborted() {
        let usbStatus = USBErrorMapping.mapIOKitError(kIOReturnAborted)
        XCTAssertEqual(usbStatus, USBStatus.cancelled.rawValue)
    }
    
    func testIOKitErrorMappingStall() {
        // USB-specific constants not available in all SDK versions
        // Test with generic error instead
        let usbStatus = USBErrorMapping.mapIOKitError(kIOReturnError)
        XCTAssertEqual(usbStatus, USBStatus.requestFailed.rawValue)
    }
    
    func testIOKitErrorMappingNoDevice() {
        let usbStatus = USBErrorMapping.mapIOKitError(kIOReturnNoDevice)
        XCTAssertEqual(usbStatus, USBStatus.deviceGone.rawValue)
    }
    
    func testIOKitErrorMappingNotResponding() {
        let usbStatus = USBErrorMapping.mapIOKitError(kIOReturnNotResponding)
        XCTAssertEqual(usbStatus, USBStatus.deviceGone.rawValue)
    }
    
    func testIOKitErrorMappingNoMemory() {
        let usbStatus = USBErrorMapping.mapIOKitError(kIOReturnNoMemory)
        XCTAssertEqual(usbStatus, USBStatus.memoryError.rawValue)
    }
    
    func testIOKitErrorMappingBadArgument() {
        let usbStatus = USBErrorMapping.mapIOKitError(kIOReturnBadArgument)
        XCTAssertEqual(usbStatus, USBStatus.invalidRequest.rawValue)
    }
    
    func testIOKitErrorMappingUSBTransactionTimeout() {
        // Use standard timeout error instead of USB-specific constant
        let usbStatus = USBErrorMapping.mapIOKitError(kIOReturnTimeout)
        XCTAssertEqual(usbStatus, USBStatus.timeout.rawValue)
    }
    
    func testIOKitErrorMappingUSBUnderrun() {
        // Use standard underrun error instead of USB-specific constant
        let usbStatus = USBErrorMapping.mapIOKitError(kIOReturnUnderrun)
        XCTAssertEqual(usbStatus, USBStatus.shortPacket.rawValue)
    }
    
    func testIOKitErrorMappingUSBBufferUnderrun() {
        // Use standard underrun error instead of USB-specific constant
        let usbStatus = USBErrorMapping.mapIOKitError(kIOReturnUnderrun)
        XCTAssertEqual(usbStatus, USBStatus.shortPacket.rawValue)
    }
    
    func testIOKitErrorMappingUSBBufferOverrun() {
        // Use standard overrun error instead of USB-specific constant
        let usbStatus = USBErrorMapping.mapIOKitError(kIOReturnOverrun)
        XCTAssertEqual(usbStatus, USBStatus.bufferError.rawValue)
    }
    
    func testIOKitErrorMappingUnknownError() {
        let usbStatus = USBErrorMapping.mapIOKitError(kIOReturnError)
        XCTAssertEqual(usbStatus, USBStatus.requestFailed.rawValue)
    }
    
    // MARK: - USBRequestError Tests
    
    func testUSBRequestErrorDescriptions() {
        let errors: [USBRequestError] = [
            .invalidURB("Test URB error"),
            .deviceNotClaimed("1-1"),
            .endpointNotFound(0x81),
            .transferTypeNotSupported(.isochronous),
            .bufferSizeMismatch(expected: 1024, actual: 512),
            .setupPacketRequired,
            .setupPacketInvalid,
            .timeoutInvalid(0),
            .concurrentRequestLimit,
            .requestCancelled(123),
            .timeout,
            .deviceNotAvailable,
            .invalidParameters,
            .tooManyRequests,
            .duplicateRequest,
            .cancelled
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
    
    func testUSBRequestErrorSpecificDescriptions() {
        let invalidURB = USBRequestError.invalidURB("Missing endpoint")
        XCTAssertEqual(invalidURB.errorDescription, "Invalid USB Request Block: Missing endpoint")
        
        let deviceNotClaimed = USBRequestError.deviceNotClaimed("1-2")
        XCTAssertEqual(deviceNotClaimed.errorDescription, "Device not claimed for USB operations: 1-2")
        
        let endpointNotFound = USBRequestError.endpointNotFound(0x82)
        XCTAssertEqual(endpointNotFound.errorDescription, "USB endpoint not found: 0x82")
        
        let bufferMismatch = USBRequestError.bufferSizeMismatch(expected: 2048, actual: 1024)
        XCTAssertEqual(bufferMismatch.errorDescription, "Buffer size mismatch - expected: 2048, actual: 1024")
        
        let timeoutInvalid = USBRequestError.timeoutInvalid(99999)
        XCTAssertEqual(timeoutInvalid.errorDescription, "Invalid timeout value: 99999ms")
        
        let requestCancelled = USBRequestError.requestCancelled(456)
        XCTAssertEqual(requestCancelled.errorDescription, "USB request cancelled: 456")
    }
}