// EncodingUtilities.swift
// Utilities for encoding and decoding USB/IP protocol messages

import Foundation
import Common

// MARK: - Data Extensions for Reading

extension Data {
    /// Read a UInt16 value from the data at the specified offset
    func readUInt16(at offset: Int) -> UInt16? {
        guard offset + 2 <= count else { return nil }
        return withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: UInt16.self)
        }
    }
    
    /// Read a UInt32 value from the data at the specified offset
    func readUInt32(at offset: Int) -> UInt32? {
        guard offset + 4 <= count else { return nil }
        return withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: UInt32.self)
        }
    }
}

// MARK: - Integer Extensions for Encoding

extension UInt16 {
    /// Convert UInt16 to Data in big-endian format
    var data: Data {
        return withUnsafeBytes(of: self) { Data($0) }
    }
}

extension UInt32 {
    /// Convert UInt32 to Data in big-endian format
    var data: Data {
        return withUnsafeBytes(of: self) { Data($0) }
    }
}

extension UInt8 {
    /// Convert UInt8 to Data
    var data: Data {
        return Data([self])
    }
}

// MARK: - Message Encoder

/// Encoder for USB/IP protocol messages
public struct USBIPMessageEncoder {
    
    /// Encode any USBIPMessageCodable message to Data
    public static func encode<T: USBIPMessageCodable>(_ message: T) throws -> Data {
        return try message.encode()
    }
    
    /// Encode a device list request
    public static func encodeDeviceListRequest() throws -> Data {
        let request = DeviceListRequest()
        return try request.encode()
    }
    
    /// Encode a device list response
    public static func encodeDeviceListResponse(devices: [USBIPExportedDevice]) throws -> Data {
        let response = DeviceListResponse(devices: devices)
        return try response.encode()
    }
    
    /// Encode a device import request
    public static func encodeDeviceImportRequest(busID: String) throws -> Data {
        let request = DeviceImportRequest(busID: busID)
        return try request.encode()
    }
    
    /// Encode a device import response
    public static func encodeDeviceImportResponse(status: UInt32, deviceInfo: USBIPDeviceInfo?) throws -> Data {
        let response = DeviceImportResponse(status: status, deviceInfo: deviceInfo)
        return try response.encode()
    }
}

// MARK: - Message Decoder

/// Decoder for USB/IP protocol messages with validation and error handling
public struct USBIPMessageDecoder {
    
    /// Decode any USBIPMessageCodable message from Data
    public static func decode<T: USBIPMessageCodable>(_ type: T.Type, from data: Data) throws -> T {
        return try type.decode(from: data)
    }
    
    /// Decode a USB/IP message based on the command in the header
    public static func decodeMessage(from data: Data) throws -> USBIPMessageCodable {
        // First, validate minimum data length for header
        guard data.count >= 8 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        // Decode the header to determine message type
        let header = try USBIPHeader.decode(from: data)
        
        // Validate protocol version
        guard header.version == USBIPProtocol.version else {
            throw USBIPProtocolError.unsupportedVersion(header.version)
        }
        
        // Decode based on command type
        switch header.command {
        case .requestDeviceList:
            return try DeviceListRequest.decode(from: data)
        case .replyDeviceList:
            return try DeviceListResponse.decode(from: data)
        case .requestDeviceImport:
            return try DeviceImportRequest.decode(from: data)
        case .replyDeviceImport:
            return try DeviceImportResponse.decode(from: data)
        }
    }
    
    /// Decode a device list request with validation
    public static func decodeDeviceListRequest(from data: Data) throws -> DeviceListRequest {
        // Validate minimum data length
        guard data.count >= 8 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        // Validate that this is exactly the expected length for a device list request
        guard data.count == 8 else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        return try DeviceListRequest.decode(from: data)
    }
    
    /// Decode a device list response with validation
    public static func decodeDeviceListResponse(from data: Data) throws -> DeviceListResponse {
        // Validate minimum data length (header + device count + reserved)
        guard data.count >= 16 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        return try DeviceListResponse.decode(from: data)
    }
    
    /// Decode a device import request with validation
    public static func decodeDeviceImportRequest(from data: Data) throws -> DeviceImportRequest {
        // Validate minimum data length (header + busID)
        guard data.count >= 40 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        // Validate that this is exactly the expected length for a device import request
        guard data.count == 40 else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        return try DeviceImportRequest.decode(from: data)
    }
    
