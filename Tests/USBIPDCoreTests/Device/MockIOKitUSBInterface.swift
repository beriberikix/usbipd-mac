// MockIOKitUSBInterface.swift
// Mock IOKit USB interface for isolated testing

import Foundation
import IOKit
import IOKit.usb
import Common
@testable import USBIPDCore

/// Mock IOKit USB interface for isolated testing of USB communication layer
public class MockIOKitUSBInterface {
    
    // MARK: - Mock Configuration
    
    /// Controls whether interface operations should succeed or fail
    public var shouldFailOperations = false
    
    /// Specific error to return when operations fail
    public var operationError: Error = USBRequestError.deviceNotAvailable
    
    /// Controls whether open/close operations should succeed
    public var shouldFailOpen = false
    public var shouldFailClose = false
    
    /// Controls latency for async operations (in milliseconds)
    public var operationLatency: UInt32 = 0
    
    /// Controls whether specific transfer types should fail
    public var shouldFailControlTransfers = false
    public var shouldFailBulkTransfers = false
    public var shouldFailInterruptTransfers = false
    public var shouldFailIsochronousTransfers = false
    
    /// Mock responses for different transfer types
    public var controlTransferResponse: Data?
    public var bulkTransferResponse: Data?
    public var interruptTransferResponse: Data?
    public var isochronousTransferResponse: Data?
    
    /// Controls mock USB status responses
    public var controlTransferStatus: USBStatus = .success
    public var bulkTransferStatus: USBStatus = .success
    public var interruptTransferStatus: USBStatus = .success
    public var isochronousTransferStatus: USBStatus = .success
    
    /// Controls actual length returned in responses
    public var controlTransferActualLength: UInt32?
    public var bulkTransferActualLength: UInt32?
    public var interruptTransferActualLength: UInt32?
    public var isochronousTransferActualLength: UInt32?
    
    /// Controls error count for isochronous transfers
    public var isochronousErrorCount: UInt32 = 0
    
    // MARK: - Request Tracking
    
    /// Track all operations for test verification
    public struct OperationCall {
        public let operation: String
        public let endpoint: UInt8
        public let timestamp: Date
        public let parameters: [String: Any]
        
        public init(operation: String, endpoint: UInt8, parameters: [String: Any] = [:]) {
            self.operation = operation
            self.endpoint = endpoint
            self.timestamp = Date()
            self.parameters = parameters
        }
    }
    
    /// All operation calls made to this mock interface
    public private(set) var operationCalls: [OperationCall] = []
    
    /// Track open/close calls
    public private(set) var openCalls: [Date] = []
    public private(set) var closeCalls: [Date] = []
    
    /// Track current interface state
    public private(set) var isOpen: Bool = false
    
    // MARK: - Mock Device Properties
    
    public let device: USBDevice
    public let interfaceNumber: UInt8
    
    // MARK: - Initialization
    
    public init(device: USBDevice, interfaceNumber: UInt8 = 0) {
        self.device = device
        self.interfaceNumber = interfaceNumber
    }
    
    // MARK: - Reset and Configuration Methods
    
    /// Reset all mock state for a fresh test
    public func reset() {
        shouldFailOperations = false
        operationError = USBRequestError.deviceNotAvailable
        shouldFailOpen = false
        shouldFailClose = false
        operationLatency = 0
        
        shouldFailControlTransfers = false
        shouldFailBulkTransfers = false
        shouldFailInterruptTransfers = false
        shouldFailIsochronousTransfers = false
        
        controlTransferResponse = nil
        bulkTransferResponse = nil
        interruptTransferResponse = nil
        isochronousTransferResponse = nil
        
        controlTransferStatus = .success
        bulkTransferStatus = .success
        interruptTransferStatus = .success
        isochronousTransferStatus = .success
        
        controlTransferActualLength = nil
        bulkTransferActualLength = nil
        interruptTransferActualLength = nil
        isochronousTransferActualLength = nil
        
        isochronousErrorCount = 0
        
        operationCalls.removeAll()
        openCalls.removeAll()
        closeCalls.removeAll()
        isOpen = false
    }
    
