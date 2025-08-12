import Foundation
import IOKit
import SystemExtensions
import os.log

/// Comprehensive diagnostic and troubleshooting system for System Extensions
public final class SystemExtensionDiagnostics {
    private let logger = Logger(config: LoggerConfig(level: .info), category: "system-extension-diagnostics")
    private let logQueue = DispatchQueue(label: "com.usbipd.diagnostics.logs", qos: .utility)
    
    public init() {}
    
    // MARK: - Public Interface
    
    /// Performs comprehensive health check of System Extension
    /// - Returns: Complete health report with status and recommendations
    public func performHealthCheck() -> SystemExtensionHealthReport {
        logger.info("Starting System Extension health check")
        
        let startTime = Date()
        var healthChecks: [HealthCheckResult] = []
        var systemInfo: [String: Any] = [:]
        var performanceMetrics: [String: Double] = [:]
        
        // Core System Extension status
        let extensionStatusResult = checkSystemExtensionStatus()
        healthChecks.append(extensionStatusResult)
        
        // Bundle integrity validation
        let bundleIntegrityResult = checkBundleIntegrity()
        healthChecks.append(bundleIntegrityResult)
        
        // System permissions and configuration
        let permissionsResult = checkSystemPermissions()
        healthChecks.append(permissionsResult)
        
        // IOKit integration health
        let ioKitResult = checkIOKitIntegration()
        healthChecks.append(ioKitResult)
        
        // System Extension communication
        let ipcResult = checkIPCCommunication()
        healthChecks.append(ipcResult)
        
        // Performance metrics
        performanceMetrics["health_check_duration"] = Date().timeIntervalSince(startTime)
        performanceMetrics["memory_usage"] = getSystemExtensionMemoryUsage()
        performanceMetrics["cpu_usage"] = getSystemExtensionCPUUsage()
        
        // System information
        systemInfo["macos_version"] = getSystemVersion()
        systemInfo["sip_status"] = getSystemIntegrityProtectionStatus()
        systemInfo["developer_mode"] = getDeveloperModeStatus()
        systemInfo["system_extension_count"] = getInstalledSystemExtensionCount()
        
        let overallHealth = determineOverallHealth(from: healthChecks)
        let recommendations = generateHealthRecommendations(from: healthChecks, overallHealth: overallHealth)
        
        let report = SystemExtensionHealthReport(
            overallHealth: overallHealth,
            healthChecks: healthChecks,
            systemInformation: systemInfo,
            performanceMetrics: performanceMetrics,
            recommendations: recommendations,
            checkTime: Date().timeIntervalSince(startTime),
            timestamp: Date()
        )
        
        logger.info("Health check completed", context: [
            "overall_health": overallHealth.rawValue,
            "checks_performed": healthChecks.count,
            "duration": String(format: "%.2fs", report.checkTime)
        ])
        
        return report
    }
    
    /// Validates System Extension bundle integrity and structure
    /// - Parameter bundlePath: Path to System Extension bundle
    /// - Returns: Detailed bundle validation report
    public func validateBundleIntegrity(bundlePath: String) -> BundleValidationReport {
        logger.info("Starting bundle validation", context: ["bundle_path": bundlePath])
        
        let startTime = Date()
        var validationResults: [BundleValidationResult] = []
        var bundleMetadata: [String: Any] = [:]
        
        // Check if bundle exists and is accessible
        let existenceResult = validateBundleExistence(bundlePath: bundlePath)
        validationResults.append(existenceResult)
        
        guard existenceResult.isValid else {
            return BundleValidationReport(
                bundlePath: bundlePath,
                isValid: false,
                validationResults: validationResults,
                bundleMetadata: bundleMetadata,
                validationTime: Date().timeIntervalSince(startTime),
                timestamp: Date()
            )
        }
        
        // Validate bundle structure
        let structureResult = validateBundleStructure(bundlePath: bundlePath)
        validationResults.append(structureResult)
        
        // Validate Info.plist
        let infoPlistResult = validateInfoPlist(bundlePath: bundlePath)
        validationResults.append(infoPlistResult)
        if let plistData = infoPlistResult.metadata {
            bundleMetadata.merge(plistData) { _, new in new }
        }
        
        // Validate executable
        let executableResult = validateExecutable(bundlePath: bundlePath)
        validationResults.append(executableResult)
        
        // Validate code signing
        let signingResult = validateCodeSigning(bundlePath: bundlePath)
        validationResults.append(signingResult)
        if let signingData = signingResult.metadata {
            bundleMetadata.merge(signingData) { _, new in new }
        }
        
        // Validate entitlements
        let entitlementsResult = validateEntitlements(bundlePath: bundlePath)
        validationResults.append(entitlementsResult)
        
        // Check bundle size and file count
        let sizeResult = validateBundleSize(bundlePath: bundlePath)
        validationResults.append(sizeResult)
        if let sizeData = sizeResult.metadata {
            bundleMetadata.merge(sizeData) { _, new in new }
        }
        
        let isValid = validationResults.allSatisfy { $0.isValid }
        let validationTime = Date().timeIntervalSince(startTime)
        
        let report = BundleValidationReport(
            bundlePath: bundlePath,
            isValid: isValid,
            validationResults: validationResults,
            bundleMetadata: bundleMetadata,
            validationTime: validationTime,
            timestamp: Date()
        )
        
        logger.info("Bundle validation completed", context: [
            "bundle_path": bundlePath,
            "is_valid": isValid,
            "checks_performed": validationResults.count,
            "duration": String(format: "%.2fs", validationTime)
        ])
        
        return report
    }
    
    /// Analyzes system logs for System Extension related issues
    /// - Parameter lookbackHours: How many hours back to search logs
    /// - Returns: Array of log entries related to System Extension issues
    public func analyzeSystemLogs(lookbackHours: Int = 24) -> SystemExtensionLogAnalysis {
        logger.info("Starting system log analysis", context: ["lookback_hours": lookbackHours])
        
        let startTime = Date()
        let cutoffDate = Date().addingTimeInterval(-Double(lookbackHours * 3600))
        
        return logQueue.sync {
            var logEntries: [SystemExtensionLogEntry] = []
            var errorPatterns: [LogErrorPattern] = []
            var warningPatterns: [LogWarningPattern] = []
            
            // Parse system logs for System Extension related entries
            let systemLogs = getSystemExtensionLogs(since: cutoffDate)
            
            for logEntry in systemLogs {
                if let extensionEntry = parseSystemExtensionLogEntry(logEntry) {
                    logEntries.append(extensionEntry)
                    
                    // Analyze for known error patterns
                    if let errorPattern = analyzeForErrorPatterns(entry: extensionEntry) {
                        errorPatterns.append(errorPattern)
                    }
                    
                    // Analyze for warning patterns
                    if let warningPattern = analyzeForWarningPatterns(entry: extensionEntry) {
                        warningPatterns.append(warningPattern)
                    }
                }
            }
            
            // Sort entries by timestamp (newest first)
            logEntries.sort { $0.timestamp > $1.timestamp }
            
            let analysisTime = Date().timeIntervalSince(startTime)
            
            let analysis = SystemExtensionLogAnalysis(
                logEntries: logEntries,
                errorPatterns: errorPatterns,
                warningPatterns: warningPatterns,
                analysisTimeRange: DateInterval(start: cutoffDate, end: Date()),
                analysisTime: analysisTime,
                timestamp: Date()
            )
            
            logger.info("System log analysis completed", context: [
                "log_entries": logEntries.count,
                "error_patterns": errorPatterns.count,
                "warning_patterns": warningPatterns.count,
                "duration": String(format: "%.2fs", analysisTime)
            ])
            
            return analysis
        }
    }
    
