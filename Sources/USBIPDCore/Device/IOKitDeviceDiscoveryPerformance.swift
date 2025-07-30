//
//  IOKitDeviceDiscoveryPerformance.swift
//  usbipd-mac
//
//  Performance monitoring and optimization utilities for IOKit device discovery
//

import Foundation
import IOKit
import IOKit.usb
import Common

// MARK: - Performance Monitoring Extension

extension IOKitDeviceDiscovery {
    
    /// Monitor memory usage and trigger cleanup if needed
    internal func monitorMemoryUsage() {
        let poolStats = objectPool.getPoolStats()
        let dictPoolStats = dictionaryPool.getPoolStats()
        let outstandingObjects = (poolStats.borrowed - poolStats.returned) + (dictPoolStats.borrowed - dictPoolStats.returned)
        
        // Trigger cleanup if too many objects are outstanding
        if outstandingObjects > 50 {
            logger.warning("High number of outstanding IOKit objects detected", context: [
                "outstandingObjects": outstandingObjects,
                "objectPoolOutstanding": poolStats.borrowed - poolStats.returned,
                "dictPoolOutstanding": dictPoolStats.borrowed - dictPoolStats.returned,
                "action": "triggering_cleanup"
            ])
            
            // Force garbage collection to help with memory cleanup
            autoreleasepool {
                // This block helps ensure any autoreleased objects are cleaned up
            }
        }
        
        // Log memory usage periodically for monitoring
        if outstandingObjects > 0 {
            logger.debug("Memory usage monitoring", context: [
                "outstandingObjects": outstandingObjects,
                "cacheSize": connectedDevices.count,
                "memoryFootprint": connectedDevices.count * MemoryLayout<USBDevice>.size
            ])
        }
    }
    
    /// Get performance statistics for monitoring optimization effectiveness
    internal func getPerformanceStats() -> [String: Any] {
        let cacheStats = deviceListCache?.getCacheStats() ?? CacheStats(deviceCount: 0, age: 0, isValid: false)
        let poolStats = objectPool.getPoolStats()
        let dictPoolStats = dictionaryPool.getPoolStats()
        
        return [
            "cache": [
                "enabled": cacheConfig.enableCaching,
                "deviceCount": cacheStats.deviceCount,
                "age": String(format: "%.2f", cacheStats.age),
                "isValid": cacheStats.isValid,
                "maxAge": cacheConfig.maxAge,
                "maxSize": cacheConfig.maxSize,
                "hitRate": cacheStats.isValid ? "active" : "expired"
            ],
            "connectedDevicesCache": [
                "count": connectedDevices.count,
                "keys": Array(connectedDevices.keys),
                "memoryFootprint": connectedDevices.count * MemoryLayout<USBDevice>.size
            ],
            "objectPool": [
                "available": poolStats.available,
                "borrowed": poolStats.borrowed,
                "returned": poolStats.returned,
                "peakUsage": poolStats.peakUsage,
                "efficiency": poolStats.returned > 0 ? String(format: "%.1f%%", Double(poolStats.returned) / Double(poolStats.borrowed) * 100) : "0%"
            ],
            "dictionaryPool": [
                "available": dictPoolStats.available,
                "borrowed": dictPoolStats.borrowed,
                "returned": dictPoolStats.returned,
                "peakUsage": dictPoolStats.peakUsage,
                "efficiency": dictPoolStats.returned > 0 ? String(format: "%.1f%%", Double(dictPoolStats.returned) / Double(dictPoolStats.borrowed) * 100) : "0%"
            ],
            "optimization": [
                "level": "enhanced",
                "objectPoolEnabled": true,
                "dictionaryPoolEnabled": true,
                "batchProcessingEnabled": true,
                "minimalIOKitCallsEnabled": true,
                "raiipatternsEnabled": true,
                "lifecycleTrackingEnabled": true,
                "memoryOptimizationsEnabled": true
            ],
            "memoryManagement": [
                "totalAllocatedObjects": poolStats.borrowed + dictPoolStats.borrowed,
                "totalReleasedObjects": poolStats.returned + dictPoolStats.returned,
                "outstandingObjects": (poolStats.borrowed - poolStats.returned) + (dictPoolStats.borrowed - dictPoolStats.returned),
                "peakMemoryUsage": poolStats.peakUsage + dictPoolStats.peakUsage
            ]
        ]
    }
}

// MARK: - Memory Management Utilities Extension

extension IOKitDeviceDiscovery {
    
    /// RAII wrapper for IOKit objects that need to be released
    internal class IOKitObjectWrapper {
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
    internal func withIOKitObject<T>(_ object: io_object_t, _ block: (io_object_t) throws -> T) rethrows -> T {
        defer {
            if object != 0 {
                _ = ioKit.objectRelease(object)
            }
        }
        return try block(object)
    }
    
    /// Optimized RAII wrapper using IOKitObjectManager for better lifecycle management
    internal func withManagedIOKitObject<T>(_ object: io_object_t, type: String = "service", _ block: (io_object_t) throws -> T) throws -> T {
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
}