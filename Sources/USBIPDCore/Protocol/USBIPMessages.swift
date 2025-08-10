// USBIPMessages.swift
// USB/IP protocol message structures

import Foundation
import Common

/// Common header for all USB/IP messages
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

/// Device list request message
public struct DeviceListRequest: USBIPMessageCodable {
    public let header: USBIPHeader
    
    public init(header: USBIPHeader = USBIPHeader(command: .requestDeviceList)) {
        self.header = header
    }
    
    public func encode() throws -> Data {
        return try header.encode()
    }
    
    public static func decode(from data: Data) throws -> DeviceListRequest {
        let header = try USBIPHeader.decode(from: data)
        
        guard header.command == .requestDeviceList else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        return DeviceListRequest(header: header)
    }
}

/// Exported device information for device list response
public struct USBIPExportedDevice: USBIPMessageCodable {
    public let path: String
    public let busID: String
    public let busnum: UInt32
    public let devnum: UInt32
    public let speed: UInt32
    public let vendorID: UInt16
    public let productID: UInt16
    public let deviceClass: UInt8
    public let deviceSubClass: UInt8
    public let deviceProtocol: UInt8
    public let configurationCount: UInt8
    public let configurationValue: UInt8
    public let interfaceCount: UInt8
    
    public init(
        path: String,
        busID: String,
        busnum: UInt32,
        devnum: UInt32,
        speed: UInt32,
        vendorID: UInt16,
        productID: UInt16,
        deviceClass: UInt8,
        deviceSubClass: UInt8,
        deviceProtocol: UInt8,
        configurationCount: UInt8,
        configurationValue: UInt8,
        interfaceCount: UInt8
    ) {
        self.path = path
        self.busID = busID
        self.busnum = busnum
        self.devnum = devnum
        self.speed = speed
        self.vendorID = vendorID
        self.productID = productID
        self.deviceClass = deviceClass
        self.deviceSubClass = deviceSubClass
        self.deviceProtocol = deviceProtocol
        self.configurationCount = configurationCount
        self.configurationValue = configurationValue
        self.interfaceCount = interfaceCount
    }
    
    public func encode() throws -> Data {
        var data = Data()
        
        // Path: 256 bytes, null-terminated, padded with zeros
        data.append(try StringEncodingUtilities.encodeFixedLengthString(path, length: 256))
        
        // BusID: 32 bytes, null-terminated, padded with zeros
        data.append(try StringEncodingUtilities.encodeFixedLengthString(busID, length: 32))
        
        // Numeric fields in network byte order (big endian)
        data.append(EndiannessConverter.writeUInt32ToData(busnum))
        data.append(EndiannessConverter.writeUInt32ToData(devnum))
        data.append(EndiannessConverter.writeUInt32ToData(speed))
        data.append(EndiannessConverter.writeUInt16ToData(vendorID))
        data.append(EndiannessConverter.writeUInt16ToData(productID))
        data.append(deviceClass)
        data.append(deviceSubClass)
        data.append(deviceProtocol)
        data.append(configurationCount)
        data.append(configurationValue)
        data.append(interfaceCount)
        
        // Reserved: 2 bytes for alignment
        data.append(contentsOf: [0 as UInt8, 0 as UInt8])
        
        return data
    }
    
