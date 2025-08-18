// SystemExtensionManager.swift
// Main coordination logic for System Extension operations

import Foundation
import Common

// MARK: - System Extension Manager

/// Main coordinator for System Extension functionality
/// Manages device claiming, IPC communication, and system lifecycle
public class SystemExtensionManager {
    
    // MARK: - Properties
    
    /// Device claimer for USB device operations
    private let deviceClaimer: DeviceClaimer
    
    /// IPC handler for daemon communication
    private let ipcHandler: IPCHandler
    
    /// Status monitor for health tracking
    private let statusMonitor: StatusMonitor?
    
    /// Logger for manager operations
    private let logger: Logger
    
    /// Queue for serializing manager operations
    private let queue: DispatchQueue
    
    /// Current manager state
    private var state: SystemExtensionState = .stopped
    
    /// Manager configuration
    private let config: SystemExtensionManagerConfig
    
    /// Health check timer
    private var healthCheckTimer: DispatchSourceTimer?
    
    /// Statistics for manager operations
    private var statistics: SystemExtensionStatistics
    
    /// Request processing delegates
    public weak var requestDelegate: SystemExtensionRequestDelegate?
    
    /// Enhanced bundle detector for production environments
    private let bundleDetector: SystemExtensionBundleDetector
    
    /// Installation orchestrator for automatic installation workflows
    private let installationOrchestrator: InstallationOrchestrator
    
    /// Current installation status (cached)
    private var cachedInstallationStatus: OrchestrationResult?
    
    /// Last installation status check time
    private var lastInstallationStatusCheck: Date?
    
    // MARK: - Initialization
    
    /// Initialize with default components
    public convenience init() {
        let logger = Logger(
            config: LoggerConfig(level: .info),
            subsystem: "com.usbipd.mac.system-extension",
            category: "manager"
        )
        
        self.init(
            deviceClaimer: IOKitDeviceClaimer(),
            ipcHandler: XPCIPCHandler(),
            statusMonitor: ComprehensiveStatusMonitor(),
            config: SystemExtensionManagerConfig(),
            bundleDetector: SystemExtensionBundleDetector(),
            installationOrchestrator: InstallationOrchestrator(),
            logger: logger
        )
    }
    
    /// Initialize with dependency injection for testing
    /// - Parameters:
    ///   - deviceClaimer: Device claiming implementation
    ///   - ipcHandler: IPC communication implementation
    ///   - statusMonitor: Optional status monitoring
    ///   - config: Manager configuration
    ///   - bundleDetector: Enhanced bundle detector for production environments
    ///   - installationOrchestrator: Installation orchestrator for automatic workflows
    ///   - logger: Logger instance
    public init(
        deviceClaimer: DeviceClaimer,
        ipcHandler: IPCHandler,
        statusMonitor: StatusMonitor? = nil,
        config: SystemExtensionManagerConfig = SystemExtensionManagerConfig(),
        bundleDetector: SystemExtensionBundleDetector = SystemExtensionBundleDetector(),
        installationOrchestrator: InstallationOrchestrator = InstallationOrchestrator(),
        logger: Logger
    ) {
        self.deviceClaimer = deviceClaimer
        self.ipcHandler = ipcHandler
        self.statusMonitor = statusMonitor
        self.config = config
        self.bundleDetector = bundleDetector
        self.installationOrchestrator = installationOrchestrator
        self.logger = logger
        self.queue = DispatchQueue(
            label: "com.usbipd.mac.system-extension.manager",
            qos: .userInitiated
        )
        self.statistics = SystemExtensionStatistics()
        
        // Perform initial bundle detection
        let bundleDetectionResult = bundleDetector.detectBundle()
        
        logger.info("SystemExtensionManager initialized", context: [
            "autoStart": config.autoStart,
            "healthCheckInterval": config.healthCheckInterval,
            "restoreStateOnStart": config.restoreStateOnStart,
            "bundleDetected": bundleDetectionResult.found,
            "bundlePath": bundleDetectionResult.bundlePath ?? "none",
            "detectionEnvironment": "\(bundleDetectionResult.detectionEnvironment)"
        ])
    }
    
