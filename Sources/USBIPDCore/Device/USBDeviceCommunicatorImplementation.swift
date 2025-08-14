// USBDeviceCommunicatorImplementation.swift
// Production USB device communication implementation using IOKit integration

import Foundation
import IOKit
import IOKit.usb
import Common

/// Production implementation of USB device communication using IOKit integration
/// Replaces placeholder implementations with real USB/IP device sharing capabilities
public class USBDeviceCommunicatorImplementation: USBDeviceCommunicator {
    
    // MARK: - Properties
    
    /// Device claim manager for access control
    private let deviceClaimManager: DeviceClaimManager
    
    /// Logger for debugging and monitoring
    private let logger: Logger
    
    /// Queue for serializing device operations
    private let queue: DispatchQueue
    
    /// IOKit interface factory for dependency injection
    private let ioKitInterfaceFactory: IOKitInterfaceFactory
    
    /// Active USB interfaces keyed by device identifier and interface number
    private var activeInterfaces: [String: [UInt8: IOKitUSBInterface]] = [:]
    
    /// Lock for thread-safe interface management
    private let interfaceLock = NSLock()
    
    // MARK: - Initialization
    
    /// Initialize the USB device communicator with dependencies
    /// - Parameters:
    ///   - deviceClaimManager: Device claim manager for access control
    ///   - ioKitInterfaceFactory: Factory for creating IOKit interfaces (for testing)
    public init(
        deviceClaimManager: DeviceClaimManager,
        ioKitInterfaceFactory: IOKitInterfaceFactory = DefaultIOKitInterfaceFactory()
    ) {
        self.deviceClaimManager = deviceClaimManager
        self.ioKitInterfaceFactory = ioKitInterfaceFactory
        self.logger = Logger(subsystem: "com.usbipd.core", category: "USBDeviceCommunicatorImplementation")
        self.queue = DispatchQueue(label: "com.usbipd.device-communicator", qos: .userInitiated)
        
        logger.info("Initialized production USB device communicator with IOKit integration")
    }
    
    // MARK: - USB Interface Lifecycle
    
    public func openUSBInterface(device: USBDevice, interfaceNumber: UInt8) async throws {
        // Validate device claim first
        _ = try validateDeviceClaim(device: device)
        
        let deviceKey = deviceIdentifier(for: device)
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.interfaceLock.lock()
                defer { self.interfaceLock.unlock() }
                
                do {
                    // Check if interface is already open
                    if let deviceInterfaces = self.activeInterfaces[deviceKey],
                       deviceInterfaces[interfaceNumber] != nil {
                        self.logger.debug("USB interface \\(interfaceNumber) already open for device \\(deviceKey)")
                        continuation.resume()
                        return
                    }
                    
                    // Create new IOKit USB interface
                    let interface = try self.ioKitInterfaceFactory.createIOKitUSBInterface(
                        device: device,
                        interfaceNumber: interfaceNumber
                    )
                    try interface.open()
                    
                    // Store the interface
                    if self.activeInterfaces[deviceKey] == nil {
                        self.activeInterfaces[deviceKey] = [:]
                    }
                    self.activeInterfaces[deviceKey]![interfaceNumber] = interface
                    
                    self.logger.info("Successfully opened USB interface \\(interfaceNumber) for device \\(deviceKey)")
                    continuation.resume()
                } catch {
                    self.logger.error("Failed to open USB interface \\(interfaceNumber) for device \\(deviceKey): \\(error)")
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
                    guard let deviceInterfaces = self.activeInterfaces[deviceKey],
                          let interface = deviceInterfaces[interfaceNumber] else {
                        self.logger.debug("USB interface \\(interfaceNumber) not open for device \\(deviceKey)")
                        continuation.resume()
                        return
                    }
                    
                    // Close the interface
                    try interface.close()
                    
                    // Remove from active interfaces
                    self.activeInterfaces[deviceKey]?.removeValue(forKey: interfaceNumber)
                    
                    // Clean up empty device entries
                    if self.activeInterfaces[deviceKey]?.isEmpty == true {
                        self.activeInterfaces.removeValue(forKey: deviceKey)
                    }
                    
                    self.logger.info("Successfully closed USB interface \\(interfaceNumber) for device \\(deviceKey)")
                    continuation.resume()
                } catch {
                    self.logger.error("Failed to close USB interface \\(interfaceNumber) for device \\(deviceKey): \\(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func isInterfaceOpen(device: USBDevice, interfaceNumber: UInt8) -> Bool {
        let deviceKey = deviceIdentifier(for: device)
        
        interfaceLock.lock()
        defer { interfaceLock.unlock() }
        
        return activeInterfaces[deviceKey]?[interfaceNumber] != nil
    }
    
    // MARK: - Device Claim Validation
    
    public func validateDeviceClaim(device: USBDevice) throws -> Bool {
        let deviceID = deviceIdentifier(for: device)
        
        guard deviceClaimManager.isDeviceClaimed(deviceID: deviceID) else {
            logger.error("Device \\(deviceID) is not claimed for USB operations")
            throw USBRequestError.deviceNotClaimed(deviceID)
        }
        
        return true
    }
    
    // MARK: - Transfer Methods
    
    public func executeControlTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        // Validate device claim and request type
        _ = try validateDeviceClaim(device: device)
        try validateRequest(request, expectedType: .control)
        
        // Get the USB interface (using interface 0 as default for now)
        let interface = try getInterface(for: device, interfaceNumber: 0)
        
        logger.debug("Executing control transfer for device \(device.busID)-\(device.deviceID), endpoint \(request.endpoint)")
        
        // Execute control transfer through IOKit interface
        return try await interface.executeControlTransfer(
            endpoint: request.endpoint,
            setupPacket: request.setupPacket ?? Data(),
            transferBuffer: request.transferBuffer,
            timeout: request.timeout
        )
    }
    
    public func executeBulkTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        // Validate device claim and request type
        _ = try validateDeviceClaim(device: device)
        try validateRequest(request, expectedType: .bulk)
        
        // Get the USB interface (using interface 0 as default for now)
        let interface = try getInterface(for: device, interfaceNumber: 0)
        
        logger.debug("Executing bulk transfer for device \(device.busID)-\(device.deviceID), endpoint \(request.endpoint)")
        
        // Execute bulk transfer through IOKit interface
        return try await interface.executeBulkTransfer(
            endpoint: request.endpoint,
            data: request.transferBuffer,
            bufferLength: request.bufferLength,
            timeout: request.timeout
        )
    }
    
