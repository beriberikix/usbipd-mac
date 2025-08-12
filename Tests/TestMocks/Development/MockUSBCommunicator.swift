// MockUSBCommunicator.swift
// Comprehensive USB communication mock for development environment testing
// Provides reliable, fast USB transfer simulation without hardware dependencies

import Foundation
import Common
@testable import USBIPDCore

// MARK: - Mock USB Device Communicator

/// Comprehensive mock for USB device communication in development environment
/// Simulates USB transfers with configurable responses and timing
public class MockUSBDeviceCommunicator: USBDeviceCommunicatorInterface {
    
    // MARK: - Mock Configuration
    
    /// Control transfer operation outcomes
    public var shouldFailControlTransfers = false
    public var shouldFailBulkTransfers = false
    public var shouldFailInterruptTransfers = false
    public var shouldFailIsochronousTransfers = false
    
    /// Mock responses for different transfer types
    public var controlTransferResponse: Data?
    public var bulkTransferResponse: Data?
    public var interruptTransferResponse: Data?
    public var isochronousTransferResponse: Data?
    
    /// Mock USB status codes
    public var controlTransferStatus: USBStatus = .success
    public var bulkTransferStatus: USBStatus = .success
    public var interruptTransferStatus: USBStatus = .success
    public var isochronousTransferStatus: USBStatus = .success
    
    /// Mock actual transfer lengths
    public var controlTransferActualLength: UInt32?
    public var bulkTransferActualLength: UInt32?
    public var interruptTransferActualLength: UInt32?
    public var isochronousTransferActualLength: UInt32?
    
    /// Transfer timing simulation
    public var controlTransferLatency: TimeInterval = 0.001 // 1ms
    public var bulkTransferLatency: TimeInterval = 0.002 // 2ms
    public var interruptTransferLatency: TimeInterval = 0.001 // 1ms
    public var isochronousTransferLatency: TimeInterval = 0.001 // 1ms
    
    /// Connection state simulation
    public var shouldFailConnection = false
    public var shouldFailDisconnection = false
    public var isConnected = false
    
    // MARK: - Transfer Tracking
    
    /// Track all transfer operations for verification
    public struct TransferCall {
        public let transferType: String
        public let endpoint: UInt8
        public let direction: USBTransferDirection
        public let data: Data?
        public let timestamp: Date
        public let parameters: [String: Any]
        
        public init(
            transferType: String,
            endpoint: UInt8,
            direction: USBTransferDirection,
            data: Data? = nil,
            parameters: [String: Any] = [:]
        ) {
            self.transferType = transferType
            self.endpoint = endpoint
            self.direction = direction
            self.data = data
            self.timestamp = Date()
            self.parameters = parameters
        }
    }
    
    /// All transfer calls made to this mock
    public private(set) var transferCalls: [TransferCall] = []
    
    /// Track connection/disconnection calls
    public private(set) var connectionCalls: [Date] = []
    public private(set) var disconnectionCalls: [Date] = []
    
    // MARK: - Development Environment Features
    
    /// Enable detailed debug logging
    public var debugLoggingEnabled = true
    
    /// Performance metrics tracking
    public private(set) var transferTimings: [String: [TimeInterval]] = [:]
    
    /// Error injection for specific endpoints
    public var endpointErrors: [UInt8: USBError] = [:]
    
    /// Bandwidth simulation (bytes per second)
    public var simulatedBandwidth: UInt64 = 480_000_000 // 480 Mbps (High-speed USB)
    
    /// Device properties
    public let device: USBDevice
    public let interfaceNumber: UInt8
    
    public init(device: USBDevice, interfaceNumber: UInt8 = 0) {
        self.device = device
        self.interfaceNumber = interfaceNumber
    }
    
    // MARK: - Reset and Configuration
    
