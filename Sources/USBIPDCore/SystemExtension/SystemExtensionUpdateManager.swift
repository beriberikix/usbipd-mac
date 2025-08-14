//
//  SystemExtensionUpdateManager.swift
//  USBIPDCore
//
//  System Extension update management and version transitions
//  Handles smooth updates while preserving device claims and configuration
//

import Foundation
import Common

/// System Extension update manager
/// Manages version transitions and preserves state during System Extension updates
public class SystemExtensionUpdateManager {
    
    // MARK: - Properties
    
    private let logger = Logger(config: LoggerConfig(level: .info), subsystem: "com.usbipd.mac", category: "update-manager")
    
    /// State manager for persistent state tracking
    private let stateManager: SystemExtensionStateManager
    
    /// System Extension installer for update operations
    private let installer: SystemExtensionInstaller
    
    /// System Extension manager for lifecycle control
    private weak var systemExtensionManager: SystemExtensionManagerProtocol?
    
    /// Update configuration
    private let config: UpdateConfiguration
    
    /// Update queue for serializing update operations
    private let updateQueue = DispatchQueue(label: "com.usbipd.mac.update", qos: .utility)
    
    /// Active update operation tracker
    private var activeUpdate: UpdateOperation?
    
    /// Update history for tracking successful updates
    private var updateHistory: [UpdateEvent] = []
    
    /// Version detection timer
    private var versionCheckTimer: Timer?
    
    // MARK: - Initialization
    
    /// Initialize update manager
    /// - Parameters:
    ///   - stateManager: State manager for persistent state
    ///   - installer: System Extension installer
    ///   - systemExtensionManager: System Extension manager (weak reference)
    ///   - config: Update configuration
    public init(stateManager: SystemExtensionStateManager,
                installer: SystemExtensionInstaller,
                systemExtensionManager: SystemExtensionManagerProtocol,
                config: UpdateConfiguration = UpdateConfiguration()) {
        self.stateManager = stateManager
        self.installer = installer
        self.systemExtensionManager = systemExtensionManager
        self.config = config
        
        logger.info("SystemExtensionUpdateManager initialized", context: [
            "versionCheckInterval": config.versionCheckInterval,
            "preserveDeviceClaims": config.preserveDeviceClaims
        ])
        
        // Start version monitoring if configured
        if config.automaticVersionCheck {
            startVersionMonitoring()
        }
    }
    
    deinit {
        versionCheckTimer?.invalidate()
    }
    
    // MARK: - Update Management
    
    /// Check for System Extension version changes and handle updates
    /// - Parameter completionHandler: Called when update check completes
    public func checkForUpdates(completionHandler: @escaping (UpdateCheckResult) -> Void) {
        logger.debug("Checking for System Extension version changes")
        
        updateQueue.async {
            do {
                let currentState = self.stateManager.getCurrentState()
                let updateCheckResult = try self.performVersionCheck(currentState: currentState)
                
                DispatchQueue.main.async {
                    completionHandler(updateCheckResult)
                }
            } catch {
                self.logger.error("Version check failed", context: ["error": error.localizedDescription])
                DispatchQueue.main.async {
                    completionHandler(.error(error))
                }
            }
        }
    }
    
    /// Initiate System Extension update
    /// - Parameters:
    ///   - newBundlePath: Path to the new System Extension bundle
    ///   - completionHandler: Called when update completes
    public func initiateUpdate(newBundlePath: String, 
                             completionHandler: @escaping (Bool, Error?) -> Void) {
        logger.info("Initiating System Extension update", context: ["newBundlePath": newBundlePath])
        
        updateQueue.async {
            // Check if update is already in progress
            if let activeOp = self.activeUpdate, !activeOp.isCompleted {
                self.logger.info("Update already in progress")
                activeOp.addCompletionHandler(completionHandler)
                return
            }
            
            // Validate new bundle before starting update
            do {
                let newVersion = try self.extractBundleVersion(bundlePath: newBundlePath)
                let currentState = self.stateManager.getCurrentState()
                
                // Start new update operation
                let operation = UpdateOperation(
                    fromVersion: self.extractCurrentVersion(state: currentState),
                    toVersion: newVersion,
                    newBundlePath: newBundlePath,
                    preserveDeviceClaims: self.config.preserveDeviceClaims
                )
                operation.addCompletionHandler(completionHandler)
                self.activeUpdate = operation
                
                self.performUpdate(operation: operation)
            } catch {
                self.logger.error("Update validation failed", context: ["error": error.localizedDescription])
                completionHandler(false, error)
            }
        }
    }
    
