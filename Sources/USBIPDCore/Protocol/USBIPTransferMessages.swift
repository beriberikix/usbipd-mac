// USBIPTransferMessages.swift  
// USB/IP SUBMIT and UNLINK transfer messages

import Foundation
import Common

/// USB/IP SUBMIT request message (USBIP_CMD_SUBMIT)
public struct USBIPSubmitRequest: USBIPMessageCodable {
    public let header: USBIPHeader
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
    
    public init(
        header: USBIPHeader = USBIPHeader(command: .submitRequest),
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
        self.header = header
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
        var data = try header.encode()
        
        // USB/IP SUBMIT command fields (40 bytes after header)
        data.append(EndiannessConverter.writeUInt32ToData(seqnum))
        data.append(EndiannessConverter.writeUInt32ToData(devid))
        data.append(EndiannessConverter.writeUInt32ToData(direction))
        data.append(EndiannessConverter.writeUInt32ToData(ep))
        data.append(EndiannessConverter.writeUInt32ToData(transferFlags))
        data.append(EndiannessConverter.writeUInt32ToData(transferBufferLength))
        data.append(EndiannessConverter.writeUInt32ToData(startFrame))
        data.append(EndiannessConverter.writeUInt32ToData(numberOfPackets))
        data.append(EndiannessConverter.writeUInt32ToData(interval))
        
        // Setup packet: always 8 bytes, padded with zeros if necessary
        if setup.count >= 8 {
            data.append(setup.prefix(8))
        } else {
            var setupData = setup
            setupData.append(Data(count: 8 - setup.count))
            data.append(setupData)
        }
        
        // Transfer buffer for OUT transfers
        if let transferBuffer = transferBuffer {
            data.append(transferBuffer)
        }
        
        return data
    }
    
    public static func decode(from data: Data) throws -> USBIPSubmitRequest {
        guard data.count >= 48 else { // 8 (header) + 40 (SUBMIT fields)
            throw USBIPProtocolError.invalidDataLength
        }
        
        let header = try USBIPHeader.decode(from: data.subdata(in: 0..<8))
        
        guard header.command == .submitRequest else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Parse SUBMIT fields
        let seqnum = try EndiannessConverter.readUInt32FromData(data, at: 8)
        let devid = try EndiannessConverter.readUInt32FromData(data, at: 12)
        let direction = try EndiannessConverter.readUInt32FromData(data, at: 16)
        let ep = try EndiannessConverter.readUInt32FromData(data, at: 20)
        let transferFlags = try EndiannessConverter.readUInt32FromData(data, at: 24)
        let transferBufferLength = try EndiannessConverter.readUInt32FromData(data, at: 28)
        let startFrame = try EndiannessConverter.readUInt32FromData(data, at: 32)
        let numberOfPackets = try EndiannessConverter.readUInt32FromData(data, at: 36)
        let interval = try EndiannessConverter.readUInt32FromData(data, at: 40)
        
        // Setup packet: 8 bytes
        let setup = data.subdata(in: 44..<52)
        
        // Transfer buffer for OUT transfers
        var transferBuffer: Data?
        if data.count > 48 && transferBufferLength > 0 {
            let remainingData = data.subdata(in: 48..<data.count)
            transferBuffer = remainingData.prefix(Int(transferBufferLength))
        }
        
        return USBIPSubmitRequest(
            header: header,
            seqnum: seqnum,
            devid: devid,
            direction: direction,
            ep: ep,
            transferFlags: transferFlags,
            transferBufferLength: transferBufferLength,
            startFrame: startFrame,
            numberOfPackets: numberOfPackets,
            interval: interval,
            setup: setup,
            transferBuffer: transferBuffer
        )
    }
}

/// USB/IP SUBMIT response message (USBIP_RET_SUBMIT)
public struct USBIPSubmitResponse: USBIPMessageCodable {
    public let header: USBIPHeader
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
    
