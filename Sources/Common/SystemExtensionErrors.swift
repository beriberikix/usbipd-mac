// SystemExtensionErrors.swift
// Comprehensive error handling for System Extension installation and management

import Foundation
import SystemExtensions

/// Comprehensive System Extension installation and management errors
public enum SystemExtensionInstallationError: Error, Equatable {
    // MARK: - Installation Errors
    
    /// System Extension installation failed due to missing bundle
    case bundleNotFound(String)
    
    /// System Extension installation failed due to invalid bundle
    case invalidBundle(String)
    
    /// System Extension installation failed due to missing entitlements
    case missingEntitlements([String])
    
    /// System Extension installation failed due to invalid code signature
    case invalidCodeSignature(String)
    
    /// System Extension installation requires user approval
    case requiresApproval
    
    /// User rejected the System Extension installation request
    case userRejected
    
    /// System Extension installation was cancelled by user
    case installationCancelled
    
    /// System Extension installation failed due to system policy restrictions
    case policyViolation(String)
    
    /// System Extension installation failed due to insufficient privileges
    case insufficientPrivileges(String)
    
    // MARK: - Runtime Errors
    
    /// System Extension activation failed
    case activationFailed(String)
    
    /// System Extension deactivation failed
    case deactivationFailed(String)
    
    /// System Extension upgrade failed
    case upgradeFailed(from: String, to: String, reason: String)
    
    /// System Extension communication failed
    case communicationFailure(String)
    
    /// System Extension health check failed
    case healthCheckFailed(String)
    
    /// System Extension crashed or terminated unexpectedly
    case unexpectedTermination(exitCode: Int32?, reason: String?)
    
    // MARK: - System Errors
    
    /// System Extension requires system reboot to complete installation
    case requiresReboot
    
    /// System Extension installation failed due to system resource constraints
    case systemResourcesUnavailable(String)
    
    /// System Extension installation failed due to version incompatibility
    case versionIncompatible(current: String, required: String)
    
    /// System Extension installation failed due to macOS version incompatibility
    case macOSVersionIncompatible(current: String, minimum: String)
    
    /// System Extension installation failed due to architecture mismatch
    case architectureMismatch(expected: String, found: String)
    
    // MARK: - Network and IPC Errors
    
    /// System Extension IPC connection failed
    case ipcConnectionFailed(String)
    
    /// System Extension IPC timeout
    case ipcTimeout(TimeInterval)
    
    /// System Extension message processing failed
    case messageProcessingFailed(String)
    
    /// System Extension protocol version mismatch
    case protocolVersionMismatch(extension: String, host: String)
    
    // MARK: - Configuration Errors
    
    /// System Extension configuration invalid
    case invalidConfiguration(String)
    
    /// System Extension dependency missing
    case missingDependency(String)
    
    /// System Extension conflicting installation detected
    case conflictingInstallation(String)
    
    /// System Extension database corruption
    case databaseCorruption(String)
    
    // MARK: - Development and Testing Errors
    
    /// System Extension development mode not enabled
    case developmentModeDisabled
    
    /// System Extension testing framework error
    case testingFrameworkError(String)
    
    /// System Extension mock environment error
    case mockEnvironmentError(String)
    
    // MARK: - Unknown and Internal Errors
    
    /// System Extension installation failed with unknown system error
    case unknownSystemError(OSStatus, String?)
    
    /// Internal error in System Extension management
    case internalError(String)
    
    /// System Extension operation timed out
    case operationTimeout(operation: String, timeout: TimeInterval)
    
