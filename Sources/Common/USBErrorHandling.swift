// USBErrorHandling.swift
// Comprehensive USB error handling utilities for USB/IP protocol implementation

import Foundation
import IOKit
import IOKit.usb

/// Comprehensive USB error types for the USB/IP implementation
public enum USBError: Error {
    // Protocol-level errors
    case invalidUSBIPMessage(String)
    case malformedSubmitRequest(String)
    case malformedUnlinkRequest(String)
    case invalidDeviceID(UInt32)
    case invalidSequenceNumber(UInt32)
    case unsupportedTransferType(UInt8)
    
    // Device access errors
    case deviceNotClaimed(String)
    case deviceNotFound(String)
    case deviceDisconnected(String)
    case systemExtensionError(String)
    case deviceBusy(String)
    
    // USB transfer errors
    case endpointError(UInt8, String)
    case transferTimeout(UInt32)
    case transferCancelled(UInt32)
    case transferStalled(UInt8)
    case bufferError(String)
    case setupPacketError(String)
    
    // Resource management errors
    case memoryAllocationFailed
    case tooManyPendingRequests(current: Int, maximum: Int)
    case requestTrackingFailed(UInt32)
    case concurrencyLimitExceeded
    
    // IOKit integration errors
    case ioKitInterfaceError(IOReturn, String)
    case ioKitPermissionDenied(String)
    case ioKitResourceUnavailable(String)
    case ioKitDeviceRemoval(String)
}

extension USBError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        // Protocol-level errors
        case .invalidUSBIPMessage(let details):
            return "Invalid USB/IP message: \(details)"
        case .malformedSubmitRequest(let details):
            return "Malformed USBIP_CMD_SUBMIT request: \(details)"
        case .malformedUnlinkRequest(let details):
            return "Malformed USBIP_CMD_UNLINK request: \(details)"
        case .invalidDeviceID(let devid):
            return "Invalid device ID: \(devid)"
        case .invalidSequenceNumber(let seqnum):
            return "Invalid sequence number: \(seqnum)"
        case .unsupportedTransferType(let type):
            return "Unsupported USB transfer type: \(type)"
            
        // Device access errors
        case .deviceNotClaimed(let busID):
            return "Device not claimed for USB operations: \(busID)"
        case .deviceNotFound(let identifier):
            return "USB device not found: \(identifier)"
        case .deviceDisconnected(let identifier):
            return "USB device disconnected: \(identifier)"
        case .systemExtensionError(let message):
            return "System Extension error: \(message)"
        case .deviceBusy(let identifier):
            return "USB device busy: \(identifier)"
            
        // USB transfer errors
        case .endpointError(let endpoint, let message):
            return "USB endpoint 0x\(String(endpoint, radix: 16)) error: \(message)"
        case .transferTimeout(let timeout):
            return "USB transfer timeout after \(timeout)ms"
        case .transferCancelled(let seqnum):
            return "USB transfer cancelled (seqnum: \(seqnum))"
        case .transferStalled(let endpoint):
            return "USB endpoint 0x\(String(endpoint, radix: 16)) stalled"
        case .bufferError(let message):
            return "USB buffer error: \(message)"
        case .setupPacketError(let message):
            return "USB setup packet error: \(message)"
            
        // Resource management errors
        case .memoryAllocationFailed:
            return "Memory allocation failed for USB operation"
        case .tooManyPendingRequests(let current, let maximum):
            return "Too many pending USB requests: \(current)/\(maximum)"
        case .requestTrackingFailed(let seqnum):
            return "USB request tracking failed for seqnum: \(seqnum)"
        case .concurrencyLimitExceeded:
            return "Concurrent USB request limit exceeded"
            
        // IOKit integration errors
        case .ioKitInterfaceError(let error, let message):
            return "IOKit interface error (0x\(String(error, radix: 16))): \(message)"
        case .ioKitPermissionDenied(let message):
            return "IOKit permission denied: \(message)"
        case .ioKitResourceUnavailable(let message):
            return "IOKit resource unavailable: \(message)"
        case .ioKitDeviceRemoval(let message):
            return "IOKit device removal: \(message)"
        }
    }
}

/// Extended USB status codes for USB/IP protocol responses
public enum USBIPStatus: Int32 {
    // Success
    case success = 0
    