    /// Configure a successful control transfer response
    public func setControlTransferResponse(data: Data, status: USBStatus = .success, actualLength: UInt32? = nil) {
        controlTransferResponse = data
        controlTransferStatus = status
        controlTransferActualLength = actualLength ?? UInt32(data.count)
    }
    
    /// Configure a successful bulk transfer response
    public func setBulkTransferResponse(data: Data, status: USBStatus = .success, actualLength: UInt32? = nil) {
        bulkTransferResponse = data
        bulkTransferStatus = status
        bulkTransferActualLength = actualLength ?? UInt32(data.count)
    }
    
    /// Configure a successful interrupt transfer response
    public func setInterruptTransferResponse(data: Data, status: USBStatus = .success, actualLength: UInt32? = nil) {
        interruptTransferResponse = data
        interruptTransferStatus = status
        interruptTransferActualLength = actualLength ?? UInt32(data.count)
    }
    
    /// Configure a successful isochronous transfer response
    public func setIsochronousTransferResponse(data: Data, status: USBStatus = .success, actualLength: UInt32? = nil, errorCount: UInt32 = 0) {
        isochronousTransferResponse = data
        isochronousTransferStatus = status
        isochronousTransferActualLength = actualLength ?? UInt32(data.count)
        isochronousErrorCount = errorCount
    }
    
    /// Configure mock to simulate specific error conditions
    public func simulateError(_ error: Error, forOperation operation: String? = nil) {
        if let operation = operation {
            switch operation {
            case "control":
                shouldFailControlTransfers = true
                controlTransferStatus = .requestFailed
            case "bulk":
                shouldFailBulkTransfers = true
                bulkTransferStatus = .requestFailed
            case "interrupt":
                shouldFailInterruptTransfers = true
                interruptTransferStatus = .requestFailed
            case "isochronous":
                shouldFailIsochronousTransfers = true
                isochronousTransferStatus = .requestFailed
            case "open":
                shouldFailOpen = true
            case "close":
                shouldFailClose = true
            default:
                shouldFailOperations = true
            }
        } else {
            shouldFailOperations = true
        }
        operationError = error
    }
    
    /// Configure mock to simulate timeout conditions
    public func simulateTimeout(forOperation operation: String? = nil) {
        if let operation = operation {
            switch operation {
            case "control":
                shouldFailControlTransfers = true
                controlTransferStatus = .timeout
            case "bulk":
                shouldFailBulkTransfers = true
                bulkTransferStatus = .timeout
            case "interrupt":
                shouldFailInterruptTransfers = true
                interruptTransferStatus = .timeout
            case "isochronous":
                shouldFailIsochronousTransfers = true
                isochronousTransferStatus = .timeout
            default:
                shouldFailOperations = true
                operationError = USBRequestError.timeout
            }
        } else {
            shouldFailOperations = true
            operationError = USBRequestError.timeout
        }
    }
    
    /// Configure mock to simulate device disconnection
    public func simulateDeviceDisconnection() {
        shouldFailOperations = true
        operationError = USBRequestError.deviceNotAvailable
        controlTransferStatus = .deviceGone
        bulkTransferStatus = .deviceGone
        interruptTransferStatus = .deviceGone
        isochronousTransferStatus = .deviceGone
    }
    
    // MARK: - Interface Lifecycle Methods
    
    /// Mock open operation
    public func open() throws {
        openCalls.append(Date())
        
        if shouldFailOpen || shouldFailOperations {
            throw operationError
        }
        
        isOpen = true
    }
    
    /// Mock close operation
    public func close() throws {
        closeCalls.append(Date())
        
        if shouldFailClose || (shouldFailOperations && isOpen) {
            throw operationError
        }
        
        isOpen = false
    }
    
    // MARK: - Transfer Methods
    