    public static func decode(from data: Data) throws -> USBIPExportedDevice {
        guard data.count >= 312 else { // 256 + 32 + 24
            throw USBIPProtocolError.invalidDataLength
        }
        
        // Extract path (256 bytes)
        let path = try StringEncodingUtilities.decodeFixedLengthString(from: data, at: 0, length: 256)
        
        // Extract busID (32 bytes)
        let busID = try StringEncodingUtilities.decodeFixedLengthString(from: data, at: 256, length: 32)
        
        // Extract numeric fields
        let busnum = try EndiannessConverter.readUInt32FromData(data, at: 288)
        let devnum = try EndiannessConverter.readUInt32FromData(data, at: 292)
        let speed = try EndiannessConverter.readUInt32FromData(data, at: 296)
        let vendorID = try EndiannessConverter.readUInt16FromData(data, at: 300)
        let productID = try EndiannessConverter.readUInt16FromData(data, at: 302)
        let deviceClass = data[304]
        let deviceSubClass = data[305]
        let deviceProtocol = data[306]
        let configurationCount = data[307]
        let configurationValue = data[308]
        let interfaceCount = data[309]
        
        return USBIPExportedDevice(
            path: path,
            busID: busID,
            busnum: busnum,
            devnum: devnum,
            speed: speed,
            vendorID: vendorID,
            productID: productID,
            deviceClass: deviceClass,
            deviceSubClass: deviceSubClass,
            deviceProtocol: deviceProtocol,
            configurationCount: configurationCount,
            configurationValue: configurationValue,
            interfaceCount: interfaceCount
        )
    }
}

/// Device list response message
public struct DeviceListResponse: USBIPMessageCodable {
    public let header: USBIPHeader
    public let deviceCount: UInt32
    public let devices: [USBIPExportedDevice]
    
    public init(header: USBIPHeader = USBIPHeader(command: .replyDeviceList), devices: [USBIPExportedDevice]) {
        self.header = header
        self.deviceCount = UInt32(devices.count)
        self.devices = devices
    }
    
    public func encode() throws -> Data {
        var data = try header.encode()
        data.append(EndiannessConverter.writeUInt32ToData(deviceCount))
        
        // Reserved: 4 bytes
        data.append(contentsOf: [UInt8](repeating: 0, count: 4))
        
        for device in devices {
            data.append(try device.encode())
        }
        
        return data
    }
    
    public static func decode(from data: Data) throws -> DeviceListResponse {
        guard data.count >= 16 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        let header = try USBIPHeader.decode(from: data.subdata(in: 0..<8))
        
        guard header.command == .replyDeviceList else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        let deviceCount = try EndiannessConverter.readUInt32FromData(data, at: 8)
        
        // Skip 4 bytes of reserved data
        
        var devices: [USBIPExportedDevice] = []
        var offset = 16
        
        for _ in 0..<deviceCount {
            guard data.count >= offset + 312 else {
                throw USBIPProtocolError.invalidDataLength
            }
            
            let deviceData = data.subdata(in: offset..<(offset + 312))
            let device = try USBIPExportedDevice.decode(from: deviceData)
            devices.append(device)
            
            offset += 312
        }
        
        return DeviceListResponse(header: header, devices: devices)
    }
}

/// Device import request message
public struct DeviceImportRequest: USBIPMessageCodable {
    public let header: USBIPHeader
    public let busID: String
    
    public init(header: USBIPHeader = USBIPHeader(command: .requestDeviceImport), busID: String) {
        self.header = header
        self.busID = busID
    }
    
    public func encode() throws -> Data {
        var data = try header.encode()
        
        // BusID: 32 bytes, null-terminated, padded with zeros
        data.append(try StringEncodingUtilities.encodeFixedLengthString(busID, length: 32))
        
        return data
    }
    
    public static func decode(from data: Data) throws -> DeviceImportRequest {
        guard data.count >= 40 else { // 8 + 32
            throw USBIPProtocolError.invalidDataLength
        }
        
        let header = try USBIPHeader.decode(from: data.subdata(in: 0..<8))
        
        guard header.command == .requestDeviceImport else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Extract busID (32 bytes)
        let busID = try StringEncodingUtilities.decodeFixedLengthString(from: data, at: 8, length: 32)
        
        return DeviceImportRequest(header: header, busID: busID)
    }
}

/// Device information for device import response
public struct USBIPDeviceInfo: USBIPMessageCodable {
    public let path: String
    public let busID: String
    public let busnum: UInt32
    public let devnum: UInt32
    public let speed: UInt32
    public let vendorID: UInt16
    public let productID: UInt16
    public let deviceClass: UInt8
    public let deviceSubClass: UInt8
    public let deviceProtocol: UInt8
    public let configurationCount: UInt8
    public let configurationValue: UInt8
    public let interfaceCount: UInt8
    
