// USBIPMessages.swift
// USB/IP protocol message extensions and utilities

import Foundation
import Common

/// USB/IP protocol error types
public enum USBIPProtocolError: Error, LocalizedError {
    case invalidDataLength
    case invalidMessageFormat
    case invalidHeader
    case unsupportedCommand(UInt16)
    case unsupportedVersion(UInt16)
    case encodingFailed(String)
    case decodingFailed(String)
    case invalidMessage
    
    public var errorDescription: String? {
        switch self {
        case .invalidDataLength:
            return "Invalid data length for USB/IP message"
        case .invalidMessageFormat:
            return "Invalid USB/IP message format"
        case .invalidHeader:
            return "Invalid USB/IP message header"
        case .unsupportedCommand(let command):
            return "Unsupported USB/IP command: 0x\(String(command, radix: 16))"
        case .unsupportedVersion(let version):
            return "Unsupported USB/IP protocol version: 0x\(String(version, radix: 16))"
        case .encodingFailed(let reason):
            return "USB/IP message encoding failed: \(reason)"
        case .decodingFailed(let reason):
            return "USB/IP message decoding failed: \(reason)"
        case .invalidMessage:
            return "Invalid USB/IP message"
        }
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