// DeveloperModeDetector.swift
// Utility for detecting macOS System Extension developer mode status for Homebrew integration

import Foundation
import Common

/// Developer mode detection result with detailed information
public struct DeveloperModeDetectionResult {
    /// Whether developer mode is currently enabled
    public let isEnabled: Bool
    
    /// Whether developer mode can be enabled on this system
    public let canEnable: Bool
    
    /// Raw output from systemextensionsctl for debugging
    public let rawOutput: String
    
    /// Any error encountered during detection
    public let error: Error?
    
    /// Timestamp when detection was performed
    public let timestamp: Date
    
    /// Whether this result came from cache
    public let fromCache: Bool
    
    public init(
        isEnabled: Bool,
        canEnable: Bool = true,
        rawOutput: String = "",
        error: Error? = nil,
        timestamp: Date = Date(),
        fromCache: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.canEnable = canEnable
        self.rawOutput = rawOutput
        self.error = error
        self.timestamp = timestamp
        self.fromCache = fromCache
    }
}

/// Installation strategy recommendation based on developer mode status
public enum InstallationStrategy {
    case automatic    // Developer mode enabled, can use automatic installation
    case manual       // Developer mode disabled, requires manual installation
    case unavailable  // Cannot determine or install System Extensions on this system
    
    public var description: String {
        switch self {
        case .automatic:
            return "Automatic installation (developer mode enabled)"
        case .manual:
            return "Manual installation required (developer mode disabled)"
        case .unavailable:
            return "System Extension installation not available"
        }
    }
    
    public var requiresUserIntervention: Bool {
        switch self {
        case .automatic:
            return false
        case .manual, .unavailable:
            return true
        }
    }
}

/// Utility for detecting macOS System Extension developer mode status
/// Optimized for Homebrew integration with caching and error handling
public class DeveloperModeDetector {
    
    // MARK: - Properties
    
    private let logger: Logger
    private let fileManager = FileManager.default
    
    /// Cache for developer mode detection results
    private var cachedResult: DeveloperModeDetectionResult?
    private let cacheValidityDuration: TimeInterval = 60.0 // Cache for 1 minute
    
    /// Path to systemextensionsctl command
    private let systemExtensionsCtlPath = "/usr/bin/systemextensionsctl"
    
    // MARK: - Initialization
    
