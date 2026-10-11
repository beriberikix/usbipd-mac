// IOKitUSBDevice.swift
// One IOKit session per served device: every interface this process may open, and a
// route from each endpoint to the interface that owns it.

import Foundation
import IOKit
import IOKit.usb
import Common

// IOKit constants manually defined since macros are unavailable
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

/// IOKit's IOUSBLib interfaces are COM-style. QueryInterface hands back a pointer TO
/// a pointer to the interface struct, and every method takes that handle as its own
/// first argument — the C idiom is `(*handle)->Method(handle)`.
///
/// Binding the QueryInterface result one level too shallow (as the struct rather than
/// as a pointer to it) reads every function pointer from the wrong offset, so the first
/// call jumps to a garbage address. The symptom is SIGBUS / EXC_ARM_DA_ALIGN with a
/// destroyed stack, on first contact with real hardware.
typealias USBDeviceHandle = UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface300>?>
typealias USBInterfaceHandle = UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface300>?>

extension UnsafeMutablePointer where Pointee == UnsafeMutablePointer<IOUSBDeviceInterface300>? {
    /// The vtable behind the handle. Non-nil for any handle this file constructs:
    /// handles are only ever built from a QueryInterface that returned S_OK with a
    /// non-nil result, and are discarded on release.
    var vtable: IOUSBDeviceInterface300 { return pointee!.pointee }
}

extension UnsafeMutablePointer where Pointee == UnsafeMutablePointer<IOUSBInterfaceInterface300>? {
    /// See the device-handle counterpart above.
    var vtable: IOUSBInterfaceInterface300 { return pointee!.pointee }
}

/// An IOKit session for one USB device.
///
/// This used to be one interface, and it was always interface 0. Every transfer went
/// through it: control requests needed it open, and only its pipes were discovered. That
/// served single-interface devices and nothing else, and failed three ways on a
/// composite one:
///
/// - A device whose interface 0 macOS holds could not even enumerate. A FreeWili 2's main
///   processor leads with a CDC-ACM control interface, which AppleUSBACMControl keeps, so
///   the client's very first GET_DESCRIPTOR failed with kIOReturnExclusiveAccess.
/// - Endpoints on any other interface did not exist. A multi-target CMSIS-DAP probe
///   served its first target and returned "No pipe for endpoint" for the rest.
/// - A failed interface open leaked the device open that preceded it, because close()
///   only undid a fully successful open. The device then stayed held exclusively and
///   every retry failed at USBDeviceOpen instead.
///
/// Now the session opens every interface macOS lets go of and routes each endpoint to
/// its owner. Control requests go to the device's default pipe, which needs no
/// interface: IOKit forwards a class request addressed to an interface this process
/// does not own, so a client can set a held CDC port's line coding and DTR — measured
/// against AppleUSBACMControl on a FreeWili 2 and its RP2040 probe. Endpoints of the
/// interfaces macOS keeps are parked rather than failed; see `parkUntilCancelled`.
public final class IOKitUSBDevice: @unchecked Sendable {

    // MARK: - Properties

    private let device: USBDevice
    private let logger: Logger

    private var service: io_service_t = 0
    private var deviceInterface: USBDeviceHandle?

    /// USBDeviceOpen is not required for anything this class does, and may be refused
    /// while another client has the device open. Remembered only so close() undoes it.
    private var deviceOpened = false

    /// Interfaces this process opened, by bInterfaceNumber.
    private var openInterfaces: [UInt8: USBInterfaceHandle] = [:]

    /// Interfaces another driver holds, with the alternate setting they are at.
    private var heldInterfaces: [UInt8: UInt8] = [:]

    /// Endpoint address -> the opened interface that owns it and its IOKit pipe.
    ///
    /// IOKit addresses pipes by a 1-based index into the interface, which is not the
    /// endpoint number. The two coincide on simple devices and diverge as soon as an
    /// interface has gaps or more than a couple of endpoints, so deriving one from the
    /// other was only ever going to work by accident.
    private var pipes: [UInt8: Pipe] = [:]

    private struct Pipe {
        let interfaceNumber: UInt8
        let pipeRef: UInt8
        let transferType: UInt8
    }

    /// Every endpoint the configuration declares, including those IOKit will not show.
    private var declaredEndpoints: [UInt8: USBEndpointOwner] = [:]

    /// One wake-up per parked endpoint. See `parkUntilCancelled`.
    private var parkingSignals: [UInt8: DispatchSemaphore] = [:]

    /// Interfaces closed but not yet released. See deinit.
    private var releasedOnDeinit: [USBInterfaceHandle] = []

    /// Device handles for instances capture replaced. See deinit.
    private var retiredDeviceInterfaces: [USBDeviceHandle] = []

    /// This session took the device from macOS and owes it back. See captureFromMacOS.
    private var captured = false

    /// Interfaces a mass-storage driver holds. Never opened; see MassStorageBridge.
    private var massStorageInterfaces: Set<UInt8> = []

    /// Bridged mass-storage interfaces by endpoint, and the disks they were built on.
    private var bridges: [UInt8: MassStorageBridge] = [:]
    private var bridgedInterfaces: [UInt8: MassStorageBridge] = [:]
    private var bridgedDisks: [String] = []

    private var isOpen = false
    private var isClosed = false

    /// Guards the tables above. SET_INTERFACE rediscovers an interface's pipes while
    /// transfers on other endpoints look theirs up, and close() can race any of them.
    /// Never held across a transfer — see EndpointQueues for why that would matter.
    private let stateLock = NSLock()

    private let ioKit: IOKitInterface

    /// One serial queue per endpoint, so that a blocking transfer on one endpoint does
    /// not hold up transfers on another. See `EndpointQueues` for why that matters.
    private let endpointQueues = EndpointQueues()

    // MARK: - Initialization

    public init(device: USBDevice, ioKit: IOKitInterface = RealIOKitInterface()) throws {
        self.device = device
        self.ioKit = ioKit
        self.logger = Logger(subsystem: "com.usbipd.core", category: "IOKitUSBDevice")

        service = try findIOKitServiceForDevice()
        deviceInterface = try createDevicePluginInterface()
        logger.info("Successfully initialized IOKit references for device \(device.busID)-\(device.deviceID)")
    }

    deinit {
        close()

        // Released only here. A transfer that looked a handle up just before close()
        // may still be inside ReadPipeTO on it; closing makes that call return, but
        // freeing the object under it would not be survivable. Every transfer holds this
        // session until it finishes, so by the time deinit runs nothing can be.
        for interface in releasedOnDeinit {
            _ = interface.vtable.Release(interface)
        }
        for handle in retiredDeviceInterfaces {
            _ = handle.vtable.Release(handle)
        }
        if let handle = deviceInterface {
            _ = handle.vtable.Release(handle)
        }
        if service != 0 {
            IOObjectRelease(service)
        }
    }

    // MARK: - Lifecycle

    /// Open the device and every interface on it that macOS will release.
    ///
    /// Succeeds as long as the device itself can be reached: an interface another driver
    /// holds is recorded, not fatal, since the client may never touch it.
    public func open() throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isOpen else { return }
        guard !isClosed, let deviceInterface = deviceInterface else {
            throw USBRequestError.deviceNotAvailable
        }

        try openEverything(deviceInterface)

        // Interfaces macOS holds are taken from it, so the client gets the device whole,
        // as if it were plugged in there. Parking those endpoints is only the fallback,
        // for a daemon without root or a device that will not be captured.
        //
        // Mass storage is left out: capture does not detach its driver, and it is
        // bridged from the disk instead, which needs the driver to stay.
        let heldElsewhere = heldInterfaces.keys.filter { !massStorageInterfaces.contains($0) }
        if !heldElsewhere.isEmpty && geteuid() == 0 {
            captureFromMacOS(self.deviceInterface ?? deviceInterface)
        }
        if geteuid() == 0 {
            bridgeMassStorage()
        }
        isOpen = true

