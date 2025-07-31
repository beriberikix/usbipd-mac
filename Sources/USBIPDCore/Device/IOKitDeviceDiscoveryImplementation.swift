//
//  IOKitDeviceDiscoveryImplementation.swift
//  usbipd-mac
//
//  Core device discovery implementation methods
//

import Foundation
import IOKit
import IOKit.usb
import Common

// MARK: - Core Implementation Extension

extension IOKitDeviceDiscovery {
    
    // MARK: - Internal Implementation Methods
    
    /// Internal device discovery implementation
    internal func discoverDevicesInternal() throws -> [USBDevice] {
        logger.debug("Starting USB device discovery")
        
        // Check cache first for performance
        if let cachedDevices = deviceListCache?.getCachedDevices() {
            logger.debug("Returning cached devices", context: ["count": cachedDevices.count])
            return cachedDevices
        }
        
        return try executeWithRetry(operation: "discover USB devices") {
            let devices = try performDeviceDiscovery()
            
            // Update cache with discovered devices
            deviceListCache?.updateCache(with: devices)
            
            logger.info("Discovered USB devices", context: ["count": devices.count])
            return devices
        }
    }
    
    /// Internal device lookup implementation
    internal func getDeviceInternal(busID: String, deviceID: String) throws -> USBDevice? {
        logger.debug("Looking up device", context: ["busID": busID, "deviceID": deviceID])
        
        return try executeWithRetry(operation: "lookup device by ID") {
            // First check connected devices cache
            let deviceKey = "\(busID)-\(deviceID)"
            if let cachedDevice = connectedDevices[deviceKey] {
                logger.debug("Found device in connected devices cache")
                return cachedDevice
            }
            
            // Fall back to full discovery and search
            let allDevices = try performDeviceDiscovery()
            let foundDevice = allDevices.first { device in
                device.busID == busID && device.deviceID == deviceID
            }
            
            if let device = foundDevice {
                logger.debug("Found device through discovery", context: [
                    "vendorID": String(format: "0x%04x", device.vendorID),
                    "productID": String(format: "0x%04x", device.productID)
                ])
            } else {
                logger.debug("Device not found")
            }
            
            return foundDevice
        }
    }
    
    /// Perform the actual device discovery using IOKit
    private func performDeviceDiscovery() throws -> [USBDevice] {
        logger.debug("Performing IOKit device discovery")
        
        // Create matching dictionary for USB devices
        guard let matchingDict = ioKit.serviceMatching("IOUSBDevice") else {
            throw handleIOKitError(KERN_FAILURE, operation: "create USB device matching dictionary")
        }
        
        // Get matching services
        var iterator: io_iterator_t = 0
        let result = ioKit.serviceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator)
        
        guard result == KERN_SUCCESS else {
            throw handleIOKitError(result, operation: "get matching USB services")
        }
        
