// AutomaticInstallationManager.swift
// Automatic System Extension installation manager for Homebrew integration

import Foundation
import SystemExtensions
import Common


/// Installation method used
public enum InstallationMethod {
    case automatic       // Automatic installation via OSSystemExtensionManager
    case development     // Development mode installation (unsigned)
    case manual          // Manual installation required
    case unavailable     // Installation not possible
    
    public var description: String {
        switch self {
        case .automatic:
            return "Automatic installation"
        case .development:
            return "Development mode installation"
        case .manual:
            return "Manual installation"
        case .unavailable:
            return "Installation unavailable"
        }
    }
}

/// Categorized installation errors for better user guidance
public enum InstallationErrorCategory {
    case developerModeRequired
    case userApprovalRequired
    case codeSigningIssues
    case systemPolicyBlocked
    case bundleValidationFailed
    case permissionDenied
    case systemIntegrityProtection
    case networkIssues
    case unknownError(String)
    
    public var userFriendlyDescription: String {
        switch self {
        case .developerModeRequired:
            return "Developer mode needs to be enabled"
        case .userApprovalRequired:
            return "User approval required in Security & Privacy settings"
        case .codeSigningIssues:
            return "Code signing validation failed"
        case .systemPolicyBlocked:
            return "Blocked by system security policy"
        case .bundleValidationFailed:
            return "System Extension bundle validation failed"
        case .permissionDenied:
            return "Permission denied during installation"
        case .systemIntegrityProtection:
            return "System Integrity Protection restrictions"
        case .networkIssues:
            return "Network connectivity issues"
        case .unknownError(let message):
            return "Unexpected error: \(message)"
        }
    }
    
    public var recoverySuggestion: String {
        switch self {
        case .developerModeRequired:
            return "Run 'sudo systemextensionsctl developer on' and restart your Mac"
        case .userApprovalRequired:
            return "Check System Preferences > Security & Privacy > General for approval prompt"
        case .codeSigningIssues:
            return "Ensure the System Extension is properly signed or use developer mode"
        case .systemPolicyBlocked:
            return "Check system security settings and policies"
        case .bundleValidationFailed:
            return "Reinstall the application and try again"
        case .permissionDenied:
            return "Run installation with administrator privileges"
        case .systemIntegrityProtection:
            return "Ensure System Integrity Protection allows System Extensions"
        case .networkIssues:
            return "Check internet connectivity and firewall settings"
        case .unknownError:
            return "Contact support with the error details"
        }
    }
}

/// Automatic installation manager for Homebrew System Extension integration
public class AutomaticInstallationManager {
    
    // MARK: - Nested Types
    
    /// Installation state tracking
    public enum InstallationState: String {
        case notStarted = "not_started"
        case inProgress = "in_progress"
        case completed = "completed"
        case failed = "failed"
        case requiresManualIntervention = "requires_manual_intervention"
        
        public var description: String {
            switch self {
            case .notStarted:
                return "Not started"
            case .inProgress:
                return "In progress"
            case .completed:
                return "Completed"
            case .failed:
                return "Failed"
            case .requiresManualIntervention:
                return "Requires manual intervention"
            }
        }
    }
    
    /// Installation attempt result with detailed information
    public struct InstallationAttemptResult {
        /// Whether the automatic installation was successful
        public let success: Bool
        
        /// Final status after installation attempt
        public let finalStatus: InstallationState
        
        /// Whether manual installation is required
        public let requiresManualInstallation: Bool
        
        /// Categorized errors that occurred during installation
        public let errors: [InstallationErrorCategory]
        
        /// Warnings that don't prevent installation
        public let warnings: [String]
        
        /// Time taken for the installation attempt
        public let installationTime: TimeInterval
        
        /// Duration (alias for installationTime for compatibility)
        public var duration: TimeInterval { return installationTime }
        
        /// Method used for installation attempt
        public let installationMethod: InstallationMethod
        
        /// User-friendly instructions if manual installation is required
        public let manualInstallationInstructions: String?
        
