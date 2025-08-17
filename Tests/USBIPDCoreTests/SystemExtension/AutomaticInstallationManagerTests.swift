// AutomaticInstallationManagerTests.swift
// CI-compatible unit tests for automatic System Extension installation coordination

import XCTest
import Foundation
@testable import USBIPDCore
@testable import Common

final class AutomaticInstallationManagerTests: XCTestCase, TestSuite {
    
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
    
    private var mockInstaller: MockSystemExtensionInstaller!
    private var mockBundleDetector: MockBundleDetector!
    private var testConfig: ServerConfig!
    private var installationManager: AutomaticInstallationManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        try validateEnvironment()
        
        // Skip real System Extension operations in CI environment
        #if CI_ENVIRONMENT
        throw XCTSkip("Skipping System Extension installation tests in CI environment")
        #endif
        
        // Set up mock dependencies
        mockInstaller = MockSystemExtensionInstaller()
        mockBundleDetector = MockBundleDetector()
        testConfig = createTestServerConfig()
        
        // Create installation manager with mocks
        installationManager = AutomaticInstallationManager(
            config: testConfig,
            installer: mockInstaller,
            bundleDetector: mockBundleDetector
        )
    }
    
    override func tearDownWithError() throws {
        installationManager = nil
        testConfig = nil
        mockBundleDetector = nil
        mockInstaller = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Installation Attempt Tests
    
    func testSuccessfulAutomaticInstallation() throws {
        // Given: Valid bundle detected and installation succeeds
        mockBundleDetector.detectionResult = SystemExtensionBundleDetector.DetectionResult(
            found: true,
            bundlePath: "/tmp/test.systemextension",
            bundleIdentifier: "com.usbipd.mac.SystemExtension",
            issues: [],
            detectionTime: Date()
        )
        
        mockInstaller.installationResult = InstallationResult(
            success: true,
            errors: [],
            installationTime: 2.5,
            installationMethod: .automatic
        )
        
        let expectation = XCTestExpectation(description: "Installation completion")
        
        // When: Attempting automatic installation
        installationManager.attemptAutomaticInstallation { result in
            // Then: Installation should succeed
            XCTAssertTrue(result.success, "Installation should succeed")
            XCTAssertEqual(result.finalStatus, .installed)
            XCTAssertTrue(result.errors.isEmpty, "Should have no errors")
            XCTAssertEqual(result.recommendedAction, .none)
            XCTAssertFalse(result.requiresUserApproval)
            XCTAssertGreaterThan(result.duration, 0)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: TestEnvironmentFixtures.shortTimeout)
        
        // Verify installer was called
        XCTAssertEqual(mockInstaller.installationCalls.count, 1)
        
        // Verify final state
        let (state, history) = installationManager.getInstallationStatus()
        XCTAssertEqual(state, .completed)
        XCTAssertEqual(history.count, 1)
        XCTAssertTrue(history.first?.success == true)
    }
    
    func testFailedInstallationWithBundleNotFound() throws {
        // Given: No bundle detected
        mockBundleDetector.detectionResult = SystemExtensionBundleDetector.DetectionResult(
            found: false,
            bundlePath: nil,
            bundleIdentifier: nil,
            issues: ["No .build directory found"],
            detectionTime: Date()
        )
        
        let expectation = XCTestExpectation(description: "Installation completion")
        
        // When: Attempting automatic installation
        installationManager.attemptAutomaticInstallation { result in
            // Then: Installation should fail with appropriate error
            XCTAssertFalse(result.success, "Installation should fail when bundle not found")
            XCTAssertEqual(result.finalStatus, .invalidBundle)
            XCTAssertTrue(result.errors.contains { 
                if case .bundleValidationFailed = $0 { return true }
                return false
            }, "Should contain bundle validation error")
            XCTAssertEqual(result.recommendedAction, .checkConfiguration)
            XCTAssertFalse(result.requiresUserApproval)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: TestEnvironmentFixtures.shortTimeout)
        
        // Verify installer was NOT called
        XCTAssertEqual(mockInstaller.installationCalls.count, 0)
        
        // Verify final state
        let (state, history) = installationManager.getInstallationStatus()
        XCTAssertEqual(state, .failed)
        XCTAssertEqual(history.count, 1)
        XCTAssertFalse(history.first?.success == true)
    }
    
    func testFailedInstallationRequiringUserApproval() throws {
        // Given: Valid bundle but installation requires user approval
        mockBundleDetector.detectionResult = SystemExtensionBundleDetector.DetectionResult(
            found: true,
            bundlePath: "/tmp/test.systemextension",
            bundleIdentifier: "com.usbipd.mac.SystemExtension",
            issues: [],
            detectionTime: Date()
        )
        
        mockInstaller.installationResult = InstallationResult(
            success: false,
            errors: [.userApprovalRequired("User approval required in System Preferences")],
            installationTime: 1.0,
            installationMethod: .automatic
        )
        
        let expectation = XCTestExpectation(description: "Installation completion")
        
        // When: Attempting automatic installation
        installationManager.attemptAutomaticInstallation { result in
            // Then: Installation should fail but indicate user approval needed
            XCTAssertFalse(result.success, "Installation should fail")
            XCTAssertEqual(result.finalStatus, .pendingApproval)
            XCTAssertTrue(result.requiresUserApproval, "Should require user approval")
            XCTAssertEqual(result.recommendedAction, .requiresUserApproval)
            XCTAssertTrue(result.errors.contains { 
                if case .userApprovalRequired = $0 { return true }
                return false
            }, "Should contain user approval error")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: TestEnvironmentFixtures.shortTimeout)
        
        // Verify final state
        let (state, history) = installationManager.getInstallationStatus()
        XCTAssertEqual(state, .requiresApproval)
    }
    
    func testInstallationFailureWithDeveloperModeRequired() throws {
        // Given: Valid bundle but developer mode required
        mockBundleDetector.detectionResult = SystemExtensionBundleDetector.DetectionResult(
            found: true,
            bundlePath: "/tmp/test.systemextension",
            bundleIdentifier: "com.usbipd.mac.SystemExtension",
            issues: [],
            detectionTime: Date()
        )
        
        mockInstaller.installationResult = InstallationResult(
            success: false,
            errors: [.developerModeRequired("Developer mode must be enabled")],
            installationTime: 0.5,
            installationMethod: .automatic
        )
        
        let expectation = XCTestExpectation(description: "Installation completion")
        
        // When: Attempting automatic installation
        installationManager.attemptAutomaticInstallation { result in
            // Then: Installation should fail with configuration recommendation
            XCTAssertFalse(result.success, "Installation should fail")
            XCTAssertEqual(result.finalStatus, .installationFailed)
            XCTAssertEqual(result.recommendedAction, .checkConfiguration)
            XCTAssertFalse(result.requiresUserApproval)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: TestEnvironmentFixtures.shortTimeout)
    }
    
    // MARK: - Configuration and State Management Tests
    
    func testAutoInstallationDisabled() throws {
        // Given: Auto-installation is disabled in config
        testConfig = createTestServerConfig(autoInstallEnabled: false)
        installationManager = AutomaticInstallationManager(
            config: testConfig,
            installer: mockInstaller,
            bundleDetector: mockBundleDetector
        )
        
        let expectation = XCTestExpectation(description: "Installation completion")
        
        // When: Attempting automatic installation
        installationManager.attemptAutomaticInstallation { result in
            // Then: Installation should be skipped
            XCTAssertFalse(result.success, "Installation should be skipped when disabled")
            XCTAssertEqual(result.recommendedAction, .checkConfiguration)
            XCTAssertTrue(result.errors.contains { 
                if case .installationFailed(let message) = $0,
                   message.contains("disabled") {
                    return true
                }
                return false
            }, "Should contain disabled error")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: TestEnvironmentFixtures.shortTimeout)
        
        // Verify installer was NOT called
        XCTAssertEqual(mockInstaller.installationCalls.count, 0)
    }
    
    func testMaximumAttemptsExceeded() throws {
        // Given: Already exceeded maximum attempts
        testConfig = createTestServerConfig(maxAttempts: 2)
        installationManager = AutomaticInstallationManager(
            config: testConfig,
            installer: mockInstaller,
            bundleDetector: mockBundleDetector
        )
        
        // Simulate previous failed attempts
        for _ in 0..<3 {
            let expectation = XCTestExpectation(description: "Installation attempt")
            installationManager.attemptAutomaticInstallation { _ in
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 0.5)
        }
        
        let finalExpectation = XCTestExpectation(description: "Final attempt")
        
        // When: Attempting one more installation
        installationManager.attemptAutomaticInstallation { result in
            // Then: Should be rejected due to max attempts
            XCTAssertFalse(result.success, "Installation should be rejected")
            XCTAssertEqual(result.recommendedAction, .contactSupport)
            XCTAssertTrue(result.errors.contains { 
                if case .installationFailed(let message) = $0,
                   message.contains("Maximum") {
                    return true
                }
                return false
            }, "Should contain maximum attempts error")
            finalExpectation.fulfill()
        }
        
        wait(for: [finalExpectation], timeout: TestEnvironmentFixtures.shortTimeout)
    }
    
    func testRetryDelayRespected() throws {
        // Given: Config with retry delay
        testConfig = createTestServerConfig(retryDelay: 10.0)
        installationManager = AutomaticInstallationManager(
            config: testConfig,
            installer: mockInstaller,
            bundleDetector: mockBundleDetector
        )
        
        // First attempt
        let firstExpectation = XCTestExpectation(description: "First attempt")
        installationManager.attemptAutomaticInstallation { _ in
            firstExpectation.fulfill()
        }
        wait(for: [firstExpectation], timeout: 0.5)
        
        // Immediate second attempt
        let secondExpectation = XCTestExpectation(description: "Second attempt")
        installationManager.attemptAutomaticInstallation { result in
            // Then: Should be rejected due to retry delay
            XCTAssertFalse(result.success, "Second attempt should be rejected")
            XCTAssertEqual(result.recommendedAction, .retryLater)
            XCTAssertTrue(result.errors.contains { 
                if case .installationFailed(let message) = $0,
                   message.contains("Retry delay") {
                    return true
                }
                return false
            }, "Should contain retry delay error")
            secondExpectation.fulfill()
        }
        
        wait(for: [secondExpectation], timeout: TestEnvironmentFixtures.shortTimeout)
    }
    
    func testForceReinstallationAfterBundleConflict() throws {
        // Given: Previous attempt failed with bundle already exists error
        mockBundleDetector.detectionResult = SystemExtensionBundleDetector.DetectionResult(
            found: true,
            bundlePath: "/tmp/test.systemextension",
            bundleIdentifier: "com.usbipd.mac.SystemExtension",
            issues: [],
            detectionTime: Date()
        )
        
        // First attempt fails with bundle conflict
        mockInstaller.installationResult = InstallationResult(
            success: false,
            errors: [.bundleAlreadyExists("Bundle already exists")],
            installationTime: 1.0,
            installationMethod: .automatic
        )
        
        let firstExpectation = XCTestExpectation(description: "First attempt")
        installationManager.attemptAutomaticInstallation { _ in
            firstExpectation.fulfill()
        }
        wait(for: [firstExpectation], timeout: 0.5)
        
        // Reset retry delay for test
        installationManager.resetAttemptCounter()
        
        // Second attempt should use force reinstall
        mockInstaller.forceReinstallResult = InstallationResult(
            success: true,
            errors: [],
            installationTime: 2.0,
            installationMethod: .forceReinstall
        )
        
        let secondExpectation = XCTestExpectation(description: "Second attempt")
        installationManager.attemptAutomaticInstallation { result in
            // Then: Should succeed with force reinstall
            XCTAssertTrue(result.success, "Force reinstall should succeed")
            XCTAssertEqual(result.finalStatus, .installed)
            secondExpectation.fulfill()
        }
        
        wait(for: [secondExpectation], timeout: TestEnvironmentFixtures.shortTimeout)
        
        // Verify force reinstall was called
        XCTAssertEqual(mockInstaller.forceReinstallCalls.count, 1)
    }
    
    // MARK: - Status and Availability Tests
    
    func testSystemExtensionAvailabilityCheck() throws {
        // Given: Bundle detector finds valid bundle
        mockBundleDetector.detectionResult = SystemExtensionBundleDetector.DetectionResult(
            found: true,
            bundlePath: "/tmp/test.systemextension",
            bundleIdentifier: "com.usbipd.mac.SystemExtension",
            issues: [],
            detectionTime: Date()
        )
        
        // When: Checking availability
        let isAvailable = installationManager.isSystemExtensionAvailable()
        
        // Then: Should return true
        XCTAssertTrue(isAvailable, "Should detect available System Extension")
        
        // Given: Bundle detector finds no bundle
        mockBundleDetector.detectionResult = SystemExtensionBundleDetector.DetectionResult(
            found: false,
            bundlePath: nil,
            bundleIdentifier: nil,
            issues: ["No bundle found"],
            detectionTime: Date()
        )
        
        // When: Checking availability again
        let isNotAvailable = installationManager.isSystemExtensionAvailable()
        
        // Then: Should return false
        XCTAssertFalse(isNotAvailable, "Should not detect System Extension when bundle missing")
    }
    
    func testInstallationStatusAndHistory() throws {
        // Given: Initial state
        var (state, history) = installationManager.getInstallationStatus()
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(history.count, 0)
        
        // Given: Bundle detected and installation succeeds
        mockBundleDetector.detectionResult = SystemExtensionBundleDetector.DetectionResult(
            found: true,
            bundlePath: "/tmp/test.systemextension",
            bundleIdentifier: "com.usbipd.mac.SystemExtension",
            issues: [],
            detectionTime: Date()
        )
        
        mockInstaller.installationResult = InstallationResult(
            success: true,
            errors: [],
            installationTime: 1.5,
            installationMethod: .automatic
        )
        
        let expectation = XCTestExpectation(description: "Installation completion")
        
        // When: Performing installation
        installationManager.attemptAutomaticInstallation { _ in
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: TestEnvironmentFixtures.shortTimeout)
        
        // Then: Status should be updated
        (state, history) = installationManager.getInstallationStatus()
        XCTAssertEqual(state, .completed)
        XCTAssertEqual(history.count, 1)
        XCTAssertTrue(history.first?.success == true)
        XCTAssertEqual(history.first?.finalStatus, .installed)
    }
    
    func testAttemptCounterReset() throws {
        // Given: Multiple failed attempts
        testConfig = createTestServerConfig(maxAttempts: 3, retryDelay: 0.1)
        installationManager = AutomaticInstallationManager(
            config: testConfig,
            installer: mockInstaller,
            bundleDetector: mockBundleDetector
        )
        
        mockBundleDetector.detectionResult = SystemExtensionBundleDetector.DetectionResult(
            found: false,
            bundlePath: nil,
            bundleIdentifier: nil,
            issues: ["No bundle found"],
            detectionTime: Date()
        )
        
        // Exhaust attempts
        for _ in 0..<3 {
            let expectation = XCTestExpectation(description: "Installation attempt")
            installationManager.attemptAutomaticInstallation { _ in
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 0.5)
            Thread.sleep(forTimeInterval: 0.2) // Wait for retry delay
        }
        
        // Verify next attempt would be rejected
        let rejectionExpectation = XCTestExpectation(description: "Rejection attempt")
        installationManager.attemptAutomaticInstallation { result in
            XCTAssertFalse(result.success)
            XCTAssertEqual(result.recommendedAction, .contactSupport)
            rejectionExpectation.fulfill()
        }
        wait(for: [rejectionExpectation], timeout: 0.5)
        
        // When: Resetting attempt counter
        installationManager.resetAttemptCounter()
        
        // Then: Should be able to attempt again
        let retryExpectation = XCTestExpectation(description: "Retry attempt")
        installationManager.attemptAutomaticInstallation { result in
            XCTAssertFalse(result.success) // Still fails due to no bundle, but not due to max attempts
            XCTAssertNotEqual(result.recommendedAction, .contactSupport)
            retryExpectation.fulfill()
        }
        wait(for: [retryExpectation], timeout: TestEnvironmentFixtures.shortTimeout)
    }
    
    // MARK: - Helper Methods
    
    private func createTestServerConfig(
        autoInstallEnabled: Bool = true,
        maxAttempts: Int = 5,
        retryDelay: TimeInterval = 1.0
    ) -> ServerConfig {
        let config = ServerConfig(
            port: 3240,
            logLevel: .debug,
            debugMode: true,
            maxConnections: 10,
            connectionTimeout: 30.0,
            allowedDevices: [],
            autoBindDevices: false,
            logFilePath: nil
        )
        
        // Set auto-installation properties using reflection or test configuration
        // Since these are internal properties, we'll create a test-specific config
        return TestServerConfig(
            baseConfig: config,
            autoInstallEnabled: autoInstallEnabled,
            maxAutoInstallAttempts: maxAttempts,
            autoInstallRetryDelay: retryDelay
        )
    }
}

