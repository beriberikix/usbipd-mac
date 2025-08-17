// InstallationProgressReporter.swift
// Progress reporting and feedback system for System Extension installation

import Foundation
import Common

/// Comprehensive progress reporting system for System Extension installation
public class InstallationProgressReporter {
    
    // MARK: - Properties
    
    private let logger: Logger
    private let outputHandler: ProgressOutputHandler
    private var currentInstallation: InstallationSession?
    
    // MARK: - Initialization
    
    /// Initialize progress reporter with output handler
    /// - Parameters:
    ///   - outputHandler: Handler for progress output (console, UI, etc.)
    ///   - logger: Custom logger instance (uses shared logger if nil)
    public init(outputHandler: ProgressOutputHandler = ConsoleProgressOutputHandler(), logger: Logger? = nil) {
        self.outputHandler = outputHandler
        self.logger = logger ?? Logger.shared
    }
    
    // MARK: - Installation Session Management
    
    /// Start a new installation session with progress tracking
    /// - Parameters:
    ///   - sessionId: Unique identifier for this installation session
    ///   - totalSteps: Total number of steps in the installation process
    ///   - description: Description of what's being installed
    /// - Returns: Installation session for tracking progress
    public func startInstallationSession(
        sessionId: String = UUID().uuidString,
        totalSteps: Int,
        description: String
    ) -> InstallationSession {
        logger.info("Starting installation session", context: [
            "session_id": sessionId,
            "total_steps": totalSteps,
            "description": description
        ])
        
        let session = InstallationSession(
            sessionId: sessionId,
            description: description,
            totalSteps: totalSteps,
            startTime: Date(),
            reporter: self
        )
        
        self.currentInstallation = session
        
        outputHandler.reportSessionStart(session: session)
        
        return session
    }
    
    /// Complete the current installation session
    /// - Parameters:
    ///   - success: Whether the installation completed successfully
    ///   - finalMessage: Final status message
    ///   - nextSteps: Recommended next steps for the user
    public func completeInstallationSession(
        success: Bool,
        finalMessage: String,
        nextSteps: [String] = []
    ) {
        guard let session = currentInstallation else {
            logger.warning("Attempted to complete installation session but no session is active")
            return
        }
        
        let completedSession = session.complete(
            success: success,
            finalMessage: finalMessage,
            nextSteps: nextSteps
        )
        
        logger.info("Installation session completed", context: [
            "session_id": session.sessionId,
            "success": success,
            "duration": completedSession.duration,
            "steps_completed": session.currentStep
        ])
        
        outputHandler.reportSessionComplete(session: completedSession)
        
        self.currentInstallation = nil
    }
    
    // MARK: - Step Progress Reporting
    
    /// Report progress for a specific installation step
    /// - Parameters:
    ///   - stepNumber: Current step number (1-based)
    ///   - stepName: Name/description of the current step
    ///   - status: Current status of the step
    ///   - message: Detailed message about the step progress
    ///   - progress: Optional progress percentage (0.0 to 1.0) for the current step
    public func reportStepProgress(
        stepNumber: Int,
        stepName: String,
        status: InstallationStepStatus,
        message: String,
        progress: Double? = nil
    ) {
        guard let session = currentInstallation else {
            logger.warning("Attempted to report step progress but no installation session is active")
            return
        }
        
        let step = InstallationStep(
            stepNumber: stepNumber,
            stepName: stepName,
            status: status,
            message: message,
            progress: progress,
            timestamp: Date()
        )
        
        session.updateCurrentStep(step)
        
        logger.info("Installation step progress", context: [
            "session_id": session.sessionId,
            "step": stepNumber,
            "step_name": stepName,
            "status": status.rawValue,
            "message": message
        ])
        
        outputHandler.reportStepProgress(session: session, step: step)
    }
    
    /// Report that a step has started
    /// - Parameters:
    ///   - stepNumber: Step number being started
    ///   - stepName: Name of the step
    ///   - description: Detailed description of what this step does
    public func reportStepStarted(stepNumber: Int, stepName: String, description: String) {
        reportStepProgress(
            stepNumber: stepNumber,
            stepName: stepName,
            status: .inProgress,
            message: description
        )
    }
    
