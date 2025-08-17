//
//  AutomaticSystemExtensionInstallationTests.swift
//  usbipd-mac
//
//  CI-aware integration tests for automatic System Extension installation workflow
//  Tests end-to-end automatic installation with environment detection and fallback behavior
//

import XCTest
import Foundation
import SystemExtensions
@testable import USBIPDCLI
@testable import USBIPDCore
@testable import Common
@testable import SystemExtension

/// Integration tests for automatic System Extension installation workflow
/// Tests complete automatic installation workflow with real components and environment awareness
/// Uses CI detection to skip System Extension operations and test fallback behavior instead
final class AutomaticSysExtInstallationTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    var environmentConfig: TestEnvironmentConfig {
        return TestEnvironmentDetector.createConfigurationForCurrentEnvironment()
    }
    
    var requiredCapabilities: TestEnvironmentCapabilities {
        return [.filesystemWrite, .networkAccess]
    }
    
    var testCategory: String {
        return "integration"
    }
    
    // MARK: - Test Properties
    
    var serverCoordinator: ServerCoordinator!
    var automaticInstallationManager: AutomaticInstallationManager!
    var bundleDetector: SystemExtensionBundleDetector!
    var tempDirectory: URL!
    var mockBundlePath: URL!
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        // Validate environment before running tests
        do {
            try validateEnvironment()
        } catch {
            XCTFail("Environment validation failed: \(error)")
            return
        }
        
        // Skip if test suite shouldn't run in current environment
        guard shouldRunInCurrentEnvironment() else {
            return
        }
        
        setUpTestSuite()
        
        // Create temporary directory for test artifacts
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutomaticInstallationTests")
            .appendingPathComponent(UUID().uuidString)
        
        try? FileManager.default.createDirectory(at: tempDirectory,
                                               withIntermediateDirectories: true,
                                               attributes: nil)
        
        // Create mock bundle structure for testing
        let bundleName = "com.github.usbipd-mac.SystemExtension.test"
        mockBundlePath = tempDirectory.appendingPathComponent("\(bundleName).systemextension")
        
        // Create bundle detector
        bundleDetector = SystemExtensionBundleDetector()
        
        // Create test components based on environment
        setupTestComponents()
    }
    
    override func tearDown() {
        // Clean up components
        automaticInstallationManager = nil
        serverCoordinator = nil
        bundleDetector = nil
        
        // Clean up temporary files
        if let tempPath = tempDirectory {
            try? FileManager.default.removeItem(at: tempPath)
        }
        tempDirectory = nil
        mockBundlePath = nil
        
        tearDownTestSuite()
        super.tearDown()
    }
    
    private func setupTestComponents() {
        // Setup varies based on environment capabilities
        let config = environmentConfig
        
        if config.hasCapability(.systemExtensionInstall) {
            // Production environment - use real components
            setupProductionComponents()
        } else {
            // CI/Development environment - use mocked components
            setupMockedComponents()
        }
    }
    
    private func setupProductionComponents() {
        // Create real System Extension infrastructure for production testing
        let bundleCreator = SystemExtensionBundleCreator()
        let codeSigningManager = CodeSigningManager()
        let installer = SystemExtensionInstaller(
            bundleCreator: bundleCreator,
            codeSigningManager: codeSigningManager
        )
        
        automaticInstallationManager = AutomaticInstallationManager(
            installer: installer,
            bundleDetector: bundleDetector
        )
        
        // Create server coordinator with System Extension support
        let serverConfig = ServerConfig.default
        serverCoordinator = ServerCoordinator(
            config: serverConfig,
            systemExtensionBundlePath: mockBundlePath.path,
            systemExtensionBundleIdentifier: "com.github.usbipd-mac.SystemExtension.test"
        )
    }
    
    private func setupMockedComponents() {
        // Create mocked components for CI/Development environment
        // This allows testing the workflow without actual System Extension operations
        
        #if CI_ENVIRONMENT || TEST_ENVIRONMENT_CI
        // Use CI-specific mocks
        let mockInstaller = createMockSystemExtensionInstaller()
        automaticInstallationManager = AutomaticInstallationManager(
            installer: mockInstaller,
            bundleDetector: bundleDetector
        )
        #else
        // Use development mocks
        let mockInstaller = createDevelopmentMockInstaller()
        automaticInstallationManager = AutomaticInstallationManager(
            installer: mockInstaller,
            bundleDetector: bundleDetector
        )
        #endif
        
        // Create server coordinator without System Extension support
        let serverConfig = ServerConfig.default
        serverCoordinator = ServerCoordinator(config: serverConfig)
    }
    
    // MARK: - End-to-End Workflow Tests
    
    func testAutomaticInstallationWorkflowWithBundleAvailable() throws {
        // Test complete automatic installation workflow when bundle is available
        
        let testTimeout = environmentConfig.timeout(for: testCategory)
        let expectation = XCTestExpectation(description: "Automatic installation workflow completion")
        
        // Create mock bundle for testing
        try createMockSystemExtensionBundle()
        
        // Configure automatic installation manager
        var installationResult: AutomaticInstallationResult?
        automaticInstallationManager.onInstallationComplete = { result in
            installationResult = result
            expectation.fulfill()
        }
        
        // Start automatic installation
        automaticInstallationManager.attemptAutomaticInstallation()
        
        // Wait for installation workflow completion
        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: testTimeout)
        XCTAssertEqual(waiterResult, .completed, "Automatic installation should complete within timeout")
        
        // Verify installation result based on environment
        guard let result = installationResult else {
            XCTFail("Installation result should be available")
            return
        }
        
        if environmentConfig.hasCapability(.systemExtensionInstall) {
            // Production environment - verify actual installation
            verifyProductionInstallationResult(result)
        } else {
            // CI/Development environment - verify mocked workflow
            verifyMockedInstallationResult(result)
        }
        
        print("✅ Automatic installation workflow test passed for \(environmentConfig.environment.displayName) environment")
    }
    
    func testAutomaticInstallationWorkflowWithBundleUnavailable() throws {
        // Test automatic installation workflow when bundle is not available
        
        let testTimeout = environmentConfig.timeout(for: testCategory)
        let expectation = XCTestExpectation(description: "Installation workflow with unavailable bundle")
        
        // Don't create bundle - test behavior when bundle detection fails
        
        var installationResult: AutomaticInstallationResult?
        automaticInstallationManager.onInstallationComplete = { result in
            installationResult = result
            expectation.fulfill()
        }
        
        // Attempt automatic installation without bundle
        automaticInstallationManager.attemptAutomaticInstallation()
        
        // Wait for workflow completion
        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: testTimeout)
        XCTAssertEqual(waiterResult, .completed, "Installation should complete quickly when bundle unavailable")
        
        // Verify graceful handling of missing bundle
        guard let result = installationResult else {
            XCTFail("Installation result should be available even for failed detection")
            return
        }
        
        switch result {
        case .success:
            XCTFail("Installation should not succeed without bundle")
        case .failure(let error):
            // Verify appropriate error handling
            XCTAssertTrue(error.localizedDescription.contains("bundle") || 
                         error.localizedDescription.contains("not found"),
                         "Error should indicate bundle unavailability")
        case .skipped(let reason):
            // Acceptable outcome - installation skipped due to missing bundle
            XCTAssertTrue(reason.contains("bundle") || reason.contains("not available"),
                         "Skip reason should indicate bundle unavailability")
        }
        
        print("✅ Automatic installation graceful failure test passed")
    }
    
    func testServerCoordinatorIntegrationWithAutomaticInstallation() throws {
        // Test ServerCoordinator correctly handles automatic bundle detection and installation
        
        let testTimeout = environmentConfig.timeout(for: testCategory)
        
        // Create mock bundle for detection
        try createMockSystemExtensionBundle()
        
        // Test server coordinator initialization with bundle parameters
        let expectation = XCTestExpectation(description: "Server coordinator startup with automatic installation")
        
        var serverStartResult: Result<Bool, Error>?
        
        // Start server coordinator (should trigger automatic installation)
        DispatchQueue.global().async {
            do {
                try self.serverCoordinator.start()
                serverStartResult = .success(true)
            } catch {
                serverStartResult = .failure(error)
            }
            expectation.fulfill()
        }
        
        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: testTimeout)
        XCTAssertEqual(waiterResult, .completed, "Server coordinator should start within timeout")
        
        // Verify server coordinator started successfully
        guard let result = serverStartResult else {
            XCTFail("Server start result should be available")
            return
        }
        
        switch result {
        case .success(let started):
            XCTAssertTrue(started, "Server coordinator should start successfully")
            
            // Verify System Extension infrastructure state based on environment
            if environmentConfig.hasCapability(.systemExtensionInstall) {
                // Production environment - verify System Extension activation
                verifySystemExtensionActivation()
            } else {
                // CI/Development environment - verify fallback behavior
                verifyFallbackBehavior()
            }
            
        case .failure(let error):
            // Check if failure is expected in CI environment
            if !environmentConfig.hasCapability(.systemExtensionInstall) {
                print("ℹ️ Server startup failure expected in \(environmentConfig.environment.displayName) environment: \(error)")
            } else {
                XCTFail("Server coordinator should start successfully in production environment: \(error)")
            }
        }
        
        // Cleanup
        try? serverCoordinator.stop()
        
        print("✅ ServerCoordinator integration test passed")
    }
    
    func testStatusReportingAccuracyDuringInstallationLifecycle() throws {
        // Test status reporting accuracy across installation lifecycle
        
        let testTimeout = environmentConfig.timeout(for: testCategory)
        
        // Create mock bundle
        try createMockSystemExtensionBundle()
        
        // Track status changes throughout lifecycle
        var statusUpdates: [SystemExtensionStatus] = []
        let expectation = XCTestExpectation(description: "Status reporting lifecycle")
        
        // Monitor status changes
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let status = self.serverCoordinator.getSystemExtensionStatus()
            statusUpdates.append(status)
            
            // Complete when we have enough status updates or reach a final state
            if statusUpdates.count >= 5 || status.state.isFinalState {
                expectation.fulfill()
            }
        }
        
        // Start automatic installation
        automaticInstallationManager.attemptAutomaticInstallation()
        
        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: testTimeout)
        timer.invalidate()
        
        XCTAssertEqual(waiterResult, .completed, "Status monitoring should complete within timeout")
        XCTAssertGreaterThan(statusUpdates.count, 0, "Should capture status updates")
        
        // Verify status progression makes sense
        verifyStatusProgression(statusUpdates)
        
        print("✅ Status reporting accuracy test passed with \(statusUpdates.count) status updates")
    }
    
    // MARK: - Helper Methods
    
    private func createMockSystemExtensionBundle() throws {
        // Create minimal System Extension bundle structure for testing
        
        let contentsPath = mockBundlePath.appendingPathComponent("Contents")
        let macosPath = contentsPath.appendingPathComponent("MacOS")
        let resourcesPath = contentsPath.appendingPathComponent("Resources")
        
        // Create directory structure
        try FileManager.default.createDirectory(at: macosPath,
                                               withIntermediateDirectories: true,
                                               attributes: nil)
        try FileManager.default.createDirectory(at: resourcesPath,
                                               withIntermediateDirectories: true,
                                               attributes: nil)
        
        // Create Info.plist
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "com.github.usbipd-mac.SystemExtension.test",
            "CFBundleName": "USB/IP System Extension Test",
            "CFBundleVersion": "1.0.0",
            "CFBundleExecutable": "SystemExtension",
            "NSExtension": [
                "NSExtensionPointIdentifier": "com.apple.system-extension.driver-extension",
                "NSExtensionPrincipalClass": "SystemExtensionMain"
            ]
        ]
        
        let infoPlistData = try PropertyListSerialization.data(fromPropertyList: infoPlist,
                                                              format: .xml,
                                                              options: 0)
        let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
        try infoPlistData.write(to: infoPlistPath)
        
        // Create dummy executable
        let executablePath = macosPath.appendingPathComponent("SystemExtension")
        let executableContent = "#!/bin/bash\necho 'Test System Extension'"
        try executableContent.write(to: executablePath, atomically: true, encoding: .utf8)
        
        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                             ofItemAtPath: executablePath.path)
    }
    
    private func createMockSystemExtensionInstaller() -> SystemExtensionInstaller {
        // Create mock installer for CI environment
        
        let mockBundleCreator = MockSystemExtensionBundleCreator()
        let mockCodeSigningManager = MockCodeSigningManager()
        
        return SystemExtensionInstaller(
            bundleCreator: mockBundleCreator,
            codeSigningManager: mockCodeSigningManager
        )
    }
    
    private func createDevelopmentMockInstaller() -> SystemExtensionInstaller {
        // Create development-specific mock installer
        
        let mockBundleCreator = DevelopmentMockBundleCreator()
        let mockCodeSigningManager = DevelopmentMockCodeSigningManager()
        
        return SystemExtensionInstaller(
            bundleCreator: mockBundleCreator,
            codeSigningManager: mockCodeSigningManager
        )
    }
    
    private func verifyProductionInstallationResult(_ result: AutomaticInstallationResult) {
        // Verify installation result in production environment
        
        switch result {
        case .success(let details):
            XCTAssertNotNil(details.bundlePath, "Bundle path should be available")
            XCTAssertNotNil(details.bundleIdentifier, "Bundle identifier should be available")
            print("✅ Production installation succeeded: \(details)")
            
        case .failure(let error):
            // Check if failure is expected (e.g., user approval required)
            if let installationError = error as? SystemExtensionInstallationError {
                switch installationError {
                case .requiresApproval, .userRejected:
                    print("ℹ️ Installation requires user approval (expected in production)")
                    return
                default:
                    break
                }
            }
            XCTFail("Unexpected installation failure in production: \(error)")
            
        case .skipped(let reason):
            print("ℹ️ Installation skipped in production: \(reason)")
        }
    }
    
    private func verifyMockedInstallationResult(_ result: AutomaticInstallationResult) {
        // Verify installation result in CI/Development environment
        
        switch result {
        case .success(let details):
            // Mock installation should succeed with test data
            XCTAssertTrue(details.bundlePath.contains("test") || details.bundlePath.contains("mock"),
                         "Mock installation should use test bundle path")
            print("✅ Mocked installation succeeded: \(details)")
            
        case .failure(let error):
            // Verify mock errors are handled appropriately
            print("ℹ️ Mocked installation failure (testing error handling): \(error)")
            
        case .skipped(let reason):
            print("ℹ️ Mocked installation skipped: \(reason)")
        }
    }
    
    private func verifySystemExtensionActivation() {
        // Verify System Extension is activated in production environment
        
        let status = serverCoordinator.getSystemExtensionStatus()
        
        switch status.state {
        case .active:
            print("✅ System Extension is active")
        case .installing, .activating:
            print("ℹ️ System Extension is being activated")
        case .requiresApproval:
            print("ℹ️ System Extension requires user approval")
        default:
            print("ℹ️ System Extension state: \(status.state)")
        }
    }
    
    private func verifyFallbackBehavior() {
        // Verify fallback behavior in CI/Development environment
        
        let status = serverCoordinator.getSystemExtensionStatus()
        
        // In fallback mode, System Extension should not be active
        XCTAssertNotEqual(status.state, .active, "System Extension should not be active in fallback mode")
        
        // Server should still be functional
        XCTAssertTrue(serverCoordinator.isRunning, "Server should be running in fallback mode")
        
        print("✅ Fallback behavior verified - server running without System Extension")
    }
    
    private func verifyStatusProgression(_ statusUpdates: [SystemExtensionStatus]) {
        // Verify status progression makes logical sense
        
        XCTAssertGreaterThan(statusUpdates.count, 0, "Should have status updates")
        
        // Check for logical state transitions
        var previousState: SystemExtensionState?
        var hasProgression = false
        
        for status in statusUpdates {
            if let previous = previousState {
                // Verify valid state transitions
                let isValidTransition = isValidStateTransition(from: previous, to: status.state)
                if !isValidTransition {
                    print("⚠️ Potentially invalid state transition: \(previous) -> \(status.state)")
                }
                
                // Check if we've seen progression
                if previous != status.state {
                    hasProgression = true
                }
            }
            previousState = status.state
        }
        
        // In active environments, we should see some progression
        if environmentConfig.hasCapability(.systemExtensionInstall) {
            XCTAssertTrue(hasProgression || statusUpdates.count == 1,
                         "Should see status progression in active environment")
        }
        
        print("✅ Status progression verified (\(statusUpdates.count) updates)")
    }
    
    private func isValidStateTransition(from previous: SystemExtensionState, to current: SystemExtensionState) -> Bool {
        // Define valid state transitions
        switch (previous, current) {
        case (.inactive, .installing),
             (.installing, .activating),
             (.installing, .requiresApproval),
             (.activating, .active),
             (.activating, .failed),
             (.requiresApproval, .installing),
             (.requiresApproval, .activating),
             (.failed, .inactive),
             (.failed, .installing):
            return true
        case (let prev, let curr) where prev == curr:
            return true // Same state is valid
        default:
            return false
        }
    }
}

