//
//  IOKitErrorHandling.swift
//  usbipd-mac
//
//  IOKit error handling utilities for device discovery
//

import Foundation
import IOKit
import IOKit.usb
import Common

// MARK: - IOKit Error Handling Extensions

extension IOKitDeviceDiscovery {
    
    // MARK: - Error Recovery and Retry Logic
    
    /// Determines if an IOKit error is transient and should be retried
    internal func isTransientIOKitError(_ result: kern_return_t) -> Bool {
        let unsignedResult = UInt32(bitPattern: result)
        switch result {
        case KERN_RESOURCE_SHORTAGE, KERN_NO_SPACE, KERN_MEMORY_FAILURE:
            return true
        case KERN_OPERATION_TIMED_OUT:
            return true
        default:
            // Check IOKit-specific transient errors
            switch unsignedResult {
            case 0xe00002bd: // kIOReturnNoMemory
                return true
            case 0xe00002be: // kIOReturnNoResources
                return true
            case 0xe00002d4: // kIOReturnBusy
                return true
            case 0xe00002d5: // kIOReturnTimeout
                return true
            case 0xe00002d7: // kIOReturnNotReady
                return true
            case 0xe00002eb: // kIOReturnNotResponding
                return true
            default:
                return false
            }
        }
    }
    
    /// Execute an IOKit operation with retry logic for transient failures
    internal func executeWithRetry<T>(
        operation: String,
        config: RetryConfiguration = .default,
        block: () throws -> T
    ) throws -> T {
        var lastError: Error?
        var delay = config.baseDelay
        
        for attempt in 0...config.maxRetries {
            do {
                if attempt > 0 {
                    logger.debug("Retrying IOKit operation", context: [
                        "operation": operation,
                        "attempt": attempt + 1,
                        "maxRetries": config.maxRetries + 1,
                        "delay": delay
                    ])
                    
                    // Sleep before retry (except for first attempt)
                    Thread.sleep(forTimeInterval: delay)
                    
                    // Exponential backoff with jitter
                    delay = min(delay * config.backoffMultiplier + Double.random(in: 0...0.1), config.maxDelay)
                }
                
                let result = try block()
                
                if attempt > 0 {
                    logger.info("IOKit operation succeeded after retry", context: [
                        "operation": operation,
                        "successfulAttempt": attempt + 1,
                        "totalAttempts": attempt + 1
                    ])
                }
                
                return result
                
            } catch let error as DeviceDiscoveryError {
                lastError = error
                
                // Check if this is a transient error that should be retried
                if case .ioKitError(let code, _) = error, isTransientIOKitError(code) {
                    if attempt < config.maxRetries {
                        logger.warning("Transient IOKit error, will retry", context: [
                            "operation": operation,
                            "attempt": attempt + 1,
                            "error": error.localizedDescription,
                            "nextRetryDelay": delay,
                            "remainingRetries": config.maxRetries - attempt
                        ])
                        continue
                    } else {
                        logger.error("IOKit operation failed after all retries", context: [
                            "operation": operation,
                            "totalAttempts": attempt + 1,
                            "finalError": error.localizedDescription
                        ])
                        throw error
                    }
                } else {
                    // Non-transient error, don't retry
                    logger.debug("Non-transient error, not retrying", context: [
                        "operation": operation,
                        "error": error.localizedDescription,
                        "attempt": attempt + 1
                    ])
                    throw error
                }
            } catch {
                lastError = error
                logger.error("Unexpected error during IOKit operation", context: [
                    "operation": operation,
                    "attempt": attempt + 1,
                    "error": error.localizedDescription
                ])
                throw error
            }
        }
        
        // This should never be reached, but provide a fallback
        throw lastError ?? DeviceDiscoveryError.ioKitError(-1, "Unknown error after retries")
    }
    
    // MARK: - IOKit Error Handling Utilities
    