    public init(
        path: String,
        busID: String,
        busnum: UInt32,
        devnum: UInt32,
        speed: UInt32,
        vendorID: UInt16,
        productID: UInt16,
        deviceClass: UInt8,
        deviceSubClass: UInt8,
        deviceProtocol: UInt8,
        configurationCount: UInt8,
        configurationValue: UInt8,
        interfaceCount: UInt8
    ) {
        self.path = path
        self.busID = busID
        self.busnum = busnum
        self.devnum = devnum
        self.speed = speed
        self.vendorID = vendorID
        self.productID = productID
        self.deviceClass = deviceClass
        self.deviceSubClass = deviceSubClass
        self.deviceProtocol = deviceProtocol
        self.configurationCount = configurationCount
        self.configurationValue = configurationValue
        self.interfaceCount = interfaceCount
    }
    
    public func encode() throws -> Data {
        var data = Data()
        
        // Path: 256 bytes, null-terminated, padded with zeros
        data.append(try StringEncodingUtilities.encodeFixedLengthString(path, length: 256))
        
        // BusID: 32 bytes, null-terminated, padded with zeros
        data.append(try StringEncodingUtilities.encodeFixedLengthString(busID, length: 32))
        
        // Numeric fields in network byte order (big endian)
        data.append(EndiannessConverter.writeUInt32ToData(busnum))
        data.append(EndiannessConverter.writeUInt32ToData(devnum))
        data.append(EndiannessConverter.writeUInt32ToData(speed))
        data.append(EndiannessConverter.writeUInt16ToData(vendorID))
        data.append(EndiannessConverter.writeUInt16ToData(productID))
        data.append(deviceClass)
        data.append(deviceSubClass)
        data.append(deviceProtocol)
        data.append(configurationCount)
        data.append(configurationValue)
        data.append(interfaceCount)
        
        // Reserved: 2 bytes for alignment
        data.append(contentsOf: [0 as UInt8, 0 as UInt8])
        
        return data
    }
    
    public static func decode(from data: Data) throws -> USBIPDeviceInfo {
        guard data.count >= 312 else { // 256 + 32 + 24
            throw USBIPProtocolError.invalidDataLength
        }
        
        // Extract path (256 bytes)
        let path = try StringEncodingUtilities.decodeFixedLengthString(from: data, at: 0, length: 256)
        
        // Extract busID (32 bytes)
        let busID = try StringEncodingUtilities.decodeFixedLengthString(from: data, at: 256, length: 32)
        
        // Extract numeric fields
        let busnum = try EndiannessConverter.readUInt32FromData(data, at: 288)
        let devnum = try EndiannessConverter.readUInt32FromData(data, at: 292)
        let speed = try EndiannessConverter.readUInt32FromData(data, at: 296)
        let vendorID = try EndiannessConverter.readUInt16FromData(data, at: 300)
        let productID = try EndiannessConverter.readUInt16FromData(data, at: 302)
        let deviceClass = data[304]
        let deviceSubClass = data[305]
        let deviceProtocol = data[306]
        let configurationCount = data[307]
        let configurationValue = data[308]
        let interfaceCount = data[309]
        
        return USBIPDeviceInfo(
            path: path,
            busID: busID,
            busnum: busnum,
            devnum: devnum,
            speed: speed,
            vendorID: vendorID,
            productID: productID,
            deviceClass: deviceClass,
            deviceSubClass: deviceSubClass,
            deviceProtocol: deviceProtocol,
            configurationCount: configurationCount,
            configurationValue: configurationValue,
            interfaceCount: interfaceCount
        )
    }
}

/// Device import response message
public struct DeviceImportResponse: USBIPMessageCodable {
    public let header: USBIPHeader
    public let status: UInt32
    public let deviceInfo: USBIPDeviceInfo?
    
