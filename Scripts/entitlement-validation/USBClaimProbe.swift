// USBClaimProbe.swift
//
// Standalone diagnostic that answers, empirically, one question:
//
//   "What can an unprivileged/privileged userspace process on macOS actually do
//    with an attached USB device, and does adding com.apple.security.device.usb
//    change the answer?"
//
// It is deliberately standalone (no USBIPDCore dependency) so the same source can
// be compiled once and then re-signed with several different entitlement sets
// without rebuilding the package. Driven by Scripts/validate-usb-entitlements.sh.
//
// Everything it does is non-destructive by default: it enumerates devices, walks
// the IORegistry to find which kernel driver currently owns each one, and attempts
// a plain open()/close() cycle. Seizing a device away from another client only
// happens with an explicit --seize flag.

import Foundation
import IOKit
import IOKit.usb

// MARK: - IOKit plugin constants
//
// These are C macros that Swift cannot import, so they are reconstructed here with
// the same byte values used by Sources/USBIPDCore/Device/IOKitUSBInterface.swift.

private let kIOUSBDeviceUserClientTypeID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xd4,
    0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

private let kIOCFPlugInInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil,
    0xc2, 0x44, 0xe8, 0x58, 0x10, 0x9c, 0x11, 0xd4,
    0x91, 0xd4, 0x00, 0x50, 0xe4, 0xc6, 0x42, 0x6f)

private let kIOUSBDeviceInterfaceID300 = CFUUIDGetConstantUUIDWithBytes(nil,
    0x39, 0x61, 0x04, 0xf7, 0x94, 0x3d, 0x48, 0x93,
    0x90, 0xf1, 0x69, 0xbd, 0x6c, 0xf5, 0xc2, 0xeb)

private let kIOUSBInterfaceUserClientTypeID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x2d, 0x97, 0x86, 0xc6, 0x9e, 0xf3, 0x11, 0xd4,
    0xad, 0x51, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

private let kIOUSBInterfaceInterfaceID300 = CFUUIDGetConstantUUIDWithBytes(nil,
    0xbc, 0xea, 0xad, 0xdc, 0x88, 0x4d, 0x4f, 0x27,
    0x83, 0x40, 0x36, 0xd6, 0x9f, 0xab, 0x90, 0xf6)

private let servicePlane = "IOService"

// MARK: - IOReturn decoding

private let ioReturnNames: [UInt32: String] = [
    0x0000_0000: "kIOReturnSuccess",
    0xe000_0001: "kIOReturnInvalid",
    0xe000_02bc: "kIOReturnError",
    0xe000_02bd: "kIOReturnNoMemory",
    0xe000_02be: "kIOReturnNoResources",
    0xe000_02bf: "kIOReturnIPCError",
    0xe000_02c0: "kIOReturnNoDevice",
    0xe000_02c1: "kIOReturnNotPrivileged",
    0xe000_02c2: "kIOReturnBadArgument",
    0xe000_02c3: "kIOReturnLockedRead",
    0xe000_02c4: "kIOReturnLockedWrite",
    0xe000_02c5: "kIOReturnExclusiveAccess",
    0xe000_02c6: "kIOReturnBadMessageID",
    0xe000_02c7: "kIOReturnUnsupported",
    0xe000_02c8: "kIOReturnVMError",
    0xe000_02c9: "kIOReturnInternalError",
    0xe000_02ca: "kIOReturnIOError",
    0xe000_02cc: "kIOReturnCannotLock",
    0xe000_02cd: "kIOReturnNotOpen",
    0xe000_02ce: "kIOReturnNotReadable",
    0xe000_02cf: "kIOReturnNotWritable",
    0xe000_02d0: "kIOReturnNotAligned",
    0xe000_02d1: "kIOReturnBadMedia",
    0xe000_02d2: "kIOReturnStillOpen",
    0xe000_02d3: "kIOReturnRLDError",
    0xe000_02d4: "kIOReturnDMAError",
    0xe000_02d5: "kIOReturnBusy",
    0xe000_02d6: "kIOReturnTimeout",
    0xe000_02d7: "kIOReturnOffline",
    0xe000_02d8: "kIOReturnNotReady",
    0xe000_02d9: "kIOReturnNotAttached",
    0xe000_02da: "kIOReturnNoChannels",
    0xe000_02db: "kIOReturnNoSpace",
    0xe000_02dd: "kIOReturnPortExists",
    0xe000_02de: "kIOReturnCannotWire",
    0xe000_02df: "kIOReturnNoInterrupt",
    0xe000_02e0: "kIOReturnNoFrames",
    0xe000_02e1: "kIOReturnMessageTooLarge",
    0xe000_02e2: "kIOReturnNotPermitted",
    0xe000_02e3: "kIOReturnNoPower",
    0xe000_02e4: "kIOReturnNoMedia",
    0xe000_02e5: "kIOReturnUnformattedMedia",
    0xe000_02e6: "kIOReturnUnsupportedMode",
    0xe000_02e7: "kIOReturnUnderrun",
    0xe000_02e8: "kIOReturnOverrun",
    0xe000_02e9: "kIOReturnDeviceError",
    0xe000_02f0: "kIOReturnNotFound"
]

