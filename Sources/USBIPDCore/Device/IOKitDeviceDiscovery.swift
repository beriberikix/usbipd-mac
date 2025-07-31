//
//  IOKitDeviceDiscoveryCore.swift
//  usbipd-mac
//
//  Core IOKit device discovery implementation - minimal main class
//

import Foundation
import IOKit
import IOKit.usb
import Common

/// IOKit-based implementation of USB device discovery
public class IOKitDeviceDiscovery: DeviceDiscovery {
    
    // MARK: - Properties
    
    public var onDeviceConnected: ((USBDevice) -> Void)?
    public var onDeviceDisconnected: ((USBDevice) -> Void)?
    
    internal var notificationPort: IONotificationPortRef?
    internal var addedIterator: io_iterator_t = 0
    internal var removedIterator: io_iterator_t = 0
    internal var isMonitoring: Bool = false
    
    // Cache of connected devices for proper disconnection callbacks
    internal var connectedDevices: [String: USBDevice] = [:]
    
    // MARK: - Performance Optimization Properties
    
    /// Device list cache to avoid repeated IOKit queries
    internal var deviceListCache: DeviceListCache?
    
    /// Cache configuration for device list caching
    internal let cacheConfig: DeviceCacheConfiguration
    
    /// IOKit object pool for reusing common objects
    internal let objectPool: IOKitObjectPool
    
    /// CF dictionary pool for reusing dictionary objects
    internal let dictionaryPool: CFDictionaryPool
    
    internal let logger: Logger
    internal let queue: DispatchQueue
    internal let ioKit: IOKitInterface
    
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
    
    // MARK: - DeviceDiscovery Protocol
    
    public func discoverDevices() throws -> [USBDevice] {
        return try queue.sync {
            return try discoverDevicesInternal()
        }
    }
    
    public func getDevice(busID: String, deviceID: String) throws -> USBDevice? {
        return try queue.sync {
            return try getDeviceInternal(busID: busID, deviceID: deviceID)
        }
    }
    
    // Implementation methods are in separate extension files:
    // - IOKitDeviceDiscoveryImplementation.swift: Core device discovery logic
    // - IOKitDeviceDiscoveryNotifications.swift: Notification system
    // - IOKitDeviceDiscoveryPerformance.swift: Performance monitoring
    // - IOKitErrorHandling.swift: Error handling utilities
    // - IOKitDeviceDiscoverySupport.swift: Supporting types and utilities
}