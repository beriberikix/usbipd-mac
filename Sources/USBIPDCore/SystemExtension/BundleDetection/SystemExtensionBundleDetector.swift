// SystemExtensionBundleDetector.swift
// Utility for detecting System Extension bundles in build directory structure

import Foundation
import Common

/// Utility for automatically locating System Extension bundles created during build
public struct SystemExtensionBundleDetector {
    
    /// Static bundle identifier for consistent usage across the application
    public static let bundleIdentifier = "com.usbipd.mac.SystemExtension"
    
    /// Detection environment type
    public enum DetectionEnvironment {
        case development(buildPath: String)
        case homebrew(cellarPath: String, version: String?)
        case manual(bundlePath: String)
        case unknown
    }
    
    /// Result of bundle detection operation
    public struct DetectionResult {
        /// Whether a valid bundle was found
        public let found: Bool
        
        /// Path to the detected bundle (if found)
        public let bundlePath: String?
        
        /// Bundle identifier of detected bundle
        public let bundleIdentifier: String?
        
        /// Any issues encountered during detection
        public let issues: [String]
        
        /// Detection timestamp
        public let detectionTime: Date
        
        /// Environment where bundle was detected
        public let detectionEnvironment: DetectionEnvironment
        
        /// Homebrew metadata (if detected in Homebrew environment)
        public let homebrewMetadata: HomebrewMetadata?
        
        /// Paths that were skipped during detection
        public let skippedPaths: [String]
        
        /// Reasons for path rejections
        public let rejectionReasons: [String: RejectionReason]

        public init(
            found: Bool,
            bundlePath: String? = nil,
            bundleIdentifier: String? = nil,
            issues: [String] = [],
            detectionTime: Date = Date(),
            detectionEnvironment: DetectionEnvironment = .unknown,
            homebrewMetadata: HomebrewMetadata? = nil,
            skippedPaths: [String] = [],
            rejectionReasons: [String: RejectionReason] = [:]
        ) {
            self.found = found
            self.bundlePath = bundlePath
            self.bundleIdentifier = bundleIdentifier
            self.issues = issues
            self.detectionTime = detectionTime
            self.detectionEnvironment = detectionEnvironment
            self.homebrewMetadata = homebrewMetadata
            self.skippedPaths = skippedPaths
            self.rejectionReasons = rejectionReasons
        }
    }
    
    /// Metadata information for Homebrew-installed bundles
    public struct HomebrewMetadata: Codable {
        /// Homebrew package version
        public let version: String?
        
        /// Installation timestamp
        public let installationDate: Date?
        
        /// Homebrew formula revision
        public let formulaRevision: String?
        
        /// Installation prefix path
        public let installationPrefix: String?
        
        /// Additional metadata from Homebrew
        public let additionalInfo: [String: String]
        
        public init(
            version: String? = nil,
            installationDate: Date? = nil,
            formulaRevision: String? = nil,
            installationPrefix: String? = nil,
            additionalInfo: [String: String] = [:]
        ) {
            self.version = version
            self.installationDate = installationDate
            self.formulaRevision = formulaRevision
            self.installationPrefix = installationPrefix
            self.additionalInfo = additionalInfo
        }
    }
    
    internal let fileManager: FileManager
    private let logger: Logger
    
