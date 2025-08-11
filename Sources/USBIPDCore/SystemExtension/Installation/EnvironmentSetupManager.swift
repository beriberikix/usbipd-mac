import Foundation
import Security

/// Environment validation and setup manager for System Extension development
public final class EnvironmentSetupManager {
    private let logger = Logger(config: LoggerConfig(level: .info), category: "environment-setup")
    
    public init() {}
    
    // MARK: - Public Interface
    
    /// Validates the current development environment for System Extension development
    /// - Returns: Comprehensive environment validation report
    public func validateDevelopmentEnvironment() -> EnvironmentValidationResult {
        logger.info("Starting development environment validation")
        
        let startTime = Date()
        var validationChecks: [ValidationResult] = []
        var issues: [EnvironmentIssue] = []
        
        // Check macOS version compatibility
        let osCheck = validateMacOSVersion()
        validationChecks.append(osCheck)
        if !osCheck.passed {
            issues.append(EnvironmentIssue(
                category: .systemRequirements,
                severity: .critical,
                description: osCheck.message,
                remediation: osCheck.recommendedActions.first ?? "Update to a supported macOS version"
            ))
        }
        
        // Check System Integrity Protection status
        let sipCheck = validateSystemIntegrityProtection()
        validationChecks.append(sipCheck)
        if !sipCheck.passed && sipCheck.severity == .warning {
            issues.append(EnvironmentIssue(
                category: .systemConfiguration,
                severity: .warning,
                description: sipCheck.message,
                remediation: sipCheck.recommendedActions.first ?? "Enable System Integrity Protection for production builds"
            ))
        }
        
        // Check Xcode Command Line Tools
        let xcodeCheck = validateXcodeCommandLineTools()
        validationChecks.append(xcodeCheck)
        if !xcodeCheck.passed {
            issues.append(EnvironmentIssue(
                category: .developerTools,
                severity: .critical,
                description: xcodeCheck.message,
                remediation: xcodeCheck.recommendedActions.first ?? "Install Xcode Command Line Tools"
            ))
        }
        
        // Check developer mode status
        let devModeCheck = validateDeveloperMode()
        validationChecks.append(devModeCheck)
        if !devModeCheck.passed {
            issues.append(EnvironmentIssue(
                category: .systemConfiguration,
                severity: .warning,
                description: devModeCheck.message,
                remediation: devModeCheck.recommendedActions.first ?? "Enable Developer Mode for unsigned System Extensions"
            ))
        }
        
        // Check for available code signing certificates
        let certCheck = validateCodeSigningCertificates()
        validationChecks.append(certCheck)
        if !certCheck.passed && certCheck.severity == .warning {
            issues.append(EnvironmentIssue(
                category: .codeSigningCertificates,
                severity: .warning,
                description: certCheck.message,
                remediation: certCheck.recommendedActions.first ?? "Install Apple Developer certificates for production builds"
            ))
        }
        
        // Check disk space and permissions
        let diskCheck = validateDiskSpaceAndPermissions()
        validationChecks.append(diskCheck)
        if !diskCheck.passed {
            issues.append(EnvironmentIssue(
                category: .systemConfiguration,
                severity: diskCheck.severity,
                description: diskCheck.message,
                remediation: diskCheck.recommendedActions.first ?? "Ensure adequate disk space and permissions"
            ))
        }
        
        let validationTime = Date().timeIntervalSince(startTime)
        let overallStatus = determineOverallStatus(from: validationChecks)
        
        let result = EnvironmentValidationResult(
            overallStatus: overallStatus,
            validationChecks: validationChecks,
            issues: issues,
            validationTime: validationTime,
            timestamp: Date(),
            recommendations: generateRecommendations(from: issues)
        )
        
        logger.info("Environment validation completed", context: [
            "status": overallStatus.rawValue,
            "issues": issues.count,
            "duration": String(format: "%.2fs", validationTime)
        ])
        
        return result
    }
    