    // MARK: - Health Check Implementation
    
    private func checkSystemExtensionStatus() -> HealthCheckResult {
        let extensionIdentifier = "com.usbipd.mac.SystemExtension"
        
        // Check if System Extension is installed and activated
        let installedExtensions = getInstalledSystemExtensions()
        let ourExtension = installedExtensions.first { $0.identifier == extensionIdentifier }
        
        if let extension = ourExtension {
            let isActive = extension.state == .activated
            return HealthCheckResult(
                checkType: .systemExtensionStatus,
                status: isActive ? .healthy : .warning,
                title: "System Extension Status",
                message: isActive ? "System Extension is active" : "System Extension is installed but not active",
                details: [
                    "Bundle ID": extension.identifier,
                    "Version": extension.version.description,
                    "State": extension.state.description
                ],
                recommendations: isActive ? [] : ["Restart the System Extension or check system logs for activation issues"]
            )
        } else {
            return HealthCheckResult(
                checkType: .systemExtensionStatus,
                status: .error,
                title: "System Extension Status",
                message: "System Extension is not installed",
                details: ["Expected Bundle ID": extensionIdentifier],
                recommendations: ["Install the System Extension using installation commands"]
            )
        }
    }
    
    private func checkBundleIntegrity() -> HealthCheckResult {
        // Look for System Extension bundle in common locations
        let commonPaths = [
            ".build/debug/USBIPSystemExtension.systemextension",
            ".build/release/USBIPSystemExtension.systemextension",
            "/usr/local/lib/SystemExtensions/com.usbipd.mac.SystemExtension.systemextension"
        ]
        
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                let validation = validateBundleIntegrity(bundlePath: path)
                
                return HealthCheckResult(
                    checkType: .bundleIntegrity,
                    status: validation.isValid ? .healthy : .error,
                    title: "Bundle Integrity",
                    message: validation.isValid ? "System Extension bundle is valid" : "System Extension bundle has integrity issues",
                    details: [
                        "Bundle Path": path,
                        "Validation Checks": "\(validation.validationResults.count)",
                        "Bundle Size": formatBundleSize(validation.bundleMetadata["bundle_size"] as? Int64)
                    ],
                    recommendations: validation.isValid ? [] : ["Rebuild the System Extension bundle to fix integrity issues"]
                )
            }
        }
        
        return HealthCheckResult(
            checkType: .bundleIntegrity,
            status: .warning,
            title: "Bundle Integrity",
            message: "No System Extension bundle found in common locations",
            details: ["Searched Paths": commonPaths.joined(separator: ", ")],
            recommendations: ["Build the System Extension to create a bundle"]
        )
    }
    
    private func checkSystemPermissions() -> HealthCheckResult {
        let hasFullDiskAccess = checkFullDiskAccess()
        let hasSystemExtensionAccess = checkSystemExtensionAccess()
        let sipEnabled = getSystemIntegrityProtectionStatus()
        
        let allPermissionsGood = hasFullDiskAccess && hasSystemExtensionAccess
        let status: HealthCheckStatus = allPermissionsGood ? .healthy : .warning
        
        var details: [String: String] = [
            "Full Disk Access": hasFullDiskAccess ? "Granted" : "Not granted",
            "System Extension Access": hasSystemExtensionAccess ? "Available" : "Restricted",
            "SIP Status": sipEnabled ? "Enabled" : "Disabled"
        ]
        
        var recommendations: [String] = []
        if !hasFullDiskAccess {
            recommendations.append("Grant Full Disk Access in System Preferences > Privacy & Security")
        }
        if !hasSystemExtensionAccess {
            recommendations.append("Enable System Extension access or Developer Mode")
        }
        
        return HealthCheckResult(
            checkType: .systemPermissions,
            status: status,
            title: "System Permissions",
            message: allPermissionsGood ? "All required permissions are available" : "Some permissions may need attention",
            details: details,
            recommendations: recommendations
        )
    }
    
    private func checkIOKitIntegration() -> HealthCheckResult {
        // Test basic IOKit functionality that System Extension will use
        let ioKitAvailable = testIOKitConnection()
        let usbServicesAvailable = testUSBServices()
        
        let status: HealthCheckStatus
        let message: String
        var recommendations: [String] = []
        
        if ioKitAvailable && usbServicesAvailable {
            status = .healthy
            message = "IOKit integration is functioning properly"
        } else if ioKitAvailable {
            status = .warning
            message = "IOKit is available but USB services may have issues"
            recommendations.append("Check USB service configuration and permissions")
        } else {
            status = .error
            message = "IOKit integration is not functioning"
            recommendations.append("Check system configuration and IOKit framework availability")
        }
        
        return HealthCheckResult(
            checkType: .ioKitIntegration,
            status: status,
            title: "IOKit Integration",
            message: message,
            details: [
                "IOKit Available": ioKitAvailable ? "Yes" : "No",
                "USB Services": usbServicesAvailable ? "Available" : "Not available"
            ],
            recommendations: recommendations
        )
    }
    
    private func checkIPCCommunication() -> HealthCheckResult {
        // Test IPC communication with System Extension
        let ipcAvailable = testIPCConnection()
        
        return HealthCheckResult(
            checkType: .ipcCommunication,
            status: ipcAvailable ? .healthy : .warning,
            title: "IPC Communication",
            message: ipcAvailable ? "IPC communication is working" : "IPC communication is not available",
            details: ["IPC Status": ipcAvailable ? "Connected" : "Not connected"],
            recommendations: ipcAvailable ? [] : ["Ensure System Extension is running and accessible"]
        )
    }
    
    // MARK: - Bundle Validation Implementation
    
    private func validateBundleExistence(bundlePath: String) -> BundleValidationResult {
        let exists = FileManager.default.fileExists(atPath: bundlePath)
        var isDirectory: ObjCBool = false
        
        if exists {
            FileManager.default.fileExists(atPath: bundlePath, isDirectory: &isDirectory)
        }
        
        return BundleValidationResult(
            validationType: .bundleExistence,
            isValid: exists && isDirectory.boolValue,
            message: exists && isDirectory.boolValue ? "Bundle exists and is a directory" : "Bundle does not exist or is not a directory",
            details: ["Path": bundlePath, "Exists": exists ? "Yes" : "No", "Is Directory": isDirectory.boolValue ? "Yes" : "No"],
            metadata: nil
        )
    }
    
    private func validateBundleStructure(bundlePath: String) -> BundleValidationResult {
        let requiredPaths = [
            "Contents/Info.plist",
            "Contents/MacOS",
            "Contents/Library/SystemExtensions"
        ]
        
        var missingPaths: [String] = []
        var presentPaths: [String] = []
        
        for requiredPath in requiredPaths {
            let fullPath = (bundlePath as NSString).appendingPathComponent(requiredPath)
            if FileManager.default.fileExists(atPath: fullPath) {
                presentPaths.append(requiredPath)
            } else {
                missingPaths.append(requiredPath)
            }
        }
        
        let isValid = missingPaths.isEmpty
        
        return BundleValidationResult(
            validationType: .bundleStructure,
            isValid: isValid,
            message: isValid ? "Bundle structure is correct" : "Bundle structure is missing required paths",
            details: [
                "Present Paths": presentPaths.joined(separator: ", "),
                "Missing Paths": missingPaths.joined(separator: ", ")
            ],
            metadata: ["missing_count": missingPaths.count, "present_count": presentPaths.count]
        )
    }
    
    private func validateInfoPlist(bundlePath: String) -> BundleValidationResult {
        let infoPlistPath = (bundlePath as NSString).appendingPathComponent("Contents/Info.plist")
        
        guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            return BundleValidationResult(
                validationType: .infoPlist,
                isValid: false,
                message: "Info.plist not found or invalid",
                details: ["Path": infoPlistPath],
                metadata: nil
            )
        }
        
        let requiredKeys = ["CFBundleIdentifier", "CFBundleVersion", "NSSystemExtensionUsageDescription"]
        var missingKeys: [String] = []
        
        for key in requiredKeys {
            if plist[key] == nil {
                missingKeys.append(key)
            }
        }
        
        let isValid = missingKeys.isEmpty
        let bundleId = plist["CFBundleIdentifier"] as? String ?? "Unknown"
        let version = plist["CFBundleVersion"] as? String ?? "Unknown"
        
        return BundleValidationResult(
            validationType: .infoPlist,
            isValid: isValid,
            message: isValid ? "Info.plist is valid" : "Info.plist is missing required keys",
            details: [
                "Bundle ID": bundleId,
                "Version": version,
                "Missing Keys": missingKeys.joined(separator: ", ")
            ],
            metadata: ["bundle_identifier": bundleId, "bundle_version": version]
        )
    }
    
    private func validateExecutable(bundlePath: String) -> BundleValidationResult {
        let macOSPath = (bundlePath as NSString).appendingPathComponent("Contents/MacOS")
        
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: macOSPath) else {
            return BundleValidationResult(
                validationType: .executable,
                isValid: false,
                message: "MacOS directory not accessible",
                details: ["Path": macOSPath],
                metadata: nil
            )
        }
        
        let executables = contents.filter { filename in
            let fullPath = (macOSPath as NSString).appendingPathComponent(filename)
            return FileManager.default.isExecutableFile(atPath: fullPath)
        }
        
        let hasExecutable = !executables.isEmpty
        
        return BundleValidationResult(
            validationType: .executable,
            isValid: hasExecutable,
            message: hasExecutable ? "Executable found in bundle" : "No executable found in bundle",
            details: [
                "MacOS Path": macOSPath,
                "Executables": executables.joined(separator: ", "),
                "File Count": "\(contents.count)"
            ],
            metadata: ["executable_count": executables.count]
        )
    }
    
    private func validateCodeSigning(bundlePath: String) -> BundleValidationResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-v", bundlePath]
        
        let pipe = Pipe()
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            let isSigned = process.terminationStatus == 0
            
            return BundleValidationResult(
                validationType: .codeSigning,
                isValid: true, // Signing is optional for development
                message: isSigned ? "Bundle is code signed" : "Bundle is not code signed (OK for development)",
                details: [
                    "Signed": isSigned ? "Yes" : "No",
                    "Verification": isSigned ? "Valid" : "Not applicable",
                    "Output": output.isEmpty ? "No errors" : output.trimmingCharacters(in: .whitespacesAndNewlines)
                ],
                metadata: ["is_signed": isSigned]
            )
        } catch {
            return BundleValidationResult(
                validationType: .codeSigning,
                isValid: false,
                message: "Unable to verify code signing",
                details: ["Error": error.localizedDescription],
                metadata: nil
            )
        }
    }
    
    private func validateEntitlements(bundlePath: String) -> BundleValidationResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--entitlements", "-", bundlePath]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let hasEntitlements = !data.isEmpty
            
            return BundleValidationResult(
                validationType: .entitlements,
                isValid: true, // Entitlements check is informational
                message: hasEntitlements ? "Bundle has entitlements" : "Bundle has no entitlements (may be unsigned)",
                details: ["Has Entitlements": hasEntitlements ? "Yes" : "No"],
                metadata: nil
            )
        } catch {
            return BundleValidationResult(
                validationType: .entitlements,
                isValid: true,
                message: "Unable to check entitlements (may be unsigned)",
                details: ["Error": error.localizedDescription],
                metadata: nil
            )
        }
    }
    
    private func validateBundleSize(bundlePath: String) -> BundleValidationResult {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: bundlePath),
              let size = attributes[.size] as? Int64 else {
            return BundleValidationResult(
                validationType: .bundleSize,
                isValid: false,
                message: "Unable to determine bundle size",
                details: ["Path": bundlePath],
                metadata: nil
            )
        }
        
        let sizeInMB = Double(size) / (1024 * 1024)
        let isReasonableSize = size > 1024 && sizeInMB < 100 // Between 1KB and 100MB
        
        return BundleValidationResult(
            validationType: .bundleSize,
            isValid: isReasonableSize,
            message: isReasonableSize ? "Bundle size is reasonable" : "Bundle size is outside expected range",
            details: [
                "Size (bytes)": "\(size)",
                "Size (MB)": String(format: "%.2f", sizeInMB),
                "Range Check": isReasonableSize ? "Pass" : "Fail"
            ],
            metadata: ["bundle_size": size, "bundle_size_mb": sizeInMB]
        )
    }
    
    // MARK: - System Information Helpers
    
    private func determineOverallHealth(from healthChecks: [HealthCheckResult]) -> HealthCheckStatus {
        if healthChecks.contains(where: { $0.status == .error }) {
            return .error
        } else if healthChecks.contains(where: { $0.status == .warning }) {
            return .warning
        } else {
            return .healthy
        }
    }
    
    private func generateHealthRecommendations(from healthChecks: [HealthCheckResult], overallHealth: HealthCheckStatus) -> [String] {
        let allRecommendations = healthChecks.flatMap { $0.recommendations }
        let uniqueRecommendations = Array(Set(allRecommendations))
        
        // Prioritize critical recommendations first
        let criticalRecommendations = healthChecks
            .filter { $0.status == .error }
            .flatMap { $0.recommendations }
        
        let warningRecommendations = healthChecks
            .filter { $0.status == .warning }
            .flatMap { $0.recommendations }
        
        return Array(Set(criticalRecommendations + warningRecommendations))
    }
    
    private func getSystemExtensionMemoryUsage() -> Double {
        // Placeholder implementation - would use system APIs to get actual memory usage
        return 0.0
    }
    
    private func getSystemExtensionCPUUsage() -> Double {
        // Placeholder implementation - would use system APIs to get actual CPU usage
        return 0.0
    }
    
    private func getSystemVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    
    private func getSystemIntegrityProtectionStatus() -> Bool {
        // Simplified SIP check
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
        process.arguments = ["status"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return output.contains("enabled")
        } catch {
            return true // Assume enabled if we can't check
        }
    }
    
    private func getDeveloperModeStatus() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
        process.arguments = ["developer"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return output.lowercased().contains("on")
        } catch {
            return false
        }
    }
    
    private func getInstalledSystemExtensionCount() -> Int {
        return getInstalledSystemExtensions().count
    }
    
    private func getInstalledSystemExtensions() -> [SystemExtensionProperties] {
        // Placeholder - would use SystemExtensions framework to get actual extensions
        return []
    }
    
    private func formatBundleSize(_ size: Int64?) -> String {
        guard let size = size else { return "Unknown" }
        
        if size < 1024 {
            return "\(size) bytes"
        } else if size < 1024 * 1024 {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(size) / (1024.0 * 1024.0))
        }
    }
    
    // MARK: - System Testing Helpers
    
    private func checkFullDiskAccess() -> Bool {
        // Test if we can read system directories that require Full Disk Access
        let testPaths = [
            "/Users",
            "/System/Library/Extensions"
        ]
        
        for path in testPaths {
            if !FileManager.default.isReadableFile(atPath: path) {
                return false
            }
        }
        return true
    }
    
    private func checkSystemExtensionAccess() -> Bool {
        // Check if system extension functionality is available
        return FileManager.default.fileExists(atPath: "/usr/bin/systemextensionsctl")
    }
    
    private func testIOKitConnection() -> Bool {
        // Test basic IOKit functionality
        let masterPort = kIOMainPortDefault
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(masterPort, matchingDict, &iterator)
        
        if result == KERN_SUCCESS {
            IOObjectRelease(iterator)
            return true
        }
        
        return false
    }
    
    private func testUSBServices() -> Bool {
        // Test USB-specific IOKit services
        return testIOKitConnection() // Simplified for now
    }
    
    private func testIPCConnection() -> Bool {
        // Test IPC connection to System Extension
        // This would attempt to connect to the actual System Extension
        return false // Placeholder - would implement actual IPC test
    }
    
    // MARK: - Comprehensive Diagnostic Reporting
    
    /// Analyzes installation issues and provides specific remediation steps
    /// - Returns: Array of installation issues with detailed analysis
    public func analyzeInstallationIssues() -> [InstallationIssue] {
        logger.info("Starting installation issue analysis")
        
        var issues: [InstallationIssue] = []
        
        // Analyze System Extension status
        let extensionStatus = checkSystemExtensionStatus()
        if extensionStatus.status != .healthy {
            issues.append(InstallationIssue(
                issueType: .systemExtensionNotLoaded,
                severity: extensionStatus.status == .error ? .critical : .warning,
                title: "System Extension Status Issue",
                description: extensionStatus.message,
                affectedComponents: ["System Extension Framework"],
                detectedConditions: extensionStatus.details,
                rootCause: analyzeSystemExtensionRootCause(from: extensionStatus),
                remediationSteps: generateSystemExtensionRemediationSteps(from: extensionStatus),
                automatedFixAvailable: false,
                relatedLogEntries: getRelatedLogEntries(for: .systemExtensionNotLoaded),
                estimatedResolutionTime: "5-15 minutes"
            ))
        }
        
        // Analyze bundle issues
        let bundleStatus = checkBundleIntegrity()
        if bundleStatus.status != .healthy {
            issues.append(InstallationIssue(
                issueType: .bundleIntegrityFailed,
                severity: .critical,
                title: "Bundle Integrity Issue",
                description: bundleStatus.message,
                affectedComponents: ["System Extension Bundle"],
                detectedConditions: bundleStatus.details,
                rootCause: "System Extension bundle is missing, corrupted, or has structural issues",
                remediationSteps: [
                    "1. Rebuild the System Extension: swift build --product SystemExtension",
                    "2. Verify bundle structure in .build directory",
                    "3. Check for build errors in compilation output",
                    "4. Ensure proper code signing if required"
                ],
                automatedFixAvailable: false,
                relatedLogEntries: getRelatedLogEntries(for: .bundleIntegrityFailed),
                estimatedResolutionTime: "10-30 minutes"
            ))
        }
        
        // Analyze permission issues
        let permissionStatus = checkSystemPermissions()
        if permissionStatus.status == .warning || permissionStatus.status == .error {
            issues.append(InstallationIssue(
                issueType: .insufficientPermissions,
                severity: permissionStatus.status == .error ? .critical : .warning,
                title: "Permission Configuration Issue",
                description: permissionStatus.message,
                affectedComponents: ["System Permissions", "Privacy Settings"],
                detectedConditions: permissionStatus.details,
                rootCause: analyzePermissionRootCause(from: permissionStatus),
                remediationSteps: generatePermissionRemediationSteps(from: permissionStatus),
                automatedFixAvailable: false,
                relatedLogEntries: getRelatedLogEntries(for: .insufficientPermissions),
                estimatedResolutionTime: "5-10 minutes"
            ))
        }
        
        // Analyze IOKit integration
        let ioKitStatus = checkIOKitIntegration()
        if ioKitStatus.status != .healthy {
            issues.append(InstallationIssue(
                issueType: .ioKitIntegrationFailed,
                severity: .critical,
                title: "IOKit Integration Issue",
                description: ioKitStatus.message,
                affectedComponents: ["IOKit Framework", "USB Services"],
                detectedConditions: ioKitStatus.details,
                rootCause: "IOKit framework is not accessible or USB services are unavailable",
                remediationSteps: [
                    "1. Check system integrity: sudo fsck -f /",
                    "2. Reset USB subsystem: sudo kextunload -b com.apple.iokit.IOUSBFamily && sudo kextload -b com.apple.iokit.IOUSBFamily",
                    "3. Restart the system if issues persist",
                    "4. Verify macOS version compatibility"
                ],
                automatedFixAvailable: false,
                relatedLogEntries: getRelatedLogEntries(for: .ioKitIntegrationFailed),
                estimatedResolutionTime: "15-45 minutes"
            ))
        }
        
        // Check for System Extension conflicts
        let conflicts = detectSystemExtensionConflicts()
        if !conflicts.isEmpty {
            issues.append(InstallationIssue(
                issueType: .systemExtensionConflict,
                severity: .warning,
                title: "System Extension Conflicts",
                description: "Multiple System Extensions may be conflicting",
                affectedComponents: ["System Extension Framework"],
                detectedConditions: ["conflicting_extensions": conflicts.joined(separator: ", ")],
                rootCause: "Multiple System Extensions with similar functionality are installed",
                remediationSteps: [
                    "1. List all installed System Extensions: systemextensionsctl list",
                    "2. Remove conflicting extensions: systemextensionsctl uninstall <bundle-id>",
                    "3. Restart the system after removal",
                    "4. Reinstall the desired System Extension"
                ],
                automatedFixAvailable: false,
                relatedLogEntries: getRelatedLogEntries(for: .systemExtensionConflict),
                estimatedResolutionTime: "10-20 minutes"
            ))
        }
        
        // Check for developer mode issues
        if !getDeveloperModeStatus() {
            let hasSignedBundles = checkForSignedBundles()
            if !hasSignedBundles {
                issues.append(InstallationIssue(
                    issueType: .developerModeRequired,
                    severity: .warning,
                    title: "Developer Mode Required",
                    description: "Unsigned System Extensions require Developer Mode to be enabled",
                    affectedComponents: ["System Extension Framework", "Security Policy"],
                    detectedConditions: ["developer_mode": "disabled", "signed_bundles": "none_found"],
                    rootCause: "Developer Mode is disabled and no signed System Extension bundles are available",
                    remediationSteps: [
                        "1. Enable Developer Mode: sudo systemextensionsctl developer on",
                        "2. Restart the system to apply changes",
                        "3. Or alternatively, obtain proper code signing certificates",
                        "4. Rebuild with signed certificates if available"
                    ],
                    automatedFixAvailable: false,
                    relatedLogEntries: getRelatedLogEntries(for: .developerModeRequired),
                    estimatedResolutionTime: "5-10 minutes"
                ))
            }
        }
        
        logger.info("Installation issue analysis completed", context: ["issues_found": issues.count])
        return issues
    }
    
    /// Detects conflicts between System Extensions
    /// - Returns: Array of conflicting System Extension bundle identifiers
    public func detectSystemExtensionConflicts() -> [String] {
        let installedExtensions = getInstalledSystemExtensions()
        var conflicts: [String] = []
        
        // Look for multiple USB/IOKit related System Extensions
        let usbRelatedKeywords = ["usb", "iokit", "device", "hardware"]
        let usbExtensions = installedExtensions.filter { ext in
            usbRelatedKeywords.contains { keyword in
                ext.identifier.lowercased().contains(keyword)
            }
        }
        
        if usbExtensions.count > 1 {
            conflicts.append(contentsOf: usbExtensions.map { $0.identifier })
        }
        
        return conflicts
    }
    
    /// Generates formatted diagnostic report
    /// - Parameter format: Output format for the report
    /// - Returns: Formatted diagnostic report string
    public func generateDiagnosticReport(format: DiagnosticReportFormat = .text) -> String {
        let healthReport = performHealthCheck()
        let installationIssues = analyzeInstallationIssues()
        let logAnalysis = analyzeSystemLogs(lookbackHours: 24)
        
        switch format {
        case .text:
            return generateTextReport(healthReport: healthReport, issues: installationIssues, logAnalysis: logAnalysis)
        case .json:
            return generateJSONReport(healthReport: healthReport, issues: installationIssues, logAnalysis: logAnalysis)
        case .markdown:
            return generateMarkdownReport(healthReport: healthReport, issues: installationIssues, logAnalysis: logAnalysis)
        }
    }
    
    // MARK: - Report Generation
    
    private func generateTextReport(healthReport: SystemExtensionHealthReport, issues: [InstallationIssue], logAnalysis: SystemExtensionLogAnalysis) -> String {
        var report = ""
        
        // Header
        report += "=== System Extension Diagnostic Report ===\n"
        report += "Generated: \(ISO8601DateFormatter().string(from: Date()))\n"
        report += "Overall Health: \(healthReport.overallHealth.displayName)\n\n"
        
        // Health Check Summary
        report += "--- Health Check Results ---\n"
        for check in healthReport.healthChecks {
            let statusIcon = check.status == .healthy ? "✓" : check.status == .warning ? "⚠" : "✗"
            report += "\(statusIcon) \(check.title): \(check.message)\n"
            
            if !check.details.isEmpty {
                for (key, value) in check.details {
                    report += "  • \(key): \(value)\n"
                }
            }
            
            if !check.recommendations.isEmpty {
                report += "  Recommendations:\n"
                for recommendation in check.recommendations {
                    report += "    - \(recommendation)\n"
                }
            }
            report += "\n"
        }
        
        // Installation Issues
        if !issues.isEmpty {
            report += "--- Installation Issues (\(issues.count)) ---\n"
            for (index, issue) in issues.enumerated() {
                let severityIcon = issue.severity == .critical ? "🔴" : issue.severity == .warning ? "🟡" : "🔵"
                report += "\(index + 1). \(severityIcon) \(issue.title)\n"
                report += "   Description: \(issue.description)\n"
                report += "   Root Cause: \(issue.rootCause)\n"
                report += "   Estimated Resolution Time: \(issue.estimatedResolutionTime)\n"
                
                if !issue.remediationSteps.isEmpty {
                    report += "   Resolution Steps:\n"
                    for step in issue.remediationSteps {
                        report += "     \(step)\n"
                    }
                }
                report += "\n"
            }
        }
        
        // Log Analysis Summary
        if !logAnalysis.logEntries.isEmpty || !logAnalysis.errorPatterns.isEmpty {
            report += "--- Log Analysis ---\n"
            report += "Log Entries Analyzed: \(logAnalysis.logEntries.count)\n"
            report += "Error Patterns Found: \(logAnalysis.errorPatterns.count)\n"
            report += "Warning Patterns Found: \(logAnalysis.warningPatterns.count)\n\n"
            
            // Recent errors
            let recentErrors = logAnalysis.errorPatterns.prefix(5)
            if !recentErrors.isEmpty {
                report += "Recent Error Patterns:\n"
                for error in recentErrors {
                    report += "  • \(error.keyword): \(error.message.prefix(100))...\n"
                }
                report += "\n"
            }
        }
        
        // Performance Metrics
        if !healthReport.performanceMetrics.isEmpty {
            report += "--- Performance Metrics ---\n"
            for (metric, value) in healthReport.performanceMetrics {
                let formattedValue = metric.contains("time") || metric.contains("duration") ? 
                    String(format: "%.2fs", value) : String(format: "%.2f", value)
                report += "• \(metric.replacingOccurrences(of: "_", with: " ").capitalized): \(formattedValue)\n"
            }
            report += "\n"
        }
        
        // Recommendations Summary
        if !healthReport.recommendations.isEmpty {
            report += "--- Priority Recommendations ---\n"
            for (index, recommendation) in healthReport.recommendations.enumerated() {
                report += "\(index + 1). \(recommendation)\n"
            }
        }
        
        return report
    }
    
    private func generateJSONReport(healthReport: SystemExtensionHealthReport, issues: [InstallationIssue], logAnalysis: SystemExtensionLogAnalysis) -> String {
        let reportData: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "overall_health": healthReport.overallHealth.rawValue,
            "health_checks": healthReport.healthChecks.map { check in
                [
                    "type": check.checkType.rawValue,
                    "status": check.status.rawValue,
                    "title": check.title,
                    "message": check.message,
                    "details": check.details,
                    "recommendations": check.recommendations
                ]
            },
            "installation_issues": issues.map { issue in
                [
                    "type": issue.issueType.rawValue,
                    "severity": issue.severity.rawValue,
                    "title": issue.title,
                    "description": issue.description,
                    "root_cause": issue.rootCause,
                    "remediation_steps": issue.remediationSteps,
                    "estimated_resolution_time": issue.estimatedResolutionTime
                ]
            },
            "log_analysis": [
                "entries_count": logAnalysis.logEntries.count,
                "error_patterns_count": logAnalysis.errorPatterns.count,
                "warning_patterns_count": logAnalysis.warningPatterns.count,
                "analysis_time": logAnalysis.analysisTime
            ],
            "performance_metrics": healthReport.performanceMetrics,
            "recommendations": healthReport.recommendations
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: reportData, options: [.prettyPrinted]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{\"error\": \"Failed to serialize diagnostic report\"}"
        }
        
        return jsonString
    }
    
    private func generateMarkdownReport(healthReport: SystemExtensionHealthReport, issues: [InstallationIssue], logAnalysis: SystemExtensionLogAnalysis) -> String {
        var report = ""
        
        // Header
        report += "# System Extension Diagnostic Report\n\n"
        report += "**Generated:** \(ISO8601DateFormatter().string(from: Date()))\n"
        report += "**Overall Health:** \(healthReport.overallHealth.displayName)\n\n"
        
        // Health Check Results
        report += "## Health Check Results\n\n"
        for check in healthReport.healthChecks {
            let statusEmoji = check.status == .healthy ? "✅" : check.status == .warning ? "⚠️" : "❌"
            report += "### \(statusEmoji) \(check.title)\n\n"
            report += "**Status:** \(check.message)\n\n"
            
            if !check.details.isEmpty {
                report += "**Details:**\n"
                for (key, value) in check.details {
                    report += "- **\(key):** \(value)\n"
                }
                report += "\n"
            }
            
            if !check.recommendations.isEmpty {
                report += "**Recommendations:**\n"
                for recommendation in check.recommendations {
                    report += "- \(recommendation)\n"
                }
                report += "\n"
            }
        }
        
        // Installation Issues
        if !issues.isEmpty {
            report += "## Installation Issues (\(issues.count))\n\n"
            for (index, issue) in issues.enumerated() {
                let severityEmoji = issue.severity == .critical ? "🔴" : issue.severity == .warning ? "🟡" : "🔵"
                report += "### \(index + 1). \(severityEmoji) \(issue.title)\n\n"
                report += "**Description:** \(issue.description)\n\n"
                report += "**Root Cause:** \(issue.rootCause)\n\n"
                report += "**Estimated Resolution Time:** \(issue.estimatedResolutionTime)\n\n"
                
                if !issue.remediationSteps.isEmpty {
                    report += "**Resolution Steps:**\n"
                    for step in issue.remediationSteps {
                        report += "\(step)\n"
                    }
                    report += "\n"
                }
            }
        }
        
        // Log Analysis
        if !logAnalysis.logEntries.isEmpty || !logAnalysis.errorPatterns.isEmpty {
            report += "## Log Analysis\n\n"
            report += "- **Log Entries Analyzed:** \(logAnalysis.logEntries.count)\n"
            report += "- **Error Patterns Found:** \(logAnalysis.errorPatterns.count)\n"
            report += "- **Warning Patterns Found:** \(logAnalysis.warningPatterns.count)\n\n"
        }
        
        // Recommendations
        if !healthReport.recommendations.isEmpty {
            report += "## Priority Recommendations\n\n"
            for (index, recommendation) in healthReport.recommendations.enumerated() {
                report += "\(index + 1). \(recommendation)\n"
            }
        }
        
        return report
    }
    
    // MARK: - Helper Methods for Issue Analysis
    
    private func analyzeSystemExtensionRootCause(from result: HealthCheckResult) -> String {
        if result.details["State"] == "Deactivated" {
            return "System Extension is installed but not activated, likely due to user approval pending or system policy restrictions"
        } else if result.status == .error {
            return "System Extension is not installed or installation failed"
        } else {
            return "System Extension state is unclear, may require user intervention or system restart"
        }
    }
    
    private func generateSystemExtensionRemediationSteps(from result: HealthCheckResult) -> [String] {
        if result.status == .error {
            return [
                "1. Install the System Extension: swift build && Scripts/install-extension.sh",
                "2. Check system logs for installation errors",
                "3. Ensure proper permissions and Developer Mode if needed",
                "4. Restart the system if installation appears successful but extension is not active"
            ]
        } else if result.details["State"] == "Deactivated" {
            return [
                "1. Restart the System Extension: systemextensionsctl reset",
                "2. Check System Preferences > Privacy & Security for approval requests",
                "3. Approve the System Extension if prompted",
                "4. Verify system logs for activation errors"
            ]
        } else {
            return result.recommendations
        }
    }
    
    private func analyzePermissionRootCause(from result: HealthCheckResult) -> String {
        let details = result.details
        var causes: [String] = []
        
        if details["Full Disk Access"] == "Not granted" {
            causes.append("Full Disk Access permission not granted")
        }
        if details["System Extension Access"] == "Restricted" {
            causes.append("System Extension access is restricted")
        }
        if details["SIP Status"] == "Enabled" && details["System Extension Access"] == "Restricted" {
            causes.append("System Integrity Protection may be blocking unsigned extensions")
        }
        
        return causes.isEmpty ? "Permission configuration issue" : causes.joined(separator: ", ")
    }
    
    private func generatePermissionRemediationSteps(from result: HealthCheckResult) -> [String] {
        var steps: [String] = []
        let details = result.details
        
        if details["Full Disk Access"] == "Not granted" {
            steps.append("1. Open System Preferences > Security & Privacy > Privacy")
            steps.append("2. Select 'Full Disk Access' from the left sidebar")
            steps.append("3. Add the USB/IP application to the allowed list")
        }
        
        if details["System Extension Access"] == "Restricted" {
            steps.append("4. Check System Preferences > Security & Privacy > General for System Extension approval")
            steps.append("5. Or enable Developer Mode: sudo systemextensionsctl developer on")
        }
        
        if details["SIP Status"] == "Enabled" && !getDeveloperModeStatus() {
            steps.append("6. Consider enabling Developer Mode for development or obtaining proper certificates")
        }
        
        return steps.isEmpty ? result.recommendations : steps
    }
    
    private func checkForSignedBundles() -> Bool {
        let commonPaths = [
            ".build/debug/USBIPSystemExtension.systemextension",
            ".build/release/USBIPSystemExtension.systemextension"
        ]
        
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                let validation = validateCodeSigning(bundlePath: path)
                if let isSigned = validation.metadata?["is_signed"] as? Bool, isSigned {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func getRelatedLogEntries(for issueType: InstallationIssueType) -> [String] {
        let logAnalysis = analyzeSystemLogs(lookbackHours: 4) // Recent logs only
        
        let relevantKeywords: [String]
        switch issueType {
        case .systemExtensionNotLoaded:
            relevantKeywords = ["systemextensions", "extension", "activate", "load"]
        case .bundleIntegrityFailed:
            relevantKeywords = ["bundle", "invalid", "corrupt", "missing"]
        case .insufficientPermissions:
            relevantKeywords = ["permission", "denied", "access", "privacy"]
        case .ioKitIntegrationFailed:
            relevantKeywords = ["iokit", "usb", "device", "hardware"]
        case .systemExtensionConflict:
            relevantKeywords = ["conflict", "duplicate", "already"]
        case .developerModeRequired:
            relevantKeywords = ["developer", "unsigned", "certificate"]
        }
        
        return logAnalysis.logEntries
            .filter { entry in
                relevantKeywords.contains { keyword in
                    entry.message.lowercased().contains(keyword)
                }
            }
            .prefix(5)
            .map { $0.message }
    }
    
    // MARK: - Log Analysis Helpers
    
    private func getSystemExtensionLogs(since: Date) -> [String] {
        // Simplified log retrieval - would use more sophisticated log parsing
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--predicate", "subsystem CONTAINS 'systemextensions' OR subsystem CONTAINS 'usbipd'",
            "--start", ISO8601DateFormatter().string(from: since)
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        } catch {
            logger.error("Failed to retrieve system logs", context: ["error": error.localizedDescription])
            return []
        }
    }
    
    private func parseSystemExtensionLogEntry(_ logLine: String) -> SystemExtensionLogEntry? {
        // Simple log parsing - would implement more sophisticated parsing
        guard !logLine.isEmpty else { return nil }
        
        return SystemExtensionLogEntry(
            timestamp: Date(), // Would parse actual timestamp
            level: .info, // Would parse actual level
            subsystem: "unknown", // Would parse actual subsystem
            category: "unknown", // Would parse actual category
            message: logLine,
            processName: "unknown"
        )
    }
    
    private func analyzeForErrorPatterns(entry: SystemExtensionLogEntry) -> LogErrorPattern? {
        let errorKeywords = ["error", "failed", "denied", "invalid", "corrupt"]
        
        for keyword in errorKeywords {
            if entry.message.lowercased().contains(keyword) {
                return LogErrorPattern(
                    patternType: .generalError,
                    keyword: keyword,
                    message: entry.message,
                    frequency: 1,
                    firstOccurrence: entry.timestamp,
                    lastOccurrence: entry.timestamp
                )
            }
        }
        
        return nil
    }
    
    private func analyzeForWarningPatterns(entry: SystemExtensionLogEntry) -> LogWarningPattern? {
        let warningKeywords = ["warning", "deprecated", "retry", "timeout"]
        
        for keyword in warningKeywords {
            if entry.message.lowercased().contains(keyword) {
                return LogWarningPattern(
                    patternType: .generalWarning,
                    keyword: keyword,
                    message: entry.message,
                    frequency: 1,
                    firstOccurrence: entry.timestamp,
                    lastOccurrence: entry.timestamp
                )
            }
        }
        
        return nil
    }
}

