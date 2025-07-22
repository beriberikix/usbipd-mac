// IOKitDeviceDiscovery.swift
// IOKit-based USB device discovery implementation

import Foundation
import IOKit
import IOKit.usb

/// IOKit-based implementation of USB device discovery
public class IOKitDeviceDiscovery: DeviceDiscovery {
    
    // MARK: - Properties
    
    public var onDeviceConnected: ((USBDevice) -> Void)?
    public var onDeviceDisconnected: ((USBDevice) -> Void)?
    
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    
    // MARK: - Initialization
    
    public init() {}
    
    deinit {
        stopNotifications()
    }
    
    // MARK: - DeviceDiscovery Protocol
    
    public func discoverDevices() throws -> [USBDevice] {
        var devices: [USBDevice] = []
        
        // Create matching dictionary for USB devices
        guard let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) else {
            throw DeviceDiscoveryError.failedToCreateMatchingDictionary
        }
        
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator)
        
        guard result == KERN_SUCCESS else {
            throw DeviceDiscoveryError.failedToGetMatchingServices(result)
        }
        
        defer {
            IOObjectRelease(iterator)
        }
        
        var service: io_service_t = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            
            do {
                let device = try createUSBDevice(from: service)
                devices.append(device)
            } catch {
                // Log error but continue with other devices
                print("Warning: Failed to create USB device from service: \(error)")
            }
        }
        
        return devices
    }
    
    public func getDevice(busID: String, deviceID: String) throws -> USBDevice? {
        let devices = try discoverDevices()
        return devices.first { $0.busID == busID && $0.deviceID == deviceID }
    }
    
    // MARK: - Private Methods
    
    private func createUSBDevice(from service: io_service_t) throws -> USBDevice {
        // Extract device properties from IOKit service
        let vendorID = try getUInt16Property(from: service, key: kUSBVendorID)
        let productID = try getUInt16Property(from: service, key: kUSBProductID)
        let deviceClass = try getUInt8Property(from: service, key: kUSBDeviceClass)
        let deviceSubClass = try getUInt8Property(from: service, key: kUSBDeviceSubClass)
        let deviceProtocol = try getUInt8Property(from: service, key: kUSBDeviceProtocol)
        let speed = getUSBSpeed(from: service)
        
        // Generate bus and device IDs
        let busID = try getBusID(from: service)
        let deviceID = try getDeviceID(from: service)
        
        // Extract string descriptors
        let manufacturerString = getStringProperty(from: service, key: "USB Vendor Name")
        let productString = getStringProperty(from: service, key: "USB Product Name")
        let serialNumberString = getStringProperty(from: service, key: "USB Serial Number")
        
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
    
    private func getUInt16Property(from service: io_service_t, key: String) throws -> UInt16 {
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            throw DeviceDiscoveryError.missingProperty(key)
        }
        
        guard let number = property as? NSNumber else {
            throw DeviceDiscoveryError.invalidPropertyType(key)
        }
        
        return number.uint16Value
    }
    
    private func getUInt8Property(from service: io_service_t, key: String) throws -> UInt8 {
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            throw DeviceDiscoveryError.missingProperty(key)
        }
        
        guard let number = property as? NSNumber else {
            throw DeviceDiscoveryError.invalidPropertyType(key)
        }
        
        return number.uint8Value
    }
    
    private func getStringProperty(from service: io_service_t, key: String) -> String? {
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        
        return property as? String
    }
    
    private func getUSBSpeed(from service: io_service_t) -> USBSpeed {
        // Try to get speed property, default to unknown if not available
        guard let property = IORegistryEntryCreateCFProperty(service, "Speed" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let number = property as? NSNumber else {
            return .unknown
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
    
    private func getBusID(from service: io_service_t) throws -> String {
        // Get the location ID which contains bus information
        let locationID = try getUInt32Property(from: service, key: "locationID")
        let busNumber = (locationID >> 24) & 0xFF
        return String(format: "%d", busNumber)
    }
    
    private func getDeviceID(from service: io_service_t) throws -> String {
        // Get the address on the bus
        let address = try getUInt8Property(from: service, key: "USB Address")
        return String(format: "%d", address)
    }
    
    private func getUInt32Property(from service: io_service_t, key: String) throws -> UInt32 {
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            throw DeviceDiscoveryError.missingProperty(key)
        }
        
        guard let number = property as? NSNumber else {
            throw DeviceDiscoveryError.invalidPropertyType(key)
        }
        
        return number.uint32Value
    }
    
    private func getUInt32PropertyOptional(from service: io_service_t, key: String) -> UInt32? {
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let number = property as? NSNumber else {
            return nil
        }
        
        return number.uint32Value
    }
    
    private func getUInt8PropertyOptional(from service: io_service_t, key: String) -> UInt8? {
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let number = property as? NSNumber else {
            return nil
        }
        
        return number.uint8Value
    }
    
    // MARK: - Notification System
    
    public func startNotifications() throws {
        guard notificationPort == nil else {
            return // Already started
        }
        
        // Create notification port
        notificationPort = IONotificationPortCreate(kIOMasterPortDefault)
        guard let port = notificationPort else {
            throw DeviceDiscoveryError.failedToCreateNotificationPort
        }
        
        // Add notification port to run loop
        let runLoopSource = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue()
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.defaultMode)
        }
        
        // Set up device added notifications
        let addedMatchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        let addedResult = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            addedMatchingDict,
            deviceAddedCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &addedIterator
        )
        
        guard addedResult == KERN_SUCCESS else {
            throw DeviceDiscoveryError.failedToAddNotification(addedResult)
        }
        
        // Set up device removed notifications
        let removedMatchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        let removedResult = IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            removedMatchingDict,
            deviceRemovedCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &removedIterator
        )
        
        guard removedResult == KERN_SUCCESS else {
            throw DeviceDiscoveryError.failedToAddNotification(removedResult)
        }
        
        // Consume initial notifications
        consumeIterator(addedIterator, isAddedNotification: true)
        consumeIterator(removedIterator, isAddedNotification: false)
    }
    
    public func stopNotifications() {
        if let port = notificationPort {
            if let runLoopSource = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.defaultMode)
            }
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
        
        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }
        
        if removedIterator != 0 {
            IOObjectRelease(removedIterator)
            removedIterator = 0
        }
    }
    
    // Changed from private to internal for callback access
    func consumeIterator(_ iterator: io_iterator_t, isAddedNotification: Bool) {
        var service: io_service_t = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            
            if isAddedNotification {
                do {
                    let device = try createUSBDevice(from: service)
                    onDeviceConnected?(device)
                } catch {
                    print("Warning: Failed to create USB device from added notification: \(error)")
                }
            } else {
                // For removed notifications, we don't have full device info
                // This is a limitation of the current approach
                // We'll need to improve this to get the device info before it's removed
                // For now, we'll create a minimal device with just the location ID
                // Try to extract minimal information for device identification
                if let locationID = getUInt32PropertyOptional(from: service, key: "locationID") {
                    let busNumber = (locationID >> 24) & 0xFF
                    let busID = String(format: "%d", busNumber)
                    
                    // Try to get address if available
                    if let address = getUInt8PropertyOptional(from: service, key: "USB Address") {
                        let deviceID = String(format: "%d", address)
                        
                        // Create minimal device with just identification info
                        let device = USBDevice(
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
                        
                        onDeviceDisconnected?(device)
                    } else {
                        print("Warning: Could not get device address for removed device")
                    }
                } else {
                    print("Warning: Could not get location ID for removed device")
                }
            }
        }
    }
}

