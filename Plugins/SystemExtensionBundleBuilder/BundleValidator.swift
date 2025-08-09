//
//  BundleValidator.swift
//  SystemExtensionBundleBuilder
//
//  System Extension bundle validation for build-time verification
//  Ensures generated bundles meet all System Extension requirements
//

import Foundation
import PackagePlugin

/// System Extension bundle validator
/// Validates bundle structure, metadata, and compliance with System Extension requirements
struct BundleValidator {
    
    // MARK: - Validation Results
    
    struct ValidationResult {
        let isValid: Bool
        let errors: [ValidationError]
        let warnings: [ValidationWarning]
        
        var hasErrors: Bool { !errors.isEmpty }
        var hasWarnings: Bool { !warnings.isEmpty }
    }
    
    enum ValidationError: Error, CustomStringConvertible {
        case bundleNotFound(String)
        case invalidBundleStructure(String)
        case missingInfoPlist
        case invalidInfoPlist(String)
        case missingExecutable(String)
        case invalidExecutablePermissions(String)
        case missingEntitlements
        case invalidEntitlements(String)
        case missingRequiredKey(String, String)
        case invalidBundleIdentifier(String)
        case incompatibleExtensionPoint(String)
        
        var description: String {
            switch self {
            case .bundleNotFound(let path):
                return "Bundle not found at path: \(path)"
            case .invalidBundleStructure(let reason):
                return "Invalid bundle structure: \(reason)"
            case .missingInfoPlist:
                return "Missing Info.plist file"
            case .invalidInfoPlist(let reason):
                return "Invalid Info.plist: \(reason)"
            case .missingExecutable(let name):
                return "Missing executable: \(name)"
            case .invalidExecutablePermissions(let path):
                return "Invalid executable permissions: \(path)"
            case .missingEntitlements:
                return "Missing entitlements file"
            case .invalidEntitlements(let reason):
                return "Invalid entitlements: \(reason)"
            case .missingRequiredKey(let key, let file):
                return "Missing required key '\(key)' in \(file)"
            case .invalidBundleIdentifier(let identifier):
                return "Invalid bundle identifier: \(identifier)"
            case .incompatibleExtensionPoint(let point):
                return "Incompatible extension point: \(point)"
            }
        }
    }
    
    enum ValidationWarning: CustomStringConvertible {
        case unsignedBundle
        case developmentCertificate
        case missingOptionalKey(String, String)
        case unusualBundleVersion(String)
        case largeExecutableSize(Int)
        
        var description: String {
            switch self {
            case .unsignedBundle:
                return "Bundle is not code signed (OK for development)"
            case .developmentCertificate:
                return "Bundle uses development certificate"
            case .missingOptionalKey(let key, let file):
                return "Missing optional key '\(key)' in \(file)"
            case .unusualBundleVersion(let version):
                return "Unusual bundle version format: \(version)"
            case .largeExecutableSize(let size):
                return "Large executable size: \(size) bytes"
            }
        }
    }
    
    // MARK: - Validation Interface
    
    /// Validate a System Extension bundle
    /// - Parameter bundlePath: Path to the .systemextension bundle
    /// - Returns: Validation result with errors and warnings
    static func validateBundle(at bundlePath: String) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        let bundleURL = URL(fileURLWithPath: bundlePath)
        
