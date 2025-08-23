import Foundation
import Common

// MARK: - Installation Verification Result

/// Comprehensive result of System Extension installation verification
public struct InstallationVerificationResult {
    /// Overall installation status
    public let status: VerificationInstallationStatus
    
    /// Individual verification checks performed
    public let verificationChecks: [VerificationCheck]
    
    /// Issues discovered during verification
    public let discoveredIssues: [VerificationInstallationIssue]
    
    /// Timestamp when verification was performed
    public let verificationTimestamp: Date
    
    /// Duration of verification process in seconds
    public let verificationDuration: TimeInterval
    
    /// Bundle identifier that was verified
    public let bundleIdentifier: String
    
    /// Human-readable summary of verification results
    public let summary: String
    
    public init(
        status: VerificationInstallationStatus,
        verificationChecks: [VerificationCheck],
        discoveredIssues: [VerificationInstallationIssue],
        verificationTimestamp: Date,
        verificationDuration: TimeInterval,
        bundleIdentifier: String,
        summary: String
    ) {
        self.status = status
        self.verificationChecks = verificationChecks
        self.discoveredIssues = discoveredIssues
        self.verificationTimestamp = verificationTimestamp
        self.verificationDuration = verificationDuration
        self.bundleIdentifier = bundleIdentifier
        self.summary = summary
    }
}

// MARK: - Installation Status

/// Overall functional status of System Extension installation
public enum VerificationInstallationStatus: String, CaseIterable {
    /// Extension is fully functional and operational
    case fullyFunctional = "fully_functional"
    
    /// Extension is mostly functional with minor issues
    case partiallyFunctional = "partially_functional"
    
    /// Extension has significant problems affecting functionality
    case problematic = "problematic"
    
    /// Extension installation has failed or is non-functional
    case failed = "failed"
    
    /// Status could not be determined
    case unknown = "unknown"
    
    /// Human-readable description of the status
    public var description: String {
        switch self {
        case .fullyFunctional:
            return "Fully Functional"
        case .partiallyFunctional:
            return "Partially Functional"
        case .problematic:
            return "Problematic"
        case .failed:
            return "Failed"
        case .unknown:
            return "Unknown"
        }
    }
    
    /// Indicates if the extension is considered operational
    public var isOperational: Bool {
        switch self {
        case .fullyFunctional, .partiallyFunctional:
            return true
        case .problematic, .failed, .unknown:
            return false
        }
    }
}

// MARK: - Verification Check

/// Result of an individual verification check
public struct VerificationCheck {
    /// Unique identifier for this check
    public let checkID: String
    
    /// Human-readable name of the check
    public let checkName: String
    
    /// Whether the check passed
    public let passed: Bool
    
    /// Message describing the check result
    public let message: String
    
    /// Severity level of any issues found
    public let severity: CheckSeverity
    
    /// Additional details about the check result
    public let details: String?
    
    /// Specific issues discovered during this check
    public let issues: [VerificationInstallationIssue]
    
    /// Timestamp when check was performed
    public let checkTimestamp: Date
    
    public init(
        checkID: String,
        checkName: String,
        passed: Bool,
        message: String,
        severity: CheckSeverity,
        details: String? = nil,
        issues: [VerificationInstallationIssue] = [],
        checkTimestamp: Date = Date()
    ) {
        self.checkID = checkID
        self.checkName = checkName
        self.passed = passed
        self.message = message
        self.severity = severity
        self.details = details
        self.issues = issues
        self.checkTimestamp = checkTimestamp
    }
}

// MARK: - Check Severity

