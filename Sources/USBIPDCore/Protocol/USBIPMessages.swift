// USBIPMessages.swift
// USB/IP protocol message extensions and utilities

import Foundation
import Common

/// Protocol for USB/IP message encoding and decoding
public protocol USBIPMessageCodable {
    func encode() throws -> Data
    static func decode(from data: Data) throws -> Self
}

/// USB/IP protocol error types
public enum USBIPProtocolError: Error, LocalizedError {
    case invalidDataLength
    case invalidMessageFormat
    case unsupportedCommand(UInt16)
    case encodingFailed(String)
    case decodingFailed(String)
    case invalidMessage
    
    public var errorDescription: String? {
        switch self {
        case .invalidDataLength:
            return "Invalid data length for USB/IP message"
        case .invalidMessageFormat:
            return "Invalid USB/IP message format"
        case .unsupportedCommand(let command):
            return "Unsupported USB/IP command: 0x\(String(command, radix: 16))"
        case .encodingFailed(let reason):
            return "USB/IP message encoding failed: \(reason)"
        case .decodingFailed(let reason):
            return "USB/IP message decoding failed: \(reason)"
        case .invalidMessage:
            return "Invalid USB/IP message"
        }
    }
}

/// String encoding utilities for USB/IP messages
public struct StringEncodingUtilities {
    
    /// Encodes a string to fixed-length data with null termination and zero padding
    public static func encodeFixedLengthString(_ string: String, length: Int) throws -> Data {
        guard let stringData = string.data(using: .utf8) else {
            throw USBIPProtocolError.encodingFailed("String encoding failed")
        }
        
        guard stringData.count < length else {
            throw USBIPProtocolError.encodingFailed("String too long for field")
        }
        
        var data = Data(capacity: length)
        data.append(stringData)
        
        // Add null terminator
        data.append(0)
        
        // Pad with zeros to reach required length
        while data.count < length {
            data.append(0)
        }
        
        return data
    }
    
    /// Decodes a fixed-length string from data, handling null termination
    public static func decodeFixedLengthString(from data: Data, at offset: Int, length: Int) throws -> String {
        guard data.count >= offset + length else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        let stringData = data.subdata(in: offset..<(offset + length))
        
        // Find null terminator or use full length
        var actualLength = length
        for i in 0..<length {
            if stringData[i] == 0 {
                actualLength = i
                break
            }
        }
        
        let actualData = stringData.prefix(actualLength)
        
        guard let string = String(data: actualData, encoding: .utf8) else {
            throw USBIPProtocolError.decodingFailed("String decoding failed")
        }
        
        return string
    }
}

/// Endianness conversion utilities for USB/IP network byte order
public struct EndiannessConverter {
    
    /// Write UInt16 in network byte order (big endian)
    public static func writeUInt16ToData(_ value: UInt16) -> Data {
        return Data([
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ])
    }
    
    /// Write UInt32 in network byte order (big endian)
    public static func writeUInt32ToData(_ value: UInt32) -> Data {
        return Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ])
    }
    
    /// Write Int32 in network byte order (big endian)
    public static func writeInt32ToData(_ value: Int32) -> Data {
        return writeUInt32ToData(UInt32(bitPattern: value))
    }
    
    /// Read UInt16 from network byte order (big endian)
    public static func readUInt16FromData(_ data: Data, at offset: Int) throws -> UInt16 {
        guard data.count >= offset + 2 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }
    
    /// Read UInt32 from network byte order (big endian)
    public static func readUInt32FromData(_ data: Data, at offset: Int) throws -> UInt32 {
        guard data.count >= offset + 4 else {
            throw USBIPProtocolError.invalidDataLength
        }
        
        return UInt32(data[offset]) << 24 |
               UInt32(data[offset + 1]) << 16 |
               UInt32(data[offset + 2]) << 8 |
               UInt32(data[offset + 3])
    }
    
    /// Read Int32 from network byte order (big endian)
    public static func readInt32FromData(_ data: Data, at offset: Int) throws -> Int32 {
        let value = try readUInt32FromData(data, at: offset)
        return Int32(bitPattern: value)
    }
}

/// USB/IP message factory for creating typed messages from raw data
public struct USBIPMessageFactory {
    
    /// Creates appropriate message type from raw data based on header
    public static func createMessage(from data: Data) throws -> USBIPMessageCodable {
        let header = try USBIPHeader.decode(from: data)
        
        switch header.command {
        case .requestDeviceList:
            return try DeviceListRequest.decode(from: data)
        case .replyDeviceList:
            return try DeviceListResponse.decode(from: data)
        case .requestDeviceImport:
            return try DeviceImportRequest.decode(from: data)
        case .replyDeviceImport:
            return try DeviceImportResponse.decode(from: data)
        case .submitRequest:
            return try USBIPSubmitRequest.decode(from: data)
        case .submitReply:
            return try USBIPSubmitResponse.decode(from: data)
        case .unlinkRequest:
            return try USBIPUnlinkRequest.decode(from: data)
        case .unlinkReply:
            return try USBIPUnlinkResponse.decode(from: data)
        }
    }
}

/// USB/IP message validation utilities
public struct USBIPMessageValidator {
    
    /// Validates message format and structure
    public static func validateMessage(_ message: USBIPMessageCodable) throws {
        // Basic validation - encode and decode cycle
        let data = try message.encode()
        
        // Ensure minimum header size
        guard data.count >= 8 else {
            throw USBIPProtocolError.invalidMessageFormat
        }
        
        // Validate header
        let header = try USBIPHeader.decode(from: data)
        
        // Basic command validation
        switch header.command {
        case .requestDeviceList, .replyDeviceList,
             .requestDeviceImport, .replyDeviceImport,
             .submitRequest, .submitReply,
             .unlinkRequest, .unlinkReply:
            break // Valid commands
        }
    }
}