    /// Initialize bundle detector with optional custom file manager
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.logger = Logger(config: LoggerConfig(level: .debug), subsystem: "com.usbipd.mac", category: "bundle-detector")
    }
    
    /// Detect System Extension bundle in both development and production environments
    /// - Returns: Detection result with bundle path if found
    public func detectBundle() -> DetectionResult {
        logger.debug("Starting System Extension bundle detection")
        var issues: [String] = []
        var skippedPaths: [String] = []
        var rejectionReasons: [String: RejectionReason] = [:]

        // First try production bundle detection (Homebrew)
        logger.debug("Attempting production bundle detection (Homebrew)")
        let productionResult = detectProductionBundle()
        if productionResult.found {
            logger.info("System Extension bundle found in production environment", context: [
                "bundlePath": productionResult.bundlePath ?? "unknown",
                "environment": formatEnvironmentForLogging(productionResult.detectionEnvironment)
            ])
            return productionResult
        } else {
            logger.debug("Production bundle detection failed, trying development environment")
            issues.append(contentsOf: productionResult.issues)
            skippedPaths.append(contentsOf: productionResult.skippedPaths)
            rejectionReasons.merge(productionResult.rejectionReasons) { _, new in new }
        }
        
        // Fall back to development environment detection
        logger.debug("Attempting development bundle detection")
        guard let currentDirectory = getCurrentDirectory() else {
            let errorMsg = "Unable to determine current working directory"
            logger.warning("Bundle detection failed: \(errorMsg)")
            issues.append(errorMsg)
            return DetectionResult(found: false, issues: issues, skippedPaths: skippedPaths, rejectionReasons: rejectionReasons)
        }
        
        // Look for .build directory
        let buildDirectory = currentDirectory.appendingPathComponent(".build")
        logger.debug("Checking for .build directory", context: ["buildPath": buildDirectory.path])
        guard fileManager.fileExists(atPath: buildDirectory.path) else {
            let errorMsg = "No .build directory found at \(buildDirectory.path)"
            logger.warning("Development bundle detection failed: \(errorMsg)")
            issues.append(errorMsg)
            return DetectionResult(
                found: false,
                issues: issues,
                detectionEnvironment: .development(buildPath: buildDirectory.path),
                skippedPaths: skippedPaths,
                rejectionReasons: rejectionReasons
            )
        }
        
        // Search for System Extension bundles in .build directory
        let searchPaths = getSearchPaths(buildDirectory: buildDirectory)
        logger.debug("Searching for System Extension bundle", context: [
            "searchPaths": searchPaths.count,
            "buildDirectory": buildDirectory.path
        ])
        
        for searchPath in searchPaths {
            logger.debug("Searching path for bundle", context: ["searchPath": searchPath.path])
            let searchResult = findBundleInPath(searchPath)
            skippedPaths.append(contentsOf: searchResult.skippedPaths)
            rejectionReasons.merge(searchResult.rejectionReasons) { _, new in new }

            if let bundlePath = searchResult.bundlePath {
                logger.debug("Found potential bundle, validating", context: ["bundlePath": bundlePath.path])
                // Validate the found bundle
                let validationResult = validateBundle(at: bundlePath)
                if validationResult.isValid {
                    logger.info("System Extension bundle found in development environment", context: [
                        "bundlePath": bundlePath.path,
                        "bundleType": validationResult.bundleType?.rawValue ?? "unknown",
                        "searchPath": searchPath.path
                    ])
                    return DetectionResult(
                        found: true,
                        bundlePath: bundlePath.path,
                        bundleIdentifier: Self.bundleIdentifier,
                        issues: validationResult.issues,
                        detectionEnvironment: .development(buildPath: searchPath.path),
                        skippedPaths: skippedPaths,
                        rejectionReasons: rejectionReasons
                    )
                } else {
                    logger.warning("Bundle validation failed", context: [
                        "bundlePath": bundlePath.path,
                        "rejectionReason": validationResult.rejectionReason?.rawValue ?? "unknown",
                        "issues": validationResult.issues.joined(separator: ", ")
                    ])
                    issues.append(contentsOf: validationResult.issues)
                    if let reason = validationResult.rejectionReason {
                        rejectionReasons[bundlePath.path] = reason
                    }
                }
            }
        }
        
        let finalError = "No valid System Extension bundle found in development or production environments"
        logger.warning("Bundle detection completely failed", context: [
            "totalSkippedPaths": skippedPaths.count,
            "totalIssues": issues.count,
            "searchedPaths": searchPaths.count
        ])
        issues.append(finalError)
        return DetectionResult(
            found: false,
            issues: issues,
            detectionEnvironment: .development(buildPath: buildDirectory.path),
            skippedPaths: skippedPaths,
            rejectionReasons: rejectionReasons
        )
    }
    
    /// Detect System Extension bundle in production Homebrew environment
    /// - Returns: Detection result with bundle path if found in Homebrew installation
    public func detectProductionBundle() -> DetectionResult {
        var issues: [String] = []
        var skippedPaths: [String] = []
        var rejectionReasons: [String: RejectionReason] = [: ]

        // Get Homebrew search paths
        let homebrewPaths = getHomebrewSearchPaths()
        
        if homebrewPaths.isEmpty {
            issues.append("No Homebrew installation paths found at /opt/homebrew/Cellar/usbip/")
            return DetectionResult(
                found: false,
                issues: issues,
                detectionEnvironment: .unknown,
                skippedPaths: skippedPaths,
                rejectionReasons: rejectionReasons
            )
        }
        
        // Search each Homebrew path for System Extension bundles
        for homebrewPath in homebrewPaths {
            let searchResult = findBundleInPath(homebrewPath)
            skippedPaths.append(contentsOf: searchResult.skippedPaths)
            rejectionReasons.merge(searchResult.rejectionReasons) { _, new in new }

            if let bundlePath = searchResult.bundlePath {
                // Validate the found bundle
                let validationResult = validateBundle(at: bundlePath)
                if validationResult.isValid {
                    // Extract version from path (e.g., /opt/homebrew/Cellar/usbip/v1.0.0/…)
                    let versionFromPath = extractVersionFromHomebrewPath(homebrewPath)
                    
                    // Parse Homebrew metadata from bundle
                    let homebrewMetadata = parseHomebrewMetadata(bundlePath: bundlePath)
                    
                    return DetectionResult(
                        found: true,
                        bundlePath: bundlePath.path,
                        bundleIdentifier: Self.bundleIdentifier,
                        issues: validationResult.issues,
                        detectionEnvironment: .homebrew(cellarPath: homebrewPath.path, version: versionFromPath),
                        homebrewMetadata: homebrewMetadata,
                        skippedPaths: skippedPaths,
                        rejectionReasons: rejectionReasons
                    )
                } else {
                    issues.append(contentsOf: validationResult.issues)
                    if let reason = validationResult.rejectionReason {
                        rejectionReasons[bundlePath.path] = reason
                    }
                }
            }
        }
        
        issues.append("No valid System Extension bundle found in Homebrew installation paths")
        return DetectionResult(
            found: false,
            issues: issues,
            detectionEnvironment: .homebrew(cellarPath: "/opt/homebrew/Cellar/usbip", version: nil),
            skippedPaths: skippedPaths,
            rejectionReasons: rejectionReasons
        )
    }
    
    /// Get list of Homebrew search paths for System Extension bundles
    /// - Returns: Array of URLs to search for bundles in Homebrew installations
    private func getHomebrewSearchPaths() -> [URL] {
        var searchPaths: [URL] = []
        
        // Check for Homebrew installation at /opt/homebrew/Cellar/usbip/
        let homebrewCellarPath = URL(fileURLWithPath: "/opt/homebrew/Cellar/usbip")
        
        guard fileManager.fileExists(atPath: homebrewCellarPath.path) else {
            return searchPaths
        }
        
        do {
            // Get all version directories in the Cellar
            let versionDirectories = try fileManager.contentsOfDirectory(
                at: homebrewCellarPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            for versionDir in versionDirectories {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: versionDir.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    // Check for Library/SystemExtensions/ in this version directory
                    let systemExtensionsPath = versionDir
                        .appendingPathComponent("Library")
                        .appendingPathComponent("SystemExtensions")
                    
                    if fileManager.fileExists(atPath: systemExtensionsPath.path) {
                        searchPaths.append(systemExtensionsPath)
                    }
                }
            }
        } catch {
            // If we can't read the directory, just return empty array
            // The caller will handle this appropriately
        }
        
        return searchPaths
    }
    
    /// Extract version from Homebrew path
    /// - Parameter homebrewPath: Path to Homebrew installation directory
    /// - Returns: Version string if found in path
    private func extractVersionFromHomebrewPath(_ homebrewPath: URL) -> String? {
        let pathComponents = homebrewPath.pathComponents
        
        // Look for version pattern in path like: /opt/homebrew/Cellar/usbip/v1.0.0/…
        for component in pathComponents {
            if component.hasPrefix("v") && component.count > 1 {
                return component
            }
            // Also check for semantic version patterns without 'v' prefix
            if component.range(of: "^\\d+\\.\\d+\\.\\d+", options: .regularExpression) != nil {
                return component
            }
        }
        
        return nil
    }
    
    /// Parse Homebrew metadata from bundle
    /// - Parameter bundlePath: Path to System Extension bundle
    /// - Returns: HomebrewMetadata if found and parseable
    private func parseHomebrewMetadata(bundlePath: URL) -> HomebrewMetadata? {
        // Look for HomebrewMetadata.json in bundle Contents directory
        let metadataPath = bundlePath.appendingPathComponent("Contents/HomebrewMetadata.json")
        
        guard fileManager.fileExists(atPath: metadataPath.path) else {
            // No metadata file found - this is not an error, just return nil
            return nil
        }
        
        do {
            let metadataData = try Data(contentsOf: metadataPath)
            let decoder = JSONDecoder()
            
            // Configure decoder for date parsing
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            decoder.dateDecodingStrategy = .formatted(dateFormatter)
            
            let metadata = try decoder.decode(HomebrewMetadata.self, from: metadataData)
            return metadata
        } catch {
            // If we can't parse the metadata, return a basic metadata object with version from path
            let parentPath = bundlePath.deletingLastPathComponent().deletingLastPathComponent()
            let version = extractVersionFromHomebrewPath(parentPath)
            
            return HomebrewMetadata(
                version: version,
                installationDate: nil,
                formulaRevision: nil,
                installationPrefix: "/opt/homebrew",
                additionalInfo: ["parse_error": error.localizedDescription]
            )
        }
    }
    
    /// Get current working directory
    private func getCurrentDirectory() -> URL? {
        let currentPath = fileManager.currentDirectoryPath
        return URL(fileURLWithPath: currentPath)
    }
    
    /// Get list of search paths within .build directory
    private func getSearchPaths(buildDirectory: URL) -> [URL] {
        var searchPaths: [URL] = []
        
        // Common build output paths for Swift Package Manager
        let commonPaths = [
            "debug",
            "release", 
            "x86_64-apple-macosx/debug",
            "x86_64-apple-macosx/release",
            "arm64-apple-macosx/debug",
            "arm64-apple-macosx/release"
        ]
        
        for path in commonPaths {
            let fullPath = buildDirectory.appendingPathComponent(path)
            if fileManager.fileExists(atPath: fullPath.path) {
                searchPaths.append(fullPath)
            }
        }
        
        // If no standard paths found, search the entire .build directory
        if searchPaths.isEmpty {
            searchPaths.append(buildDirectory)
        }
        
        return searchPaths
    }
    
    /// Find System Extension bundle in specific path
    internal func findBundleInPath(_ path: URL) -> BundleSearchResult {
        var skippedPaths: [String] = []
        var rejectionReasons: [String: RejectionReason] = [: ]
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: path,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            for item in contents {
                // Exclude dSYM directories from our search
                if isDSYMPath(item) {
                    logger.debug("Skipping dSYM directory during bundle search", context: [
                        "skippedPath": item.path,
                        "reason": "dSYM directory"
                    ])
                    skippedPaths.append(item.path)
                    rejectionReasons[item.path] = .dSYMPath
                    continue
                }

                // Look for .systemextension bundles (production)
                if item.pathExtension == "systemextension" {
                    logger.debug("Found production bundle (.systemextension)", context: [
                        "bundlePath": item.path,
                        "bundleType": "production"
                    ])
                    return BundleSearchResult(bundlePath: item, skippedPaths: skippedPaths, rejectionReasons: rejectionReasons)
                }
                
                // Look for development SystemExtension executable
                if item.lastPathComponent == "USBIPDSystemExtension" {
                    logger.debug("Found development bundle (executable)", context: [
                        "executablePath": item.path,
                        "bundlePath": path.path,
                        "bundleType": "development"
                    ])
                    // In development mode, return the parent directory as bundle path
                    // This allows the rest of the system to work with development builds
                    return BundleSearchResult(bundlePath: path, skippedPaths: skippedPaths, rejectionReasons: rejectionReasons)
                }
                
                // Recursively search subdirectories
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    let subdirResult = findBundleInPath(item)
                    if let bundlePath = subdirResult.bundlePath {
                        return BundleSearchResult(
                            bundlePath: bundlePath,
                            skippedPaths: skippedPaths + subdirResult.skippedPaths,
                            rejectionReasons: rejectionReasons.merging(subdirResult.rejectionReasons) { _, new in new }
                        )
                    }
                    skippedPaths.append(contentsOf: subdirResult.skippedPaths)
                    rejectionReasons.merge(subdirResult.rejectionReasons) { _, new in new }
                }
            }
        } catch {
            // Silently continue searching other paths
        }
        
        return BundleSearchResult(bundlePath: nil, skippedPaths: skippedPaths, rejectionReasons: rejectionReasons)
    }

    /// Check if a given path is a dSYM bundle
    /// - Parameter path: The URL to check
    /// - Returns: True if the path contains a .dSYM component
    private func isDSYMPath(_ path: URL) -> Bool {
        return path.pathComponents.contains { $0.hasSuffix(".dSYM") }
    }
    
    /// Type of bundle detected
    public enum BundleType: String {
        case development
        case production
    }

    /// Reason for bundle validation rejection
    public enum RejectionReason: String, Codable, Equatable {
        case dSYMPath
        case missingExecutable
        case invalidBundleStructure
        case missingInfoPlist
    }

    /// Result of bundle search operation
    internal struct BundleSearchResult {
        let bundlePath: URL?
        let skippedPaths: [String]
        let rejectionReasons: [String: RejectionReason]
    }

    /// Validation result for bundle
    private struct BundleValidationResult {
        let isValid: Bool
        let issues: [String]
        let bundleType: BundleType?
        let rejectionReason: RejectionReason?
    }
    
    /// Validate found bundle structure and contents
    private func validateBundle(at bundlePath: URL) -> BundleValidationResult {
        logger.debug("Validating bundle structure", context: ["bundlePath": bundlePath.path])
        var issues: [String] = []
        
        // Check if path exists and is a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: bundlePath.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            let errorMsg = "Bundle path does not exist or is not a directory: \(bundlePath.path)"
            logger.warning("Bundle validation failed - invalid path", context: [
                "bundlePath": bundlePath.path,
                "rejectionReason": RejectionReason.invalidBundleStructure.rawValue
            ])
            issues.append(errorMsg)
            return BundleValidationResult(isValid: false, issues: issues, bundleType: nil, rejectionReason: .invalidBundleStructure)
        }
        
        // Check if this is a development environment (has USBIPDSystemExtension executable)
        let developmentExecutablePath = bundlePath.appendingPathComponent("USBIPDSystemExtension")
        if fileManager.fileExists(atPath: developmentExecutablePath.path) {
            // Development mode validation - just check for executable
            let infoMsg = "Development mode bundle detected - SystemExtension executable found"
            logger.info("Bundle validation successful - development bundle", context: [
                "bundlePath": bundlePath.path,
                "bundleType": BundleType.development.rawValue,
                "executablePath": developmentExecutablePath.path
            ])
            issues.append(infoMsg)
            return BundleValidationResult(isValid: true, issues: issues, bundleType: .development, rejectionReason: nil)
        }
        
        // Production mode validation - check for proper bundle structure
        logger.debug("Validating production bundle structure", context: ["bundlePath": bundlePath.path])
        // Check for Info.plist
        let infoPlistPath = bundlePath.appendingPathComponent("Contents/Info.plist")
        guard fileManager.fileExists(atPath: infoPlistPath.path) else {
            let errorMsg = "Missing Info.plist at \(infoPlistPath.path)"
            logger.warning("Bundle validation failed - missing Info.plist", context: [
                "bundlePath": bundlePath.path,
                "rejectionReason": RejectionReason.missingInfoPlist.rawValue,
                "expectedInfoPlistPath": infoPlistPath.path
            ])
            issues.append(errorMsg)
            return BundleValidationResult(isValid: false, issues: issues, bundleType: .production, rejectionReason: .missingInfoPlist)
        }
        
        // Validate Info.plist contents
        do {
            let plistData = try Data(contentsOf: infoPlistPath)
            guard let plist = try PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
            ) as? [String: Any] else {
                issues.append("Invalid Info.plist format")
                return BundleValidationResult(isValid: false, issues: issues, bundleType: .production, rejectionReason: .invalidBundleStructure)
            }
            
            // Check bundle identifier
            guard let bundleId = plist["CFBundleIdentifier"] as? String else {
                issues.append("Missing CFBundleIdentifier in Info.plist")
                return BundleValidationResult(isValid: false, issues: issues, bundleType: .production, rejectionReason: .invalidBundleStructure)
            }
            
            if bundleId != Self.bundleIdentifier {
                issues.append("Bundle identifier mismatch: expected \(Self.bundleIdentifier), found \(bundleId)")
            }
            
            // Check for executable
            if let executableName = plist["CFBundleExecutable"] as? String {
                let executablePath = bundlePath.appendingPathComponent("Contents/MacOS").appendingPathComponent(executableName)
                if !fileManager.fileExists(atPath: executablePath.path) {
                    let errorMsg = "Missing executable at \(executablePath.path)"
                    logger.warning("Bundle validation failed - missing executable", context: [
                        "bundlePath": bundlePath.path,
                        "rejectionReason": RejectionReason.missingExecutable.rawValue,
                        "expectedExecutablePath": executablePath.path,
                        "executableName": executableName
                    ])
                    issues.append(errorMsg)
                    return BundleValidationResult(isValid: false, issues: issues, bundleType: .production, rejectionReason: .missingExecutable)
                }
            } else {
                let errorMsg = "Missing CFBundleExecutable in Info.plist"
                logger.warning("Bundle validation failed - missing CFBundleExecutable", context: [
                    "bundlePath": bundlePath.path,
                    "rejectionReason": RejectionReason.missingExecutable.rawValue,
                    "infoPlistPath": infoPlistPath.path
                ])
                issues.append(errorMsg)
                return BundleValidationResult(isValid: false, issues: issues, bundleType: .production, rejectionReason: .missingExecutable)
            }
        } catch {
            issues.append("Error reading Info.plist: \(error.localizedDescription)")
            return BundleValidationResult(isValid: false, issues: issues, bundleType: .production, rejectionReason: .invalidBundleStructure)
        }
        
        // Bundle is valid if no critical issues found
        let hasExecutableIssues = issues.contains { $0.contains("Missing executable") || $0.contains("Missing CFBundleExecutable") }
        let hasPlistIssues = issues.contains { $0.contains("Info.plist") && !$0.contains("Bundle identifier mismatch") }
        
        let isValid = !hasExecutableIssues && !hasPlistIssues
        
        if isValid {
            logger.info("Bundle validation successful - production bundle", context: [
                "bundlePath": bundlePath.path,
                "bundleType": BundleType.production.rawValue,
                "issueCount": issues.count
            ])
        } else {
            logger.warning("Bundle validation failed - production bundle issues", context: [
                "bundlePath": bundlePath.path,
                "hasExecutableIssues": hasExecutableIssues,
                "hasPlistIssues": hasPlistIssues,
                "totalIssues": issues.count
            ])
        }
        
        return BundleValidationResult(isValid: isValid, issues: issues, bundleType: .production, rejectionReason: nil)
    }
    
    // MARK: - Logging Helpers
    
    /// Format detection environment for structured logging
    private func formatEnvironmentForLogging(_ environment: DetectionEnvironment) -> String {
        switch environment {
        case .development(let buildPath):
            return "development(\(buildPath))"
        case .homebrew(let cellarPath, let version):
            if let version = version {
                return "homebrew(\(cellarPath), \(version))"
            } else {
                return "homebrew(\(cellarPath))"
            }
        case .manual(let bundlePath):
            return "manual(\(bundlePath))"
        case .unknown:
            return "unknown"
        }
    }
}

// MARK: - Bundle Configuration Extensions

extension SystemExtensionBundleConfig {
    /// Create config from detection result
    public static func from(detectionResult: SystemExtensionBundleDetector.DetectionResult) -> SystemExtensionBundleConfig? {
        guard detectionResult.found,
              let bundlePath = detectionResult.bundlePath,
              let bundleIdentifier = detectionResult.bundleIdentifier else {
            return nil
        }
        
        // Get bundle size and modification time
        let fileManager = FileManager.default
        var bundleSize: Int64 = 0
        var modificationTime = Date()
        
        if let attributes = try? fileManager.attributesOfItem(atPath: bundlePath) {
            bundleSize = attributes[.size] as? Int64 ?? 0
            modificationTime = attributes[.modificationDate] as? Date ?? Date()
        }
        
        return SystemExtensionBundleConfig(
            bundlePath: bundlePath,
            bundleIdentifier: bundleIdentifier,
            lastDetectionTime: detectionResult.detectionTime,
            isValid: true,
            installationStatus: "unknown",
            detectionIssues: detectionResult.issues,
            bundleSize: bundleSize,
            modificationTime: modificationTime
        )
    }
}
