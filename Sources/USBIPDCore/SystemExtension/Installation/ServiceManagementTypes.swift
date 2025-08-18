// ServiceManagementTypes.swift
// Service management types and diagnostic structures

import Foundation

// MARK: - Service Integration Status

/// Status of service integration with launchd and brew services
public struct ServiceIntegrationStatus {
    /// Whether service is registered with launchd
    public let launchdRegistered: Bool
    
    /// Whether service is currently running
    public let serviceRunning: Bool
    
    /// Whether service is managed by brew services
    public let brewServicesManaged: Bool
    
    /// Number of orphaned processes detected
    public let orphanedProcesses: Int
    
    /// Last error encountered during service operations
    public let lastError: String?
    
    public init(
        launchdRegistered: Bool,
        serviceRunning: Bool,
        brewServicesManaged: Bool,
        orphanedProcesses: Int,
        lastError: String? = nil
    ) {
        self.launchdRegistered = launchdRegistered
        self.serviceRunning = serviceRunning
        self.brewServicesManaged = brewServicesManaged
        self.orphanedProcesses = orphanedProcesses
        self.lastError = lastError
    }
}

// MARK: - Service Issues

/// Specific service management problems that can occur
public enum ServiceIssue: Error, Equatable {
    /// Service is not registered with launchd
    case serviceNotRegistered
    
    /// Orphaned processes detected
    case orphanedProcesses
    
    /// Port conflicts detected
    case portConflicts
    
    /// Service failed to start
    case serviceStartFailed
    
    /// Service failed to stop
    case serviceStopFailed
    
    /// Service configuration is invalid
    case invalidConfiguration
    
    /// Permissions issue preventing service management
    case permissionsError
    
    /// Homebrew formula not found
    case homebrewFormulaNotFound
    
    /// Service dependencies missing
    case missingDependencies
    
    /// Service health check failed
    case healthCheckFailed
    
    // MARK: - Error Information
    
    /// User-friendly description of the service issue
    public var userDescription: String {
        switch self {
        case .serviceNotRegistered:
            return "Service is not registered with launchd"
        case .orphanedProcesses:
            return "Orphaned service processes detected"
        case .portConflicts:
            return "Port conflicts preventing service startup"
        case .serviceStartFailed:
            return "Service failed to start"
        case .serviceStopFailed:
            return "Service failed to stop"
        case .invalidConfiguration:
            return "Service configuration is invalid"
        case .permissionsError:
            return "Insufficient permissions for service management"
        case .homebrewFormulaNotFound:
            return "Homebrew formula not found"
        case .missingDependencies:
            return "Service dependencies are missing"
        case .healthCheckFailed:
            return "Service health check failed"
        }
    }
    
    /// Recommended recovery actions for the issue
    public var recoveryActions: [String] {
        switch self {
        case .serviceNotRegistered:
            return [
                "Register service with: sudo launchctl load <plist-path>",
                "Ensure service plist is in correct location",
                "Check plist syntax and permissions"
            ]
        case .orphanedProcesses:
            return [
                "Terminate orphaned processes manually",
                "Use service restart to clean up processes",
                "Check for stuck processes in Activity Monitor"
            ]
        case .portConflicts:
            return [
                "Check what process is using port 3240: lsof -i :3240",
                "Stop conflicting service",
                "Use different port in configuration"
            ]
        case .serviceStartFailed:
            return [
                "Check service logs for errors",
                "Verify service configuration",
                "Ensure all dependencies are available",
                "Check System Extension status"
            ]
        case .serviceStopFailed:
            return [
                "Try force stopping: sudo launchctl unload -w <plist>",
                "Terminate processes manually if needed",
                "Check for permission issues"
            ]
        case .invalidConfiguration:
            return [
                "Validate service plist syntax",
                "Check file paths in configuration",
                "Verify service executable exists",
                "Reinstall service configuration"
            ]
        case .permissionsError:
            return [
                "Run service commands with sudo",
                "Check file and directory permissions",
                "Verify user has admin privileges"
            ]
        case .homebrewFormulaNotFound:
            return [
                "Install usbipd-mac via Homebrew",
                "Update Homebrew: brew update",
                "Check formula availability: brew search usbipd-mac"
            ]
        case .missingDependencies:
            return [
                "Install missing system dependencies",
                "Reinstall usbipd-mac package",
                "Check System Extension installation"
            ]
        case .healthCheckFailed:
            return [
                "Check service logs for errors",
                "Restart the service",
                "Verify System Extension is loaded",
                "Run full diagnostic check"
            ]
        }
    }
}

// MARK: - Service Results

/// Result of service integration operation
public struct ServiceIntegrationResult {
    /// Whether the integration was successful
    public let success: Bool
    
    /// Current service integration status
    public let status: ServiceIntegrationStatus
    
    /// Issues encountered during integration
    public let issues: [ServiceIssue]
    
    /// Recommendations for resolving issues
    public let recommendations: [String]
    
