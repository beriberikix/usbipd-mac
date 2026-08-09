// USBDeviceCommunicator.swift
// USB device communication interface and lifecycle management

import Foundation
import IOKit
import IOKit.usb
@preconcurrency import Common

/// Protocol defining USB device communication operations
public protocol USBDeviceCommunicator: AnyObject {
    /// The transfer type the device reports for an endpoint, or nil if it cannot be
    /// determined. CMD_SUBMIT carries no transfer type, so the server has to learn it
    /// from the device rather than infer it from the request.
    func endpointTransferType(device: USBDevice, endpoint: UInt8) -> USBTransferType?

    /// Execute a control transfer on the specified device
    /// - Parameters:
    ///   - device: Target USB device
    ///   - request: USB request block containing transfer parameters
    /// - Returns: Transfer result with status and data
    /// - Throws: USBRequestError for invalid parameters or device access issues
    func executeControlTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult
    
    /// Execute a bulk transfer on the specified device
    /// - Parameters:
    ///   - device: Target USB device
    ///   - request: USB request block containing transfer parameters
    /// - Returns: Transfer result with status and data
    /// - Throws: USBRequestError for invalid parameters or device access issues
    func executeBulkTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult
    
    /// Execute an interrupt transfer on the specified device
    /// - Parameters:
    ///   - device: Target USB device
    ///   - request: USB request block containing transfer parameters
    /// - Returns: Transfer result with status and data
    /// - Throws: USBRequestError for invalid parameters or device access issues
    func executeInterruptTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult
    
    /// Execute an isochronous transfer on the specified device
    /// - Parameters:
    ///   - device: Target USB device
    ///   - request: USB request block containing transfer parameters
    /// - Returns: Transfer result with status and data
    /// - Throws: USBRequestError for invalid parameters or device access issues
    func executeIsochronousTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult
    
    /// Open a USB interface for communication
    /// - Parameters:
    ///   - device: Target USB device
    ///   - interfaceNumber: USB interface number to open
    /// - Throws: USBRequestError if interface cannot be opened
    func openUSBInterface(device: USBDevice, interfaceNumber: UInt8) async throws
    
    /// Close a USB interface
    /// - Parameters:
    ///   - device: Target USB device
    ///   - interfaceNumber: USB interface number to close
    /// - Throws: USBRequestError if interface cannot be closed
    func closeUSBInterface(device: USBDevice, interfaceNumber: UInt8) async throws
    
    /// Check if a USB interface is currently open
    /// - Parameters:
    ///   - device: Target USB device
    ///   - interfaceNumber: USB interface number to check
    /// - Returns: True if interface is open, false otherwise
    func isInterfaceOpen(device: USBDevice, interfaceNumber: UInt8) -> Bool
    
    /// Validate that a device is properly claimed before operations
    /// - Parameter device: USB device to validate
    /// - Returns: True if device is claimed and accessible
    /// - Throws: USBRequestError if device is not claimed or accessible
    func validateDeviceClaim(device: USBDevice) throws -> Bool
    
    /// Cancel all pending transfers on a device interface
    /// - Parameters:
    ///   - device: Target USB device
    ///   - interfaceNumber: USB interface number to cancel transfers on
    /// - Throws: USBRequestError if cancellation fails
    func cancelAllTransfers(device: USBDevice, interfaceNumber: UInt8) async throws
    
    /// Cancel transfers on a specific endpoint
    /// - Parameters:
    ///   - device: Target USB device
    ///   - interfaceNumber: USB interface number
    ///   - endpoint: Endpoint address to cancel transfers on
    /// - Throws: USBRequestError if cancellation fails
    func cancelTransfers(device: USBDevice, interfaceNumber: UInt8, endpoint: UInt8) async throws
}

/// Default implementation of USB device communication
public extension USBDeviceCommunicator {
    /// Conformers that cannot inspect the device fall back to the caller's inference.
    func endpointTransferType(device: USBDevice, endpoint: UInt8) -> USBTransferType? {
        return nil
    }
}
