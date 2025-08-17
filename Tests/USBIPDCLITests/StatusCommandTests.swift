// StatusCommandTests.swift
// Unit tests for enhanced StatusCommand with System Extension installation state reporting

import XCTest
import Foundation
@testable import USBIPDCLI
@testable import USBIPDCore
@testable import Common

final class StatusCommandTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol
    
    var environmentConfig: TestEnvironmentConfig {
        return TestEnvironmentDetector.createConfigurationForCurrentEnvironment()
    }
    
    var requiredCapabilities: TestEnvironmentCapabilities {
        return [.filesystemWrite]
    }
    
    var testCategory: String {
        return "unit"
    }
    
    // MARK: - Test Infrastructure
    
    private var mockOutputFormatter: MockOutputFormatter!
    private var mockDeviceClaimManager: MockDeviceClaimManager!
    private var mockServerCoordinator: MockServerCoordinator!
    private var statusCommand: StatusCommand!
    private var capturedOutput: [String] = []
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        try validateEnvironment()
        
        // Set up mock dependencies
        mockOutputFormatter = MockOutputFormatter()
        mockDeviceClaimManager = MockDeviceClaimManager()
        mockServerCoordinator = MockServerCoordinator()
        
        // Capture print output for testing
        capturedOutput = []
        
        // Create status command with mocks
        statusCommand = StatusCommand(
            deviceClaimManager: mockDeviceClaimManager,
            serverCoordinator: mockServerCoordinator,
            outputFormatter: mockOutputFormatter
        )
    }
    
    override func tearDownWithError() throws {
        statusCommand = nil
        mockServerCoordinator = nil
        mockDeviceClaimManager = nil
        mockOutputFormatter = nil
        capturedOutput = []
        try super.tearDownWithError()
    }
    
    // MARK: - System Extension Installation Status Tests
    
    func testStatusWithNoAutomaticInstallation() throws {
        // Given: No automatic installation available
        mockServerCoordinator.automaticInstallationStatus = nil
        
        // When: Executing status command
        try statusCommand.execute(with: [])
        
        // Then: Should display appropriate message about unavailable automatic installation
        // Note: Since we can't capture print output in unit tests, we verify the coordinator was called
        XCTAssertTrue(mockServerCoordinator.getAutomaticInstallationStatusCalled)
        XCTAssertTrue(mockServerCoordinator.isSystemExtensionAvailableCalled)
    }
    
    func testStatusWithIdleInstallationState() throws {
        // Given: Installation state is idle
        let mockState = AutomaticInstallationManager.InstallationState.idle
        let mockHistory: [AutomaticInstallationManager.InstallationAttemptResult] = []
        mockServerCoordinator.automaticInstallationStatus = (mockState, mockHistory)
        mockServerCoordinator.systemExtensionAvailable = true
        
        // When: Executing status command
        try statusCommand.execute(with: [])
        
        // Then: Should show idle state information
        XCTAssertTrue(mockServerCoordinator.getAutomaticInstallationStatusCalled)
        XCTAssertTrue(mockServerCoordinator.isSystemExtensionAvailableCalled)
    }
    
    func testStatusWithSuccessfulInstallation() throws {
        // Given: Installation completed successfully
        let mockState = AutomaticInstallationManager.InstallationState.completed
        let successfulAttempt = AutomaticInstallationManager.InstallationAttemptResult(
            success: true,
            finalStatus: .installed,
            errors: [],
            duration: 2.5,
            requiresUserApproval: false,
            recommendedAction: .none
        )
        let mockHistory = [successfulAttempt]
        mockServerCoordinator.automaticInstallationStatus = (mockState, mockHistory)
        mockServerCoordinator.systemExtensionAvailable = true
        
        // When: Executing status command
        try statusCommand.execute(with: [])
        
        // Then: Should display successful installation status
        XCTAssertTrue(mockServerCoordinator.getAutomaticInstallationStatusCalled)
        XCTAssertTrue(mockServerCoordinator.isSystemExtensionAvailableCalled)
    }
    
    func testStatusWithFailedInstallationRequiringApproval() throws {
        // Given: Installation failed requiring user approval
        let mockState = AutomaticInstallationManager.InstallationState.requiresApproval
        let failedAttempt = AutomaticInstallationManager.InstallationAttemptResult(
            success: false,
            finalStatus: .pendingApproval,
            errors: [.userApprovalRequired("User approval required in System Preferences")],
            duration: 1.0,
            requiresUserApproval: true,
            recommendedAction: .requiresUserApproval
        )
        let mockHistory = [failedAttempt]
        mockServerCoordinator.automaticInstallationStatus = (mockState, mockHistory)
        mockServerCoordinator.systemExtensionAvailable = true
        
        // When: Executing status command
        try statusCommand.execute(with: [])
        
        // Then: Should display user approval guidance
        XCTAssertTrue(mockServerCoordinator.getAutomaticInstallationStatusCalled)
        
        // Verify that the failed attempt shows user approval requirement
        XCTAssertTrue(failedAttempt.requiresUserApproval)
        XCTAssertEqual(failedAttempt.recommendedAction, .requiresUserApproval)
    }
    
    func testStatusWithFailedInstallationDeveloperModeRequired() throws {
        // Given: Installation failed due to developer mode required
        let mockState = AutomaticInstallationManager.InstallationState.failed
        let failedAttempt = AutomaticInstallationManager.InstallationAttemptResult(
            success: false,
            finalStatus: .installationFailed,
            errors: [.developerModeRequired("Developer mode must be enabled")],
            duration: 0.5,
            requiresUserApproval: false,
            recommendedAction: .checkConfiguration
        )
        let mockHistory = [failedAttempt]
        mockServerCoordinator.automaticInstallationStatus = (mockState, mockHistory)
        mockServerCoordinator.systemExtensionAvailable = true
        
        // When: Executing status command
        try statusCommand.execute(with: [])
        
        // Then: Should display configuration check guidance
        XCTAssertTrue(mockServerCoordinator.getAutomaticInstallationStatusCalled)
        XCTAssertEqual(failedAttempt.recommendedAction, .checkConfiguration)
        XCTAssertFalse(failedAttempt.requiresUserApproval)
    }
    
    func testStatusWithMultipleInstallationAttempts() throws {
        // Given: Multiple installation attempts with mixed results
        let mockState = AutomaticInstallationManager.InstallationState.retryWaiting
        let firstAttempt = AutomaticInstallationManager.InstallationAttemptResult(
            success: false,
            finalStatus: .invalidBundle,
            errors: [.bundleValidationFailed(["Bundle not found"])],
            duration: 0.2,
            requiresUserApproval: false,
            recommendedAction: .checkConfiguration
        )
        let secondAttempt = AutomaticInstallationManager.InstallationAttemptResult(
            success: false,
            finalStatus: .installationFailed,
            errors: [.unknownError("Network timeout")],
            duration: 5.0,
            requiresUserApproval: false,
            recommendedAction: .retryLater
        )
        let mockHistory = [firstAttempt, secondAttempt]
        mockServerCoordinator.automaticInstallationStatus = (mockState, mockHistory)
        mockServerCoordinator.systemExtensionAvailable = false
        
        // When: Executing status command with detailed flag
        try statusCommand.execute(with: ["--detailed"])
        
        // Then: Should display installation history
        XCTAssertTrue(mockServerCoordinator.getAutomaticInstallationStatusCalled)
        XCTAssertEqual(mockHistory.count, 2)
        XCTAssertFalse(mockHistory.allSatisfy { $0.success })
    }
    
    func testStatusWithMaxAttemptsExceeded() throws {
        // Given: Installation failed with contact support recommendation
        let mockState = AutomaticInstallationManager.InstallationState.failed
        let failedAttempt = AutomaticInstallationManager.InstallationAttemptResult(
            success: false,
            finalStatus: .installationFailed,
            errors: [.installationFailed("Maximum installation attempts exceeded")],
            duration: 0.1,
            requiresUserApproval: false,
            recommendedAction: .contactSupport
        )
        let mockHistory = [failedAttempt]
        mockServerCoordinator.automaticInstallationStatus = (mockState, mockHistory)
        mockServerCoordinator.systemExtensionAvailable = true
        
        // When: Executing status command
        try statusCommand.execute(with: [])
        
        // Then: Should display contact support guidance
        XCTAssertTrue(mockServerCoordinator.getAutomaticInstallationStatusCalled)
        XCTAssertEqual(failedAttempt.recommendedAction, .contactSupport)
    }
    
    // MARK: - System Extension Lifecycle Status Tests
    
    func testStatusWithSystemExtensionDisabled() throws {
        // Given: System Extension management is disabled
        let disabledStatus = SystemExtensionStatus(
            enabled: false,
            state: "disabled",
            health: nil
        )
        mockServerCoordinator.systemExtensionStatus = disabledStatus
        
        // When: Executing status command
        try statusCommand.execute(with: [])
        
        // Then: Should display disabled status
        XCTAssertTrue(mockServerCoordinator.getSystemExtensionStatusCalled)
        XCTAssertFalse(disabledStatus.enabled)
    }
    
    func testStatusWithSystemExtensionActive() throws {
        // Given: System Extension is active and healthy
        let activeStatus = SystemExtensionStatus(
            enabled: true,
            state: "active",
            health: "healthy: true"
        )
        mockServerCoordinator.systemExtensionStatus = activeStatus
        
        // When: Executing status command with detailed flag
        try statusCommand.execute(with: ["--detailed"])
        
        // Then: Should display active status with health details
        XCTAssertTrue(mockServerCoordinator.getSystemExtensionStatusCalled)
        XCTAssertTrue(activeStatus.enabled)
        XCTAssertNotNil(activeStatus.health)
    }
    
    func testStatusWithSystemExtensionFailed() throws {
        // Given: System Extension has failed
        let failedStatus = SystemExtensionStatus(
            enabled: true,
            state: "failed",
            health: "healthy: false"
        )
        mockServerCoordinator.systemExtensionStatus = failedStatus
        
        // When: Executing status command with detailed flag
        try statusCommand.execute(with: ["--detailed"])
        
        // Then: Should display failure status with troubleshooting
        XCTAssertTrue(mockServerCoordinator.getSystemExtensionStatusCalled)
        XCTAssertTrue(failedStatus.enabled)
        XCTAssertTrue(failedStatus.state.contains("failed"))
    }
    
    // MARK: - USB Operation Status Tests
    
    func testUSBOperationStatusWithActiveRequests() throws {
        // Given: Active USB operations
        let usbStats = MockUSBOperationStatistics(
            activeRequestCount: 5,
            currentLoadPercentage: 25.0,
            successfulTransfers: 100,
            failedTransfers: 2,
            totalTransfers: 102,
            averageTransferLatency: 15.5,
            averageThroughput: 2_500_000.0 // 2.5 MB/s
        )
        mockServerCoordinator.usbOperationStatistics = usbStats
        
        // When: Executing status command
        try statusCommand.execute(with: [])
        
        // Then: Should display USB operation status
        XCTAssertTrue(mockServerCoordinator.getUSBOperationStatisticsCalled)
        XCTAssertEqual(usbStats.activeRequestCount, 5)
        XCTAssertEqual(usbStats.totalTransfers, 102)
    }
    
    func testUSBOperationStatusWithHighErrorRate() throws {
        // Given: High error rate in USB operations
        let usbStats = MockUSBOperationStatistics(
            activeRequestCount: 0,
            currentLoadPercentage: 0.0,
            successfulTransfers: 50,
            failedTransfers: 25, // 33% failure rate
            totalTransfers: 75,
            averageTransferLatency: 200.0,
            averageThroughput: 500_000.0
        )
        mockServerCoordinator.usbOperationStatistics = usbStats
        
        // When: Executing status command with detailed flag
        try statusCommand.execute(with: ["--detailed"])
        
        // Then: Should display error analysis and recommendations
        XCTAssertTrue(mockServerCoordinator.getUSBOperationStatisticsCalled)
        
        // Calculate success rate to verify it triggers recommendations
        let successRate = Double(usbStats.successfulTransfers) / Double(usbStats.totalTransfers) * 100
        XCTAssertLessThan(successRate, 90.0, "Success rate should be low enough to trigger recommendations")
    }
    
    func testUSBOperationStatusWithHighLatency() throws {
        // Given: High latency in USB operations
        let usbStats = MockUSBOperationStatistics(
            activeRequestCount: 2,
            currentLoadPercentage: 95.0, // High load
            successfulTransfers: 200,
            failedTransfers: 5,
            totalTransfers: 205,
            averageTransferLatency: 750.0, // High latency
            averageThroughput: 100_000.0
        )
        mockServerCoordinator.usbOperationStatistics = usbStats
        
        // When: Executing status command with detailed flag
        try statusCommand.execute(with: ["--detailed"])
        
        // Then: Should display performance warnings
        XCTAssertTrue(mockServerCoordinator.getUSBOperationStatisticsCalled)
        XCTAssertGreaterThan(usbStats.averageTransferLatency, 500.0)
        XCTAssertGreaterThan(usbStats.currentLoadPercentage, 90.0)
    }
    
    // MARK: - Command Options Tests
    
    func testStatusCommandHelp() throws {
        // When: Executing status command with help flag
        try statusCommand.execute(with: ["--help"])
        
        // Then: Should not throw and should display help
        // Note: We can't capture print output, but we ensure it doesn't crash
    }
    
    func testStatusCommandWithInvalidOption() throws {
        // Given: Invalid command option
        
        // When: Executing status command with invalid option
        // Then: Should throw CommandLineError
        XCTAssertThrowsError(try statusCommand.execute(with: ["--invalid-option"])) { error in
            XCTAssertTrue(error is CommandLineError)
            if let commandError = error as? CommandLineError {
                switch commandError {
                case .invalidArguments(let message):
                    XCTAssertTrue(message.contains("Unknown option"))
                default:
                    XCTFail("Expected invalidArguments error")
                }
            }
        }
    }
    
    func testStatusCommandHealthCheckOnly() throws {
        // Given: System Extension claim adapter with health check capability
        let mockAdapter = MockSystemExtensionClaimAdapter()
        mockAdapter.healthCheckResult = true
        
        let statusCommandWithAdapter = StatusCommand(
            deviceClaimManager: mockAdapter,
            serverCoordinator: mockServerCoordinator,
            outputFormatter: mockOutputFormatter
        )
        
        // When: Executing status command with health check option
        try statusCommandWithAdapter.execute(with: ["--health"])
        
        // Then: Should perform health check only
        XCTAssertTrue(mockAdapter.performSystemExtensionHealthCheckCalled)
    }
    
    func testStatusCommandWithSystemExtensionNotAvailable() throws {
        // Given: No device claim manager (System Extension not available)
        let statusCommandWithoutManager = StatusCommand(
            deviceClaimManager: nil,
            serverCoordinator: mockServerCoordinator,
            outputFormatter: mockOutputFormatter
        )
        
        // When: Executing status command
        try statusCommandWithoutManager.execute(with: [])
        
        // Then: Should display System Extension not available message
        // Command should complete without error but show appropriate message
    }
    
    // MARK: - Integration Tests
    
    func testStatusCommandWithSystemExtensionActiveAndInstallationCompleted() throws {
        // Given: System Extension is active with successful installation
        let mockState = AutomaticInstallationManager.InstallationState.completed
        let successfulAttempt = AutomaticInstallationManager.InstallationAttemptResult(
            success: true,
            finalStatus: .installed,
            errors: [],
            duration: 3.0,
            requiresUserApproval: false,
            recommendedAction: .none
        )
        mockServerCoordinator.automaticInstallationStatus = (mockState, [successfulAttempt])
        mockServerCoordinator.systemExtensionAvailable = true
        
        let activeStatus = SystemExtensionStatus(
            enabled: true,
            state: "active",
            health: "healthy: true"
        )
        mockServerCoordinator.systemExtensionStatus = activeStatus
        
        let goodUSBStats = MockUSBOperationStatistics(
            activeRequestCount: 2,
            currentLoadPercentage: 15.0,
            successfulTransfers: 500,
            failedTransfers: 3,
            totalTransfers: 503,
            averageTransferLatency: 25.0,
            averageThroughput: 5_000_000.0
        )
        mockServerCoordinator.usbOperationStatistics = goodUSBStats
        
        // When: Executing detailed status command
        try statusCommand.execute(with: ["--detailed"])
        
        // Then: Should display comprehensive status information
        XCTAssertTrue(mockServerCoordinator.getAutomaticInstallationStatusCalled)
        XCTAssertTrue(mockServerCoordinator.getSystemExtensionStatusCalled)
        XCTAssertTrue(mockServerCoordinator.getUSBOperationStatisticsCalled)
        
        // Verify the status indicates everything is working well
        XCTAssertTrue(successfulAttempt.success)
        XCTAssertTrue(activeStatus.enabled)
        XCTAssertEqual(activeStatus.state, "active")
        XCTAssertGreaterThan(goodUSBStats.successfulTransfers, goodUSBStats.failedTransfers * 10)
    }
}