        /// Developer mode status during installation
        public let developerModeStatus: DeveloperModeDetectionResult
        
        public init(
            success: Bool,
            finalStatus: InstallationState,
            requiresManualInstallation: Bool = false,
            errors: [InstallationErrorCategory] = [],
            warnings: [String] = [],
            installationTime: TimeInterval = 0,
            installationMethod: InstallationMethod = .automatic,
            manualInstallationInstructions: String? = nil,
            developerModeStatus: DeveloperModeDetectionResult
        ) {
            self.success = success
            self.finalStatus = finalStatus
            self.requiresManualInstallation = requiresManualInstallation
            self.errors = errors
            self.warnings = warnings
            self.installationTime = installationTime
            self.installationMethod = installationMethod
            self.manualInstallationInstructions = manualInstallationInstructions
            self.developerModeStatus = developerModeStatus
        }
    }
    
    // MARK: - Properties
    
    private let logger: Logger
    private let systemExtensionInstaller: SystemExtensionInstaller
    private let developerModeDetector: DeveloperModeDetector
    private let homebrewBundleCreator: HomebrewBundleCreator
    
    /// Installation timeout for automatic attempts
    public var installationTimeout: TimeInterval = 60.0
    
    /// Maximum retry attempts for automatic installation
    public var maxRetryAttempts: Int = 3
    
    /// Current installation state
    private var currentState: InstallationState = .notStarted
    
    /// Installation attempt history
    private var attemptHistory: [InstallationAttemptResult] = []
    
    // MARK: - Initialization
    
    /// Initialize automatic installation manager
    /// - Parameters:
    ///   - config: Server configuration
    ///   - installer: System Extension installer instance
    ///   - logger: Custom logger instance (uses shared logger if nil)
    public init(
        config: ServerConfig,
        installer: SystemExtensionInstaller,
        logger: Logger? = nil
    ) {
        self.systemExtensionInstaller = installer
        self.developerModeDetector = DeveloperModeDetector(logger: logger)
        self.homebrewBundleCreator = HomebrewBundleCreator(logger: logger)
        self.logger = logger ?? Logger.shared
    }
    
    // MARK: - Automatic Installation
    
    /// Attempt automatic System Extension installation for Homebrew
    /// - Parameter config: Homebrew bundle configuration
    /// - Returns: Installation attempt result with detailed information
    public func attemptAutomaticInstallation(with config: HomebrewBundleConfig) async -> InstallationAttemptResult {
        let startTime = Date()
        
        logger.info("Starting automatic System Extension installation", context: [
            "bundleIdentifier": config.bundleIdentifier,
            "formulaName": config.formulaName
        ])
        
        // Step 1: Check developer mode status
        let developerModeStatus = developerModeDetector.detectDeveloperMode()
        let installationStrategy = developerModeDetector.getInstallationStrategy()
        
        logger.debug("Installation strategy determined", context: [
            "strategy": installationStrategy.description,
            "developerModeEnabled": developerModeStatus.isEnabled
        ])
        
        // Step 2: Validate Homebrew configuration
        let configValidationErrors = homebrewBundleCreator.validateHomebrewConfig(config)
        if !configValidationErrors.isEmpty {
            let installationTime = Date().timeIntervalSince(startTime)
            return InstallationAttemptResult(
                success: false,
                requiresManualInstallation: true,
                errors: [.bundleValidationFailed],
                warnings: configValidationErrors,
                installationTime: installationTime,
                installationMethod: .unavailable,
                manualInstallationInstructions: generateConfigValidationInstructions(errors: configValidationErrors),
                developerModeStatus: developerModeStatus
            )
        }
        
        // Step 3: Determine installation approach based on strategy
        switch installationStrategy {
        case .automatic:
            return await performAutomaticInstallation(config: config, developerModeStatus: developerModeStatus, startTime: startTime)
        case .manual:
            return await attemptDevelopmentModeInstallation(config: config, developerModeStatus: developerModeStatus, startTime: startTime)
        case .unavailable:
            let installationTime = Date().timeIntervalSince(startTime)
            return InstallationAttemptResult(
                success: false,
                requiresManualInstallation: true,
                errors: [.systemPolicyBlocked],
                installationTime: installationTime,
                installationMethod: .unavailable,
                manualInstallationInstructions: generateUnavailableInstallationInstructions(),
                developerModeStatus: developerModeStatus
            )
        }
    }
    
