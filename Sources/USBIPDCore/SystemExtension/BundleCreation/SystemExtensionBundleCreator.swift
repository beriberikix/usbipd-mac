// SystemExtensionBundleCreator.swift
// Foundation for creating System Extension bundles replacing broken plugin system

import Foundation
import Common

/// Creates properly structured System Extension bundles with executable integration
public class SystemExtensionBundleCreator {
    
    // MARK: - Properties
    
    private let logger: Logger
    private let fileManager = FileManager.default
    
    /// Bundle creation configuration
    public struct BundleCreationConfig {
        /// Target bundle path where bundle will be created
        public let bundlePath: String
        
        /// Bundle identifier (e.g., com.example.USBIPSystemExtension)
        public let bundleIdentifier: String
        
        /// Display name for the bundle
        public let displayName: String
        
        /// Bundle version string
        public let version: String
        
        /// Bundle build number
        public let buildNumber: String
        
        /// Executable name within bundle
        public let executableName: String
        
        /// Team identifier for code signing (optional)
        public let teamIdentifier: String?
        
        /// Path to compiled executable
        public let executablePath: String
        
        public init(
            bundlePath: String,
            bundleIdentifier: String,
            displayName: String,
            version: String,
            buildNumber: String,
            executableName: String,
            teamIdentifier: String? = nil,
            executablePath: String
        ) {
            self.bundlePath = bundlePath
            self.bundleIdentifier = bundleIdentifier
            self.displayName = displayName
            self.version = version
            self.buildNumber = buildNumber
            self.executableName = executableName
            self.teamIdentifier = teamIdentifier
            self.executablePath = executablePath
        }
    }
    
    // MARK: - Initialization
    
