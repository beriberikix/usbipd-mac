// HomebrewBundleCreator.swift
// Homebrew-specific wrapper around SystemExtensionBundleCreator for formula integration

import Foundation
import Common

/// Homebrew-specific configuration for bundle creation
public struct HomebrewBundleConfig {
    /// Homebrew formula prefix path (typically from ENV["HOMEBREW_PREFIX"])
    public let homebrewPrefix: String
    
    /// Version string from Homebrew formula
    public let formulaVersion: String
    
    /// Installation prefix for the bundle (e.g., #{prefix}/Library/SystemExtensions)
    public let installationPrefix: String
    
    /// Bundle identifier for the System Extension
    public let bundleIdentifier: String
    
    /// Display name for the bundle
    public let displayName: String
    
    /// Executable name within bundle
    public let executableName: String
    
    /// Team identifier for code signing (optional)
    public let teamIdentifier: String?
    
    /// Path to the compiled executable
    public let executablePath: String
    
    /// Additional Homebrew-specific metadata
    public let formulaName: String
    public let buildNumber: String
    
    public init(
        homebrewPrefix: String,
        formulaVersion: String,
        installationPrefix: String,
        bundleIdentifier: String,
        displayName: String,
        executableName: String,
        teamIdentifier: String? = nil,
        executablePath: String,
        formulaName: String,
        buildNumber: String
    ) {
        self.homebrewPrefix = homebrewPrefix
        self.formulaVersion = formulaVersion
        self.installationPrefix = installationPrefix
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.executableName = executableName
        self.teamIdentifier = teamIdentifier
        self.executablePath = executablePath
        self.formulaName = formulaName
        self.buildNumber = buildNumber
    }
}

/// Homebrew-specific bundle creation utility that integrates with formula build process
public class HomebrewBundleCreator {
    
    // MARK: - Properties
    
    private let systemExtensionBundleCreator: SystemExtensionBundleCreator
    private let logger: Logger
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    
    /// Initialize Homebrew bundle creator with optional custom logger
    /// - Parameter logger: Custom logger instance (uses shared logger if nil)
    public init(logger: Logger? = nil) {
        let logger = logger ?? Logger.shared
        self.logger = logger
        self.systemExtensionBundleCreator = SystemExtensionBundleCreator(logger: logger)
    }
    
    // MARK: - Bundle Path Resolution
    
    /// Resolve full bundle path based on Homebrew configuration
    /// - Parameter config: Homebrew bundle configuration
    /// - Returns: Full path where bundle should be created
    public func resolveBundlePath(from config: HomebrewBundleConfig) -> String {
        let bundleName = "\(config.formulaName).systemextension"
        return URL(fileURLWithPath: config.installationPrefix)
            .appendingPathComponent(bundleName)
            .path
    }
    
    /// Resolve installation prefix path for Homebrew formula
    /// - Parameter config: Homebrew bundle configuration
    /// - Returns: Installation prefix path with proper directory structure
    public func resolveInstallationPrefix(from config: HomebrewBundleConfig) -> String {
        return URL(fileURLWithPath: config.installationPrefix)
            .appendingPathComponent("Library")
            .appendingPathComponent("SystemExtensions")
            .path
    }
    
    // MARK: - Version Handling
    
    /// Generate build number from Homebrew formula version
    /// - Parameter config: Homebrew bundle configuration
    /// - Returns: Build number suitable for bundle creation
    public func generateBuildNumber(from config: HomebrewBundleConfig) -> String {
        // Use provided build number or generate from version
        if !config.buildNumber.isEmpty {
            return config.buildNumber
        }
        
        // Convert version string to build number (e.g., "1.2.3" -> "123")
        let versionComponents = config.formulaVersion.components(separatedBy: ".")
        let buildComponents = versionComponents.compactMap { Int($0) }
        
        if buildComponents.count >= 3 {
            return String(format: "%d%02d%02d", buildComponents[0], buildComponents[1], buildComponents[2])
        } else if buildComponents.count >= 2 {
            return String(format: "%d%02d00", buildComponents[0], buildComponents[1])
        } else if buildComponents.count >= 1 {
            return String(format: "%d0000", buildComponents[0])
        } else {
            return "10000" // Default build number
        }
    }
    
