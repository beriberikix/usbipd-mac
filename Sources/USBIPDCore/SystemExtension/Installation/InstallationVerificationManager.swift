// InstallationVerificationManager.swift
// Installation verification manager for System Extension status validation

import Foundation
import SystemExtensions
import Common

/// Manager for verifying System Extension installation status and generating diagnostic reports
public final class InstallationVerificationManager: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.github.usbipd-mac", category: "InstallationVerificationManager")
    
    /// Bundle identifier to verify
    private let bundleIdentifier: String
    
    /// Expected installation path patterns
    private let expectedPaths: [String]
    
    // MARK: - Initialization
    
    /// Initialize installation verification manager
    /// - Parameters:
    ///   - bundleIdentifier: Bundle identifier of the System Extension to verify
    ///   - expectedPaths: Expected installation paths to check
    public init(bundleIdentifier: String = "com.github.usbipd-mac.systemextension", expectedPaths: [String] = []) {
        self.bundleIdentifier = bundleIdentifier
        self.expectedPaths = expectedPaths.isEmpty ? [
            "/opt/homebrew/Cellar/usbip/*/Library/SystemExtensions/",
            "/usr/local/Cellar/usbip/*/Library/SystemExtensions/",
            "./build/SystemExtension/"
        ] : expectedPaths
        
        logger.info("InstallationVerificationManager initialized", context: [
            "bundleIdentifier": bundleIdentifier,
            "expectedPaths": expectedPaths.count
        ])
    }
    
    // MARK: - Public Interface
    
    /// Verify System Extension installation status
    /// - Returns: Comprehensive verification result
    public func verifyInstallation() async -> InstallationVerificationResult {
        logger.info("Starting System Extension installation verification")
        
        let startTime = Date()
        var verificationChecks: [VerificationCheck] = []
        var discoveredIssues: [VerificationInstallationIssue] = []
        
        // Check 1: System Extension registry status
        let registryCheck = await checkSystemExtensionRegistry()
        verificationChecks.append(registryCheck)
        if !registryCheck.passed {
            discoveredIssues.append(contentsOf: registryCheck.issues)
        }
        
        // Check 2: Bundle file existence and integrity
        let bundleCheck = await checkBundleIntegrity()
        verificationChecks.append(bundleCheck)
        if !bundleCheck.passed {
            discoveredIssues.append(contentsOf: bundleCheck.issues)
        }
        
        // Check 3: Process and runtime status
        let runtimeCheck = await checkRuntimeStatus()
        verificationChecks.append(runtimeCheck)
        if !runtimeCheck.passed {
            discoveredIssues.append(contentsOf: runtimeCheck.issues)
        }
        
        // Check 4: Permissions and entitlements
        let permissionsCheck = await checkPermissionsAndEntitlements()
        verificationChecks.append(permissionsCheck)
        if !permissionsCheck.passed {
            discoveredIssues.append(contentsOf: permissionsCheck.issues)
        }
        
        // Check 5: Service integration
        let serviceCheck = await checkServiceIntegration()
        verificationChecks.append(serviceCheck)
        if !serviceCheck.passed {
            discoveredIssues.append(contentsOf: serviceCheck.issues)
        }
        
        // Determine overall status
        let overallStatus = determineInstallationStatus(from: verificationChecks)
        let verificationTime = Date().timeIntervalSince(startTime)
        
        let result = InstallationVerificationResult(
            status: overallStatus,
            verificationChecks: verificationChecks,
            discoveredIssues: discoveredIssues,
            verificationTimestamp: Date(),
            verificationDuration: verificationTime,
            bundleIdentifier: bundleIdentifier,
            summary: generateVerificationSummary(status: overallStatus, checks: verificationChecks)
        )
        
        logger.info("Installation verification completed", context: [
            "status": overallStatus.rawValue,
            "checks": verificationChecks.count,
            "issues": discoveredIssues.count,
            "duration": verificationTime
        ])
        
        return result
    }
    
    /// Generate comprehensive diagnostic report
    /// - Returns: Detailed diagnostic report with troubleshooting information
    public func generateDiagnosticReport() async -> InstallationDiagnosticReport {
        logger.info("Generating comprehensive diagnostic report")
        
        let verificationResult = await verifyInstallation()
        
        // Gather system information
        let systemInfo = await gatherSystemInformation()
        
        // Collect detailed logs
        let systemLogs = await collectSystemLogs()
        
        // Analyze configuration
        let configAnalysis = await analyzeSystemConfiguration()
        
        // Generate recommendations
        let recommendations = generateRecommendations(
            from: verificationResult,
            systemInfo: systemInfo,
            configAnalysis: configAnalysis
        )
        
        let report = InstallationDiagnosticReport(
            verificationResult: verificationResult,
            systemInformation: systemInfo,
            systemLogs: systemLogs,
            configurationAnalysis: configAnalysis,
            recommendations: recommendations,
            reportTimestamp: Date(),
            reportVersion: "1.0"
        )
        
        logger.info("Diagnostic report generated", context: [
            "recommendations": recommendations.count,
            "logEntries": systemLogs.count
        ])
        
        return report
    }
    
    /// Detect specific installation issues
    /// - Returns: Array of detected issues with details
    public func detectInstallationIssues() async -> [DetectedInstallationIssue] {
        logger.info("Detecting installation issues")
        
        var detectedIssues: [DetectedInstallationIssue] = []
        
        // Check for common installation problems
        let commonIssues = await detectCommonIssues()
        detectedIssues.append(contentsOf: commonIssues)
        
        // Check for permission issues
        let permissionIssues = await detectPermissionIssues()
        detectedIssues.append(contentsOf: permissionIssues)
        
        // Check for configuration problems
        let configIssues = await detectConfigurationIssues()
        detectedIssues.append(contentsOf: configIssues)
        
        // Check for environment-specific issues
        let environmentIssues = await detectEnvironmentIssues()
        detectedIssues.append(contentsOf: environmentIssues)
        
        logger.info("Installation issue detection completed", context: [
            "totalIssues": detectedIssues.count
        ])
        
        return detectedIssues
    }
    
    /// Verify System Extension is properly loaded and functional
    /// - Returns: Functional verification result
    public func verifySystemExtensionFunctionality() async -> FunctionalVerificationResult {
        logger.info("Verifying System Extension functionality")
        
        var functionalityChecks: [FunctionalityCheck] = []
        
        // Check extension loading
        let loadingCheck = await checkExtensionLoading()
        functionalityChecks.append(loadingCheck)
        
        // Check communication capabilities
        let communicationCheck = await checkExtensionCommunication()
        functionalityChecks.append(communicationCheck)
        
        // Check device interaction
        let deviceCheck = await checkDeviceInteraction()
        functionalityChecks.append(deviceCheck)
        
        // Check network capabilities
        let networkCheck = await checkNetworkCapabilities()
        functionalityChecks.append(networkCheck)
        
        let overallFunctional = functionalityChecks.allSatisfy { $0.passed }
        
        return FunctionalVerificationResult(
            isFunctional: overallFunctional,
            functionalityChecks: functionalityChecks,
            verificationTimestamp: Date()
        )
    }
    
    // MARK: - System Extension Registry Verification
    
    private func checkSystemExtensionRegistry() async -> VerificationCheck {
        logger.debug("Checking System Extension registry status")
        
        do {
            let output = try await executeSystemExtensionsCtl(command: "list")
            let analysis = parseSystemExtensionsList(output)
            
            if analysis.isRegistered && analysis.isEnabled && analysis.isActive {
                return VerificationCheck(
                    checkID: "registry_status",
                    checkName: "System Extension Registry",
                    passed: true,
                    message: "System Extension is properly registered, enabled, and active",
                    severity: .info,
                    details: "Extension found in registry with correct status",
                    issues: []
                )
            } else if analysis.isRegistered && analysis.isEnabled {
                return VerificationCheck(
                    checkID: "registry_status",
                    checkName: "System Extension Registry",
                    passed: false,
                    message: "System Extension is registered but not active",
                    severity: .warning,
                    details: "Extension may require restart or user approval",
                    issues: [.extensionNotActive]
                )
            } else if analysis.isRegistered {
                return VerificationCheck(
                    checkID: "registry_status",
                    checkName: "System Extension Registry",
                    passed: false,
                    message: "System Extension is registered but not enabled",
                    severity: .error,
                    details: "Extension registration incomplete or failed",
                    issues: [.extensionNotEnabled]
                )
            } else {
                return VerificationCheck(
                    checkID: "registry_status",
                    checkName: "System Extension Registry",
                    passed: false,
                    message: "System Extension is not registered",
                    severity: .critical,
                    details: "Extension not found in system registry",
                    issues: [.extensionNotRegistered]
                )
            }
        } catch {
            logger.error("Failed to check registry status", context: ["error": error.localizedDescription])
            return VerificationCheck(
                checkID: "registry_status",
                checkName: "System Extension Registry",
                passed: false,
                message: "Failed to query System Extension registry",
                severity: .critical,
                details: "systemextensionsctl command failed: \(error.localizedDescription)",
                issues: [.systemCommandFailed]
            )
        }
    }
    
    private func checkBundleIntegrity() async -> VerificationCheck {
        logger.debug("Checking bundle integrity")
        
        var foundBundles: [String] = []
        var validBundles: [String] = []
        var issues: [VerificationInstallationIssue] = []
        
        // Check all expected paths
        for pathPattern in expectedPaths {
            let foundPaths = expandPathPattern(pathPattern)
            for path in foundPaths {
                let bundlePath = "\(path)/\(bundleIdentifier).systemextension"
                if FileManager.default.fileExists(atPath: bundlePath) {
                    foundBundles.append(bundlePath)
                    
                    // Validate bundle
                    if await validateBundle(at: bundlePath) {
                        validBundles.append(bundlePath)
                    } else {
                        issues.append(.bundleCorrupted)
                    }
                }
            }
        }
        
        if validBundles.isEmpty && foundBundles.isEmpty {
            return VerificationCheck(
                checkID: "bundle_integrity",
                checkName: "Bundle Integrity",
                passed: false,
                message: "No System Extension bundles found",
                severity: .critical,
                details: "Searched paths: \(expectedPaths.joined(separator: ", "))",
                issues: [.bundleNotFound]
            )
        } else if validBundles.isEmpty {
            return VerificationCheck(
                checkID: "bundle_integrity",
                checkName: "Bundle Integrity",
                passed: false,
                message: "System Extension bundles found but all are invalid",
                severity: .critical,
                details: "Found bundles: \(foundBundles.joined(separator: ", "))",
                issues: issues
            )
        } else {
            let hasIssues = foundBundles.count != validBundles.count
            return VerificationCheck(
                checkID: "bundle_integrity",
                checkName: "Bundle Integrity",
                passed: !hasIssues,
                message: hasIssues ? 
                    "Some bundles are invalid (\(validBundles.count)/\(foundBundles.count) valid)" :
                    "All System Extension bundles are valid",
                severity: hasIssues ? .warning : .info,
                details: "Valid bundles: \(validBundles.joined(separator: ", "))",
                issues: issues
            )
        }
    }
    
    private func checkRuntimeStatus() async -> VerificationCheck {
        logger.debug("Checking runtime status")
        
        // Check if extension process is running
        let processRunning = await isExtensionProcessRunning()
        
        // Check memory and CPU usage
        let resourceUsage = await getExtensionResourceUsage()
        
        if processRunning {
            let highUsage = resourceUsage.memoryMB > 100 || resourceUsage.cpuPercent > 50
            return VerificationCheck(
                checkID: "runtime_status",
                checkName: "Runtime Status",
                passed: !highUsage,
                message: processRunning ? "System Extension is running" : "System Extension process not found",
                severity: highUsage ? .warning : .info,
                details: "Memory: \(resourceUsage.memoryMB)MB, CPU: \(resourceUsage.cpuPercent)%",
                issues: highUsage ? [.highResourceUsage] : []
            )
        } else {
            return VerificationCheck(
                checkID: "runtime_status",
                checkName: "Runtime Status",
                passed: false,
                message: "System Extension process is not running",
                severity: .error,
                details: "No active process found for System Extension",
                issues: [.processNotRunning]
            )
        }
    }
    
    private func checkPermissionsAndEntitlements() async -> VerificationCheck {
        logger.debug("Checking permissions and entitlements")
        
        // Check SIP status
        let sipEnabled = await checkSIPStatus()
        
        // Check developer mode
        let devModeEnabled = await checkDeveloperMode()
        
        // Check code signing
        let codeSigningValid = await checkCodeSigning()
        
        var issues: [VerificationInstallationIssue] = []
        var warnings: [String] = []
        
        if !codeSigningValid {
            issues.append(.codeSigningInvalid)
        }
        
        if !devModeEnabled && !codeSigningValid {
            issues.append(.developerModeRequired)
        }
        
        if !sipEnabled {
            warnings.append("SIP is disabled")
        }
        
        let hasIssues = !issues.isEmpty
        
        return VerificationCheck(
            checkID: "permissions_entitlements",
            checkName: "Permissions & Entitlements",
            passed: !hasIssues,
            message: hasIssues ? "Permission or entitlement issues detected" : "Permissions and entitlements are correct",
            severity: hasIssues ? .error : .info,
            details: warnings.isEmpty ? "All checks passed" : "Warnings: \(warnings.joined(separator: ", "))",
            issues: issues
        )
    }
    
    private func checkServiceIntegration() async -> VerificationCheck {
        logger.debug("Checking service integration")
        
        // Check if service is properly configured
        let serviceConfigured = await isServiceConfigured()
        
        // Check if service is running
        let serviceRunning = await isServiceRunning()
        
        // Check communication between service and extension
        let communicationWorking = await testServiceExtensionCommunication()
        
        var issues: [VerificationInstallationIssue] = []
        
        if !serviceConfigured {
            issues.append(.serviceNotConfigured)
        }
        
        if !serviceRunning {
            issues.append(.serviceNotRunning)
        }
        
        if !communicationWorking {
            issues.append(.communicationFailed)
        }
        
        let hasIssues = !issues.isEmpty
        
        return VerificationCheck(
            checkID: "service_integration",
            checkName: "Service Integration",
            passed: !hasIssues,
            message: hasIssues ? "Service integration issues detected" : "Service integration is working correctly",
            severity: hasIssues ? .error : .info,
            details: "Service configured: \(serviceConfigured), running: \(serviceRunning), communication: \(communicationWorking)",
            issues: issues
        )
    }
    
    // MARK: - System Information Gathering
    
    private func gatherSystemInformation() async -> SystemInformation {
        logger.debug("Gathering system information")
        
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let architecture = "arm64" // ProcessInfo.processInfo.machineHardwareName doesn't exist, use fallback
        let sipStatus = await checkSIPStatus()
        let devModeStatus = await checkDeveloperMode()
        
        return SystemInformation(
            osVersion: osVersion,
            architecture: architecture,
            sipEnabled: sipStatus,
            developerModeEnabled: devModeStatus,
            homebrewPrefix: getHomebrewPrefix(),
            timestamp: Date()
        )
    }
    
    private func collectSystemLogs() async -> [SystemLogEntry] {
        logger.debug("Collecting system logs")
        
        var logEntries: [SystemLogEntry] = []
        
        // Collect systemextensionsctl logs
        if let extensionLogs = await getSystemExtensionLogs() {
            logEntries.append(contentsOf: extensionLogs)
        }
        
        // Collect service logs
        if let serviceLogs = await getServiceLogs() {
            logEntries.append(contentsOf: serviceLogs)
        }
        
        // Collect crash logs
        if let crashLogs = await getCrashLogs() {
            logEntries.append(contentsOf: crashLogs)
        }
        
        return logEntries.sorted { $0.timestamp > $1.timestamp }
    }
    
    private func analyzeSystemConfiguration() async -> ConfigurationAnalysis {
        logger.debug("Analyzing system configuration")
        
        let homebrewInstalled = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ||
                               FileManager.default.fileExists(atPath: "/usr/local/bin/brew")
        
        let xcodeInstalled = FileManager.default.fileExists(atPath: "/Applications/Xcode.app") ||
                           FileManager.default.fileExists(atPath: "/usr/bin/xcodebuild")
        
        let systemExtensionDirectory = expectedPaths.first { path in
            FileManager.default.fileExists(atPath: expandPathPattern(path).first ?? "")
        }
        
        return ConfigurationAnalysis(
            homebrewInstalled: homebrewInstalled,
            xcodeInstalled: xcodeInstalled,
            systemExtensionDirectoryExists: systemExtensionDirectory != nil,
            expectedInstallationPath: systemExtensionDirectory,
            configurationValid: homebrewInstalled && (systemExtensionDirectory != nil)
        )
    }
    
    // MARK: - Issue Detection Methods
    
    private func detectCommonIssues() async -> [DetectedInstallationIssue] {
        var issues: [DetectedInstallationIssue] = []
        
        // Check for common bundle problems
        if !(await bundleExistsInExpectedLocations()) {
            issues.append(DetectedInstallationIssue(
                issue: .bundleNotFound,
                severity: .critical,
                description: "System Extension bundle not found in expected locations",
                detectionMethod: "File system scan",
                affectedComponents: ["Bundle", "Installation"],
                suggestedActions: [
                    "Reinstall the System Extension",
                    "Verify installation completed successfully",
                    "Check Homebrew installation"
                ]
            ))
        }
        
        // Check for permission issues
        if !(await hasRequiredPermissions()) {
            issues.append(DetectedInstallationIssue(
                issue: .permissionDenied,
                severity: .error,
                description: "Insufficient permissions for System Extension operation",
                detectionMethod: "Permission check",
                affectedComponents: ["System Extension", "File System"],
                suggestedActions: [
                    "Run with administrator privileges",
                    "Check System Preferences > Security & Privacy",
                    "Enable System Extension in security settings"
                ]
            ))
        }
        
        return issues
    }
    
    private func detectPermissionIssues() async -> [DetectedInstallationIssue] {
        var issues: [DetectedInstallationIssue] = []
        
        // Check SIP compatibility
        let sipEnabled = await checkSIPStatus()
        let codeSigningValid = await checkCodeSigning()
        
        if sipEnabled && !codeSigningValid {
            issues.append(DetectedInstallationIssue(
                issue: .codeSigningInvalid,
                severity: .critical,
                description: "Code signing invalid with SIP enabled",
                detectionMethod: "Code signature verification",
                affectedComponents: ["System Extension", "Security"],
                suggestedActions: [
                    "Re-sign the System Extension with valid certificate",
                    "Use Apple Developer certificate",
                    "Enable developer mode for unsigned extensions"
                ]
            ))
        }
        
        return issues
    }
    
    private func detectConfigurationIssues() async -> [DetectedInstallationIssue] {
        var issues: [DetectedInstallationIssue] = []
        
        // Check for missing dependencies
        if !(await checkDependenciesInstalled()) {
            issues.append(DetectedInstallationIssue(
                issue: .dependenciesMissing,
                severity: .error,
                description: "Required dependencies are missing",
                detectionMethod: "Dependency scan",
                affectedComponents: ["Dependencies", "Runtime"],
                suggestedActions: [
                    "Install missing dependencies",
                    "Reinstall via Homebrew",
                    "Check system requirements"
                ]
            ))
        }
        
        return issues
    }
    
    private func detectEnvironmentIssues() async -> [DetectedInstallationIssue] {
        var issues: [DetectedInstallationIssue] = []
        
        // Check macOS version compatibility
        if !(await checkMacOSCompatibility()) {
            issues.append(DetectedInstallationIssue(
                issue: .incompatibleSystem,
                severity: .critical,
                description: "System Extension not compatible with this macOS version",
                detectionMethod: "Version check",
                affectedComponents: ["System Extension", "macOS"],
                suggestedActions: [
                    "Update to compatible macOS version",
                    "Check system requirements",
                    "Use compatible System Extension version"
                ]
            ))
        }
        
        return issues
    }
    
    // MARK: - Functionality Verification
    
    private func checkExtensionLoading() async -> FunctionalityCheck {
        let isLoaded = await isExtensionProcessRunning()
        return FunctionalityCheck(
            checkName: "Extension Loading",
            passed: isLoaded,
            message: isLoaded ? "Extension is loaded and running" : "Extension failed to load",
            details: isLoaded ? "Process found in system" : "No process found"
        )
    }
    
    private func checkExtensionCommunication() async -> FunctionalityCheck {
        let canCommunicate = await testServiceExtensionCommunication()
        return FunctionalityCheck(
            checkName: "Extension Communication",
            passed: canCommunicate,
            message: canCommunicate ? "Communication is working" : "Communication failed",
            details: canCommunicate ? "Service can communicate with extension" : "Communication test failed"
        )
    }
    
    private func checkDeviceInteraction() async -> FunctionalityCheck {
        let canInteract = await testDeviceInteraction()
        return FunctionalityCheck(
            checkName: "Device Interaction",
            passed: canInteract,
            message: canInteract ? "Device interaction working" : "Device interaction failed",
            details: canInteract ? "Can enumerate and interact with USB devices" : "Device interaction test failed"
        )
    }
    
    private func checkNetworkCapabilities() async -> FunctionalityCheck {
        let networkWorking = await testNetworkCapabilities()
        return FunctionalityCheck(
            checkName: "Network Capabilities",
            passed: networkWorking,
            message: networkWorking ? "Network capabilities working" : "Network capabilities failed",
            details: networkWorking ? "Can create network connections" : "Network test failed"
        )
    }
    
    // MARK: - Helper Methods
    
    private func determineInstallationStatus(from checks: [VerificationCheck]) -> VerificationInstallationStatus {
        let criticalFailures = checks.filter { !$0.passed && $0.severity == .critical }
        let errorFailures = checks.filter { !$0.passed && $0.severity == .error }
        let warnings = checks.filter { !$0.passed && $0.severity == .warning }
        
        if !criticalFailures.isEmpty {
            return .failed
        } else if !errorFailures.isEmpty {
            return .problematic
        } else if !warnings.isEmpty {
            return .partiallyFunctional
        } else {
            return .fullyFunctional
        }
    }
    
    private func generateVerificationSummary(status: VerificationInstallationStatus, checks: [VerificationCheck]) -> String {
        let totalChecks = checks.count
        let passedChecks = checks.filter { $0.passed }.count
        
        let statusDescription = switch status {
        case .fullyFunctional:
            "System Extension is fully functional"
        case .partiallyFunctional:
            "System Extension is partially functional with minor issues"
        case .problematic:
            "System Extension has significant issues affecting functionality"
        case .failed:
            "System Extension installation has critical failures"
        case .unknown:
            "System Extension status could not be determined"
        }
        
        return "\(statusDescription). Verification completed: \(passedChecks)/\(totalChecks) checks passed."
    }
    
    private func generateRecommendations(
        from verificationResult: InstallationVerificationResult,
        systemInfo: SystemInformation,
        configAnalysis: ConfigurationAnalysis
    ) -> [String] {
        var recommendations: [String] = []
        
        // Add recommendations based on detected issues
        let allIssues = verificationResult.discoveredIssues
        for issue in Set(allIssues) {
            recommendations.append(contentsOf: issue.suggestedActions)
        }
        
        // Add system-specific recommendations
        if !systemInfo.sipEnabled {
            recommendations.append("Consider re-enabling System Integrity Protection for security")
        }
        
        if !systemInfo.developerModeEnabled && verificationResult.status != .fullyFunctional {
            recommendations.append("Enable System Extension developer mode for troubleshooting")
        }
        
        if !configAnalysis.homebrewInstalled {
            recommendations.append("Install Homebrew for easier System Extension management")
        }
        
        return Array(Set(recommendations)).sorted()
    }
    
    // MARK: - System Command Execution
    
    private func executeSystemExtensionsCtl(command: String) async throws -> String {
        return try await executeSystemExtensionsCtl(arguments: [command])
    }
    
    private func executeSystemExtensionsCtl(arguments: [String]) async throws -> String {
        logger.debug("Executing systemextensionsctl with arguments: \(arguments)")
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
            process.arguments = arguments
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let error = SystemExtensionsCtlError.commandFailed(
                        exitCode: Int(process.terminationStatus),
                        output: output,
                        arguments: arguments
                    )
                    continuation.resume(throwing: error)
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Parse system extension status from systemextensionsctl output
    public func parseSystemExtensionStatus(_ output: String) -> VerificationSystemExtensionStatus {
        logger.debug("Parsing system extension status from output")
        
        let lines = output.components(separatedBy: .newlines)
        var extensions: [ParsedSystemExtension] = []
        
        for line in lines {
            if let parsedExtension = parseExtensionLine(line) {
                extensions.append(parsedExtension)
            }
        }
        
        // Find our specific extension
        let ourExtension = extensions.first { $0.bundleIdentifier == bundleIdentifier }
        
        return VerificationSystemExtensionStatus(
            isRegistered: ourExtension != nil,
            isEnabled: ourExtension?.isEnabled ?? false,
            isActive: ourExtension?.isActive ?? false,
            state: ourExtension?.state ?? .unknown,
            teamIdentifier: ourExtension?.teamIdentifier,
            version: ourExtension?.version,
            allExtensions: extensions,
            rawOutput: output
        )
    }
    
    /// Validate extension registration against expected criteria
    private func validateExtensionRegistration() async throws -> ExtensionRegistrationValidation {
        logger.debug("Validating System Extension registration")
        
        let output = try await executeSystemExtensionsCtl(command: "list")
        let status = parseSystemExtensionStatus(output)
        
        var validationIssues: [RegistrationIssue] = []
        var validationWarnings: [String] = []
        
        // Check registration status
        if !status.isRegistered {
            validationIssues.append(.notRegistered)
        } else {
            // Check if enabled
            if !status.isEnabled {
                validationIssues.append(.notEnabled)
            }
            
            // Check if active
            if !status.isActive {
                validationIssues.append(.notActive)
            }
            
            // Check state
            switch status.state {
            case .unknown:
                validationWarnings.append("Extension state is unknown")
            case .terminated:
                validationIssues.append(.terminated)
            case .waitingForUserApproval:
                validationWarnings.append("Extension is waiting for user approval")
            case .replacementWaitingForUserApproval:
                validationWarnings.append("Extension replacement is waiting for user approval")
            case .activated, .enabled:
                // These are good states
                break
            }
            
            // Validate team identifier if available
            if let teamID = status.teamIdentifier, teamID.isEmpty {
                validationWarnings.append("Team identifier is empty")
            }
        }
        
        let isValid = validationIssues.isEmpty
        let severity: VerificationValidationSeverity = validationIssues.isEmpty ? 
            (validationWarnings.isEmpty ? .info : .warning) : .error
        
        return ExtensionRegistrationValidation(
            isValid: isValid,
            severity: severity,
            issues: validationIssues,
            warnings: validationWarnings,
            detectedStatus: status,
            validationTimestamp: Date()
        )
    }
    
    // MARK: - Parsing and Analysis
    
    private func parseSystemExtensionsList(_ output: String) -> SystemExtensionRegistryAnalysis {
        let status = parseSystemExtensionStatus(output)
        
        return SystemExtensionRegistryAnalysis(
            isRegistered: status.isRegistered,
            isEnabled: status.isEnabled,
            isActive: status.isActive,
            rawOutput: output
        )
    }
    
    /// Parse individual extension line from systemextensionsctl output
    public func parseExtensionLine(_ line: String) -> ParsedSystemExtension? {
        // systemextensionsctl output format:
        // * <team_id> <bundle_id> (<version>) [<state>]
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        
        // Skip non-extension lines
        guard trimmedLine.hasPrefix("*") || trimmedLine.hasPrefix("-") else {
            return nil
        }
        
        // Remove the prefix marker (* or -)
        let contentLine = String(trimmedLine.dropFirst(1)).trimmingCharacters(in: .whitespaces)
        
        // Parse components using regex pattern
        let pattern = #"^(\w+)\s+([^\s]+)\s+\(([^)]+)\)\s+\[([^\]]+)\]"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: contentLine, range: NSRange(contentLine.startIndex..., in: contentLine)) else {
            return nil
        }
        
        let teamIdentifier = String(contentLine[Range(match.range(at: 1), in: contentLine)!])
        let bundleIdentifier = String(contentLine[Range(match.range(at: 2), in: contentLine)!])
        let version = String(contentLine[Range(match.range(at: 3), in: contentLine)!])
        let stateString = String(contentLine[Range(match.range(at: 4), in: contentLine)!])
        
        let state = ExtensionState.from(string: stateString)
        let isEnabled = stateString.contains("enabled") || stateString.contains("activated")
        let isActive = stateString.contains("activated") || stateString.contains("active")
        
        return ParsedSystemExtension(
            bundleIdentifier: bundleIdentifier,
            teamIdentifier: teamIdentifier,
            version: version,
            state: state,
            stateString: stateString,
            isEnabled: isEnabled,
            isActive: isActive
        )
    }
    
    // MARK: - Stub Methods for Implementation
    
    // These methods provide the interface for the verification functionality
    // In a real implementation, these would contain the actual verification logic
    
    private func expandPathPattern(_ pattern: String) -> [String] {
        // Expand glob patterns to actual paths
        // This is a simplified implementation
        return [pattern.replacingOccurrences(of: "*", with: "")]
    }
    
    private func validateBundle(at path: String) async -> Bool {
        // Validate bundle structure and contents
        let contentsPath = "\(path)/Contents"
        let infoPlistPath = "\(contentsPath)/Info.plist"
        return FileManager.default.fileExists(atPath: infoPlistPath)
    }
    
    private func isExtensionProcessRunning() async -> Bool {
        // Check if extension process is running
        // This would typically check for running processes
        return false // Stub implementation
    }
    
    private func getExtensionResourceUsage() async -> ResourceUsage {
        // Get memory and CPU usage for extension
        return ResourceUsage(memoryMB: 0, cpuPercent: 0) // Stub implementation
    }
    
    private func checkSIPStatus() async -> Bool {
        // Check System Integrity Protection status
        return true // Stub implementation
    }
    
    private func checkDeveloperMode() async -> Bool {
        // Check if developer mode is enabled
        return false // Stub implementation
    }
    
    private func checkCodeSigning() async -> Bool {
        // Check code signing validity
        return true // Stub implementation
    }
    
    private func isServiceConfigured() async -> Bool {
        // Check if service is properly configured
        return true // Stub implementation
    }
    
    private func isServiceRunning() async -> Bool {
        // Check if service is running
        return false // Stub implementation
    }
    
    private func testServiceExtensionCommunication() async -> Bool {
        // Test communication between service and extension
        return false // Stub implementation
    }
    
    private func getHomebrewPrefix() -> String {
        return ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"] ?? "/opt/homebrew"
    }
    
    private func getSystemExtensionLogs() async -> [SystemLogEntry]? {
        // Collect system extension logs
        return nil // Stub implementation
    }
    
    private func getServiceLogs() async -> [SystemLogEntry]? {
        // Collect service logs
        return nil // Stub implementation
    }
    
    private func getCrashLogs() async -> [SystemLogEntry]? {
        // Collect crash logs
        return nil // Stub implementation
    }
    
    private func bundleExistsInExpectedLocations() async -> Bool {
        // Check if bundle exists in expected locations
        return false // Stub implementation
    }
    
    private func hasRequiredPermissions() async -> Bool {
        // Check required permissions
        return true // Stub implementation
    }
    
    private func checkDependenciesInstalled() async -> Bool {
        // Check if required dependencies are installed
        return true // Stub implementation
    }
    
    private func checkMacOSCompatibility() async -> Bool {
        // Check macOS version compatibility
        return true // Stub implementation
    }
    
    private func testDeviceInteraction() async -> Bool {
        // Test device interaction capabilities
        return false // Stub implementation
    }
    
    private func testNetworkCapabilities() async -> Bool {
        // Test network capabilities
        return false // Stub implementation
    }
}