    // Linux USB error codes (matching kernel definitions)
    case eperm = -1         // Operation not permitted
    case enoent = -2        // No such file or directory
    case esrch = -3         // No such process
    case eintr = -4         // Interrupted system call
    case eio = -5           // I/O error
    case enxio = -6         // No such device or address
    case e2big = -7         // Argument list too long
    case enoexec = -8       // Exec format error
    case ebadf = -9         // Bad file number
    case echild = -10       // No child processes
    case eagain = -11       // Try again
    case enomem = -12       // Out of memory
    case eacces = -13       // Permission denied
    case efault = -14       // Bad address
    case enotblk = -15      // Block device required
    case ebusy = -16        // Device or resource busy
    case eexist = -17       // File exists
    case exdev = -18        // Cross-device link
    case enodev = -19       // No such device
    case enotdir = -20      // Not a directory
    case eisdir = -21       // Is a directory
    case einval = -22       // Invalid argument
    case enfile = -23       // File table overflow
    case emfile = -24       // Too many open files
    case enotty = -25       // Not a typewriter
    case etxtbsy = -26      // Text file busy
    case efbig = -27        // File too large
    case enospc = -28       // No space left on device
    case espipe = -29       // Illegal seek
    case erofs = -30        // Read-only file system
    case emlink = -31       // Too many links
    case epipe = -32        // Broken pipe
    
    // USB-specific error codes
    case eshutdown = -108   // Cannot send after transport endpoint shutdown
    case econnaborted = -103 // Software caused connection abort
    case eproto = -71       // Protocol error
    case eilseq = -84       // Illegal byte sequence
    case etimeout = -110    // Connection timed out
    case econnreset = -104  // Connection reset by peer
    case enolink = -67      // Link has been severed
    case eremoteio = -121   // Remote I/O error
    case ecanceled = -125   // Operation Cancelled
    case enosr = -63        // Out of streams resources
}

/// USB/IP protocol error handling utilities
public struct USBIPErrorHandling {
    
    /// Map common errors to USB/IP status codes for protocol responses
    public static func mapErrorToUSBIPStatus(_ error: Error) -> Int32 {
        switch error {
        case let usbError as USBError:
            return mapUSBErrorToStatus(usbError)
        case let deviceError as DeviceError:
            return mapDeviceErrorToStatus(deviceError)
        default:
            return USBIPStatus.eio.rawValue
        }
    }
    
    private static func mapUSBErrorToStatus(_ error: USBError) -> Int32 {
        switch error {
        case .invalidUSBIPMessage, .malformedSubmitRequest, .malformedUnlinkRequest:
            return USBIPStatus.einval.rawValue
        case .invalidDeviceID, .invalidSequenceNumber, .unsupportedTransferType:
            return USBIPStatus.einval.rawValue
        case .deviceNotClaimed, .deviceNotFound:
            return USBIPStatus.enodev.rawValue
        case .deviceDisconnected:
            return USBIPStatus.enodev.rawValue
        case .systemExtensionError, .ioKitPermissionDenied:
            return USBIPStatus.eacces.rawValue
        case .deviceBusy:
            return USBIPStatus.ebusy.rawValue
        case .endpointError, .transferStalled:
            return USBIPStatus.epipe.rawValue
        case .transferTimeout:
            return USBIPStatus.etimeout.rawValue
        case .transferCancelled:
            return USBIPStatus.ecanceled.rawValue
        case .bufferError, .setupPacketError:
            return USBIPStatus.einval.rawValue
        case .memoryAllocationFailed:
            return USBIPStatus.enomem.rawValue
        case .tooManyPendingRequests, .concurrencyLimitExceeded:
            return USBIPStatus.eagain.rawValue
        case .requestTrackingFailed:
            return USBIPStatus.eio.rawValue
        case .ioKitInterfaceError(let ioReturn, _):
            return mapIOReturnToUSBIPStatus(ioReturn)
        case .ioKitResourceUnavailable:
            return USBIPStatus.ebusy.rawValue
        case .ioKitDeviceRemoval:
            return USBIPStatus.enodev.rawValue
        }
    }
    
    private static func mapDeviceErrorToStatus(_ error: DeviceError) -> Int32 {
        switch error {
        case .deviceNotFound:
            return USBIPStatus.enodev.rawValue
        case .accessDenied:
            return USBIPStatus.eacces.rawValue
        case .ioKitError(let code, _):
            return mapIOReturnToUSBIPStatus(code)
        }
    }
    
    
    /// Map IOKit return codes to USB/IP status codes
    public static func mapIOReturnToUSBIPStatus(_ ioReturn: IOReturn) -> Int32 {
        switch ioReturn {
        case kIOReturnSuccess:
            return USBIPStatus.success.rawValue
        case kIOReturnTimeout:
            return USBIPStatus.etimeout.rawValue
        case kIOReturnAborted:
            return USBIPStatus.ecanceled.rawValue
        // Note: USB-specific IOKit errors are not available in this SDK version
        // case kIOUSBPipeStalled:
        //     return USBIPStatus.epipe.rawValue
        case kIOReturnNoDevice, kIOReturnNotResponding:
            return USBIPStatus.enodev.rawValue
        case kIOReturnNoMemory:
            return USBIPStatus.enomem.rawValue
        case kIOReturnBadArgument:
            return USBIPStatus.einval.rawValue
        case kIOReturnNotPermitted:
            return USBIPStatus.eacces.rawValue
        case kIOReturnBusy:
            return USBIPStatus.ebusy.rawValue
        // Note: USB-specific IOKit errors are not available in this SDK version
        // case kIOUSBUnderrun:
        //     return USBIPStatus.eremoteio.rawValue
        // case kIOUSBBufferUnderrun, kIOUSBBufferOverrun:
        //     return USBIPStatus.eio.rawValue
        default:
            return USBIPStatus.eio.rawValue
        }
    }
    
