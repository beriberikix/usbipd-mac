// AutomaticInstallationManager.swift
// Coordinates transparent System Extension installation and management

import Foundation
import Common

/// Manager for automatic System Extension installation and lifecycle management
public class AutomaticInstallationManager {
    
    // MARK: - Types
    
    /// Installation attempt result
    public struct InstallationAttemptResult {
        /// Whether the attempt was successful
        public let success: Bool
        
        /// Installation status after attempt
        public let finalStatus: SystemExtensionInstallationStatus
        
        /// Errors encountered during installation
        public let errors: [InstallationError]
        
        /// Time taken for the attempt
        public let duration: TimeInterval
        
        /// Whether user approval is required
        public let requiresUserApproval: Bool
        
        /// Recommended next action
        public let recommendedAction: RecommendedAction
        
        public init(
            success: Bool,
            finalStatus: SystemExtensionInstallationStatus,
            errors: [InstallationError] = [],
            duration: TimeInterval,
            requiresUserApproval: Bool = false,
            recommendedAction: RecommendedAction = .none
        ) {
            self.success = success
            self.finalStatus = finalStatus
            self.errors = errors
            self.duration = duration
            self.requiresUserApproval = requiresUserApproval
            self.recommendedAction = recommendedAction
        }
    }
    
    /// Recommended actions after installation attempt
    public enum RecommendedAction {
        case none
        case retryLater
        case requiresUserApproval
        case checkConfiguration
        case contactSupport
    }
    
    /// Installation state tracking
    public enum InstallationState {
        case idle
        case detecting
        case installing
        case verifying
        case completed
        case failed
        case requiresApproval
        case retryWaiting
    }
    
    // MARK: - Properties
    
    /// Server configuration reference
    private let config: ServerConfig
    
    /// System Extension installer
    private let installer: SystemExtensionInstaller
    
    /// Bundle detector for locating System Extension bundles
    private let bundleDetector: SystemExtensionBundleDetector
    
    /// Logger instance
    private let logger: Logger
    
    /// Current installation state
    public private(set) var currentState: InstallationState = .idle
    
    /// Installation attempt history
    private var attemptHistory: [InstallationAttemptResult] = []
    
    /// Current attempt count
    private var currentAttemptCount = 0
    
    /// Last installation attempt time
    private var lastAttemptTime: Date?
    
    /// Installation completion handlers
    private var completionHandlers: [(InstallationAttemptResult) -> Void] = []
    
    /// Background installation queue
    private let installationQueue = DispatchQueue(
        label: "com.usbipd.mac.automatic-installation",
        qos: .background
    )
    
    // MARK: - Initialization
    
    /// Initialize with configuration and installer
    /// - Parameters:
    ///   - config: Server configuration
    ///   - installer: System Extension installer
    ///   - bundleDetector: Bundle detector (optional, creates default if nil)
    public init(
        config: ServerConfig,
        installer: SystemExtensionInstaller,
        bundleDetector: SystemExtensionBundleDetector? = nil
    ) {
        self.config = config
        self.installer = installer
        self.bundleDetector = bundleDetector ?? SystemExtensionBundleDetector()
        
        let loggerConfig = LoggerConfig(level: config.logLevel)
        self.logger = Logger(config: loggerConfig, subsystem: "com.usbipd.mac", category: "auto-install")
        
        logger.info("AutomaticInstallationManager initialized")
    }
    
    // MARK: - Public Interface
    