private func describeIOReturn(_ code: Int32) -> String {
    let raw = UInt32(bitPattern: code)
    let hex = "0x" + String(raw, radix: 16)
    if let name = ioReturnNames[raw] {
        return "\(name) (\(hex))"
    }
    return "unknown (\(hex))"
}

private func isSuccess(_ code: Int32) -> Bool {
    return code == 0
}

// MARK: - Report model

struct DriverNode: Codable {
    let className: String
    let depth: Int
}

struct InterfaceReport: Codable {
    let interfaceNumber: Int?
    let interfaceClass: Int?
    let interfaceSubClass: Int?
    let interfaceProtocol: Int?
    /// Classes of IORegistry children of this interface. A non-empty list means a
    /// kernel driver is already matched against the interface.
    let attachedDrivers: [String]
    let pluginResult: String
    let openResult: String?
    let openSeizeResult: String?
}

struct DeviceReport: Codable {
    let locationID: String
    let vendorID: Int
    let productID: Int
    let vendorName: String?
    let productName: String?
    let serialNumber: String?
    let deviceClass: Int?
    let deviceSubClass: Int?
    let deviceProtocol: Int?
    let registryClass: String
    let currentConfiguration: Int?
    /// Every IORegistry descendant class below the device node, excluding the
    /// structural USB nodes. Non-empty means something in the kernel owns it.
    let descendantDrivers: [DriverNode]
    let kernelDriverAttached: Bool
    let pluginResult: String
    let openResult: String?
    let openSeizeResult: String?
    let interfaceIteratorResult: String?
    let interfaces: [InterfaceReport]
    /// One-line interpretation of the results above.
    let verdict: String

    var key: String {
        return String(format: "%04x:%04x@%@", vendorID, productID, locationID)
    }

    var label: String {
        let name = productName ?? "(unnamed)"
        return String(format: "%04x:%04x %@", vendorID, productID, name)
    }
}

struct ProbeRun: Codable {
    let variant: String
    let timestamp: String
    let osVersion: String
    let euid: UInt32
    let seizeEnabled: Bool
    let devices: [DeviceReport]
}

// MARK: - IORegistry helpers

private func defaultMainPort() -> mach_port_t {
    if #available(macOS 12.0, *) {
        return kIOMainPortDefault
    }
    return kIOMasterPortDefault
}

private func copyClassName(_ object: io_object_t) -> String {
    guard let cls = IOObjectCopyClass(object)?.takeRetainedValue() else {
        return "(unknown)"
    }
    return cls as String
}

private func intProperty(_ entry: io_registry_entry_t, _ key: String) -> Int? {
    guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() else {
        return nil
    }
    guard let number = value as? NSNumber else { return nil }
    return number.intValue
}

private func stringProperty(_ entry: io_registry_entry_t, _ key: String) -> String? {
    guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() else {
        return nil
    }
    return value as? String
}

private func registryEntryID(_ entry: io_registry_entry_t) -> UInt64 {
    var identifier: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(entry, &identifier) == KERN_SUCCESS else { return 0 }
    return identifier
}

