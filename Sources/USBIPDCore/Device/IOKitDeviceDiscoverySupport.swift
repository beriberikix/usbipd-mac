//
//  IOKitDeviceDiscoverySupport.swift
//  usbipd-mac
//
//  Supporting types and utilities for IOKit device discovery
//

import Foundation
import IOKit
import IOKit.usb
import Common

// MARK: - Supporting Types

/// Cache statistics structure
internal struct CacheStats {
    let deviceCount: Int
    let age: TimeInterval
    let isValid: Bool
}

/// Pool statistics structure
internal struct PoolStats {
    let available: Int
    let borrowed: Int
    let returned: Int
    let peakUsage: Int
}

/// Object lifecycle information structure
internal struct LifecycleInfo {
    let age: TimeInterval
    let isReleased: Bool
    let type: String
}

/// Internal structure to hold extracted device properties
internal struct DeviceProperties {
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

// MARK: - Performance Optimization Types

/// Configuration for device list caching
internal struct DeviceCacheConfiguration {
    let maxAge: TimeInterval
    let maxSize: Int
    let enableCaching: Bool
    
    static let `default` = DeviceCacheConfiguration(
        maxAge: 2.0,        // Cache for 2 seconds
        maxSize: 100,       // Maximum 100 cached devices
        enableCaching: true
    )
    
    static let aggressive = DeviceCacheConfiguration(
        maxAge: 5.0,        // Cache for 5 seconds
        maxSize: 200,       // Maximum 200 cached devices
        enableCaching: true
    )
    
    static let disabled = DeviceCacheConfiguration(
        maxAge: 0,
        maxSize: 0,
        enableCaching: false
    )
}

/// Device list cache with automatic expiration
internal class DeviceListCache {
    private let config: DeviceCacheConfiguration
    private var cachedDevices: [USBDevice] = []
    private var cacheTimestamp: Date = Date.distantPast
    private let lock = NSLock()
    
    init(config: DeviceCacheConfiguration) {
        self.config = config
    }
    
    /// Check if cache is valid and not expired
    var isValid: Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard config.enableCaching else { return false }
        
        let age = Date().timeIntervalSince(cacheTimestamp)
        return age < config.maxAge && !cachedDevices.isEmpty
    }
    
    /// Get cached devices if valid
    func getCachedDevices() -> [USBDevice]? {
        lock.lock()
        defer { lock.unlock() }
        
        guard isValid else { return nil }
        return cachedDevices
    }
    
    /// Update cache with new device list
    func updateCache(with devices: [USBDevice]) {
        lock.lock()
        defer { lock.unlock() }
        
        guard config.enableCaching else { return }
        
        // Limit cache size to prevent memory issues
        let limitedDevices = Array(devices.prefix(config.maxSize))
        
        cachedDevices = limitedDevices
        cacheTimestamp = Date()
    }
    
    /// Clear the cache
    func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        
        cachedDevices.removeAll()
        cacheTimestamp = Date.distantPast
    }
    
    /// Get cache statistics for monitoring
    func getCacheStats() -> CacheStats {
        lock.lock()
        defer { lock.unlock() }
        
        let age = Date().timeIntervalSince(cacheTimestamp)
        return CacheStats(deviceCount: cachedDevices.count, age: age, isValid: isValid)
    }
}

/// Pool for reusing IOKit objects to reduce allocation overhead
internal class IOKitObjectPool {
    private var availableIterators: [io_iterator_t] = []
    private let lock = NSLock()
    private let maxPoolSize: Int
    private var totalBorrowed: Int = 0
    private var totalReturned: Int = 0
    private var peakUsage: Int = 0
    
    init(maxPoolSize: Int = 10) {
        self.maxPoolSize = maxPoolSize
    }
    
    /// Get an iterator from the pool or create a new one
    func borrowIterator() -> io_iterator_t? {
        lock.lock()
        defer { lock.unlock() }
        
        totalBorrowed += 1
        let currentUsage = totalBorrowed - totalReturned
        peakUsage = max(peakUsage, currentUsage)
        
        if !availableIterators.isEmpty {
            return availableIterators.removeLast()
        }
        
        return nil // Caller should create new iterator
    }
    
    /// Return an iterator to the pool for reuse
    func returnIterator(_ iterator: io_iterator_t) {
        lock.lock()
        defer { lock.unlock() }
        
        totalReturned += 1
        
        guard iterator != 0 && availableIterators.count < maxPoolSize else {
            // Pool is full or invalid iterator, release it
            IOObjectRelease(iterator)
            return
        }
        
        availableIterators.append(iterator)
    }
    