    deinit {
        // Ensure clean shutdown
        if state != .stopped {
            logger.warning("SystemExtensionManager being deinitialized while not stopped")
            do {
                try stop()
            } catch {
                logger.error("Failed to stop manager during deinitialization", context: [
                    "error": error.localizedDescription
                ])
            }
        }
        
        logger.info("SystemExtensionManager deinitialized", context: [
            "totalRequests": statistics.totalRequests,
            "uptime": statistics.uptime
        ])
    }
    
    // MARK: - Lifecycle Management
    
    /// Start the System Extension manager
    /// - Throws: SystemExtensionError if startup fails
    public func start() throws {
        try queue.sync {
            guard state == .stopped else {
                logger.warning("Attempted to start manager that is not stopped", context: [
                    "currentState": state.description
                ])
                return
            }
            
            logger.info("Starting SystemExtensionManager")
            state = .starting
            statistics.startTime = Date()
            
            do {
                // Start IPC handler first to accept connections
                try ipcHandler.startListener()
                logger.debug("IPC handler started successfully")
                
                // Restore device claims if configured
                if config.restoreStateOnStart {
                    try restoreDeviceClaimState()
                }
                
                // Set up health monitoring
                if let statusMonitor = statusMonitor {
                    try statusMonitor.startMonitoring()
                    logger.debug("Status monitoring started")
                }
                
                // Start health check timer
                startHealthCheckTimer()
                
                // Set up IPC request handling (simulated for MVP)
                setupIPCRequestHandling()
                
                state = .running
                logger.info("SystemExtensionManager started successfully")
            } catch {
                // Clean up on startup failure
                state = .error(error.localizedDescription)
                try? cleanupAfterFailure()
                
                logger.error("Failed to start SystemExtensionManager", context: [
                    "error": error.localizedDescription
                ])
                throw SystemExtensionError.extensionNotRunning
            }
        }
    }
    
    /// Stop the System Extension manager
    /// - Throws: SystemExtensionError if shutdown fails
    public func stop() throws {
        queue.sync {
            guard state == .running else {
                logger.warning("Attempted to stop manager that is not running", context: [
                    "currentState": state.description
                ])
                return
            }
            
            logger.info("Stopping SystemExtensionManager")
            state = .stopping
            
            // Stop health check timer
            healthCheckTimer?.cancel()
            healthCheckTimer = nil
            
            // Save current state for restoration
            if config.saveStateOnStop {
                do {
                    try deviceClaimer.saveClaimState()
                    logger.debug("Device claim state saved")
                } catch {
                    logger.error("Failed to save device claim state", context: [
                        "error": error.localizedDescription
                    ])
                }
            }
            
            // Stop status monitoring
            statusMonitor?.stopMonitoring()
            
            // Stop IPC handler
            ipcHandler.stopListener()
            logger.debug("IPC handler stopped")
            
            state = .stopped
            statistics.stopTime = Date()
            
            logger.info("SystemExtensionManager stopped successfully", context: [
                "uptime": statistics.uptime,
                "totalRequests": statistics.totalRequests
            ])
        }
    }
    
    /// Restart the System Extension manager
    /// - Throws: SystemExtensionError if restart fails
    public func restart() throws {
        logger.info("Restarting SystemExtensionManager")
        
        try stop()
        
        // Brief delay to ensure clean shutdown
        Thread.sleep(forTimeInterval: 0.5)
        
        try start()
        
        logger.info("SystemExtensionManager restarted successfully")
    }
    
    // MARK: - Device Operations
    
