// HealthTypes.swift
// Health monitoring data structures and types

import Foundation

// MARK: - Health Check Results

/// Overall health status levels
public enum HealthStatus: String, CaseIterable, Codable {
    case healthy = "healthy"
    case warning = "warning"
    case critical = "critical"
    case unknown = "unknown"
    
    public var color: String {
        switch self {
        case .healthy: return "green"
        case .warning: return "yellow"
        case .critical: return "red"
        case .unknown: return "gray"
        }
    }
    
    public var priority: Int {
        switch self {
        case .healthy: return 0
        case .warning: return 1
        case .critical: return 2
        case .unknown: return 3
        }
    }
}

/// Comprehensive health check result
public struct HealthCheckResult: Codable {
    /// Timestamp when health check was performed
    public let timestamp: Date
    
    /// Overall health status
    public let status: HealthStatus
    
    /// Overall health score (0.0 - 1.0)
    public let overallScore: Double
    
    /// Resource health information
    public let resourceHealth: ResourceHealthStatus
    
    /// Process health information
    public let processHealth: ProcessHealthStatus
    
    /// Device health information
    public let deviceHealth: DeviceHealthStatus
    
    /// Duration of health check in milliseconds
    public let checkDuration: Double
    
    public init(
        timestamp: Date,
        status: HealthStatus,
        overallScore: Double,
        resourceHealth: ResourceHealthStatus,
        processHealth: ProcessHealthStatus,
        deviceHealth: DeviceHealthStatus,
        checkDuration: Double
    ) {
        self.timestamp = timestamp
        self.status = status
        self.overallScore = overallScore
        self.resourceHealth = resourceHealth
        self.processHealth = processHealth
        self.deviceHealth = deviceHealth
        self.checkDuration = checkDuration
    }
}

// MARK: - Resource Health

/// Resource health status information
public struct ResourceHealthStatus: Codable {
    /// Memory usage in MB
    public let memoryUsage: Double
    
    /// Memory usage as percentage of total
    public let memoryUsagePercent: Double
    
    /// CPU usage as percentage (0.0 - 1.0)
    public let cpuUsage: Double
    
    /// System load average (1 minute)
    public let loadAverage: Double
    
    /// Available disk space in GB
    public let availableDiskSpace: Double
    
    /// Number of open file descriptors
    public let openFileDescriptors: Int
    
    /// Overall resource health score (0.0 - 1.0)
    public let healthScore: Double
    
    /// Resource-specific issues identified
    public let issues: [ResourceIssue]
    
    public init(
        memoryUsage: Double,
        memoryUsagePercent: Double,
        cpuUsage: Double,
        loadAverage: Double,
        availableDiskSpace: Double,
        openFileDescriptors: Int,
        healthScore: Double,
        issues: [ResourceIssue] = []
    ) {
        self.memoryUsage = memoryUsage
        self.memoryUsagePercent = memoryUsagePercent
        self.cpuUsage = cpuUsage
        self.loadAverage = loadAverage
        self.availableDiskSpace = availableDiskSpace
        self.openFileDescriptors = openFileDescriptors
        self.healthScore = healthScore
        self.issues = issues
    }
}

/// Resource-specific issue
public struct ResourceIssue: Codable {
    public let type: ResourceIssueType
    public let severity: IssueSeverity
    public let description: String
    public let value: Double
    public let threshold: Double
    
    public init(
        type: ResourceIssueType,
        severity: IssueSeverity,
        description: String,
        value: Double,
        threshold: Double
    ) {
        self.type = type
        self.severity = severity
        self.description = description
        self.value = value
        self.threshold = threshold
    }
}

public enum ResourceIssueType: String, Codable, CaseIterable {
    case memoryUsage = "memory_usage"
    case cpuUsage = "cpu_usage"
    case diskSpace = "disk_space"
    case fileDescriptors = "file_descriptors"
    case loadAverage = "load_average"
}

public enum IssueSeverity: String, Codable, CaseIterable {
    case info = "info"
    case warning = "warning"
    case critical = "critical"
    
    public var priority: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }
}

// MARK: - Process Health

/// Process health status information
public struct ProcessHealthStatus: Codable {
    /// Process uptime in seconds
    public let uptime: TimeInterval
    
    /// Process ID
    public let processID: Int32
    
    /// Thread count
    public let threadCount: Int
    
    /// Memory mapped regions count
    public let mappedRegions: Int
    
    /// Process health score (0.0 - 1.0)
    public let healthScore: Double
    
    /// Process-specific issues
    public let issues: [ProcessIssue]
    
    /// Whether process is responsive
    public let isResponsive: Bool
    
    /// Last response check time
    public let lastResponseTime: Date
    
    public init(
        uptime: TimeInterval,
        processID: Int32,
        threadCount: Int,
        mappedRegions: Int,
        healthScore: Double,
        issues: [ProcessIssue] = [],
        isResponsive: Bool = true,
        lastResponseTime: Date = Date()
    ) {
        self.uptime = uptime
        self.processID = processID
        self.threadCount = threadCount
        self.mappedRegions = mappedRegions
        self.healthScore = healthScore
        self.issues = issues
        self.isResponsive = isResponsive
        self.lastResponseTime = lastResponseTime
    }
}

/// Process-specific issue
public struct ProcessIssue: Codable {
    public let type: ProcessIssueType
    public let severity: IssueSeverity
    public let description: String
    
    public init(type: ProcessIssueType, severity: IssueSeverity, description: String) {
        self.type = type
        self.severity = severity
        self.description = description
    }
}

public enum ProcessIssueType: String, Codable, CaseIterable {
    case unresponsive = "unresponsive"
    case highThreadCount = "high_thread_count"
    case memoryLeak = "memory_leak"
    case highMappedRegions = "high_mapped_regions"
}

