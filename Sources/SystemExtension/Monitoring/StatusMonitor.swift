// StatusMonitor.swift
// Comprehensive status monitoring and health checking for System Extension

import Foundation
import Common
import USBIPDCore

// MARK: - Status Monitor Protocol

/// Protocol for comprehensive system status monitoring
/// Monitors system health, resource usage, and operational status
public protocol StatusMonitor {
    /// Start status monitoring with background health checks
    /// - Throws: SystemExtensionError if monitoring setup fails
    func startMonitoring() throws
    
    /// Stop status monitoring and cleanup resources
    func stopMonitoring()
    
    /// Check if monitoring is currently active
    /// - Returns: True if monitoring is active, false otherwise
    func isMonitoring() -> Bool
    
    /// Perform immediate health check
    /// - Returns: Current health status
    func performHealthCheck() -> HealthCheckResult
    
    /// Get current system status
    /// - Returns: Comprehensive system status information
    func getSystemStatus() -> SystemStatus
    
    /// Get health metrics for monitoring dashboard
    /// - Returns: Current health metrics
    func getHealthMetrics() -> HealthMetrics
    
    /// Register health check delegate for notifications
    /// - Parameter delegate: Delegate to receive health notifications
    func setHealthDelegate(_ delegate: HealthCheckDelegate?)
}

// MARK: - Comprehensive Status Monitor Implementation

/// Comprehensive status monitor implementation for System Extension
public class ComprehensiveStatusMonitor: StatusMonitor {
    
    // MARK: - Properties
    
    /// Logger for monitoring operations
    private let logger: Logger
    
    /// Queue for monitoring operations
    private let queue: DispatchQueue
    
    /// Configuration for monitoring behavior
    private let config: StatusMonitorConfig
    
    /// Current monitoring state
    private var isActive = false
    
    /// Health check timer for periodic monitoring
    private var healthCheckTimer: DispatchSourceTimer?
    
    /// Resource monitoring timer
    private var resourceMonitorTimer: DispatchSourceTimer?
    
    /// Health check delegate for notifications
    public weak var healthDelegate: HealthCheckDelegate?
    
    /// Current system status cache
    private var cachedSystemStatus: SystemStatus?
    
    /// Health metrics tracking
    private var healthMetrics: HealthMetrics
    
    /// System resource monitor
    private let resourceMonitor: SystemResourceMonitor
    
    /// Process monitor for System Extension health
    private let processMonitor: ProcessHealthMonitor
    
    /// Device health tracker
    private let deviceHealthTracker: DeviceHealthTracker
    
    // MARK: - Initialization
    
    /// Initialize with default configuration
    public convenience init() {
        let logger = Logger(
            config: LoggerConfig(level: .info),
            subsystem: "com.usbipd.mac.system-extension",
            category: "status-monitor"
        )
        
        self.init(
            config: StatusMonitorConfig(),
            logger: logger
        )
    }
    
    /// Initialize with custom configuration
    /// - Parameters:
    ///   - config: Monitoring configuration
    ///   - logger: Logger instance
    public init(config: StatusMonitorConfig, logger: Logger) {
        self.config = config
        self.logger = logger
        self.queue = DispatchQueue(
            label: "com.usbipd.mac.system-extension.status-monitor",
            qos: .utility
        )
        self.healthMetrics = HealthMetrics()
        self.resourceMonitor = SystemResourceMonitor(logger: logger)
        self.processMonitor = ProcessHealthMonitor(logger: logger)
        self.deviceHealthTracker = DeviceHealthTracker(logger: logger)
        
        logger.info("ComprehensiveStatusMonitor initialized", context: [
            "healthCheckInterval": config.healthCheckInterval,
            "resourceMonitorInterval": config.resourceMonitorInterval,
            "alertThresholds": config.alertThresholds.description
        ])
    }
    
    deinit {
        stopMonitoring()
        logger.info("ComprehensiveStatusMonitor deinitialized")
    }
    
    // MARK: - StatusMonitor Protocol Implementation
    
