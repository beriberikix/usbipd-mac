//
//  DevelopmentModeSupport.swift
//  USBIPDCore
//
//  Development mode support for System Extension testing and development
//  Provides utilities for detecting and working with systemextensionsctl developer mode
//

import Foundation
import Common

/// Development mode support utilities for System Extension development and testing
/// Provides detection of development mode status and specialized handling for development scenarios
public class DevelopmentModeSupport {
    
    // MARK: - Properties
    
    private let logger = Logger(config: LoggerConfig(level: .debug), subsystem: "com.usbipd.mac", category: "development-mode")
    
    /// Cached development mode status to avoid repeated system calls
    private var cachedDevelopmentModeStatus: Bool?
    private var cacheTimestamp: Date?
    private let cacheValidityDuration: TimeInterval = 30.0 // Cache for 30 seconds
    
    // MARK: - Public Interface
    
    /// Check if System Extension development mode is enabled
    /// - Returns: True if development mode is enabled, false otherwise
    public func isDevelopmentModeEnabled() -> Bool {
        // Check cache first
        if let cached = cachedDevelopmentModeStatus,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValidityDuration {
            logger.debug("Using cached development mode status", context: ["enabled": cached])
            return cached
        }
        
        // Query system for development mode status
        let enabled = querySystemExtensionDevelopmentMode()
        
        // Update cache
        cachedDevelopmentModeStatus = enabled
        cacheTimestamp = Date()
        
        logger.info("System Extension development mode status", context: ["enabled": enabled])
        return enabled
    }
    
    /// Get development mode status with detailed information
    /// - Returns: Development mode status information
    public func getDevelopmentModeStatus() -> DevelopmentModeStatus {
        let enabled = isDevelopmentModeEnabled()
        let canEnable = canEnableDevelopmentMode()
        let requiresReboot = checkIfRebootRequired()
        
        return DevelopmentModeStatus(
            enabled: enabled,
            canEnable: canEnable,
            requiresReboot: requiresReboot,
            enableCommand: "systemextensionsctl developer on",
            disableCommand: "systemextensionsctl developer off",
            statusCommand: "systemextensionsctl developer"
        )
    }
    
    /// Validate System Extension for development mode installation
    /// - Parameter bundlePath: Path to the System Extension bundle
    /// - Returns: Validation result with any development-specific issues
    public func validateForDevelopmentInstallation(bundlePath: String) -> DevelopmentValidationResult {
        logger.debug("Validating System Extension for development installation", context: ["bundlePath": bundlePath])
        
        var issues: [DevelopmentValidationIssue] = []
        var canProceed = true
        
        // Check if development mode is enabled
        if !isDevelopmentModeEnabled() {
            issues.append(.developmentModeDisabled)
            canProceed = false
        }
        
        // Check bundle exists
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            issues.append(.bundleNotFound(bundlePath))
            canProceed = false
            return DevelopmentValidationResult(canProceed: canProceed, issues: issues)
        }
        
        // Check bundle structure
        let bundleURL = URL(fileURLWithPath: bundlePath)
        if !isValidSystemExtensionBundle(at: bundleURL) {
            issues.append(.invalidBundleStructure)
            canProceed = false
        }
        
        // Check code signing status (warn for unsigned in development)
        let signingStatus = checkCodeSigningStatus(bundlePath: bundlePath)
        switch signingStatus {
        case .unsigned:
            issues.append(.unsignedBundle)
            // Don't fail - unsigned is OK in development mode
        case .invalidSignature:
            issues.append(.invalidSignature)
            // Still allow in development mode, but warn
        case .signed:
            // All good
            break
        }
        
        // Check entitlements
        if !hasRequiredEntitlements(bundlePath: bundlePath) {
            issues.append(.missingEntitlements)
            canProceed = false
        }
        
        logger.debug("Development validation completed", context: [
            "canProceed": canProceed,
            "issueCount": issues.count
        ])
        