    // MARK: - Homebrew Bundle Creation
    
    /// Create System Extension bundle optimized for Homebrew installation
    /// - Parameter config: Homebrew bundle configuration
    /// - Returns: Created SystemExtensionBundle
    /// - Throws: InstallationError on creation failure
    public func createHomebrewBundle(with config: HomebrewBundleConfig) throws -> SystemExtensionBundle {
        logger.info("Starting Homebrew System Extension bundle creation", context: [
            "formulaName": config.formulaName,
            "formulaVersion": config.formulaVersion,
            "bundleIdentifier": config.bundleIdentifier
        ])
        
        // Resolve paths and configuration
        let resolvedInstallationPrefix = resolveInstallationPrefix(from: config)
        let bundlePath = resolveBundlePath(from: HomebrewBundleConfig(
            homebrewPrefix: config.homebrewPrefix,
            formulaVersion: config.formulaVersion,
            installationPrefix: resolvedInstallationPrefix,
            bundleIdentifier: config.bundleIdentifier,
            displayName: config.displayName,
            executableName: config.executableName,
            teamIdentifier: config.teamIdentifier,
            executablePath: config.executablePath,
            formulaName: config.formulaName,
            buildNumber: config.buildNumber
        ))
        let buildNumber = generateBuildNumber(from: config)
        
        // Ensure installation directory exists
        try createInstallationDirectory(at: resolvedInstallationPrefix)
        
        // Create SystemExtensionBundleCreator configuration
        let bundleCreationConfig = SystemExtensionBundleCreator.BundleCreationConfig(
            bundlePath: bundlePath,
            bundleIdentifier: config.bundleIdentifier,
            displayName: config.displayName,
            version: config.formulaVersion,
            buildNumber: buildNumber,
            executableName: config.executableName,
            teamIdentifier: config.teamIdentifier,
            executablePath: config.executablePath
        )
        
        // Create bundle using SystemExtensionBundleCreator
        let bundle = try systemExtensionBundleCreator.createBundle(with: bundleCreationConfig)
        
        // Complete bundle creation with executable integration
        let completedBundle = try systemExtensionBundleCreator.completeBundle(bundle, with: bundleCreationConfig)
        
        // Perform Homebrew-specific post-processing
        try performHomebrewPostProcessing(bundle: completedBundle, config: config)
        
        logger.info("Homebrew System Extension bundle creation completed", context: [
            "bundlePath": bundlePath,
            "bundleSize": completedBundle.contents.bundleSize
        ])
        
        return completedBundle
    }
    
    // MARK: - Installation Directory Management
    
