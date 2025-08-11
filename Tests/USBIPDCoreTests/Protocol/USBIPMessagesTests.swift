// USBIPMessagesTests.swift
// Tests for USB/IP SUBMIT/UNLINK message encoding and decoding

import XCTest
@testable import USBIPDCore
@testable import Common

final class USBIPMessagesTests: XCTestCase {
    
    // MARK: - USBIPSubmitRequest Tests
    
    func testUSBIPSubmitRequestEncodingDecoding() throws {
        let setupPacket = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00])
        let transferBuffer = Data(repeating: 0xAB, count: 64)
        
        let request = USBIPSubmitRequest(
            seqnum: 123,
            devid: 456,
            direction: 0, // OUT
            ep: 0x02,
            transferFlags: 0x1000,
            transferBufferLength: 64,
            startFrame: 100,
            numberOfPackets: 0,
            interval: 0,
            setup: setupPacket,
            transferBuffer: transferBuffer
        )
        
        let encodedData = try request.encode()
        
        // Verify the encoded data has the correct minimum length
        // Header (8) + command fields (40) + reserved (4) + setup (8) + buffer (64) = 124 bytes
        XCTAssertEqual(encodedData.count, 124)
        
        // Verify the data can be decoded back correctly
        let decodedRequest = try USBIPSubmitRequest.decode(from: encodedData)
        XCTAssertEqual(decodedRequest.seqnum, request.seqnum)
        XCTAssertEqual(decodedRequest.devid, request.devid)
        XCTAssertEqual(decodedRequest.direction, request.direction)
        XCTAssertEqual(decodedRequest.ep, request.ep)
        XCTAssertEqual(decodedRequest.transferFlags, request.transferFlags)
        XCTAssertEqual(decodedRequest.transferBufferLength, request.transferBufferLength)
        XCTAssertEqual(decodedRequest.startFrame, request.startFrame)
        XCTAssertEqual(decodedRequest.numberOfPackets, request.numberOfPackets)
        XCTAssertEqual(decodedRequest.interval, request.interval)
        XCTAssertEqual(decodedRequest.setup, request.setup)
        XCTAssertEqual(decodedRequest.transferBuffer, request.transferBuffer)
        XCTAssertEqual(decodedRequest.header.command, .submitRequest)
    }
    
    func testUSBIPSubmitRequestControlTransfer() throws {
        let setupPacket = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00]) // GET_DESCRIPTOR
        
        let request = USBIPSubmitRequest(
            seqnum: 1,
            devid: 1,
            direction: 1, // IN
            ep: 0x00,
            transferFlags: 0,
            transferBufferLength: 18,
            setup: setupPacket
        )
        
        let encodedData = try request.encode()
        
        // Header (8) + command fields (40) + reserved (4) + setup (8) = 60 bytes (no transfer buffer for control IN)
        XCTAssertEqual(encodedData.count, 60)
        
        let decodedRequest = try USBIPSubmitRequest.decode(from: encodedData)
        XCTAssertEqual(decodedRequest.ep, 0x00)
        XCTAssertEqual(decodedRequest.direction, 1)
        XCTAssertEqual(decodedRequest.transferBufferLength, 18)
        XCTAssertEqual(decodedRequest.setup.count, 8)
        XCTAssertEqual(decodedRequest.setup, setupPacket)
        XCTAssertNil(decodedRequest.transferBuffer)
    }
    
    func testUSBIPSubmitRequestBulkTransfer() throws {
        let testData = Data(repeating: 0x42, count: 512)
        
        let request = USBIPSubmitRequest(
            seqnum: 2,
            devid: 1,
            direction: 0, // OUT
            ep: 0x02,
            transferFlags: 0,
            transferBufferLength: 512,
            transferBuffer: testData
        )
        
        let encodedData = try request.encode()
        
        // Header (8) + command fields (40) + reserved (4) + setup (8) + buffer (512) = 572 bytes
        XCTAssertEqual(encodedData.count, 572)
        
        let decodedRequest = try USBIPSubmitRequest.decode(from: encodedData)
        XCTAssertEqual(decodedRequest.ep, 0x02)
        XCTAssertEqual(decodedRequest.direction, 0)
        XCTAssertEqual(decodedRequest.transferBufferLength, 512)
        XCTAssertEqual(decodedRequest.transferBuffer?.count, 512)
        XCTAssertEqual(decodedRequest.transferBuffer, testData)
    }
    
    func testUSBIPSubmitRequestInterruptTransfer() throws {
        let request = USBIPSubmitRequest(
            seqnum: 3,
            devid: 1,
            direction: 1, // IN
            ep: 0x81,
            transferFlags: 0,
            transferBufferLength: 8,
            interval: 10
        )
        
        let encodedData = try request.encode()
        let decodedRequest = try USBIPSubmitRequest.decode(from: encodedData)
        
        XCTAssertEqual(decodedRequest.ep, 0x81)
        XCTAssertEqual(decodedRequest.direction, 1)
        XCTAssertEqual(decodedRequest.interval, 10)
        XCTAssertEqual(decodedRequest.transferBufferLength, 8)
    }
    
    func testUSBIPSubmitRequestIsochronousTransfer() throws {
        let request = USBIPSubmitRequest(
            seqnum: 4,
            devid: 1,
            direction: 1, // IN
            ep: 0x83,
            transferFlags: 0,
            transferBufferLength: 1024,
            startFrame: 1000,
            numberOfPackets: 10
        )
        
        let encodedData = try request.encode()
        let decodedRequest = try USBIPSubmitRequest.decode(from: encodedData)
        
        XCTAssertEqual(decodedRequest.ep, 0x83)
        XCTAssertEqual(decodedRequest.direction, 1)
        XCTAssertEqual(decodedRequest.startFrame, 1000)
        XCTAssertEqual(decodedRequest.numberOfPackets, 10)
        XCTAssertEqual(decodedRequest.transferBufferLength, 1024)
    }
    
    func testUSBIPSubmitRequestSetupPacketPadding() throws {
        // Test with short setup packet (should be padded to 8 bytes)
        let shortSetup = Data([0x80, 0x06])
        
        let request = USBIPSubmitRequest(
            seqnum: 5,
            devid: 1,
            direction: 1,
            ep: 0x00,
            transferFlags: 0,
            transferBufferLength: 0,
            setup: shortSetup
        )
        
        let encodedData = try request.encode()
        let decodedRequest = try USBIPSubmitRequest.decode(from: encodedData)
        
        XCTAssertEqual(decodedRequest.setup.count, 8)
        // First two bytes should match original, rest should be zero-padded
        XCTAssertEqual(decodedRequest.setup[0], 0x80)
        XCTAssertEqual(decodedRequest.setup[1], 0x06)
        XCTAssertEqual(decodedRequest.setup[2], 0x00)
        XCTAssertEqual(decodedRequest.setup[7], 0x00)
    }
    
    func testUSBIPSubmitRequestSetupPacketTruncation() throws {
        // Test with long setup packet (should be truncated to 8 bytes)
        let longSetup = Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00, 0xFF, 0xFF, 0xFF])
        
        let request = USBIPSubmitRequest(
            seqnum: 6,
            devid: 1,
            direction: 1,
            ep: 0x00,
            transferFlags: 0,
            transferBufferLength: 0,
            setup: longSetup
        )
        
        let encodedData = try request.encode()
        let decodedRequest = try USBIPSubmitRequest.decode(from: encodedData)
        
        XCTAssertEqual(decodedRequest.setup.count, 8)
        // Should contain only the first 8 bytes
        XCTAssertEqual(decodedRequest.setup, Data([0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x12, 0x00]))
    }
    
    // MARK: - USBIPSubmitResponse Tests
    
    func testUSBIPSubmitResponseEncodingDecoding() throws {
        let responseData = Data(repeating: 0xCD, count: 256)
        
        let response = USBIPSubmitResponse(
            seqnum: 123,
            devid: 456,
            direction: 1, // IN
            ep: 0x81,
            status: 0, // Success
            actualLength: 256,
            startFrame: 100,
            numberOfPackets: 0,
            errorCount: 0,
            transferBuffer: responseData
        )
        
        let encodedData = try response.encode()
        
        // Header (8) + response fields (36) + reserved (8) + buffer (256) = 308 bytes
        XCTAssertEqual(encodedData.count, 308)
        
        let decodedResponse = try USBIPSubmitResponse.decode(from: encodedData)
        XCTAssertEqual(decodedResponse.seqnum, response.seqnum)
        XCTAssertEqual(decodedResponse.devid, response.devid)
        XCTAssertEqual(decodedResponse.direction, response.direction)
        XCTAssertEqual(decodedResponse.ep, response.ep)
        XCTAssertEqual(decodedResponse.status, response.status)
        XCTAssertEqual(decodedResponse.actualLength, response.actualLength)
        XCTAssertEqual(decodedResponse.startFrame, response.startFrame)
        XCTAssertEqual(decodedResponse.numberOfPackets, response.numberOfPackets)
        XCTAssertEqual(decodedResponse.errorCount, response.errorCount)
        XCTAssertEqual(decodedResponse.transferBuffer, response.transferBuffer)
        XCTAssertEqual(decodedResponse.header.command, .submitReply)
    }
    
    func testUSBIPSubmitResponseWithError() throws {
        let response = USBIPSubmitResponse(
            seqnum: 123,
            devid: 456,
            direction: 0, // OUT
            ep: 0x02,
            status: -110, // Timeout error
            actualLength: 0,
            errorCount: 1
        )
        
        let encodedData = try response.encode()
        
        // Header (8) + response fields (36) + reserved (8) = 52 bytes (no buffer for error)
        XCTAssertEqual(encodedData.count, 52)
        
        let decodedResponse = try USBIPSubmitResponse.decode(from: encodedData)
        XCTAssertEqual(decodedResponse.seqnum, 123)
        XCTAssertEqual(decodedResponse.status, -110)
        XCTAssertEqual(decodedResponse.actualLength, 0)
        XCTAssertEqual(decodedResponse.errorCount, 1)
        XCTAssertNil(decodedResponse.transferBuffer)
    }
    
    func testUSBIPSubmitResponsePartialTransfer() throws {
        let partialData = Data(repeating: 0xEF, count: 100)
        
        let response = USBIPSubmitResponse(
            seqnum: 456,
            devid: 789,
            direction: 1, // IN
            ep: 0x81,
            status: -121, // Short packet
            actualLength: 100, // Less than requested
            transferBuffer: partialData
        )
        
        let encodedData = try response.encode()
        let decodedResponse = try USBIPSubmitResponse.decode(from: encodedData)
        
        XCTAssertEqual(decodedResponse.status, -121)
        XCTAssertEqual(decodedResponse.actualLength, 100)
        XCTAssertEqual(decodedResponse.transferBuffer?.count, 100)
        XCTAssertEqual(decodedResponse.transferBuffer, partialData)
    }
    
    func testUSBIPSubmitResponseIsochronousWithErrors() throws {
        let response = USBIPSubmitResponse(
            seqnum: 789,
            devid: 101,
            direction: 1, // IN
            ep: 0x83,
            status: 0, // Success
            actualLength: 800,
            startFrame: 2000,
            numberOfPackets: 10,
            errorCount: 2 // Some packets had errors
        )
        
        let encodedData = try response.encode()
        let decodedResponse = try USBIPSubmitResponse.decode(from: encodedData)
        
        XCTAssertEqual(decodedResponse.startFrame, 2000)
        XCTAssertEqual(decodedResponse.numberOfPackets, 10)
        XCTAssertEqual(decodedResponse.errorCount, 2)
        XCTAssertEqual(decodedResponse.actualLength, 800)
    }
    
    // MARK: - USBIPUnlinkRequest Tests
    
    func testUSBIPUnlinkRequestEncodingDecoding() throws {
        let request = USBIPUnlinkRequest(
            seqnum: 999,
            devid: 123,
            direction: 1, // IN
            ep: 0x81,
            unlinkSeqnum: 888 // Sequence number of request to cancel
        )
        
        let encodedData = try request.encode()
        
        // Header (8) + command fields (20) + reserved (24) = 52 bytes
        XCTAssertEqual(encodedData.count, 52)
        
        let decodedRequest = try USBIPUnlinkRequest.decode(from: encodedData)
        XCTAssertEqual(decodedRequest.seqnum, request.seqnum)
        XCTAssertEqual(decodedRequest.devid, request.devid)
        XCTAssertEqual(decodedRequest.direction, request.direction)
        XCTAssertEqual(decodedRequest.ep, request.ep)
        XCTAssertEqual(decodedRequest.unlinkSeqnum, request.unlinkSeqnum)
        XCTAssertEqual(decodedRequest.header.command, .unlinkRequest)
    }
    
    func testUSBIPUnlinkRequestValidation() throws {
        let request = USBIPUnlinkRequest(
            seqnum: 1000,
            devid: 456,
            direction: 0, // OUT
            ep: 0x02,
            unlinkSeqnum: 500
        )
        
        let encodedData = try request.encode()
        let decodedRequest = try USBIPUnlinkRequest.decode(from: encodedData)
        
        // Verify all fields are correctly encoded/decoded
        XCTAssertEqual(decodedRequest.seqnum, 1000)
        XCTAssertEqual(decodedRequest.devid, 456)
        XCTAssertEqual(decodedRequest.direction, 0)
        XCTAssertEqual(decodedRequest.ep, 0x02)
        XCTAssertEqual(decodedRequest.unlinkSeqnum, 500)
    }
    
    // MARK: - USBIPUnlinkResponse Tests
    
    func testUSBIPUnlinkResponseEncodingDecoding() throws {
        let response = USBIPUnlinkResponse(
            seqnum: 999,
            devid: 123,
            direction: 1, // IN
            ep: 0x81,
            status: 0 // Success
        )
        
        let encodedData = try response.encode()
        
        // Header (8) + response fields (20) + reserved (24) = 52 bytes
        XCTAssertEqual(encodedData.count, 52)
        
        let decodedResponse = try USBIPUnlinkResponse.decode(from: encodedData)
        XCTAssertEqual(decodedResponse.seqnum, response.seqnum)
        XCTAssertEqual(decodedResponse.devid, response.devid)
        XCTAssertEqual(decodedResponse.direction, response.direction)
        XCTAssertEqual(decodedResponse.ep, response.ep)
        XCTAssertEqual(decodedResponse.status, response.status)
        XCTAssertEqual(decodedResponse.header.command, .unlinkReply)
    }
    
    func testUSBIPUnlinkResponseWithError() throws {
        let response = USBIPUnlinkResponse(
            seqnum: 1001,
            devid: 789,
            direction: 0, // OUT
            ep: 0x02,
            status: -22 // Invalid request (request not found)
        )
        
        let encodedData = try response.encode()
        let decodedResponse = try USBIPUnlinkResponse.decode(from: encodedData)
        
        XCTAssertEqual(decodedResponse.seqnum, 1001)
        XCTAssertEqual(decodedResponse.status, -22)
        XCTAssertEqual(decodedResponse.devid, 789)
        XCTAssertEqual(decodedResponse.direction, 0)
        XCTAssertEqual(decodedResponse.ep, 0x02)
    }
    
    // MARK: - Message Validation Tests
    
    func testUSBIPSubmitRequestInvalidDataLength() throws {
        // Test with insufficient data for minimum message size
        let shortData = Data(count: 30) // Less than minimum 56 bytes
        
        XCTAssertThrowsError(try USBIPSubmitRequest.decode(from: shortData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.invalidDataLength = error {
                // Expected error
            } else {
                XCTFail("Expected invalidDataLength error")
            }
        }
    }
    
    func testUSBIPSubmitResponseInvalidDataLength() throws {
        // Test with insufficient data for minimum message size
        let shortData = Data(count: 30) // Less than minimum 52 bytes
        
        XCTAssertThrowsError(try USBIPSubmitResponse.decode(from: shortData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.invalidDataLength = error {
                // Expected error
            } else {
                XCTFail("Expected invalidDataLength error")
            }
        }
    }
    
    func testUSBIPUnlinkRequestInvalidDataLength() throws {
        // Test with insufficient data for minimum message size
        let shortData = Data(count: 30) // Less than minimum 52 bytes
        
        XCTAssertThrowsError(try USBIPUnlinkRequest.decode(from: shortData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.invalidDataLength = error {
                // Expected error
            } else {
                XCTFail("Expected invalidDataLength error")
            }
        }
    }
    
    func testUSBIPUnlinkResponseInvalidDataLength() throws {
        // Test with insufficient data for minimum message size
        let shortData = Data(count: 30) // Less than minimum 52 bytes
        
        XCTAssertThrowsError(try USBIPUnlinkResponse.decode(from: shortData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.invalidDataLength = error {
                // Expected error
            } else {
                XCTFail("Expected invalidDataLength error")
            }
        }
    }
    
    func testInvalidMessageFormatHandling() throws {
        // Create a valid header but with wrong command for SUBMIT request
        let header = USBIPHeader(command: .requestDeviceList) // Wrong command
        let invalidData = try header.encode() + Data(count: 48) // Pad to minimum size
        
        XCTAssertThrowsError(try USBIPSubmitRequest.decode(from: invalidData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.invalidMessageFormat = error {
                // Expected error
            } else {
                XCTFail("Expected invalidMessageFormat error")
            }
        }
        
        // Test wrong command for UNLINK request
        XCTAssertThrowsError(try USBIPUnlinkRequest.decode(from: invalidData)) { error in
            XCTAssertTrue(error is USBIPProtocolError)
            if case USBIPProtocolError.invalidMessageFormat = error {
                // Expected error
            } else {
                XCTFail("Expected invalidMessageFormat error")
            }
        }
    }
    
    // MARK: - Edge Cases and Boundary Conditions
    
    func testUSBIPSubmitRequestZeroLengthTransfer() throws {
        let request = USBIPSubmitRequest(
            seqnum: 100,
            devid: 200,
            direction: 0, // OUT
            ep: 0x01,
            transferFlags: 0,
            transferBufferLength: 0 // Zero-length transfer
        )
        
        let encodedData = try request.encode()
        let decodedRequest = try USBIPSubmitRequest.decode(from: encodedData)
        
        XCTAssertEqual(decodedRequest.transferBufferLength, 0)
        XCTAssertNil(decodedRequest.transferBuffer)
    }
    
    func testUSBIPSubmitResponseZeroLengthResponse() throws {
        let response = USBIPSubmitResponse(
            seqnum: 100,
            devid: 200,
            direction: 1, // IN
            ep: 0x81,
            status: 0,
            actualLength: 0 // Zero-length response
        )
        
        let encodedData = try response.encode()
        let decodedResponse = try USBIPSubmitResponse.decode(from: encodedData)
        
        XCTAssertEqual(decodedResponse.actualLength, 0)
        XCTAssertNil(decodedResponse.transferBuffer)
    }
    
    func testUSBIPSubmitRequestMaximumSequenceNumber() throws {
        let request = USBIPSubmitRequest(
            seqnum: UInt32.max,
            devid: UInt32.max,
            direction: 1,
            ep: 0xFF,
            transferFlags: UInt32.max,
            transferBufferLength: 1
        )
        
        let encodedData = try request.encode()
        let decodedRequest = try USBIPSubmitRequest.decode(from: encodedData)
        
        XCTAssertEqual(decodedRequest.seqnum, UInt32.max)
        XCTAssertEqual(decodedRequest.devid, UInt32.max)
        XCTAssertEqual(decodedRequest.transferFlags, UInt32.max)
    }
    
    func testUSBIPSubmitResponseNegativeStatus() throws {
        let response = USBIPSubmitResponse(
            seqnum: 123,
            devid: 456,
            direction: 0,
            ep: 0x02,
            status: Int32.min, // Most negative value
            actualLength: 0
        )
        
        let encodedData = try response.encode()
        let decodedResponse = try USBIPSubmitResponse.decode(from: encodedData)
        
        XCTAssertEqual(decodedResponse.status, Int32.min)
    }
    
    func testUSBIPUnlinkResponseNegativeStatus() throws {
        let response = USBIPUnlinkResponse(
            seqnum: 123,
            devid: 456,
            direction: 0,
            ep: 0x02,
            status: Int32.min // Most negative value
        )
        
        let encodedData = try response.encode()
        let decodedResponse = try USBIPUnlinkResponse.decode(from: encodedData)
        
        XCTAssertEqual(decodedResponse.status, Int32.min)
    }
    
    // MARK: - Endianness and Binary Format Tests
    
    func testUSBIPSubmitRequestEndiannessHandling() throws {
        let request = USBIPSubmitRequest(
            seqnum: 0x12345678,
            devid: 0x9ABCDEF0,
            direction: 1,
            ep: 0x81,
            transferFlags: 0xABCDEF12,
            transferBufferLength: 0x87654321,
            startFrame: 0x11223344,
            numberOfPackets: 0x55667788,
            interval: 0x99AABBCC
        )
        
        let encodedData = try request.encode()
        let decodedRequest = try USBIPSubmitRequest.decode(from: encodedData)
        
        // Verify all multi-byte values are correctly encoded/decoded
        XCTAssertEqual(decodedRequest.seqnum, 0x12345678)
        XCTAssertEqual(decodedRequest.devid, 0x9ABCDEF0)
        XCTAssertEqual(decodedRequest.transferFlags, 0xABCDEF12)
        XCTAssertEqual(decodedRequest.transferBufferLength, 0x87654321)
        XCTAssertEqual(decodedRequest.startFrame, 0x11223344)
        XCTAssertEqual(decodedRequest.numberOfPackets, 0x55667788)
        XCTAssertEqual(decodedRequest.interval, 0x99AABBCC)
    }
    
    func testUSBIPSubmitResponseSignedStatusHandling() throws {
        let testValues: [Int32] = [
            0,           // Success
            -1,          // Generic error
            -110,        // Timeout
            -125,        // Cancelled
            -32,         // Stall
            -19,         // Device gone
            Int32.max,   // Maximum positive
            Int32.min    // Maximum negative
        ]
        
        for statusValue in testValues {
            let response = USBIPSubmitResponse(
                seqnum: 123,
                devid: 456,
                direction: 0,
                ep: 0x02,
                status: statusValue,
                actualLength: 0
            )
            
            let encodedData = try response.encode()
            let decodedResponse = try USBIPSubmitResponse.decode(from: encodedData)
            
            XCTAssertEqual(decodedResponse.status, statusValue, "Status value \(statusValue) not correctly encoded/decoded")
        }
    }
    
    func testUSBIPUnlinkResponseSignedStatusHandling() throws {
        let testValues: [Int32] = [
            0,           // Success
            -22,         // Invalid request
            -125,        // Cancelled
            Int32.max,   // Maximum positive
            Int32.min    // Maximum negative
        ]
        
        for statusValue in testValues {
            let response = USBIPUnlinkResponse(
                seqnum: 789,
                devid: 101,
                direction: 1,
                ep: 0x81,
                status: statusValue
            )
            
            let encodedData = try response.encode()
            let decodedResponse = try USBIPUnlinkResponse.decode(from: encodedData)
            
            XCTAssertEqual(decodedResponse.status, statusValue, "Status value \(statusValue) not correctly encoded/decoded")
        }
    }
    
    // MARK: - Buffer Handling Edge Cases
    
    func testUSBIPSubmitRequestBufferLengthMismatch() throws {
        // Test when transferBufferLength doesn't match actual buffer size
        let buffer = Data(repeating: 0xFF, count: 100)
        
        let request = USBIPSubmitRequest(
            seqnum: 123,
            devid: 456,
            direction: 0, // OUT
            ep: 0x02,
            transferFlags: 0,
            transferBufferLength: 200, // Different from actual buffer size
            transferBuffer: buffer
        )
        
        let encodedData = try request.encode()
        let decodedRequest = try USBIPSubmitRequest.decode(from: encodedData)
        
        XCTAssertEqual(decodedRequest.transferBufferLength, 200)
        XCTAssertEqual(decodedRequest.transferBuffer?.count, 100) // Actual buffer size
        XCTAssertEqual(decodedRequest.transferBuffer, buffer)
    }
    
    func testUSBIPSubmitResponseBufferTruncation() throws {
        // Test when encoded data is truncated before full buffer
        let originalData = Data(repeating: 0xAA, count: 1000)
        
        let response = USBIPSubmitResponse(
            seqnum: 123,
            devid: 456,
            direction: 1, // IN
            ep: 0x81,
            status: 0,
            actualLength: 1000,
            transferBuffer: originalData
        )
        
        let encodedData = try response.encode()
        
        // Artificially truncate the encoded data
        let truncatedData = encodedData.subdata(in: 0..<(52 + 500)) // Only first 500 bytes of buffer
        
        let decodedResponse = try USBIPSubmitResponse.decode(from: truncatedData)
        
        XCTAssertEqual(decodedResponse.actualLength, 1000) // Original length
        XCTAssertEqual(decodedResponse.transferBuffer?.count, 500) // Truncated buffer
    }
    
    // MARK: - Protocol Compliance Tests
    
    func testUSBIPMessageHeaderConsistency() throws {
        let submitRequest = USBIPSubmitRequest(seqnum: 1, devid: 1, direction: 0, ep: 1, transferFlags: 0, transferBufferLength: 0)
        let submitResponse = USBIPSubmitResponse(seqnum: 1, devid: 1, direction: 0, ep: 1, status: 0, actualLength: 0)
        let unlinkRequest = USBIPUnlinkRequest(seqnum: 2, devid: 1, direction: 0, ep: 1, unlinkSeqnum: 1)
        let unlinkResponse = USBIPUnlinkResponse(seqnum: 2, devid: 1, direction: 0, ep: 1, status: 0)
        
        // Verify all headers have correct version and commands
        XCTAssertEqual(submitRequest.header.version, USBIPProtocol.version)
        XCTAssertEqual(submitRequest.header.command, .submitRequest)
        
        XCTAssertEqual(submitResponse.header.version, USBIPProtocol.version)
        XCTAssertEqual(submitResponse.header.command, .submitReply)
        
        XCTAssertEqual(unlinkRequest.header.version, USBIPProtocol.version)
        XCTAssertEqual(unlinkRequest.header.command, .unlinkRequest)
        
        XCTAssertEqual(unlinkResponse.header.version, USBIPProtocol.version)
        XCTAssertEqual(unlinkResponse.header.command, .unlinkReply)
    }
    
    func testRoundTripEncodingDecoding() throws {
        // Test multiple round trips to ensure data integrity
        let originalRequest = USBIPSubmitRequest(
            seqnum: 0xDEADBEEF,
            devid: 0xCAFEBABE,
            direction: 1,
            ep: 0x83,
            transferFlags: 0x12345678,
            transferBufferLength: 256,
            startFrame: 0xABCDEF01,
            numberOfPackets: 16,
            interval: 8,
            setup: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            transferBuffer: Data(0x00...0xFF) // 256 bytes
        )
        
        // First round trip
        let encoded1 = try originalRequest.encode()
        let decoded1 = try USBIPSubmitRequest.decode(from: encoded1)
        
        // Second round trip
        let encoded2 = try decoded1.encode()
        let decoded2 = try USBIPSubmitRequest.decode(from: encoded2)
        
        // Third round trip
        let encoded3 = try decoded2.encode()
        let decoded3 = try USBIPSubmitRequest.decode(from: encoded3)
        
        // All should be identical
        XCTAssertEqual(encoded1, encoded2)
        XCTAssertEqual(encoded2, encoded3)
        XCTAssertEqual(decoded1.seqnum, decoded2.seqnum)
        XCTAssertEqual(decoded2.seqnum, decoded3.seqnum)
        XCTAssertEqual(decoded1.transferBuffer, decoded2.transferBuffer)
        XCTAssertEqual(decoded2.transferBuffer, decoded3.transferBuffer)
    }
}