/// Severity level for verification check results
public enum CheckSeverity: String, CaseIterable, Comparable {
    case info
    case warning
    case error
    case critical
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .info:
            return "Information"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        case .critical:
            return "Critical"
        }
    }
    
    /// Icon representation for display
    public var icon: String {
        switch self {
        case .info:
            return "ℹ️"
        case .warning:
            return "⚠️"
        case .error:
            return "❌"
        case .critical:
            return "🚨"
        }
    }
    
    public static func < (lhs: CheckSeverity, rhs: CheckSeverity) -> Bool {
        let order: [CheckSeverity] = [.info, .warning, .error, .critical]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

// MARK: - Installation Issue

/// Specific installation issues that can be detected and resolved
public enum VerificationInstallationIssue: String, CaseIterable, Hashable {
    // Bundle-related issues
    case bundleNotFound = "bundle_not_found"
    case bundleCorrupted = "bundle_corrupted"
    case bundleInvalidSignature = "bundle_invalid_signature"
    
    // Registration issues
    case extensionNotRegistered = "extension_not_registered"
    case extensionNotEnabled = "extension_not_enabled"
    case extensionNotActive = "extension_not_active"
    case registrationCheckFailed = "registration_check_failed"
    case activationCheckFailed = "activation_check_failed"
    
    // System issues
    case systemExtensionsCtlFailed = "systemextensionsctl_failed"
    case systemCommandFailed = "system_command_failed"
    case permissionDenied = "permission_denied"
    case incompatibleSystem = "incompatible_system"
    
    // Code signing and security
    case codeSigningInvalid = "code_signing_invalid"
    case developerModeRequired = "developer_mode_required"
    case sipCompatibilityIssue = "sip_compatibility_issue"
    
    // Service integration
    case serviceNotConfigured = "service_not_configured"
    case serviceNotRunning = "service_not_running"
    case communicationFailed = "communication_failed"
    case processNotRunning = "process_not_running"
    
    // Resource and performance
    case highResourceUsage = "high_resource_usage"
    case memoryIssues = "memory_issues"
    case dependenciesMissing = "dependencies_missing"
    
    /// Human-readable description of the issue
    public var description: String {
        switch self {
        case .bundleNotFound:
            return "System Extension bundle not found in expected locations"
        case .bundleCorrupted:
            return "System Extension bundle is corrupted or invalid"
        case .bundleInvalidSignature:
            return "System Extension bundle has invalid code signature"
        case .extensionNotRegistered:
            return "System Extension is not registered with macOS"
        case .extensionNotEnabled:
            return "System Extension is registered but not enabled"
        case .extensionNotActive:
            return "System Extension is enabled but not active"
        case .registrationCheckFailed:
            return "Failed to check System Extension registration status"
        case .activationCheckFailed:
            return "Failed to check System Extension activation status"
        case .systemExtensionsCtlFailed:
            return "systemextensionsctl command execution failed"
        case .systemCommandFailed:
            return "System command execution failed"
        case .permissionDenied:
            return "Insufficient permissions for System Extension operations"
        case .incompatibleSystem:
            return "System Extension is incompatible with this macOS version"
        case .codeSigningInvalid:
            return "Code signing validation failed"
        case .developerModeRequired:
            return "System Extension developer mode is required"
        case .sipCompatibilityIssue:
            return "System Integrity Protection compatibility issue"
        case .serviceNotConfigured:
            return "Associated service is not properly configured"
        case .serviceNotRunning:
            return "Associated service is not running"
        case .communicationFailed:
            return "Communication between service and extension failed"
        case .processNotRunning:
            return "System Extension process is not running"
        case .highResourceUsage:
            return "System Extension is using excessive system resources"
        case .memoryIssues:
            return "System Extension has memory-related issues"
        case .dependenciesMissing:
            return "Required dependencies are missing or incompatible"
        }
    }
    
    /// Suggested remediation actions
    public var remediation: String? {
        switch self {
        case .bundleNotFound:
            return "Reinstall the System Extension using the installer or Homebrew"
        case .bundleCorrupted:
            return "Download and reinstall the System Extension"
        case .bundleInvalidSignature:
            return "Reinstall with a properly signed version or enable developer mode"
        case .extensionNotRegistered:
            return "Run the installation command to register the System Extension"
        case .extensionNotEnabled:
            return "Enable the System Extension in System Preferences > Security & Privacy"
        case .extensionNotActive:
            return "Restart the system or manually activate the System Extension"
        case .registrationCheckFailed, .activationCheckFailed:
            return "Check system permissions and try running with administrator privileges"
        case .systemExtensionsCtlFailed, .systemCommandFailed:
            return "Ensure you have administrator privileges and systemextensionsctl is available"
        case .permissionDenied:
            return "Run with administrator privileges (sudo) or check System Preferences security settings"
        case .incompatibleSystem:
            return "Update to a compatible macOS version (10.15+ required)"
        case .codeSigningInvalid:
            return "Use a properly signed System Extension or enable developer mode"
        case .developerModeRequired:
            return "Enable System Extension developer mode: systemextensionsctl developer on"
        case .sipCompatibilityIssue:
            return "Use a properly signed extension or temporarily disable SIP for development"
        case .serviceNotConfigured:
            return "Configure the associated service using the appropriate configuration commands"
        case .serviceNotRunning:
            return "Start the associated service: brew services start usbip"
        case .communicationFailed:
            return "Restart both the service and System Extension"
        case .processNotRunning:
            return "Restart the System Extension or reboot the system"
        case .highResourceUsage:
            return "Monitor system resources and consider restarting the System Extension"
        case .memoryIssues:
            return "Restart the System Extension or increase available system memory"
        case .dependenciesMissing:
            return "Install missing dependencies using Homebrew or the system installer"
        }
    }
    
    /// Category of the issue for organization
    public var category: IssueCategory {
        switch self {
        case .bundleNotFound, .bundleCorrupted, .bundleInvalidSignature:
            return .bundle
        case .extensionNotRegistered, .extensionNotEnabled, .extensionNotActive,
             .registrationCheckFailed, .activationCheckFailed:
            return .registration
        case .systemExtensionsCtlFailed, .systemCommandFailed, .permissionDenied,
             .incompatibleSystem:
            return .system
        case .codeSigningInvalid, .developerModeRequired, .sipCompatibilityIssue:
            return .security
        case .serviceNotConfigured, .serviceNotRunning, .communicationFailed,
             .processNotRunning:
            return .service
        case .highResourceUsage, .memoryIssues, .dependenciesMissing:
            return .performance
        }
    }
    
    /// Suggested actions for resolving the issue
    public var suggestedActions: [String] {
        if let remediation = self.remediation {
            return [remediation]
        } else {
            return []
        }
    }
    
    /// Severity level of the issue
    public var severity: CheckSeverity {
        switch self {
        case .bundleNotFound, .extensionNotRegistered, .incompatibleSystem,
             .codeSigningInvalid, .systemExtensionsCtlFailed:
            return .critical
        case .bundleCorrupted, .extensionNotEnabled, .extensionNotActive,
             .permissionDenied, .serviceNotRunning, .processNotRunning:
            return .error
        case .bundleInvalidSignature, .registrationCheckFailed, .activationCheckFailed,
             .systemCommandFailed, .developerModeRequired, .serviceNotConfigured,
             .communicationFailed, .dependenciesMissing:
            return .warning
        case .sipCompatibilityIssue, .highResourceUsage, .memoryIssues:
            return .info
        }
    }
}

// MARK: - Issue Category

/// Categories for organizing installation issues
public enum IssueCategory: String, CaseIterable {
    case bundle
    case registration
    case system
    case security
    case service
    case performance
    
    public var description: String {
        switch self {
        case .bundle:
            return "Bundle & Files"
        case .registration:
            return "System Extension Registration"
        case .system:
            return "System Compatibility"
        case .security:
            return "Security & Code Signing"
        case .service:
            return "Service Integration"
        case .performance:
            return "Performance & Resources"
        }
    }
}

// MARK: - Detected Installation Issue

/// Detailed information about a detected installation issue
public struct DetectedInstallationIssue {
    /// The specific issue that was detected
    public let issue: VerificationInstallationIssue
    
    /// Severity level of the issue
    public let severity: CheckSeverity
    
    /// Detailed description of the issue in this context
    public let description: String
    
    /// Method used to detect this issue
    public let detectionMethod: String
    
    /// Components affected by this issue
    public let affectedComponents: [String]
    
    /// Suggested actions to resolve the issue
    public let suggestedActions: [String]
    
    /// Timestamp when issue was detected
    public let detectionTimestamp: Date
    
    /// Additional context data for the issue
    public let contextData: [String: String]
    
    public init(
        issue: VerificationInstallationIssue,
        severity: CheckSeverity,
        description: String,
        detectionMethod: String,
        affectedComponents: [String],
        suggestedActions: [String],
        detectionTimestamp: Date = Date(),
        contextData: [String: String] = [:]
    ) {
        self.issue = issue
        self.severity = severity
        self.description = description
        self.detectionMethod = detectionMethod
        self.affectedComponents = affectedComponents
        self.suggestedActions = suggestedActions
        self.detectionTimestamp = detectionTimestamp
        self.contextData = contextData
    }
}

// MARK: - Diagnostic Report

/// Comprehensive diagnostic report for System Extension installation
public struct InstallationDiagnosticReport {
    /// Main verification result
    public let verificationResult: InstallationVerificationResult
    
    /// System information at time of diagnosis
    public let systemInformation: SystemInformation
    
    /// Relevant system logs
    public let systemLogs: [SystemLogEntry]
    
    /// Analysis of system configuration
    public let configurationAnalysis: ConfigurationAnalysis
    
    /// Recommended actions based on findings
    public let recommendations: [String]
    
    /// Timestamp when report was generated
    public let reportTimestamp: Date
    
    /// Version of diagnostic report format
    public let reportVersion: String
    
    public init(
        verificationResult: InstallationVerificationResult,
        systemInformation: SystemInformation,
        systemLogs: [SystemLogEntry],
        configurationAnalysis: ConfigurationAnalysis,
        recommendations: [String],
        reportTimestamp: Date,
        reportVersion: String
    ) {
        self.verificationResult = verificationResult
        self.systemInformation = systemInformation
        self.systemLogs = systemLogs
        self.configurationAnalysis = configurationAnalysis
        self.recommendations = recommendations
        self.reportTimestamp = reportTimestamp
        self.reportVersion = reportVersion
    }
}

// MARK: - System Information

/// System information relevant to System Extension installation
public struct SystemInformation {
    /// macOS version string
    public let osVersion: String
    
    /// System architecture (arm64, x86_64, etc.)
    public let architecture: String
    
    /// Whether System Integrity Protection is enabled
    public let sipEnabled: Bool
    
    /// Whether developer mode is enabled for System Extensions
    public let developerModeEnabled: Bool
    
    /// Homebrew installation prefix
    public let homebrewPrefix: String
    
    /// Timestamp when information was gathered
    public let timestamp: Date
    
    public init(
        osVersion: String,
        architecture: String,
        sipEnabled: Bool,
        developerModeEnabled: Bool,
        homebrewPrefix: String,
        timestamp: Date
    ) {
        self.osVersion = osVersion
        self.architecture = architecture
        self.sipEnabled = sipEnabled
        self.developerModeEnabled = developerModeEnabled
        self.homebrewPrefix = homebrewPrefix
        self.timestamp = timestamp
    }
}

// MARK: - System Log Entry

/// System log entry relevant to System Extension diagnosis
public struct SystemLogEntry {
    /// Timestamp of log entry
    public let timestamp: Date
    
    /// Log level/severity
    public let level: VerificationLogLevel
    
    /// Source component that generated the log
    public let source: String
    
    /// Log message content
    public let message: String
    
    /// Category or subsystem of the log
    public let category: String?
    
    public init(
        timestamp: Date,
        level: VerificationLogLevel,
        source: String,
        message: String,
        category: String? = nil
    ) {
        self.timestamp = timestamp
        self.level = level
        self.source = source
        self.message = message
        self.category = category
    }
}

// MARK: - Log Level

/// Log severity levels - using Common.LogLevel
public typealias VerificationLogLevel = Common.LogLevel

/// Backup log levels if Common.LogLevel is not available
public enum VerificationLogLevelBackup: String, CaseIterable {
    case debug
    case info
    case warning
    case error
    case critical
}

// MARK: - Configuration Analysis

/// Analysis of system configuration relevant to System Extension
public struct ConfigurationAnalysis {
    /// Whether Homebrew is installed and accessible
    public let homebrewInstalled: Bool
    
    /// Whether Xcode or command line tools are installed
    public let xcodeInstalled: Bool
    
    /// Whether System Extension directory structure exists
    public let systemExtensionDirectoryExists: Bool
    
    /// Expected installation path that was found
    public let expectedInstallationPath: String?
    
    /// Overall configuration validity
    public let configurationValid: Bool
    
    /// Additional configuration notes
    public let notes: [String]
    
    public init(
        homebrewInstalled: Bool,
        xcodeInstalled: Bool,
        systemExtensionDirectoryExists: Bool,
        expectedInstallationPath: String? = nil,
        configurationValid: Bool,
        notes: [String] = []
    ) {
        self.homebrewInstalled = homebrewInstalled
        self.xcodeInstalled = xcodeInstalled
        self.systemExtensionDirectoryExists = systemExtensionDirectoryExists
        self.expectedInstallationPath = expectedInstallationPath
        self.configurationValid = configurationValid
        self.notes = notes
    }
}

// MARK: - Functionality Verification

/// Result of functional verification tests
public struct FunctionalVerificationResult {
    /// Whether the System Extension is functionally operational
    public let isFunctional: Bool
    
    /// Individual functionality checks performed
    public let functionalityChecks: [FunctionalityCheck]
    
    /// Timestamp when verification was performed
    public let verificationTimestamp: Date
    
    public init(
        isFunctional: Bool,
        functionalityChecks: [FunctionalityCheck],
        verificationTimestamp: Date
    ) {
        self.isFunctional = isFunctional
        self.functionalityChecks = functionalityChecks
        self.verificationTimestamp = verificationTimestamp
    }
}

// MARK: - Functionality Check

/// Individual functionality test result
public struct FunctionalityCheck {
    /// Name of the functionality being tested
    public let checkName: String
    
    /// Whether the functionality check passed
    public let passed: Bool
    
    /// Message describing the test result
    public let message: String
    
    /// Additional details about the test
    public let details: String?
    
    /// Timestamp when check was performed
    public let checkTimestamp: Date
    
    public init(
        checkName: String,
        passed: Bool,
        message: String,
        details: String? = nil,
        checkTimestamp: Date = Date()
    ) {
        self.checkName = checkName
        self.passed = passed
        self.message = message
        self.details = details
        self.checkTimestamp = checkTimestamp
    }
}