    /// Decode a device import response with validation
    public static func decodeDeviceImportResponse(from data: Data) throws -> DeviceImportResponse {
        // Validate minimum data length (header + status)
        guard data.count >= 12 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        // Validate expected lengths: 12 bytes (error response) or 324 bytes (success response)
        guard data.count == 12 || data.count == 324 else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        return try DeviceImportResponse.decode(from: data)
    }
    
    /// Validate that data contains a valid USB/IP header
    public static func validateHeader(in data: Data) throws -> USBIPHeader {
        guard data.count >= 8 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        let header = try USBIPHeader.decode(from: data)
        
        // Validate protocol version
        guard header.version == USBIPProtocol.version else {
            throw USBIPProtocolError.unsupportedVersion(header.version)
        }
        
        return header
    }
    
    /// Peek at the command type without fully decoding the message
    public static func peekCommand(in data: Data) throws -> USBIPProtocol.Command {
        guard data.count >= 8 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        let commandValue = try EndiannessConverter.readUInt16FromData(data, at: 2)
        
        guard let command = USBIPProtocol.Command(rawValue: commandValue) else {
            throw USBIPProtocolError.unsupportedCommand(commandValue)
        }
        
        return command
    }
    
    /// Validate message integrity by attempting to decode and re-encode
    public static func validateMessageIntegrity(data: Data) throws -> Bool {
        do {
            let decodedMessage = try decodeMessage(from: data)
            let reEncodedData = try decodedMessage.encode()
            
            // Compare original and re-encoded data
            return data == reEncodedData
        } catch {
            // If decoding or encoding fails, the message is not valid
            return false
        }
    }
}

// MARK: - Endianness Handling

/// Utilities for handling endianness conversion
public struct EndiannessConverter {
    
    /// Convert UInt16 to network byte order (big endian)
    public static func toNetworkByteOrder(_ value: UInt16) -> UInt16 {
        return value.bigEndian
    }
    
    /// Convert UInt32 to network byte order (big endian)
    public static func toNetworkByteOrder(_ value: UInt32) -> UInt32 {
        return value.bigEndian
    }
    
    /// Convert UInt16 from network byte order (big endian)
    public static func fromNetworkByteOrder(_ value: UInt16) -> UInt16 {
        return UInt16(bigEndian: value)
    }
    
    /// Convert UInt32 from network byte order (big endian)
    public static func fromNetworkByteOrder(_ value: UInt32) -> UInt32 {
        return UInt32(bigEndian: value)
    }
    
    /// Write UInt16 to Data in network byte order
    public static func writeUInt16ToData(_ value: UInt16) -> Data {
        return toNetworkByteOrder(value).data
    }
    
    /// Write UInt32 to Data in network byte order
    public static func writeUInt32ToData(_ value: UInt32) -> Data {
        return toNetworkByteOrder(value).data
    }
    
    /// Read UInt16 from Data in network byte order
    public static func readUInt16FromData(_ data: Data, at offset: Int) throws -> UInt16 {
        guard let value = data.readUInt16(at: offset) else {
            throw USBIPProtocolError.invalidDataLength
        }
        return fromNetworkByteOrder(value)
    }
    
    /// Read UInt32 from Data in network byte order
    public static func readUInt32FromData(_ data: Data, at offset: Int) throws -> UInt32 {
        guard let value = data.readUInt32(at: offset) else {
            throw USBIPProtocolError.invalidDataLength
        }
        return fromNetworkByteOrder(value)
    }
}

// MARK: - String Encoding Utilities

/// Utilities for encoding strings in USB/IP messages
public struct StringEncodingUtilities {
    
    /// Encode a string to fixed-length ASCII data with null termination and padding
    public static func encodeFixedLengthString(_ string: String, length: Int) throws -> Data {
        guard let stringData = string.data(using: .ascii) else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        guard stringData.count < length else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        var data = Data(capacity: length)
        data.append(stringData)
        
        // Add null terminator and padding
        data.append(contentsOf: [UInt8](repeating: 0, count: length - stringData.count))
        
        return data
    }
    
    /// Decode a fixed-length string from ASCII data
    public static func decodeFixedLengthString(from data: Data, at offset: Int, length: Int) throws -> String {
        guard offset + length <= data.count else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        let stringData = data.subdata(in: offset..<(offset + length))
        
        // Find null terminator
        guard let nullIndex = stringData.firstIndex(of: 0) else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        let actualStringData = stringData.subdata(in: 0..<nullIndex)
        
        guard let string = String(data: actualStringData, encoding: .ascii) else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        return string
    }
}