        let served = openInterfaces.keys.sorted().map(String.init).joined(separator: ",")
        let held = heldInterfaces.keys.sorted().map(String.init).joined(separator: ",")
        logger.info("Opened device \(device.busID)-\(device.deviceID): interfaces [\(served)] served, [\(held)] held by macOS")
    }

    /// USBDeviceOpen, then every interface this process may open.
    ///
    /// Caller holds `stateLock`.
    private func openEverything(_ deviceInterface: USBDeviceHandle, openDevice: Bool = true) throws {
        openInterfaces.removeAll()
        heldInterfaces.removeAll()
        massStorageInterfaces.removeAll()
        pipes.removeAll()

        // Not required: control requests reach the default pipe without it, and interface
        // opens do not depend on it. Taking it anyway keeps another process from changing
        // the configuration underneath a client that is mid-transfer.
        //
        // Skipped once the device is captured. Nothing else can claim it then, and with
        // the device open a captured card reader refused its interface's user client
        // (kIOReturnNoResources) while a separate process could open the same interface.
        if openDevice {
            let openResult = deviceInterface.vtable.USBDeviceOpen(deviceInterface)
            deviceOpened = openResult == kIOReturnSuccess
            if !deviceOpened {
                logger.info("Device open refused (\(String(format: "0x%08x", openResult))); continuing with interface access only")
            }
        }

        declaredEndpoints = readDeclaredEndpoints(deviceInterface)
        try openAllInterfaces(deviceInterface)
    }

    /// Detach macOS's drivers from the device and take all of it.
    ///
    /// USBDeviceReEnumerate with the capture option terminates every driver on the
    /// device and its interfaces and enumerates it again with none attached. IOUSBLib.h
    /// allows it for root, which this daemon is as a LaunchDaemon — no entitlement. It
    /// is what libusb's "detach kernel driver" does on macOS.
    ///
    /// It was never tried here. What was measured and recorded as impossible was
    /// USBInterfaceOpenSeize, and unmounting, neither of which detaches anything. With
    /// the device captured, a Linux client drives a CDC-ACM control interface itself —
    /// line coding, DTR, notifications — exactly as it would with the board plugged in.
    ///
    /// Mass-storage interfaces are the documented exception: capture leaves their
    /// driver alone, and they are bridged rather than opened. See MassStorageBridge.
    ///
    /// On any failure the session carries on as it was, with held endpoints parked.
    /// Caller holds `stateLock`.
    private func captureFromMacOS(_ originalInterface: USBDeviceHandle) {
        let held = heldInterfaces.keys.sorted().map(String.init).joined(separator: ",")
        logger.info("Capturing \(device.busID)-\(device.deviceID) from macOS (interfaces [\(held)] held)")

        // Everything opened so far belongs to the device instance that is about to go.
        for interface in openInterfaces.values {
            _ = interface.vtable.USBInterfaceClose(interface)
            releasedOnDeinit.append(interface)
        }
        openInterfaces.removeAll()
        pipes.removeAll()
        if deviceOpened {
            _ = originalInterface.vtable.USBDeviceClose(originalInterface)
            deviceOpened = false
        }

        // Done by a separate process. IOKit treats the task that captured a device
        // differently: it was refused a user client on the captured card reader's
        // mass-storage interface (kIOReturnNoResources) — while any other process,
        // unprivileged included, opened the same interface without complaint. So a
        // short-lived helper captures and exits, and this task only opens.
        let result = Self.runReEnumerateHelper(location: location, capture: true, logger: logger)
        guard result == kIOReturnSuccess else {
            logger.warning("Capture refused (\(String(format: "0x%08x", result))); serving the free interfaces only")
            reopenAfterFailedCapture(originalInterface)
            return
        }

        // The device reappears as a new registry entry. Wait for it, then start over.
        retiredDeviceInterfaces.append(originalInterface)
        deviceInterface = nil
        if service != 0 {
            IOObjectRelease(service)
            service = 0
        }

        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            guard let found = try? findIOKitServiceForDevice() else { continue }
            service = found
            guard let handle = try? createDevicePluginInterface() else {
                IOObjectRelease(found)
                service = 0
                continue
            }
            deviceInterface = handle
            break
        }
        guard let capturedInterface = deviceInterface else {
            logger.error("Captured device did not reappear within 8 s")
            return
        }
        captured = true

        // The device entry comes back before its interfaces do: they are published a
        // moment later, and opening straight away found none — a card reader was
        // served with no interfaces at all and the client reset it in a loop. So wait
        // for them. If they never come, nothing configured the device (its drivers are
        // gone), and setting the configuration is what brings them.
        for attempt in 0..<25 {
            do {
                try openEverything(capturedInterface, openDevice: false)
            } catch {
                logger.debug("Captured device not openable yet: \(error)")
            }
            if !openInterfaces.isEmpty || !heldInterfaces.isEmpty { break }
            if attempt == 10 {
                selectConfiguration(capturedInterface)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        let served = openInterfaces.keys.sorted().map(String.init).joined(separator: ",")
        let stillHeld = heldInterfaces.keys.sorted().map(String.init).joined(separator: ",")
        logger.info("Captured \(device.busID)-\(device.deviceID): interfaces [\(served)] served, [\(stillHeld)] still held")
    }

    /// The device's IOKit locationID. Derived from the busid it was built from.
    private var location: UInt32 {
        return USBDeviceLocation.locationID(busID: device.busID, deviceID: device.deviceID) ?? 0
    }

    /// Capture or release a device from a child process. See captureFromMacOS.
    static func runReEnumerateHelper(location: UInt32, capture: Bool, logger: Logger) -> IOReturn {
        expectReEnumeration(location: location)
        guard let executable = Bundle.main.executableURL else { return kIOReturnNotFound }
        let helper = Process()
        helper.executableURL = executable
        helper.arguments = [reEnumerateHelperCommand, String(location, radix: 16), capture ? "capture" : "release"]
        do {
            try helper.run()
        } catch {
            logger.error("Could not start the re-enumeration helper: \(error)")
            return kIOReturnError
        }
        helper.waitUntilExit()
        endExpectedReEnumeration(location: location)
        // The helper exits with the IOReturn's low byte, plus 1 so that 0 stays success.
        let code = helper.terminationStatus
        return code == 0 ? kIOReturnSuccess : IOReturn(bitPattern: 0xE000_0200 | UInt32(code - 1))
    }

    /// Re-enumerations this daemon caused, by location, with when they were started.
    /// The device disappears and returns as they run, and that must not read as unplug.
    private static var expectedReEnumerations: [UInt32: Date] = [:]
    private static let expectedReEnumerationsLock = NSLock()

    static func expectReEnumeration(location: UInt32) {
        expectedReEnumerationsLock.lock()
        expectedReEnumerations[location] = Date()
        expectedReEnumerationsLock.unlock()
    }

    /// Stop treating disconnects here as ours, a moment after the helper has finished.
    static func endExpectedReEnumeration(location: UInt32) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            expectedReEnumerationsLock.lock()
            expectedReEnumerations.removeValue(forKey: location)
            expectedReEnumerationsLock.unlock()
        }
    }

    /// Whether a disconnect at this busid is one this daemon is causing right now.
    ///
    /// Scoped to the helper actually running, plus a second. A fixed window after the
    /// fact swallowed real unplugs: capture turned out to raise no disconnect at all —
    /// macOS keeps the device object and only detaches its drivers — so the expectation
    /// sat unused until an RP2040 sent into BOOTSEL moments later consumed it, and that
    /// client was never told its device had gone.
    public static func isReEnumerationExpected(busID: String, deviceID: String) -> Bool {
        guard let location = USBDeviceLocation.locationID(busID: busID, deviceID: deviceID) else { return false }
        expectedReEnumerationsLock.lock()
        defer { expectedReEnumerationsLock.unlock() }
        guard let started = expectedReEnumerations[location] else { return false }
        return Date().timeIntervalSince(started) < 10
    }

    /// The hidden subcommand `runReEnumerateHelper` invokes.
    public static let reEnumerateHelperCommand = "__reenumerate"

    /// Entry point for the helper process: `__reenumerate <location-hex> capture|release`.
    /// Returns the exit status.
    public static func reEnumerateHelperMain(_ arguments: [String]) -> Int32 {
        guard arguments.count == 2,
              let location = UInt32(arguments[0], radix: 16),
              arguments[1] == "capture" || arguments[1] == "release" else {
            return 64
        }
        let options = arguments[1] == "capture" ? kUSBReEnumerateCaptureDeviceMask : kUSBReEnumerateReleaseDeviceMask

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(kIOUSBDeviceClassName), &iterator) == KERN_SUCCESS else {
            return 65
        }
        defer { IOObjectRelease(iterator) }

        // A `let` per pass: a defer over a reassigned `var` releases the next entry
        // instead of this one — the bug DeviceOwnership.swift documents.
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }
            let found = (IORegistryEntryCreateCFProperty(entry, "locationID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber)?.uint32Value
            if found == location {
                var plugin: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
                var score: Int32 = 0
                guard IOCreatePlugInInterfaceForService(entry, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID,
                                                        &plugin, &score) == kIOReturnSuccess,
                      let plug = plugin else {
                    return 66
                }
                defer { _ = plug.pointee?.pointee.Release(plug) }
                var raw: UnsafeMutableRawPointer?
                guard plug.pointee?.pointee.QueryInterface(plug, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID300), &raw) == S_OK,
                      let pointer = raw else {
                    return 66
                }
                let handle = pointer.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBDeviceInterface300>?.self)
                defer { _ = handle.vtable.Release(handle) }
                let result = handle.vtable.USBDeviceReEnumerate(handle, UInt32(bitPattern: options.rawValue))
                return result == kIOReturnSuccess ? 0 : Int32(UInt32(bitPattern: result) & 0xFF) + 1
            }
        }
        return 67
    }

    /// Capture failed and the device is unchanged: reopen what was open before.
    private func reopenAfterFailedCapture(_ deviceInterface: USBDeviceHandle) {
        do {
            try openEverything(deviceInterface)
        } catch {
            logger.error("Could not reopen after a refused capture: \(error)")
        }
    }

    /// Set the device's first configuration, which is what macOS's composite driver
    /// would have done had capture not removed it.
    private func selectConfiguration(_ deviceInterface: USBDeviceHandle) {
        var current: UInt8 = 0
        _ = deviceInterface.vtable.GetConfiguration(deviceInterface, &current)
        guard current == 0 else { return }

        var descriptor: IOUSBConfigurationDescriptorPtr?
        guard deviceInterface.vtable.GetConfigurationDescriptorPtr(deviceInterface, 0, &descriptor) == kIOReturnSuccess,
              let value = descriptor?.pointee.bConfigurationValue else {
            logger.warning("Captured device has no readable configuration")
            return
        }
        // SetConfiguration needs the device open; held only for the call. See openEverything.
        let opened = deviceInterface.vtable.USBDeviceOpen(deviceInterface) == kIOReturnSuccess
        let result = deviceInterface.vtable.SetConfiguration(deviceInterface, value)
        if opened {
            _ = deviceInterface.vtable.USBDeviceClose(deviceInterface)
        }
        logger.info("Set configuration \(value) on the captured device: \(String(format: "0x%08x", result))")
    }

    /// Serve each mass-storage interface from its disk. See MassStorageBridge.
    ///
    /// The volume is unmounted first so nothing on this Mac reads or writes it while
    /// the client does. If it will not unmount — a file open on it — the interface is
    /// served as a drive with no medium rather than risk two writers on one filesystem.
    ///
    /// Caller holds `stateLock`.
    private func bridgeMassStorage() {
        for number in massStorageInterfaces.sorted() {
            let owned = declaredEndpoints.filter { $0.value.interfaceNumber == number && $0.value.transferType == 2 }
            guard let inEndpoint = owned.keys.first(where: { $0 & 0x80 != 0 }),
                  let outEndpoint = owned.keys.first(where: { $0 & 0x80 == 0 }) else {
                logger.warning("Mass-storage interface \(number) has no bulk pair; leaving it held")
                continue
            }

            // macOS publishes the disk a few seconds after the device: an RP2040 just
            // rebooted into BOOTSEL was served as "no medium" when looked up at once.
            var bsdDisk = wholeDisk(underInterface: number)
            let deadline = Date().addingTimeInterval(5)
            while bsdDisk == nil && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.25)
                bsdDisk = wholeDisk(underInterface: number)
            }

            var disk: BlockDevice?
            if let bsdName = bsdDisk {
                if runDiskutil(["unmountDisk", "/dev/\(bsdName)"]) {
                    do {
                        disk = try RawDiskBlockDevice(path: "/dev/r\(bsdName)")
                        bridgedDisks.append(bsdName)
                    } catch {
                        logger.error("Could not open /dev/r\(bsdName): \(error)")
                    }
                } else {
                    logger.warning("/dev/\(bsdName) would not unmount; serving interface \(number) with no medium")
                }
            }

            let bridge = MassStorageBridge(
                inEndpoint: inEndpoint, outEndpoint: outEndpoint, device: disk,
                vendor: device.manufacturerString ?? "", product: device.productString ?? "")
            bridges[inEndpoint] = bridge
            bridges[outEndpoint] = bridge
            bridgedInterfaces[number] = bridge
            heldInterfaces.removeValue(forKey: number)

            let medium = disk.map { "\($0.blockCount) x \($0.blockSize) bytes\($0.isWritable ? "" : ", read-only")" } ?? "no medium"
            logger.info("Bridging mass-storage interface \(number) (\(medium))")
        }
    }

    /// BSD name of the whole disk macOS built from one interface, e.g. "disk4".
    private func wholeDisk(underInterface number: UInt8) -> String? {
        var interfaces: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &interfaces) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(interfaces) }

        while true {
            let interface = IOIteratorNext(interfaces)
            guard interface != 0 else { return nil }
            defer { IOObjectRelease(interface) }
            guard self.number(interface, "bInterfaceNumber")?.uint8Value == number else { continue }

            var descendants: io_iterator_t = 0
            guard IORegistryEntryCreateIterator(interface, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively),
                                                &descendants) == KERN_SUCCESS else { return nil }
            defer { IOObjectRelease(descendants) }
            while true {
                let entry = IOIteratorNext(descendants)
                guard entry != 0 else { return nil }
                defer { IOObjectRelease(entry) }
                if IOObjectConformsTo(entry, "IOMedia") != 0,
                   (IORegistryEntryCreateCFProperty(entry, "Whole" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? Bool) == true,
                   let name = IORegistryEntryCreateCFProperty(entry, "BSD Name" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? String {
                    return name
                }
            }
        }
    }

    @discardableResult
    private func runDiskutil(_ arguments: [String]) -> Bool {
        let tool = Process()
        tool.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        tool.arguments = arguments
        tool.standardOutput = FileHandle.nullDevice
        tool.standardError = FileHandle.nullDevice
        do {
            try tool.run()
            tool.waitUntilExit()
        } catch {
            return false
        }
        logger.info("diskutil \(arguments.joined(separator: " ")): exit \(tool.terminationStatus)")
        return tool.terminationStatus == 0
    }

    /// Close every interface and the device, and wake anything parked.
    ///
    /// Safe to call more than once, and after a partial open: each resource is undone
    /// only if it was taken, which is exactly what the old per-interface close got wrong.
    /// Handles stay allocated until deinit; see there.
    public func close() {
        stateLock.lock()
        guard !isClosed else {
            stateLock.unlock()
            return
        }
        let interfaces = openInterfaces
        let signals = parkingSignals
        releasedOnDeinit.append(contentsOf: openInterfaces.values)
        openInterfaces.removeAll()
        heldInterfaces.removeAll()
        pipes.removeAll()
        parkingSignals.removeAll()
        let handle = deviceInterface
        let wasDeviceOpened = deviceOpened
        let wasCaptured = captured
        // Two endpoints per bridge; cancel each bridge once.
        var seen = Set<ObjectIdentifier>()
        let liveBridges = bridges.values.filter { seen.insert(ObjectIdentifier($0)).inserted }
        let disks = bridgedDisks
        bridges.removeAll()
        bridgedInterfaces.removeAll()
        bridgedDisks.removeAll()
        deviceOpened = false
        captured = false
        isOpen = false
        isClosed = true
        stateLock.unlock()

        for signal in signals.values {
            signal.signal()
        }
        for bridge in liveBridges {
            bridge.cancelPendingReads()
        }

        // USBInterfaceClose aborts whatever is pending on the interface's pipes, so a
        // transfer blocked in IOKit returns rather than holding its endpoint queue.
        for (number, interface) in interfaces {
            let result = interface.vtable.USBInterfaceClose(interface)
            if result != kIOReturnSuccess {
                logger.debug("USBInterfaceClose(\(number)) returned \(result)")
            }
        }

        if let handle = handle, wasDeviceOpened {
            _ = handle.vtable.USBDeviceClose(handle)
        }

        // The raw disks close as the bridges go; hand the volumes back to the Mac.
        for disk in disks {
            runDiskutil(["mountDisk", "/dev/\(disk)"])
        }

        // Give a captured device back: macOS re-enumerates it and its drivers return.
        if wasCaptured {
            let result = Self.runReEnumerateHelper(location: location, capture: false, logger: logger)
            logger.info("Released \(device.busID)-\(device.deviceID) back to macOS: \(String(format: "0x%08x", result))")
        }
    }

    // MARK: - Endpoint lookup

    /// The endpoint's transfer type as the device reports it: 0 control, 1 isochronous,
    /// 2 bulk, 3 interrupt.
    public func transferType(for endpoint: UInt8) -> UInt8? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pipes[endpoint]?.transferType ?? declaredEndpoints[endpoint]?.transferType
    }

    private enum Route {
        case pipe(USBInterfaceHandle, pipeRef: UInt8)
        case bridge(MassStorageBridge)
        case held(interfaceNumber: UInt8)
        case missing
        case closed
    }

    private func route(for endpoint: UInt8) -> Route {
        stateLock.lock()
        defer { stateLock.unlock() }

        if isClosed {
            return .closed
        }
        if let bridge = bridges[endpoint] {
            return .bridge(bridge)
        }
        if let pipe = pipes[endpoint], let interface = openInterfaces[pipe.interfaceNumber] {
            return .pipe(interface, pipeRef: pipe.pipeRef)
        }
        if let owner = declaredEndpoints[endpoint], heldInterfaces[owner.interfaceNumber] != nil {
            return .held(interfaceNumber: owner.interfaceNumber)
        }
        return .missing
    }

    // MARK: - Transfers

    /// Execute a control transfer on the default pipe.
    public func executeControlTransfer(
        setupPacket: Data,
        transferBuffer: Data?,
        timeout: UInt32
    ) async throws -> USBTransferResult {
        guard setupPacket.count == 8 else {
            throw USBRequestError.setupPacketInvalid
        }

        return try await withCheckedThrowingContinuation { continuation in
            endpointQueues.queue(for: 0).async {
                do {
                    let result = try self.performControlTransfer(
                        setupPacket: setupPacket,
                        transferBuffer: transferBuffer,
                        timeout: timeout
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Execute a bulk or interrupt transfer. IOKit drives both through the same pipe
    /// calls; the type only decides how the host schedules them, which IOKit already
    /// knows from the descriptor.
    public func executePipeTransfer(
        endpoint: UInt8,
        data: Data?,
        bufferLength: UInt32,
        timeout: UInt32
    ) async throws -> USBTransferResult {
        return try await withCheckedThrowingContinuation { continuation in
            endpointQueues.queue(for: endpoint).async {
                do {
                    let result = try self.performPipeTransfer(
                        endpoint: endpoint,
                        data: data,
                        bufferLength: bufferLength,
                        timeout: timeout
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Execute an isochronous transfer
    public func executeIsochronousTransfer(
        endpoint: UInt8,
        data: Data?,
        bufferLength: UInt32,
        startFrame: UInt32,
        numberOfPackets: UInt32
    ) async throws -> USBTransferResult {
        return try await withCheckedThrowingContinuation { continuation in
            endpointQueues.queue(for: endpoint).async {
                do {
                    let result = try self.performIsochronousTransfer(
                        endpoint: endpoint,
                        data: data,
                        bufferLength: bufferLength,
                        startFrame: startFrame,
                        numberOfPackets: numberOfPackets
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Transfer cancellation

    /// Abort whatever is outstanding on one endpoint.
    public func cancelTransfers(endpoint: UInt8) {
        switch route(for: endpoint) {
        case let .pipe(interface, pipeRef):
            abortPipe(interface, pipeRef: pipeRef, endpoint: endpoint)
        case let .bridge(bridge):
            bridge.cancelPendingReads()
        case .held:
            stateLock.lock()
            let signal = parkingSignals[endpoint]
            stateLock.unlock()
            signal?.signal()
        case .missing, .closed:
            logger.debug("Nothing to abort on endpoint 0x\(String(endpoint, radix: 16))")
        }
    }

    /// Abort everything outstanding on every endpoint.
    public func cancelAllTransfers() {
        stateLock.lock()
        let endpoints = Array(pipes.keys) + Array(parkingSignals.keys)
        stateLock.unlock()

        for endpoint in endpoints {
            cancelTransfers(endpoint: endpoint)
        }
    }

    private func abortPipe(_ interface: USBInterfaceHandle, pipeRef: UInt8, endpoint: UInt8) {
        let result = interface.vtable.AbortPipe(interface, pipeRef)
        if result != kIOReturnSuccess {
            // Not an error as such: there may simply have been nothing pending.
            logger.warning("AbortPipe failed for endpoint 0x\(String(endpoint, radix: 16)): \(result)")
        } else {
            logger.debug("Successfully aborted transfers on pipe \(pipeRef)")
        }

        // Both ends, not just the host. An abort can land mid-transaction, and
        // ClearPipeStall resets only the host's data toggle: the device keeps its own,
        // the two disagree, and the device's next packet is taken for a retransmission
        // and silently dropped. openocd showed it exactly — every session that exited
        // with reads outstanding made the next session's first CMSIS-DAP reply vanish,
        // "CMD_INFO failed", and the session after that worked again. libusb does the
        // same thing after AbortPipe, for the same reason.
        let clearResult = interface.vtable.ClearPipeStallBothEnds(interface, pipeRef)
        if clearResult != kIOReturnSuccess {
            logger.warning("ClearPipeStallBothEnds failed for endpoint 0x\(String(endpoint, radix: 16)): \(clearResult)")
        }
    }

    // MARK: - Device and interface discovery

    private func findIOKitServiceForDevice() throws -> io_service_t {
        guard let wanted = USBDeviceLocation.locationID(busID: device.busID, deviceID: device.deviceID) else {
            throw IOKitError.serviceNotFound("Cannot derive a location from busid \(device.busID)-\(device.deviceID)")
        }

        guard let matchingDict = ioKit.serviceMatching(kIOUSBDeviceClassName) else {
            logger.error("Failed to create USB device matching dictionary")
            throw IOKitError.serviceNotFound("Failed to create matching dictionary")
        }

        var iterator: io_iterator_t = 0
        let result = ioKit.serviceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator)
        guard result == KERN_SUCCESS else {
            logger.error("Failed to get matching USB services: \(result)")
            throw IOKitError.serviceNotFound("IOServiceGetMatchingServices failed with result: \(result)")
        }
        defer {
            _ = ioKit.objectRelease(iterator)
        }

        // Match on location, then confirm the identity. A device replugged into another
        // port has a new busid and must be bound again; one swapped into this port is a
        // different device, and quietly serving it would be worse than refusing.
        var candidate = ioKit.iteratorNext(iterator)
        while candidate != 0 {
            if number(candidate, "locationID")?.uint32Value == wanted {
                let vendor = number(candidate, kUSBVendorID)
                let product = number(candidate, kUSBProductID)
                if vendor?.uint16Value == device.vendorID && product?.uint16Value == device.productID {
                    logger.debug("Found IOKit service for USB device: \(device.busID)-\(device.deviceID)")
                    return candidate
                }
            }
            _ = ioKit.objectRelease(candidate)
            candidate = ioKit.iteratorNext(iterator)
        }

        logger.error("No USB device at \(device.busID)-\(device.deviceID) matching \(String(format: "%04x:%04x", device.vendorID, device.productID))")
        throw IOKitError.serviceNotFound("No matching USB device found")
    }

    private func hasMassStorageDriver(_ interfaceService: io_service_t) -> Bool {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(interfaceService, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let child = IOIteratorNext(iterator)
            guard child != 0 else { return false }
            defer { IOObjectRelease(child) }
            if let name = IOObjectCopyClass(child)?.takeRetainedValue() as String?, name.contains("MassStorage") {
                return true
            }
        }
    }

    private func number(_ entry: io_registry_entry_t, _ key: String) -> NSNumber? {
        return ioKit.registryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber
    }

    private func createDevicePluginInterface() throws -> USBDeviceHandle? {
        guard service != 0 else {
            throw IOKitError.invalidReference("Invalid device reference")
        }

        var pluginInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0

        let result = IOCreatePlugInInterfaceForService(
            service,
            kIOUSBDeviceUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &pluginInterface,
            &score
        )

        guard result == kIOReturnSuccess, let plugin = pluginInterface else {
            logger.error("Failed to create plugin interface: \(result)")
            throw IOKitError.pluginCreationFailed("IOCreatePlugInInterfaceForService", result)
        }

        defer {
            // Release the plugin interface after we're done with it
            _ = plugin.pointee?.pointee.Release(plugin)
        }

        var deviceInterface: UnsafeMutableRawPointer?
        let queryResult = plugin.pointee?.pointee.QueryInterface(
            plugin,
            CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID300),
            &deviceInterface
        )

        guard queryResult == S_OK, let deviceInterfacePtr = deviceInterface else {
            logger.error("Failed to query device interface: \(String(describing: queryResult))")
            throw IOKitError.interfaceCreationFailed("QueryInterface for device", IOReturn(queryResult ?? -2147483640))
        }

        return deviceInterfacePtr.assumingMemoryBound(
            to: UnsafeMutablePointer<IOUSBDeviceInterface300>?.self)
    }

    /// Every endpoint in the active configuration, from the descriptor IOKit cached at
    /// enumeration. Reading it needs no open.
    private func readDeclaredEndpoints(_ deviceInterface: USBDeviceHandle) -> [UInt8: USBEndpointOwner] {
        var current: UInt8 = 0
        var count: UInt8 = 0
        guard deviceInterface.vtable.GetConfiguration(deviceInterface, &current) == kIOReturnSuccess,
              deviceInterface.vtable.GetNumberOfConfigurations(deviceInterface, &count) == kIOReturnSuccess else {
            logger.warning("Could not read the device's configuration")
            return [:]
        }

        for index in 0..<count {
            var descriptor: IOUSBConfigurationDescriptorPtr?
            guard deviceInterface.vtable.GetConfigurationDescriptorPtr(deviceInterface, index, &descriptor) == kIOReturnSuccess,
                  let config = descriptor,
                  config.pointee.bConfigurationValue == current else {
                continue
            }
            let length = Int(UInt16(littleEndian: config.pointee.wTotalLength))
            let bytes = [UInt8](UnsafeRawBufferPointer(start: UnsafeRawPointer(config), count: length))
            return USBConfigurationLayout.endpoints(in: bytes)
        }
        return [:]
    }

    private func openAllInterfaces(_ deviceInterface: USBDeviceHandle) throws {
        var interfaceRequest = IOUSBFindInterfaceRequest()
        interfaceRequest.bInterfaceClass = UInt16(kIOUSBFindInterfaceDontCare)
        interfaceRequest.bInterfaceSubClass = UInt16(kIOUSBFindInterfaceDontCare)
        interfaceRequest.bInterfaceProtocol = UInt16(kIOUSBFindInterfaceDontCare)
        interfaceRequest.bAlternateSetting = UInt16(kIOUSBFindInterfaceDontCare)

        var interfaceIterator: io_iterator_t = 0
        let iteratorResult = deviceInterface.vtable.CreateInterfaceIterator(deviceInterface, &interfaceRequest, &interfaceIterator)
        guard iteratorResult == kIOReturnSuccess else {
            logger.error("Failed to create interface iterator: \(iteratorResult)")
            throw IOKitError.operationFailed("CreateInterfaceIterator", iteratorResult)
        }
        defer {
            _ = ioKit.objectRelease(interfaceIterator)
        }

        var interfaceService = ioKit.iteratorNext(interfaceIterator)
        while interfaceService != 0 {
            openInterfaceWithDeadline(interfaceService)
            interfaceService = ioKit.iteratorNext(interfaceIterator)
        }
    }

    /// Open one interface, giving up on it if IOKit does not answer.
    ///
    /// Creating an interface's user client can block in the kernel indefinitely — seen on
    /// a card reader, both while its mass-storage driver held it and after capture had
    /// removed that driver, once another open was already stuck there. There is no way
    /// to cancel the call, so it runs on its own thread and is abandoned after a
    /// deadline, and the interface counts as held. Waited on inline it froze this
    /// session and, through the communicator's lock, every other device the daemon was
    /// serving.
    ///
    /// Caller holds `stateLock`; the worker records its result under the same lock only
    /// after this function has stopped waiting for it, and an abandoned worker records
    /// nothing.
    private func openInterfaceWithDeadline(_ interfaceService: io_service_t) {
        let interfaceNumber = number(interfaceService, "bInterfaceNumber")?.uint8Value ?? 0xFF
        let alternate = number(interfaceService, "bAlternateSetting")?.uint8Value ?? 0

        if hasMassStorageDriver(interfaceService) {
            logger.info("Interface \(interfaceNumber) is held by macOS mass storage")
            heldInterfaces[interfaceNumber] = alternate
            massStorageInterfaces.insert(interfaceNumber)
            _ = ioKit.objectRelease(interfaceService)
            return
        }

        final class Outcome: @unchecked Sendable {
            var handle: USBInterfaceHandle?
            var held = false
            var abandoned = false
            let lock = NSLock()
        }
        let outcome = Outcome()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer { _ = ioKit.objectRelease(interfaceService) }
            let (handle, held) = openInterface(interfaceService)
            outcome.lock.lock()
            let abandoned = outcome.abandoned
            if !abandoned {
                outcome.handle = handle
                outcome.held = held
            }
            outcome.lock.unlock()
            if abandoned, let handle = handle {
                // Too late to be used: give it back rather than leave it open.
                _ = handle.vtable.USBInterfaceClose(handle)
                _ = handle.vtable.Release(handle)
            }
            finished.signal()
        }

        if finished.wait(timeout: .now() + .seconds(3)) == .timedOut {
            outcome.lock.lock()
            outcome.abandoned = true
            outcome.lock.unlock()
            logger.warning("Interface \(interfaceNumber) did not open within 3 s; treating it as held")
            heldInterfaces[interfaceNumber] = alternate
            return
        }

        if let handle = outcome.handle {
            openInterfaces[interfaceNumber] = handle
            discoverPipes(on: handle, interfaceNumber: interfaceNumber)
        } else if outcome.held {
            heldInterfaces[interfaceNumber] = alternate
        }
    }

    /// Open one interface, or record that another driver holds it.
    ///
    /// Numbers come from the interface itself. They were counted off the iterator, which
    /// matches bInterfaceNumber only while numbering has no gaps.
    private func openInterface(_ interfaceService: io_service_t) -> (handle: USBInterfaceHandle?, held: Bool) {
        // Not even a user client for an interface a mass-storage driver holds: creating
        // one blocks in the kernel indefinitely on current macOS, and would take this
        // session and its endpoint queues with it.
        if hasMassStorageDriver(interfaceService) {
            logger.info("Interface \(number(interfaceService, "bInterfaceNumber")?.stringValue ?? "?") is held by macOS mass storage")
            return (nil, true)
        }

        var pluginInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0

        let pluginResult = IOCreatePlugInInterfaceForService(
            interfaceService,
            kIOUSBInterfaceUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &pluginInterface,
            &score
        )

        // A mass-storage interface is gated by privacy control (TCC), not by ownership:
        // with the device captured and no driver left on it, the open is still refused
        // with kIOReturnNoResources unless the responsible app has been granted Full
        // Disk Access (or Removable Volumes). Measured with one unprivileged process,
        // same user, same interface, same moment — allowed when launched from a terminal
        // holding the grant, refused when launched over SSH. Root does not help, nor
        // does switching uid; a LaunchDaemon has no grant until someone gives it one.
        if pluginResult == kIOReturnNoResources {
            logger.warning("""
                macOS refused interface \(number(interfaceService, "bInterfaceNumber")?.stringValue ?? "?") \
                (kIOReturnNoResources). For mass storage this means the daemon lacks Full Disk \
                Access: System Settings > Privacy & Security > Full Disk Access, add \
                \(Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? "the usbipd binary")
                """)
        }

        guard pluginResult == kIOReturnSuccess, let plugin = pluginInterface else {
            logger.warning("Failed to create interface plugin: \(pluginResult)")
            return (nil, false)
        }
        defer {
            _ = plugin.pointee?.pointee.Release(plugin)
        }

        var usbInterface: UnsafeMutableRawPointer?
        let queryResult = plugin.pointee?.pointee.QueryInterface(
            plugin,
            CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300),
            &usbInterface
        )
        guard queryResult == S_OK, let interfacePtr = usbInterface else {
            logger.warning("Failed to query interface: \(String(describing: queryResult))")
            return (nil, false)
        }

        let interface = interfacePtr.assumingMemoryBound(
            to: UnsafeMutablePointer<IOUSBInterfaceInterface300>?.self)

        var number: UInt8 = 0
        _ = interface.vtable.GetInterfaceNumber(interface, &number)

        let openResult = interface.vtable.USBInterfaceOpen(interface)
        guard openResult == kIOReturnSuccess else {
            // kIOReturnExclusiveAccess is the normal answer for an interface a macOS
            // driver has claimed. Its endpoints are parked, not failed.
            logger.info("Interface \(number) is held by another driver (\(String(format: "0x%08x", openResult)))")
            _ = interface.vtable.Release(interface)
            return (nil, true)
        }

        return (interface, false)
    }

    /// Ask IOKit what pipes this interface actually has.
    ///
    /// USB/IP does not carry a transfer type on the wire — CMD_SUBMIT has no field for
    /// it — so the server is expected to know each endpoint's type from the device.
    /// Guessing it from the request's interval field misclassified every bulk endpoint
    /// with a non-zero bInterval, which is common: a J-Link reports bInterval 1 on both
    /// of its bulk pipes.
    ///
    /// Caller holds `stateLock`.
    private func discoverPipes(on interface: USBInterfaceHandle, interfaceNumber: UInt8) {
        pipes = pipes.filter { $0.value.interfaceNumber != interfaceNumber }

        var endpointCount: UInt8 = 0
        let countResult = interface.vtable.GetNumEndpoints(interface, &endpointCount)
        guard countResult == kIOReturnSuccess else {
            logger.warning("Could not read endpoint count for interface \(interfaceNumber): \(countResult)")
            return
        }

        // Pipe 0 is the default control pipe and is not reported by GetNumEndpoints.
        guard endpointCount > 0 else { return }

        for pipeRef in 1...endpointCount {
            var direction: UInt8 = 0
            var number: UInt8 = 0
            var transferType: UInt8 = 0
            var maxPacketSize: UInt16 = 0
            var interval: UInt8 = 0

            let result = interface.vtable.GetPipeProperties(
                interface, pipeRef, &direction, &number, &transferType, &maxPacketSize, &interval)
            guard result == kIOReturnSuccess else {
                logger.warning("Could not read properties for pipe \(pipeRef): \(result)")
                continue
            }

            // Direction 1 is IN, which USB encodes as bit 7 of the endpoint address.
            let address = direction == 1 ? (number | 0x80) : number
            pipes[address] = Pipe(interfaceNumber: interfaceNumber, pipeRef: pipeRef, transferType: transferType)

            logger.debug("""
                Interface \(interfaceNumber) pipe \(pipeRef): endpoint 0x\(String(address, radix: 16)), \
                type \(transferType), maxPacket \(maxPacketSize), interval \(interval)
                """)
        }
    }

    // MARK: - Control transfers

    private func performControlTransfer(
        setupPacket: Data,
        transferBuffer: Data?,
        timeout: UInt32
    ) throws -> USBTransferResult {

        // Validate transfer parameters
        guard timeout > 0 && timeout <= 60000 else {
            throw USBRequestError.timeoutInvalid(timeout)
        }

        // Copied, not borrowed. This used to return `bytes.bindMemory(to:)` out of
        // `setupPacket.withUnsafeBytes`, a pointer valid only inside the closure. Debug
        // builds happened to leave the bytes intact; optimised builds did not, and the
        // device received garbage requests and stalled — which shipped in v0.5.0.
        let setupBytes = [UInt8](setupPacket)

        let bmRequestType = setupBytes[0]
        let bRequest = setupBytes[1]
        let wValue = UInt16(setupBytes[2]) | (UInt16(setupBytes[3]) << 8)
        let wIndex = UInt16(setupBytes[4]) | (UInt16(setupBytes[5]) << 8)
        let wLength = UInt16(setupBytes[6]) | (UInt16(setupBytes[7]) << 8)

        // Validate buffer size for OUT transfers (host to device)
        if (bmRequestType & 0x80) == 0 {
            if let transferBuffer = transferBuffer {
                guard transferBuffer.count == Int(wLength) else {
                    throw USBRequestError.bufferSizeMismatch(expected: UInt32(wLength), actual: UInt32(transferBuffer.count))
                }
            } else if wLength > 0 {
                throw USBRequestError.setupPacketInvalid
            }
        }

        logger.debug("Control transfer: bmRequestType=0x\(String(bmRequestType, radix: 16)), bRequest=0x\(String(bRequest, radix: 16)), wValue=0x\(String(wValue, radix: 16)), wIndex=0x\(String(wIndex, radix: 16)), wLength=\(wLength)")

        if let handled = handleBridgedInterfaceRequest(setupBytes) {
            return handled
        }
        if let handled = handleStandardRequest(USBStandardRequest(setupPacket: setupBytes)) {
            return handled
        }

        guard let deviceInterface = currentDeviceInterface() else {
            return result(kIOReturnNoDevice)
        }

        var buffer = [UInt8](repeating: 0, count: Int(wLength))
        if let transferBuffer = transferBuffer, !transferBuffer.isEmpty {
            buffer = [UInt8](transferBuffer)
        }

        var request = IOUSBDevRequestTO()
        request.bmRequestType = bmRequestType
        request.bRequest = bRequest
        request.wValue = wValue
        request.wIndex = wIndex
        request.wLength = wLength
        request.wLenDone = 0
        request.noDataTimeout = timeout
        request.completionTimeout = timeout

        let status: IOReturn = buffer.withUnsafeMutableBytes { bytes in
            request.pData = wLength > 0 ? bytes.baseAddress : nil
            return deviceInterface.vtable.DeviceRequestTO(deviceInterface, &request)
        }

        if status != kIOReturnSuccess {
            logger.warning("Control transfer failed with IOKit result: \(String(format: "0x%08x", status))")
        }

        let actualLength = UInt32(request.wLenDone)
        var receivedData: Data?
        if status == kIOReturnSuccess && actualLength > 0 && (bmRequestType & 0x80) != 0 {
            receivedData = Data(buffer.prefix(Int(actualLength)))
        }
        return result(status, actualLength: actualLength, data: receivedData)
    }

    /// Answer the standard requests that must not be forwarded verbatim, or return nil
    /// to forward the request.
    ///
    /// A client resends SET_CONFIGURATION after every enumeration. Forwarded, it asks
    /// IOKit to rebuild every interface — including the ones macOS's own drivers hold —
    /// which this process cannot do and should not try. SET_INTERFACE and CLEAR_FEATURE
    /// change the host's view of a pipe as well as the device's, so they go through the
    /// calls that update both.
    private func handleStandardRequest(_ request: USBStandardRequest) -> USBTransferResult? {
        switch request {
        case .other:
            return nil

        case let .setConfiguration(value):
            guard let deviceInterface = currentDeviceInterface() else { return result(kIOReturnNoDevice) }
            var current: UInt8 = 0
            _ = deviceInterface.vtable.GetConfiguration(deviceInterface, &current)
            if value == current {
                return result(kIOReturnSuccess)
            }
            logger.warning("Refusing SET_CONFIGURATION \(value): the device is in configuration \(current) and macOS drivers hold it there")
            return result(USBErrorMapping.kIOUSBPipeStalled)

        case let .setInterface(interfaceNumber, alternate):
            stateLock.lock()
            let interface = openInterfaces[interfaceNumber]
            let heldAlternate = heldInterfaces[interfaceNumber]
            stateLock.unlock()

            if let interface = interface {
                let status = interface.vtable.SetAlternateInterface(interface, alternate)
                if status == kIOReturnSuccess {
                    stateLock.lock()
                    discoverPipes(on: interface, interfaceNumber: interfaceNumber)
                    stateLock.unlock()
                }
                return result(status)
            }
            if let heldAlternate = heldAlternate {
                // Already there is true, and harmless. Anything else would change a
                // setting a macOS driver depends on, which this process cannot do.
                if heldAlternate == alternate {
                    return result(kIOReturnSuccess)
                }
                logger.info("Refusing SET_INTERFACE \(interfaceNumber) alt \(alternate): held by macOS at alt \(heldAlternate)")
                return result(USBErrorMapping.kIOUSBPipeStalled)
            }
            return nil

        case let .clearEndpointHalt(endpoint):
            switch route(for: endpoint) {
            case let .pipe(interface, pipeRef):
                return result(interface.vtable.ClearPipeStallBothEnds(interface, pipeRef))
            case .bridge:
                // The bridge never stalls; there is nothing to clear.
                return result(kIOReturnSuccess)
            case .held:
                // The pipe belongs to a macOS driver, which manages its own halts.
                return result(kIOReturnSuccess)
            case .missing:
                return nil
            case .closed:
                return result(kIOReturnNoDevice)
            }
        }
    }

    /// Requests addressed to a bridged mass-storage interface are answered here: the
    /// device's own BOT state belongs to macOS's driver, which is still using it.
    private func handleBridgedInterfaceRequest(_ setup: [UInt8]) -> USBTransferResult? {
        let requestType = setup[0]
        let interfaceNumber = setup[4]
        stateLock.lock()
        let bridge = bridgedInterfaces[interfaceNumber]
        stateLock.unlock()
        guard let bridge = bridge, (requestType & 0x1F) == 0x01 else { return nil }

        switch (requestType & 0x60, setup[1]) {
        case (0x20, 0xFE): // GET MAX LUN: one logical unit
            return result(kIOReturnSuccess, actualLength: 1, data: Data([0]))
        case (0x20, 0xFF): // Bulk-Only Mass Storage Reset
            bridge.reset()
            return result(kIOReturnSuccess)
        case (0x00, 0x0B): // SET_INTERFACE: one alternate setting
            return result(setup[2] == 0 ? kIOReturnSuccess : USBErrorMapping.kIOUSBPipeStalled)
        default:
            return result(USBErrorMapping.kIOUSBPipeStalled)
        }
    }

    private func currentDeviceInterface() -> USBDeviceHandle? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isClosed ? nil : deviceInterface
    }

    private func result(_ status: IOReturn, actualLength: UInt32 = 0, data: Data? = nil) -> USBTransferResult {
        return USBTransferResult(
            status: USBStatus(rawValue: USBErrorMapping.mapIOKitError(status)) ?? .requestFailed,
            actualLength: actualLength,
            data: data,
            completionTime: Date().timeIntervalSince1970
        )
    }

    // MARK: - Bulk and interrupt transfers

    private func performPipeTransfer(
        endpoint: UInt8,
        data: Data?,
        bufferLength: UInt32,
        timeout: UInt32
    ) throws -> USBTransferResult {

        guard timeout > 0 && timeout <= 60000 else {
            throw USBRequestError.timeoutInvalid(timeout)
        }
        guard bufferLength > 0 else {
            throw USBRequestError.invalidParameters
        }

        let isInTransfer = (endpoint & 0x80) != 0

        let interface: USBInterfaceHandle
        let pipeRef: UInt8
        switch route(for: endpoint) {
        case let .pipe(handle, ref):
            interface = handle
            pipeRef = ref
        case let .bridge(bridge):
            if isInTransfer {
                guard let data = bridge.send(maxLength: Int(bufferLength),
                                             deadline: Date().addingTimeInterval(Double(timeout) / 1000)) else {
                    return result(kIOReturnTimeout)
                }
                return result(kIOReturnSuccess, actualLength: UInt32(data.count), data: data)
            }
            let payload = data ?? Data()
            bridge.receive(payload)
            return result(kIOReturnSuccess, actualLength: UInt32(payload.count))
        case let .held(interfaceNumber):
            return parkUntilCancelled(endpoint: endpoint, interfaceNumber: interfaceNumber, timeout: timeout)
        case .missing:
            logger.error("No pipe for endpoint 0x\(String(endpoint, radix: 16))")
            throw USBRequestError.invalidParameters
        case .closed:
            return result(kIOReturnNoDevice)
        }

        logger.debug("Pipe transfer: endpoint=0x\(String(endpoint, radix: 16)), direction=\(isInTransfer ? "IN" : "OUT"), bufferLength=\(bufferLength)")

        var actualLength: UInt32 = 0
        var transferData: Data?
        let status: IOReturn

        if isInTransfer {
            // ReadPipeTO, not ReadPipe: ReadPipe has no timeout and blocks until the
            // device speaks, so a read on a quiet endpoint hung forever.
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(bufferLength))
            defer { buffer.deallocate() }

            // The size argument is in/out: on entry the buffer's capacity, on return the
            // bytes read. Leaving it at 0 told IOKit the buffer held nothing, and every
            // packet overran it — kIOReturnOverrun, EMSGSIZE at the client.
            actualLength = bufferLength
            status = interface.vtable.ReadPipeTO(interface, pipeRef, buffer, &actualLength, timeout, timeout)

            if status == kIOReturnSuccess && actualLength > 0 {
                transferData = Data(bytes: buffer, count: Int(actualLength))
            } else if status != kIOReturnSuccess {
                // IOKit does not reset the primed length when nothing was read. Left
                // as-is, RET_SUBMIT reported a full buffer alongside a failure status and
                // no payload, and a client reading that many bytes desynchronised.
                actualLength = 0
                logger.debug("Pipe IN on 0x\(String(endpoint, radix: 16)) ended with \(String(format: "0x%08x", status))")
            }
        } else {
            guard let data = data else {
                logger.error("No data provided for OUT transfer")
                return result(kIOReturnBadArgument)
            }
            guard data.count <= Int(bufferLength) else {
                throw USBRequestError.bufferSizeMismatch(expected: bufferLength, actual: UInt32(data.count))
            }

            actualLength = UInt32(data.count)
            var bytes = [UInt8](data)
            status = bytes.withUnsafeMutableBytes { buffer in
                interface.vtable.WritePipeTO(interface, pipeRef, buffer.baseAddress, actualLength, timeout, timeout)
            }
            if status != kIOReturnSuccess {
                actualLength = 0
                logger.debug("Pipe OUT on 0x\(String(endpoint, radix: 16)) ended with \(String(format: "0x%08x", status))")
            }
        }

        return result(status, actualLength: actualLength, data: transferData)
    }

    /// Hold a transfer to an endpoint macOS owns until it is cancelled or times out.
    ///
    /// The client enumerated the whole device, so it binds drivers to interfaces this
    /// process could not open — Linux's cdc_acm binds the control interface of every CDC
    /// port and posts a read on its notification endpoint. Failing that read is not
    /// neutral: an error completion is resubmitted immediately, so the client spins, and
    /// some errors make it tear the port down. An endpoint that never has anything to say
    /// is indistinguishable, to the client, from one that is merely quiet, and a quiet
    /// interrupt endpoint is what a CDC notification pipe almost always is. So the
    /// transfer behaves exactly like a read that timed out with no data, which is what it
    /// would have been had the pipe been reachable.
    private func parkUntilCancelled(endpoint: UInt8, interfaceNumber: UInt8, timeout: UInt32) -> USBTransferResult {
        stateLock.lock()
        let signal: DispatchSemaphore
        if let existing = parkingSignals[endpoint] {
            signal = existing
        } else {
            signal = DispatchSemaphore(value: 0)
            parkingSignals[endpoint] = signal
        }
        stateLock.unlock()

        logger.debug("Parking transfer on 0x\(String(endpoint, radix: 16)) (interface \(interfaceNumber) is held by macOS)")

        // A cancel that arrives while nothing is parked banks a signal, which releases
        // the next park early. That early release is a timeout with no data, which a
        // client treats as one more quiet interval — harmless, and simpler than a
        // handshake the serial endpoint queue already makes unnecessary.
        _ = signal.wait(timeout: .now() + .milliseconds(Int(timeout)))
        return result(kIOReturnTimeout)
    }

    // MARK: - Isochronous transfers

    private func performIsochronousTransfer(
        endpoint: UInt8,
        data: Data?,
        bufferLength: UInt32,
        startFrame: UInt32,
        numberOfPackets: UInt32
    ) throws -> USBTransferResult {

        guard numberOfPackets > 0 && numberOfPackets <= 1024 else {
            throw USBRequestError.invalidParameters
        }
        guard bufferLength > 0 else {
            throw USBRequestError.invalidParameters
        }

        let isInTransfer = (endpoint & 0x80) != 0
        guard case let .pipe(interface, pipeRef) = route(for: endpoint) else {
            logger.error("No pipe for endpoint 0x\(String(endpoint, radix: 16))")
            throw USBRequestError.invalidParameters
        }

        logger.debug("Isochronous transfer: endpoint=0x\(String(endpoint, radix: 16)), direction=\(isInTransfer ? "IN" : "OUT"), bufferLength=\(bufferLength), startFrame=\(startFrame), packets=\(numberOfPackets)")

        var actualLength: UInt32 = 0
        var transferData: Data?
        var errorCount: UInt32 = 0
        let status: IOReturn
        var actualStartFrame = UInt64(startFrame)

        // Calculate packet size - distribute buffer evenly across packets
        let packetSize = bufferLength / numberOfPackets
        guard packetSize > 0 else {
            throw USBRequestError.invalidParameters
        }

        // If startFrame is 0, get current frame and schedule for near future
        if actualStartFrame == 0 {
            var currentFrame: UInt64 = 0
            let frameResult = interface.vtable.GetBusFrameNumber(interface, &currentFrame, nil)
            actualStartFrame = frameResult == kIOReturnSuccess ? currentFrame + 10 : 100
        }

        let frameList = UnsafeMutablePointer<IOUSBIsocFrame>.allocate(capacity: Int(numberOfPackets))
        defer { frameList.deallocate() }

        if isInTransfer {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(bufferLength))
            defer { buffer.deallocate() }

            for i in 0..<Int(numberOfPackets) {
                frameList[i].frStatus = kIOReturnInvalid
                frameList[i].frReqCount = UInt16(packetSize)
                frameList[i].frActCount = 0
            }

            status = interface.vtable.ReadIsochPipeAsync(
                interface, pipeRef, buffer, actualStartFrame, numberOfPackets, frameList, nil, nil)

            if status == kIOReturnSuccess {
                for i in 0..<Int(numberOfPackets) {
                    actualLength += UInt32(frameList[i].frActCount)
                    if frameList[i].frStatus != kIOReturnSuccess {
                        errorCount += 1
                    }
                }
                if actualLength > 0 {
                    transferData = Data(bytes: buffer, count: Int(actualLength))
                }
            } else {
                logger.warning("Isochronous IN transfer failed with result: \(status)")
            }
        } else {
            guard let data = data else {
                logger.error("No data provided for isochronous OUT transfer")
                return result(kIOReturnBadArgument)
            }
            guard data.count <= Int(bufferLength) else {
                throw USBRequestError.bufferSizeMismatch(expected: bufferLength, actual: UInt32(data.count))
            }

            var remainingData = data.count
            for i in 0..<Int(numberOfPackets) {
                let currentPacketSize = min(remainingData, Int(packetSize))
                frameList[i].frStatus = kIOReturnInvalid
                frameList[i].frReqCount = UInt16(currentPacketSize)
                frameList[i].frActCount = 0
                remainingData -= currentPacketSize
            }

            actualLength = UInt32(data.count)
            var bytes = [UInt8](data)
            status = bytes.withUnsafeMutableBytes { buffer in
                interface.vtable.WriteIsochPipeAsync(
                    interface, pipeRef, buffer.baseAddress, actualStartFrame, numberOfPackets, frameList, nil, nil)
            }

            if status == kIOReturnSuccess {
                for i in 0..<Int(numberOfPackets) where frameList[i].frStatus != kIOReturnSuccess {
                    errorCount += 1
                }
            } else {
                logger.warning("Isochronous OUT transfer failed with result: \(status)")
            }
        }

        return USBTransferResult(
            status: USBStatus(rawValue: USBErrorMapping.mapIOKitError(status)) ?? .requestFailed,
            actualLength: actualLength,
            errorCount: errorCount,
            data: transferData,
            completionTime: Date().timeIntervalSince1970,
            startFrame: UInt32(actualStartFrame)
        )
    }
}

// MARK: - IOKit Error Handling

/// IOKit-specific errors for USB interface operations
public enum IOKitError: Error {
    case serviceNotFound(String)
    case pluginCreationFailed(String, IOReturn)
    case interfaceCreationFailed(String, IOReturn)
    case operationFailed(String, IOReturn)
    case invalidReference(String)
}

extension IOKitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .serviceNotFound(let device):
            return "IOKit service not found for device: \(device)"
        case .pluginCreationFailed(let operation, let result):
            return "IOKit plugin creation failed for \(operation): \(result)"
        case .interfaceCreationFailed(let interface, let result):
            return "IOKit interface creation failed for \(interface): \(result)"
        case .operationFailed(let operation, let result):
            return "IOKit operation failed: \(operation) (result: \(result))"
        case .invalidReference(let reference):
            return "Invalid IOKit reference: \(reference)"
        }
    }
}