        return DevelopmentValidationResult(canProceed: canProceed, issues: issues)
    }
    
    /// Get development-specific installation options
    /// - Returns: Installation options optimized for development
    public func getDevelopmentInstallationOptions() -> DevelopmentInstallationOptions {
        let developmentModeEnabled = isDevelopmentModeEnabled()
        
        return DevelopmentInstallationOptions(
            allowUnsignedBundles: developmentModeEnabled,
            skipUserApproval: false, // Still requires user approval even in development
            enableVerboseLogging: true,
            enableDebugging: true,
            timeoutInterval: 60.0, // Longer timeout for development
            retryCount: 3
        )
    }
    
    /// Handle development-specific errors with enhanced messaging
    /// - Parameter error: Original error from System Extension operation
    /// - Returns: Enhanced error with development-specific guidance
    public func enhanceErrorForDevelopment(_ error: Error) -> Error {
        logger.debug("Enhancing error for development context", context: ["originalError": error.localizedDescription])
        
        if let systemExtensionError = error as? SystemExtensionInstallationError {
            switch systemExtensionError {
            case .requiresApproval:
                return SystemExtensionInstallationError.internalError("""
                    System Extension requires user approval in development mode.
                    
                    Development Steps:
                    1. Check System Preferences > Security & Privacy > General
                    2. Look for "System Extension Blocked" notification
                    3. Click "Allow" to approve the extension
                    4. Development mode: \(isDevelopmentModeEnabled() ? "ENABLED" : "DISABLED")
                    
                    If development mode is disabled, enable it with:
                    sudo systemextensionsctl developer on
                    """)
                
            case .developmentModeDisabled:
                return SystemExtensionInstallationError.internalError("""
                    System Extension development mode is not enabled.
                    
                    To enable development mode:
                    1. Run: sudo systemextensionsctl developer on
                    2. Restart your Mac (required for development mode)
                    3. Retry System Extension installation
                    
                    Development mode allows:
                    • Installing unsigned System Extensions
                    • Loading extensions without notarization
                    • Enhanced debugging and logging
                    """)
                
            case .invalidCodeSignature(let reason):
                return SystemExtensionInstallationError.internalError("""
                    Code signature issue in development mode: \(reason)
                    
                    Development Options:
                    1. For testing: Use unsigned bundle (development mode allows this)
                    2. For distribution: Sign with valid developer certificate
                    3. Check signing: codesign -dv --verbose=4 /path/to/bundle
                    
                    Current development mode: \(isDevelopmentModeEnabled() ? "ENABLED" : "DISABLED")
                    """)
                
            default:
                break
            }
        }
        
        // For other errors, add development context
        if isDevelopmentModeEnabled() {
            let enhancedMessage = """
                \(error.localizedDescription)
                
                Development Mode Information:
                • Development mode is ENABLED
                • Check logs with: log show --predicate 'subsystem == "com.github.usbipd-mac"' --last 1h
                • Reset extensions if needed: sudo systemextensionsctl reset
                """
            return SystemExtensionInstallationError.internalError(enhancedMessage)
        } else {
            let enhancedMessage = """
                \(error.localizedDescription)
                
                Development Mode Information:
                • Development mode is DISABLED
                • Enable with: sudo systemextensionsctl developer on (requires reboot)
                • This may resolve installation issues for development/testing
                """
            return SystemExtensionInstallationError.internalError(enhancedMessage)
        }
        
        return error
    }
    
    // MARK: - Private Implementation
    
    private func querySystemExtensionDevelopmentMode() -> Bool {
        let task = Process()
        let pipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
        task.arguments = ["developer"]
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            logger.debug("systemextensionsctl developer output", context: ["output": output])
            
            // Parse output to determine if development mode is enabled
            // Output format: "Developer mode: enabled" or "Developer mode: disabled"
            return output.lowercased().contains("enabled")
        } catch {
            logger.error("Failed to query development mode status", context: ["error": error.localizedDescription])
            return false
        }
    }
    
    private func canEnableDevelopmentMode() -> Bool {
        // Check if we have the ability to run systemextensionsctl
        // This typically requires admin privileges
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["systemextensionsctl"]
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private func checkIfRebootRequired() -> Bool {
        // Check if a reboot is required for development mode changes
        // This could check for pending system extension operations or mode changes
        // For now, we'll use a simple heuristic
        return false // Simplified implementation
    }
    
    private func isValidSystemExtensionBundle(at bundleURL: URL) -> Bool {
        let contentsPath = bundleURL.appendingPathComponent("Contents")
        let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
        let macosPath = contentsPath.appendingPathComponent("MacOS")
        
        var isDirectory: ObjCBool = false
        
        // Check required directories and files exist
        guard FileManager.default.fileExists(atPath: contentsPath.path, isDirectory: &isDirectory) && isDirectory.boolValue,
              FileManager.default.fileExists(atPath: infoPlistPath.path),
              FileManager.default.fileExists(atPath: macosPath.path, isDirectory: &isDirectory) && isDirectory.boolValue else {
            return false
        }
        
        // Check Info.plist has required keys
        do {
            let plistData = try Data(contentsOf: infoPlistPath)
            let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
            
            guard let infoPlist = plist,
                  infoPlist["CFBundleIdentifier"] != nil,
                  infoPlist["NSExtension"] != nil else {
                return false
            }
            
            return true
        } catch {
            logger.error("Failed to validate bundle Info.plist", context: ["error": error.localizedDescription])
            return false
        }
    }
    
    private func checkCodeSigningStatus(bundlePath: String) -> CodeSigningStatus {
        let task = Process()
        let pipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", bundlePath]
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if task.terminationStatus == 0 {
                // Successfully verified - bundle is signed
                return .signed
            } else if output.contains("not signed") {
                return .unsigned
            } else {
                return .invalidSignature
            }
        } catch {
            logger.error("Failed to check code signing status", context: ["error": error.localizedDescription])
            return .unsigned
        }
    }
    
    private func hasRequiredEntitlements(bundlePath: String) -> Bool {
        let bundleURL = URL(fileURLWithPath: bundlePath)
        let entitlementsPath = bundleURL.appendingPathComponent("Contents")
                                        .appendingPathComponent("Resources")
                                        .appendingPathComponent("SystemExtension.entitlements")
        
        guard FileManager.default.fileExists(atPath: entitlementsPath.path) else {
            logger.debug("Entitlements file not found", context: ["path": entitlementsPath.path])
            return false
        }
        
        do {
            let entitlementsData = try Data(contentsOf: entitlementsPath)
            let entitlements = try PropertyListSerialization.propertyList(from: entitlementsData,
                                                                         options: [],
                                                                         format: nil) as? [String: Any]
            
            guard let plist = entitlements else {
                return false
            }
            
            // Check for required System Extension entitlements
            let hasInstallEntitlement = plist["com.apple.developer.system-extension.install"] as? Bool == true
            let hasDriverKitEntitlement = plist["com.apple.developer.driverkit"] as? Bool == true
            
            return hasInstallEntitlement && hasDriverKitEntitlement
        } catch {
            logger.error("Failed to validate entitlements", context: ["error": error.localizedDescription])
            return false
        }
    }
}

