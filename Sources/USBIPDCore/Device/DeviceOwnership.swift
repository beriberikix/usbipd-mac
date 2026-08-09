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

    /// The device exposes no interfaces at all, so there is nothing to open.
    ///
    /// Usually this means macOS has not configured it — no configuration is selected,
    /// so no interface nodes exist — which is common for devices another process is
    /// driving directly, such as a WebUSB page in a browser. Reporting it as free was
    /// worse than useless: `bind` accepted the device, announced that nothing held it,
    /// and then every transfer failed with "Interface 0 not found".
    case noInterfaces

    /// Some interfaces are free and others are owned. Common on debug probes, which
    /// pair a vendor-specific debug interface with a CDC serial port that macOS claims:
    /// a Raspberry Pi Debug Probe has CMSIS-DAP free on interface 0 while
    /// AppleUSBACMControl holds the serial interfaces. Treating that as fully owned
    /// refused hardware that works, which is most of what this project is for.
    case partiallyClaimed(freeInterfaces: [Int], claimedBy: [String])

    /// Whether anything can be served. A device with one free interface is usable —
    /// the debug half of a composite probe is exactly the part anyone wants.
    public var isServable: Bool {
        switch self {
        case .unbound, .partiallyClaimed:
            return true
        case .kernelDriver, .userspaceProcess, .noInterfaces:
            return false
        }
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
    /// Per interface: the drivers attached to it, and whether it can actually be opened.
    ///
    /// Both are needed. The open attempt decides whether the interface is usable; the
    /// driver names are only there to tell the user who is holding one that is not.
    private func collectClaimants(of deviceEntry: io_registry_entry_t) -> [(drivers: [String], opens: Bool)] {
        var perInterface: [(drivers: [String], opens: Bool)] = []
        for interfaceEntry in interfaceNodes(under: deviceEntry) {
            defer { _ = ioKit.objectRelease(interfaceEntry) }
            let drivers = immediateDrivers(of: interfaceEntry)
            // Only probe interfaces something has matched against. An interface with no
            // driver is free by definition, and opening it needlessly would disturb it.
            let opens = drivers.isEmpty ? true : ioKit.usbInterfaceOpens(interfaceEntry)
            perInterface.append((drivers: drivers, opens: opens))
        }
        return perInterface
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

    private func classify(_ perInterface: [(drivers: [String], opens: Bool)]) -> DeviceOwnership {
        // Distinguish "no interfaces exist" from "interfaces exist and nothing has
        // claimed them". Both used to arrive here with no driver names and both were
        // called unbound, so a device with nothing to open was offered for sharing.
        guard !perInterface.isEmpty else { return .noInterfaces }

        let all = perInterface.flatMap { $0.drivers }
        guard !all.isEmpty else { return .unbound }

        // Usable means it opened, not that nothing is attached. An FTDI or CP210x has
        // IOUserSerial on every interface and opens regardless.
        let free = perInterface.enumerated().filter { $0.element.opens }.map { $0.offset }

        // If every interface opens, the drivers present are not holding anything, so
        // there is nothing to warn about.
        if free.count == perInterface.count {
            return .unbound
        }

        // Report only the drivers on interfaces that actually refused, so the message
        // names what is really in the way.
        let blocking = perInterface.filter { !$0.opens }.flatMap { $0.drivers }
        let unique = Array(Set(blocking)).sorted()
        let kernelDrivers = unique.filter { !userspaceClientClasses.contains($0) }

        // At least one interface is unclaimed, so there is something to serve. This is
        // the ordinary shape of a debug probe: a free vendor-specific interface next to
        // a CDC serial port macOS has taken.
        if !free.isEmpty {
            return .partiallyClaimed(freeInterfaces: free,
                                     claimedBy: kernelDrivers.isEmpty ? unique : kernelDrivers)
        }

        // Every interface is spoken for. A device can be claimed by both kinds — a
        // webcam's audio control interface is kernel-owned while its video interfaces
        // are held by the camera framework. A kernel driver is the harder blocker, so
        // it decides the verdict.
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
