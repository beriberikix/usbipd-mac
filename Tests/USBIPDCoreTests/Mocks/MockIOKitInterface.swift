// MockIOKitInterface.swift
// Mock IOKit interface for testing IOKitDeviceDiscovery

import Foundation
import IOKit
import IOKit.usb
@testable import USBIPDCore

// MARK: - Mock IOKit Implementation

/// Mock IOKit implementation for unit testing
public class MockIOKitInterface: IOKitInterface {
    
    // MARK: - Mock State
    
    /// Mock devices that will be returned by the iterator
    public var mockDevices: [MockUSBDevice] = []
    
    /// Controls whether service matching should fail
    public var shouldFailServiceMatching = false
    
    /// Controls whether getting matching services should fail
    public var shouldFailGetMatchingServices = false
    public var getMatchingServicesError: kern_return_t = KERN_FAILURE
    
    /// Controls whether notification port creation should fail
    public var shouldFailNotificationPortCreate = false
    
    /// Controls whether adding notifications should fail
    public var shouldFailAddNotification = false
    public var addNotificationError: kern_return_t = KERN_FAILURE
    
    /// Track method calls for verification
    public var serviceMatchingCalls: [String] = []
    public var serviceGetMatchingServicesCalls: [(mach_port_t, CFDictionary)] = []
    public var iteratorNextCalls: [io_iterator_t] = []
    public var objectReleaseCalls: [io_object_t] = []
    public var registryEntryCreateCFPropertyCalls: [(io_registry_entry_t, String)] = []
    public var notificationPortCreateCalls: [mach_port_t] = []
    public var serviceAddMatchingNotificationCalls: [(IONotificationPortRef, String)] = []
    public var notificationPortGetRunLoopSourceCalls: [IONotificationPortRef] = []
    public var notificationPortSetDispatchQueueCalls: [(IONotificationPortRef, DispatchQueue?)] = []
    public var notificationPortDestroyCalls: [IONotificationPortRef] = []
    
    // MARK: - Mock Iterator State
    
    private var currentIteratorIndex = 0
    private var mockIteratorValue: io_iterator_t = 1000
    private var mockServiceValue: io_service_t = 2000
    
    public init() {}
    
    // MARK: - Reset Methods
    
    /// Reset all mock state for a fresh test
    public func reset() {
        mockDevices.removeAll()
        shouldFailServiceMatching = false
        shouldFailGetMatchingServices = false
        getMatchingServicesError = KERN_FAILURE
        shouldFailNotificationPortCreate = false
        shouldFailAddNotification = false
        addNotificationError = KERN_FAILURE
        
        serviceMatchingCalls.removeAll()
        serviceGetMatchingServicesCalls.removeAll()
        iteratorNextCalls.removeAll()
        objectReleaseCalls.removeAll()
        registryEntryCreateCFPropertyCalls.removeAll()
        notificationPortCreateCalls.removeAll()
        serviceAddMatchingNotificationCalls.removeAll()
        notificationPortGetRunLoopSourceCalls.removeAll()
        notificationPortSetDispatchQueueCalls.removeAll()
        notificationPortDestroyCalls.removeAll()
        
        currentIteratorIndex = 0
    }
    
    // MARK: - IOKitInterface Implementation
    