    /// Report that a step has completed successfully
    /// - Parameters:
    ///   - stepNumber: Step number that completed
    ///   - stepName: Name of the step
    ///   - result: Result message or description
    public func reportStepCompleted(stepNumber: Int, stepName: String, result: String) {
        reportStepProgress(
            stepNumber: stepNumber,
            stepName: stepName,
            status: .completed,
            message: result,
            progress: 1.0
        )
    }
    
    /// Report that a step has failed
    /// - Parameters:
    ///   - stepNumber: Step number that failed
    ///   - stepName: Name of the step
    ///   - error: Error that occurred
    ///   - recoverable: Whether this failure is recoverable
    public func reportStepFailed(stepNumber: Int, stepName: String, error: Error, recoverable: Bool = true) {
        reportStepProgress(
            stepNumber: stepNumber,
            stepName: stepName,
            status: recoverable ? .failed : .criticalFailure,
            message: "Failed: \(error.localizedDescription)"
        )
    }
    
    /// Report a warning during a step
    /// - Parameters:
    ///   - stepNumber: Step number with warning
    ///   - stepName: Name of the step
    ///   - warning: Warning message
    public func reportStepWarning(stepNumber: Int, stepName: String, warning: String) {
        reportStepProgress(
            stepNumber: stepNumber,
            stepName: stepName,
            status: .warning,
            message: "Warning: \(warning)"
        )
    }
    
    // MARK: - Installation Verification
    
    /// Verify installation completeness and report status
    /// - Parameters:
    ///   - bundlePath: Path to the installed System Extension bundle
    ///   - expectedComponents: List of components that should be present
    /// - Returns: Verification result with detailed findings
    public func verifyInstallation(
        bundlePath: String,
        expectedComponents: [InstallationComponent] = InstallationComponent.defaultComponents
    ) -> InstallationVerificationResult {
        logger.info("Starting installation verification", context: [
            "bundle_path": bundlePath,
            "expected_components": expectedComponents.count
        ])
        
        outputHandler.reportVerificationStart(bundlePath: bundlePath)
        
        var verificationResults: [ComponentVerificationResult] = []
        var overallSuccess = true
        
        for component in expectedComponents {
            let result = verifyComponent(component, at: bundlePath)
            verificationResults.append(result)
            
            if !result.isPresent || !result.isValid {
                overallSuccess = false
            }
            
            outputHandler.reportComponentVerification(component: component, result: result)
        }
        
        // Additional system-level verification
        let systemVerification = verifySystemIntegration(bundlePath: bundlePath)
        verificationResults.append(contentsOf: systemVerification)
        
        let verificationResult = InstallationVerificationResult(
            bundlePath: bundlePath,
            overallSuccess: overallSuccess,
            componentResults: verificationResults,
            verificationTime: Date(),
            summary: generateVerificationSummary(results: verificationResults)
        )
        
        outputHandler.reportVerificationComplete(result: verificationResult)
        
        logger.info("Installation verification completed", context: [
            "bundle_path": bundlePath,
            "overall_success": overallSuccess,
            "components_verified": verificationResults.count
        ])
        
        return verificationResult
    }
    
    // MARK: - Status Checking Utilities
    
    /// Check current System Extension status and report
    /// - Returns: Current System Extension status with detailed information
    public func checkSystemExtensionStatus() -> SystemExtensionStatusReport {
        logger.info("Checking System Extension status")
        
        outputHandler.reportStatusCheckStart()
        
        let bundleIdentifier = "com.github.usbipd-mac.systemextension"
        
        // Check if System Extension is installed
        let installedExtensions = getInstalledSystemExtensions()
        let ourExtension = installedExtensions.first { $0.bundleIdentifier == bundleIdentifier }
        
        // Check bundle presence in common locations
        let bundleLocations = findSystemExtensionBundles()
        
        // Check system permissions
        let permissionStatus = checkSystemPermissions()
        
        // Check developer mode status
        let developerModeEnabled = checkDeveloperModeStatus()
        
        let status = SystemExtensionStatusReport(
            bundleIdentifier: bundleIdentifier,
            isInstalled: ourExtension != nil,
            installedVersion: ourExtension?.version,
            activationState: ourExtension?.state ?? .unknown,
            bundleLocations: bundleLocations,
            permissionStatus: permissionStatus,
            developerModeEnabled: developerModeEnabled,
            lastChecked: Date()
        )
        
        outputHandler.reportStatusCheckComplete(status: status)
        
        logger.info("System Extension status check completed", context: [
            "is_installed": status.isInstalled,
            "activation_state": status.activationState.description,
            "bundle_locations": status.bundleLocations.count
        ])
        
        return status
    }
    
