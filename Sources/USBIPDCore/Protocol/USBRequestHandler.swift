// USBRequestHandler.swift
// USB request handling implementation for SUBMIT and UNLINK operations

import Foundation
import Common

/// Default implementation of USB request handler for SUBMIT/UNLINK operations
/// Carries a result across the thread boundary in executeAsyncSynchronously.
///
/// Declared at file scope because Swift does not allow a type to be nested inside a
/// generic function. Access is ordered by the semaphore: the task writes before
/// signalling, the waiter reads after waiting.
private final class AsyncResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

public class USBRequestHandler: USBRequestHandlerProtocol {
    
    /// Device discovery for finding USB devices
    private let deviceDiscovery: DeviceDiscovery
    
    /// Device claim manager for validating device access
    private let deviceClaimManager: DeviceClaimManager
    
    /// USB device communicator for executing USB operations (will be injected later)
    private var deviceCommunicator: USBDeviceCommunicator?
    
    /// URB tracker for managing concurrent USB requests
    private let urbTracker: URBTracker
    
    /// USB Submit Processor for handling SUBMIT requests
    private let submitProcessor: USBSubmitProcessor
    
    /// USB Unlink Processor for handling UNLINK requests  
    private let unlinkProcessor: USBUnlinkProcessor
    
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
        
        // Initialize processors
        self.submitProcessor = USBSubmitProcessor()
        self.unlinkProcessor = USBUnlinkProcessor()
        
        // Link processors together for URB cancellation
        self.unlinkProcessor.setSubmitProcessor(self.submitProcessor)

        // Wire the submit processor for real USB traffic. This used to depend on
        // setUSBDeviceCommunicator, which nothing ever called, so the processor ran
        // permanently unconfigured and every transfer failed. Both dependencies are
        // available right here, so there is no reason to defer them to a setter.
        let communicator = USBDeviceCommunicatorImplementation(deviceClaimManager: deviceClaimManager)
        self.deviceCommunicator = communicator
        self.submitProcessor.setDeviceCommunicator(communicator)
        self.submitProcessor.setDeviceDiscovery(deviceDiscovery)
    }
    
    // MARK: - USBRequestHandlerProtocol Implementation
    
    /// Handle a USB SUBMIT request and return response data
    public func handleSubmitRequest(_ data: Data) throws -> Data {
        log("Processing USB SUBMIT request with USBSubmitProcessor", .debug)
        
        // Validate minimum data length for USB/IP header
        // These arrive after import, so they are framed with usbip_header_basic — a
        // 4-byte command at offset 0, no version — not the 8-byte op_common used by
        // the handshake. Decoding them as op_common read version 0x0000 and code
        // 0x0001, which is not a valid op code, so every SUBMIT was rejected as
        // "Unsupported USB/IP command: 0x1" before it reached a processor.
        guard data.count >= USBIPProtocol.commandMessagePrefixSize else {
            log("Invalid data length for USB SUBMIT request", .error, ["dataSize": String(data.count)])
            throw USBIPProtocolError.invalidDataLength
        }

        let header = try USBIPBasicHeader.decode(from: data)
        guard header.command == .submit else {
            log("Invalid command for USB SUBMIT request", .error, ["command": String(format: "0x%08x", header.command.rawValue)])
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Use Task to handle async processor call synchronously for now
        // In a real implementation, the protocol should be async
        let result = try executeAsyncSynchronously {
            try await self.submitProcessor.processSubmitRequest(data)
        }
        
        log("USB SUBMIT request processed successfully", .info)
        return result
    }
    
    /// Handle a USB UNLINK request and return response data
    public func handleUnlinkRequest(_ data: Data) throws -> Data {
        log("Processing USB UNLINK request with USBUnlinkProcessor", .debug)
        
        // Validate minimum data length for USB/IP header
        // These arrive after import, so they are framed with usbip_header_basic — a
        // 4-byte command at offset 0, no version — not the 8-byte op_common used by
        // the handshake. Decoding them as op_common read version 0x0000 and code
        // 0x0001, which is not a valid op code, so every UNLINK was rejected as
        // "Unsupported USB/IP command: 0x1" before it reached a processor.
        guard data.count >= USBIPProtocol.commandMessagePrefixSize else {
            log("Invalid data length for USB UNLINK request", .error, ["dataSize": String(data.count)])
            throw USBIPProtocolError.invalidDataLength
        }

        let header = try USBIPBasicHeader.decode(from: data)
        guard header.command == .unlink else {
            log("Invalid command for USB UNLINK request", .error, ["command": String(format: "0x%08x", header.command.rawValue)])
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Use Task to handle async processor call synchronously for now
        // In a real implementation, the protocol should be async
        let result = try executeAsyncSynchronously {
            try await self.unlinkProcessor.processUnlinkRequest(data)
        }
        
        log("USB UNLINK request processed successfully", .info)
        return result
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
    private func ensureDeviceCommunicator() throws -> USBDeviceCommunicator {
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
    
    /// Execute an async throwing task synchronously
    /// This is a temporary bridge until the protocol can be made async
    /// Bridge an async processor call into this synchronous request path.
    ///
    /// The previous implementation wrapped everything in MainActor.assumeIsolated.
    /// Requests are processed on ServerCoordinator's background queue, so that
    /// assertion failed and took the whole daemon down with SIGTRAP the first time a
    /// URB arrived — dispatch_assert_queue_fail, via _swift_task_checkIsolatedSwift.
    ///
    /// It would not have worked had the assertion passed: it spun on Thread.sleep
    /// while holding the main actor, which is exactly what the Task needed in order to
    /// finish, and it read `result` from two threads with no synchronization.
    ///
    /// A semaphore is the honest bridge here. Note it does block the calling thread
    /// until the operation completes; that is acceptable on a dedicated request queue,
    /// but the real fix is to make this path async end to end rather than to bridge.
    private func executeAsyncSynchronously<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let box = AsyncResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)

        // Detached so it runs on the global executor rather than inheriting whatever
        // context this happens to be called from.
        Task.detached {
            do {
                box.result = .success(try await operation())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()

        guard let result = box.result else {
            throw USBIPProtocolError.decodingFailed("async operation completed without a result")
        }
        return try result.get()
    }
}

