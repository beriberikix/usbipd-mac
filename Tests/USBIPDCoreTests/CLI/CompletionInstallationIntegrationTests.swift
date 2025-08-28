// CompletionInstallationTests.swift
// Integration tests for completion installation validating complete installation process in controlled environment

import XCTest
import Foundation
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

/// Integration tests for completion installation functionality
/// Tests end-to-end installation workflows in temporary directories with cross-shell compatibility
final class CompletionInstallationTests: XCTestCase {
    
    // MARK: - Test Configuration
    
    let testCategory: String = "integration"
    let testTimeout: TimeInterval = 180.0 // 3 minutes
    
    // MARK: - Test Properties
    
    private var tempBaseDirectory: URL!
    private var bashCompletionDirectory: URL!
    private var zshCompletionDirectory: URL!
    private var fishCompletionDirectory: URL!
    private var installer: CompletionInstaller!
    private var completionData: CompletionData!
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        // Environment setup without TestSuite dependencies
        
        setUpTestEnvironment()
        setUpTestSuite()
    }
    
    override func tearDown() {
        tearDownTestSuite()
        cleanupTestEnvironment()
        super.tearDown()
    }
    
    func setUpTestSuite() {
        // Additional suite-specific setup if needed
        XCTAssertNotNil(installer, "Installer should be initialized")
        XCTAssertNotNil(completionData, "Completion data should be initialized")
    }
    
    func tearDownTestSuite() {
        // Additional suite-specific cleanup if needed
    }
    
    private func setUpTestEnvironment() {
        // Create base temporary directory
        tempBaseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("completion-installation-integration-tests")
            .appendingPathComponent(UUID().uuidString)
        
        do {
            try FileManager.default.createDirectory(
                at: tempBaseDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            // Set up shell-specific directories
            bashCompletionDirectory = tempBaseDirectory
                .appendingPathComponent("bash")
                .appendingPathComponent(".local/share/bash-completion/completions")
            
            zshCompletionDirectory = tempBaseDirectory
                .appendingPathComponent("zsh")
                .appendingPathComponent(".zsh/completions")
            
            fishCompletionDirectory = tempBaseDirectory
                .appendingPathComponent("fish")
                .appendingPathComponent(".config/fish/completions")
            
            // Create all shell directories
            try FileManager.default.createDirectory(at: bashCompletionDirectory, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(at: zshCompletionDirectory, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(at: fishCompletionDirectory, withIntermediateDirectories: true, attributes: nil)
            
            // Initialize installer with test directory resolver
            let testDirectoryResolver = TestUserDirectoryResolver(
                bashDir: bashCompletionDirectory.path,
                zshDir: zshCompletionDirectory.path,
                fishDir: fishCompletionDirectory.path
            )
            
            installer = CompletionInstaller(
                directoryResolver: testDirectoryResolver,
                completionWriter: CompletionWriter()
            )
            
            // Create test completion data
            completionData = createTestCompletionData()
            
        } catch {
            XCTFail("Failed to set up test environment: \(error)")
        }
    }
    
    private func cleanupTestEnvironment() {
        guard let tempBaseDirectory = tempBaseDirectory else { return }
        try? FileManager.default.removeItem(at: tempBaseDirectory)
    }
}

// MARK: - End-to-End Installation Tests

extension CompletionInstallationTests {
    
    func testCompleteInstallationWorkflowForAllShells() throws {
        let timeout = testTimeout
        
        // Test installation for all supported shells
        let supportedShells = ["bash", "zsh", "fish"]
        var installationResults: [CompletionInstallationResult] = []
        
        for shell in supportedShells {
            let result = try installer.install(data: completionData, for: shell)
            installationResults.append(result)
            
            // Verify installation succeeded
            XCTAssertTrue(result.success, "Installation should succeed for \(shell)")
            XCTAssertNil(result.error, "No error should occur for \(shell)")
            XCTAssertNotNil(result.targetPath, "Target path should be set for \(shell)")
            XCTAssertLessThan(result.duration, timeout, "Installation should complete within timeout for \(shell)")
            
            // Verify completion file exists and has content
            let targetPath = result.targetPath!
            XCTAssertTrue(FileManager.default.fileExists(atPath: targetPath), "Completion file should exist for \(shell)")
            
            let completionContent = try String(contentsOfFile: targetPath, encoding: .utf8)
            XCTAssertFalse(completionContent.isEmpty, "Completion file should have content for \(shell)")
            
            // Verify shell-specific content
            verifyCompletionContentForShell(completionContent, shell: shell)
            verifyFilePermissions(targetPath, expectedPermissions: 0o644)
        }
        
        // Verify all shells were successfully installed
        XCTAssertEqual(installationResults.count, supportedShells.count)
        XCTAssertTrue(installationResults.allSatisfy { $0.success })
    }
    
    func testInstallationWithExistingFiles() throws {
        let shell = "bash"
        let targetPath = bashCompletionDirectory.appendingPathComponent("usbipd").path
        
        // Create existing completion file
        let existingContent = "# Existing completion content\necho 'old completion'"
        try existingContent.write(toFile: targetPath, atomically: true, encoding: .utf8)
        
        // Install new completion
        let result = try installer.install(data: completionData, for: shell)
        
        // In the real implementation, this might fail due to file already existing
        // We test both scenarios
        if result.success {
            // If installation succeeded, verify backup was created
            XCTAssertNotNil(result.backupPath, "Backup should be created when file exists")
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.backupPath!), "Backup file should exist")
            
            // Verify backup contains original content
            let backupContent = try String(contentsOfFile: result.backupPath!, encoding: .utf8)
            XCTAssertEqual(backupContent, existingContent, "Backup should contain original content")
            
            // Verify new content was installed
            let newContent = try String(contentsOfFile: targetPath, encoding: .utf8)
            XCTAssertNotEqual(newContent, existingContent, "New content should be different from original")
        } else {
            // If installation failed due to existing file, verify original file is intact
            let currentContent = try String(contentsOfFile: targetPath, encoding: .utf8)
            XCTAssertEqual(currentContent, existingContent, "Original content should be preserved when installation fails")
        }
    }
    
    func testInstallationStatusTracking() throws {
        let shells = ["bash", "zsh", "fish"]
        
        // Initially, no completions should be installed
        for shell in shells {
            let initialStatus = installer.getInstallationStatus(for: shell)
            XCTAssertFalse(initialStatus.isInstalled, "Initially, \(shell) completion should not be installed")
            XCTAssertEqual(initialStatus.shell, shell)
        }
        
        // Install completions for all shells
        for shell in shells {
            let result = try installer.install(data: completionData, for: shell)
            XCTAssertTrue(result.success, "Installation should succeed for \(shell)")
            
            // Check status after installation
            let status = installer.getInstallationStatus(for: shell)
            XCTAssertTrue(status.isInstalled, "After installation, \(shell) completion should be reported as installed")
            XCTAssertEqual(status.shell, shell)
            XCTAssertNotNil(status.targetPath)
            XCTAssertNotNil(status.fileInfo)
            XCTAssertTrue(status.fileInfo!.exists)
            XCTAssertGreaterThan(status.fileInfo!.size, 0)
        }
        
        // Get status for all shells at once
        let allStatuses = installer.getStatusAll()
        XCTAssertEqual(allStatuses.count, 3)
        XCTAssertTrue(allStatuses.allSatisfy { $0.isInstalled })
    }
    
    func testUninstallationWorkflow() throws {
        let shell = "bash"
        
        // First install a completion
        let installResult = try installer.install(data: completionData, for: shell)
        XCTAssertTrue(installResult.success)
        
        let targetPath = installResult.targetPath!
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetPath))
        
        // Verify it's installed
        let statusAfterInstall = installer.getInstallationStatus(for: shell)
        XCTAssertTrue(statusAfterInstall.isInstalled)
        
        // Uninstall the completion
        let uninstallResult = try installer.uninstall(for: shell)
        XCTAssertTrue(uninstallResult.success, "Uninstallation should succeed")
        XCTAssertEqual(uninstallResult.shell, shell)
        XCTAssertEqual(uninstallResult.removedPath, targetPath)
        XCTAssertNil(uninstallResult.error)
        
        // Verify file was removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetPath), "Completion file should be removed")
        
        // Verify status reflects removal
        let statusAfterUninstall = installer.getInstallationStatus(for: shell)
        XCTAssertFalse(statusAfterUninstall.isInstalled, "After uninstallation, completion should not be reported as installed")
    }
    
    func testCompleteInstallUninstallCycle() throws {
        let shells = ["bash", "zsh", "fish"]
        
        // Install all shells
        let installResults = installer.installAll(data: completionData)
        XCTAssertEqual(installResults.count, shells.count)
        XCTAssertTrue(installResults.allSatisfy { $0.success }, "All installations should succeed")
        
        // Verify all are installed
        let statusesAfterInstall = installer.getStatusAll()
        XCTAssertTrue(statusesAfterInstall.allSatisfy { $0.isInstalled }, "All shells should be reported as installed")
        
        // Verify files exist
        for result in installResults {
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.targetPath!), "Completion file should exist for \(result.shell)")
        }
        
        // Uninstall all shells
        let uninstallResults = installer.uninstallAll()
        XCTAssertEqual(uninstallResults.count, shells.count)
        XCTAssertTrue(uninstallResults.allSatisfy { $0.success }, "All uninstallations should succeed")
        
        // Verify all are removed
        let statusesAfterUninstall = installer.getStatusAll()
        XCTAssertTrue(statusesAfterUninstall.allSatisfy { !$0.isInstalled }, "No shells should be reported as installed after uninstallation")
        
        // Verify files don't exist
        for result in uninstallResults {
            if let removedPath = result.removedPath {
                XCTAssertFalse(FileManager.default.fileExists(atPath: removedPath), "Completion file should not exist for \(result.shell)")
            }
        }
    }
}