    /// Claim a USB device through the System Extension
    /// - Parameter device: USB device to claim
    /// - Returns: ClaimedDevice information
    /// - Throws: SystemExtensionError if claiming fails
    public func claimDevice(_ device: USBDevice) throws -> ClaimedDevice {
        return try queue.sync {
            guard state == .running else {
                throw SystemExtensionError.extensionNotRunning
            }
            
            logger.info("Processing device claim request", context: [
                "deviceID": "\(device.busID)-\(device.deviceID)",
                "vendorID": String(format: "0x%04x", device.vendorID),
                "productID": String(format: "0x%04x", device.productID)
            ])
            
            do {
                let claimedDevice = try deviceClaimer.claimDevice(device: device)
                statistics.recordDeviceClaim(success: true)
                
                logger.info("Device claimed successfully", context: [
                    "deviceID": claimedDevice.deviceID,
                    "claimMethod": claimedDevice.claimMethod.rawValue
                ])
                
                return claimedDevice
            } catch {
                statistics.recordDeviceClaim(success: false)
                logger.error("Failed to claim device", context: [
                    "deviceID": "\(device.busID)-\(device.deviceID)",
                    "error": error.localizedDescription
                ])
                throw error
            }
        }
    }
    
    /// Release a USB device from System Extension control
    /// - Parameter device: USB device to release
    /// - Throws: SystemExtensionError if release fails
    public func releaseDevice(_ device: USBDevice) throws {
        try queue.sync {
            guard state == .running else {
                throw SystemExtensionError.extensionNotRunning
            }
            
            let deviceID = "\(device.busID)-\(device.deviceID)"
            logger.info("Processing device release request", context: ["deviceID": deviceID])
            
            do {
                try deviceClaimer.releaseDevice(device: device)
                statistics.recordDeviceRelease(success: true)
                
                logger.info("Device released successfully", context: ["deviceID": deviceID])
            } catch {
                statistics.recordDeviceRelease(success: false)
                logger.error("Failed to release device", context: [
                    "deviceID": deviceID,
                    "error": error.localizedDescription
                ])
                throw error
            }
        }
    }
    
    /// Get all currently claimed devices
    /// - Returns: Array of claimed devices
    public func getClaimedDevices() -> [ClaimedDevice] {
        return queue.sync {
            return deviceClaimer.getAllClaimedDevices()
        }
    }
    
    /// Check if a device is currently claimed
    /// - Parameter deviceID: Device identifier to check
    /// - Returns: True if device is claimed
    public func isDeviceClaimed(deviceID: String) -> Bool {
        return queue.sync {
            return deviceClaimer.isDeviceClaimed(deviceID: deviceID)
        }
    }
    
    // MARK: - Status and Health
    
    /// Get current System Extension status
    /// - Returns: Current status information
    public func getStatus() -> SystemExtensionStatus {
        return queue.sync {
            let claimedDevices = deviceClaimer.getAllClaimedDevices()
            let healthMetrics = getHealthMetrics()
            let installationStatus = getCurrentInstallationStatus()
            let bundleInfo = getBundleInfo()
            
            return SystemExtensionStatus(
                isRunning: state == .running,
                claimedDevices: claimedDevices,
                lastStartTime: statistics.startTime ?? Date(),
                errorCount: statistics.totalErrors,
                memoryUsage: getMemoryUsage(),
                version: "1.0.0", // System Extension version
                healthMetrics: healthMetrics,
                installationStatus: installationStatus,
                bundleInfo: bundleInfo
            )
        }
    }
    
    // MARK: - Installation Status Integration
    