    /// Handle automatic update when version change is detected
    /// - Parameters:
    ///   - oldVersion: Previous System Extension version
    ///   - newVersion: New System Extension version
    ///   - newBundlePath: Path to the new bundle
    ///   - completionHandler: Called when update completes
    public func handleAutomaticUpdate(oldVersion: String,
                                    newVersion: String,
                                    newBundlePath: String,
                                    completionHandler: @escaping (Bool, Error?) -> Void) {
        logger.info("Handling automatic System Extension update", context: [
            "oldVersion": oldVersion,
            "newVersion": newVersion
        ])
        
        // Check if automatic updates are enabled
        guard config.enableAutomaticUpdates else {
            logger.info("Automatic updates disabled, skipping update")
            completionHandler(false, UpdateError.automaticUpdatesDisabled)
            return
        }
        
        // Initiate the update
        initiateUpdate(newBundlePath: newBundlePath, completionHandler: completionHandler)
    }
    
    // MARK: - Update Process Implementation
    
    private func performUpdate(operation: UpdateOperation) {
        logger.info("Starting System Extension update", context: [
            "fromVersion": operation.fromVersion ?? "unknown",
            "toVersion": operation.toVersion,
            "preserveDeviceClaims": operation.preserveDeviceClaims
        ])
        
        let updateSteps: [UpdateStep] = [
            .validateNewBundle,
            .captureCurrentState,
            .gracefulShutdown,
            .backupCurrentBundle,
            .installNewBundle,
            .startNewExtension,
            .restoreState,
            .verifyUpdate,
            .cleanupBackup
        ]
        
        executeUpdateSteps(steps: updateSteps, operation: operation)
    }
    
    private func executeUpdateSteps(steps: [UpdateStep], operation: UpdateOperation) {
        guard !steps.isEmpty else {
            // Update completed successfully
            completeUpdate(operation: operation, success: true, error: nil)
            return
        }
        
        var remainingSteps = steps
        let currentStep = remainingSteps.removeFirst()
        
        logger.debug("Executing update step", context: ["step": currentStep.description])
        
        executeUpdateStep(currentStep, operation: operation) { [weak self] success, error in
            if success {
                // Continue with remaining steps
                self?.executeUpdateSteps(steps: remainingSteps, operation: operation)
            } else {
                // Step failed, initiate rollback
                self?.handleUpdateFailure(step: currentStep, operation: operation, error: error)
            }
        }
    }
    
    private func executeUpdateStep(_ step: UpdateStep,
                                 operation: UpdateOperation,
                                 completion: @escaping (Bool, Error?) -> Void) {
        switch step {
        case .validateNewBundle:
            validateNewBundle(operation: operation, completion: completion)
            
        case .captureCurrentState:
            captureCurrentState(operation: operation, completion: completion)
            
        case .gracefulShutdown:
            gracefulShutdown(operation: operation, completion: completion)
            
        case .backupCurrentBundle:
            backupCurrentBundle(operation: operation, completion: completion)
            
        case .installNewBundle:
            installNewBundle(operation: operation, completion: completion)
            
        case .startNewExtension:
            startNewExtension(operation: operation, completion: completion)
            
        case .restoreState:
            restoreState(operation: operation, completion: completion)
            
        case .verifyUpdate:
            verifyUpdate(operation: operation, completion: completion)
            
        case .cleanupBackup:
            cleanupBackup(operation: operation, completion: completion)
        }
    }
    
    // MARK: - Update Steps Implementation
    
    private func validateNewBundle(operation: UpdateOperation, completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Validating new System Extension bundle")
        
        let developmentSupport = DevelopmentModeSupport()
        let validationResult = developmentSupport.validateForDevelopmentInstallation(bundlePath: operation.newBundlePath)
        
        if validationResult.canProceed {
            // Additional version compatibility check
            if let fromVersion = operation.fromVersion,
               !isVersionCompatible(from: fromVersion, to: operation.toVersion) {
                completion(false, UpdateError.incompatibleVersion(from: fromVersion, to: operation.toVersion))
                return
            }
            
            completion(true, nil)
        } else {
            let errorMessage = validationResult.issues.map { $0.description }.joined(separator: "; ")
            completion(false, UpdateError.bundleValidationFailed(errorMessage))
        }
    }
    
