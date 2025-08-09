// SystemExtensionModels.swift
// Core data models and error types for System Extension IPC communication

import Foundation

// MARK: - System Extension Status

/// System Extension operational status and health information
public struct SystemExtensionStatus: Codable {
    /// Whether the System Extension is currently running
    public let isRunning: Bool
    
    /// List of devices currently claimed by the System Extension
    public let claimedDevices: [ClaimedDevice]
    
    /// Timestamp when the System Extension was last started
    public let lastStartTime: Date
    
    /// Count of errors that have occurred since startup
    public let errorCount: Int
    
    /// Current memory usage in bytes
    public let memoryUsage: Int
    
    /// System Extension version information
    public let version: String
    
    /// Additional health metrics
    public let healthMetrics: SystemExtensionHealthMetrics
    
    public init(
        isRunning: Bool,
        claimedDevices: [ClaimedDevice],
        lastStartTime: Date,
        errorCount: Int,
        memoryUsage: Int,
        version: String,
        healthMetrics: SystemExtensionHealthMetrics
    ) {
        self.isRunning = isRunning
        self.claimedDevices = claimedDevices
        self.lastStartTime = lastStartTime
        self.errorCount = errorCount
        self.memoryUsage = memoryUsage
        self.version = version
        self.healthMetrics = healthMetrics
    }
}

/// Health metrics for System Extension monitoring (legacy)
public struct SystemExtensionHealthMetrics: Codable {
    /// Number of successful device claims
    public let successfulClaims: Int
    
    /// Number of failed device claims
    public let failedClaims: Int
    
    /// Number of active IPC connections
    public let activeConnections: Int
    
    /// Average device claim time in milliseconds
    public let averageClaimTime: Double
    
    /// Last health check timestamp
    public let lastHealthCheck: Date
    
    public init(
        successfulClaims: Int,
        failedClaims: Int,
        activeConnections: Int,
        averageClaimTime: Double,
        lastHealthCheck: Date
    ) {
        self.successfulClaims = successfulClaims
        self.failedClaims = failedClaims
        self.activeConnections = activeConnections
        self.averageClaimTime = averageClaimTime
        self.lastHealthCheck = lastHealthCheck
    }
}

// MARK: - Claimed Device

/// Information about a USB device claimed by the System Extension
public struct ClaimedDevice: Codable {
    /// Unique device identifier (busID-deviceID format)
    public let deviceID: String
    
    /// USB bus identifier
    public let busID: String
    
    /// USB vendor ID
    public let vendorID: UInt16
    
    /// USB product ID
    public let productID: UInt16
    
    /// Product description string (optional)
    public let productString: String?
    
    /// Manufacturer string (optional)
    public let manufacturerString: String?
    
    /// Serial number string (optional)
    public let serialNumber: String?
    
    /// Timestamp when device was claimed
    public let claimTime: Date
    
    /// Method used to claim the device
    public let claimMethod: DeviceClaimMethod
    
    /// Current device claim state
    public let claimState: DeviceClaimState
    
    /// USB device class (e.g., HID, Mass Storage, etc.)
    public let deviceClass: UInt8
    
    /// USB device subclass
    public let deviceSubclass: UInt8
    
    /// USB device protocol
    public let deviceProtocol: UInt8
    
    public init(
        deviceID: String,
        busID: String,
        vendorID: UInt16,
        productID: UInt16,
        productString: String? = nil,
        manufacturerString: String? = nil,
        serialNumber: String? = nil,
        claimTime: Date,
        claimMethod: DeviceClaimMethod,
        claimState: DeviceClaimState,
        deviceClass: UInt8,
        deviceSubclass: UInt8,
        deviceProtocol: UInt8
    ) {
        self.deviceID = deviceID
        self.busID = busID
        self.vendorID = vendorID
        self.productID = productID
        self.productString = productString
        self.manufacturerString = manufacturerString
        self.serialNumber = serialNumber
        self.claimTime = claimTime
        self.claimMethod = claimMethod
        self.claimState = claimState
        self.deviceClass = deviceClass
        self.deviceSubclass = deviceSubclass
        self.deviceProtocol = deviceProtocol
    }
}

/// Method used to claim a USB device
public enum DeviceClaimMethod: String, Codable, CaseIterable {
    /// Device claimed through IOKit driver unbinding
    case driverUnbind = "driver_unbind"
    
    /// Device claimed through IOKit exclusive access
    case exclusiveAccess = "exclusive_access"
    
