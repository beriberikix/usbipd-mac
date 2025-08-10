// USBRequestHandler.swift
// USB request handling implementation for SUBMIT and UNLINK operations

import Foundation
import Common

/// Default implementation of USB request handler for SUBMIT/UNLINK operations
public class USBRequestHandler: USBRequestHandlerProtocol {
    
    /// Device discovery for finding USB devices
    private let deviceDiscovery: DeviceDiscovery
    
    /// Device claim manager for validating device access
    private let deviceClaimManager: DeviceClaimManager
    
    /// USB device communicator for executing USB operations (will be injected later)
    private var deviceCommunicator: USBDeviceCommunicatorProtocol?
    
    /// URB tracker for managing concurrent USB requests
    private let urbTracker: URBTracker
    
    /// Logger for diagnostic information
    private let logger: ((String, LogLevel) -> Void)?
    
    /// Log levels for USB request handling
    public enum LogLevel {
        case debug
        case info
        case warning
        case error
    }
    
    /// Initialize with required dependencies
    public init(
        deviceDiscovery: DeviceDiscovery,
        deviceClaimManager: DeviceClaimManager,
        logger: ((String, LogLevel) -> Void)? = nil
    ) {
        self.deviceDiscovery = deviceDiscovery
        self.deviceClaimManager = deviceClaimManager
        self.urbTracker = URBTracker()
        self.logger = logger
    }
    
    /// Set the USB device communicator for actual USB operations
    public func setUSBDeviceCommunicator(_ communicator: USBDeviceCommunicatorProtocol) {
        self.deviceCommunicator = communicator
    }
    
    // MARK: - USBRequestHandlerProtocol Implementation
    