    public static func == (lhs: SystemExtensionInstallationError, rhs: SystemExtensionInstallationError) -> Bool {
        switch (lhs, rhs) {
        case (.bundleNotFound(let lhsPath), .bundleNotFound(let rhsPath)):
            return lhsPath == rhsPath
        case (.invalidBundle(let lhsReason), .invalidBundle(let rhsReason)):
            return lhsReason == rhsReason
        case (.missingEntitlements(let lhsEntitlements), .missingEntitlements(let rhsEntitlements)):
            return lhsEntitlements == rhsEntitlements
        case (.invalidCodeSignature(let lhsReason), .invalidCodeSignature(let rhsReason)):
            return lhsReason == rhsReason
        case (.requiresApproval, .requiresApproval),
             (.userRejected, .userRejected),
             (.installationCancelled, .installationCancelled),
             (.requiresReboot, .requiresReboot),
             (.developmentModeDisabled, .developmentModeDisabled):
            return true
        case (.policyViolation(let lhsReason), .policyViolation(let rhsReason)):
            return lhsReason == rhsReason
        case (.insufficientPrivileges(let lhsReason), .insufficientPrivileges(let rhsReason)):
            return lhsReason == rhsReason
        case (.activationFailed(let lhsReason), .activationFailed(let rhsReason)):
            return lhsReason == rhsReason
        case (.deactivationFailed(let lhsReason), .deactivationFailed(let rhsReason)):
            return lhsReason == rhsReason
        case (.upgradeFailed(let lhsFrom, let lhsTo, let lhsReason), .upgradeFailed(let rhsFrom, let rhsTo, let rhsReason)):
            return lhsFrom == rhsFrom && lhsTo == rhsTo && lhsReason == rhsReason
        case (.unexpectedTermination(let lhsCode, let lhsReason), .unexpectedTermination(let rhsCode, let rhsReason)):
            return lhsCode == rhsCode && lhsReason == rhsReason
        case (.versionIncompatible(let lhsCurrent, let lhsRequired), .versionIncompatible(let rhsCurrent, let rhsRequired)):
            return lhsCurrent == rhsCurrent && lhsRequired == rhsRequired
        case (.macOSVersionIncompatible(let lhsCurrent, let lhsMinimum), .macOSVersionIncompatible(let rhsCurrent, let rhsMinimum)):
            return lhsCurrent == rhsCurrent && lhsMinimum == rhsMinimum
        case (.architectureMismatch(let lhsExpected, let lhsFound), .architectureMismatch(let rhsExpected, let rhsFound)):
            return lhsExpected == rhsExpected && lhsFound == rhsFound
        case (.unknownSystemError(let lhsStatus, let lhsMessage), .unknownSystemError(let rhsStatus, let rhsMessage)):
            return lhsStatus == rhsStatus && lhsMessage == rhsMessage
        case (.operationTimeout(let lhsOp, let lhsTimeout), .operationTimeout(let rhsOp, let rhsTimeout)):
            return lhsOp == rhsOp && lhsTimeout == rhsTimeout
        default:
            // For other cases with associated values, compare string representations
            return String(describing: lhs) == String(describing: rhs)
        }
    }
}

// MARK: - LocalizedError Implementation