    /// Device claimed through IOKit matching
    case ioKitMatching = "iokit_matching"
    
    /// Device claimed through System Extension entitlements
    case systemExtension = "system_extension"
}

/// Current state of device claim
public enum DeviceClaimState: String, Codable, CaseIterable {
    /// Device claim is pending
    case pending
    
    /// Device successfully claimed
    case claimed
    
    /// Device claim failed
    case failed
    
    /// Device released from claim
    case released
    
    /// Device disconnected while claimed
    case disconnected
}

// MARK: - IPC Communication

/// Request sent to System Extension via IPC
public struct IPCRequest: Codable {
    /// Unique request identifier
    public let requestID: UUID
    
    /// Client identifier for authentication
    public let clientID: String
    
    /// Command to execute
    public let command: IPCCommand
    
    /// Command parameters
    public let parameters: [String: String]
    
    /// Request timestamp
    public let timestamp: Date
    
    /// Request priority level
    public let priority: RequestPriority
    
    public init(
        requestID: UUID = UUID(),
        clientID: String,
        command: IPCCommand,
        parameters: [String: String] = [:],
        timestamp: Date = Date(),
        priority: RequestPriority = .normal
    ) {
        self.requestID = requestID
        self.clientID = clientID
        self.command = command
        self.parameters = parameters
        self.timestamp = timestamp
        self.priority = priority
    }
}

/// Response sent from System Extension via IPC
public struct IPCResponse: Codable {
    /// Matching request identifier
    public let requestID: UUID
    
    /// Whether the request was successful
    public let success: Bool
    
    /// Response data (if successful)
    public let result: IPCResult?
    
    /// Error information (if unsuccessful)
    public let error: SystemExtensionError?
    
    /// Response timestamp
    public let timestamp: Date
    
    /// Processing time in milliseconds
    public let processingTime: Double
    
    public init(
        requestID: UUID,
        success: Bool,
        result: IPCResult? = nil,
        error: SystemExtensionError? = nil,
        timestamp: Date = Date(),
        processingTime: Double = 0.0
    ) {
        self.requestID = requestID
        self.success = success
        self.result = result
        self.error = error
        self.timestamp = timestamp
        self.processingTime = processingTime
    }
}

/// Commands that can be sent via IPC
public enum IPCCommand: String, Codable, CaseIterable {
    /// Claim a USB device
    case claimDevice = "claim_device"
    
    /// Release a claimed USB device
    case releaseDevice = "release_device"
    
    /// Get list of claimed devices
    case getClaimedDevices = "get_claimed_devices"
    
    /// Get System Extension status
    case getStatus = "get_status"
    
    /// Perform health check
    case healthCheck = "health_check"
    
    /// Get device claim history
    case getClaimHistory = "get_claim_history"
    
    /// Shutdown System Extension
    case shutdown = "shutdown"
}

/// IPC request priority levels
public enum RequestPriority: String, Codable, CaseIterable {
    /// Low priority request
    case low
    
    /// Normal priority request
    case normal
    
    /// High priority request
    case high
    
    /// Critical priority request (e.g., shutdown)
    case critical
}

/// Result data for IPC responses
public enum IPCResult: Codable {
    /// Device claim result
    case deviceClaimed(ClaimedDevice)
    
    /// Device release confirmation
    case deviceReleased(String)
    
    /// List of claimed devices
    case claimedDevices([ClaimedDevice])
    
    /// System Extension status
    case status(SystemExtensionStatus)
    
    /// Health check result
    case healthCheck(Bool)
    
    /// Device claim history
    case claimHistory([DeviceClaimHistoryEntry])
    
    /// Generic success message
    case success(String)
}

/// Historical entry for device claim operations
public struct DeviceClaimHistoryEntry: Codable {
    /// Device identifier
    public let deviceID: String
    
    /// Operation type (claim/release)
    public let operation: ClaimOperation
    
    /// Operation timestamp
    public let timestamp: Date
    
    /// Whether operation was successful
    public let success: Bool
    
    /// Error message if unsuccessful
    public let errorMessage: String?
    
    /// Duration of operation in milliseconds
    public let duration: Double
    
    public init(
        deviceID: String,
        operation: ClaimOperation,
        timestamp: Date,
        success: Bool,
        errorMessage: String? = nil,
        duration: Double
    ) {
        self.deviceID = deviceID
        self.operation = operation
        self.timestamp = timestamp
        self.success = success
        self.errorMessage = errorMessage
        self.duration = duration
    }
}