    /// Mock control transfer execution
    public func executeControlTransfer(
        endpoint: UInt8,
        setupPacket: Data,
        transferBuffer: Data?,
        timeout: UInt32
    ) async throws -> USBTransferResult {
        
        let call = OperationCall(
            operation: "control_transfer",
            endpoint: endpoint,
            parameters: [
                "setup_packet": setupPacket,
                "transfer_buffer": transferBuffer as Any,
                "timeout": timeout
            ]
        )
        operationCalls.append(call)
        
        // Check if interface is open
        guard isOpen else {
            throw USBRequestError.deviceNotAvailable
        }
        
        // Simulate operation latency
        if operationLatency > 0 {
            try await Task.sleep(nanoseconds: UInt64(operationLatency) * 1_000_000)
        }
        
        // Check for specific control transfer failures
        if shouldFailControlTransfers || shouldFailOperations {
            throw operationError
        }
        
        // Validate setup packet
        guard setupPacket.count == 8 else {
            throw USBRequestError.setupPacketInvalid
        }
        
        // Extract transfer direction from setup packet
        let bmRequestType = setupPacket[0]
        let isIn = (bmRequestType & 0x80) != 0
        
        // Determine response data
        var responseData: Data? = nil
        var actualLength: UInt32 = 0
        
        if isIn {
            // IN transfer - return mock response data
            responseData = controlTransferResponse
            actualLength = controlTransferActualLength ?? UInt32(controlTransferResponse?.count ?? 0)
        } else {
            // OUT transfer - acknowledge the sent data
            actualLength = controlTransferActualLength ?? UInt32(transferBuffer?.count ?? 0)
        }
        
        return USBTransferResult(
            status: controlTransferStatus,
            actualLength: actualLength,
            data: responseData,
            completionTime: Date().timeIntervalSince1970
        )
    }
    
    /// Mock bulk transfer execution
    public func executeBulkTransfer(
        endpoint: UInt8,
        data: Data?,
        bufferLength: UInt32,
        timeout: UInt32
    ) async throws -> USBTransferResult {
        
        let call = OperationCall(
            operation: "bulk_transfer",
            endpoint: endpoint,
            parameters: [
                "data": data as Any,
                "buffer_length": bufferLength,
                "timeout": timeout
            ]
        )
        operationCalls.append(call)
        
        // Check if interface is open
        guard isOpen else {
            throw USBRequestError.deviceNotAvailable
        }
        
        // Simulate operation latency
        if operationLatency > 0 {
            try await Task.sleep(nanoseconds: UInt64(operationLatency) * 1_000_000)
        }
        
        // Check for specific bulk transfer failures
        if shouldFailBulkTransfers || shouldFailOperations {
            throw operationError
        }
        
        // Determine transfer direction from endpoint
        let isIn = (endpoint & 0x80) != 0
        
        // Determine response data
        var responseData: Data? = nil
        var actualLength: UInt32 = 0
        
        if isIn {
            // IN transfer - return mock response data
            responseData = bulkTransferResponse
            actualLength = bulkTransferActualLength ?? UInt32(bulkTransferResponse?.count ?? 0)
        } else {
            // OUT transfer - acknowledge the sent data
            actualLength = bulkTransferActualLength ?? UInt32(data?.count ?? 0)
        }
        
        return USBTransferResult(
            status: bulkTransferStatus,
            actualLength: actualLength,
            data: responseData,
            completionTime: Date().timeIntervalSince1970
        )
    }
    
    /// Mock interrupt transfer execution
    public func executeInterruptTransfer(
        endpoint: UInt8,
        data: Data?,
        bufferLength: UInt32,
        timeout: UInt32
    ) async throws -> USBTransferResult {
        
        let call = OperationCall(
            operation: "interrupt_transfer",
            endpoint: endpoint,
            parameters: [
                "data": data as Any,
                "buffer_length": bufferLength,
                "timeout": timeout
            ]
        )
        operationCalls.append(call)
        
        // Check if interface is open
        guard isOpen else {
            throw USBRequestError.deviceNotAvailable
        }
        
        // Simulate operation latency
        if operationLatency > 0 {
            try await Task.sleep(nanoseconds: UInt64(operationLatency) * 1_000_000)
        }
        
        // Check for specific interrupt transfer failures
        if shouldFailInterruptTransfers || shouldFailOperations {
            throw operationError
        }
        
        // Determine transfer direction from endpoint
        let isIn = (endpoint & 0x80) != 0
        
        // Determine response data
        var responseData: Data? = nil
        var actualLength: UInt32 = 0
        
        if isIn {
            // IN transfer - return mock response data
            responseData = interruptTransferResponse
            actualLength = interruptTransferActualLength ?? UInt32(interruptTransferResponse?.count ?? 0)
        } else {
            // OUT transfer - acknowledge the sent data
            actualLength = interruptTransferActualLength ?? UInt32(data?.count ?? 0)
        }
        
        return USBTransferResult(
            status: interruptTransferStatus,
            actualLength: actualLength,
            data: responseData,
            completionTime: Date().timeIntervalSince1970
        )
    }
    
