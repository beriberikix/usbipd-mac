// USBIPProtocol.swift
// Core protocol implementation for USB/IP

import Foundation

/// Main protocol implementation for USB/IP
public enum USBIPProtocol {
    /// USB/IP protocol version
    public static let version: UInt16 = 0x0111 // Version 1.1.1

    /// Fixed prefix on every CMD_/RET_ message: a 20-byte usbip_header_basic plus a
    /// 28-byte command block. The block is 28 because `union u` in `struct
    /// usbip_header` is sized by its largest member, usbip_header_cmd_submit
    /// (5 x 4-byte fields + setup[8]); the unlink variants are padded out to match.
    ///
    /// Kept in one place because these sizes were previously duplicated as literals
    /// across encode, decode and validation, and drifted apart.
    public static let commandMessagePrefixSize = 48
    
    /// USB/IP message identifiers used for dispatch within this codebase.
    ///
    /// IMPORTANT: only the four OP_ cases carry wire values here. USB/IP has two
    /// distinct message framings, and their number spaces overlap:
    ///
    ///  - The OP_ handshake (device list, import) uses `op_common`:
    ///    version(2) + code(2) + status(4) = 8 bytes. Those 2-byte codes are the
    ///    raw values below.
    ///  - Everything after import — SUBMIT/UNLINK and their replies — uses
    ///    `usbip_header_basic`: command(4) + seqnum(4) + devid(4) + direction(4) +
    ///    ep(4) = 20 bytes, with no version field. Those 4-byte codes live in
    ///    `BasicCommand`.
    ///
    /// The spaces genuinely collide: USBIP_RET_SUBMIT is 0x3 and OP_REP_IMPORT is
    /// also 0x3. Earlier revisions of this file forced both framings through one
    /// enum, which required inventing 0x0013 for submitReply to dodge that clash
    /// and produced a wire format no usbip client can parse.
    ///
    /// The raw values on the CMD_/RET_ cases below are therefore internal dispatch
    /// tokens only. Never write them to the wire — use `BasicCommand`.
    public enum Command: UInt16 {
        case requestDeviceList = 0x8005
        case replyDeviceList = 0x0005
        case requestDeviceImport = 0x8003
        case replyDeviceImport = 0x0003
        case submitRequest = 0xF001      // internal token; wire value is BasicCommand.submit
        case submitReply = 0xF003        // internal token; wire value is BasicCommand.retSubmit
        case unlinkRequest = 0xF002      // internal token; wire value is BasicCommand.unlink
        case unlinkReply = 0xF004        // internal token; wire value is BasicCommand.retUnlink

        /// The wire command for messages framed with `usbip_header_basic`,
        /// or nil for the OP_ handshake messages, which are not.
        public var basicCommand: BasicCommand? {
            switch self {
            case .submitRequest: return .submit
            case .unlinkRequest: return .unlink
            case .submitReply: return .retSubmit
            case .unlinkReply: return .retUnlink
            default: return nil
            }
        }
    }

    /// Command codes carried in the 4-byte `command` field of `usbip_header_basic`.
    /// Values from linux/drivers/usb/usbip/usbip_common.h.
    public enum BasicCommand: UInt32 {
        case submit = 0x0000_0001       // USBIP_CMD_SUBMIT
        case unlink = 0x0000_0002       // USBIP_CMD_UNLINK
        case retSubmit = 0x0000_0003    // USBIP_RET_SUBMIT
        case retUnlink = 0x0000_0004    // USBIP_RET_UNLINK

        /// The internal dispatch token for this wire command.
        public var command: Command {
            switch self {
            case .submit: return .submitRequest
            case .unlink: return .unlinkRequest
            case .retSubmit: return .submitReply
            case .retUnlink: return .unlinkReply
            }
        }
    }
}

/// Protocol for USB/IP message encoding and decoding
public protocol USBIPMessageCodable {
    /// Encode the message to binary data
    func encode() throws -> Data
    
    /// Decode a message from binary data
    static func decode(from data: Data) throws -> Self
}