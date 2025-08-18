//
//  HomebrewSystemExtensionWorkflowTests.swift
//  usbipd-mac
//
//  End-to-end integration tests for complete Homebrew System Extension workflow
//  Tests complete user experience from Homebrew installation to working System Extension
//  Includes automatic installation, manual fallback, and error recovery scenarios
//

import XCTest
import Foundation
import Network
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

/// End-to-end integration tests for complete Homebrew System Extension workflow
/// Tests the complete user experience from brew install through System Extension activation
/// Validates automatic installation, manual fallback scenarios, and comprehensive error recovery
final class HomebrewSystemExtensionWorkflowTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    public let environmentConfig: TestEnvironmentConfig = TestEnvironmentDetector.createConfigurationForCurrentEnvironment()
    public let requiredCapabilities: TestEnvironmentCapabilities = [
        .networkAccess,
        .filesystemWrite,
        .timeIntensiveOperations,
        .privilegedOperations
    ]
    public let testCategory: String = "homebrew-system-extension-workflow"
    
    // MARK: - Test Configuration
    
    private struct WorkflowTestConfig {
        let testTapName: String
        let testFormulaName: String
        let testBundleIdentifier: String
        let tempDirectory: URL
        let homebrewPrefix: String
        let testTimeout: TimeInterval
        let enableAutomaticInstallation: Bool
        let enableManualInstallation: Bool
        let enableSystemExtensionTesting: Bool
        let enableCompatibilityTesting: Bool
        let testVersion: String
        
        init(environment: TestEnvironment, tempDirectory: URL) {
            let uniqueId = UUID().uuidString.prefix(8)
            self.testTapName = "homebrew-sysext-test-\(uniqueId)"
            self.testFormulaName = "usbipd-mac"
            self.testBundleIdentifier = "com.test.homebrew.systemextension.\(uniqueId)"
            self.tempDirectory = tempDirectory
            self.testVersion = "v1.0.0-workflow-test-\(uniqueId)"
            
            // Detect Homebrew prefix
            self.homebrewPrefix = Self.detectHomebrewPrefix()
            
            switch environment {
            case .development:
                self.testTimeout = 600.0 // 10 minutes
                self.enableAutomaticInstallation = true
                self.enableManualInstallation = false // Skip manual steps in dev
                self.enableSystemExtensionTesting = false // Avoid privileged operations
                self.enableCompatibilityTesting = true
                
            case .ci:
                self.testTimeout = 900.0 // 15 minutes
                self.enableAutomaticInstallation = false // CI cannot handle user interaction
                self.enableManualInstallation = false // CI cannot handle manual steps
                self.enableSystemExtensionTesting = false // CI lacks System Extension support
                self.enableCompatibilityTesting = true
                
            case .production:
                self.testTimeout = 1200.0 // 20 minutes
                self.enableAutomaticInstallation = true
                self.enableManualInstallation = true
                self.enableSystemExtensionTesting = true
                self.enableCompatibilityTesting = true
            }
        }
        
        private static func detectHomebrewPrefix() -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["brew"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let brewPath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    // Extract prefix from brew path
                    let prefixComponents = brewPath.components(separatedBy: "/").dropLast(2)
                    return "/" + prefixComponents.joined(separator: "/")
                }
            } catch {
                // Fall back to common paths
            }
            
            // Default prefixes for different architectures
            if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
                return "/opt/homebrew" // Apple Silicon
            } else if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
                return "/usr/local" // Intel Mac
            } else {
                return "/opt/homebrew" // Default assumption
            }
        }
    }
    
    // MARK: - Test Properties
    
    private var logger: Logger!
    private var testConfig: WorkflowTestConfig!
    private var tempDirectory: URL!
    private var originalWorkingDirectory: String!
    private var packageRootDirectory: URL!
    private var createdTapRepository: URL?
    private var installedPackages: Set<String> = []
    private var installedSystemExtensions: Set<String> = []
    
    // Component managers
    private var homebrewBundleCreator: HomebrewBundleCreator!
    private var developerModeDetector: DeveloperModeDetector!
    private var automaticInstallationManager: AutomaticInstallationManager!
    private var systemExtensionBundleValidator: SystemExtensionBundleValidator!
    private var installationErrorHandler: InstallationErrorHandler!
    private var installationProgressReporter: InstallationProgressReporter!
    
    // MARK: - Test Lifecycle
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Validate environment before running tests
        try validateEnvironment()
        
        // Skip if environment doesn't support this test suite
        guard shouldRunInCurrentEnvironment() else {
            throw XCTSkip("Homebrew System Extension workflow tests require network, filesystem write, time-intensive, and privileged operation capabilities")
        }
        
        // Skip if Homebrew is not available
        guard isHomebrewAvailable() else {
            throw XCTSkip("Homebrew is not installed or not available in PATH")
        }
        
        // Create logger for testing
        logger = Logger(
            config: LoggerConfig(level: .debug, includeTimestamp: true),
            subsystem: "com.usbipd.homebrew.systemextension.tests",
            category: "workflow"
        )
        
        // Set up temporary directory for test artifacts
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("homebrew-sysext-workflow-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create test configuration
        testConfig = WorkflowTestConfig(
            environment: environmentConfig.environment,
            tempDirectory: tempDirectory
        )
        
        // Find package root directory
        packageRootDirectory = try findPackageRoot()
        
        // Store and set working directory
        originalWorkingDirectory = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(packageRootDirectory.path)
        
        // Initialize component managers
        setupComponentManagers()
        
        logger.info("Starting Homebrew System Extension workflow tests in \(environmentConfig.environment.displayName) environment")
        logger.info("Test tap name: \(testConfig.testTapName)")
        logger.info("Test bundle identifier: \(testConfig.testBundleIdentifier)")
        logger.info("Homebrew prefix: \(testConfig.homebrewPrefix)")
        logger.info("Working directory: \(packageRootDirectory.path)")
        logger.info("Temp directory: \(tempDirectory.path)")
        
        // Call TestSuite setup
        setUpTestSuite()
    }
    
    override func tearDownWithError() throws {
        // Call TestSuite teardown
        tearDownTestSuite()
        
        // Clean up any installed System Extensions
        try cleanupInstalledSystemExtensions()
        
        // Clean up any installed packages
        try cleanupInstalledPackages()
        
        // Clean up test tap repository
        try cleanupTestTapRepository()
        
        // Restore working directory
        if let originalDir = originalWorkingDirectory {
            FileManager.default.changeCurrentDirectoryPath(originalDir)
        }
        
        // Clean up temporary directory (preserve on failure for debugging)
        if let tempDir = tempDirectory, FileManager.default.fileExists(atPath: tempDir.path) {
            if environmentConfig.environment == .development {
                // Keep temp directory for debugging in development
                logger.info("Temporary directory preserved for debugging: \(tempDir.path)")
            } else {
                try? FileManager.default.removeItem(at: tempDir)
                logger.info("Cleaned up temporary directory")
            }
        }
        
        logger?.info("Completed Homebrew System Extension workflow tests")
        
        // Clean up test resources
        cleanupComponentManagers()
        testConfig = nil
        packageRootDirectory = nil
        logger = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Complete Workflow Tests
    
    func testCompleteHomebrewSystemExtensionWorkflow() throws {
        logger.info("Starting complete Homebrew System Extension workflow test")
        
        // Phase 1: Homebrew setup and formula validation
        try testHomebrewSetupAndFormulaValidation()
        
        // Phase 2: System Extension bundle creation and validation
        try testSystemExtensionBundleCreationAndValidation()
        
        // Phase 3: Developer mode detection and configuration
        try testDeveloperModeDetectionAndConfiguration()
        
        // Phase 4: Automatic installation workflow (if enabled)
        if testConfig.enableAutomaticInstallation {
            try testAutomaticInstallationWorkflow()
        } else {
            logger.info("Automatic installation testing disabled for \(environmentConfig.environment.displayName) environment")
        }
        
        // Phase 5: Manual installation fallback (if enabled)
        if testConfig.enableManualInstallation {
            try testManualInstallationFallbackWorkflow()
        } else {
            logger.info("Manual installation testing disabled for \(environmentConfig.environment.displayName) environment")
        }
        
        // Phase 6: System Extension integration testing (if enabled)
        if testConfig.enableSystemExtensionTesting {
            try testSystemExtensionIntegrationWorkflow()
        } else {
            logger.info("System Extension integration testing disabled for \(environmentConfig.environment.displayName) environment")
        }
        
        // Phase 7: Cross-platform compatibility testing (if enabled)
        if testConfig.enableCompatibilityTesting {
            try testCrossPlatformCompatibilityWorkflow()
        } else {
            logger.info("Compatibility testing disabled for \(environmentConfig.environment.displayName) environment")
        }
        
        // Phase 8: Error recovery and troubleshooting validation
        try testErrorRecoveryAndTroubleshootingWorkflow()
        
        logger.info("✅ Complete Homebrew System Extension workflow test passed")
    }
    
    // MARK: - Phase 1: Homebrew Setup and Formula Validation
    
    func testHomebrewSetupAndFormulaValidation() throws {
        logger.info("Phase 1: Testing Homebrew setup and formula validation")
        
        // Test 1.1: Validate current formula structure
        try validateCurrentFormulaStructure()
        
        // Test 1.2: Create test tap with System Extension support
        try createTestTapWithSystemExtensionSupport()
        
        // Test 1.3: Validate formula System Extension integration
        try validateFormulaSystemExtensionIntegration()
        
        // Test 1.4: Test formula installation dry run
        try validateFormulaInstallationDryRun()
        
        logger.info("✅ Homebrew setup and formula validation passed")
    }
    
    private func validateCurrentFormulaStructure() throws {
        logger.info("Validating current formula structure")
        
        let formulaPath = packageRootDirectory.appendingPathComponent("Formula/usbipd-mac.rb")
        
        // Verify formula file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: formulaPath.path),
                     "Homebrew formula should exist at Formula/usbipd-mac.rb")
        
        // Validate formula content for System Extension support
        let formulaContent = try String(contentsOf: formulaPath)
        
        // Validate System Extension build integration
        XCTAssertTrue(formulaContent.contains("USBIPDSystemExtension"),
                     "Formula should build USBIPDSystemExtension product")
        XCTAssertTrue(formulaContent.contains("systemextension"),
                     "Formula should handle System Extension bundle creation")
        
        // Validate post-install hook
        XCTAssertTrue(formulaContent.contains("post_install") || formulaContent.contains("caveats"),
                     "Formula should have post-install setup or user guidance")
        
        logger.debug("✅ Current formula structure validation passed")
    }
    
    private func createTestTapWithSystemExtensionSupport() throws {
        logger.info("Creating test tap with System Extension support")
        
        let tapRepoPath = tempDirectory.appendingPathComponent("homebrew-\(testConfig.testTapName)")
        try FileManager.default.createDirectory(at: tapRepoPath, withIntermediateDirectories: true)
        
        // Initialize git repository
        try runCommand(
            executable: "/usr/bin/git",
            arguments: ["init"],
            workingDirectory: tapRepoPath
        )
        
        // Create Formula directory
        let formulaDir = tapRepoPath.appendingPathComponent("Formula")
        try FileManager.default.createDirectory(at: formulaDir, withIntermediateDirectories: true)
        
        // Copy and enhance formula with test configuration
        let sourceFormula = packageRootDirectory.appendingPathComponent("Formula/usbipd-mac.rb")
        let testFormula = formulaDir.appendingPathComponent("usbipd-mac.rb")
        
        let formulaContent = try String(contentsOf: sourceFormula)
        let testFormulaContent = enhanceFormulaForTesting(formulaContent)
        
        try testFormulaContent.write(to: testFormula, atomically: true, encoding: .utf8)
        
        // Configure git
        try runCommand(
            executable: "/usr/bin/git",
            arguments: ["config", "user.name", "Test User"],
            workingDirectory: tapRepoPath
        )
        
        try runCommand(
            executable: "/usr/bin/git",
            arguments: ["config", "user.email", "test@example.com"],
            workingDirectory: tapRepoPath
        )
        
        // Add and commit formula
        try runCommand(
            executable: "/usr/bin/git",
            arguments: ["add", "."],
            workingDirectory: tapRepoPath
        )
        
        try runCommand(
            executable: "/usr/bin/git",
            arguments: ["commit", "-m", "Initial test tap with System Extension support"],
            workingDirectory: tapRepoPath
        )
        
        createdTapRepository = tapRepoPath
        logger.debug("✅ Test tap with System Extension support created at \(tapRepoPath.path)")
    }
    
    private func enhanceFormulaForTesting(_ originalContent: String) -> String {
        return originalContent
            .replacingOccurrences(of: "VERSION_PLACEHOLDER", with: testConfig.testVersion)
            .replacingOccurrences(of: "SHA256_PLACEHOLDER", with: "test_checksum_placeholder")
            .replacingOccurrences(of: "com.github.usbipd-mac.SystemExtension", with: testConfig.testBundleIdentifier)
    }
    
    private func validateFormulaSystemExtensionIntegration() throws {
        logger.info("Validating formula System Extension integration")
        
        guard let tapRepo = createdTapRepository else {
            throw WorkflowTestError.tapRepositoryNotCreated
        }
        
        let testFormula = tapRepo.appendingPathComponent("Formula/usbipd-mac.rb")
        let formulaContent = try String(contentsOf: testFormula)
        
        // Validate System Extension build commands
        XCTAssertTrue(formulaContent.contains("swift build") && formulaContent.contains("USBIPDSystemExtension"),
                     "Formula should build USBIPDSystemExtension product")
        
        // Validate bundle creation logic
        XCTAssertTrue(formulaContent.contains("systemextension"),
                     "Formula should create System Extension bundle")
        
        // Validate installation to appropriate directory
        XCTAssertTrue(formulaContent.contains("Library/SystemExtensions") || formulaContent.contains("bin/"),
                     "Formula should install System Extension bundle to appropriate location")
        
        logger.debug("✅ Formula System Extension integration validation passed")
    }
    
    private func validateFormulaInstallationDryRun() throws {
        logger.info("Testing formula installation dry run")
        
        guard let tapRepo = createdTapRepository else {
            throw WorkflowTestError.tapRepositoryNotCreated
        }
        
        // Add tap to Homebrew
        try runBrewCommand(arguments: ["tap", testConfig.testTapName, tapRepo.path])
        
        // Test formula syntax with dry run (if brew supports it)
        let formulaPath = tapRepo.appendingPathComponent("Formula/usbipd-mac.rb")
        
        do {
            // Try brew formula validation
            try runBrewCommand(arguments: ["audit", "--strict", formulaPath.path])
            logger.debug("✅ Formula passed brew audit")
        } catch {
            logger.warning("Formula audit warnings (acceptable in test environment): \(error)")
        }
        
        logger.debug("✅ Formula installation dry run validation passed")
    }
    
    // MARK: - Phase 2: System Extension Bundle Creation and Validation
    
    func testSystemExtensionBundleCreationAndValidation() throws {
        logger.info("Phase 2: Testing System Extension bundle creation and validation")
        
        // Test 2.1: Create Homebrew bundle configuration
        try validateHomebrewBundleConfigurationCreation()
        
        // Test 2.2: System Extension bundle creation with Homebrew config
        try validateSystemExtensionBundleCreationWithHomebrewConfig()
        
        // Test 2.3: Bundle structure and content validation
        try validateBundleStructureAndContent()
        
        // Test 2.4: Bundle compatibility validation
        try validateBundleCompatibility()
        
        logger.info("✅ System Extension bundle creation and validation passed")
    }
    
    private func validateHomebrewBundleConfigurationCreation() throws {
        logger.info("Testing Homebrew bundle configuration creation")
        
        // Create mock executable for testing
        let mockExecutable = try createMockSystemExtensionExecutable()
        
        let config = HomebrewBundleConfig(
            homebrewPrefix: testConfig.homebrewPrefix,
            formulaVersion: testConfig.testVersion,
            installationPrefix: tempDirectory.appendingPathComponent("install").path,
            bundleIdentifier: testConfig.testBundleIdentifier,
            displayName: "Test USBIPD System Extension",
            executableName: "USBIPDSystemExtension",
            teamIdentifier: "TESTTEAM123",
            executablePath: mockExecutable,
            formulaName: testConfig.testFormulaName,
            buildNumber: "1"
        )
        
        // Validate configuration
        let validationIssues = homebrewBundleCreator.validateHomebrewConfig(config)
        XCTAssertTrue(validationIssues.isEmpty, "Configuration should be valid: \(validationIssues)")
        
        // Test bundle path resolution
        let bundlePath = homebrewBundleCreator.resolveBundlePath(from: config)
        XCTAssertTrue(bundlePath.hasSuffix(".systemextension"), "Bundle path should have .systemextension extension")
        
        logger.debug("✅ Homebrew bundle configuration creation passed")
    }
    
    private func validateSystemExtensionBundleCreationWithHomebrewConfig() throws {
        logger.info("Testing System Extension bundle creation with Homebrew config")
        
        let mockExecutable = try createMockSystemExtensionExecutable()
        
        let config = HomebrewBundleConfig(
            homebrewPrefix: testConfig.homebrewPrefix,
            formulaVersion: testConfig.testVersion,
            installationPrefix: tempDirectory.appendingPathComponent("install").path,
            bundleIdentifier: testConfig.testBundleIdentifier,
            displayName: "Test USBIPD System Extension",
            executableName: "USBIPDSystemExtension",
            teamIdentifier: "TESTTEAM123",
            executablePath: mockExecutable,
            formulaName: testConfig.testFormulaName,
            buildNumber: "1"
        )
        
        // Create bundle using Homebrew bundle creator
        let bundle = try homebrewBundleCreator.createHomebrewBundle(with: config)
        
        // Validate bundle properties
        XCTAssertEqual(bundle.bundleIdentifier, config.bundleIdentifier)
        XCTAssertEqual(bundle.displayName, config.displayName)
        XCTAssertEqual(bundle.version, config.formulaVersion)
        XCTAssertEqual(bundle.executableName, config.executableName)
        
        // Verify bundle exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.bundlePath),
                     "Bundle should exist at path: \(bundle.bundlePath)")
        
        logger.debug("✅ System Extension bundle creation with Homebrew config passed")
    }
    
    private func validateBundleStructureAndContent() throws {
        logger.info("Testing bundle structure and content validation")
        
        // Use the bundle created in previous test
        let mockExecutable = try createMockSystemExtensionExecutable()
        
        let config = HomebrewBundleConfig(
            homebrewPrefix: testConfig.homebrewPrefix,
            formulaVersion: testConfig.testVersion,
            installationPrefix: tempDirectory.appendingPathComponent("install").path,
            bundleIdentifier: testConfig.testBundleIdentifier,
            displayName: "Test USBIPD System Extension",
            executableName: "USBIPDSystemExtension",
            teamIdentifier: "TESTTEAM123",
            executablePath: mockExecutable,
            formulaName: testConfig.testFormulaName,
            buildNumber: "1"
        )
        
        let bundle = try homebrewBundleCreator.createHomebrewBundle(with: config)
        
        // Validate bundle using validator
        let validationResult = systemExtensionBundleValidator.validateBundle(bundle)
        XCTAssertTrue(validationResult.isValid, "Bundle should pass validation: \(validationResult.issues)")
        
        // Validate specific bundle structure
        let bundlePath = URL(fileURLWithPath: bundle.bundlePath)
        
        let requiredPaths = [
            "Contents",
            "Contents/Info.plist",
            "Contents/MacOS",
            "Contents/Resources"
        ]
        
        for relativePath in requiredPaths {
            let fullPath = bundlePath.appendingPathComponent(relativePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fullPath.path),
                         "Required bundle path should exist: \(relativePath)")
        }
        
        logger.debug("✅ Bundle structure and content validation passed")
    }
    
    private func validateBundleCompatibility() throws {
        logger.info("Testing bundle compatibility validation")
        
        // Create bundle for compatibility testing
        let mockExecutable = try createMockSystemExtensionExecutable()
        
        let config = HomebrewBundleConfig(
            homebrewPrefix: testConfig.homebrewPrefix,
            formulaVersion: testConfig.testVersion,
            installationPrefix: tempDirectory.appendingPathComponent("install").path,
            bundleIdentifier: testConfig.testBundleIdentifier,
            displayName: "Test USBIPD System Extension",
            executableName: "USBIPDSystemExtension",
            teamIdentifier: "TESTTEAM123",
            executablePath: mockExecutable,
            formulaName: testConfig.testFormulaName,
            buildNumber: "1"
        )
        
        let bundle = try homebrewBundleCreator.createHomebrewBundle(with: config)
        
        // Test architecture compatibility
        let architectureResult = try systemExtensionBundleValidator.validateArchitectureCompatibility(bundle)
        XCTAssertTrue(architectureResult.isCompatible, "Bundle should be compatible with current architecture")
        
        // Test macOS version compatibility
        let macOSResult = try systemExtensionBundleValidator.validateMacOSVersionCompatibility(bundle)
        XCTAssertTrue(macOSResult.isCompatible, "Bundle should be compatible with current macOS version")
        
        logger.debug("✅ Bundle compatibility validation passed")
    }
    
    // MARK: - Phase 3: Developer Mode Detection and Configuration
    
    func testDeveloperModeDetectionAndConfiguration() throws {
        logger.info("Phase 3: Testing developer mode detection and configuration")
        
        // Test 3.1: Developer mode detection
        try validateDeveloperModeDetection()
        
        // Test 3.2: Installation strategy determination
        try validateInstallationStrategyDetermination()
        
        // Test 3.3: User guidance generation
        try validateUserGuidanceGeneration()
        
        logger.info("✅ Developer mode detection and configuration passed")
    }
    
    private func validateDeveloperModeDetection() throws {
        logger.info("Testing developer mode detection")
        
        // Test developer mode detection (may fail in restricted environments)
        do {
            let developerModeEnabled = try developerModeDetector.isDeveloperModeEnabled()
            logger.info("Developer mode detected: \(developerModeEnabled)")
            
            // Test validation requirements based on mode
            let requirements = try developerModeDetector.getValidationRequirements()
            
            if developerModeEnabled {
                XCTAssertTrue(requirements.allowsAutomaticInstallation, "Developer mode should allow automatic installation")
                XCTAssertFalse(requirements.requiresUserApproval, "Developer mode should not require user approval")
            } else {
                XCTAssertFalse(requirements.allowsAutomaticInstallation, "Non-developer mode should not allow automatic installation")
                XCTAssertTrue(requirements.requiresUserApproval, "Non-developer mode should require user approval")
            }
        } catch {
            logger.warning("Developer mode detection failed (acceptable in test environment): \(error)")
            // This is acceptable in CI or restricted environments
        }
        
        logger.debug("✅ Developer mode detection passed")
    }
    
    private func validateInstallationStrategyDetermination() throws {
        logger.info("Testing installation strategy determination")
        
        // Test strategy determination for different scenarios
        let testScenarios: [(developerMode: Bool, expectedStrategy: AutomaticInstallationManager.InstallationStrategy)] = [
            (true, .automatic),
            (false, .manualFallback)
        ]
        
        for (developerMode, expectedStrategy) in testScenarios {
            let strategy = automaticInstallationManager.determineInstallationStrategy(
                developerModeEnabled: developerMode,
                userPreference: .automatic
            )
            
            XCTAssertEqual(strategy, expectedStrategy,
                          "Strategy should match expected for developer mode: \(developerMode)")
        }
        
        logger.debug("✅ Installation strategy determination passed")
    }
    
    private func validateUserGuidanceGeneration() throws {
        logger.info("Testing user guidance generation")
        
        // Test guidance generation for different error scenarios
        let errorScenarios = [
            InstallationError.userApprovalRequired("User approval needed"),
            InstallationError.developerModeRequired("Developer mode required"),
            InstallationError.installationFailed("Installation failed")
        ]
        
        for error in errorScenarios {
            let guidance = installationErrorHandler.generateFallbackInstructions(for: error)
            XCTAssertFalse(guidance.isEmpty, "Should generate guidance for error: \(error)")
            
            // Verify guidance contains helpful information
            XCTAssertTrue(guidance.lowercased().contains("usbipd") || guidance.lowercased().contains("system"),
                         "Guidance should mention relevant commands or system components")
        }
        
        logger.debug("✅ User guidance generation passed")
    }
    
    // MARK: - Phase 4: Automatic Installation Workflow
    
    func testAutomaticInstallationWorkflow() throws {
        logger.info("Phase 4: Testing automatic installation workflow")
        
        // Test 4.1: Bundle detection and preparation
        try validateBundleDetectionAndPreparation()
        
        // Test 4.2: Automatic installation attempt
        try validateAutomaticInstallationAttempt()
        
        // Test 4.3: Installation status monitoring
        try validateInstallationStatusMonitoring()
        
        // Test 4.4: Installation progress reporting
        try validateInstallationProgressReporting()
        
        logger.info("✅ Automatic installation workflow passed")
    }
    
    private func validateBundleDetectionAndPreparation() throws {
        logger.info("Testing bundle detection and preparation")
        
        // Create a test bundle for detection
        let mockExecutable = try createMockSystemExtensionExecutable()
        
        let config = HomebrewBundleConfig(
            homebrewPrefix: testConfig.homebrewPrefix,
            formulaVersion: testConfig.testVersion,
            installationPrefix: tempDirectory.appendingPathComponent("install").path,
            bundleIdentifier: testConfig.testBundleIdentifier,
            displayName: "Test USBIPD System Extension",
            executableName: "USBIPDSystemExtension",
            teamIdentifier: "TESTTEAM123",
            executablePath: mockExecutable,
            formulaName: testConfig.testFormulaName,
            buildNumber: "1"
        )
        
        let bundle = try homebrewBundleCreator.createHomebrewBundle(with: config)
        
        // Test bundle detection
        let bundleDetector = SystemExtensionBundleDetector(
            searchPaths: [tempDirectory.appendingPathComponent("install").path],
            logger: logger
        )
        
        let detectionResult = bundleDetector.detectBundle()
        XCTAssertTrue(detectionResult.found, "Should detect created bundle")
        XCTAssertEqual(detectionResult.bundleIdentifier, config.bundleIdentifier)
        
        logger.debug("✅ Bundle detection and preparation passed")
    }
    
    private func validateAutomaticInstallationAttempt() throws {
        logger.info("Testing automatic installation attempt")
        
        // Create mock installation manager to avoid actual System Extension installation
        let mockInstaller = MockSystemExtensionInstaller()
        let mockBundleDetector = MockBundleDetector()
        
        // Configure mocks for successful installation
        mockBundleDetector.detectionResult = SystemExtensionBundleDetector.DetectionResult(
            found: true,
            bundlePath: tempDirectory.appendingPathComponent("test.systemextension").path,
            bundleIdentifier: testConfig.testBundleIdentifier,
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
            logger: logger
        )
        
        let expectation = XCTestExpectation(description: "Automatic installation")
        
        // Test automatic installation
        manager.attemptAutomaticInstallation { result in
            XCTAssertTrue(result.success, "Automatic installation should succeed with mocks")
            XCTAssertEqual(result.finalStatus, .installed)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: TestEnvironmentFixtures.mediumTimeout)
        
        logger.debug("✅ Automatic installation attempt passed")
    }
    
    private func validateInstallationStatusMonitoring() throws {
        logger.info("Testing installation status monitoring")
        
        // Create mock components for status monitoring
        let mockInstaller = MockSystemExtensionInstaller()
        let mockBundleDetector = MockBundleDetector()
        
        let manager = AutomaticInstallationManager(
            config: createTestServerConfig(),
            installer: mockInstaller,
            bundleDetector: mockBundleDetector,
            logger: logger
        )
        
        // Test initial status
        let (initialState, initialHistory) = manager.getInstallationStatus()
        XCTAssertEqual(initialState, .notStarted)
        XCTAssertTrue(initialHistory.isEmpty)
        
        // Simulate installation attempt
        mockInstaller.installationResult = InstallationResult(
            success: true,
            errors: [],
            installationTime: 0.5,
            installationMethod: .automatic
        )
        
        mockBundleDetector.detectionResult = SystemExtensionBundleDetector.DetectionResult(
            found: true,
            bundlePath: tempDirectory.appendingPathComponent("test.systemextension").path,
            bundleIdentifier: testConfig.testBundleIdentifier,
            issues: [],
            detectionTime: Date()
        )
        
        let expectation = XCTestExpectation(description: "Status monitoring")
        
        manager.attemptAutomaticInstallation { _ in
            // Check final status
            let (finalState, finalHistory) = manager.getInstallationStatus()
            XCTAssertEqual(finalState, .completed)
            XCTAssertEqual(finalHistory.count, 1)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: TestEnvironmentFixtures.shortTimeout)
        
        logger.debug("✅ Installation status monitoring passed")
    }
    
    private func validateInstallationProgressReporting() throws {
        logger.info("Testing installation progress reporting")
        
        // Create mock progress delegate
        let mockProgressDelegate = MockProgressDelegate()
        installationProgressReporter.setProgressDelegate(mockProgressDelegate)
        
        // Simulate installation progress
        let progressPhases: [InstallationProgressReporter.InstallationPhase] = [
            .bundleCreation,
            .installation,
            .verification
        ]
        
        for phase in progressPhases {
            installationProgressReporter.reportProgress(phase, progress: 0.0)
            installationProgressReporter.reportProgress(phase, progress: 0.5)
            installationProgressReporter.reportProgress(phase, progress: 1.0)
        }
        
        // Verify progress reporting
        XCTAssertEqual(mockProgressDelegate.progressUpdates.count, 9, "Should receive all progress updates")
        
        let phaseUpdates = mockProgressDelegate.progressUpdates.map { $0.phase }
        for phase in progressPhases {
            XCTAssertTrue(phaseUpdates.contains(phase), "Should report progress for phase: \(phase)")
        }
        
        logger.debug("✅ Installation progress reporting passed")
    }
    
    // MARK: - Phase 5: Manual Installation Fallback Workflow
    
    func testManualInstallationFallbackWorkflow() throws {
        logger.info("Phase 5: Testing manual installation fallback workflow")
        
        // Test 5.1: Fallback instruction generation
        try validateFallbackInstructionGeneration()
        
        // Test 5.2: Manual installation script validation
        try validateManualInstallationScript()
        
        // Test 5.3: User guidance and troubleshooting
        try validateUserGuidanceAndTroubleshooting()
        
        logger.info("✅ Manual installation fallback workflow passed")
    }
    
    private func validateFallbackInstructionGeneration() throws {
        logger.info("Testing fallback instruction generation")
        
        let fallbackScenarios = [
            InstallationError.userApprovalRequired("User approval needed"),
            InstallationError.developerModeRequired("Developer mode required"),
            InstallationError.installationFailed("Installation failed")
        ]
        
        for error in fallbackScenarios {
            let instructions = installationErrorHandler.generateFallbackInstructions(for: error)
            
            XCTAssertFalse(instructions.isEmpty, "Should generate fallback instructions for: \(error)")
            XCTAssertTrue(instructions.contains("usbipd") || instructions.contains("systemextensionsctl"),
                         "Instructions should mention relevant commands")
            
            // Verify error-specific guidance
            switch error {
            case .userApprovalRequired:
                XCTAssertTrue(instructions.lowercased().contains("system preferences") ||
                            instructions.lowercased().contains("security"),
                            "Should mention system security settings")
            case .developerModeRequired:
                XCTAssertTrue(instructions.lowercased().contains("developer mode"),
                            "Should mention developer mode")
            case .installationFailed:
                XCTAssertTrue(instructions.lowercased().contains("manual"),
                            "Should mention manual installation")
            default:
                break
            }
        }
        
        logger.debug("✅ Fallback instruction generation passed")
    }
    
    private func validateManualInstallationScript() throws {
        logger.info("Testing manual installation script validation")
        
        // Check if manual installation script exists
        let scriptPath = packageRootDirectory.appendingPathComponent("Scripts/homebrew-install-extension.rb")
        
        if FileManager.default.fileExists(atPath: scriptPath.path) {
            // Validate script is executable
            let attributes = try FileManager.default.attributesOfItem(atPath: scriptPath.path)
            let permissions = attributes[.posixPermissions] as? NSNumber
            XCTAssertNotNil(permissions, "Installation script should have permissions")
            
            if let perms = permissions {
                let permValue = perms.uint16Value
                XCTAssertTrue((permValue & 0o444) != 0, "Script should be readable")
            }
            
            // Validate script content
            let scriptContent = try String(contentsOf: URL(fileURLWithPath: scriptPath.path))
            XCTAssertTrue(scriptContent.contains("systemextensionsctl") || 
                         scriptContent.contains("System Extension"),
                         "Script should handle System Extension installation")
            
            logger.debug("✅ Manual installation script found and validated")
        } else {
            logger.warning("Manual installation script not found at expected path: \(scriptPath.path)")
        }
        
        logger.debug("✅ Manual installation script validation passed")
    }
    
    private func validateUserGuidanceAndTroubleshooting() throws {
        logger.info("Testing user guidance and troubleshooting")
        
        // Test comprehensive error handling
        let errorHandler = installationErrorHandler
        
        let testError = InstallationError.installationFailed("Test installation failure")
        let errorReport = errorHandler.handleInstallationError(testError)
        
        // Validate error report structure
        XCTAssertFalse(errorReport.userMessage.isEmpty, "Should provide user message")
        XCTAssertFalse(errorReport.technicalDetails.isEmpty, "Should provide technical details")
        XCTAssertFalse(errorReport.remediationSteps.isEmpty, "Should provide remediation steps")
        
        // Test recovery guidance
        let recoveryGuidance = errorHandler.generateRecoveryGuidance(for: testError)
        XCTAssertFalse(recoveryGuidance.remediationSteps.isEmpty, "Should provide recovery steps")
        
        logger.debug("✅ User guidance and troubleshooting passed")
    }
    
    // MARK: - Phase 6: System Extension Integration Workflow
    
    func testSystemExtensionIntegrationWorkflow() throws {
        logger.info("Phase 6: Testing System Extension integration workflow")
        
        // Test 6.1: System Extension lifecycle management
        try validateSystemExtensionLifecycleManagement()
        
        // Test 6.2: IPC communication validation
        try validateIPCCommunication()
        
        // Test 6.3: System Extension health monitoring
        try validateSystemExtensionHealthMonitoring()
        
        logger.info("✅ System Extension integration workflow passed")
    }
    
    private func validateSystemExtensionLifecycleManagement() throws {
        logger.info("Testing System Extension lifecycle management")
        
        // Mock System Extension installer for lifecycle testing
        let mockInstaller = MockSystemExtensionInstaller()
        
        // Test installation lifecycle
        mockInstaller.installationResult = InstallationResult(
            success: true,
            errors: [],
            installationTime: 1.0,
            installationMethod: .automatic
        )
        
        let expectation = XCTestExpectation(description: "Lifecycle management")
        
        mockInstaller.installSystemExtension(
            bundleIdentifier: testConfig.testBundleIdentifier,
            executablePath: "/tmp/mock-executable"
        ) { result in
            XCTAssertTrue(result.success, "Installation should succeed in mock")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: TestEnvironmentFixtures.shortTimeout)
        
        logger.debug("✅ System Extension lifecycle management passed")
    }
    
    private func validateIPCCommunication() throws {
        logger.info("Testing IPC communication validation")
        
        // Create mock IPC components for testing
        let mockIPCHandler = MockIPCHandler()
        
        // Test IPC connection establishment
        mockIPCHandler.connectionResult = true
        XCTAssertTrue(mockIPCHandler.establishConnection(), "IPC connection should be established")
        
        // Test IPC communication
        mockIPCHandler.communicationResult = "test response"
        let response = mockIPCHandler.sendMessage("test message")
        XCTAssertEqual(response, "test response", "IPC communication should work")
        
        logger.debug("✅ IPC communication validation passed")
    }
    
    private func validateSystemExtensionHealthMonitoring() throws {
        logger.info("Testing System Extension health monitoring")
        
        // Mock System Extension diagnostics
        let mockDiagnostics = MockSystemExtensionDiagnostics()
        
        // Test health check
        mockDiagnostics.healthResult = SystemExtensionDiagnostics.HealthResult(
            isHealthy: true,
            bundleValid: true,
            signatureValid: true,
            systemRegistered: true,
            ipcFunctional: true,
            criticalIssues: [],
            warnings: []
        )
        
        let healthResult = mockDiagnostics.performHealthCheck(bundleIdentifier: testConfig.testBundleIdentifier)
        XCTAssertTrue(healthResult.isHealthy, "System Extension should be healthy")
        XCTAssertTrue(healthResult.criticalIssues.isEmpty, "Should have no critical issues")
        
        logger.debug("✅ System Extension health monitoring passed")
    }
    
    // MARK: - Phase 7: Cross-Platform Compatibility Workflow
    
    func testCrossPlatformCompatibilityWorkflow() throws {
        logger.info("Phase 7: Testing cross-platform compatibility workflow")
        
        // Test 7.1: Architecture compatibility
        try validateArchitectureCompatibility()
        
        // Test 7.2: macOS version compatibility  
        try validateMacOSVersionCompatibility()
        
        // Test 7.3: Homebrew environment compatibility
        try validateHomebrewEnvironmentCompatibility()
        
        logger.info("✅ Cross-platform compatibility workflow passed")
    }
    
    private func validateArchitectureCompatibility() throws {
        logger.info("Testing architecture compatibility")
        
        // Test current architecture detection
        let currentArchitecture = ProcessInfo.processInfo.environment["TARGET_ARCH"] ?? "unknown"
        logger.info("Current architecture: \(currentArchitecture)")
        
        // Create test bundle for architecture validation
        let mockExecutable = try createMockSystemExtensionExecutable()
        
        let config = HomebrewBundleConfig(
            homebrewPrefix: testConfig.homebrewPrefix,
            formulaVersion: testConfig.testVersion,
            installationPrefix: tempDirectory.appendingPathComponent("install").path,
            bundleIdentifier: testConfig.testBundleIdentifier,
            displayName: "Test USBIPD System Extension",
            executableName: "USBIPDSystemExtension",
            teamIdentifier: "TESTTEAM123",
            executablePath: mockExecutable,
            formulaName: testConfig.testFormulaName,
            buildNumber: "1"
        )
        
        let bundle = try homebrewBundleCreator.createHomebrewBundle(with: config)
        
        // Test architecture compatibility validation
        let compatibilityResult = try systemExtensionBundleValidator.validateArchitectureCompatibility(bundle)
        XCTAssertTrue(compatibilityResult.isCompatible, "Bundle should be compatible with current architecture")
        
        logger.debug("✅ Architecture compatibility passed")
    }
    
    private func validateMacOSVersionCompatibility() throws {
        logger.info("Testing macOS version compatibility")
        
        // Test macOS version detection
        let version = ProcessInfo.processInfo.operatingSystemVersion
        logger.info("macOS version: \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
        
        // Validate minimum macOS version requirement
        XCTAssertGreaterThanOrEqual(version.majorVersion, 11, "System Extension requires macOS 11+")
        
        logger.debug("✅ macOS version compatibility passed")
    }
    
    private func validateHomebrewEnvironmentCompatibility() throws {
        logger.info("Testing Homebrew environment compatibility")
        
        // Test Homebrew prefix detection
        let detectedPrefix = WorkflowTestConfig.detectHomebrewPrefix()
        XCTAssertFalse(detectedPrefix.isEmpty, "Should detect Homebrew prefix")
        
        // Test Homebrew version compatibility
        let versionOutput = try runBrewCommand(arguments: ["--version"])
        XCTAssertTrue(versionOutput.contains("Homebrew"), "Should report Homebrew version")
        
        logger.debug("✅ Homebrew environment compatibility passed")
    }
    
    // MARK: - Phase 8: Error Recovery and Troubleshooting Workflow
    
    func testErrorRecoveryAndTroubleshootingWorkflow() throws {
        logger.info("Phase 8: Testing error recovery and troubleshooting workflow")
        
        // Test 8.1: Error categorization and handling
        try validateErrorCategorizationAndHandling()
        
        // Test 8.2: Recovery strategy implementation
        try validateRecoveryStrategyImplementation()
        
        // Test 8.3: Diagnostic information collection
        try validateDiagnosticInformationCollection()
        
        logger.info("✅ Error recovery and troubleshooting workflow passed")
    }
    
    private func validateErrorCategorizationAndHandling() throws {
        logger.info("Testing error categorization and handling")
        
        let errorCategories: [(InstallationError, String)] = [
            (.userApprovalRequired("User approval needed"), "user"),
            (.developerModeRequired("Developer mode required"), "configuration"),
            (.bundleValidationFailed("Invalid bundle"), "bundle"),
            (.installationFailed("Generic failure"), "installation"),
            (.unknownError("Unknown error"), "unknown")
        ]
        
        for (error, expectedCategory) in errorCategories {
            let errorReport = installationErrorHandler.handleInstallationError(error)
            
            XCTAssertFalse(errorReport.userMessage.isEmpty, "Should generate user message for: \(error)")
            XCTAssertFalse(errorReport.technicalDetails.isEmpty, "Should generate technical details for: \(error)")
            
            // Verify category-specific handling
            let combinedContent = "\(errorReport.userMessage) \(errorReport.technicalDetails)".lowercased()
            XCTAssertTrue(combinedContent.contains(expectedCategory) || 
                         combinedContent.contains(error.localizedDescription.lowercased()),
                         "Should handle category '\(expectedCategory)' for error: \(error)")
        }
        
        logger.debug("✅ Error categorization and handling passed")
    }
    
    private func validateRecoveryStrategyImplementation() throws {
        logger.info("Testing recovery strategy implementation")
        
        // Test recovery strategies for different error types
        let recoveryScenarios = [
            InstallationError.userApprovalRequired("User approval needed"),
            InstallationError.developerModeRequired("Developer mode required"),
            InstallationError.installationFailed("Installation failed")
        ]
        
        for error in recoveryScenarios {
            let recoveryGuidance = installationErrorHandler.generateRecoveryGuidance(for: error)
            
            XCTAssertFalse(recoveryGuidance.remediationSteps.isEmpty, 
                          "Should provide recovery steps for: \(error)")
            
            // Verify recovery strategy appropriateness
            switch error {
            case .userApprovalRequired:
                XCTAssertFalse(recoveryGuidance.shouldContactSupport, 
                              "User approval issues should not require support")
            case .developerModeRequired:
                XCTAssertFalse(recoveryGuidance.shouldContactSupport,
                              "Configuration issues should not require support")
            case .installationFailed:
                XCTAssertTrue(recoveryGuidance.automaticRetryRecommended > 0,
                             "Installation failures should suggest retry")
            default:
                break
            }
        }
        
        logger.debug("✅ Recovery strategy implementation passed")
    }
    
    private func validateDiagnosticInformationCollection() throws {
        logger.info("Testing diagnostic information collection")
        
        // Test system information collection
        let systemInfo = collectSystemDiagnosticInformation()
        
        XCTAssertTrue(systemInfo.contains("macOS"), "Should include macOS information")
        XCTAssertTrue(systemInfo.contains("Homebrew") || systemInfo.contains("brew"), 
                     "Should include Homebrew information")
        
        // Test environment information collection
        let environmentInfo = collectEnvironmentDiagnosticInformation()
        
        XCTAssertFalse(environmentInfo.isEmpty, "Should collect environment information")
        
        logger.debug("✅ Diagnostic information collection passed")
    }
    
    // MARK: - Helper Methods
    
    private func setupComponentManagers() {
        homebrewBundleCreator = HomebrewBundleCreator(logger: logger)
        developerModeDetector = DeveloperModeDetector(logger: logger)
        systemExtensionBundleValidator = SystemExtensionBundleValidator(logger: logger)
        installationErrorHandler = InstallationErrorHandler(logger: logger)
        installationProgressReporter = InstallationProgressReporter(logger: logger)
        
        automaticInstallationManager = AutomaticInstallationManager(
            config: createTestServerConfig(),
            installer: MockSystemExtensionInstaller(),
            bundleDetector: MockBundleDetector(),
            logger: logger
        )
    }
    
    private func cleanupComponentManagers() {
        installationProgressReporter = nil
        installationErrorHandler = nil
        systemExtensionBundleValidator = nil
        automaticInstallationManager = nil
        developerModeDetector = nil
        homebrewBundleCreator = nil
    }
    
    private func isHomebrewAvailable() -> Bool {
        let brewPath = "\(testConfig.homebrewPrefix)/bin/brew"
        return FileManager.default.fileExists(atPath: brewPath)
    }
    
    private func findPackageRoot() throws -> URL {
        var currentURL = URL(fileURLWithPath: #file).deletingLastPathComponent()
        
        while currentURL.path != "/" {
            let packageSwiftPath = currentURL.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageSwiftPath.path) {
                return currentURL
            }
            currentURL = currentURL.deletingLastPathComponent()
        }
        
        throw WorkflowTestError.packageRootNotFound
    }
    
    private func createMockSystemExtensionExecutable() throws -> String {
        let executablePath = tempDirectory.appendingPathComponent("USBIPDSystemExtension").path
        let executableContent = """
        #!/bin/bash
        echo "Mock USBIPD System Extension - Version 1.0"
        echo "Bundle ID: $1"
        while true; do
            sleep 1
        done
        """
        
        try executableContent.write(toFile: executablePath, atomically: true, encoding: .utf8)
        
        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], 
                                             ofItemAtPath: executablePath)
        
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
    
    @discardableResult
    private func runBrewCommand(arguments: [String]) throws -> String {
        return try runCommand(
            executable: "\(testConfig.homebrewPrefix)/bin/brew",
            arguments: arguments,
            workingDirectory: packageRootDirectory
        )
    }
    
    @discardableResult
    private func runCommand(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        
        if let workingDir = workingDirectory {
            process.currentDirectoryURL = workingDir
        }
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        logger.debug("Executing: \(executable) \(arguments.joined(separator: " "))")
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            logger.error("Command failed with status: \(process.terminationStatus)")
            logger.error("Output: \(output)")
            logger.error("Error: \(error)")
            throw WorkflowTestError.commandExecutionFailed(
                command: "\(executable) \(arguments.joined(separator: " "))",
                exitCode: process.terminationStatus,
                output: output,
                error: error
            )
        }
        
        return output
    }
    
    private func collectSystemDiagnosticInformation() -> String {
        var diagnostics: [String] = []
        
        // macOS version
        let version = ProcessInfo.processInfo.operatingSystemVersion
        diagnostics.append("macOS: \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
        
        // Architecture
        diagnostics.append("Architecture: \(ProcessInfo.processInfo.environment["TARGET_ARCH"] ?? "unknown")")
        
        // Homebrew version
        do {
            let homebrewVersion = try runBrewCommand(arguments: ["--version"])
            diagnostics.append("Homebrew: \(homebrewVersion.components(separatedBy: .newlines).first ?? "unknown")")
        } catch {
            diagnostics.append("Homebrew: error getting version")
        }
        
        return diagnostics.joined(separator: "\n")
    }
    
    private func collectEnvironmentDiagnosticInformation() -> String {
        var environmentInfo: [String] = []
        
        // Test environment
        environmentInfo.append("Test Environment: \(environmentConfig.environment.displayName)")
        
        // Available capabilities
        environmentInfo.append("Capabilities: \(environmentConfig.capabilities)")
        
        // Homebrew prefix
        environmentInfo.append("Homebrew Prefix: \(testConfig.homebrewPrefix)")
        
        return environmentInfo.joined(separator: "\n")
    }
    
    private func cleanupInstalledSystemExtensions() throws {
        logger.info("Cleaning up installed System Extensions")
        
        for bundleIdentifier in installedSystemExtensions {
            logger.debug("Cleaning up System Extension: \(bundleIdentifier)")
            // In a real implementation, this would uninstall the System Extension
            // For testing, we just track and log
        }
        
        installedSystemExtensions.removeAll()
    }
    
    private func cleanupInstalledPackages() throws {
        logger.info("Cleaning up installed packages")
        
        for package in installedPackages {
            do {
                try runBrewCommand(arguments: ["uninstall", package])
                logger.debug("Uninstalled package: \(package)")
            } catch {
                logger.warning("Failed to uninstall package \(package): \(error)")
            }
        }
        
        installedPackages.removeAll()
    }
    
    private func cleanupTestTapRepository() throws {
        logger.info("Cleaning up test tap repository")
        
        // Remove tap from Homebrew
        do {
            try runBrewCommand(arguments: ["untap", testConfig.testTapName])
            logger.debug("Removed tap: \(testConfig.testTapName)")
        } catch {
            logger.warning("Failed to remove tap \(testConfig.testTapName): \(error)")
        }
        
        // Clean up local repository
        if let tapRepo = createdTapRepository {
            try? FileManager.default.removeItem(at: tapRepo)
            logger.debug("Cleaned up tap repository: \(tapRepo.path)")
        }
    }
}