    public func startMonitoring() throws {
        try queue.sync {
            guard !isActive else {
                logger.warning("Status monitoring already active")
                return
            }
            
            logger.info("Starting comprehensive status monitoring")
            
            do {
                // Start resource monitoring
                try resourceMonitor.startMonitoring()
                
                // Start process health monitoring
                try processMonitor.startMonitoring()
                
                // Start device health tracking
                try deviceHealthTracker.startTracking()
                
                // Set up periodic health checks
                try setupHealthCheckTimer()
                
                // Set up resource monitoring timer
                try setupResourceMonitorTimer()
                
                isActive = true
                healthMetrics.monitoringStartTime = Date()
                
                // Perform initial health check
                let initialHealth = performHealthCheck()
                logger.info("Initial health check completed", context: [
                    "status": initialHealth.status.rawValue,
                    "score": initialHealth.overallScore
                ])
                
                logger.info("Status monitoring started successfully")
                
            } catch {
                logger.error("Failed to start status monitoring", context: [
                    "error": error.localizedDescription
                ])
                // Cleanup on failure
                try? cleanupMonitoring()
                throw SystemExtensionError.internalError("Status monitoring startup failed: \(error.localizedDescription)")
            }
        }
    }
    
    public func stopMonitoring() {
        queue.sync {
            guard isActive else {
                logger.debug("Status monitoring not active")
                return
            }
            
            logger.info("Stopping status monitoring")
            
            // Stop timers
            healthCheckTimer?.cancel()
            healthCheckTimer = nil
            
            resourceMonitorTimer?.cancel()
            resourceMonitorTimer = nil
            
            // Stop component monitors
            resourceMonitor.stopMonitoring()
            processMonitor.stopMonitoring()
            deviceHealthTracker.stopTracking()
            
            isActive = false
            healthMetrics.monitoringStopTime = Date()
            
            logger.info("Status monitoring stopped", context: [
                "totalUptime": String(format: "%.2f", healthMetrics.monitoringUptime),
                "totalHealthChecks": healthMetrics.totalHealthChecks
            ])
        }
    }
    
    public func isMonitoring() -> Bool {
        return queue.sync {
            return isActive
        }
    }
    
    public func performHealthCheck() -> HealthCheckResult {
        return queue.sync {
            let startTime = Date()
            healthMetrics.totalHealthChecks += 1
            
            logger.debug("Performing comprehensive health check")
            
            // Collect health data from all components
            let resourceHealth = resourceMonitor.getHealthStatus()
            let processHealth = processMonitor.getHealthStatus()
            let deviceHealth = deviceHealthTracker.getHealthStatus()
            
            // Calculate overall health score
            let overallScore = calculateOverallHealthScore(
                resourceHealth: resourceHealth,
                processHealth: processHealth,
                deviceHealth: deviceHealth
            )
            
            // Determine health status
            let status = determineHealthStatus(score: overallScore)
            
            // Create comprehensive health result
            let result = HealthCheckResult(
                timestamp: Date(),
                status: status,
                overallScore: overallScore,
                resourceHealth: resourceHealth,
                processHealth: processHealth,
                deviceHealth: deviceHealth,
                checkDuration: Date().timeIntervalSince(startTime) * 1000 // milliseconds
            )
            
            // Update metrics
            healthMetrics.lastHealthCheck = result.timestamp
            healthMetrics.lastHealthScore = overallScore
            
            if status == .healthy {
                healthMetrics.healthyChecks += 1
            } else if status == .critical {
                healthMetrics.criticalChecks += 1
            }
            
            // Notify delegate if health status changed significantly
            notifyHealthDelegate(result: result)
            
            // Update cached system status
            updateCachedSystemStatus(healthResult: result)
            
            logger.debug("Health check completed", context: [
                "status": status.rawValue,
                "score": String(format: "%.2f", overallScore),
                "duration": String(format: "%.2f", result.checkDuration)
            ])
            
            return result
        }
    }
    
    public func getSystemStatus() -> SystemStatus {
        return queue.sync {
            if let cached = cachedSystemStatus, 
               Date().timeIntervalSince(cached.timestamp) < config.statusCacheTimeout {
                return cached
            }
            
            // Generate fresh system status
            let healthResult = performHealthCheck()
            let systemInfo = collectSystemInformation()
            let networkStatus = collectNetworkStatus()
            
            let status = SystemStatus(
                timestamp: Date(),
                healthResult: healthResult,
                systemInfo: systemInfo,
                networkStatus: networkStatus,
                metrics: healthMetrics
            )
            
            cachedSystemStatus = status
            return status
        }
    }
    
