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
    
    private let logger: Logger
    private let queue: DispatchQueue
    
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
        
        logger.debug("IOKitDeviceDiscovery initialized with dedicated dispatch queue")
    }
    
    deinit {
        stopNotifications()
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
                IOObjectRelease(object)
            }
        }
        return try block(object)
    }
    
    /// Convert IOKit error codes to DeviceDiscoveryError
    private func handleIOKitError(_ result: kern_return_t, operation: String) -> DeviceDiscoveryError {
        let errorMessage = "IOKit operation '\(operation)' failed with code: \(result)"
        logger.error(errorMessage, context: ["kern_return": result])
        return DeviceDiscoveryError.ioKitError(result, errorMessage)
    }
    
    // MARK: - DeviceDiscovery Protocol
    
    public func discoverDevices() throws -> [USBDevice] {
        return try queue.sync {
            return try discoverDevicesInternal()
        }
    }
    
    /// Internal device discovery method that doesn't use queue synchronization
    private func discoverDevicesInternal() throws -> [USBDevice] {
        logger.debug("Starting USB device discovery")
        var devices: [USBDevice] = []
        
        // Create matching dictionary for USB devices
        guard let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) else {
            logger.error("Failed to create IOKit matching dictionary")
            throw DeviceDiscoveryError.failedToCreateMatchingDictionary
        }
        
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator)
        
        guard result == KERN_SUCCESS else {
            throw DeviceDiscoveryError.failedToGetMatchingServices(result)
        }
        
        return try withIOKitObject(iterator) { iterator in
            logger.debug("Iterating through discovered USB devices")
            var deviceCount = 0
            var service: io_service_t = IOIteratorNext(iterator)
            
            while service != 0 {
                let device = try withIOKitObject(service) { service in
                    return try createUSBDevice(from: service)
                }
                
                devices.append(device)
                deviceCount += 1
                
                logger.debug("Found USB device", context: [
                    "busID": device.busID,
                    "deviceID": device.deviceID,
                    "vendorID": String(format: "0x%04x", device.vendorID),
                    "productID": String(format: "0x%04x", device.productID),
                    "product": device.productString ?? "Unknown"
                ])
                
                service = IOIteratorNext(iterator)
            }
            
            logger.info("Discovered \(deviceCount) USB devices")
            return devices
        }
    }
    
    public func getDevice(busID: String, deviceID: String) throws -> USBDevice? {
        return try queue.sync {
            logger.debug("Looking for specific device", context: ["busID": busID, "deviceID": deviceID])
            
            // Discover devices directly without calling the public method to avoid queue deadlock
            let devices = try discoverDevicesInternal()
            let device = devices.first { $0.busID == busID && $0.deviceID == deviceID }
            
            if let device = device {
                logger.debug("Found requested device", context: [
                    "busID": device.busID,
                    "deviceID": device.deviceID,
                    "vendorID": String(format: "0x%04x", device.vendorID),
                    "productID": String(format: "0x%04x", device.productID)
                ])
            } else {
                logger.warning("Device not found", context: ["busID": busID, "deviceID": deviceID])
            }
            
            return device
        }
    }
    
    // MARK: - Private Methods
    
    private func createUSBDevice(from service: io_service_t) throws -> USBDevice {
        // Extract device properties using the comprehensive property extraction method
        let properties = try extractDeviceProperties(from: service)
        
        // Generate bus and device IDs
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
    
    /// Extract comprehensive device properties from IOKit service
    /// Maps IOKit property keys to USBDevice struct fields with graceful error handling
    private func extractDeviceProperties(from service: io_service_t) throws -> DeviceProperties {
        logger.debug("Extracting device properties from IOKit service")
        
        // Extract required properties with error handling
        let vendorID = try extractVendorID(from: service)
        let productID = try extractProductID(from: service)
        let deviceClass = extractDeviceClass(from: service)
        let deviceSubClass = extractDeviceSubClass(from: service)
        let deviceProtocol = extractDeviceProtocol(from: service)
        let speed = extractUSBSpeed(from: service)
        
        // Extract optional string descriptors
        let manufacturerString = extractManufacturerString(from: service)
        let productString = extractProductString(from: service)
        let serialNumberString = extractSerialNumberString(from: service)
        
        logger.debug("Successfully extracted device properties", context: [
            "vendorID": String(format: "0x%04x", vendorID),
            "productID": String(format: "0x%04x", productID),
            "deviceClass": String(format: "0x%02x", deviceClass),
            "deviceSubClass": String(format: "0x%02x", deviceSubClass),
            "deviceProtocol": String(format: "0x%02x", deviceProtocol),
            "speed": speed.rawValue,
            "hasManufacturer": manufacturerString != nil,
            "hasProduct": productString != nil,
            "hasSerial": serialNumberString != nil
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
    
    // MARK: - Property Extraction Methods
    
    /// Extract vendor ID (VID) from IOKit properties
    private func extractVendorID(from service: io_service_t) throws -> UInt16 {
        do {
            return try getUInt16Property(from: service, key: kUSBVendorID)
        } catch {
            logger.error("Failed to extract vendor ID", context: ["error": error.localizedDescription])
            throw DeviceDiscoveryError.missingProperty(kUSBVendorID)
        }
    }
    
    /// Extract product ID (PID) from IOKit properties
    private func extractProductID(from service: io_service_t) throws -> UInt16 {
        do {
            return try getUInt16Property(from: service, key: kUSBProductID)
        } catch {
            logger.error("Failed to extract product ID", context: ["error": error.localizedDescription])
            throw DeviceDiscoveryError.missingProperty(kUSBProductID)
        }
    }
    
    /// Extract device class with graceful fallback to default value
    private func extractDeviceClass(from service: io_service_t) -> UInt8 {
        do {
            return try getUInt8Property(from: service, key: kUSBDeviceClass)
        } catch {
            logger.warning("Failed to extract device class, using default", context: [
                "error": error.localizedDescription,
                "default": "0x00"
            ])
            return 0x00 // Default to unspecified class
        }
    }
    
    /// Extract device subclass with graceful fallback to default value
    private func extractDeviceSubClass(from service: io_service_t) -> UInt8 {
        do {
            return try getUInt8Property(from: service, key: kUSBDeviceSubClass)
        } catch {
            logger.warning("Failed to extract device subclass, using default", context: [
                "error": error.localizedDescription,
                "default": "0x00"
            ])
            return 0x00 // Default to unspecified subclass
        }
    }
    
    /// Extract device protocol with graceful fallback to default value
    private func extractDeviceProtocol(from service: io_service_t) -> UInt8 {
        do {
            return try getUInt8Property(from: service, key: kUSBDeviceProtocol)
        } catch {
            logger.warning("Failed to extract device protocol, using default", context: [
                "error": error.localizedDescription,
                "default": "0x00"
            ])
            return 0x00 // Default to unspecified protocol
        }
    }
    
    /// Extract USB speed with graceful fallback to unknown
    private func extractUSBSpeed(from service: io_service_t) -> USBSpeed {
        // Try multiple possible property keys for speed information
        let speedKeys = ["Speed", "Device Speed"]
        
        for key in speedKeys {
            if let speed = tryExtractSpeed(from: service, key: key) {
                logger.debug("Successfully extracted USB speed", context: [
                    "key": key,
                    "speed": speed.rawValue
                ])
                return speed
            }
        }
        
        logger.warning("Could not determine USB speed, using unknown")
        return .unknown
    }
    
    /// Try to extract speed from a specific property key
    private func tryExtractSpeed(from service: io_service_t, key: String) -> USBSpeed? {
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
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
        // Try multiple possible property keys for manufacturer string
        let manufacturerKeys = ["USB Vendor Name", "Manufacturer"]
        
        for key in manufacturerKeys {
            if let manufacturer = getStringProperty(from: service, key: key) {
                logger.debug("Found manufacturer string", context: [
                    "key": key,
                    "manufacturer": manufacturer
                ])
                return manufacturer
            }
        }
        
        logger.debug("No manufacturer string found")
        return nil
    }
    
    /// Extract product string descriptor with graceful handling
    private func extractProductString(from service: io_service_t) -> String? {
        // Try multiple possible property keys for product string
        let productKeys = ["USB Product Name", "Product"]
        
        for key in productKeys {
            if let product = getStringProperty(from: service, key: key) {
                logger.debug("Found product string", context: [
                    "key": key,
                    "product": product
                ])
                return product
            }
        }
        
        logger.debug("No product string found")
        return nil
    }
    
    /// Extract serial number string descriptor with graceful handling
    private func extractSerialNumberString(from service: io_service_t) -> String? {
        // Try multiple possible property keys for serial number string
        let serialKeys = ["USB Serial Number", "Serial Number"]
        
        for key in serialKeys {
            if let serial = getStringProperty(from: service, key: key) {
                logger.debug("Found serial number string", context: [
                    "key": key,
                    "serial": serial
                ])
                return serial
            }
        }
        
        logger.debug("No serial number string found")
        return nil
    }
    
    private func getUInt16Property(from service: io_service_t, key: String) throws -> UInt16 {
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            logger.warning("Missing required property", context: ["key": key])
            throw DeviceDiscoveryError.missingProperty(key)
        }
        
        guard let number = property as? NSNumber else {
            logger.warning("Invalid property type", context: ["key": key])
            throw DeviceDiscoveryError.invalidPropertyType(key)
        }
        
        return number.uint16Value
    }
    
    private func getUInt8Property(from service: io_service_t, key: String) throws -> UInt8 {
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            logger.warning("Missing required property", context: ["key": key])
            throw DeviceDiscoveryError.missingProperty(key)
        }
        
        guard let number = property as? NSNumber else {
            logger.warning("Invalid property type", context: ["key": key])
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
            logger.warning("Missing required property", context: ["key": key])
            throw DeviceDiscoveryError.missingProperty(key)
        }
        
        guard let number = property as? NSNumber else {
            logger.warning("Invalid property type", context: ["key": key])
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
        try queue.sync {
            guard !isMonitoring else {
                logger.debug("Device notifications already started")
                return // Already started
            }
            
            logger.info("Starting USB device notifications")
            
            // Create notification port
            notificationPort = IONotificationPortCreate(kIOMasterPortDefault)
            guard let port = notificationPort else {
                logger.error("Failed to create IOKit notification port")
                throw DeviceDiscoveryError.failedToCreateNotificationPort
            }
            
            // Set notification port dispatch queue
            IONotificationPortSetDispatchQueue(port, queue)
            logger.debug("Set notification port dispatch queue")
            
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
            
            logger.debug("Consuming initial device notifications")
            
            // Consume initial notifications
            consumeIterator(addedIterator, isAddedNotification: true)
            consumeIterator(removedIterator, isAddedNotification: false)
            
            isMonitoring = true
            logger.info("USB device notifications started successfully")
        }
    }
    
    public func stopNotifications() {
        queue.sync {
            guard isMonitoring else {
                logger.debug("Device notifications already stopped")
                return
            }
            
            logger.info("Stopping USB device notifications")
            
            if let port = notificationPort {
                IONotificationPortDestroy(port)
                notificationPort = nil
                logger.debug("Destroyed notification port")
            }
            
            if addedIterator != 0 {
                IOObjectRelease(addedIterator)
                addedIterator = 0
                logger.debug("Released device added iterator")
            }
            
            if removedIterator != 0 {
                IOObjectRelease(removedIterator)
                removedIterator = 0
                logger.debug("Released device removed iterator")
            }
            
            isMonitoring = false
            logger.info("USB device notifications stopped")
        }
    }
    
    // Changed from private to internal for callback access
    func consumeIterator(_ iterator: io_iterator_t, isAddedNotification: Bool) {
        let eventType = isAddedNotification ? "added" : "removed"
        logger.debug("Processing \(eventType) device notifications")
        
        var deviceCount = 0
        var service: io_service_t = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            
            deviceCount += 1
            
            if isAddedNotification {
                do {
                    let device = try createUSBDevice(from: service)
                    logger.info("USB device connected", context: [
                        "busID": device.busID,
                        "deviceID": device.deviceID,
                        "vendorID": String(format: "0x%04x", device.vendorID),
                        "productID": String(format: "0x%04x", device.productID),
                        "product": device.productString ?? "Unknown"
                    ])
                    onDeviceConnected?(device)
                } catch {
                    logger.error("Failed to create USB device from added notification", context: ["error": error.localizedDescription])
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
                        
                        logger.info("USB device disconnected", context: [
                            "busID": busID,
                            "deviceID": deviceID
                        ])
                        
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
                        logger.warning("Could not get device address for removed device", context: ["locationID": locationID])
                    }
                } else {
                    logger.warning("Could not get location ID for removed device")
                }
            }
        }
        
        if deviceCount > 0 {
            logger.debug("Processed \(deviceCount) \(eventType) device notifications")
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