        // Check bundle exists
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            errors.append(.bundleNotFound(bundlePath))
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }
        
        // Validate bundle structure
        let structureResult = validateBundleStructure(bundleURL: bundleURL)
        errors.append(contentsOf: structureResult.errors)
        warnings.append(contentsOf: structureResult.warnings)
        
        // If structure is invalid, can't continue with detailed validation
        guard structureResult.isValid else {
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }
        
        // Validate Info.plist
        let infoPlistResult = validateInfoPlist(bundleURL: bundleURL)
        errors.append(contentsOf: infoPlistResult.errors)
        warnings.append(contentsOf: infoPlistResult.warnings)
        
        // Validate executable
        let executableResult = validateExecutable(bundleURL: bundleURL)
        errors.append(contentsOf: executableResult.errors)
        warnings.append(contentsOf: executableResult.warnings)
        
        // Validate entitlements
        let entitlementsResult = validateEntitlements(bundleURL: bundleURL)
        errors.append(contentsOf: entitlementsResult.errors)
        warnings.append(contentsOf: entitlementsResult.warnings)
        
        // Validate code signing
        let signingResult = validateCodeSigning(bundleURL: bundleURL)
        errors.append(contentsOf: signingResult.errors)
        warnings.append(contentsOf: signingResult.warnings)
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
    
    // MARK: - Detailed Validation Methods
    
    private static func validateBundleStructure(bundleURL: URL) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        // Check required directories
        let contentsDir = bundleURL.appendingPathComponent("Contents")
        let macosDir = contentsDir.appendingPathComponent("MacOS")
        let resourcesDir = contentsDir.appendingPathComponent("Resources")
        
        var isDirectory: ObjCBool = false
        
        // Contents directory
        guard FileManager.default.fileExists(atPath: contentsDir.path, isDirectory: &isDirectory) && isDirectory.boolValue else {
            errors.append(.invalidBundleStructure("Missing Contents directory"))
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }
        
        // MacOS directory
        guard FileManager.default.fileExists(atPath: macosDir.path, isDirectory: &isDirectory) && isDirectory.boolValue else {
            errors.append(.invalidBundleStructure("Missing Contents/MacOS directory"))
        }
        
        // Resources directory (optional but recommended)
        if !FileManager.default.fileExists(atPath: resourcesDir.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            warnings.append(.missingOptionalKey("Contents/Resources", "bundle structure"))
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    private static func validateInfoPlist(bundleURL: URL) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        let infoPlistPath = bundleURL.appendingPathComponent("Contents/Info.plist")
        
        // Check Info.plist exists
        guard FileManager.default.fileExists(atPath: infoPlistPath.path) else {
            errors.append(.missingInfoPlist)
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }
        
        // Load and parse Info.plist
        do {
            let infoPlistData = try Data(contentsOf: infoPlistPath)
            let infoPlist = try PropertyListSerialization.propertyList(from: infoPlistData, options: [], format: nil) as? [String: Any]
            
            guard let plist = infoPlist else {
                errors.append(.invalidInfoPlist("Could not parse Info.plist as dictionary"))
                return ValidationResult(isValid: false, errors: errors, warnings: warnings)
            }
            
            // Validate required keys
            let requiredKeys = [
                "CFBundleIdentifier",
                "CFBundleName",
                "CFBundleVersion",
                "CFBundleShortVersionString",
                "CFBundleExecutable",
                "NSExtension"
            ]
            
            for key in requiredKeys {
                guard plist[key] != nil else {
                    errors.append(.missingRequiredKey(key, "Info.plist"))
                    continue
                }
            }
            
            // Validate bundle identifier format
            if let bundleIdentifier = plist["CFBundleIdentifier"] as? String {
                if !isValidBundleIdentifier(bundleIdentifier) {
                    errors.append(.invalidBundleIdentifier(bundleIdentifier))
                }
            }
            
            // Validate NSExtension configuration
            if let nsExtension = plist["NSExtension"] as? [String: Any] {
                // Check extension point
                if let extensionPoint = nsExtension["NSExtensionPointIdentifier"] as? String {
                    if extensionPoint != "com.apple.system-extension.driver-extension" {
                        errors.append(.incompatibleExtensionPoint(extensionPoint))
                    }
                } else {
                    errors.append(.missingRequiredKey("NSExtensionPointIdentifier", "NSExtension"))
                }
                
                // Check principal class (optional but recommended)
                if nsExtension["NSExtensionPrincipalClass"] == nil {
                    warnings.append(.missingOptionalKey("NSExtensionPrincipalClass", "NSExtension"))
                }
            }
            
            // Validate version formats
            if let version = plist["CFBundleVersion"] as? String {
                if !isValidVersionString(version) {
                    warnings.append(.unusualBundleVersion(version))
                }
            }
            
            if let shortVersion = plist["CFBundleShortVersionString"] as? String {
                if !isValidVersionString(shortVersion) {
                    warnings.append(.unusualBundleVersion(shortVersion))
                }
            }
            
        } catch {
            errors.append(.invalidInfoPlist("Failed to read Info.plist: \(error.localizedDescription)"))
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    private static func validateExecutable(bundleURL: URL) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        // Get executable name from Info.plist
        let infoPlistPath = bundleURL.appendingPathComponent("Contents/Info.plist")
        var executableName = "SystemExtension" // Default fallback
        
        if let infoPlistData = try? Data(contentsOf: infoPlistPath),
           let infoPlist = try? PropertyListSerialization.propertyList(from: infoPlistData, options: [], format: nil) as? [String: Any],
           let bundleExecutable = infoPlist["CFBundleExecutable"] as? String {
            executableName = bundleExecutable
        }
        
        let executablePath = bundleURL.appendingPathComponent("Contents/MacOS/\(executableName)")
        
        // Check executable exists
        guard FileManager.default.fileExists(atPath: executablePath.path) else {
            errors.append(.missingExecutable(executableName))
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }
        
        // Check executable permissions
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: executablePath.path)
            if let permissions = attributes[.posixPermissions] as? NSNumber {
                let permissionValue = permissions.uint16Value
                if (permissionValue & 0o111) == 0 {
                    errors.append(.invalidExecutablePermissions("Executable is not executable"))
                }
            }
            
            // Check executable size
            if let fileSize = attributes[.size] as? NSNumber {
                let sizeInBytes = fileSize.intValue
                if sizeInBytes > 50 * 1024 * 1024 { // Warn if larger than 50MB
                    warnings.append(.largeExecutableSize(sizeInBytes))
                }
            }
        } catch {
            errors.append(.invalidExecutablePermissions("Could not check executable permissions: \(error.localizedDescription)"))
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    private static func validateEntitlements(bundleURL: URL) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        let entitlementsPath = bundleURL.appendingPathComponent("Contents/Resources/SystemExtension.entitlements")
        
        // Check entitlements file exists
        guard FileManager.default.fileExists(atPath: entitlementsPath.path) else {
            errors.append(.missingEntitlements)
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }
        
        // Load and validate entitlements
        do {
            let entitlementsData = try Data(contentsOf: entitlementsPath)
            let entitlements = try PropertyListSerialization.propertyList(from: entitlementsData, options: [], format: nil) as? [String: Any]
            
            guard let plist = entitlements else {
                errors.append(.invalidEntitlements("Could not parse entitlements as dictionary"))
                return ValidationResult(isValid: false, errors: errors, warnings: warnings)
            }
            
            // Check required entitlements
            let requiredEntitlements = [
                "com.apple.developer.system-extension.install",
                "com.apple.developer.driverkit"
            ]
            
            for entitlement in requiredEntitlements {
                if plist[entitlement] as? Bool != true {
                    errors.append(.missingRequiredKey(entitlement, "entitlements"))
                }
            }
            
            // Check recommended entitlements
            let recommendedEntitlements = [
                "com.apple.developer.driverkit.transport.usb"
            ]
            
            for entitlement in recommendedEntitlements {
                if plist[entitlement] == nil {
                    warnings.append(.missingOptionalKey(entitlement, "entitlements"))
                }
            }
            
        } catch {
            errors.append(.invalidEntitlements("Failed to read entitlements: \(error.localizedDescription)"))
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    private static func validateCodeSigning(bundleURL: URL) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []
        
        // Check code signing using codesign tool
        let task = Process()
        let pipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", bundleURL.path]
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if task.terminationStatus == 0 {
                // Bundle is signed, check if it's a development certificate
                if output.contains("Developer ID") {
                    // Production certificate - all good
                } else if output.contains("Mac Developer") || output.contains("iPhone Developer") {
                    warnings.append(.developmentCertificate)
                }
            } else if output.contains("not signed") {
                warnings.append(.unsignedBundle)
            } else {
                // Some other signing issue - this might be an error in production
                warnings.append(.unsignedBundle) // Treat as warning for now
            }
        } catch {
            // Could not run codesign - treat as warning
            warnings.append(.unsignedBundle)
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    // MARK: - Helper Methods
    
    private static func isValidBundleIdentifier(_ identifier: String) -> Bool {
        // Bundle identifier should be reverse domain notation
        let components = identifier.split(separator: ".")
        guard components.count >= 2 else { return false }
        
        // Each component should be valid
        for component in components {
            if component.isEmpty { return false }
            if !component.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
                return false
            }
        }
        
        return true
    }
    
    private static func isValidVersionString(_ version: String) -> Bool {
        // Version should be in format like "1.0.0" or "1.0"
        let components = version.split(separator: ".")
        guard !components.isEmpty && components.count <= 4 else { return false }
        
        for component in components {
            if component.isEmpty { return false }
            if !component.allSatisfy({ $0.isNumber }) { return false }
        }
        
        return true
    }
}