    public func executeInterruptTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        // Validate device claim and request type
        _ = try validateDeviceClaim(device: device)
        try validateRequest(request, expectedType: .interrupt)
        
        // Get the USB interface (using interface 0 as default for now)
        let interface = try getInterface(for: device, interfaceNumber: 0)
        
        logger.debug("Executing interrupt transfer for device \(device.busID)-\(device.deviceID), endpoint \(request.endpoint)")
        
        // Execute interrupt transfer through IOKit interface
        return try await interface.executeInterruptTransfer(
            endpoint: request.endpoint,
            data: request.transferBuffer,
            bufferLength: request.bufferLength,
            timeout: request.timeout
        )
    }
    
    public func executeIsochronousTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        // Validate device claim and request type
        _ = try validateDeviceClaim(device: device)
        try validateRequest(request, expectedType: .isochronous)
        
        // Get the USB interface (using interface 0 as default for now)
        let interface = try getInterface(for: device, interfaceNumber: 0)
        
        logger.debug("Executing isochronous transfer for device \(device.busID)-\(device.deviceID), endpoint \(request.endpoint)")
        
        // Execute isochronous transfer through IOKit interface
        return try await interface.executeIsochronousTransfer(
            endpoint: request.endpoint,
            data: request.transferBuffer,
            bufferLength: request.bufferLength,
            startFrame: request.startFrame,
            numberOfPackets: max(request.numberOfPackets, 1)
        )
    }
    
    // MARK: - Helper Methods
    
    /// Generate a unique device identifier for internal tracking
    /// - Parameter device: USB device
    /// - Returns: Device identifier string
    private func deviceIdentifier(for device: USBDevice) -> String {
        return "\\(device.busID)-\\(device.deviceID)"
    }
    
    /// Validate that a USB request has the expected transfer type and required parameters
    /// - Parameters:
    ///   - request: USB request to validate
    ///   - expectedType: Expected transfer type
    /// - Throws: USBRequestError if validation fails
    private func validateRequest(_ request: USBRequestBlock, expectedType: USBTransferType) throws {
        // Validate transfer type matches expectation
        guard request.transferType == expectedType else {
            logger.error("Request transfer type mismatch: expected \(expectedType), got \(request.transferType)")
            throw USBRequestError.transferTypeNotSupported(request.transferType)
        }
        
        // Validate timeout is reasonable
        guard request.timeout > 0 && request.timeout <= 60000 else {
            logger.error("Invalid timeout value: \(request.timeout)ms")
            throw USBRequestError.timeoutInvalid(request.timeout)
        }
        
        // Transfer-specific validations
        switch expectedType {
        case .control:
            // Control transfers require setup packet
            guard request.setupPacket != nil else {
                logger.error("Control transfer missing setup packet")
                throw USBRequestError.setupPacketInvalid
            }
            
        case .bulk, .interrupt:
            // Bulk and interrupt transfers require buffer length
            guard request.bufferLength > 0 else {
                logger.error("Bulk/Interrupt transfer requires valid buffer length")
                throw USBRequestError.invalidParameters
            }
            
        case .isochronous:
            // Isochronous transfers require buffer length and packet info
            guard request.bufferLength > 0 else {
                logger.error("Isochronous transfer requires valid buffer length")
                throw USBRequestError.invalidParameters
            }
            
            let numberOfPackets = request.numberOfPackets
            guard numberOfPackets == 0 || (numberOfPackets > 0 && numberOfPackets <= 1024) else {
                logger.error("Invalid number of packets for isochronous transfer: \(numberOfPackets)")
                throw USBRequestError.invalidParameters
            }
        }
        
        logger.debug("Request validation passed for \(expectedType) transfer")
    }
    
    /// Get the IOKit interface for a specific device and interface number
    /// - Parameters:
    ///   - device: USB device
    ///   - interfaceNumber: Interface number
    /// - Returns: IOKit USB interface
    /// - Throws: USBRequestError if interface is not available
    private func getInterface(for device: USBDevice, interfaceNumber: UInt8) throws -> IOKitUSBInterface {
        let deviceKey = deviceIdentifier(for: device)
        
        interfaceLock.lock()
        defer { interfaceLock.unlock() }
        
        guard let deviceInterfaces = activeInterfaces[deviceKey],
              let interface = deviceInterfaces[interfaceNumber] else {
            logger.error("USB interface \\(interfaceNumber) not open for device \\(deviceKey)")
            throw USBRequestError.deviceNotAvailable
        }
        
        return interface
    }
    
    // MARK: - Transfer Cancellation
    
    public func cancelAllTransfers(device: USBDevice, interfaceNumber: UInt8) async throws {
        let deviceKey = deviceIdentifier(for: device)
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.interfaceLock.lock()
                defer { self.interfaceLock.unlock() }
                
                do {
                    guard let deviceInterfaces = self.activeInterfaces[deviceKey],
                          let interface = deviceInterfaces[interfaceNumber] else {
                        self.logger.debug("USB interface \\(interfaceNumber) not open for device \\(deviceKey) - no transfers to cancel")
                        continuation.resume()
                        return
                    }
                    
                    // Cancel all transfers on the interface
                    try interface.cancelAllTransfers()
                    
                    self.logger.info("Successfully cancelled all transfers on interface \\(interfaceNumber) for device \\(deviceKey)")
                    continuation.resume()
                } catch {
                    self.logger.error("Failed to cancel transfers on interface \\(interfaceNumber) for device \\(deviceKey): \\(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func cancelTransfers(device: USBDevice, interfaceNumber: UInt8, endpoint: UInt8) async throws {
        let deviceKey = deviceIdentifier(for: device)
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.interfaceLock.lock()
                defer { self.interfaceLock.unlock() }
                
                do {
                    guard let deviceInterfaces = self.activeInterfaces[deviceKey],
                          let interface = deviceInterfaces[interfaceNumber] else {
                        self.logger.debug("USB interface \\(interfaceNumber) not open for device \\(deviceKey) - no transfers to cancel")
                        continuation.resume()
                        return
                    }
                    
                    // Cancel transfers on the specific endpoint
                    try interface.cancelTransfers(endpoint: endpoint)
                    
                    self.logger.info("Successfully cancelled transfers on endpoint 0x\\(String(endpoint, radix: 16)) for device \\(deviceKey)")
                    continuation.resume()
                } catch {
                    self.logger.error("Failed to cancel transfers on endpoint 0x\\(String(endpoint, radix: 16)) for device \\(deviceKey): \\(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - IOKit Interface Factory

/// Protocol for creating IOKit USB interfaces (for dependency injection and testing)
public protocol IOKitInterfaceFactory {
    func createIOKitUSBInterface(device: USBDevice, interfaceNumber: UInt8) throws -> IOKitUSBInterface
}

/// Default implementation of IOKit interface factory
public class DefaultIOKitInterfaceFactory: IOKitInterfaceFactory {
    public init() {}
    
    public func createIOKitUSBInterface(device: USBDevice, interfaceNumber: UInt8) throws -> IOKitUSBInterface {
        return try IOKitUSBInterface(device: device, interfaceNumber: interfaceNumber)
    }
}

/// Mock factory for testing
public class MockIOKitInterfaceFactory: IOKitInterfaceFactory {
    public init() {}
    
    public func createIOKitUSBInterface(device: USBDevice, interfaceNumber: UInt8) throws -> IOKitUSBInterface {
        // In tests, this would return a mock interface
        // For now, create a real interface (tests will need proper mocking)
        return try IOKitUSBInterface(device: device, interfaceNumber: interfaceNumber)
    }
}