    public func getHealthMetrics() -> HealthMetrics {
        return queue.sync {
            return healthMetrics
        }
    }
    
    public func setHealthDelegate(_ delegate: HealthCheckDelegate?) {
        queue.sync {
            healthDelegate = delegate
        }
    }
    
    // MARK: - Private Implementation
    
    private func setupHealthCheckTimer() throws {
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
    
    private func setupResourceMonitorTimer() throws {
        guard config.resourceMonitorInterval > 0 else { return }
        
        resourceMonitorTimer = DispatchSource.makeTimerSource(queue: queue)
        resourceMonitorTimer?.schedule(
            deadline: .now() + .seconds(Int(config.resourceMonitorInterval)),
            repeating: .seconds(Int(config.resourceMonitorInterval))
        )
        
        resourceMonitorTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.updateResourceMetrics()
        }
        
        resourceMonitorTimer?.resume()
        
        logger.debug("Resource monitor timer started", context: [
            "interval": config.resourceMonitorInterval
        ])
    }
    
    private func calculateOverallHealthScore(
        resourceHealth: ResourceHealthStatus,
        processHealth: ProcessHealthStatus, 
        deviceHealth: DeviceHealthStatus
    ) -> Double {
        // Weighted health score calculation
        let resourceWeight = 0.4
        let processWeight = 0.4
        let deviceWeight = 0.2
        
        let resourceScore = resourceHealth.healthScore
        let processScore = processHealth.healthScore
        let deviceScore = deviceHealth.healthScore
        
        return (resourceScore * resourceWeight) + 
               (processScore * processWeight) + 
               (deviceScore * deviceWeight)
    }
    
    private func determineHealthStatus(score: Double) -> HealthStatus {
        if score >= config.alertThresholds.healthyThreshold {
            return .healthy
        } else if score >= config.alertThresholds.warningThreshold {
            return .warning
        } else {
            return .critical
        }
    }
    
    private func notifyHealthDelegate(result: HealthCheckResult) {
        // Only notify on significant changes or critical status
        let shouldNotify = result.status == .critical || 
                          healthMetrics.lastHealthStatus != result.status
        
        if shouldNotify {
            healthDelegate?.healthCheckCompleted(result: result)
            healthMetrics.lastHealthStatus = result.status
        }
    }
    
    private func updateCachedSystemStatus(healthResult: HealthCheckResult) {
        // Update cached status with latest health information
        if cachedSystemStatus == nil {
            cachedSystemStatus = SystemStatus(
                timestamp: Date(),
                healthResult: healthResult,
                systemInfo: SystemInformation(),
                networkStatus: NetworkStatus(),
                metrics: healthMetrics
            )
        } else {
            cachedSystemStatus?.timestamp = Date()
            cachedSystemStatus?.healthResult = healthResult
            cachedSystemStatus?.metrics = healthMetrics
        }
    }
    
    private func updateResourceMetrics() {
        let resourceStatus = resourceMonitor.getHealthStatus()
        
        // Update metrics with current resource usage
        healthMetrics.currentMemoryUsage = resourceStatus.memoryUsage
        healthMetrics.currentCPUUsage = resourceStatus.cpuUsage
        healthMetrics.peakMemoryUsage = max(healthMetrics.peakMemoryUsage, resourceStatus.memoryUsage)
        healthMetrics.peakCPUUsage = max(healthMetrics.peakCPUUsage, resourceStatus.cpuUsage)
    }
    
    private func collectSystemInformation() -> SystemInformation {
        return SystemInformation(
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            processUptime: processMonitor.getUptime(),
            totalMemory: resourceMonitor.getTotalMemory(),
            availableMemory: resourceMonitor.getAvailableMemory(),
            loadAverage: resourceMonitor.getLoadAverage()
        )
    }
    
    private func collectNetworkStatus() -> NetworkStatus {
        return NetworkStatus(
            activeConnections: 0, // Would be provided by IPCHandler
            totalDataTransferred: 0, // Would be tracked by network layer
            networkLatency: 0.0 // Would be measured by network tests
        )
    }
    
