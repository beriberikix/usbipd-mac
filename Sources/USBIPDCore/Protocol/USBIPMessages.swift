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