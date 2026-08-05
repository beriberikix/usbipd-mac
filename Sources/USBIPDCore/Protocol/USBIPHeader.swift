// USBIPHeader.swift
// USB/IP protocol header and core message types

import Foundation
import Common

/// `usbip_header_basic` — the 20-byte header on every SUBMIT/UNLINK message and
/// their replies, i.e. everything exchanged after a device has been imported.
///
///     command(4) seqnum(4) devid(4) direction(4) ep(4)
///
/// Note there is no version field: version negotiation happens once, during the
/// OP_ handshake, which uses `USBIPHeader` instead. Conflating the two framings
/// yields a byte stream no usbip client can parse — see `USBIPProtocol.Command`.
public struct USBIPBasicHeader {
    /// Wire size in bytes. The command-specific block that follows is a further
    /// 28 bytes, so every CMD_/RET_ message has a 48-byte fixed prefix.
    public static let encodedSize = 20

    public let command: USBIPProtocol.BasicCommand
    public let seqnum: UInt32
    public let devid: UInt32
    public let direction: UInt32
    public let ep: UInt32

    public init(
        command: USBIPProtocol.BasicCommand,
        seqnum: UInt32,
        devid: UInt32,
        direction: UInt32,
        ep: UInt32
    ) {
        self.command = command
        self.seqnum = seqnum
        self.devid = devid
        self.direction = direction
        self.ep = ep
    }

    public func encode() -> Data {
        var data = Data(capacity: USBIPBasicHeader.encodedSize)
        data.append(EndiannessConverter.writeUInt32ToData(command.rawValue))
        data.append(EndiannessConverter.writeUInt32ToData(seqnum))
        data.append(EndiannessConverter.writeUInt32ToData(devid))
        data.append(EndiannessConverter.writeUInt32ToData(direction))
        data.append(EndiannessConverter.writeUInt32ToData(ep))
        return data
    }

    public static func decode(from data: Data) throws -> USBIPBasicHeader {
        guard data.count >= encodedSize else {
            throw USBIPProtocolError.invalidDataLength
        }

        let commandValue = try EndiannessConverter.readUInt32FromData(data, at: 0)
        guard let command = USBIPProtocol.BasicCommand(rawValue: commandValue) else {
            throw USBIPProtocolError.unsupportedCommand(UInt16(truncatingIfNeeded: commandValue))
        }

        return USBIPBasicHeader(
            command: command,
            seqnum: try EndiannessConverter.readUInt32FromData(data, at: 4),
            devid: try EndiannessConverter.readUInt32FromData(data, at: 8),
            direction: try EndiannessConverter.readUInt32FromData(data, at: 12),
            ep: try EndiannessConverter.readUInt32FromData(data, at: 16)
        )
    }
}

/// `op_common` — the 8-byte header used only by the OP_ handshake messages
/// (device list and import). Post-import traffic uses `USBIPBasicHeader`.
public struct USBIPHeader: USBIPMessageCodable {
    public let version: UInt16
    public let command: USBIPProtocol.Command
    public let status: UInt32
    
    public init(version: UInt16 = USBIPProtocol.version, command: USBIPProtocol.Command, status: UInt32 = 0) {
        self.version = version
        self.command = command
        self.status = status
    }
    
    public func encode() throws -> Data {
        var data = Data(capacity: 8)
        data.append(EndiannessConverter.writeUInt16ToData(version))
        data.append(EndiannessConverter.writeUInt16ToData(command.rawValue))
        data.append(EndiannessConverter.writeUInt32ToData(status))
        return data
    }
    
    public static func decode(from data: Data) throws -> USBIPHeader {
        guard data.count >= 8 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        let version = try EndiannessConverter.readUInt16FromData(data, at: 0)
        let commandValue = try EndiannessConverter.readUInt16FromData(data, at: 2)
        
        guard let command = USBIPProtocol.Command(rawValue: commandValue) else {
            throw USBIPProtocolError.unsupportedCommand(commandValue)
        }
        
        let status = try EndiannessConverter.readUInt32FromData(data, at: 4)
        
        return USBIPHeader(version: version, command: command, status: status)
    }
}