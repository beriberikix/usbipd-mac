// HomebrewInstallationTests.swift
// Comprehensive unit tests for Homebrew installation components

import XCTest
import Foundation
@testable import USBIPDCore
@testable import Common

final class HomebrewInstallationTests: XCTestCase, TestSuite {
    
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
    
    private var tempDirectory: URL!
    private var mockLogger: MockLogger!
    private var homebrewBundleCreator: HomebrewBundleCreator!
    private var developerModeDetector: DeveloperModeDetector!
    private var automaticInstallationManager: AutomaticInstallationManager!
    private var systemExtensionBundleValidator: SystemExtensionBundleValidator!
    private var installationErrorHandler: InstallationErrorHandler!
    private var installationProgressReporter: InstallationProgressReporter!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        try validateEnvironment()
        
        // Create temporary directory for testing
        tempDirectory = TestEnvironmentFixtures.createTemporaryDirectory()
        
        // Set up mock logger
        mockLogger = MockLogger()
        
        // Initialize components under test
        homebrewBundleCreator = HomebrewBundleCreator(logger: mockLogger)
        developerModeDetector = DeveloperModeDetector(logger: mockLogger)
        systemExtensionBundleValidator = SystemExtensionBundleValidator(logger: mockLogger)
        installationErrorHandler = InstallationErrorHandler(logger: mockLogger)
        installationProgressReporter = InstallationProgressReporter(logger: mockLogger)
        
