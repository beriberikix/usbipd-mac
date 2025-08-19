// SystemExtensionSubmissionTypes.swift
// Data types for System Extension submission and approval workflow

import Foundation

// MARK: - Submission Status

/// Status of System Extension submission to macOS
public enum SystemExtensionSubmissionStatus: Equatable {
    /// Extension has not been submitted
    case notSubmitted
    
    /// Submission is in progress
    case submitting
    
    /// Submission is pending user approval
    case pendingApproval(requestID: UUID)
    
    /// Extension has been approved and is active
    case approved(extensionID: String)
    
    /// Submission failed with error
    case failed(error: SystemExtensionSubmissionError)
    
    /// User action is required to complete installation
    case requiresUserAction(instructions: String)
}

// MARK: - Submission Result

/// Result of System Extension submission operation
public struct SubmissionResult {
    /// Final submission status
    public let status: SystemExtensionSubmissionStatus
    
    /// Timestamp when submission was initiated
    public let submissionTime: Date
    
    /// Completion timestamp (if applicable)
    public let approvalTime: Date?
    
    /// User-friendly instructions for next steps
    public let userInstructions: [String]
    
    /// Detailed error information (if failed)
    public let errorDetails: String?
    
    public init(
        status: SystemExtensionSubmissionStatus,
        submissionTime: Date,
        approvalTime: Date? = nil,
        userInstructions: [String] = [],
        errorDetails: String? = nil
    ) {
        self.status = status
        self.submissionTime = submissionTime
        self.approvalTime = approvalTime
        self.userInstructions = userInstructions
        self.errorDetails = errorDetails
    }
}

// MARK: - Submission Errors

/// Specific errors that can occur during System Extension submission
public enum SystemExtensionSubmissionError: Error, Equatable {
    /// Bundle file not found at specified path
    case bundleNotFound
    
    /// Bundle is invalid or corrupted
    case invalidBundle
    
    /// Extension is not properly code signed
    case unsignedExtension
    
    /// Code signature is invalid or expired
    case invalidSignature
    
    /// Required entitlements are missing
    case missingEntitlement
    
    /// User authorization is required
    case authorizationRequired
    
    /// Installation request was canceled
    case requestCanceled
    
    /// Request was superseded by another request
    case requestSuperseded
    
    /// Extension with this identifier already exists
    case duplicateExtensionIdentifier
    
    /// Extension cannot be used on this system
    case extensionNotUsable
    
    /// Extension not found in system
    case extensionNotFound
    
    /// Another request is already in progress
    case requestInProgress
    
    /// Unknown or unhandled error
    case unknownError
    
    // MARK: - Error Information
    
    /// User-friendly error description
    public var userDescription: String {
        switch self {
        case .bundleNotFound:
            return "System Extension bundle not found"
        case .invalidBundle:
            return "System Extension bundle is invalid"
        case .unsignedExtension:
            return "System Extension is not code signed"
        case .invalidSignature:
            return "System Extension signature is invalid"
        case .missingEntitlement:
            return "System Extension is missing required entitlements"
        case .authorizationRequired:
            return "User authorization required"
        case .requestCanceled:
            return "Installation request was canceled"
        case .requestSuperseded:
            return "Installation request was superseded"
        case .duplicateExtensionIdentifier:
            return "Extension with this identifier already exists"
        case .extensionNotUsable:
            return "System Extension cannot be used"
        case .extensionNotFound:
            return "System Extension not found"
        case .requestInProgress:
            return "Another installation request is in progress"
        case .unknownError:
            return "Unknown error occurred"
        }
    }
    
    /// Recommended recovery actions
    public var recoveryActions: [String] {
        switch self {
        case .bundleNotFound:
            return [
                "Verify the bundle path is correct",
                "Ensure the System Extension was built successfully",
                "Check file permissions"
            ]
        case .invalidBundle:
            return [
                "Rebuild the System Extension",
                "Verify bundle structure and Info.plist",
                "Check for bundle corruption"
            ]
        case .unsignedExtension:
            return [
                "Code sign the System Extension with a valid certificate",
                "Ensure you have a valid Apple Developer account",
                "Check signing configuration"
            ]
        case .invalidSignature:
            return [
                "Re-sign the System Extension",
                "Verify certificate is not expired",
                "Check certificate chain"
            ]
        case .missingEntitlement:
            return [
                "Add required entitlements to the extension",
                "Verify entitlements file is correct",
                "Check provisioning profile"
            ]
        case .authorizationRequired:
            return [
                "Open System Preferences > Security & Privacy",
                "Allow the blocked System Extension",
                "Try installation again"
            ]
        case .requestCanceled:
            return [
                "Try installation again",
                "Ensure you complete the approval process"
            ]
        case .requestSuperseded:
            return [
                "This usually resolves automatically",
                "Wait for the newer request to complete"
            ]
        case .duplicateExtensionIdentifier:
            return [
                "Uninstall the existing extension first",
                "Use a unique bundle identifier",
                "Check for conflicting installations"
            ]
        case .extensionNotUsable:
            return [
                "Check system requirements",
                "Verify extension compatibility",
                "Check macOS version compatibility"
            ]
        case .extensionNotFound:
            return [
                "Verify bundle exists at specified path",
                "Check bundle identifier",
                "Ensure extension was built properly"
            ]
        case .requestInProgress:
            return [
                "Wait for current request to complete",
                "Cancel existing request if needed"
            ]
        case .unknownError:
            return [
                "Check system logs for more information",
                "Retry the operation",
                "Contact support if issue persists"
            ]
        }
    }
}

