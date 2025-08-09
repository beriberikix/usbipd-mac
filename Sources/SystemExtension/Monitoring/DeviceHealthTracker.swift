// DeviceHealthTracker.swift
// Device operation health tracking for System Extension

import Foundation
import Common
import USBIPDCore

/// Track device operation health and performance
public class DeviceHealthTracker {
    
    // MARK: - Properties
    
    /// Logger for device health tracking
    private let logger: Logger
    
    /// Queue for tracking operations
    private let queue: DispatchQueue
    
    /// Whether tracking is active
    private var isActive = false
    
    /// Device operation history
    private var operationHistory: [DeviceOperation] = []
    private let maxHistorySize = 100
    
    /// Device failure tracking
    private var deviceFailures: [String: DeviceFailureRecord] = [:]
    
    /// Operation timing tracking
    private var operationTimings: [String: [TimeInterval]] = [:]
    private let maxTimingHistory = 20
    
    /// Last successful operation timestamp
    private var lastSuccessfulOperation: Date?
    
    // MARK: - Initialization
    
    public init(logger: Logger) {
        self.logger = logger
        self.queue = DispatchQueue(
            label: "com.usbipd.mac.system-extension.device-health",
            qos: .utility
        )
    }
    
    // MARK: - Public Methods
    
    /// Start device health tracking
    public func startTracking() throws {
        queue.sync {
            guard !isActive else {
                logger.debug("Device health tracking already active")
                return
            }
            
            logger.debug("Starting device health tracking")
            isActive = true
        }
    }
    
    /// Stop device health tracking
    public func stopTracking() {
        queue.sync {
            guard isActive else {
                logger.debug("Device health tracking not active")
                return
            }
            
            logger.debug("Stopping device health tracking")
            isActive = false
            
            // Clear tracking data
            operationHistory.removeAll()
            deviceFailures.removeAll()
            operationTimings.removeAll()
        }
    }
    
    /// Record a device operation
    public func recordOperation(_ operation: DeviceOperation) {
        queue.async { [weak self] in
            guard let self = self, self.isActive else { return }
            
            self.addOperationToHistory(operation)
            self.updateOperationTimings(operation)
            self.updateFailureTracking(operation)
            
            if operation.success {
                self.lastSuccessfulOperation = operation.timestamp
            }
            
            self.logger.debug("Device operation recorded", context: [
                "deviceID": operation.deviceID,
                "type": operation.type.rawValue,
                "success": operation.success,
                "duration": String(format: "%.2f", operation.duration)
            ])
        }
    }
    
    /// Get current device health status
    public func getHealthStatus() -> DeviceHealthStatus {
        return queue.sync {
            guard isActive else {
                return DeviceHealthStatus(
                    claimedDevices: 0,
                    failedOperations: 0,
                    averageOperationTime: 0.0,
                    healthScore: 0.0
                )
            }
            
            return calculateDeviceHealth()
        }
    }
    
    /// Get device-specific health information
    public func getDeviceHealth(deviceID: String) -> DeviceSpecificHealth {
        return queue.sync {
            let deviceOperations = operationHistory.filter { $0.deviceID == deviceID }
            let failureRecord = deviceFailures[deviceID]
            let timings = operationTimings[deviceID] ?? []
            
            return DeviceSpecificHealth(
                deviceID: deviceID,
                totalOperations: deviceOperations.count,
                successfulOperations: deviceOperations.filter { $0.success }.count,
                failedOperations: deviceOperations.filter { !$0.success }.count,
                averageOperationTime: timings.isEmpty ? 0.0 : timings.reduce(0, +) / Double(timings.count),
                lastOperation: deviceOperations.last,
                failureRecord: failureRecord
            )
        }
    }
    
    /// Get currently claimed devices (would be provided by DeviceClaimer in real implementation)
    public func getClaimedDevicesCount() -> Int {
        return queue.sync {
            // In a real implementation, this would query the DeviceClaimer
            // For now, return estimated count based on recent successful claims
            let recentClaims = operationHistory
                .filter { $0.type == .claim && $0.success }
                .filter { Date().timeIntervalSince($0.timestamp) < 300 } // Last 5 minutes
            
            return Set(recentClaims.map { $0.deviceID }).count
        }
    }
    
