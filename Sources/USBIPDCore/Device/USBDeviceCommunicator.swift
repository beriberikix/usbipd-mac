// USBDeviceCommunicator.swift
// USB device communication interface and lifecycle management

import Foundation
import IOKit
import IOKit.usb
import Common

/// Protocol defining USB device communication operations
public protocol USBDeviceCommunicator {
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
}

/// Default implementation of USB device communication
public class DefaultUSBDeviceCommunicator: USBDeviceCommunicator {
    
    // MARK: - Properties
    
    private let deviceClaimManager: DeviceClaimManager
    private let logger: Logger
    private let queue: DispatchQueue
    
    /// IOKit USB interface instances keyed by device identifier and interface number
    private var openInterfaces: [String: [UInt8: IOKitUSBInterface]] = [:]
    private let interfaceLock = NSLock()
    
    // MARK: - Initialization
    
    public init(deviceClaimManager: DeviceClaimManager, logger: Logger? = nil) {
        self.deviceClaimManager = deviceClaimManager
        self.logger = logger ?? Logger(subsystem: "com.usbipd.core", category: "USBDeviceCommunicator")
        self.queue = DispatchQueue(label: "com.usbipd.device-communicator", qos: .userInitiated)
    }
    
    // MARK: - USB Interface Lifecycle
    