// MARK: - C Callbacks

private func deviceAddedCallback(
    refcon: UnsafeMutableRawPointer?,
    iterator: io_iterator_t
) {
    guard let refcon = refcon else { return }
    let discovery = Unmanaged<IOKitDeviceDiscovery>.fromOpaque(refcon).takeUnretainedValue()
    discovery.consumeIterator(iterator, isAddedNotification: true)
}

private func deviceRemovedCallback(
    refcon: UnsafeMutableRawPointer?,
    iterator: io_iterator_t
) {
    guard let refcon = refcon else { return }
    let discovery = Unmanaged<IOKitDeviceDiscovery>.fromOpaque(refcon).takeUnretainedValue()
    discovery.consumeIterator(iterator, isAddedNotification: false)
}

// MARK: - Error Types

public enum DeviceDiscoveryError: Error, LocalizedError {
    case failedToCreateMatchingDictionary
    case failedToGetMatchingServices(kern_return_t)
    case missingProperty(String)
    case invalidPropertyType(String)
    case failedToCreateNotificationPort
    case failedToAddNotification(kern_return_t)
    
    public var errorDescription: String? {
        switch self {
        case .failedToCreateMatchingDictionary:
            return "Failed to create IOKit matching dictionary"
        case .failedToGetMatchingServices(let result):
            return "Failed to get matching services: \(result)"
        case .missingProperty(let key):
            return "Missing required property: \(key)"
        case .invalidPropertyType(let key):
            return "Invalid property type for key: \(key)"
        case .failedToCreateNotificationPort:
            return "Failed to create IOKit notification port"
        case .failedToAddNotification(let result):
            return "Failed to add IOKit notification: \(result)"
        }
    }
}