    /// Create installation directory structure for Homebrew
    /// - Parameter installationPrefix: Installation prefix path
    /// - Throws: InstallationError on directory creation failure
    private func createInstallationDirectory(at installationPrefix: String) throws {
        do {
            try fileManager.createDirectory(atPath: installationPrefix, withIntermediateDirectories: true, attributes: nil)
            logger.debug("Created installation directory", context: ["path": installationPrefix])
        } catch {
            logger.error("Failed to create installation directory", context: [
                "path": installationPrefix,
                "error": error.localizedDescription
            ])
            throw InstallationError.bundleCreationFailed("Failed to create installation directory: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Homebrew Post-Processing
    
    /// Perform Homebrew-specific post-processing on created bundle
    /// - Parameters:
    ///   - bundle: Created SystemExtensionBundle
    ///   - config: Homebrew bundle configuration
    /// - Throws: InstallationError on post-processing failure
    private func performHomebrewPostProcessing(bundle: SystemExtensionBundle, config: HomebrewBundleConfig) throws {
        logger.debug("Performing Homebrew-specific post-processing", context: [
            "bundlePath": bundle.bundlePath
        ])
        
        // Add Homebrew metadata file
        try createHomebrewMetadataFile(bundle: bundle, config: config)
        
        // Set appropriate permissions for Homebrew installation
        try setHomebrewPermissions(bundle: bundle)
        
        // Create convenience symlinks if needed
        try createConvenienceSymlinks(bundle: bundle, config: config)
        
        logger.debug("Homebrew post-processing completed")
    }
    
    /// Create Homebrew metadata file in bundle
    /// - Parameters:
    ///   - bundle: SystemExtensionBundle
    ///   - config: Homebrew bundle configuration
    /// - Throws: InstallationError on metadata creation failure
    private func createHomebrewMetadataFile(bundle: SystemExtensionBundle, config: HomebrewBundleConfig) throws {
        let metadataPath = URL(fileURLWithPath: bundle.bundlePath)
            .appendingPathComponent("Contents")
            .appendingPathComponent("HomebrewMetadata.plist")
            .path
        
        let metadata: [String: Any] = [
            "HomebrewFormulaName": config.formulaName,
            "HomebrewFormulaVersion": config.formulaVersion,
            "HomebrewPrefix": config.homebrewPrefix,
            "InstallationDate": Date(),
            "BundleCreator": "HomebrewBundleCreator",
            "CreatorVersion": "1.0.0"
        ]
        
        do {
            let metadataData = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
            try metadataData.write(to: URL(fileURLWithPath: metadataPath))
            
            logger.debug("Created Homebrew metadata file", context: [
                "path": metadataPath
            ])
        } catch {
            logger.warning("Failed to create Homebrew metadata file", context: [
                "path": metadataPath,
                "error": error.localizedDescription
            ])
            // Non-critical error, don't throw
        }
    }
    
    /// Set appropriate permissions for Homebrew installation
    /// - Parameter bundle: SystemExtensionBundle
    /// - Throws: InstallationError on permission setting failure
    private func setHomebrewPermissions(bundle: SystemExtensionBundle) throws {
        // Set bundle directory permissions (755)
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: bundle.bundlePath
            )
            
            // Set Contents directory permissions (755)
            let contentsPath = URL(fileURLWithPath: bundle.bundlePath)
                .appendingPathComponent("Contents")
                .path
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: contentsPath
            )
            
            logger.debug("Set Homebrew-appropriate permissions")
        } catch {
            logger.warning("Failed to set Homebrew permissions", context: [
                "bundlePath": bundle.bundlePath,
                "error": error.localizedDescription
            ])
            // Non-critical error for permissions, don't throw
        }
    }
    
    /// Create convenience symlinks for Homebrew integration
    /// - Parameters:
    ///   - bundle: SystemExtensionBundle
    ///   - config: Homebrew bundle configuration
    /// - Throws: InstallationError on symlink creation failure
    private func createConvenienceSymlinks(bundle: SystemExtensionBundle, config: HomebrewBundleConfig) throws {
        // Create symlink in Homebrew bin directory if desired
        let binDir = URL(fileURLWithPath: config.homebrewPrefix)
            .appendingPathComponent("bin")
            .path
        
        if fileManager.fileExists(atPath: binDir) {
            let symlinkPath = URL(fileURLWithPath: binDir)
                .appendingPathComponent("\(config.formulaName)-systemextension")
                .path
            
            let targetPath = bundle.bundlePath
            
            // Remove existing symlink if present
            if fileManager.fileExists(atPath: symlinkPath) {
                do {
                    try fileManager.removeItem(atPath: symlinkPath)
                } catch {
                    logger.debug("Could not remove existing symlink", context: [
                        "path": symlinkPath,
                        "error": error.localizedDescription
                    ])
                }
            }
            
            // Create new symlink
            do {
                try fileManager.createSymbolicLink(atPath: symlinkPath, withDestinationPath: targetPath)
                logger.debug("Created convenience symlink", context: [
                    "symlink": symlinkPath,
                    "target": targetPath
                ])
            } catch {
                logger.debug("Could not create convenience symlink", context: [
                    "symlink": symlinkPath,
                    "error": error.localizedDescription
                ])
                // Non-critical error, don't throw
            }
        }
    }
    