        // Initialize automatic installation manager with mocks
        automaticInstallationManager = AutomaticInstallationManager(
            config: createTestServerConfig(),
            installer: MockSystemExtensionInstaller(),
            bundleDetector: MockBundleDetector(),
            logger: mockLogger
        )
    }
    
    override func tearDownWithError() throws {
        // Clean up temporary directory
        TestEnvironmentFixtures.cleanupTemporaryDirectory(tempDirectory)
        
        installationProgressReporter = nil
        installationErrorHandler = nil
        systemExtensionBundleValidator = nil
        automaticInstallationManager = nil
        developerModeDetector = nil
        homebrewBundleCreator = nil
        mockLogger = nil
        tempDirectory = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - HomebrewBundleCreator Tests
    
    func testHomebrewBundleConfigurationValidation() throws {
        // Given: Valid configuration
        let validConfig = createValidHomebrewConfig()
        
        // When: Validating configuration
        let issues = homebrewBundleCreator.validateHomebrewConfig(validConfig)
        
        // Then: Should have no validation issues
        XCTAssertTrue(issues.isEmpty, "Valid configuration should have no issues: \(issues)")
        
        // Given: Invalid configuration with missing fields
        let invalidConfig = HomebrewBundleConfig(
            homebrewPrefix: "", // Empty prefix
            formulaVersion: "", // Empty version
            installationPrefix: tempDirectory.path,
            bundleIdentifier: "invalid-bundle-id", // Invalid format
            displayName: "Test Bundle",
            executableName: "test-executable",
            teamIdentifier: nil,
            executablePath: "/nonexistent/path", // Nonexistent executable
            formulaName: "test-formula",
            buildNumber: "1"
        )
        
        // When: Validating invalid configuration
        let invalidIssues = homebrewBundleCreator.validateHomebrewConfig(invalidConfig)
        
        // Then: Should have multiple validation issues
        XCTAssertGreaterThan(invalidIssues.count, 0, "Invalid configuration should have issues")
        XCTAssertTrue(invalidIssues.contains { $0.contains("prefix cannot be empty") })
        XCTAssertTrue(invalidIssues.contains { $0.contains("version cannot be empty") })
        XCTAssertTrue(invalidIssues.contains { $0.contains("invalid format") })
        XCTAssertTrue(invalidIssues.contains { $0.contains("does not exist") })
    }
    
    func testHomebrewBundlePathResolution() throws {
        // Given: Homebrew configuration
        let config = createValidHomebrewConfig()
        
        // When: Resolving bundle path
        let bundlePath = homebrewBundleCreator.resolveBundlePath(from: config)
        
        // Then: Should generate correct path
        XCTAssertTrue(bundlePath.contains(config.installationPrefix))
        XCTAssertTrue(bundlePath.hasSuffix("\(config.formulaName).systemextension"))
        XCTAssertTrue(bundlePath.isAbsolutePath, "Bundle path should be absolute")
        
        // When: Resolving installation prefix
        let installationPrefix = homebrewBundleCreator.resolveInstallationPrefix(from: config)
        
        // Then: Should include Library/SystemExtensions
        XCTAssertTrue(installationPrefix.contains("Library/SystemExtensions"))
        XCTAssertTrue(installationPrefix.hasPrefix(config.installationPrefix))
    }
    
    func testHomebrewBuildNumberGeneration() throws {
        // Given: Configuration with various version formats
        let configs = [
            createValidHomebrewConfig(version: "1.2.3"),
            createValidHomebrewConfig(version: "2.0"),
            createValidHomebrewConfig(version: "3"),
            createValidHomebrewConfig(version: "invalid.version"),
            createValidHomebrewConfig(version: "", buildNumber: "42")
        ]
        
        for config in configs {
            // When: Generating build number
            let buildNumber = homebrewBundleCreator.generateBuildNumber(from: config)
            
            // Then: Should generate valid build number
            XCTAssertFalse(buildNumber.isEmpty, "Build number should not be empty")
            XCTAssertTrue(buildNumber.allSatisfy { $0.isNumber }, "Build number should contain only digits")
            
            // Check specific version formats
            if config.formulaVersion == "1.2.3" {
                XCTAssertEqual(buildNumber, "10203", "Should generate correct build number for 1.2.3")
            } else if config.formulaVersion == "2.0" {
                XCTAssertEqual(buildNumber, "20000", "Should generate correct build number for 2.0")
            } else if config.formulaVersion == "3" {
                XCTAssertEqual(buildNumber, "30000", "Should generate correct build number for 3")
            } else if config.buildNumber == "42" {
                XCTAssertEqual(buildNumber, "42", "Should use provided build number when available")
            }
        }
    }
    
    func testHomebrewBundleCreationWithMockExecutable() throws {
        // Given: Valid configuration with mock executable
        let executablePath = createMockExecutable()
        let config = createValidHomebrewConfig(executablePath: executablePath)
        
        // Mock SystemExtensionBundleCreator behavior
        let mockBundleCreator = MockSystemExtensionBundleCreator()
        let expectedBundle = SystemExtensionTestFixtures.createMockBundle(
            bundlePath: homebrewBundleCreator.resolveBundlePath(from: config),
            bundleIdentifier: config.bundleIdentifier
        )
        mockBundleCreator.createBundleResult = expectedBundle
        mockBundleCreator.completeBundleResult = expectedBundle
        
        // Replace internal bundle creator with mock
        let homebrewCreatorWithMock = MockHomebrewBundleCreator(
            mockBundleCreator: mockBundleCreator,
            logger: mockLogger
        )
        
        // When: Creating Homebrew bundle
        let bundle = try homebrewCreatorWithMock.createHomebrewBundle(with: config)
        
        // Then: Should create bundle successfully
        XCTAssertEqual(bundle.bundleIdentifier, config.bundleIdentifier)
        XCTAssertEqual(bundle.displayName, config.displayName)
        XCTAssertEqual(bundle.version, config.formulaVersion)
        XCTAssertEqual(bundle.executableName, config.executableName)
        
        // Verify mock interactions
        XCTAssertEqual(mockBundleCreator.createBundleCalls.count, 1)
        XCTAssertEqual(mockBundleCreator.completeBundleCalls.count, 1)
        
        // Verify logging
        XCTAssertTrue(mockLogger.infoMessages.contains { $0.contains("Starting Homebrew System Extension bundle creation") })
        XCTAssertTrue(mockLogger.infoMessages.contains { $0.contains("bundle creation completed") })
    }
    
    // MARK: - DeveloperModeDetector Tests
    
    func testDeveloperModeDetectionWithMockEnvironment() throws {
        // Skip this test in CI environment as it requires system interaction
        #if CI_ENVIRONMENT
        throw XCTSkip("Skipping developer mode detection tests in CI environment")
        #endif
        
        // Given: Mock developer mode detector
        let mockDetector = MockDeveloperModeDetector()
        
        // Test enabled state
        mockDetector.isDeveloperModeEnabledResult = true
        XCTAssertTrue(try mockDetector.isDeveloperModeEnabled(), "Should detect enabled developer mode")
        
        // Test disabled state
        mockDetector.isDeveloperModeEnabledResult = false
        XCTAssertFalse(try mockDetector.isDeveloperModeEnabled(), "Should detect disabled developer mode")
        
        // Test error state
        mockDetector.isDeveloperModeEnabledError = InstallationError.developerModeDetectionFailed("Mock error")
        XCTAssertThrowsError(try mockDetector.isDeveloperModeEnabled()) { error in
            XCTAssertTrue(error is InstallationError)
            if case .developerModeDetectionFailed(let message) = error as! InstallationError {
                XCTAssertEqual(message, "Mock error")
            } else {
                XCTFail("Expected developerModeDetectionFailed error")
            }
        }
    }
    
    func testDeveloperModeValidationRequirements() throws {
        // Given: Mock detector with various states
        let mockDetector = MockDeveloperModeDetector()
        
        // Test validation requirements for enabled state
        mockDetector.isDeveloperModeEnabledResult = true
        let enabledRequirements = try mockDetector.getValidationRequirements()
        XCTAssertTrue(enabledRequirements.allowsAutomaticInstallation)
        XCTAssertFalse(enabledRequirements.requiresUserApproval)
        
        // Test validation requirements for disabled state
        mockDetector.isDeveloperModeEnabledResult = false
        let disabledRequirements = try mockDetector.getValidationRequirements()
        XCTAssertFalse(disabledRequirements.allowsAutomaticInstallation)
        XCTAssertTrue(disabledRequirements.requiresUserApproval)
    }
    
    // MARK: - AutomaticInstallationManager Tests
    
    func testAutomaticInstallationManagerIntegration() throws {
        // Given: Mock installation manager with valid configuration
        let mockInstaller = MockSystemExtensionInstaller()
        let mockBundleDetector = MockBundleDetector()
        
        mockBundleDetector.detectionResult = SystemExtensionBundleDetector.DetectionResult(
            found: true,
            bundlePath: tempDirectory.appendingPathComponent("test.systemextension").path,
            bundleIdentifier: "com.test.systemextension",
            issues: [],
            detectionTime: Date()
        )
        
        mockInstaller.installationResult = InstallationResult(
            success: true,
            errors: [],
            installationTime: 1.0,
            installationMethod: .automatic
        )
        
        let manager = AutomaticInstallationManager(
            config: createTestServerConfig(),
            installer: mockInstaller,
            bundleDetector: mockBundleDetector,
            logger: mockLogger
        )
        
        let expectation = XCTestExpectation(description: "Installation completion")
        
        // When: Attempting automatic installation
        manager.attemptAutomaticInstallation { result in
            // Then: Should succeed
            XCTAssertTrue(result.success, "Installation should succeed")
            XCTAssertEqual(result.finalStatus, .installed)
            XCTAssertTrue(result.errors.isEmpty)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: TestEnvironmentFixtures.shortTimeout)
        
        // Verify installation status
        let (state, history) = manager.getInstallationStatus()
        XCTAssertEqual(state, .completed)
        XCTAssertEqual(history.count, 1)
        XCTAssertTrue(history.first?.success == true)
    }
    
    func testAutomaticInstallationFallbackScenarios() throws {
        // Given: Installation manager with various failure scenarios
        let testScenarios: [(InstallationResult, AutomaticInstallationManager.RecommendedAction)] = [
            (InstallationResult(
                success: false,
                errors: [.userApprovalRequired("User approval needed")],
                installationTime: 0.5,
                installationMethod: .automatic
            ), .requiresUserApproval),
            
            (InstallationResult(
                success: false,
                errors: [.developerModeRequired("Developer mode needed")],
                installationTime: 0.3,
                installationMethod: .automatic
            ), .checkConfiguration),
            
            (InstallationResult(
                success: false,
                errors: [.bundleValidationFailed("Invalid bundle")],
                installationTime: 0.1,
                installationMethod: .automatic
            ), .checkConfiguration),
            
            (InstallationResult(
                success: false,
                errors: [.installationFailed("Generic failure")],
                installationTime: 0.2,
                installationMethod: .automatic
            ), .retryLater)
        ]
        
        for (installationResult, expectedAction) in testScenarios {
            // Given: Fresh installation manager for each scenario
            let mockInstaller = MockSystemExtensionInstaller()
            let mockBundleDetector = MockBundleDetector()
            
            mockBundleDetector.detectionResult = SystemExtensionBundleDetector.DetectionResult(
                found: true,
                bundlePath: tempDirectory.appendingPathComponent("test.systemextension").path,
                bundleIdentifier: "com.test.systemextension",
                issues: [],
                detectionTime: Date()
            )
            
            mockInstaller.installationResult = installationResult
            
            let manager = AutomaticInstallationManager(
                config: createTestServerConfig(),
                installer: mockInstaller,
                bundleDetector: mockBundleDetector,
                logger: mockLogger
            )
            
            let expectation = XCTestExpectation(description: "Installation scenario: \(expectedAction)")
            
            // When: Attempting automatic installation
            manager.attemptAutomaticInstallation { result in
                // Then: Should fail with expected action
                XCTAssertFalse(result.success, "Installation should fail for scenario: \(expectedAction)")
                XCTAssertEqual(result.recommendedAction, expectedAction, "Should recommend correct action for scenario")
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: TestEnvironmentFixtures.shortTimeout)
        }
    }
    
    // MARK: - SystemExtensionBundleValidator Tests
    
    func testSystemExtensionBundleValidation() throws {
        // Given: Mock bundle with validation scenarios
        let validBundle = SystemExtensionTestFixtures.createMockBundle(
            bundlePath: tempDirectory.appendingPathComponent("valid.systemextension").path,
            bundleIdentifier: "com.test.valid"
        )
        
        let invalidBundle = SystemExtensionTestFixtures.createMockBundle(
            bundlePath: tempDirectory.appendingPathComponent("invalid.systemextension").path,
            bundleIdentifier: "invalid-bundle-id"
        )
        
        // When: Validating bundles
        let validResult = systemExtensionBundleValidator.validateBundle(validBundle)
        let invalidResult = systemExtensionBundleValidator.validateBundle(invalidBundle)
        
        // Then: Should correctly identify valid and invalid bundles
        XCTAssertTrue(validResult.isValid, "Valid bundle should pass validation")
        XCTAssertTrue(validResult.issues.isEmpty, "Valid bundle should have no issues")
        
        XCTAssertFalse(invalidResult.isValid, "Invalid bundle should fail validation")
        XCTAssertGreaterThan(invalidResult.issues.count, 0, "Invalid bundle should have issues")
    }
    
    func testBundleStructureValidation() throws {
        // Given: Bundle with missing required components
        let bundlePath = tempDirectory.appendingPathComponent("incomplete.systemextension").path
        
        // Create incomplete bundle structure
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true, attributes: nil)
        
        let bundle = SystemExtensionBundle(
            bundlePath: bundlePath,
            bundleIdentifier: "com.test.incomplete",
            displayName: "Incomplete Bundle",
            version: "1.0.0",
            buildNumber: "1",
            executableName: "test-executable",
            teamIdentifier: nil,
            contents: SystemExtensionBundle.BundleContents(
                infoPlistPath: bundlePath + "/Contents/Info.plist",
                executablePath: bundlePath + "/Contents/MacOS/test-executable",
                entitlementsPath: nil,
                resourceFiles: [],
                bundleSize: 1024,
                isValid: false
            ),
            creationTime: Date()
        )
        
        // When: Validating incomplete bundle
        let result = systemExtensionBundleValidator.validateBundle(bundle)
        
        // Then: Should identify missing components
        XCTAssertFalse(result.isValid, "Incomplete bundle should fail validation")
        XCTAssertTrue(result.issues.contains { $0.contains("Info.plist") }, "Should identify missing Info.plist")
        XCTAssertTrue(result.issues.contains { $0.contains("executable") }, "Should identify missing executable")
    }
    
    // MARK: - InstallationErrorHandler Tests
    
    func testInstallationErrorHandling() throws {
        // Given: Various installation error scenarios
        let errorScenarios: [(InstallationError, String)] = [
            (.userApprovalRequired("User approval needed"), "approval"),
            (.developerModeRequired("Developer mode required"), "developer mode"),
            (.bundleValidationFailed("Invalid bundle"), "bundle"),
            (.installationFailed("Generic failure"), "installation"),
            (.bundleCreationFailed("Creation failed"), "creation"),
            (.unknownError("Unknown error"), "unknown")
        ]
        
        for (error, expectedKeyword) in errorScenarios {
            // When: Handling error
            let errorReport = installationErrorHandler.handleInstallationError(error)
            
            // Then: Should generate appropriate error report
            XCTAssertFalse(errorReport.userMessage.isEmpty, "Should generate user message for error: \(error)")
            XCTAssertFalse(errorReport.technicalDetails.isEmpty, "Should generate technical details for error: \(error)")
            XCTAssertFalse(errorReport.remediationSteps.isEmpty, "Should provide remediation steps for error: \(error)")
            
            // Verify error-specific content
            let combinedContent = "\(errorReport.userMessage) \(errorReport.technicalDetails)".lowercased()
            XCTAssertTrue(combinedContent.contains(expectedKeyword), "Should mention '\(expectedKeyword)' for error: \(error)")
        }
    }
    
    func testErrorRecoveryGuidance() throws {
        // Given: Error handler with different error categories
        let criticalError = InstallationError.bundleCreationFailed("Critical bundle creation failure")
        let recoverableError = InstallationError.userApprovalRequired("User needs to approve")
        
        // When: Getting recovery guidance
        let criticalGuidance = installationErrorHandler.generateRecoveryGuidance(for: criticalError)
        let recoverableGuidance = installationErrorHandler.generateRecoveryGuidance(for: recoverableError)
        
        // Then: Should provide appropriate guidance
        XCTAssertTrue(criticalGuidance.shouldContactSupport, "Critical errors should recommend contacting support")
        XCTAssertGreaterThan(criticalGuidance.automaticRetryRecommended, 0, "Critical errors should suggest retry delay")
        
        XCTAssertFalse(recoverableGuidance.shouldContactSupport, "Recoverable errors should not require support")
        XCTAssertFalse(recoverableGuidance.remediationSteps.isEmpty, "Should provide recovery steps")
    }
    
    // MARK: - InstallationProgressReporter Tests
    
    func testInstallationProgressReporting() throws {
        // Given: Progress reporter
        let mockProgressDelegate = MockProgressDelegate()
        installationProgressReporter.setProgressDelegate(mockProgressDelegate)
        
        // When: Reporting installation progress
        installationProgressReporter.reportProgress(.bundleCreation, progress: 0.0)
        installationProgressReporter.reportProgress(.bundleCreation, progress: 0.5)
        installationProgressReporter.reportProgress(.bundleCreation, progress: 1.0)
        installationProgressReporter.reportProgress(.installation, progress: 0.0)
        installationProgressReporter.reportProgress(.installation, progress: 1.0)
        installationProgressReporter.reportProgress(.verification, progress: 1.0)
        
        // Then: Should report progress correctly
        XCTAssertEqual(mockProgressDelegate.progressUpdates.count, 6, "Should receive all progress updates")
        
        let finalUpdate = mockProgressDelegate.progressUpdates.last!
        XCTAssertEqual(finalUpdate.phase, .verification)
        XCTAssertEqual(finalUpdate.progress, 1.0)
    }
    
    func testInstallationCompletionReporting() throws {
        // Given: Installation completion scenarios
        let successResult = AutomaticInstallationManager.InstallationAttemptResult(
            success: true,
            finalStatus: .installed,
            errors: [],
            duration: 2.5,
            recommendedAction: .none,
            requiresUserApproval: false
        )
        
        let failureResult = AutomaticInstallationManager.InstallationAttemptResult(
            success: false,
            finalStatus: .installationFailed,
            errors: [.installationFailed("Test failure")],
            duration: 1.0,
            recommendedAction: .retryLater,
            requiresUserApproval: false
        )
        
        // When: Reporting completion
        let successReport = installationProgressReporter.generateCompletionReport(successResult)
        let failureReport = installationProgressReporter.generateCompletionReport(failureResult)
        
        // Then: Should generate appropriate reports
        XCTAssertTrue(successReport.contains("successful"), "Success report should mention success")
        XCTAssertTrue(successReport.contains("2.5"), "Success report should include duration")
        
        XCTAssertTrue(failureReport.contains("failed"), "Failure report should mention failure")
        XCTAssertTrue(failureReport.contains("retry"), "Failure report should mention retry recommendation")
    }
    
    // MARK: - Error Handling and Fallback Instruction Generation Tests
    
    func testFallbackInstructionGeneration() throws {
        // Given: Various error scenarios requiring fallback instructions
        let errorScenarios = [
            InstallationError.userApprovalRequired("User approval needed"),
            InstallationError.developerModeRequired("Developer mode required"),
            InstallationError.installationFailed("Installation failed")
        ]
        
        for error in errorScenarios {
            // When: Generating fallback instructions
            let instructions = installationErrorHandler.generateFallbackInstructions(for: error)
            
            // Then: Should provide clear instructions
            XCTAssertFalse(instructions.isEmpty, "Should generate fallback instructions for error: \(error)")
            XCTAssertTrue(instructions.contains("usbipd"), "Instructions should mention the command")
            
            // Verify error-specific instructions
            switch error {
            case .userApprovalRequired:
                XCTAssertTrue(instructions.lowercased().contains("system preferences") || 
                            instructions.lowercased().contains("security"), "Should mention system security settings")
            case .developerModeRequired:
                XCTAssertTrue(instructions.lowercased().contains("developer mode"), "Should mention developer mode")
            case .installationFailed:
                XCTAssertTrue(instructions.lowercased().contains("manual"), "Should mention manual installation")
            default:
                break
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createValidHomebrewConfig(
        version: String = "1.0.0",
        buildNumber: String = "1",
        executablePath: String? = nil
    ) -> HomebrewBundleConfig {
        let actualExecutablePath = executablePath ?? createMockExecutable()
        
        return HomebrewBundleConfig(
            homebrewPrefix: tempDirectory.path,
            formulaVersion: version,
            installationPrefix: tempDirectory.appendingPathComponent("prefix").path,
            bundleIdentifier: "com.test.homebrew.bundle",
            displayName: "Test Homebrew Bundle",
            executableName: "test-executable",
            teamIdentifier: "TESTTEAM123",
            executablePath: actualExecutablePath,
            formulaName: "test-formula",
            buildNumber: buildNumber
        )
    }
    
    private func createMockExecutable() -> String {
        let executablePath = tempDirectory.appendingPathComponent("test-executable").path
        let executableData = "#!/bin/sh\necho 'Mock executable'\n".data(using: .utf8)!
        
        FileManager.default.createFile(atPath: executablePath, contents: executableData, attributes: [
            .posixPermissions: 0o755
        ])
        
        return executablePath
    }
    
    private func createTestServerConfig() -> ServerConfig {
        return ServerConfig(
            port: 3240,
            logLevel: .debug,
            debugMode: true,
            maxConnections: 10,
            connectionTimeout: 30.0,
            allowedDevices: [],
            autoBindDevices: false,
            logFilePath: nil
        )
    }
}

// MARK: - Mock Classes

/// Mock logger for testing
private class MockLogger: Logger {
    var debugMessages: [String] = []
    var infoMessages: [String] = []
    var warningMessages: [String] = []
    var errorMessages: [String] = []
    
    override func debug(_ message: String, context: [String: Any]? = nil) {
        debugMessages.append(message)
    }
    
    override func info(_ message: String, context: [String: Any]? = nil) {
        infoMessages.append(message)
    }
    
    override func warning(_ message: String, context: [String: Any]? = nil) {
        warningMessages.append(message)
    }
    
    override func error(_ message: String, context: [String: Any]? = nil) {
        errorMessages.append(message)
    }
}

/// Mock SystemExtensionBundleCreator for testing
private class MockSystemExtensionBundleCreator: SystemExtensionBundleCreator {
    var createBundleResult: SystemExtensionBundle?
    var completeBundleResult: SystemExtensionBundle?
    var createBundleCalls: [SystemExtensionBundleCreator.BundleCreationConfig] = []
    var completeBundleCalls: [SystemExtensionBundle] = []
    
    override func createBundle(with config: BundleCreationConfig) throws -> SystemExtensionBundle {
        createBundleCalls.append(config)
        
        guard let result = createBundleResult else {
            throw InstallationError.bundleCreationFailed("Mock bundle creation not configured")
        }
        
        return result
    }
    
    override func completeBundle(_ bundle: SystemExtensionBundle, with config: BundleCreationConfig) throws -> SystemExtensionBundle {
        completeBundleCalls.append(bundle)
        
        guard let result = completeBundleResult else {
            throw InstallationError.bundleCreationFailed("Mock bundle completion not configured")
        }
        
        return result
    }
}

/// Mock HomebrewBundleCreator that uses mock internal bundle creator
private class MockHomebrewBundleCreator: HomebrewBundleCreator {
    private let mockBundleCreator: MockSystemExtensionBundleCreator
    
    init(mockBundleCreator: MockSystemExtensionBundleCreator, logger: Logger) {
        self.mockBundleCreator = mockBundleCreator
        super.init(logger: logger)
    }
    
    override func createHomebrewBundle(with config: HomebrewBundleConfig) throws -> SystemExtensionBundle {
        // Simulate bundle creation using mock
        let bundlePath = resolveBundlePath(from: config)
        let buildNumber = generateBuildNumber(from: config)
        
        let bundleCreationConfig = SystemExtensionBundleCreator.BundleCreationConfig(
            bundlePath: bundlePath,
            bundleIdentifier: config.bundleIdentifier,
            displayName: config.displayName,
            version: config.formulaVersion,
            buildNumber: buildNumber,
            executableName: config.executableName,
            teamIdentifier: config.teamIdentifier,
            executablePath: config.executablePath
        )
        
        let bundle = try mockBundleCreator.createBundle(with: bundleCreationConfig)
        return try mockBundleCreator.completeBundle(bundle, with: bundleCreationConfig)
    }
}

/// Mock DeveloperModeDetector for testing
private class MockDeveloperModeDetector: DeveloperModeDetector {
    var isDeveloperModeEnabledResult: Bool = false
    var isDeveloperModeEnabledError: Error?
    
    override func isDeveloperModeEnabled() throws -> Bool {
        if let error = isDeveloperModeEnabledError {
            throw error
        }
        return isDeveloperModeEnabledResult
    }
    
    func getValidationRequirements() throws -> (allowsAutomaticInstallation: Bool, requiresUserApproval: Bool) {
        let enabled = try isDeveloperModeEnabled()
        return (allowsAutomaticInstallation: enabled, requiresUserApproval: !enabled)
    }
}

/// Mock SystemExtensionInstaller for testing
private class MockSystemExtensionInstaller: SystemExtensionInstaller {
    var installationResult: InstallationResult?
    var installationCalls: [Date] = []
    
    override func installSystemExtension(
        bundleIdentifier: String,
        executablePath: String,
        completion: @escaping InstallationCompletion
    ) {
        installationCalls.append(Date())
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            let result = self.installationResult ?? InstallationResult(
                success: false,
                errors: [.unknownError("Mock installation not configured")]
            )
            completion(result)
        }
    }
}

/// Mock BundleDetector for testing
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

/// Mock progress delegate for testing
private class MockProgressDelegate: InstallationProgressDelegate {
    var progressUpdates: [(phase: InstallationProgressReporter.InstallationPhase, progress: Double)] = []
    
    func installationProgress(_ phase: InstallationProgressReporter.InstallationPhase, progress: Double) {
        progressUpdates.append((phase: phase, progress: progress))
    }
}

/// Extension to SystemExtensionTestFixtures for additional mock creation
extension SystemExtensionTestFixtures {
    static func createMockBundle(bundlePath: String, bundleIdentifier: String) -> SystemExtensionBundle {
        return SystemExtensionBundle(
            bundlePath: bundlePath,
            bundleIdentifier: bundleIdentifier,
            displayName: "Mock Bundle",
            version: "1.0.0",
            buildNumber: "1",
            executableName: "mock-executable",
            teamIdentifier: "MOCKTEAM123",
            contents: SystemExtensionBundle.BundleContents(
                infoPlistPath: bundlePath + "/Contents/Info.plist",
                executablePath: bundlePath + "/Contents/MacOS/mock-executable",
                entitlementsPath: bundlePath + "/Contents/MockExtension.entitlements",
                resourceFiles: [],
                bundleSize: 2048,
                isValid: bundleIdentifier.contains("valid")
            ),
            creationTime: Date()
        )
    }
}

/// String extension for path validation
private extension String {
    var isAbsolutePath: Bool {
        return hasPrefix("/")
    }
}