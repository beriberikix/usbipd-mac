//
//  SystemExtensionStateManager.swift
//  USBIPDCore
//
//  System Extension state persistence and recovery management
//  Maintains reliable state tracking across daemon restarts and system reboots
//

import Foundation
import Common

/// System Extension state persistence and recovery manager
/// Tracks installation, activation, and runtime state across daemon restarts
public class SystemExtensionStateManager {
    
    // MARK: - Properties
    
    private let logger = Logger(config: LoggerConfig(level: .debug), subsystem: "com.usbipd.mac", category: "state-manager")
    
    /// File manager for state persistence
    private let fileManager = FileManager.default
    
    /// State file path
    private let stateFilePath: URL
    
    /// State synchronization queue
    private let stateQueue = DispatchQueue(label: "com.usbipd.mac.state-manager", qos: .utility)
    
    /// Current state cache
    private var cachedState: SystemExtensionPersistentState?
    
    /// State change observers
    private var stateObservers: [(SystemExtensionPersistentState) -> Void] = []
    
    /// State persistence timer
    private var persistenceTimer: Timer?
    
    // MARK: - Initialization
    
    /// Initialize state manager with custom state directory
    /// - Parameter stateDirectory: Directory to store state files (optional)
    public init(stateDirectory: URL? = nil) {
        let baseDirectory = stateDirectory ?? SystemExtensionStateManager.defaultStateDirectory()
        self.stateFilePath = baseDirectory.appendingPathComponent("system_extension_state.json")
        
        // Ensure state directory exists
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // Load initial state
        self.cachedState = loadState()
        
        logger.info("SystemExtensionStateManager initialized", context: [
            "stateFilePath": stateFilePath.path,
            "initialState": cachedState?.debugDescription ?? "none"
        ])
        
        // Start periodic persistence
        startPeriodicPersistence()
    }
    
    deinit {
        persistenceTimer?.invalidate()
        saveState() // Final save
    }
    
    // MARK: - State Management
    
    /// Get current System Extension state
    /// - Returns: Current persistent state
    public func getCurrentState() -> SystemExtensionPersistentState {
        return stateQueue.sync {
            return cachedState ?? SystemExtensionPersistentState()
        }
    }
    
    /// Update System Extension installation state
    /// - Parameters:
    ///   - bundleIdentifier: Bundle identifier of the System Extension
    ///   - bundlePath: Path to the System Extension bundle
    ///   - installationStatus: Installation status
    public func updateInstallationState(bundleIdentifier: String, bundlePath: String, installationStatus: InstallationStatus) {
        stateQueue.async {
            var state = self.cachedState ?? SystemExtensionPersistentState()
            
            state.bundleIdentifier = bundleIdentifier
            state.bundlePath = bundlePath
            state.installationStatus = installationStatus
            state.lastInstallationAttempt = Date()
            
            if installationStatus == .installed {
                state.lastSuccessfulInstallation = Date()
            }
            
            self.updateStateInternal(state)
        }
    }
    
    /// Update System Extension activation state
    /// - Parameters:
    ///   - activationStatus: Current activation status
    ///   - pid: Process ID if running
    public func updateActivationState(activationStatus: ActivationStatus, pid: pid_t? = nil) {
        stateQueue.async {
            var state = self.cachedState ?? SystemExtensionPersistentState()
            
            state.activationStatus = activationStatus
            state.processId = pid
            state.lastActivationAttempt = Date()
            
            if activationStatus == .active {
                state.lastSuccessfulActivation = Date()
                state.activationCount += 1
            }
            
            self.updateStateInternal(state)
        }
    }
    
    /// Update device claim state
    /// - Parameters:
    ///   - deviceId: Device identifier
    ///   - claimed: Whether device is claimed
    public func updateDeviceClaimState(deviceId: String, claimed: Bool) {
        stateQueue.async {
            var state = self.cachedState ?? SystemExtensionPersistentState()
            
            if claimed {
                state.claimedDevices.insert(deviceId)
            } else {
                state.claimedDevices.remove(deviceId)
            }
            
            state.lastDeviceOperation = Date()
            
            self.updateStateInternal(state)
        }
    }
    
    /// Update error state
    /// - Parameters:
    ///   - error: Error that occurred
    ///   - context: Additional context
    public func recordError(_ error: Error, context: String? = nil) {
        stateQueue.async {
            var state = self.cachedState ?? SystemExtensionPersistentState()
            
            let errorRecord = ErrorRecord(
                error: error.localizedDescription,
                context: context,
                timestamp: Date()
            )
            
            state.recentErrors.append(errorRecord)
            
            // Keep only recent errors (last 50)
            if state.recentErrors.count > 50 {
                state.recentErrors.removeFirst(state.recentErrors.count - 50)
            }
            
            state.lastError = Date()
            state.errorCount += 1
            
            self.updateStateInternal(state)
        }
    }
    
    /// Clear error state
    public func clearErrors() {
        stateQueue.async {
            var state = self.cachedState ?? SystemExtensionPersistentState()
            state.recentErrors.removeAll()
            self.updateStateInternal(state)
        }
    }
    
