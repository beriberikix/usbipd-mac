import Foundation
import SystemExtensions
import Common

/// Advanced System Extension installer with comprehensive installation management
public final class SystemExtensionInstaller: NSObject, @unchecked Sendable {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.github.usbipd-mac", category: "SystemExtensionInstaller")
    private let bundleCreator: SystemExtensionBundleCreator
    private let codeSigningManager: CodeSigningManager
    
    /// Current installation status
    public private(set) var installationStatus: SystemExtensionInstallationStatus = .unknown
    
    /// Installation completion handler
    public typealias InstallationCompletion = (USBIPDCore.InstallationResult) -> Void
    
    private var currentCompletion: InstallationCompletion?
    private var currentRequest: OSSystemExtensionRequest?
    private var installationStartTime: Date?
    
    // MARK: - Initialization
    
    /// Initialize installer with bundle creator and code signing manager
    /// - Parameters:
    ///   - bundleCreator: Bundle creator for System Extension bundles
    ///   - codeSigningManager: Manager for code signing operations
    public init(bundleCreator: SystemExtensionBundleCreator, codeSigningManager: CodeSigningManager) {
        self.bundleCreator = bundleCreator
        self.codeSigningManager = codeSigningManager
        super.init()
        
        logger.info("SystemExtensionInstaller initialized")
    }
    
    // MARK: - Installation Status Detection
    
    /// Check current installation status using systemextensionsctl
    public func checkInstallationStatus() async -> SystemExtensionInstallationStatus {
        logger.debug("Checking System Extension installation status")
        
        do {
            let result = try await executeSystemExtensionsCtl(command: "list")
            return parseInstallationStatus(from: result)
        } catch {
            logger.error("Failed to check installation status", context: ["error": error.localizedDescription])
            return .unknown
        }
    }
    
