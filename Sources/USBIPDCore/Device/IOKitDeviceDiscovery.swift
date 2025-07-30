// IOKitDeviceDiscovery.swift
// IOKit-based USB device discovery implementation

import Foundation
import IOKit
import IOKit.usb
import Common

// Supporting types are now in IOKitDeviceDiscoverySupport.swift

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
    
    // MARK: - Performance Optimization Properties
    
    /// Device list cache to avoid repeated IOKit queries
    private var deviceListCache: DeviceListCache?
    
    /// Cache configuration for device list caching
    private let cacheConfig: DeviceCacheConfiguration
    
    /// IOKit object pool for reusing common objects
    private let objectPool: IOKitObjectPool
    
    /// CF dictionary pool for reusing dictionary objects
    private let dictionaryPool: CFDictionaryPool
    
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
        self.cacheConfig = .default
        self.deviceListCache = DeviceListCache(config: self.cacheConfig)
        self.objectPool = IOKitObjectPool()
        self.dictionaryPool = CFDictionaryPool()
        
        logger.debug("IOKitDeviceDiscovery initialized with performance optimizations", context: [
            "cacheEnabled": cacheConfig.enableCaching,
            "cacheMaxAge": cacheConfig.maxAge,
            "cacheMaxSize": cacheConfig.maxSize,
            "objectPoolEnabled": true,
            "dictionaryPoolEnabled": true,
            "optimizationLevel": "enhanced"
        ])
    }
    
    /// Internal initializer for testing with dependency injection
    internal init(ioKit: IOKitInterface, logger: Logger? = nil, cacheConfig: DeviceCacheConfiguration? = nil) {
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
        self.cacheConfig = cacheConfig ?? .default
        self.deviceListCache = DeviceListCache(config: self.cacheConfig)
        self.objectPool = IOKitObjectPool()
        self.dictionaryPool = CFDictionaryPool()
        
        self.logger.debug("IOKitDeviceDiscovery initialized with injected dependencies for testing", context: [
            "cacheEnabled": self.cacheConfig.enableCaching,
            "testMode": true,
            "objectPoolEnabled": true,
            "dictionaryPoolEnabled": true,
            "optimizationLevel": "enhanced"
        ])
    }
    
    deinit {
        // Ensure notifications are stopped and resources are cleaned up
        if isMonitoring {
            logger.warning("IOKitDeviceDiscovery being deinitialized while monitoring is active")
            stopNotifications()
        }
        
        // Clean up performance optimization resources
        deviceListCache?.clearCache()
        objectPool.clearPool()
        dictionaryPool.clearPool()
        
        // Final verification that all resources are cleaned up
        if !verifyNotificationCleanup() {
            logger.error("IOKitDeviceDiscovery deinitialized with unclean notification state")
        }
        
        logger.debug("IOKitDeviceDiscovery deinitialized with performance optimization cleanup")
    }
    
    // MARK: - Performance Monitoring
    
    // Performance monitoring is now in IOKitDeviceDiscoveryPerformance.swift
    
    // Performance statistics are now in IOKitDeviceDiscoveryPerformance.swift
    
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
    
    /// Optimized RAII wrapper using IOKitObjectManager for better lifecycle management
    private func withManagedIOKitObject<T>(_ object: io_object_t, type: String = "service", _ block: (io_object_t) throws -> T) throws -> T {
        let manager = IOKitObjectManager(object, type: type)
        
        do {
            let result = try block(manager.value)
            
            // Explicitly release early for better memory management
            let releaseResult = manager.release()
            if releaseResult != KERN_SUCCESS {
                let lifecycleInfo = manager.lifecycleInfo
                logger.warning("Failed to release managed IOKit object", context: [
                    "object": object,
                    "type": lifecycleInfo.type,
                    "age": String(format: "%.3f", lifecycleInfo.age),
                    "kern_return": releaseResult
                ])
            } else {
                let lifecycleInfo = manager.lifecycleInfo
                logger.debug("Successfully released managed IOKit object", context: [
                    "object": object,
                    "type": lifecycleInfo.type,
                    "age": String(format: "%.3f", lifecycleInfo.age)
                ])
            }
            
            return result
        } catch {
            // Manager will automatically clean up in deinit
            let lifecycleInfo = manager.lifecycleInfo
            logger.debug("IOKit object will be auto-released due to error", context: [
                "object": object,
                "type": lifecycleInfo.type,
                "age": String(format: "%.3f", lifecycleInfo.age),
                "error": error.localizedDescription
            ])
            throw error
        }
    }
    
    // MARK: - Error Recovery Configuration
    
    /// Configuration for retry logic during IOKit operations
    private struct RetryConfiguration {
        let maxRetries: Int
        let baseDelay: TimeInterval
        let maxDelay: TimeInterval
        let backoffMultiplier: Double
        
        static let `default` = RetryConfiguration(
            maxRetries: 3,
            baseDelay: 0.1,
            maxDelay: 2.0,
            backoffMultiplier: 2.0
        )
        
        static let aggressive = RetryConfiguration(
            maxRetries: 5,
            baseDelay: 0.05,
            maxDelay: 1.0,
            backoffMultiplier: 1.5
        )
    }
    
    /// Determines if an IOKit error is transient and should be retried
    private func isTransientIOKitError(_ result: kern_return_t) -> Bool {
        let unsignedResult = UInt32(bitPattern: result)
        switch result {
        case KERN_RESOURCE_SHORTAGE, KERN_NO_SPACE, KERN_MEMORY_FAILURE:
            return true
        case KERN_OPERATION_TIMED_OUT:
            return true
        default:
            // Check IOKit-specific transient errors
            switch unsignedResult {
            case 0xe00002bd: // kIOReturnNoMemory
                return true
            case 0xe00002be: // kIOReturnNoResources
                return true
            case 0xe00002d4: // kIOReturnBusy
                return true
            case 0xe00002d5: // kIOReturnTimeout
                return true
            case 0xe00002d7: // kIOReturnNotReady
                return true
            case 0xe00002eb: // kIOReturnNotResponding
                return true
            default:
                return false
            }
        }
    }
    
    /// Execute an IOKit operation with retry logic for transient failures
    private func executeWithRetry<T>(
        operation: String,
        config: RetryConfiguration = .default,
        block: () throws -> T
    ) throws -> T {
        var lastError: Error?
        var delay = config.baseDelay
        
        for attempt in 0...config.maxRetries {
            do {
                if attempt > 0 {
                    logger.debug("Retrying IOKit operation", context: [
                        "operation": operation,
                        "attempt": attempt + 1,
                        "maxRetries": config.maxRetries + 1,
                        "delay": delay
                    ])
                    
                    // Sleep before retry (except for first attempt)
                    Thread.sleep(forTimeInterval: delay)
                    
                    // Exponential backoff with jitter
                    delay = min(delay * config.backoffMultiplier + Double.random(in: 0...0.1), config.maxDelay)
                }
                
                let result = try block()
                
                if attempt > 0 {
                    logger.info("IOKit operation succeeded after retry", context: [
                        "operation": operation,
                        "successfulAttempt": attempt + 1,
                        "totalAttempts": attempt + 1
                    ])
                }
                
                return result
                
            } catch let error as DeviceDiscoveryError {
                lastError = error
                
                // Check if this is a transient error that should be retried
                if case .ioKitError(let code, _) = error, isTransientIOKitError(code) {
                    if attempt < config.maxRetries {
                        logger.warning("Transient IOKit error, will retry", context: [
                            "operation": operation,
                            "attempt": attempt + 1,
                            "error": error.localizedDescription,
                            "nextRetryDelay": delay,
                            "remainingRetries": config.maxRetries - attempt
                        ])
                        continue
                    } else {
                        logger.error("IOKit operation failed after all retries", context: [
                            "operation": operation,
                            "totalAttempts": attempt + 1,
                            "finalError": error.localizedDescription
                        ])
                        throw error
                    }
                } else {
                    // Non-transient error, don't retry
                    logger.debug("Non-transient error, not retrying", context: [
                        "operation": operation,
                        "error": error.localizedDescription,
                        "attempt": attempt + 1
                    ])
                    throw error
                }
            } catch {
                lastError = error
                logger.error("Unexpected error during IOKit operation", context: [
                    "operation": operation,
                    "attempt": attempt + 1,
                    "error": error.localizedDescription
                ])
                throw error
            }
        }
        
        // This should never be reached, but provide a fallback
        throw lastError ?? DeviceDiscoveryError.ioKitError(-1, "Unknown error after retries")
    }
    
    // Error handling utilities are now in IOKitErrorHandling.swift
    
    // Error description methods are now in IOKitErrorHandling.swift
    
    // IOKit-specific error descriptions are now in IOKitErrorHandling.swift
    
    // Error categorization is now in IOKitErrorHandling.swift
    
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
    
    /// Optimized property access with minimal overhead for performance-critical paths
    private func getUInt32PropertyOptimal(from service: io_service_t, key: String) -> UInt32? {
        // Use direct IOKit call without extensive error handling for performance
        guard let property = ioKit.registryEntryCreateCFProperty(
            service, 
            key as CFString, 
            kCFAllocatorDefault, 
            0
        )?.takeRetainedValue() else {
            return nil
        }
        
        defer {
            // Ensure immediate cleanup for optimal memory management
            if CFGetTypeID(property) == CFNumberGetTypeID() {
                // Property will be automatically released when going out of scope
            }
        }
        
        guard let number = property as? NSNumber else {
            return nil
        }
        
        return number.uint32Value
    }
    
    /// Optimized string property access with minimal overhead
    private func getStringPropertyOptimal(from service: io_service_t, key: String) -> String? {
        guard let property = ioKit.registryEntryCreateCFProperty(
            service, 
            key as CFString, 
            kCFAllocatorDefault, 
            0
        )?.takeRetainedValue() else {
            return nil
        }
        
        defer {
            // Ensure immediate cleanup for optimal memory management
            if CFGetTypeID(property) == CFStringGetTypeID() {
                // Property will be automatically released when going out of scope
            }
        }
        
        return property as? String
    }
    
    /// Enhanced RAII wrapper for multiple IOKit objects with automatic cleanup
    private class IOKitObjectBatch {
        private var objects: [io_object_t] = []
        private let lock = NSLock()
        private var isReleased = false
        
        func add(_ object: io_object_t) {
            lock.lock()
            defer { lock.unlock() }
            
            guard !isReleased && object != 0 else { return }
            objects.append(object)
        }
        
        func releaseAll() -> [kern_return_t] {
            lock.lock()
            defer { lock.unlock() }
            
            guard !isReleased else { return [] }
            
            var results: [kern_return_t] = []
            for object in objects {
                if object != 0 {
                    results.append(IOObjectRelease(object))
                }
            }
            
            objects.removeAll()
            isReleased = true
            return results
        }
        
        deinit {
            if !isReleased {
                _ = releaseAll()
            }
        }
    }
    
    /// Memory pool for reusing CFMutableDictionary objects to reduce allocation overhead
    private class CFDictionaryPool {
        private var availableDictionaries: [CFMutableDictionary] = []
        private let lock = NSLock()
        private let maxPoolSize: Int
        private var totalBorrowed: Int = 0
        private var totalReturned: Int = 0
        private var peakUsage: Int = 0
        
        init(maxPoolSize: Int = 5) {
            self.maxPoolSize = maxPoolSize
        }
        
        /// Get a dictionary from the pool or create a new one
        func borrowDictionary() -> CFMutableDictionary {
            lock.lock()
            defer { lock.unlock() }
            
            totalBorrowed += 1
            let currentUsage = totalBorrowed - totalReturned
            peakUsage = max(peakUsage, currentUsage)
            
            if !availableDictionaries.isEmpty {
                let dict = availableDictionaries.removeLast()
                CFDictionaryRemoveAllValues(dict)
                return dict
            }
            
            var keyCallbacks = kCFTypeDictionaryKeyCallBacks
            var valueCallbacks = kCFTypeDictionaryValueCallBacks
            return CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &keyCallbacks, &valueCallbacks)
        }
        
        /// Return a dictionary to the pool for reuse
        func returnDictionary(_ dictionary: CFMutableDictionary) {
            lock.lock()
            defer { lock.unlock() }
            
            totalReturned += 1
            
            guard availableDictionaries.count < maxPoolSize else {
                // Pool is full, let the dictionary be deallocated
                return
            }
            
            CFDictionaryRemoveAllValues(dictionary)
            availableDictionaries.append(dictionary)
        }
        
        /// Get pool statistics for monitoring
        func getPoolStats() -> (available: Int, borrowed: Int, returned: Int, peakUsage: Int) {
            lock.lock()
            defer { lock.unlock() }
            
            return (availableDictionaries.count, totalBorrowed, totalReturned, peakUsage)
        }
        
        /// Clear the pool and release all dictionaries
        func clearPool() {
            lock.lock()
            defer { lock.unlock() }
            
            availableDictionaries.removeAll()
            totalBorrowed = 0
            totalReturned = 0
            peakUsage = 0
        }
        
        deinit {
            clearPool()
        }
    }
    
    /// Batch property extraction for improved performance with optimized memory management
    private func extractPropertiesBatch(from service: io_service_t, keys: [String]) -> [String: Any] {
        var properties: [String: Any] = [:]
        properties.reserveCapacity(keys.count)
        
        // Extract properties individually with optimized error handling
        for key in keys {
            if let property = ioKit.registryEntryCreateCFProperty(
                service, 
                key as CFString, 
                kCFAllocatorDefault, 
                0
            )?.takeRetainedValue() {
                properties[key] = property
            }
        }
        
        return properties
    }
    
    /// Ultra-optimized property extraction for performance-critical paths
    private func extractPropertiesBatchOptimal(from service: io_service_t, keys: [String]) -> [String: Any] {
        var properties: [String: Any] = [:]
        properties.reserveCapacity(keys.count)
        
        // Use direct IOKit calls with minimal overhead for critical properties
        let criticalKeys = [kUSBVendorID, kUSBProductID, "locationID"]
        let optionalKeys = keys.filter { !criticalKeys.contains($0) }
        
        // Extract critical properties first with error handling
        for key in criticalKeys where keys.contains(key) {
            if let property = ioKit.registryEntryCreateCFProperty(
                service, 
                key as CFString, 
                kCFAllocatorDefault, 
                0
            )?.takeRetainedValue() {
                properties[key] = property
            }
        }
        
        // Extract optional properties with graceful failure handling
        for key in optionalKeys {
            if let property = ioKit.registryEntryCreateCFProperty(
                service, 
                key as CFString, 
                kCFAllocatorDefault, 
                0
            )?.takeRetainedValue() {
                properties[key] = property
            }
        }
        
        return properties
    }
    
    /// Extract only essential properties needed for device identification and creation
    private func extractEssentialPropertiesBatch(from service: io_service_t) -> [String: Any] {
        let essentialKeys = [
            "locationID",
            kUSBVendorID,
            kUSBProductID,
            kUSBDeviceClass,
            kUSBDeviceSubClass,
            kUSBDeviceProtocol,
            "USB Address",
            "Speed"
        ]
        
        return extractPropertiesBatch(from: service, keys: essentialKeys)
    }
    
    /// Create USB device from pre-extracted properties to avoid redundant IOKit calls
    private func createUSBDeviceFromPreExtractedProperties(
        service: io_service_t,
        properties: [String: Any],
        locationID: UInt32,
        vendorID: UInt16,
        productID: UInt16
    ) throws -> USBDevice {
        
        // Extract bus and device IDs from locationID
        let busNumber = (locationID >> 24) & 0xFF
        let busID = String(format: "%d", busNumber)
        
        // Try USB Address first, fallback to locationID
        let deviceID: String
        if let usbAddress = properties["USB Address"] as? UInt8 {
            deviceID = String(format: "%d", usbAddress)
        } else {
            let deviceAddress = locationID & 0xFF
            deviceID = String(format: "%d", deviceAddress)
        }
        
        // Extract other properties with defaults
        let deviceClass = (properties[kUSBDeviceClass] as? UInt8) ?? 0
        let deviceSubClass = (properties[kUSBDeviceSubClass] as? UInt8) ?? 0
        let deviceProtocol = (properties[kUSBDeviceProtocol] as? UInt8) ?? 0
        
        // Extract USB speed with fallback using existing extraction method
        let speed = extractUSBSpeed(from: service)
        
        // Extract string descriptors only if needed (lazy loading for performance)
        let manufacturerString = getStringPropertyOptimal(from: service, key: kUSBManufacturerStringIndex)
        let productString = getStringPropertyOptimal(from: service, key: kUSBProductStringIndex)
        let serialNumberString = getStringPropertyOptimal(from: service, key: kUSBSerialNumberStringIndex)
        
        logger.debug("Created USB device from pre-extracted properties", context: [
            "busID": busID,
            "deviceID": deviceID,
            "vendorID": String(format: "0x%04x", vendorID),
            "productID": String(format: "0x%04x", productID),
            "deviceClass": String(format: "0x%02x", deviceClass),
            "speed": speed.rawValue,
            "optimized": true
        ])
        
        return USBDevice(
            busID: busID,
            deviceID: deviceID,
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
    
    /// Create optimized matching dictionary using dictionary pool for better memory management
    private func createOptimizedMatchingDictionary() -> CFMutableDictionary? {
        // Try to use the standard IOKit method first for compatibility
        if let standardDict = ioKit.serviceMatching(kIOUSBDeviceClassName) {
            return standardDict
        }
        
        // Fallback to manual creation using dictionary pool
        let dict = dictionaryPool.borrowDictionary()
        
        // Set up USB device matching criteria
        let ioProviderClass = kIOUSBDeviceClassName as CFString
        CFDictionarySetValue(dict, Unmanaged.passUnretained(kIOProviderClassKey as CFString).toOpaque(), Unmanaged.passUnretained(ioProviderClass).toOpaque())
        
        logger.debug("Created optimized matching dictionary using dictionary pool", context: [
            "className": kIOUSBDeviceClassName,
            "method": "dictionary_pool_fallback"
        ])
        
        return dict
    }
    
    /// Release matching dictionary back to pool for reuse
    private func releaseMatchingDictionary(_ dict: CFMutableDictionary?) {
        guard let dict = dict else { return }
        
        // Return dictionary to pool for reuse
        dictionaryPool.returnDictionary(dict)
        
        logger.debug("Returned matching dictionary to pool for reuse", context: [
            "poolEnabled": true,
            "memoryOptimization": "active"
        ])
    }
    
    /// Handle device disconnection using pre-computed device key
    private func handleDeviceDisconnectionWithKey(deviceKey: String) {
        // Look up the cached device information
        if let cachedDevice = connectedDevices.removeValue(forKey: deviceKey) {
            logger.info("USB device disconnected (optimized)", context: [
                "event": "device_disconnected_optimized",
                "busID": cachedDevice.busID,
                "deviceID": cachedDevice.deviceID,
                "deviceKey": deviceKey,
                "vendorID": String(format: "0x%04x", cachedDevice.vendorID),
                "productID": String(format: "0x%04x", cachedDevice.productID),
                "product": cachedDevice.productString ?? "Unknown",
                "manufacturer": cachedDevice.manufacturerString ?? "Unknown",
                "remainingCachedDevices": connectedDevices.count,
                "optimizationLevel": "minimal_iokit_calls"
            ])
            
            // Trigger the disconnection callback with complete device information
            logger.debug("Triggering optimized device disconnection callback")
            onDeviceDisconnected?(cachedDevice)
            
        } else {
            logger.warning("Device disconnected but not found in cache (optimized)", context: [
                "deviceKey": deviceKey,
                "cachedDeviceCount": connectedDevices.count,
                "cachedDeviceKeys": Array(connectedDevices.keys),
                "possibleCause": "Device was connected before monitoring started or cache was cleared"
            ])
            
            // Create minimal device information from device key
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
                
                logger.info("USB device disconnected (minimal info, optimized)", context: [
                    "event": "device_disconnected_minimal_optimized",
                    "busID": busID,
                    "deviceID": deviceID,
                    "deviceKey": deviceKey,
                    "dataAvailable": "minimal",
                    "reason": "Device not found in cache",
                    "optimizationLevel": "minimal_iokit_calls"
                ])
                
                logger.debug("Triggering optimized device disconnection callback with minimal info")
                onDeviceDisconnected?(minimalDevice)
            }
        }
    }
    
    /// Optional property access with graceful fallback
    private func getUInt32PropertyOptional(from service: io_service_t, key: String) -> UInt32? {
        do {
            return try getUInt32Property(from: service, key: key)
        } catch {
            return nil
        }
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
        // Check cache first for performance optimization
        if let cachedDevices = deviceListCache?.getCachedDevices() {
            let cacheStats = deviceListCache?.getCacheStats() ?? (0, 0, false)
            logger.debug("Using cached device list for performance", context: [
                "cachedDeviceCount": cachedDevices.count,
                "cacheAge": String(format: "%.2f", cacheStats.1),
                "cacheMaxAge": cacheConfig.maxAge
            ])
            return cachedDevices
        }
        
        return try executeWithRetry(operation: "device discovery") {
            return try safeIOKitOperation("device discovery with retry") {
                logger.debug("Starting USB device discovery with error recovery and caching")
                var devices: [USBDevice] = []
                var skippedDevices = 0
                var recoveredDevices = 0
                var partialFailures: [String] = []
                
                // Create matching dictionary for USB devices with retry logic and dictionary pooling
                guard let matchingDict = createOptimizedMatchingDictionary() else {
                    logger.error("Failed to create IOKit matching dictionary")
                    throw DeviceDiscoveryError.failedToCreateMatchingDictionary
                }
                
                // Ensure dictionary is returned to pool after use
                defer {
                    releaseMatchingDictionary(matchingDict)
                }
                
                logger.debug("Created IOKit matching dictionary for USB devices", context: [
                    "className": kIOUSBDeviceClassName
                ])
                
                var iterator: io_iterator_t = 0
                let masterPort: mach_port_t
                if #available(macOS 12.0, *) {
                    masterPort = kIOMainPortDefault
                } else {
                    masterPort = kIOMasterPortDefault
                }
                
                // Use retry logic for service enumeration
                _ = try executeWithRetry(operation: "IOServiceGetMatchingServices") {
                    let result = ioKit.serviceGetMatchingServices(masterPort, matchingDict, &iterator)
                    guard result == KERN_SUCCESS else {
                        throw handleServiceAccessError(result, operation: "IOServiceGetMatchingServices")
                    }
                    return result
                }
                
                logger.debug("Successfully obtained IOKit service iterator with retry support", context: [
                    "iterator": iterator
                ])
            
            return try withIOKitObjectAndCleanup(iterator) { iterator in
                logger.debug("Iterating through discovered USB devices with error recovery")
                var deviceCount = 0
                var service: io_service_t = ioKit.iteratorNext(iterator)
                
                while service != 0 {
                    let currentDeviceIndex = deviceCount + 1
                    
                    // Process each device with comprehensive error recovery
                    let deviceResult = processDeviceWithRecovery(service: service, deviceIndex: currentDeviceIndex)
                    
                    switch deviceResult {
                    case .success(let device):
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
                        
                    case .recovered(let device):
                        devices.append(device)
                        recoveredDevices += 1
                        
                        logger.info("Successfully recovered device after partial failure", context: [
                            "deviceIndex": currentDeviceIndex,
                            "busID": device.busID,
                            "deviceID": device.deviceID,
                            "recoveryType": "partial_data",
                            "availableData": getAvailableDeviceDataDescription(device)
                        ])
                        
                    case .skipped(let reason):
                        skippedDevices += 1
                        partialFailures.append("Device \(currentDeviceIndex): \(reason)")
                        
                        logger.warning("Skipping device due to unrecoverable error", context: [
                            "deviceIndex": currentDeviceIndex,
                            "reason": reason,
                            "action": "skipped"
                        ])
                    }
                    
                    service = ioKit.iteratorNext(iterator)
                }
                
                // Log comprehensive discovery summary with recovery statistics
                logger.info("USB device discovery completed with error recovery", context: [
                    "successfulDevices": deviceCount - recoveredDevices,
                    "recoveredDevices": recoveredDevices,
                    "skippedDevices": skippedDevices,
                    "totalProcessed": deviceCount + skippedDevices,
                    "recoveryRate": recoveredDevices > 0 ? String(format: "%.1f%%", Double(recoveredDevices) / Double(deviceCount + skippedDevices) * 100) : "0%"
                ])
                
                if skippedDevices > 0 {
                    logger.warning("Some devices were skipped during enumeration", context: [
                        "skippedCount": skippedDevices,
                        "successfulCount": deviceCount,
                        "partialFailures": partialFailures,
                        "recommendation": "Check device permissions and IOKit access"
                    ])
                }
                
                if recoveredDevices > 0 {
                    logger.info("Successfully recovered devices from partial failures", context: [
                        "recoveredCount": recoveredDevices,
                        "totalDevices": deviceCount,
                        "impact": "Some device information may be incomplete but devices are usable"
                    ])
                }
                
                // Update cache with discovered devices for performance optimization
                deviceListCache?.updateCache(with: devices)
                
                // Monitor memory usage and trigger cleanup if needed
                monitorMemoryUsage()
                
                logger.debug("Device discovery completed with caching and memory monitoring", context: [
                    "discoveredDevices": devices.count,
                    "cacheEnabled": cacheConfig.enableCaching,
                    "cacheMaxAge": cacheConfig.maxAge,
                    "memoryOptimizationsActive": true
                ])
                
                return devices
            }
            }
        }
    }
    
    /// Enhanced IOKit object wrapper with comprehensive cleanup
    private func withIOKitObjectAndCleanup<T>(_ object: io_object_t, _ block: (io_object_t) throws -> T) throws -> T {
        var cleanupPerformed = false
        
        defer {
            if !cleanupPerformed && object != 0 {
                let result = ioKit.objectRelease(object)
                if result != KERN_SUCCESS {
                    logger.warning("Failed to release IOKit object during cleanup", context: [
                        "object": object,
                        "kern_return": result
                    ])
                } else {
                    logger.debug("Successfully released IOKit object during cleanup", context: [
                        "object": object
                    ])
                }
            }
        }
        
        do {
            let result = try block(object)
            
            // Perform explicit cleanup on success
            if object != 0 {
                let releaseResult = ioKit.objectRelease(object)
                cleanupPerformed = true
                
                if releaseResult != KERN_SUCCESS {
                    logger.warning("Failed to release IOKit object after successful operation", context: [
                        "object": object,
                        "kern_return": releaseResult
                    ])
                } else {
                    logger.debug("Successfully released IOKit object after successful operation", context: [
                        "object": object
                    ])
                }
            }
            
            return result
            
        } catch {
            // Perform explicit cleanup on error
            if object != 0 {
                let releaseResult = ioKit.objectRelease(object)
                cleanupPerformed = true
                
                if releaseResult != KERN_SUCCESS {
                    logger.error("Failed to release IOKit object after error", context: [
                        "object": object,
                        "kern_return": releaseResult,
                        "originalError": error.localizedDescription
                    ])
                } else {
                    logger.debug("Successfully released IOKit object after error", context: [
                        "object": object,
                        "originalError": error.localizedDescription
                    ])
                }
            }
            
            throw error
        }
    }
    
    /// Result type for device processing with recovery
    private enum DeviceProcessingResult {
        case success(USBDevice)
        case recovered(USBDevice)
        case skipped(String)
    }
    
    /// Process a single device with comprehensive error recovery
    private func processDeviceWithRecovery(service: io_service_t, deviceIndex: Int) -> DeviceProcessingResult {
        do {
            // Try normal device creation first
            let device = try withIOKitObject(service) { service in
                return try createUSBDeviceFromService(service)
            }
            return .success(device)
            
        } catch let error as DeviceDiscoveryError {
            // Attempt recovery based on error type
            switch error {
            case .deviceNotFound(_):
                // Device was removed during processing - try to create minimal device
                logger.debug("Attempting device recovery after removal", context: [
                    "deviceIndex": deviceIndex,
                    "error": error.localizedDescription
                ])
                
                if let recoveredDevice = attemptDeviceRecovery(service: service) {
                    return .recovered(recoveredDevice)
                } else {
                    return .skipped("Device removed during processing and recovery failed")
                }
                
            case .ioKitError(_, _) where isDeviceRemovalError(error):
                // Device was removed during processing - try to create minimal device
                logger.debug("Attempting device recovery after removal", context: [
                    "deviceIndex": deviceIndex,
                    "error": error.localizedDescription
                ])
                
                if let recoveredDevice = attemptDeviceRecovery(service: service) {
                    return .recovered(recoveredDevice)
                } else {
                    return .skipped("Device removed during processing and recovery failed")
                }
                
            case .missingProperty(let property):
                // Try to create device with default values for missing properties
                logger.debug("Attempting device recovery with missing property", context: [
                    "deviceIndex": deviceIndex,
                    "missingProperty": property
                ])
                
                if let recoveredDevice = attemptDeviceRecoveryWithDefaults(service: service, missingProperty: property) {
                    return .recovered(recoveredDevice)
                } else {
                    return .skipped("Missing critical property: \(property)")
                }
                
            case .invalidPropertyType(let property):
                return .skipped("Invalid property type: \(property)")
                
            case .ioKitError(let code, let message):
                if isTransientIOKitError(code) {
                    // For transient errors, the retry logic in executeWithRetry should handle it
                    // If we reach here, all retries failed
                    return .skipped("Transient IOKit error after retries: \(message)")
                } else {
                    return .skipped("IOKit error: \(message)")
                }
                
            default:
                return .skipped("Unexpected error: \(error.localizedDescription)")
            }
            
        } catch {
            return .skipped("Unexpected error: \(error.localizedDescription)")
        }
    }
    
    /// Attempt to recover device information after device removal
    private func attemptDeviceRecovery(service: io_service_t) -> USBDevice? {
        logger.debug("Attempting device recovery after removal")
        
        // Try to extract minimal identification information
        guard let locationID = getUInt32PropertyOptional(from: service, key: "locationID") else {
            logger.debug("Cannot recover device - no locationID available")
            return nil
        }
        
        let busNumber = (locationID >> 24) & 0xFF
        let busID = String(format: "%d", busNumber)
        
        let deviceAddress = locationID & 0xFF
        let deviceID = String(format: "%d", deviceAddress)
        
        logger.debug("Recovered basic device identification", context: [
            "busID": busID,
            "deviceID": deviceID,
            "locationID": String(format: "0x%08x", locationID)
        ])
        
        // Create minimal device with available information
        return USBDevice(
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
    }
    
    /// Attempt to recover device with default values for missing properties
    private func attemptDeviceRecoveryWithDefaults(service: io_service_t, missingProperty: String) -> USBDevice? {
        logger.debug("Attempting device recovery with defaults", context: [
            "missingProperty": missingProperty
        ])
        
        do {
            // Extract what we can and use defaults for the rest
            let busID = try getBusID(from: service)
            let deviceID = try getDeviceID(from: service)
            
            // Try to extract vendor/product IDs - these are critical
            let vendorID: UInt16
            let productID: UInt16
            
            if missingProperty == kUSBVendorID {
                vendorID = 0 // Default for missing vendor ID
                productID = try getUInt16Property(from: service, key: kUSBProductID)
            } else if missingProperty == kUSBProductID {
                vendorID = try getUInt16Property(from: service, key: kUSBVendorID)
                productID = 0 // Default for missing product ID
            } else {
                // Missing property is not critical, extract normally
                vendorID = try getUInt16Property(from: service, key: kUSBVendorID)
                productID = try getUInt16Property(from: service, key: kUSBProductID)
            }
            
            // Use defaults for other properties
            let deviceClass = extractDeviceClass(from: service)
            let deviceSubClass = extractDeviceSubClass(from: service)
            let deviceProtocol = extractDeviceProtocol(from: service)
            let speed = extractUSBSpeed(from: service)
            let manufacturerString = extractManufacturerString(from: service)
            let productString = extractProductString(from: service)
            let serialNumberString = extractSerialNumberString(from: service)
            
            logger.debug("Successfully recovered device with defaults", context: [
                "busID": busID,
                "deviceID": deviceID,
                "vendorID": String(format: "0x%04x", vendorID),
                "productID": String(format: "0x%04x", productID),
                "missingProperty": missingProperty
            ])
            
            return USBDevice(
                busID: busID,
                deviceID: deviceID,
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
            
        } catch {
            logger.debug("Device recovery with defaults failed", context: [
                "error": error.localizedDescription,
                "missingProperty": missingProperty
            ])
            return nil
        }
    }
    
    /// Get description of available device data for logging
    private func getAvailableDeviceDataDescription(_ device: USBDevice) -> String {
        var available: [String] = []
        
        if device.vendorID != 0 { available.append("vendorID") }
        if device.productID != 0 { available.append("productID") }
        if device.deviceClass != 0 { available.append("deviceClass") }
        if device.speed != .unknown { available.append("speed") }
        if device.manufacturerString != nil { available.append("manufacturer") }
        if device.productString != nil { available.append("product") }
        if device.serialNumberString != nil { available.append("serial") }
        
        return available.isEmpty ? "minimal" : available.joined(separator: ", ")
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
    
    /// Create USBDevice object from IOKit service with comprehensive error recovery
    /// Converts IOKit service to USBDevice with proper bus/device ID generation and retry logic
    private func createUSBDeviceFromService(_ service: io_service_t) throws -> USBDevice {
        return try executeWithRetry(operation: "USB device creation", config: .aggressive) {
            return try safeIOKitOperation("USB device creation with recovery") {
                logger.debug("Creating USBDevice from IOKit service with error recovery", context: [
                    "service": service
                ])
                
                // Use the enhanced device creation method with removal handling
                return try createUSBDeviceWithDeviceRemovalHandling(service)
            }
        }
    }
    
    /// Create USBDevice with graceful handling of device removal during property extraction
    private func createUSBDeviceWithDeviceRemovalHandling(_ service: io_service_t) throws -> USBDevice {
        // First, verify the service is still valid before proceeding
        guard isServiceValid(service) else {
            logger.warning("Device service is no longer valid, device may have been removed")
            throw DeviceDiscoveryError.deviceNotFound("Device removed during property extraction")
        }
        
        var partiallyExtractedData: [String: Any] = [:]
        
        do {
            // Extract critical properties first (bus/device IDs) to enable partial recovery
            logger.debug("Extracting critical device identification properties first")
            let busID = try getBusID(from: service)
            let deviceID = try getDeviceID(from: service)
            partiallyExtractedData["busID"] = busID
            partiallyExtractedData["deviceID"] = deviceID
            
            // Extract device properties using the comprehensive property extraction method
            let properties = try extractDevicePropertiesWithRecovery(from: service, partialData: &partiallyExtractedData)
            
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
            
        } catch let error as DeviceDiscoveryError {
            // Handle device removal during property extraction
            if isDeviceRemovalError(error) {
                logger.warning("Device was removed during property extraction, attempting recovery", context: [
                    "error": error.localizedDescription,
                    "partialDataKeys": Array(partiallyExtractedData.keys),
                    "recoveryAction": "creating_minimal_device"
                ])
                
                // Try to create a minimal device from any successfully extracted data
                if let minimalDevice = createMinimalDeviceFromPartialData(partiallyExtractedData) {
                    logger.info("Successfully created minimal device from partial data", context: [
                        "busID": minimalDevice.busID,
                        "deviceID": minimalDevice.deviceID,
                        "availableData": Array(partiallyExtractedData.keys)
                    ])
                    return minimalDevice
                } else {
                    logger.error("Could not create minimal device from partial data", context: [
                        "partialDataKeys": Array(partiallyExtractedData.keys),
                        "originalError": error.localizedDescription
                    ])
                    throw error
                }
            } else {
                // Re-throw non-removal errors
                throw error
            }
        }
    }
    
    /// Check if a service is still valid (device hasn't been removed)
    private func isServiceValid(_ service: io_service_t) -> Bool {
        // Try to get a basic property to verify the service is still accessible
        guard let property = ioKit.registryEntryCreateCFProperty(service, "IOObjectClass" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return false
        }
        
        // Check if it's a USB device class
        guard let className = property as? String else {
            return false
        }
        
        // Valid if it's a USB device or related class
        return className.contains("USB") || className == "IOUSBDevice" || className == "IOUSBInterface"
    }
    
    /// Check if an error indicates device removal
    private func isDeviceRemovalError(_ error: DeviceDiscoveryError) -> Bool {
        switch error {
        case .ioKitError(let code, _):
            let unsignedCode = UInt32(bitPattern: code)
            switch unsignedCode {
            case 0xe00002c0: // kIOReturnNoDevice
                return true
            case 0xe00002d8: // kIOReturnNotAttached
                return true
            case 0xe00002ee: // kIOReturnNotFound
                return true
            default:
                return false
            }
        case .deviceNotFound(_):
            return true
        case .missingProperty(_):
            // Could indicate device removal if critical properties are missing
            return true
        default:
            return false
        }
    }
    
    /// Create a minimal device from partially extracted data
    private func createMinimalDeviceFromPartialData(_ partialData: [String: Any]) -> USBDevice? {
        // Extract required fields with fallbacks
        guard let busID = partialData["busID"] as? String,
              let deviceID = partialData["deviceID"] as? String else {
            return nil
        }
        
        let vendorID = partialData["vendorID"] as? UInt16 ?? 0
        let productID = partialData["productID"] as? UInt16 ?? 0
        let deviceClass = partialData["deviceClass"] as? UInt8 ?? 0
        let deviceSubClass = partialData["deviceSubClass"] as? UInt8 ?? 0
        let deviceProtocol = partialData["deviceProtocol"] as? UInt8 ?? 0
        let speed = partialData["speed"] as? USBSpeed ?? .unknown
        let manufacturerString = partialData["manufacturerString"] as? String
        let productString = partialData["productString"] as? String
        let serialNumberString = partialData["serialNumberString"] as? String
        
        return USBDevice(
            busID: busID,
            deviceID: deviceID,
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
    
    /// Extract comprehensive device properties from IOKit service
    /// Maps IOKit property keys to USBDevice struct fields with graceful error handling
    private func extractDeviceProperties(from service: io_service_t) throws -> DeviceProperties {
        var partialData: [String: Any] = [:]
        return try extractDevicePropertiesWithRecovery(from: service, partialData: &partialData)
    }
    
    /// Extract device properties with recovery support for device removal during extraction
    private func extractDevicePropertiesWithRecovery(from service: io_service_t, partialData: inout [String: Any]) throws -> DeviceProperties {
        return try safeIOKitOperation("device property extraction with recovery") {
            logger.debug("Starting device property extraction from IOKit service with recovery support")
            
            // Extract required properties with detailed logging and recovery tracking
            logger.debug("Extracting required device properties")
            let vendorID = try extractVendorIDWithRecovery(from: service, partialData: &partialData)
            let productID = try extractProductIDWithRecovery(from: service, partialData: &partialData)
            
            logger.debug("Extracting device class information")
            let deviceClass = extractDeviceClassWithRecovery(from: service, partialData: &partialData)
            let deviceSubClass = extractDeviceSubClassWithRecovery(from: service, partialData: &partialData)
            let deviceProtocol = extractDeviceProtocolWithRecovery(from: service, partialData: &partialData)
            
            logger.debug("Extracting device speed information")
            let speed = extractUSBSpeedWithRecovery(from: service, partialData: &partialData)
        
            // Extract optional string descriptors with detailed logging
            logger.debug("Extracting optional string descriptors")
            let manufacturerString = extractManufacturerStringWithRecovery(from: service, partialData: &partialData)
            let productString = extractProductStringWithRecovery(from: service, partialData: &partialData)
            let serialNumberString = extractSerialNumberStringWithRecovery(from: service, partialData: &partialData)
            
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
    
    // MARK: - Recovery-Enabled Property Extraction Methods
    
    /// Extract vendor ID with recovery support for device removal
    private func extractVendorIDWithRecovery(from service: io_service_t, partialData: inout [String: Any]) throws -> UInt16 {
        logger.debug("Extracting vendor ID from device properties with recovery support")
        
        // Check if device is still valid before attempting extraction
        guard isServiceValid(service) else {
            logger.warning("Device service invalid during vendor ID extraction")
            throw DeviceDiscoveryError.deviceNotFound("Device removed during vendor ID extraction")
        }
        
        do {
            let vendorID = try getUInt16Property(from: service, key: kUSBVendorID)
            partialData["vendorID"] = vendorID
            logger.debug("Successfully extracted vendor ID with recovery", context: [
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
    
    /// Extract product ID with recovery support for device removal
    private func extractProductIDWithRecovery(from service: io_service_t, partialData: inout [String: Any]) throws -> UInt16 {
        logger.debug("Extracting product ID from device properties with recovery support")
        
        // Check if device is still valid before attempting extraction
        guard isServiceValid(service) else {
            logger.warning("Device service invalid during product ID extraction")
            throw DeviceDiscoveryError.deviceNotFound("Device removed during product ID extraction")
        }
        
        do {
            let productID = try getUInt16Property(from: service, key: kUSBProductID)
            partialData["productID"] = productID
            logger.debug("Successfully extracted product ID with recovery", context: [
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
    
    /// Extract device class with recovery support for device removal
    private func extractDeviceClassWithRecovery(from service: io_service_t, partialData: inout [String: Any]) -> UInt8 {
        logger.debug("Extracting device class from properties with recovery support")
        
        // Check if device is still valid before attempting extraction
        guard isServiceValid(service) else {
            logger.warning("Device service invalid during device class extraction, using default")
            let defaultClass: UInt8 = 0x00
            partialData["deviceClass"] = defaultClass
            return defaultClass
        }
        
        do {
            let deviceClass = try getUInt8Property(from: service, key: kUSBDeviceClass)
            partialData["deviceClass"] = deviceClass
            logger.debug("Successfully extracted device class with recovery", context: [
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
            let defaultClass: UInt8 = 0x00
            partialData["deviceClass"] = defaultClass
            return defaultClass
        }
    }
    
    /// Extract device subclass with recovery support for device removal
    private func extractDeviceSubClassWithRecovery(from service: io_service_t, partialData: inout [String: Any]) -> UInt8 {
        logger.debug("Extracting device subclass from properties with recovery support")
        
        // Check if device is still valid before attempting extraction
        guard isServiceValid(service) else {
            logger.warning("Device service invalid during device subclass extraction, using default")
            let defaultSubClass: UInt8 = 0x00
            partialData["deviceSubClass"] = defaultSubClass
            return defaultSubClass
        }
        
        do {
            let deviceSubClass = try getUInt8Property(from: service, key: kUSBDeviceSubClass)
            partialData["deviceSubClass"] = deviceSubClass
            logger.debug("Successfully extracted device subclass with recovery", context: [
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
            let defaultSubClass: UInt8 = 0x00
            partialData["deviceSubClass"] = defaultSubClass
            return defaultSubClass
        }
    }
    
    /// Extract device protocol with recovery support for device removal
    private func extractDeviceProtocolWithRecovery(from service: io_service_t, partialData: inout [String: Any]) -> UInt8 {
        logger.debug("Extracting device protocol from properties with recovery support")
        
        // Check if device is still valid before attempting extraction
        guard isServiceValid(service) else {
            logger.warning("Device service invalid during device protocol extraction, using default")
            let defaultProtocol: UInt8 = 0x00
            partialData["deviceProtocol"] = defaultProtocol
            return defaultProtocol
        }
        
        do {
            let deviceProtocol = try getUInt8Property(from: service, key: kUSBDeviceProtocol)
            partialData["deviceProtocol"] = deviceProtocol
            logger.debug("Successfully extracted device protocol with recovery", context: [
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
            let defaultProtocol: UInt8 = 0x00
            partialData["deviceProtocol"] = defaultProtocol
            return defaultProtocol
        }
    }
    
    /// Extract USB speed with recovery support for device removal
    private func extractUSBSpeedWithRecovery(from service: io_service_t, partialData: inout [String: Any]) -> USBSpeed {
        logger.debug("Extracting USB speed from device properties with recovery support")
        
        // Check if device is still valid before attempting extraction
        guard isServiceValid(service) else {
            logger.warning("Device service invalid during USB speed extraction, using unknown")
            let defaultSpeed = USBSpeed.unknown
            partialData["speed"] = defaultSpeed
            return defaultSpeed
        }
        
        // Try multiple possible property keys for speed information
        let speedKeys = ["Speed", "Device Speed"]
        
        for key in speedKeys {
            logger.debug("Attempting to extract speed from property with recovery", context: [
                "property": key
            ])
            
            if let speed = tryExtractSpeed(from: service, key: key) {
                partialData["speed"] = speed
                logger.debug("Successfully extracted USB speed with recovery", context: [
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
        let defaultSpeed = USBSpeed.unknown
        partialData["speed"] = defaultSpeed
        return defaultSpeed
    }
    
    /// Extract manufacturer string with recovery support for device removal
    private func extractManufacturerStringWithRecovery(from service: io_service_t, partialData: inout [String: Any]) -> String? {
        logger.debug("Extracting manufacturer string descriptor with recovery support")
        
        // Check if device is still valid before attempting extraction
        guard isServiceValid(service) else {
            logger.warning("Device service invalid during manufacturer string extraction")
            partialData["manufacturerString"] = nil
            return nil
        }
        
        // Try multiple possible property keys for manufacturer string
        let manufacturerKeys = ["USB Vendor Name", "Manufacturer"]
        
        for key in manufacturerKeys {
            logger.debug("Attempting to extract manufacturer from property with recovery", context: [
                "property": key
            ])
            
            if let manufacturer = getStringProperty(from: service, key: key) {
                partialData["manufacturerString"] = manufacturer
                logger.debug("Successfully found manufacturer string with recovery", context: [
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
        partialData["manufacturerString"] = nil
        return nil
    }
    
    /// Extract product string with recovery support for device removal
    private func extractProductStringWithRecovery(from service: io_service_t, partialData: inout [String: Any]) -> String? {
        logger.debug("Extracting product string descriptor with recovery support")
        
        // Check if device is still valid before attempting extraction
        guard isServiceValid(service) else {
            logger.warning("Device service invalid during product string extraction")
            partialData["productString"] = nil
            return nil
        }
        
        // Try multiple possible property keys for product string
        let productKeys = ["USB Product Name", "Product"]
        
        for key in productKeys {
            logger.debug("Attempting to extract product from property with recovery", context: [
                "property": key
            ])
            
            if let product = getStringProperty(from: service, key: key) {
                partialData["productString"] = product
                logger.debug("Successfully found product string with recovery", context: [
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
        partialData["productString"] = nil
        return nil
    }
    
    /// Extract serial number string with recovery support for device removal
    private func extractSerialNumberStringWithRecovery(from service: io_service_t, partialData: inout [String: Any]) -> String? {
        logger.debug("Extracting serial number string descriptor with recovery support")
        
        // Check if device is still valid before attempting extraction
        guard isServiceValid(service) else {
            logger.warning("Device service invalid during serial number string extraction")
            partialData["serialNumberString"] = nil
            return nil
        }
        
        // Try multiple possible property keys for serial number string
        let serialKeys = ["USB Serial Number", "Serial Number"]
        
        for key in serialKeys {
            logger.debug("Attempting to extract serial from property with recovery", context: [
                "property": key
            ])
            
            if let serial = getStringProperty(from: service, key: key) {
                partialData["serialNumberString"] = serial
                logger.debug("Successfully found serial number string with recovery", context: [
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
        partialData["serialNumberString"] = nil
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
            
            logger.info("Initializing USB device notification system with error recovery")
            
            // Ensure clean state before starting with comprehensive cleanup
            try ensureCleanNotificationStateWithRecovery()
            
            // Use retry logic for notification setup
            try executeWithRetry(operation: "notification system setup") {
                try setupNotificationSystemWithRecovery()
            }
            
            isMonitoring = true
            logger.info("USB device notification system started successfully with error recovery", context: [
                "addedIterator": addedIterator,
                "removedIterator": removedIterator,
                "isMonitoring": isMonitoring
            ])
        }
    }
    
    /// Setup notification system with comprehensive error recovery
    private func setupNotificationSystemWithRecovery() throws {
        logger.debug("Starting USB device notification setup with recovery")
        
        // Create notification port with retry logic
        logger.debug("Creating IOKit notification port with retry support")
        let masterPort: mach_port_t
        if #available(macOS 12.0, *) {
            masterPort = kIOMainPortDefault
        } else {
            masterPort = kIOMasterPortDefault
        }
        
        notificationPort = try executeWithRetry(operation: "IONotificationPortCreate") {
            let port = ioKit.notificationPortCreate(masterPort)
            guard let port = port else {
                throw handleNotificationError(KERN_FAILURE, operation: "IONotificationPortCreate")
            }
            return port
        }
        
        guard let port = notificationPort else {
            let error = handleNotificationError(KERN_FAILURE, operation: "IONotificationPortCreate")
            logger.error("Failed to create IOKit notification port after retries", context: [
                "error": error.localizedDescription,
                "impact": "Device monitoring will not be available"
            ])
            throw error
        }
        
        logger.debug("Successfully created IOKit notification port with retry support")
        
        // Set notification port dispatch queue
        ioKit.notificationPortSetDispatchQueue(port, queue)
        logger.debug("Configured notification port with dispatch queue", context: [
            "queueLabel": queue.label
        ])
        
        // Set up device added notifications with retry logic
        try setupDeviceAddedNotificationsWithRecovery(port: port)
        
        // Set up device removed notifications with retry logic
        try setupDeviceRemovedNotificationsWithRecovery(port: port)
        
        logger.debug("Consuming initial device notifications to prime iterators")
        
        // Consume initial notifications with error handling
        consumeIteratorWithRecovery(addedIterator, isAddedNotification: true)
        consumeIteratorWithRecovery(removedIterator, isAddedNotification: false)
    }
    
    /// Setup device added notifications with comprehensive error recovery
    private func setupDeviceAddedNotificationsWithRecovery(port: IONotificationPortRef) throws {
        logger.debug("Setting up device connection notifications with recovery")
        
        _ = try executeWithRetry(operation: "device added notification setup") {
            guard let addedMatchingDict = ioKit.serviceMatching(kIOUSBDeviceClassName) else {
                throw DeviceDiscoveryError.failedToCreateMatchingDictionary
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
                throw handleNotificationError(addedResult, operation: "IOServiceAddMatchingNotification (device added)")
            }
            
            return addedResult
        }
        
        logger.debug("Successfully setup device connection notifications with recovery", context: [
            "iterator": addedIterator
        ])
    }
    
    /// Setup device removed notifications with comprehensive error recovery
    private func setupDeviceRemovedNotificationsWithRecovery(port: IONotificationPortRef) throws {
        logger.debug("Setting up device disconnection notifications with recovery")
        
        _ = try executeWithRetry(operation: "device removed notification setup") {
            guard let removedMatchingDict = ioKit.serviceMatching(kIOUSBDeviceClassName) else {
                throw DeviceDiscoveryError.failedToCreateMatchingDictionary
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
                throw handleNotificationError(removedResult, operation: "IOServiceAddMatchingNotification (device removed)")
            }
            
            return removedResult
        }
        
        logger.debug("Successfully setup device disconnection notifications with recovery", context: [
            "iterator": removedIterator
        ])
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
            logger.debug("Clearing device cache and performance optimization resources")
            cleanupDeviceCache()
            cleanupPerformanceOptimizations()
            
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
            ioKit.notificationPortSetDispatchQueue(port, nil)
            
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
    
    /// Clean up performance optimization resources
    private func cleanupPerformanceOptimizations() {
        logger.debug("Cleaning up performance optimization resources")
        
        // Clear device list cache
        let cacheStats = deviceListCache?.getCacheStats() ?? (0, 0, false)
        deviceListCache?.clearCache()
        
        // Clear object pool
        objectPool.clearPool()
        
        logger.debug("Completed performance optimization cleanup", context: [
            "previousCacheDeviceCount": cacheStats.0,
            "previousCacheAge": String(format: "%.2f", cacheStats.1),
            "cacheWasValid": cacheStats.2,
            "objectPoolCleared": true
        ])
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
    
    /// Ensure clean notification state with comprehensive error recovery
    /// Enhanced version with retry logic and better error handling
    private func ensureCleanNotificationStateWithRecovery() throws {
        logger.debug("Ensuring clean notification state with error recovery")
        
        var cleanupErrors: [String] = []
        
        // Check for any leftover notification port with retry cleanup
        if notificationPort != nil {
            logger.warning("Found leftover notification port, cleaning up with recovery")
            do {
                _ = try executeWithRetry(operation: "notification port cleanup") {
                    cleanupNotificationPort()
                    return true
                }
            } catch {
                cleanupErrors.append("Failed to cleanup notification port: \(error.localizedDescription)")
                logger.error("Failed to cleanup leftover notification port", context: [
                    "error": error.localizedDescription
                ])
            }
        }
        
        // Check for any leftover iterators with retry cleanup
        if addedIterator != 0 {
            logger.warning("Found leftover added iterator, cleaning up with recovery")
            do {
                _ = try executeWithRetry(operation: "added iterator cleanup") {
                    let result = ioKit.objectRelease(addedIterator)
                    guard result == KERN_SUCCESS else {
                        throw DeviceDiscoveryError.ioKitError(result, "Failed to release added iterator")
                    }
                    addedIterator = 0
                    return result
                }
            } catch {
                cleanupErrors.append("Failed to cleanup added iterator: \(error.localizedDescription)")
                logger.error("Failed to cleanup leftover added iterator", context: [
                    "error": error.localizedDescription
                ])
            }
        }
        
        if removedIterator != 0 {
            logger.warning("Found leftover removed iterator, cleaning up with recovery")
            do {
                _ = try executeWithRetry(operation: "removed iterator cleanup") {
                    let result = ioKit.objectRelease(removedIterator)
                    guard result == KERN_SUCCESS else {
                        throw DeviceDiscoveryError.ioKitError(result, "Failed to release removed iterator")
                    }
                    removedIterator = 0
                    return result
                }
            } catch {
                cleanupErrors.append("Failed to cleanup removed iterator: \(error.localizedDescription)")
                logger.error("Failed to cleanup leftover removed iterator", context: [
                    "error": error.localizedDescription
                ])
            }
        }
        
        // Clear device cache if it has stale data
        if !connectedDevices.isEmpty {
            logger.warning("Found stale device cache, clearing with recovery")
            connectedDevices.removeAll()
        }
        
        if cleanupErrors.isEmpty {
            logger.debug("Notification state is clean after recovery")
        } else {
            logger.warning("Notification state cleanup completed with some errors", context: [
                "cleanupErrors": cleanupErrors,
                "impact": "Some resources may not have been properly cleaned up"
            ])
            
            // Don't throw error for cleanup issues - log and continue
            // This allows the system to attempt to start notifications even if cleanup had issues
        }
    }
    
    /// Enhanced iterator consumption with error recovery
    private func consumeIteratorWithRecovery(_ iterator: io_iterator_t, isAddedNotification: Bool) {
        let eventType = isAddedNotification ? "connection" : "disconnection"
        logger.debug("Starting to process \(eventType) notifications with recovery", context: [
            "iterator": iterator,
            "eventType": eventType
        ])
        
        do {
            _ = try executeWithRetry(operation: "iterator consumption", config: .default) {
                consumeIterator(iterator, isAddedNotification: isAddedNotification)
                return true
            }
        } catch {
            logger.error("Failed to consume iterator notifications after retries", context: [
                "eventType": eventType,
                "iterator": iterator,
                "error": error.localizedDescription,
                "impact": "Some initial device notifications may be lost"
            ])
        }
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
        logger.debug("Starting to process \(eventType) notifications with optimizations", context: [
            "iterator": iterator,
            "eventType": eventType
        ])
        
        // Invalidate cache on device changes for consistency
        if cacheConfig.enableCaching {
            deviceListCache?.clearCache()
            logger.debug("Cleared device cache due to device \(eventType) event")
        }
        
        var deviceCount = 0
        var processedSuccessfully = 0
        var processingErrors = 0
        
        // Optimized notification processing with minimal IOKit calls
        let objectBatch = IOKitObjectBatch()
        var servicesToProcess: [(service: io_service_t, index: Int)] = []
        
        // Collect all services in a single pass to minimize iterator overhead
        var service: io_service_t = ioKit.iteratorNext(iterator)
        while service != 0 {
            servicesToProcess.append((service: service, index: deviceCount))
            objectBatch.add(service)
            deviceCount += 1
            service = ioKit.iteratorNext(iterator)
        }
        
        // Process collected services with optimized batch operations
        if !servicesToProcess.isEmpty {
            logger.debug("Processing \(eventType) notifications in optimized batch", context: [
                "batchSize": servicesToProcess.count,
                "eventType": eventType
            ])
            
            // Process notifications with minimal IOKit overhead
            for (serviceInfo) in servicesToProcess {
                do {
                    if isAddedNotification {
                        try handleDeviceAddedNotificationOptimized(service: serviceInfo.service, batchIndex: serviceInfo.index)
                    } else {
                        handleDeviceRemovedNotificationOptimized(service: serviceInfo.service, batchIndex: serviceInfo.index)
                    }
                    processedSuccessfully += 1
                } catch {
                    logger.warning("Failed to process device \(eventType) notification", context: [
                        "deviceIndex": serviceInfo.index + 1,
                        "error": error.localizedDescription,
                        "eventType": eventType,
                        "batchIndex": serviceInfo.index + 1
                    ])
                    processingErrors += 1
                }
            }
            
            // Batch release all IOKit objects for optimal memory management
            let releaseResults = objectBatch.releaseAll()
            let failedReleases = releaseResults.filter { $0 != KERN_SUCCESS }
            
            if !failedReleases.isEmpty {
                logger.warning("Some IOKit objects failed to release during batch cleanup", context: [
                    "totalObjects": releaseResults.count,
                    "failedReleases": failedReleases.count,
                    "eventType": eventType
                ])
            }
        }
        
        if deviceCount > 0 {
            logger.debug("Completed processing \(eventType) notifications with optimizations", context: [
                "totalNotifications": deviceCount,
                "processedSuccessfully": processedSuccessfully,
                "processingErrors": processingErrors,
                "eventType": eventType,
                "batchProcessing": true,
                "cacheCleared": cacheConfig.enableCaching,
                "optimizationLevel": "enhanced"
            ])
        } else {
            logger.debug("No \(eventType) notifications to process")
        }
    }
    
    // MARK: - Device Notification Handlers
    
    /// Optimized device connection handler with minimal IOKit calls
    private func handleDeviceAddedNotificationOptimized(service: io_service_t, batchIndex: Int) throws {
        logger.debug("Processing device connection notification with minimal IOKit overhead", context: [
            "service": service,
            "batchIndex": batchIndex
        ])
        
        // Extract only essential properties in a single optimized batch to minimize IOKit calls
        let essentialProperties = extractPropertiesBatchOptimal(from: service, keys: [
            "locationID",
            kUSBVendorID,
            kUSBProductID,
            kUSBDeviceClass,
            kUSBDeviceSubClass,
            kUSBDeviceProtocol,
            "USB Address",
            "Speed"
        ])
        
        // Quick validation of essential properties before full device creation
        guard let locationID = essentialProperties["locationID"] as? UInt32,
              let vendorID = essentialProperties[kUSBVendorID] as? UInt16,
              let productID = essentialProperties[kUSBProductID] as? UInt16 else {
            logger.debug("Skipping device connection - missing essential properties", context: [
                "service": service,
                "batchIndex": batchIndex,
                "availableProperties": essentialProperties.keys.sorted()
            ])
            return
        }
        
        // Create device with pre-extracted properties to avoid redundant IOKit calls
        let device = try createUSBDeviceFromPreExtractedProperties(
            service: service,
            properties: essentialProperties,
            locationID: locationID,
            vendorID: vendorID,
            productID: productID
        )
        
        handleSuccessfulDeviceConnection(device: device)
    }
    
    /// Optimized device disconnection handler with minimal IOKit calls
    private func handleDeviceRemovedNotificationOptimized(service: io_service_t, batchIndex: Int) {
        logger.debug("Processing device disconnection notification with minimal IOKit overhead", context: [
            "service": service,
            "batchIndex": batchIndex
        ])
        
        // Extract only locationID for device identification to minimize IOKit calls
        guard let locationID = getUInt32PropertyOptimal(from: service, key: "locationID") else {
            logger.warning("Could not extract locationID from disconnected device", context: [
                "service": service,
                "batchIndex": batchIndex,
                "impact": "Device disconnection event may be lost"
            ])
            return
        }
        
        // Generate device key from locationID without additional IOKit calls
        let busNumber = (locationID >> 24) & 0xFF
        let busID = String(format: "%d", busNumber)
        let deviceAddress = locationID & 0xFF
        let deviceID = String(format: "%d", deviceAddress)
        let deviceKey = "\(busID):\(deviceID)"
        
        logger.debug("Generated device key from locationID for optimized disconnection", context: [
            "locationID": String(format: "0x%08x", locationID),
            "deviceKey": deviceKey,
            "batchIndex": batchIndex
        ])
        
        // Handle disconnection using cached device information
        handleDeviceDisconnectionWithKey(deviceKey: deviceKey)
    }
    
    /// Handle device connection events with comprehensive error recovery
    /// Creates USBDevice from IOKit service and triggers onDeviceConnected callback
    private func handleDeviceAddedNotification(service: io_service_t) throws {
        logger.debug("Processing device connection notification with error recovery", context: [
            "service": service
        ])
        
        // Use retry logic for device creation during notifications
        let deviceResult = try executeWithRetry(operation: "device connection notification", config: .aggressive) {
            return try processDeviceConnectionWithRecovery(service: service)
        }
        
        switch deviceResult {
        case .success(let device):
            handleSuccessfulDeviceConnection(device: device)
            
        case .recovered(let device):
            handleRecoveredDeviceConnection(device: device)
            
        case .failed(let reason):
            logger.warning("Failed to process device connection notification", context: [
                "service": service,
                "reason": reason,
                "impact": "Device connection event will be lost"
            ])
            // Don't throw error for notification failures - log and continue
        }
    }
    
    /// Process device connection with comprehensive error recovery
    private func processDeviceConnectionWithRecovery(service: io_service_t) throws -> DeviceConnectionResult {
        do {
            let device = try createUSBDeviceFromService(service)
            return .success(device)
            
        } catch let error as DeviceDiscoveryError {
            // Attempt recovery based on error type
            switch error {
            case .deviceNotFound(_):
                // Device was removed during notification processing
                logger.debug("Attempting device recovery during connection notification", context: [
                    "error": error.localizedDescription
                ])
                
                if let recoveredDevice = attemptDeviceRecovery(service: service) {
                    return .recovered(recoveredDevice)
                } else {
                    return .failed("Device removed during connection processing and recovery failed")
                }
                
            case .ioKitError(_, _) where isDeviceRemovalError(error):
                // Device was removed during notification processing
                logger.debug("Attempting device recovery during connection notification", context: [
                    "error": error.localizedDescription
                ])
                
                if let recoveredDevice = attemptDeviceRecovery(service: service) {
                    return .recovered(recoveredDevice)
                } else {
                    return .failed("Device removed during connection processing and recovery failed")
                }
                
            case .missingProperty(let property):
                // Try to create device with default values
                logger.debug("Attempting device recovery with missing property during connection", context: [
                    "missingProperty": property
                ])
                
                if let recoveredDevice = attemptDeviceRecoveryWithDefaults(service: service, missingProperty: property) {
                    return .recovered(recoveredDevice)
                } else {
                    return .failed("Missing critical property: \(property)")
                }
                
            default:
                return .failed("Device creation error: \(error.localizedDescription)")
            }
            
        } catch {
            return .failed("Unexpected error: \(error.localizedDescription)")
        }
    }
    
    /// Result type for device connection processing
    private enum DeviceConnectionResult {
        case success(USBDevice)
        case recovered(USBDevice)
        case failed(String)
    }
    
    /// Handle successful device connection
    private func handleSuccessfulDeviceConnection(device: USBDevice) {
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
    }
    
    /// Handle recovered device connection
    private func handleRecoveredDeviceConnection(device: USBDevice) {
        let deviceKey = "\(device.busID):\(device.deviceID)"
        
        // Check if device is already in cache (duplicate notification)
        if connectedDevices[deviceKey] != nil {
            logger.debug("Recovered device connection notification for already cached device", context: [
                "deviceKey": deviceKey,
                "action": "ignoring_duplicate"
            ])
            return
        }
        
        // Cache the device for proper disconnection handling
        connectedDevices[deviceKey] = device
        
        logger.info("USB device connected (recovered from partial failure)", context: [
            "event": "device_connected_recovered",
            "busID": device.busID,
            "deviceID": device.deviceID,
            "deviceKey": deviceKey,
            "vendorID": String(format: "0x%04x", device.vendorID),
            "productID": String(format: "0x%04x", device.productID),
            "availableData": getAvailableDeviceDataDescription(device),
            "cachedDeviceCount": connectedDevices.count,
            "recoveryType": "connection_notification"
        ])
        
        // Trigger the connection callback with recovered device information
        logger.debug("Triggering device connection callback for recovered device")
        onDeviceConnected?(device)
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