    /// Convert IOKit error codes to DeviceDiscoveryError with detailed logging
    /// Provides comprehensive error mapping and logging for IOKit operations
    internal func handleIOKitError(_ result: kern_return_t, operation: String, context: [String: Any] = [:]) -> DeviceDiscoveryError {
        let errorDescription = getIOKitErrorDescription(result)
        let errorMessage = "IOKit operation '\(operation)' failed: \(errorDescription)"
        
        var logContext = context
        logContext["kern_return"] = result
        logContext["operation"] = operation
        logContext["error_description"] = errorDescription
        logContext["error_category"] = getIOKitErrorCategory(result)
        
        logger.error(errorMessage, context: logContext)
        return DeviceDiscoveryError.ioKitError(result, errorMessage)
    }
    
    /// Get human-readable description for IOKit error codes
    /// Maps common IOKit error codes to descriptive messages
    internal func getIOKitErrorDescription(_ result: kern_return_t) -> String {
        switch result {
        case KERN_SUCCESS:
            return "Success"
        case KERN_INVALID_ARGUMENT:
            return "Invalid argument provided to IOKit function"
        case KERN_FAILURE:
            return "General IOKit failure"
        case KERN_RESOURCE_SHORTAGE:
            return "Insufficient system resources"
        case KERN_NO_SPACE:
            return "No space available"
        case KERN_INVALID_ADDRESS:
            return "Invalid memory address"
        case KERN_PROTECTION_FAILURE:
            return "Memory protection violation"
        case KERN_NO_ACCESS:
            return "Access denied - insufficient privileges"
        case KERN_MEMORY_FAILURE:
            return "Memory allocation failure"
        case KERN_MEMORY_ERROR:
            return "Memory error"
        case KERN_NOT_IN_SET:
            return "Object not found in set"
        case KERN_NAME_EXISTS:
            return "Name already exists"
        case KERN_ABORTED:
            return "Operation aborted"
        case KERN_INVALID_NAME:
            return "Invalid name specified"
        case KERN_INVALID_TASK:
            return "Invalid task"
        case KERN_INVALID_RIGHT:
            return "Invalid right"
        case KERN_INVALID_VALUE:
            return "Invalid value"
        case KERN_UREFS_OVERFLOW:
            return "User references overflow"
        case KERN_INVALID_CAPABILITY:
            return "Invalid capability"
        case KERN_RIGHT_EXISTS:
            return "Right already exists"
        case KERN_INVALID_HOST:
            return "Invalid host"
        case KERN_MEMORY_PRESENT:
            return "Memory already present"
        case KERN_MEMORY_DATA_MOVED:
            return "Memory data moved"
        case KERN_MEMORY_RESTART_COPY:
            return "Memory restart copy"
        case KERN_INVALID_PROCESSOR_SET:
            return "Invalid processor set"
        case KERN_POLICY_LIMIT:
            return "Policy limit exceeded"
        case KERN_INVALID_POLICY:
            return "Invalid policy"
        case KERN_INVALID_OBJECT:
            return "Invalid object"
        case KERN_ALREADY_IN_SET:
            return "Object already in set"
        case KERN_NOT_FOUND:
            return "Object not found"
        case KERN_NOT_RECEIVER:
            return "Not a receiver"
        case KERN_SEMAPHORE_DESTROYED:
            return "Semaphore destroyed"
        case KERN_RPC_SERVER_TERMINATED:
            return "RPC server terminated"
        case KERN_RPC_TERMINATE_ORPHAN:
            return "RPC terminate orphan"
        case KERN_RPC_CONTINUE_ORPHAN:
            return "RPC continue orphan"
        case KERN_NOT_SUPPORTED:
            return "Operation not supported"
        case KERN_NODE_DOWN:
            return "Node is down"
        case KERN_NOT_WAITING:
            return "Thread not waiting"
        case KERN_OPERATION_TIMED_OUT:
            return "Operation timed out"
        case KERN_CODESIGN_ERROR:
            return "Code signing error"
        case KERN_POLICY_STATIC:
            return "Policy is static"
        case KERN_DENIED:
            return "Operation denied"
        case KERN_RETURN_MAX:
            return "Maximum return value"
        default:
            // Handle IOKit-specific error codes (cast to UInt32 for comparison)
            let unsignedResult = UInt32(bitPattern: result)
            if unsignedResult >= 0xe00002bc && unsignedResult <= 0xe00002ff {
                return getIOKitSpecificErrorDescription(result)
            }
            return "Unknown IOKit error (code: \(String(format: "0x%08x", UInt32(bitPattern: result))))"
        }
    }
    
