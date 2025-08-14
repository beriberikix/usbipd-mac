// IOKitErrorMapping.swift
// Comprehensive IOKit error mapping utilities for USB device operations

import Foundation
import IOKit
import IOKit.usb
import Common

/// Comprehensive IOKit error mapping utilities for USB device operations
public struct IOKitErrorMapping {
    
    // MARK: - Error Context
    
    /// Contextual information about where an IOKit error occurred
    public struct ErrorContext {
        public let operation: String
        public let deviceID: String?
        public let endpoint: UInt8?
        public let additionalInfo: [String: String]
        
        public init(
            operation: String,
            deviceID: String? = nil,
            endpoint: UInt8? = nil,
            additionalInfo: [String: String] = [:]
        ) {
            self.operation = operation
            self.deviceID = deviceID
            self.endpoint = endpoint
            self.additionalInfo = additionalInfo
        }
    }
    
    /// Recovery suggestion for handling specific IOKit errors
    public struct RecoverySuggestion {
        public let isRecoverable: Bool
        public let retryDelay: TimeInterval?
        public let maxRetries: Int
        public let userAction: String?
        public let systemAction: String?
        
        public init(
            isRecoverable: Bool,
            retryDelay: TimeInterval? = nil,
            maxRetries: Int = 0,
            userAction: String? = nil,
            systemAction: String? = nil
        ) {
            self.isRecoverable = isRecoverable
            self.retryDelay = retryDelay
            self.maxRetries = maxRetries
            self.userAction = userAction
            self.systemAction = systemAction
        }
    }
    
    // MARK: - IOKit Error Mapping
    
    /// Maps IOKit return codes to USBRequestError types with detailed context
    /// - Parameters:
    ///   - ioReturn: IOKit return code from USB operation
    ///   - context: Context information about the operation
    /// - Returns: Mapped USBRequestError with appropriate type and message
    public static func mapIOKitError(_ ioReturn: IOReturn, context: ErrorContext) -> USBRequestError {
        // Note: Detailed error message is available via createDetailedErrorMessage() for logging
        
        switch ioReturn {
        case kIOReturnSuccess:
            // This should not happen, but handle gracefully
            return .requestFailed
            
        // Device availability errors
        case kIOReturnNoDevice:
            return .deviceNotAvailable
            
        case kIOReturnNotResponding:
            return .deviceNotAvailable
            
        case kIOReturnNotAttached:
            return .deviceNotAvailable
            
        case kIOReturnNotOpen:
            return .deviceNotClaimed(context.deviceID ?? "unknown")
            
        // Permission and access errors
        case kIOReturnNotPermitted:
            return .deviceNotClaimed(context.deviceID ?? "unknown")
            
        case kIOReturnNotPrivileged:
            return .deviceNotClaimed(context.deviceID ?? "unknown")
            
        case kIOReturnExclusiveAccess:
            return .deviceNotClaimed(context.deviceID ?? "unknown")
            
        // Resource and memory errors
        case kIOReturnNoMemory:
            return .tooManyRequests
            
        case kIOReturnNoResources:
            return .tooManyRequests
            
        case kIOReturnBusy:
            return .tooManyRequests
            
        // Parameter validation errors
        case kIOReturnBadArgument:
            return .invalidParameters
            
        case kIOReturnUnsupported:
            if let endpoint = context.endpoint {
                return .endpointNotFound(endpoint)
            }
            return .invalidParameters
            
        // Transfer-specific errors
        case kIOReturnTimeout:
            return .timeout
            
        case kIOReturnAborted:
            return .cancelled
            
        case kIOReturnUnderrun:
            return .requestFailed
            
        case kIOReturnOverrun:
            return .requestFailed
            
        // USB-specific IOKit errors (when available)
        // Note: Some USB-specific constants may not be available in all SDK versions
        case kIOReturnStillOpen:
            return .deviceNotClaimed(context.deviceID ?? "unknown")
            
        case kIOReturnCannotWire:
            return .tooManyRequests
            
        case kIOReturnCannotLock:
            return .tooManyRequests
            
        // Generic errors
        case kIOReturnError:
            return .requestFailed
            
        case kIOReturnInternalError:
            return .requestFailed
            
        case kIOReturnIOError:
            return .requestFailed
            
        default:
            return .requestFailed
        }
    }
    