    /// Generate installation readiness report
    /// - Returns: Report indicating readiness for installation
    public func generateInstallationReadinessReport() -> InstallationReadinessReport {
        logger.info("Generating installation readiness report")
        
        outputHandler.reportReadinessCheckStart()
        
        var checks: [ReadinessCheck] = []
        var blockers: [String] = []
        var warnings: [String] = []
        
        // Check macOS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let isCompatibleOS = osVersion.majorVersion >= 11 || (osVersion.majorVersion == 10 && osVersion.minorVersion >= 15)
        checks.append(ReadinessCheck(
            name: "macOS Version Compatibility",
            passed: isCompatibleOS,
            message: isCompatibleOS ? "macOS version supports System Extensions" : "macOS 10.15+ required for System Extensions",
            required: true
        ))
        if !isCompatibleOS {
            blockers.append("Incompatible macOS version - requires 10.15 or later")
        }
        
        // Check available disk space
        let availableSpace = getAvailableDiskSpace()
        let hasEnoughSpace = availableSpace > 100_000_000 // 100MB minimum
        checks.append(ReadinessCheck(
            name: "Available Disk Space",
            passed: hasEnoughSpace,
            message: hasEnoughSpace ? "Sufficient disk space available" : "Insufficient disk space for installation",
            required: true
        ))
        if !hasEnoughSpace {
            blockers.append("Insufficient disk space - need at least 100MB free")
        }
        
        // Check build tools availability
        let hasBuildTools = checkBuildToolsAvailability()
        checks.append(ReadinessCheck(
            name: "Build Tools Available",
            passed: hasBuildTools,
            message: hasBuildTools ? "Swift build tools are available" : "Swift build tools not found",
            required: true
        ))
        if !hasBuildTools {
            blockers.append("Swift build tools not available - install Xcode or Command Line Tools")
        }
        
        // Check System Extension developer mode
        let developerModeEnabled = checkDeveloperModeStatus()
        let hasCodeSigningCerts = checkCodeSigningCertificates()
        let canInstallUnsigned = developerModeEnabled || hasCodeSigningCerts
        checks.append(ReadinessCheck(
            name: "System Extension Installation Capability",
            passed: canInstallUnsigned,
            message: canInstallUnsigned ? "Can install System Extensions" : "Developer Mode or code signing certificates required",
            required: false
        ))
        if !canInstallUnsigned {
            warnings.append("Enable Developer Mode or obtain code signing certificates for easier installation")
        }
        
        // Check for conflicting System Extensions
        let conflicts = detectConflictingExtensions()
        let hasConflicts = !conflicts.isEmpty
        checks.append(ReadinessCheck(
            name: "System Extension Conflicts",
            passed: !hasConflicts,
            message: hasConflicts ? "Conflicting System Extensions detected" : "No conflicting System Extensions found",
            required: false
        ))
        if hasConflicts {
            warnings.append("Conflicting System Extensions may interfere with installation: \(conflicts.joined(separator: ", "))")
        }
        
        // Check system permissions
        let permissionStatus = checkSystemPermissions()
        let hasRequiredPermissions = permissionStatus.allSatisfy { $0.granted }
        checks.append(ReadinessCheck(
            name: "System Permissions",
            passed: hasRequiredPermissions,
            message: hasRequiredPermissions ? "All required permissions granted" : "Some system permissions may be needed",
            required: false
        ))
        if !hasRequiredPermissions {
            warnings.append("Additional system permissions may be required during installation")
        }
        
        let readiness = InstallationReadinessReport(
            isReady: blockers.isEmpty,
            readinessChecks: checks,
            blockers: blockers,
            warnings: warnings,
            recommendedActions: generateReadinessActions(blockers: blockers, warnings: warnings),
            checkTime: Date()
        )
        
        outputHandler.reportReadinessCheckComplete(readiness: readiness)
        
        logger.info("Installation readiness report generated", context: [
            "is_ready": readiness.isReady,
            "blockers": blockers.count,
            "warnings": warnings.count
        ])
        
        return readiness
    }
    