    /// Create user-friendly error messages for debugging and logging
    public static func createDiagnosticMessage(for error: Error, context: String) -> String {
        let errorDescription = error.localizedDescription
        let errorType = String(describing: type(of: error))
        
        return """
        USB Operation Error in \(context):
        Type: \(errorType)
        Description: \(errorDescription)
        """
    }
    
    /// Validate USB/IP protocol message parameters
    public static func validateUSBIPMessage(
        deviceID: UInt32,
        endpoint: UInt8,
        transferType: UInt8,
        bufferLength: UInt32,
        maxBufferSize: UInt32 = 1048576 // 1MB default limit
    ) throws {
        // Validate device ID (should be non-zero for valid devices)
        if deviceID == 0 {
            throw USBError.invalidDeviceID(deviceID)
        }
        
        // Validate endpoint address (0-15 with direction bit)
        if endpoint & 0x0F > 15 {
            throw USBError.endpointError(endpoint, "Invalid endpoint number")
        }
        
        // Validate transfer type
        if transferType > 3 {
            throw USBError.unsupportedTransferType(transferType)
        }
        
        // Validate buffer size limits
        if bufferLength > maxBufferSize {
            throw USBError.bufferError("Buffer size \(bufferLength) exceeds maximum \(maxBufferSize)")
        }
    }
    
    /// Validate control transfer setup packet
    public static func validateSetupPacket(_ setupData: Data?) throws {
        guard let setup = setupData else {
            throw USBError.setupPacketError("Setup packet required for control transfers")
        }
        
        if setup.count != 8 {
            throw USBError.setupPacketError("Setup packet must be exactly 8 bytes, got \(setup.count)")
        }
        
        // Basic validation of setup packet structure
        let bmRequestType = setup[0]
        
        // Check for reserved bits in bmRequestType
        if (bmRequestType & 0x60) == 0x60 {
            throw USBError.setupPacketError("Invalid bmRequestType: reserved bits set")
        }
    }
    
    /// Check if an error is recoverable (should retry) or fatal (abort operation)
    public static func isRecoverableError(_ error: Error) -> Bool {
        switch error {
        case let usbError as USBError:
            switch usbError {
            case .transferTimeout, .deviceBusy, .tooManyPendingRequests, 
                 .concurrencyLimitExceeded, .ioKitResourceUnavailable:
                return true
            case .deviceNotFound, .deviceDisconnected, .systemExtensionError,
                 .ioKitPermissionDenied, .ioKitDeviceRemoval:
                return false
            default:
                return false
            }
        case let deviceError as DeviceError:
            switch deviceError {
            case .deviceNotFound, .accessDenied:
                return false
            case .ioKitError(let code, _):
                return code == kIOReturnBusy || code == kIOReturnTimeout
            }
        default:
            return false
        }
    }
    
    /// Get retry delay for recoverable errors (in seconds)
    public static func getRetryDelay(for error: Error, attempt: Int) -> TimeInterval {
        let baseDelay: TimeInterval = 0.1
        let maxDelay: TimeInterval = 5.0
        
        switch error {
        case let usbError as USBError:
            switch usbError {
            case .transferTimeout:
                return min(baseDelay * pow(2.0, Double(attempt)), maxDelay)
            case .deviceBusy, .tooManyPendingRequests:
                return min(baseDelay * 2.0 * Double(attempt + 1), maxDelay)
            default:
                return baseDelay
            }
        default:
            return baseDelay
        }
    }
}

/// USB operation result wrapper for consistent error handling
public enum USBOperationResult<T> {
    case success(T)
    case failure(USBError)
    case cancelled
    
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    
    public var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
    
    public var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
    
    public func getValue() throws -> T {
        switch self {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .cancelled:
            throw USBError.transferCancelled(0)
        }
    }
}