    /// Initialize developer mode detector with optional custom logger
    /// - Parameter logger: Custom logger instance (uses shared logger if nil)
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger.shared
    }
    
    // MARK: - Developer Mode Detection
    
    /// Detect current developer mode status with caching
    /// - Parameter forceRefresh: If true, bypass cache and query system directly
    /// - Returns: Developer mode detection result
    public func detectDeveloperMode(forceRefresh: Bool = false) -> DeveloperModeDetectionResult {
        // Check cache first (unless forced refresh)
        if !forceRefresh,
           let cached = cachedResult,
           Date().timeIntervalSince(cached.timestamp) < cacheValidityDuration {
            logger.debug("Using cached developer mode status", context: [
                "enabled": cached.isEnabled,
                "age": Date().timeIntervalSince(cached.timestamp)
            ])
            return DeveloperModeDetectionResult(
                isEnabled: cached.isEnabled,
                canEnable: cached.canEnable,
                rawOutput: cached.rawOutput,
                error: cached.error,
                timestamp: cached.timestamp,
                fromCache: true
            )
        }
        
        logger.debug("Detecting System Extension developer mode status")
        
        // Perform fresh detection
        let result = performDeveloperModeDetection()
        
        // Cache the result
        cachedResult = result
        
        logger.info("Developer mode detection completed", context: [
            "enabled": result.isEnabled,
            "canEnable": result.canEnable,
            "hasError": result.error != nil
        ])
        
        return result
    }
    
    /// Get installation strategy recommendation based on developer mode status
    /// - Returns: Recommended installation strategy
    public func getInstallationStrategy() -> InstallationStrategy {
        let result = detectDeveloperMode()
        
        if let error = result.error {
            logger.warning("Cannot determine installation strategy due to error", context: [
                "error": error.localizedDescription
            ])
            return .unavailable
        }
        
        if result.isEnabled {
            return .automatic
        } else if result.canEnable {
            return .manual
        } else {
            return .unavailable
        }
    }
    
    /// Check if automatic installation is possible
    /// - Returns: True if automatic installation can be attempted
    public func canUseAutomaticInstallation() -> Bool {
        let strategy = getInstallationStrategy()
        return strategy == .automatic
    }
    
    // MARK: - System Extension Control Wrapper
    
    /// Execute systemextensionsctl command with error handling
    /// - Parameter arguments: Arguments to pass to systemextensionsctl
    /// - Returns: Command output and exit status
    public func executeSystemExtensionsCtl(arguments: [String]) -> (output: String, exitStatus: Int32, error: Error?) {
        logger.debug("Executing systemextensionsctl", context: [
            "arguments": arguments.joined(separator: " ")
        ])
        
        guard fileManager.fileExists(atPath: systemExtensionsCtlPath) else {
            let error = DeveloperModeError.systemExtensionsCtlNotFound(systemExtensionsCtlPath)
            logger.error("systemextensionsctl not found", context: [
                "path": systemExtensionsCtlPath
            ])
            return ("", -1, error)
        }
        
        let task = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: systemExtensionsCtlPath)
        task.arguments = arguments
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            // Combine stdout and stderr for complete output
            let combinedOutput = [output, errorOutput].filter { !$0.isEmpty }.joined(separator: "\n")
            
            logger.debug("systemextensionsctl execution completed", context: [
                "exitStatus": task.terminationStatus,
                "outputLength": combinedOutput.count
            ])
            
            return (combinedOutput, task.terminationStatus, nil)
        } catch {
            logger.error("Failed to execute systemextensionsctl", context: [
                "error": error.localizedDescription
            ])
            return ("", -1, error)
        }
    }
    
    /// Parse developer mode status from systemextensionsctl output
    /// - Parameter output: Raw output from systemextensionsctl developer command
    /// - Returns: True if developer mode is enabled, false otherwise
    public func parseDeveloperModeStatus(from output: String) -> Bool {
        let normalizedOutput = output.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for various patterns that indicate enabled state
        let enabledPatterns = [
            "developer mode: enabled",
            "developer mode enabled",
            "development mode: enabled",
            "development mode enabled",
            "enabled"
        ]
        
        for pattern in enabledPatterns {
            if normalizedOutput.contains(pattern) {
                logger.debug("Found enabled pattern in output", context: [
                    "pattern": pattern
                ])
                return true
            }
        }
        
        // Check for disabled patterns
        let disabledPatterns = [
            "developer mode: disabled",
            "developer mode disabled",
            "development mode: disabled",
            "development mode disabled",
            "disabled"
        ]
        
        for pattern in disabledPatterns {
            if normalizedOutput.contains(pattern) {
                logger.debug("Found disabled pattern in output", context: [
                    "pattern": pattern
                ])
                return false
            }
        }
        
        logger.warning("Could not parse developer mode status from output", context: [
            "output": output
        ])
        return false
    }
    
    // MARK: - Validation and Status Parsing
    
    /// Validate that systemextensionsctl is available and functional
    /// - Returns: True if systemextensionsctl can be used
    public func validateSystemExtensionsCtlAvailability() -> Bool {
        let (_, exitStatus, error) = executeSystemExtensionsCtl(arguments: ["--help"])
        
        if let error = error {
            logger.error("systemextensionsctl validation failed", context: [
                "error": error.localizedDescription
            ])
            return false
        }
        
        // Help command should succeed (exit status 0) or show usage info (exit status 1)
        let isAvailable = exitStatus == 0 || exitStatus == 1
        
        logger.debug("systemextensionsctl availability check", context: [
            "available": isAvailable,
            "exitStatus": exitStatus
        ])
        
        return isAvailable
    }
    
    /// Get detailed status information including version and capabilities
    /// - Returns: Detailed status information
    public func getDetailedStatus() -> DetailedDeveloperModeStatus {
        let basicResult = detectDeveloperMode()
        let isCtlAvailable = validateSystemExtensionsCtlAvailability()
        
        return DetailedDeveloperModeStatus(
            detectionResult: basicResult,
            systemExtensionsCtlAvailable: isCtlAvailable,
            recommendedStrategy: getInstallationStrategy(),
            systemInfo: getSystemInfo()
        )
    }
    
    // MARK: - Private Implementation
    
    /// Perform the actual developer mode detection
    /// - Returns: Fresh detection result
    private func performDeveloperModeDetection() -> DeveloperModeDetectionResult {
        // First check if systemextensionsctl is available
        guard validateSystemExtensionsCtlAvailability() else {
            let error = DeveloperModeError.systemExtensionsCtlNotAvailable
            return DeveloperModeDetectionResult(
                isEnabled: false,
                canEnable: false,
                rawOutput: "",
                error: error
            )
        }
        
        // Execute developer mode query
        let (output, exitStatus, error) = executeSystemExtensionsCtl(arguments: ["developer"])
        
        if let error = error {
            return DeveloperModeDetectionResult(
                isEnabled: false,
                canEnable: true, // Assume we can enable unless proven otherwise
                rawOutput: output,
                error: error
            )
        }
        
        // Parse the output to determine status
        let isEnabled = parseDeveloperModeStatus(from: output)
        
        // Check if we can enable (based on command availability and admin privileges)
        let canEnable = exitStatus == 0 || isEnabled
        
        return DeveloperModeDetectionResult(
            isEnabled: isEnabled,
            canEnable: canEnable,
            rawOutput: output
        )
    }
    
    /// Get system information relevant to developer mode
    /// - Returns: System information dictionary
    private func getSystemInfo() -> [String: Any] {
        var info: [String: Any] = [:]
        
        // macOS version
        let version = ProcessInfo.processInfo.operatingSystemVersion
        info["macOSVersion"] = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        
        // Architecture
        info["architecture"] = ProcessInfo.processInfo.architecture
        
        // User privileges
        info["isRunningAsRoot"] = getuid() == 0
        info["effectiveUserID"] = getuid()
        
        // System Extension support
        info["systemExtensionsSupported"] = version.majorVersion >= 11 || (version.majorVersion == 10 && version.minorVersion >= 15)
        
        return info
    }
}

