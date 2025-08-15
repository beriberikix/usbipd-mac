//
//  IOKitDeviceDiscoveryNotifications.swift
//  usbipd-mac
//
//  IOKit device notification system for device discovery
//

import Foundation
import IOKit
import IOKit.usb
import Common

// MARK: - Notification System Extension

extension IOKitDeviceDiscovery {
    
    // MARK: - Notification System
    
    public func startNotifications() throws {
        logger.debug("Starting IOKit device notifications")
        
        guard !isMonitoring else {
            logger.debug("Notifications already started")
            return
        }
        
        // Create notification port
        guard let port = ioKit.notificationPortCreate(kIOMasterPortDefault) else {
            let error = handleIOKitError(KERN_FAILURE, operation: "create notification port")
            logger.error("Failed to create notification port", context: ["error": error.localizedDescription])
            throw error
        }
        
        notificationPort = port
        logger.debug("Created IOKit notification port")
        
        // Set up notification port on our dispatch queue
        ioKit.notificationPortSetDispatchQueue(port, queue)
        logger.debug("Set notification port dispatch queue")
        
        // Create matching dictionary for USB devices
        guard let matchingDict = ioKit.serviceMatching("IOUSBDevice") else {
            let error = handleIOKitError(KERN_FAILURE, operation: "create USB device matching dictionary")
            logger.error("Failed to create matching dictionary", context: ["error": error.localizedDescription])
            throw error
        }
        
        // Register for device addition notifications
        let addResult = ioKit.serviceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            matchingDict,
            deviceAddedCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &addedIterator
        )
        
        guard addResult == KERN_SUCCESS else {
            let error = handleIOKitError(addResult, operation: "register device addition notification")
            logger.error("Failed to register device addition notification", context: ["error": error.localizedDescription])
            throw error
        }
        
        logger.debug("Registered device addition notification")
        
        // Create another matching dictionary for removal notifications
        guard let removalMatchingDict = ioKit.serviceMatching("IOUSBDevice") else {
            let error = handleIOKitError(KERN_FAILURE, operation: "create USB device removal matching dictionary")
            logger.error("Failed to create removal matching dictionary", context: ["error": error.localizedDescription])
            throw error
        }
        
