// DeviceOwnership.swift
// Determines whether anything already owns a USB device, before we promise to share it.

import Foundation
import IOKit
import Common

/// Who currently holds a device's interfaces.
public enum DeviceOwnership: Equatable {
    /// Nothing has matched against the interfaces. This is the servable case.
    case unbound

    /// A kernel driver owns at least one interface. Releasing it needs DriverKit
    /// rebinding, which requires an entitlement Apple has to grant — measured on
    /// 2026-08-06, `USBInterfaceOpenSeize` does not help.
    case kernelDriver(drivers: [String])

    /// A userspace process holds the interfaces open. Blocks a claim just as firmly,
    /// but quitting that process frees the device, so the two must not be reported
    /// alike — one is a dead end, the other is a thing the user can act on.
    case userspaceProcess(clients: [String])

    public var isServable: Bool {
        if case .unbound = self { return true }
        return false
    }
}

/// Structural USB nodes. Their presence says nothing about whether a function driver
/// claimed anything — every device has them.
private let structuralClasses: Set<String> = [
    "IOUSBHostDevice",
    "IOUSBDevice",
    "IOUSBHostInterface",
    "IOUSBInterface",
    "IOUSBHostLegacyClient",
    "AppleUSBHostLegacyClient",
    "IOUSBHostLegacyDevice",
    "IOUSBHostLegacyInterface",
    // Creates the interface nodes; structural, not a claim.
    "AppleUSBHostCompositeDevice",
    // A transient device-level handle that appears whenever any process opens the
    // device — including this project's own probe. It says nothing about whether an
    // interface can be claimed, and treating it as an owner made a device that opens
    // perfectly well report as taken.
    "AppleUSBHostDeviceUserClient",
    "IOUSBHostDeviceUserClient"
]

/// Userspace client connections — libusb, WebUSB, a framework daemon. Not kernel
/// drivers. Counting them as such made a fully usable device look kernel-owned during
/// harness development, and pointed at DriverKit when the fix was to quit an app.
private let userspaceClientClasses: Set<String> = [
    "AppleUSBHostFrameworkInterfaceClient",
    "IOUSBHostInterfaceUserClient",
    "AppleUSBHostFrameworkDeviceClient"
]

/// Reads device ownership out of the IORegistry.
public struct DeviceOwnershipInspector {
    private let ioKit: IOKitInterface

    public init(ioKit: IOKitInterface = RealIOKitInterface()) {
        self.ioKit = ioKit
    }

    /// Determine who owns the device with this vendor and product ID.
    ///
    /// Returns `.unbound` when the device cannot be found: absent evidence of an
    /// owner, refusing to bind would be worse than letting the attempt proceed and
    /// fail with a real error.
    public func ownership(vendorID: UInt16, productID: UInt16) -> DeviceOwnership {
        guard let matching = ioKit.serviceMatching("IOUSBHostDevice") else {
            return .unbound
        }

        var iterator: io_iterator_t = 0
        guard ioKit.serviceGetMatchingServices(kIOMasterPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return .unbound
        }
        defer { _ = ioKit.objectRelease(iterator) }

        // Bind the current service to a `let` before the defer. A `defer` capturing the
        // loop's `var` releases whatever it holds when the iteration ends — by which
        // point it has already been reassigned to the next service, so each pass freed
        // the entry the next pass was about to read.
        while true {
            let service = ioKit.iteratorNext(iterator)
            guard service != 0 else { break }
            defer { _ = ioKit.objectRelease(service) }

            if intProperty(service, "idVendor") == Int(vendorID),
               intProperty(service, "idProduct") == Int(productID) {
                return classify(collectClaimants(of: service))
            }
        }

        return .unbound
    }

    /// Drivers matched against the device's interfaces.
    ///
    /// Claimability is decided per interface, not for the device as a whole: a device
    /// can be opened while its interface is held by someone else, and it is the
    /// interface that a transfer needs. Collecting every class in the subtree instead
    /// swept up unrelated nodes and reported servable hardware as owned.
    private func collectClaimants(of deviceEntry: io_registry_entry_t) -> [String] {
        var claimants: [String] = []
        for interfaceEntry in interfaceNodes(under: deviceEntry) {
            defer { _ = ioKit.objectRelease(interfaceEntry) }
            claimants.append(contentsOf: immediateDrivers(of: interfaceEntry))
        }
        return claimants
    }

    /// Interface nodes below a device, wherever the composite driver put them.
    private func interfaceNodes(under entry: io_registry_entry_t, depth: Int = 0) -> [io_registry_entry_t] {
        guard depth < 4 else { return [] }

        var iterator: io_iterator_t = 0
        guard ioKit.registryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { _ = ioKit.objectRelease(iterator) }

        var interfaces: [io_registry_entry_t] = []
        while true {
            let child = ioKit.iteratorNext(iterator)
            guard child != 0 else { break }

            let className = ioKit.objectCopyClass(child) ?? ""
            if className == "IOUSBHostInterface" || className == "IOUSBInterface" {
                interfaces.append(child)   // released by the caller
            } else {
                interfaces.append(contentsOf: interfaceNodes(under: child, depth: depth + 1))
                _ = ioKit.objectRelease(child)
            }
        }
        return interfaces
    }

    /// Immediate driver children of one interface — what actually holds it.
    private func immediateDrivers(of interfaceEntry: io_registry_entry_t) -> [String] {
        var iterator: io_iterator_t = 0
        guard ioKit.registryEntryGetChildIterator(interfaceEntry, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { _ = ioKit.objectRelease(iterator) }

        var drivers: [String] = []
        while true {
            let child = ioKit.iteratorNext(iterator)
            guard child != 0 else { break }
            defer { _ = ioKit.objectRelease(child) }

            if let className = ioKit.objectCopyClass(child), !structuralClasses.contains(className) {
                drivers.append(className)
            }
        }
        return drivers
    }

    private func classify(_ claimants: [String]) -> DeviceOwnership {
        guard !claimants.isEmpty else { return .unbound }

        let unique = Array(Set(claimants)).sorted()
        let kernelDrivers = unique.filter { !userspaceClientClasses.contains($0) }

        // A device can have both — a webcam's audio control interface is kernel-owned
        // while its video interfaces are held by the camera framework. A kernel driver
        // is the harder blocker, so it decides the verdict.
        if kernelDrivers.isEmpty {
            return .userspaceProcess(clients: unique)
        }
        return .kernelDriver(drivers: kernelDrivers)
    }

    private func intProperty(_ service: io_service_t, _ key: String) -> Int? {
        guard let ref = ioKit.registryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return (ref.takeRetainedValue() as? NSNumber)?.intValue
    }
}