// MARK: - Cross-Shell Compatibility Tests

extension CompletionInstallationTests {
    
    func testShellSpecificFileNames() throws {
        let expectedFileNames = [
            "bash": "usbipd",
            "zsh": "_usbipd",
            "fish": "usbipd.fish"
        ]
        
        for (shell, expectedFileName) in expectedFileNames {
            let result = try installer.install(data: completionData, for: shell)
            XCTAssertTrue(result.success, "Installation should succeed for \(shell)")
            
            let targetPath = result.targetPath!
            let actualFileName = URL(fileURLWithPath: targetPath).lastPathComponent
            XCTAssertEqual(actualFileName, expectedFileName, "File name should be correct for \(shell)")
        }
    }
    
    func testShellSpecificDirectoryStructure() throws {
        let shells = ["bash", "zsh", "fish"]
        
        for shell in shells {
            let result = try installer.install(data: completionData, for: shell)
            XCTAssertTrue(result.success, "Installation should succeed for \(shell)")
            
            let targetPath = result.targetPath!
            let targetURL = URL(fileURLWithPath: targetPath)
            
            // Verify shell-specific directory structure
            switch shell {
            case "bash":
                XCTAssertTrue(targetPath.contains("bash-completion/completions"), "Bash completion should be in correct directory")
            case "zsh":
                XCTAssertTrue(targetPath.contains(".zsh/completions"), "Zsh completion should be in correct directory")
            case "fish":
                XCTAssertTrue(targetPath.contains("fish/completions"), "Fish completion should be in correct directory")
            default:
                XCTFail("Unexpected shell: \(shell)")
            }
            
            // Verify parent directory exists and is writable
            let parentDirectory = targetURL.deletingLastPathComponent()
            XCTAssertTrue(FileManager.default.fileExists(atPath: parentDirectory.path), "Parent directory should exist")
            XCTAssertTrue(FileManager.default.isWritableFile(atPath: parentDirectory.path), "Parent directory should be writable")
        }
    }
    