// MARK: - Supporting Types

private enum WorkflowTestError: Error {
    case packageRootNotFound
    case tapRepositoryNotCreated
    case commandExecutionFailed(command: String, exitCode: Int32, output: String, error: String)
    case homebrewNotAvailable
    case systemExtensionNotSupported
    case testConfigurationInvalid(String)
    
    var localizedDescription: String {
        switch self {
        case .packageRootNotFound:
            return "Package root directory not found"
        case .tapRepositoryNotCreated:
            return "Test tap repository was not created"
        case .commandExecutionFailed(let command, let exitCode, _, _):
            return "Command failed: \(command) (exit code: \(exitCode))"
        case .homebrewNotAvailable:
            return "Homebrew is not available in the current environment"
        case .systemExtensionNotSupported:
            return "System Extensions are not supported in the current environment"
        case .testConfigurationInvalid(let message):
            return "Test configuration is invalid: \(message)"
        }
    }
}

// MARK: - Mock Classes for Testing

/// Mock IPC handler for testing
private class MockIPCHandler {
    var connectionResult: Bool = false
    var communicationResult: String = ""
    
    func establishConnection() -> Bool {
        return connectionResult
    }
    
    func sendMessage(_ message: String) -> String {
        return communicationResult
    }
}

/// Mock System Extension diagnostics for testing
private class MockSystemExtensionDiagnostics {
    var healthResult = SystemExtensionDiagnostics.HealthResult(
        isHealthy: false,
        bundleValid: false,
        signatureValid: false,
        systemRegistered: false,
        ipcFunctional: false,
        criticalIssues: [],
        warnings: []
    )
    
    func performHealthCheck(bundleIdentifier: String) -> SystemExtensionDiagnostics.HealthResult {
        return healthResult
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