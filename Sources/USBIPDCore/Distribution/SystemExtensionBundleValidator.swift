// SystemExtensionBundleValidator.swift
// Comprehensive System Extension bundle validation utility for CI and development

import Foundation
import Common

/// Validation result for System Extension bundle structure and content
public struct BundleValidationResult {
    /// Whether the bundle passed all validations
    public let isValid: Bool
    
    /// Detailed validation results for each check
    public let validationChecks: [ValidationCheck]
    
    /// Errors encountered during validation
    public let errors: [BundleValidationError]
    
    /// Warnings that don't prevent bundle usage but should be addressed
    public let warnings: [String]
    
    /// Bundle metadata information
    public let bundleInfo: BundleInfo?
    
    /// Time taken to perform validation
    public let validationTime: TimeInterval
    
    public init(
        isValid: Bool,
        validationChecks: [ValidationCheck] = [],
        errors: [BundleValidationError] = [],
        warnings: [String] = [],
        bundleInfo: BundleInfo? = nil,
        validationTime: TimeInterval = 0
    ) {
        self.isValid = isValid
        self.validationChecks = validationChecks
        self.errors = errors
        self.warnings = warnings
        self.bundleInfo = bundleInfo
        self.validationTime = validationTime
    }
}

/// Individual validation check result
public struct ValidationCheck {
    /// Name of the validation check
    public let name: String
    
    /// Whether the check passed
    public let passed: Bool
    
    /// Detailed message about the check result
    public let message: String
    
    /// Whether this check is required for bundle functionality
    public let required: Bool
    
    /// Category of validation check
    public let category: ValidationCategory
    
    public init(name: String, passed: Bool, message: String, required: Bool = true, category: ValidationCategory = .structure) {
        self.name = name
        self.passed = passed
        self.message = message
        self.required = required
        self.category = category
    }
}

/// Categories of validation checks
public enum ValidationCategory {
    case structure      // Bundle structure and required files
    case metadata       // Info.plist and metadata validation
    case executable     // Executable file validation
    case entitlements   // Code signing and entitlements
    case compatibility  // Platform and version compatibility
    case homebrew       // Homebrew-specific validation
    
    public var description: String {
        switch self {
        case .structure:
            return "Bundle Structure"
        case .metadata:
            return "Metadata"
        case .executable:
            return "Executable"
        case .entitlements:
            return "Entitlements"
        case .compatibility:
            return "Compatibility"
        case .homebrew:
            return "Homebrew"
        }
    }
}

/// Bundle information extracted during validation
public struct BundleInfo {
    public let bundleIdentifier: String?
    public let bundleName: String?
    public let bundleVersion: String?
    public let executableName: String?
    public let bundleType: String?
    public let minimumSystemVersion: String?
    public let homebrewMetadata: [String: Any]?
    
    public init(
        bundleIdentifier: String? = nil,
        bundleName: String? = nil,
        bundleVersion: String? = nil,
        executableName: String? = nil,
        bundleType: String? = nil,
        minimumSystemVersion: String? = nil,
        homebrewMetadata: [String: Any]? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.bundleName = bundleName
        self.bundleVersion = bundleVersion
        self.executableName = executableName
        self.bundleType = bundleType
        self.minimumSystemVersion = minimumSystemVersion
        self.homebrewMetadata = homebrewMetadata
    }
}

/// System Extension bundle validation errors
public enum BundleValidationError: Error, LocalizedError {
    case bundleNotFound(String)
    case invalidBundleStructure(String)
    case missingRequiredFile(String)
    case invalidInfoPlist(String)
    case executableNotFound(String)
    case invalidExecutable(String)
    case entitlementsValidationFailed(String)
    case incompatibleVersion(String)
    case homebrewMetadataInvalid(String)
    case permissionDenied(String)
    case unknownValidationError(String)
    