    /// Performs automated setup of development environment where possible
    /// - Returns: Setup result with completed actions and remaining manual steps
    public func setupDevelopmentEnvironment() throws -> EnvironmentSetupResult {
        logger.info("Starting automated development environment setup")
        
        let startTime = Date()
        var completedActions: [String] = []
        var manualSteps: [ManualSetupStep] = []
        var setupErrors: [EnvironmentSetupError] = []
        
        // First validate current state
        let validation = validateDevelopmentEnvironment()
        
        // Attempt to resolve critical issues automatically
        for issue in validation.issues {
            switch issue.category {
            case .systemRequirements:
                manualSteps.append(ManualSetupStep(
                    title: "Update macOS",
                    description: issue.description,
                    instructions: [issue.remediation],
                    priority: .high
                ))
                
            case .developerTools:
                do {
                    try installXcodeCommandLineTools()
                    completedActions.append("Initiated Xcode Command Line Tools installation")
                } catch {
                    setupErrors.append(.xcodeInstallationFailed(error.localizedDescription))
                    manualSteps.append(ManualSetupStep(
                        title: "Install Xcode Command Line Tools",
                        description: "Manual installation required",
                        instructions: ["Run: xcode-select --install", "Follow the installation prompts"],
                        priority: .high
                    ))
                }
                
            case .systemConfiguration:
                if issue.description.contains("System Integrity Protection") {
                    manualSteps.append(ManualSetupStep(
                        title: "Configure System Integrity Protection",
                        description: issue.description,
                        instructions: [issue.remediation],
                        priority: .medium
                    ))
                }
                
                if issue.description.contains("Developer Mode") {
                    manualSteps.append(ManualSetupStep(
                        title: "Enable Developer Mode",
                        description: issue.description,
                        instructions: [
                            "Open Terminal",
                            "Run: sudo systemextensionsctl developer on",
                            "Enter administrator password when prompted"
                        ],
                        priority: .high
                    ))
                }
                
            case .codeSigningCertificates:
                manualSteps.append(ManualSetupStep(
                    title: "Install Code Signing Certificates",
                    description: issue.description,
                    instructions: [
                        "Open Xcode and sign in with your Apple ID",
                        "Go to Xcode > Preferences > Accounts",
                        "Download certificates for your development team",
                        "Alternatively, download certificates from Apple Developer portal"
                    ],
                    priority: .medium
                ))
            }
        }
        
        let setupTime = Date().timeIntervalSince(startTime)
        let result = EnvironmentSetupResult(
            success: setupErrors.isEmpty,
            completedActions: completedActions,
            manualSteps: manualSteps,
            errors: setupErrors,
            setupTime: setupTime,
            timestamp: Date()
        )
        
        logger.info("Environment setup completed", context: [
            "success": result.success,
            "automated_actions": completedActions.count,
            "manual_steps": manualSteps.count,
            "errors": setupErrors.count,
            "duration": String(format: "%.2fs", setupTime)
        ])
        
        return result
    }
    
    /// Provides comprehensive diagnostic information about the development environment
    /// - Returns: Array of diagnostic results with specific recommendations
    public func provideDiagnostics() -> [DiagnosticResult] {
        logger.info("Generating environment diagnostics")
        
        var diagnostics: [DiagnosticResult] = []
        
        // System information
        diagnostics.append(DiagnosticResult(
            category: .systemInformation,
            title: "System Information",
            status: .info,
            details: getSystemInformation(),
            recommendations: []
        ))
        
        // Development tools status
        diagnostics.append(DiagnosticResult(
            category: .developerTools,
            title: "Development Tools",
            status: getDevToolsStatus(),
            details: getDevToolsInformation(),
            recommendations: getDevToolsRecommendations()
        ))
        
        // Code signing environment
        diagnostics.append(DiagnosticResult(
            category: .codeSigningCertificates,
            title: "Code Signing Environment",
            status: getCodeSigningStatus(),
            details: getCodeSigningInformation(),
            recommendations: getCodeSigningRecommendations()
        ))
        
        // System Extension configuration
        diagnostics.append(DiagnosticResult(
            category: .systemConfiguration,
            title: "System Extension Configuration",
            status: getSystemExtensionConfigStatus(),
            details: getSystemExtensionConfigInformation(),
            recommendations: getSystemExtensionConfigRecommendations()
        ))
        
        logger.info("Generated \(diagnostics.count) diagnostic reports")
        return diagnostics
    }
    