    public init(
        header: USBIPHeader = USBIPHeader(command: .submitReply),
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
        self.header = header
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
        var data = try header.encode()
        
        // USB/IP SUBMIT reply fields (40 bytes after header)
        data.append(EndiannessConverter.writeUInt32ToData(seqnum))
        data.append(EndiannessConverter.writeUInt32ToData(devid))
        data.append(EndiannessConverter.writeUInt32ToData(direction))
        data.append(EndiannessConverter.writeUInt32ToData(ep))
        data.append(EndiannessConverter.writeInt32ToData(status))
        data.append(EndiannessConverter.writeUInt32ToData(actualLength))
        data.append(EndiannessConverter.writeUInt32ToData(startFrame))
        data.append(EndiannessConverter.writeUInt32ToData(numberOfPackets))
        data.append(EndiannessConverter.writeUInt32ToData(errorCount))
        
        // Reserved: 8 bytes to align with setup packet space from request
        data.append(Data(count: 8))
        
        // Transfer buffer for IN transfers
        if let transferBuffer = transferBuffer {
            data.append(transferBuffer)
        }
        
        return data
    }
    
    public static func decode(from data: Data) throws -> USBIPSubmitResponse {
        guard data.count >= 48 else { // 8 (header) + 40 (SUBMIT reply fields)
            throw USBIPProtocolError.invalidDataLength
        }
        
        let header = try USBIPHeader.decode(from: data.subdata(in: 0..<8))
        
        guard header.command == .submitReply else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Parse SUBMIT reply fields
        let seqnum = try EndiannessConverter.readUInt32FromData(data, at: 8)
        let devid = try EndiannessConverter.readUInt32FromData(data, at: 12)
        let direction = try EndiannessConverter.readUInt32FromData(data, at: 16)
        let ep = try EndiannessConverter.readUInt32FromData(data, at: 20)
        let status = try EndiannessConverter.readInt32FromData(data, at: 24)
        let actualLength = try EndiannessConverter.readUInt32FromData(data, at: 28)
        let startFrame = try EndiannessConverter.readUInt32FromData(data, at: 32)
        let numberOfPackets = try EndiannessConverter.readUInt32FromData(data, at: 36)
        let errorCount = try EndiannessConverter.readUInt32FromData(data, at: 40)
        
        // Skip 8 bytes reserved space (44-52)
        
        // Transfer buffer for IN transfers
        var transferBuffer: Data?
        if data.count > 48 && actualLength > 0 {
            let remainingData = data.subdata(in: 48..<data.count)
            transferBuffer = remainingData.prefix(Int(actualLength))
        }
        
        return USBIPSubmitResponse(
            header: header,
            seqnum: seqnum,
            devid: devid,
            direction: direction,
            ep: ep,
            status: status,
            actualLength: actualLength,
            startFrame: startFrame,
            numberOfPackets: numberOfPackets,
            errorCount: errorCount,
            transferBuffer: transferBuffer
        )
    }
}

/// USB/IP UNLINK request message (USBIP_CMD_UNLINK)
public struct USBIPUnlinkRequest: USBIPMessageCodable {
    public let header: USBIPHeader
    public let seqnum: UInt32              // New sequence number for this unlink request
    public let unlinkSeqnum: UInt32        // Sequence number of the request to unlink
    public let devid: UInt32               // Device ID
    public let direction: UInt32           // Transfer direction
    public let ep: UInt32                  // Endpoint address
    
    public init(
        header: USBIPHeader = USBIPHeader(command: .unlinkRequest),
        seqnum: UInt32,
        unlinkSeqnum: UInt32,
        devid: UInt32,
        direction: UInt32,
        ep: UInt32
    ) {
        self.header = header
        self.seqnum = seqnum
        self.unlinkSeqnum = unlinkSeqnum
        self.devid = devid
        self.direction = direction
        self.ep = ep
    }
    
    public func encode() throws -> Data {
        var data = try header.encode()
        
        // USB/IP UNLINK command fields (24 bytes after header)
        data.append(EndiannessConverter.writeUInt32ToData(seqnum))
        data.append(EndiannessConverter.writeUInt32ToData(unlinkSeqnum))
        data.append(EndiannessConverter.writeUInt32ToData(devid))
        data.append(EndiannessConverter.writeUInt32ToData(direction))
        data.append(EndiannessConverter.writeUInt32ToData(ep))
        
        // Reserved: 4 bytes to align structure
        data.append(Data(count: 4))
        
        return data
    }
    
