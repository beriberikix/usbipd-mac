// IOKitDeviceDiscovery.swift
// IOKit-based USB device discovery implementation

import Foundation
import IOKit
import IOKit.usb
import Common

// MARK: - Supporting Types

/// Internal structure to hold extracted device properties
private struct DeviceProperties {
    let vendorID: UInt16
    let productID: UInt16
    let deviceClass: UInt8
    let deviceSubClass: UInt8
    let deviceProtocol: UInt8
    let speed: USBSpeed
    let manufacturerString: String?
    let productString: String?
    let serialNumberString: String?
}

/// IOKit-based implementation of USB device discovery
public class IOKitDeviceDiscovery: DeviceDiscovery {
    
    // MARK: - Properties
    
    public var onDeviceConnected: ((USBDevice) -> Void)?
    public var onDeviceDisconnected: ((USBDevice) -> Void)?
    
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var isMonitoring: Bool = false
    
    // Cache of connected devices for proper disconnection callbacks
    private var connectedDevices: [String: USBDevice] = [:]
    
    private let logger: Logger
    private let queue: DispatchQueue
    private let ioKit: IOKitInterface
    
    // MARK: - Initialization
    
    public init() {
        self.logger = Logger(
            config: LoggerConfig(level: .info), 
            subsystem: "com.usbipd.mac", 
            category: "device-discovery"
        )
        self.queue = DispatchQueue(
            label: "com.usbipd.mac.device-discovery",
            qos: .userInitiated
        )
        self.ioKit = RealIOKitInterface()
        
        logger.debug("IOKitDeviceDiscovery initialized with dedicated dispatch queue")
    }
    
    /// Internal initializer for testing with dependency injection
    internal init(ioKit: IOKitInterface, logger: Logger? = nil) {
        self.ioKit = ioKit
        self.logger = logger ?? Logger(
            config: LoggerConfig(level: .info), 
            subsystem: "com.usbipd.mac", 
            category: "device-discovery"
        )
        self.queue = DispatchQueue(
            label: "com.usbipd.mac.device-discovery",
            qos: .userInitiated
        )
        
        self.logger.debug("IOKitDeviceDiscovery initialized with injected IOKit interface for testing")
    }
    
    deinit {
        // Ensure notifications are stopped and resources are cleaned up
        if isMonitoring {
            logger.warning("IOKitDeviceDiscovery being deinitialized while monitoring is active")
            stopNotifications()
        }
        
        // Final verification that all resources are cleaned up
        if !verifyNotificationCleanup() {
            logger.error("IOKitDeviceDiscovery deinitialized with unclean notification state")
        }
        
        logger.debug("IOKitDeviceDiscovery deinitialized")
    }
    
    // MARK: - IOKit Memory Management Utilities
    
    /// RAII wrapper for IOKit objects that need to be released
    private class IOKitObjectWrapper {
        private let object: io_object_t
        
        init(_ object: io_object_t) {
            self.object = object
        }
        
        deinit {
            if object != 0 {
                IOObjectRelease(object)
            }
        }
        
        var value: io_object_t {
            return object
        }
    }
    
    /// Safely execute a block with automatic IOKit object cleanup
    private func withIOKitObject<T>(_ object: io_object_t, _ block: (io_object_t) throws -> T) rethrows -> T {
        defer {
            if object != 0 {
                _ = ioKit.objectRelease(object)
            }
        }
        return try block(object)
    }
    
    // MARK: - IOKit Error Handling Utilities
    
    /// Convert IOKit error codes to DeviceDiscoveryError with detailed logging
    /// Provides comprehensive error mapping and logging for IOKit operations
    private func handleIOKitError(_ result: kern_return_t, operation: String, context: [String: Any] = [:]) -> DeviceDiscoveryError {
        let errorDescription = getIOKitErrorDescription(result)
        let errorMessage = "IOKit operation '\(operation)' failed: \(errorDescription)"
        
        var logContext = context
        logContext["kern_return"] = result
        logContext["operation"] = operation
        logContext["error_description"] = errorDescription
        logContext["error_category"] = getIOKitErrorCategory(result)
        
        logger.error(errorMessage, context: logContext)
        return DeviceDiscoveryError.ioKitError(result, errorMessage)
    }
    
    /// Get human-readable description for IOKit error codes
    /// Maps common IOKit error codes to descriptive messages
    private func getIOKitErrorDescription(_ result: kern_return_t) -> String {
        switch result {
        case KERN_SUCCESS:
            return "Success"
        case KERN_INVALID_ARGUMENT:
            return "Invalid argument provided to IOKit function"
        case KERN_FAILURE:
            return "General IOKit failure"
        case KERN_RESOURCE_SHORTAGE:
            return "Insufficient system resources"
        case KERN_NO_SPACE:
            return "No space available"
        case KERN_INVALID_ADDRESS:
            return "Invalid memory address"
        case KERN_PROTECTION_FAILURE:
            return "Memory protection violation"
        case KERN_NO_ACCESS:
            return "Access denied - insufficient privileges"
        case KERN_MEMORY_FAILURE:
            return "Memory allocation failure"
        case KERN_MEMORY_ERROR:
            return "Memory error"
        case KERN_NOT_IN_SET:
            return "Object not found in set"
        case KERN_NAME_EXISTS:
            return "Name already exists"
        case KERN_ABORTED:
            return "Operation aborted"
        case KERN_INVALID_NAME:
            return "Invalid name specified"
        case KERN_INVALID_TASK:
            return "Invalid task"
        case KERN_INVALID_RIGHT:
            return "Invalid right"
        case KERN_INVALID_VALUE:
            return "Invalid value"
        case KERN_UREFS_OVERFLOW:
            return "User references overflow"
        case KERN_INVALID_CAPABILITY:
            return "Invalid capability"
        case KERN_RIGHT_EXISTS:
            return "Right already exists"
        case KERN_INVALID_HOST:
            return "Invalid host"
        case KERN_MEMORY_PRESENT:
            return "Memory already present"
        case KERN_MEMORY_DATA_MOVED:
            return "Memory data moved"
        case KERN_MEMORY_RESTART_COPY:
            return "Memory restart copy"
        case KERN_INVALID_PROCESSOR_SET:
            return "Invalid processor set"
        case KERN_POLICY_LIMIT:
            return "Policy limit exceeded"
        case KERN_INVALID_POLICY:
            return "Invalid policy"
        case KERN_INVALID_OBJECT:
            return "Invalid object"
        case KERN_ALREADY_IN_SET:
            return "Object already in set"
        case KERN_NOT_FOUND:
            return "Object not found"
        case KERN_NOT_RECEIVER:
            return "Not a receiver"
        case KERN_SEMAPHORE_DESTROYED:
            return "Semaphore destroyed"
        case KERN_RPC_SERVER_TERMINATED:
            return "RPC server terminated"
        case KERN_RPC_TERMINATE_ORPHAN:
            return "RPC terminate orphan"
        case KERN_RPC_CONTINUE_ORPHAN:
            return "RPC continue orphan"
        case KERN_NOT_SUPPORTED:
            return "Operation not supported"
        case KERN_NODE_DOWN:
            return "Node is down"
        case KERN_NOT_WAITING:
            return "Thread not waiting"
        case KERN_OPERATION_TIMED_OUT:
            return "Operation timed out"
        case KERN_CODESIGN_ERROR:
            return "Code signing error"
        case KERN_POLICY_STATIC:
            return "Policy is static"

        case KERN_DENIED:
            return "Operation denied"

        case KERN_RETURN_MAX:
            return "Maximum return value"
        default:
            // Handle IOKit-specific error codes (cast to UInt32 for comparison)
            let unsignedResult = UInt32(bitPattern: result)
            if unsignedResult >= 0xe00002bc && unsignedResult <= 0xe00002ff {
                return getIOKitSpecificErrorDescription(result)
            }
            return "Unknown IOKit error (code: \(String(format: "0x%08x", UInt32(bitPattern: result))))"
        }
    }
    