// MARK: - Supporting Types

/// Overall health check status
public enum HealthCheckStatus: String, Codable, CaseIterable {
    case healthy = "healthy"
    case warning = "warning"
    case error = "error"
    
    public var displayName: String {
        switch self {
        case .healthy: return "Healthy"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }
}

/// Type of health check performed
public enum HealthCheckType: String, Codable, CaseIterable {
    case systemExtensionStatus = "system_extension_status"
    case bundleIntegrity = "bundle_integrity"
    case systemPermissions = "system_permissions"
    case ioKitIntegration = "iokit_integration"
    case ipcCommunication = "ipc_communication"
}

/// Result of individual health check
public struct HealthCheckResult: Codable {
    /// Type of check performed
    public let checkType: HealthCheckType
    
    /// Overall status of this check
    public let status: HealthCheckStatus
    
    /// Human-readable title
    public let title: String
    
    /// Status message
    public let message: String
    
    /// Detailed information
    public let details: [String: String]
    
    /// Recommendations to address issues
    public let recommendations: [String]
    
    public init(
        checkType: HealthCheckType,
        status: HealthCheckStatus,
        title: String,
        message: String,
        details: [String: String],
        recommendations: [String]
    ) {
        self.checkType = checkType
        self.status = status
        self.title = title
        self.message = message
        self.details = details
        self.recommendations = recommendations
    }
}

/// Comprehensive System Extension health report
public struct SystemExtensionHealthReport: Codable {
    /// Overall health status
    public let overallHealth: HealthCheckStatus
    