    private func captureCurrentState(operation: UpdateOperation, completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Capturing current System Extension state")
        
        let currentState = stateManager.getCurrentState()
        
        // Create update snapshot
        let snapshot = UpdateSnapshot(
            timestamp: Date(),
            bundleVersion: operation.fromVersion,
            claimedDevices: Array(currentState.claimedDevices),
            healthMetrics: currentState.healthMetrics,
            activationStatus: currentState.activationStatus
        )
        
        operation.preUpdateSnapshot = snapshot
        
        // Force state persistence
        stateManager.saveState()
        
        completion(true, nil)
    }
    
    private func gracefulShutdown(operation: UpdateOperation, completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Performing graceful System Extension shutdown")
        
        guard let manager = systemExtensionManager else {
            completion(false, UpdateError.managerNotAvailable)
            return
        }
        
        // Notify System Extension of impending update
        notifyExtensionOfUpdate(manager: manager)
        
        // Allow time for graceful shutdown
        Task { @MainActor in
            try await Task.sleep(nanoseconds: UInt64(config.gracefulShutdownTimeout * 1_000_000_000))
            do {
                try manager.stop()
                completion(true, nil)
            } catch {
                self.logger.error("Failed to stop System Extension gracefully", context: ["error": error.localizedDescription])
                completion(false, error)
            }
        }
    }
    
    private func backupCurrentBundle(operation: UpdateOperation, completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Backing up current System Extension bundle")
        
        let currentState = stateManager.getCurrentState()
        guard let currentBundlePath = currentState.bundlePath else {
            // No current bundle to backup
            completion(true, nil)
            return
        }
        
        // Create backup path
        let backupPath = createBackupPath(originalPath: currentBundlePath, version: operation.fromVersion)
        operation.backupPath = backupPath
        
        do {
            try FileManager.default.copyItem(atPath: currentBundlePath, toPath: backupPath)
            logger.info("Current bundle backed up", context: ["backupPath": backupPath])
            completion(true, nil)
        } catch {
            logger.error("Failed to backup current bundle", context: ["error": error.localizedDescription])
            completion(false, UpdateError.backupFailed(error))
        }
    }
    
    private func installNewBundle(operation: UpdateOperation, completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Installing new System Extension bundle")
        
        // Extract bundle identifier from new bundle
        guard let bundleIdentifier = extractBundleIdentifier(bundlePath: operation.newBundlePath) else {
            completion(false, UpdateError.invalidBundleIdentifier)
            return
        }
        
        // TODO: Implement proper installation method call when installer API is available
        installer.installSystemExtension(bundleIdentifier: "com.example.systemextension", executablePath: "/tmp/executable") { (result: InstallationResult) in
            if result.success {
                // Update state with new bundle information
                self.stateManager.updateInstallationState(
                    bundleIdentifier: bundleIdentifier,
                    bundlePath: operation.newBundlePath,
                    installationStatus: .installed
                )
                completion(true, nil)
            } else {
                let error = result.errors.first ?? InstallationError.unknownError("Installation failed")
                completion(false, error)
            }
        }
    }
    
    private func startNewExtension(operation: UpdateOperation, completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Starting updated System Extension")
        
        guard let manager = systemExtensionManager else {
            completion(false, UpdateError.managerNotAvailable)
            return
        }
        
        do {
            try manager.start()
            
            // Wait for startup and verify
            Task { @MainActor in
                try await Task.sleep(nanoseconds: UInt64(config.startupTimeout * 1_000_000_000))
                let status = manager.getStatus()
                if status.isRunning {
                    self.stateManager.updateActivationState(activationStatus: .active)
                    completion(true, nil)
                } else {
                    completion(false, UpdateError.startupFailed)
                }
            }
        } catch {
            logger.error("Failed to start updated System Extension", context: ["error": error.localizedDescription])
            completion(false, error)
        }
    }
    
