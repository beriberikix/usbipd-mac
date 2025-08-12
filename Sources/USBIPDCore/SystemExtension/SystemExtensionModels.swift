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
    
    /// Installation status information
    public let installationStatus: SystemExtensionInstallationStatus
    
    /// Overall system health assessment
    public let healthStatus: HealthStatus
    
    /// Bundle information (if available)
    public let bundleInfo: SystemExtensionBundle?
    
    /// System extension approval status
    public let approvalStatus: ApprovalStatus
    
    /// Validation results from system checks
    public let validationResults: [ValidationResult]
    
    public init(
        isRunning: Bool,
        claimedDevices: [ClaimedDevice],
        lastStartTime: Date,
        errorCount: Int,
        memoryUsage: Int,
        version: String,
        healthMetrics: SystemExtensionHealthMetrics,
        installationStatus: SystemExtensionInstallationStatus = .unknown,
        healthStatus: HealthStatus = .unknown,
        bundleInfo: SystemExtensionBundle? = nil,
        approvalStatus: ApprovalStatus = .unknown,
        validationResults: [ValidationResult] = []
    ) {
        self.isRunning = isRunning
        self.claimedDevices = claimedDevices
        self.lastStartTime = lastStartTime
        self.errorCount = errorCount
        self.memoryUsage = memoryUsage
        self.version = version
        self.healthMetrics = healthMetrics
        self.installationStatus = installationStatus
        self.healthStatus = healthStatus
        self.bundleInfo = bundleInfo
        self.approvalStatus = approvalStatus
        self.validationResults = validationResults
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

// MARK: - Installation and Status Models

/// System Extension installation status
public enum SystemExtensionInstallationStatus: String, Codable, CaseIterable {
    /// Installation status is unknown
    case unknown = "unknown"
    
    /// System Extension is not installed
    case notInstalled = "not_installed"
    
    /// System Extension installation is in progress
    case installing = "installing"
    
    /// System Extension is installed and ready
    case installed = "installed"
    
    /// System Extension installation failed
    case installationFailed = "installation_failed"
    
    /// System Extension requires reinstallation
    case requiresReinstall = "requires_reinstall"
    
    /// System Extension bundle is invalid
    case invalidBundle = "invalid_bundle"
    
    /// System Extension is pending user approval
    case pendingApproval = "pending_approval"
}

/// Overall health status of System Extension
public enum HealthStatus: String, Codable, CaseIterable {
    /// Health status is unknown
    case unknown = "unknown"
    
    /// System Extension is healthy and functioning normally
    case healthy = "healthy"
    
    /// System Extension has minor issues but is functional
    case degraded = "degraded"
    
    /// System Extension has significant issues
    case unhealthy = "unhealthy"
    
    /// System Extension is not responding or crashed
    case critical = "critical"
    
    /// System Extension requires attention
    case requiresAttention = "requires_attention"
    
    /// User-readable description of health status
    public var displayName: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .healthy:
            return "Healthy"
        case .degraded:
            return "Degraded Performance"
        case .unhealthy:
            return "Unhealthy"
        case .critical:
            return "Critical"
        case .requiresAttention:
            return "Requires Attention"
        }
    }
}

/// System Extension approval status with user
public enum ApprovalStatus: String, Codable, CaseIterable {
    /// Approval status is unknown
    case unknown = "unknown"
    
    /// System Extension is approved by user
    case approved = "approved"
    
    /// System Extension approval is pending user action
    case pending = "pending"
    
    /// System Extension was denied by user
    case denied = "denied"
    
    /// System Extension approval was revoked
    case revoked = "revoked"
    
    /// System Extension requires reapproval
    case requiresReapproval = "requires_reapproval"
}

/// Result of a validation check
public struct ValidationResult: Codable {
    /// Unique identifier for the validation check
    public let checkID: String
    
    /// Human-readable name of the validation
    public let checkName: String
    
    /// Whether the validation passed
    public let passed: Bool
    
    /// Validation result message
    public let message: String
    
    /// Severity level of any issues found
    public let severity: ValidationSeverity
    
    /// Recommended actions to resolve issues
    public let recommendedActions: [String]
    
    /// Validation timestamp
    public let timestamp: Date
    
    public init(
        checkID: String,
        checkName: String,
        passed: Bool,
        message: String,
        severity: ValidationSeverity,
        recommendedActions: [String] = [],
        timestamp: Date = Date()
    ) {
        self.checkID = checkID
        self.checkName = checkName
        self.passed = passed
        self.message = message
        self.severity = severity
        self.recommendedActions = recommendedActions
        self.timestamp = timestamp
    }
}

/// Severity level for validation results
public enum ValidationSeverity: String, Codable, CaseIterable {
    /// Informational message
    case info
    
    /// Warning that may affect functionality
    case warning
    