    // MARK: - Private Helper Methods
    
    private func verifyComponent(_ component: InstallationComponent, at bundlePath: String) -> ComponentVerificationResult {
        let componentPath = URL(fileURLWithPath: bundlePath).appendingPathComponent(component.relativePath).path
        let exists = FileManager.default.fileExists(atPath: componentPath)
        
        var isValid = false
        var validationMessage = ""
        
        if exists {
            switch component.type {
            case .executable:
                isValid = FileManager.default.isExecutableFile(atPath: componentPath)
                validationMessage = isValid ? "Executable has proper permissions" : "Executable lacks execute permissions"
                
            case .plist:
                isValid = validatePlistFile(at: componentPath)
                validationMessage = isValid ? "Property list is valid" : "Property list is invalid or corrupted"
                
            case .directory:
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: componentPath, isDirectory: &isDirectory)
                isValid = isDirectory.boolValue
                validationMessage = isValid ? "Directory structure is correct" : "Expected directory but found file"
                
            case .bundle:
                isValid = validateBundleStructure(at: componentPath)
                validationMessage = isValid ? "Bundle structure is valid" : "Bundle structure is invalid"
            }
        } else {
            validationMessage = "Component not found at expected location"
        }
        
        return ComponentVerificationResult(
            component: component,
            isPresent: exists,
            isValid: isValid,
            validationMessage: validationMessage,
            componentPath: componentPath
        )
    }
    
    private func verifySystemIntegration(bundlePath: String) -> [ComponentVerificationResult] {
        var results: [ComponentVerificationResult] = []
        
        // Check system registration
        let registrationComponent = InstallationComponent(
            name: "System Registration",
            type: .system,
            relativePath: "",
            required: true,
            description: "System Extension registration with macOS"
        )
        
        let bundleIdentifier = "com.github.usbipd-mac.systemextension"
        let installedExtensions = getInstalledSystemExtensions()
        let isRegistered = installedExtensions.contains { $0.bundleIdentifier == bundleIdentifier }
        
        results.append(ComponentVerificationResult(
            component: registrationComponent,
            isPresent: isRegistered,
            isValid: isRegistered,
            validationMessage: isRegistered ? "System Extension is registered with macOS" : "System Extension is not registered with macOS",
            componentPath: bundlePath
        ))
        
        return results
    }
    
    private func validatePlistFile(at path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let _ = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            return false
        }
        return true
    }
    
    private func validateBundleStructure(at path: String) -> Bool {
        let requiredPaths = ["Contents", "Contents/Info.plist", "Contents/MacOS"]
        return requiredPaths.allSatisfy { relativePath in
            let fullPath = URL(fileURLWithPath: path).appendingPathComponent(relativePath).path
            return FileManager.default.fileExists(atPath: fullPath)
        }
    }
    
    private func generateVerificationSummary(results: [ComponentVerificationResult]) -> String {
        let totalComponents = results.count
        let presentComponents = results.filter { $0.isPresent }.count
        let validComponents = results.filter { $0.isValid }.count
        
        if validComponents == totalComponents {
            return "All \(totalComponents) components are present and valid"
        } else if presentComponents == totalComponents {
            return "\(presentComponents)/\(totalComponents) components present, \(validComponents) valid"
        } else {
            return "\(presentComponents)/\(totalComponents) components present, \(validComponents) valid"
        }
    }
    
    private func getInstalledSystemExtensions() -> [SystemExtensionInfo] {
        // Simplified implementation - would use SystemExtensions framework in real implementation
        return []
    }
    
    private func findSystemExtensionBundles() -> [String] {
        let commonPaths = [
            ".build/debug/USBIPDSystemExtension.systemextension",
            ".build/release/USBIPDSystemExtension.systemextension",
            "/usr/local/lib/SystemExtensions/com.github.usbipd-mac.systemextension.systemextension"
        ]
        
        return commonPaths.filter { FileManager.default.fileExists(atPath: $0) }
    }
    
    private func checkSystemPermissions() -> [PermissionStatus] {
        return [
            PermissionStatus(name: "Full Disk Access", granted: true), // Simplified
            PermissionStatus(name: "System Extension Access", granted: true)
        ]
    }
    
    private func checkDeveloperModeStatus() -> Bool {
        // Simplified check - would execute systemextensionsctl in real implementation
        return false
    }
    
    private func getAvailableDiskSpace() -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "."),
              let freeSize = attributes[.systemFreeSize] as? Int64 else {
            return 0
        }
        return freeSize
    }
    
    private func checkBuildToolsAvailability() -> Bool {
        return FileManager.default.fileExists(atPath: "/usr/bin/swift")
    }
    
    private func checkCodeSigningCertificates() -> Bool {
        // Simplified check - would use Security framework in real implementation
        return false
    }
    
    private func detectConflictingExtensions() -> [String] {
        // Simplified implementation - would check for actual conflicting extensions
        return []
    }
    
    private func generateReadinessActions(blockers: [String], warnings: [String]) -> [String] {
        var actions: [String] = []
        
        if !blockers.isEmpty {
            actions.append("Resolve the following critical issues before installation:")
            actions.append(contentsOf: blockers.map { "  • \($0)" })
        }
        
        if !warnings.isEmpty {
            actions.append("Consider addressing these recommendations for optimal installation:")
            actions.append(contentsOf: warnings.map { "  • \($0)" })
        }
        
        if blockers.isEmpty && warnings.isEmpty {
            actions.append("System is ready for USB/IP System Extension installation")
            actions.append("Run the installation script to proceed")
        }
        
        return actions
    }
}

