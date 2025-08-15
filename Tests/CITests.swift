// CITests.swift
// CI test environment for automated validation without hardware dependencies
// Consolidates CI-appropriate tests including protocol validation, network testing, and integration tests suitable for automated environments

import XCTest
import Foundation
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

// Import shared test utilities
import struct SharedUtilities.TestEnvironmentConfig
import struct SharedUtilities.TestEnvironmentCapabilities
import protocol SharedUtilities.TestSuite
import struct SharedUtilities.ProtocolMessageAssertions
import struct SharedUtilities.ErrorAssertions
import struct SharedUtilities.TestExecutionAssertions

/// CI Test Suite for automated testing without hardware dependencies
/// Focuses on protocol validation, network testing, and integration tests
/// suitable for GitHub Actions and other CI environments
final class CITests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    var environmentConfig: TestEnvironmentConfig {
        return .ci
    }
    
    var requiredCapabilities: TestEnvironmentCapabilities {
        return [.networkAccess, .filesystemWrite]
    }
    
    var testCategory: String {
        return "integration"
    }
    
    func setUpTestSuite() {
        // Set up CI-specific test environment
        do {
            try validateEnvironment()
        } catch {
            XCTFail("CI environment validation failed: \(error)")
        }
    }
    
    func tearDownTestSuite() {
        // Clean up CI test artifacts
    }
    
    // MARK: - Test Setup/Teardown
    
    override func setUp() {
        super.setUp()
        setUpTestSuite()
    }
    
    override func tearDown() {
        tearDownTestSuite()
        super.tearDown()
    }
    
    // MARK: - USB/IP Protocol Message Validation Tests
    
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
    
    // MARK: - Protocol Error Handling Tests
    
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
    
    // MARK: - Protocol Compliance Tests
    
    func testUSBIPMessageHeaderConsistency() throws {
        let submitRequest = USBIPSubmitRequest(seqnum: 1, devid: 1, direction: 0, ep: 1, transferFlags: 0, transferBufferLength: 0)
        let submitResponse = USBIPSubmitResponse(seqnum: 1, devid: 1, direction: 0, ep: 1, status: 0, actualLength: 0)
        let unlinkRequest = USBIPUnlinkRequest(seqnum: 2, unlinkSeqnum: 1, devid: 1, direction: 0, ep: 1)
        let unlinkResponse = USBIPUnlinkResponse(seqnum: 2, unlinkSeqnum: 1, devid: 1, direction: 0, ep: 1, status: 0)
        
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
    
    // MARK: - TCP Server Tests (CI-appropriate)
    
    func testServerStartStop() throws {
        let server = TCPServer()
        
        // Test initial state
        XCTAssertFalse(server.isRunning())
        
        // Test starting server with random port to avoid conflicts
        let port = Int.random(in: 8000...9000)
        try server.start(port: port)
        XCTAssertTrue(server.isRunning())
        
        // Test stopping server
        try server.stop()
        XCTAssertFalse(server.isRunning())
    }
    
    func testServerErrorHandling() throws {
        let server = TCPServer()
        
        // Should throw error when trying to stop a server that's not running
        XCTAssertThrowsError(try server.stop()) { error in
            XCTAssertTrue(error is ServerError)
            if case ServerError.notRunning = error {
                // Expected error
            } else {
                XCTFail("Expected ServerError.notRunning")
            }
        }
        
        // Test with invalid port number (0 is invalid)
        XCTAssertThrowsError(try server.start(port: 0)) { error in
            XCTAssertTrue(error is NetworkError)
            if case NetworkError.bindFailed = error {
                // Expected error
            } else {
                XCTFail("Expected NetworkError.bindFailed")
            }
        }
    }
    
    func testServerAlreadyRunningError() throws {
        let server = TCPServer()
        let port = Int.random(in: 8000...9000)
        try server.start(port: port)
        
        // Should throw error when trying to start again
        XCTAssertThrowsError(try server.start(port: port)) { error in
            XCTAssertTrue(error is ServerError)
            if case ServerError.alreadyRunning = error {
                // Expected error
            } else {
                XCTFail("Expected ServerError.alreadyRunning")
            }
        }
        
        try server.stop()
    }
    
    // MARK: - Protocol Version Tests
    
    func testProtocolVersion() {
        XCTAssertEqual(USBIPProtocol.version, 0x0111, "Protocol version should be 1.1.1")
    }
    
    // MARK: - USB Transfer Type Tests
    
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
    
    // MARK: - Error Response Tests
    
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
    
    // MARK: - CI-Specific Performance Tests
    
    func testMessageEncodingPerformance() throws {
        // Measure encoding performance for CI environment
        let request = USBIPSubmitRequest(
            seqnum: 1,
            devid: 1,
            direction: 0,
            ep: 1,
            transferFlags: 0,
            transferBufferLength: 1024,
            transferBuffer: Data(repeating: 0xFF, count: 1024)
        )
        
        TestExecutionAssertions.assertCompletesWithinTimeLimit(0.1) {
            for _ in 0..<100 {
                _ = try request.encode()
            }
        }
    }
    
    func testMessageDecodingPerformance() throws {
        // Measure decoding performance for CI environment
        let request = USBIPSubmitRequest(
            seqnum: 1,
            devid: 1,
            direction: 0,
            ep: 1,
            transferFlags: 0,
            transferBufferLength: 1024,
            transferBuffer: Data(repeating: 0xFF, count: 1024)
        )
        
        let encodedData = try request.encode()
        
        TestExecutionAssertions.assertCompletesWithinTimeLimit(0.1) {
            for _ in 0..<100 {
                _ = try USBIPSubmitRequest.decode(from: encodedData)
            }
        }
    }
    
    // MARK: - Edge Cases for CI Validation
    
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
}