    // MARK: - Private Validation Methods
    
    private func validateMacOSVersion() -> ValidationResult {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        
        // System Extensions require macOS 10.15+ (Catalina), but we recommend 11.0+ (Big Sur)
        let isSupported = version.majorVersion >= 11 || (version.majorVersion == 10 && version.minorVersion >= 15)
        let isRecommended = version.majorVersion >= 11
        
        if !isSupported {
            return ValidationResult(
                checkID: "macos_version",
                checkName: "macOS Version Compatibility",
                passed: false,
                message: "macOS \(versionString) is not supported. System Extensions require macOS 10.15 or later.",
                severity: .critical,
                recommendedActions: ["Upgrade to macOS 11.0 or later for full System Extension support"]
            )
        }
        
        if !isRecommended {
            return ValidationResult(
                checkID: "macos_version",
                checkName: "macOS Version Compatibility",
                passed: true,
                message: "macOS \(versionString) is supported but macOS 11.0+ is recommended.",
                severity: .warning,
                recommendedActions: ["Consider upgrading to macOS 11.0 or later for optimal System Extension support"]
            )
        }
        
        return ValidationResult(
            checkID: "macos_version",
            checkName: "macOS Version Compatibility",
            passed: true,
            message: "macOS \(versionString) fully supports System Extensions.",
            severity: .info
        )
    }
    
    private func validateSystemIntegrityProtection() -> ValidationResult {
        let sipStatus = getSystemIntegrityProtectionStatus()
        
        switch sipStatus {
        case .enabled:
            return ValidationResult(
                checkID: "sip_status",
                checkName: "System Integrity Protection",
                passed: true,
                message: "System Integrity Protection is enabled (recommended for production).",
                severity: .info
            )
            
        case .disabled:
            return ValidationResult(
                checkID: "sip_status",
                checkName: "System Integrity Protection",
                passed: false,
                message: "System Integrity Protection is disabled. This may be needed for unsigned System Extension development.",
                severity: .warning,
                recommendedActions: [
                    "Enable SIP for production builds: reboot to Recovery mode and run 'csrutil enable'",
                    "Keep SIP disabled only if developing unsigned System Extensions"
                ]
            )
            
        case .unknown:
            return ValidationResult(
                checkID: "sip_status",
                checkName: "System Integrity Protection",
                passed: true,
                message: "Unable to determine System Integrity Protection status.",
                severity: .warning,
                recommendedActions: ["Check SIP status manually: csrutil status"]
            )
        }
    }
    
    private func validateXcodeCommandLineTools() -> ValidationResult {
        let hasXcodeSelect = FileManager.default.fileExists(atPath: "/usr/bin/xcode-select")
        
        guard hasXcodeSelect else {
            return ValidationResult(
                checkID: "xcode_cli_tools",
                checkName: "Xcode Command Line Tools",
                passed: false,
                message: "Xcode Command Line Tools are not installed.",
                severity: .critical,
                recommendedActions: ["Install Xcode Command Line Tools: xcode-select --install"]
            )
        }
        
        // Check if tools are properly configured
        let xcodeSelectPath = getXcodeSelectPath()
        let hasValidPath = !xcodeSelectPath.isEmpty && FileManager.default.fileExists(atPath: xcodeSelectPath)
        
        if !hasValidPath {
            return ValidationResult(
                checkID: "xcode_cli_tools",
                checkName: "Xcode Command Line Tools",
                passed: false,
                message: "Xcode Command Line Tools are installed but not properly configured.",
                severity: .error,
                recommendedActions: [
                    "Reset Xcode Command Line Tools: xcode-select --reset",
                    "Or install manually: xcode-select --install"
                ]
            )
        }
        
        return ValidationResult(
            checkID: "xcode_cli_tools",
            checkName: "Xcode Command Line Tools",
            passed: true,
            message: "Xcode Command Line Tools are properly installed and configured.",
            severity: .info
        )
    }
    