    /// Get descriptions for IOKit-specific error codes
    /// Handles IOKit framework specific error codes beyond general kernel errors
    internal func getIOKitSpecificErrorDescription(_ result: kern_return_t) -> String {
        let unsignedResult = UInt32(bitPattern: result)
        switch unsignedResult {
        case 0xe00002bc: // kIOReturnError
            return "General IOKit error"
        case 0xe00002bd: // kIOReturnNoMemory
            return "IOKit memory allocation failed"
        case 0xe00002be: // kIOReturnNoResources
            return "IOKit resources unavailable"
        case 0xe00002bf: // kIOReturnIPCError
            return "IOKit IPC communication error"
        case 0xe00002c0: // kIOReturnNoDevice
            return "IOKit device not found"
        case 0xe00002c1: // kIOReturnNotPrivileged
            return "IOKit operation requires elevated privileges"
        case 0xe00002c2: // kIOReturnBadArgument
            return "IOKit invalid argument"
        case 0xe00002c3: // kIOReturnLockedRead
            return "IOKit locked for reading"
        case 0xe00002c4: // kIOReturnLockedWrite
            return "IOKit locked for writing"
        case 0xe00002c5: // kIOReturnExclusiveAccess
            return "IOKit device requires exclusive access"
        case 0xe00002c6: // kIOReturnBadMessageID
            return "IOKit invalid message ID"
        case 0xe00002c7: // kIOReturnUnsupported
            return "IOKit operation not supported"
        case 0xe00002c8: // kIOReturnVMError
            return "IOKit virtual memory error"
        case 0xe00002c9: // kIOReturnInternalError
            return "IOKit internal error"
        case 0xe00002ca: // kIOReturnIOError
            return "IOKit I/O error"
        case 0xe00002cb: // kIOReturnCannotLock
            return "IOKit cannot acquire lock"
        case 0xe00002cc: // kIOReturnNotOpen
            return "IOKit device not open"
        case 0xe00002cd: // kIOReturnNotReadable
            return "IOKit device not readable"
        case 0xe00002ce: // kIOReturnNotWritable
            return "IOKit device not writable"
        case 0xe00002cf: // kIOReturnNotAligned
            return "IOKit data not aligned"
        case 0xe00002d0: // kIOReturnBadMedia
            return "IOKit bad media"
        case 0xe00002d1: // kIOReturnStillOpen
            return "IOKit device still open"
        case 0xe00002d2: // kIOReturnRLDError
            return "IOKit RLD error"
        case 0xe00002d3: // kIOReturnDMAError
            return "IOKit DMA error"
        case 0xe00002d4: // kIOReturnBusy
            return "IOKit device busy"
        case 0xe00002d5: // kIOReturnTimeout
            return "IOKit operation timeout"
        case 0xe00002d6: // kIOReturnOffline
            return "IOKit device offline"
        case 0xe00002d7: // kIOReturnNotReady
            return "IOKit device not ready"
        case 0xe00002d8: // kIOReturnNotAttached
            return "IOKit device not attached"
        case 0xe00002d9: // kIOReturnNoChannels
            return "IOKit no channels available"
        case 0xe00002da: // kIOReturnNoSpace
            return "IOKit no space available"
        case 0xe00002db: // kIOReturnPortExists
            return "IOKit port already exists"
        case 0xe00002dc: // kIOReturnCannotWire
            return "IOKit cannot wire memory"
        case 0xe00002dd: // kIOReturnNoInterrupt
            return "IOKit no interrupt available"
        case 0xe00002de: // kIOReturnNoFrames
            return "IOKit no frames available"
        case 0xe00002df: // kIOReturnMessageTooLarge
            return "IOKit message too large"
        case 0xe00002e0: // kIOReturnNotPermitted
            return "IOKit operation not permitted"
        case 0xe00002e1: // kIOReturnNoPower
            return "IOKit no power available"
        case 0xe00002e2: // kIOReturnNoMedia
            return "IOKit no media present"
        case 0xe00002e3: // kIOReturnUnformattedMedia
            return "IOKit media not formatted"
        case 0xe00002e4: // kIOReturnUnsupportedMode
            return "IOKit unsupported mode"
        case 0xe00002e5: // kIOReturnUnderrun
            return "IOKit data underrun"
        case 0xe00002e6: // kIOReturnOverrun
            return "IOKit data overrun"
        case 0xe00002e7: // kIOReturnDeviceError
            return "IOKit device error"
        case 0xe00002e8: // kIOReturnNoCompletion
            return "IOKit no completion"
        case 0xe00002e9: // kIOReturnAborted
            return "IOKit operation aborted"
        case 0xe00002ea: // kIOReturnNoBandwidth
            return "IOKit insufficient bandwidth"
        case 0xe00002eb: // kIOReturnNotResponding
            return "IOKit device not responding"
        case 0xe00002ec: // kIOReturnIsoTooOld
            return "IOKit isochronous data too old"
        case 0xe00002ed: // kIOReturnIsoTooNew
            return "IOKit isochronous data too new"
        case 0xe00002ee: // kIOReturnNotFound
            return "IOKit object not found"
        case 0xe00002ef: // kIOReturnInvalid
            return "IOKit invalid operation"
        default:
            return "Unknown IOKit-specific error (code: \(String(format: "0x%08x", unsignedResult)))"
        }
    }
    