/// IORegistry classes that are part of the USB stack's own scaffolding rather than
/// a driver that has taken ownership of the device.
private let structuralClasses: Set<String> = [
    "IOUSBHostDevice",
    "IOUSBDevice",
    "IOUSBHostInterface",
    "IOUSBInterface",
    "IOUSBHostLegacyClient",
    "AppleUSBHostLegacyClient",
    "IOUSBHostLegacyDevice",
    "IOUSBHostLegacyInterface"
]

private func childServices(of entry: io_registry_entry_t) -> [io_registry_entry_t] {
    var iterator: io_iterator_t = 0
    guard IORegistryEntryGetChildIterator(entry, servicePlane, &iterator) == KERN_SUCCESS else {
        return []
    }
    defer { IOObjectRelease(iterator) }

    var results: [io_registry_entry_t] = []
    var child = IOIteratorNext(iterator)
    while child != 0 {
        results.append(child)
        child = IOIteratorNext(iterator)
    }
    return results
}

/// Walks the whole subtree below a device node and records every non-structural class.
private func collectDescendantDrivers(_ entry: io_registry_entry_t, depth: Int = 1) -> [DriverNode] {
    var nodes: [DriverNode] = []
    for child in childServices(of: entry) {
        defer { IOObjectRelease(child) }
        let className = copyClassName(child)
        if !structuralClasses.contains(className) {
            nodes.append(DriverNode(className: className, depth: depth))
        }
        nodes.append(contentsOf: collectDescendantDrivers(child, depth: depth + 1))
    }
    return nodes
}

/// Immediate driver children of a single interface node.
private func attachedDriverClasses(_ interfaceService: io_service_t) -> [String] {
    var classes: [String] = []
    for child in childServices(of: interfaceService) {
        defer { IOObjectRelease(child) }
        let className = copyClassName(child)
        if !structuralClasses.contains(className) {
            classes.append(className)
        }
    }
    return classes
}

// MARK: - Device enumeration

private func enumerateUSBDevices() -> [io_service_t] {
    var seen = Set<UInt64>()
    var devices: [io_service_t] = []

    // IOUSBHostDevice is the modern class; IOUSBDevice still matches via the legacy
    // compatibility shim. Query both and de-duplicate on registry entry ID so the
    // probe behaves the same across macOS versions.
    for className in ["IOUSBHostDevice", "IOUSBDevice"] {
        guard let matching = IOServiceMatching(className) else { continue }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(defaultMainPort(), matching, &iterator) == KERN_SUCCESS else {
            continue
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            let identifier = registryEntryID(service)
            if identifier != 0 && seen.contains(identifier) {
                IOObjectRelease(service)
            } else {
                seen.insert(identifier)
                devices.append(service)
            }
            service = IOIteratorNext(iterator)
        }
    }
    return devices
}

// MARK: - Open attempts

private struct OpenAttempt {
    var pluginResult: String
    var openResult: String?
    var openSeizeResult: String?
    var interfaceIteratorResult: String?
    var interfaces: [InterfaceReport] = []
}

