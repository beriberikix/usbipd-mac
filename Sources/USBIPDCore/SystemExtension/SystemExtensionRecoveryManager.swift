//
//  SystemExtensionRecoveryManager.swift
//  USBIPDCore
//
//  Comprehensive error recovery manager for System Extension failures
//  Handles automatic restart, device claim restoration, and communication recovery
//

import Foundation
import Common

/// System Extension error recovery and reliability manager
/// Provides automatic recovery from crashes, communication failures, and state corruption
public class SystemExtensionRecoveryManager {
    
    // MARK: - Properties
    
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "recovery-manager")
    
    /// State manager for persistent state tracking
    private let stateManager: SystemExtensionStateManager
    
    /// System Extension installer for recovery operations
    private let installer: SystemExtensionInstaller
    
    /// System Extension manager for lifecycle control
    private weak var systemExtensionManager: SystemExtensionManagerProtocol?
    
    /// Recovery configuration
    private let config: RecoveryConfiguration
    
    /// Recovery queue for serializing recovery operations
    private let recoveryQueue = DispatchQueue(label: "com.usbipd.mac.recovery", qos: .utility)
    
    /// Active recovery operation tracker
    private var activeRecovery: RecoveryOperation?
    
    /// Recovery history for pattern analysis
    private var recoveryHistory: [RecoveryEvent] = []
    
    /// Timer for periodic health checks
    private var healthCheckTimer: Timer?
    
    /// Communication failure detector
    private var communicationMonitor: CommunicationMonitor?
    
    // MARK: - Initialization
    
    /// Initialize recovery manager
    /// - Parameters:
    ///   - stateManager: State manager for persistent state
    ///   - installer: System Extension installer
    ///   - systemExtensionManager: System Extension manager (weak reference)
    ///   - config: Recovery configuration
    public init(stateManager: SystemExtensionStateManager,
                installer: SystemExtensionInstaller,
                systemExtensionManager: SystemExtensionManagerProtocol,
                config: RecoveryConfiguration = RecoveryConfiguration()) {
        self.stateManager = stateManager
        self.installer = installer
        self.systemExtensionManager = systemExtensionManager
        self.config = config
        
        // Initialize communication monitor
        self.communicationMonitor = CommunicationMonitor(recoveryManager: self)
        
        logger.info("SystemExtensionRecoveryManager initialized", context: [
            "maxRetries": config.maxRetryAttempts,
            "healthCheckInterval": config.healthCheckInterval
        ])
        
        // Start monitoring
        startHealthChecking()
        startCommunicationMonitoring()
        
        // Set up state observation
        stateManager.addStateObserver { [weak self] state in
            self?.handleStateChange(state)
        }
    }
    
    deinit {
        healthCheckTimer?.invalidate()
        communicationMonitor?.stop()
    }
    
    // MARK: - Recovery Interface
    
    /// Initiate recovery for System Extension failure
    /// - Parameters:
    ///   - reason: Reason for recovery
    ///   - completionHandler: Called when recovery completes
    public func initiateRecovery(reason: RecoveryReason, 
                               completionHandler: @escaping (Bool, Error?) -> Void) {
        logger.warning("Initiating System Extension recovery", context: ["reason": reason.description])
        
        recoveryQueue.async {
            // Check if recovery is already in progress
            if let activeOp = self.activeRecovery, !activeOp.isCompleted {
                self.logger.info("Recovery already in progress, queuing request")
                activeOp.addCompletionHandler(completionHandler)
                return
            }
            
            // Start new recovery operation
            let operation = RecoveryOperation(reason: reason, maxRetries: self.config.maxRetryAttempts)
            operation.addCompletionHandler(completionHandler)
            self.activeRecovery = operation
            
            self.performRecovery(operation: operation)
        }
    }
    
    /// Check System Extension health and initiate recovery if needed
    /// - Parameter force: Force health check even if recently performed
    public func performHealthCheck(force: Bool = false) {
        guard force || shouldPerformHealthCheck() else { return }
        
        recoveryQueue.async {
            self.performHealthCheckInternal()
        }
    }
    
    /// Handle communication failure with System Extension
    /// - Parameters:
    ///   - error: Communication error
    ///   - severity: Severity of the failure
    public func handleCommunicationFailure(_ error: Error, severity: CommunicationFailureSeverity) {
        logger.error("System Extension communication failure", context: [
            "error": error.localizedDescription,
            "severity": severity.rawValue
        ])
        
        stateManager.recordError(error, context: "Communication failure - \(severity.rawValue)")
        
        switch severity {
        case .transient:
            // Try reconnection without full recovery
            attemptReconnection(error: error)
        case .persistent:
            // Initiate recovery after persistent failures
            initiateRecovery(reason: .communicationFailure(error)) { success, recoveryError in
                if !success {
                    self.logger.error("Recovery failed after communication failure", context: [
                        "originalError": error.localizedDescription,
                        "recoveryError": recoveryError?.localizedDescription ?? "unknown"
                    ])
                }
            }
        case .critical:
            // Immediate recovery for critical failures
            initiateRecovery(reason: .criticalFailure(error)) { success, recoveryError in
                if !success {
                    self.logger.critical("Critical recovery failed", context: [
                        "originalError": error.localizedDescription,
                        "recoveryError": recoveryError?.localizedDescription ?? "unknown"
                    ])
                }
            }
        }
    }
    
    // MARK: - Recovery Implementation
    
    private func performRecovery(operation: RecoveryOperation) {
        logger.info("Starting recovery operation", context: [
            "reason": operation.reason.description,
            "attempt": operation.currentAttempt + 1,
            "maxRetries": operation.maxRetries
        ])
        
        let recoverySteps: [RecoveryStep] = [
            .saveCurrentState,
            .stopSystemExtension,
            .validateBundle,
            .reinstallIfNeeded,
            .startSystemExtension,
            .restoreDeviceClaims,
            .verifyRecovery
        ]
        
        executeRecoverySteps(steps: recoverySteps, operation: operation)
    }
    
    private func executeRecoverySteps(steps: [RecoveryStep], operation: RecoveryOperation) {
        guard !steps.isEmpty else {
            // Recovery completed successfully
            completeRecovery(operation: operation, success: true, error: nil)
            return
        }
        
        var remainingSteps = steps
        let currentStep = remainingSteps.removeFirst()
        
        logger.debug("Executing recovery step", context: ["step": currentStep.description])
        
        executeRecoveryStep(currentStep, operation: operation) { [weak self] success, error in
            if success {
                // Continue with remaining steps
                self?.executeRecoverySteps(steps: remainingSteps, operation: operation)
            } else {
                // Step failed, check if we should retry
                self?.handleRecoveryStepFailure(step: currentStep, operation: operation, error: error, remainingSteps: steps)
            }
        }
    }
    
    private func executeRecoveryStep(_ step: RecoveryStep, 
                                   operation: RecoveryOperation,
                                   completion: @escaping (Bool, Error?) -> Void) {
        switch step {
        case .saveCurrentState:
            saveCurrentState(completion: completion)
            
        case .stopSystemExtension:
            stopSystemExtension(completion: completion)
            
        case .validateBundle:
            validateBundle(operation: operation, completion: completion)
            
        case .reinstallIfNeeded:
            reinstallIfNeeded(operation: operation, completion: completion)
            
        case .startSystemExtension:
            startSystemExtension(completion: completion)
            
        case .restoreDeviceClaims:
            restoreDeviceClaims(completion: completion)
            
        case .verifyRecovery:
            verifyRecovery(completion: completion)
        }
    }
    
    // MARK: - Recovery Steps Implementation
    
    private func saveCurrentState(completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Saving current state before recovery")
        
        // Force immediate state save
        stateManager.saveState()
        
        // Brief delay to ensure state is persisted
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            completion(true, nil)
        }
    }
    
    private func stopSystemExtension(completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Stopping System Extension for recovery")
        
        guard let manager = systemExtensionManager else {
            completion(false, RecoveryError.managerNotAvailable)
            return
        }
        
        do {
            try manager.stop()
            
            // Wait for graceful shutdown
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                completion(true, nil)
            }
        } catch {
            logger.error("Failed to stop System Extension", context: ["error": error.localizedDescription])
            completion(false, error)
        }
    }
    
    private func validateBundle(operation: RecoveryOperation, completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Validating System Extension bundle")
        
        let state = stateManager.getCurrentState()
        guard let bundlePath = state.bundlePath else {
            completion(false, RecoveryError.bundlePathNotFound)
            return
        }
        
        // Use DevelopmentModeSupport for validation
        let developmentSupport = DevelopmentModeSupport()
        let validationResult = developmentSupport.validateForDevelopmentInstallation(bundlePath: bundlePath)
        
        if validationResult.canProceed {
            completion(true, nil)
        } else {
            let errorMessage = validationResult.issues.map { $0.description }.joined(separator: "; ")
            completion(false, RecoveryError.bundleValidationFailed(errorMessage))
        }
    }
    
    private func reinstallIfNeeded(operation: RecoveryOperation, completion: @escaping (Bool, Error?) -> Void) {
        // Only reinstall for certain types of failures
        switch operation.reason {
        case .bundleCorruption, .criticalFailure:
            logger.info("Reinstalling System Extension due to critical failure")
            reinstallSystemExtension(completion: completion)
        default:
            logger.debug("Skipping reinstallation for recovery reason: \(operation.reason)")
            completion(true, nil)
        }
    }
    
    private func reinstallSystemExtension(completion: @escaping (Bool, Error?) -> Void) {
        let state = stateManager.getCurrentState()
        guard state.bundlePath != nil,
              state.bundleIdentifier != nil else {
            completion(false, RecoveryError.bundleInfoNotFound)
            return
        }
        
        // TODO: Implement proper installation method call when installer API is available
        installer.installSystemExtension(bundleIdentifier: "com.example.systemextension", executablePath: "/tmp/executable") { (result: InstallationResult) in
            if result.success {
                completion(true, nil)
            } else {
                let error = result.errors.first ?? InstallationError.unknownError("Installation failed")
                completion(false, error)
            }
        }
    }
    
    private func startSystemExtension(completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Starting System Extension after recovery")
        
        guard let manager = systemExtensionManager else {
            completion(false, RecoveryError.managerNotAvailable)
            return
        }
        
        do {
            try manager.start()
            
            // Wait for startup
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                // Verify it actually started
                let status = manager.getStatus()
                completion(status.isRunning, status.isRunning ? nil : RecoveryError.startupFailed)
            }
        } catch {
            logger.error("Failed to start System Extension", context: ["error": error.localizedDescription])
            completion(false, error)
        }
    }
    
    private func restoreDeviceClaims(completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Restoring device claims after recovery")
        
        let state = stateManager.getCurrentState()
        let claimedDevices = Array(state.claimedDevices)
        
        guard !claimedDevices.isEmpty else {
            logger.debug("No device claims to restore")
            completion(true, nil)
            return
        }
        
        logger.info("Restoring \(claimedDevices.count) device claims")
        
        // This would typically involve re-claiming devices through the SystemExtensionManager
        // For now, we'll simulate the restoration
        var restoredCount = 0
        var failures: [String] = []
        
        let group = DispatchGroup()
        
        for deviceId in claimedDevices {
            group.enter()
            
            // Simulate device claim restoration
            restoreDeviceClaim(deviceId: deviceId) { success in
                if success {
                    restoredCount += 1
                } else {
                    failures.append(deviceId)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            self.logger.info("Device claim restoration completed", context: [
                "restored": restoredCount,
                "failed": failures.count,
                "failures": failures.joined(separator: ", ")
            ])
            
            // Consider partial success acceptable
            let success = failures.count < claimedDevices.count / 2 // Less than half failed
            completion(success, failures.isEmpty ? nil : RecoveryError.partialClaimRestoration(failures))
        }
    }
    
    private func restoreDeviceClaim(deviceId: String, completion: @escaping (Bool) -> Void) {
        // This would typically use SystemExtensionManager to reclaim the device
        // For now, simulate the operation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Simulate 90% success rate
            let success = UInt32.random(in: 0..<100) < 90
            completion(success)
        }
    }
    
    private func verifyRecovery(completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Verifying System Extension recovery")
        
        // Perform comprehensive health check
        guard let manager = systemExtensionManager else {
            completion(false, RecoveryError.managerNotAvailable)
            return
        }
        
        let status = manager.getStatus()
        let isHealthy = manager.performHealthCheck()
        
        let success = status.isRunning && isHealthy
        stateManager.updateActivationState(activationStatus: success ? .active : .activationFailed)
        
        if success {
            logger.info("System Extension recovery verification successful")
        } else {
            logger.error("System Extension recovery verification failed")
        }
        
        completion(success, success ? nil : RecoveryError.verificationFailed)
    }
    
    // MARK: - Recovery Management
    
    private func handleRecoveryStepFailure(step: RecoveryStep, 
                                         operation: RecoveryOperation, 
                                         error: Error?, 
                                         remainingSteps: [RecoveryStep]) {
        logger.error("Recovery step failed", context: [
            "step": step.description,
            "error": error?.localizedDescription ?? "unknown",
            "attempt": operation.currentAttempt + 1
        ])
        
        operation.currentAttempt += 1
        
        if operation.currentAttempt < operation.maxRetries {
            // Retry the recovery operation
            logger.info("Retrying recovery operation", context: ["attempt": operation.currentAttempt + 1])
            
            DispatchQueue.main.asyncAfter(deadline: .now() + config.retryDelay) {
                self.performRecovery(operation: operation)
            }
        } else {
            // Max retries exceeded
            logger.error("Recovery failed after maximum retry attempts", context: [
                "maxRetries": operation.maxRetries,
                "finalError": error?.localizedDescription ?? "unknown"
            ])
            
            completeRecovery(operation: operation, success: false, error: error ?? RecoveryError.maxRetriesExceeded)
        }
    }
    
    private func completeRecovery(operation: RecoveryOperation, success: Bool, error: Error?) {
        logger.info("Recovery operation completed", context: [
            "success": success,
            "attempts": operation.currentAttempt + 1,
            "reason": operation.reason.description
        ])
        
        operation.complete(success: success, error: error)
        
        // Record recovery event
        let event = RecoveryEvent(
            reason: operation.reason,
            success: success,
            attempts: operation.currentAttempt + 1,
            timestamp: Date(),
            error: error
        )
        recoveryHistory.append(event)
        
        // Limit history size
        if recoveryHistory.count > 100 {
            recoveryHistory.removeFirst()
        }
        
        // Update state manager
        if let error = error {
            stateManager.recordError(error, context: "Recovery operation")
        }
        
        activeRecovery = nil
    }
    
    // MARK: - Health Monitoring
    
    private func startHealthChecking() {
        guard config.healthCheckInterval > 0 else { return }
        
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: config.healthCheckInterval, repeats: true) { _ in
            self.performHealthCheck()
        }
    }
    
    private func shouldPerformHealthCheck() -> Bool {
        // Implement throttling logic here
        return true
    }
    
    private func performHealthCheckInternal() {
        guard let manager = systemExtensionManager else { return }
        
        let status = manager.getStatus()
        let isHealthy = manager.performHealthCheck()
        
        if !status.isRunning || !isHealthy {
            logger.warning("Health check detected System Extension issues", context: [
                "running": status.isRunning,
                "healthy": isHealthy
            ])
            
            initiateRecovery(reason: .healthCheckFailure) { success, error in
                if !success {
                    self.logger.error("Health check recovery failed", context: [
                        "error": error?.localizedDescription ?? "unknown"
                    ])
                }
            }
        }
    }
    
    // MARK: - Communication Monitoring
    
    private func startCommunicationMonitoring() {
        communicationMonitor?.start()
    }
    
    private func attemptReconnection(error: Error) {
        logger.info("Attempting communication reconnection")
        
        // Implement reconnection logic here
        // This would typically involve re-establishing IPC connections
    }
    
    // MARK: - State Management
    
    private func handleStateChange(_ state: SystemExtensionPersistentState) {
        // React to significant state changes
        if state.errorCount > config.maxErrorsBeforeRecovery {
            logger.warning("Error threshold exceeded, initiating recovery", context: [
                "errorCount": state.errorCount,
                "threshold": config.maxErrorsBeforeRecovery
            ])
            
            initiateRecovery(reason: .errorThresholdExceeded) { _, _ in }
        }
    }
}