    /// Mock isochronous transfer execution
    public func executeIsochronousTransfer(
        endpoint: UInt8,
        data: Data?,
        bufferLength: UInt32,
        startFrame: UInt32,
        numberOfPackets: UInt32
    ) async throws -> USBTransferResult {
        
        let call = OperationCall(
            operation: "isochronous_transfer",
            endpoint: endpoint,
            parameters: [
                "data": data as Any,
                "buffer_length": bufferLength,
                "start_frame": startFrame,
                "number_of_packets": numberOfPackets
            ]
        )
        operationCalls.append(call)
        
        // Check if interface is open
        guard isOpen else {
            throw USBRequestError.deviceNotAvailable
        }
        
        // Simulate operation latency
        if operationLatency > 0 {
            try await Task.sleep(nanoseconds: UInt64(operationLatency) * 1_000_000)
        }
        
        // Check for specific isochronous transfer failures
        if shouldFailIsochronousTransfers || shouldFailOperations {
            throw operationError
        }
        
        // Determine transfer direction from endpoint
        let isIn = (endpoint & 0x80) != 0
        
        // Determine response data
        var responseData: Data? = nil
        var actualLength: UInt32 = 0
        
        if isIn {
            // IN transfer - return mock response data
            responseData = isochronousTransferResponse
            actualLength = isochronousTransferActualLength ?? UInt32(isochronousTransferResponse?.count ?? 0)
        } else {
            // OUT transfer - acknowledge the sent data
            actualLength = isochronousTransferActualLength ?? UInt32(data?.count ?? 0)
        }
        
        return USBTransferResult(
            status: isochronousTransferStatus,
            actualLength: actualLength,
            errorCount: isochronousErrorCount,
            data: responseData,
            completionTime: Date().timeIntervalSince1970,
            startFrame: startFrame
        )
    }
    
    // MARK: - Validation and Test Helper Methods
    
    /// Verify that a specific operation was called
    public func wasOperationCalled(_ operation: String, endpoint: UInt8? = nil) -> Bool {
        return operationCalls.contains { call in
            call.operation == operation && (endpoint == nil || call.endpoint == endpoint)
        }
    }
    
    /// Get all calls for a specific operation
    public func getOperationCalls(_ operation: String) -> [OperationCall] {
        return operationCalls.filter { $0.operation == operation }
    }
    
    /// Get the last call for a specific operation
    public func getLastOperationCall(_ operation: String) -> OperationCall? {
        return operationCalls.last { $0.operation == operation }
    }
    
    /// Verify that interface was opened and closed properly
    public func verifyLifecycle() -> (opened: Bool, closed: Bool, properSequence: Bool) {
        let opened = !openCalls.isEmpty
        let closed = !closeCalls.isEmpty
        var properSequence = true
        
        if opened && closed && !openCalls.isEmpty && !closeCalls.isEmpty {
            // Check that the last open was before the last close
            properSequence = openCalls.last! < closeCalls.last!
        }
        
        return (opened: opened, closed: closed, properSequence: properSequence)
    }
    
    /// Get total number of transfer operations performed
    public var totalTransferOperations: Int {
        return operationCalls.filter { call in
            ["control_transfer", "bulk_transfer", "interrupt_transfer", "isochronous_transfer"].contains(call.operation)
        }.count
    }
    
    /// Get operations by endpoint
    public func getOperationsByEndpoint() -> [UInt8: [OperationCall]] {
        var result: [UInt8: [OperationCall]] = [:]
        for call in operationCalls {
            if result[call.endpoint] == nil {
                result[call.endpoint] = []
            }
            result[call.endpoint]?.append(call)
        }
        return result
    }
    