private func probeInterfaces(
    deviceInterface: UnsafeMutablePointer<IOUSBDeviceInterface300>,
    attempt: inout OpenAttempt,
    options: Options
) {
    var request = IOUSBFindInterfaceRequest()
    request.bInterfaceClass = UInt16(kIOUSBFindInterfaceDontCare)
    request.bInterfaceSubClass = UInt16(kIOUSBFindInterfaceDontCare)
    request.bInterfaceProtocol = UInt16(kIOUSBFindInterfaceDontCare)
    request.bAlternateSetting = UInt16(kIOUSBFindInterfaceDontCare)

    var iterator: io_iterator_t = 0
    let iteratorResult = deviceInterface.pointee.CreateInterfaceIterator(deviceInterface, &request, &iterator)
    attempt.interfaceIteratorResult = describeIOReturn(iteratorResult)
    guard isSuccess(iteratorResult) else { return }
    defer { IOObjectRelease(iterator) }

    var interfaceService = IOIteratorNext(iterator)
    while interfaceService != 0 {
        defer {
            IOObjectRelease(interfaceService)
            interfaceService = IOIteratorNext(iterator)
        }

        let drivers = attachedDriverClasses(interfaceService)
        var pluginDescription = "not attempted"
        var openDescription: String?
        var seizeDescription: String?

        if !options.listOnly {
            var plugin: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
            var score: Int32 = 0
            let pluginResult = IOCreatePlugInInterfaceForService(
                interfaceService,
                kIOUSBInterfaceUserClientTypeID,
                kIOCFPlugInInterfaceID,
                &plugin,
                &score
            )
            pluginDescription = describeIOReturn(pluginResult)

            if isSuccess(pluginResult), let plugin = plugin {
                var raw: UnsafeMutableRawPointer?
                let queryResult = plugin.pointee?.pointee.QueryInterface(
                    plugin,
                    CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300),
                    &raw
                )
                _ = plugin.pointee?.pointee.Release(plugin)

                if queryResult == S_OK, let raw = raw {
                    let usbInterface = raw.assumingMemoryBound(to: IOUSBInterfaceInterface300.self)
                    let openResult = usbInterface.pointee.USBInterfaceOpen(usbInterface)
                    openDescription = describeIOReturn(openResult)
                    if isSuccess(openResult) {
                        _ = usbInterface.pointee.USBInterfaceClose(usbInterface)
                    } else if options.seize {
                        let seizeResult = usbInterface.pointee.USBInterfaceOpenSeize(usbInterface)
                        seizeDescription = describeIOReturn(seizeResult)
                        if isSuccess(seizeResult) {
                            _ = usbInterface.pointee.USBInterfaceClose(usbInterface)
                        }
                    }
                    _ = usbInterface.pointee.Release(usbInterface)
                } else {
                    pluginDescription += " / QueryInterface failed"
                }
            }
        }

        attempt.interfaces.append(InterfaceReport(
            interfaceNumber: intProperty(interfaceService, "bInterfaceNumber"),
            interfaceClass: intProperty(interfaceService, "bInterfaceClass"),
            interfaceSubClass: intProperty(interfaceService, "bInterfaceSubClass"),
            interfaceProtocol: intProperty(interfaceService, "bInterfaceProtocol"),
            attachedDrivers: drivers,
            pluginResult: pluginDescription,
            openResult: openDescription,
            openSeizeResult: seizeDescription
        ))
    }
}

private func probeDevice(_ service: io_service_t, options: Options) -> OpenAttempt {
    var attempt = OpenAttempt(pluginResult: "not attempted", openResult: nil, openSeizeResult: nil,
                              interfaceIteratorResult: nil)
    guard !options.listOnly else { return attempt }

    var plugin: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
    var score: Int32 = 0
    let pluginResult = IOCreatePlugInInterfaceForService(
        service,
        kIOUSBDeviceUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &plugin,
        &score
    )
    attempt.pluginResult = describeIOReturn(pluginResult)
    guard isSuccess(pluginResult), let plugin = plugin else { return attempt }

    var raw: UnsafeMutableRawPointer?
    let queryResult = plugin.pointee?.pointee.QueryInterface(
        plugin,
        CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID300),
        &raw
    )
    _ = plugin.pointee?.pointee.Release(plugin)

    guard queryResult == S_OK, let raw = raw else {
        attempt.pluginResult += " / QueryInterface failed"
        return attempt
    }
    let deviceInterface = raw.assumingMemoryBound(to: IOUSBDeviceInterface300.self)
    defer { _ = deviceInterface.pointee.Release(deviceInterface) }

    let openResult = deviceInterface.pointee.USBDeviceOpen(deviceInterface)
    attempt.openResult = describeIOReturn(openResult)
    var deviceIsOpen = isSuccess(openResult)

    if !deviceIsOpen && options.seize {
        let seizeResult = deviceInterface.pointee.USBDeviceOpenSeize(deviceInterface)
        attempt.openSeizeResult = describeIOReturn(seizeResult)
        deviceIsOpen = isSuccess(seizeResult)
    }

    // Interface enumeration works whether or not the device itself opened, and the
    // interface-level result is the one that matters for USB/IP: that is the level a
    // kernel driver binds at.
    probeInterfaces(deviceInterface: deviceInterface, attempt: &attempt, options: options)

    if deviceIsOpen {
        _ = deviceInterface.pointee.USBDeviceClose(deviceInterface)
    }
    return attempt
}

