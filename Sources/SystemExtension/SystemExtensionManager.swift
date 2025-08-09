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
            logger: logger
        )
    }
    
    /// Initialize with dependency injection for testing
    /// - Parameters:
    ///   - deviceClaimer: Device claiming implementation
    ///   - ipcHandler: IPC communication implementation
    ///   - statusMonitor: Optional status monitoring
    ///   - config: Manager configuration
    ///   - logger: Logger instance
    public init(
        deviceClaimer: DeviceClaimer,
        ipcHandler: IPCHandler,
        statusMonitor: StatusMonitor? = nil,
        config: SystemExtensionManagerConfig = SystemExtensionManagerConfig(),
        logger: Logger
    ) {
        self.deviceClaimer = deviceClaimer
        self.ipcHandler = ipcHandler
        self.statusMonitor = statusMonitor
        self.config = config
        self.logger = logger
        self.queue = DispatchQueue(
            label: "com.usbipd.mac.system-extension.manager",
            qos: .userInitiated
        )
        self.statistics = SystemExtensionStatistics()
        
        logger.info("SystemExtensionManager initialized", context: [
            "autoStart": config.autoStart,
            "healthCheckInterval": config.healthCheckInterval,
            "restoreStateOnStart": config.restoreStateOnStart
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
        try queue.sync {
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
            
            return SystemExtensionStatus(
                isRunning: state == .running,
                claimedDevices: claimedDevices,
                lastStartTime: statistics.startTime ?? Date(),
                errorCount: statistics.totalErrors,
                memoryUsage: getMemoryUsage(),
                version: "1.0.0", // System Extension version
                healthMetrics: healthMetrics
            )
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
        
        healthCheckTimer = DispatchSource.makeTimerSource(queue: queue)
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