    /// Check if automatic installation is possible
    /// - Returns: True if automatic installation can be attempted
    public func canAttemptAutomaticInstallation() -> Bool {
        let strategy = developerModeDetector.getInstallationStrategy()
        return strategy == .automatic || strategy == .manual
    }
    
    // MARK: - Installation Attempts
    
    /// Perform automatic installation when developer mode is enabled
    private func performAutomaticInstallation(
        config: HomebrewBundleConfig,
        developerModeStatus: DeveloperModeDetectionResult,
        startTime: Date
    ) async -> InstallationAttemptResult {
        logger.info("Performing automatic installation with developer mode enabled")
        
        do {
            // Create Homebrew bundle
            let bundle = try homebrewBundleCreator.createHomebrewBundle(with: config)
            
            // Attempt installation with the created bundle
            return await withCheckedContinuation { continuation in
                systemExtensionInstaller.installWithRetry(
                    bundleIdentifier: config.bundleIdentifier,
                    executablePath: config.executablePath,
                    maxRetries: maxRetryAttempts
                ) { [weak self] result in
                    let installationTime = Date().timeIntervalSince(startTime)
                    let attemptResult = self?.processInstallationResult(
                        result: result,
                        config: config,
                        developerModeStatus: developerModeStatus,
                        installationTime: installationTime,
                        method: .automatic
                    ) ?? InstallationAttemptResult(
                        success: false,
                        requiresManualInstallation: true,
                        errors: [.unknownError("Installation manager unavailable")],
                        installationTime: installationTime,
                        developerModeStatus: developerModeStatus
                    )
                    continuation.resume(returning: attemptResult)
                }
            }
        } catch {
            let installationTime = Date().timeIntervalSince(startTime)
            logger.error("Bundle creation failed during automatic installation", context: [
                "error": error.localizedDescription
            ])
            
            return InstallationAttemptResult(
                success: false,
                requiresManualInstallation: true,
                errors: [.bundleValidationFailed],
                warnings: ["Bundle creation failed: \(error.localizedDescription)"],
                installationTime: installationTime,
                installationMethod: .automatic,
                manualInstallationInstructions: generateBundleCreationFailureInstructions(error: error),
                developerModeStatus: developerModeStatus
            )
        }
    }
    
    /// Attempt installation in development mode (fallback when developer mode is disabled)
    private func attemptDevelopmentModeInstallation(
        config: HomebrewBundleConfig,
        developerModeStatus: DeveloperModeDetectionResult,
        startTime: Date
    ) async -> InstallationAttemptResult {
        logger.info("Attempting development mode installation as fallback")
        
        let installationTime = Date().timeIntervalSince(startTime)
        
        // Generate instructions for enabling developer mode and manual installation
        let instructions = generateDeveloperModeInstructions(config: config)
        
        return InstallationAttemptResult(
            success: false,
            requiresManualInstallation: true,
            errors: [.developerModeRequired],
            warnings: ["Developer mode must be enabled for automatic installation"],
            installationTime: installationTime,
            installationMethod: .manual,
            manualInstallationInstructions: instructions,
            developerModeStatus: developerModeStatus
        )
    }
    
    // MARK: - Result Processing
    