    /// Get current installation status using enhanced verification
    /// - Returns: Current installation status
    private func getCurrentInstallationStatus() -> SystemExtensionInstallationStatus {
        // Check if we have cached status that's still fresh (within last 30 seconds)
        let cacheTimeout: TimeInterval = 30.0
        if let lastCheck = lastInstallationStatusCheck,
           let cachedStatus = cachedInstallationStatus,
           Date().timeIntervalSince(lastCheck) < cacheTimeout {
            
            // Return cached status based on the orchestration result
            return mapOrchestrationResultToInstallationStatus(cachedStatus)
        }
        
        // Perform fresh installation status check
        Task {
            await refreshInstallationStatus()
        }
        
        // Return best-effort status based on current state and bundle detection
        let bundleDetectionResult = bundleDetector.detectBundle()
        
        if !bundleDetectionResult.found {
            return .notInstalled
        }
        
        if state == .running {
            return .installed
        }
        
        // Default to unknown if we can't determine status
        return .unknown
    }
    
    /// Refresh installation status asynchronously
    private func refreshInstallationStatus() async {
        // Use the installation verification manager directly for quick status check
        let verificationManager = InstallationVerificationManager()
        let verificationResult = await verificationManager.verifyInstallation()
        
        // Create a simplified orchestration result based on verification
        let orchestrationResult = OrchestrationResult(
            success: verificationResult.status.isOperational,
            finalPhase: verificationResult.status.isOperational ? .completed : .failed,
            verificationResult: verificationResult,
            issues: verificationResult.discoveredIssues.map { $0.description },
            recommendations: verificationResult.discoveredIssues.compactMap { $0.remediation }
        )
        
        // Cache the result
        await MainActor.run {
            self.cachedInstallationStatus = orchestrationResult
            self.lastInstallationStatusCheck = Date()
        }
    }
    
    /// Map orchestration result to installation status enum
    private func mapOrchestrationResultToInstallationStatus(_ result: OrchestrationResult) -> SystemExtensionInstallationStatus {
        if result.success {
            switch result.finalPhase {
            case .completed:
                return .installed
            case .failed:
                return .installationFailed
            case .systemExtensionSubmission, .serviceIntegration, .installationVerification:
                return .installing
            case .bundleDetection:
                return .notInstalled
            }
        } else {
            switch result.finalPhase {
            case .bundleDetection:
                return .notInstalled
            case .failed:
                return .installationFailed
            default:
                return .installing
            }
        }
    }
    
    /// Get enhanced bundle information using the enhanced bundle detector
    /// - Returns: Bundle information if available
    private func getBundleInfo() -> SystemExtensionBundle? {
        let detectionResult = bundleDetector.detectBundle()
        
        guard detectionResult.found,
              let bundlePath = detectionResult.bundlePath,
              let bundleIdentifier = detectionResult.bundleIdentifier else {
            return nil
        }
        
        let bundleContents = BundleContents(
            infoPlistPath: "\(bundlePath)/Contents/Info.plist",
            executablePath: "\(bundlePath)/Contents/MacOS/USBIPDSystemExtension",
            entitlementsPath: nil,
            resourceFiles: [],
            isValid: true,
            bundleSize: 0 // Would need actual file size calculation
        )
        
        return SystemExtensionBundle(
            bundlePath: bundlePath,
            bundleIdentifier: bundleIdentifier,
            displayName: "USB/IP System Extension",
            version: detectionResult.homebrewMetadata?.version ?? "unknown",
            buildNumber: "1.0.0",
            executableName: "USBIPDSystemExtension",
            teamIdentifier: nil,
            contents: bundleContents,
            codeSigningInfo: nil,
            creationTime: detectionResult.homebrewMetadata?.installationDate ?? Date()
        )
    }
    
    // MARK: - Automatic Installation Integration
    