    /// Initialize bundle creator with optional custom logger
    /// - Parameter logger: Custom logger instance (uses shared logger if nil)
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger.shared
    }
    
    // MARK: - Bundle Creation Foundation
    
    /// Create bundle directory structure
    /// - Parameter config: Bundle creation configuration
    /// - Returns: Created SystemExtensionBundle on success
    /// - Throws: InstallationError on failure
    public func createBundle(with config: BundleCreationConfig) throws -> SystemExtensionBundle {
        logger.info("Starting System Extension bundle creation", context: [
            "bundlePath": config.bundlePath,
            "bundleIdentifier": config.bundleIdentifier
        ])
        
        // Create bundle directory structure
        try createBundleDirectoryStructure(config: config)
        
        // Generate and write Info.plist
        let infoPlistPath = try createInfoPlist(config: config)
        
        // Create basic bundle contents structure
        let contents = BundleContents(
            infoPlistPath: infoPlistPath,
            executablePath: "", // Will be set during executable integration
            entitlementsPath: nil,
            resourceFiles: [],
            isValid: false, // Will be validated during completion
            bundleSize: 0 // Will be calculated during completion
        )
        
        let bundle = SystemExtensionBundle(
            bundlePath: config.bundlePath,
            bundleIdentifier: config.bundleIdentifier,
            displayName: config.displayName,
            version: config.version,
            buildNumber: config.buildNumber,
            executableName: config.executableName,
            teamIdentifier: config.teamIdentifier,
            contents: contents,
            codeSigningInfo: nil,
            creationTime: Date()
        )
        
        logger.info("System Extension bundle structure created successfully", context: [
            "bundlePath": config.bundlePath
        ])
        
        return bundle
    }
    
    // MARK: - Directory Structure Creation
    
    /// Create the basic bundle directory structure
    /// - Parameter config: Bundle creation configuration
    /// - Throws: InstallationError on directory creation failure
    private func createBundleDirectoryStructure(config: BundleCreationConfig) throws {
        let bundleURL = URL(fileURLWithPath: config.bundlePath)
        
        // Create main bundle directory
        do {
            try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true, attributes: nil)
            logger.debug("Created bundle directory", context: ["path": config.bundlePath])
        } catch {
            logger.error("Failed to create bundle directory", context: [
                "path": config.bundlePath,
                "error": error.localizedDescription
            ])
            throw InstallationError.bundleCreationFailed("Failed to create bundle directory: \(error.localizedDescription)")
        }
        
        // Create Contents directory
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        do {
            try fileManager.createDirectory(at: contentsURL, withIntermediateDirectories: true, attributes: nil)
            logger.debug("Created Contents directory")
        } catch {
            logger.error("Failed to create Contents directory", context: ["error": error.localizedDescription])
            throw InstallationError.bundleCreationFailed("Failed to create Contents directory: \(error.localizedDescription)")
        }
        
        // Create MacOS directory for executable
        let macosURL = contentsURL.appendingPathComponent("MacOS")
        do {
            try fileManager.createDirectory(at: macosURL, withIntermediateDirectories: true, attributes: nil)
            logger.debug("Created MacOS directory")
        } catch {
            logger.error("Failed to create MacOS directory", context: ["error": error.localizedDescription])
            throw InstallationError.bundleCreationFailed("Failed to create MacOS directory: \(error.localizedDescription)")
        }
        
        // Create Resources directory (optional, for future use)
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        do {
            try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true, attributes: nil)
            logger.debug("Created Resources directory")
        } catch {
            logger.error("Failed to create Resources directory", context: ["error": error.localizedDescription])
            throw InstallationError.bundleCreationFailed("Failed to create Resources directory: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Info.plist Template Processing
    
    /// Create Info.plist file with System Extension specific configuration
    /// - Parameter config: Bundle creation configuration
    /// - Returns: Path to created Info.plist file
    /// - Throws: InstallationError on plist creation failure
    private func createInfoPlist(config: BundleCreationConfig) throws -> String {
        let infoPlistPath = URL(fileURLWithPath: config.bundlePath)
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")
            .path
        
        // Create Info.plist dictionary with System Extension specific keys
        var plistDict: [String: Any] = [
            "CFBundleDisplayName": config.displayName,
            "CFBundleExecutable": config.executableName,
            "CFBundleIdentifier": config.bundleIdentifier,
            "CFBundleName": config.displayName,
            "CFBundlePackageType": "SYSX",
            "CFBundleShortVersionString": config.version,
            "CFBundleVersion": config.buildNumber,
            "CFBundleInfoDictionaryVersion": "6.0",
            "LSMinimumSystemVersion": "11.0",
            "NSSystemExtensionUsageDescription": "USB/IP System Extension for sharing USB devices over network"
        ]
        
        // Add team identifier if provided
        if config.teamIdentifier != nil {
            plistDict["CFBundleDevelopmentRegion"] = "en"
            plistDict["ITSAppUsesNonExemptEncryption"] = false
            // Team identifier is typically handled by code signing, but we store it for reference
        }
        
        // Add System Extension specific configuration
        plistDict["NSSystemExtensionUsageDescription"] = "This System Extension enables USB/IP protocol support for sharing USB devices over the network."
        
        // Write plist to file
        do {
            let plistData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
            try plistData.write(to: URL(fileURLWithPath: infoPlistPath))
            
            logger.debug("Created Info.plist", context: [
                "path": infoPlistPath,
                "bundleIdentifier": config.bundleIdentifier
            ])
            
            return infoPlistPath
        } catch {
            logger.error("Failed to create Info.plist", context: [
                "path": infoPlistPath,
                "error": error.localizedDescription
            ])
            throw InstallationError.bundleCreationFailed("Failed to create Info.plist: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Executable Integration and Bundle Completion
    
    /// Complete bundle creation by integrating compiled executable and resources
    /// - Parameters:
    ///   - bundle: Partially created bundle from createBundle()
    ///   - config: Bundle creation configuration
    /// - Returns: Completed SystemExtensionBundle with executable integration
    /// - Throws: InstallationError on completion failure
    public func completeBundle(_ bundle: SystemExtensionBundle, with config: BundleCreationConfig) throws -> SystemExtensionBundle {
        logger.info("Completing System Extension bundle with executable integration", context: [
            "bundlePath": bundle.bundlePath,
            "executablePath": config.executablePath
        ])
        
        // Copy compiled executable to bundle
        let executablePath = try copyExecutableToBundle(config: config)
        
        // Copy entitlements if available
        let entitlementsPath = try copyEntitlementsIfAvailable(config: config)
        
        // Copy additional resources
        let resourceFiles = try copyResourceFiles(config: config)
        
        // Validate completed bundle structure
        let validationIssues = validateCompletedBundle(at: bundle.bundlePath)
        let isValid = validationIssues.isEmpty
        
        if !isValid {
            logger.warning("Bundle validation found issues", context: [
                "issues": validationIssues.joined(separator: ", ")
            ])
        }
        
        // Calculate bundle size
        let bundleSize = calculateBundleSize(at: bundle.bundlePath)
        
        // Create updated bundle contents
        let updatedContents = BundleContents(
            infoPlistPath: bundle.contents.infoPlistPath,
            executablePath: executablePath,
            entitlementsPath: entitlementsPath,
            resourceFiles: resourceFiles,
            isValid: isValid,
            bundleSize: bundleSize
        )
        
        // Return completed bundle
        let completedBundle = SystemExtensionBundle(
            bundlePath: bundle.bundlePath,
            bundleIdentifier: bundle.bundleIdentifier,
            displayName: bundle.displayName,
            version: bundle.version,
            buildNumber: bundle.buildNumber,
            executableName: bundle.executableName,
            teamIdentifier: bundle.teamIdentifier,
            contents: updatedContents,
            codeSigningInfo: bundle.codeSigningInfo,
            creationTime: bundle.creationTime
        )
        
        logger.info("System Extension bundle completion successful", context: [
            "bundlePath": bundle.bundlePath,
            "bundleSize": bundleSize,
            "isValid": isValid
        ])
        
        return completedBundle
    }
    
    /// Copy compiled executable into bundle MacOS directory
    /// - Parameter config: Bundle creation configuration
    /// - Returns: Path to executable within bundle
    /// - Throws: InstallationError on copy failure
    private func copyExecutableToBundle(config: BundleCreationConfig) throws -> String {
        let sourceExecutablePath = config.executablePath
        let targetExecutablePath = URL(fileURLWithPath: config.bundlePath)
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(config.executableName)
            .path
        
        // Check if source executable exists
        guard fileManager.fileExists(atPath: sourceExecutablePath) else {
            logger.error("Source executable not found", context: ["path": sourceExecutablePath])
            throw InstallationError.bundleCreationFailed("Source executable not found: \(sourceExecutablePath)")
        }
        
        // Remove existing executable if present
        if fileManager.fileExists(atPath: targetExecutablePath) {
            do {
                try fileManager.removeItem(atPath: targetExecutablePath)
                logger.debug("Removed existing executable")
            } catch {
                logger.warning("Failed to remove existing executable", context: ["error": error.localizedDescription])
            }
        }
        
        // Copy executable to bundle
        do {
            try fileManager.copyItem(atPath: sourceExecutablePath, toPath: targetExecutablePath)
            logger.debug("Copied executable to bundle", context: [
                "source": sourceExecutablePath,
                "target": targetExecutablePath
            ])
        } catch {
            logger.error("Failed to copy executable", context: [
                "source": sourceExecutablePath,
                "target": targetExecutablePath,
                "error": error.localizedDescription
            ])
            throw InstallationError.bundleCreationFailed("Failed to copy executable: \(error.localizedDescription)")
        }
        
        // Set executable permissions
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: targetExecutablePath
            )
            logger.debug("Set executable permissions")
        } catch {
            logger.warning("Failed to set executable permissions", context: ["error": error.localizedDescription])
        }
        
        return targetExecutablePath
    }
    
    /// Copy entitlements file if available
    /// - Parameter config: Bundle creation configuration
    /// - Returns: Path to entitlements file within bundle (nil if not available)
    /// - Throws: InstallationError on copy failure
    private func copyEntitlementsIfAvailable(config: BundleCreationConfig) throws -> String? {
        // Look for entitlements file in common locations
        let possibleEntitlementsPaths = [
            config.executablePath.replacingOccurrences(of: ".app", with: ".entitlements"),
            config.executablePath + ".entitlements",
            URL(fileURLWithPath: config.executablePath).deletingLastPathComponent()
                .appendingPathComponent("SystemExtension.entitlements").path
        ]
        
        for entitlementsPath in possibleEntitlementsPaths where fileManager.fileExists(atPath: entitlementsPath) {
            let targetPath = URL(fileURLWithPath: config.bundlePath)
                .appendingPathComponent("Contents")
                .appendingPathComponent("SystemExtension.entitlements")
                .path
            
            do {
                try fileManager.copyItem(atPath: entitlementsPath, toPath: targetPath)
                logger.debug("Copied entitlements file", context: [
                    "source": entitlementsPath,
                    "target": targetPath
                ])
                return targetPath
            } catch {
                logger.warning("Failed to copy entitlements file", context: [
                    "source": entitlementsPath,
                    "error": error.localizedDescription
                ])
            }
        }
        
        logger.debug("No entitlements file found or copied")
        return nil
    }
    
    /// Copy additional resource files to bundle
    /// - Parameter config: Bundle creation configuration
    /// - Returns: List of resource file paths copied to bundle
    /// - Throws: InstallationError on copy failure
    private func copyResourceFiles(config: BundleCreationConfig) throws -> [String] {
        var copiedResources: [String] = []
        
        // Look for common resource files in executable directory
        let executableDir = URL(fileURLWithPath: config.executablePath).deletingLastPathComponent()
        let resourcesDir = URL(fileURLWithPath: config.bundlePath)
            .appendingPathComponent("Contents/Resources")
        
        // Common resource file extensions to look for
        let resourceExtensions = ["plist", "strings", "lproj", "nib", "storyboard"]
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: executableDir, includingPropertiesForKeys: nil, options: [])
            
            for fileURL in contents {
                let fileExtension = fileURL.pathExtension.lowercased()
                if resourceExtensions.contains(fileExtension) {
                    let targetURL = resourcesDir.appendingPathComponent(fileURL.lastPathComponent)
                    
                    do {
                        try fileManager.copyItem(at: fileURL, to: targetURL)
                        copiedResources.append(targetURL.path)
                        logger.debug("Copied resource file", context: [
                            "source": fileURL.path,
                            "target": targetURL.path
                        ])
                    } catch {
                        logger.warning("Failed to copy resource file", context: [
                            "source": fileURL.path,
                            "error": error.localizedDescription
                        ])
                    }
                }
            }
        } catch {
            logger.debug("Could not scan for resource files", context: [
                "directory": executableDir.path,
                "error": error.localizedDescription
            ])
        }
        
        logger.debug("Resource file copying completed", context: [
            "copiedCount": copiedResources.count
        ])
        
        return copiedResources
    }
    
    /// Calculate total size of bundle directory
    /// - Parameter bundlePath: Path to bundle
    /// - Returns: Bundle size in bytes
    private func calculateBundleSize(at bundlePath: String) -> Int64 {
        var totalSize: Int64 = 0
        
        if let enumerator = fileManager.enumerator(atPath: bundlePath) {
            while let filename = enumerator.nextObject() as? String {
                let filePath = URL(fileURLWithPath: bundlePath).appendingPathComponent(filename).path
                
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: filePath)
                    if let fileSize = attributes[.size] as? Int64 {
                        totalSize += fileSize
                    }
                } catch {
                    // Ignore individual file size calculation errors
                    continue
                }
            }
        }
        
        logger.debug("Bundle size calculated", context: [
            "bundlePath": bundlePath,
            "sizeBytes": totalSize
        ])
        
        return totalSize
    }
    
    // MARK: - Bundle Validation Foundation
    
    /// Validate basic bundle directory structure
    /// - Parameter bundlePath: Path to bundle to validate
    /// - Returns: Array of validation issues (empty if valid)
    public func validateBundleStructure(at bundlePath: String) -> [String] {
        var issues: [String] = []
        
        let bundleURL = URL(fileURLWithPath: bundlePath)
        
        // Check if bundle directory exists
        guard fileManager.fileExists(atPath: bundlePath) else {
            issues.append("Bundle directory does not exist: \(bundlePath)")
            return issues
        }
        
        // Check Contents directory
        let contentsPath = bundleURL.appendingPathComponent("Contents").path
        guard fileManager.fileExists(atPath: contentsPath) else {
            issues.append("Contents directory missing")
            return issues
        }
        
        // Check Info.plist
        let infoPlistPath = bundleURL.appendingPathComponent("Contents/Info.plist").path
        if !fileManager.fileExists(atPath: infoPlistPath) {
            issues.append("Info.plist missing")
        }
        
        // Check MacOS directory
        let macosPath = bundleURL.appendingPathComponent("Contents/MacOS").path
        if !fileManager.fileExists(atPath: macosPath) {
            issues.append("MacOS directory missing")
        }
        
        logger.debug("Bundle structure validation completed", context: [
            "bundlePath": bundlePath,
            "issuesFound": issues.count
        ])
        
        return issues
    }
    
    /// Validate completed bundle with executable and all required components
    /// - Parameter bundlePath: Path to bundle to validate
    /// - Returns: Array of validation issues (empty if valid)
    public func validateCompletedBundle(at bundlePath: String) -> [String] {
        var issues = validateBundleStructure(at: bundlePath)
        
        let bundleURL = URL(fileURLWithPath: bundlePath)
        
        // Additional validation for completed bundles
        
        // Check if MacOS directory has executable files
        let macosPath = bundleURL.appendingPathComponent("Contents/MacOS").path
        if fileManager.fileExists(atPath: macosPath) {
            do {
                let macosContents = try fileManager.contentsOfDirectory(atPath: macosPath)
                if macosContents.isEmpty {
                    issues.append("MacOS directory is empty - no executable found")
                } else {
                    // Check if at least one file is executable
                    var hasExecutable = false
                    for filename in macosContents {
                        let filePath = URL(fileURLWithPath: macosPath).appendingPathComponent(filename).path
                        if fileManager.isExecutableFile(atPath: filePath) {
                            hasExecutable = true
                            break
                        }
                    }
                    if !hasExecutable {
                        issues.append("No executable files found in MacOS directory")
                    }
                }
            } catch {
                issues.append("Cannot read MacOS directory contents")
            }
        }
        
        // Validate Info.plist content
        let infoPlistPath = bundleURL.appendingPathComponent("Contents/Info.plist").path
        if fileManager.fileExists(atPath: infoPlistPath) {
            do {
                let plistData = try Data(contentsOf: URL(fileURLWithPath: infoPlistPath))
                let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
                
                if let plistDict = plist as? [String: Any] {
                    // Check required System Extension keys
                    let requiredKeys = [
                        "CFBundleIdentifier",
                        "CFBundleExecutable",
                        "CFBundlePackageType",
                        "CFBundleShortVersionString"
                    ]
                    
                    for key in requiredKeys where plistDict[key] == nil {
                        issues.append("Missing required Info.plist key: \(key)")
                    }
                    
                    // Validate CFBundlePackageType for System Extensions
                    if let packageType = plistDict["CFBundlePackageType"] as? String {
                        if packageType != "SYSX" {
                            issues.append("Invalid CFBundlePackageType: expected 'SYSX', found '\(packageType)'")
                        }
                    }
                } else {
                    issues.append("Info.plist is not a valid property list dictionary")
                }
            } catch {
                issues.append("Cannot read or parse Info.plist: \(error.localizedDescription)")
            }
        }
        
        logger.debug("Completed bundle validation finished", context: [
            "bundlePath": bundlePath,
            "totalIssues": issues.count
        ])
        
        return issues
    }
    
    // MARK: - Comprehensive Error Handling and Validation
    
    /// Perform comprehensive bundle integrity checking with detailed error reporting
    /// - Parameter bundle: Bundle to validate
    /// - Returns: Array of detailed validation results with remediation steps
    public func performIntegrityCheck(on bundle: SystemExtensionBundle) -> [ValidationResult] {
        var results: [ValidationResult] = []
        let timestamp = Date()
        
        logger.info("Starting comprehensive bundle integrity check", context: [
            "bundlePath": bundle.bundlePath,
            "bundleIdentifier": bundle.bundleIdentifier
        ])
        
        // 1. File system structure validation
        results.append(contentsOf: validateFileSystemStructure(bundle: bundle, timestamp: timestamp))
        
        // 2. Info.plist comprehensive validation
        results.append(contentsOf: validateInfoPlistIntegrity(bundle: bundle, timestamp: timestamp))
        
        // 3. Executable validation and permissions
        results.append(contentsOf: validateExecutableIntegrity(bundle: bundle, timestamp: timestamp))
        
        // 4. Bundle identifier validation
        results.append(contentsOf: validateBundleIdentifier(bundle: bundle, timestamp: timestamp))
        
        // 5. System Extension specific validation
        results.append(contentsOf: validateSystemExtensionRequirements(bundle: bundle, timestamp: timestamp))
        
        // 6. Security and permissions validation
        results.append(contentsOf: validateSecurityRequirements(bundle: bundle, timestamp: timestamp))
        
        let errorCount = results.filter { !$0.passed }.count
        logger.info("Bundle integrity check completed", context: [
            "bundlePath": bundle.bundlePath,
            "totalChecks": results.count,
            "errorCount": errorCount
        ])
        
        return results
    }
    
    /// Validate file system structure with detailed error reporting
    private func validateFileSystemStructure(bundle: SystemExtensionBundle, timestamp: Date) -> [ValidationResult] {
        var results: [ValidationResult] = []
        
        // Check main bundle directory
        if !fileManager.fileExists(atPath: bundle.bundlePath) {
            results.append(ValidationResult(
                checkID: "fs.bundle_directory",
                checkName: "Bundle Directory Exists",
                passed: false,
                message: "Bundle directory does not exist at path: \(bundle.bundlePath)",
                severity: .critical,
                recommendedActions: [
                    "Recreate the bundle directory structure",
                    "Ensure the bundle creation process completed successfully",
                    "Check file system permissions"
                ],
                timestamp: timestamp
            ))
            return results // Cannot continue without main directory
        }
        
        results.append(ValidationResult(
            checkID: "fs.bundle_directory",
            checkName: "Bundle Directory Exists",
            passed: true,
            message: "Bundle directory exists",
            severity: .info,
            timestamp: timestamp
        ))
        
        // Validate required directory structure
        let requiredPaths = [
            ("Contents", "Contents directory"),
            ("Contents/MacOS", "MacOS executable directory"),
            ("Contents/Resources", "Resources directory")
        ]
        
        for (relativePath, description) in requiredPaths {
            let fullPath = URL(fileURLWithPath: bundle.bundlePath).appendingPathComponent(relativePath).path
            let exists = fileManager.fileExists(atPath: fullPath)
            
            results.append(ValidationResult(
                checkID: "fs.\(relativePath.replacingOccurrences(of: "/", with: "_").lowercased())",
                checkName: "\(description) Exists",
                passed: exists,
                message: exists ? "\(description) exists" : "\(description) is missing",
                severity: exists ? .info : .error,
                recommendedActions: exists ? [] : [
                    "Recreate the missing directory: \(relativePath)",
                    "Run bundle creation process again",
                    "Check file system permissions"
                ],
                timestamp: timestamp
            ))
        }
        
        return results
    }
    
    /// Validate Info.plist with comprehensive checks
    private func validateInfoPlistIntegrity(bundle: SystemExtensionBundle, timestamp: Date) -> [ValidationResult] {
        // Helper struct to replace large tuple
        struct InfoPlistKey {
            let key: String
            let description: String
            let critical: Bool
        }
        
        var results: [ValidationResult] = []
        let infoPlistPath = bundle.contents.infoPlistPath
        
        // Check if Info.plist exists
        guard fileManager.fileExists(atPath: infoPlistPath) else {
            results.append(ValidationResult(
                checkID: "plist.exists",
                checkName: "Info.plist Exists",
                passed: false,
                message: "Info.plist file not found at expected location",
                severity: .critical,
                recommendedActions: [
                    "Recreate the Info.plist file",
                    "Ensure bundle creation completed successfully",
                    "Check the bundle contents structure"
                ],
                timestamp: timestamp
            ))
            return results
        }
        
        results.append(ValidationResult(
            checkID: "plist.exists",
            checkName: "Info.plist Exists",
            passed: true,
            message: "Info.plist file exists",
            severity: .info,
            timestamp: timestamp
        ))
        
        // Parse and validate plist content
        do {
            let plistData = try Data(contentsOf: URL(fileURLWithPath: infoPlistPath))
            let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
            
            guard let plistDict = plist as? [String: Any] else {
                results.append(ValidationResult(
                    checkID: "plist.format",
                    checkName: "Info.plist Format",
                    passed: false,
                    message: "Info.plist is not a valid dictionary format",
                    severity: .error,
                    recommendedActions: [
                        "Recreate Info.plist with proper dictionary structure",
                        "Validate XML format with plist editor",
                        "Check for XML parsing errors"
                    ],
                    timestamp: timestamp
                ))
                return results
            }
            
            results.append(ValidationResult(
                checkID: "plist.format",
                checkName: "Info.plist Format",
                passed: true,
                message: "Info.plist has valid dictionary format",
                severity: .info,
                timestamp: timestamp
            ))
            
            // Validate required System Extension keys
            let systemExtensionKeys: [InfoPlistKey] = [
                InfoPlistKey(key: "CFBundleIdentifier", description: "Bundle Identifier", critical: true),
                InfoPlistKey(key: "CFBundleExecutable", description: "Executable Name", critical: true),
                InfoPlistKey(key: "CFBundlePackageType", description: "Package Type", critical: true),
                InfoPlistKey(key: "CFBundleShortVersionString", description: "Version String", critical: true),
                InfoPlistKey(key: "CFBundleVersion", description: "Build Number", critical: true),
                InfoPlistKey(key: "LSMinimumSystemVersion", description: "Minimum System Version", critical: false),
                InfoPlistKey(key: "NSSystemExtensionUsageDescription", description: "Usage Description", critical: false)
            ]
            
            for keyInfo in systemExtensionKeys {
                let exists = plistDict[keyInfo.key] != nil
                let severity: ValidationSeverity = keyInfo.critical ? .error : .warning
                
                var recommendedActions: [String] = []
                if !exists {
                    if keyInfo.critical {
                        recommendedActions = [
                            "Add required key '\(keyInfo.key)' to Info.plist",
                            "Refer to System Extension documentation for proper values",
                            "Regenerate Info.plist with bundle creation tools"
                        ]
                    } else {
                        recommendedActions = [
                            "Consider adding '\(keyInfo.key)' for better compatibility",
                            "Review System Extension best practices"
                        ]
                    }
                }
                
                results.append(ValidationResult(
                    checkID: "plist.key.\(keyInfo.key.lowercased())",
                    checkName: "\(keyInfo.description) Key",
                    passed: exists,
                    message: exists ? "\(keyInfo.description) is present" : "\(keyInfo.description) is missing",
                    severity: exists ? .info : severity,
                    recommendedActions: recommendedActions,
                    timestamp: timestamp
                ))
            }
            
            // Validate specific values
            if let packageType = plistDict["CFBundlePackageType"] as? String {
                let isCorrect = packageType == "SYSX"
                results.append(ValidationResult(
                    checkID: "plist.package_type_value",
                    checkName: "Package Type Value",
                    passed: isCorrect,
                    message: isCorrect ? "Package type is correctly set to 'SYSX'" : "Package type is '\(packageType)', should be 'SYSX'",
                    severity: isCorrect ? .info : .error,
                    recommendedActions: isCorrect ? [] : [
                        "Set CFBundlePackageType to 'SYSX' for System Extensions",
                        "Review System Extension requirements",
                        "Regenerate Info.plist with correct package type"
                    ],
                    timestamp: timestamp
                ))
            }
        } catch {
            results.append(ValidationResult(
                checkID: "plist.parse",
                checkName: "Info.plist Parsing",
                passed: false,
                message: "Failed to parse Info.plist: \(error.localizedDescription)",
                severity: .error,
                recommendedActions: [
                    "Check Info.plist XML syntax",
                    "Validate property list format",
                    "Recreate Info.plist file",
                    "Use Xcode Property List Editor to verify format"
                ],
                timestamp: timestamp
            ))
        }
        
        return results
    }
    
    /// Validate executable integrity and permissions
    private func validateExecutableIntegrity(bundle: SystemExtensionBundle, timestamp: Date) -> [ValidationResult] {
        var results: [ValidationResult] = []
        let executablePath = bundle.contents.executablePath
        
        // Check if executable exists
        guard !executablePath.isEmpty && fileManager.fileExists(atPath: executablePath) else {
            results.append(ValidationResult(
                checkID: "exec.exists",
                checkName: "Executable Exists",
                passed: false,
                message: "Executable not found at expected location: \(executablePath)",
                severity: .critical,
                recommendedActions: [
                    "Copy compiled executable to bundle MacOS directory",
                    "Ensure build process completed successfully",
                    "Check executable path configuration",
                    "Verify file system permissions"
                ],
                timestamp: timestamp
            ))
            return results
        }
        
        results.append(ValidationResult(
            checkID: "exec.exists",
            checkName: "Executable Exists",
            passed: true,
            message: "Executable file exists",
            severity: .info,
            timestamp: timestamp
        ))
        
        // Check executable permissions
        let isExecutable = fileManager.isExecutableFile(atPath: executablePath)
        results.append(ValidationResult(
            checkID: "exec.permissions",
            checkName: "Executable Permissions",
            passed: isExecutable,
            message: isExecutable ? "Executable has proper permissions" : "Executable lacks execute permissions",
            severity: isExecutable ? .info : .error,
            recommendedActions: isExecutable ? [] : [
                "Set executable permissions with: chmod +x \(executablePath)",
                "Ensure file permissions are 755 (rwxr-xr-x)",
                "Check file system mount options"
            ],
            timestamp: timestamp
        ))
        
        // Validate executable architecture and format
        do {
            let attributes = try fileManager.attributesOfItem(atPath: executablePath)
            if let fileSize = attributes[.size] as? Int64 {
                let hasReasonableSize = fileSize > 1000 // At least 1KB
                results.append(ValidationResult(
                    checkID: "exec.size",
                    checkName: "Executable Size",
                    passed: hasReasonableSize,
                    message: hasReasonableSize ? "Executable has reasonable size (\(fileSize) bytes)" : "Executable size seems too small (\(fileSize) bytes)",
                    severity: hasReasonableSize ? .info : .warning,
                    recommendedActions: hasReasonableSize ? [] : [
                        "Verify executable was built correctly",
                        "Check for build errors or incomplete compilation",
                        "Ensure all dependencies are linked"
                    ],
                    timestamp: timestamp
                ))
            }
        } catch {
            results.append(ValidationResult(
                checkID: "exec.attributes",
                checkName: "Executable Attributes",
                passed: false,
                message: "Cannot read executable attributes: \(error.localizedDescription)",
                severity: .warning,
                recommendedActions: [
                    "Check file system permissions",
                    "Verify executable file integrity"
                ],
                timestamp: timestamp
            ))
        }
        
        return results
    }
    
    /// Validate bundle identifier format and uniqueness
    private func validateBundleIdentifier(bundle: SystemExtensionBundle, timestamp: Date) -> [ValidationResult] {
        var results: [ValidationResult] = []
        let bundleId = bundle.bundleIdentifier
        
        // Check reverse DNS format
        let bundleIdPattern = #"^[a-zA-Z0-9][a-zA-Z0-9\-]*(\.[a-zA-Z0-9][a-zA-Z0-9\-]*)+$"#
        let isValidFormat = bundleId.range(of: bundleIdPattern, options: .regularExpression) != nil
        
        results.append(ValidationResult(
            checkID: "bundle_id.format",
            checkName: "Bundle ID Format",
            passed: isValidFormat,
            message: isValidFormat ? "Bundle identifier has valid reverse DNS format" : "Bundle identifier format is invalid: \(bundleId)",
            severity: isValidFormat ? .info : .error,
            recommendedActions: isValidFormat ? [] : [
                "Use reverse DNS format: com.company.product",
                "Avoid special characters except dots and hyphens",
                "Start each component with alphanumeric character",
                "Example: com.example.USBIPSystemExtension"
            ],
            timestamp: timestamp
        ))
        
        // Check for System Extension appropriate naming
        let hasSystemExtensionIndicator = bundleId.lowercased().contains("systemextension") || 
                                        bundleId.lowercased().contains("extension") ||
                                        bundleId.lowercased().contains("sysext")
        
        results.append(ValidationResult(
            checkID: "bundle_id.naming",
            checkName: "Bundle ID Naming Convention",
            passed: hasSystemExtensionIndicator,
            message: hasSystemExtensionIndicator ? "Bundle ID follows System Extension naming conventions" : "Bundle ID should indicate it's a System Extension",
            severity: hasSystemExtensionIndicator ? .info : .warning,
            recommendedActions: hasSystemExtensionIndicator ? [] : [
                "Consider including 'SystemExtension' in bundle ID",
                "Follow Apple's System Extension naming guidelines",
                "Ensure bundle ID clearly identifies the extension type"
            ],
            timestamp: timestamp
        ))
        
        return results
    }
    
    /// Validate System Extension specific requirements
    private func validateSystemExtensionRequirements(bundle: SystemExtensionBundle, timestamp: Date) -> [ValidationResult] {
        var results: [ValidationResult] = []
        
        // Check macOS version compatibility
        let bundleURL = URL(fileURLWithPath: bundle.bundlePath)
        let infoPlistPath = bundleURL.appendingPathComponent("Contents/Info.plist").path
        
        if let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
           let plistDict = plist as? [String: Any],
           let minSystemVersion = plistDict["LSMinimumSystemVersion"] as? String {
            
            let supportsBigSur = minSystemVersion.compare("11.0", options: .numeric) != .orderedDescending
            results.append(ValidationResult(
                checkID: "sysext.macos_version",
                checkName: "macOS Version Compatibility",
                passed: supportsBigSur,
                message: supportsBigSur ? "System Extension supports macOS 11.0+" : "System Extension requires macOS \(minSystemVersion), should support 11.0+",
                severity: supportsBigSur ? .info : .warning,
                recommendedActions: supportsBigSur ? [] : [
                    "Set LSMinimumSystemVersion to '11.0' or lower",
                    "System Extensions require macOS Big Sur (11.0) or later",
                    "Test compatibility with target macOS versions"
                ],
                timestamp: timestamp
            ))
        }
        
        // Check for proper entitlements
        if let entitlementsPath = bundle.contents.entitlementsPath {
            let entitlementsExist = fileManager.fileExists(atPath: entitlementsPath)
            results.append(ValidationResult(
                checkID: "sysext.entitlements",
                checkName: "Entitlements File",
                passed: entitlementsExist,
                message: entitlementsExist ? "Entitlements file is present" : "Entitlements file is missing",
                severity: entitlementsExist ? .info : .warning,
                recommendedActions: entitlementsExist ? [] : [
                    "Create entitlements file for System Extension",
                    "Include required System Extension entitlements",
                    "Refer to Apple documentation for required entitlements"
                ],
                timestamp: timestamp
            ))
        } else {
            results.append(ValidationResult(
                checkID: "sysext.entitlements",
                checkName: "Entitlements File",
                passed: false,
                message: "No entitlements file found",
                severity: .warning,
                recommendedActions: [
                    "Create entitlements file for System Extension",
                    "Include required System Extension entitlements",
                    "Add entitlements during code signing process"
                ],
                timestamp: timestamp
            ))
        }
        
        return results
    }
    
    /// Validate security and permissions requirements
    private func validateSecurityRequirements(bundle: SystemExtensionBundle, timestamp: Date) -> [ValidationResult] {
        var results: [ValidationResult] = []
        
        // Check bundle location security
        let bundlePath = bundle.bundlePath
        let isInSecureLocation = !bundlePath.contains("/tmp/") && 
                                !bundlePath.contains("/var/tmp/") &&
                                !bundlePath.hasPrefix("/private/tmp/")
        
        results.append(ValidationResult(
            checkID: "security.location",
            checkName: "Secure Bundle Location",
            passed: isInSecureLocation,
            message: isInSecureLocation ? "Bundle is in a secure location" : "Bundle is in a temporary or insecure location",
            severity: isInSecureLocation ? .info : .warning,
            recommendedActions: isInSecureLocation ? [] : [
                "Move bundle to a permanent, secure location",
                "Avoid using temporary directories for System Extension bundles",
                "Consider using ~/Library/SystemExtensions or /Library/SystemExtensions"
            ],
            timestamp: timestamp
        ))
        
        // Check for world-writable permissions
        do {
            let attributes = try fileManager.attributesOfItem(atPath: bundlePath)
            if let permissions = attributes[.posixPermissions] as? NSNumber {
                let perms = permissions.uint16Value
                let isWorldWritable = (perms & 0o002) != 0
                
                results.append(ValidationResult(
                    checkID: "security.permissions",
                    checkName: "Bundle Permissions",
                    passed: !isWorldWritable,
                    message: isWorldWritable ? "Bundle has world-writable permissions (security risk)" : "Bundle permissions are secure",
                    severity: isWorldWritable ? .warning : .info,
                    recommendedActions: isWorldWritable ? [
                        "Remove world-write permissions: chmod o-w \(bundlePath)",
                        "Set appropriate permissions (755 for directories, 644 for files)",
                        "Review file system security settings"
                    ] : [],
                    timestamp: timestamp
                ))
            }
        } catch {
            results.append(ValidationResult(
                checkID: "security.permissions",
                checkName: "Bundle Permissions Check",
                passed: false,
                message: "Cannot check bundle permissions: \(error.localizedDescription)",
                severity: .warning,
                recommendedActions: [
                    "Verify file system access permissions",
                    "Check bundle directory exists and is accessible"
                ],
                timestamp: timestamp
            ))
        }
        
        return results
    }
    
    /// Generate detailed remediation report for validation failures
    /// - Parameter validationResults: Results from integrity check
    /// - Returns: Formatted remediation report with prioritized actions
    public func generateRemediationReport(from validationResults: [ValidationResult]) -> String {
        let failures = validationResults.filter { !$0.passed }
        
        if failures.isEmpty {
            return "✅ Bundle validation passed - no issues found"
        }
        
        var report = "❌ Bundle Validation Report - \(failures.count) issue(s) found\n\n"
        
        // Group by severity
        let critical = failures.filter { $0.severity == .critical }
        let errors = failures.filter { $0.severity == .error }
        let warnings = failures.filter { $0.severity == .warning }
        
        if !critical.isEmpty {
            report += "🚨 CRITICAL ISSUES (must fix before installation):\n"
            for result in critical {
                report += formatValidationIssue(result)
            }
            report += "\n"
        }
        
        if !errors.isEmpty {
            report += "❗ ERRORS (should fix before installation):\n"
            for result in errors {
                report += formatValidationIssue(result)
            }
            report += "\n"
        }
        
        if !warnings.isEmpty {
            report += "⚠️  WARNINGS (recommended to fix):\n"
            for result in warnings {
                report += formatValidationIssue(result)
            }
        }
        
        return report
    }
    
    /// Format individual validation issue for reporting
    private func formatValidationIssue(_ result: ValidationResult) -> String {
        var formatted = "  • \(result.checkName): \(result.message)\n"
        
        if !result.recommendedActions.isEmpty {
            formatted += "    Recommended actions:\n"
            for action in result.recommendedActions {
                formatted += "    - \(action)\n"
            }
        }
        
        return formatted
    }
}