extension SystemExtensionInstallationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        // Installation Errors
        case .bundleNotFound(let path):
            return "System Extension bundle not found at path: \(path)"
        case .invalidBundle(let reason):
            return "Invalid System Extension bundle: \(reason)"
        case .missingEntitlements(let entitlements):
            return "System Extension missing required entitlements: \(entitlements.joined(separator: ", "))"
        case .invalidCodeSignature(let reason):
            return "System Extension has invalid code signature: \(reason)"
        case .requiresApproval:
            return "System Extension installation requires user approval in System Preferences"
        case .userRejected:
            return "User rejected System Extension installation request"
        case .installationCancelled:
            return "System Extension installation was cancelled"
        case .policyViolation(let reason):
            return "System Extension installation violates system policy: \(reason)"
        case .insufficientPrivileges(let reason):
            return "Insufficient privileges for System Extension installation: \(reason)"
            
        // Runtime Errors
        case .activationFailed(let reason):
            return "System Extension activation failed: \(reason)"
        case .deactivationFailed(let reason):
            return "System Extension deactivation failed: \(reason)"
        case let .upgradeFailed(from, to, reason):
            return "System Extension upgrade failed from \(from) to \(to): \(reason)"
        case .communicationFailure(let reason):
            return "System Extension communication failure: \(reason)"
        case .healthCheckFailed(let reason):
            return "System Extension health check failed: \(reason)"
        case let .unexpectedTermination(exitCode, reason):
            let codeInfo = exitCode.map { " (exit code: \($0))" } ?? ""
            let reasonInfo = reason.map { ": \($0)" } ?? ""
            return "System Extension terminated unexpectedly\(codeInfo)\(reasonInfo)"
            
        // System Errors
        case .requiresReboot:
            return "System Extension installation requires a system reboot to complete"
        case .systemResourcesUnavailable(let reason):
            return "System resources unavailable for System Extension: \(reason)"
        case let .versionIncompatible(current, required):
            return "System Extension version incompatible: current \(current), required \(required)"
        case let .macOSVersionIncompatible(current, minimum):
            return "macOS version incompatible: current \(current), minimum required \(minimum)"
        case let .architectureMismatch(expected, found):
            return "Architecture mismatch: expected \(expected), found \(found)"
            
        // Network and IPC Errors
        case .ipcConnectionFailed(let reason):
            return "System Extension IPC connection failed: \(reason)"
        case .ipcTimeout(let timeout):
            return "System Extension IPC timeout after \(timeout) seconds"
        case .messageProcessingFailed(let reason):
            return "System Extension message processing failed: \(reason)"
        case let .protocolVersionMismatch(`extension`, host):
            return "Protocol version mismatch: extension \(`extension`), host \(host)"
            
        // Configuration Errors
        case .invalidConfiguration(let reason):
            return "Invalid System Extension configuration: \(reason)"
        case .missingDependency(let dependency):
            return "Missing System Extension dependency: \(dependency)"
        case .conflictingInstallation(let details):
            return "Conflicting System Extension installation detected: \(details)"
        case .databaseCorruption(let reason):
            return "System Extension database corruption: \(reason)"
            
        // Development and Testing Errors
        case .developmentModeDisabled:
            return "System Extension development mode is not enabled"
        case .testingFrameworkError(let reason):
            return "System Extension testing framework error: \(reason)"
        case .mockEnvironmentError(let reason):
            return "System Extension mock environment error: \(reason)"
            
        // Unknown and Internal Errors
        case let .unknownSystemError(status, message):
            let messageInfo = message.map { ": \($0)" } ?? ""
            return "Unknown system error \(status)\(messageInfo)"
        case .internalError(let reason):
            return "Internal System Extension error: \(reason)"
        case let .operationTimeout(operation, timeout):
            return "System Extension operation '\(operation)' timed out after \(timeout) seconds"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .bundleNotFound:
            return "The System Extension bundle file could not be located"
        case .invalidBundle:
            return "The System Extension bundle is corrupted or invalid"
        case .missingEntitlements:
            return "Required entitlements are not present in the System Extension"
        case .invalidCodeSignature:
            return "The System Extension code signature is invalid or untrusted"
        case .requiresApproval:
            return "User approval is required for System Extension installation"
        case .userRejected:
            return "The user declined to approve the System Extension"
        case .insufficientPrivileges:
            return "Administrator privileges are required for this operation"
        case .activationFailed, .deactivationFailed:
            return "System Extension lifecycle operation failed"
        case .communicationFailure:
            return "Unable to communicate with the System Extension"
        case .requiresReboot:
            return "A system reboot is required to complete the operation"
        case .versionIncompatible, .macOSVersionIncompatible, .architectureMismatch:
            return "Version or architecture compatibility issue"
        case .ipcConnectionFailed, .ipcTimeout:
            return "Inter-process communication with System Extension failed"
        case .developmentModeDisabled:
            return "System Extension development features are not available"
        default:
            return nil
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .bundleNotFound:
            return "Verify the System Extension bundle path and ensure the file exists"
        case .invalidBundle:
            return "Rebuild the System Extension bundle and verify code signing"
        case .missingEntitlements:
            return "Add the required entitlements to the System Extension Info.plist"
        case .invalidCodeSignature:
            return "Re-sign the System Extension bundle with a valid developer certificate"
        case .requiresApproval:
            return "Open System Preferences > Security & Privacy > General and approve the System Extension"
        case .userRejected:
            return "Try the installation again and approve when prompted"
        case .insufficientPrivileges:
            return "Run the application with administrator privileges using 'sudo'"
        case .activationFailed:
            return "Check system logs and try restarting the System Extension"
        case .deactivationFailed:
            return "Force quit the System Extension and try again"
        case .communicationFailure:
            return "Restart the System Extension or reboot the system"
        case .requiresReboot:
            return "Restart your Mac to complete the System Extension installation"
        case .versionIncompatible:
            return "Update to a compatible version of the System Extension"
        case .macOSVersionIncompatible:
            return "Update macOS to the minimum required version"
        case .architectureMismatch:
            return "Install the correct architecture version of the System Extension"
        case .ipcConnectionFailed, .ipcTimeout:
            return "Restart the application and ensure the System Extension is running"
        case .developmentModeDisabled:
            return "Enable System Extension development mode with 'systemextensionsctl developer on'"
        case .operationTimeout:
            return "Try the operation again or check system performance"
        default:
            return "Check system logs for more detailed error information"
        }
    }
}

// MARK: - User-Friendly Error Messages