// MARK: - Verdict

private func verdict(kernelDriverAttached: Bool, attempt: OpenAttempt, options: Options) -> String {
    if options.listOnly {
        return kernelDriverAttached ? "kernel driver bound (no open attempted)" : "unbound (no open attempted)"
    }

    let openedDevice = attempt.openResult.map { $0.hasPrefix("kIOReturnSuccess") } ?? false
    let interfacesOpened = attempt.interfaces.filter { ($0.openResult ?? "").hasPrefix("kIOReturnSuccess") }.count
    let interfacesTotal = attempt.interfaces.count

    if interfacesTotal > 0 && interfacesOpened == interfacesTotal && openedDevice {
        return "USABLE TODAY — full userspace access without any special entitlement"
    }
    if interfacesOpened > 0 {
        return "PARTIAL — \(interfacesOpened)/\(interfacesTotal) interfaces open; the rest are held by a kernel driver"
    }
    if kernelDriverAttached {
        return "BLOCKED — kernel driver owns the device; requires DriverKit-level rebinding"
    }
    if !openedDevice {
        return "BLOCKED — device open refused (\(attempt.openResult ?? "n/a"))"
    }
    return "INCONCLUSIVE — device opened but no interfaces were enumerable"
}

// MARK: - Options

struct Options {
    var variant = "unspecified"
    var jsonPath: String?
    var seize = false
    var listOnly = false
    var includeApple = false
    var includeHubs = false
    var compareInputs: [String] = []
    var markdownPath: String?
}

private func parseOptions() -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())

    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--variant":
            options.variant = arguments.isEmpty ? "unspecified" : arguments.removeFirst()
        case "--json":
            options.jsonPath = arguments.isEmpty ? nil : arguments.removeFirst()
        case "--markdown":
            options.markdownPath = arguments.isEmpty ? nil : arguments.removeFirst()
        case "--seize":
            options.seize = true
        case "--list-only":
            options.listOnly = true
        case "--include-apple":
            options.includeApple = true
        case "--include-hubs":
            options.includeHubs = true
        case "--compare":
            // Consume paths up to the next flag so --markdown can follow --compare.
            while let next = arguments.first, !next.hasPrefix("--") {
                options.compareInputs.append(arguments.removeFirst())
            }
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            FileHandle.standardError.write("Unknown argument: \(argument)\n".data(using: .utf8)!)
            printUsage()
            exit(2)
        }
    }
    return options
}

private func printUsage() {
    print("""
    usb-claim-probe — measure what userspace can do with attached USB devices

    Usage:
      usb-claim-probe [--variant NAME] [--json PATH] [--list-only]
                      [--seize] [--include-apple] [--include-hubs]
      usb-claim-probe --compare run1.json run2.json ... [--markdown PATH]

    Options:
      --variant NAME    Label recorded in the JSON output (e.g. the entitlement set)
      --json PATH       Write machine-readable results to PATH. Use "-" for stdout,
                        which moves the human-readable table to stderr — required for
                        sandboxed variants, which cannot write to arbitrary paths.
      --markdown PATH   In --compare mode, write the comparison table to PATH
      --list-only       Enumerate and show driver ownership; attempt no opens
      --seize           If a plain open is refused, also try OpenSeize. This can
                        disconnect a device from its current driver — opt-in only.
      --include-apple   Include Apple-vendor (0x05ac) devices, skipped by default
      --include-hubs    Include USB hubs, skipped by default
      --compare         Read several JSON runs and print a cross-variant matrix
    """)
}

// MARK: - Comparison mode