    /// Process installation result and categorize errors
    private func processInstallationResult(
        result: InstallationResult,
        config: HomebrewBundleConfig,
        developerModeStatus: DeveloperModeDetectionResult,
        installationTime: TimeInterval,
        method: InstallationMethod
    ) -> InstallationAttemptResult {
        if result.success {
            logger.info("Automatic installation completed successfully", context: [
                "installationTime": installationTime,
                "method": method.description
            ])
            
            return InstallationAttemptResult(
                success: true,
                requiresManualInstallation: false,
                warnings: result.warnings,
                installationTime: installationTime,
                installationMethod: method,
                developerModeStatus: developerModeStatus
            )
        } else {
            logger.warning("Automatic installation failed", context: [
                "errorCount": result.errors.count,
                "installationTime": installationTime
            ])
            
            let categorizedErrors = categorizeInstallationErrors(result.errors)
            let requiresManual = shouldFallbackToManual(errors: categorizedErrors)
            let instructions = requiresManual ? generateManualInstallationInstructions(
                config: config,
                errors: categorizedErrors,
                warnings: result.warnings
            ) : nil
            
            return InstallationAttemptResult(
                success: false,
                requiresManualInstallation: requiresManual,
                errors: categorizedErrors,
                warnings: result.warnings,
                installationTime: installationTime,
                installationMethod: method,
                manualInstallationInstructions: instructions,
                developerModeStatus: developerModeStatus
            )
        }
    }
    
    // MARK: - Error Categorization
    
    /// Categorize installation errors for better user guidance
    private func categorizeInstallationErrors(_ errors: [InstallationError]) -> [InstallationErrorCategory] {
        return errors.map { error in
            switch error {
            case .developerModeRequired:
                return .developerModeRequired
            case .userApprovalFailed:
                return .userApprovalRequired
            case .codeSigningFailed, .certificateValidationFailed:
                return .codeSigningIssues
            case .sipBlocked:
                return .systemIntegrityProtection
            case .bundleValidationFailed:
                return .bundleValidationFailed
            case .permissionDenied:
                return .permissionDenied
            case .networkError:
                return .networkIssues
            case .unknownError(let message):
                return .unknownError(message)
            default:
                return .unknownError(error.localizedDescription)
            }
        }
    }
    
    /// Determine if manual installation fallback is appropriate
    private func shouldFallbackToManual(errors: [InstallationErrorCategory]) -> Bool {
        // Always fallback to manual for these error types
        let manualRequiredErrors: [InstallationErrorCategory] = [
            .developerModeRequired,
            .userApprovalRequired,
            .systemPolicyBlocked,
            .systemIntegrityProtection
        ]
        
        return errors.contains { error in
            manualRequiredErrors.contains { manualError in
                switch (error, manualError) {
                case (.developerModeRequired, .developerModeRequired),
                     (.userApprovalRequired, .userApprovalRequired),
                     (.systemPolicyBlocked, .systemPolicyBlocked),
                     (.systemIntegrityProtection, .systemIntegrityProtection):
                    return true
                default:
                    return false
                }
            }
        }
    }
    
    // MARK: - Instruction Generation
    
    /// Generate manual installation instructions
    private func generateManualInstallationInstructions(
        config: HomebrewBundleConfig,
        errors: [InstallationErrorCategory],
        warnings: [String]
    ) -> String {
        var instructions: [String] = []
        
        instructions.append("Manual System Extension Installation Required")
        instructions.append("================================================")
        instructions.append("")
        
        // Add error-specific instructions
        for error in errors {
            instructions.append("Issue: \(error.userFriendlyDescription)")
            instructions.append("Solution: \(error.recoverySuggestion)")
            instructions.append("")
        }
        
        // Add general installation steps
        instructions.append("Manual Installation Steps:")
        instructions.append("1. Enable System Extension developer mode:")
        instructions.append("   sudo systemextensionsctl developer on")
        instructions.append("   # Restart your Mac after enabling")
        instructions.append("")
        instructions.append("2. Retry Homebrew installation:")
        instructions.append("   brew reinstall \(config.formulaName)")
        instructions.append("")
        instructions.append("3. If issues persist, check Security & Privacy:")
        instructions.append("   System Preferences > Security & Privacy > General")
        instructions.append("   Look for blocked System Extension notifications")
        instructions.append("")
        
        if !warnings.isEmpty {
            instructions.append("Additional Notes:")
            for warning in warnings {
                instructions.append("• \(warning)")
            }
            instructions.append("")
        }
        
        instructions.append("For more help, visit: https://github.com/usbipd-mac/usbipd-mac/wiki")
        
        return instructions.joined(separator: "\n")
    }
    