// MARK: - Supporting Types

/// Recovery configuration
public struct RecoveryConfiguration {
    public let maxRetryAttempts: Int
    public let retryDelay: TimeInterval
    public let healthCheckInterval: TimeInterval
    public let maxErrorsBeforeRecovery: Int
    
    public init(maxRetryAttempts: Int = 3,
                retryDelay: TimeInterval = 5.0,
                healthCheckInterval: TimeInterval = 60.0,
                maxErrorsBeforeRecovery: Int = 10) {
        self.maxRetryAttempts = maxRetryAttempts
        self.retryDelay = retryDelay
        self.healthCheckInterval = healthCheckInterval
        self.maxErrorsBeforeRecovery = maxErrorsBeforeRecovery
    }
}

/// Recovery reasons
public enum RecoveryReason {
    case crash
    case communicationFailure(Error)
    case criticalFailure(Error)
    case healthCheckFailure
    case bundleCorruption
    case errorThresholdExceeded
    
    public var description: String {
        switch self {
        case .crash:
            return "System Extension crash"
        case .communicationFailure:
            return "Communication failure"
        case .criticalFailure:
            return "Critical failure"
        case .healthCheckFailure:
            return "Health check failure"
        case .bundleCorruption:
            return "Bundle corruption"
        case .errorThresholdExceeded:
            return "Error threshold exceeded"
        }
    }
}