    /// Perform automatic installation if needed and configured
    /// This integrates with the installation orchestrator for automatic workflows
    public func performAutomaticInstallationIfNeeded() async -> Bool {
        logger.info("Checking if automatic installation is needed")
        
        // Check if bundle is detected and if installation is needed
        let bundleDetectionResult = bundleDetector.detectBundle()
        
        if !bundleDetectionResult.found {
            logger.info("No bundle detected, automatic installation not possible")
            return false
        }
        
        // Check current installation status
        let currentStatus = getCurrentInstallationStatus()
        
        // Only proceed with automatic installation for certain status conditions
        switch currentStatus {
        case .notInstalled, .installationFailed, .requiresReinstall:
            logger.info("Automatic installation needed", context: [
                "currentStatus": currentStatus.rawValue,
                "bundlePath": bundleDetectionResult.bundlePath ?? "unknown"
            ])
            
            // Use the installation orchestrator to perform the installation
            let result = await installationOrchestrator.performCompleteInstallation()
            
            // Cache the result
            cachedInstallationStatus = result
            lastInstallationStatusCheck = Date()
            
            if result.success {
                logger.info("Automatic installation completed successfully")
                return true
            } else {
                logger.warning("Automatic installation failed", context: [
                    "finalPhase": result.finalPhase.rawValue,
                    "issues": result.issues.joined(separator: ", ")
                ])
                return false
            }
            
        case .installed, .installing, .pendingApproval:
            logger.debug("Automatic installation not needed", context: [
                "currentStatus": currentStatus.rawValue
            ])
            return true
            
        case .unknown, .invalidBundle:
            logger.warning("Cannot perform automatic installation", context: [
                "currentStatus": currentStatus.rawValue
            ])
            return false
        }
    }
    
    /// Perform health check
    /// - Returns: True if all systems are healthy
    public func performHealthCheck() -> Bool {
        return queue.sync {
            logger.debug("Performing health check")
            
            var isHealthy = true
            
            // Check manager state
            if state != .running {
                logger.warning("Health check failed: manager not running", context: [
                    "state": state.description
                ])
                isHealthy = false
            }
            
            // Check IPC handler
            if !ipcHandler.isListening() {
                logger.warning("Health check failed: IPC handler not listening")
                isHealthy = false
            }
            
            // Check status monitor if available
            if let statusMonitor = statusMonitor, !statusMonitor.isMonitoring() {
                logger.warning("Health check failed: status monitor not active")
                isHealthy = false
            }
            
            statistics.recordHealthCheck(healthy: isHealthy)
            
            logger.debug("Health check completed", context: ["healthy": isHealthy])
            return isHealthy
        }
    }
    
    /// Get System Extension statistics
    /// - Returns: Current statistics
    public func getStatistics() -> SystemExtensionStatistics {
        return queue.sync {
            return statistics
        }
    }
    
    // MARK: - Private Implementation
    
    private func restoreDeviceClaimState() throws {
        logger.info("Restoring device claim state")
        
        do {
            try deviceClaimer.restoreClaimedDevices()
            let restoredDevices = deviceClaimer.getAllClaimedDevices()
            
            logger.info("Device claim state restored", context: [
                "restoredDevices": restoredDevices.count
            ])
            
            statistics.restoredDevices = restoredDevices.count
        } catch {
            logger.error("Failed to restore device claim state", context: [
                "error": error.localizedDescription
            ])
            throw error
        }
    }
    
    private func startHealthCheckTimer() {
        guard config.healthCheckInterval > 0 else { return }
        
        healthCheckTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        healthCheckTimer?.schedule(
            deadline: .now() + .seconds(Int(config.healthCheckInterval)),
            repeating: .seconds(Int(config.healthCheckInterval))
        )
        
        healthCheckTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            _ = self.performHealthCheck()
        }
        
