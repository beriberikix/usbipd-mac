import Foundation
import SystemExtensions
import Common

/// Manages the complete lifecycle of System Extensions including activation, health monitoring, and updates
public class SystemExtensionLifecycleManager {
    
    /// Lifecycle state of the System Extension
    public enum LifecycleState: Equatable {
        case inactive
        case activating
        case active
        case deactivating
        case failed(String)
        case upgrading(from: String, to: String)
        case requiresReboot
        
        public static func == (lhs: LifecycleState, rhs: LifecycleState) -> Bool {
            switch (lhs, rhs) {
            case (.inactive, .inactive),
                 (.activating, .activating),
                 (.active, .active),
                 (.deactivating, .deactivating),
                 (.requiresReboot, .requiresReboot):
                return true
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError == rhsError
            case (.upgrading(let lhsFrom, let lhsTo), .upgrading(let rhsFrom, let rhsTo)):
                return lhsFrom == rhsFrom && lhsTo == rhsTo
            default:
                return false
            }
        }
    }
    
    /// Health monitoring configuration
    public struct HealthConfig {
        let checkInterval: TimeInterval
        let maxFailuresBeforeRestart: Int
        let restartDelay: TimeInterval
        let enableAutoRestart: Bool
        
        public init(checkInterval: TimeInterval = 30.0,
                   maxFailuresBeforeRestart: Int = 3,
                   restartDelay: TimeInterval = 5.0,
                   enableAutoRestart: Bool = true) {
            self.checkInterval = checkInterval
            self.maxFailuresBeforeRestart = maxFailuresBeforeRestart
            self.restartDelay = restartDelay
            self.enableAutoRestart = enableAutoRestart
        }
    }
    
    /// Health status of the System Extension
    public struct HealthStatus {
        let isHealthy: Bool
        let lastCheckTime: Date
        let consecutiveFailures: Int
        let lastError: String?
        let uptime: TimeInterval
        let restartCount: Int
        
        public init(isHealthy: Bool = false,
                   lastCheckTime: Date = Date(),
                   consecutiveFailures: Int = 0,
                   lastError: String? = nil,
                   uptime: TimeInterval = 0,
                   restartCount: Int = 0) {
            self.isHealthy = isHealthy
            self.lastCheckTime = lastCheckTime
            self.consecutiveFailures = consecutiveFailures
            self.lastError = lastError
            self.uptime = uptime
            self.restartCount = restartCount
        }
    }
    
    /// Version information for System Extension
    public struct VersionInfo: Equatable {
        let bundleVersion: String
        let bundleShortVersion: String
        let bundleIdentifier: String
        
        public init(bundleVersion: String, bundleShortVersion: String, bundleIdentifier: String) {
            self.bundleVersion = bundleVersion
            self.bundleShortVersion = bundleShortVersion
            self.bundleIdentifier = bundleIdentifier
        }
    }
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.github.usbipd-mac", category: "SystemExtensionLifecycleManager")
    private let installer: SystemExtensionInstaller
    private let healthConfig: HealthConfig
    
    /// Current lifecycle state
    public private(set) var state: LifecycleState = .inactive
    
    /// Current health status
    public private(set) var healthStatus: HealthStatus
    
    /// Current version information
    public private(set) var currentVersion: VersionInfo?
    
    /// Health monitoring timer
    private var healthCheckTimer: DispatchSourceTimer?
    
    /// Extension start time for uptime calculation
    private var startTime: Date?
    
    /// Queue for lifecycle operations
    private let lifecycleQueue = DispatchQueue(label: "systemextension.lifecycle", qos: .utility)
    
    /// Delegates for lifecycle events
    public weak var delegate: SystemExtensionLifecycleDelegate?
    
    // MARK: - Initialization
    