    public func openUSBInterface(device: USBDevice, interfaceNumber: UInt8) async throws {
        try validateDeviceClaim(device: device)
        
        let deviceKey = deviceIdentifier(for: device)
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.interfaceLock.lock()
                defer { self.interfaceLock.unlock() }
                
                do {
                    // Check if interface is already open
                    if let interfaces = self.openInterfaces[deviceKey],
                       interfaces[interfaceNumber] != nil {
                        self.logger.debug("USB interface \(interfaceNumber) already open for device \(deviceKey)")
                        continuation.resume(returning: ())
                        return
                    }
                    
                    // Create new IOKit USB interface
                    let interface = try IOKitUSBInterface(device: device, interfaceNumber: interfaceNumber)
                    try interface.open()
                    
                    // Store the open interface
                    if self.openInterfaces[deviceKey] == nil {
                        self.openInterfaces[deviceKey] = [:]
                    }
                    self.openInterfaces[deviceKey]?[interfaceNumber] = interface
                    
                    self.logger.info("Successfully opened USB interface \(interfaceNumber) for device \(deviceKey)")
                    continuation.resume(returning: ())
                    
                } catch {
                    self.logger.error("Failed to open USB interface \(interfaceNumber) for device \(deviceKey): \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func closeUSBInterface(device: USBDevice, interfaceNumber: UInt8) async throws {
        let deviceKey = deviceIdentifier(for: device)
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.interfaceLock.lock()
                defer { self.interfaceLock.unlock() }
                
                do {
                    guard let interfaces = self.openInterfaces[deviceKey],
                          let interface = interfaces[interfaceNumber] else {
                        self.logger.debug("USB interface \(interfaceNumber) not open for device \(deviceKey)")
                        continuation.resume(returning: ())
                        return
                    }
                    
                    // Close the interface
                    try interface.close()
                    
                    // Remove from tracking
                    self.openInterfaces[deviceKey]?[interfaceNumber] = nil
                    if self.openInterfaces[deviceKey]?.isEmpty == true {
                        self.openInterfaces[deviceKey] = nil
                    }
                    
                    self.logger.info("Successfully closed USB interface \(interfaceNumber) for device \(deviceKey)")
                    continuation.resume(returning: ())
                    
                } catch {
                    self.logger.error("Failed to close USB interface \(interfaceNumber) for device \(deviceKey): \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func isInterfaceOpen(device: USBDevice, interfaceNumber: UInt8) -> Bool {
        let deviceKey = deviceIdentifier(for: device)
        
        interfaceLock.lock()
        defer { interfaceLock.unlock() }
        
        return openInterfaces[deviceKey]?[interfaceNumber] != nil
    }
    
    // MARK: - Device Validation
    
    public func validateDeviceClaim(device: USBDevice) throws -> Bool {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        
        // Basic claim status check
        guard deviceClaimManager.isDeviceClaimed(deviceID: deviceID) else {
            logger.error("Device not claimed for USB operations: \(deviceID)")
            throw USBRequestError.deviceNotClaimed(deviceID)
        }
        
        // Enhanced validation for System Extension integration
        if let systemExtensionAdapter = deviceClaimManager as? SystemExtensionClaimAdapter {
            // Check System Extension health status
            let status = systemExtensionAdapter.getSystemExtensionStatus()
            guard status.isRunning else {
                logger.error("System Extension not running, cannot perform USB operations on device: \(deviceID)")
                throw USBRequestError.deviceNotAvailable
            }
            
            // Verify device is in the claimed devices list
            let isInClaimedList = status.claimedDevices.contains { claimedDevice in
                "\(claimedDevice.busID)-\(claimedDevice.deviceID)" == deviceID
            }
            
            guard isInClaimedList else {
                logger.error("Device not found in System Extension claimed devices list: \(deviceID)")
                throw USBRequestError.deviceNotClaimed(deviceID)
            }
            
            // Perform health check to ensure System Extension is responsive
            guard systemExtensionAdapter.performSystemExtensionHealthCheck() else {
                logger.error("System Extension health check failed, cannot perform USB operations on device: \(deviceID)")
                throw USBRequestError.deviceNotAvailable
            }
            
            logger.debug("Enhanced device claim validation passed for device: \(deviceID)")
        }
        
        return true
    }
    
    /// Comprehensive device validation including System Extension status
    /// - Parameters:
    ///   - device: USB device to validate
    ///   - operationType: Type of USB operation being attempted
    /// - Returns: True if device is ready for operations
    /// - Throws: USBRequestError with specific validation failure
    public func validateDeviceForOperation(device: USBDevice, operationType: String) throws -> Bool {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        
        // Perform standard device claim validation
        try validateDeviceClaim(device: device)
        
        // Additional operation-specific validation
        logger.debug("Validating device \(deviceID) for \(operationType) operation")
        
        // Check if System Extension has reported any errors for this device
        if let systemExtensionAdapter = deviceClaimManager as? SystemExtensionClaimAdapter {
            let status = systemExtensionAdapter.getSystemExtensionStatus()
            let stats = systemExtensionAdapter.getSystemExtensionStatistics()
            
            // Check if error count is excessive (indicating system instability)
            if status.errorCount > 100 {
                logger.warning("System Extension has high error count (\(status.errorCount)), USB operations may be unstable")
            }
            
            // Check memory usage to ensure system stability
            let memoryUsageMB = status.memoryUsage / (1024 * 1024)
            if memoryUsageMB > 100 {
                logger.warning("System Extension using high memory (\(memoryUsageMB)MB), performance may be impacted")
            }
        }
        
        logger.debug("Device \(deviceID) validation passed for \(operationType)")
        return true
    }
    
    // MARK: - USB Transfer Execution
    
    public func executeControlTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        try validateDeviceForOperation(device: device, operationType: "control transfer")
        
        guard request.transferType == .control else {
            throw USBRequestError.transferTypeNotSupported(request.transferType)
        }
        
        guard let setupPacket = request.setupPacket, setupPacket.count == 8 else {
            throw USBRequestError.setupPacketRequired
        }
        
        // Validate timeout
        guard request.timeout > 0 && request.timeout <= 30000 else {
            throw USBRequestError.timeoutInvalid(request.timeout)
        }
        
        logger.debug("Executing control transfer for device \(deviceIdentifier(for: device)), endpoint 0x\(String(request.endpoint, radix: 16))")
        
        do {
            // Ensure interface is open (control transfers typically use interface 0)
            let interfaceNumber: UInt8 = 0
            if !isInterfaceOpen(device: device, interfaceNumber: interfaceNumber) {
                try await openUSBInterface(device: device, interfaceNumber: interfaceNumber)
            }
            
            // Get the interface and execute transfer
            let interface = try getInterface(for: device, interfaceNumber: interfaceNumber)
            
            let result = try await interface.executeControlTransfer(
                endpoint: request.endpoint,
                setupPacket: setupPacket,
                transferBuffer: request.transferBuffer,
                timeout: request.timeout
            )
            
            logger.debug("Control transfer completed with status: \(result.status), length: \(result.actualLength)")
            return result
            
        } catch {
            logger.error("Control transfer failed for device \(deviceIdentifier(for: device)): \(error)")
            throw error
        }
    }
    
    public func executeBulkTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        try validateDeviceForOperation(device: device, operationType: "bulk transfer")
        
        guard request.transferType == .bulk else {
            throw USBRequestError.transferTypeNotSupported(request.transferType)
        }
        
        // Validate buffer size
        if request.direction == .out {
            guard let buffer = request.transferBuffer else {
                throw USBRequestError.invalidParameters
            }
            guard buffer.count == Int(request.bufferLength) else {
                throw USBRequestError.bufferSizeMismatch(expected: request.bufferLength, actual: UInt32(buffer.count))
            }
        }
        
        // Validate timeout
        guard request.timeout > 0 && request.timeout <= 30000 else {
            throw USBRequestError.timeoutInvalid(request.timeout)
        }
        
        logger.debug("Executing bulk transfer for device \(deviceIdentifier(for: device)), endpoint 0x\(String(request.endpoint, radix: 16))")
        
        do {
            // Extract interface number from endpoint (typically endpoint >> 4)
            let interfaceNumber = UInt8((request.endpoint >> 4) & 0x0F)
            
            // Ensure interface is open
            if !isInterfaceOpen(device: device, interfaceNumber: interfaceNumber) {
                try await openUSBInterface(device: device, interfaceNumber: interfaceNumber)
            }
            
            // Get the interface and execute transfer
            let interface = try getInterface(for: device, interfaceNumber: interfaceNumber)
            
            let result = try await interface.executeBulkTransfer(
                endpoint: request.endpoint,
                data: request.transferBuffer,
                bufferLength: request.bufferLength,
                timeout: request.timeout
            )
            
            logger.debug("Bulk transfer completed with status: \(result.status), length: \(result.actualLength)")
            return result
            
        } catch {
            logger.error("Bulk transfer failed for device \(deviceIdentifier(for: device)): \(error)")
            throw error
        }
    }
    
    public func executeInterruptTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        try validateDeviceForOperation(device: device, operationType: "interrupt transfer")
        
        guard request.transferType == .interrupt else {
            throw USBRequestError.transferTypeNotSupported(request.transferType)
        }
        
        // Validate buffer size for OUT transfers
        if request.direction == .out {
            guard let buffer = request.transferBuffer else {
                throw USBRequestError.invalidParameters
            }
            guard buffer.count == Int(request.bufferLength) else {
                throw USBRequestError.bufferSizeMismatch(expected: request.bufferLength, actual: UInt32(buffer.count))
            }
        }
        
        // Validate timeout
        guard request.timeout > 0 && request.timeout <= 30000 else {
            throw USBRequestError.timeoutInvalid(request.timeout)
        }
        
        logger.debug("Executing interrupt transfer for device \(deviceIdentifier(for: device)), endpoint 0x\(String(request.endpoint, radix: 16))")
        
        do {
            // Extract interface number from endpoint
            let interfaceNumber = UInt8((request.endpoint >> 4) & 0x0F)
            
            // Ensure interface is open
            if !isInterfaceOpen(device: device, interfaceNumber: interfaceNumber) {
                try await openUSBInterface(device: device, interfaceNumber: interfaceNumber)
            }
            
            // Get the interface and execute transfer
            let interface = try getInterface(for: device, interfaceNumber: interfaceNumber)
            
            let result = try await interface.executeInterruptTransfer(
                endpoint: request.endpoint,
                data: request.transferBuffer,
                bufferLength: request.bufferLength,
                timeout: request.timeout
            )
            
            logger.debug("Interrupt transfer completed with status: \(result.status), length: \(result.actualLength)")
            return result
            
        } catch {
            logger.error("Interrupt transfer failed for device \(deviceIdentifier(for: device)): \(error)")
            throw error
        }
    }
    
    public func executeIsochronousTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        try validateDeviceForOperation(device: device, operationType: "isochronous transfer")
        
        guard request.transferType == .isochronous else {
            throw USBRequestError.transferTypeNotSupported(request.transferType)
        }
        
        // Validate buffer size for OUT transfers
        if request.direction == .out {
            guard let buffer = request.transferBuffer else {
                throw USBRequestError.invalidParameters
            }
            guard buffer.count == Int(request.bufferLength) else {
                throw USBRequestError.bufferSizeMismatch(expected: request.bufferLength, actual: UInt32(buffer.count))
            }
        }
        
        // Validate isochronous-specific parameters
        guard request.numberOfPackets > 0 else {
            throw USBRequestError.invalidParameters
        }
        
        logger.debug("Executing isochronous transfer for device \(deviceIdentifier(for: device)), endpoint 0x\(String(request.endpoint, radix: 16))")
        
        do {
            // Extract interface number from endpoint
            let interfaceNumber = UInt8((request.endpoint >> 4) & 0x0F)
            
            // Ensure interface is open
            if !isInterfaceOpen(device: device, interfaceNumber: interfaceNumber) {
                try await openUSBInterface(device: device, interfaceNumber: interfaceNumber)
            }
            
            // Get the interface and execute transfer
            let interface = try getInterface(for: device, interfaceNumber: interfaceNumber)
            
            let result = try await interface.executeIsochronousTransfer(
                endpoint: request.endpoint,
                data: request.transferBuffer,
                bufferLength: request.bufferLength,
                startFrame: request.startFrame,
                numberOfPackets: request.numberOfPackets
            )
            
            logger.debug("Isochronous transfer completed with status: \(result.status), length: \(result.actualLength)")
            return result
            
        } catch {
            logger.error("Isochronous transfer failed for device \(deviceIdentifier(for: device)): \(error)")
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    private func deviceIdentifier(for device: USBDevice) -> String {
        return "\(device.busID)-\(device.deviceID)"
    }
    
    /// Get the IOKit USB interface for a device and interface number
    private func getInterface(for device: USBDevice, interfaceNumber: UInt8) throws -> IOKitUSBInterface {
        let deviceKey = deviceIdentifier(for: device)
        
        interfaceLock.lock()
        defer { interfaceLock.unlock() }
        
        guard let interfaces = openInterfaces[deviceKey],
              let interface = interfaces[interfaceNumber] else {
            throw USBRequestError.deviceNotAvailable
        }
        
        return interface
    }
}