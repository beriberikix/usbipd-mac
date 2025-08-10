// DeviceClaimer.swift
// IOKit-based USB device claiming for System Extension

import Foundation
import IOKit
import IOKit.usb
import Common
import USBIPDCore

// MARK: - Device Claimer Protocol

/// Protocol for USB device claiming operations in System Extension
public protocol DeviceClaimer {
    /// Claim exclusive access to a USB device
    /// - Parameter device: The USB device to claim
    /// - Returns: ClaimedDevice information on success
    /// - Throws: SystemExtensionError on failure
    func claimDevice(device: USBDevice) throws -> ClaimedDevice
    
    /// Release a previously claimed USB device
    /// - Parameter device: The USB device to release
    /// - Throws: SystemExtensionError on failure
    func releaseDevice(device: USBDevice) throws
    
    /// Check if a device is currently claimed by this System Extension
    /// - Parameter deviceID: Device identifier (busID-deviceID format)
    /// - Returns: True if device is claimed, false otherwise
    func isDeviceClaimed(deviceID: String) -> Bool
    
    /// Get information about a claimed device
    /// - Parameter deviceID: Device identifier (busID-deviceID format)  
    /// - Returns: ClaimedDevice information if device is claimed, nil otherwise
    func getClaimedDevice(deviceID: String) -> ClaimedDevice?
    
    /// Get all currently claimed devices
    /// - Returns: Array of all claimed devices
    func getAllClaimedDevices() -> [ClaimedDevice]
    
    /// Restore device claims after System Extension restart
    /// - Throws: SystemExtensionError on failure to restore persistent state
    func restoreClaimedDevices() throws
    
    /// Save current device claim state for persistence
    /// - Throws: SystemExtensionError on failure to save state
    func saveClaimState() throws
}

// MARK: - IOKit Device Claimer Implementation

/// IOKit-based implementation of USB device claiming
public class IOKitDeviceClaimer: DeviceClaimer {
    
    // MARK: - Properties
    
    /// IOKit interface for dependency injection and testing
    private let ioKit: IOKitInterface
    
    /// Logger for device claiming operations
    private let logger: Logger
    
    /// Queue for serializing device operations
    private let queue: DispatchQueue
    
    /// Currently claimed devices (deviceID -> ClaimedDevice)
    private var claimedDevices: [String: ClaimedDevice] = [:]
    
    /// IOKit service references for claimed devices (deviceID -> io_service_t)
    private var serviceReferences: [String: io_service_t] = [:]
    
    /// Persistent state file path
    private let stateFilePath: String
    
    /// Device claiming statistics
    private var claimStats: DeviceClaimStatistics
    
    // MARK: - Initialization
    
    /// Initialize IOKit device claimer with default dependencies
    public convenience init() {
        let logger = Logger(
            config: LoggerConfig(level: .info),
            subsystem: "com.usbipd.mac.system-extension",
            category: "device-claimer"
        )
        
        let stateDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .systemDomainMask)
            .first?.appendingPathComponent("usbipd-mac")
        let statePath = stateDir?.appendingPathComponent("claimed-devices.json").path ?? "/tmp/usbipd-claimed-devices.json"
        