    /// Get error category for logging and monitoring purposes
    internal func getIOKitErrorCategory(_ result: kern_return_t) -> String {
        let unsignedResult = UInt32(bitPattern: result)
        
        switch result {
        case KERN_SUCCESS:
            return "success"
        case KERN_INVALID_ARGUMENT, KERN_INVALID_ADDRESS, KERN_INVALID_NAME, KERN_INVALID_TASK, KERN_INVALID_RIGHT, KERN_INVALID_VALUE, KERN_INVALID_CAPABILITY, KERN_INVALID_HOST, KERN_INVALID_PROCESSOR_SET, KERN_INVALID_POLICY, KERN_INVALID_OBJECT:
            return "invalid_parameter"
        case KERN_RESOURCE_SHORTAGE, KERN_NO_SPACE, KERN_MEMORY_FAILURE, KERN_MEMORY_ERROR:
            return "resource_shortage"
        case KERN_NO_ACCESS, KERN_PROTECTION_FAILURE:
            return "access_denied"
        case KERN_OPERATION_TIMED_OUT:
            return "timeout"
        case KERN_NOT_FOUND, KERN_NOT_IN_SET:
            return "not_found"
        case KERN_ABORTED:
            return "aborted"
        default:
            // Check IOKit-specific categories
            if unsignedResult >= 0xe00002bc && unsignedResult <= 0xe00002ff {
                switch unsignedResult {
                case 0xe00002bd, 0xe00002be, 0xe00002da: // Memory/resource errors
                    return "resource_shortage"
                case 0xe00002c1, 0xe00002e0: // Permission errors
                    return "access_denied"
                case 0xe00002c0, 0xe00002ee: // Device not found
                    return "not_found"
                case 0xe00002d4, 0xe00002d5, 0xe00002d6, 0xe00002d7: // Busy/timeout/not ready
                    return "device_busy"
                case 0xe00002c2, 0xe00002c6, 0xe00002ef: // Invalid arguments
                    return "invalid_parameter"
                default:
                    return "iokit_error"
                }
            }
            return "unknown_error"
        }
    }
}