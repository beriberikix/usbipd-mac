// USBDeviceCommunicatorTransferTests.swift
// Transfer-specific tests for USB device communicator

import XCTest
@testable import USBIPDCore
@testable import Common
import Foundation

final class USBDeviceCommunicatorTransferTests: XCTestCase {
    
    // MARK: - Test Properties
    
    var deviceCommunicator: USBDeviceCommunicator!
    var mockIOKitInterface: MockIOKitUSBInterface!
    var mockClaimManager: MockDeviceClaimManager!
    var testDevice: USBDevice!
    
    // MARK: - Test Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        mockIOKitInterface = MockIOKitUSBInterface()
        mockClaimManager = MockDeviceClaimManager()
        
        deviceCommunicator = USBDeviceCommunicator(
            ioKitInterface: mockIOKitInterface,
            claimManager: mockClaimManager
        )
        
        testDevice = createTestDevice()
    }
    
    override func tearDown() {
        deviceCommunicator = nil
        mockIOKitInterface = nil  
        mockClaimManager = nil
        testDevice = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func createTestDevice() -> USBDevice {
        return USBDevice(
            busID: "1",
            deviceID: "1",
            vendorID: 0x1234,
            productID: 0x5678,
            deviceClass: 0x09,
            deviceSubClass: 0x00,
            deviceProtocol: 0x00,
            speed: .high,
            interfaces: [
                USBInterface(
                    interfaceNumber: 0,
                    alternateSetting: 0,
                    interfaceClass: 0x09,
                    interfaceSubClass: 0x00,
                    interfaceProtocol: 0x00,
                    endpoints: [
                        USBEndpoint(
                            address: 0x81,
                            direction: .in,
                            transferType: .interrupt,
                            maxPacketSize: 8,
                            interval: 10
                        ),
                        USBEndpoint(
                            address: 0x02,
                            direction: .out,
                            transferType: .bulk,
                            maxPacketSize: 64,
                            interval: 0
                        )
                    ]
                )
            ]
        )
    }
    
    private func createBulkTransferRequest(direction: USBEndpoint.Direction, data: Data? = nil) -> USBRequestBlock {
        return USBRequestBlock(
            requestType: .standard,
            recipient: .device,
            request: 0x00,
            value: 0x0000,
            index: 0x0000,
            bufferLength: UInt32(data?.count ?? 64),
            timeout: 5000,
            data: data,
            transferType: .bulk,
            endpointAddress: direction == .out ? 0x02 : 0x82
        )
    }
    
    private func createInterruptTransferRequest(direction: USBEndpoint.Direction, data: Data? = nil) -> USBRequestBlock {
        return USBRequestBlock(
            requestType: .standard,
            recipient: .device,
            request: 0x00,
            value: 0x0000,
            index: 0x0000,
            bufferLength: UInt32(data?.count ?? 8),
            timeout: 5000,
            data: data,
            transferType: .interrupt,
            endpointAddress: direction == .out ? 0x03 : 0x83
        )
    }
    
    private func createIsochronousTransferRequest(direction: USBEndpoint.Direction, data: Data? = nil) -> USBRequestBlock {
        return USBRequestBlock(
            requestType: .standard,
            recipient: .device,
            request: 0x00,
            value: 0x0000,
            index: 0x0000,
            bufferLength: UInt32(data?.count ?? 64),
            timeout: 5000,
            data: data,
            transferType: .isochronous,
            endpointAddress: direction == .out ? 0x04 : 0x84,
            startFrame: 0,
            numberOfPackets: 1
        )
    }

    // MARK: - Bulk Transfer Tests
    
    func testExecuteBulkTransferOutValidation() async throws {
        let transferData = Data(repeating: 0x42, count: 64)
        let request = createBulkTransferRequest(direction: .out, data: transferData)
        
        mockIOKitInterface.setTransferResponse(
            data: transferData,
            status: .success,
            actualLength: 64
        )
        
        let result = try await deviceCommunicator.executeBulkTransfer(
            device: testDevice,
            request: request
        )
        
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.actualLength, 64)
        XCTAssertEqual(mockIOKitInterface.getOperationCount("performBulkTransfer"), 1)
    }
    
    func testExecuteBulkTransferInValidation() async throws {
        let expectedData = Data(repeating: 0x55, count: 32)
        let request = createBulkTransferRequest(direction: .in)
        
        mockIOKitInterface.setTransferResponse(
            data: expectedData,
            status: .success,
            actualLength: 32
        )
        
        let result = try await deviceCommunicator.executeBulkTransfer(
            device: testDevice,
            request: request
        )
        
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.actualLength, 32)
        XCTAssertEqual(result.data, expectedData)
    }
    
    func testExecuteBulkTransferTimeout() async throws {
        let request = createBulkTransferRequest(direction: .out)
        
        mockIOKitInterface.setTransferError(USBRequestError.timeout)
        
        do {
            _ = try await deviceCommunicator.executeBulkTransfer(
                device: testDevice,
                request: request
            )
            XCTFail("Expected timeout error")
        } catch {
            XCTAssertTrue(error is USBRequestError)
            if let usbError = error as? USBRequestError {
                XCTAssertEqual(usbError, .timeout)
            }
        }
    }
    
    // MARK: - Interrupt Transfer Tests
    
    func testExecuteInterruptTransferValidation() async throws {
        let transferData = Data([0x01, 0x02, 0x03, 0x04])
        let request = createInterruptTransferRequest(direction: .out, data: transferData)
        
        mockIOKitInterface.setTransferResponse(
            data: transferData,
            status: .success,
            actualLength: 4
        )
        
        let result = try await deviceCommunicator.executeInterruptTransfer(
            device: testDevice,
            request: request
        )
        
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.actualLength, 4)
        XCTAssertEqual(mockIOKitInterface.getOperationCount("performInterruptTransfer"), 1)
    }
    
    func testExecuteInterruptTransferDeviceNotAvailable() async throws {
        let request = createInterruptTransferRequest(direction: .in)
        
        mockIOKitInterface.setTransferError(USBRequestError.deviceNotAvailable)
        
        do {
            _ = try await deviceCommunicator.executeInterruptTransfer(
                device: testDevice,
                request: request
            )
            XCTFail("Expected device not available error")
        } catch {
            XCTAssertTrue(error is USBRequestError)
            if let usbError = error as? USBRequestError {
                XCTAssertEqual(usbError, .deviceNotAvailable)
            }
        }
    }
    
    // MARK: - Isochronous Transfer Tests
    
    func testExecuteIsochronousTransferValidation() async throws {
        let transferData = Data(repeating: 0xFF, count: 1024)
        let request = createIsochronousTransferRequest(direction: .out, data: transferData)
        
        mockIOKitInterface.setTransferResponse(
            data: transferData,
            status: .success,
            actualLength: 1024
        )
        
        let result = try await deviceCommunicator.executeIsochronousTransfer(
            device: testDevice,
            request: request
        )
        
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.actualLength, 1024)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(mockIOKitInterface.getOperationCount("performIsochronousTransfer"), 1)
    }
    
    func testExecuteIsochronousTransferPartialData() async throws {
        let request = createIsochronousTransferRequest(direction: .in)
        
        mockIOKitInterface.setTransferResponse(
            data: Data(repeating: 0xAA, count: 512),
            status: .success,
            actualLength: 512
        )
        
        let result = try await deviceCommunicator.executeIsochronousTransfer(
            device: testDevice,
            request: request
        )
        
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.actualLength, 512)
        XCTAssertNotNil(result.data)
        XCTAssertEqual(result.data?.count, 512)
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