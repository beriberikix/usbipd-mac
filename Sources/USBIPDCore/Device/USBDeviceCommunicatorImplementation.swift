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
    
    // MARK: - Transfer Methods (Stubs for Task 9)
    
    public func executeControlTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        // This will be implemented in Task 9
        throw USBRequestError.transferTypeNotSupported(.control)
    }
    
    public func executeBulkTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        // This will be implemented in Task 9
        throw USBRequestError.transferTypeNotSupported(.bulk)
    }
    
    public func executeInterruptTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        // This will be implemented in Task 9
        throw USBRequestError.transferTypeNotSupported(.interrupt)
    }
    
    public func executeIsochronousTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        // This will be implemented in Task 9
        throw USBRequestError.transferTypeNotSupported(.isochronous)
    }
    
    // MARK: - Helper Methods
    
    /// Generate a unique device identifier for internal tracking
    /// - Parameter device: USB device
    /// - Returns: Device identifier string
    private func deviceIdentifier(for device: USBDevice) -> String {
        return "\\(device.busID)-\\(device.deviceID)"
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