    /// Simulate a partial transfer (short packet)
    public func simulatePartialTransfer(operation: String, partialLength: UInt32) {
        switch operation {
        case "control":
            controlTransferStatus = .shortPacket
            controlTransferActualLength = partialLength
        case "bulk":
            bulkTransferStatus = .shortPacket
            bulkTransferActualLength = partialLength
        case "interrupt":
            interruptTransferStatus = .shortPacket
            interruptTransferActualLength = partialLength
        case "isochronous":
            isochronousTransferStatus = .shortPacket
            isochronousTransferActualLength = partialLength
        default:
            break
        }
    }
    
    /// Simulate a stalled endpoint
    public func simulateEndpointStall(operation: String) {
        switch operation {
        case "control":
            controlTransferStatus = .stall
        case "bulk":
            bulkTransferStatus = .stall
        case "interrupt":
            interruptTransferStatus = .stall
        case "isochronous":
            isochronousTransferStatus = .stall
        default:
            break
        }
    }
    
    /// Generate mock descriptor data for testing
    public func generateMockDescriptorData() -> Data {
        // Generate a mock device descriptor
        var descriptor = Data()
        descriptor.append(0x12) // bLength
        descriptor.append(0x01) // bDescriptorType (Device)
        descriptor.append(0x00) // bcdUSB (low)
        descriptor.append(0x02) // bcdUSB (high) - USB 2.0
        descriptor.append(UInt8(device.deviceClass)) // bDeviceClass
        descriptor.append(device.deviceSubClass) // bDeviceSubClass
        descriptor.append(device.deviceProtocol) // bDeviceProtocol
        descriptor.append(0x40) // bMaxPacketSize0 (64 bytes)
        descriptor.append(UInt8(device.vendorID & 0xFF)) // idVendor (low)
        descriptor.append(UInt8(device.vendorID >> 8)) // idVendor (high)
        descriptor.append(UInt8(device.productID & 0xFF)) // idProduct (low)
        descriptor.append(UInt8(device.productID >> 8)) // idProduct (high)
        descriptor.append(0x00) // bcdDevice (low)
        descriptor.append(0x01) // bcdDevice (high)
        descriptor.append(0x01) // iManufacturer
        descriptor.append(0x02) // iProduct
        descriptor.append(0x03) // iSerialNumber
        descriptor.append(0x01) // bNumConfigurations
        
        return descriptor
    }
    
    /// Generate mock string descriptor data
    public func generateMockStringDescriptor(_ string: String) -> Data {
        let utf16Data = string.data(using: .utf16LittleEndian) ?? Data()
        var descriptor = Data()
        descriptor.append(UInt8(2 + utf16Data.count)) // bLength
        descriptor.append(0x03) // bDescriptorType (String)
        descriptor.append(utf16Data)
        return descriptor
    }
}

// MARK: - Mock USB Transfer Result Extensions

extension USBTransferResult {
    /// Create a mock success result
    public static func mockSuccess(data: Data? = nil, actualLength: UInt32? = nil) -> USBTransferResult {
        return USBTransferResult(
            status: .success,
            actualLength: actualLength ?? UInt32(data?.count ?? 0),
            data: data,
            completionTime: Date().timeIntervalSince1970
        )
    }
    
    /// Create a mock error result
    public static func mockError(_ status: USBStatus, actualLength: UInt32 = 0) -> USBTransferResult {
        return USBTransferResult(
            status: status,
            actualLength: actualLength,
            completionTime: Date().timeIntervalSince1970
        )
    }
    
    /// Create a mock timeout result
    public static func mockTimeout() -> USBTransferResult {
        return USBTransferResult(
            status: .timeout,
            actualLength: 0,
            completionTime: Date().timeIntervalSince1970
        )
    }
    
    /// Create a mock partial transfer result
    public static func mockPartialTransfer(data: Data, actualLength: UInt32) -> USBTransferResult {
        return USBTransferResult(
            status: .shortPacket,
            actualLength: actualLength,
            data: data,
            completionTime: Date().timeIntervalSince1970
        )
    }
}