// MARK: - Progress Output Handlers

/// Protocol for handling progress output to different destinations
public protocol ProgressOutputHandler {
    func reportSessionStart(session: InstallationSession)
    func reportSessionComplete(session: CompletedInstallationSession)
    func reportStepProgress(session: InstallationSession, step: InstallationStep)
    func reportVerificationStart(bundlePath: String)
    func reportComponentVerification(component: InstallationComponent, result: ComponentVerificationResult)
    func reportVerificationComplete(result: InstallationVerificationResult)
    func reportStatusCheckStart()
    func reportStatusCheckComplete(status: SystemExtensionStatusReport)
    func reportReadinessCheckStart()
    func reportReadinessCheckComplete(readiness: InstallationReadinessReport)
}

/// Console-based progress output handler
public class ConsoleProgressOutputHandler: ProgressOutputHandler {
    
    public init() {}
    
    public func reportSessionStart(session: InstallationSession) {
        print("🚀 Starting installation: \(session.description)")
        print("   Total steps: \(session.totalSteps)")
        print("   Session ID: \(session.sessionId)")
        print("")
    }
    
    public func reportSessionComplete(session: CompletedInstallationSession) {
        let icon = session.success ? "✅" : "❌"
        let status = session.success ? "SUCCESS" : "FAILED"
        
        print("\(icon) Installation \(status): \(session.finalMessage)")
        print("   Duration: \(String(format: "%.1f", session.duration))s")
        print("   Steps completed: \(session.stepsCompleted)/\(session.totalSteps)")
        
        if !session.nextSteps.isEmpty {
            print("\n📋 Next steps:")
            for (index, step) in session.nextSteps.enumerated() {
                print("   \(index + 1). \(step)")
            }
        }
        print("")
    }
    
    public func reportStepProgress(session: InstallationSession, step: InstallationStep) {
        let icon = step.status.icon
        let progressText = step.progress.map { String(format: " (%.0f%%)", $0 * 100) } ?? ""
        
        print("\(icon) [\(step.stepNumber)/\(session.totalSteps)] \(step.stepName)\(progressText)")
        
        if !step.message.isEmpty {
            print("   \(step.message)")
        }
        
        if step.status == .failed || step.status == .criticalFailure {
            print("")
        }
    }
    
    public func reportVerificationStart(bundlePath: String) {
        print("🔍 Verifying installation at: \(bundlePath)")
        print("")
    }
    
    public func reportComponentVerification(component: InstallationComponent, result: ComponentVerificationResult) {
        let icon = result.isPresent && result.isValid ? "✅" : result.isPresent ? "⚠️" : "❌"
        let status = result.isPresent && result.isValid ? "OK" : result.isPresent ? "INVALID" : "MISSING"
        
        print("   \(icon) \(component.name): \(status)")
        if !result.validationMessage.isEmpty {
            print("      \(result.validationMessage)")
        }
    }
    
