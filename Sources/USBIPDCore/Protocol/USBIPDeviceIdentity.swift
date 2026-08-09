// USBIPDeviceIdentity.swift
// Maps between a macOS device and the integer identity USB/IP puts on the wire.

import Foundation
import Common

/// USB/IP identifies a device on the wire by `devid`, a 32-bit value conventionally
/// built as `(busnum << 16) | devnum`. macOS has no devnum: a device is located by its
/// bus and the chain of hub ports leading to it, which this project renders as a busid
/// like `32-2.1.3`.
///
/// Squeezing that path into an integer used to keep only the final port —
/// `deviceID.split(separator: ".").last` — so `2.1.3` and `3` both became 3, and so did
/// the hub sitting at port 3. A client that imported a device behind a hub was handed a
/// devid that pointed at the hub, and every transfer went to the wrong device. In
/// practice it failed at the first step, because macOS owns hubs and `USBDeviceOpen`
/// returned `kIOReturnExclusiveAccess`. On a docked machine that is most devices.
///
/// The path is packed one nibble per tier instead, which mirrors how macOS builds
/// `locationID` in the first place, so `2.1.3` becomes 0x213.
enum USBIPDeviceIdentity {

    /// Pack a dotted hub port path into the low 16 bits of a devid.
    ///
    /// Returns nil when the path cannot be represented: more than four tiers, or a port
    /// above 15. Both are beyond what a nibble-per-tier encoding can hold, and inventing
    /// a lossy answer is what caused the bug this replaces.
    static func devnum(forPortPath portPath: String) -> UInt32? {
        let components = portPath.split(separator: ".")
        guard !components.isEmpty, components.count <= 4 else { return nil }

        var packed: UInt32 = 0
        for component in components {
            guard let port = UInt32(component), port <= 0xF else { return nil }
            packed = (packed << 4) | port
        }
        return packed
    }

    /// The devid a client should be given for this device, or nil if it cannot be
    /// represented — see `devnum(forPortPath:)`.
    static func devid(for device: USBDevice) -> UInt32? {
        guard let busnum = UInt32(device.busID),
              let devnum = devnum(forPortPath: device.deviceID) else {
            return nil
        }
        return (busnum << 16) | devnum
    }

    /// The dotted port path packed into a devnum — the exact inverse of
    /// `devnum(forPortPath:)`.
    ///
    /// Leading zero nibbles are dropped rather than emitted as ports. Hub ports are
    /// numbered from one, so a real path never begins with zero and nothing is lost.
    static func portPath(forDevnum devnum: UInt32) -> String {
        var nibbles: [String] = []
        for shift in stride(from: 12, through: 0, by: -4) {
            let port = (devnum >> UInt32(shift)) & 0xF
            // Skip only the leading run; a zero after a real port would be part of the
            // path, though the encoding cannot produce one.
            if nibbles.isEmpty && port == 0 { continue }
            nibbles.append(String(port))
        }
        return nibbles.isEmpty ? "0" : nibbles.joined(separator: ".")
    }

    /// Find the attached device a devid refers to.
    ///
    /// Resolution is by search rather than by arithmetic. Unpacking the nibbles would
    /// reproduce the port path, but only for devices the encoding can represent, and it
    /// would happily name a device that is no longer attached. Comparing against the
    /// devices actually present means an unrepresentable or stale devid resolves to
    /// nothing, which the caller reports as "no such device" — the truthful answer, and
    /// far better than opening whichever device the arithmetic happened to land on.
    static func device(forDevid devid: UInt32, among devices: [USBDevice]) -> USBDevice? {
        return devices.first { self.devid(for: $0) == devid }
    }
}