    /// Get descriptions for IOKit-specific error codes
    /// Handles IOKit framework specific error codes beyond general kernel errors
    private func getIOKitSpecificErrorDescription(_ result: kern_return_t) -> String {
        let unsignedResult = UInt32(bitPattern: result)
        switch unsignedResult {
        case 0xe00002bc: // kIOReturnError
            return "General IOKit error"
        case 0xe00002bd: // kIOReturnNoMemory
            return "IOKit memory allocation failed"
        case 0xe00002be: // kIOReturnNoResources
            return "IOKit resources unavailable"
        case 0xe00002bf: // kIOReturnIPCError
            return "IOKit IPC communication error"
        case 0xe00002c0: // kIOReturnNoDevice
            return "IOKit device not found"
        case 0xe00002c1: // kIOReturnNotPrivileged
            return "IOKit operation requires elevated privileges"
        case 0xe00002c2: // kIOReturnBadArgument
            return "IOKit invalid argument"
        case 0xe00002c3: // kIOReturnLockedRead
            return "IOKit locked for reading"
        case 0xe00002c4: // kIOReturnLockedWrite
            return "IOKit locked for writing"
        case 0xe00002c5: // kIOReturnExclusiveAccess
            return "IOKit device requires exclusive access"
        case 0xe00002c6: // kIOReturnBadMessageID
            return "IOKit invalid message ID"
        case 0xe00002c7: // kIOReturnUnsupported
            return "IOKit operation not supported"
        case 0xe00002c8: // kIOReturnVMError
            return "IOKit virtual memory error"
        case 0xe00002c9: // kIOReturnInternalError
            return "IOKit internal error"
        case 0xe00002ca: // kIOReturnIOError
            return "IOKit I/O error"
        case 0xe00002cb: // kIOReturnCannotLock
            return "IOKit cannot acquire lock"
        case 0xe00002cc: // kIOReturnNotOpen
            return "IOKit device not open"
        case 0xe00002cd: // kIOReturnNotReadable
            return "IOKit device not readable"
        case 0xe00002ce: // kIOReturnNotWritable
            return "IOKit device not writable"
        case 0xe00002cf: // kIOReturnNotAligned
            return "IOKit data not aligned"
        case 0xe00002d0: // kIOReturnBadMedia
            return "IOKit bad media"
        case 0xe00002d1: // kIOReturnStillOpen
            return "IOKit device still open"
        case 0xe00002d2: // kIOReturnRLDError
            return "IOKit runtime linker error"
        case 0xe00002d3: // kIOReturnDMAError
            return "IOKit DMA error"
        case 0xe00002d4: // kIOReturnBusy
            return "IOKit device busy"
        case 0xe00002d5: // kIOReturnTimeout
            return "IOKit operation timed out"
        case 0xe00002d6: // kIOReturnOffline
            return "IOKit device offline"
        case 0xe00002d7: // kIOReturnNotReady
            return "IOKit device not ready"
        case 0xe00002d8: // kIOReturnNotAttached
            return "IOKit device not attached"
        case 0xe00002d9: // kIOReturnNoChannels
            return "IOKit no channels available"
        case 0xe00002da: // kIOReturnNoSpace
            return "IOKit no space available"
        case 0xe00002db: // kIOReturnPortExists
            return "IOKit port already exists"
        case 0xe00002dc: // kIOReturnCannotWire
            return "IOKit cannot wire memory"
        case 0xe00002dd: // kIOReturnNoInterrupt
            return "IOKit no interrupt available"
        case 0xe00002de: // kIOReturnNoFrames
            return "IOKit no frames available"
        case 0xe00002df: // kIOReturnMessageTooLarge
            return "IOKit message too large"
        case 0xe00002e0: // kIOReturnNotPermitted
            return "IOKit operation not permitted"
        case 0xe00002e1: // kIOReturnNoPower
            return "IOKit insufficient power"
        case 0xe00002e2: // kIOReturnNoMedia
            return "IOKit no media present"
        case 0xe00002e3: // kIOReturnUnformattedMedia
            return "IOKit media not formatted"
        case 0xe00002e4: // kIOReturnUnsupportedMode
            return "IOKit unsupported mode"
        case 0xe00002e5: // kIOReturnUnderrun
            return "IOKit data underrun"
        case 0xe00002e6: // kIOReturnOverrun
            return "IOKit data overrun"
        case 0xe00002e7: // kIOReturnDeviceError
            return "IOKit device error"
        case 0xe00002e8: // kIOReturnNoCompletion
            return "IOKit no completion routine"
        case 0xe00002e9: // kIOReturnAborted
            return "IOKit operation aborted"
        case 0xe00002ea: // kIOReturnNoBandwidth
            return "IOKit insufficient bandwidth"
        case 0xe00002eb: // kIOReturnNotResponding
            return "IOKit device not responding"
        case 0xe00002ec: // kIOReturnIsoTooOld
            return "IOKit isochronous request too old"
        case 0xe00002ed: // kIOReturnIsoTooNew
            return "IOKit isochronous request too new"
        case 0xe00002ee: // kIOReturnNotFound
            return "IOKit object not found"
        case 0xe00002ef: // kIOReturnInvalid
            return "IOKit invalid operation"
        default:
            return "Unknown IOKit-specific error (code: \(String(format: "0x%08x", unsignedResult)))"
        }
    }
    
    /// Categorize IOKit errors for better error handling
    /// Groups errors into categories for appropriate handling strategies
    private func getIOKitErrorCategory(_ result: kern_return_t) -> String {
        let unsignedResult = UInt32(bitPattern: result)
        switch result {
        case KERN_SUCCESS:
            return "success"
        case KERN_NO_ACCESS, KERN_PROTECTION_FAILURE:
            return "permission"
        case KERN_RESOURCE_SHORTAGE, KERN_NO_SPACE, KERN_MEMORY_FAILURE, KERN_MEMORY_ERROR:
            return "resource"
        case KERN_INVALID_ARGUMENT, KERN_INVALID_ADDRESS, KERN_INVALID_VALUE:
            return "argument"
        case KERN_NOT_FOUND:
            return "not_found"
        case KERN_OPERATION_TIMED_OUT:
            return "timeout"
        case KERN_NOT_SUPPORTED:
            return "unsupported"
        default:
            // Check IOKit-specific error codes
            switch unsignedResult {
            case 0xe00002c1: // kIOReturnNotPrivileged
                return "permission"
            case 0xe00002bd: // kIOReturnNoMemory
                return "resource"
            case 0xe00002c2: // kIOReturnBadArgument
                return "argument"
            case 0xe00002c0, 0xe00002ee: // kIOReturnNoDevice, kIOReturnNotFound
                return "not_found"
            case 0xe00002d5: // kIOReturnTimeout
                return "timeout"
            case 0xe00002d4: // kIOReturnBusy
                return "busy"
            case 0xe00002ca, 0xe00002e7: // kIOReturnIOError, kIOReturnDeviceError
                return "hardware"
            case 0xe00002c7: // kIOReturnUnsupported
                return "unsupported"
            default:
                return "unknown"
            }
        }
    }
    
    /// Helper method for common IOKit service access errors
    /// Provides standardized error handling for service enumeration failures
    private func handleServiceAccessError(_ result: kern_return_t, operation: String = "service access") -> DeviceDiscoveryError {
        let context = [
            "error_type": "service_access",
            "common_causes": getServiceAccessErrorCauses(result)
        ]
        return handleIOKitError(result, operation: operation, context: context)
    }
    
    /// Helper method for common IOKit property access errors
    /// Provides standardized error handling for property extraction failures
    private func handlePropertyAccessError(_ result: kern_return_t, property: String, operation: String = "property access") -> DeviceDiscoveryError {
        let context = [
            "error_type": "property_access",
            "property": property,
            "common_causes": getPropertyAccessErrorCauses(result)
        ]
        return handleIOKitError(result, operation: operation, context: context)
    }
    
    /// Helper method for common IOKit notification errors
    /// Provides standardized error handling for notification setup failures
    private func handleNotificationError(_ result: kern_return_t, operation: String = "notification setup") -> DeviceDiscoveryError {
        let context = [
            "error_type": "notification",
            "common_causes": getNotificationErrorCauses(result)
        ]
        return handleIOKitError(result, operation: operation, context: context)
    }
    