// MARK: - Supporting Types

/// Detailed developer mode status with comprehensive information
public struct DetailedDeveloperModeStatus {
    public let detectionResult: DeveloperModeDetectionResult
    public let systemExtensionsCtlAvailable: Bool
    public let recommendedStrategy: InstallationStrategy
    public let systemInfo: [String: Any]
    
    public var summary: String {
        var lines: [String] = []
        
        lines.append("System Extension Developer Mode Status")
        lines.append("====================================")
        lines.append("")
        
        if detectionResult.isEnabled {
            lines.append("✅ Developer mode: ENABLED")
        } else {
            lines.append("❌ Developer mode: DISABLED")
        }
        
        lines.append("🔧 systemextensionsctl: \(systemExtensionsCtlAvailable ? "Available" : "Not Available")")
        lines.append("📋 Strategy: \(recommendedStrategy.description)")
        
        if let macOSVersion = systemInfo["macOSVersion"] as? String {
            lines.append("💻 macOS: \(macOSVersion)")
        }
        
        if let error = detectionResult.error {
            lines.append("⚠️  Error: \(error.localizedDescription)")
        }
        
        if !detectionResult.isEnabled && detectionResult.canEnable {
            lines.append("")
            lines.append("To enable developer mode:")
            lines.append("  sudo systemextensionsctl developer on")
            lines.append("  # Restart required after enabling")
        }
        
        return lines.joined(separator: "\n")
    }
}

/// Developer mode detection errors
public enum DeveloperModeError: Error, LocalizedError {
    case systemExtensionsCtlNotFound(String)
    case systemExtensionsCtlNotAvailable
    case executionFailed(String)
    case invalidOutput(String)
    
    public var errorDescription: String? {
        switch self {
        case .systemExtensionsCtlNotFound(let path):
            return "systemextensionsctl not found at path: \(path)"
        case .systemExtensionsCtlNotAvailable:
            return "systemextensionsctl is not available or functional"
        case .executionFailed(let reason):
            return "Failed to execute systemextensionsctl: \(reason)"
        case .invalidOutput(let output):
            return "Invalid or unexpected output from systemextensionsctl: \(output)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .systemExtensionsCtlNotFound:
            return "Ensure you are running on macOS 10.15+ where systemextensionsctl is available"
        case .systemExtensionsCtlNotAvailable:
            return "Check macOS version and system integrity"
        case .executionFailed:
            return "Try running the command manually to diagnose the issue"
        case .invalidOutput:
            return "Update to a newer version of macOS or contact support"
        }
    }
}

// MARK: - Extensions

extension ProcessInfo {
    /// Get the current architecture string
    var architecture: String {
        var size: size_t = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        
        return String(cString: machine)
    }
}