    // MARK: - Validation and Verification
    
    /// Validate Homebrew bundle configuration before creation
    /// - Parameter config: Homebrew bundle configuration to validate
    /// - Returns: Array of validation issues (empty if valid)
    public func validateHomebrewConfig(_ config: HomebrewBundleConfig) -> [String] {
        var issues: [String] = []
        
        // Validate Homebrew prefix
        if config.homebrewPrefix.isEmpty {
            issues.append("Homebrew prefix cannot be empty")
        } else if !fileManager.fileExists(atPath: config.homebrewPrefix) {
            issues.append("Homebrew prefix directory does not exist: \(config.homebrewPrefix)")
        }
        
        // Validate formula version
        if config.formulaVersion.isEmpty {
            issues.append("Formula version cannot be empty")
        }
        
        // Validate installation prefix
        if config.installationPrefix.isEmpty {
            issues.append("Installation prefix cannot be empty")
        }
        
        // Validate executable path
        if config.executablePath.isEmpty {
            issues.append("Executable path cannot be empty")
        } else if !fileManager.fileExists(atPath: config.executablePath) {
            issues.append("Executable file does not exist: \(config.executablePath)")
        }
        
        // Validate bundle identifier format
        let bundleIdPattern = #"^[a-zA-Z0-9][a-zA-Z0-9\-]*(\.[a-zA-Z0-9][a-zA-Z0-9\-]*)+$"#
        if config.bundleIdentifier.range(of: bundleIdPattern, options: .regularExpression) == nil {
            issues.append("Bundle identifier has invalid format: \(config.bundleIdentifier)")
        }
        
        logger.debug("Homebrew configuration validation completed", context: [
            "issuesFound": issues.count
        ])
        
        return issues
    }
    
    /// Generate comprehensive bundle report for Homebrew integration
    /// - Parameter bundle: SystemExtensionBundle to report on
    /// - Returns: Formatted report string
    public func generateHomebrewBundleReport(for bundle: SystemExtensionBundle) -> String {
        var report = "Homebrew System Extension Bundle Report\n"
        report += "=====================================\n\n"
        
        report += "Bundle Information:\n"
        report += "  Bundle Path: \(bundle.bundlePath)\n"
        report += "  Bundle Identifier: \(bundle.bundleIdentifier)\n"
        report += "  Display Name: \(bundle.displayName)\n"
        report += "  Version: \(bundle.version)\n"
        report += "  Build Number: \(bundle.buildNumber)\n"
        report += "  Executable: \(bundle.executableName)\n"
        
        if let teamId = bundle.teamIdentifier {
            report += "  Team Identifier: \(teamId)\n"
        }
        
        report += "\nBundle Contents:\n"
        report += "  Info.plist: \(bundle.contents.infoPlistPath)\n"
        report += "  Executable: \(bundle.contents.executablePath)\n"
        
        if let entitlements = bundle.contents.entitlementsPath {
            report += "  Entitlements: \(entitlements)\n"
        }
        
        if !bundle.contents.resourceFiles.isEmpty {
            report += "  Resource Files: \(bundle.contents.resourceFiles.count)\n"
        }
        
        report += "  Bundle Size: \(bundle.contents.bundleSize) bytes\n"
        report += "  Valid: \(bundle.contents.isValid ? "Yes" : "No")\n"
        
        report += "\nCreation Time: \(bundle.creationTime)\n"
        
        // Add validation report
        let validationResults = systemExtensionBundleCreator.performIntegrityCheck(on: bundle)
        let validationReport = systemExtensionBundleCreator.generateRemediationReport(from: validationResults)
        report += "\nValidation Results:\n\(validationReport)\n"
        
        return report
    }
}