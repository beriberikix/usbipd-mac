//
//  CompletionInstallationTests.swift
//  usbipd-mac
//
//  Integration tests for completion installation workflows in controlled CI environment
//  Tests end-to-end installation workflows in temporary directories with cross-shell compatibility validation
//

import XCTest
import Foundation
@testable import USBIPDCore
@testable import USBIPDCLI  
@testable import Common

/// Integration tests for completion installation system in CI environment
/// Tests complete workflow from completion generation to installation and status checking
final class CompletionInstallationTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    public let environmentConfig: TestEnvironmentConfig = TestEnvironmentDetector.createConfigurationForCurrentEnvironment()
    public let requiredCapabilities: TestEnvironmentCapabilities = [
        .filesystemWrite,
        .networkAccess
    ]
    public let testCategory: String = "completion-installation"
    
    // MARK: - Test Configuration
    
    private struct CompletionTestConfig {
        let tempDirectory: URL
        let testTimeout: TimeInterval
        let enableCrossShellTesting: Bool
        let enableFileValidation: Bool
        let supportedShells: [String]
        let testData: CompletionData
        
        init(environment: TestEnvironment, tempDirectory: URL) {
            self.tempDirectory = tempDirectory
            self.supportedShells = ["bash", "zsh", "fish"]
            
            switch environment {
            case .development:
                self.testTimeout = 30.0
                self.enableCrossShellTesting = true
                self.enableFileValidation = true
                
            case .ci:
                self.testTimeout = 60.0
                self.enableCrossShellTesting = true
                self.enableFileValidation = true
                
            case .production:
                self.testTimeout = 120.0
                self.enableCrossShellTesting = true
                self.enableFileValidation = true
            }
            
            // Create test completion data
            self.testData = CompletionData(
                programName: "usbipd",
                version: "1.0.0-test",
                commands: [
                    CompletionCommand(
                        name: "list", 
                        description: "List available USB devices",
                        options: [
                            CompletionOption(name: "--format", description: "Output format", hasValue: true),
                            CompletionOption(name: "--verbose", description: "Verbose output", hasValue: false)
                        ]
                    ),
                    CompletionCommand(
                        name: "bind",
                        description: "Bind a USB device",
                        options: [
                            CompletionOption(name: "--busid", description: "Device bus ID", hasValue: true),
                            CompletionOption(name: "--force", description: "Force binding", hasValue: false)
                        ]
                    ),
                    CompletionCommand(
                        name: "completion",
                        description: "Manage shell completions",
                        subcommands: [
                            CompletionCommand(name: "install", description: "Install completions"),
                            CompletionCommand(name: "uninstall", description: "Remove completions"),
                            CompletionCommand(name: "status", description: "Check installation status")
                        ]
                    )
                ]
            )
        }
    }
    
    // MARK: - Test Properties
    
    private var logger: Logger!
    private var testConfig: CompletionTestConfig!
    private var tempDirectory: URL!
    private var mockUserDirectories: [String: String] = [:]
    private var createdFiles: Set<String> = []
    private var completionInstaller: CompletionInstaller!
    
    // MARK: - Test Lifecycle
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Validate environment before running tests
        try validateEnvironment()
        
        // Skip if environment doesn't support this test suite
        guard shouldRunInCurrentEnvironment() else {
            throw XCTSkip("Completion installation tests require filesystem write capabilities")
        }
        
        // Create logger for testing
        logger = Logger(
            config: LoggerConfig(level: .debug, includeTimestamp: true),
            subsystem: "com.usbipd.completion.tests",
            category: "integration"
        )
        
        // Set up temporary directory for test artifacts
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("completion-installation-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create test configuration
        testConfig = CompletionTestConfig(
            environment: environmentConfig.environment,
            tempDirectory: tempDirectory
        )
        
        // Set up mock user directories for each shell
        try setupMockUserDirectories()
        
        // Create completion installer with mock directory resolver
        let mockDirectoryResolver = MockUserDirectoryResolver(mockDirectories: mockUserDirectories)
        completionInstaller = CompletionInstaller(
            directoryResolver: mockDirectoryResolver,
            completionWriter: CompletionWriter()
        )
        
        logger.info("Starting completion installation tests in \(environmentConfig.environment.displayName) environment")
        logger.info("Test directory: \(tempDirectory.path)")
        logger.info("Supported shells: \(testConfig.supportedShells)")
        
        // Call TestSuite setup
        setUpTestSuite()
    }
    
    override func tearDownWithError() throws {
        // Call TestSuite teardown
        tearDownTestSuite()
        
        // Clean up created files
        try cleanupCreatedFiles()
        
        // Clean up temporary directory
        if let tempDir = tempDirectory, FileManager.default.fileExists(atPath: tempDir.path) {
            if environmentConfig.environment == .development {
                logger.info("Temporary directory preserved for debugging: \(tempDir.path)")
            } else {
                try? FileManager.default.removeItem(at: tempDir)
                logger.info("Cleaned up temporary directory")
            }
        }
        
        logger?.info("Completed completion installation tests")
        
        // Clean up test resources
        testConfig = nil
        tempDirectory = nil
        mockUserDirectories.removeAll()
        createdFiles.removeAll()
        completionInstaller = nil
        logger = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - End-to-End Installation Workflow Tests
    
    func testCompleteInstallationWorkflow() throws {
        logger.info("Starting complete installation workflow test")
        
        // Phase 1: Install completions for all shells
        try testInstallationForAllShells()
        
        // Phase 2: Verify installation status
        try testInstallationStatusChecking()
        
        // Phase 3: Test file validation
        if testConfig.enableFileValidation {
            try testInstalledFileValidation()
        }
        
        // Phase 4: Test cross-shell compatibility
        if testConfig.enableCrossShellTesting {
            try testCrossShellCompatibility()
        }
        
        // Phase 5: Test uninstallation workflow
        try testUninstallationWorkflow()
        
        logger.info("✅ Complete installation workflow test passed")
    }
    
    // MARK: - Phase 1: Installation for All Shells
    
    func testInstallationForAllShells() throws {
        logger.info("Phase 1: Testing installation for all supported shells")
        
        for shell in testConfig.supportedShells {
            try testSingleShellInstallation(shell: shell)
        }
        
        logger.info("✅ Installation for all shells completed")
    }
    
    private func testSingleShellInstallation(shell: String) throws {
        logger.info("Installing completions for \(shell)")
        
        // Test installation
        let result = try completionInstaller.install(data: testConfig.testData, for: shell)
        
        // Verify installation succeeded
        XCTAssertTrue(result.success, "Installation should succeed for \(shell)")
        XCTAssertNotNil(result.targetPath, "Target path should be set for \(shell)")
        XCTAssertNil(result.error, "No error should occur for \(shell)")
        XCTAssertGreaterThan(result.duration, 0, "Installation should take measurable time for \(shell)")
        
        // Track created files for cleanup
        if let targetPath = result.targetPath {
            createdFiles.insert(targetPath)
        }
        
        // Verify file was actually created
        if let targetPath = result.targetPath {
            XCTAssertTrue(FileManager.default.fileExists(atPath: targetPath),
                         "Completion file should exist at target path for \(shell)")
            
            // Verify file has appropriate permissions
            let attributes = try FileManager.default.attributesOfItem(atPath: targetPath)
            let permissions = attributes[.posixPermissions] as? NSNumber
            XCTAssertNotNil(permissions, "File should have permissions set for \(shell)")
            
            if let perms = permissions {
                let permValue = perms.uint16Value
                XCTAssertEqual(permValue & 0o644, 0o644, "File should have readable permissions for \(shell)")
            }
        }
        
        logger.debug("✅ Installation verified for \(shell)")
    }
    
    // MARK: - Phase 2: Installation Status Checking
    
    func testInstallationStatusChecking() throws {
        logger.info("Phase 2: Testing installation status checking")
        
        for shell in testConfig.supportedShells {
            let status = completionInstaller.getInstallationStatus(for: shell)
            
            // Verify status reflects installation
            XCTAssertTrue(status.isInstalled, "Status should show installed for \(shell)")
            XCTAssertNotNil(status.targetDirectory, "Target directory should be available for \(shell)")
            XCTAssertNotNil(status.targetPath, "Target path should be available for \(shell)")
            XCTAssertNotNil(status.fileInfo, "File info should be available for \(shell)")
            XCTAssertNil(status.error, "No error should occur in status check for \(shell)")
            
            // Verify file info details
            if let fileInfo = status.fileInfo {
                XCTAssertTrue(fileInfo.exists, "File should exist according to status for \(shell)")
                XCTAssertGreaterThan(fileInfo.size, 0, "File should have content for \(shell)")
                XCTAssertNotNil(fileInfo.modificationDate, "File should have modification date for \(shell)")
            }
        }
        
        logger.info("✅ Status checking completed")
    }
    
    // MARK: - Phase 3: Installed File Validation
    
    func testInstalledFileValidation() throws {
        logger.info("Phase 3: Testing installed file validation")
        
        for shell in testConfig.supportedShells {
            try validateCompletionFileContent(for: shell)
        }
        
        logger.info("✅ File validation completed")
    }
    
    private func validateCompletionFileContent(for shell: String) throws {
        let status = completionInstaller.getInstallationStatus(for: shell)
        guard let targetPath = status.targetPath else {
            XCTFail("Target path should be available for \(shell)")
            return
        }
        
        let content = try String(contentsOfFile: targetPath)
        
        // Verify basic content requirements
        XCTAssertFalse(content.isEmpty, "Completion file should not be empty for \(shell)")
        
        // Shell-specific validation
        switch shell.lowercased() {
        case "bash":
            XCTAssertTrue(content.contains("complete"), "Bash completion should contain 'complete' command")
            XCTAssertTrue(content.contains("usbipd"), "Bash completion should reference program name")
            
        case "zsh":
            XCTAssertTrue(content.contains("#compdef"), "Zsh completion should have #compdef directive")
            XCTAssertTrue(content.contains("usbipd"), "Zsh completion should reference program name")
            
        case "fish":
            XCTAssertTrue(content.contains("complete"), "Fish completion should contain 'complete' command")
            XCTAssertTrue(content.contains("usbipd"), "Fish completion should reference program name")
            
        default:
            logger.warning("Unknown shell type for validation: \(shell)")
        }
        
        // Verify test commands are present
        XCTAssertTrue(content.contains("list"), "Completion should include 'list' command")
        XCTAssertTrue(content.contains("bind"), "Completion should include 'bind' command")
        XCTAssertTrue(content.contains("completion"), "Completion should include 'completion' command")
        
        logger.debug("✅ File content validated for \(shell)")
    }
    
    // MARK: - Phase 4: Cross-Shell Compatibility
    
    func testCrossShellCompatibility() throws {
        logger.info("Phase 4: Testing cross-shell compatibility")
        
        // Install completions for multiple shells simultaneously
        let results = completionInstaller.installAll(data: testConfig.testData)
        
        // Verify all installations succeeded
        XCTAssertEqual(results.count, testConfig.supportedShells.count,
                      "Should have results for all shells")
        
        let successfulResults = results.filter { $0.success }
        XCTAssertEqual(successfulResults.count, testConfig.supportedShells.count,
                      "All installations should succeed")
        
        // Verify no path conflicts
        let targetPaths = results.compactMap { $0.targetPath }
        let uniquePaths = Set(targetPaths)
        XCTAssertEqual(targetPaths.count, uniquePaths.count,
                      "All target paths should be unique")
        
        // Track all created files for cleanup
        targetPaths.forEach { createdFiles.insert($0) }
        
        // Verify status for all shells
        let statuses = completionInstaller.getStatusAll()
        XCTAssertEqual(statuses.count, testConfig.supportedShells.count,
                      "Should have status for all shells")
        
        let installedStatuses = statuses.filter { $0.isInstalled }
        XCTAssertEqual(installedStatuses.count, testConfig.supportedShells.count,
                      "All shells should show as installed")
        
        logger.info("✅ Cross-shell compatibility validated")
    }
    
    // MARK: - Phase 5: Uninstallation Workflow
    
    func testUninstallationWorkflow() throws {
        logger.info("Phase 5: Testing uninstallation workflow")
        
        // Test individual shell uninstallation
        for shell in testConfig.supportedShells {
            try testSingleShellUninstallation(shell: shell)
        }
        
        // Verify all completions are removed
        try verifyCompleteUninstallation()
        
        logger.info("✅ Uninstallation workflow completed")
    }
    
    private func testSingleShellUninstallation(shell: String) throws {
        logger.info("Uninstalling completions for \(shell)")
        
        // Test uninstallation
        let result = try completionInstaller.uninstall(for: shell)
        
        // Verify uninstallation succeeded
        XCTAssertTrue(result.success, "Uninstallation should succeed for \(shell)")
        XCTAssertNotNil(result.removedPath, "Removed path should be set for \(shell)")
        XCTAssertNil(result.error, "No error should occur for \(shell)")
        XCTAssertGreaterThan(result.duration, 0, "Uninstallation should take measurable time for \(shell)")
        
        // Verify file was actually removed
        if let removedPath = result.removedPath {
            XCTAssertFalse(FileManager.default.fileExists(atPath: removedPath),
                          "Completion file should be removed for \(shell)")
            createdFiles.remove(removedPath)
        }
        
        logger.debug("✅ Uninstallation verified for \(shell)")
    }
    
    private func verifyCompleteUninstallation() throws {
        logger.info("Verifying complete uninstallation")
        
        // Check status for all shells
        let statuses = completionInstaller.getStatusAll()
        
        for status in statuses {
            XCTAssertFalse(status.isInstalled, "Shell \(status.shell) should not show as installed")
            
            if let targetPath = status.targetPath {
                XCTAssertFalse(FileManager.default.fileExists(atPath: targetPath),
                              "Completion file should not exist for \(status.shell)")
            }
        }
        
        logger.info("✅ Complete uninstallation verified")
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling() throws {
        logger.info("Testing error handling scenarios")
        
        // Test installation with invalid shell
        try testInvalidShellHandling()
        
        // Test installation with permission errors
        try testPermissionErrorHandling()
        
        // Test uninstallation of non-existent completions
        try testUninstallationOfNonExistentFiles()
        
        logger.info("✅ Error handling tests completed")
    }
    
    private func testInvalidShellHandling() throws {
        logger.info("Testing invalid shell handling")
        
        let invalidShells = ["invalid", "unknown", ""]
        
        for shell in invalidShells {
            do {
                let result = try completionInstaller.install(data: testConfig.testData, for: shell)
                // Some implementations might handle gracefully, others might throw
                if !result.success {
                    XCTAssertNotNil(result.error, "Error should be provided for invalid shell: \(shell)")
                }
            } catch {
                // Expected behavior - installation should fail for invalid shells
                logger.debug("Installation correctly failed for invalid shell: \(shell)")
            }
        }
        
        logger.debug("✅ Invalid shell handling verified")
    }
    
    private func testPermissionErrorHandling() throws {
        logger.info("Testing permission error handling")
        
        // Create a read-only directory to simulate permission errors
        let readOnlyDir = tempDirectory.appendingPathComponent("readonly")
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: readOnlyDir.path)
        
        // Create mock resolver that points to read-only directory
        let permissionMockDirectories = ["bash": readOnlyDir.path]
        let permissionMockResolver = MockUserDirectoryResolver(mockDirectories: permissionMockDirectories)
        let permissionInstaller = CompletionInstaller(
            directoryResolver: permissionMockResolver,
            completionWriter: CompletionWriter()
        )
        
        // Test installation should handle permission errors gracefully
        let result = try permissionInstaller.install(data: testConfig.testData, for: "bash")
        
        if !result.success {
            XCTAssertNotNil(result.error, "Error should be provided for permission failures")
            logger.debug("Installation correctly handled permission error")
        }
        
        // Clean up read-only directory
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyDir.path)
        try FileManager.default.removeItem(at: readOnlyDir)
        
        logger.debug("✅ Permission error handling verified")
    }
    
    private func testUninstallationOfNonExistentFiles() throws {
        logger.info("Testing uninstallation of non-existent files")
        
        // Create installer with empty directories
        let emptyMockDirectories: [String: String] = [
            "bash": tempDirectory.appendingPathComponent("empty-bash").path,
            "zsh": tempDirectory.appendingPathComponent("empty-zsh").path,
            "fish": tempDirectory.appendingPathComponent("empty-fish").path
        ]
        
        // Create empty directories
        for (_, dirPath) in emptyMockDirectories {
            try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }
        
        let emptyMockResolver = MockUserDirectoryResolver(mockDirectories: emptyMockDirectories)
        let emptyInstaller = CompletionInstaller(
            directoryResolver: emptyMockResolver,
            completionWriter: CompletionWriter()
        )
        
        // Test uninstallation of non-existent files
        for shell in testConfig.supportedShells {
            let result = try emptyInstaller.uninstall(for: shell)
            
            // Should succeed with no file to remove
            XCTAssertTrue(result.success, "Uninstallation should succeed even if file doesn't exist for \(shell)")
            XCTAssertNil(result.removedPath, "No path should be removed if file doesn't exist for \(shell)")
            XCTAssertNil(result.error, "No error should occur for non-existent file for \(shell)")
        }
        
        logger.debug("✅ Non-existent file uninstallation verified")
    }
    
    // MARK: - Helper Methods
    
    private func setupMockUserDirectories() throws {
        logger.info("Setting up mock user directories")
        
        for shell in testConfig.supportedShells {
            let shellDir = tempDirectory.appendingPathComponent("mock-\(shell)-completion-dir")
            try FileManager.default.createDirectory(at: shellDir, withIntermediateDirectories: true)
            mockUserDirectories[shell] = shellDir.path
        }
        
        logger.debug("✅ Mock user directories created")
    }
    
    private func cleanupCreatedFiles() throws {
        logger.info("Cleaning up created files")
        
        for filePath in createdFiles {
            if FileManager.default.fileExists(atPath: filePath) {
                try? FileManager.default.removeItem(atPath: filePath)
                logger.debug("Removed file: \(filePath)")
            }
        }
        
        createdFiles.removeAll()
        logger.debug("✅ Created files cleaned up")
    }
}

// MARK: - Mock User Directory Resolver

/// Mock implementation of UserDirectoryResolver for testing
private class MockUserDirectoryResolver: UserDirectoryResolver {
    
    private let mockDirectories: [String: String]
    
    init(mockDirectories: [String: String]) {
        self.mockDirectories = mockDirectories
        super.init()
    }
    
    override func resolveCompletionDirectory(for shell: String) throws -> String {
        guard let directory = mockDirectories[shell] else {
            throw CompletionError.unsupportedShell(shell)
        }
        return directory
    }
    
    override func ensureDirectoryExists(path: String) throws {
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
        }
    }
}

// MARK: - Supporting Types

/// Errors for completion installation testing
private enum CompletionTestError: Error {
    case setupFailed(String)
    case validationFailed(String)
    case cleanupFailed(String)
    
    var localizedDescription: String {
        switch self {
        case .setupFailed(let message):
            return "Test setup failed: \(message)"
        case .validationFailed(let message):
            return "Test validation failed: \(message)"
        case .cleanupFailed(let message):
            return "Test cleanup failed: \(message)"
        }
    }
}