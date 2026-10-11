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
    
    /// Open IOKit sessions keyed by device identifier. One per device: a session opens
    /// every interface macOS will release, so there is nothing to key by interface.
    private var activeDevices: [String: IOKitUSBDevice] = [:]
    
    /// Lock for thread-safe session management
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
    
    /// Open the device for transfers. The interface number is not used: interfaces are
    /// not opened one at a time any more, because a transfer's endpoint decides which
    /// interface it needs and the caller cannot know that. See IOKitUSBDevice.
    public func openUSBInterface(device: USBDevice, interfaceNumber: UInt8) async throws {
        _ = try validateDeviceClaim(device: device)

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    _ = try self.session(for: device)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Release the device. Every interface goes with it; see `openUSBInterface`.
    public func closeUSBInterface(device: USBDevice, interfaceNumber: UInt8) async throws {
        releaseDevice(device)
    }
    
    public func isInterfaceOpen(device: USBDevice, interfaceNumber: UInt8) -> Bool {
        let deviceKey = deviceIdentifier(for: device)
        
        interfaceLock.lock()
        defer { interfaceLock.unlock() }
        
        return activeDevices[deviceKey] != nil
    }

    /// Give back everything held for a device: its interfaces, the device open, and any
    /// transfer parked on it.
    ///
    /// Called when the client serving it disconnects. Sessions used to live until the
    /// daemon restarted, so a detached device stayed open by this process — and a later
    /// bind found its interfaces taken, by the daemon itself.
    public func releaseDevice(_ device: USBDevice) {
        let deviceKey = deviceIdentifier(for: device)

        interfaceLock.lock()
        let released = activeDevices.removeValue(forKey: deviceKey)
        interfaceLock.unlock()

        guard let session = released else { return }
        // Closed outside the lock: close() makes IOKit calls, and wakes parked transfers
        // that will want the lock to report their completion.
        session.close()
        logger.info("Released device \(deviceKey)")
    }

    /// The open session for a device, opening one on first use.
    private func session(for device: USBDevice) throws -> IOKitUSBDevice {
        let deviceKey = deviceIdentifier(for: device)

        interfaceLock.lock()
        defer { interfaceLock.unlock() }

        if let existing = activeDevices[deviceKey] {
            return existing
        }

        let session = try ioKitInterfaceFactory.createIOKitUSBDevice(device: device)
        do {
            try session.open()
        } catch {
            session.close()
            logger.error("Failed to open device \(deviceKey): \(error)")
            throw error
        }
        activeDevices[deviceKey] = session
        return session
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
    
    /// Ask the device what kind of endpoint this is. IOKit reports the type from the
    /// device's own descriptors, which is the only authoritative source — USB/IP does
    /// not put it on the wire.
    ///
    /// Opens the device if it is not open yet. This is asked before the first transfer
    /// runs, and answering nil then sent that transfer down the inference path, which
    /// guesses.
    public func endpointTransferType(device: USBDevice, endpoint: UInt8) -> USBTransferType? {
        guard let session = try? session(for: device),
              let raw = session.transferType(for: endpoint) else {
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
        _ = try validateDeviceClaim(device: device)
        try validateRequest(request, expectedType: .control)
        
        let session = try getSession(for: device)
        
        logger.debug("Executing control transfer for device \(device.busID)-\(device.deviceID), endpoint \(request.endpoint)")
        
        let result = try await session.executeControlTransfer(
            setupPacket: request.setupPacket ?? Data(),
            transferBuffer: request.transferBuffer,
            timeout: request.timeout
        )
        discardSessionIfDeviceGone(result, device: device)
        return result
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
        _ = try validateDeviceClaim(device: device)
        try validateRequest(request, expectedType: .bulk)
        return try await executePipeTransfer(device: device, request: request)
    }
    
    public func executeInterruptTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        _ = try validateDeviceClaim(device: device)
        try validateRequest(request, expectedType: .interrupt)
        return try await executePipeTransfer(device: device, request: request)
    }

    /// Bulk and interrupt run through the same IOKit pipe calls.
    private func executePipeTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        let session = try getSession(for: device)
        
        logger.debug("Executing \(request.transferType) transfer for device \(device.busID)-\(device.deviceID), endpoint \(request.endpoint)")
        
        let result = try await session.executePipeTransfer(
            endpoint: endpointAddress(for: request),
            data: request.transferBuffer,
            bufferLength: request.bufferLength,
            timeout: request.timeout
        )
        discardSessionIfDeviceGone(result, device: device)
        return result
    }
    
    public func executeIsochronousTransfer(device: USBDevice, request: USBRequestBlock) async throws -> USBTransferResult {
        // Validate device claim and request type
        _ = try validateDeviceClaim(device: device)
        try validateRequest(request, expectedType: .isochronous)
        
        let session = try getSession(for: device)
        
        logger.debug("Executing isochronous transfer for device \(device.busID)-\(device.deviceID), endpoint \(request.endpoint)")
        
        let result = try await session.executeIsochronousTransfer(
            endpoint: endpointAddress(for: request),
            data: request.transferBuffer,
            bufferLength: request.bufferLength,
            startFrame: request.startFrame,
            numberOfPackets: max(request.numberOfPackets, 1)
        )
        discardSessionIfDeviceGone(result, device: device)
        return result
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
    
    /// The session for a device, opening it if this is the first transfer.
    private func getSession(for device: USBDevice) throws -> IOKitUSBDevice {
        do {
            return try session(for: device)
        } catch {
            logger.error("Device \(deviceIdentifier(for: device)) could not be opened: \(error)")
            throw USBRequestError.deviceNotAvailable
        }
    }
    
    /// Whether a transfer result means the cached session can no longer be used.
    ///
    /// `deviceGone` is what both `kIOReturnNoDevice` and `kIOReturnNotResponding` map
    /// to. Either way the IOKit handles behind the session are finished, and every
    /// transfer through them will keep failing.
    static func shouldDiscardInterface(after status: USBStatus) -> Bool {
        return status == .deviceGone
    }

    /// Drop a session whose device has gone, so the next request opens a new one
    /// instead of reusing handles that can only fail.
    ///
    /// Sessions are opened once and kept. That is right while a device stays put, and
    /// wrong the moment it does not: a device that disappears briefly — re-enumerating,
    /// or an Android phone changing its USB configuration — left the daemon holding a
    /// dead handle, and every subsequent transfer returned "no device" until the daemon
    /// was restarted. Observed with a Pixel, where a fresh daemon worked immediately
    /// while the running one never recovered.
    private func discardSessionIfDeviceGone(_ result: USBTransferResult, device: USBDevice) {
        guard USBDeviceCommunicatorImplementation.shouldDiscardInterface(after: result.status) else {
            return
        }
        logger.warning("Device reported gone; discarding its session so it is reopened", context: [
            "device": deviceIdentifier(for: device)
        ])
        releaseDevice(device)
    }

    // MARK: - Transfer Cancellation
    
    /// Abort everything outstanding on the device. Sessions span every interface, so
    /// the interface number no longer narrows anything.
    public func cancelAllTransfers(device: USBDevice, interfaceNumber: UInt8) async throws {
        existingSession(for: device)?.cancelAllTransfers()
    }
    
    /// Abort what is outstanding on one endpoint. The session knows which interface owns
    /// it, which the caller does not — CMD_UNLINK carries no endpoint at all.
    public func cancelTransfers(device: USBDevice, interfaceNumber: UInt8, endpoint: UInt8) async throws {
        guard let session = existingSession(for: device) else {
            logger.debug("Device \(deviceIdentifier(for: device)) not open - no transfers to cancel")
            return
        }
        session.cancelTransfers(endpoint: endpoint)
    }

    /// A session only if one is already open. Cancelling must never open a device.
    private func existingSession(for device: USBDevice) -> IOKitUSBDevice? {
        interfaceLock.lock()
        defer { interfaceLock.unlock() }
        return activeDevices[deviceIdentifier(for: device)]
    }
}

// MARK: - IOKit Interface Factory

/// Protocol for creating IOKit device sessions (for dependency injection and testing)
public protocol IOKitInterfaceFactory {
    func createIOKitUSBDevice(device: USBDevice) throws -> IOKitUSBDevice
}

/// Default implementation of IOKit interface factory
public class DefaultIOKitInterfaceFactory: IOKitInterfaceFactory {
    public init() {}
    
    public func createIOKitUSBDevice(device: USBDevice) throws -> IOKitUSBDevice {
        return try IOKitUSBDevice(device: device)
    }
}

// MockIOKitInterfaceFactory was removed. Despite the name it returned a real
// IOKit wrapper — "in tests, this would return a mock interface / for now, create a
// real interface" — so any test reaching for it would have opened live hardware while
// believing it was mocked. Nothing referenced it. A real mock belongs here if the
// transfer path ever needs one, but an empty shell with a misleading name is worse
// than nothing.