// USBRequestModels.swift
// USB request/response data models for USB/IP protocol implementation

import Foundation
import IOKit
import IOKit.usb
import Common

/// USB transfer type enumeration matching USB specification
public enum USBTransferType: UInt8 {
    case control = 0
    case isochronous = 1
    case bulk = 2
    case interrupt = 3
}

/// URB (USB Request Block) processing status
public enum URBStatus {
    case pending        // Request created but not yet started
    case inProgress     // Request is being processed
    case completed      // Request completed successfully
    case cancelled      // Request was cancelled
    case failed         // Request failed with error
}

/// USB transfer direction
public enum USBTransferDirection: UInt32 {
    case out = 0    // Host to device
    case `in` = 1   // Device to host
}

/// USB Request Block (URB) representing a USB transfer operation
public struct USBRequestBlock {
    /// Unique request sequence number for tracking
    public let seqnum: UInt32
    
    /// Target device identifier
    public let devid: UInt32
    
    /// Transfer direction (in/out)
    public let direction: USBTransferDirection
    
    /// USB endpoint address
    public let endpoint: UInt8
    
    /// Transfer type (control, bulk, interrupt, isochronous)
    public let transferType: USBTransferType
    
    /// USB transfer flags (e.g., short packet handling)
    public let transferFlags: UInt32
    
    /// Expected transfer length in bytes
    public let bufferLength: UInt32
    
    /// Control transfer setup packet (8 bytes, only for control transfers)
    public let setupPacket: Data?
    
    /// Data buffer for OUT transfers
    public let transferBuffer: Data?
    
    /// Operation timeout in milliseconds
    public let timeout: UInt32
    
    /// Start frame number for isochronous transfers
    public let startFrame: UInt32
    
    /// Number of packets for isochronous transfers
    public let numberOfPackets: UInt32
    
    /// Polling interval for interrupt transfers
    public let interval: UInt32
    
    public init(
        seqnum: UInt32,
        devid: UInt32,
        direction: USBTransferDirection,
        endpoint: UInt8,
        transferType: USBTransferType,
        transferFlags: UInt32,
        bufferLength: UInt32,
        setupPacket: Data? = nil,
        transferBuffer: Data? = nil,
        timeout: UInt32 = 5000,
        startFrame: UInt32 = 0,
        numberOfPackets: UInt32 = 0,
        interval: UInt32 = 0
    ) {
        self.seqnum = seqnum
        self.devid = devid
        self.direction = direction
        self.endpoint = endpoint
        self.transferType = transferType
        self.transferFlags = transferFlags
        self.bufferLength = bufferLength
        self.setupPacket = setupPacket
        self.transferBuffer = transferBuffer
        self.timeout = timeout
        self.startFrame = startFrame
        self.numberOfPackets = numberOfPackets
        self.interval = interval
    }
}

/// USB transfer completion result
public struct USBTransferResult {
    /// USB completion status code
    public let status: USBStatus
    
    /// Actual number of bytes transferred
    public let actualLength: UInt32
    
    /// Error count for isochronous transfers
    public let errorCount: UInt32
    
    /// Received data for IN transfers
    public let data: Data?
    
    /// Transfer completion timestamp
    public let completionTime: TimeInterval
    
    /// Start frame for isochronous transfers
    public let startFrame: UInt32
    
    public init(
        status: USBStatus,
        actualLength: UInt32,
        errorCount: UInt32 = 0,
        data: Data? = nil,
        completionTime: TimeInterval = Date().timeIntervalSince1970,
        startFrame: UInt32 = 0
    ) {
        self.status = status
        self.actualLength = actualLength
        self.errorCount = errorCount
        self.data = data
        self.completionTime = completionTime
        self.startFrame = startFrame
    }
}

/// USB status codes following USB specification and Linux USB/IP implementation
public enum USBStatus: Int32 {
    // Success
    case success = 0
    
    // USB errors
    case stall = -32        // Endpoint stalled
    case timeout = -110     // Transfer timed out
    case cancelled = -125   // Transfer cancelled
    case shortPacket = -121 // Short packet detected
    case deviceGone = -19   // Device disconnected
    case noDevice = -20     // No device present
    case requestFailed = -71 // Generic request failure
    
    // Protocol errors
    case protocolError = -72
    case memoryError = -12
    case invalidRequest = -22
    case busError = -73
    case bufferError = -90
}

/// USB error handling utilities for IOKit to USB status mapping
public struct USBErrorMapping {
    
    /// Maps IOKit error codes to USB status codes
    public static func mapIOKitError(_ ioKitError: IOReturn) -> Int32 {
        switch ioKitError {
        case kIOReturnSuccess:
            return USBStatus.success.rawValue
        case kIOReturnTimeout:
            return USBStatus.timeout.rawValue
        case kIOReturnAborted:
            return USBStatus.cancelled.rawValue
        case kIOReturnBadArgument:
            return USBStatus.invalidRequest.rawValue
        case kIOReturnNoDevice:
            return USBStatus.deviceGone.rawValue
        case kIOReturnNotResponding:
            return USBStatus.deviceGone.rawValue
        case kIOReturnNoMemory:
            return USBStatus.memoryError.rawValue
        case kIOReturnUnderrun:
            return USBStatus.shortPacket.rawValue
        case kIOReturnOverrun:
            return USBStatus.bufferError.rawValue
        default:
            return USBStatus.requestFailed.rawValue
        }
    }
    
