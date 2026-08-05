// USBIPTransferMessages.swift
// USB/IP SUBMIT and UNLINK transfer messages
//
// Wire layouts follow linux/drivers/usb/usbip/usbip_common.h. Every message here
// is framed with `usbip_header_basic` (20 bytes) followed by a command-specific
// block of exactly 28 bytes, giving a 48-byte fixed prefix, optionally followed by
// a transfer buffer.
//
// These messages do NOT carry the 8-byte op_common header used by the device-list
// and import handshake. See USBIPProtocol.Command for why that distinction matters.

import Foundation
import Common

/// Size of the fixed prefix on every CMD_/RET_ message: 20-byte basic header plus
/// a 28-byte command block.
private let usbipCommandPrefixSize = 48

/// Offset at which the command-specific block begins.
private let usbipCommandBlockOffset = USBIPBasicHeader.encodedSize

/// USB/IP SUBMIT request message (USBIP_CMD_SUBMIT)
public struct USBIPSubmitRequest: USBIPMessageCodable {
    public let seqnum: UInt32              // Unique request sequence number
    public let devid: UInt32               // Device ID
    public let direction: UInt32           // Transfer direction (0=OUT, 1=IN)
    public let ep: UInt32                  // Endpoint address
    public let transferFlags: UInt32       // USB transfer flags
    public let transferBufferLength: UInt32 // Length of transfer buffer
    public let startFrame: UInt32          // Start frame for isochronous transfers
    public let numberOfPackets: UInt32     // Number of packets for isochronous transfers
    public let interval: UInt32            // Polling interval for interrupt transfers
    public let setup: Data                 // 8 bytes setup packet for control transfers
    public let transferBuffer: Data?       // Variable length data for OUT transfers

    public var command: USBIPProtocol.Command { return .submitRequest }

    public var basicHeader: USBIPBasicHeader {
        return USBIPBasicHeader(command: .submit, seqnum: seqnum, devid: devid,
                                direction: direction, ep: ep)
    }

    public init(
        seqnum: UInt32,
        devid: UInt32,
        direction: UInt32,
        ep: UInt32,
        transferFlags: UInt32,
        transferBufferLength: UInt32,
        startFrame: UInt32 = 0,
        numberOfPackets: UInt32 = 0,
        interval: UInt32 = 0,
        setup: Data = Data(count: 8),
        transferBuffer: Data? = nil
    ) {
        self.seqnum = seqnum
        self.devid = devid
        self.direction = direction
        self.ep = ep
        self.transferFlags = transferFlags
        self.transferBufferLength = transferBufferLength
        self.startFrame = startFrame
        self.numberOfPackets = numberOfPackets
        self.interval = interval
        self.setup = setup
        self.transferBuffer = transferBuffer
    }

    public func encode() throws -> Data {
        var data = basicHeader.encode()

        // usbip_header_cmd_submit — 28 bytes
        data.append(EndiannessConverter.writeUInt32ToData(transferFlags))
        data.append(EndiannessConverter.writeUInt32ToData(transferBufferLength))
        data.append(EndiannessConverter.writeUInt32ToData(startFrame))
        data.append(EndiannessConverter.writeUInt32ToData(numberOfPackets))
        data.append(EndiannessConverter.writeUInt32ToData(interval))

        // setup: always exactly 8 bytes, zero-padded or truncated
        if setup.count >= 8 {
            data.append(setup.prefix(8))
        } else {
            var setupData = setup
            setupData.append(Data(count: 8 - setup.count))
            data.append(setupData)
        }

        // Transfer buffer, present only on OUT transfers
        if let transferBuffer = transferBuffer {
            data.append(transferBuffer)
        }

        return data
    }