    /// Handle a USB SUBMIT request and return response data
    public func handleSubmitRequest(_ data: Data) throws -> Data {
        log("Processing USB SUBMIT request", .debug)
        
        // For now, return a placeholder response since message types aren't implemented yet
        // This will be updated in task 2.3 when USBSubmitProcessor is created
        log("USB SUBMIT request handler not yet fully implemented", .warning)
        
        // Validate minimum data length for USB/IP header
        guard data.count >= 8 else {
            log("Invalid data length for USB SUBMIT request", .error, ["dataSize": String(data.count)])
            throw USBIPProtocolError.invalidDataLength
        }
        
        // Extract basic header information for validation
        let header = try USBIPHeader.decode(from: data)
        guard header.command == .submitRequest else {
            log("Invalid command for USB SUBMIT request", .error, ["command": String(format: "0x%04x", header.command.rawValue)])
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        log("USB SUBMIT request validated but processing deferred to USBSubmitProcessor", .info)
        
        // Create a placeholder error response for now
        let errorResponse = USBIPHeader(
            command: .submitReply,
            status: 1 // Error status
        )
        
        return try errorResponse.encode()
    }
    
    /// Handle a USB UNLINK request and return response data
    public func handleUnlinkRequest(_ data: Data) throws -> Data {
        log("Processing USB UNLINK request", .debug)
        
        // For now, return a placeholder response since message types aren't implemented yet
        // This will be updated in task 2.4 when USBUnlinkProcessor is created
        log("USB UNLINK request handler not yet fully implemented", .warning)
        
        // Validate minimum data length for USB/IP header
        guard data.count >= 8 else {
            log("Invalid data length for USB UNLINK request", .error, ["dataSize": String(data.count)])
            throw USBIPProtocolError.invalidDataLength
        }
        
        // Extract basic header information for validation
        let header = try USBIPHeader.decode(from: data)
        guard header.command == .unlinkRequest else {
            log("Invalid command for USB UNLINK request", .error, ["command": String(format: "0x%04x", header.command.rawValue)])
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        log("USB UNLINK request validated but processing deferred to USBUnlinkProcessor", .info)
        
        // Create a placeholder error response for now
        let errorResponse = USBIPHeader(
            command: .unlinkReply,
            status: 1 // Error status
        )
        
        return try errorResponse.encode()
    }
    
    /// Validate that a device is accessible for USB operations
    public func validateDeviceAccess(_ busID: String) throws -> Bool {
        log("Validating device access", .debug, ["busID": busID])
        
        do {
            // Parse the busID to extract components (assuming format like "1-1:1.0" or just "1-1")
            let components = busID.split(separator: ":")
            guard !components.isEmpty else {
                log("Invalid busID format", .error, ["busID": busID])
                throw USBRequestError.invalidURB("Invalid busID format: \(busID)")
            }
            
            let deviceBusID = String(components[0])
            let deviceID = components.count > 1 ? String(components[1]) : "1.0" // Default deviceID
            
            log("Parsed device identifiers", .debug, ["deviceBusID": deviceBusID, "deviceID": deviceID])
            
            // Check if device exists
            guard let device = try deviceDiscovery.getDevice(busID: deviceBusID, deviceID: deviceID) else {
                log("Device not found", .error, ["busID": deviceBusID, "deviceID": deviceID])
                throw USBRequestError.deviceNotClaimed("Device not found: \(busID)")
            }
            
            // Check if device is claimed for USB operations
            let deviceIdentifier = "\(device.busID)-\(device.deviceID)"
            guard deviceClaimManager.isDeviceClaimed(deviceID: deviceIdentifier) else {
                log("Device not claimed for USB operations", .error, ["deviceIdentifier": deviceIdentifier])
                throw USBRequestError.deviceNotClaimed("Device not claimed: \(busID)")
            }
            
            log("Device access validation successful", .info, [
                "busID": busID,
                "deviceIdentifier": deviceIdentifier,
                "vendorID": String(format: "0x%04x", device.vendorID),
                "productID": String(format: "0x%04x", device.productID)
            ])
            
            return true
        } catch let error as USBRequestError {
            log("Device access validation failed", .error, ["busID": busID, "error": error.localizedDescription])
            throw error
        } catch {
            log("Unexpected error during device access validation", .error, ["busID": busID, "error": error.localizedDescription])
            throw USBRequestError.deviceNotClaimed("Device access validation failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Get device information for USB request processing
    private func getDeviceForRequest(_ busID: String) throws -> USBDevice {
        // Parse the busID to extract components
        let components = busID.split(separator: ":")
        guard !components.isEmpty else {
            throw USBRequestError.invalidURB("Invalid busID format: \(busID)")
        }
        
        let deviceBusID = String(components[0])
        let deviceID = components.count > 1 ? String(components[1]) : "1.0"
        
        guard let device = try deviceDiscovery.getDevice(busID: deviceBusID, deviceID: deviceID) else {
            throw USBRequestError.deviceNotClaimed("Device not found: \(busID)")
        }
        
        return device
    }
    
    /// Validate that USB device communicator is available
    private func ensureDeviceCommunicator() throws -> USBDeviceCommunicatorProtocol {
        guard let communicator = deviceCommunicator else {
            log("USB device communicator not available", .error)
            throw USBRequestError.invalidURB("USB device communicator not configured")
        }
        return communicator
    }
    
    /// Log a message with the specified level and optional context
    private func log(_ message: String, _ level: LogLevel, _ context: [String: String] = [:]) {
        logger?(message, level)
        
        // Also log context if available for debugging
        if !context.isEmpty && level == .debug {
            let contextString = context.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            logger?("Context: \(contextString)", level)
        }
    }
}

// MARK: - USB Device Communicator Protocol

/// Protocol for USB device communication operations
/// This will be implemented in later tasks when IOKit integration is added
public protocol USBDeviceCommunicatorProtocol {
    /// Execute a USB transfer operation
    func executeUSBTransfer(_ urb: USBRequestBlock, device: USBDevice) async throws -> USBTransferResult
    
    /// Cancel a pending USB transfer operation
    func cancelUSBTransfer(_ seqnum: UInt32) async throws -> Bool
    
    /// Validate that a USB endpoint is available on the device
    func validateEndpoint(_ endpoint: UInt8, device: USBDevice) throws -> Bool
}