// MARK: - Helper Structures

private struct SystemExtensionRegistryAnalysis {
    let isRegistered: Bool
    let isEnabled: Bool
    let isActive: Bool
    let rawOutput: String
}

private struct ResourceUsage {
    let memoryMB: Double
    let cpuPercent: Double
}

// MARK: - SystemExtensionsCtl Data Structures

public enum SystemExtensionsCtlError: LocalizedError {
    case commandFailed(exitCode: Int, output: String, arguments: [String])
    
    public var errorDescription: String? {
        switch self {
        case .commandFailed(let exitCode, let output, let arguments):
            return "systemextensionsctl command failed (exit code: \(exitCode), args: \(arguments)): \(output)"
        }
    }
}

public struct VerificationSystemExtensionStatus {
    public let isRegistered: Bool
    public let isEnabled: Bool
    public let isActive: Bool
    public let state: ExtensionState
    public let teamIdentifier: String?
    public let version: String?
    public let allExtensions: [ParsedSystemExtension]
    public let rawOutput: String
}

public struct ParsedSystemExtension {
    public let bundleIdentifier: String
    public let teamIdentifier: String
    public let version: String
    public let state: ExtensionState
    public let stateString: String
    public let isEnabled: Bool
    public let isActive: Bool
}

public enum ExtensionState: String, CaseIterable {
    case unknown = "unknown"
    case waitingForUserApproval = "waiting for user approval"
    case replacementWaitingForUserApproval = "replacement waiting for user approval"
    case enabled = "enabled"
    case activated = "activated"
    case terminated = "terminated"
    
    public static func from(string: String) -> ExtensionState {
        let lowercased = string.lowercased()
        return ExtensionState.allCases.first { lowercased.contains($0.rawValue) } ?? .unknown
    }
}

public struct ExtensionRegistrationValidation {
    public let isValid: Bool
    public let severity: VerificationValidationSeverity
    public let issues: [RegistrationIssue]
    public let warnings: [String]
    public let detectedStatus: VerificationSystemExtensionStatus
    public let validationTimestamp: Date
}

public enum VerificationValidationSeverity {
    case info
    case warning
    case error
    case critical
}

public enum RegistrationIssue {
    case notRegistered
    case notEnabled
    case notActive
    case terminated
    case waitingForApproval
    case codeSigningInvalid
    case incompatibleVersion
}