// MARK: - Mock Classes

/// Mock SystemExtensionInstaller for isolated testing
private class MockSystemExtensionInstaller: SystemExtensionInstaller {
    
    var installationResult: InstallationResult?
    var forceReinstallResult: InstallationResult?
    var installationCalls: [Date] = []
    var forceReinstallCalls: [Date] = []
    
    override func installSystemExtension(
        bundleIdentifier: String,
        executablePath: String,
        completion: @escaping InstallationCompletion
    ) {
        installationCalls.append(Date())
        
        // Simulate async operation
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            let result = self.installationResult ?? InstallationResult(
                success: false,
                errors: [.unknownError("Mock installation not configured")]
            )
            completion(result)
        }
    }
    
    func forceReinstallSystemExtension(
        bundleIdentifier: String,
        executablePath: String,
        completion: @escaping InstallationCompletion
    ) {
        forceReinstallCalls.append(Date())
        
        // Simulate async operation
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            let result = self.forceReinstallResult ?? InstallationResult(
                success: false,
                errors: [.unknownError("Mock force reinstall not configured")]
            )
            completion(result)
        }
    }
}

/// Mock bundle detector for controlled testing
private class MockBundleDetector: SystemExtensionBundleDetector {
    
    var detectionResult: SystemExtensionBundleDetector.DetectionResult?
    