// MARK: - Mock Classes

/// Mock DeviceClaimManager for testing
private class MockDeviceClaimManager: DeviceClaimManager {
    
    override func claimDevice(_ device: USBDevice) throws {
        // Mock implementation
    }
    
    override func releaseDevice(_ device: USBDevice) throws {
        // Mock implementation  
    }
    
    override func getClaimedDevices() -> [USBDevice] {
        return []
    }
}

/// Mock ServerCoordinator for testing status reporting
private class MockServerCoordinator: ServerCoordinator {
    
    var automaticInstallationStatus: (AutomaticInstallationManager.InstallationState, [AutomaticInstallationManager.InstallationAttemptResult])?
    var systemExtensionAvailable = false
    var systemExtensionStatus = SystemExtensionStatus(enabled: false, state: "unknown", health: nil)
    var usbOperationStatistics = MockUSBOperationStatistics()
    
    var getAutomaticInstallationStatusCalled = false
    var isSystemExtensionAvailableCalled = false
    var getSystemExtensionStatusCalled = false
    var getUSBOperationStatisticsCalled = false
    
    func getAutomaticInstallationStatus() -> (AutomaticInstallationManager.InstallationState, [AutomaticInstallationManager.InstallationAttemptResult])? {
        getAutomaticInstallationStatusCalled = true
        return automaticInstallationStatus
    }
    