    /// Reset all mock state for clean testing
    public func reset() {
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
        
        controlTransferLatency = 0.001
        bulkTransferLatency = 0.002
        interruptTransferLatency = 0.001
        isochronousTransferLatency = 0.001
        
        shouldFailConnection = false
        shouldFailDisconnection = false
        isConnected = false
        
        transferCalls.removeAll()
        connectionCalls.removeAll()
        disconnectionCalls.removeAll()
        transferTimings.removeAll()
        endpointErrors.removeAll()
        
        simulatedBandwidth = 480_000_000
    }
    
    // MARK: - USBDeviceCommunicatorInterface Implementation
    
    public func connect() async throws {
        connectionCalls.append(Date())
        
        if debugLoggingEnabled {
            print("MOCK: Connecting to USB device: \(device.productString ?? "Unknown")")
        }
        
        if shouldFailConnection {
            let error = USBError.connectionFailed("Mock connection failure")
            if debugLoggingEnabled {
                print("MOCK: Connection failed: \(error)")
            }
            throw error
        }
        
        // Simulate brief connection delay
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        isConnected = true
        
        if debugLoggingEnabled {
            print("MOCK: Successfully connected to USB device")
        }
    }
    
    public func disconnect() async throws {
        disconnectionCalls.append(Date())
        
        if debugLoggingEnabled {
            print("MOCK: Disconnecting from USB device")
        }
        
        if shouldFailDisconnection {
            let error = USBError.disconnectionFailed("Mock disconnection failure")
            if debugLoggingEnabled {
                print("MOCK: Disconnection failed: \(error)")
            }
            throw error
        }
        
        // Simulate brief disconnection delay
        try await Task.sleep(nanoseconds: 5_000_000) // 5ms
        
        isConnected = false
        
        if debugLoggingEnabled {
            print("MOCK: Successfully disconnected from USB device")
        }
    }
    
    public func controlTransfer(
        requestType: UInt8,
        request: UInt8,
        value: UInt16,
        index: UInt16,
        data: Data?,
        direction: USBTransferDirection,
        timeout: TimeInterval
    ) async throws -> USBTransferResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let transferCall = TransferCall(
            transferType: "control",
            endpoint: 0,
            direction: direction,
            data: data,
            parameters: [
                "requestType": requestType,
                "request": request,
                "value": value,
                "index": index,
                "timeout": timeout
            ]
        )
        transferCalls.append(transferCall)
        
        if debugLoggingEnabled {
            print("MOCK: Control transfer - requestType: 0x\(String(requestType, radix: 16)), request: 0x\(String(request, radix: 16)), direction: \(direction)")
        }
        
        // Check for endpoint-specific errors
        if let error = endpointErrors[0] {
            if debugLoggingEnabled {
                print("MOCK: Control transfer failed with endpoint error: \(error)")
            }
            throw error
        }
        
        // Check for configured failure
        if shouldFailControlTransfers {
            let error = USBError.transferFailed("Mock control transfer failure")
            if debugLoggingEnabled {
                print("MOCK: Control transfer failed: \(error)")
            }
            throw error
        }
        
        // Simulate transfer latency
        if controlTransferLatency > 0 {
            let latencyNanoseconds = UInt64(controlTransferLatency * 1_000_000_000)
            try await Task.sleep(nanoseconds: latencyNanoseconds)
        }
        
        // Calculate actual length
        let actualLength: UInt32
        if let configuredLength = controlTransferActualLength {
            actualLength = configuredLength
        } else if direction == .out, let outData = data {
            actualLength = UInt32(outData.count)
        } else if direction == .in, let responseData = controlTransferResponse {
            actualLength = UInt32(responseData.count)
        } else {
            actualLength = 0
        }
        
        // Prepare response data
        let responseData: Data?
        if direction == .in {
            responseData = controlTransferResponse
        } else {
            responseData = nil
        }
        
        let result = USBTransferResult(
            status: controlTransferStatus,
            data: responseData,
            actualLength: actualLength
        )
        
