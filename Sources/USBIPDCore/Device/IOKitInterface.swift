// IOKitInterface.swift
// Protocol wrapper around IOKit functions for dependency injection

import Foundation
import IOKit
import IOKit.usb

// MARK: - IOKit Interface Protocol

/// Protocol wrapper around IOKit functions for dependency injection
/// This allows us to mock IOKit operations for unit testing
public protocol IOKitInterface {
    // Service matching and enumeration
    func serviceMatching(_ name: String) -> CFMutableDictionary?
    func serviceGetMatchingServices(_ masterPort: mach_port_t, _ matching: CFDictionary, _ existing: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t
    func iteratorNext(_ iterator: io_iterator_t) -> io_service_t
    func objectRelease(_ object: io_object_t) -> kern_return_t
    
    // Property access
    func registryEntryCreateCFProperty(_ entry: io_registry_entry_t, _ key: CFString, _ allocator: CFAllocator?, _ options: IOOptionBits) -> Unmanaged<CFTypeRef>?
    
    // Notification system
    func notificationPortCreate(_ masterPort: mach_port_t) -> IONotificationPortRef?
    func serviceAddMatchingNotification(_ notifyPort: IONotificationPortRef, _ notificationType: String, _ matching: CFDictionary, _ callback: IOServiceMatchingCallback?, _ refCon: UnsafeMutableRawPointer?, _ notification: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t
    func notificationPortGetRunLoopSource(_ notify: IONotificationPortRef) -> CFRunLoopSource?
    func notificationPortDestroy(_ notify: IONotificationPortRef)
}

// MARK: - Real IOKit Implementation

/// Real IOKit implementation that wraps actual IOKit functions
public class RealIOKitInterface: IOKitInterface {
    public init() {}
    
    public func serviceMatching(_ name: String) -> CFMutableDictionary? {
        return IOServiceMatching(name)
    }
    
    public func serviceGetMatchingServices(_ masterPort: mach_port_t, _ matching: CFDictionary, _ existing: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t {
        return IOServiceGetMatchingServices(masterPort, matching, existing)
    }
    
    public func iteratorNext(_ iterator: io_iterator_t) -> io_service_t {
        return IOIteratorNext(iterator)
    }
    
    public func objectRelease(_ object: io_object_t) -> kern_return_t {
        return IOObjectRelease(object)
    }
    
    public func registryEntryCreateCFProperty(_ entry: io_registry_entry_t, _ key: CFString, _ allocator: CFAllocator?, _ options: IOOptionBits) -> Unmanaged<CFTypeRef>? {
        return IORegistryEntryCreateCFProperty(entry, key, allocator, options)
    }
    
    public func notificationPortCreate(_ masterPort: mach_port_t) -> IONotificationPortRef? {
        return IONotificationPortCreate(masterPort)
    }
    
    public func serviceAddMatchingNotification(_ notifyPort: IONotificationPortRef, _ notificationType: String, _ matching: CFDictionary, _ callback: IOServiceMatchingCallback?, _ refCon: UnsafeMutableRawPointer?, _ notification: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t {
        return IOServiceAddMatchingNotification(notifyPort, notificationType, matching, callback, refCon, notification)
    }
    
    public func notificationPortGetRunLoopSource(_ notify: IONotificationPortRef) -> CFRunLoopSource? {
        return IONotificationPortGetRunLoopSource(notify)?.takeRetainedValue()
    }
    
    public func notificationPortDestroy(_ notify: IONotificationPortRef) {
        IONotificationPortDestroy(notify)
    }
}