    public func serviceMatching(_ name: String) -> CFMutableDictionary? {
        serviceMatchingCalls.append(name)
        
        if shouldFailServiceMatching {
            return nil
        }
        
        // Return a mock dictionary
        var keyCallbacks = kCFTypeDictionaryKeyCallBacks
        var valueCallbacks = kCFTypeDictionaryValueCallBacks
        let dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &keyCallbacks, &valueCallbacks)
        CFDictionarySetValue(dict, Unmanaged.passRetained("IOProviderClass" as CFString).toOpaque(), Unmanaged.passRetained(name as CFString).toOpaque())
        return dict
    }
    
    public func serviceGetMatchingServices(_ masterPort: mach_port_t, _ matching: CFDictionary, _ existing: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t {
        serviceGetMatchingServicesCalls.append((masterPort, matching))
        
        if shouldFailGetMatchingServices {
            return getMatchingServicesError
        }
        
        // Set up iterator for mock devices
        currentIteratorIndex = 0
        existing.pointee = mockIteratorValue
        return KERN_SUCCESS
    }
    
    public func iteratorNext(_ iterator: io_iterator_t) -> io_service_t {
        iteratorNextCalls.append(iterator)
        
        // Return mock services based on current index
        if currentIteratorIndex < mockDevices.count {
            let service = io_service_t(mockServiceValue + UInt32(currentIteratorIndex))
            currentIteratorIndex += 1
            return service
        }
        
        // End of iteration
        return 0
    }
    
    public func objectRelease(_ object: io_object_t) -> kern_return_t {
        objectReleaseCalls.append(object)
        return KERN_SUCCESS
    }
    
    public func registryEntryCreateCFProperty(_ entry: io_registry_entry_t, _ key: CFString, _ allocator: CFAllocator?, _ options: IOOptionBits) -> Unmanaged<CFTypeRef>? {
        let keyString = key as String
        registryEntryCreateCFPropertyCalls.append((entry, keyString))
        
        // Find the mock device for this service
        let serviceIndex = Int(entry - mockServiceValue)
        guard serviceIndex >= 0 && serviceIndex < mockDevices.count else {
            return nil
        }
        
        let mockDevice = mockDevices[serviceIndex]
        return mockDevice.getProperty(key: keyString)
    }
    
    public func notificationPortCreate(_ masterPort: mach_port_t) -> IONotificationPortRef? {
        notificationPortCreateCalls.append(masterPort)
        
        if shouldFailNotificationPortCreate {
            return nil
        }
        
        // Return a mock notification port (using a dummy pointer)
        return OpaquePointer(bitPattern: 0x12345678)
    }
    
    public func serviceAddMatchingNotification(_ notifyPort: IONotificationPortRef, _ notificationType: String, _ matching: CFDictionary, _ callback: IOServiceMatchingCallback?, _ refCon: UnsafeMutableRawPointer?, _ notification: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t {
        serviceAddMatchingNotificationCalls.append((notifyPort, notificationType))
        
        if shouldFailAddNotification {
            return addNotificationError
        }
        
        // Set up a mock iterator for notifications
        notification.pointee = io_iterator_t(mockIteratorValue + 100)
        return KERN_SUCCESS
    }
    
    public func notificationPortGetRunLoopSource(_ notify: IONotificationPortRef) -> CFRunLoopSource? {
        notificationPortGetRunLoopSourceCalls.append(notify)
        // Return a mock run loop source
        return CFRunLoopSourceCreate(kCFAllocatorDefault, 0, nil)
    }
    
    public func notificationPortSetDispatchQueue(_ notify: IONotificationPortRef, _ queue: DispatchQueue?) {
        notificationPortSetDispatchQueueCalls.append((notify, queue))
        // Mock implementation - nothing to do
    }
    
    public func notificationPortDestroy(_ notify: IONotificationPortRef) {
        notificationPortDestroyCalls.append(notify)
        // Mock implementation - nothing to do
    }
}

// MARK: - Mock USB Device

/// Mock USB device for testing
public struct MockUSBDevice {
    public let vendorID: UInt16
    public let productID: UInt16
    public let deviceClass: UInt8
    public let deviceSubClass: UInt8
    public let deviceProtocol: UInt8
    public let speed: UInt8
    public let manufacturerString: String?
    public let productString: String?
    public let serialNumberString: String?
    public let locationID: UInt32
    
    /// Properties that should be missing (for testing error cases)
    public let missingProperties: Set<String>
    
    /// Properties that should have invalid types (for testing error cases)
    public let invalidTypeProperties: Set<String>
    
    public init(
        vendorID: UInt16,
        productID: UInt16,
        deviceClass: UInt8 = 0x09,
        deviceSubClass: UInt8 = 0x00,
        deviceProtocol: UInt8 = 0x00,
        speed: UInt8 = 2, // Full speed
        manufacturerString: String? = nil,
        productString: String? = nil,
        serialNumberString: String? = nil,
        locationID: UInt32 = 0x14100000,
        missingProperties: Set<String> = [],
        invalidTypeProperties: Set<String> = []
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.deviceClass = deviceClass
        self.deviceSubClass = deviceSubClass
        self.deviceProtocol = deviceProtocol
        self.speed = speed
        self.manufacturerString = manufacturerString
        self.productString = productString
        self.serialNumberString = serialNumberString
        self.locationID = locationID
        self.missingProperties = missingProperties
        self.invalidTypeProperties = invalidTypeProperties
    }
    
    /// Get property value for a given key
    func getProperty(key: String) -> Unmanaged<CFTypeRef>? {
        // Check if property should be missing
        if missingProperties.contains(key) {
            return nil
        }
        
        // Check if property should have invalid type
        if invalidTypeProperties.contains(key) {
            // Return a string instead of expected number type
            return Unmanaged.passRetained("invalid_type" as CFString)
        }
        
        switch key {
        case kUSBVendorID:
            return Unmanaged.passRetained(NSNumber(value: vendorID))
        case kUSBProductID:
            return Unmanaged.passRetained(NSNumber(value: productID))
        case kUSBDeviceClass:
            return Unmanaged.passRetained(NSNumber(value: deviceClass))
        case kUSBDeviceSubClass:
            return Unmanaged.passRetained(NSNumber(value: deviceSubClass))
        case kUSBDeviceProtocol:
            return Unmanaged.passRetained(NSNumber(value: deviceProtocol))
        case "Speed", "Device Speed":
            return Unmanaged.passRetained(NSNumber(value: speed))
        case "USB Vendor Name", "Manufacturer":
            if let manufacturer = manufacturerString {
                return Unmanaged.passRetained(manufacturer as CFString)
            }
            return nil
        case "USB Product Name", "Product":
            if let product = productString {
                return Unmanaged.passRetained(product as CFString)
            }
            return nil
        case "USB Serial Number", "Serial Number":
            if let serial = serialNumberString {
                return Unmanaged.passRetained(serial as CFString)
            }
            return nil
        case "locationID":
            return Unmanaged.passRetained(NSNumber(value: locationID))
        default:
            return nil
        }
    }
}