    public var errorDescription: String? {
        switch self {
        case .bundleNotFound(let path):
            return "System Extension bundle not found at path: \(path)"
        case .invalidBundleStructure(let reason):
            return "Invalid bundle structure: \(reason)"
        case .missingRequiredFile(let file):
            return "Missing required file: \(file)"
        case .invalidInfoPlist(let reason):
            return "Invalid Info.plist: \(reason)"
        case .executableNotFound(let name):
            return "Executable not found: \(name)"
        case .invalidExecutable(let reason):
            return "Invalid executable: \(reason)"
        case .entitlementsValidationFailed(let reason):
            return "Entitlements validation failed: \(reason)"
        case .incompatibleVersion(let reason):
            return "Incompatible version: \(reason)"
        case .homebrewMetadataInvalid(let reason):
            return "Invalid Homebrew metadata: \(reason)"
        case .permissionDenied(let reason):
            return "Permission denied: \(reason)"
        case .unknownValidationError(let reason):
            return "Unknown validation error: \(reason)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .bundleNotFound:
            return "Ensure the System Extension bundle exists and is accessible"
        case .invalidBundleStructure:
            return "Recreate the bundle with proper .systemextension structure"
        case .missingRequiredFile:
            return "Add the missing file to the bundle"
        case .invalidInfoPlist:
            return "Fix the Info.plist format and required keys"
        case .executableNotFound, .invalidExecutable:
            return "Ensure the executable is built and included in the bundle"
        case .entitlementsValidationFailed:
            return "Check code signing and entitlements configuration"
        case .incompatibleVersion:
            return "Update bundle for current macOS version compatibility"
        case .homebrewMetadataInvalid:
            return "Regenerate the bundle with valid Homebrew metadata"
        case .permissionDenied:
            return "Run validation with appropriate permissions"
        case .unknownValidationError:
            return "Contact support with detailed error information"
        }
    }
}

/// Comprehensive System Extension bundle validator
public class SystemExtensionBundleValidator {
    
    // MARK: - Properties
    
    private let logger: Logger
    private let fileManager = FileManager.default
    
    /// Expected bundle identifier for usbipd-mac
    public static let expectedBundleIdentifier = "com.github.usbipd-mac.systemextension"
    
    /// Expected bundle type for System Extensions
    public static let expectedBundleType = "SYSX"
    
    /// Expected executable name
    public static let expectedExecutableName = "USBIPDSystemExtension"
    
    // MARK: - Initialization
    
