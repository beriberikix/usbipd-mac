// EndpointDirectionTests.swift
// USB/IP carries endpoint number and direction separately; IOKit expects them combined.

import XCTest
@testable import USBIPDCore
@testable import Common

final class EndpointDirectionTests: XCTestCase {

    private func makeCommunicator() -> USBDeviceCommunicatorImplementation {
        return USBDeviceCommunicatorImplementation(deviceClaimManager: MockDeviceClaimManager())
    }

    private func makeRequest(endpoint: UInt8, direction: USBTransferDirection) -> USBRequestBlock {
        return USBRequestBlock(
            seqnum: 1,
            devid: 0x0001_0011,
            direction: direction,
            endpoint: endpoint,
            transferType: .bulk,
            transferFlags: 0,
            bufferLength: 64,
            setupPacket: nil,
            transferBuffer: nil,
            timeout: 5000
        )
    }

    /// A real Linux client sends ep=1 with direction=IN for a bulk IN transfer. Passing
    /// that through untouched left bit 7 clear, so the transfer ran as an OUT and failed.
    func testInDirectionSetsDirectionBit() {
        let address = makeCommunicator().endpointAddress(for: makeRequest(endpoint: 1, direction: .in))
        XCTAssertEqual(address, 0x81, "An IN transfer on endpoint 1 must address 0x81")
    }

    func testOutDirectionLeavesDirectionBitClear() {
        let address = makeCommunicator().endpointAddress(for: makeRequest(endpoint: 1, direction: .out))
        XCTAssertEqual(address, 0x01, "An OUT transfer on endpoint 1 must address 0x01")
    }

    /// A client that already sets bit 7 must not be double-encoded into a different endpoint.
    func testDirectionBitAlreadySetIsPreserved() {
        let address = makeCommunicator().endpointAddress(for: makeRequest(endpoint: 0x81, direction: .in))
        XCTAssertEqual(address, 0x81, "Endpoint number must survive an already-set direction bit")
    }

    func testDirectionWinsOverStaleDirectionBit() {
        let address = makeCommunicator().endpointAddress(for: makeRequest(endpoint: 0x81, direction: .out))
        XCTAssertEqual(address, 0x01, "The direction field decides, not a stale bit in ep")
    }
}