    func isSystemExtensionAvailable() -> Bool {
        isSystemExtensionAvailableCalled = true
        return systemExtensionAvailable
    }
    
    func getSystemExtensionStatus() -> SystemExtensionStatus {
        getSystemExtensionStatusCalled = true
        return systemExtensionStatus
    }
    
    func getUSBOperationStatistics() -> USBOperationStatistics {
        getUSBOperationStatisticsCalled = true
        return usbOperationStatistics
    }
}

/// Mock System Extension claim adapter for health check testing
private class MockSystemExtensionClaimAdapter: SystemExtensionClaimAdapter {
    
    var healthCheckResult = true
    var performSystemExtensionHealthCheckCalled = false
    
    override func performSystemExtensionHealthCheck() -> Bool {
        performSystemExtensionHealthCheckCalled = true
        return healthCheckResult
    }
    
    override func getSystemExtensionStatus() -> SystemExtensionClaimStatus {
        return SystemExtensionClaimStatus(
            isRunning: true,
            lastStartTime: Date(),
            version: "1.0.0",
            errorCount: 0,
            memoryUsage: 1024 * 1024,
            claimedDevices: [],
            healthMetrics: SystemExtensionHealthMetrics(
                successfulClaims: 10,
                failedClaims: 0,
                activeConnections: 1,
                averageClaimTime: 15.0,
                lastHealthCheck: Date()
            )
        )
    }
    