    public init(
        success: Bool,
        status: ServiceIntegrationStatus,
        issues: [ServiceIssue] = [],
        recommendations: [String] = []
    ) {
        self.success = success
        self.status = status
        self.issues = issues
        self.recommendations = recommendations
    }
}

/// Result of service coordination operation
public struct ServiceCoordinationResult {
    /// Whether the coordination was successful
    public let success: Bool
    
    /// Coordination status details
    public let status: ServiceCoordinationStatus
    
    /// Issues encountered during coordination
    public let issues: [ServiceIssue]
    
    /// Warnings generated during coordination
    public let warnings: [String]
    
    public init(
        success: Bool,
        status: ServiceCoordinationStatus,
        issues: [ServiceIssue] = [],
        warnings: [String] = []
    ) {
        self.success = success
        self.status = status
        self.issues = issues
        self.warnings = warnings
    }
}

/// Result of service verification operation
public struct ServiceVerificationResult {
    /// Overall service health status
    public let overallHealth: ServiceHealth
    
    /// Individual validation checks performed
    public let validationChecks: [ServiceValidationCheck]
    
    /// Timestamp when verification was performed
    public let timestamp: Date
    
    public init(
        overallHealth: ServiceHealth,
        validationChecks: [ServiceValidationCheck],
        timestamp: Date
    ) {
        self.overallHealth = overallHealth
        self.validationChecks = validationChecks
        self.timestamp = timestamp
    }
}

/// Result of service operation (start/stop/restart)
public struct ServiceOperationResult {
    /// Whether the operation was successful
    public let success: Bool
    
    /// Output from the service operation
    public let output: String
    
    /// Error if operation failed
    public let error: Error?
    
    public init(
        success: Bool,
        output: String,
        error: Error? = nil
    ) {
        self.success = success
        self.output = output
        self.error = error
    }
}

// MARK: - Service Status Types

/// Detailed service status with comprehensive information
public struct DetailedServiceStatus {
    /// Whether service is currently running
    public let isRunning: Bool
    
    /// Whether service is managed by brew services
    public let isManagedByBrew: Bool
    
    /// Whether service is registered with launchd
    public let isRegisteredWithLaunchd: Bool
    
    /// Number of orphaned processes
    public let orphanedProcessCount: Int
    
    /// Whether there are port conflicts
    public let hasPortConflicts: Bool
    
    /// Last error encountered
    public let lastError: String?
    
    /// Detailed status information
    public let statusDetails: ServiceStatusDetails
    
    /// Convenience properties
    public var hasOrphanedProcesses: Bool { orphanedProcessCount > 0 }
    
    public init(
        isRunning: Bool,
        isManagedByBrew: Bool,
        isRegisteredWithLaunchd: Bool,
        orphanedProcessCount: Int,
        hasPortConflicts: Bool,
        lastError: String? = nil,
        statusDetails: ServiceStatusDetails
    ) {
        self.isRunning = isRunning
        self.isManagedByBrew = isManagedByBrew
        self.isRegisteredWithLaunchd = isRegisteredWithLaunchd
        self.orphanedProcessCount = orphanedProcessCount
        self.hasPortConflicts = hasPortConflicts
        self.lastError = lastError
        self.statusDetails = statusDetails
    }
}

/// Detailed status information from various sources
public struct ServiceStatusDetails {
    /// Output from launchctl command
    public let launchdOutput: String
    
    /// Output from brew services command
    public let brewServicesOutput: String
    
    /// List of orphaned processes
    public let orphanedProcesses: [OrphanedProcess]
    
    /// List of port conflicts
    public let portConflicts: [PortConflict]
    
    public init(
        launchdOutput: String,
        brewServicesOutput: String,
        orphanedProcesses: [OrphanedProcess],
        portConflicts: [PortConflict]
    ) {
        self.launchdOutput = launchdOutput
        self.brewServicesOutput = brewServicesOutput
        self.orphanedProcesses = orphanedProcesses
        self.portConflicts = portConflicts
    }
}

/// Service coordination status
public struct ServiceCoordinationStatus {
    /// Whether coordination was successful
    public let coordinationSuccessful: Bool
    
    /// Whether service was running before coordination
    public let serviceWasRunning: Bool
    
    /// Whether service restart is required
    public let serviceRestartRequired: Bool
    
    /// Whether cleanup was performed
    public let cleanupPerformed: Bool
    
    public init(
        coordinationSuccessful: Bool,
        serviceWasRunning: Bool,
        serviceRestartRequired: Bool,
        cleanupPerformed: Bool
    ) {
        self.coordinationSuccessful = coordinationSuccessful
        self.serviceWasRunning = serviceWasRunning
        self.serviceRestartRequired = serviceRestartRequired
        self.cleanupPerformed = cleanupPerformed
    }
}

// MARK: - Service Health

