// MockUSBDeviceCommunicator.swift
// Mock USB device communicator for USB request processor testing

import Foundation
@testable import USBIPDCore
@testable import Common

// Use USBStatus from USBIPDCore, qualified to avoid ambiguity with IOKit USBStatus

// MARK: - Mock Response Types

struct MockTransferResponse {
    let data: Data
    let status: USBIPDCore.USBStatus
    let actualLength: UInt32
}

struct MockIsochronousResponse {
    let data: Data
    let status: USBIPDCore.USBStatus
    let actualLength: UInt32
    let errorCount: UInt32
}

// MARK: - Mock USB Device Communicator Protocol

protocol USBDeviceCommunicatorProtocol: AnyObject {
    func executeControlTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult
    func executeBulkTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult
    func executeInterruptTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult
    func executeIsochronousTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult
}

// MARK: - Mock Device Communicator for Testing

class MockUSBDeviceCommunicator: USBDeviceCommunicator {
    
    // MARK: - Mock Configuration
    
    private var shouldSucceed = true
    private var operationLatency: UInt32 = 0
    private var simulatedError: Error?
    
    // Mock responses for different transfer types
    private var controlResponse: MockTransferResponse?
    private var bulkResponse: MockTransferResponse?
    private var interruptResponse: MockTransferResponse?
    private var isochronousResponse: MockIsochronousResponse?
    
    // MARK: - Configuration Methods
    
    func reset() {
        shouldSucceed = true
        operationLatency = 0
        simulatedError = nil
        controlResponse = nil
        bulkResponse = nil
        interruptResponse = nil
        isochronousResponse = nil
    }
    
    func setShouldSucceed(_ succeed: Bool) {
        shouldSucceed = succeed
    }
    
    func setOperationLatency(_ latency: UInt32) {
        operationLatency = latency
    }
    
    func setControlTransferResponse(_ data: Data, status: USBIPDCore.USBStatus = .success, actualLength: UInt32? = nil) {
        controlResponse = MockTransferResponse(
            data: data,
            status: status,
            actualLength: actualLength ?? UInt32(data.count)
        )
    }
    
    func setBulkTransferResponse(_ data: Data, status: USBIPDCore.USBStatus = .success, actualLength: UInt32? = nil) {
        bulkResponse = MockTransferResponse(
            data: data,
            status: status,
            actualLength: actualLength ?? UInt32(data.count)
        )
    }
    
    func setInterruptTransferResponse(_ data: Data, status: USBIPDCore.USBStatus = .success, actualLength: UInt32? = nil) {
        interruptResponse = MockTransferResponse(
            data: data,
            status: status,
            actualLength: actualLength ?? UInt32(data.count)
        )
    }
    
    func setIsochronousTransferResponse(
        _ data: Data,
        status: USBIPDCore.USBStatus = .success,
        actualLength: UInt32? = nil,
        errorCount: UInt32 = 0
    ) {
        isochronousResponse = MockIsochronousResponse(
            data: data,
            status: status,
            actualLength: actualLength ?? UInt32(data.count),
            errorCount: errorCount
        )
    }
    
    func simulateTimeout() {
        simulatedError = USBRequestError.timeout
        shouldSucceed = false
    }
    
    func simulateDeviceDisconnection() {
        simulatedError = USBRequestError.deviceNotAvailable
        shouldSucceed = false
    }
    
    func simulateEndpointStall() {
        simulatedError = USBRequestError.invalidParameters
        shouldSucceed = false
    }
    
    // MARK: - Protocol Implementation
    
    func executeControlTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        if operationLatency > 0 {
            try await Task.sleep(nanoseconds: UInt64(operationLatency) * 1_000_000)
        }
        
        if !shouldSucceed, let error = simulatedError {
            throw error
        }
        
        if let response = controlResponse {
            return USBTransferResult(
                status: response.status,
                actualLength: response.actualLength,
                data: response.data,
                completionTime: Date().timeIntervalSince1970
            )
        }
        
        return USBTransferResult(
            status: .success,
            actualLength: 0,
            completionTime: Date().timeIntervalSince1970
        )
    }
    
    func executeBulkTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        if operationLatency > 0 {
            try await Task.sleep(nanoseconds: UInt64(operationLatency) * 1_000_000)
        }
        
        if !shouldSucceed, let error = simulatedError {
            throw error
        }
        
        if let response = bulkResponse {
            return USBTransferResult(
                status: response.status,
                actualLength: response.actualLength,
                data: response.data,
                completionTime: Date().timeIntervalSince1970
            )
        }
        
        return USBTransferResult(
            status: .success,
            actualLength: request.bufferLength,
            completionTime: Date().timeIntervalSince1970
        )
    }
    
    func executeInterruptTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        if operationLatency > 0 {
            try await Task.sleep(nanoseconds: UInt64(operationLatency) * 1_000_000)
        }
        
        if !shouldSucceed, let error = simulatedError {
            throw error
        }
        
        if let response = interruptResponse {
            return USBTransferResult(
                status: response.status,
                actualLength: response.actualLength,
                data: response.data,
                completionTime: Date().timeIntervalSince1970
            )
        }
        
        return USBTransferResult(
            status: .success,
            actualLength: request.bufferLength,
            completionTime: Date().timeIntervalSince1970
        )
    }
    
    func executeIsochronousTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        if operationLatency > 0 {
            try await Task.sleep(nanoseconds: UInt64(operationLatency) * 1_000_000)
        }
        
        if !shouldSucceed, let error = simulatedError {
            throw error
        }
        
        if let response = isochronousResponse {
            return USBTransferResult(
                status: response.status,
                actualLength: response.actualLength,
                errorCount: response.errorCount,
                data: response.data,
                completionTime: Date().timeIntervalSince1970,
                startFrame: request.startFrame
            )
        }
        
        return USBTransferResult(
            status: .success,
            actualLength: request.bufferLength,
            errorCount: 0,
            completionTime: Date().timeIntervalSince1970,
            startFrame: request.startFrame
        )
    }
    
    // MARK: - Interface Management
    
    private var openInterfaces: Set<String> = []
    
    func openUSBInterface(device: USBDevice, interfaceNumber: UInt8) async throws {
        let key = "\(device.busID)-\(device.deviceID)-\(interfaceNumber)"
        openInterfaces.insert(key)
    }
    
    func closeUSBInterface(device: USBDevice, interfaceNumber: UInt8) async throws {
        let key = "\(device.busID)-\(device.deviceID)-\(interfaceNumber)"
        openInterfaces.remove(key)
    }
    
    func isInterfaceOpen(device: USBDevice, interfaceNumber: UInt8) -> Bool {
        let key = "\(device.busID)-\(device.deviceID)-\(interfaceNumber)"
        return openInterfaces.contains(key)
    }
    
    // MARK: - Device Validation
    
    func validateDeviceClaim(device: USBDevice) throws -> Bool {
        if !shouldSucceed, let error = simulatedError {
            throw error
        }
        return true
    }
    
    // MARK: - Transfer Cancellation
    
    func cancelAllTransfers(device: USBDevice, interfaceNumber: UInt8) async throws {
        // Mock implementation - no actual transfers to cancel
    }
    
    func cancelTransfers(device: USBDevice, interfaceNumber: UInt8, endpoint: UInt8) async throws {
        // Mock implementation - no actual transfers to cancel
    }
}