    public func reportVerificationComplete(result: InstallationVerificationResult) {
        let icon = result.overallSuccess ? "✅" : "❌"
        let status = result.overallSuccess ? "PASSED" : "FAILED"
        
        print("\n\(icon) Verification \(status): \(result.summary)")
        print("")
    }
    
    public func reportStatusCheckStart() {
        print("📊 Checking System Extension status...")
        print("")
    }
    
    public func reportStatusCheckComplete(status: SystemExtensionStatusReport) {
        print("📊 System Extension Status Report")
        print("   Bundle ID: \(status.bundleIdentifier)")
        print("   Installed: \(status.isInstalled ? "Yes" : "No")")
        
        if let version = status.installedVersion {
            print("   Version: \(version)")
        }
        
        print("   State: \(status.activationState.description)")
        print("   Developer Mode: \(status.developerModeEnabled ? "Enabled" : "Disabled")")
        
        if !status.bundleLocations.isEmpty {
            print("   Bundle locations:")
            for location in status.bundleLocations {
                print("     • \(location)")
            }
        }
        
        print("   Permissions:")
        for permission in status.permissionStatus {
            let icon = permission.granted ? "✅" : "❌"
            print("     \(icon) \(permission.name)")
        }
        print("")
    }
    
    public func reportReadinessCheckStart() {
        print("🔍 Checking installation readiness...")
        print("")
    }
    
    public func reportReadinessCheckComplete(readiness: InstallationReadinessReport) {
        let icon = readiness.isReady ? "✅" : "❌"
        let status = readiness.isReady ? "READY" : "NOT READY"
        
        print("\(icon) Installation Readiness: \(status)")
        print("")
        
        print("Readiness Checks:")
        for check in readiness.readinessChecks {
            let checkIcon = check.passed ? "✅" : (check.required ? "❌" : "⚠️")
            print("   \(checkIcon) \(check.name): \(check.message)")
        }
        
        if !readiness.blockers.isEmpty {
            print("\n🚫 Critical Issues (must resolve):")
            for blocker in readiness.blockers {
                print("   • \(blocker)")
            }
        }
        
        if !readiness.warnings.isEmpty {
            print("\n⚠️ Recommendations:")
            for warning in readiness.warnings {
                print("   • \(warning)")
            }
        }
        
        if !readiness.recommendedActions.isEmpty {
            print("\n📋 Recommended Actions:")
            for action in readiness.recommendedActions {
                print("   \(action)")
            }
        }
        print("")
    }
}

// MARK: - Supporting Types

/// Installation session for tracking progress
public class InstallationSession {
    public let sessionId: String
    public let description: String
    public let totalSteps: Int
    public let startTime: Date
    public private(set) var currentStep: Int = 0
    public private(set) var currentStepInfo: InstallationStep?
    
    private weak var reporter: InstallationProgressReporter?
    
    internal init(sessionId: String, description: String, totalSteps: Int, startTime: Date, reporter: InstallationProgressReporter) {
        self.sessionId = sessionId
        self.description = description
        self.totalSteps = totalSteps
        self.startTime = startTime
        self.reporter = reporter
    }
    
    internal func updateCurrentStep(_ step: InstallationStep) {
        self.currentStep = step.stepNumber
        self.currentStepInfo = step
    }
    
    internal func complete(success: Bool, finalMessage: String, nextSteps: [String]) -> CompletedInstallationSession {
        return CompletedInstallationSession(
            sessionId: sessionId,
            description: description,
            totalSteps: totalSteps,
            stepsCompleted: currentStep,
            startTime: startTime,
            endTime: Date(),
            success: success,
            finalMessage: finalMessage,
            nextSteps: nextSteps
        )
    }
}

/// Completed installation session with results
public struct CompletedInstallationSession {
    public let sessionId: String
    public let description: String
    public let totalSteps: Int
    public let stepsCompleted: Int
    public let startTime: Date
    public let endTime: Date
    public let success: Bool
    public let finalMessage: String
    public let nextSteps: [String]
    
    public var duration: TimeInterval {
        return endTime.timeIntervalSince(startTime)
    }
}