/// Types of device claim operations
public enum ClaimOperation: String, Codable, CaseIterable {
    /// Device claim operation
    case claim
    
    /// Device release operation
    case release
    
    /// Device reconnection handling
    case reconnect
    
    /// Device restoration after crash
    case restore
}

// MARK: - System Extension Errors

/// Comprehensive error types for System Extension operations
public enum SystemExtensionError: Error, Codable {
    /// System Extension is not implemented (placeholder error)
    case notImplemented
    
    /// Device not found
    case deviceNotFound(String)
    
    /// Access denied for device or operation
    case accessDenied(String)
    
    /// Device claiming failed
    case deviceClaimFailed(String, Int32?)
    
    /// Device release failed
    case deviceReleaseFailed(String, Int32?)
    
    /// IOKit operation error
    case ioKitError(Int32, String)
    
    /// System Extension not authorized
    case notAuthorized(String)
    
    /// System Extension not running
    case extensionNotRunning
    
    /// IPC communication error
    case ipcError(String)
    
    /// Authentication failed
    case authenticationFailed(String)
    
    /// Invalid request parameters
    case invalidParameters(String)
    
    /// Operation timeout
    case timeout(String)
    
    /// Internal system error
    case internalError(String)
    
    /// Configuration error
    case configurationError(String)
    
    /// Resource unavailable (memory, handles, etc.)
    case resourceUnavailable(String)
    
    /// Device already claimed
    case deviceAlreadyClaimed(String)
    
    /// Device not claimed
    case deviceNotClaimed(String)
    
    /// Incompatible system version
    case incompatibleSystem(String)
    
    /// Operation canceled
    case operationCanceled(String)
}

extension SystemExtensionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "System Extension functionality not yet implemented"
        case .deviceNotFound(let deviceID):
            return "Device not found: \(deviceID)"
        case .accessDenied(let reason):
            return "Access denied: \(reason)"
        case let .deviceClaimFailed(deviceID, code):
            if let code = code {
                return "Failed to claim device \(deviceID) (IOKit code: \(code))"
            } else {
                return "Failed to claim device \(deviceID)"
            }
        case let .deviceReleaseFailed(deviceID, code):
            if let code = code {
                return "Failed to release device \(deviceID) (IOKit code: \(code))"
            } else {
                return "Failed to release device \(deviceID)"
            }
        case let .ioKitError(code, message):
            return "IOKit error (code: \(code)): \(message)"
        case .notAuthorized(let reason):
            return "System Extension not authorized: \(reason)"
        case .extensionNotRunning:
            return "System Extension is not running"
        case .ipcError(let message):
            return "IPC communication error: \(message)"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .invalidParameters(let details):
            return "Invalid parameters: \(details)"
        case .timeout(let operation):
            return "Operation timed out: \(operation)"
        case .internalError(let details):
            return "Internal system error: \(details)"
        case .configurationError(let details):
            return "Configuration error: \(details)"
        case .resourceUnavailable(let resource):
            return "Resource unavailable: \(resource)"
        case .deviceAlreadyClaimed(let deviceID):
            return "Device already claimed: \(deviceID)"
        case .deviceNotClaimed(let deviceID):
            return "Device not claimed: \(deviceID)"
        case .incompatibleSystem(let details):
            return "Incompatible system: \(details)"
        case .operationCanceled(let operation):
            return "Operation canceled: \(operation)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .notAuthorized:
            return "System Extension requires user approval in System Preferences"
        case .extensionNotRunning:
            return "System Extension may not be installed or activated"
        case .deviceClaimFailed, .deviceReleaseFailed:
            return "USB device may be in use by another process"
        case .ioKitError:
            return "Low-level system error occurred during USB operation"
        case .authenticationFailed:
            return "Client authentication credentials are invalid"
        case .timeout:
            return "Operation took longer than expected to complete"
        default:
            return nil
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .notAuthorized:
            return "Open System Preferences > Privacy & Security > System Extensions and approve the USB/IP System Extension"
        case .extensionNotRunning:
            return "Try restarting the USB/IP daemon or reinstalling the System Extension"
        case .deviceClaimFailed:
            return "Ensure no other applications are using the USB device and try again"
        case .authenticationFailed:
            return "Restart the USB/IP daemon to refresh authentication"
        case .timeout:
            return "Try the operation again or check system load"
        default:
            return "Check system logs for more detailed error information"
        }
    }
}