        // Register for device removal notifications
        let removeResult = ioKit.serviceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            removalMatchingDict,
            deviceRemovedCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &removedIterator
        )
        
        guard removeResult == KERN_SUCCESS else {
            let error = handleIOKitError(removeResult, operation: "register device removal notification")
            logger.error("Failed to register device removal notification", context: ["error": error.localizedDescription])
            throw error
        }
        
        logger.debug("Registered device removal notification")
        
        // Process any devices that are already connected
        processExistingDevices()
        
        isMonitoring = true
        logger.info("IOKit device notifications started successfully")
    }
    
    public func stopNotifications() {
        logger.debug("Stopping IOKit device notifications")
        
        guard isMonitoring else {
            logger.debug("Notifications not currently active")
            return
        }
        
        // Clean up iterators
        if addedIterator != 0 {
            _ = ioKit.objectRelease(addedIterator)
            addedIterator = 0
            logger.debug("Released added iterator")
        }
        
        if removedIterator != 0 {
            _ = ioKit.objectRelease(removedIterator)
            removedIterator = 0
            logger.debug("Released removed iterator")
        }
        
        // Clean up notification port
        if let port = notificationPort {
            ioKit.notificationPortDestroy(port)
            notificationPort = nil
            logger.debug("Destroyed notification port")
        }
        
        // Clear connected devices cache
        connectedDevices.removeAll()
        logger.debug("Cleared connected devices cache")
        
        isMonitoring = false
        logger.info("IOKit device notifications stopped successfully")
    }
    
    /// Process devices that are already connected when notifications start
    private func processExistingDevices() {
        logger.debug("Processing existing connected devices")
        
        // Process devices from the added iterator to catch already-connected devices
        var device = ioKit.iteratorNext(addedIterator)
        var processedCount = 0
        
        while device != 0 {
            defer {
                _ = ioKit.objectRelease(device)
                device = ioKit.iteratorNext(addedIterator)
            }
            
            processedCount += 1
            
            // Process the device in the background to avoid blocking
            let currentDevice = device
            queue.async { [weak self] in
                self?.handleDeviceAdded(currentDevice)
            }
        }
        
        // Process devices from the removed iterator to clear any stale entries
        device = ioKit.iteratorNext(removedIterator)
        while device != 0 {
            _ = ioKit.objectRelease(device)
            device = ioKit.iteratorNext(removedIterator)
            
            // Just consume the iterator without processing
        }
        
        logger.debug("Processed existing devices", context: ["count": processedCount])
    }
    
    /// Verify notification cleanup was successful
    internal func verifyNotificationCleanup() -> Bool {
        let isClean = !isMonitoring && 
                     notificationPort == nil && 
                     addedIterator == 0 && 
                     removedIterator == 0
        
        if !isClean {
            logger.warning("Notification cleanup verification failed", context: [
                "isMonitoring": isMonitoring,
                "hasNotificationPort": notificationPort != nil,
                "hasAddedIterator": addedIterator != 0,
                "hasRemovedIterator": removedIterator != 0
            ])
        }
        
        return isClean
    }
    
    // MARK: - Device Notification Handlers
    
    /// Optimized device connection handler with minimal IOKit calls
    internal func handleDeviceAdded(_ service: io_service_t) {
        logger.debug("Processing device addition", context: ["service": service])
        
        do {
            // Create USBDevice from the service with error recovery
            let device = try executeWithRetry(operation: "create device from added service") {
                return try createUSBDeviceFromService(service)
            }
            
            let deviceKey = "\(device.busID)-\(device.deviceID)"
            
            // Update connected devices cache
            connectedDevices[deviceKey] = device
            
            logger.info("Device connected", context: [
                "busID": device.busID,
                "deviceID": device.deviceID,
                "vendorID": String(format: "0x%04x", device.vendorID),
                "productID": String(format: "0x%04x", device.productID),
                "product": device.productString ?? "Unknown"
            ])
            
            // Trigger callback on main queue for thread safety
            DispatchQueue.main.async { [weak self] in
                self?.onDeviceConnected?(device)
            }
        } catch {
            logger.warning("Failed to process added device", context: [
                "service": service,
                "error": error.localizedDescription
            ])
        }
    }
    
    /// Optimized device disconnection handler with minimal IOKit calls
    internal func handleDeviceRemoved(_ service: io_service_t) {
        logger.debug("Processing device removal", context: ["service": service])
        
        do {
            // Try to create device info for the removed device
            // This might fail if the device is already gone, which is expected
            let device = try createUSBDeviceFromService(service)
            let deviceKey = "\(device.busID)-\(device.deviceID)"
            
            // Remove from connected devices cache
            if let removedDevice = connectedDevices.removeValue(forKey: deviceKey) {
                logger.info("Device disconnected", context: [
                    "busID": removedDevice.busID,
                    "deviceID": removedDevice.deviceID,
                    "vendorID": String(format: "0x%04x", removedDevice.vendorID),
                    "productID": String(format: "0x%04x", removedDevice.productID),
                    "product": removedDevice.productString ?? "Unknown"
                ])
                
                // Trigger callback on main queue for thread safety
                DispatchQueue.main.async { [weak self] in
                    self?.onDeviceDisconnected?(removedDevice)
                }
            } else {
                logger.debug("Removed device was not in connected devices cache", context: [
                    "deviceKey": deviceKey
                ])
            }
        } catch {
            // Device removal often fails to read properties since the device is gone
            // This is expected behavior, so we log at debug level
            logger.debug("Could not read properties of removed device (expected)", context: [
                "service": service,
                "error": error.localizedDescription
            ])
            // Try to find and remove the device from cache by service reference
            // This is a fallback when we can't read device properties
            for (_, _) in connectedDevices {
                // We can't easily match the service to the cached device without properties
                // So we'll rely on the successful case above for most removals
                // This fallback is mainly for logging purposes
                break
            }
        }
    }
}

// MARK: - C Callbacks

/// IOKit callback function for device connection events
/// This function is called from IOKit's C API and must be a C function
private func deviceAddedCallback(
    refCon: UnsafeMutableRawPointer?,
    iterator: io_iterator_t
) {
    guard let refCon = refCon else {
        print("Device added callback called with nil refCon")
        return
    }
    
    let discovery = Unmanaged<IOKitDeviceDiscovery>.fromOpaque(refCon).takeUnretainedValue()
    
    // Process all devices in the iterator
    var service = IOIteratorNext(iterator)
    while service != 0 {
        let currentService = service
        
        // Handle the device addition on the discovery's queue
        discovery.queue.async {
            discovery.handleDeviceAdded(currentService)
        }
        
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }
}

/// IOKit callback function for device disconnection events
/// This function is called from IOKit's C API and must be a C function
private func deviceRemovedCallback(
    refCon: UnsafeMutableRawPointer?,
    iterator: io_iterator_t
) {
    guard let refCon = refCon else {
        print("Device removed callback called with nil refCon")
        return
    }
    
    let discovery = Unmanaged<IOKitDeviceDiscovery>.fromOpaque(refCon).takeUnretainedValue()
    
    // Process all devices in the iterator
    var service = IOIteratorNext(iterator)
    while service != 0 {
        let currentService = service
        
        // Handle the device removal on the discovery's queue
        discovery.queue.async {
            discovery.handleDeviceRemoved(currentService)
        }
        
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }
}