    // MARK: - Private Implementation
    
    private func addOperationToHistory(_ operation: DeviceOperation) {
        operationHistory.append(operation)
        
        // Maintain history size limit
        if operationHistory.count > maxHistorySize {
            operationHistory.removeFirst(operationHistory.count - maxHistorySize)
        }
    }
    
    private func updateOperationTimings(_ operation: DeviceOperation) {
        let key = "\(operation.type.rawValue)-\(operation.deviceID)"
        
        if operationTimings[key] == nil {
            operationTimings[key] = []
        }
        
        operationTimings[key]?.append(operation.duration)
        
        // Maintain timing history limit
        if let count = operationTimings[key]?.count, count > maxTimingHistory {
            operationTimings[key]?.removeFirst(count - maxTimingHistory)
        }
    }
    
    private func updateFailureTracking(_ operation: DeviceOperation) {
        if !operation.success {
            if deviceFailures[operation.deviceID] == nil {
                deviceFailures[operation.deviceID] = DeviceFailureRecord(deviceID: operation.deviceID)
            }
            
            deviceFailures[operation.deviceID]?.recordFailure(
                type: operation.type,
                error: operation.error,
                timestamp: operation.timestamp
            )
        }
    }
    
    private func calculateDeviceHealth() -> DeviceHealthStatus {
        var issues: [DeviceIssue] = []
        
        let claimedDevicesCount = getClaimedDevicesCount()
        let totalOperations = operationHistory.count
        let failedOperations = operationHistory.filter { !$0.success }.count
        
        // Calculate average operation time
        let allTimings = operationTimings.values.flatMap { $0 }
        let averageOperationTime = allTimings.isEmpty ? 0.0 : allTimings.reduce(0, +) / Double(allTimings.count) * 1000 // Convert to milliseconds
        
        // Check for excessive failures
        let failureRate = totalOperations > 0 ? Double(failedOperations) / Double(totalOperations) : 0.0
        
        if failureRate > 0.5 {
            issues.append(DeviceIssue(
                type: .claimFailure,
                severity: .critical,
                description: "High device operation failure rate: \(String(format: "%.1f", failureRate * 100))%"
            ))
        } else if failureRate > 0.2 {
            issues.append(DeviceIssue(
                type: .claimFailure,
                severity: .warning,
                description: "Elevated device operation failure rate: \(String(format: "%.1f", failureRate * 100))%"
            ))
        }
        
        // Check for slow operations
        if averageOperationTime > 5000 { // 5 seconds
            issues.append(DeviceIssue(
                type: .timeoutError,
                severity: .warning,
                description: "Slow device operations: \(String(format: "%.0f", averageOperationTime))ms average"
            ))
        }
        
        // Check for devices with repeated failures
        for (deviceID, failureRecord) in deviceFailures where failureRecord.consecutiveFailures > 3 {
            issues.append(DeviceIssue(
                type: .communicationError,
                severity: .critical,
                description: "Device experiencing repeated failures",
                deviceID: deviceID
            ))
        }
        
        // Check for stale operations (no successful operations recently)
        let timeSinceLastSuccess = lastSuccessfulOperation.map { Date().timeIntervalSince($0) } ?? TimeInterval.greatestFiniteMagnitude
        
        if timeSinceLastSuccess > 600 && totalOperations > 0 { // 10 minutes
            issues.append(DeviceIssue(
                type: .communicationError,
                severity: .warning,
                description: "No successful device operations in \(Int(timeSinceLastSuccess / 60)) minutes"
            ))
        }
        
        // Calculate health score
        let healthScore = calculateDeviceHealthScore(
            failureRate: failureRate,
            averageOperationTime: averageOperationTime,
            timeSinceLastSuccess: timeSinceLastSuccess,
            issueCount: issues.count
        )
        
        return DeviceHealthStatus(
            claimedDevices: claimedDevicesCount,
            failedOperations: failedOperations,
            averageOperationTime: averageOperationTime,
            healthScore: healthScore,
            issues: issues,
            lastSuccessfulOperation: lastSuccessfulOperation
        )
    }
    