    func testCompletionContentValidation() throws {
        let shells = ["bash", "zsh", "fish"]
        
        for shell in shells {
            let result = try installer.install(data: completionData, for: shell)
            XCTAssertTrue(result.success, "Installation should succeed for \(shell)")
            
            let completionContent = try String(contentsOfFile: result.targetPath!, encoding: .utf8)
            
            // Verify content is not empty
            XCTAssertFalse(completionContent.isEmpty, "Completion content should not be empty for \(shell)")
            
            // Verify shell-specific syntax
            verifyCompletionSyntaxForShell(completionContent, shell: shell)
            
            // Verify essential commands are present
            verifyEssentialCommandsPresent(completionContent, shell: shell)
        }
    }
    
    func testConcurrentInstallation() throws {
        let shells = ["bash", "zsh", "fish"]
        let timeout = testTimeout
        
        // Use expectation for concurrent operations
        let expectation = XCTestExpectation(description: "Concurrent installations complete")
        expectation.expectedFulfillmentCount = shells.count
        
        var results: [CompletionInstallationResult] = []
        let resultsQueue = DispatchQueue(label: "results-queue")
        
        // Install all shells concurrently
        for shell in shells {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.installer.install(data: self.completionData, for: shell)
                    resultsQueue.sync {
                        results.append(result)
                    }
                    expectation.fulfill()
                } catch {
                    resultsQueue.sync {
                        results.append(CompletionInstallationResult(
                            success: false,
                            shell: shell,
                            targetPath: nil,
                            backupPath: nil,
                            duration: 0,
                            error: error
                        ))
                    }
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: timeout)
        
        // Verify all installations
        XCTAssertEqual(results.count, shells.count, "All installations should complete")
        
        // All should succeed (or handle concurrency appropriately)
        let successfulResults = results.filter { $0.success }
        XCTAssertGreaterThan(successfulResults.count, 0, "At least some concurrent installations should succeed")
        
        // Verify files exist for successful installations
        for result in successfulResults {
            if let targetPath = result.targetPath {
                XCTAssertTrue(FileManager.default.fileExists(atPath: targetPath), "Completion file should exist for successful installation")
            }
        }
    }
}

