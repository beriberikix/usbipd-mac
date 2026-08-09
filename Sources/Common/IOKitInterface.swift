// IOKitInterface.swift
// Protocol wrapper around IOKit functions for dependency injection

import Foundation
import IOKit
import IOKit.usb

private let kIOCFPlugInInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil,
    0xc2, 0x44, 0xe8, 0x58, 0x10, 0x9c, 0x11, 0xd4,
    0x91, 0xd4, 0x00, 0x50, 0xe4, 0xc6, 0x42, 0x6f)

private let kIOUSBInterfaceUserClientTypeID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x2d, 0x97, 0x86, 0xc6, 0x9e, 0xf3, 0x11, 0xd4,
    0xad, 0x51, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

private let kIOUSBInterfaceInterfaceID300 = CFUUIDGetConstantUUIDWithBytes(nil,
    0xbc, 0xea, 0xad, 0xdc, 0x88, 0x4d, 0x4f, 0x27,
    0x83, 0x40, 0x36, 0xd6, 0x9f, 0xab, 0x90, 0xf6)

// MARK: - IOKit Interface Protocol

/// Protocol wrapper around IOKit functions for dependency injection
/// This allows us to mock IOKit operations for unit testing
public protocol IOKitInterface {
    // Service matching and enumeration
    func serviceMatching(_ name: String) -> CFMutableDictionary?
    func serviceGetMatchingServices(_ mainPort: mach_port_t, _ matching: CFDictionary, _ existing: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t
    func iteratorNext(_ iterator: io_iterator_t) -> io_service_t
    func objectRelease(_ object: io_object_t) -> kern_return_t
    
    // Property access
    func registryEntryCreateCFProperty(_ entry: io_registry_entry_t, _ key: CFString, _ allocator: CFAllocator?, _ options: IOOptionBits) -> Unmanaged<CFTypeRef>?

    /// Children of a registry entry in the given plane. Needed to see which drivers
    /// have matched against a device, which is how device ownership is determined.
    func registryEntryGetChildIterator(_ entry: io_registry_entry_t, _ plane: String, _ iterator: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t

    /// The IOKit class name of a service, e.g. "IOUSBMassStorageDriver".
    func objectCopyClass(_ object: io_object_t) -> String?

    /// Whether a USB interface can actually be opened, by opening it and closing it
    /// again. Which driver is attached does not predict this — see the implementation.
    func usbInterfaceOpens(_ interfaceService: io_service_t) -> Bool
    
    // Notification system
    func notificationPortCreate(_ mainPort: mach_port_t) -> IONotificationPortRef?
    func serviceAddMatchingNotification(_ notifyPort: IONotificationPortRef, _ notificationType: String, _ matching: CFDictionary, _ callback: IOServiceMatchingCallback?, _ refCon: UnsafeMutableRawPointer?, _ notification: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t
    func notificationPortGetRunLoopSource(_ notify: IONotificationPortRef) -> CFRunLoopSource?
    func notificationPortSetDispatchQueue(_ notify: IONotificationPortRef, _ queue: DispatchQueue?)
    func notificationPortDestroy(_ notify: IONotificationPortRef)
}

// MARK: - Real IOKit Implementation

/// Real IOKit implementation that wraps actual IOKit functions
public class RealIOKitInterface: IOKitInterface {
    public init() {}
    
    public func serviceMatching(_ name: String) -> CFMutableDictionary? {
        return IOServiceMatching(name)
    }
    
    public func serviceGetMatchingServices(_ mainPort: mach_port_t, _ matching: CFDictionary, _ existing: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t {
        return IOServiceGetMatchingServices(mainPort, matching, existing)
    }
    
    public func iteratorNext(_ iterator: io_iterator_t) -> io_service_t {
        return IOIteratorNext(iterator)
    }
    
    public func objectRelease(_ object: io_object_t) -> kern_return_t {
        return IOObjectRelease(object)
    }
    
    public func registryEntryGetChildIterator(_ entry: io_registry_entry_t, _ plane: String, _ iterator: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t {
        return IORegistryEntryGetChildIterator(entry, plane, iterator)
    }

    public func objectCopyClass(_ object: io_object_t) -> String? {
        guard let name = IOObjectCopyClass(object) else { return nil }
        return name.takeRetainedValue() as String
    }

    /// Try to claim the interface, then let it go again.
    ///
    /// The presence of a driver does not predict whether this succeeds. `IOUserSerial`
    /// sits on every FTDI and CP210x interface and does not take exclusive access —
    /// those devices open, and serve real bulk traffic. `AppleUserHIDDevice` is also a
    /// DriverKit dext and does block. Neither the driver's name nor whether it is a
    /// dext is a reliable signal; only attempting the open is.
    ///
    /// Inferring from names is what made this project refuse USB-serial adapters, the
    /// devices it is most often asked for, and tell users they needed an entitlement.
    public func usbInterfaceOpens(_ interfaceService: io_service_t) -> Bool {
        var plugin: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0

        guard IOCreatePlugInInterfaceForService(
            interfaceService,
            kIOUSBInterfaceUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &plugin,
            &score
        ) == kIOReturnSuccess, let plugin = plugin else {
            // Cannot ask, so do not pretend to know. Treated as openable, because
            // refusing on an inconclusive probe is the failure mode being fixed.
            return true
        }

        var raw: UnsafeMutableRawPointer?
        let queryResult = plugin.pointee?.pointee.QueryInterface(
            plugin,
            CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300),
            &raw
        )
        _ = plugin.pointee?.pointee.Release(plugin)

        guard queryResult == S_OK, let raw = raw else { return true }

        let handle = raw.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBInterfaceInterface300>?.self)
        guard let usbInterface = handle.pointee else { return true }
        defer { _ = usbInterface.pointee.Release(handle) }

        let openResult = usbInterface.pointee.USBInterfaceOpen(handle)
        if openResult == kIOReturnSuccess {
            _ = usbInterface.pointee.USBInterfaceClose(handle)
            return true
        }
        return false
    }

    public func registryEntryCreateCFProperty(_ entry: io_registry_entry_t, _ key: CFString, _ allocator: CFAllocator?, _ options: IOOptionBits) -> Unmanaged<CFTypeRef>? {
        return IORegistryEntryCreateCFProperty(entry, key, allocator, options)
    }
    
    public func notificationPortCreate(_ mainPort: mach_port_t) -> IONotificationPortRef? {
        return IONotificationPortCreate(mainPort)
    }
    
    public func serviceAddMatchingNotification(_ notifyPort: IONotificationPortRef, _ notificationType: String, _ matching: CFDictionary, _ callback: IOServiceMatchingCallback?, _ refCon: UnsafeMutableRawPointer?, _ notification: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t {
        return IOServiceAddMatchingNotification(notifyPort, notificationType, matching, callback, refCon, notification)
    }
    
    public func notificationPortGetRunLoopSource(_ notify: IONotificationPortRef) -> CFRunLoopSource? {
        return IONotificationPortGetRunLoopSource(notify)?.takeRetainedValue()
    }
    
    public func notificationPortSetDispatchQueue(_ notify: IONotificationPortRef, _ queue: DispatchQueue?) {
        IONotificationPortSetDispatchQueue(notify, queue)
    }
    
    public func notificationPortDestroy(_ notify: IONotificationPortRef) {
        IONotificationPortDestroy(notify)
    }
}