    /// Attempt automatic installation if conditions are met
    /// - Parameter completion: Completion handler called when attempt finishes
    public func attemptAutomaticInstallation(completion: @escaping (InstallationAttemptResult) -> Void) {
        logger.debug("Attempting automatic System Extension installation")
        
        // Check if auto-installation is enabled
        guard config.shouldAttemptAutoInstall() else {
            logger.info("Automatic installation is disabled")
            let result = InstallationAttemptResult(
                success: false,
                finalStatus: .unknown,
                errors: [.installationFailed("Automatic installation is disabled")],
                duration: 0,
                recommendedAction: .checkConfiguration
            )
            completion(result)
            return
        }
        
        // Check if we've exceeded maximum attempts
        guard currentAttemptCount < config.maxAutoInstallAttempts else {
            logger.warning("Maximum automatic installation attempts exceeded", context: [
                "attempts": currentAttemptCount,
                "maxAttempts": config.maxAutoInstallAttempts
            ])
            let result = InstallationAttemptResult(
                success: false,
                finalStatus: .installationFailed,
                errors: [.installationFailed("Maximum installation attempts exceeded")],
                duration: 0,
                recommendedAction: .contactSupport
            )
            completion(result)
            return
        }
        
        // Check retry delay
        if let lastAttempt = lastAttemptTime,
           Date().timeIntervalSince(lastAttempt) < config.autoInstallRetryDelay {
            let remainingDelay = config.autoInstallRetryDelay - Date().timeIntervalSince(lastAttempt)
            logger.debug("Installation retry delay not met", context: [
                "remainingDelay": remainingDelay
            ])
            let result = InstallationAttemptResult(
                success: false,
                finalStatus: .unknown,
                errors: [.installationFailed("Retry delay not met")],
                duration: 0,
                recommendedAction: .retryLater
            )
            completion(result)
            return
        }
        
        // Add completion handler
        completionHandlers.append(completion)
        
        // Perform installation on background queue
        installationQueue.async { [weak self] in
            self?.performInstallationAttempt()
        }
    }
    
    /// Get current installation status and history
    /// - Returns: Current status and attempt history
    public func getInstallationStatus() -> (state: InstallationState, history: [InstallationAttemptResult]) {
        return (currentState, attemptHistory)
    }
    
    /// Reset installation attempt counter (for manual retry)
    public func resetAttemptCounter() {
        logger.info("Resetting automatic installation attempt counter")
        currentAttemptCount = 0
        lastAttemptTime = nil
    }
    
    /// Check if System Extension is available for installation
    /// - Returns: True if bundle is detected and valid
    public func isSystemExtensionAvailable() -> Bool {
        let detectionResult = bundleDetector.detectBundle()
        return detectionResult.found
    }
    
    // MARK: - Private Implementation
    
    /// Perform the actual installation attempt
    private func performInstallationAttempt() {
        let startTime = Date()
        currentState = .detecting
        currentAttemptCount += 1
        lastAttemptTime = startTime
        
        logger.info("Starting automatic installation attempt", context: [
            "attemptNumber": currentAttemptCount,
            "maxAttempts": config.maxAutoInstallAttempts
        ])
        
        // Detect System Extension bundle
        currentState = .detecting
        let detectionResult = bundleDetector.detectBundle()
        
        guard detectionResult.found,
              let bundlePath = detectionResult.bundlePath,
              let bundleIdentifier = detectionResult.bundleIdentifier else {
            logger.warning("No System Extension bundle found for installation", context: [
                "issues": detectionResult.issues.joined(separator: ", ")
            ])
            
            let result = InstallationAttemptResult(
                success: false,
                finalStatus: .invalidBundle,
                errors: [.bundleValidationFailed(detectionResult.issues)],
                duration: Date().timeIntervalSince(startTime),
                recommendedAction: .checkConfiguration
            )
            
            finishInstallationAttempt(result: result)
            return
        }
        
        logger.debug("System Extension bundle detected", context: [
            "bundlePath": bundlePath,
            "bundleIdentifier": bundleIdentifier
        ])
        
        // Update server configuration with bundle information
        if let bundleConfig = SystemExtensionBundleConfig.from(detectionResult: detectionResult) {
            config.updateSystemExtensionBundleConfig(bundleConfig)
        }
        
        // Start installation
        currentState = .installing
        
        // Determine if this should be a regular install or force reinstall
        let shouldForceReinstall = attemptHistory.contains { result in
            result.finalStatus == .installationFailed && result.errors.contains { error in
                if case .bundleAlreadyExists = error { return true }
                return false
            }
        }
        
        let installationCompletion: (InstallationResult) -> Void = { [weak self] result in
            self?.handleInstallationResult(result, startTime: startTime, bundleIdentifier: bundleIdentifier)
        }
        
        if shouldForceReinstall {
            logger.info("Performing force reinstallation due to previous conflicts")
            installer.forceReinstallSystemExtension(
                bundleIdentifier: bundleIdentifier,
                executablePath: bundlePath,
                completion: installationCompletion
            )
        } else {
            installer.installSystemExtension(
                bundleIdentifier: bundleIdentifier,
                executablePath: bundlePath,
                completion: installationCompletion
            )
        }
    }
    