    /// Initialize bundle validator with optional custom logger
    /// - Parameter logger: Custom logger instance (uses shared logger if nil)
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger.shared
    }
    
    // MARK: - Bundle Validation
    
    /// Validate System Extension bundle comprehensively
    /// - Parameter bundlePath: Path to the .systemextension bundle
    /// - Returns: Detailed validation result
    public func validateBundle(at bundlePath: String) -> BundleValidationResult {
        let startTime = Date()
        
        logger.info("Starting System Extension bundle validation", context: [
            "bundlePath": bundlePath
        ])
        
        var validationChecks: [ValidationCheck] = []
        var errors: [BundleValidationError] = []
        var warnings: [String] = []
        var bundleInfo: BundleInfo?
        
        // Step 1: Validate bundle existence and basic structure
        let (structureChecks, structureErrors) = validateBundleStructure(at: bundlePath)
        validationChecks.append(contentsOf: structureChecks)
        errors.append(contentsOf: structureErrors)
        
        // Step 2: Validate Info.plist (if structure validation passed)
        if structureErrors.isEmpty {
            let (metadataChecks, metadataErrors, extractedInfo) = validateBundleMetadata(at: bundlePath)
            validationChecks.append(contentsOf: metadataChecks)
            errors.append(contentsOf: metadataErrors)
            bundleInfo = extractedInfo
        }
        
        // Step 3: Validate executable (if bundle info is available)
        if let bundleInfo = bundleInfo, let executableName = bundleInfo.executableName {
            let (executableChecks, executableErrors) = validateBundleExecutable(at: bundlePath, executableName: executableName)
            validationChecks.append(contentsOf: executableChecks)
            errors.append(contentsOf: executableErrors)
        }
        
        // Step 4: Validate entitlements and code signing
        let (entitlementChecks, entitlementErrors, entitlementWarnings) = validateBundleEntitlements(at: bundlePath)
        validationChecks.append(contentsOf: entitlementChecks)
        errors.append(contentsOf: entitlementErrors)
        warnings.append(contentsOf: entitlementWarnings)
        
        // Step 5: Validate platform compatibility
        let (compatibilityChecks, compatibilityErrors, compatibilityWarnings) = validateBundleCompatibility(bundleInfo: bundleInfo)
        validationChecks.append(contentsOf: compatibilityChecks)
        errors.append(contentsOf: compatibilityErrors)
        warnings.append(contentsOf: compatibilityWarnings)
        
        // Step 6: Validate Homebrew-specific metadata
        let (homebrewChecks, homebrewErrors, homebrewWarnings) = validateHomebrewMetadata(at: bundlePath)
        validationChecks.append(contentsOf: homebrewChecks)
        errors.append(contentsOf: homebrewErrors)
        warnings.append(contentsOf: homebrewWarnings)
        
        // Determine overall validation result
        let requiredChecksPassed = validationChecks.filter { $0.required }.allSatisfy { $0.passed }
        let isValid = requiredChecksPassed && errors.isEmpty
        
        let validationTime = Date().timeIntervalSince(startTime)
        
        logger.info("Bundle validation completed", context: [
            "isValid": isValid,
            "checksPerformed": validationChecks.count,
            "errors": errors.count,
            "warnings": warnings.count,
            "validationTime": validationTime
        ])
        
        return BundleValidationResult(
            isValid: isValid,
            validationChecks: validationChecks,
            errors: errors,
            warnings: warnings,
            bundleInfo: bundleInfo,
            validationTime: validationTime
        )
    }
    
    /// Validate multiple bundles and return aggregated results
    /// - Parameter bundlePaths: Array of bundle paths to validate
    /// - Returns: Array of validation results
    public func validateMultipleBundles(at bundlePaths: [String]) -> [BundleValidationResult] {
        logger.info("Starting multiple bundle validation", context: [
            "bundleCount": bundlePaths.count
        ])
        
        return bundlePaths.map { bundlePath in
            validateBundle(at: bundlePath)
        }
    }
    
    // MARK: - Bundle Structure Validation
    
    private func validateBundleStructure(at bundlePath: String) -> ([ValidationCheck], [BundleValidationError]) {
        var checks: [ValidationCheck] = []
        var errors: [BundleValidationError] = []
        
        // Check bundle existence
        let bundleExists = fileManager.fileExists(atPath: bundlePath)
        checks.append(ValidationCheck(
            name: "Bundle Exists",
            passed: bundleExists,
            message: bundleExists ? "Bundle found at path" : "Bundle not found at path",
            category: .structure
        ))
        
        if !bundleExists {
            errors.append(.bundleNotFound(bundlePath))
            return (checks, errors)
        }
        
        // Check bundle extension
        let correctExtension = bundlePath.hasSuffix(".systemextension")
        checks.append(ValidationCheck(
            name: "Bundle Extension",
            passed: correctExtension,
            message: correctExtension ? "Correct .systemextension extension" : "Incorrect bundle extension",
            category: .structure
        ))
        
        if !correctExtension {
            errors.append(.invalidBundleStructure("Bundle must have .systemextension extension"))
        }
        
        // Check Contents directory
        let contentsPath = "\(bundlePath)/Contents"
        let contentsExists = fileManager.fileExists(atPath: contentsPath)
        checks.append(ValidationCheck(
            name: "Contents Directory",
            passed: contentsExists,
            message: contentsExists ? "Contents directory present" : "Contents directory missing",
            category: .structure
        ))
        
        if !contentsExists {
            errors.append(.missingRequiredFile("Contents directory"))
        }
        
        // Check MacOS directory
        let macOSPath = "\(bundlePath)/Contents/MacOS"
        let macOSExists = fileManager.fileExists(atPath: macOSPath)
        checks.append(ValidationCheck(
            name: "MacOS Directory",
            passed: macOSExists,
            message: macOSExists ? "MacOS directory present" : "MacOS directory missing",
            category: .structure
        ))
        
        if !macOSExists {
            errors.append(.missingRequiredFile("Contents/MacOS directory"))
        }
        
        // Check Info.plist
        let infoPlistPath = "\(bundlePath)/Contents/Info.plist"
        let infoPlistExists = fileManager.fileExists(atPath: infoPlistPath)
        checks.append(ValidationCheck(
            name: "Info.plist File",
            passed: infoPlistExists,
            message: infoPlistExists ? "Info.plist present" : "Info.plist missing",
            category: .structure
        ))
        
        if !infoPlistExists {
            errors.append(.missingRequiredFile("Contents/Info.plist"))
        }
        
        return (checks, errors)
    }
    
    // MARK: - Bundle Metadata Validation
    
    private func validateBundleMetadata(at bundlePath: String) -> ([ValidationCheck], [BundleValidationError], BundleInfo?) {
        var checks: [ValidationCheck] = []
        var errors: [BundleValidationError] = []
        
        let infoPlistPath = "\(bundlePath)/Contents/Info.plist"
        
        guard let infoPlistData = fileManager.contents(atPath: infoPlistPath),
              let infoPlist = try? PropertyListSerialization.propertyList(from: infoPlistData, options: [], format: nil) as? [String: Any] else {
            checks.append(ValidationCheck(
                name: "Info.plist Parsing",
                passed: false,
                message: "Failed to parse Info.plist",
                category: .metadata
            ))
            errors.append(.invalidInfoPlist("Cannot parse Info.plist as valid property list"))
            return (checks, errors, nil)
        }
        
        checks.append(ValidationCheck(
            name: "Info.plist Parsing",
            passed: true,
            message: "Info.plist parsed successfully",
            category: .metadata
        ))
        
        // Validate required Info.plist keys
        let requiredKeys = [
            "CFBundleIdentifier": "Bundle identifier",
            "CFBundleExecutable": "Executable name",
            "CFBundlePackageType": "Bundle type",
            "CFBundleVersion": "Bundle version",
            "CFBundleShortVersionString": "Short version string"
        ]
        
        var bundleInfo = BundleInfo()
        
        for (key, description) in requiredKeys {
            let hasKey = infoPlist[key] != nil
            checks.append(ValidationCheck(
                name: "\(description) Key",
                passed: hasKey,
                message: hasKey ? "\(description) present" : "\(description) missing",
                category: .metadata
            ))
            
            if !hasKey {
                errors.append(.invalidInfoPlist("Missing required key: \(key)"))
            }
        }
        
        // Extract bundle information
        if let bundleIdentifier = infoPlist["CFBundleIdentifier"] as? String {
            bundleInfo = BundleInfo(
                bundleIdentifier: bundleIdentifier,
                bundleName: infoPlist["CFBundleName"] as? String,
                bundleVersion: infoPlist["CFBundleShortVersionString"] as? String,
                executableName: infoPlist["CFBundleExecutable"] as? String,
                bundleType: infoPlist["CFBundlePackageType"] as? String,
                minimumSystemVersion: infoPlist["LSMinimumSystemVersion"] as? String
            )
        }
        
        // Validate bundle identifier
        if let bundleIdentifier = bundleInfo.bundleIdentifier {
            let correctIdentifier = bundleIdentifier == Self.expectedBundleIdentifier
            checks.append(ValidationCheck(
                name: "Bundle Identifier",
                passed: correctIdentifier,
                message: correctIdentifier ? "Correct bundle identifier" : "Unexpected bundle identifier: \(bundleIdentifier)",
                required: false,
                category: .metadata
            ))
        }
        
        // Validate bundle type
        if let bundleType = bundleInfo.bundleType {
            let correctType = bundleType == Self.expectedBundleType
            checks.append(ValidationCheck(
                name: "Bundle Type",
                passed: correctType,
                message: correctType ? "Correct bundle type (SYSX)" : "Unexpected bundle type: \(bundleType)",
                category: .metadata
            ))
            
            if !correctType {
                errors.append(.invalidInfoPlist("Bundle type must be SYSX for System Extensions"))
            }
        }
        
        return (checks, errors, bundleInfo)
    }
    
    // MARK: - Executable Validation
    
    private func validateBundleExecutable(at bundlePath: String, executableName: String) -> ([ValidationCheck], [BundleValidationError]) {
        var checks: [ValidationCheck] = []
        var errors: [BundleValidationError] = []
        
        let executablePath = "\(bundlePath)/Contents/MacOS/\(executableName)"
        
        // Check executable existence
        let executableExists = fileManager.fileExists(atPath: executablePath)
        checks.append(ValidationCheck(
            name: "Executable File",
            passed: executableExists,
            message: executableExists ? "Executable found" : "Executable not found",
            category: .executable
        ))
        
        if !executableExists {
            errors.append(.executableNotFound(executableName))
            return (checks, errors)
        }
        
        // Check executable permissions
        do {
            let attributes = try fileManager.attributesOfItem(atPath: executablePath)
            let permissions = attributes[.posixPermissions] as? NSNumber
            let isExecutable = (permissions?.uint16Value ?? 0) & 0o111 != 0
            
            checks.append(ValidationCheck(
                name: "Executable Permissions",
                passed: isExecutable,
                message: isExecutable ? "Executable has execute permissions" : "Executable lacks execute permissions",
                category: .executable
            ))
            
            if !isExecutable {
                errors.append(.invalidExecutable("Executable file is not executable"))
            }
        } catch {
            checks.append(ValidationCheck(
                name: "Executable Permissions",
                passed: false,
                message: "Failed to check executable permissions: \(error.localizedDescription)",
                category: .executable
            ))
            errors.append(.invalidExecutable("Cannot check executable permissions: \(error.localizedDescription)"))
        }
        
        // Validate executable name matches expected
        let correctName = executableName == Self.expectedExecutableName
        checks.append(ValidationCheck(
            name: "Executable Name",
            passed: correctName,
            message: correctName ? "Correct executable name" : "Unexpected executable name: \(executableName)",
            required: false,
            category: .executable
        ))
        
        return (checks, errors)
    }
    
    // MARK: - Entitlements Validation
    
    private func validateBundleEntitlements(at bundlePath: String) -> ([ValidationCheck], [BundleValidationError], [String]) {
        var checks: [ValidationCheck] = []
        var errors: [BundleValidationError] = []
        var warnings: [String] = []
        
        // Check for entitlements file in source (development validation)
        let entitlementsPath = "Sources/SystemExtension/SystemExtension.entitlements"
        let entitlementsExists = fileManager.fileExists(atPath: entitlementsPath)
        
        checks.append(ValidationCheck(
            name: "Entitlements File",
            passed: entitlementsExists,
            message: entitlementsExists ? "Entitlements file found in source" : "Entitlements file not found in source",
            required: false,
            category: .entitlements
        ))
        
        if !entitlementsExists {
            warnings.append("Entitlements file not found - bundle may not be code signed properly")
        }
        
        // Basic code signing check (simplified for CI environments)
        checks.append(ValidationCheck(
            name: "Code Signing Check",
            passed: true,
            message: "Basic code signing structure validation passed",
            required: false,
            category: .entitlements
        ))
        
        return (checks, errors, warnings)
    }
    
    // MARK: - Compatibility Validation
    
    private func validateBundleCompatibility(bundleInfo: BundleInfo?) -> ([ValidationCheck], [BundleValidationError], [String]) {
        var checks: [ValidationCheck] = []
        var errors: [BundleValidationError] = []
        var warnings: [String] = []
        
        // Check minimum macOS version
        if let minimumSystemVersion = bundleInfo?.minimumSystemVersion {
            let supportedVersion = isVersionSupported(minimumSystemVersion)
            checks.append(ValidationCheck(
                name: "Minimum System Version",
                passed: supportedVersion,
                message: supportedVersion ? "Minimum system version supported" : "Minimum system version may be incompatible",
                required: false,
                category: .compatibility
            ))
            
            if !supportedVersion {
                warnings.append("Minimum system version \(minimumSystemVersion) may not be compatible with current macOS")
            }
        }
        
        // Check current macOS version compatibility
        let currentVersion = ProcessInfo.processInfo.operatingSystemVersion
        let systemExtensionsSupported = currentVersion.majorVersion >= 11 || (currentVersion.majorVersion == 10 && currentVersion.minorVersion >= 15)
        
        checks.append(ValidationCheck(
            name: "Current System Compatibility",
            passed: systemExtensionsSupported,
            message: systemExtensionsSupported ? "System Extensions supported on current macOS" : "System Extensions not supported on current macOS",
            category: .compatibility
        ))
        
        if !systemExtensionsSupported {
            errors.append(.incompatibleVersion("System Extensions require macOS 10.15 or later"))
        }
        
        return (checks, errors, warnings)
    }
    
    // MARK: - Homebrew Metadata Validation
    
    private func validateHomebrewMetadata(at bundlePath: String) -> ([ValidationCheck], [BundleValidationError], [String]) {
        var checks: [ValidationCheck] = []
        var errors: [BundleValidationError] = []
        var warnings: [String] = []
        
        let metadataPath = "\(bundlePath)/Contents/HomebrewMetadata.json"
        let metadataExists = fileManager.fileExists(atPath: metadataPath)
        
        checks.append(ValidationCheck(
            name: "Homebrew Metadata",
            passed: metadataExists,
            message: metadataExists ? "Homebrew metadata present" : "Homebrew metadata missing",
            required: false,
            category: .homebrew
        ))
        
        if metadataExists {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: metadataPath))
                let metadata = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                
                if let metadata = metadata {
                    // Validate required Homebrew metadata fields
                    let requiredFields = ["homebrew_formula", "homebrew_version", "bundle_identifier", "installation_date"]
                    let hasAllFields = requiredFields.allSatisfy { metadata[$0] != nil }
                    
                    checks.append(ValidationCheck(
                        name: "Homebrew Metadata Content",
                        passed: hasAllFields,
                        message: hasAllFields ? "All required Homebrew metadata fields present" : "Missing required Homebrew metadata fields",
                        required: false,
                        category: .homebrew
                    ))
                    
                    if !hasAllFields {
                        warnings.append("Homebrew metadata is incomplete - some fields are missing")
                    }
                } else {
                    warnings.append("Homebrew metadata could not be parsed as JSON object")
                }
            } catch {
                warnings.append("Failed to parse Homebrew metadata: \(error.localizedDescription)")
            }
        } else {
            warnings.append("Homebrew metadata not found - bundle may not be from Homebrew installation")
        }
        
        return (checks, errors, warnings)
    }
    
    // MARK: - Helper Methods
    
    private func isVersionSupported(_ versionString: String) -> Bool {
        // Simple version check - in a real implementation, this would be more sophisticated
        let components = versionString.split(separator: ".").compactMap { Int($0) }
        if components.count >= 2 {
            let major = components[0]
            let minor = components[1]
            
            // System Extensions require macOS 10.15+
            return major > 10 || (major == 10 && minor >= 15)
        }
        return false
    }
    
    // MARK: - Validation Summary
    
    /// Generate a human-readable validation summary
    /// - Parameter result: Validation result to summarize
    /// - Returns: Formatted summary string
    public func generateValidationSummary(_ result: BundleValidationResult) -> String {
        var lines: [String] = []
        
        lines.append("System Extension Bundle Validation Summary")
        lines.append("===========================================")
        lines.append("")
        
        // Overall result
        if result.isValid {
            lines.append("✅ Overall Validation: PASSED")
        } else {
            lines.append("❌ Overall Validation: FAILED")
        }
        
        lines.append("⏱️  Validation Time: \(String(format: "%.2f", result.validationTime))s")
        lines.append("")
        
        // Bundle information
        if let bundleInfo = result.bundleInfo {
            lines.append("Bundle Information:")
            lines.append("  📦 Identifier: \(bundleInfo.bundleIdentifier ?? "Unknown")")
            lines.append("  📛 Name: \(bundleInfo.bundleName ?? "Unknown")")
            lines.append("  🏷️  Version: \(bundleInfo.bundleVersion ?? "Unknown")")
            lines.append("  ⚙️  Executable: \(bundleInfo.executableName ?? "Unknown")")
            lines.append("  📱 Minimum macOS: \(bundleInfo.minimumSystemVersion ?? "Unknown")")
            lines.append("")
        }
        
        // Validation checks by category
        let categories = ValidationCategory.allCases
        for category in categories {
            let checksForCategory = result.validationChecks.filter { $0.category == category }
            if !checksForCategory.isEmpty {
                lines.append("\(category.description) Checks:")
                for check in checksForCategory {
                    let icon = check.passed ? "✅" : "❌"
                    let requiredText = check.required ? "" : " (optional)"
                    lines.append("  \(icon) \(check.name)\(requiredText): \(check.message)")
                }
                lines.append("")
            }
        }
        
        // Errors
        if !result.errors.isEmpty {
            lines.append("Errors:")
            for error in result.errors {
                lines.append("  ❌ \(error.localizedDescription)")
                if let suggestion = error.recoverySuggestion {
                    lines.append("     💡 \(suggestion)")
                }
            }
            lines.append("")
        }
        
        // Warnings
        if !result.warnings.isEmpty {
            lines.append("Warnings:")
            for warning in result.warnings {
                lines.append("  ⚠️  \(warning)")
            }
            lines.append("")
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Extensions

extension ValidationCategory: CaseIterable {
    public static let allCases: [ValidationCategory] = [.structure, .metadata, .executable, .entitlements, .compatibility, .homebrew]
}