    /// Creates a detailed error message with context information
    /// - Parameters:
    ///   - ioReturn: IOKit return code
    ///   - context: Error context information
    /// - Returns: Detailed error message string
    public static func createDetailedErrorMessage(ioReturn: IOReturn, context: ErrorContext) -> String {
        let baseMessage = getIOKitErrorDescription(ioReturn)
        var contextParts: [String] = []
        
        contextParts.append("Operation: \(context.operation)")
        
        if let deviceID = context.deviceID {
            contextParts.append("Device: \(deviceID)")
        }
        
        if let endpoint = context.endpoint {
            contextParts.append("Endpoint: 0x\(String(endpoint, radix: 16))")
        }
        
        for (key, value) in context.additionalInfo {
            contextParts.append("\(key): \(value)")
        }
        
        let contextString = contextParts.joined(separator: ", ")
        
        return "\(baseMessage) (\(contextString)) [IOKit: 0x\(String(ioReturn, radix: 16))]"
    }
    
    /// Gets a human-readable description for IOKit error codes
    /// - Parameter ioReturn: IOKit return code
    /// - Returns: Human-readable error description
    public static func getIOKitErrorDescription(_ ioReturn: IOReturn) -> String {
        switch ioReturn {
        case kIOReturnSuccess:
            return "Operation completed successfully"
        case kIOReturnError:
            return "General I/O error"
        case kIOReturnNoMemory:
            return "Cannot allocate memory"
        case kIOReturnNoResources:
            return "Resource shortage"
        case kIOReturnIPCError:
            return "Error during IPC"
        case kIOReturnNoDevice:
            return "No such device"
        case kIOReturnNotPrivileged:
            return "Privilege violation"
        case kIOReturnBadArgument:
            return "Invalid argument"
        case kIOReturnLockedRead:
            return "Device read locked"
        case kIOReturnLockedWrite:
            return "Device write locked"
        case kIOReturnExclusiveAccess:
            return "Exclusive access and device already open"
        case kIOReturnBadMessageID:
            return "Sent/received messages had different msg_id"
        case kIOReturnUnsupported:
            return "Unsupported function"
        case kIOReturnVMError:
            return "Misc. VM failure"
        case kIOReturnInternalError:
            return "Internal error"
        case kIOReturnIOError:
            return "General I/O error"
        case kIOReturnCannotLock:
            return "Can't acquire lock"
        case kIOReturnNotOpen:
            return "Device not open"
        case kIOReturnNotReadable:
            return "Read not supported"
        case kIOReturnNotWritable:
            return "Write not supported"
        case kIOReturnNotAligned:
            return "Alignment error"
        case kIOReturnBadMedia:
            return "Media error"
        case kIOReturnStillOpen:
            return "Device(s) still open"
        case kIOReturnRLDError:
            return "RLD failure"
        case kIOReturnDMAError:
            return "DMA failure"
        case kIOReturnBusy:
            return "Device busy"
        case kIOReturnTimeout:
            return "I/O timeout"
        case kIOReturnOffline:
            return "Device offline"
        case kIOReturnNotReady:
            return "Not ready"
        case kIOReturnNotAttached:
            return "Device not attached"
        case kIOReturnNoChannels:
            return "No DMA channels left"
        case kIOReturnNoSpace:
            return "No space for data"
        case kIOReturnPortExists:
            return "Port already exists"
        case kIOReturnCannotWire:
            return "Can't wire down physical memory"
        case kIOReturnNoInterrupt:
            return "No interrupt attached"
        case kIOReturnNoFrames:
            return "No DMA frames enqueued"
        case kIOReturnMessageTooLarge:
            return "Oversized msg received on interrupt port"
        case kIOReturnNotPermitted:
            return "Not permitted"
        case kIOReturnNoPower:
            return "No power to device"
        case kIOReturnNoMedia:
            return "Media not present"
        case kIOReturnUnformattedMedia:
            return "Media not formatted"
        case kIOReturnUnsupportedMode:
            return "No such mode"
        case kIOReturnUnderrun:
            return "Data underrun"
        case kIOReturnOverrun:
            return "Data overrun"
        case kIOReturnDeviceError:
            return "Device error"
        case kIOReturnNoCompletion:
            return "A completion routine is required"
        case kIOReturnAborted:
            return "Operation aborted"
        case kIOReturnNoBandwidth:
            return "Bus bandwidth would be exceeded"
        case kIOReturnNotResponding:
            return "Device not responding"
        case kIOReturnIsoTooOld:
            return "Isochronous I/O request for distant past"
        case kIOReturnIsoTooNew:
            return "Isochronous I/O request for distant future"
        case kIOReturnNotFound:
            return "Data was not found"
        default:
            return "Unknown IOKit error"
        }
    }
    