    private func validateDeveloperMode() -> ValidationResult {
        let developerModeEnabled = getDeveloperModeStatus()
        
        if developerModeEnabled {
            return ValidationResult(
                checkID: "developer_mode",
                checkName: "System Extension Developer Mode",
                passed: true,
                message: "System Extension Developer Mode is enabled.",
                severity: .info
            )
        } else {
            return ValidationResult(
                checkID: "developer_mode",
                checkName: "System Extension Developer Mode",
                passed: false,
                message: "System Extension Developer Mode is not enabled. This is required for unsigned System Extension development.",
                severity: .warning,
                recommendedActions: [
                    "Enable Developer Mode: sudo systemextensionsctl developer on",
                    "Disable for production builds: sudo systemextensionsctl developer off"
                ]
            )
        }
    }
    
    private func validateCodeSigningCertificates() -> ValidationResult {
        let certificates = getAvailableCodeSigningCertificates()
        let validCerts = certificates.filter { $0.isValidForSystemExtensions }
        
        if validCerts.isEmpty {
            return ValidationResult(
                checkID: "code_signing_certs",
                checkName: "Code Signing Certificates",
                passed: false,
                message: "No valid code signing certificates found for System Extensions.",
                severity: .warning,
                recommendedActions: [
                    "Install Apple Development certificate from Xcode",
                    "Or download certificates from Apple Developer portal",
                    "Unsigned development is possible with Developer Mode enabled"
                ]
            )
        }
        
        return ValidationResult(
            checkID: "code_signing_certs",
            checkName: "Code Signing Certificates",
            passed: true,
            message: "Found \(validCerts.count) valid code signing certificate(s) for System Extensions.",
            severity: .info
        )
    }
    
    private func validateDiskSpaceAndPermissions() -> ValidationResult {
        let currentDirectory = FileManager.default.currentDirectoryPath
        
        // Check available disk space (need at least 1GB for builds)
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: currentDirectory),
              let freeSize = attributes[.systemFreeSize] as? NSNumber else {
            return ValidationResult(
                checkID: "disk_space",
                checkName: "Disk Space and Permissions",
                passed: false,
                message: "Unable to check disk space.",
                severity: .warning,
                recommendedActions: ["Manually verify adequate disk space is available"]
            )
        }
        
        let freeSpaceGB = freeSize.int64Value / (1024 * 1024 * 1024)
        
        if freeSpaceGB < 1 {
            return ValidationResult(
                checkID: "disk_space",
                checkName: "Disk Space and Permissions",
                passed: false,
                message: "Insufficient disk space. Found \(freeSpaceGB)GB, need at least 1GB for builds.",
                severity: .error,
                recommendedActions: ["Free up disk space and try again"]
            )
        }
        
        // Check write permissions
        let testFile = currentDirectory + "/.usbipd_test_write"
        let testData = Data("test".utf8)
        
        do {
            try testData.write(to: URL(fileURLWithPath: testFile))
            try FileManager.default.removeItem(atPath: testFile)
        } catch {
            return ValidationResult(
                checkID: "disk_space",
                checkName: "Disk Space and Permissions",
                passed: false,
                message: "Insufficient write permissions in current directory.",
                severity: .error,
                recommendedActions: ["Ensure write permissions in the project directory"]
            )
        }
        