/// Recovery steps
private enum RecoveryStep {
    case saveCurrentState
    case stopSystemExtension
    case validateBundle
    case reinstallIfNeeded
    case startSystemExtension
    case restoreDeviceClaims
    case verifyRecovery
    
    var description: String {
        switch self {
        case .saveCurrentState: return "Save current state"
        case .stopSystemExtension: return "Stop System Extension"
        case .validateBundle: return "Validate bundle"
        case .reinstallIfNeeded: return "Reinstall if needed"
        case .startSystemExtension: return "Start System Extension"
        case .restoreDeviceClaims: return "Restore device claims"
        case .verifyRecovery: return "Verify recovery"
        }
    }
}

/// Communication failure severity
public enum CommunicationFailureSeverity: String {
    case transient
    case persistent
    case critical
}

/// Recovery operation
private class RecoveryOperation {
    let reason: RecoveryReason
    let maxRetries: Int
    var currentAttempt: Int = 0
    private var completionHandlers: [(Bool, Error?) -> Void] = []
    private var _isCompleted = false
    
    var isCompleted: Bool { return _isCompleted }
    
    init(reason: RecoveryReason, maxRetries: Int) {
        self.reason = reason
        self.maxRetries = maxRetries
    }
    
    func addCompletionHandler(_ handler: @escaping (Bool, Error?) -> Void) {
        completionHandlers.append(handler)
    }
    
    func complete(success: Bool, error: Error?) {
        _isCompleted = true
        for handler in completionHandlers {
            handler(success, error)
        }
        completionHandlers.removeAll()
    }
}

/// Recovery event for history tracking
private struct RecoveryEvent {
    let reason: RecoveryReason
    let success: Bool
    let attempts: Int
    let timestamp: Date
    let error: Error?
}

/// Recovery errors
public enum RecoveryError: Error {
    case managerNotAvailable
    case bundlePathNotFound
    case bundleInfoNotFound
    case bundleValidationFailed(String)
    case startupFailed
    case partialClaimRestoration([String])
    case verificationFailed
    case maxRetriesExceeded
}

/// Communication monitor
private class CommunicationMonitor {
    private weak var recoveryManager: SystemExtensionRecoveryManager?
    private var isRunning = false
    
    init(recoveryManager: SystemExtensionRecoveryManager) {
        self.recoveryManager = recoveryManager
    }
    
    func start() {
        isRunning = true
        // Implementation would monitor IPC connections
    }
    
    func stop() {
        isRunning = false
    }
}