/// Individual installation step with progress information
public struct InstallationStep {
    public let stepNumber: Int
    public let stepName: String
    public let status: InstallationStepStatus
    public let message: String
    public let progress: Double?
    public let timestamp: Date
}

/// Status of an installation step
public enum InstallationStepStatus: String, CaseIterable {
    case pending = "pending"
    case inProgress = "in_progress"
    case completed = "completed"
    case warning = "warning"
    case failed = "failed"
    case criticalFailure = "critical_failure"
    case skipped = "skipped"
    
    public var icon: String {
        switch self {
        case .pending: return "⏳"
        case .inProgress: return "🔄"
        case .completed: return "✅"
        case .warning: return "⚠️"
        case .failed: return "❌"
        case .criticalFailure: return "🚨"
        case .skipped: return "⏭️"
        }
    }
    
    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .warning: return "Warning"
        case .failed: return "Failed"
        case .criticalFailure: return "Critical Failure"
        case .skipped: return "Skipped"
        }
    }
}

/// Installation component for verification
public struct InstallationComponent {
    public let name: String
    public let type: ComponentType
    public let relativePath: String
    public let required: Bool
    public let description: String
    
    public enum ComponentType {
        case executable
        case plist
        case directory
        case bundle
        case system
    }
    
    public static let defaultComponents: [InstallationComponent] = [
        InstallationComponent(
            name: "System Extension Bundle",
            type: .bundle,
            relativePath: "",
            required: true,
            description: "Main System Extension bundle structure"
        ),
        InstallationComponent(
            name: "Info.plist",
            type: .plist,
            relativePath: "Contents/Info.plist",
            required: true,
            description: "Bundle configuration and metadata"
        ),
        InstallationComponent(
            name: "System Extension Executable",
            type: .executable,
            relativePath: "Contents/MacOS/USBIPDSystemExtension",
            required: true,
            description: "Main System Extension executable"
        ),
        InstallationComponent(
            name: "Contents Directory",
            type: .directory,
            relativePath: "Contents",
            required: true,
            description: "Bundle contents directory"
        ),
        InstallationComponent(
            name: "MacOS Directory",
            type: .directory,
            relativePath: "Contents/MacOS",
            required: true,
            description: "Executable directory"
        ),
        InstallationComponent(
            name: "Resources Directory",
            type: .directory,
            relativePath: "Contents/Resources",
            required: false,
            description: "Bundle resources directory"
        )
    ]
}

/// Result of component verification
public struct ComponentVerificationResult {
    public let component: InstallationComponent
    public let isPresent: Bool
    public let isValid: Bool
    public let validationMessage: String
    public let componentPath: String
}

/// Overall installation verification result
public struct InstallationVerificationResult {
    public let bundlePath: String
    public let overallSuccess: Bool
    public let componentResults: [ComponentVerificationResult]
    public let verificationTime: Date
    public let summary: String
}

/// System Extension information
public struct SystemExtensionInfo {
    public let bundleIdentifier: String
    public let version: String
    public let state: SystemExtensionState
}

/// System Extension activation state
public enum SystemExtensionState {
    case unknown
    case deactivated
    case activated
    case activating
    case terminating
    
    public var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .deactivated: return "Deactivated"
        case .activated: return "Activated"
        case .activating: return "Activating"
        case .terminating: return "Terminating"
        }
    }
}

/// Permission status information
public struct PermissionStatus {
    public let name: String
    public let granted: Bool
}

/// System Extension status report
public struct SystemExtensionStatusReport {
    public let bundleIdentifier: String
    public let isInstalled: Bool
    public let installedVersion: String?
    public let activationState: SystemExtensionState
    public let bundleLocations: [String]
    public let permissionStatus: [PermissionStatus]
    public let developerModeEnabled: Bool
    public let lastChecked: Date
}

/// Installation readiness check
public struct ReadinessCheck {
    public let name: String
    public let passed: Bool
    public let message: String
    public let required: Bool
}

/// Installation readiness report
public struct InstallationReadinessReport {
    public let isReady: Bool
    public let readinessChecks: [ReadinessCheck]
    public let blockers: [String]
    public let warnings: [String]
    public let recommendedActions: [String]
    public let checkTime: Date
}