        return ValidationResult(
            checkID: "disk_space",
            checkName: "Disk Space and Permissions",
            passed: true,
            message: "Disk space (\(freeSpaceGB)GB available) and permissions are adequate.",
            severity: .info
        )
    }
    
    // MARK: - Helper Methods
    
    private func determineOverallStatus(from validationChecks: [ValidationResult]) -> EnvironmentStatus {
        let hasCriticalIssues = validationChecks.contains { !$0.passed && $0.severity == .critical }
        let hasErrorIssues = validationChecks.contains { !$0.passed && $0.severity == .error }
        let hasWarnings = validationChecks.contains { !$0.passed && $0.severity == .warning }
        
        if hasCriticalIssues {
            return .criticalIssues
        } else if hasErrorIssues {
            return .hasErrors
        } else if hasWarnings {
            return .hasWarnings
        } else {
            return .ready
        }
    }
    
    private func generateRecommendations(from issues: [EnvironmentIssue]) -> [String] {
        let priorityOrder: [EnvironmentIssue.Priority] = [.high, .medium, .low]
        let sortedIssues = issues.sorted { lhs, rhs in
            let lhsPriority = priorityOrder.firstIndex(of: lhs.severity.priority) ?? priorityOrder.count
            let rhsPriority = priorityOrder.firstIndex(of: rhs.severity.priority) ?? priorityOrder.count
            return lhsPriority < rhsPriority
        }
        
        return sortedIssues.prefix(5).map { $0.remediation }
    }
    
    private func installXcodeCommandLineTools() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw EnvironmentSetupError.xcodeInstallationFailed("xcode-select --install failed with status \(process.terminationStatus)")
        }
    }
    
    // MARK: - System Information Gathering
    
    private func getSystemIntegrityProtectionStatus() -> SIPStatus {
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
            
            if output.contains("enabled") {
                return .enabled
            } else if output.contains("disabled") {
                return .disabled
            } else {
                return .unknown
            }
        } catch {
            return .unknown
        }
    }
    
    private func getXcodeSelectPath() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
        } catch {
            // Fall through to return empty string
        }
        
        return ""
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
            
            // Developer mode is enabled if output contains "on"
            return output.lowercased().contains("on")
        } catch {
            return false
        }
    }
    
    private func getAvailableCodeSigningCertificates() -> [CodeSigningCertificate] {
        // This is a simplified implementation
        // In practice, this would query the Security framework for available certificates
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-certificate", "-p"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // For now, return empty array since certificate parsing is complex
            // This would be implemented with proper Security framework integration
            return []
        } catch {
            return []
        }
    }
    
    // MARK: - Diagnostic Information Methods
    
    private func getSystemInformation() -> [String: String] {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        
        return [
            "macOS Version": versionString,
            "System": ProcessInfo.processInfo.hostName,
            "Architecture": ProcessInfo.processInfo.machineType,
            "SIP Status": getSystemIntegrityProtectionStatus().description
        ]
    }
    
    private func getDevToolsStatus() -> DiagnosticStatus {
        let hasXcode = FileManager.default.fileExists(atPath: "/usr/bin/xcode-select")
        let validPath = !getXcodeSelectPath().isEmpty
        
        if hasXcode && validPath {
            return .healthy
        } else if hasXcode {
            return .warning
        } else {
            return .error
        }
    }
    
    private func getDevToolsInformation() -> [String: String] {
        let xcodeSelectPath = getXcodeSelectPath()
        
        return [
            "Xcode Select Path": xcodeSelectPath.isEmpty ? "Not configured" : xcodeSelectPath,
            "Command Line Tools": FileManager.default.fileExists(atPath: "/usr/bin/xcode-select") ? "Installed" : "Not installed"
        ]
    }
    
    private func getDevToolsRecommendations() -> [String] {
        let hasXcode = FileManager.default.fileExists(atPath: "/usr/bin/xcode-select")
        let validPath = !getXcodeSelectPath().isEmpty
        
        if !hasXcode {
            return ["Install Xcode Command Line Tools: xcode-select --install"]
        } else if !validPath {
            return ["Reset Xcode Command Line Tools: xcode-select --reset"]
        } else {
            return []
        }
    }
    
    private func getCodeSigningStatus() -> DiagnosticStatus {
        let certificates = getAvailableCodeSigningCertificates()
        let validCerts = certificates.filter { $0.isValidForSystemExtensions }
        
        if validCerts.isEmpty {
            return .warning
        } else {
            return .healthy
        }
    }
    
    private func getCodeSigningInformation() -> [String: String] {
        let certificates = getAvailableCodeSigningCertificates()
        
        return [
            "Available Certificates": "\(certificates.count)",
            "Valid for System Extensions": "\(certificates.filter { $0.isValidForSystemExtensions }.count)"
        ]
    }
    
    private func getCodeSigningRecommendations() -> [String] {
        let certificates = getAvailableCodeSigningCertificates()
        let validCerts = certificates.filter { $0.isValidForSystemExtensions }
        
        if validCerts.isEmpty {
            return [
                "Install Apple Development certificate from Xcode",
                "Or enable Developer Mode for unsigned development"
            ]
        } else {
            return []
        }
    }
    
    private func getSystemExtensionConfigStatus() -> DiagnosticStatus {
        let developerModeEnabled = getDeveloperModeStatus()
        let certificates = getAvailableCodeSigningCertificates()
        let hasValidCerts = certificates.contains { $0.isValidForSystemExtensions }
        
        if hasValidCerts || developerModeEnabled {
            return .healthy
        } else {
            return .warning
        }
    }
    
    private func getSystemExtensionConfigInformation() -> [String: String] {
        return [
            "Developer Mode": getDeveloperModeStatus() ? "Enabled" : "Disabled",
            "System Extension Support": "Available"
        ]
    }
    
    private func getSystemExtensionConfigRecommendations() -> [String] {
        let developerModeEnabled = getDeveloperModeStatus()
        let certificates = getAvailableCodeSigningCertificates()
        let hasValidCerts = certificates.contains { $0.isValidForSystemExtensions }
        
        var recommendations: [String] = []
        
        if !hasValidCerts && !developerModeEnabled {
            recommendations.append("Either install code signing certificates or enable Developer Mode")
        }
        
        if !developerModeEnabled {
            recommendations.append("Enable Developer Mode for unsigned development: sudo systemextensionsctl developer on")
        }
        
        return recommendations
    }
}