        // Track timing
        let transferTime = CFAbsoluteTimeGetCurrent() - startTime
        if transferTimings["control"] == nil {
            transferTimings["control"] = []
        }
        transferTimings["control"]?.append(transferTime)
        
        if debugLoggingEnabled {
            print("MOCK: Control transfer completed - status: \(controlTransferStatus), actualLength: \(actualLength)")
        }
        
        return result
    }
    
    public func bulkTransfer(
        endpoint: UInt8,
        data: Data?,
        direction: USBTransferDirection,
        timeout: TimeInterval
    ) async throws -> USBTransferResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let transferCall = TransferCall(
            transferType: "bulk",
            endpoint: endpoint,
            direction: direction,
            data: data,
            parameters: [
                "timeout": timeout
            ]
        )
        transferCalls.append(transferCall)
        
        if debugLoggingEnabled {
            print("MOCK: Bulk transfer - endpoint: 0x\(String(endpoint, radix: 16)), direction: \(direction)")
        }
        
        // Check for endpoint-specific errors
        if let error = endpointErrors[endpoint] {
            if debugLoggingEnabled {
                print("MOCK: Bulk transfer failed with endpoint error: \(error)")
            }
            throw error
        }
        
        // Check for configured failure
        if shouldFailBulkTransfers {
            let error = USBError.transferFailed("Mock bulk transfer failure")
            if debugLoggingEnabled {
                print("MOCK: Bulk transfer failed: \(error)")
            }
            throw error
        }
        
        // Simulate bandwidth-based latency
        let transferSize = data?.count ?? bulkTransferResponse?.count ?? 0
        let bandwidthLatency = TimeInterval(transferSize * 8) / TimeInterval(simulatedBandwidth) // Convert to seconds
        let totalLatency = max(bulkTransferLatency, bandwidthLatency)
        
        if totalLatency > 0 {
            let latencyNanoseconds = UInt64(totalLatency * 1_000_000_000)
            try await Task.sleep(nanoseconds: latencyNanoseconds)
        }
        
        // Calculate actual length
        let actualLength: UInt32
        if let configuredLength = bulkTransferActualLength {
            actualLength = configuredLength
        } else if direction == .out, let outData = data {
            actualLength = UInt32(outData.count)
        } else if direction == .in, let responseData = bulkTransferResponse {
            actualLength = UInt32(responseData.count)
        } else {
            actualLength = 0
        }
        
        // Prepare response data
        let responseData: Data?
        if direction == .in {
            responseData = bulkTransferResponse
        } else {
            responseData = nil
        }
        
        let result = USBTransferResult(
            status: bulkTransferStatus,
            data: responseData,
            actualLength: actualLength
        )
        
        // Track timing
        let transferTime = CFAbsoluteTimeGetCurrent() - startTime
        if transferTimings["bulk"] == nil {
            transferTimings["bulk"] = []
        }
        transferTimings["bulk"]?.append(transferTime)
        
        if debugLoggingEnabled {
            print("MOCK: Bulk transfer completed - status: \(bulkTransferStatus), actualLength: \(actualLength)")
        }
        
        return result
    }
    
    public func interruptTransfer(
        endpoint: UInt8,
        data: Data?,
        direction: USBTransferDirection,
        timeout: TimeInterval
    ) async throws -> USBTransferResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let transferCall = TransferCall(
            transferType: "interrupt",
            endpoint: endpoint,
            direction: direction,
            data: data,
            parameters: [
                "timeout": timeout
            ]
        )
        transferCalls.append(transferCall)
        
        if debugLoggingEnabled {
            print("MOCK: Interrupt transfer - endpoint: 0x\(String(endpoint, radix: 16)), direction: \(direction)")
        }
        
        // Check for endpoint-specific errors
        if let error = endpointErrors[endpoint] {
            if debugLoggingEnabled {
                print("MOCK: Interrupt transfer failed with endpoint error: \(error)")
            }
            throw error
        }
        
        // Check for configured failure
        if shouldFailInterruptTransfers {
            let error = USBError.transferFailed("Mock interrupt transfer failure")
            if debugLoggingEnabled {
                print("MOCK: Interrupt transfer failed: \(error)")
            }
            throw error
        }
        
        // Simulate transfer latency
        if interruptTransferLatency > 0 {
            let latencyNanoseconds = UInt64(interruptTransferLatency * 1_000_000_000)
            try await Task.sleep(nanoseconds: latencyNanoseconds)
        }
        
        // Calculate actual length
        let actualLength: UInt32
        if let configuredLength = interruptTransferActualLength {
            actualLength = configuredLength
        } else if direction == .out, let outData = data {
            actualLength = UInt32(outData.count)
        } else if direction == .in, let responseData = interruptTransferResponse {
            actualLength = UInt32(responseData.count)
        } else {
            actualLength = 0
        }
        
        // Prepare response data
        let responseData: Data?
        if direction == .in {
            responseData = interruptTransferResponse
        } else {
            responseData = nil
        }
        
        let result = USBTransferResult(
            status: interruptTransferStatus,
            data: responseData,
            actualLength: actualLength
        )
        
        // Track timing
        let transferTime = CFAbsoluteTimeGetCurrent() - startTime
        if transferTimings["interrupt"] == nil {
            transferTimings["interrupt"] = []
        }
        transferTimings["interrupt"]?.append(transferTime)
        
        if debugLoggingEnabled {
            print("MOCK: Interrupt transfer completed - status: \(interruptTransferStatus), actualLength: \(actualLength)")
        }
        
        return result
    }
    
    // MARK: - Test Scenario Configuration
    
    /// Configure mock for successful transfers scenario
    public func setupSuccessfulTransfersScenario() {
        reset()
        
        // Configure successful responses
        controlTransferResponse = Data([0x12, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x40]) // Mock device descriptor
        bulkTransferResponse = Data(repeating: 0xAB, count: 64)
        interruptTransferResponse = Data([0x01, 0x02, 0x03, 0x04])
        
        controlTransferStatus = .success
        bulkTransferStatus = .success
        interruptTransferStatus = .success
    }
    
    /// Configure mock for transfer failures scenario
    public func setupTransferFailuresScenario() {
        reset()
        shouldFailControlTransfers = true
        shouldFailBulkTransfers = true
        shouldFailInterruptTransfers = true
    }
    
    /// Configure mock for timeout scenario
    public func setupTimeoutScenario() {
        reset()
        controlTransferStatus = .timeout
        bulkTransferStatus = .timeout
        interruptTransferStatus = .timeout
    }
    
    /// Configure mock for specific endpoint errors
    public func setupEndpointErrorScenario(endpoint: UInt8, error: USBError) {
        endpointErrors[endpoint] = error
    }
    
    /// Configure mock for low bandwidth scenario
    public func setupLowBandwidthScenario() {
        simulatedBandwidth = 1_500_000 // 1.5 Mbps (Low-speed USB)
        bulkTransferLatency = 0.1 // 100ms
    }
    
    // MARK: - Development Statistics
    
    /// Get comprehensive statistics for test verification
    public func getDevelopmentStatistics() -> USBCommunicatorMockStatistics {
        var averageTimings: [String: TimeInterval] = [:]
        
        for (transferType, timings) in transferTimings {
            if !timings.isEmpty {
                averageTimings[transferType] = timings.reduce(0, +) / Double(timings.count)
            }
        }
        
        return USBCommunicatorMockStatistics(
            totalTransferCalls: transferCalls.count,
            controlTransferCalls: transferCalls.filter { $0.transferType == "control" }.count,
            bulkTransferCalls: transferCalls.filter { $0.transferType == "bulk" }.count,
            interruptTransferCalls: transferCalls.filter { $0.transferType == "interrupt" }.count,
            connectionAttempts: connectionCalls.count,
            disconnectionAttempts: disconnectionCalls.count,
            isCurrentlyConnected: isConnected,
            averageTransferTimings: averageTimings,
            simulatedBandwidth: simulatedBandwidth
        )
    }
}