        healthCheckTimer?.resume()
        logger.debug("Health check timer started", context: [
            "interval": config.healthCheckInterval
        ])
    }
    
    private func setupIPCRequestHandling() {
        // In a real implementation, this would set up the IPC request processing
        // For the MVP, we simulate the setup
        logger.debug("Setting up IPC request handling")
        
        // This would typically involve setting up callbacks or delegates
        // to handle incoming IPC requests from the main daemon
    }
    
    private func cleanupAfterFailure() throws {
        logger.debug("Cleaning up after startup failure")
        
        // Stop any components that may have started
        healthCheckTimer?.cancel()
        healthCheckTimer = nil
        
        statusMonitor?.stopMonitoring()
        ipcHandler.stopListener()
        
        statistics.stopTime = Date()
    }
    
    private func getHealthMetrics() -> SystemExtensionHealthMetrics {
        let ipcStats = ipcHandler.getStatistics()
        
        return SystemExtensionHealthMetrics(
            successfulClaims: statistics.successfulClaims,
            failedClaims: statistics.failedClaims,
            activeConnections: ipcStats.acceptedConnections - ipcStats.disconnectedClients,
            averageClaimTime: 0.0, // Would be calculated from actual timing data
            lastHealthCheck: statistics.lastHealthCheck ?? Date()
        )
    }
    
    private func getMemoryUsage() -> Int {
        // Get current memory usage
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Int(info.resident_size)
        } else {
            return 0
        }
    }
    
    private func processIPCRequest(_ request: IPCRequest) -> IPCResponse {
        logger.debug("Processing IPC request", context: [
            "requestID": request.requestID.uuidString,
            "command": request.command.rawValue,
            "clientID": request.clientID
        ])
        
        let startTime = Date()
        statistics.recordRequest()
        
        do {
            let result = try handleCommand(request.command, parameters: request.parameters)
            let processingTime = Date().timeIntervalSince(startTime) * 1000 // milliseconds
            
            let response = IPCResponse(
                requestID: request.requestID,
                success: true,
                result: result,
                timestamp: Date(),
                processingTime: processingTime
            )
            
            statistics.recordResponse(success: true)
            
            logger.debug("IPC request processed successfully", context: [
                "requestID": request.requestID.uuidString,
                "processingTime": String(format: "%.2f", processingTime)
            ])
            
            return response
        } catch let error as SystemExtensionError {
            let processingTime = Date().timeIntervalSince(startTime) * 1000
            
            statistics.recordResponse(success: false)
            statistics.recordError()
            
            logger.error("IPC request failed", context: [
                "requestID": request.requestID.uuidString,
                "error": error.localizedDescription
            ])
            
            return IPCResponse(
                requestID: request.requestID,
                success: false,
                error: error,
                timestamp: Date(),
                processingTime: processingTime
            )
        } catch {
            let systemError = SystemExtensionError.internalError("Unexpected error: \(error.localizedDescription)")
            let processingTime = Date().timeIntervalSince(startTime) * 1000
            
            statistics.recordResponse(success: false)
            statistics.recordError()
            
            return IPCResponse(
                requestID: request.requestID,
                success: false,
                error: systemError,
                timestamp: Date(),
                processingTime: processingTime
            )
        }
    }
    
    private func handleCommand(_ command: IPCCommand, parameters: [String: String]) throws -> IPCResult? {
        switch command {
        case .getStatus:
            let status = getStatus()
            return .status(status)
            
        case .getClaimedDevices:
            let devices = getClaimedDevices()
            return .claimedDevices(devices)
            
        case .healthCheck:
            let isHealthy = performHealthCheck()
            return .healthCheck(isHealthy)
            
        case .claimDevice:
            // Parse device parameters and claim device
            // This would require converting parameters to USBDevice
            // For MVP, we'll return a placeholder response
            return .success("Device claiming not fully implemented in MVP")
            
        case .releaseDevice:
            // Parse device parameters and release device
            return .success("Device releasing not fully implemented in MVP")
            
        case .getClaimHistory:
            // Return claim history
            return .claimHistory([]) // Empty history for MVP
            
        case .shutdown:
            // Initiate graceful shutdown
            try stop()
            return .success("System Extension shutdown initiated")
        }
    }
}

// MARK: - System Extension State

