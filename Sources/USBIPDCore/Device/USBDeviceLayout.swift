// USBDeviceLayout.swift
// What a device looks like from the descriptors alone: where it is, which interface owns
// each endpoint, and which standard requests the server must answer itself.
//
// Kept apart from IOKitUSBDevice because none of it needs hardware, and every piece of
// it has been wrong before in a way only a real device exposed.

import Foundation

/// Maps a busid back to the IOKit locationID it was derived from.
enum USBDeviceLocation {

    /// The inverse of the busid derivation in IOKitDeviceDiscoveryImplementation:
    /// locationID is 0xBBPPPPPP, the top byte the controller and each following nibble
    /// the port at successive hub tiers. Bus "2", device "1.1" is 0x02110000.
    ///
    /// Devices used to be found by vendor and product ID, taking the first match. Two
    /// identical boards on one Mac are the ordinary case for anyone doing hardware work,
    /// and a FreeWili carries an FT232H, the same chip as half the FPGA cables on the
    /// bench, so whichever IOKit listed first received the other device's traffic.
    static func locationID(busID: String, deviceID: String) -> UInt32? {
        guard let bus = UInt32(busID), bus <= 0xFF else { return nil }

        var location = bus << 24
        if deviceID == "0" {
            return location
        }

        let ports = deviceID.split(separator: ".")
        guard !ports.isEmpty, ports.count <= 6 else { return nil }
        for (tier, text) in ports.enumerated() {
            guard let port = UInt32(text), port >= 1, port <= 0xF else { return nil }
            location |= port << UInt32(20 - 4 * tier)
        }
        return location
    }
}

/// The interface an endpoint belongs to, as the configuration descriptor declares it.
struct USBEndpointOwner: Equatable {
    let interfaceNumber: UInt8
    /// bmAttributes & 3: 0 control, 1 isochronous, 2 bulk, 3 interrupt.
    let transferType: UInt8
}

enum USBConfigurationLayout {

    /// Every endpoint in a configuration descriptor, keyed by address, with the
    /// interface that owns it.
    ///
    /// IOKit only describes the pipes of an interface this process has opened. An
    /// interface macOS keeps — a CDC-ACM control interface, held by AppleUSBACMControl —
    /// cannot be opened, so its endpoints are invisible to IOKit, and the only record of
    /// them is the descriptor the client was sent at enumeration. Without it the server
    /// cannot tell a transfer to an endpoint it may not touch from one to an endpoint that
    /// does not exist.
    ///
    /// Alternate settings may reuse an address; the first declaration wins, which is the
    /// interface that owns it whichever setting is selected.
    static func endpoints(in descriptor: [UInt8]) -> [UInt8: USBEndpointOwner] {
        var owners: [UInt8: USBEndpointOwner] = [:]
        var currentInterface: UInt8?
        var offset = 0

        while offset + 2 <= descriptor.count {
            let length = Int(descriptor[offset])
            let type = descriptor[offset + 1]
            // A zero length would never advance; a length past the end is truncation.
            guard length >= 2, offset + length <= descriptor.count else { break }

            switch type {
            case 0x04 where length >= 3:
                currentInterface = descriptor[offset + 2]
            case 0x05 where length >= 4:
                if let interface = currentInterface {
                    let address = descriptor[offset + 2]
                    if owners[address] == nil {
                        owners[address] = USBEndpointOwner(
                            interfaceNumber: interface,
                            transferType: descriptor[offset + 3] & 0x03)
                    }
                }
            default:
                break
            }
            offset += length
        }
        return owners
    }
}

/// The standard requests the server must handle itself rather than forward.
///
/// Linux's own server (stub_rx.c) intercepts the same three. Each changes host-side
/// state as well as the device's, and IOKit will not let one process change it behind
/// the backs of the drivers that hold the device's other interfaces.
enum USBStandardRequest: Equatable {
    case setConfiguration(UInt8)
    case setInterface(interface: UInt8, alternate: UInt8)
    case clearEndpointHalt(endpoint: UInt8)
    case other

    init(setupPacket: [UInt8]) {
        guard setupPacket.count == 8 else {
            self = .other
            return
        }
        let requestType = setupPacket[0]
        let request = setupPacket[1]
        let value = UInt16(setupPacket[2]) | UInt16(setupPacket[3]) << 8
        let index = UInt16(setupPacket[4]) | UInt16(setupPacket[5]) << 8

        switch (requestType, request) {
        case (0x00, 0x09):
            self = .setConfiguration(UInt8(truncatingIfNeeded: value))
        case (0x01, 0x0B):
            self = .setInterface(
                interface: UInt8(truncatingIfNeeded: index),
                alternate: UInt8(truncatingIfNeeded: value))
        case (0x02, 0x01) where value == 0:
            self = .clearEndpointHalt(endpoint: UInt8(truncatingIfNeeded: index))
        default:
            self = .other
        }
    }
}