// MARK: - Supporting Types

/// Overall environment status
public enum EnvironmentStatus: String, Codable, CaseIterable {
    /// Environment is ready for System Extension development
    case ready = "ready"
    
    /// Environment has warnings but can be used
    case hasWarnings = "has_warnings"
    
    /// Environment has errors that should be fixed
    case hasErrors = "has_errors"
    
    /// Environment has critical issues that must be resolved
    case criticalIssues = "critical_issues"
    
    /// User-readable description
    public var displayName: String {
        switch self {
        case .ready:
            return "Ready for Development"
        case .hasWarnings:
            return "Ready with Warnings"
        case .hasErrors:
            return "Has Errors"
        case .criticalIssues:
            return "Critical Issues"
        }
    }
}

/// System Integrity Protection status
public enum SIPStatus {
    case enabled
    case disabled
    case unknown
    
    var description: String {
        switch self {
        case .enabled: return "Enabled"
        case .disabled: return "Disabled"
        case .unknown: return "Unknown"
        }
    }
}

/// Environment validation result
public struct EnvironmentValidationResult: Codable {
    /// Overall environment status
    public let overallStatus: EnvironmentStatus
    
    /// Individual validation check results
    public let validationChecks: [ValidationResult]
    
    /// Issues found during validation
    public let issues: [EnvironmentIssue]
    
    /// Time taken for validation
    public let validationTime: TimeInterval
    
    /// Validation timestamp
    public let timestamp: Date
    
    /// Prioritized recommendations
    public let recommendations: [String]
    
    public init(
        overallStatus: EnvironmentStatus,
        validationChecks: [ValidationResult],
        issues: [EnvironmentIssue],
        validationTime: TimeInterval,
        timestamp: Date,
        recommendations: [String]
    ) {
        self.overallStatus = overallStatus
        self.validationChecks = validationChecks
        self.issues = issues
        self.validationTime = validationTime
        self.timestamp = timestamp
        self.recommendations = recommendations
    }
}

/// Environment issue found during validation
public struct EnvironmentIssue: Codable {
    /// Issue category
    public let category: IssueCategory
    
    /// Issue severity
    public let severity: ValidationSeverity
    