    /// Error that will prevent proper operation
    case error
    
    /// Critical issue requiring immediate attention
    case critical
}

/// Result of installation operation
public struct InstallationResult: Codable {
    /// Whether installation was successful
    public let success: Bool
    
    /// Installed bundle information (if successful)
    public let installedBundle: SystemExtensionBundle?
    
    /// Installation errors encountered
    public let errors: [InstallationError]
    
    /// Installation warnings
    public let warnings: [String]
    
    /// Time taken for installation in seconds
    public let installationTime: TimeInterval
    
    /// Installation timestamp
    public let timestamp: Date
    
    /// Installation method used
    public let installationMethod: InstallationMethod
    
    /// Post-installation validation results
    public let validationResults: [ValidationResult]
    
    public init(
        success: Bool,
        installedBundle: SystemExtensionBundle? = nil,
        errors: [InstallationError] = [],
        warnings: [String] = [],
        installationTime: TimeInterval = 0.0,
        timestamp: Date = Date(),
        installationMethod: InstallationMethod = .automatic,
        validationResults: [ValidationResult] = []
    ) {
        self.success = success
        self.installedBundle = installedBundle
        self.errors = errors
        self.warnings = warnings
        self.installationTime = installationTime
        self.timestamp = timestamp
        self.installationMethod = installationMethod
        self.validationResults = validationResults
    }
}

/// Installation method used
public enum InstallationMethod: String, Codable, CaseIterable {
    /// Automatic installation using systemextensionsctl
    case automatic = "automatic"
    
    /// Manual installation with user intervention
    case manual = "manual"
    
    /// Force reinstallation
    case forceReinstall = "force_reinstall"
    
    /// Development installation (unsigned)
    case development = "development"
}

/// Specific installation error types
public enum InstallationError: Error, Codable {
    /// Bundle creation failed
    case bundleCreationFailed(String)
    
    /// Code signing failed
    case codeSigningFailed(String)
    
    /// Bundle validation failed
    case bundleValidationFailed([String])
    
    /// systemextensionsctl command failed
    case systemExtensionsCtlFailed(Int32, String)
    
    /// User approval timeout or denial
    case userApprovalFailed(String)
    
    /// System Integrity Protection blocking installation
    case sipBlocked(String)
    
    /// Developer mode not enabled
    case developerModeRequired(String)
    
    /// Insufficient permissions
    case insufficientPermissions(String)
    
    /// Bundle already exists
    case bundleAlreadyExists(String)
    
    /// Invalid bundle identifier
    case invalidBundleIdentifier(String)
    
    /// Certificate validation failed
    case certificateValidationFailed(String)
    
    /// System extension conflicts
    case extensionConflict([String])
    
    /// Installation timeout
    case installationTimeout(TimeInterval)
    
    /// File system error
    case fileSystemError(String)
    
    /// Unknown installation error
    case unknownError(String)
    
    /// System extension requires user approval
    case requiresApproval
    
    /// Development mode disabled
    case developmentModeDisabled
    
    /// Invalid code signature
    case invalidCodeSignature(String)
    
    /// User rejected installation
    case userRejected
}

/// Type alias for system extension installation errors
public typealias SystemExtensionInstallationError = InstallationError