    /// Individual health check results
    public let healthChecks: [HealthCheckResult]
    
    /// System information
    public let systemInformation: [String: Any]
    
    /// Performance metrics
    public let performanceMetrics: [String: Double]
    
    /// Prioritized recommendations
    public let recommendations: [String]
    
    /// Time taken for health check
    public let checkTime: TimeInterval
    
    /// Report timestamp
    public let timestamp: Date
    
    public init(
        overallHealth: HealthCheckStatus,
        healthChecks: [HealthCheckResult],
        systemInformation: [String: Any],
        performanceMetrics: [String: Double],
        recommendations: [String],
        checkTime: TimeInterval,
        timestamp: Date
    ) {
        self.overallHealth = overallHealth
        self.healthChecks = healthChecks
        self.systemInformation = systemInformation
        self.performanceMetrics = performanceMetrics
        self.recommendations = recommendations
        self.checkTime = checkTime
        self.timestamp = timestamp
    }
    
    // Custom Codable implementation for [String: Any]
    private enum CodingKeys: String, CodingKey {
        case overallHealth, healthChecks, performanceMetrics
        case recommendations, checkTime, timestamp
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(overallHealth, forKey: .overallHealth)
        try container.encode(healthChecks, forKey: .healthChecks)
        try container.encode(performanceMetrics, forKey: .performanceMetrics)
        try container.encode(recommendations, forKey: .recommendations)
        try container.encode(checkTime, forKey: .checkTime)
        try container.encode(timestamp, forKey: .timestamp)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overallHealth = try container.decode(HealthCheckStatus.self, forKey: .overallHealth)
        healthChecks = try container.decode([HealthCheckResult].self, forKey: .healthChecks)
        performanceMetrics = try container.decode([String: Double].self, forKey: .performanceMetrics)
        recommendations = try container.decode([String].self, forKey: .recommendations)
        checkTime = try container.decode(TimeInterval.self, forKey: .checkTime)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        systemInformation = [:] // Not persisted in Codable representation
    }
}

// MARK: - Bundle Validation Types

/// Type of bundle validation performed
public enum BundleValidationType: String, Codable, CaseIterable {
    case bundleExistence = "bundle_existence"
    case bundleStructure = "bundle_structure"
    case infoPlist = "info_plist"
    case executable = "executable"
    case codeSigning = "code_signing"
    case entitlements = "entitlements"
    case bundleSize = "bundle_size"
}

/// Result of individual bundle validation
public struct BundleValidationResult: Codable {
    /// Type of validation performed
    public let validationType: BundleValidationType
    