    /// Issue description
    public let description: String
    
    /// Remediation instructions
    public let remediation: String
    
    public init(category: IssueCategory, severity: ValidationSeverity, description: String, remediation: String) {
        self.category = category
        self.severity = severity
        self.description = description
        self.remediation = remediation
    }
    
    /// Issue category types
    public enum IssueCategory: String, Codable, CaseIterable {
        case systemRequirements = "system_requirements"
        case developerTools = "developer_tools"
        case systemConfiguration = "system_configuration"
        case codeSigningCertificates = "code_signing_certificates"
    }
}

/// Environment setup result
public struct EnvironmentSetupResult: Codable {
    /// Whether setup was successful
    public let success: Bool
    
    /// Actions completed automatically
    public let completedActions: [String]
    
    /// Manual steps required
    public let manualSteps: [ManualSetupStep]
    
    /// Setup errors encountered
    public let errors: [EnvironmentSetupError]
    
    /// Time taken for setup
    public let setupTime: TimeInterval
    
    /// Setup timestamp
    public let timestamp: Date
    
    public init(
        success: Bool,
        completedActions: [String],
        manualSteps: [ManualSetupStep],
        errors: [EnvironmentSetupError],
        setupTime: TimeInterval,
        timestamp: Date
    ) {
        self.success = success
        self.completedActions = completedActions
        self.manualSteps = manualSteps
        self.errors = errors
        self.setupTime = setupTime
        self.timestamp = timestamp
    }
}

/// Manual setup step required
public struct ManualSetupStep: Codable {
    /// Step title
    public let title: String
    
    /// Step description
    public let description: String
    
    /// Detailed instructions
    public let instructions: [String]
    
    /// Step priority
    public let priority: Priority
    
    public init(title: String, description: String, instructions: [String], priority: Priority) {
        self.title = title
        self.description = description
        self.instructions = instructions
        self.priority = priority
    }
    
    /// Setup step priority
    public enum Priority: String, Codable, CaseIterable {
        case low = "low"
        case medium = "medium"
        case high = "high"
    }
}

/// Environment setup errors
public enum EnvironmentSetupError: Error, Codable {
    /// Xcode Command Line Tools installation failed
    case xcodeInstallationFailed(String)
    
    /// Permission error during setup
    case permissionError(String)
    
    /// File system error during setup
    case fileSystemError(String)
    
    /// Unknown setup error
    case unknownError(String)
}

extension EnvironmentSetupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .xcodeInstallationFailed(let details):
            return "Xcode Command Line Tools installation failed: \(details)"
        case .permissionError(let details):
            return "Permission error: \(details)"
        case .fileSystemError(let details):
            return "File system error: \(details)"
        case .unknownError(let details):
            return "Unknown setup error: \(details)"
        }
    }
}

/// Diagnostic result for environment components
public struct DiagnosticResult: Codable {
    /// Diagnostic category
    public let category: EnvironmentIssue.IssueCategory
    
    /// Result title
    public let title: String
    
    /// Overall status
    public let status: DiagnosticStatus
    
    /// Detailed information
    public let details: [String: String]
    
    /// Recommendations for improvement
    public let recommendations: [String]
    
    public init(
        category: EnvironmentIssue.IssueCategory,
        title: String,
        status: DiagnosticStatus,
        details: [String: String],
        recommendations: [String]
    ) {
        self.category = category
        self.title = title
        self.status = status
        self.details = details
        self.recommendations = recommendations
    }
}

/// Status for diagnostic results
public enum DiagnosticStatus: String, Codable, CaseIterable {
    case healthy = "healthy"
    case warning = "warning"
    case error = "error"
    case info = "info"
    
    public var displayName: String {
        switch self {
        case .healthy: return "Healthy"
        case .warning: return "Warning"
        case .error: return "Error"
        case .info: return "Information"
        }
    }
}

extension ValidationSeverity {
    var priority: ManualSetupStep.Priority {
        switch self {
        case .critical, .error:
            return .high
        case .warning:
            return .medium
        case .info:
            return .low
        }
    }
}