    /// Generate developer mode enablement instructions
    private func generateDeveloperModeInstructions(config: HomebrewBundleConfig) -> String {
        return """
        System Extension Developer Mode Required
        =======================================
        
        The \(config.formulaName) System Extension requires developer mode to be enabled
        for automatic installation.
        
        Steps to enable developer mode:
        
        1. Enable developer mode:
           sudo systemextensionsctl developer on
        
        2. Restart your Mac (required for developer mode to take effect)
        
        3. Retry the Homebrew installation:
           brew reinstall \(config.formulaName)
        
        Alternative: Manual Installation
        ===============================
        
        If you prefer not to enable developer mode:
        
        1. Install the bundle manually through System Preferences
        2. Navigate to Security & Privacy > General
        3. Look for blocked System Extension notifications
        4. Click "Allow" to approve the extension
        
        For more information about System Extensions and developer mode:
        https://developer.apple.com/documentation/systemextensions
        """
    }
    
    /// Generate instructions for configuration validation failures
    private func generateConfigValidationInstructions(errors: [String]) -> String {
        var instructions: [String] = []
        
        instructions.append("Homebrew Configuration Validation Failed")
        instructions.append("=======================================")
        instructions.append("")
        instructions.append("The following issues were found with the installation configuration:")
        instructions.append("")
        
        for (index, error) in errors.enumerated() {
            instructions.append("\(index + 1). \(error)")
        }
        
        instructions.append("")
        instructions.append("Please ensure that:")
        instructions.append("• Homebrew is properly installed")
        instructions.append("• The formula is compatible with your system")
        instructions.append("• All required dependencies are available")
        instructions.append("")
        instructions.append("Try reinstalling the formula:")
        instructions.append("brew reinstall usbipd-mac")
        
        return instructions.joined(separator: "\n")
    }
    
    /// Generate instructions for unavailable installation
    private func generateUnavailableInstallationInstructions() -> String {
        return """
        System Extension Installation Not Available
        ==========================================
        
        System Extension installation is not available on this system.
        This may be due to:
        
        • Unsupported macOS version (requires macOS 10.15+)
        • System Integrity Protection restrictions
        • Corporate security policies
        • Missing system components
        
        System Requirements:
        • macOS 10.15 (Catalina) or later
        • System Extensions support enabled
        • Administrator privileges
        
        Contact your system administrator if you believe this is an error.
        """
    }
    
    /// Generate instructions for bundle creation failures
    private func generateBundleCreationFailureInstructions(error: Error) -> String {
        return """
        System Extension Bundle Creation Failed
        ======================================
        
        Failed to create the System Extension bundle during installation.
        
        Error: \(error.localizedDescription)
        
        Troubleshooting Steps:
        
        1. Ensure sufficient disk space is available
        2. Check file system permissions
        3. Verify Homebrew installation integrity:
           brew doctor
        
        4. Reinstall the formula:
           brew uninstall usbipd-mac
           brew install usbipd-mac
        
        5. If issues persist, try a clean installation:
           brew cleanup
           brew install usbipd-mac
        
        For additional support, please file an issue at:
        https://github.com/usbipd-mac/usbipd-mac/issues
        """
    }
    
    // MARK: - Status and Diagnostics
    
    /// Get current installation readiness status
    /// - Returns: Detailed status information for diagnostics
    public func getInstallationReadinessStatus() -> InstallationReadinessStatus {
        let developerModeStatus = developerModeDetector.detectDeveloperMode()
        let detailedStatus = developerModeDetector.getDetailedStatus()
        let strategy = developerModeDetector.getInstallationStrategy()
        
        return InstallationReadinessStatus(
            canAttemptAutomatic: canAttemptAutomaticInstallation(),
            recommendedStrategy: strategy,
            developerModeStatus: developerModeStatus,
            systemInfo: detailedStatus.systemInfo,
            readinessChecks: performReadinessChecks()
        )
    }
    
