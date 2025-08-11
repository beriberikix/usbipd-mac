// USBIPProtocol.swift
// Core protocol implementation for USB/IP

import Foundation

/// Main protocol implementation for USB/IP
public enum USBIPProtocol {
    /// USB/IP protocol version
    public static let version: UInt16 = 0x0111 // Version 1.1.1
    
    /// USB/IP command codes
    public enum Command: UInt16 {
        case requestDeviceList = 0x8005
        case replyDeviceList = 0x0005
        case requestDeviceImport = 0x8003
        case replyDeviceImport = 0x0003
        case submitRequest = 0x0001      // USBIP_CMD_SUBMIT
        case submitReply = 0x0013        // USBIP_RET_SUBMIT  
        case unlinkRequest = 0x0002      // USBIP_CMD_UNLINK
        case unlinkReply = 0x0004        // USBIP_RET_UNLINK
    }
}

/// Protocol for USB/IP message encoding and decoding
public protocol USBIPMessageCodable {
    /// Encode the message to binary data
    func encode() throws -> Data
    
    /// Decode a message from binary data
    static func decode(from data: Data) throws -> Self
}