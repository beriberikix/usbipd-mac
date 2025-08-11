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
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
    case fault = "fault"
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