    /// Maps USB status codes to IOKit errors for consistency
    public static func mapUSBStatusToIOKit(_ usbStatus: Int32) -> IOReturn {
        switch USBStatus(rawValue: usbStatus) {
        case .success:
            return kIOReturnSuccess
        case .timeout:
            return kIOReturnTimeout
        case .cancelled:
            return kIOReturnAborted
        case .stall:
            return kIOReturnError
        case .deviceGone, .noDevice:
            return kIOReturnNoDevice
        case .memoryError:
            return kIOReturnNoMemory
        case .invalidRequest:
            return kIOReturnBadArgument
        case .shortPacket:
            return kIOReturnUnderrun
        case .bufferError:
            return kIOReturnOverrun
        default:
            return kIOReturnError
        }
    }
    
    /// Creates a localized error description for USB status codes
    public static func errorDescription(for status: Int32) -> String {
        switch USBStatus(rawValue: status) {
        case .success:
            return "Operation completed successfully"
        case .stall:
            return "USB endpoint stalled"
        case .timeout:
            return "USB transfer timed out"
        case .cancelled:
            return "USB transfer was cancelled"
        case .shortPacket:
            return "Short packet received"
        case .deviceGone, .noDevice:
            return "USB device disconnected or not present"
        case .requestFailed:
            return "USB request failed"
        case .protocolError:
            return "USB protocol error"
        case .memoryError:
            return "Memory allocation error"
        case .invalidRequest:
            return "Invalid USB request"
        case .busError:
            return "USB bus error"
        case .bufferError:
            return "USB buffer error"
        default:
            return "Unknown USB error (code: \(status))"
        }
    }
}

/// USB-specific errors for request processing
public enum USBRequestError: Error {
    case invalidURB(String)
    case deviceNotClaimed(String)
    case endpointNotFound(UInt8)
    case transferTypeNotSupported(USBTransferType)
    case bufferSizeMismatch(expected: UInt32, actual: UInt32)
    case setupPacketRequired
    case setupPacketInvalid
    case timeoutInvalid(UInt32)
    case concurrentRequestLimit
    case requestCancelled(UInt32)
    case timeout
    case deviceNotAvailable
    case invalidParameters
    case tooManyRequests
    case duplicateRequest
    case cancelled
    case requestFailed
}

extension USBRequestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURB(let message):
            return "Invalid USB Request Block: \(message)"
        case .deviceNotClaimed(let busID):
            return "Device not claimed for USB operations: \(busID)"
        case .endpointNotFound(let endpoint):
            return "USB endpoint not found: 0x\(String(endpoint, radix: 16))"
        case .transferTypeNotSupported(let type):
            return "USB transfer type not supported: \(type)"
        case .bufferSizeMismatch(let expected, let actual):
            return "Buffer size mismatch - expected: \(expected), actual: \(actual)"
        case .setupPacketRequired:
            return "Setup packet required for control transfers"
        case .setupPacketInvalid:
            return "Invalid setup packet format"
        case .timeoutInvalid(let timeout):
            return "Invalid timeout value: \(timeout)ms"
        case .concurrentRequestLimit:
            return "Concurrent request limit exceeded"
        case .requestCancelled(let seqnum):
            return "USB request cancelled: \(seqnum)"
        case .timeout:
            return "USB transfer timed out"
        case .deviceNotAvailable:
            return "USB device not available"
        case .invalidParameters:
            return "Invalid USB request parameters"
        case .tooManyRequests:
            return "Too many concurrent USB requests"
        case .duplicateRequest:
            return "Duplicate USB request sequence number"
        case .cancelled:
            return "USB request was cancelled"
        case .requestFailed:
            return "USB request failed"
        }
    }
}

/// URB lifecycle tracking for concurrent request management
public class URBTracker {
    private var pendingURBs: [UInt32: USBRequestBlock] = [:]
    private let queue = DispatchQueue(label: "com.usbipd.urb-tracker", attributes: .concurrent)
    
    public init() {}
    
    /// Add a pending URB for tracking
    public func addPendingURB(_ urb: USBRequestBlock) {
        queue.async(flags: .barrier) {
            self.pendingURBs[urb.seqnum] = urb
        }
    }
    
    /// Remove a completed URB from tracking
    public func removeCompletedURB(_ seqnum: UInt32) -> USBRequestBlock? {
        return queue.sync(flags: .barrier) {
            return self.pendingURBs.removeValue(forKey: seqnum)
        }
    }
    
    /// Get a pending URB by sequence number
    public func getPendingURB(_ seqnum: UInt32) -> USBRequestBlock? {
        return queue.sync {
            return self.pendingURBs[seqnum]
        }
    }
    
    /// Get all pending URB sequence numbers
    public func getAllPendingSeqnums() -> [UInt32] {
        return queue.sync {
            return Array(self.pendingURBs.keys)
        }
    }
    
    /// Get count of pending URBs
    public var pendingCount: Int {
        return queue.sync {
            return self.pendingURBs.count
        }
    }
    
    /// Clear all pending URBs (used during cleanup/reset)
    public func clearAllPendingURBs() -> [USBRequestBlock] {
        return queue.sync(flags: .barrier) {
            let pending = Array(self.pendingURBs.values)
            self.pendingURBs.removeAll()
            return pending
        }
    }
}