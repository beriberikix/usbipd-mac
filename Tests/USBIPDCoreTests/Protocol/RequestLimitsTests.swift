// RequestLimitsTests.swift
// ServerConfig carried these limits from the start and nothing read them.

import XCTest
@testable import USBIPDCore
@testable import Common

final class RequestLimitsTests: XCTestCase {

    private func makeRequestData(bufferLength: UInt32) throws -> Data {
        let request = USBIPSubmitRequest(
            seqnum: 1,
            devid: 0x0001_0011,
            direction: 1,
            ep: 1,
            transferFlags: 0,
            transferBufferLength: bufferLength,
            startFrame: 0,
            numberOfPackets: 0,
            interval: 0,
            setup: Data(count: 8),
            transferBuffer: nil
        )
        return try request.encode()
    }

    /// IOKitUSBInterface allocates Int(bufferLength) straight from this field, so an
    /// unbounded UInt32 lets a remote client request an allocation of up to 4 GiB.
    func testOversizedTransferIsRejected() async throws {
        let config = ServerConfig()
        config.maxUSBBufferSize = 65536
        let processor = USBSubmitProcessor(config: config)

        let response = try await processor.processSubmitRequest(makeRequestData(bufferLength: 1_048_576))
        let decoded = try USBIPSubmitResponse.decode(from: response)

        // Assert the specific status. Merely checking "not success" passes even with
        // the size guard removed, because the request then fails later on device
        // lookup instead — a vacuous test that a negative control caught.
        XCTAssertEqual(decoded.status, -22, "Oversized transfer must be refused with EINVAL, not fail later")
    }

    func testTransferWithinLimitIsNotRejectedForSize() async throws {
        let config = ServerConfig()
        config.maxUSBBufferSize = 65536
        let processor = USBSubmitProcessor(config: config)

        // No communicator or discovery is configured, so this fails on device lookup
        // rather than on size. The point is that it gets past the size check at all.
        let response = try await processor.processSubmitRequest(makeRequestData(bufferLength: 4096))
        let decoded = try USBIPSubmitResponse.decode(from: response)

        // ENODEV, not EINVAL: this got past the size check and failed on device lookup,
        // which is what distinguishes it from the oversized case above.
        XCTAssertEqual(decoded.status, -19, "A transfer within the limit must reach device lookup")
    }

    func testDefaultsMatchThePreviouslyHardcodedLimits() {
        let config = ServerConfig()
        XCTAssertEqual(config.maxTotalConcurrentRequests, 64)
        XCTAssertEqual(config.maxPendingURBsPerDevice, 32)
        XCTAssertEqual(config.maxUSBBufferSize, 1_048_576)
        XCTAssertEqual(config.usbOperationTimeout, 5000)
    }
}

/// The bulk path uses ReadPipeTO/WritePipeTO, which report expiry with IOUSBFamily's
/// own timeout code rather than kIOReturnTimeout.
final class IOKitTimeoutMappingTests: XCTestCase {

    func testTransactionTimeoutMapsToETIMEDOUT() {
        let status = USBErrorMapping.mapIOKitError(IOReturn(bitPattern: 0xE000_4051))
        XCTAssertEqual(status, -110, "kIOUSBTransactionTimeout must map to ETIMEDOUT")
    }

    func testGenericTimeoutStillMapsToETIMEDOUT() {
        XCTAssertEqual(USBErrorMapping.mapIOKitError(kIOReturnTimeout), -110)
    }

    /// Before the mapping existed a timed-out transfer surfaced as EPROTO, telling the
    /// client its protocol was wrong rather than that the device had nothing to say.
    func testTransactionTimeoutIsNotReportedAsProtocolError() {
        XCTAssertNotEqual(USBErrorMapping.mapIOKitError(IOReturn(bitPattern: 0xE000_4051)), -71)
    }
}