    /// Get common causes for service access errors
    private func getServiceAccessErrorCauses(_ result: kern_return_t) -> String {
        let unsignedResult = UInt32(bitPattern: result)
        switch result {
        case KERN_NO_ACCESS:
            return "Application lacks required entitlements or running without proper privileges"
        case KERN_RESOURCE_SHORTAGE, KERN_NO_SPACE:
            return "System resources exhausted, try closing other applications"
        case KERN_NOT_FOUND:
            return "No USB devices found or USB subsystem not available"
        case KERN_INVALID_ARGUMENT:
            return "Invalid matching dictionary or service parameters"
        default:
            if unsignedResult == 0xe00002c1 { // kIOReturnNotPrivileged
                return "Application lacks required entitlements or running without proper privileges"
            }
            return "Check system logs for additional details"
        }
    }
    
    /// Get common causes for property access errors
    private func getPropertyAccessErrorCauses(_ result: kern_return_t) -> String {
        let unsignedResult = UInt32(bitPattern: result)
        switch result {
        case KERN_NO_ACCESS:
            return "Property access denied, device may require elevated privileges"
        case KERN_NOT_FOUND:
            return "Property not available for this device type"
        case KERN_INVALID_ARGUMENT:
            return "Invalid property key or device service"
        default:
            if unsignedResult == 0xe00002c0 { // kIOReturnNoDevice
                return "Device disconnected during property access"
            }
            return "Property may not be supported by this device"
        }
    }
    
    /// Get common causes for notification errors
    private func getNotificationErrorCauses(_ result: kern_return_t) -> String {
        let unsignedResult = UInt32(bitPattern: result)
        switch result {
        case KERN_NO_ACCESS:
            return "Notification setup requires elevated privileges"
        case KERN_RESOURCE_SHORTAGE:
            return "System notification resources exhausted"
        case KERN_INVALID_ARGUMENT:
            return "Invalid notification parameters or callback"
        default:
            if unsignedResult == 0xe00002bc { // kIOReturnError
                return "IOKit notification system error, try restarting application"
            }
            return "Check system notification limits and permissions"
        }
    }
    
    /// Safely execute IOKit operations with automatic error handling
    /// Wraps IOKit operations with comprehensive error handling and logging
    private func safeIOKitOperation<T>(_ operation: String, _ block: () throws -> T) throws -> T {
        do {
            logger.debug("Starting IOKit operation", context: ["operation": operation])
            let result = try block()
            logger.debug("IOKit operation completed successfully", context: ["operation": operation])
            return result
        } catch let error as DeviceDiscoveryError {
            // Re-throw DeviceDiscoveryError with additional context
            logger.error("IOKit operation failed", context: [
                "operation": operation,
                "error": error.localizedDescription
            ])
            throw error
        } catch {
            // Convert unexpected errors to DeviceDiscoveryError
            let message = "Unexpected error during IOKit operation '\(operation)': \(error.localizedDescription)"
            logger.error(message, context: [
                "operation": operation,
                "error_type": String(describing: type(of: error))
            ])
            throw DeviceDiscoveryError.ioKitError(-1, message)
        }
    }
    
    // MARK: - DeviceDiscovery Protocol
    
    public func discoverDevices() throws -> [USBDevice] {
        return try queue.sync {
            return try discoverDevicesInternal()
        }
    }
    