/// Overall service health status
public enum ServiceHealth: String, CaseIterable {
    /// Service is healthy and operating normally
    case healthy = "healthy"
    
    /// Service has minor issues but is functional
    case degraded = "degraded"
    
    /// Service has significant issues affecting functionality
    case unhealthy = "unhealthy"
    
    /// Service has critical issues and may not function
    case critical = "critical"
    
    /// Service health is unknown
    case unknown = "unknown"
}

// MARK: - Validation Types

/// Individual service validation check
public struct ServiceValidationCheck {
    /// Unique identifier for the check
    public let checkID: String
    
    /// Human-readable name of the check
    public let checkName: String
    
    /// Whether the check passed
    public let passed: Bool
    
    /// Description of the check result
    public let message: String
    
    /// Severity of the check result
    public let severity: ServiceValidationSeverity
    
    /// Additional details about the check
    public let details: String?
    
    public init(
        checkID: String,
        checkName: String,
        passed: Bool,
        message: String,
        severity: ServiceValidationSeverity,
        details: String? = nil
    ) {
        self.checkID = checkID
        self.checkName = checkName
        self.passed = passed
        self.message = message
        self.severity = severity
        self.details = details
    }
}

/// Validation check severity levels - using CheckSeverity from InstallationVerificationTypes
public typealias ServiceValidationSeverity = CheckSeverity

// MARK: - Process and Conflict Types

/// Information about an orphaned process
public struct OrphanedProcess {
    /// Process ID
    public let pid: Int
    
    /// Parent process ID
    public let ppid: Int
    
    /// Command line that started the process
    public let command: String
    
    public init(pid: Int, ppid: Int, command: String) {
        self.pid = pid
        self.ppid = ppid
        self.command = command
    }
}

/// Information about a port conflict
public struct PortConflict {
    /// Port number that has a conflict
    public let port: Int
    
    /// Process name using the port
    public let process: String
    
    /// Process ID using the port
    public let pid: String
    
    public init(port: Int, process: String, pid: String) {
        self.port = port
        self.process = process
        self.pid = pid
    }
}

/// Result of service conflict resolution
public struct ServiceConflictResolution {
    /// Number of processes terminated
    public let processesTerminated: Int
    
    /// List of failures during cleanup
    public let failures: [String]
    
    /// Whether cleanup was successful
    public let success: Bool
    
    public init(
        processesTerminated: Int,
        failures: [String],
        success: Bool
    ) {
        self.processesTerminated = processesTerminated
        self.failures = failures
        self.success = success
    }
}

// MARK: - Internal Status Types

/// Launchd registration status
internal struct LaunchdRegistrationStatus {
    /// Whether service is registered
    let isRegistered: Bool
    
    /// Registration information from launchctl
    let registrationInfo: String
    
    init(isRegistered: Bool, registrationInfo: String) {
        self.isRegistered = isRegistered
        self.registrationInfo = registrationInfo
    }
}

/// Brew services status
internal struct BrewServicesStatus {
    /// Whether brew services is available
    let isAvailable: Bool
    
    /// Whether the formula is managed by brew services
    let formulaManaged: Bool
    
    /// Output from brew services status
    let statusOutput: String
    
    init(isAvailable: Bool, formulaManaged: Bool = false, statusOutput: String) {
        self.isAvailable = isAvailable
        self.formulaManaged = formulaManaged
        self.statusOutput = statusOutput
    }
}

// MARK: - Integration Validation Types

/// Result of comprehensive service integration validation
public struct ServiceIntegrationValidationResult {
    /// Whether overall validation was successful
    public let overallSuccess: Bool
    
    /// Individual validation steps performed
    public let validationSteps: [ServiceValidationStep]
    
    /// Recommendations for resolving issues
    public let recommendations: [String]
    
    /// Timestamp when validation was performed
    public let timestamp: Date
    
    /// Summary of validation results
    public let summary: String
    
    public init(
        overallSuccess: Bool,
        validationSteps: [ServiceValidationStep],
        recommendations: [String],
        timestamp: Date,
        summary: String
    ) {
        self.overallSuccess = overallSuccess
        self.validationSteps = validationSteps
        self.recommendations = recommendations
        self.timestamp = timestamp
        self.summary = summary
    }
}

/// Individual validation step in service integration validation
public struct ServiceValidationStep {
    /// Name of the validation step
    public let stepName: String
    
    /// Unique identifier for the step
    public let stepID: String
    
    /// Whether the step was successful
    public let success: Bool
    
    /// Message describing the step result
    public let message: String
    
    /// Additional details about the step
    public let details: String?
    
    /// Issues found during this step
    public let issues: [ServiceIssue]
    
    public init(
        stepName: String,
        stepID: String,
        success: Bool,
        message: String,
        details: String? = nil,
        issues: [ServiceIssue] = []
    ) {
        self.stepName = stepName
        self.stepID = stepID
        self.success = success
        self.message = message
        self.details = details
        self.issues = issues
    }
}