    /// Monitor installation status changes
    public func monitorInstallationStatus(interval: TimeInterval = 2.0, callback: @escaping (SystemExtensionInstallationStatus) -> Void) {
        Task {
            while installationStatus == .installing {
                let status = await checkInstallationStatus()
                if status != installationStatus {
                    installationStatus = status
                    callback(status)
                    
                    if status != .installing {
                        break
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }
    
    // MARK: - Installation Workflows
    
    /// Perform basic installation workflow with bundle creation and signing
    /// - Parameters:
    ///   - bundleIdentifier: Bundle identifier for the System Extension
    ///   - executablePath: Path to compiled executable
    ///   - completion: Installation completion handler
    public func installSystemExtension(
        bundleIdentifier: String,
        executablePath: String,
        completion: @escaping InstallationCompletion
    ) {
        logger.info("Starting System Extension installation", context: [
            "bundleIdentifier": bundleIdentifier,
            "executablePath": executablePath
        ])
        
        guard installationStatus != .installing else {
            let result = InstallationResult(
                success: false,
                errors: [.unknownError("Installation already in progress")]
            )
            completion(result)
            return
        }
        
        self.currentCompletion = completion
        self.installationStartTime = Date()
        self.installationStatus = .installing
        
        Task {
            await performInstallationWorkflow(
                bundleIdentifier: bundleIdentifier,
                executablePath: executablePath
            )
        }
    }
    
    /// Perform force reinstallation of System Extension
    /// - Parameters:
    ///   - bundleIdentifier: Bundle identifier for the System Extension
    ///   - executablePath: Path to compiled executable
    ///   - completion: Installation completion handler
    public func forceReinstallSystemExtension(
        bundleIdentifier: String,
        executablePath: String,
        completion: @escaping InstallationCompletion
    ) {
        logger.info("Starting force reinstallation", context: ["bundleIdentifier": bundleIdentifier])
        
        Task {
            // First uninstall existing extension
            uninstallSystemExtension { [weak self] uninstallResult in
                if uninstallResult.success {
                    // Wait a moment for system cleanup
                    Task { @MainActor [weak self] in
                        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        self?.installSystemExtension(
                            bundleIdentifier: bundleIdentifier,
                            executablePath: executablePath,
                            completion: completion
                        )
                    }
                } else {
                    // Proceed with installation even if uninstall failed
                    self?.installSystemExtension(
                        bundleIdentifier: bundleIdentifier,
                        executablePath: executablePath,
                        completion: completion
                    )
                }
            }
        }
    }
    
    /// Uninstall System Extension
    /// - Parameter completion: Installation completion handler
    public func uninstallSystemExtension(completion: @escaping InstallationCompletion) {
        logger.info("Starting System Extension uninstallation")
        
        guard let request = currentRequest else {
            // Create deactivation request if no current request
            Task {
                await performUninstallWorkflow(completion: completion)
            }
            return
        }
        
        // Cancel current request first
        request.delegate = nil
        currentRequest = nil
        
        Task {
            await performUninstallWorkflow(completion: completion)
        }
    }
    
    /// Verify System Extension installation integrity
    /// - Returns: Validation results for the installation
    public func verifyInstallation() async -> [ValidationResult] {
        logger.debug("Verifying System Extension installation")
        
        var results: [ValidationResult] = []
        
        // Check installation status
        let status = await checkInstallationStatus()
        let statusResult = ValidationResult(
            checkID: "installation_status",
            checkName: "Installation Status",
            passed: status == .installed,
            message: "System Extension status: \(status.rawValue)",
            severity: status == .installed ? .info : .error,
            recommendedActions: status == .installed ? [] : ["Reinstall System Extension"]
        )
        results.append(statusResult)
        
        // Check for running processes
        let processResult = await verifyExtensionProcess()
        results.append(processResult)
        
        // Check system logs for errors
        let logResult = await checkSystemLogs()
        results.append(logResult)
        
        return results
    }
    
    /// Get installation health status
    /// - Returns: Current health status with detailed information
    public func getInstallationHealth() async -> HealthStatus {
        let validationResults = await verifyInstallation()
        
        let failedCritical = validationResults.filter { !$0.passed && $0.severity == .critical }
        let failedError = validationResults.filter { !$0.passed && $0.severity == .error }
        let warnings = validationResults.filter { !$0.passed && $0.severity == .warning }
        
        if !failedCritical.isEmpty {
            return .critical
        } else if !failedError.isEmpty {
            return .unhealthy
        } else if !warnings.isEmpty {
            return .degraded
        } else {
            return .healthy
        }
    }
    
    // MARK: - Private Installation Implementation
    
    private func performInstallationWorkflow(
        bundleIdentifier: String,
        executablePath: String
    ) async {
        var errors: [InstallationError] = []
        var warnings: [String] = []
        
        do {
            // Step 1: Create System Extension bundle
            logger.info("Creating System Extension bundle")
            let config = SystemExtensionBundleCreator.BundleCreationConfig(
                bundlePath: "/tmp/SystemExtension.appex",
                bundleIdentifier: bundleIdentifier,
                displayName: "USB/IP System Extension",
                version: "1.0.0",
                buildNumber: "1",
                executableName: "SystemExtension",
                executablePath: executablePath
            )
            let bundle = try bundleCreator.createBundle(with: config)
            
            // Step 2: Sign the bundle
            logger.info("Signing System Extension bundle")
            let signingResult = try codeSigningManager.signBundle(at: bundle.bundlePath)
            
            if signingResult.success {
                // Step 3: Install the signed bundle
                await installBundle(bundle, warnings: &warnings)
            } else {
                logger.warning("Code signing failed, attempting unsigned installation", context: [
                    "errors": signingResult.errors.joined(separator: "; ")
                ])
                warnings.append("Code signing failed: \(signingResult.errors.joined(separator: "; "))")
                
                // Attempt installation without signing (development mode)
                await installBundle(bundle, warnings: &warnings)
            }
        } catch {
            errors.append(.bundleCreationFailed(error.localizedDescription))
            completeInstallation(
                success: false,
                bundle: nil,
                errors: errors,
                warnings: warnings
            )
        }
    }
    
    private func installBundle(_ bundle: SystemExtensionBundle, warnings: inout [String]) async {
        // Create activation request
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: bundle.bundleIdentifier,
            queue: .main
        )
        
        request.delegate = self
        self.currentRequest = request
        
        // Submit the request
        logger.info("Submitting System Extension activation request")
        await MainActor.run {
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }
    
    // MARK: - System Extensions Control Integration
    
    private func executeSystemExtensionsCtl(command: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
            process.arguments = [command]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let error = InstallationError.systemExtensionsCtlFailed(
                        process.terminationStatus,
                        output
                    )
                    continuation.resume(throwing: error)
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: InstallationError.systemExtensionsCtlFailed(-1, error.localizedDescription))
            }
        }
    }
    
    private func parseInstallationStatus(from output: String) -> SystemExtensionInstallationStatus {
        // Parse systemextensionsctl output to determine installation status
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("enabled") && line.contains("active") {
                return .installed
            } else if line.contains("enabled") {
                return .pendingApproval
            }
        }
        
        return .notInstalled
    }
    