extension InstallationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .bundleCreationFailed(let details):
            return "Bundle creation failed: \(details)"
        case .codeSigningFailed(let details):
            return "Code signing failed: \(details)"
        case .bundleValidationFailed(let issues):
            return "Bundle validation failed: \(issues.joined(separator: ", "))"
        case .systemExtensionsCtlFailed(let code, let message):
            return "systemextensionsctl failed (code \(code)): \(message)"
        case .userApprovalFailed(let reason):
            return "User approval failed: \(reason)"
        case .sipBlocked(let details):
            return "System Integrity Protection blocked installation: \(details)"
        case .developerModeRequired(let details):
            return "Developer mode required: \(details)"
        case .insufficientPermissions(let details):
            return "Insufficient permissions: \(details)"
        case .bundleAlreadyExists(let path):
            return "Bundle already exists at: \(path)"
        case .invalidBundleIdentifier(let identifier):
            return "Invalid bundle identifier: \(identifier)"
        case .certificateValidationFailed(let details):
            return "Certificate validation failed: \(details)"
        case .extensionConflict(let conflicts):
            return "Extension conflicts: \(conflicts.joined(separator: ", "))"
        case .installationTimeout(let timeout):
            return "Installation timed out after \(timeout) seconds"
        case .fileSystemError(let details):
            return "File system error: \(details)"
        case .unknownError(let details):
            return "Unknown installation error: \(details)"
        case .requiresApproval:
            return "System Extension requires user approval"
        case .developmentModeDisabled:
            return "Development mode is disabled"
        case .invalidCodeSignature(let reason):
            return "Invalid code signature: \(reason)"
        case .userRejected:
            return "System Extension installation was rejected by user"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .bundleCreationFailed:
            return "Check build configuration and ensure executable is available"
        case .codeSigningFailed:
            return "Verify code signing certificate is installed and valid"
        case .bundleValidationFailed:
            return "Fix bundle structure issues and try again"
        case .systemExtensionsCtlFailed:
            return "Check system logs for more details and retry installation"
        case .userApprovalFailed:
            return "Approve the System Extension in System Preferences > Privacy & Security"
        case .sipBlocked:
            return "Consider disabling SIP for development or use proper certificates"
        case .developerModeRequired:
            return "Enable Developer Mode in Terminal: systemextensionsctl developer on"
        case .insufficientPermissions:
            return "Run installation with appropriate permissions or as administrator"
        case .bundleAlreadyExists:
            return "Remove existing bundle or use force reinstall option"
        case .invalidBundleIdentifier:
            return "Use a valid reverse DNS bundle identifier"
        case .certificateValidationFailed:
            return "Install a valid Apple Developer certificate"
        case .extensionConflict:
            return "Remove conflicting system extensions before installing"
        case .installationTimeout:
            return "Retry installation or check system performance"
        case .fileSystemError:
            return "Check disk space and file system permissions"
        case .unknownError:
            return "Check system logs for more details"
        case .requiresApproval:
            return "Approve the System Extension in System Preferences > Security & Privacy"
        case .developmentModeDisabled:
            return "Enable developer mode using: systemextensionsctl developer on"
        case .invalidCodeSignature:
            return "Re-sign the extension with a valid certificate"
        case .userRejected:
            return "Retry installation and approve when prompted"
        }
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

// MARK: - System Extension Bundle Models

/// System Extension bundle information for creation and management
public struct SystemExtensionBundle: Codable {
    /// Bundle path on filesystem
    public let bundlePath: String
    
    /// Bundle identifier (e.g., com.example.USBIPSystemExtension)
    public let bundleIdentifier: String
    
    /// Bundle display name
    public let displayName: String
    
    /// Bundle version string
    public let version: String
    
    /// Bundle build number
    public let buildNumber: String
    
    /// Executable name within bundle
    public let executableName: String
    
    /// Team identifier for code signing
    public let teamIdentifier: String?
    
    /// Bundle contents structure
    public let contents: BundleContents
    
    /// Code signing information
    public let codeSigningInfo: CodeSigningInfo?
    
    /// Bundle creation timestamp
    public let creationTime: Date
    
    public init(
        bundlePath: String,
        bundleIdentifier: String,
        displayName: String,
        version: String,
        buildNumber: String,
        executableName: String,
        teamIdentifier: String? = nil,
        contents: BundleContents,
        codeSigningInfo: CodeSigningInfo? = nil,
        creationTime: Date = Date()
    ) {
        self.bundlePath = bundlePath
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.version = version
        self.buildNumber = buildNumber
        self.executableName = executableName
        self.teamIdentifier = teamIdentifier
        self.contents = contents
        self.codeSigningInfo = codeSigningInfo
        self.creationTime = creationTime
    }
}

/// Contents structure of System Extension bundle
public struct BundleContents: Codable {
    /// Info.plist file path
    public let infoPlistPath: String
    
    /// Main executable path within bundle
    public let executablePath: String
    
    /// Entitlements file path (optional)
    public let entitlementsPath: String?
    
    /// Additional resource files
    public let resourceFiles: [String]
    
    /// Bundle directory structure validation
    public let isValid: Bool
    
    /// Bundle size in bytes
    public let bundleSize: Int64
    
    public init(
        infoPlistPath: String,
        executablePath: String,
        entitlementsPath: String? = nil,
        resourceFiles: [String] = [],
        isValid: Bool,
        bundleSize: Int64
    ) {
        self.infoPlistPath = infoPlistPath
        self.executablePath = executablePath
        self.entitlementsPath = entitlementsPath
        self.resourceFiles = resourceFiles
        self.isValid = isValid
        self.bundleSize = bundleSize
    }
}

/// Code signing certificate information
public struct CodeSigningCertificate: Codable {
    /// Certificate common name
    public let commonName: String
    
    /// Certificate type (development, distribution, etc.)
    public let certificateType: CertificateType
    
    /// Team identifier from certificate
    public let teamIdentifier: String
    
    /// Certificate SHA-1 fingerprint
    public let fingerprint: String
    
    /// Certificate expiration date
    public let expirationDate: Date
    
    /// Whether certificate is valid for System Extensions
    public let isValidForSystemExtensions: Bool
    
    /// Keychain location of certificate
    public let keychainPath: String?
    