    /// Internal device discovery method that doesn't use queue synchronization
    private func discoverDevicesInternal() throws -> [USBDevice] {
        return try safeIOKitOperation("device discovery") {
            logger.debug("Starting USB device discovery")
            var devices: [USBDevice] = []
            var skippedDevices = 0
            let unsupportedDevices = 0
            
            // Create matching dictionary for USB devices
            guard let matchingDict = ioKit.serviceMatching(kIOUSBDeviceClassName) else {
                logger.error("Failed to create IOKit matching dictionary")
                throw DeviceDiscoveryError.failedToCreateMatchingDictionary
            }
            
            logger.debug("Created IOKit matching dictionary for USB devices", context: [
                "className": kIOUSBDeviceClassName
            ])
            
            var iterator: io_iterator_t = 0
            let result = ioKit.serviceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator)
            
            guard result == KERN_SUCCESS else {
                throw handleServiceAccessError(result, operation: "IOServiceGetMatchingServices")
            }
            
            logger.debug("Successfully obtained IOKit service iterator", context: [
                "iterator": iterator
            ])
        
        return withIOKitObject(iterator) { iterator in
            logger.debug("Iterating through discovered USB devices")
            var deviceCount = 0
            var service: io_service_t = ioKit.iteratorNext(iterator)
            
            while service != 0 {
                do {
                    let device = try withIOKitObject(service) { service in
                        return try createUSBDeviceFromService(service)
                    }
                    
                    devices.append(device)
                    deviceCount += 1
                    
                    logger.debug("Successfully enumerated USB device", context: [
                        "deviceIndex": deviceCount,
                        "busID": device.busID,
                        "deviceID": device.deviceID,
                        "vendorID": String(format: "0x%04x", device.vendorID),
                        "productID": String(format: "0x%04x", device.productID),
                        "deviceClass": String(format: "0x%02x", device.deviceClass),
                        "deviceSubClass": String(format: "0x%02x", device.deviceSubClass),
                        "deviceProtocol": String(format: "0x%02x", device.deviceProtocol),
                        "speed": device.speed.rawValue,
                        "product": device.productString ?? "Unknown",
                        "manufacturer": device.manufacturerString ?? "Unknown",
                        "hasSerial": device.serialNumberString != nil
                    ])
                    
                } catch let error as DeviceDiscoveryError {
                    // Handle device enumeration errors gracefully - continue with other devices
                    switch error {
                    case .missingProperty(let property):
                        logger.warning("Skipping device due to missing required property", context: [
                            "missingProperty": property,
                            "deviceIndex": deviceCount + 1,
                            "action": "skipped"
                        ])
                        skippedDevices += 1
                    case .invalidPropertyType(let property):
                        logger.warning("Skipping device due to invalid property type", context: [
                            "invalidProperty": property,
                            "deviceIndex": deviceCount + 1,
                            "action": "skipped"
                        ])
                        skippedDevices += 1
                    case .ioKitError(let code, let message):
                        logger.warning("Skipping device due to IOKit error", context: [
                            "ioKitCode": code,
                            "ioKitMessage": message,
                            "deviceIndex": deviceCount + 1,
                            "action": "skipped"
                        ])
                        skippedDevices += 1
                    default:
                        logger.warning("Skipping device due to unexpected error", context: [
                            "error": error.localizedDescription,
                            "deviceIndex": deviceCount + 1,
                            "action": "skipped"
                        ])
                        skippedDevices += 1
                    }
                } catch {
                    logger.warning("Skipping device due to unexpected error", context: [
                        "error": error.localizedDescription,
                        "errorType": String(describing: type(of: error)),
                        "deviceIndex": deviceCount + 1,
                        "action": "skipped"
                    ])
                    skippedDevices += 1
                }
                
                service = ioKit.iteratorNext(iterator)
            }
            
            // Log comprehensive discovery summary
            logger.info("USB device discovery completed", context: [
                "successfulDevices": deviceCount,
                "skippedDevices": skippedDevices,
                "unsupportedDevices": unsupportedDevices,
                "totalProcessed": deviceCount + skippedDevices + unsupportedDevices
            ])
            
            if skippedDevices > 0 {
                logger.warning("Some devices were skipped during enumeration", context: [
                    "skippedCount": skippedDevices,
                    "successfulCount": deviceCount,
                    "recommendation": "Check device permissions and IOKit access"
                ])
            }
            
            return devices
        }
        }
    }
    
    public func getDevice(busID: String, deviceID: String) throws -> USBDevice? {
        return queue.sync {
            logger.debug("Starting device lookup", context: [
                "busID": busID, 
                "deviceID": deviceID,
                "operation": "getDevice"
            ])
            
            // Validate input parameters before proceeding
            guard !busID.isEmpty && !deviceID.isEmpty else {
                logger.warning("Invalid device lookup parameters", context: [
                    "busID": busID.isEmpty ? "empty" : busID,
                    "deviceID": deviceID.isEmpty ? "empty" : deviceID,
                    "result": "nil"
                ])
                return nil
            }
            
            // Handle IOKit errors gracefully by catching them and returning nil
            // This satisfies requirement 4.5: handle IOKit errors gracefully and return nil
            do {
                logger.debug("Discovering devices for lookup operation")
                
                // Discover devices directly without calling the public method to avoid queue deadlock
                let devices = try discoverDevicesInternal()
                
                logger.debug("Device discovery completed for lookup", context: [
                    "totalDevicesFound": devices.count,
                    "searchingFor": "\(busID):\(deviceID)"
                ])
                
                // Find device matching the specified bus and device IDs
                // This satisfies requirement 4.4: return only the device matching the specified IDs
                let device = devices.first { device in
                    return device.busID == busID && device.deviceID == deviceID
                }
                
                if let device = device {
                    logger.info("Device lookup successful", context: [
                        "busID": device.busID,
                        "deviceID": device.deviceID,
                        "vendorID": String(format: "0x%04x", device.vendorID),
                        "productID": String(format: "0x%04x", device.productID),
                        "product": device.productString ?? "Unknown",
                        "manufacturer": device.manufacturerString ?? "Unknown",
                        "operation": "getDevice",
                        "result": "found"
                    ])
                    return device
                } else {
                    // This satisfies requirements 4.2 and 4.3: return nil for invalid IDs or disconnected devices
                    logger.warning("Device lookup failed - device not found", context: [
                        "busID": busID, 
                        "deviceID": deviceID,
                        "totalDevicesFound": devices.count,
                        "availableDevices": devices.map { "\($0.busID):\($0.deviceID)" },
                        "operation": "getDevice",
                        "result": "nil"
                    ])
                    return nil
                }
            } catch let error as DeviceDiscoveryError {
                // Handle specific DeviceDiscoveryError types with detailed logging
                switch error {
                case .ioKitError(let code, let message):
                    logger.error("IOKit error during device lookup", context: [
                        "busID": busID,
                        "deviceID": deviceID,
                        "ioKitCode": code,
                        "ioKitMessage": message,
                        "operation": "getDevice",
                        "result": "nil"
                    ])
                case .failedToCreateMatchingDictionary:
                    logger.error("Failed to create IOKit matching dictionary during lookup", context: [
                        "busID": busID,
                        "deviceID": deviceID,
                        "operation": "getDevice",
                        "result": "nil"
                    ])
                case .failedToGetMatchingServices(let code):
                    logger.error("Failed to get matching services during lookup", context: [
                        "busID": busID,
                        "deviceID": deviceID,
                        "serviceCode": code,
                        "operation": "getDevice",
                        "result": "nil"
                    ])
                case .missingProperty(let property):
                    logger.error("Missing device property during lookup", context: [
                        "busID": busID,
                        "deviceID": deviceID,
                        "missingProperty": property,
                        "operation": "getDevice",
                        "result": "nil"
                    ])
                case .invalidPropertyType(let property):
                    logger.error("Invalid property type during lookup", context: [
                        "busID": busID,
                        "deviceID": deviceID,
                        "invalidProperty": property,
                        "operation": "getDevice",
                        "result": "nil"
                    ])
                case .accessDenied(let message):
                    logger.error("Access denied during device lookup", context: [
                        "busID": busID,
                        "deviceID": deviceID,
                        "accessMessage": message,
                        "operation": "getDevice",
                        "result": "nil"
                    ])
                default:
                    logger.error("Device discovery error during lookup", context: [
                        "busID": busID,
                        "deviceID": deviceID,
                        "error": error.localizedDescription,
                        "operation": "getDevice",
                        "result": "nil"
                    ])
                }
                return nil
            } catch {
                // Handle any other unexpected errors gracefully
                logger.error("Unexpected error during device lookup", context: [
                    "busID": busID,
                    "deviceID": deviceID,
                    "error": error.localizedDescription,
                    "errorType": String(describing: type(of: error)),
                    "operation": "getDevice",
                    "result": "nil"
                ])
                return nil
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Create USBDevice object from IOKit service
    /// Converts IOKit service to USBDevice with proper bus/device ID generation
    private func createUSBDeviceFromService(_ service: io_service_t) throws -> USBDevice {
        return try safeIOKitOperation("USB device creation") {
            // Extract device properties using the comprehensive property extraction method
            let properties = try extractDeviceProperties(from: service)
            
            // Generate bus and device IDs from IOKit locationID
            let busID = try getBusID(from: service)
            let deviceID = try getDeviceID(from: service)
            
            return USBDevice(
                busID: busID,
                deviceID: deviceID,
                vendorID: properties.vendorID,
                productID: properties.productID,
                deviceClass: properties.deviceClass,
                deviceSubClass: properties.deviceSubClass,
                deviceProtocol: properties.deviceProtocol,
                speed: properties.speed,
                manufacturerString: properties.manufacturerString,
                productString: properties.productString,
                serialNumberString: properties.serialNumberString
            )
        }
    }
    
    /// Extract comprehensive device properties from IOKit service
    /// Maps IOKit property keys to USBDevice struct fields with graceful error handling
    private func extractDeviceProperties(from service: io_service_t) throws -> DeviceProperties {
        return try safeIOKitOperation("device property extraction") {
            logger.debug("Starting device property extraction from IOKit service")
            
            // Extract required properties with detailed logging
            logger.debug("Extracting required device properties")
            let vendorID = try extractVendorID(from: service)
            let productID = try extractProductID(from: service)
            
            logger.debug("Extracting device class information")
            let deviceClass = extractDeviceClass(from: service)
            let deviceSubClass = extractDeviceSubClass(from: service)
            let deviceProtocol = extractDeviceProtocol(from: service)
            
            logger.debug("Extracting device speed information")
            let speed = extractUSBSpeed(from: service)
        
            // Extract optional string descriptors with detailed logging
            logger.debug("Extracting optional string descriptors")
            let manufacturerString = extractManufacturerString(from: service)
            let productString = extractProductString(from: service)
            let serialNumberString = extractSerialNumberString(from: service)
            
            // Log missing optional properties as warnings
            var missingProperties: [String] = []
            if manufacturerString == nil {
                missingProperties.append("manufacturer")
            }
            if productString == nil {
                missingProperties.append("product")
            }
            if serialNumberString == nil {
                missingProperties.append("serial")
            }
            
            if !missingProperties.isEmpty {
                logger.warning("Some optional device properties are missing", context: [
                    "vendorID": String(format: "0x%04x", vendorID),
                    "productID": String(format: "0x%04x", productID),
                    "missingProperties": missingProperties.joined(separator: ", "),
                    "impact": "Device identification may be limited"
                ])
            }
            
            logger.debug("Successfully extracted device properties", context: [
                "vendorID": String(format: "0x%04x", vendorID),
                "productID": String(format: "0x%04x", productID),
                "deviceClass": String(format: "0x%02x", deviceClass),
                "deviceSubClass": String(format: "0x%02x", deviceSubClass),
                "deviceProtocol": String(format: "0x%02x", deviceProtocol),
                "speed": speed.rawValue,
                "hasManufacturer": manufacturerString != nil,
                "hasProduct": productString != nil,
                "hasSerial": serialNumberString != nil,
                "manufacturerString": manufacturerString ?? "N/A",
                "productString": productString ?? "N/A"
            ])
        
            return DeviceProperties(
                vendorID: vendorID,
                productID: productID,
                deviceClass: deviceClass,
                deviceSubClass: deviceSubClass,
                deviceProtocol: deviceProtocol,
                speed: speed,
                manufacturerString: manufacturerString,
                productString: productString,
                serialNumberString: serialNumberString
            )
        }
    }
    
    // MARK: - Property Extraction Methods
    
    /// Extract vendor ID (VID) from IOKit properties
    private func extractVendorID(from service: io_service_t) throws -> UInt16 {
        logger.debug("Extracting vendor ID from device properties")
        do {
            let vendorID = try getUInt16Property(from: service, key: kUSBVendorID)
            logger.debug("Successfully extracted vendor ID", context: [
                "vendorID": String(format: "0x%04x", vendorID),
                "property": kUSBVendorID
            ])
            return vendorID
        } catch {
            logger.error("Failed to extract vendor ID - this is a critical property", context: [
                "error": error.localizedDescription,
                "property": kUSBVendorID,
                "impact": "Device cannot be properly identified"
            ])
            throw DeviceDiscoveryError.missingProperty(kUSBVendorID)
        }
    }
    
    /// Extract product ID (PID) from IOKit properties
    private func extractProductID(from service: io_service_t) throws -> UInt16 {
        logger.debug("Extracting product ID from device properties")
        do {
            let productID = try getUInt16Property(from: service, key: kUSBProductID)
            logger.debug("Successfully extracted product ID", context: [
                "productID": String(format: "0x%04x", productID),
                "property": kUSBProductID
            ])
            return productID
        } catch {
            logger.error("Failed to extract product ID - this is a critical property", context: [
                "error": error.localizedDescription,
                "property": kUSBProductID,
                "impact": "Device cannot be properly identified"
            ])
            throw DeviceDiscoveryError.missingProperty(kUSBProductID)
        }
    }
    
    /// Extract device class with graceful fallback to default value
    private func extractDeviceClass(from service: io_service_t) -> UInt8 {
        logger.debug("Extracting device class from properties")
        do {
            let deviceClass = try getUInt8Property(from: service, key: kUSBDeviceClass)
            logger.debug("Successfully extracted device class", context: [
                "deviceClass": String(format: "0x%02x", deviceClass),
                "property": kUSBDeviceClass,
                "classDescription": getUSBClassDescription(deviceClass)
            ])
            return deviceClass
        } catch {
            logger.warning("Failed to extract device class, using default", context: [
                "error": error.localizedDescription,
                "property": kUSBDeviceClass,
                "default": "0x00",
                "defaultDescription": "Unspecified class",
                "impact": "Device class information will be incomplete"
            ])
            return 0x00 // Default to unspecified class
        }
    }
    
    /// Extract device subclass with graceful fallback to default value
    private func extractDeviceSubClass(from service: io_service_t) -> UInt8 {
        logger.debug("Extracting device subclass from properties")
        do {
            let deviceSubClass = try getUInt8Property(from: service, key: kUSBDeviceSubClass)
            logger.debug("Successfully extracted device subclass", context: [
                "deviceSubClass": String(format: "0x%02x", deviceSubClass),
                "property": kUSBDeviceSubClass
            ])
            return deviceSubClass
        } catch {
            logger.warning("Failed to extract device subclass, using default", context: [
                "error": error.localizedDescription,
                "property": kUSBDeviceSubClass,
                "default": "0x00",
                "defaultDescription": "Unspecified subclass",
                "impact": "Device subclass information will be incomplete"
            ])
            return 0x00 // Default to unspecified subclass
        }
    }
    
    /// Extract device protocol with graceful fallback to default value
    private func extractDeviceProtocol(from service: io_service_t) -> UInt8 {
        logger.debug("Extracting device protocol from properties")
        do {
            let deviceProtocol = try getUInt8Property(from: service, key: kUSBDeviceProtocol)
            logger.debug("Successfully extracted device protocol", context: [
                "deviceProtocol": String(format: "0x%02x", deviceProtocol),
                "property": kUSBDeviceProtocol
            ])
            return deviceProtocol
        } catch {
            logger.warning("Failed to extract device protocol, using default", context: [
                "error": error.localizedDescription,
                "property": kUSBDeviceProtocol,
                "default": "0x00",
                "defaultDescription": "Unspecified protocol",
                "impact": "Device protocol information will be incomplete"
            ])
            return 0x00 // Default to unspecified protocol
        }
    }
    
    /// Extract USB speed with graceful fallback to unknown
    private func extractUSBSpeed(from service: io_service_t) -> USBSpeed {
        logger.debug("Extracting USB speed from device properties")
        
        // Try multiple possible property keys for speed information
        let speedKeys = ["Speed", "Device Speed"]
        
        for key in speedKeys {
            logger.debug("Attempting to extract speed from property", context: [
                "property": key
            ])
            
            if let speed = tryExtractSpeed(from: service, key: key) {
                logger.debug("Successfully extracted USB speed", context: [
                    "property": key,
                    "speed": speed.rawValue,
                    "speedDescription": getUSBSpeedDescription(speed)
                ])
                return speed
            } else {
                logger.debug("Speed property not found or invalid", context: [
                    "property": key
                ])
            }
        }
        
        logger.warning("Could not determine USB speed from any known property", context: [
            "attemptedProperties": speedKeys.joined(separator: ", "),
            "fallback": "unknown",
            "impact": "Speed information will be unavailable for this device"
        ])
        return .unknown
    }
    
    /// Try to extract speed from a specific property key
    private func tryExtractSpeed(from service: io_service_t, key: String) -> USBSpeed? {
        guard let property = ioKit.registryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        
        guard let number = property as? NSNumber else {
            return nil
        }
        
        let speedValue = number.uint8Value
        switch speedValue {
        case 0:
            return .low
        case 1:
            return .full
        case 2:
            return .high
        case 3:
            return .superSpeed
        default:
            return .unknown
        }
    }
    
    /// Extract manufacturer string descriptor with graceful handling
    private func extractManufacturerString(from service: io_service_t) -> String? {
        logger.debug("Extracting manufacturer string descriptor")
        
        // Try multiple possible property keys for manufacturer string
        let manufacturerKeys = ["USB Vendor Name", "Manufacturer"]
        
        for key in manufacturerKeys {
            logger.debug("Attempting to extract manufacturer from property", context: [
                "property": key
            ])
            
            if let manufacturer = getStringProperty(from: service, key: key) {
                logger.debug("Successfully found manufacturer string", context: [
                    "property": key,
                    "manufacturer": manufacturer,
                    "length": manufacturer.count
                ])
                return manufacturer
            }
        }
        
        logger.debug("No manufacturer string found in any property", context: [
            "attemptedProperties": manufacturerKeys.joined(separator: ", "),
            "result": "nil"
        ])
        return nil
    }
    
    /// Extract product string descriptor with graceful handling
    private func extractProductString(from service: io_service_t) -> String? {
        logger.debug("Extracting product string descriptor")
        
        // Try multiple possible property keys for product string
        let productKeys = ["USB Product Name", "Product"]
        
        for key in productKeys {
            logger.debug("Attempting to extract product from property", context: [
                "property": key
            ])
            
            if let product = getStringProperty(from: service, key: key) {
                logger.debug("Successfully found product string", context: [
                    "property": key,
                    "product": product,
                    "length": product.count
                ])
                return product
            }
        }
        
        logger.debug("No product string found in any property", context: [
            "attemptedProperties": productKeys.joined(separator: ", "),
            "result": "nil"
        ])
        return nil
    }
    
    /// Extract serial number string descriptor with graceful handling
    private func extractSerialNumberString(from service: io_service_t) -> String? {
        logger.debug("Extracting serial number string descriptor")
        
        // Try multiple possible property keys for serial number string
        let serialKeys = ["USB Serial Number", "Serial Number"]
        
        for key in serialKeys {
            logger.debug("Attempting to extract serial from property", context: [
                "property": key
            ])
            
            if let serial = getStringProperty(from: service, key: key) {
                logger.debug("Successfully found serial number string", context: [
                    "property": key,
                    "serial": serial,
                    "length": serial.count
                ])
                return serial
            }
        }
        
        logger.debug("No serial number string found in any property", context: [
            "attemptedProperties": serialKeys.joined(separator: ", "),
            "result": "nil"
        ])
        return nil
    }
    
    private func getUInt16Property(from service: io_service_t, key: String) throws -> UInt16 {
        logger.debug("Attempting to extract UInt16 property", context: [
            "property": key
        ])
        
        guard let property = ioKit.registryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            logger.warning("Missing required UInt16 property", context: [
                "property": key,
                "error_type": "missing_property",
                "impact": "Property extraction will fail"
            ])
            throw DeviceDiscoveryError.missingProperty(key)
        }
        
        guard let number = property as? NSNumber else {
            logger.warning("Invalid property type for UInt16 property", context: [
                "property": key,
                "actualType": String(describing: type(of: property)),
                "expectedType": "NSNumber",
                "error_type": "invalid_property_type",
                "impact": "Property extraction will fail"
            ])
            throw DeviceDiscoveryError.invalidPropertyType(key)
        }
        
        let value = number.uint16Value
        logger.debug("Successfully extracted UInt16 property", context: [
            "property": key,
            "value": String(format: "0x%04x", value)
        ])
        
        return value
    }
    
    private func getUInt8Property(from service: io_service_t, key: String) throws -> UInt8 {
        logger.debug("Attempting to extract UInt8 property", context: [
            "property": key
        ])
        
        guard let property = ioKit.registryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            logger.warning("Missing required UInt8 property", context: [
                "property": key,
                "error_type": "missing_property",
                "impact": "Property extraction will fail"
            ])
            throw DeviceDiscoveryError.missingProperty(key)
        }
        
        guard let number = property as? NSNumber else {
            logger.warning("Invalid property type for UInt8 property", context: [
                "property": key,
                "actualType": String(describing: type(of: property)),
                "expectedType": "NSNumber",
                "error_type": "invalid_property_type",
                "impact": "Property extraction will fail"
            ])
            throw DeviceDiscoveryError.invalidPropertyType(key)
        }
        
        let value = number.uint8Value
        logger.debug("Successfully extracted UInt8 property", context: [
            "property": key,
            "value": String(format: "0x%02x", value)
        ])
        
        return value
    }
    
    private func getStringProperty(from service: io_service_t, key: String) -> String? {
        logger.debug("Attempting to extract string property", context: [
            "property": key
        ])
        
        guard let property = ioKit.registryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            logger.debug("String property not found", context: [
                "property": key,
                "result": "nil"
            ])
            return nil
        }
        
        guard let stringValue = property as? String else {
            logger.warning("Property exists but is not a string", context: [
                "property": key,
                "actualType": String(describing: type(of: property)),
                "expectedType": "String",
                "result": "nil"
            ])
            return nil
        }
        
        logger.debug("Successfully extracted string property", context: [
            "property": key,
            "value": stringValue,
            "length": stringValue.count
        ])
        
        return stringValue
    }
    

    
    /// Generate bus ID from IOKit locationID
    /// Bus ID is extracted from the high 24 bits of locationID for USB/IP compatibility
    private func getBusID(from service: io_service_t) throws -> String {
        // Get the location ID which contains bus information
        let locationID = try getUInt32Property(from: service, key: "locationID")
        let busNumber = (locationID >> 24) & 0xFF
        return String(format: "%d", busNumber)
    }
    
    /// Generate device ID from IOKit locationID and USB Address
    /// Device ID is extracted from the low 8 bits of locationID or USB Address for USB/IP compatibility
    private func getDeviceID(from service: io_service_t) throws -> String {
        // Try to get the USB Address first (more reliable for device identification)
        if let address = getUInt8PropertyOptional(from: service, key: "USB Address") {
            return String(format: "%d", address)
        }
        
        // Fallback to extracting from locationID if USB Address is not available
        let locationID = try getUInt32Property(from: service, key: "locationID")
        let deviceAddress = locationID & 0xFF
        return String(format: "%d", deviceAddress)
    }
    
    private func getUInt32Property(from service: io_service_t, key: String) throws -> UInt32 {
        guard let property = ioKit.registryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            logger.warning("Missing required property", context: [
                "key": key,
                "error_type": "missing_property"
            ])
            throw DeviceDiscoveryError.missingProperty(key)
        }
        
        guard let number = property as? NSNumber else {
            logger.warning("Invalid property type", context: [
                "key": key,
                "property_type": String(describing: type(of: property)),
                "expected_type": "NSNumber",
                "error_type": "invalid_property_type"
            ])
            throw DeviceDiscoveryError.invalidPropertyType(key)
        }
        
        return number.uint32Value
    }
    
    private func getUInt32PropertyOptional(from service: io_service_t, key: String) -> UInt32? {
        guard let property = ioKit.registryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let number = property as? NSNumber else {
            return nil
        }
        
        return number.uint32Value
    }
    
    private func getUInt8PropertyOptional(from service: io_service_t, key: String) -> UInt8? {
        guard let property = ioKit.registryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let number = property as? NSNumber else {
            return nil
        }
        
        return number.uint8Value
    }
    
    // MARK: - USB Description Helpers
    
    /// Get human-readable description for USB device class
    private func getUSBClassDescription(_ deviceClass: UInt8) -> String {
        switch deviceClass {
        case 0x00:
            return "Use class information in the Interface Descriptors"
        case 0x01:
            return "Audio"
        case 0x02:
            return "Communications and CDC Control"
        case 0x03:
            return "HID (Human Interface Device)"
        case 0x05:
            return "Physical"
        case 0x06:
            return "Image"
        case 0x07:
            return "Printer"
        case 0x08:
            return "Mass Storage"
        case 0x09:
            return "Hub"
        case 0x0A:
            return "CDC-Data"
        case 0x0B:
            return "Smart Card"
        case 0x0D:
            return "Content Security"
        case 0x0E:
            return "Video"
        case 0x0F:
            return "Personal Healthcare"
        case 0x10:
            return "Audio/Video Devices"
        case 0x11:
            return "Billboard Device Class"
        case 0x12:
            return "USB Type-C Bridge Class"
        case 0xDC:
            return "Diagnostic Device"
        case 0xE0:
            return "Wireless Controller"
        case 0xEF:
            return "Miscellaneous"
        case 0xFE:
            return "Application Specific"
        case 0xFF:
            return "Vendor Specific"
        default:
            return "Unknown Class (\(String(format: "0x%02x", deviceClass)))"
        }
    }
    
    /// Get human-readable description for USB speed
    private func getUSBSpeedDescription(_ speed: USBSpeed) -> String {
        switch speed {
        case .low:
            return "Low Speed (1.5 Mbps)"
        case .full:
            return "Full Speed (12 Mbps)"
        case .high:
            return "High Speed (480 Mbps)"
        case .superSpeed:
            return "SuperSpeed (5 Gbps)"
        case .unknown:
            return "Unknown Speed"
        }
    }
    
    // MARK: - Notification System
    
    public func startNotifications() throws {
        try queue.sync {
            guard !isMonitoring else {
                logger.debug("Device notifications already started - skipping initialization")
                return // Already started
            }
            
            logger.info("Initializing USB device notification system")
            
            // Ensure clean state before starting
            ensureCleanNotificationState()
            
            logger.debug("Starting USB device notification setup")
            
            // Create notification port
            logger.debug("Creating IOKit notification port")
            notificationPort = ioKit.notificationPortCreate(kIOMasterPortDefault)
            guard let port = notificationPort else {
                let error = handleNotificationError(KERN_FAILURE, operation: "IONotificationPortCreate")
                logger.error("Failed to create IOKit notification port", context: [
                    "error": error.localizedDescription,
                    "impact": "Device monitoring will not be available"
                ])
                throw error
            }
            
            logger.debug("Successfully created IOKit notification port")
            
            // Set notification port dispatch queue
            IONotificationPortSetDispatchQueue(port, queue)
            logger.debug("Configured notification port with dispatch queue", context: [
                "queueLabel": queue.label
            ])
            
            // Set up device added notifications
            logger.debug("Setting up device connection notifications")
            guard let addedMatchingDict = ioKit.serviceMatching(kIOUSBDeviceClassName) else {
                let error = DeviceDiscoveryError.failedToCreateMatchingDictionary
                logger.error("Failed to create matching dictionary for device connection notifications")
                throw error
            }
            let addedResult = ioKit.serviceAddMatchingNotification(
                port,
                kIOFirstMatchNotification,
                addedMatchingDict,
                deviceAddedCallback,
                Unmanaged.passUnretained(self).toOpaque(),
                &addedIterator
            )
            
            guard addedResult == KERN_SUCCESS else {
                let error = handleNotificationError(addedResult, operation: "IOServiceAddMatchingNotification (device added)")
                logger.error("Failed to setup device connection notifications", context: [
                    "error": error.localizedDescription,
                    "kernReturn": addedResult
                ])
                throw error
            }
            
            logger.debug("Successfully setup device connection notifications", context: [
                "iterator": addedIterator
            ])
            
            // Set up device removed notifications
            logger.debug("Setting up device disconnection notifications")
            guard let removedMatchingDict = ioKit.serviceMatching(kIOUSBDeviceClassName) else {
                let error = DeviceDiscoveryError.failedToCreateMatchingDictionary
                logger.error("Failed to create matching dictionary for device disconnection notifications")
                throw error
            }
            let removedResult = ioKit.serviceAddMatchingNotification(
                port,
                kIOTerminatedNotification,
                removedMatchingDict,
                deviceRemovedCallback,
                Unmanaged.passUnretained(self).toOpaque(),
                &removedIterator
            )
            
            guard removedResult == KERN_SUCCESS else {
                let error = handleNotificationError(removedResult, operation: "IOServiceAddMatchingNotification (device removed)")
                logger.error("Failed to setup device disconnection notifications", context: [
                    "error": error.localizedDescription,
                    "kernReturn": removedResult
                ])
                throw error
            }
            
            logger.debug("Successfully setup device disconnection notifications", context: [
                "iterator": removedIterator
            ])
            
            logger.debug("Consuming initial device notifications to prime iterators")
            
            // Consume initial notifications
            consumeIterator(addedIterator, isAddedNotification: true)
            consumeIterator(removedIterator, isAddedNotification: false)
            
            isMonitoring = true
            logger.info("USB device notification system started successfully", context: [
                "addedIterator": addedIterator,
                "removedIterator": removedIterator,
                "isMonitoring": isMonitoring
            ])
        }
    }
    
    public func stopNotifications() {
        queue.sync {
            guard isMonitoring else {
                logger.debug("Device notifications already stopped - no cleanup needed")
                return
            }
            
            logger.info("Initiating USB device notification system shutdown")
            
            // Set monitoring flag to false first to prevent race conditions
            isMonitoring = false
            logger.debug("Set monitoring flag to false to prevent new notifications")
            
            // Clean up notification iterators first to stop new notifications
            logger.debug("Cleaning up notification iterators")
            cleanupNotificationIterators()
            
            // Destroy notification port after iterators are cleaned up
            logger.debug("Destroying notification port")
            cleanupNotificationPort()
            
            // Clear the device cache when stopping notifications
            logger.debug("Clearing device cache")
            cleanupDeviceCache()
            
            // Verify that cleanup was successful
            if verifyNotificationCleanup() {
                logger.info("USB device notification system stopped successfully")
            } else {
                logger.error("USB device notification system stopped but cleanup verification failed", context: [
                    "recommendation": "Check for resource leaks and restart application if needed"
                ])
            }
        }
    }
    
    /// Clean up notification iterators with proper resource management
    /// Ensures all iterator resources are properly released
    private func cleanupNotificationIterators() {
        logger.debug("Cleaning up notification iterators")
        
        // Clean up device added iterator
        if addedIterator != 0 {
            // Consume any remaining notifications before cleanup
            var service: io_service_t = ioKit.iteratorNext(addedIterator)
            while service != 0 {
                _ = ioKit.objectRelease(service)
                service = ioKit.iteratorNext(addedIterator)
            }
            
            // Release the iterator itself
            let result = ioKit.objectRelease(addedIterator)
            if result != KERN_SUCCESS {
                logger.warning("Failed to release device added iterator", context: [
                    "kern_return": result
                ])
            } else {
                logger.debug("Successfully released device added iterator")
            }
            addedIterator = 0
        }
        
        // Clean up device removed iterator
        if removedIterator != 0 {
            // Consume any remaining notifications before cleanup
            var service: io_service_t = ioKit.iteratorNext(removedIterator)
            while service != 0 {
                _ = ioKit.objectRelease(service)
                service = ioKit.iteratorNext(removedIterator)
            }
            
            // Release the iterator itself
            let result = ioKit.objectRelease(removedIterator)
            if result != KERN_SUCCESS {
                logger.warning("Failed to release device removed iterator", context: [
                    "kern_return": result
                ])
            } else {
                logger.debug("Successfully released device removed iterator")
            }
            removedIterator = 0
        }
        
        logger.debug("Notification iterator cleanup completed")
    }
    
    /// Clean up notification port with proper resource management
    /// Ensures the notification port is properly destroyed and nullified
    private func cleanupNotificationPort() {
        logger.debug("Cleaning up notification port")
        
        if let port = notificationPort {
            // Remove the dispatch queue from the notification port before destroying
            IONotificationPortSetDispatchQueue(port, nil)
            
            // Destroy the notification port
            ioKit.notificationPortDestroy(port)
            notificationPort = nil
            
            logger.debug("Successfully destroyed notification port")
        } else {
            logger.debug("Notification port was already nil")
        }
    }
    
    /// Clean up device cache with thread-safe state management
    /// Clears the connected devices cache and logs the cleanup
    private func cleanupDeviceCache() {
        logger.debug("Cleaning up device cache")
        
        let cachedDeviceCount = connectedDevices.count
        connectedDevices.removeAll()
        
        if cachedDeviceCount > 0 {
            logger.debug("Cleared device cache", context: [
                "deviceCount": cachedDeviceCount
            ])
        } else {
            logger.debug("Device cache was already empty")
        }
    }
    
    /// Ensure clean notification state before starting notifications
    /// Verifies that all notification resources are properly cleaned up
    private func ensureCleanNotificationState() {
        logger.debug("Ensuring clean notification state")
        
        // Check for any leftover notification port
        if notificationPort != nil {
            logger.warning("Found leftover notification port, cleaning up")
            cleanupNotificationPort()
        }
        
        // Check for any leftover iterators
        if addedIterator != 0 {
            logger.warning("Found leftover added iterator, cleaning up")
            _ = ioKit.objectRelease(addedIterator)
            addedIterator = 0
        }
        
        if removedIterator != 0 {
            logger.warning("Found leftover removed iterator, cleaning up")
            _ = ioKit.objectRelease(removedIterator)
            removedIterator = 0
        }
        
        // Clear device cache if it has stale data
        if !connectedDevices.isEmpty {
            logger.warning("Found stale device cache, clearing")
            connectedDevices.removeAll()
        }
        
        logger.debug("Notification state is clean")
    }
    
    /// Verify that notification resources are properly cleaned up
    /// Returns true if all resources are properly released
    private func verifyNotificationCleanup() -> Bool {
        let isClean = notificationPort == nil && 
                     addedIterator == 0 && 
                     removedIterator == 0 && 
                     !isMonitoring
        
        if isClean {
            logger.debug("Notification cleanup verification passed")
        } else {
            logger.warning("Notification cleanup verification failed", context: [
                "hasNotificationPort": notificationPort != nil,
                "hasAddedIterator": addedIterator != 0,
                "hasRemovedIterator": removedIterator != 0,
                "isMonitoring": isMonitoring
            ])
        }
        
        return isClean
    }
    
    // Changed from private to internal for callback access
    func consumeIterator(_ iterator: io_iterator_t, isAddedNotification: Bool) {
        let eventType = isAddedNotification ? "connection" : "disconnection"
        logger.debug("Starting to process \(eventType) notifications", context: [
            "iterator": iterator,
            "eventType": eventType
        ])
        
        var deviceCount = 0
        var processedSuccessfully = 0
        var processingErrors = 0
        var service: io_service_t = IOIteratorNext(iterator)
        
        while service != 0 {
            defer {
                _ = ioKit.objectRelease(service)
                service = ioKit.iteratorNext(iterator)
            }
            
            deviceCount += 1
            
            logger.debug("Processing device \(eventType) notification", context: [
                "deviceIndex": deviceCount,
                "service": service,
                "eventType": eventType
            ])
            
            do {
                if isAddedNotification {
                    try handleDeviceAddedNotification(service: service)
                } else {
                    handleDeviceRemovedNotification(service: service)
                }
                processedSuccessfully += 1
            } catch {
                logger.warning("Failed to process device \(eventType) notification", context: [
                    "deviceIndex": deviceCount,
                    "error": error.localizedDescription,
                    "eventType": eventType
                ])
                processingErrors += 1
            }
        }
        
        if deviceCount > 0 {
            logger.debug("Completed processing \(eventType) notifications", context: [
                "totalNotifications": deviceCount,
                "processedSuccessfully": processedSuccessfully,
                "processingErrors": processingErrors,
                "eventType": eventType
            ])
        } else {
            logger.debug("No \(eventType) notifications to process")
        }
    }
    
    // MARK: - Device Notification Handlers
    
    /// Handle device connection events
    /// Creates USBDevice from IOKit service and triggers onDeviceConnected callback
    private func handleDeviceAddedNotification(service: io_service_t) throws {
        logger.debug("Processing device connection notification", context: [
            "service": service
        ])
        
        do {
            let device = try createUSBDeviceFromService(service)
            let deviceKey = "\(device.busID):\(device.deviceID)"
            
            // Check if device is already in cache (duplicate notification)
            if connectedDevices[deviceKey] != nil {
                logger.debug("Device connection notification for already cached device", context: [
                    "deviceKey": deviceKey,
                    "action": "ignoring_duplicate"
                ])
                return
            }
            
            // Cache the device for proper disconnection handling
            connectedDevices[deviceKey] = device
            
            logger.info("USB device connected", context: [
                "event": "device_connected",
                "busID": device.busID,
                "deviceID": device.deviceID,
                "deviceKey": deviceKey,
                "vendorID": String(format: "0x%04x", device.vendorID),
                "productID": String(format: "0x%04x", device.productID),
                "deviceClass": String(format: "0x%02x", device.deviceClass),
                "deviceClassDescription": getUSBClassDescription(device.deviceClass),
                "speed": device.speed.rawValue,
                "speedDescription": getUSBSpeedDescription(device.speed),
                "product": device.productString ?? "Unknown",
                "manufacturer": device.manufacturerString ?? "Unknown",
                "serial": device.serialNumberString ?? "None",
                "cachedDeviceCount": connectedDevices.count
            ])
            
            // Trigger the connection callback with complete device information
            logger.debug("Triggering device connection callback")
            onDeviceConnected?(device)
            
        } catch let error as DeviceDiscoveryError {
            logger.error("Failed to process device connection due to discovery error", context: [
                "service": service,
                "error": error.localizedDescription,
                "errorType": "DeviceDiscoveryError",
                "impact": "Device will not be available for use"
            ])
            throw error
        } catch {
            logger.error("Failed to process device connection due to unexpected error", context: [
                "service": service,
                "error": error.localizedDescription,
                "errorType": String(describing: type(of: error)),
                "impact": "Device will not be available for use"
            ])
            throw error
        }
    }
    
    /// Handle device disconnection events
    /// Attempts to provide complete device information using cached data
    private func handleDeviceRemovedNotification(service: io_service_t) {
        logger.debug("Processing device disconnection notification", context: [
            "service": service
        ])
        
        // Try to extract device identification from the terminating service
        guard let deviceKey = extractDeviceKey(from: service) else {
            logger.warning("Could not extract device identification from disconnected device", context: [
                "service": service,
                "impact": "Device disconnection event may be lost"
            ])
            return
        }
        
        logger.debug("Extracted device key from disconnection notification", context: [
            "deviceKey": deviceKey
        ])
        
        // Look up the cached device information
        if let cachedDevice = connectedDevices.removeValue(forKey: deviceKey) {
            logger.info("USB device disconnected", context: [
                "event": "device_disconnected",
                "busID": cachedDevice.busID,
                "deviceID": cachedDevice.deviceID,
                "deviceKey": deviceKey,
                "vendorID": String(format: "0x%04x", cachedDevice.vendorID),
                "productID": String(format: "0x%04x", cachedDevice.productID),
                "deviceClass": String(format: "0x%02x", cachedDevice.deviceClass),
                "deviceClassDescription": getUSBClassDescription(cachedDevice.deviceClass),
                "speed": cachedDevice.speed.rawValue,
                "speedDescription": getUSBSpeedDescription(cachedDevice.speed),
                "product": cachedDevice.productString ?? "Unknown",
                "manufacturer": cachedDevice.manufacturerString ?? "Unknown",
                "serial": cachedDevice.serialNumberString ?? "None",
                "remainingCachedDevices": connectedDevices.count
            ])
            
            // Trigger the disconnection callback with complete device information
            logger.debug("Triggering device disconnection callback with cached device info")
            onDeviceDisconnected?(cachedDevice)
            
        } else {
            logger.warning("Device disconnected but not found in cache", context: [
                "deviceKey": deviceKey,
                "cachedDeviceCount": connectedDevices.count,
                "cachedDeviceKeys": Array(connectedDevices.keys),
                "possibleCause": "Device was connected before monitoring started or cache was cleared"
            ])
            
            // Create minimal device information from available data
            let components = deviceKey.split(separator: ":")
            if components.count == 2 {
                let busID = String(components[0])
                let deviceID = String(components[1])
                
                let minimalDevice = USBDevice(
                    busID: busID,
                    deviceID: deviceID,
                    vendorID: 0,
                    productID: 0,
                    deviceClass: 0,
                    deviceSubClass: 0,
                    deviceProtocol: 0,
                    speed: .unknown,
                    manufacturerString: nil,
                    productString: nil,
                    serialNumberString: nil
                )
                
                logger.info("USB device disconnected (minimal info only)", context: [
                    "event": "device_disconnected_minimal",
                    "busID": busID,
                    "deviceID": deviceID,
                    "deviceKey": deviceKey,
                    "dataAvailable": "minimal",
                    "reason": "Device not found in cache"
                ])
                
                logger.debug("Triggering device disconnection callback with minimal device info")
                onDeviceDisconnected?(minimalDevice)
            } else {
                logger.error("Invalid device key format for disconnected device", context: [
                    "deviceKey": deviceKey,
                    "expectedFormat": "busID:deviceID",
                    "impact": "Disconnection callback will not be triggered"
                ])
            }
        }
    }
    
    /// Extract device key (busID:deviceID) from IOKit service for cache lookup
    private func extractDeviceKey(from service: io_service_t) -> String? {
        logger.debug("Extracting device key from IOKit service for cache lookup")
        
        // Try to extract locationID and derive bus/device IDs
        guard let locationID = getUInt32PropertyOptional(from: service, key: "locationID") else {
            logger.debug("Could not get locationID from device service", context: [
                "service": service,
                "property": "locationID",
                "result": "nil"
            ])
            return nil
        }
        
        logger.debug("Successfully extracted locationID", context: [
            "locationID": String(format: "0x%08x", locationID)
        ])
        
        let busNumber = (locationID >> 24) & 0xFF
        let busID = String(format: "%d", busNumber)
        
        logger.debug("Derived bus ID from locationID", context: [
            "busNumber": String(format: "0x%02x", busNumber),
            "busID": busID
        ])
        
        // Try to get USB Address first (more reliable)
        if let address = getUInt8PropertyOptional(from: service, key: "USB Address") {
            let deviceID = String(format: "%d", address)
            let deviceKey = "\(busID):\(deviceID)"
            
            logger.debug("Successfully extracted device key using USB Address", context: [
                "usbAddress": String(format: "0x%02x", address),
                "deviceID": deviceID,
                "deviceKey": deviceKey,
                "method": "USB Address"
            ])
            
            return deviceKey
        }
        
        logger.debug("USB Address not available, falling back to locationID extraction")
        
        // Fallback to extracting from locationID
        let deviceAddress = locationID & 0xFF
        let deviceID = String(format: "%d", deviceAddress)
        let deviceKey = "\(busID):\(deviceID)"
        
        logger.debug("Successfully extracted device key using locationID fallback", context: [
            "deviceAddress": String(format: "0x%02x", deviceAddress),
            "deviceID": deviceID,
            "deviceKey": deviceKey,
            "method": "locationID fallback"
        ])
        
        return deviceKey
    }
}

// MARK: - C Callbacks

/// IOKit callback function for device connection events
/// Called when a USB device is connected to the system
private func deviceAddedCallback(
    refcon: UnsafeMutableRawPointer?,
    iterator: io_iterator_t
) {
    guard let refcon = refcon else { 
        print("ERROR: deviceAddedCallback called with nil refcon")
        return 
    }
    
    let discovery = Unmanaged<IOKitDeviceDiscovery>.fromOpaque(refcon).takeUnretainedValue()
    discovery.consumeIterator(iterator, isAddedNotification: true)
}

/// IOKit callback function for device disconnection events
/// Called when a USB device is disconnected from the system
private func deviceRemovedCallback(
    refcon: UnsafeMutableRawPointer?,
    iterator: io_iterator_t
) {
    guard let refcon = refcon else { 
        print("ERROR: deviceRemovedCallback called with nil refcon")
        return 
    }
    
    let discovery = Unmanaged<IOKitDeviceDiscovery>.fromOpaque(refcon).takeUnretainedValue()
    discovery.consumeIterator(iterator, isAddedNotification: false)
}