    // MARK: - Installation Verification and Monitoring
    
    private func performUninstallWorkflow(completion: @escaping InstallationCompletion) async {
        logger.info("Performing System Extension uninstallation")
        
        do {
            _ = try await executeSystemExtensionsCtl(command: "reset")
            
            logger.info("System Extension uninstallation completed")
            let uninstallResult = InstallationResult(
                success: true,
                warnings: ["System extensions reset - may affect other extensions"]
            )
            completion(uninstallResult)
        } catch {
            logger.error("System Extension uninstallation failed", context: ["error": error.localizedDescription])
            let uninstallResult = InstallationResult(
                success: false,
                errors: [.systemExtensionsCtlFailed(-1, error.localizedDescription)]
            )
            completion(uninstallResult)
        }
    }
    
    private func verifyExtensionProcess() async -> ValidationResult {
        do {
            let output = try await executeSystemExtensionsCtl(command: "list")
            let isRunning = output.contains("active") && output.contains("enabled")
            
            return ValidationResult(
                checkID: "extension_process",
                checkName: "Extension Process Check",
                passed: isRunning,
                message: isRunning ? "System Extension is active" : "System Extension is not active",
                severity: isRunning ? .info : .error,
                recommendedActions: isRunning ? [] : ["Restart System Extension", "Check system logs"]
            )
        } catch {
            return ValidationResult(
                checkID: "extension_process",
                checkName: "Extension Process Check",
                passed: false,
                message: "Failed to check extension status: \(error.localizedDescription)",
                severity: .error,
                recommendedActions: ["Check systemextensionsctl permissions", "Restart system"]
            )
        }
    }
    