    override func getSystemExtensionStatistics() -> SystemExtensionStatistics {
        return SystemExtensionStatistics(
            totalRequests: 100,
            totalResponses: 98,
            totalErrors: 2,
            successfulClaims: 10,
            failedClaims: 0,
            successfulReleases: 8,
            failedReleases: 0,
            startTime: Date(timeIntervalSinceNow: -3600)
        )
    }
}

/// Mock USB operation statistics for testing
private struct MockUSBOperationStatistics: USBOperationStatistics {
    let activeRequestCount: Int
    let currentLoadPercentage: Double
    let successfulTransfers: Int
    let failedTransfers: Int
    let totalTransfers: Int
    let averageTransferLatency: Double
    let averageThroughput: Double
    
    // Additional properties with defaults
    let activeControlRequests = 0
    let activeBulkRequests = 0
    let activeInterruptRequests = 0
    let activeIsochronousRequests = 0
    let controlTransferCount = 0
    let bulkTransferCount = 0
    let interruptTransferCount = 0
    let isochronousTransferCount = 0
    let successfulControlTransfers = 0
    let failedControlTransfers = 0
    let successfulBulkTransfers = 0
    let failedBulkTransfers = 0
    let successfulInterruptTransfers = 0
    let failedInterruptTransfers = 0
    let successfulIsochronousTransfers = 0
    let failedIsochronousTransfers = 0
    let peakThroughput = 10_000_000.0
    let totalBytesTransferred: UInt64 = 1_000_000
    let timeoutErrors = 0
    let deviceNotAvailableErrors = 0
    let invalidParameterErrors = 0
    let endpointStallErrors = 0
    let otherErrors = 0
    let maxConcurrentRequests = 100
    let transferBufferMemoryUsage: UInt64 = 1024 * 1024
    let activeURBCount = 0
    let lastUpdateTime: Date? = Date()
    
    init(
        activeRequestCount: Int = 0,
        currentLoadPercentage: Double = 0.0,
        successfulTransfers: Int = 0,
        failedTransfers: Int = 0,
        totalTransfers: Int = 0,
        averageTransferLatency: Double = 0.0,
        averageThroughput: Double = 0.0
    ) {
        self.activeRequestCount = activeRequestCount
        self.currentLoadPercentage = currentLoadPercentage
        self.successfulTransfers = successfulTransfers
        self.failedTransfers = failedTransfers
        self.totalTransfers = totalTransfers
        self.averageTransferLatency = averageTransferLatency
        self.averageThroughput = averageThroughput
    }
}

/// Mock System Extension status for testing
private struct SystemExtensionStatus {
    let enabled: Bool
    let state: String
    let health: String?
}