    /// Whether this validation passed
    public let isValid: Bool
    
    /// Validation message
    public let message: String
    
    /// Detailed information
    public let details: [String: String]
    
    /// Additional metadata
    public let metadata: [String: Any]?
    
    public init(
        validationType: BundleValidationType,
        isValid: Bool,
        message: String,
        details: [String: String],
        metadata: [String: Any]?
    ) {
        self.validationType = validationType
        self.isValid = isValid
        self.message = message
        self.details = details
        self.metadata = metadata
    }
    
    // Custom Codable implementation for [String: Any]
    private enum CodingKeys: String, CodingKey {
        case validationType, isValid, message, details
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(validationType, forKey: .validationType)
        try container.encode(isValid, forKey: .isValid)
        try container.encode(message, forKey: .message)
        try container.encode(details, forKey: .details)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        validationType = try container.decode(BundleValidationType.self, forKey: .validationType)
        isValid = try container.decode(Bool.self, forKey: .isValid)
        message = try container.decode(String.self, forKey: .message)
        details = try container.decode([String: String].self, forKey: .details)
        metadata = nil // Not persisted in Codable representation
    }
}

/// Complete bundle validation report
public struct BundleValidationReport: Codable {
    /// Path to validated bundle
    public let bundlePath: String
    
    /// Overall validation result
    public let isValid: Bool
    