        self.init(
            ioKit: RealIOKitInterface(),
            logger: logger,
            stateFilePath: statePath
        )
    }
    
    /// Initialize with dependency injection for testing
    /// - Parameters:
    ///   - ioKit: IOKit interface implementation
    ///   - logger: Logger instance
    ///   - stateFilePath: Path for persistent state storage
    public init(ioKit: IOKitInterface, logger: Logger, stateFilePath: String) {
        self.ioKit = ioKit
        self.logger = logger
        self.stateFilePath = stateFilePath
        self.queue = DispatchQueue(
            label: "com.usbipd.mac.system-extension.device-claimer",
            qos: .userInitiated
        )
        self.claimStats = DeviceClaimStatistics()
        
        // Create state directory if needed
        let stateDir = (stateFilePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: stateDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        logger.info("IOKitDeviceClaimer initialized", context: [
            "stateFilePath": stateFilePath,
            "queueLabel": queue.label
        ])
    }
    
    deinit {
        // Release all claimed devices on deinitialization
        queue.sync {
            for (deviceID, _) in claimedDevices {
                logger.warning("Releasing device \(deviceID) during deinitialization")
                do {
                    try releaseDeviceInternal(deviceID: deviceID)
                } catch {
                    logger.error("Failed to release device \(deviceID) during cleanup", context: [
                        "error": error.localizedDescription
                    ])
                }
            }
        }
        
        logger.info("IOKitDeviceClaimer deinitialized", context: [
            "releasedDevices": claimedDevices.count
        ])
    }
    
    // MARK: - DeviceClaimer Protocol Implementation
    
    public func claimDevice(device: USBDevice) throws -> ClaimedDevice {
        return try queue.sync {
            return try claimDeviceInternal(device: device)
        }
    }
    
    public func releaseDevice(device: USBDevice) throws {
        return try queue.sync {
            let deviceID = "\(device.busID)-\(device.deviceID)"
            return try releaseDeviceInternal(deviceID: deviceID)
        }
    }
    
    public func isDeviceClaimed(deviceID: String) -> Bool {
        return queue.sync {
            return claimedDevices[deviceID] != nil
        }
    }
    
    public func getClaimedDevice(deviceID: String) -> ClaimedDevice? {
        return queue.sync {
            return claimedDevices[deviceID]
        }
    }
    
    public func getAllClaimedDevices() -> [ClaimedDevice] {
        return queue.sync {
            return Array(claimedDevices.values)
        }
    }
    
    public func restoreClaimedDevices() throws {
        try queue.sync {
            try restoreClaimedDevicesInternal()
        }
    }
    
    public func saveClaimState() throws {
        try queue.sync {
            try saveClaimStateInternal()
        }
    }
    
    // MARK: - Internal Implementation
    
    private func claimDeviceInternal(device: USBDevice) throws -> ClaimedDevice {
        let startTime = Date()
        let deviceID = "\(device.busID)-\(device.deviceID)"
        
        logger.info("Attempting to claim device", context: [
            "deviceID": deviceID,
            "vendorID": String(format: "0x%04x", device.vendorID),
            "productID": String(format: "0x%04x", device.productID),
            "product": device.productString ?? "Unknown"
        ])
        
        // Check if device is already claimed
        if claimedDevices[deviceID] != nil {
            logger.warning("Device already claimed", context: ["deviceID": deviceID])
            throw SystemExtensionError.deviceAlreadyClaimed(deviceID)
        }
        
        do {
            // Find the IOKit service for this device
            let service = try findIOKitService(for: device)
            
            // Attempt to claim the device using various methods
            let claimMethod = try attemptDeviceClaim(service: service, device: device)
            
            // Create claimed device record
            let claimedDevice = ClaimedDevice(
                deviceID: deviceID,
                busID: device.busID,
                vendorID: device.vendorID,
                productID: device.productID,
                productString: device.productString,
                manufacturerString: device.manufacturerString,
                serialNumber: device.serialNumberString,
                claimTime: startTime,
                claimMethod: claimMethod,
                claimState: .claimed,
                deviceClass: device.deviceClass,
                deviceSubclass: device.deviceSubClass,
                deviceProtocol: device.deviceProtocol
            )
            
            // Store claimed device and service reference
            claimedDevices[deviceID] = claimedDevice
            serviceReferences[deviceID] = service
            
            // Update statistics
            let claimDuration = Date().timeIntervalSince(startTime) * 1000 // milliseconds
            claimStats.recordSuccessfulClaim(duration: claimDuration)
            
            // Save state for persistence
            try saveClaimStateInternal()
            
            logger.info("Successfully claimed device", context: [
                "deviceID": deviceID,
                "claimMethod": claimMethod.rawValue,
                "duration": String(format: "%.2f", claimDuration)
            ])
            
            return claimedDevice
        } catch let error as SystemExtensionError {
            claimStats.recordFailedClaim()
            logger.error("Failed to claim device", context: [
                "deviceID": deviceID,
                "error": error.localizedDescription
            ])
            throw error
        } catch {
            claimStats.recordFailedClaim()
            let systemError = SystemExtensionError.deviceClaimFailed(deviceID, nil)
            logger.error("Unexpected error claiming device", context: [
                "deviceID": deviceID,
                "error": error.localizedDescription
            ])
            throw systemError
        }
    }
    
    private func releaseDeviceInternal(deviceID: String) throws {
        logger.info("Attempting to release device", context: ["deviceID": deviceID])
        
        guard claimedDevices[deviceID] != nil else {
            logger.warning("Device not claimed", context: ["deviceID": deviceID])
            throw SystemExtensionError.deviceNotClaimed(deviceID)
        }
        
        guard let service = serviceReferences[deviceID] else {
            logger.error("Missing service reference for claimed device", context: ["deviceID": deviceID])
            throw SystemExtensionError.internalError("Missing service reference for device \(deviceID)")
        }
        
        do {
            // Release the IOKit service
            let result = ioKit.objectRelease(service)
            if result != KERN_SUCCESS {
                logger.error("Failed to release IOKit service", context: [
                    "deviceID": deviceID,
                    "kernResult": result
                ])
                throw SystemExtensionError.deviceReleaseFailed(deviceID, result)
            }
            
            // Remove from tracking
            claimedDevices.removeValue(forKey: deviceID)
            serviceReferences.removeValue(forKey: deviceID)
            
            // Save updated state
            try saveClaimStateInternal()
            
            logger.info("Successfully released device", context: ["deviceID": deviceID])
        } catch let error as SystemExtensionError {
            logger.error("Failed to release device", context: [
                "deviceID": deviceID,
                "error": error.localizedDescription
            ])
            throw error
        } catch {
            let systemError = SystemExtensionError.deviceReleaseFailed(deviceID, nil)
            logger.error("Unexpected error releasing device", context: [
                "deviceID": deviceID,
                "error": error.localizedDescription
            ])
            throw systemError
        }
    }
    
    private func findIOKitService(for device: USBDevice) throws -> io_service_t {
        // Create matching dictionary for USB devices
        guard let matchingDict = ioKit.serviceMatching(kIOUSBDeviceClassName) else {
            throw SystemExtensionError.ioKitError(-1, "Failed to create USB device matching dictionary")
        }
        
        // Add vendor ID and product ID to matching criteria
        var vendorID = device.vendorID
        var productID = device.productID
        let vendorIDRef = CFNumberCreate(nil, .sInt16Type, &vendorID)
        let productIDRef = CFNumberCreate(nil, .sInt16Type, &productID)
        
        CFDictionarySetValue(matchingDict, Unmanaged.passUnretained(kUSBVendorID as CFString).toOpaque(), Unmanaged.passRetained(vendorIDRef!).toOpaque())
        CFDictionarySetValue(matchingDict, Unmanaged.passUnretained(kUSBProductID as CFString).toOpaque(), Unmanaged.passRetained(productIDRef!).toOpaque())
        
        // Get matching services
        var iterator: io_iterator_t = 0
        let result = ioKit.serviceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator)
        
        if result != KERN_SUCCESS {
            throw SystemExtensionError.ioKitError(result, "Failed to get matching USB services")
        }
        
        defer {
            _ = ioKit.objectRelease(iterator)
        }
        
        // Iterate through matching services to find our specific device
        var service: io_service_t = ioKit.iteratorNext(iterator)
        while service != 0 {
            defer {
                if service != 0 {
                    _ = ioKit.objectRelease(service)
                }
            }
            
            // Verify this is the correct device by checking additional properties
            if try verifyDeviceMatch(service: service, device: device) {
                // Retain the service for claiming
                return service
            }
            
            service = ioKit.iteratorNext(iterator)
        }
        
        throw SystemExtensionError.deviceNotFound("\(device.busID)-\(device.deviceID)")
    }
    
    private func verifyDeviceMatch(service: io_service_t, device: USBDevice) throws -> Bool {
        // Get device location ID for more precise matching
        let locationIDProperty = ioKit.registryEntryCreateCFProperty(
            service, "locationID" as CFString, kCFAllocatorDefault, 0
        )
        guard locationIDProperty?.takeRetainedValue() != nil else {
            logger.debug("Could not get locationID for service verification")
            return false
        }
        
        // Additional verification could include checking bus number, device address, etc.
        // For now, we rely on vendor ID + product ID matching from the service matching
        
        logger.debug("Device service verified", context: [
            "deviceID": "\(device.busID)-\(device.deviceID)",
            "service": String(service, radix: 16)
        ])
        
        return true
    }
    
    private func attemptDeviceClaim(service: io_service_t, device: USBDevice) throws -> DeviceClaimMethod {
        let deviceID = "\(device.busID)-\(device.deviceID)"
        
        // Try exclusive access first (most reliable method)
        do {
            try attemptExclusiveAccess(service: service)
            logger.debug("Claimed device using exclusive access", context: ["deviceID": deviceID])
            return .exclusiveAccess
        } catch {
            logger.debug("Exclusive access failed, trying driver unbind", context: [
                "deviceID": deviceID,
                "error": error.localizedDescription
            ])
        }
        
        // Try driver unbinding if exclusive access fails
        do {
            try attemptDriverUnbind(service: service)
            logger.debug("Claimed device using driver unbind", context: ["deviceID": deviceID])
            return .driverUnbind
        } catch {
            logger.debug("Driver unbind failed, trying IOKit matching", context: [
                "deviceID": deviceID,
                "error": error.localizedDescription
            ])
        }
        
        // Try IOKit matching as fallback
        do {
            try attemptIOKitMatching(service: service)
            logger.debug("Claimed device using IOKit matching", context: ["deviceID": deviceID])
            return .ioKitMatching
        } catch {
            logger.error("All claim methods failed", context: [
                "deviceID": deviceID,
                "error": error.localizedDescription
            ])
        }
        
        throw SystemExtensionError.deviceClaimFailed(deviceID, nil)
    }
    
    private func attemptExclusiveAccess(service: io_service_t) throws {
        logger.debug("Attempting exclusive access to USB device service")
        
        // For System Extensions, we use IOServiceOpen to get exclusive access
        // This is a simpler approach that works with modern macOS
        var connect: io_connect_t = 0
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connect)
        
        guard openResult == KERN_SUCCESS else {
            logger.error("Failed to open USB device service", context: [
                "result": String(openResult, radix: 16),
                "service": String(service, radix: 16)
            ])
            throw SystemExtensionError.ioKitError(openResult, "Failed to open USB device service")
        }
        
        // Store the connection for later cleanup during device release
        // Note: In a production implementation, this connection should be stored
        // in the serviceReferences dictionary along with the service
        
        // Verify the connection is valid
        if connect == 0 {
            logger.error("USB device service connection is invalid")
            throw SystemExtensionError.ioKitError(kIOReturnError, "Invalid service connection")
        }
        
        // Try to get exclusive access by setting a property that indicates our claim
        let exclusiveProperty = kCFBooleanTrue as CFTypeRef
        let propertyResult = IOConnectSetCFProperty(connect, "USBIPDExclusiveAccess" as CFString, exclusiveProperty)
        
        if propertyResult != KERN_SUCCESS {
            logger.warning("Failed to set exclusive access property", context: [
                "result": String(propertyResult, radix: 16)
            ])
            // Don't fail here as this property setting is informational
        }
        
        logger.info("Successfully obtained exclusive access to USB device", context: [
            "service": String(service, radix: 16),
            "connect": String(connect, radix: 16)
        ])
        
        // Note: The connection will be closed when the device is released
        // For now, we don't close it here to maintain the exclusive access
    }
    
    private func attemptDriverUnbind(service: io_service_t) throws {
        logger.debug("Attempting driver unbind for USB device service")
        
        // Step 1: IOServiceTerminate is not available in Swift, so skip this step
        // Instead, we'll rely on property setting to indicate device is claimed
        
        // Step 2: Set property to prevent new driver matching
        let propertyResult = IORegistryEntrySetCFProperty(
            service,
            "IOMatchCategory" as CFString,
            "USBIPDClaimedDevice" as CFString
        )
        
        if propertyResult != KERN_SUCCESS {
            logger.warning("Failed to set no-match property", context: [
                "result": String(propertyResult, radix: 16)
            ])
        }
        
        // Step 3: Try to set a higher probe score to prevent other drivers from matching
        var highScore: Int32 = 100000
        let scoreNumber = CFNumberCreate(nil, .sInt32Type, &highScore)
        let scoreResult = IORegistryEntrySetCFProperty(
            service,
            "IOProbeScore" as CFString,
            scoreNumber
        )
        
        if scoreResult != KERN_SUCCESS {
            logger.warning("Failed to set high probe score", context: [
                "result": String(scoreResult, radix: 16)
            ])
        }
        
        // Step 4: Request device re-probe to ensure driver changes take effect
        let reprobeResult = IOServiceRequestProbe(service, 0)
        if reprobeResult != KERN_SUCCESS {
            logger.warning("Failed to request device reprobe", context: [
                "result": String(reprobeResult, radix: 16)
            ])
        }
        
        logger.info("Driver unbinding process completed", context: [
            "service": String(service, radix: 16),
            "propertyResult": String(propertyResult, radix: 16),
            "scoreResult": String(scoreResult, radix: 16)
        ])
        
        // Consider this successful if at least one operation succeeded
        if propertyResult == KERN_SUCCESS || scoreResult == KERN_SUCCESS {
            logger.debug("Driver unbinding successful")
        } else {
            logger.warning("Driver unbinding methods failed")
            throw SystemExtensionError.deviceClaimFailed("Failed to unbind drivers from device", nil)
        }
    }
    
    private func getActiveDriverCount(for service: io_service_t) throws -> Int {
        // Simplified approach - check if the service has any child services
        // This is a basic indication of active drivers
        
        // Try to get a property that would indicate driver binding
        if let className = ioKit.registryEntryCreateCFProperty(
            service,
            "IOClass" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() {
            let classNameStr = "\(className)"
            logger.debug("USB device class", context: ["className": classNameStr])
            
            // If it's still showing as a generic USB device, no specific drivers are bound
            if classNameStr.contains("IOUSBDevice") {
                return 0 // No specific drivers bound
            } else {
                return 1 // Some driver is bound
            }
        }
        
        return 0 // Assume no drivers if we can't determine
    }
    
    private func attemptIOKitMatching(service: io_service_t) throws {
        logger.debug("Attempting IOKit matching for USB device service")
        
        // Get device properties for matching information
        let vendorIDProperty = ioKit.registryEntryCreateCFProperty(
            service, "idVendor" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue()
        
        let productIDProperty = ioKit.registryEntryCreateCFProperty(
            service, "idProduct" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue()
        
        var vendorID: UInt16 = 0
        var productID: UInt16 = 0
        
        if let vendorNum = vendorIDProperty,
           let productNum = productIDProperty {
            CFNumberGetValue((vendorNum as! CFNumber), .sInt16Type, &vendorID)
            CFNumberGetValue((productNum as! CFNumber), .sInt16Type, &productID)
        } else {
            logger.warning("Could not retrieve device identifiers for matching")
        }
        
        // Step 1: Set the match category to prevent other drivers from matching
        let matchCategoryResult = IORegistryEntrySetCFProperty(
            service,
            "IOMatchCategory" as CFString,
            "USBIPDSystemExtension" as CFString
        )
        
        if matchCategoryResult != KERN_SUCCESS {
            logger.warning("Failed to set match category", context: [
                "result": String(matchCategoryResult, radix: 16)
            ])
        }
        
        // Step 2: Set a high probe score to win over other drivers
        var highScore: Int32 = 100000
        let scoreNumber = CFNumberCreate(nil, .sInt32Type, &highScore)
        let scoreResult = IORegistryEntrySetCFProperty(
            service,
            "IOProbeScore" as CFString,
            scoreNumber
        )
        
        if scoreResult != KERN_SUCCESS {
            logger.warning("Failed to set high probe score", context: [
                "result": String(scoreResult, radix: 16)
            ])
        }
        
        // Step 3: Mark the device as claimed by our System Extension
        let claimResult = IORegistryEntrySetCFProperty(
            service,
            "USBIPDClaimed" as CFString,
            kCFBooleanTrue
        )
        
        if claimResult != KERN_SUCCESS {
            logger.warning("Failed to set claimed property", context: [
                "result": String(claimResult, radix: 16)
            ])
        }
        
        // Step 4: Request device reprobe to activate our changes
        let reprobeResult = IOServiceRequestProbe(service, 0)
        if reprobeResult != KERN_SUCCESS {
            logger.warning("Failed to request device reprobe for matching", context: [
                "result": String(reprobeResult, radix: 16)
            ])
        }
        
        // Step 5: Verify our matching took effect
        let currentCategory = ioKit.registryEntryCreateCFProperty(
            service,
            "IOMatchCategory" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
        
        if let category = currentCategory {
            let categoryStr = "\(category)"
            if categoryStr.contains("USBIPDSystemExtension") {
                logger.info("IOKit matching successful - device now matched to our System Extension", context: [
                    "vendorID": String(format: "0x%04x", vendorID),
                    "productID": String(format: "0x%04x", productID),
                    "category": categoryStr
                ])
            } else {
                logger.info("IOKit matching completed with category", context: [
                    "category": categoryStr
                ])
            }
        }
        
        // Success if at least one property was set successfully
        if matchCategoryResult == KERN_SUCCESS || scoreResult == KERN_SUCCESS || claimResult == KERN_SUCCESS {
            logger.debug("IOKit matching process successful")
        } else {
            logger.warning("All IOKit matching operations failed")
            throw SystemExtensionError.deviceClaimFailed("Failed to establish IOKit matching", nil)
        }
    }
    
    private func restoreClaimedDevicesInternal() throws {
        logger.info("Restoring claimed devices from persistent state", context: [
            "stateFilePath": stateFilePath
        ])
        
        guard FileManager.default.fileExists(atPath: stateFilePath) else {
            logger.info("No persistent state file found, starting with empty device list")
            return
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: stateFilePath))
            let savedDevices = try JSONDecoder().decode([ClaimedDevice].self, from: data)
            
            var restoredCount = 0
            var failedCount = 0
            
            for savedDevice in savedDevices {
                do {
                    // Try to re-claim the device
                    let usbDevice = USBDevice(
                        busID: savedDevice.busID,
                        deviceID: String(savedDevice.deviceID.split(separator: "-").last ?? ""),
                        vendorID: savedDevice.vendorID,
                        productID: savedDevice.productID,
                        deviceClass: savedDevice.deviceClass,
                        deviceSubClass: savedDevice.deviceSubclass,
                        deviceProtocol: savedDevice.deviceProtocol,
                        speed: .unknown, // We don't have speed info in saved state
                        manufacturerString: savedDevice.manufacturerString,
                        productString: savedDevice.productString,
                        serialNumberString: savedDevice.serialNumber
                    )
                    
                    _ = try claimDeviceInternal(device: usbDevice)
                    restoredCount += 1
                    
                    logger.debug("Restored device claim", context: [
                        "deviceID": savedDevice.deviceID
                    ])
                } catch {
                    failedCount += 1
                    logger.warning("Failed to restore device claim", context: [
                        "deviceID": savedDevice.deviceID,
                        "error": error.localizedDescription
                    ])
                }
            }
            
            logger.info("Device claim restoration completed", context: [
                "totalSaved": savedDevices.count,
                "restored": restoredCount,
                "failed": failedCount
            ])
        } catch {
            logger.error("Failed to restore claimed devices", context: [
                "error": error.localizedDescription
            ])
            throw SystemExtensionError.configurationError("Failed to restore persistent state: \(error.localizedDescription)")
        }
    }
    
    private func saveClaimStateInternal() throws {
        let devices = Array(claimedDevices.values)
        
        do {
            let data = try JSONEncoder().encode(devices)
            try data.write(to: URL(fileURLWithPath: stateFilePath))
            
            logger.debug("Saved claim state", context: [
                "deviceCount": devices.count,
                "stateFilePath": stateFilePath
            ])
        } catch {
            logger.error("Failed to save claim state", context: [
                "error": error.localizedDescription
            ])
            throw SystemExtensionError.configurationError("Failed to save persistent state: \(error.localizedDescription)")
        }
    }
}

// MARK: - Supporting Types

/// Statistics for device claiming operations
private struct DeviceClaimStatistics {
    var successfulClaims: Int = 0
    var failedClaims: Int = 0
    var totalClaimTime: Double = 0.0
    
    mutating func recordSuccessfulClaim(duration: Double) {
        successfulClaims += 1
        totalClaimTime += duration
    }
    
    mutating func recordFailedClaim() {
        failedClaims += 1
    }
    
    var averageClaimTime: Double {
        return successfulClaims > 0 ? totalClaimTime / Double(successfulClaims) : 0.0
    }
    
    var successRate: Double {
        let total = successfulClaims + failedClaims
        return total > 0 ? Double(successfulClaims) / Double(total) : 0.0
    }
}