    private func restoreState(operation: UpdateOperation, completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Restoring System Extension state after update")
        
        guard operation.preserveDeviceClaims,
              let snapshot = operation.preUpdateSnapshot else {
            // No state to restore or not preserving state
            completion(true, nil)
            return
        }
        
        // Restore claimed devices
        let deviceClaimGroup = DispatchGroup()
        var restoredCount = 0
        var failures: [String] = []
        
        for deviceId in snapshot.claimedDevices {
            deviceClaimGroup.enter()
            
            restoreDeviceClaim(deviceId: deviceId) { success in
                if success {
                    restoredCount += 1
                    self.stateManager.updateDeviceClaimState(deviceId: deviceId, claimed: true)
                } else {
                    failures.append(deviceId)
                }
                deviceClaimGroup.leave()
            }
        }
        
        deviceClaimGroup.notify(queue: .main) {
            self.logger.info("State restoration completed", context: [
                "restored": restoredCount,
                "failed": failures.count
            ])
            
            // Consider partial success acceptable
            let success = failures.count < snapshot.claimedDevices.count / 2
            completion(success, failures.isEmpty ? nil : UpdateError.partialStateRestoration(failures))
        }
    }
    
    private func verifyUpdate(operation: UpdateOperation, completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Verifying System Extension update")
        
        guard let manager = systemExtensionManager else {
            completion(false, UpdateError.managerNotAvailable)
            return
        }
        
        let status = manager.getStatus()
        let isHealthy = manager.performHealthCheck()
        
        let success = status.isRunning && isHealthy
        
        if success {
            logger.info("System Extension update verification successful")
        } else {
            logger.error("System Extension update verification failed")
        }
        
        completion(success, success ? nil : UpdateError.verificationFailed)
    }
    
    private func cleanupBackup(operation: UpdateOperation, completion: @escaping (Bool, Error?) -> Void) {
        logger.debug("Cleaning up backup after successful update")
        
        guard let backupPath = operation.backupPath else {
            completion(true, nil)
            return
        }
        
        // Only cleanup if update was successful and not in rollback mode
        if !operation.isRollback && config.cleanupBackupsAfterSuccess {
            do {
                try FileManager.default.removeItem(atPath: backupPath)
                logger.debug("Backup cleaned up", context: ["backupPath": backupPath])
            } catch {
                // Non-fatal error
                logger.warning("Failed to cleanup backup", context: ["error": error.localizedDescription])
            }
        }
        
        completion(true, nil)
    }
    
    // MARK: - Update Failure and Rollback
    
    private func handleUpdateFailure(step: UpdateStep, operation: UpdateOperation, error: Error?) {
        logger.error("Update step failed, initiating rollback", context: [
            "step": step.description,
            "error": error?.localizedDescription ?? "unknown"
        ])
        
        // Initiate rollback
        performRollback(operation: operation, failureError: error)
    }
    
    private func performRollback(operation: UpdateOperation, failureError: Error?) {
        logger.warning("Performing System Extension update rollback")
        
        guard let backupPath = operation.backupPath else {
            // No backup available, complete with failure
            completeUpdate(operation: operation, success: false, error: failureError ?? UpdateError.rollbackFailed("No backup available"))
            return
        }
        
        operation.isRollback = true
        
        let rollbackSteps: [UpdateStep] = [
            .gracefulShutdown,
            .installNewBundle, // Install backup (old version)
            .startNewExtension,
            .restoreState
        ]
        
        // Temporarily update the "new" bundle path to the backup for rollback
        let originalNewPath = operation.newBundlePath
        operation.newBundlePath = backupPath
        
        executeUpdateSteps(steps: rollbackSteps, operation: operation)
        
        // Restore original path for completion handling
        operation.newBundlePath = originalNewPath
    }
    
    // MARK: - Version Management
    
    private func performVersionCheck(currentState: SystemExtensionPersistentState) throws -> UpdateCheckResult {
        guard let bundlePath = currentState.bundlePath else {
            return .noVersionInfo
        }
        
        let currentVersion = extractCurrentVersion(state: currentState)
        let bundleVersion = try extractBundleVersion(bundlePath: bundlePath)
        
        if let current = currentVersion, current != bundleVersion {
            return .updateAvailable(from: current, to: bundleVersion, bundlePath: bundlePath)
        } else {
            return .upToDate(bundleVersion)
        }
    }
    
    private func extractBundleVersion(bundlePath: String) throws -> String {
        let infoPlistPath = "\(bundlePath)/Contents/Info.plist"
        
        guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
            throw UpdateError.cannotReadBundleInfo
        }
        