    public static func decode(from data: Data) throws -> USBIPUnlinkRequest {
        guard data.count >= 32 else { // 8 (header) + 24 (UNLINK fields)
            throw USBIPProtocolError.invalidDataLength
        }
        
        let header = try USBIPHeader.decode(from: data.subdata(in: 0..<8))
        
        guard header.command == .unlinkRequest else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Parse UNLINK fields
        let seqnum = try EndiannessConverter.readUInt32FromData(data, at: 8)
        let unlinkSeqnum = try EndiannessConverter.readUInt32FromData(data, at: 12)
        let devid = try EndiannessConverter.readUInt32FromData(data, at: 16)
        let direction = try EndiannessConverter.readUInt32FromData(data, at: 20)
        let ep = try EndiannessConverter.readUInt32FromData(data, at: 24)
        
        return USBIPUnlinkRequest(
            header: header,
            seqnum: seqnum,
            unlinkSeqnum: unlinkSeqnum,
            devid: devid,
            direction: direction,
            ep: ep
        )
    }
}

/// USB/IP UNLINK response message (USBIP_RET_UNLINK)
public struct USBIPUnlinkResponse: USBIPMessageCodable {
    public let header: USBIPHeader
    public let seqnum: UInt32              // Sequence number from unlink request
    public let unlinkSeqnum: UInt32        // Sequence number of the unlinked request
    public let devid: UInt32               // Device ID
    public let direction: UInt32           // Transfer direction
    public let ep: UInt32                  // Endpoint address
    public let status: Int32               // Unlink status
    
    public init(
        header: USBIPHeader = USBIPHeader(command: .unlinkReply),
        seqnum: UInt32,
        unlinkSeqnum: UInt32,
        devid: UInt32,
        direction: UInt32,
        ep: UInt32,
        status: Int32
    ) {
        self.header = header
        self.seqnum = seqnum
        self.unlinkSeqnum = unlinkSeqnum
        self.devid = devid
        self.direction = direction
        self.ep = ep
        self.status = status
    }
    
    public func encode() throws -> Data {
        var data = try header.encode()
        
        // USB/IP UNLINK reply fields (28 bytes after header)
        data.append(EndiannessConverter.writeUInt32ToData(seqnum))
        data.append(EndiannessConverter.writeUInt32ToData(unlinkSeqnum))
        data.append(EndiannessConverter.writeUInt32ToData(devid))
        data.append(EndiannessConverter.writeUInt32ToData(direction))
        data.append(EndiannessConverter.writeUInt32ToData(ep))
        data.append(EndiannessConverter.writeInt32ToData(status))
        
        return data
    }
    
    public static func decode(from data: Data) throws -> USBIPUnlinkResponse {
        guard data.count >= 32 else { // 8 (header) + 24 (UNLINK reply fields)
            throw USBIPProtocolError.invalidDataLength
        }
        
        let header = try USBIPHeader.decode(from: data.subdata(in: 0..<8))
        
        guard header.command == .unlinkReply else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Parse UNLINK reply fields
        let seqnum = try EndiannessConverter.readUInt32FromData(data, at: 8)
        let unlinkSeqnum = try EndiannessConverter.readUInt32FromData(data, at: 12)
        let devid = try EndiannessConverter.readUInt32FromData(data, at: 16)
        let direction = try EndiannessConverter.readUInt32FromData(data, at: 20)
        let ep = try EndiannessConverter.readUInt32FromData(data, at: 24)
        let status = try EndiannessConverter.readInt32FromData(data, at: 28)
        
        return USBIPUnlinkResponse(
            header: header,
            seqnum: seqnum,
            unlinkSeqnum: unlinkSeqnum,
            devid: devid,
            direction: direction,
            ep: ep,
            status: status
        )
    }
}