/// Current state of the System Extension manager
public enum SystemExtensionState: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case error(String) // Changed from Error to String for Equatable conformance
    
    public var description: String {
        switch self {
        case .stopped: return "stopped"
        case .starting: return "starting"
        case .running: return "running"
        case .stopping: return "stopping"
        case .error(let error): return "error: \(error)"
        }
    }
}

// MARK: - Configuration

/// Configuration for SystemExtensionManager behavior
public struct SystemExtensionManagerConfig {
    /// Whether to automatically start components on initialization
    public let autoStart: Bool
    
    /// Whether to restore device claim state on startup
    public let restoreStateOnStart: Bool
    
    /// Whether to save device claim state on shutdown
    public let saveStateOnStop: Bool
    
    /// Health check interval in seconds (0 to disable)
    public let healthCheckInterval: TimeInterval
    
    public init(
        autoStart: Bool = false,
        restoreStateOnStart: Bool = true,
        saveStateOnStop: Bool = true,
        healthCheckInterval: TimeInterval = 60.0
    ) {
        self.autoStart = autoStart
        self.restoreStateOnStart = restoreStateOnStart
        self.saveStateOnStop = saveStateOnStop
        self.healthCheckInterval = healthCheckInterval
    }
}

// MARK: - Statistics

/// Statistics for System Extension manager operations
public struct SystemExtensionStatistics {
    /// Manager start time
    public var startTime: Date?
    
    /// Manager stop time
    public var stopTime: Date?
    
    /// Total requests processed
    public var totalRequests: Int = 0
    
    /// Total responses sent
    public var totalResponses: Int = 0
    
    /// Total errors encountered
    public var totalErrors: Int = 0
    
    /// Successful device claims
    public var successfulClaims: Int = 0
    
    /// Failed device claims
    public var failedClaims: Int = 0
    
    /// Successful device releases
    public var successfulReleases: Int = 0
    
    /// Failed device releases
    public var failedReleases: Int = 0
    
    /// Number of devices restored on startup
    public var restoredDevices: Int = 0
    
    /// Number of health checks performed
    public var healthChecks: Int = 0
    
    /// Number of successful health checks
    public var healthyChecks: Int = 0
    
    /// Last health check time
    public var lastHealthCheck: Date?
    
    public init() {}
    
    mutating func recordRequest() {
        totalRequests += 1
    }
    
    mutating func recordResponse(success: Bool) {
        totalResponses += 1
    }
    
    mutating func recordError() {
        totalErrors += 1
    }
    
    mutating func recordDeviceClaim(success: Bool) {
        if success {
            successfulClaims += 1
        } else {
            failedClaims += 1
        }
    }
    
    mutating func recordDeviceRelease(success: Bool) {
        if success {
            successfulReleases += 1
        } else {
            failedReleases += 1
        }
    }
    
    mutating func recordHealthCheck(healthy: Bool) {
        healthChecks += 1
        lastHealthCheck = Date()
        
        if healthy {
            healthyChecks += 1
        }
    }
    
    /// Get uptime in seconds
    public var uptime: TimeInterval {
        if let startTime = startTime {
            return (stopTime ?? Date()).timeIntervalSince(startTime)
        }
        return 0.0
    }
    
    /// Get health check success rate
    public var healthCheckSuccessRate: Double {
        return healthChecks > 0 ? Double(healthyChecks) / Double(healthChecks) * 100.0 : 0.0
    }
    
    /// Get device claim success rate
    public var deviceClaimSuccessRate: Double {
        let total = successfulClaims + failedClaims
        return total > 0 ? Double(successfulClaims) / Double(total) * 100.0 : 0.0
    }
}

// MARK: - Request Delegate Protocol

/// Delegate protocol for handling System Extension requests
public protocol SystemExtensionRequestDelegate: AnyObject {
    /// Handle an incoming IPC request
    /// - Parameter request: IPC request to handle
    /// - Returns: IPC response
    func handleRequest(_ request: IPCRequest) -> IPCResponse
}