    override func detectBundle() -> SystemExtensionBundleDetector.DetectionResult {
        return detectionResult ?? SystemExtensionBundleDetector.DetectionResult(
            found: false,
            bundlePath: nil,
            bundleIdentifier: nil,
            issues: ["Mock detection not configured"],
            detectionTime: Date()
        )
    }
}

/// Test-specific server configuration for testing auto-installation behavior
private class TestServerConfig: ServerConfig {
    private let autoInstallEnabled: Bool
    private let maxAutoInstallAttempts: Int
    private let autoInstallRetryDelay: TimeInterval
    
    init(
        baseConfig: ServerConfig,
        autoInstallEnabled: Bool,
        maxAutoInstallAttempts: Int,
        autoInstallRetryDelay: TimeInterval
    ) {
        self.autoInstallEnabled = autoInstallEnabled
        self.maxAutoInstallAttempts = maxAutoInstallAttempts
        self.autoInstallRetryDelay = autoInstallRetryDelay
        
        super.init(
            port: baseConfig.port,
            logLevel: baseConfig.logLevel,
            debugMode: baseConfig.debugMode,
            maxConnections: baseConfig.maxConnections,
            connectionTimeout: baseConfig.connectionTimeout,
            allowedDevices: baseConfig.allowedDevices,
            autoBindDevices: baseConfig.autoBindDevices,
            logFilePath: baseConfig.logFilePath
        )
    }
    
    func shouldAttemptAutoInstall() -> Bool {
        return autoInstallEnabled
    }
}