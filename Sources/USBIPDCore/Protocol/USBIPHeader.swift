// USBIPHeader.swift
// USB/IP protocol header and core message types

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