// MockStatusMonitor.swift
// Mock implementation of StatusMonitor for testing System Extension health monitoring

import Foundation
import Common
@testable import SystemExtension

// MARK: - Mock Status Monitor

/// Mock implementation of StatusMonitor protocol for testing health monitoring
/// without requiring actual system resource access
public class MockStatusMonitor: StatusMonitor {
    
    // MARK: - Mock Configuration
    
    /// Whether operations should succeed
    public var shouldSucceed = true
    
    /// Error to throw when operations fail
    public var startError: Error?
    
    // MARK: - Mock State
    
    /// Whether monitoring is currently active
    public var isMonitoringValue = false
    
    /// Track method calls for verification
    public var startMonitoringCalled = false
    public var stopMonitoringCalled = false
    public var performHealthCheckCalled = false
    public var getSystemStatusCalled = false
    public var getHealthMetricsCalled = false
    
    /// Mock health check results
    public var healthCheckResults: [HealthCheckResult] = []
    public var healthCheckIndex = 0
    
    /// Mock system status
    public var mockSystemStatus: SystemStatus?
    
    /// Mock health metrics
    public var mockHealthMetrics = HealthMetrics()
    
    /// Health delegate
    public weak var healthDelegate: HealthCheckDelegate?
    
    /// Track health check calls
    public var healthCheckCount = 0
    
    // MARK: - StatusMonitor Protocol Implementation
    
    public func startMonitoring() throws {
        startMonitoringCalled = true
        
        if !shouldSucceed, let error = startError {
            throw error
        }
        
        isMonitoringValue = true
        mockHealthMetrics.monitoringStartTime = Date()
    }
    
    public func stopMonitoring() {
        stopMonitoringCalled = true
        isMonitoringValue = false
        mockHealthMetrics.monitoringStopTime = Date()
    }
    
    public func isMonitoring() -> Bool {
        return isMonitoringValue
    }
    
    public func performHealthCheck() -> HealthCheckResult {
        performHealthCheckCalled = true
        healthCheckCount += 1
        mockHealthMetrics.totalHealthChecks += 1
        
        // Return configured result or create default
        let result: HealthCheckResult
        if healthCheckIndex < healthCheckResults.count {
            result = healthCheckResults[healthCheckIndex]
            healthCheckIndex += 1
        } else {
            result = createDefaultHealthCheckResult()
        }
        
        mockHealthMetrics.lastHealthCheck = result.timestamp
        mockHealthMetrics.lastHealthScore = result.overallScore
        mockHealthMetrics.lastHealthStatus = result.status
        
        if result.status == .healthy {
            mockHealthMetrics.healthyChecks += 1
        } else if result.status == .critical {
            mockHealthMetrics.criticalChecks += 1
        }
        
        return result
    }
    
    public func getSystemStatus() -> SystemStatus {
        getSystemStatusCalled = true
        
        if let mockStatus = mockSystemStatus {
            return mockStatus
        }
        
        // Create default system status
        let healthResult = performHealthCheck()
        return SystemStatus(
            timestamp: Date(),
            healthResult: healthResult,
            systemInfo: SystemInformation(),
            networkStatus: NetworkStatus(),
            metrics: mockHealthMetrics
        )
    }
    
    public func getHealthMetrics() -> HealthMetrics {
        getHealthMetricsCalled = true
        return mockHealthMetrics
    }
    
    public func setHealthDelegate(_ delegate: HealthCheckDelegate?) {
        healthDelegate = delegate
    }
    
    // MARK: - Mock Helper Methods
    
    /// Reset all call flags and state
    public func resetCallFlags() {
        startMonitoringCalled = false
        stopMonitoringCalled = false
        performHealthCheckCalled = false
        getSystemStatusCalled = false
        getHealthMetricsCalled = false
    }
    
    /// Reset all mock state
    public func reset() {
        resetCallFlags()
        isMonitoringValue = false
        healthCheckResults.removeAll()
        healthCheckIndex = 0
        mockSystemStatus = nil
        mockHealthMetrics = HealthMetrics()
        healthDelegate = nil
        healthCheckCount = 0
        shouldSucceed = true
        startError = nil
    }
    