    public init(
        commonName: String,
        certificateType: CertificateType,
        teamIdentifier: String,
        fingerprint: String,
        expirationDate: Date,
        isValidForSystemExtensions: Bool,
        keychainPath: String? = nil
    ) {
        self.commonName = commonName
        self.certificateType = certificateType
        self.teamIdentifier = teamIdentifier
        self.fingerprint = fingerprint
        self.expirationDate = expirationDate
        self.isValidForSystemExtensions = isValidForSystemExtensions
        self.keychainPath = keychainPath
    }
}

/// Types of code signing certificates
public enum CertificateType: String, Codable, CaseIterable {
    /// Apple Development certificate for local development
    case appleDevelopment = "apple_development"
    
    /// Apple Distribution certificate for App Store
    case appleDistribution = "apple_distribution"
    
    /// Developer ID Application certificate for outside App Store
    case developerIdApplication = "developer_id_application"
    
    /// Mac Developer certificate (legacy)
    case macDeveloper = "mac_developer"
    
    /// Mac App Distribution certificate (legacy)
    case macAppDistribution = "mac_app_distribution"
    
    /// Certificate type is unknown or not recognized
    case unknown = "unknown"
    
    /// User-readable description of certificate type
    public var displayName: String {
        switch self {
        case .appleDevelopment:
            return "Apple Development"
        case .appleDistribution:
            return "Apple Distribution"
        case .developerIdApplication:
            return "Developer ID Application"
        case .macDeveloper:
            return "Mac Developer"
        case .macAppDistribution:
            return "Mac App Distribution"
        case .unknown:
            return "Unknown"
        }
    }
    
    /// Whether this certificate type can be used for System Extensions
    public var supportsSystemExtensions: Bool {
        switch self {
        case .appleDevelopment, .appleDistribution, .developerIdApplication:
            return true
        case .macDeveloper, .macAppDistribution, .unknown:
            return false
        }
    }
}

/// Code signing information for a bundle
public struct CodeSigningInfo: Codable {
    /// Certificate used for signing
    public let certificate: CodeSigningCertificate
    
    /// Whether bundle is currently signed
    public let isSigned: Bool
    
    /// Signing timestamp
    public let signingTime: Date?
    
    /// Code signing flags used
    public let signingFlags: [String]
    
    /// Entitlements applied during signing
    public let appliedEntitlements: [String: Any]?
    
    /// Signing verification status
    public let verificationStatus: SigningVerificationStatus
    
    /// Any signing errors encountered
    public let signingErrors: [String]
    
    public init(
        certificate: CodeSigningCertificate,
        isSigned: Bool,
        signingTime: Date? = nil,
        signingFlags: [String] = [],
        appliedEntitlements: [String: Any]? = nil,
        verificationStatus: SigningVerificationStatus,
        signingErrors: [String] = []
    ) {
        self.certificate = certificate
        self.isSigned = isSigned
        self.signingTime = signingTime
        self.signingFlags = signingFlags
        self.appliedEntitlements = appliedEntitlements
        self.verificationStatus = verificationStatus
        self.signingErrors = signingErrors
    }
    
    // Custom Codable implementation to handle [String: Any] dictionary
    private enum CodingKeys: String, CodingKey {
        case certificate, isSigned, signingTime, signingFlags
        case verificationStatus, signingErrors
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(certificate, forKey: .certificate)
        try container.encode(isSigned, forKey: .isSigned)
        try container.encodeIfPresent(signingTime, forKey: .signingTime)
        try container.encode(signingFlags, forKey: .signingFlags)
        try container.encode(verificationStatus, forKey: .verificationStatus)
        try container.encode(signingErrors, forKey: .signingErrors)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        certificate = try container.decode(CodeSigningCertificate.self, forKey: .certificate)
        isSigned = try container.decode(Bool.self, forKey: .isSigned)
        signingTime = try container.decodeIfPresent(Date.self, forKey: .signingTime)
        signingFlags = try container.decode([String].self, forKey: .signingFlags)
        verificationStatus = try container.decode(SigningVerificationStatus.self, forKey: .verificationStatus)
        signingErrors = try container.decode([String].self, forKey: .signingErrors)
        appliedEntitlements = nil // Not persisted in Codable representation
    }
}

/// Code signing verification status
public enum SigningVerificationStatus: String, Codable, CaseIterable {
    /// Bundle signature is valid and verified
    case valid = "valid"
    
    /// Bundle signature is invalid
    case invalid = "invalid"
    
    /// Bundle is not signed
    case notSigned = "not_signed"
    
    /// Unable to verify signature
    case verificationFailed = "verification_failed"
    
    /// Certificate has expired
    case certificateExpired = "certificate_expired"
    
    /// Certificate is not trusted
    case certificateUntrusted = "certificate_untrusted"
    
    /// Signing process failed
    case signingFailed = "signing_failed"
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