    public static func decode(from data: Data) throws -> USBIPSubmitRequest {
        guard data.count >= usbipCommandPrefixSize else {
            throw USBIPProtocolError.invalidDataLength
        }

        let header = try USBIPBasicHeader.decode(from: data)
        guard header.command == .submit else {
            throw USBIPProtocolError.invalidMessageFormat
        }

        let base = usbipCommandBlockOffset
        let transferBufferLength = try EndiannessConverter.readUInt32FromData(data, at: base + 4)

        // setup occupies the last 8 bytes of the command block
        let setup = data.subdata(in: (base + 20)..<usbipCommandPrefixSize)

        var transferBuffer: Data?
        if data.count > usbipCommandPrefixSize && transferBufferLength > 0 {
            let remaining = data.subdata(in: usbipCommandPrefixSize..<data.count)
            transferBuffer = remaining.prefix(Int(transferBufferLength))
        }

        return USBIPSubmitRequest(
            seqnum: header.seqnum,
            devid: header.devid,
            direction: header.direction,
            ep: header.ep,
            transferFlags: try EndiannessConverter.readUInt32FromData(data, at: base),
            transferBufferLength: transferBufferLength,
            startFrame: try EndiannessConverter.readUInt32FromData(data, at: base + 8),
            numberOfPackets: try EndiannessConverter.readUInt32FromData(data, at: base + 12),
            interval: try EndiannessConverter.readUInt32FromData(data, at: base + 16),
            setup: setup,
            transferBuffer: transferBuffer
        )
    }
}

/// USB/IP SUBMIT response message (USBIP_RET_SUBMIT)
public struct USBIPSubmitResponse: USBIPMessageCodable {
    public let seqnum: UInt32              // Sequence number from request
    public let devid: UInt32               // Device ID
    public let direction: UInt32           // Transfer direction
    public let ep: UInt32                  // Endpoint address
    public let status: Int32               // Transfer status (USB status codes)
    public let actualLength: UInt32        // Actual length of transferred data
    public let startFrame: UInt32          // Start frame for isochronous transfers
    public let numberOfPackets: UInt32     // Number of packets for isochronous transfers
    public let errorCount: UInt32          // Error count for isochronous transfers
    public let transferBuffer: Data?       // Variable length data for IN transfers

    public var command: USBIPProtocol.Command { return .submitReply }

    public var basicHeader: USBIPBasicHeader {
        return USBIPBasicHeader(command: .retSubmit, seqnum: seqnum, devid: devid,
                                direction: direction, ep: ep)
    }

    public init(
        seqnum: UInt32,
        devid: UInt32,
        direction: UInt32,
        ep: UInt32,
        status: Int32,
        actualLength: UInt32,
        startFrame: UInt32 = 0,
        numberOfPackets: UInt32 = 0,
        errorCount: UInt32 = 0,
        transferBuffer: Data? = nil
    ) {
        self.seqnum = seqnum
        self.devid = devid
        self.direction = direction
        self.ep = ep
        self.status = status
        self.actualLength = actualLength
        self.startFrame = startFrame
        self.numberOfPackets = numberOfPackets
        self.errorCount = errorCount
        self.transferBuffer = transferBuffer
    }

    public func encode() throws -> Data {
        var data = basicHeader.encode()

        // usbip_header_ret_submit — 28 bytes
        data.append(EndiannessConverter.writeInt32ToData(status))
        data.append(EndiannessConverter.writeUInt32ToData(actualLength))
        data.append(EndiannessConverter.writeUInt32ToData(startFrame))
        data.append(EndiannessConverter.writeUInt32ToData(numberOfPackets))
        data.append(EndiannessConverter.writeUInt32ToData(errorCount))
        data.append(Data(count: 8)) // padding, where the request carries setup

        // Transfer buffer, present only on IN transfers
        if let transferBuffer = transferBuffer {
            data.append(transferBuffer)
        }

        return data
    }

    public static func decode(from data: Data) throws -> USBIPSubmitResponse {
        guard data.count >= usbipCommandPrefixSize else {
            throw USBIPProtocolError.invalidDataLength
        }

        let header = try USBIPBasicHeader.decode(from: data)
        guard header.command == .retSubmit else {
            throw USBIPProtocolError.invalidMessageFormat
        }

        let base = usbipCommandBlockOffset
        let actualLength = try EndiannessConverter.readUInt32FromData(data, at: base + 4)

        var transferBuffer: Data?
        if data.count > usbipCommandPrefixSize && actualLength > 0 {
            let remaining = data.subdata(in: usbipCommandPrefixSize..<data.count)
            transferBuffer = remaining.prefix(Int(actualLength))
        }

        return USBIPSubmitResponse(
            seqnum: header.seqnum,
            devid: header.devid,
            direction: header.direction,
            ep: header.ep,
            status: try EndiannessConverter.readInt32FromData(data, at: base),
            actualLength: actualLength,
            startFrame: try EndiannessConverter.readUInt32FromData(data, at: base + 8),
            numberOfPackets: try EndiannessConverter.readUInt32FromData(data, at: base + 12),
            errorCount: try EndiannessConverter.readUInt32FromData(data, at: base + 16),
            transferBuffer: transferBuffer
        )
    }
}