    /// Update health metrics
    /// - Parameter metrics: Health metrics to record
    public func updateHealthMetrics(_ metrics: HealthMetrics) {
        stateQueue.async {
            var state = self.cachedState ?? SystemExtensionPersistentState()
            
            state.healthMetrics = metrics
            state.lastHealthCheck = Date()
            
            self.updateStateInternal(state)
        }
    }
    
    // MARK: - Recovery and Synchronization
    
    /// Check if recovery is needed after daemon restart
    /// - Returns: Recovery information if needed
    public func checkRecoveryNeeded() -> RecoveryInfo? {
        let state = getCurrentState()
        
        // Check if System Extension was previously active but may have been lost
        guard state.activationStatus == .active,
              let lastActivation = state.lastSuccessfulActivation else {
            logger.debug("No recovery needed - System Extension not previously active")
            return nil
        }
        
        // Check if it's been too long since last successful activation
        let timeSinceLastActivation = Date().timeIntervalSince(lastActivation)
        if timeSinceLastActivation > 300 { // 5 minutes
            logger.info("Recovery may be needed - System Extension inactive for \(timeSinceLastActivation) seconds")
            return RecoveryInfo(
                bundleIdentifier: state.bundleIdentifier,
                bundlePath: state.bundlePath,
                claimedDevices: Array(state.claimedDevices),
                lastActivation: lastActivation,
                reason: .inactiveTimeout
            )
        }
        
        // Check process ID if available
        if let pid = state.processId, !isProcessRunning(pid: pid) {
            logger.info("Recovery needed - System Extension process no longer running", context: ["pid": pid])
            return RecoveryInfo(
                bundleIdentifier: state.bundleIdentifier,
                bundlePath: state.bundlePath,
                claimedDevices: Array(state.claimedDevices),
                lastActivation: lastActivation,
                reason: .processNotFound
            )
        }
        
        logger.debug("No recovery needed - System Extension appears to be running normally")
        return nil
    }
    
    /// Synchronize state with running System Extension
    /// - Parameter completionHandler: Called when synchronization completes
    public func synchronizeWithSystemExtension(completionHandler: @escaping (Bool, Error?) -> Void) {
        logger.debug("Starting state synchronization with System Extension")
        
        // This would typically involve IPC communication with the System Extension
        // For now, we'll implement a basic state verification
        
        DispatchQueue.global(qos: .utility).async {
            let currentState = self.getCurrentState()
            
            // Verify System Extension is actually running
            let isRunning = self.verifySystemExtensionRunning(bundleIdentifier: currentState.bundleIdentifier)
            
            if isRunning {
                // Update activation status if needed
                if currentState.activationStatus != .active {
                    self.updateActivationState(activationStatus: .active)
                }
                
                self.logger.info("State synchronization successful - System Extension is running")
                completionHandler(true, nil)
            } else {
                // System Extension is not running, update state
                self.updateActivationState(activationStatus: .inactive)
                
                self.logger.warning("State synchronization found System Extension not running")
                completionHandler(false, nil)
            }
        }
    }
    
    // MARK: - State Observation
    
    /// Add state change observer
    /// - Parameter observer: Observer closure called when state changes
    public func addStateObserver(_ observer: @escaping (SystemExtensionPersistentState) -> Void) {
        stateQueue.async {
            self.stateObservers.append(observer)
        }
    }
    
    // MARK: - Persistence Management
    
    /// Force immediate state persistence
    public func saveState() {
        stateQueue.async {
            self.saveStateInternal()
        }
    }
    
    /// Reset all persistent state (use with caution)
    public func resetState() {
        stateQueue.async {
            self.cachedState = SystemExtensionPersistentState()
            self.saveStateInternal()
            self.notifyObservers()
            
            self.logger.warning("System Extension persistent state has been reset")
        }
    }
    
    // MARK: - Private Implementation
    
