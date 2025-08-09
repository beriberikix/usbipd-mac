// MockIOKitInterface.swift
// Mock IOKit interface for testing IOKitDeviceDiscovery

import Foundation
import IOKit
import IOKit.usb
import Common
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
    
    // MARK: - Notification Simulation State
    
    /// Controls whether notification setup should fail
    public var shouldFailNotificationSetup = false
    public var notificationSetupError: Error?
    
    /// Stored callbacks for notification simulation
    private var deviceAddedCallback: IOServiceMatchingCallback?
    private var deviceRemovedCallback: IOServiceMatchingCallback?
    private var callbackRefCon: UnsafeMutableRawPointer?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    
    /// Devices to simulate in notifications
    private var notificationDevices: [MockUSBDevice] = []
    
    /// Devices to return for notification iterators
    private var addedNotificationDevices: [MockUSBDevice] = []
    private var removedNotificationDevices: [MockUSBDevice] = []
    
    /// Current index for notification iterators
    private var addedNotificationIndex = 0
    private var removedNotificationIndex = 0
    
    /// Error to simulate during device discovery operations
    private var simulatedDiscoveryError: Error?
    
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
        shouldFailNotificationSetup = false
        notificationSetupError = nil
        deviceAddedCallback = nil
        deviceRemovedCallback = nil
        callbackRefCon = nil
        addedIterator = 0
        removedIterator = 0
        notificationDevices.removeAll()
        addedNotificationDevices.removeAll()
        removedNotificationDevices.removeAll()
        addedNotificationIndex = 0
        removedNotificationIndex = 0
        simulatedDiscoveryError = nil
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
    
    public func serviceGetMatchingServices(_ mainPort: mach_port_t, _ matching: CFDictionary, _ existing: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t {
        serviceGetMatchingServicesCalls.append((mainPort, matching))
        
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
        
        // Handle notification iterators
        if iterator == addedIterator {
            print("DEBUG: iteratorNext called for addedIterator \(iterator), index: \(addedNotificationIndex), devices: \(addedNotificationDevices.count)")
            if addedNotificationIndex < addedNotificationDevices.count {
                let service = io_service_t(mockServiceValue + 1000 + UInt32(addedNotificationIndex))
                addedNotificationIndex += 1
                print("DEBUG: Returning service \(service) for added notification")
                return service
            }
            print("DEBUG: No more added notification devices to return")
            return 0
        }
        
        if iterator == removedIterator {
            print("DEBUG: iteratorNext called for removedIterator \(iterator), index: \(removedNotificationIndex), devices: \(removedNotificationDevices.count)")
            if removedNotificationIndex < removedNotificationDevices.count {
                let service = io_service_t(mockServiceValue + 2000 + UInt32(removedNotificationIndex))
                removedNotificationIndex += 1
                print("DEBUG: Returning service \(service) for removed notification")
                return service
            }
            print("DEBUG: No more removed notification devices to return")
            return 0
        }
        
        // Handle regular discovery iterator
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
        
        // Handle notification services
        if entry >= mockServiceValue + 1000 && entry < mockServiceValue + 2000 {
            // Added notification device
            let deviceIndex = Int(entry - mockServiceValue - 1000)
            if deviceIndex >= 0 && deviceIndex < addedNotificationDevices.count {
                let mockDevice = addedNotificationDevices[deviceIndex]
                return mockDevice.getProperty(key: keyString)
            }
        } else if entry >= mockServiceValue + 2000 && entry < mockServiceValue + 3000 {
            // Removed notification device
            let deviceIndex = Int(entry - mockServiceValue - 2000)
            if deviceIndex >= 0 && deviceIndex < removedNotificationDevices.count {
                let mockDevice = removedNotificationDevices[deviceIndex]
                return mockDevice.getProperty(key: keyString)
            }
        } else {
            // Regular discovery device
            let serviceIndex = Int(entry - mockServiceValue)
            if serviceIndex >= 0 && serviceIndex < mockDevices.count {
                let mockDevice = mockDevices[serviceIndex]
                return mockDevice.getProperty(key: keyString)
            }
        }
        
        return nil
    }
    
    public func notificationPortCreate(_ mainPort: mach_port_t) -> IONotificationPortRef? {
        notificationPortCreateCalls.append(mainPort)
        
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
        
        // Store callback and refcon for simulation
        if notificationType == kIOFirstMatchNotification {
            deviceAddedCallback = callback
            addedIterator = io_iterator_t(mockIteratorValue + 100)
            notification.pointee = addedIterator
        } else if notificationType == kIOTerminatedNotification {
            deviceRemovedCallback = callback
            removedIterator = io_iterator_t(mockIteratorValue + 200)
            notification.pointee = removedIterator
        }
        
        callbackRefCon = refCon
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
    
    // MARK: - Simulation Methods for Testing
    
    /// Simulate a device connection notification
    public func simulateDeviceConnection(_ device: USBDevice) {
        // Convert USBDevice to MockUSBDevice for simulation
        let mockDevice = MockUSBDevice(
            vendorID: device.vendorID,
            productID: device.productID,
            deviceClass: device.deviceClass,
            deviceSubClass: device.deviceSubClass,
            deviceProtocol: device.deviceProtocol,
            speed: UInt8(device.speed.rawValue),
            manufacturerString: device.manufacturerString,
            productString: device.productString,
            serialNumberString: device.serialNumberString,
            locationID: UInt32((Int(device.busID) ?? 20) << 24) | UInt32(Int(device.deviceID) ?? 0)
        )
        
        // Add to notification devices
        notificationDevices.append(mockDevice)
        
        // Set up the notification device and reset index before triggering callback
        addedNotificationDevices = [mockDevice] // Replace with single device for this notification
        addedNotificationIndex = 0 // Reset index for new notification
        
        // Trigger callback if set
        if let callback = deviceAddedCallback {
            callback(callbackRefCon, addedIterator)
        }
    }
    
    /// Simulate a device disconnection notification
    public func simulateDeviceDisconnection(_ device: USBDevice) {
        // Convert USBDevice to MockUSBDevice for simulation
        let mockDevice = MockUSBDevice(
            vendorID: device.vendorID,
            productID: device.productID,
            deviceClass: device.deviceClass,
            deviceSubClass: device.deviceSubClass,
            deviceProtocol: device.deviceProtocol,
            speed: UInt8(device.speed.rawValue),
            manufacturerString: device.manufacturerString,
            productString: device.productString,
            serialNumberString: device.serialNumberString,
            locationID: UInt32((Int(device.busID) ?? 20) << 24) | UInt32(Int(device.deviceID) ?? 0)
        )
        
        // Remove from notification devices
        notificationDevices.removeAll { existingDevice in
            existingDevice.vendorID == device.vendorID &&
            existingDevice.productID == device.productID &&
            existingDevice.locationID == mockDevice.locationID
        }
        
        // Set up the notification device and reset index before triggering callback
        removedNotificationDevices = [mockDevice] // Replace with single device for this notification
        removedNotificationIndex = 0 // Reset index for new notification
        
        // Trigger callback if set
        if let callback = deviceRemovedCallback {
            callback(callbackRefCon, removedIterator)
        }
    }
    
    /// Simulate a device discovery error
    public func simulateDeviceDiscoveryError(_ error: Error) {
        simulatedDiscoveryError = error
        // In a real implementation, this would trigger error handling in the device discovery
        // For testing purposes, we'll store the error and let tests verify it's handled
    }
    
    /// Get the simulated discovery error (for test verification)
    public func getSimulatedDiscoveryError() -> Error? {
        return simulatedDiscoveryError
    }
    
    /// Clear the simulated discovery error
    public func clearSimulatedDiscoveryError() {
        simulatedDiscoveryError = nil
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
        case "IOObjectClass":
            return Unmanaged.passRetained("IOUSBDevice" as CFString)
        case "USB Address":
            return Unmanaged.passRetained(NSNumber(value: UInt8(locationID & 0xFF)))
        default:
            return nil
        }
    }
}