    public init(header: USBIPHeader = USBIPHeader(command: .replyDeviceImport), status: UInt32, deviceInfo: USBIPDeviceInfo?) {
        self.header = header
        self.status = status
        self.deviceInfo = deviceInfo
    }
    
    public func encode() throws -> Data {
        var data = try header.encode()
        data.append(EndiannessConverter.writeUInt32ToData(status))
        
        if let deviceInfo = deviceInfo {
            data.append(try deviceInfo.encode())
        }
        
        return data
    }
    
    public static func decode(from data: Data) throws -> DeviceImportResponse {
        guard data.count >= 12 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        let header = try USBIPHeader.decode(from: data.subdata(in: 0..<8))
        
        guard header.command == .replyDeviceImport else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        let status = try EndiannessConverter.readUInt32FromData(data, at: 8)
        
        var deviceInfo: USBIPDeviceInfo? = nil
        if data.count >= 324 && status == 0 { // 12 + 312
            deviceInfo = try USBIPDeviceInfo.decode(from: data.subdata(in: 12..<324))
        }
        
        return DeviceImportResponse(header: header, status: status, deviceInfo: deviceInfo)
    }
}

// MARK: - USB SUBMIT Request/Response Messages

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
        
        // Reserved field: 4 bytes
        data.append(contentsOf: [UInt8](repeating: 0, count: 4))
        
        // Setup packet: exactly 8 bytes (padded or truncated if needed)
        var setupData = setup
        if setupData.count > 8 {
            setupData = setupData.subdata(in: 0..<8)
        } else if setupData.count < 8 {
            setupData.append(contentsOf: [UInt8](repeating: 0, count: 8 - setupData.count))
        }
        data.append(setupData)
        
        // Transfer buffer for OUT transfers
        if let buffer = transferBuffer {
            data.append(buffer)
        }
        
        return data
    }
    
    public static func decode(from data: Data) throws -> USBIPSubmitRequest {
        // Validate minimum size: header (8) + command fields (40) + setup (8) = 56 bytes
        guard data.count >= 56 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        // Decode header
        let header = try USBIPHeader.decode(from: data.subdata(in: 0..<8))
        
        guard header.command == .submitRequest else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Decode command fields
        let seqnum = try EndiannessConverter.readUInt32FromData(data, at: 8)
        let devid = try EndiannessConverter.readUInt32FromData(data, at: 12)
        let direction = try EndiannessConverter.readUInt32FromData(data, at: 16)
        let ep = try EndiannessConverter.readUInt32FromData(data, at: 20)
        let transferFlags = try EndiannessConverter.readUInt32FromData(data, at: 24)
        let transferBufferLength = try EndiannessConverter.readUInt32FromData(data, at: 28)
        let startFrame = try EndiannessConverter.readUInt32FromData(data, at: 32)
        let numberOfPackets = try EndiannessConverter.readUInt32FromData(data, at: 36)
        let interval = try EndiannessConverter.readUInt32FromData(data, at: 40)
        
        // Skip reserved field (4 bytes at offset 44)
        
        // Extract setup packet (8 bytes at offset 48)
        let setup = data.subdata(in: 48..<56)
        
        // Extract transfer buffer if present (for OUT transfers)
        var transferBuffer: Data? = nil
        if data.count > 56 && transferBufferLength > 0 {
            let bufferEndIndex = min(data.count, 56 + Int(transferBufferLength))
            transferBuffer = data.subdata(in: 56..<bufferEndIndex)
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
    public let seqnum: UInt32              // Matching request sequence number
    public let devid: UInt32               // Device ID
    public let direction: UInt32           // Transfer direction (0=OUT, 1=IN)
    public let ep: UInt32                  // Endpoint address
    public let status: Int32               // USB transfer completion status
    public let actualLength: UInt32        // Actual bytes transferred
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
        
        // USB/IP SUBMIT response fields (36 bytes after header)
        data.append(EndiannessConverter.writeUInt32ToData(seqnum))
        data.append(EndiannessConverter.writeUInt32ToData(devid))
        data.append(EndiannessConverter.writeUInt32ToData(direction))
        data.append(EndiannessConverter.writeUInt32ToData(ep))
        
        // Status is signed 32-bit integer
        data.append(withUnsafeBytes(of: status.bigEndian) { Data($0) })
        
        data.append(EndiannessConverter.writeUInt32ToData(actualLength))
        data.append(EndiannessConverter.writeUInt32ToData(startFrame))
        data.append(EndiannessConverter.writeUInt32ToData(numberOfPackets))
        data.append(EndiannessConverter.writeUInt32ToData(errorCount))
        
        // Reserved field: 8 bytes
        data.append(contentsOf: [UInt8](repeating: 0, count: 8))
        
        // Transfer buffer for IN transfers
        if let buffer = transferBuffer {
            data.append(buffer)
        }
        
        return data
    }
    
    public static func decode(from data: Data) throws -> USBIPSubmitResponse {
        // Validate minimum size: header (8) + response fields (36) + reserved (8) = 52 bytes
        guard data.count >= 52 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        // Decode header
        let header = try USBIPHeader.decode(from: data.subdata(in: 0..<8))
        
        guard header.command == .submitReply else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Decode response fields
        let seqnum = try EndiannessConverter.readUInt32FromData(data, at: 8)
        let devid = try EndiannessConverter.readUInt32FromData(data, at: 12)
        let direction = try EndiannessConverter.readUInt32FromData(data, at: 16)
        let ep = try EndiannessConverter.readUInt32FromData(data, at: 20)
        
        // Status is signed 32-bit integer
        let statusRaw = try EndiannessConverter.readUInt32FromData(data, at: 24)
        let status = Int32(bitPattern: statusRaw)
        
        let actualLength = try EndiannessConverter.readUInt32FromData(data, at: 28)
        let startFrame = try EndiannessConverter.readUInt32FromData(data, at: 32)
        let numberOfPackets = try EndiannessConverter.readUInt32FromData(data, at: 36)
        let errorCount = try EndiannessConverter.readUInt32FromData(data, at: 40)
        
        // Skip reserved field (8 bytes at offset 44)
        
        // Extract transfer buffer if present (for IN transfers)
        var transferBuffer: Data? = nil
        if data.count > 52 && actualLength > 0 {
            let bufferEndIndex = min(data.count, 52 + Int(actualLength))
            transferBuffer = data.subdata(in: 52..<bufferEndIndex)
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

// MARK: - USB UNLINK Request/Response Messages

/// USB/IP UNLINK request message (USBIP_CMD_UNLINK)
public struct USBIPUnlinkRequest: USBIPMessageCodable {
    public let header: USBIPHeader
    public let seqnum: UInt32              // Unique request sequence number
    public let devid: UInt32               // Device ID
    public let direction: UInt32           // Transfer direction (0=OUT, 1=IN)
    public let ep: UInt32                  // Endpoint address
    public let unlinkSeqnum: UInt32        // Sequence number of request to unlink
    
    public init(
        header: USBIPHeader = USBIPHeader(command: .unlinkRequest),
        seqnum: UInt32,
        devid: UInt32,
        direction: UInt32,
        ep: UInt32,
        unlinkSeqnum: UInt32
    ) {
        self.header = header
        self.seqnum = seqnum
        self.devid = devid
        self.direction = direction
        self.ep = ep
        self.unlinkSeqnum = unlinkSeqnum
    }
    
    public func encode() throws -> Data {
        var data = try header.encode()
        
        // USB/IP UNLINK command fields (20 bytes after header)
        data.append(EndiannessConverter.writeUInt32ToData(seqnum))
        data.append(EndiannessConverter.writeUInt32ToData(devid))
        data.append(EndiannessConverter.writeUInt32ToData(direction))
        data.append(EndiannessConverter.writeUInt32ToData(ep))
        data.append(EndiannessConverter.writeUInt32ToData(unlinkSeqnum))
        
        // Reserved fields: 24 bytes for protocol alignment
        data.append(contentsOf: [UInt8](repeating: 0, count: 24))
        
        return data
    }
    
    public static func decode(from data: Data) throws -> USBIPUnlinkRequest {
        // Validate minimum size: header (8) + command fields (20) + reserved (24) = 52 bytes
        guard data.count >= 52 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        // Decode header
        let header = try USBIPHeader.decode(from: data.subdata(in: 0..<8))
        
        guard header.command == .unlinkRequest else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Decode command fields
        let seqnum = try EndiannessConverter.readUInt32FromData(data, at: 8)
        let devid = try EndiannessConverter.readUInt32FromData(data, at: 12)
        let direction = try EndiannessConverter.readUInt32FromData(data, at: 16)
        let ep = try EndiannessConverter.readUInt32FromData(data, at: 20)
        let unlinkSeqnum = try EndiannessConverter.readUInt32FromData(data, at: 24)
        
        // Skip reserved fields (24 bytes at offset 28)
        
        return USBIPUnlinkRequest(
            header: header,
            seqnum: seqnum,
            devid: devid,
            direction: direction,
            ep: ep,
            unlinkSeqnum: unlinkSeqnum
        )
    }
}

/// USB/IP UNLINK response message (USBIP_RET_UNLINK)
public struct USBIPUnlinkResponse: USBIPMessageCodable {
    public let header: USBIPHeader
    public let seqnum: UInt32              // Matching request sequence number
    public let devid: UInt32               // Device ID
    public let direction: UInt32           // Transfer direction (0=OUT, 1=IN)
    public let ep: UInt32                  // Endpoint address
    public let status: Int32               // Unlink operation status (0=success, negative=error)
    
    public init(
        header: USBIPHeader = USBIPHeader(command: .unlinkReply),
        seqnum: UInt32,
        devid: UInt32,
        direction: UInt32,
        ep: UInt32,
        status: Int32
    ) {
        self.header = header
        self.seqnum = seqnum
        self.devid = devid
        self.direction = direction
        self.ep = ep
        self.status = status
    }
    
    public func encode() throws -> Data {
        var data = try header.encode()
        
        // USB/IP UNLINK response fields (20 bytes after header)
        data.append(EndiannessConverter.writeUInt32ToData(seqnum))
        data.append(EndiannessConverter.writeUInt32ToData(devid))
        data.append(EndiannessConverter.writeUInt32ToData(direction))
        data.append(EndiannessConverter.writeUInt32ToData(ep))
        
        // Status is signed 32-bit integer
        data.append(withUnsafeBytes(of: status.bigEndian) { Data($0) })
        
        // Reserved fields: 24 bytes for protocol alignment
        data.append(contentsOf: [UInt8](repeating: 0, count: 24))
        
        return data
    }
    
    public static func decode(from data: Data) throws -> USBIPUnlinkResponse {
        // Validate minimum size: header (8) + response fields (20) + reserved (24) = 52 bytes
        guard data.count >= 52 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        // Decode header
        let header = try USBIPHeader.decode(from: data.subdata(in: 0..<8))
        
        guard header.command == .unlinkReply else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Decode response fields
        let seqnum = try EndiannessConverter.readUInt32FromData(data, at: 8)
        let devid = try EndiannessConverter.readUInt32FromData(data, at: 12)
        let direction = try EndiannessConverter.readUInt32FromData(data, at: 16)
        let ep = try EndiannessConverter.readUInt32FromData(data, at: 20)
        
        // Status is signed 32-bit integer
        let statusRaw = try EndiannessConverter.readUInt32FromData(data, at: 24)
        let status = Int32(bitPattern: statusRaw)
        
        // Skip reserved fields (24 bytes at offset 28)
        
        return USBIPUnlinkResponse(
            header: header,
            seqnum: seqnum,
            devid: devid,
            direction: direction,
            ep: ep,
            status: status
        )
    }
}