    /// Initialize lifecycle manager with installer and configuration
    /// - Parameters:
    ///   - installer: System Extension installer instance
    ///   - healthConfig: Health monitoring configuration
    public init(installer: SystemExtensionInstaller, healthConfig: HealthConfig = HealthConfig()) {
        self.installer = installer
        self.healthConfig = healthConfig
        self.healthStatus = HealthStatus()
        
        logger.info("SystemExtensionLifecycleManager initialized", context: [
            "healthCheckInterval": healthConfig.checkInterval,
            "maxFailuresBeforeRestart": healthConfig.maxFailuresBeforeRestart,
            "autoRestartEnabled": healthConfig.enableAutoRestart
        ])
    }
    
    deinit {
        stopHealthMonitoring()
    }
    
    // MARK: - Lifecycle Management
    
    /// Activate the System Extension with health monitoring
    /// - Parameter completion: Completion handler called when activation completes
    public func activate(completion: @escaping (Result<Void, SystemExtensionInstallationError>) -> Void) {
        lifecycleQueue.async(flags: []) { [weak self] in
            guard let self = self else { return }
            
            guard self.state != .activating && self.state != .active else {
                self.logger.warning("System Extension already active or activating")
                DispatchQueue.main.async {
                    completion(.success(()))
                }
                return
            }
            
            self.logger.info("Starting System Extension activation")
            self.setState(.activating)
            
            self.installer.installSystemExtension(bundleIdentifier: "placeholder", executablePath: "/tmp/placeholder") { [weak self] result in
                guard let self = self else { return }
                
                if result.success {
                    self.handleActivationSuccess()
                    completion(.success(()))
                } else {
                    let error = result.errors.first ?? InstallationError.unknownError("Activation failed")
                    self.handleActivationFailure(error)
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Deactivate the System Extension
    /// - Parameter completion: Completion handler called when deactivation completes
    public func deactivate(completion: @escaping (Result<Void, SystemExtensionInstallationError>) -> Void) {
        lifecycleQueue.async(flags: []) { [weak self] in
            guard let self = self else { return }
            
            guard self.state == .active || self.state == .failed("") else {
                self.logger.warning("System Extension not active")
                DispatchQueue.main.async {
                    completion(.success(()))
                }
                return
            }
            
            self.logger.info("Starting System Extension deactivation")
            self.setState(.deactivating)
            self.stopHealthMonitoring()
            
            self.installer.uninstallSystemExtension { [weak self] result in
                guard let self = self else { return }
                
                if result.success {
                    self.handleDeactivationSuccess()
                    completion(.success(()))
                } else {
                    let error = result.errors.first ?? InstallationError.unknownError("Deactivation failed")
                    self.handleDeactivationFailure(error)
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Restart the System Extension
    /// - Parameter completion: Completion handler called when restart completes
    public func restart(completion: @escaping (Result<Void, SystemExtensionInstallationError>) -> Void) {
        logger.info("Restarting System Extension")
        
        deactivate { [weak self] deactivationResult in
            guard let self = self else { return }
            
            switch deactivationResult {
            case .success:
                // Wait a moment before reactivating
                DispatchQueue.main.asyncAfter(deadline: .now() + self.healthConfig.restartDelay) {
                    self.activate(completion: completion)
                }
                
            case .failure(let error):
                self.logger.error("Failed to deactivate before restart", context: ["error": error.localizedDescription])
                completion(.failure(error))
            }
        }
    }
    
    /// Update to a new version of the System Extension
    /// - Parameters:
    ///   - newVersion: Version information for the new extension
    ///   - completion: Completion handler called when update completes
    public func updateToVersion(_ newVersion: VersionInfo, completion: @escaping (Result<Void, SystemExtensionInstallationError>) -> Void) {
        lifecycleQueue.async(flags: []) { [weak self] in
            guard let self = self else { return }
            
            let oldVersion = self.currentVersion?.bundleShortVersion ?? "unknown"
            
            self.logger.info("Starting System Extension update", context: [
                "fromVersion": oldVersion,
                "toVersion": newVersion.bundleShortVersion
            ])
            
            self.setState(.upgrading(from: oldVersion, to: newVersion.bundleShortVersion))
            
            // For System Extensions, updates are handled by activating the new version
            // The system will automatically replace the old version
            self.installer.installSystemExtension(bundleIdentifier: "placeholder", executablePath: "/tmp/placeholder") { [weak self] result in
                guard let self = self else { return }
                
                if result.success {
                    self.currentVersion = newVersion
                    self.handleActivationSuccess()
                    self.logger.info("System Extension update completed successfully")
                    completion(.success(()))
                } else {
                    let error = result.errors.first ?? InstallationError.unknownError("Update failed")
                    self.handleActivationFailure(error)
                    self.logger.error("System Extension update failed", context: ["error": error.localizedDescription])
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Health Monitoring
    
    /// Start health monitoring for the System Extension
    public func startHealthMonitoring() {
        lifecycleQueue.async(flags: []) { [weak self] in
            guard let self = self else { return }
            
            guard self.healthCheckTimer == nil else {
                self.logger.debug("Health monitoring already active")
                return
            }
            
            self.logger.info("Starting health monitoring", context: [
                "interval": self.healthConfig.checkInterval,
                "autoRestart": self.healthConfig.enableAutoRestart
            ])
            
            let timer = DispatchSource.makeTimerSource(queue: self.lifecycleQueue)
            timer.schedule(deadline: .now() + self.healthConfig.checkInterval,
                          repeating: self.healthConfig.checkInterval)
            
            timer.setEventHandler { [weak self] in
                self?.performHealthCheck()
            }
            
            self.healthCheckTimer = timer
            timer.resume()
        }
    }
    
    /// Stop health monitoring
    public func stopHealthMonitoring() {
        lifecycleQueue.async(flags: []) { [weak self] in
            guard let self = self else { return }
            
            self.healthCheckTimer?.cancel()
            self.healthCheckTimer = nil
            
            self.logger.info("Health monitoring stopped")
        }
    }
    
    /// Perform an immediate health check
    /// - Returns: Current health status
    @discardableResult
    public func performHealthCheck() -> HealthStatus {
        let startTime = Date()
        var isHealthy = true
        var errorMessage: String?
        
        // Perform health checks
        do {
            // Check if System Extension is responsive
            try checkSystemExtensionResponsiveness()
            
            // Check resource usage
            try checkResourceUsage()
            
            // Check IPC connectivity
            try checkIPCConnectivity()
        } catch {
            isHealthy = false
            errorMessage = error.localizedDescription
            logger.warning("Health check failed", context: ["error": error.localizedDescription])
        }
        
        // Update health status
        let consecutiveFailures = isHealthy ? 0 : healthStatus.consecutiveFailures + 1
        let uptime = self.startTime?.timeIntervalSinceNow.magnitude ?? 0
        
        healthStatus = HealthStatus(
            isHealthy: isHealthy,
            lastCheckTime: startTime,
            consecutiveFailures: consecutiveFailures,
            lastError: errorMessage,
            uptime: uptime,
            restartCount: healthStatus.restartCount
        )
        
        // Handle consecutive failures
        if consecutiveFailures >= healthConfig.maxFailuresBeforeRestart && healthConfig.enableAutoRestart {
            logger.error("Maximum consecutive failures reached, initiating restart", context: [
                "failures": consecutiveFailures,
                "maxFailures": healthConfig.maxFailuresBeforeRestart
            ])
            
            initiateAutoRestart()
        }
        
        // Notify delegate
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.lifecycleManager(self!, didUpdateHealth: self!.healthStatus)
        }
        
        return healthStatus
    }
    
    // MARK: - Private Methods
    
    private func setState(_ newState: LifecycleState) {
        let oldState = state
        state = newState
        
        logger.info("Lifecycle state changed", context: [
            "from": String(describing: oldState),
            "to": String(describing: newState)
        ])
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.lifecycleManager(self, didChangeState: oldState, to: newState)
        }
    }
    
    private func handleActivationSuccess() {
        startTime = Date()
        setState(.active)
        startHealthMonitoring()
        
        healthStatus = HealthStatus(
            isHealthy: true,
            lastCheckTime: Date(),
            consecutiveFailures: 0,
            lastError: nil,
            uptime: 0,
            restartCount: healthStatus.restartCount
        )
        
        logger.info("System Extension activated successfully")
    }
    
    private func handleActivationFailure(_ error: SystemExtensionInstallationError) {
        setState(.failed(error.localizedDescription))
        stopHealthMonitoring()
        
        logger.error("System Extension activation failed", context: ["error": error.localizedDescription])
    }
    
    private func handleDeactivationSuccess() {
        startTime = nil
        setState(.inactive)
        
        logger.info("System Extension deactivated successfully")
    }
    
    private func handleDeactivationFailure(_ error: SystemExtensionInstallationError) {
        setState(.failed(error.localizedDescription))
        
        logger.error("System Extension deactivation failed", context: ["error": error.localizedDescription])
    }
    
    private func initiateAutoRestart() {
        guard healthConfig.enableAutoRestart else { return }
        
        logger.info("Initiating automatic restart due to health failures")
        
        let newRestartCount = healthStatus.restartCount + 1
        healthStatus = HealthStatus(
            isHealthy: healthStatus.isHealthy,
            lastCheckTime: healthStatus.lastCheckTime,
            consecutiveFailures: healthStatus.consecutiveFailures,
            lastError: healthStatus.lastError,
            uptime: healthStatus.uptime,
            restartCount: newRestartCount
        )
        
        restart { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                self.logger.info("Automatic restart completed successfully")
                
            case .failure(let error):
                self.logger.error("Automatic restart failed", context: ["error": error.localizedDescription])
                self.setState(.failed("Auto-restart failed: \(error.localizedDescription)"))
            }
        }
    }
    
    // MARK: - Health Check Methods
    
    private func checkSystemExtensionResponsiveness() throws {
        // In a real implementation, this would:
        // - Send a ping/health check request to the System Extension
        // - Check if it responds within a reasonable time
        // - Verify the response is valid
        
        // For now, we'll simulate a responsiveness check
        // This would be replaced with actual IPC communication
    }
    
    private func checkResourceUsage() throws {
        // In a real implementation, this would:
        // - Monitor CPU usage of the System Extension
        // - Check memory consumption
        // - Monitor file descriptor usage
        // - Check for resource leaks
        
        // For now, this is a placeholder
    }
    
    private func checkIPCConnectivity() throws {
        // In a real implementation, this would:
        // - Test IPC connection to the System Extension
        // - Verify bidirectional communication
        // - Check for IPC channel health
        
        // For now, this is a placeholder
    }
}

// MARK: - SystemExtensionLifecycleDelegate Protocol

/// Delegate protocol for System Extension lifecycle events
public protocol SystemExtensionLifecycleDelegate: AnyObject {
    /// Called when the lifecycle state changes
    /// - Parameters:
    ///   - manager: The lifecycle manager
    ///   - oldState: Previous state
    ///   - newState: New state
    func lifecycleManager(_ manager: SystemExtensionLifecycleManager,
                         didChangeState oldState: SystemExtensionLifecycleManager.LifecycleState,
                         to newState: SystemExtensionLifecycleManager.LifecycleState)
    
    /// Called when health status is updated
    /// - Parameters:
    ///   - manager: The lifecycle manager
    ///   - healthStatus: Updated health status
    func lifecycleManager(_ manager: SystemExtensionLifecycleManager,
                         didUpdateHealth healthStatus: SystemExtensionLifecycleManager.HealthStatus)
}