    /// Configure health check results for testing
    public func setHealthCheckResults(_ results: [HealthCheckResult]) {
        healthCheckResults = results
        healthCheckIndex = 0
    }
    
    /// Add a single health check result
    public func addHealthCheckResult(_ result: HealthCheckResult) {
        healthCheckResults.append(result)
    }
    
    /// Configure system status for testing
    public func setSystemStatus(_ status: SystemStatus) {
        mockSystemStatus = status
    }
    
    /// Configure health metrics for testing
    public func setHealthMetrics(_ metrics: HealthMetrics) {
        mockHealthMetrics = metrics
    }
    
    /// Simulate a critical health status and notify delegate
    public func simulateCriticalHealth() {
        guard let delegate = healthDelegate else { return }
        
        let criticalResult = HealthCheckResult(
            timestamp: Date(),
            status: .critical,
            overallScore: 0.2,
            resourceHealth: createMockResourceHealth(score: 0.1),
            processHealth: createMockProcessHealth(score: 0.2),
            deviceHealth: createMockDeviceHealth(score: 0.3),
            checkDuration: 150.0
        )
        
        delegate.healthCheckCompleted(result: criticalResult)
        delegate.healthStatusCritical(status: criticalResult)
    }
    
    /// Simulate health recovery and notify delegate
    public func simulateHealthRecovery() {
        guard let delegate = healthDelegate else { return }
        
        let healthyResult = createDefaultHealthCheckResult()
        delegate.healthCheckCompleted(result: healthyResult)
        delegate.healthStatusRecovered(status: healthyResult)
    }
    
    // MARK: - Private Helper Methods
    
    private func createDefaultHealthCheckResult() -> HealthCheckResult {
        let healthStatus: HealthStatus = shouldSucceed ? .healthy : .critical
        let healthScore = shouldSucceed ? 0.95 : 0.25
        
        return HealthCheckResult(
            timestamp: Date(),
            status: healthStatus,
            overallScore: healthScore,
            resourceHealth: createMockResourceHealth(score: healthScore),
            processHealth: createMockProcessHealth(score: healthScore),
            deviceHealth: createMockDeviceHealth(score: healthScore),
            checkDuration: 50.0
        )
    }
    
    private func createMockResourceHealth(score: Double) -> ResourceHealthStatus {
        return ResourceHealthStatus(
            memoryUsage: 128.0, // 128MB
            memoryUsagePercent: 25.0, // 25%
            cpuUsage: 0.15, // 15%
            loadAverage: 1.2,
            availableDiskSpace: 50.0, // 50GB
            openFileDescriptors: 45,
            healthScore: score,
            issues: score < 0.5 ? [
                ResourceIssue(
                    type: .memoryUsage,
                    severity: .critical,
                    description: "Mock high memory usage",
                    value: 90.0,
                    threshold: 80.0
                )
            ] : []
        )
    }
    
    private func createMockProcessHealth(score: Double) -> ProcessHealthStatus {
        return ProcessHealthStatus(
            uptime: 3600.0, // 1 hour
            processID: 12345,
            threadCount: 8,
            mappedRegions: 150,
            healthScore: score,
            issues: score < 0.5 ? [
                ProcessIssue(
                    type: .unresponsive,
                    severity: .critical,
                    description: "Mock process unresponsive"
                )
            ] : [],
            isResponsive: score >= 0.5,
            lastResponseTime: Date()
        )
    }
    
    private func createMockDeviceHealth(score: Double) -> DeviceHealthStatus {
        return DeviceHealthStatus(
            claimedDevices: 3,
            failedOperations: score < 0.5 ? 5 : 0,
            averageOperationTime: 250.0, // 250ms
            healthScore: score,
            issues: score < 0.5 ? [
                DeviceIssue(
                    type: .claimFailure,
                    severity: .warning,
                    description: "Mock device claim failures",
                    deviceID: "1-1"
                )
            ] : [],
            lastSuccessfulOperation: Date()
        )
    }
}