// MARK: - Supporting Types

/// Development mode status information
public struct DevelopmentModeStatus {
    public let enabled: Bool
    public let canEnable: Bool
    public let requiresReboot: Bool
    public let enableCommand: String
    public let disableCommand: String
    public let statusCommand: String
    
    public var statusMessage: String {
        if enabled {
            return "✅ System Extension development mode is ENABLED"
        } else {
            return "❌ System Extension development mode is DISABLED"
        }
    }
    
    public var enableInstructions: String {
        return """
            To enable System Extension development mode:
            1. Run: sudo \(enableCommand)
            2. Restart your Mac (required)
            3. Verify with: \(statusCommand)
            """
    }
}

/// Development validation result
public struct DevelopmentValidationResult {
    public let canProceed: Bool
    public let issues: [DevelopmentValidationIssue]
    
    public var hasWarnings: Bool {
        return issues.contains { $0.isWarning }
    }
    
    public var hasErrors: Bool {
        return issues.contains { !$0.isWarning }
    }
}

/// Development validation issues
public enum DevelopmentValidationIssue {
    case developmentModeDisabled
    case bundleNotFound(String)
    case invalidBundleStructure
    case unsignedBundle
    case invalidSignature
    case missingEntitlements
    
    public var isWarning: Bool {
        switch self {
        case .unsignedBundle:
            return true // Warning in development mode
        default:
            return false
        }
    }
    
    public var description: String {
        switch self {
        case .developmentModeDisabled:
            return "System Extension development mode is not enabled"
        case .bundleNotFound(let path):
            return "System Extension bundle not found at path: \(path)"
        case .invalidBundleStructure:
            return "System Extension bundle has invalid structure"
        case .unsignedBundle:
            return "System Extension bundle is unsigned (OK in development mode)"
        case .invalidSignature:
            return "System Extension bundle has invalid code signature"
        case .missingEntitlements:
            return "System Extension bundle missing required entitlements"
        }
    }
    
    public var suggestion: String {
        switch self {
        case .developmentModeDisabled:
            return "Run 'sudo systemextensionsctl developer on' and restart your Mac"
        case .bundleNotFound:
            return "Build the System Extension bundle first"
        case .invalidBundleStructure:
            return "Rebuild the System Extension bundle with correct structure"
        case .unsignedBundle:
            return "Sign the bundle for distribution, or use as-is for development testing"
        case .invalidSignature:
            return "Re-sign the bundle with a valid developer certificate"
        case .missingEntitlements:
            return "Add required entitlements to the bundle's entitlements file"
        }
    }
}

/// Development installation options
public struct DevelopmentInstallationOptions {
    public let allowUnsignedBundles: Bool
    public let skipUserApproval: Bool
    public let enableVerboseLogging: Bool
    public let enableDebugging: Bool
    public let timeoutInterval: TimeInterval
    public let retryCount: Int
}

/// Code signing status
private enum CodeSigningStatus {
    case signed
    case unsigned
    case invalidSignature
}