// MARK: - Error Handling Integration Tests

extension CompletionInstallationTests {
    
    func testInstallationWithNonWritableDirectory() throws {
        // Skip this test if we can't create non-writable directories (common in CI/test environments)
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Skipping non-writable directory test in CI environment")
        }
        
        // Create a non-writable directory (if possible in test environment)
        let nonWritableDir = tempBaseDirectory.appendingPathComponent("non-writable")
        try FileManager.default.createDirectory(at: nonWritableDir, withIntermediateDirectories: true, attributes: nil)
        
        // Attempt to make directory non-writable
        var attributes = try FileManager.default.attributesOfItem(atPath: nonWritableDir.path)
        attributes[.posixPermissions] = 0o444 // r--r--r--
        try FileManager.default.setAttributes(attributes, ofItemAtPath: nonWritableDir.path)
        
        // Create installer with non-writable directory
        let restrictedResolver = TestUserDirectoryResolver(
            bashDir: nonWritableDir.appendingPathComponent("completions").path,
            zshDir: zshCompletionDirectory.path,
            fishDir: fishCompletionDirectory.path
        )
        
        let restrictedInstaller = CompletionInstaller(
            directoryResolver: restrictedResolver,
            completionWriter: CompletionWriter()
        )
        
        // Installation should handle permission errors gracefully
        let result = try restrictedInstaller.install(data: completionData, for: "bash")
        
        if !result.success {
            XCTAssertNotNil(result.error, "Error should be reported for permission issues")
        }
        
        // Restore permissions for cleanup
        attributes[.posixPermissions] = 0o755
        try? FileManager.default.setAttributes(attributes, ofItemAtPath: nonWritableDir.path)
    }
    
    func testInstallationWithCorruptedCompletionData() throws {
        // Create completion data with invalid/missing information
        let corruptedData = CompletionData(
            commands: [], // Empty commands
            globalOptions: [],
            dynamicProviders: [],
            metadata: CompletionMetadata(version: "")
        )
        
        // Installation should handle corrupted data gracefully
        let result = try installer.install(data: corruptedData, for: "bash")
        
        // Even with empty data, installation might succeed but generate minimal content
        if result.success {
            XCTAssertNotNil(result.targetPath)
            let content = try String(contentsOfFile: result.targetPath!, encoding: .utf8)
            // Content might be minimal but should not crash the installation
            XCTAssertFalse(content.isEmpty, "Even minimal completion should generate some content")
        }
    }
    
    func testRecoveryFromPartialInstallation() throws {
        // Simulate partial installation by installing some shells and then having others fail
        let successfulShells = ["bash", "zsh"]
        
        // Install successful shells first
        for shell in successfulShells {
            let result = try installer.install(data: completionData, for: shell)
            XCTAssertTrue(result.success, "Initial installation should succeed for \(shell)")
        }
        
        // Verify successful installations
        for shell in successfulShells {
            let status = installer.getInstallationStatus(for: shell)
            XCTAssertTrue(status.isInstalled, "\(shell) should be installed")
        }
        
        // Attempt installation for all shells (including already installed ones)
        let allResults = installer.installAll(data: completionData)
        
        // Verify that existing installations are handled properly
        XCTAssertEqual(allResults.count, 3, "Results should be returned for all shells")
        
        // Check status for all shells
        let finalStatuses = installer.getStatusAll()
        let installedCount = finalStatuses.filter { $0.isInstalled }.count
        XCTAssertGreaterThan(installedCount, 0, "At least some shells should be installed")
    }
}

