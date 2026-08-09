// StaleInterfaceTests.swift
// A cached interface must be dropped once its device is gone, and kept otherwise.

import XCTest
@testable import USBIPDCore
@testable import Common

final class StaleInterfaceTests: XCTestCase {

    /// Interfaces are opened once and reused, which is right while a device stays put
    /// and wrong the moment it does not. A device that disappeared briefly left the
    /// daemon holding a dead IOKit handle, and every transfer through it failed with
    /// "no device" until the daemon was restarted — observed with a Pixel, where a fresh
    /// daemon worked immediately while the running one never recovered.
    func testDeviceGoneDiscardsTheInterface() {
        XCTAssertTrue(USBDeviceCommunicatorImplementation.shouldDiscardInterface(after: .deviceGone))
    }

    /// The other half, and the more important one. Reopening on any old failure would
    /// throw away a perfectly good interface on every stall or timeout — and a timeout
    /// is the ordinary outcome of a read on an endpoint with nothing to say, which this
    /// project's own concurrency check produces on purpose.
    func testOrdinaryFailuresKeepTheInterface() {
        let keepers: [USBIPDCore.USBStatus] = [
            .success,
            .timeout,
            .cancelled,
            .stall,
            .shortPacket,
            .bufferError,
            .invalidRequest,
            .requestFailed
        ]
        for status in keepers {
            XCTAssertFalse(
                USBDeviceCommunicatorImplementation.shouldDiscardInterface(after: status),
                "\(status) must not discard a usable interface")
        }
    }

    /// Both IOKit codes that mean the device is finished map to the same status, so
    /// covering `deviceGone` covers `kIOReturnNoDevice` and `kIOReturnNotResponding`.
    func testBothIOKitDeviceGoneCodesMapToTheDiscardedStatus() {
        XCTAssertEqual(USBErrorMapping.mapIOKitError(kIOReturnNoDevice), USBStatus.deviceGone.rawValue)
        XCTAssertEqual(USBErrorMapping.mapIOKitError(kIOReturnNotResponding), USBStatus.deviceGone.rawValue)

        // And a timeout does not, or the check above would be vacuous.
        XCTAssertNotEqual(USBErrorMapping.mapIOKitError(kIOReturnTimeout), USBStatus.deviceGone.rawValue)
    }
}