// MARK: - Supporting Types

/// USB transfer directions
public enum USBTransferDirection: String, CaseIterable {
    case `in` = "in"
    case out = "out"
}

/// USB transfer result
public struct USBTransferResult {
    public let status: USBStatus
    public let data: Data?
    public let actualLength: UInt32
    
    public init(status: USBStatus, data: Data?, actualLength: UInt32) {
        self.status = status
        self.data = data
        self.actualLength = actualLength
    }
}

/// USB status codes
public enum USBStatus: Int, CaseIterable {
    case success = 0
    case timeout = -1
    case stall = -2
    case noDevice = -3
    case noResources = -4
    case invalidParameter = -5
    case transferFailed = -6
}

/// USB errors for testing
public enum USBError: Error, LocalizedError {
    case connectionFailed(String)
    case disconnectionFailed(String)
    case transferFailed(String)
    case timeout(String)
    case deviceNotFound(String)
    case invalidEndpoint(String)
    case insufficientResources(String)
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .disconnectionFailed(let message):
            return "Disconnection failed: \(message)"
        case .transferFailed(let message):
            return "Transfer failed: \(message)"
        case .timeout(let message):
            return "Timeout: \(message)"
        case .deviceNotFound(let message):
            return "Device not found: \(message)"
        case .invalidEndpoint(let message):
            return "Invalid endpoint: \(message)"
        case .insufficientResources(let message):
            return "Insufficient resources: \(message)"
        }
    }
}