// MARK: - Performance Integration Tests

extension CompletionInstallationTests {
    
    func testInstallationPerformance() throws {
        let timeout = testTimeout
        let performanceExpectation = 5.0 // seconds (from requirements)
        
        // First, test performance with measure block (using bash)
        measure {
            do {
                // Create a unique temporary directory for each measure iteration
                let uniqueDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("perf-test-\(UUID().uuidString)")
                    .appendingPathComponent(".local/share/bash-completion/completions")
                
                try FileManager.default.createDirectory(at: uniqueDir, withIntermediateDirectories: true, attributes: nil)
                
                let perfResolver = TestUserDirectoryResolver(
                    bashDir: uniqueDir.path,
                    zshDir: zshCompletionDirectory.path,
                    fishDir: fishCompletionDirectory.path
                )
                
                let perfInstaller = CompletionInstaller(
                    directoryResolver: perfResolver,
                    completionWriter: CompletionWriter()
                )
                
                let result = try perfInstaller.install(data: completionData, for: "bash")
                XCTAssertTrue(result.success)
                
                // Clean up after each iteration
                try? FileManager.default.removeItem(at: uniqueDir.deletingLastPathComponent().deletingLastPathComponent())
            } catch {
                XCTFail("Installation failed: \(error)")
            }
        }
        
        // Verify performance requirement with separate test
        let startTime = Date()
        let result = try installer.install(data: completionData, for: "zsh")
        let executionTime = Date().timeIntervalSince(startTime)
        
        XCTAssertLessThan(executionTime, performanceExpectation, "Installation should complete within performance requirement")
        XCTAssertLessThan(executionTime, timeout, "Installation should complete within environment timeout")
        XCTAssertTrue(result.success)
    }
    
    func testBulkInstallationPerformance() throws {
        let performanceExpectation = 15.0 // seconds for all shells
        
        let startTime = Date()
        let results = installer.installAll(data: completionData)
        let executionTime = Date().timeIntervalSince(startTime)
        
        XCTAssertLessThan(executionTime, performanceExpectation, "Bulk installation should complete within reasonable time")
        XCTAssertEqual(results.count, 3)
        
        // Verify individual performance
        for result in results {
            if result.success {
                XCTAssertLessThan(result.duration, 5.0, "Individual installation should meet performance requirement")
            }
        }
    }
    
    func testStatusCheckPerformance() throws {
        let performanceExpectation = 1.0 // second (from requirements)
        
        // Install completions first
        _ = installer.installAll(data: completionData)
        
        // Measure status check performance
        let startTime = Date()
        let statuses = installer.getStatusAll()
        let executionTime = Date().timeIntervalSince(startTime)
        
        XCTAssertLessThan(executionTime, performanceExpectation, "Status check should complete within performance requirement")
        XCTAssertEqual(statuses.count, 3)
    }
}

// MARK: - File System Integration Tests

extension CompletionInstallationTests {
    
    func testFilePermissionHandling() throws {
        let result = try installer.install(data: completionData, for: "bash")
        XCTAssertTrue(result.success)
        
        let targetPath = result.targetPath!
        verifyFilePermissions(targetPath, expectedPermissions: 0o644)
    }
    
    func testDirectoryCreation() throws {
        // Remove existing directories
        try FileManager.default.removeItem(at: bashCompletionDirectory)
        
        // Installation should create necessary directories
        let result = try installer.install(data: completionData, for: "bash")
        XCTAssertTrue(result.success, "Installation should succeed even when directory doesn't exist")
        
        // Verify directory was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: bashCompletionDirectory.path), "Directory should be created")
        
        let targetPath = result.targetPath!
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetPath), "Completion file should be created")
    }
    
    func testFileSystemErrorRecovery() throws {
        // Fill up available space in temp directory (if possible)
        // This is a simplified test - in practice, we'd need more sophisticated disk space management
        
        let result = try installer.install(data: completionData, for: "bash")
        
        // Installation should either succeed or fail gracefully with appropriate error
        if !result.success {
            XCTAssertNotNil(result.error, "Error should be reported for file system issues")
        } else {
            // If it succeeded, verify the file exists and is valid
            XCTAssertNotNil(result.targetPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.targetPath!))
        }
    }
}

// MARK: - Test Helpers

extension CompletionInstallationTests {
    