/// USB/IP UNLINK request message (USBIP_CMD_UNLINK)
public struct USBIPUnlinkRequest: USBIPMessageCodable {
    public let seqnum: UInt32              // Sequence number of this unlink request
    public let unlinkSeqnum: UInt32        // Sequence number of the request being unlinked
    public let devid: UInt32               // Device ID
    public let direction: UInt32           // Transfer direction
    public let ep: UInt32                  // Endpoint address

    public var command: USBIPProtocol.Command { return .unlinkRequest }

    public var basicHeader: USBIPBasicHeader {
        return USBIPBasicHeader(command: .unlink, seqnum: seqnum, devid: devid,
                                direction: direction, ep: ep)
    }

    public init(
        seqnum: UInt32,
        unlinkSeqnum: UInt32,
        devid: UInt32,
        direction: UInt32,
        ep: UInt32
    ) {
        self.seqnum = seqnum
        self.unlinkSeqnum = unlinkSeqnum
        self.devid = devid
        self.direction = direction
        self.ep = ep
    }

    public func encode() throws -> Data {
        var data = basicHeader.encode()

        // usbip_header_cmd_unlink — 28 bytes: the target seqnum then 24 bytes padding
        data.append(EndiannessConverter.writeUInt32ToData(unlinkSeqnum))
        data.append(Data(count: 24))

        return data
    }

    public static func decode(from data: Data) throws -> USBIPUnlinkRequest {
        guard data.count >= usbipCommandPrefixSize else {
            throw USBIPProtocolError.invalidDataLength
        }

        let header = try USBIPBasicHeader.decode(from: data)
        guard header.command == .unlink else {
            throw USBIPProtocolError.invalidMessageFormat
        }

        return USBIPUnlinkRequest(
            seqnum: header.seqnum,
            unlinkSeqnum: try EndiannessConverter.readUInt32FromData(data, at: usbipCommandBlockOffset),
            devid: header.devid,
            direction: header.direction,
            ep: header.ep
        )
    }
}

/// USB/IP UNLINK response message (USBIP_RET_UNLINK)
///
/// The reply carries only a status. The sequence number of the unlinked request is
/// not retransmitted — it is correlated via the basic header's seqnum, which echoes
/// the seqnum of the CMD_UNLINK that prompted this reply.
public struct USBIPUnlinkResponse: USBIPMessageCodable {
    public let seqnum: UInt32              // Sequence number from the unlink request
    public let devid: UInt32               // Device ID
    public let direction: UInt32           // Transfer direction
    public let ep: UInt32                  // Endpoint address
    public let status: Int32               // Unlink status

    public var command: USBIPProtocol.Command { return .unlinkReply }

    public var basicHeader: USBIPBasicHeader {
        return USBIPBasicHeader(command: .retUnlink, seqnum: seqnum, devid: devid,
                                direction: direction, ep: ep)
    }

    public init(
        seqnum: UInt32,
        devid: UInt32,
        direction: UInt32,
        ep: UInt32,
        status: Int32
    ) {
        self.seqnum = seqnum
        self.devid = devid
        self.direction = direction
        self.ep = ep
        self.status = status
    }

    public func encode() throws -> Data {
        var data = basicHeader.encode()

        // usbip_header_ret_unlink — 28 bytes: status then 24 bytes padding
        data.append(EndiannessConverter.writeInt32ToData(status))
        data.append(Data(count: 24))

        return data
    }

    public static func decode(from data: Data) throws -> USBIPUnlinkResponse {
        guard data.count >= usbipCommandPrefixSize else {
            throw USBIPProtocolError.invalidDataLength
        }

        let header = try USBIPBasicHeader.decode(from: data)
        guard header.command == .retUnlink else {
            throw USBIPProtocolError.invalidMessageFormat
        }

        return USBIPUnlinkResponse(
            seqnum: header.seqnum,
            devid: header.devid,
            direction: header.direction,
            ep: header.ep,
            status: try EndiannessConverter.readInt32FromData(data, at: usbipCommandBlockOffset)
        )
    }
}