// MARK: - Build Plugin Integration

extension BundleValidator {
    
    /// Validate bundle as part of build process
    /// - Parameters:
    ///   - bundlePath: Path to the bundle to validate
    ///   - context: Build context for diagnostics
    ///   - target: Target being built
    /// - Throws: ValidationError if bundle is invalid
    static func validateForBuild(bundlePath: String, context: PluginContext, target: Target) throws {
        let result = validateBundle(at: bundlePath)
        
        // Report warnings
        for warning in result.warnings {
            Diagnostics.warning(warning.description, file: nil, line: nil)
        }
        
        // Report errors and throw if any
        for error in result.errors {
            Diagnostics.error(error.description, file: nil, line: nil)
        }
        
        if result.hasErrors {
            throw ValidationError.invalidBundleStructure("Bundle validation failed with \(result.errors.count) errors")
        }
        
        // Success message
        if !result.hasWarnings {
            print("✅ System Extension bundle validation passed")
        } else {
            print("⚠️  System Extension bundle validation passed with \(result.warnings.count) warnings")
        }
    }
    
    /// Generate validation summary for logging
    /// - Parameter result: Validation result
    /// - Returns: Human-readable summary
    static func generateSummary(_ result: ValidationResult) -> String {
        var summary = ""
        
        if result.isValid {
            summary += "✅ Bundle validation PASSED"
        } else {
            summary += "❌ Bundle validation FAILED"
        }
        
        if result.hasErrors {
            summary += " (\(result.errors.count) errors"
            if result.hasWarnings {
                summary += ", \(result.warnings.count) warnings)"
            } else {
                summary += ")"
            }
        } else if result.hasWarnings {
            summary += " (\(result.warnings.count) warnings)"
        }
        
        // Add detailed error/warning information
        if result.hasErrors {
            summary += "\n\nErrors:"
            for (index, error) in result.errors.enumerated() {
                summary += "\n  \(index + 1). \(error.description)"
            }
        }
        
        if result.hasWarnings {
            summary += "\n\nWarnings:"
            for (index, warning) in result.warnings.enumerated() {
                summary += "\n  \(index + 1). \(warning.description)"
            }
        }
        
        return summary
    }
}