private func runComparison(_ options: Options) {
    var runs: [ProbeRun] = []
    let decoder = JSONDecoder()
    for path in options.compareInputs {
        guard let data = FileManager.default.contents(atPath: path) else {
            FileHandle.standardError.write("Cannot read \(path)\n".data(using: .utf8)!)
            continue
        }
        do {
            runs.append(try decoder.decode(ProbeRun.self, from: data))
        } catch {
            FileHandle.standardError.write("Cannot parse \(path): \(error)\n".data(using: .utf8)!)
        }
    }

    guard !runs.isEmpty else {
        FileHandle.standardError.write("No usable runs to compare\n".data(using: .utf8)!)
        exit(1)
    }

    var deviceKeys: [String] = []
    var labels: [String: String] = [:]
    for run in runs {
        for device in run.devices where !deviceKeys.contains(device.key) {
            deviceKeys.append(device.key)
            labels[device.key] = device.label
        }
    }

    var lines: [String] = []
    lines.append("# USB entitlement validation results")
    lines.append("")
    lines.append("- Host: macOS \(runs[0].osVersion)")
    lines.append("- Generated: \(runs[0].timestamp)")
    lines.append("- Variants compared: \(runs.map { $0.variant }.joined(separator: ", "))")
    lines.append("")
    lines.append("## Device open results by entitlement variant")
    lines.append("")

    let header = "| Device | Kernel driver | " + runs.map { "`\($0.variant)`" }.joined(separator: " | ") + " |"
    let divider = "| --- | --- | " + runs.map { _ in "---" }.joined(separator: " | ") + " |"
    lines.append(header)
    lines.append(divider)

    var identicalAcrossVariants = true
    for key in deviceKeys {
        var cells: [String] = []
        var reference: String?
        var driverCell = "—"
        for run in runs {
            guard let device = run.devices.first(where: { $0.key == key }) else {
                cells.append("not present")
                continue
            }
            driverCell = device.descendantDrivers.isEmpty
                ? "none"
                : device.descendantDrivers.map { $0.className }.joined(separator: ", ")
            let opened = device.interfaces.filter { ($0.openResult ?? "").hasPrefix("kIOReturnSuccess") }.count
            let cell = "\(opened)/\(device.interfaces.count) ifaces · \(device.openResult ?? "n/a")"
            cells.append(cell)
            if reference == nil {
                reference = cell
            } else if reference != cell {
                identicalAcrossVariants = false
            }
        }
        lines.append("| \(labels[key] ?? key) | \(driverCell) | " + cells.joined(separator: " | ") + " |")
    }

    lines.append("")
    lines.append("## Interpretation")
    lines.append("")
    if identicalAcrossVariants {
        lines.append("**Every variant produced identical results.** Adding "
            + "`com.apple.security.device.usb` did not change what userspace can do with any "
            + "attached device, which is the expected outcome for a non-sandboxed process: that "
            + "entitlement only relaxes App Sandbox restrictions and is not the gate on detaching "
            + "a device from its in-kernel driver.")
    } else {
        lines.append("**Results differ between variants.** The per-device rows above show which "
            + "entitlement set changed the outcome; that difference is the finding to report.")
    }
    lines.append("")
    lines.append("Devices whose `Kernel driver` column reads `none` are already fully usable from "
        + "userspace with no entitlement at all. Devices with a driver listed are the ones a "
        + "USB/IP server cannot serve without DriverKit-level rebinding.")
    lines.append("")

    for run in runs {
        lines.append("### Variant `\(run.variant)`")
        lines.append("")
        lines.append("- euid: \(run.euid)\(run.euid == 0 ? " (root)" : " (non-root)")")
        lines.append("- seize attempted: \(run.seizeEnabled)")
        lines.append("")
        for device in run.devices {
            lines.append("- **\(device.label)** — \(device.verdict)")
            for interface in device.interfaces {
                let number = interface.interfaceNumber.map(String.init) ?? "?"
                let drivers = interface.attachedDrivers.isEmpty
                    ? "no driver"
                    : interface.attachedDrivers.joined(separator: ", ")
                let open = interface.openResult ?? "not attempted"
                let seize = interface.openSeizeResult.map { ", seize: \($0)" } ?? ""
                lines.append("  - iface \(number) (class \(interface.interfaceClass.map(String.init) ?? "?")): "
                    + "\(drivers) — open: \(open)\(seize)")
            }
        }
        lines.append("")
    }

    let markdown = lines.joined(separator: "\n")
    print(markdown)
    if let path = options.markdownPath {
        try? markdown.write(toFile: path, atomically: true, encoding: .utf8)
        FileHandle.standardError.write("Report written to \(path)\n".data(using: .utf8)!)
    }
}

// MARK: - Main

let options = parseOptions()

if !options.compareInputs.isEmpty {
    runComparison(options)
    exit(0)
}