    /// Perform readiness checks for installation
    private func performReadinessChecks() -> [ReadinessCheck] {
        var checks: [ReadinessCheck] = []
        
        // Check developer mode
        let developerModeResult = developerModeDetector.detectDeveloperMode()
        checks.append(ReadinessCheck(
            name: "Developer Mode",
            passed: developerModeResult.isEnabled,
            message: developerModeResult.isEnabled ? "Enabled" : "Disabled",
            required: false
        ))
        
        // Check systemextensionsctl availability
        let ctlAvailable = developerModeDetector.validateSystemExtensionsCtlAvailability()
        checks.append(ReadinessCheck(
            name: "System Extensions Control",
            passed: ctlAvailable,
            message: ctlAvailable ? "Available" : "Not available",
            required: true
        ))
        
        // Check macOS version
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let supportedVersion = version.majorVersion >= 11 || (version.majorVersion == 10 && version.minorVersion >= 15)
        checks.append(ReadinessCheck(
            name: "macOS Version",
            passed: supportedVersion,
            message: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            required: true
        ))
        
        return checks
    }
}

// MARK: - Supporting Types

/// Installation readiness status
public struct InstallationReadinessStatus {
    public let canAttemptAutomatic: Bool
    public let recommendedStrategy: InstallationStrategy
    public let developerModeStatus: DeveloperModeDetectionResult
    public let systemInfo: [String: Any]
    public let readinessChecks: [ReadinessCheck]
    
    public var overallReadiness: ReadinessLevel {
        let failedRequired = readinessChecks.filter { $0.required && !$0.passed }
        let failedOptional = readinessChecks.filter { !$0.required && !$0.passed }
        
        if !failedRequired.isEmpty {
            return .notReady
        } else if !failedOptional.isEmpty {
            return .partiallyReady
        } else {
            return .ready
        }
    }
}

/// Readiness level for installation
public enum ReadinessLevel {
    case ready
    case partiallyReady
    case notReady
    
    public var description: String {
        switch self {
        case .ready:
            return "Ready for installation"
        case .partiallyReady:
            return "Partially ready (some optional features unavailable)"
        case .notReady:
            return "Not ready for installation"
        }
    }
}

/// Individual readiness check
public struct ReadinessCheck {
    public let name: String
    public let passed: Bool
    public let message: String
    public let required: Bool
    
    public init(name: String, passed: Bool, message: String, required: Bool = false) {
        self.name = name
        self.passed = passed
        self.message = message
        self.required = required
    }
}

// MARK: - Server Coordinator API Compatibility

extension AutomaticInstallationManager {
    
    /// Attempt automatic installation with callback (for compatibility with ServerCoordinator)
    /// - Parameter completion: Completion handler with installation result
    public func attemptAutomaticInstallation(completion: @escaping (InstallationAttemptResult) -> Void) {
        currentState = .inProgress
        
        // Create a default Homebrew configuration for automatic installation
        let config = HomebrewBundleConfig(
            homebrewPrefix: "/opt/homebrew", // Default for Apple Silicon, fallback to detecting
            formulaVersion: "latest",
            installationPrefix: "/opt/homebrew/Cellar/usbipd-mac/latest",
            bundleIdentifier: "com.github.usbipd-mac.systemextension",
            displayName: "USBIPD System Extension",
            executableName: "USBIPDSystemExtension",
            teamIdentifier: "", // Will be determined at runtime
            executablePath: "", // Will be determined at runtime
            formulaName: "usbipd-mac",
            buildNumber: "1"
        )
        
        Task {
            let result = await attemptAutomaticInstallation(with: config)
            
            // Update internal state
            currentState = result.success ? .completed : .failed
            attemptHistory.append(result)
            
            // Call completion handler on main queue
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    /// Get current installation status and history (for compatibility with ServerCoordinator)
    /// - Returns: Tuple of current state and attempt history
    public func getInstallationStatus() -> (state: InstallationState, history: [InstallationAttemptResult]) {
        return (state: currentState, history: attemptHistory)
    }
}