        guard let version = plist["CFBundleShortVersionString"] as? String ?? plist["CFBundleVersion"] as? String else {
            throw UpdateError.versionNotFound
        }
        
        return version
    }
    
    private func extractBundleIdentifier(bundlePath: String) -> String? {
        let infoPlistPath = "\(bundlePath)/Contents/Info.plist"
        
        guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: infoPlistPath)),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let identifier = plist["CFBundleIdentifier"] as? String else {
            return nil
        }
        
        return identifier
    }
    
    private func extractCurrentVersion(state: SystemExtensionPersistentState) -> String? {
        // This would typically be stored in state or extracted from running extension
        return state.bundlePath.flatMap { try? extractBundleVersion(bundlePath: $0) }
    }
    
    private func isVersionCompatible(from: String, to: String) -> Bool {
        // Implement version compatibility checking logic
        // For now, assume all versions are compatible
        return true
    }
    
    // MARK: - Helper Methods
    
    private func startVersionMonitoring() {
        guard config.versionCheckInterval > 0 else { return }
        
        versionCheckTimer = Timer.scheduledTimer(withTimeInterval: config.versionCheckInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdates { result in
                switch result {
                case .updateAvailable(let from, let to, let bundlePath):
                    self?.logger.info("Automatic version check detected update", context: [
                        "from": from,
                        "to": to
                    ])
                    
                    if self?.config.enableAutomaticUpdates == true {
                        self?.handleAutomaticUpdate(oldVersion: from, newVersion: to, newBundlePath: bundlePath) { success, error in
                            if !success {
                                self?.logger.error("Automatic update failed", context: ["error": error?.localizedDescription ?? "unknown"])
                            }
                        }
                    }
                case .upToDate, .noVersionInfo:
                    break
                case .error(let error):
                    self?.logger.error("Automatic version check failed", context: ["error": error.localizedDescription])
                }
            }
        }
    }
    
    private func notifyExtensionOfUpdate(manager: SystemExtensionManagerProtocol) {
        // This would typically send an IPC message to the System Extension
        // informing it of the impending update so it can prepare gracefully
        logger.debug("Notifying System Extension of impending update")
    }
    
    private func createBackupPath(originalPath: String, version: String?) -> String {
        let backupDir = NSTemporaryDirectory()
        let timestamp = Int(Date().timeIntervalSince1970)
        let versionSuffix = version.map { "_v\($0)" } ?? ""
        return "\(backupDir)/SystemExtensionBackup\(versionSuffix)_\(timestamp).systemextension"
    }
    
    private func restoreDeviceClaim(deviceId: String, completion: @escaping (Bool) -> Void) {
        // This would typically use SystemExtensionManager to reclaim the device
        // For now, simulate the operation
        Task {
            try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            // Simulate 95% success rate for updates (higher than recovery)
            let success = UInt32.random(in: 0..<100) < 95
            completion(success)
        }
    }
    
    private func completeUpdate(operation: UpdateOperation, success: Bool, error: Error?) {
        logger.info("Update operation completed", context: [
            "success": success,
            "fromVersion": operation.fromVersion ?? "unknown",
            "toVersion": operation.toVersion,
            "isRollback": operation.isRollback
        ])
        
        operation.complete(success: success, error: error)
        
        // Record update event
        let event = UpdateEvent(
            fromVersion: operation.fromVersion,
            toVersion: operation.toVersion,
            success: success,
            timestamp: Date(),
            error: error,
            isRollback: operation.isRollback
        )
        updateHistory.append(event)
        
        // Limit history size
        if updateHistory.count > 50 {
            updateHistory.removeFirst()
        }
        
        // Update state manager
        if let error = error {
            stateManager.recordError(error, context: "System Extension update")
        }
        
        activeUpdate = nil
    }
}

// MARK: - Supporting Types

/// Update configuration
public struct UpdateConfiguration {
    public let enableAutomaticUpdates: Bool
    public let automaticVersionCheck: Bool
    public let versionCheckInterval: TimeInterval
    public let preserveDeviceClaims: Bool
    public let gracefulShutdownTimeout: TimeInterval
    public let startupTimeout: TimeInterval
    public let cleanupBackupsAfterSuccess: Bool
    