if options.seize {
    FileHandle.standardError.write(
        "WARNING: --seize will attempt to take devices away from their current driver.\n"
            .data(using: .utf8)!)
}

var reports: [DeviceReport] = []

for service in enumerateUSBDevices() {
    defer { IOObjectRelease(service) }

    guard let vendorID = intProperty(service, "idVendor"),
          let productID = intProperty(service, "idProduct") else {
        continue
    }
    let deviceClass = intProperty(service, "bDeviceClass")

    if vendorID == 0x05ac && !options.includeApple { continue }
    if deviceClass == 9 && !options.includeHubs { continue }

    let locationID = intProperty(service, "locationID").map { String($0, radix: 16) } ?? "unknown"
    let descendants = collectDescendantDrivers(service)
    let attempt = probeDevice(service, options: options)

    reports.append(DeviceReport(
        locationID: locationID,
        vendorID: vendorID,
        productID: productID,
        vendorName: stringProperty(service, "USB Vendor Name"),
        productName: stringProperty(service, "USB Product Name"),
        serialNumber: stringProperty(service, "USB Serial Number"),
        deviceClass: deviceClass,
        deviceSubClass: intProperty(service, "bDeviceSubClass"),
        deviceProtocol: intProperty(service, "bDeviceProtocol"),
        registryClass: copyClassName(service),
        currentConfiguration: intProperty(service, "kUSBCurrentConfiguration"),
        descendantDrivers: descendants,
        kernelDriverAttached: !descendants.isEmpty,
        pluginResult: attempt.pluginResult,
        openResult: attempt.openResult,
        openSeizeResult: attempt.openSeizeResult,
        interfaceIteratorResult: attempt.interfaceIteratorResult,
        interfaces: attempt.interfaces,
        verdict: verdict(kernelDriverAttached: !descendants.isEmpty, attempt: attempt, options: options)
    ))
}

// When JSON goes to stdout the human-readable table moves to stderr so the two
// streams stay separable. A sandboxed variant cannot write to an arbitrary path,
// so stdout redirection is the only way to collect its results.
let jsonToStdout = options.jsonPath == "-"
func emit(_ line: String) {
    if jsonToStdout {
        FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
    } else {
        print(line)
    }
}

let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
let formatter = ISO8601DateFormatter()
let run = ProbeRun(
    variant: options.variant,
    timestamp: formatter.string(from: Date()),
    osVersion: osVersion,
    euid: geteuid(),
    seizeEnabled: options.seize,
    devices: reports
)

emit("variant: \(run.variant)   euid: \(run.euid)   \(osVersion)")
emit(String(repeating: "-", count: 78))
if reports.isEmpty {
    emit("No non-Apple, non-hub USB devices found.")
    emit("Attach a device you want to share, or re-run with --include-apple --include-hubs.")
}
for device in reports {
    emit("\(device.label)  [\(device.registryClass) @ \(device.locationID)]")
    let drivers = device.descendantDrivers.isEmpty
        ? "none"
        : device.descendantDrivers.map { $0.className }.joined(separator: ", ")
    emit("  kernel drivers : \(drivers)")
    emit("  device open    : \(device.openResult ?? "not attempted")")
    if let seize = device.openSeizeResult {
        emit("  device seize   : \(seize)")
    }
    for interface in device.interfaces {
        let number = interface.interfaceNumber.map(String.init) ?? "?"
        let attached = interface.attachedDrivers.isEmpty
            ? "no driver"
            : interface.attachedDrivers.joined(separator: ", ")
        emit("  iface \(number)        : \(attached) — open: \(interface.openResult ?? "not attempted")"
            + (interface.openSeizeResult.map { ", seize: \($0)" } ?? ""))
    }
    emit("  verdict        : \(device.verdict)")
    emit("")
}

if let jsonPath = options.jsonPath {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        let data = try encoder.encode(run)
        if jsonToStdout {
            FileHandle.standardOutput.write(data)
        } else {
            try data.write(to: URL(fileURLWithPath: jsonPath))
            FileHandle.standardError.write("JSON written to \(jsonPath)\n".data(using: .utf8)!)
        }
    } catch {
        FileHandle.standardError.write("Failed to write JSON: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