        return try withIOKitObject(iterator) { iterator in
            var devices: [USBDevice] = []
            
            // Iterate through all matching services
            var service = ioKit.iteratorNext(iterator)
            while service != 0 {
                defer {
                    _ = ioKit.objectRelease(service)
                    service = ioKit.iteratorNext(iterator)
                }
                
                do {
                    let device = try createUSBDeviceFromService(service)
                    devices.append(device)
                } catch {
                    logger.warning("Failed to create device from service", context: [
                        "service": service,
                        "error": error.localizedDescription
                    ])
                    // Continue with other devices
                }
            }
            
            logger.debug("Created devices from services", context: ["count": devices.count])
            return devices
        }
    }
    
    /// Create USBDevice object from IOKit service
    internal func createUSBDeviceFromService(_ service: io_service_t) throws -> USBDevice {
        logger.debug("Creating USB device from IOKit service", context: ["service": service])
        
        // Extract device properties
        let properties = try extractDeviceProperties(from: service)
        
        // Generate bus and device IDs from IOKit locationID
        let (busID, deviceID) = try generateDeviceIDs(from: service)
        
        let device = USBDevice(
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
        
        logger.debug("Created USB device", context: [
            "busID": device.busID,
            "deviceID": device.deviceID,
            "vendorID": String(format: "0x%04x", device.vendorID),
            "productID": String(format: "0x%04x", device.productID),
            "product": device.productString ?? "Unknown"
        ])
        
        return device
    }
    
    /// Extract device properties from IOKit service
    private func extractDeviceProperties(from service: io_service_t) throws -> DeviceProperties {
        logger.debug("Extracting device properties from service", context: ["service": service])
        
        // Extract required properties
        guard let vendorID = getUInt16Property(from: service, key: "idVendor") else {
            throw DeviceDiscoveryError.missingProperty("idVendor")
        }
        
        guard let productID = getUInt16Property(from: service, key: "idProduct") else {
            throw DeviceDiscoveryError.missingProperty("idProduct")
        }
        
        // Extract optional properties with defaults
        let deviceClass = getUInt8Property(from: service, key: "bDeviceClass") ?? 0
        let deviceSubClass = getUInt8Property(from: service, key: "bDeviceSubClass") ?? 0
        let deviceProtocol = getUInt8Property(from: service, key: "bDeviceProtocol") ?? 0
        
        // Determine USB speed
        let speed = determineUSBSpeed(from: service)
        
        // Extract string descriptors
        let manufacturerString = getStringProperty(from: service, key: "USB Vendor Name")
        let productString = getStringProperty(from: service, key: "USB Product Name")
        let serialNumberString = getStringProperty(from: service, key: "USB Serial Number")
        
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
    
    /// Generate bus and device IDs from IOKit locationID
    private func generateDeviceIDs(from service: io_service_t) throws -> (String, String) {
        guard let locationID = getUInt32Property(from: service, key: "locationID") else {
            throw DeviceDiscoveryError.missingProperty("locationID")
        }
        
        // Extract bus and device numbers from locationID
        // LocationID format: 0xAABBCCDD where AA is bus, BB is device
        let busNumber = (locationID >> 24) & 0xFF
        let deviceNumber = (locationID >> 16) & 0xFF
        
        return (String(busNumber), String(deviceNumber))
    }
    
    /// Determine USB speed from IOKit properties
    private func determineUSBSpeed(from service: io_service_t) -> USBSpeed {
        // Try to get speed from various IOKit properties
        if let speedValue = getUInt32Property(from: service, key: "Device Speed") {
            switch speedValue {
            case 0: return .low
            case 1: return .full
            case 2: return .high
            case 3: return .superSpeed
            default: return .unknown
            }
        }
        
        // Fallback: try to determine from device class or other properties
        return .unknown
    }
    
    // MARK: - Property Extraction Helpers
    
    private func getUInt16Property(from service: io_service_t, key: String) -> UInt16? {
        guard let property = ioKit.registryEntryCreateCFProperty(
            service, 
            key as CFString, 
            kCFAllocatorDefault, 
            0
        )?
            .takeRetainedValue() else {
            return nil
        }
        
        if CFGetTypeID(property) == CFNumberGetTypeID() {
            // Safe to cast since we've verified the type
            let number = unsafeBitCast(property, to: CFNumber.self)
            var value: UInt16 = 0
            if CFNumberGetValue(number, .sInt16Type, &value) {
                return value
            }
        }
        
        return nil
    }
    
    private func getUInt8Property(from service: io_service_t, key: String) -> UInt8? {
        guard let property = ioKit.registryEntryCreateCFProperty(
            service, 
            key as CFString, 
            kCFAllocatorDefault, 
            0
        )?
            .takeRetainedValue() else {
            return nil
        }
        
        if CFGetTypeID(property) == CFNumberGetTypeID() {
            // Safe to cast since we've verified the type
            let number = unsafeBitCast(property, to: CFNumber.self)
            var value: UInt8 = 0
            if CFNumberGetValue(number, .sInt8Type, &value) {
                return value
            }
        }
        
        return nil
    }
    
    private func getUInt32Property(from service: io_service_t, key: String) -> UInt32? {
        guard let property = ioKit.registryEntryCreateCFProperty(
            service, 
            key as CFString, 
            kCFAllocatorDefault, 
            0
        )?
            .takeRetainedValue() else {
            return nil
        }
        
        if CFGetTypeID(property) == CFNumberGetTypeID() {
            // Safe to cast since we've verified the type
            let number = unsafeBitCast(property, to: CFNumber.self)
            var value: UInt32 = 0
            if CFNumberGetValue(number, .sInt32Type, &value) {
                return value
            }
        }
        
        return nil
    }
    
    private func getStringProperty(from service: io_service_t, key: String) -> String? {
        guard let property = ioKit.registryEntryCreateCFProperty(
            service, 
            key as CFString, 
            kCFAllocatorDefault, 
            0
        )?
            .takeRetainedValue() else {
            return nil
        }
        
        if CFGetTypeID(property) == CFStringGetTypeID() {
            return property as? String
        }
        
        return nil
    }
}