    /// Handle installation result from SystemExtensionInstaller
    private func handleInstallationResult(_ result: InstallationResult, startTime: Date, bundleIdentifier: String) {
        let duration = Date().timeIntervalSince(startTime)
        
        logger.info("Installation attempt completed", context: [
            "success": result.success,
            "duration": duration,
            "errors": result.errors.map { $0.localizedDescription }.joined(separator: ", ")
        ])
        
        currentState = .verifying
        
        // Determine final status and recommended action
        var finalStatus: SystemExtensionInstallationStatus = .unknown
        var requiresUserApproval = false
        var recommendedAction: RecommendedAction = .none
        
        if result.success {
            finalStatus = .installed
            currentState = .completed
            recommendedAction = .none
        } else {
            // Analyze errors to determine status and recommendations
            let hasApprovalError = result.errors.contains { error in
                switch error {
                case .requiresApproval, .userApprovalRequired, .userApprovalFailed:
                    return true
                default:
                    return false
                }
            }
            
            if hasApprovalError {
                finalStatus = .pendingApproval
                currentState = .requiresApproval
                requiresUserApproval = true
                recommendedAction = .requiresUserApproval
            } else {
                finalStatus = .installationFailed
                currentState = .failed
                
                // Determine recommendation based on error types
                let hasDeveloperModeError = result.errors.contains { error in
                    if case .developerModeRequired = error { return true }
                    if case .developmentModeDisabled = error { return true }
                    return false
                }
                
                let hasPermissionError = result.errors.contains { error in
                    if case .insufficientPermissions = error { return true }
                    return false
                }
                
                if hasDeveloperModeError || hasPermissionError {
                    recommendedAction = .checkConfiguration
                } else if currentAttemptCount < config.maxAutoInstallAttempts {
                    recommendedAction = .retryLater
                    currentState = .retryWaiting
                } else {
                    recommendedAction = .contactSupport
                }
            }
        }
        
        // Create attempt result
        let attemptResult = InstallationAttemptResult(
            success: result.success,
            finalStatus: finalStatus,
            errors: result.errors,
            duration: duration,
            requiresUserApproval: requiresUserApproval,
            recommendedAction: recommendedAction
        )
        
        finishInstallationAttempt(result: attemptResult)
    }
    
    /// Finish installation attempt and notify handlers
    private func finishInstallationAttempt(result: InstallationAttemptResult) {
        // Add to history
        attemptHistory.append(result)
        
        // Update state
        if result.success {
            currentState = .completed
        } else if result.requiresUserApproval {
            currentState = .requiresApproval
        } else if result.recommendedAction == .retryLater {
            currentState = .retryWaiting
        } else {
            currentState = .failed
        }
        
        logger.info("Installation attempt finished", context: [
            "finalState": String(describing: currentState),
            "success": result.success,
            "recommendedAction": String(describing: result.recommendedAction)
        ])
        
        // Notify completion handlers
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            for handler in self.completionHandlers {
                handler(result)
            }
            self.completionHandlers.removeAll()
        }
    }
}

// MARK: - Installation State Extensions

extension AutomaticInstallationManager.InstallationState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle: return "idle"
        case .detecting: return "detecting"
        case .installing: return "installing"
        case .verifying: return "verifying"
        case .completed: return "completed"
        case .failed: return "failed"
        case .requiresApproval: return "requiresApproval"
        case .retryWaiting: return "retryWaiting"
        }
    }
}

extension AutomaticInstallationManager.RecommendedAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .none: return "none"
        case .retryLater: return "retryLater"
        case .requiresUserApproval: return "requiresUserApproval"
        case .checkConfiguration: return "checkConfiguration"
        case .contactSupport: return "contactSupport"
        }
    }
}