    private static func defaultStateDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                in: .localDomainMask).first!
        return applicationSupport.appendingPathComponent("usbipd-mac")
    }
    
    private func updateStateInternal(_ newState: SystemExtensionPersistentState) {
        let previousState = cachedState
        cachedState = newState
        
        // Schedule persistence (debounced)
        schedulePersistence()
        
        // Notify observers if state changed significantly
        if shouldNotifyObservers(previous: previousState, current: newState) {
            notifyObservers()
        }
    }
    
    private func shouldNotifyObservers(previous: SystemExtensionPersistentState?, current: SystemExtensionPersistentState) -> Bool {
        guard let prev = previous else { return true }
        
        // Notify on significant state changes
        return prev.installationStatus != current.installationStatus ||
               prev.activationStatus != current.activationStatus ||
               prev.claimedDevices != current.claimedDevices ||
               prev.errorCount != current.errorCount
    }
    
    private func notifyObservers() {
        guard let state = cachedState else { return }
        
        for observer in stateObservers {
            observer(state)
        }
    }
    
    private func loadState() -> SystemExtensionPersistentState? {
        guard fileManager.fileExists(atPath: stateFilePath.path) else {
            logger.debug("No existing state file found")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: stateFilePath)
            let state = try JSONDecoder().decode(SystemExtensionPersistentState.self, from: data)
            logger.debug("Loaded persistent state", context: ["claimedDevices": state.claimedDevices.count])
            return state
        } catch {
            logger.error("Failed to load persistent state", context: ["error": error.localizedDescription])
            return nil
        }
    }
    
    private func saveStateInternal() {
        guard let state = cachedState else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: stateFilePath)
            
            logger.debug("Saved persistent state", context: [
                "claimedDevices": state.claimedDevices.count,
                "errorCount": state.errorCount
            ])
        } catch {
            logger.error("Failed to save persistent state", context: ["error": error.localizedDescription])
        }
    }
    
    private func startPeriodicPersistence() {
        persistenceTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            self.saveState()
        }
    }
    
    private var pendingPersistenceTimer: Timer?
    
    private func schedulePersistence() {
        // Debounce persistence to avoid excessive writes
        pendingPersistenceTimer?.invalidate()
        pendingPersistenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            self.saveStateInternal()
        }
    }
    
    private func verifySystemExtensionRunning(bundleIdentifier: String?) -> Bool {
        guard let identifier = bundleIdentifier else { return false }
        
        // Use systemextensionsctl to check if extension is running
        let task = Process()
        let pipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
        task.arguments = ["list"]
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Check if our extension is listed as activated
            return output.contains(identifier) && output.contains("[activated enabled]")
        } catch {
            logger.error("Failed to verify System Extension status", context: ["error": error.localizedDescription])
            return false
        }
    }
    
    private func isProcessRunning(pid: pid_t) -> Bool {
        return kill(pid, 0) == 0
    }
}

// MARK: - Supporting Types

/// System Extension persistent state
public struct SystemExtensionPersistentState: Codable {
    /// Bundle identifier of the System Extension
    public var bundleIdentifier: String?
    
    /// Path to the System Extension bundle
    public var bundlePath: String?
    
    /// Current installation status
    public var installationStatus: InstallationStatus = .notInstalled
    
    /// Current activation status
    public var activationStatus: ActivationStatus = .inactive
    
    /// Process ID if running
    public var processId: pid_t?
    
    /// Set of currently claimed device IDs
    public var claimedDevices: Set<String> = []
    
    /// Recent errors
    public var recentErrors: [ErrorRecord] = []
    
    /// Health metrics
    public var healthMetrics: HealthMetrics?
    
    /// Timestamps
    public var lastInstallationAttempt: Date?
    public var lastSuccessfulInstallation: Date?
    public var lastActivationAttempt: Date?
    public var lastSuccessfulActivation: Date?
    public var lastDeviceOperation: Date?
    public var lastError: Date?
    public var lastHealthCheck: Date?
    
    /// Counters
    public var activationCount: Int = 0
    public var errorCount: Int = 0
    
    public init() {}
}

/// Installation status
public enum InstallationStatus: String, Codable {
    case notInstalled
    case installing
    case installed
    case installationFailed
    case upgrading
    case upgradeFailed
}

/// Activation status
public enum ActivationStatus: String, Codable {
    case inactive
    case activating
    case active
    case activationFailed
    case deactivating
}

/// Error record for persistence
public struct ErrorRecord: Codable {
    public let error: String
    public let context: String?
    public let timestamp: Date
    
    public init(error: String, context: String?, timestamp: Date) {
        self.error = error
        self.context = context
        self.timestamp = timestamp
    }
}

/// Health metrics
public struct HealthMetrics: Codable {
    public let memoryUsage: Int
    public let cpuUsage: Double
    public let activeConnections: Int
    public let successfulClaims: Int
    public let failedClaims: Int
    public let averageResponseTime: TimeInterval
    
    public init(
        memoryUsage: Int,
        cpuUsage: Double,
        activeConnections: Int,
        successfulClaims: Int,
        failedClaims: Int,
        averageResponseTime: TimeInterval
    ) {
        self.memoryUsage = memoryUsage
        self.cpuUsage = cpuUsage
        self.activeConnections = activeConnections
        self.successfulClaims = successfulClaims
        self.failedClaims = failedClaims
        self.averageResponseTime = averageResponseTime
    }
}

/// Recovery information
public struct RecoveryInfo {
    public let bundleIdentifier: String?
    public let bundlePath: String?
    public let claimedDevices: [String]
    public let lastActivation: Date
    public let reason: RecoveryReason
    
    public enum RecoveryReason {
        case processNotFound
        case inactiveTimeout
        case systemRestart
    }
}

// MARK: - Debug Support

extension SystemExtensionPersistentState: CustomDebugStringConvertible {
    public var debugDescription: String {
        return """
        SystemExtensionPersistentState(
          bundleIdentifier: \(bundleIdentifier ?? "nil"),
          installationStatus: \(installationStatus),
          activationStatus: \(activationStatus),
          claimedDevices: \(claimedDevices.count),
          errorCount: \(errorCount),
          activationCount: \(activationCount)
        )
        """
    }
}