    /// Individual validation results
    public let validationResults: [BundleValidationResult]
    
    /// Bundle metadata extracted during validation
    public let bundleMetadata: [String: Any]
    
    /// Time taken for validation
    public let validationTime: TimeInterval
    
    /// Validation timestamp
    public let timestamp: Date
    
    public init(
        bundlePath: String,
        isValid: Bool,
        validationResults: [BundleValidationResult],
        bundleMetadata: [String: Any],
        validationTime: TimeInterval,
        timestamp: Date
    ) {
        self.bundlePath = bundlePath
        self.isValid = isValid
        self.validationResults = validationResults
        self.bundleMetadata = bundleMetadata
        self.validationTime = validationTime
        self.timestamp = timestamp
    }
    
    // Custom Codable implementation for [String: Any]
    private enum CodingKeys: String, CodingKey {
        case bundlePath, isValid, validationResults, validationTime, timestamp
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundlePath, forKey: .bundlePath)
        try container.encode(isValid, forKey: .isValid)
        try container.encode(validationResults, forKey: .validationResults)
        try container.encode(validationTime, forKey: .validationTime)
        try container.encode(timestamp, forKey: .timestamp)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundlePath = try container.decode(String.self, forKey: .bundlePath)
        isValid = try container.decode(Bool.self, forKey: .isValid)
        validationResults = try container.decode([BundleValidationResult].self, forKey: .validationResults)
        validationTime = try container.decode(TimeInterval.self, forKey: .validationTime)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        bundleMetadata = [:] // Not persisted in Codable representation
    }
}