    /// Get pool statistics for monitoring
    func getPoolStats() -> PoolStats {
        lock.lock()
        defer { lock.unlock() }
        
        return PoolStats(
            available: availableIterators.count,
            borrowed: totalBorrowed,
            returned: totalReturned,
            peakUsage: peakUsage
        )
    }
    
    /// Clear the pool and release all objects
    func clearPool() {
        lock.lock()
        defer { lock.unlock() }
        
        for iterator in availableIterators {
            IOObjectRelease(iterator)
        }
        availableIterators.removeAll()
        totalBorrowed = 0
        totalReturned = 0
        peakUsage = 0
    }
    
    deinit {
        clearPool()
    }
}

/// RAII wrapper for IOKit objects with automatic cleanup and lifecycle tracking
internal class IOKitObjectManager {
    private let object: io_object_t
    private var isReleased = false
    private let lock = NSLock()
    private let creationTime: Date
    private let objectType: String
    
    init(_ object: io_object_t, type: String = "unknown") {
        self.object = object
        self.objectType = type
        self.creationTime = Date()
    }
    
    var value: io_object_t {
        lock.lock()
        defer { lock.unlock() }
        return isReleased ? 0 : object
    }
    
    /// Get object lifecycle information
    var lifecycleInfo: LifecycleInfo {
        lock.lock()
        defer { lock.unlock() }
        
        return LifecycleInfo(
            age: Date().timeIntervalSince(creationTime),
            isReleased: isReleased,
            type: objectType
        )
    }
    
    /// Manually release the object (useful for early cleanup)
    func release() -> kern_return_t {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isReleased && object != 0 else {
            return KERN_SUCCESS
        }
        
        isReleased = true
        let result = IOObjectRelease(object)
        
        // Log long-lived objects for memory management monitoring
        let age = Date().timeIntervalSince(creationTime)
        if age > 10.0 { // Objects held for more than 10 seconds
            print("IOKit object held for \(String(format: "%.2f", age))s before release: \(objectType)")
        }
        
        return result
    }
    
    deinit {
        if !isReleased && object != 0 {
            let age = Date().timeIntervalSince(creationTime)
            if age > 5.0 { // Log objects that lived longer than expected
                print("IOKit object auto-released after \(String(format: "%.2f", age))s: \(objectType)")
            }
            IOObjectRelease(object)
        }
    }
}

// MARK: - CF Dictionary Pool

/// Pool for reusing CF dictionaries to reduce allocation overhead
internal class CFDictionaryPool {
    private var availableDictionaries: [CFMutableDictionary] = []
    private let lock = NSLock()
    private let maxPoolSize: Int
    private var totalBorrowed: Int = 0
    private var totalReturned: Int = 0
    private var peakUsage: Int = 0
    
    init(maxPoolSize: Int = 10) {
        self.maxPoolSize = maxPoolSize
    }
    
    /// Get a dictionary from the pool or create a new one
    func borrowDictionary() -> CFMutableDictionary? {
        lock.lock()
        defer { lock.unlock() }
        
        totalBorrowed += 1
        let currentUsage = totalBorrowed - totalReturned
        peakUsage = max(peakUsage, currentUsage)
        
        if !availableDictionaries.isEmpty {
            let dict = availableDictionaries.removeLast()
            CFDictionaryRemoveAllValues(dict) // Clear for reuse
            return dict
        }
        
        return nil // Caller should create new dictionary
    }
    
    /// Return a dictionary to the pool for reuse
    func returnDictionary(_ dictionary: CFMutableDictionary) {
        lock.lock()
        defer { lock.unlock() }
        
        totalReturned += 1
        
        guard availableDictionaries.count < maxPoolSize else {
            // Pool is full, don't store it
            return
        }
        
        availableDictionaries.append(dictionary)
    }
    
    /// Get pool statistics for monitoring
    func getPoolStats() -> PoolStats {
        lock.lock()
        defer { lock.unlock() }
        
        return PoolStats(
            available: availableDictionaries.count,
            borrowed: totalBorrowed,
            returned: totalReturned,
            peakUsage: peakUsage
        )
    }
    
    /// Clear the pool
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

// MARK: - Error Recovery Configuration

/// Configuration for retry logic during IOKit operations
internal struct RetryConfiguration {
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