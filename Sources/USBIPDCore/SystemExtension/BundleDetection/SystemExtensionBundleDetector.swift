// SystemExtensionBundleDetector.swift
// Utility for detecting System Extension bundles in build directory structure

import Foundation

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
        
        public init(
            found: Bool,
            bundlePath: String? = nil,
            bundleIdentifier: String? = nil,
            issues: [String] = [],
            detectionTime: Date = Date(),
            detectionEnvironment: DetectionEnvironment = .unknown,
            homebrewMetadata: HomebrewMetadata? = nil
        ) {
            self.found = found
            self.bundlePath = bundlePath
            self.bundleIdentifier = bundleIdentifier
            self.issues = issues
            self.detectionTime = detectionTime
            self.detectionEnvironment = detectionEnvironment
            self.homebrewMetadata = homebrewMetadata
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
    
    private let fileManager: FileManager
    
    /// Initialize bundle detector with optional custom file manager
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }
    
    /// Detect System Extension bundle in both development and production environments
    /// - Returns: Detection result with bundle path if found
    public func detectBundle() -> DetectionResult {
        var issues: [String] = []
        
        // First try production bundle detection (Homebrew)
        let productionResult = detectProductionBundle()
        if productionResult.found {
            return productionResult
        } else {
            issues.append(contentsOf: productionResult.issues)
        }
        
        // Fall back to development environment detection
        guard let currentDirectory = getCurrentDirectory() else {
            issues.append("Unable to determine current working directory")
            return DetectionResult(found: false, issues: issues)
        }
        
        // Look for .build directory
        let buildDirectory = currentDirectory.appendingPathComponent(".build")
        guard fileManager.fileExists(atPath: buildDirectory.path) else {
            issues.append("No .build directory found at \(buildDirectory.path)")
            return DetectionResult(
                found: false, 
                issues: issues,
                detectionEnvironment: .development(buildPath: buildDirectory.path)
            )
        }
        
        // Search for System Extension bundles in .build directory
        let searchPaths = getSearchPaths(buildDirectory: buildDirectory)
        
        for searchPath in searchPaths {
            if let bundlePath = findBundleInPath(searchPath) {
                // Validate the found bundle
                let validationResult = validateBundle(at: bundlePath)
                if validationResult.isValid {
                    return DetectionResult(
                        found: true,
                        bundlePath: bundlePath.path,
                        bundleIdentifier: Self.bundleIdentifier,
                        issues: validationResult.issues,
                        detectionEnvironment: .development(buildPath: searchPath.path)
                    )
                } else {
                    issues.append(contentsOf: validationResult.issues)
                }
            }
        }
        
        issues.append("No valid System Extension bundle found in development or production environments")
        return DetectionResult(
            found: false, 
            issues: issues,
            detectionEnvironment: .development(buildPath: buildDirectory.path)
        )
    }
    
    /// Detect System Extension bundle in production Homebrew environment
    /// - Returns: Detection result with bundle path if found in Homebrew installation
    public func detectProductionBundle() -> DetectionResult {
        var issues: [String] = []
        
        // Get Homebrew search paths
        let homebrewPaths = getHomebrewSearchPaths()
        
        if homebrewPaths.isEmpty {
            issues.append("No Homebrew installation paths found at /opt/homebrew/Cellar/usbipd-mac/")
            return DetectionResult(
                found: false, 
                issues: issues,
                detectionEnvironment: .unknown
            )
        }
        
        // Search each Homebrew path for System Extension bundles
        for homebrewPath in homebrewPaths {
            if let bundlePath = findBundleInPath(homebrewPath) {
                // Validate the found bundle
                let validationResult = validateBundle(at: bundlePath)
                if validationResult.isValid {
                    // Extract version from path (e.g., /opt/homebrew/Cellar/usbipd-mac/v1.0.0/...)
                    let versionFromPath = extractVersionFromHomebrewPath(homebrewPath)
                    
                    // Parse Homebrew metadata from bundle
                    let homebrewMetadata = parseHomebrewMetadata(bundlePath: bundlePath)
                    
                    return DetectionResult(
                        found: true,
                        bundlePath: bundlePath.path,
                        bundleIdentifier: Self.bundleIdentifier,
                        issues: validationResult.issues,
                        detectionEnvironment: .homebrew(cellarPath: homebrewPath.path, version: versionFromPath),
                        homebrewMetadata: homebrewMetadata
                    )
                } else {
                    issues.append(contentsOf: validationResult.issues)
                }
            }
        }
        
        issues.append("No valid System Extension bundle found in Homebrew installation paths")
        return DetectionResult(
            found: false, 
            issues: issues,
            detectionEnvironment: .homebrew(cellarPath: "/opt/homebrew/Cellar/usbipd-mac", version: nil)
        )
    }
    
    /// Get list of Homebrew search paths for System Extension bundles
    /// - Returns: Array of URLs to search for bundles in Homebrew installations
    private func getHomebrewSearchPaths() -> [URL] {
        var searchPaths: [URL] = []
        
        // Check for Homebrew installation at /opt/homebrew/Cellar/usbipd-mac/
        let homebrewCellarPath = URL(fileURLWithPath: "/opt/homebrew/Cellar/usbipd-mac")
        
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
        
        // Look for version pattern in path like: /opt/homebrew/Cellar/usbipd-mac/v1.0.0/...
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
    private func findBundleInPath(_ path: URL) -> URL? {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: path,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            for item in contents {
                // Look for .systemextension bundles
                if item.pathExtension == "systemextension" {
                    return item
                }
                
                // Recursively search subdirectories
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    if let bundleInSubdir = findBundleInPath(item) {
                        return bundleInSubdir
                    }
                }
            }
        } catch {
            // Silently continue searching other paths
        }
        
        return nil
    }
    
    /// Validation result for bundle
    private struct BundleValidationResult {
        let isValid: Bool
        let issues: [String]
    }
    
    /// Validate found bundle structure and contents
    private func validateBundle(at bundlePath: URL) -> BundleValidationResult {
        var issues: [String] = []
        
        // Check if path exists and is a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: bundlePath.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            issues.append("Bundle path does not exist or is not a directory: \(bundlePath.path)")
            return BundleValidationResult(isValid: false, issues: issues)
        }
        
        // Check for Info.plist
        let infoPlistPath = bundlePath.appendingPathComponent("Contents/Info.plist")
        guard fileManager.fileExists(atPath: infoPlistPath.path) else {
            issues.append("Missing Info.plist at \(infoPlistPath.path)")
            return BundleValidationResult(isValid: false, issues: issues)
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
                return BundleValidationResult(isValid: false, issues: issues)
            }
            
            // Check bundle identifier
            guard let bundleId = plist["CFBundleIdentifier"] as? String else {
                issues.append("Missing CFBundleIdentifier in Info.plist")
                return BundleValidationResult(isValid: false, issues: issues)
            }
            
            if bundleId != Self.bundleIdentifier {
                issues.append("Bundle identifier mismatch: expected \(Self.bundleIdentifier), found \(bundleId)")
            }
            
            // Check for executable
            if let executableName = plist["CFBundleExecutable"] as? String {
                let executablePath = bundlePath.appendingPathComponent("Contents/MacOS").appendingPathComponent(executableName)
                if !fileManager.fileExists(atPath: executablePath.path) {
                    issues.append("Missing executable at \(executablePath.path)")
                }
            } else {
                issues.append("Missing CFBundleExecutable in Info.plist")
            }
        } catch {
            issues.append("Error reading Info.plist: \(error.localizedDescription)")
            return BundleValidationResult(isValid: false, issues: issues)
        }
        
        // Bundle is valid if no critical issues found
        let hasExecutableIssues = issues.contains { $0.contains("Missing executable") || $0.contains("Missing CFBundleExecutable") }
        let hasPlistIssues = issues.contains { $0.contains("Info.plist") && !$0.contains("Bundle identifier mismatch") }
        
        let isValid = !hasExecutableIssues && !hasPlistIssues
        return BundleValidationResult(isValid: isValid, issues: issues)
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