// MARK: - Log Analysis Types

/// System Extension log entry
public struct SystemExtensionLogEntry: Codable {
    /// Log entry timestamp
    public let timestamp: Date
    
    /// Log level
    public let level: LogLevel
    
    /// Log subsystem
    public let subsystem: String
    
    /// Log category
    public let category: String
    
    /// Log message
    public let message: String
    
    /// Process name
    public let processName: String
    
    public init(
        timestamp: Date,
        level: LogLevel,
        subsystem: String,
        category: String,
        message: String,
        processName: String
    ) {
        self.timestamp = timestamp
        self.level = level
        self.subsystem = subsystem
        self.category = category
        self.message = message
        self.processName = processName
    }
}

/// Log level for analysis
public enum LogLevel: String, Codable, CaseIterable {
    case debug
    case info
    case warning
    case error
    case fault
}

/// Error pattern found in logs
public struct LogErrorPattern: Codable {
    /// Type of error pattern
    public let patternType: ErrorPatternType
    
    /// Keyword that triggered the pattern
    public let keyword: String
    
    /// Example message
    public let message: String
    
    /// Frequency of this pattern
    public let frequency: Int
    
    /// First occurrence
    public let firstOccurrence: Date
    
    /// Last occurrence  
    public let lastOccurrence: Date
    