    private func checkSystemLogs() async -> ValidationResult {
        // Check system logs for System Extension related errors
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = [
                "show",
                "--last", "10m",
                "--predicate", "subsystem CONTAINS 'systemextensions' OR category CONTAINS 'systemextensions'",
                "--style", "compact"
            ]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            let hasErrors = output.contains("error") || output.contains("failed") || output.contains("denied")
            
            return ValidationResult(
                checkID: "system_logs",
                checkName: "System Log Check",
                passed: !hasErrors,
                message: hasErrors ? "System Extension errors found in logs" : "No System Extension errors in recent logs",
                severity: hasErrors ? .warning : .info,
                recommendedActions: hasErrors ? ["Check full system logs", "Reinstall extension"] : []
            )
        } catch {
            return ValidationResult(
                checkID: "system_logs",
                checkName: "System Log Check",
                passed: false,
                message: "Failed to check system logs: \(error.localizedDescription)",
                severity: .warning,
                recommendedActions: ["Check log access permissions"]
            )
        }
    }
    
    /// Perform installation retry with exponential backoff
    /// - Parameters:
    ///   - bundleIdentifier: Bundle identifier for the System Extension
    ///   - executablePath: Path to compiled executable
    ///   - maxRetries: Maximum number of retry attempts
    ///   - completion: Installation completion handler
    public func installWithRetry(
        bundleIdentifier: String,
        executablePath: String,
        maxRetries: Int = 3,
        completion: @escaping InstallationCompletion
    ) {
        performRetryInstallation(
            bundleIdentifier: bundleIdentifier,
            executablePath: executablePath,
            currentAttempt: 1,
            maxRetries: maxRetries,
            completion: completion
        )
    }
    
    private func performRetryInstallation(
        bundleIdentifier: String,
        executablePath: String,
        currentAttempt: Int,
        maxRetries: Int,
        completion: @escaping InstallationCompletion
    ) {
        logger.info("Installation attempt \(currentAttempt) of \(maxRetries)")
        
        installSystemExtension(bundleIdentifier: bundleIdentifier, executablePath: executablePath) { [weak self] result in
            if result.success || currentAttempt >= maxRetries {
                completion(result)
            } else {
                // Calculate backoff delay (exponential: 2^attempt seconds)
                let delaySeconds = min(pow(2.0, Double(currentAttempt)), 30.0)
                
                self?.logger.info("Installation failed, retrying in \(delaySeconds) seconds", context: [
                    "attempt": currentAttempt,
                    "maxRetries": maxRetries
                ])
                
                Task { @MainActor [weak self] in
                    try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                    self?.performRetryInstallation(
                        bundleIdentifier: bundleIdentifier,
                        executablePath: executablePath,
                        currentAttempt: currentAttempt + 1,
                        maxRetries: maxRetries,
                        completion: completion
                    )
                }
            }
        }
    }
    
    // MARK: - Developer Mode Management
    
    /// Check if System Extension developer mode is enabled
    /// - Returns: True if developer mode is enabled
    public func isDeveloperModeEnabled() async -> Bool {
        do {
            let output = try await executeSystemExtensionsCtl(command: "developer")
            return output.contains("Developer mode: on") || output.contains("enabled")
        } catch {
            logger.debug("Failed to check developer mode status", context: ["error": error.localizedDescription])
            return false
        }
    }
    
    /// Enable System Extension developer mode
    /// - Returns: Success or failure of enabling developer mode
    public func enableDeveloperMode() async throws {
        logger.info("Attempting to enable System Extension developer mode")
        
        do {
            _ = try await executeSystemExtensionsCtl(command: "developer on")
            logger.info("System Extension developer mode enabled successfully")
        } catch {
            logger.error("Failed to enable developer mode", context: ["error": error.localizedDescription])
            throw InstallationError.developerModeRequired("Failed to enable developer mode: \(error.localizedDescription)")
        }
    }
    
    /// Disable System Extension developer mode
    /// - Returns: Success or failure of disabling developer mode
    public func disableDeveloperMode() async throws {
        logger.info("Attempting to disable System Extension developer mode")
        
        do {
            _ = try await executeSystemExtensionsCtl(command: "developer off")
            logger.info("System Extension developer mode disabled successfully")
        } catch {
            logger.error("Failed to disable developer mode", context: ["error": error.localizedDescription])
            throw InstallationError.unknownError("Failed to disable developer mode: \(error.localizedDescription)")
        }
    }
    
    /// Get developer mode guidance and status
    /// - Returns: Validation result with developer mode information
    public func getDeveloperModeGuidance() async -> ValidationResult {
        let isEnabled = await isDeveloperModeEnabled()
        
        if isEnabled {
            return ValidationResult(
                checkID: "developer_mode",
                checkName: "Developer Mode Status",
                passed: true,
                message: "Developer mode is enabled",
                severity: .info,
                recommendedActions: []
            )
        } else {
            return ValidationResult(
                checkID: "developer_mode",
                checkName: "Developer Mode Status",
                passed: false,
                message: "Developer mode is disabled - required for unsigned System Extensions",
                severity: .warning,
                recommendedActions: [
                    "Enable developer mode: systemextensionsctl developer on",
                    "Restart Terminal/IDE after enabling",
                    "Use proper code signing certificates for production"
                ]
            )
        }
    }
    
    /// Check System Integrity Protection (SIP) status
    /// - Returns: Validation result with SIP status information
    public func checkSIPStatus() async -> ValidationResult {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
            process.arguments = ["status"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            let sipEnabled = output.contains("enabled")
            
            return ValidationResult(
                checkID: "sip_status",
                checkName: "System Integrity Protection",
                passed: true, // SIP status is informational
                message: sipEnabled ? "SIP is enabled (normal)" : "SIP is disabled",
                severity: sipEnabled ? .info : .warning,
                recommendedActions: sipEnabled ? [] : [
                    "Consider re-enabling SIP for security",
                    "Use proper code signing for production"
                ]
            )
        } catch {
            return ValidationResult(
                checkID: "sip_status",
                checkName: "System Integrity Protection",
                passed: false,
                message: "Failed to check SIP status: \(error.localizedDescription)",
                severity: .warning,
                recommendedActions: ["Check csrutil command availability"]
            )
        }
    }
    
    /// Setup development environment for System Extension development
    /// - Returns: Installation result with setup status and guidance
    public func setupDevelopmentEnvironment() async -> InstallationResult {
        logger.info("Setting up development environment for System Extensions")
        
        var errors: [InstallationError] = []
        var warnings: [String] = []
        var validationResults: [ValidationResult] = []
        
        // Check developer mode
        let developerModeResult = await getDeveloperModeGuidance()
        validationResults.append(developerModeResult)
        
        if !developerModeResult.passed {
            do {
                try await enableDeveloperMode()
                warnings.append("Developer mode was enabled automatically")
            } catch {
                errors.append(.developerModeRequired("Failed to enable developer mode"))
            }
        }
        
        // Check SIP status
        let sipResult = await checkSIPStatus()
        validationResults.append(sipResult)
        
        // Check Xcode Command Line Tools
        let xcodeCLTResult = await checkXcodeCommandLineTools()
        validationResults.append(xcodeCLTResult)
        
        if !xcodeCLTResult.passed {
            warnings.append("Xcode Command Line Tools may be required for development")
        }
        
        // Check code signing certificates
        let certificatesResult = await checkDevelopmentCertificates()
        validationResults.append(certificatesResult)
        
        if !certificatesResult.passed {
            warnings.append("No valid development certificates found - unsigned development mode will be used")
        }
        
        return InstallationResult(
            success: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            installationMethod: .development,
            validationResults: validationResults
        )
    }
    
    private func checkXcodeCommandLineTools() async -> ValidationResult {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
            process.arguments = ["-p"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            let isInstalled = process.terminationStatus == 0 && !output.isEmpty
            
            return ValidationResult(
                checkID: "xcode_clt",
                checkName: "Xcode Command Line Tools",
                passed: isInstalled,
                message: isInstalled ? "Xcode Command Line Tools are installed" : "Xcode Command Line Tools not found",
                severity: isInstalled ? .info : .warning,
                recommendedActions: isInstalled ? [] : [
                    "Install Xcode Command Line Tools: xcode-select --install",
                    "Install full Xcode from App Store for complete development environment"
                ]
            )
        } catch {
            return ValidationResult(
                checkID: "xcode_clt",
                checkName: "Xcode Command Line Tools",
                passed: false,
                message: "Failed to check Xcode Command Line Tools: \(error.localizedDescription)",
                severity: .warning,
                recommendedActions: ["Install Xcode Command Line Tools: xcode-select --install"]
            )
        }
    }
    
    private func checkDevelopmentCertificates() async -> ValidationResult {
        // This would normally integrate with CodeSigningManager
        // For now, provide a basic check
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-identity", "-v", "-p", "codesigning"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            let hasDevelopmentCerts = output.contains("Apple Development") || 
                                    output.contains("Mac Developer") ||
                                    output.contains("Apple Distribution")
            
            return ValidationResult(
                checkID: "development_certificates",
                checkName: "Development Certificates",
                passed: hasDevelopmentCerts,
                message: hasDevelopmentCerts ? "Development certificates available" : "No development certificates found",
                severity: hasDevelopmentCerts ? .info : .warning,
                recommendedActions: hasDevelopmentCerts ? [] : [
                    "Install Apple Development certificate from Apple Developer Portal",
                    "Sign in to Xcode with Apple ID to automatically manage certificates",
                    "Use unsigned development mode if certificates unavailable"
                ]
            )
        } catch {
            return ValidationResult(
                checkID: "development_certificates",
                checkName: "Development Certificates",
                passed: false,
                message: "Failed to check development certificates: \(error.localizedDescription)",
                severity: .warning,
                recommendedActions: ["Check keychain access permissions"]
            )
        }
    }
    
    // MARK: - Installation Completion
    
    private func completeInstallation(
        success: Bool,
        bundle: SystemExtensionBundle?,
        errors: [InstallationError],
        warnings: [String]
    ) {
        guard let completion = currentCompletion else { return }
        
        let installationTime = installationStartTime.map { Date().timeIntervalSince($0) } ?? 0.0
        let result = InstallationResult(
            success: success,
            installedBundle: success ? bundle : nil,
            errors: errors,
            warnings: warnings,
            installationTime: installationTime,
            installationMethod: errors.contains { error in
                if case .codeSigningFailed = error { return true }
                return false
            } ? .development : .automatic
        )
        
        installationStatus = success ? .installed : .installationFailed
        currentCompletion = nil
        currentRequest = nil
        installationStartTime = nil
        
        logger.info("Installation completed", context: [
            "success": success,
            "installationTime": installationTime,
            "errors": errors.count,
            "warnings": warnings.count
        ])
        
        completion(result)
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension SystemExtensionInstaller: OSSystemExtensionRequestDelegate {
    
    public func request(_ request: OSSystemExtensionRequest,
                       actionForReplacingExtension existing: OSSystemExtensionProperties,
                       withExtension extension: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        
        logger.info("System Extension replacement requested", context: [
            "existing": existing.bundleIdentifier,
            "new": `extension`.bundleIdentifier,
            "existingVersion": existing.bundleVersion,
            "newVersion": `extension`.bundleVersion
        ])
        
        return .replace
    }
    
    public func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.info("System Extension requires user approval")
        installationStatus = .pendingApproval
        
        // Monitor for approval completion
        monitorInstallationStatus { [weak self] status in
            if status == .installed {
                self?.completeInstallation(
                    success: true,
                    bundle: nil,
                    errors: [],
                    warnings: ["User approval was required"]
                )
            }
        }
    }
    
    public func request(_ request: OSSystemExtensionRequest,
                       didFinishWithResult result: OSSystemExtensionRequest.Result) {
        
        switch result {
        case .completed:
            logger.info("System Extension installation completed successfully")
            completeInstallation(
                success: true,
                bundle: nil,
                errors: [],
                warnings: []
            )
            
        case .willCompleteAfterReboot:
            logger.info("System Extension installation will complete after reboot")
            completeInstallation(
                success: true,
                bundle: nil,
                errors: [],
                warnings: ["Reboot required to complete installation"]
            )
            
        @unknown default:
            logger.warning("Unknown System Extension request result", context: ["result": String(describing: result)])
            completeInstallation(
                success: false,
                bundle: nil,
                errors: [.unknownError("Unknown result: \(result)")],
                warnings: []
            )
        }
    }
    
    public func request(_ request: OSSystemExtensionRequest,
                       didFailWithError error: Error) {
        
        logger.error("System Extension installation failed", context: ["error": error.localizedDescription])
        
        let installationError: InstallationError
        
        if let osError = error as? OSSystemExtensionError {
            switch osError.code {
            case .authorizationRequired:
                installationError = .userApprovalFailed("Authorization required")
            case .unsupportedParentBundleLocation:
                installationError = .bundleValidationFailed(["Unsupported parent bundle location"])
            case .extensionMissingIdentifier:
                installationError = .invalidBundleIdentifier("Extension missing identifier")
            case .duplicateExtensionIdentifer:
                installationError = .bundleAlreadyExists("Extension with same identifier already exists")
            case .missingEntitlement:
                installationError = .certificateValidationFailed("Missing required entitlements")
            case .extensionNotFound:
                installationError = .bundleValidationFailed(["Extension bundle not found"])
            case .codeSignatureInvalid:
                installationError = .codeSigningFailed("Invalid code signature")
            case .validationFailed:
                installationError = .bundleValidationFailed(["Extension validation failed"])
            case .forbiddenBySystemPolicy:
                installationError = .sipBlocked("Forbidden by system policy")
            case .requestCanceled:
                installationError = .userApprovalFailed("Request was canceled")
            default:
                installationError = .unknownError(osError.localizedDescription)
            }
        } else {
            installationError = .unknownError(error.localizedDescription)
        }
        
        completeInstallation(
            success: false,
            bundle: nil,
            errors: [installationError],
            warnings: []
        )
    }
}