// USBDeviceCommunicatorImplementation.swift
// Production USB device communication implementation using IOKit integration

import Foundation
import IOKit
import IOKit.usb
@preconcurrency import Common

/// Production implementation of USB device communication using IOKit integration
/// Replaces placeholder implementations with real USB/IP device sharing capabilities
public class USBDeviceCommunicatorImplementation: USBDeviceCommunicator, @unchecked Sendable {
    
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
                        self.logger.debug("USB interface \(interfaceNumber) already open for device \(deviceKey)")
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
                    
                    self.logger.info("Successfully opened USB interface \(interfaceNumber) for device \(deviceKey)")
                    continuation.resume()
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
                    guard let deviceInterfaces = self.activeInterfaces[deviceKey],
                          let interface = deviceInterfaces[interfaceNumber] else {
                        self.logger.debug("USB interface \(interfaceNumber) not open for device \(deviceKey)")
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
                    
                    self.logger.info("Successfully closed USB interface \(interfaceNumber) for device \(deviceKey)")
                    continuation.resume()
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
        
        return activeInterfaces[deviceKey]?[interfaceNumber] != nil
    }
    
    // MARK: - Device Claim Validation
    
    public func validateDeviceClaim(device: USBDevice) throws -> Bool {
        let deviceID = deviceIdentifier(for: device)

        // Not being "claimed" does not stop a transfer.
        //
        // The claim is recorded by the System Extension manager, which cannot be
        // activated on a shipping install. Gating transfers on it meant that once the
        // manager stopped being started at launch, every transfer failed with
        // "Device not claimed for USB operations" — the third place a fictional claim
        // blocked real work, after bind and import.
        //
        // What actually gates access is real: the allow-list decides which devices are
        // offered at all, and IOKit refuses to open an interface another driver owns.
        if !deviceClaimManager.isDeviceClaimed(deviceID: deviceID) {
            logger.debug("Device \(deviceID) has no recorded claim; proceeding via IOKit")
        }

        return true
    }
    
    // MARK: - Transfer Methods
    
    /// Ask the open interface what kind of endpoint this is. IOKit reports the type
    /// from the device's own descriptors, which is the only authoritative source —
    /// USB/IP does not put it on the wire.
    public func endpointTransferType(device: USBDevice, endpoint: UInt8) -> USBTransferType? {
        guard let interface = try? getInterface(for: device, interfaceNumber: 0),
              let raw = interface.transferType(for: endpoint) else {
            return nil
        }

        switch raw {
        case 0: return .control
        case 1: return .isochronous
        case 2: return .bulk
        case 3: return .interrupt
        default: return nil
        }
    }

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
    
    // Compose the USB endpoint address IOKit expects.
    //
    // USB/IP carries the endpoint number and its direction in separate fields:
    // usbip_header_basic.ep is the bare number (0-15) and direction is a distinct
    // field. The IOKit layer, like USB itself, encodes direction in bit 7 of the
    // endpoint address. Passing ep through untouched meant every IN transfer from a
    // real client — which sends ep=1, direction=1 — arrived with bit 7 clear and was
    // executed as an OUT, failing with "No data provided for bulk OUT transfer".
    // Internal rather than private so the mapping can be asserted directly; the
    // IOKit factory returns a concrete type, leaving no seam to capture the call.
    func endpointAddress(for request: USBRequestBlock) -> UInt8 {
        let number = request.endpoint & 0x7F
        return request.direction == .in ? (number | 0x80) : number
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
            endpoint: endpointAddress(for: request),
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
            endpoint: endpointAddress(for: request),
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
            endpoint: endpointAddress(for: request),
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
        return "\(device.busID)-\(device.deviceID)"
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
            logger.error("USB interface \(interfaceNumber) not open for device \(deviceKey)")
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
                        self.logger.debug("USB interface \(interfaceNumber) not open for device \(deviceKey) - no transfers to cancel")
                        continuation.resume()
                        return
                    }
                    
                    // Cancel all transfers on the interface
                    try interface.cancelAllTransfers()
                    
                    self.logger.info("Successfully cancelled all transfers on interface \(interfaceNumber) for device \(deviceKey)")
                    continuation.resume()
                } catch {
                    self.logger.error("Failed to cancel transfers on interface \(interfaceNumber) for device \(deviceKey): \(error)")
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
                        self.logger.debug("USB interface \(interfaceNumber) not open for device \(deviceKey) - no transfers to cancel")
                        continuation.resume()
                        return
                    }
                    
                    // Cancel transfers on the specific endpoint
                    try interface.cancelTransfers(endpoint: endpoint)
                    
                    self.logger.info("Successfully cancelled transfers on endpoint 0x\(String(endpoint, radix: 16)) for device \(deviceKey)")
                    continuation.resume()
                } catch {
                    self.logger.error("Failed to cancel transfers on endpoint 0x\(String(endpoint, radix: 16)) for device \(deviceKey): \(error)")
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

// MockIOKitInterfaceFactory was removed. Despite the name it returned a real
// IOKitUSBInterface — "in tests, this would return a mock interface / for now, create a
// real interface" — so any test reaching for it would have opened live hardware while
// believing it was mocked. Nothing referenced it. A real mock belongs here if the
// transfer path ever needs one, but an empty shell with a misleading name is worse
// than nothing.