    public init(
        patternType: ErrorPatternType,
        keyword: String,
        message: String,
        frequency: Int,
        firstOccurrence: Date,
        lastOccurrence: Date
    ) {
        self.patternType = patternType
        self.keyword = keyword
        self.message = message
        self.frequency = frequency
        self.firstOccurrence = firstOccurrence
        self.lastOccurrence = lastOccurrence
    }
}

/// Type of error pattern
public enum ErrorPatternType: String, Codable, CaseIterable {
    case generalError = "general_error"
    case authenticationError = "authentication_error"
    case permissionError = "permission_error"
    case ioKitError = "iokit_error"
    case bundleError = "bundle_error"
}

/// Warning pattern found in logs
public struct LogWarningPattern: Codable {
    /// Type of warning pattern
    public let patternType: WarningPatternType
    
    /// Keyword that triggered the pattern
    public let keyword: String
    
    /// Example message
    public let message: String
    
    /// Frequency of this pattern
    public let frequency: Int
    
    /// First occurrence
    public let firstOccurrence: Date
    
    /// Last occurrence
    public let lastOccurrence: Date
    
    public init(
        patternType: WarningPatternType,
        keyword: String,
        message: String,
        frequency: Int,
        firstOccurrence: Date,
        lastOccurrence: Date
    ) {
        self.patternType = patternType
        self.keyword = keyword
        self.message = message
        self.frequency = frequency
        self.firstOccurrence = firstOccurrence
        self.lastOccurrence = lastOccurrence
    }
}

/// Type of warning pattern
public enum WarningPatternType: String, Codable, CaseIterable {
    case generalWarning = "general_warning"
    case performanceWarning = "performance_warning"
    case deprecationWarning = "deprecation_warning"
    case configurationWarning = "configuration_warning"
}

/// Complete log analysis result
public struct SystemExtensionLogAnalysis: Codable {
    /// Parsed log entries
    public let logEntries: [SystemExtensionLogEntry]
    
    /// Error patterns found
    public let errorPatterns: [LogErrorPattern]
    
    /// Warning patterns found
    public let warningPatterns: [LogWarningPattern]
    
    /// Time range analyzed
    public let analysisTimeRange: DateInterval
    
    /// Time taken for analysis
    public let analysisTime: TimeInterval
    
    /// Analysis timestamp
    public let timestamp: Date
    
    public init(
        logEntries: [SystemExtensionLogEntry],
        errorPatterns: [LogErrorPattern],
        warningPatterns: [LogWarningPattern],
        analysisTimeRange: DateInterval,
        analysisTime: TimeInterval,
        timestamp: Date
    ) {
        self.logEntries = logEntries
        self.errorPatterns = errorPatterns
        self.warningPatterns = warningPatterns
        self.analysisTimeRange = analysisTimeRange
        self.analysisTime = analysisTime
        self.timestamp = timestamp
    }
}

/// System Extension properties for diagnostics
public struct SystemExtensionProperties {
    public let identifier: String
    public let version: OperatingSystemVersion
    public let state: SystemExtensionState
    
    public init(identifier: String, version: OperatingSystemVersion, state: SystemExtensionState) {
        self.identifier = identifier
        self.version = version
        self.state = state
    }
}

/// System Extension state
public enum SystemExtensionState {
    case deactivated
    case activated
    case unknown
    
    var description: String {
        switch self {
        case .deactivated: return "Deactivated"
        case .activated: return "Activated"  
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Installation Issue Types

/// Specific installation issue types
public enum InstallationIssueType: String, Codable, CaseIterable {
    case systemExtensionNotLoaded = "system_extension_not_loaded"
    case bundleIntegrityFailed = "bundle_integrity_failed"
    case insufficientPermissions = "insufficient_permissions"
    case ioKitIntegrationFailed = "iokit_integration_failed"
    case systemExtensionConflict = "system_extension_conflict"
    case developerModeRequired = "developer_mode_required"
}

/// Detailed installation issue with analysis and remediation
public struct InstallationIssue: Codable {
    /// Type of installation issue
    public let issueType: InstallationIssueType
    
    /// Issue severity level
    public let severity: ValidationSeverity
    
    /// Human-readable title
    public let title: String
    
    /// Detailed description
    public let description: String
    
    /// System components affected
    public let affectedComponents: [String]
    
    /// Specific conditions detected
    public let detectedConditions: [String: String]
    
    /// Root cause analysis
    public let rootCause: String
    
    /// Step-by-step remediation instructions
    public let remediationSteps: [String]
    
    /// Whether automated fix is available
    public let automatedFixAvailable: Bool
    
    /// Related log entries
    public let relatedLogEntries: [String]
    
    /// Estimated time to resolve
    public let estimatedResolutionTime: String
    
    public init(
        issueType: InstallationIssueType,
        severity: ValidationSeverity,
        title: String,
        description: String,
        affectedComponents: [String],
        detectedConditions: [String: String],
        rootCause: String,
        remediationSteps: [String],
        automatedFixAvailable: Bool,
        relatedLogEntries: [String],
        estimatedResolutionTime: String
    ) {
        self.issueType = issueType
        self.severity = severity
        self.title = title
        self.description = description
        self.affectedComponents = affectedComponents
        self.detectedConditions = detectedConditions
        self.rootCause = rootCause
        self.remediationSteps = remediationSteps
        self.automatedFixAvailable = automatedFixAvailable
        self.relatedLogEntries = relatedLogEntries
        self.estimatedResolutionTime = estimatedResolutionTime
    }
}

/// Diagnostic report output format
public enum DiagnosticReportFormat: String, CaseIterable {
    case text
    case json
    case markdown
    
    public var displayName: String {
        switch self {
        case .text: return "Plain Text"
        case .json: return "JSON"
        case .markdown: return "Markdown"
        }
    }
    
    public var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .json: return "json"
        case .markdown: return "md"
        }
    }
}