    private func calculateDeviceHealthScore(
        failureRate: Double,
        averageOperationTime: Double,
        timeSinceLastSuccess: TimeInterval,
        issueCount: Int
    ) -> Double {
        var score = 1.0
        
        // Failure rate impact
        if failureRate > 0.5 {
            score *= 0.0 // Critical failure rate
        } else if failureRate > 0.3 {
            score *= 0.4
        } else if failureRate > 0.1 {
            score *= 0.7
        } else if failureRate > 0.05 {
            score *= 0.9
        }
        
        // Operation timing impact
        if averageOperationTime > 10000 { // 10 seconds
            score *= 0.3
        } else if averageOperationTime > 5000 { // 5 seconds
            score *= 0.6
        } else if averageOperationTime > 2000 { // 2 seconds
            score *= 0.8
        }
        
        // Recency impact
        if timeSinceLastSuccess > 1800 { // 30 minutes
            score *= 0.2
        } else if timeSinceLastSuccess > 600 { // 10 minutes
            score *= 0.6
        } else if timeSinceLastSuccess > 300 { // 5 minutes
            score *= 0.8
        }
        
        // Issue count impact
        if issueCount > 3 {
            score *= 0.4
        } else if issueCount > 1 {
            score *= 0.7
        }
        
        return max(score, 0.0)
    }
}

// MARK: - Supporting Types

/// Device operation record
public struct DeviceOperation: Codable {
    public let deviceID: String
    public let type: DeviceOperationType
    public let timestamp: Date
    public let duration: TimeInterval
    public let success: Bool
    public let error: String?
    
    public init(
        deviceID: String,
        type: DeviceOperationType,
        timestamp: Date = Date(),
        duration: TimeInterval,
        success: Bool,
        error: String? = nil
    ) {
        self.deviceID = deviceID
        self.type = type
        self.timestamp = timestamp
        self.duration = duration
        self.success = success
        self.error = error
    }
}

/// Device operation types
public enum DeviceOperationType: String, Codable, CaseIterable {
    case claim = "claim"
    case release = "release"
    case query = "query"
    case healthCheck = "health_check"
}

/// Device failure record
public class DeviceFailureRecord {
    public let deviceID: String
    public private(set) var totalFailures: Int = 0
    public private(set) var consecutiveFailures: Int = 0
    public private(set) var lastFailureTime: Date?
    public private(set) var failureTypes: [DeviceOperationType: Int] = [:]
    public private(set) var recentErrors: [String] = []
    
    private let maxRecentErrors = 5
    
    public init(deviceID: String) {
        self.deviceID = deviceID
    }
    
    public func recordFailure(type: DeviceOperationType, error: String?, timestamp: Date) {
        totalFailures += 1
        consecutiveFailures += 1
        lastFailureTime = timestamp
        failureTypes[type, default: 0] += 1
        
        if let error = error {
            recentErrors.append(error)
            if recentErrors.count > maxRecentErrors {
                recentErrors.removeFirst()
            }
        }
    }
    
    public func recordSuccess() {
        consecutiveFailures = 0
    }
}

/// Device-specific health information
public struct DeviceSpecificHealth {
    public let deviceID: String
    public let totalOperations: Int
    public let successfulOperations: Int
    public let failedOperations: Int
    public let averageOperationTime: Double
    public let lastOperation: DeviceOperation?
    public let failureRecord: DeviceFailureRecord?
    
    public var successRate: Double {
        return totalOperations > 0 ? Double(successfulOperations) / Double(totalOperations) : 0.0
    }
    
    public init(
        deviceID: String,
        totalOperations: Int,
        successfulOperations: Int,
        failedOperations: Int,
        averageOperationTime: Double,
        lastOperation: DeviceOperation?,
        failureRecord: DeviceFailureRecord?
    ) {
        self.deviceID = deviceID
        self.totalOperations = totalOperations
        self.successfulOperations = successfulOperations
        self.failedOperations = failedOperations
        self.averageOperationTime = averageOperationTime
        self.lastOperation = lastOperation
        self.failureRecord = failureRecord
    }
}