    // MARK: - Recovery Suggestions
    
    /// Provides recovery suggestions for specific IOKit errors
    /// - Parameters:
    ///   - ioReturn: IOKit return code
    ///   - context: Error context information
    /// - Returns: Recovery suggestion with retry and user action guidance
    public static func getRecoverySuggestion(for ioReturn: IOReturn, context: ErrorContext) -> RecoverySuggestion {
        switch ioReturn {
        // Recoverable errors with retry
        case kIOReturnTimeout:
            return RecoverySuggestion(
                isRecoverable: true,
                retryDelay: 0.1,
                maxRetries: 3,
                userAction: nil,
                systemAction: "Retry operation with exponential backoff"
            )
            
        case kIOReturnBusy:
            return RecoverySuggestion(
                isRecoverable: true,
                retryDelay: 0.2,
                maxRetries: 5,
                userAction: nil,
                systemAction: "Wait for device to become available and retry"
            )
            
        case kIOReturnNoResources, kIOReturnNoMemory:
            return RecoverySuggestion(
                isRecoverable: true,
                retryDelay: 0.5,
                maxRetries: 3,
                userAction: nil,
                systemAction: "Wait for system resources to become available"
            )
            
        case kIOReturnCannotWire, kIOReturnCannotLock:
            return RecoverySuggestion(
                isRecoverable: true,
                retryDelay: 0.3,
                maxRetries: 2,
                userAction: nil,
                systemAction: "Retry memory operation"
            )
            
        // Device-related errors requiring user action
        case kIOReturnNoDevice, kIOReturnNotAttached, kIOReturnNotResponding:
            return RecoverySuggestion(
                isRecoverable: false,
                userAction: "Check device connection and ensure device is properly connected",
                systemAction: "Refresh device discovery"
            )
            
        case kIOReturnNotPermitted, kIOReturnNotPrivileged, kIOReturnExclusiveAccess:
            return RecoverySuggestion(
                isRecoverable: false,
                userAction: "Ensure System Extension is running and device is properly bound using 'usbipd bind' command",
                systemAction: "Verify System Extension status and device claim state"
            )
            
        case kIOReturnNotOpen:
            return RecoverySuggestion(
                isRecoverable: false,
                userAction: "Device must be bound for USB/IP sharing using 'usbipd bind' command",
                systemAction: "Check device claim status and re-establish device interface"
            )
            
        // Parameter errors requiring code fix
        case kIOReturnBadArgument, kIOReturnUnsupported:
            return RecoverySuggestion(
                isRecoverable: false,
                userAction: nil,
                systemAction: "Validate request parameters and endpoint configuration"
            )
            
        // Cancellation and abort - not errors
        case kIOReturnAborted:
            return RecoverySuggestion(
                isRecoverable: false,
                userAction: nil,
                systemAction: "Operation was cancelled by user or system"
            )
            
        // Unrecoverable device errors
        case kIOReturnDeviceError, kIOReturnBadMedia, kIOReturnIOError:
            return RecoverySuggestion(
                isRecoverable: false,
                userAction: "Check device functionality and try reconnecting device",
                systemAction: "Log device error for diagnostics"
            )
            
        default:
            return RecoverySuggestion(
                isRecoverable: false,
                userAction: "Try reconnecting the device or restarting the USB/IP service",
                systemAction: "Log unknown error for investigation"
            )
        }
    }
    