    private func cleanupMonitoring() throws {
        healthCheckTimer?.cancel()
        resourceMonitorTimer?.cancel()
        resourceMonitor.stopMonitoring()
        processMonitor.stopMonitoring()
        deviceHealthTracker.stopTracking()
        isActive = false
    }
}

// MARK: - Configuration

/// Configuration for status monitoring behavior
public struct StatusMonitorConfig {
    /// Health check interval in seconds (0 to disable)
    public let healthCheckInterval: TimeInterval
    
    /// Resource monitoring interval in seconds (0 to disable)  
    public let resourceMonitorInterval: TimeInterval
    
    /// Status cache timeout in seconds
    public let statusCacheTimeout: TimeInterval
    
    /// Alert thresholds for health scoring
    public let alertThresholds: AlertThresholds
    
    public init(
        healthCheckInterval: TimeInterval = 30.0,
        resourceMonitorInterval: TimeInterval = 10.0,
        statusCacheTimeout: TimeInterval = 5.0,
        alertThresholds: AlertThresholds = AlertThresholds()
    ) {
        self.healthCheckInterval = healthCheckInterval
        self.resourceMonitorInterval = resourceMonitorInterval  
        self.statusCacheTimeout = statusCacheTimeout
        self.alertThresholds = alertThresholds
    }
}

/// Health alert thresholds
public struct AlertThresholds {
    /// Minimum score for healthy status (0.0-1.0)
    public let healthyThreshold: Double
    
    /// Minimum score for warning status (0.0-1.0)
    public let warningThreshold: Double
    
    /// Memory usage threshold for alerts (MB)
    public let memoryThreshold: Double
    
    /// CPU usage threshold for alerts (0.0-1.0)
    public let cpuThreshold: Double
    
    public init(
        healthyThreshold: Double = 0.8,
        warningThreshold: Double = 0.6,
        memoryThreshold: Double = 512.0, // 512MB
        cpuThreshold: Double = 0.8 // 80%
    ) {
        self.healthyThreshold = healthyThreshold
        self.warningThreshold = warningThreshold
        self.memoryThreshold = memoryThreshold
        self.cpuThreshold = cpuThreshold
    }
    
    public var description: String {
        return "healthy>=\(healthyThreshold), warning>=\(warningThreshold), memory<\(memoryThreshold)MB, cpu<\(cpuThreshold*100)%"
    }
}

// MARK: - Health Check Delegate

/// Delegate protocol for health check notifications
public protocol HealthCheckDelegate: AnyObject {
    /// Called when a health check completes with significant changes
    /// - Parameter result: Health check result
    func healthCheckCompleted(result: HealthCheckResult)
    
    /// Called when health status reaches critical level
    /// - Parameter status: Critical health status details
    func healthStatusCritical(status: HealthCheckResult)
    
    /// Called when system recovers from critical status
    /// - Parameter status: Recovery health status details
    func healthStatusRecovered(status: HealthCheckResult)
}

// MARK: - Default Implementation (Legacy Support)

/// Default status monitor implementation for backward compatibility
public class DefaultStatusMonitor: StatusMonitor {
    private let comprehensiveMonitor: ComprehensiveStatusMonitor
    
    public init() {
        self.comprehensiveMonitor = ComprehensiveStatusMonitor()
    }
    
    public func startMonitoring() throws {
        try comprehensiveMonitor.startMonitoring()
    }
    
    public func stopMonitoring() {
        comprehensiveMonitor.stopMonitoring()
    }
    
    public func isMonitoring() -> Bool {
        return comprehensiveMonitor.isMonitoring()
    }
    
    public func performHealthCheck() -> HealthCheckResult {
        return comprehensiveMonitor.performHealthCheck()
    }
    
    public func getSystemStatus() -> SystemStatus {
        return comprehensiveMonitor.getSystemStatus()
    }
    
    public func getHealthMetrics() -> HealthMetrics {
        return comprehensiveMonitor.getHealthMetrics()
    }
    
    public func setHealthDelegate(_ delegate: HealthCheckDelegate?) {
        comprehensiveMonitor.setHealthDelegate(delegate)
    }
}