/// Statistics for USB communicator mock operations
public struct USBCommunicatorMockStatistics {
    public let totalTransferCalls: Int
    public let controlTransferCalls: Int
    public let bulkTransferCalls: Int
    public let interruptTransferCalls: Int
    public let connectionAttempts: Int
    public let disconnectionAttempts: Int
    public let isCurrentlyConnected: Bool
    public let averageTransferTimings: [String: TimeInterval]
    public let simulatedBandwidth: UInt64
    
    public init(
        totalTransferCalls: Int,
        controlTransferCalls: Int,
        bulkTransferCalls: Int,
        interruptTransferCalls: Int,
        connectionAttempts: Int,
        disconnectionAttempts: Int,
        isCurrentlyConnected: Bool,
        averageTransferTimings: [String: TimeInterval],
        simulatedBandwidth: UInt64
    ) {
        self.totalTransferCalls = totalTransferCalls
        self.controlTransferCalls = controlTransferCalls
        self.bulkTransferCalls = bulkTransferCalls
        self.interruptTransferCalls = interruptTransferCalls
        self.connectionAttempts = connectionAttempts
        self.disconnectionAttempts = disconnectionAttempts
        self.isCurrentlyConnected = isCurrentlyConnected
        self.averageTransferTimings = averageTransferTimings
        self.simulatedBandwidth = simulatedBandwidth
    }
}

/// Protocol for USB device communicator interface
public protocol USBDeviceCommunicatorInterface {
    func connect() async throws
    func disconnect() async throws
    func controlTransfer(
        requestType: UInt8,
        request: UInt8,
        value: UInt16,
        index: UInt16,
        data: Data?,
        direction: USBTransferDirection,
        timeout: TimeInterval
    ) async throws -> USBTransferResult
    func bulkTransfer(
        endpoint: UInt8,
        data: Data?,
        direction: USBTransferDirection,
        timeout: TimeInterval
    ) async throws -> USBTransferResult
    func interruptTransfer(
        endpoint: UInt8,
        data: Data?,
        direction: USBTransferDirection,
        timeout: TimeInterval
    ) async throws -> USBTransferResult
}