    public init(enableAutomaticUpdates: Bool = false,
                automaticVersionCheck: Bool = true,
                versionCheckInterval: TimeInterval = 300.0, // 5 minutes
                preserveDeviceClaims: Bool = true,
                gracefulShutdownTimeout: TimeInterval = 5.0,
                startupTimeout: TimeInterval = 10.0,
                cleanupBackupsAfterSuccess: Bool = true) {
        self.enableAutomaticUpdates = enableAutomaticUpdates
        self.automaticVersionCheck = automaticVersionCheck
        self.versionCheckInterval = versionCheckInterval
        self.preserveDeviceClaims = preserveDeviceClaims
        self.gracefulShutdownTimeout = gracefulShutdownTimeout
        self.startupTimeout = startupTimeout
        self.cleanupBackupsAfterSuccess = cleanupBackupsAfterSuccess
    }
}

/// Update check result
public enum UpdateCheckResult {
    case upToDate(String)
    case updateAvailable(from: String, to: String, bundlePath: String)
    case noVersionInfo
    case error(Error)
}

/// Update steps
private enum UpdateStep {
    case validateNewBundle
    case captureCurrentState
    case gracefulShutdown
    case backupCurrentBundle
    case installNewBundle
    case startNewExtension
    case restoreState
    case verifyUpdate
    case cleanupBackup
    
    var description: String {
        switch self {
        case .validateNewBundle: return "Validate new bundle"
        case .captureCurrentState: return "Capture current state"
        case .gracefulShutdown: return "Graceful shutdown"
        case .backupCurrentBundle: return "Backup current bundle"
        case .installNewBundle: return "Install new bundle"
        case .startNewExtension: return "Start new extension"
        case .restoreState: return "Restore state"
        case .verifyUpdate: return "Verify update"
        case .cleanupBackup: return "Cleanup backup"
        }
    }
}

/// Update operation
private class UpdateOperation {
    let fromVersion: String?
    let toVersion: String
    var newBundlePath: String
    let preserveDeviceClaims: Bool
    
    var preUpdateSnapshot: UpdateSnapshot?
    var backupPath: String?
    var isRollback: Bool = false
    
    private var completionHandlers: [(Bool, Error?) -> Void] = []
    private var _isCompleted = false
    
    var isCompleted: Bool { return _isCompleted }
    
    init(fromVersion: String?, toVersion: String, newBundlePath: String, preserveDeviceClaims: Bool) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.newBundlePath = newBundlePath
        self.preserveDeviceClaims = preserveDeviceClaims
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

/// Update snapshot for state preservation
private struct UpdateSnapshot {
    let timestamp: Date
    let bundleVersion: String?
    let claimedDevices: [String]
    let healthMetrics: HealthMetrics?
    let activationStatus: ActivationStatus
}

/// Update event for history tracking
private struct UpdateEvent {
    let fromVersion: String?
    let toVersion: String
    let success: Bool
    let timestamp: Date
    let error: Error?
    let isRollback: Bool
}

/// Update errors
public enum UpdateError: Error, CustomStringConvertible {
    case automaticUpdatesDisabled
    case managerNotAvailable
    case bundleValidationFailed(String)
    case incompatibleVersion(from: String, to: String)
    case backupFailed(Error)
    case installationFailed
    case startupFailed
    case verificationFailed
    case partialStateRestoration([String])
    case rollbackFailed(String)
    case cannotReadBundleInfo
    case versionNotFound
    case invalidBundleIdentifier
    
    public var description: String {
        switch self {
        case .automaticUpdatesDisabled:
            return "Automatic updates are disabled"
        case .managerNotAvailable:
            return "System Extension manager not available"
        case .bundleValidationFailed(let reason):
            return "Bundle validation failed: \(reason)"
        case .incompatibleVersion(let from, let to):
            return "Incompatible version transition from \(from) to \(to)"
        case .backupFailed(let error):
            return "Backup failed: \(error.localizedDescription)"
        case .installationFailed:
            return "New bundle installation failed"
        case .startupFailed:
            return "Updated System Extension failed to start"
        case .verificationFailed:
            return "Update verification failed"
        case .partialStateRestoration(let failures):
            return "Partial state restoration failed for devices: \(failures.joined(separator: ", "))"
        case .rollbackFailed(let reason):
            return "Rollback failed: \(reason)"
        case .cannotReadBundleInfo:
            return "Cannot read bundle information"
        case .versionNotFound:
            return "Version information not found in bundle"
        case .invalidBundleIdentifier:
            return "Invalid bundle identifier"
        }
    }
}