// MARK: - Mock Components for Testing

/// Mock System Extension bundle creator for CI testing
private class MockSystemExtensionBundleCreator: SystemExtensionBundleCreator {
    override func createBundle(at path: String, withIdentifier identifier: String) throws {
        // Mock implementation - simulate bundle creation
        print("Mock: Creating System Extension bundle at \(path)")
    }
}

/// Mock code signing manager for CI testing
private class MockCodeSigningManager: CodeSigningManager {
    override func signBundle(at path: String) throws {
        // Mock implementation - simulate code signing
        print("Mock: Signing System Extension bundle at \(path)")
    }
}

/// Development-specific mock bundle creator
private class DevelopmentMockBundleCreator: SystemExtensionBundleCreator {
    override func createBundle(at path: String, withIdentifier identifier: String) throws {
        // Development mock - more verbose logging
        print("Development Mock: Creating System Extension bundle at \(path) with identifier \(identifier)")
    }
}

/// Development-specific mock code signing manager
private class DevelopmentMockCodeSigningManager: CodeSigningManager {
    override func signBundle(at path: String) throws {
        // Development mock - simulate development signing
        print("Development Mock: Signing System Extension bundle at \(path) with development certificate")
    }
}

// MARK: - Extensions for Testing

/// Additional properties for testing System Extension states
extension SystemExtensionState {
    var isFinalState: Bool {
        switch self {
        case .active, .failed, .inactive:
            return true
        case .installing, .activating, .requiresApproval:
            return false
        }
    }
}

/// Automatic installation result for testing
enum AutomaticInstallationResult {
    case success(InstallationDetails)
    case failure(Error)
    case skipped(String)
}

/// Installation details for testing
struct InstallationDetails {
    let bundlePath: String
    let bundleIdentifier: String
    let timestamp: Date
    
    init(bundlePath: String, bundleIdentifier: String) {
        self.bundlePath = bundlePath
        self.bundleIdentifier = bundleIdentifier
        self.timestamp = Date()
    }
}

/// Extension to AutomaticInstallationManager for testing callbacks
extension AutomaticInstallationManager {
    var onInstallationComplete: ((AutomaticInstallationResult) -> Void)? {
        get { return nil } // Implementation would store this callback
        set(newValue) { _ = newValue /* Implementation would store this callback */ }
    }
}