    // MARK: - Utility Functions
    
    /// Determines if an IOKit error indicates the operation should be retried
    /// - Parameter ioReturn: IOKit return code
    /// - Returns: True if the error is transient and retry may succeed
    public static func isRetryableError(_ ioReturn: IOReturn) -> Bool {
        switch ioReturn {
        case kIOReturnTimeout, kIOReturnBusy, kIOReturnNoResources, 
             kIOReturnNoMemory, kIOReturnCannotWire, kIOReturnCannotLock:
            return true
        default:
            return false
        }
    }
    
    /// Gets the recommended retry delay for specific IOKit errors
    /// - Parameters:
    ///   - ioReturn: IOKit return code
    ///   - attemptNumber: Current retry attempt (1-based)
    /// - Returns: Recommended delay in seconds before retry
    public static func getRetryDelay(for ioReturn: IOReturn, attemptNumber: Int) -> TimeInterval {
        let baseDelay: TimeInterval
        let maxDelay: TimeInterval = 5.0
        
        switch ioReturn {
        case kIOReturnTimeout:
            baseDelay = 0.1
        case kIOReturnBusy:
            baseDelay = 0.2
        case kIOReturnNoResources, kIOReturnNoMemory:
            baseDelay = 0.5
        default:
            baseDelay = 0.3
        }
        
        // Exponential backoff with jitter
        let exponentialDelay = baseDelay * pow(2.0, Double(attemptNumber - 1))
        let jitter = Double.random(in: 0.8...1.2)
        
        return min(exponentialDelay * jitter, maxDelay)
    }
    
    /// Creates a comprehensive error report for logging and diagnostics
    /// - Parameters:
    ///   - ioReturn: IOKit return code
    ///   - context: Error context information
    /// - Returns: Detailed error report for logging
    public static func createErrorReport(ioReturn: IOReturn, context: ErrorContext) -> String {
        let errorDescription = getIOKitErrorDescription(ioReturn)
        let recoverySuggestion = getRecoverySuggestion(for: ioReturn, context: context)
        let isRetryable = isRetryableError(ioReturn)
        
        var report = """
        IOKit Error Report
        ==================
        Error Code: 0x\(String(ioReturn, radix: 16)) (\(ioReturn))
        Description: \(errorDescription)
        Operation: \(context.operation)
        """
        
        if let deviceID = context.deviceID {
            report += "\nDevice ID: \(deviceID)"
        }
        
        if let endpoint = context.endpoint {
            report += "\nEndpoint: 0x\(String(endpoint, radix: 16))"
        }
        
        if !context.additionalInfo.isEmpty {
            report += "\nAdditional Info:"
            for (key, value) in context.additionalInfo {
                report += "\n  \(key): \(value)"
            }
        }
        
        report += "\nRecoverable: \(isRetryable ? "Yes" : "No")"
        
        if recoverySuggestion.isRecoverable {
            report += "\nMax Retries: \(recoverySuggestion.maxRetries)"
            if let delay = recoverySuggestion.retryDelay {
                report += "\nRetry Delay: \(delay)s"
            }
        }
        
        if let userAction = recoverySuggestion.userAction {
            report += "\nUser Action: \(userAction)"
        }
        
        if let systemAction = recoverySuggestion.systemAction {
            report += "\nSystem Action: \(systemAction)"
        }
        
        return report
    }
}

// MARK: - Convenience Extensions

extension USBRequestError {
    /// Creates a USBRequestError from IOKit error with context
    /// - Parameters:
    ///   - ioReturn: IOKit return code
    ///   - operation: Operation that failed
    ///   - deviceID: Optional device identifier
    ///   - endpoint: Optional endpoint address
    /// - Returns: Mapped USBRequestError
    public static func fromIOKitError(
        _ ioReturn: IOReturn,
        operation: String,
        deviceID: String? = nil,
        endpoint: UInt8? = nil
    ) -> USBRequestError {
        let context = IOKitErrorMapping.ErrorContext(
            operation: operation,
            deviceID: deviceID,
            endpoint: endpoint
        )
        return IOKitErrorMapping.mapIOKitError(ioReturn, context: context)
    }
}