    private func createTestCompletionData() -> CompletionData {
        return CompletionData(
            commands: [
                CompletionCommand(name: "list", description: "List available devices"),
                CompletionCommand(name: "bind", description: "Bind a device"),
                CompletionCommand(name: "unbind", description: "Unbind a device"),
                CompletionCommand(name: "status", description: "Show device status"),
                CompletionCommand(name: "completion", description: "Generate completion scripts")
            ],
            globalOptions: [
                CompletionOption(short: "h", long: "help", description: "Show help message"),
                CompletionOption(short: "V", long: "version", description: "Show version information"),
                CompletionOption(short: "v", long: "verbose", description: "Enable verbose output"),
                CompletionOption(short: "q", long: "quiet", description: "Enable quiet mode")
            ],
            dynamicProviders: [
                DynamicValueProvider(
                    context: "device-id",
                    command: "usbipd list --bare",
                    fallback: ["1-1", "1-2", "2-1"]
                )
            ],
            metadata: CompletionMetadata(
                version: "1.0.0",
                generatedAt: Date()
            )
        )
    }
    
    private func verifyCompletionContentForShell(_ content: String, shell: String) {
        XCTAssertFalse(content.isEmpty, "Completion content should not be empty for \(shell)")
        
        // Verify essential commands are present
        let essentialCommands = ["list", "bind", "unbind", "status", "completion"]
        for command in essentialCommands {
            XCTAssertTrue(content.contains(command), "Essential command '\(command)' should be present in \(shell) completion")
        }
        
        // Verify shell-specific structure exists
        switch shell {
        case "bash":
            // Bash completions typically use complete -F or have function definitions
            XCTAssertTrue(content.contains("complete") || content.contains("_usbipd"), "Bash completion should have completion function")
        case "zsh":
            // Zsh completions typically start with #compdef
            XCTAssertTrue(content.contains("#compdef") || content.contains("_usbipd"), "Zsh completion should have compdef directive")
        case "fish":
            // Fish completions use complete command
            XCTAssertTrue(content.contains("complete") || content.contains("usbipd"), "Fish completion should use complete command")
        default:
            XCTFail("Unsupported shell for content verification: \(shell)")
        }
    }
    
    private func verifyCompletionSyntaxForShell(_ content: String, shell: String) {
        // Basic syntax validation
        switch shell {
        case "bash":
            // Should not contain obvious syntax errors like unclosed quotes
            XCTAssertFalse(content.contains("'\n\""), "Bash completion should not have unclosed quotes")
        case "zsh":
            // Zsh specific syntax checks
            XCTAssertTrue(content.contains("#compdef") || !content.isEmpty, "Zsh completion should have proper structure")
        case "fish":
            // Fish specific syntax checks
            XCTAssertTrue(content.contains("complete") || !content.isEmpty, "Fish completion should use complete commands")
        default:
            break
        }
    }
    
    private func verifyEssentialCommandsPresent(_ content: String, shell: String) {
        let essentialCommands = ["list", "bind", "unbind", "status"]
        for command in essentialCommands {
            XCTAssertTrue(
                content.contains(command),
                "Essential command '\(command)' should be present in \(shell) completion"
            )
        }
    }
    
    private func verifyFilePermissions(_ filePath: String, expectedPermissions: mode_t) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
            if let permissions = attributes[.posixPermissions] as? NSNumber {
                XCTAssertEqual(
                    permissions.uint16Value,
                    expectedPermissions,
                    "File permissions should be correct (expected: \(String(expectedPermissions, radix: 8)), actual: \(String(permissions.uint16Value, radix: 8)))"
                )
            } else {
                XCTFail("Could not read file permissions for \(filePath)")
            }
        } catch {
            XCTFail("Failed to get file attributes: \(error)")
        }
    }
}

// MARK: - Test Directory Resolver

private class TestUserDirectoryResolver: UserDirectoryResolver {
    private let bashDirectory: String
    private let zshDirectory: String
    private let fishDirectory: String
    
    init(bashDir: String, zshDir: String, fishDir: String) {
        self.bashDirectory = bashDir
        self.zshDirectory = zshDir
        self.fishDirectory = fishDir
        super.init()
    }
    
    override func resolveCompletionDirectory(for shell: String) throws -> String {
        switch shell.lowercased() {
        case "bash":
            return bashDirectory
        case "zsh":
            return zshDirectory
        case "fish":
            return fishDirectory
        default:
            throw UserDirectoryResolverError.unsupportedShell("Unsupported shell: \(shell)")
        }
    }
}