extension SystemExtensionInstallationError {
    /// Get a user-friendly error message suitable for display in UI
    public var userFriendlyMessage: String {
        switch self {
        case .bundleNotFound:
            return "System Extension file not found. Please reinstall the application."
        case .invalidBundle:
            return "System Extension is damaged. Please download a fresh copy of the application."
        case .missingEntitlements, .invalidCodeSignature:
            return "System Extension security validation failed. Please download from official sources."
        case .requiresApproval:
            return "System Extension needs your approval. Check System Preferences > Security & Privacy."
        case .userRejected:
            return "System Extension installation was cancelled. It's needed for USB device management."
        case .insufficientPrivileges:
            return "Administrator access required. Please run as administrator or use sudo."
        case .activationFailed:
            return "Failed to start System Extension. Try restarting the application."
        case .deactivationFailed:
            return "Failed to stop System Extension. You may need to restart your Mac."
        case .communicationFailure:
            return "Lost connection to System Extension. Try restarting the application."
        case .requiresReboot:
            return "Please restart your Mac to complete the System Extension installation."
        case .versionIncompatible:
            return "System Extension version is incompatible. Please update the application."
        case .macOSVersionIncompatible:
            return "This System Extension requires a newer version of macOS."
        case .architectureMismatch:
            return "System Extension architecture doesn't match your Mac. Download the correct version."
        case .ipcConnectionFailed, .ipcTimeout:
            return "Communication with System Extension failed. Try restarting the application."
        case .developmentModeDisabled:
            return "Development features are not available. Enable development mode if needed."
        case .operationTimeout:
            return "Operation took too long to complete. Please try again."
        default:
            return "System Extension error occurred. Check system logs for details."
        }
    }
    
    /// Check if this error is recoverable through user action
    public var isRecoverable: Bool {
        switch self {
        case .requiresApproval, .userRejected, .insufficientPrivileges, .requiresReboot,
             .activationFailed, .communicationFailure, .ipcConnectionFailed, .ipcTimeout,
             .operationTimeout:
            return true
        case .bundleNotFound, .invalidBundle, .missingEntitlements, .invalidCodeSignature,
             .versionIncompatible, .macOSVersionIncompatible, .architectureMismatch,
             .policyViolation, .databaseCorruption:
            return false
        default:
            return false
        }
    }
    
    /// Check if this error requires immediate user attention
    public var requiresUserAttention: Bool {
        switch self {
        case .requiresApproval, .userRejected, .requiresReboot, .insufficientPrivileges:
            return true
        default:
            return false
        }
    }
    
    /// Get the error category for logging and analytics
    public var category: String {
        switch self {
        case .bundleNotFound, .invalidBundle, .missingEntitlements, .invalidCodeSignature:
            return "installation"
        case .requiresApproval, .userRejected, .installationCancelled:
            return "user_interaction"
        case .activationFailed, .deactivationFailed, .upgradeFailed:
            return "lifecycle"
        case .communicationFailure, .ipcConnectionFailed, .ipcTimeout, .messageProcessingFailed:
            return "communication"
        case .versionIncompatible, .macOSVersionIncompatible, .architectureMismatch:
            return "compatibility"
        case .insufficientPrivileges, .policyViolation:
            return "security"
        case .systemResourcesUnavailable, .requiresReboot:
            return "system"
        case .developmentModeDisabled, .testingFrameworkError, .mockEnvironmentError:
            return "development"
        default:
            return "general"
        }
    }
}

// MARK: - Convenience Methods

extension SystemExtensionInstallationError {
    /// Create error from SystemExtensions framework errors
    public static func from(systemExtensionError error: Error) -> SystemExtensionInstallationError {
        if let osError = error as? OSSystemExtensionError {
            switch osError.code {
            case .requestCanceled:
                return .installationCancelled
            case .missingEntitlement:
                return .missingEntitlements(["Unknown entitlement"])
            case .unsupportedParentBundleLocation:
                return .invalidBundle("Unsupported bundle location")
            case .extensionNotFound:
                return .bundleNotFound("Extension not found in bundle")
            case .forbiddenBySystemPolicy:
                return .policyViolation("Forbidden by system policy")
            case .requestSuperseded:
                return .internalError("Request superseded by newer request")
            case .authorizationRequired:
                return .requiresApproval
            default:
                return .unknownSystemError(OSStatus(osError.code.rawValue), osError.localizedDescription)
            }
        }
        
        return .internalError("Unknown error: \(error.localizedDescription)")
    }
    
    /// Create error from NSError
    public static func from(nsError error: NSError) -> SystemExtensionInstallationError {
        switch error.domain {
        case "OSSystemExtensionErrorDomain":
            return from(systemExtensionError: error)
        case "NSOSStatusErrorDomain":
            return .unknownSystemError(OSStatus(error.code), error.localizedDescription)
        default:
            return .internalError("NSError: \(error.localizedDescription)")
        }
    }
}