// MARK: - Device Health

/// Device health status information
public struct DeviceHealthStatus: Codable {
    /// Number of claimed devices
    public let claimedDevices: Int
    
    /// Number of failed device operations
    public let failedOperations: Int
    
    /// Average device operation time in milliseconds
    public let averageOperationTime: Double
    
    /// Device health score (0.0 - 1.0)
    public let healthScore: Double
    
    /// Device-specific issues
    public let issues: [DeviceIssue]
    
    /// Last successful device operation time
    public let lastSuccessfulOperation: Date?
    
    public init(
        claimedDevices: Int,
        failedOperations: Int,
        averageOperationTime: Double,
        healthScore: Double,
        issues: [DeviceIssue] = [],
        lastSuccessfulOperation: Date? = nil
    ) {
        self.claimedDevices = claimedDevices
        self.failedOperations = failedOperations
        self.averageOperationTime = averageOperationTime
        self.healthScore = healthScore
        self.issues = issues
        self.lastSuccessfulOperation = lastSuccessfulOperation
    }
}

/// Device-specific issue
public struct DeviceIssue: Codable {
    public let type: DeviceIssueType
    public let severity: IssueSeverity
    public let description: String
    public let deviceID: String?
    
    public init(
        type: DeviceIssueType,
        severity: IssueSeverity,
        description: String,
        deviceID: String? = nil
    ) {
        self.type = type
        self.severity = severity
        self.description = description
        self.deviceID = deviceID
    }
}

public enum DeviceIssueType: String, Codable, CaseIterable {
    case claimFailure = "claim_failure"
    case releaseFailure = "release_failure"
    case communicationError = "communication_error"
    case timeoutError = "timeout_error"
}

// MARK: - System Status

/// Comprehensive system status information
public struct SystemStatus: Codable {
    /// Status timestamp
    public var timestamp: Date
    
    /// Current health check result
    public var healthResult: HealthCheckResult
    
    /// System information
    public var systemInfo: SystemInformation
    
    /// Network status
    public var networkStatus: NetworkStatus
    
    /// Health metrics
    public var metrics: HealthMetrics
    
    public init(
        timestamp: Date,
        healthResult: HealthCheckResult,
        systemInfo: SystemInformation,
        networkStatus: NetworkStatus,
        metrics: HealthMetrics
    ) {
        self.timestamp = timestamp
        self.healthResult = healthResult
        self.systemInfo = systemInfo
        self.networkStatus = networkStatus
        self.metrics = metrics
    }
}

/// System information
public struct SystemInformation: Codable {
    /// Operating system version
    public let systemVersion: String
    
    /// Process uptime in seconds
    public let processUptime: TimeInterval
    
    /// Total system memory in bytes
    public let totalMemory: UInt64
    
    /// Available system memory in bytes
    public let availableMemory: UInt64
    
    /// System load average
    public let loadAverage: Double
    
    public init(
        systemVersion: String = "Unknown",
        processUptime: TimeInterval = 0,
        totalMemory: UInt64 = 0,
        availableMemory: UInt64 = 0,
        loadAverage: Double = 0.0
    ) {
        self.systemVersion = systemVersion
        self.processUptime = processUptime
        self.totalMemory = totalMemory
        self.availableMemory = availableMemory
        self.loadAverage = loadAverage
    }
}

/// Network status information
public struct NetworkStatus: Codable {
    /// Number of active network connections
    public let activeConnections: Int
    
    /// Total data transferred in bytes
    public let totalDataTransferred: UInt64
    
    /// Network latency in milliseconds
    public let networkLatency: Double
    
    public init(
        activeConnections: Int = 0,
        totalDataTransferred: UInt64 = 0,
        networkLatency: Double = 0.0
    ) {
        self.activeConnections = activeConnections
        self.totalDataTransferred = totalDataTransferred
        self.networkLatency = networkLatency
    }
}

// MARK: - Health Metrics

/// Health metrics tracking over time
public struct HealthMetrics: Codable {
    /// When monitoring started
    public var monitoringStartTime: Date?
    
    /// When monitoring stopped
    public var monitoringStopTime: Date?
    
    /// Total number of health checks performed
    public var totalHealthChecks: Int = 0
    
    /// Number of healthy check results
    public var healthyChecks: Int = 0
    
    /// Number of critical check results
    public var criticalChecks: Int = 0
    
    /// Last health check timestamp
    public var lastHealthCheck: Date?
    
    /// Last health check score
    public var lastHealthScore: Double = 0.0
    
    /// Last health status
    public var lastHealthStatus: HealthStatus = .unknown
    
    /// Current memory usage in MB
    public var currentMemoryUsage: Double = 0.0
    
    /// Peak memory usage in MB
    public var peakMemoryUsage: Double = 0.0
    
    /// Current CPU usage (0.0 - 1.0)
    public var currentCPUUsage: Double = 0.0
    
    /// Peak CPU usage (0.0 - 1.0) 
    public var peakCPUUsage: Double = 0.0
    
    public init() {}
    
    /// Get monitoring uptime in seconds
    public var monitoringUptime: TimeInterval {
        guard let startTime = monitoringStartTime else { return 0 }
        let endTime = monitoringStopTime ?? Date()
        return endTime.timeIntervalSince(startTime)
    }
    
    /// Get health check success rate as percentage
    public var healthCheckSuccessRate: Double {
        guard totalHealthChecks > 0 else { return 0.0 }
        return Double(healthyChecks) / Double(totalHealthChecks) * 100.0
    }
    
    /// Get average health score
    public var averageHealthScore: Double {
        // This would be calculated from historical data in a real implementation
        return lastHealthScore
    }
}