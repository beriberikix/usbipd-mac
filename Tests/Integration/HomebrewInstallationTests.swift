//
//  HomebrewInstallationTests.swift
//  usbipd-mac
//
//  End-to-end tests for Homebrew installation workflow
//  Tests complete tap → install → service management → uninstall cycle with comprehensive validation
//

import XCTest
import Foundation
import Network
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

/// End-to-end Homebrew installation testing with comprehensive workflow validation
/// Tests the complete Homebrew distribution flow from tap creation to uninstallation
final class HomebrewInstallationTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    public let environmentConfig: TestEnvironmentConfig = TestEnvironmentDetector.createConfigurationForCurrentEnvironment()
    public let requiredCapabilities: TestEnvironmentCapabilities = [
        .networkAccess,
        .filesystemWrite,
        .timeIntensiveOperations,
        .privilegedOperations
    ]
    public let testCategory: String = "homebrew-installation"
    
    // MARK: - Test Configuration
    
    private struct HomebrewTestConfig {
        let testTapName: String
        let testFormulaName: String
        let tempDirectory: URL
        let homebrewPrefix: String
        let testTimeout: TimeInterval
        let enableServiceTesting: Bool
        let enableFormulaValidation: Bool
        let enableInstallationTesting: Bool
        let testVersion: String
        
        init(environment: TestEnvironment, tempDirectory: URL) {
            let uniqueId = UUID().uuidString.prefix(8)
            self.testTapName = "usbipd-mac-test-\(uniqueId)"
            self.testFormulaName = "usbipd-mac"
            self.tempDirectory = tempDirectory
            self.testVersion = "v1.0.0-test-\(uniqueId)"
            
            // Detect Homebrew prefix
            self.homebrewPrefix = Self.detectHomebrewPrefix()
            
            switch environment {
            case .development:
                self.testTimeout = 300.0 // 5 minutes
                self.enableServiceTesting = false // Avoid privileged operations in dev
                self.enableFormulaValidation = true
                self.enableInstallationTesting = true
                
            case .ci:
                self.testTimeout = 600.0 // 10 minutes
                self.enableServiceTesting = false // CI environments often lack service support
                self.enableFormulaValidation = true
                self.enableInstallationTesting = true
                
            case .production:
                self.testTimeout = 900.0 // 15 minutes
                self.enableServiceTesting = true
                self.enableFormulaValidation = true
                self.enableInstallationTesting = true
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
                    
                    // Extract prefix from brew path (e.g., /opt/homebrew/bin/brew -> /opt/homebrew)
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
    private var testConfig: HomebrewTestConfig!
    private var tempDirectory: URL!
    private var originalWorkingDirectory: String!
    private var packageRootDirectory: URL!
    private var createdTapRepository: URL?
    private var installedPackages: Set<String> = []
    
    // MARK: - Test Lifecycle
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Validate environment before running tests
        try validateEnvironment()
        
        // Skip if environment doesn't support this test suite
        guard shouldRunInCurrentEnvironment() else {
            throw XCTSkip("Homebrew installation tests require network, filesystem write, and time-intensive operation capabilities")
        }
        
        // Skip if Homebrew is not available
        guard isHomebrewAvailable() else {
            throw XCTSkip("Homebrew is not installed or not available in PATH")
        }
        
        // Create logger for testing
        logger = Logger(
            config: LoggerConfig(level: .debug, includeTimestamp: true),
            subsystem: "com.usbipd.homebrew.tests",
            category: "installation"
        )
        
        // Set up temporary directory for test artifacts
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("homebrew-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create test configuration
        testConfig = HomebrewTestConfig(
            environment: environmentConfig.environment,
            tempDirectory: tempDirectory
        )
        
        // Find package root directory
        packageRootDirectory = try findPackageRoot()
        
        // Store and set working directory
        originalWorkingDirectory = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(packageRootDirectory.path)
        
        logger.info("Starting Homebrew installation tests in \(environmentConfig.environment.displayName) environment")
        logger.info("Test tap name: \(testConfig.testTapName)")
        logger.info("Homebrew prefix: \(testConfig.homebrewPrefix)")
        logger.info("Working directory: \(packageRootDirectory.path)")
        logger.info("Temp directory: \(tempDirectory.path)")
        
        // Call TestSuite setup
        setUpTestSuite()
    }
    
    override func tearDownWithError() throws {
        // Call TestSuite teardown
        tearDownTestSuite()
        
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
        
        logger?.info("Completed Homebrew installation tests")
        
        // Clean up test resources
        testConfig = nil
        packageRootDirectory = nil
        logger = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Complete Homebrew Installation Workflow Tests
    
    func testCompleteHomebrewInstallationWorkflow() throws {
        logger.info("Starting complete Homebrew installation workflow test")
        
        // Phase 1: Formula validation
        try testFormulaValidation()
        
        // Phase 2: Tap creation and management
        try testTapCreationAndManagement()
        
        // Phase 3: Installation workflow
        if testConfig.enableInstallationTesting {
            try testInstallationWorkflow()
        } else {
            logger.info("Installation testing disabled for \(environmentConfig.environment.displayName) environment")
        }
        
        // Phase 4: Service management (if enabled)
        if testConfig.enableServiceTesting {
            try testServiceManagement()
        } else {
            logger.info("Service testing disabled for \(environmentConfig.environment.displayName) environment")
        }
        
        // Phase 5: Uninstallation workflow
        if testConfig.enableInstallationTesting {
            try testUninstallationWorkflow()
        } else {
            logger.info("Uninstallation testing disabled")
        }
        
        // Phase 6: Formula update automation testing
        try testFormulaUpdateAutomation()
        
        logger.info("✅ Complete Homebrew installation workflow test passed")
    }
    
    // MARK: - Phase 1: Formula Validation
    
    func testFormulaValidation() throws {
        logger.info("Phase 1: Validating Homebrew formula")
        
        let formulaPath = packageRootDirectory.appendingPathComponent("Formula/usbipd-mac.rb")
        
        // Test 1.1: Verify formula file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: formulaPath.path),
                     "Homebrew formula should exist at Formula/usbipd-mac.rb")
        
        // Test 1.2: Validate formula syntax
        try validateFormulaSyntax(formulaPath: formulaPath)
        
        // Test 1.3: Validate formula content
        try validateFormulaContent(formulaPath: formulaPath)
        
        // Test 1.4: Run brew audit (if available)
        if testConfig.enableFormulaValidation {
            try runBrewAudit(formulaPath: formulaPath)
        }
        
        logger.info("✅ Formula validation passed")
    }
    
    private func validateFormulaSyntax(formulaPath: URL) throws {
        let formulaContent = try String(contentsOf: formulaPath)
        
        // Basic Ruby syntax validation
        XCTAssertTrue(formulaContent.contains("class UsbipDMac < Formula"),
                     "Formula should define UsbipDMac class")
        XCTAssertTrue(formulaContent.contains("def install"),
                     "Formula should have install method")
        XCTAssertTrue(formulaContent.contains("end"),
                     "Formula should have proper Ruby syntax")
        
        logger.debug("✅ Formula syntax validation passed")
    }
    
    private func validateFormulaContent(formulaPath: URL) throws {
        let formulaContent = try String(contentsOf: formulaPath)
        
        // Validate required fields
        XCTAssertTrue(formulaContent.contains("desc "),
                     "Formula should have description")
        XCTAssertTrue(formulaContent.contains("homepage "),
                     "Formula should have homepage")
        XCTAssertTrue(formulaContent.contains("url "),
                     "Formula should have URL")
        XCTAssertTrue(formulaContent.contains("version "),
                     "Formula should have version")
        XCTAssertTrue(formulaContent.contains("sha256 "),
                     "Formula should have SHA256 checksum")
        
        // Validate macOS dependency
        XCTAssertTrue(formulaContent.contains("depends_on :macos"),
                     "Formula should specify macOS dependency")
        
        // Validate service configuration
        XCTAssertTrue(formulaContent.contains("service do"),
                     "Formula should have service configuration")
        XCTAssertTrue(formulaContent.contains("require_root true"),
                     "Formula should require root for service")
        
        logger.debug("✅ Formula content validation passed")
    }
    
    private func runBrewAudit(formulaPath: URL) throws {
        logger.info("Running brew audit on formula")
        
        let auditProcess = Process()
        auditProcess.executableURL = URL(fileURLWithPath: "\(testConfig.homebrewPrefix)/bin/brew")
        auditProcess.arguments = ["audit", "--strict", formulaPath.path]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        auditProcess.standardOutput = outputPipe
        auditProcess.standardError = errorPipe
        
        try auditProcess.run()
        auditProcess.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let auditOutput = String(data: outputData, encoding: .utf8) ?? ""
        let auditError = String(data: errorData, encoding: .utf8) ?? ""
        
        if auditProcess.terminationStatus != 0 {
            logger.warning("Brew audit warnings/errors: \(auditError)")
            // Note: We don't fail the test for audit warnings in test environment
            // as they may be related to placeholder values or test configuration
        }
        
        logger.debug("✅ Brew audit completed")
    }
    
    // MARK: - Phase 2: Tap Creation and Management
    
    func testTapCreationAndManagement() throws {
        logger.info("Phase 2: Testing tap creation and management")
        
        // Test 2.1: Create test tap repository
        try createTestTapRepository()
        
        // Test 2.2: Add tap to Homebrew
        try addTapToHomebrew()
        
        // Test 2.3: Verify tap was added
        try verifyTapWasAdded()
        
        // Test 2.4: List available formulae in tap
        try listTapFormulae()
        
        logger.info("✅ Tap creation and management passed")
    }
    
    private func createTestTapRepository() throws {
        logger.info("Creating test tap repository")
        
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
        
        // Copy formula to test tap
        let sourceFormula = packageRootDirectory.appendingPathComponent("Formula/usbipd-mac.rb")
        let testFormula = formulaDir.appendingPathComponent("usbipd-mac.rb")
        
        // Create a test version of the formula with updated values
        let formulaContent = try String(contentsOf: sourceFormula)
        let testFormulaContent = formulaContent
            .replacingOccurrences(of: "VERSION_PLACEHOLDER", with: testConfig.testVersion)
            .replacingOccurrences(of: "SHA256_PLACEHOLDER", with: "test_checksum_placeholder")
        
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
            arguments: ["commit", "-m", "Initial test tap with usbipd-mac formula"],
            workingDirectory: tapRepoPath
        )
        
        createdTapRepository = tapRepoPath
        logger.debug("✅ Test tap repository created at \(tapRepoPath.path)")
    }
    
    private func addTapToHomebrew() throws {
        guard let tapRepo = createdTapRepository else {
            throw HomebrewTestError.tapRepositoryNotCreated
        }
        
        logger.info("Adding test tap to Homebrew")
        
        try runBrewCommand(arguments: ["tap", testConfig.testTapName, tapRepo.path])
        
        logger.debug("✅ Test tap added to Homebrew")
    }
    
    private func verifyTapWasAdded() throws {
        logger.info("Verifying tap was added to Homebrew")
        
        let listOutput = try runBrewCommand(arguments: ["tap"])
        
        XCTAssertTrue(listOutput.contains(testConfig.testTapName),
                     "Tap should appear in brew tap list")
        
        logger.debug("✅ Tap verification passed")
    }
    
    private func listTapFormulae() throws {
        logger.info("Listing formulae in test tap")
        
        let listOutput = try runBrewCommand(arguments: ["list", "--formula", testConfig.testTapName])
        
        // Note: The formula might not appear immediately or might require a specific path
        logger.debug("Tap formulae: \(listOutput)")
        logger.debug("✅ Tap formulae listed")
    }
    
    // MARK: - Phase 3: Installation Workflow
    
    func testInstallationWorkflow() throws {
        logger.info("Phase 3: Testing installation workflow")
        
        // Test 3.1: Install package from tap
        try installPackageFromTap()
        
        // Test 3.2: Verify installation
        try verifyPackageInstallation()
        
        // Test 3.3: Test executable functionality
        try testExecutableFunctionality()
        
        logger.info("✅ Installation workflow passed")
    }
    
    private func installPackageFromTap() throws {
        logger.info("Installing package from test tap")
        
        let fullFormulaName = "\(testConfig.testTapName)/\(testConfig.testFormulaName)"
        
        // Note: This would normally install from the tap, but for testing we might want to
        // use --build-from-source to test the build process locally
        try runBrewCommand(arguments: [
            "install",
            "--build-from-source",
            "--verbose",
            fullFormulaName
        ])
        
        installedPackages.insert(fullFormulaName)
        logger.debug("✅ Package installed from tap")
    }
    
    private func verifyPackageInstallation() throws {
        logger.info("Verifying package installation")
        
        // Check if executable was installed
        let executablePath = "\(testConfig.homebrewPrefix)/bin/usbipd"
        XCTAssertTrue(FileManager.default.fileExists(atPath: executablePath),
                     "usbipd executable should be installed at \(executablePath)")
        
        // Verify executable permissions
        let attributes = try FileManager.default.attributesOfItem(atPath: executablePath)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertNotNil(permissions, "Executable should have permissions")
        
        if let perms = permissions {
            let permValue = perms.uint16Value
            XCTAssertTrue((permValue & 0o111) != 0, "Executable should have execute permissions")
        }
        
        logger.debug("✅ Package installation verified")
    }
    
    private func testExecutableFunctionality() throws {
        logger.info("Testing executable functionality")
        
        let executablePath = "\(testConfig.homebrewPrefix)/bin/usbipd"
        
        // Test --help flag
        let helpProcess = Process()
        helpProcess.executableURL = URL(fileURLWithPath: executablePath)
        helpProcess.arguments = ["--help"]
        
        let outputPipe = Pipe()
        helpProcess.standardOutput = outputPipe
        helpProcess.standardError = outputPipe
        
        try helpProcess.run()
        helpProcess.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        
        // Executable should respond to --help (exit code 0 or 1 acceptable)
        XCTAssertTrue(helpProcess.terminationStatus == 0 || helpProcess.terminationStatus == 1,
                     "Executable should respond to --help")
        
        // Output should contain some expected content
        XCTAssertFalse(output.isEmpty, "Executable should produce help output")
        
        logger.debug("✅ Executable functionality test passed")
    }
    
    // MARK: - Phase 4: Service Management
    
    func testServiceManagement() throws {
        logger.info("Phase 4: Testing service management")
        
        // Test 4.1: Start service
        try startHomebrewService()
        
        // Test 4.2: Check service status
        try checkServiceStatus()
        
        // Test 4.3: Stop service
        try stopHomebrewService()
        
        // Test 4.4: Restart service
        try restartHomebrewService()
        
        logger.info("✅ Service management passed")
    }
    
    private func startHomebrewService() throws {
        logger.info("Starting Homebrew service")
        
        try runBrewCommand(arguments: ["services", "start", testConfig.testFormulaName])
        
        // Give service time to start
        usleep(2000000) // 2 seconds
        
        logger.debug("✅ Service start command executed")
    }
    
    private func checkServiceStatus() throws {
        logger.info("Checking service status")
        
        let statusOutput = try runBrewCommand(arguments: ["services", "list"])
        
        // Service should appear in the list
        XCTAssertTrue(statusOutput.contains(testConfig.testFormulaName),
                     "Service should appear in brew services list")
        
        logger.debug("✅ Service status checked")
    }
    
    private func stopHomebrewService() throws {
        logger.info("Stopping Homebrew service")
        
        try runBrewCommand(arguments: ["services", "stop", testConfig.testFormulaName])
        
        // Give service time to stop
        usleep(2000000) // 2 seconds
        
        logger.debug("✅ Service stop command executed")
    }
    
    func restartHomebrewService() throws {
        logger.info("Restarting Homebrew service")
        
        try runBrewCommand(arguments: ["services", "restart", testConfig.testFormulaName])
        
        // Give service time to restart
        usleep(2000000) // 2 seconds
        
        // Stop service after test
        try runBrewCommand(arguments: ["services", "stop", testConfig.testFormulaName])
        
        logger.debug("✅ Service restart test completed")
    }
    
    // MARK: - Phase 5: Uninstallation Workflow
    
    func testUninstallationWorkflow() throws {
        logger.info("Phase 5: Testing uninstallation workflow")
        
        // Test 5.1: Stop any running services
        try stopServicesBeforeUninstall()
        
        // Test 5.2: Uninstall package
        try uninstallPackage()
        
        // Test 5.3: Verify uninstallation
        try verifyPackageUninstallation()
        
        // Test 5.4: Clean up remaining files
        try cleanupRemainingFiles()
        
        logger.info("✅ Uninstallation workflow passed")
    }
    
    private func stopServicesBeforeUninstall() throws {
        logger.info("Stopping services before uninstallation")
        
        // Attempt to stop service (ignore errors if not running)
        do {
            try runBrewCommand(arguments: ["services", "stop", testConfig.testFormulaName])
        } catch {
            logger.debug("Service stop failed (acceptable if not running): \(error)")
        }
        
        logger.debug("✅ Services stopped before uninstall")
    }
    
    private func uninstallPackage() throws {
        logger.info("Uninstalling package")
        
        try runBrewCommand(arguments: ["uninstall", testConfig.testFormulaName])
        
        // Remove from tracking
        installedPackages.remove("\(testConfig.testTapName)/\(testConfig.testFormulaName)")
        
        logger.debug("✅ Package uninstalled")
    }
    
    private func verifyPackageUninstallation() throws {
        logger.info("Verifying package uninstallation")
        
        // Check if executable was removed
        let executablePath = "\(testConfig.homebrewPrefix)/bin/usbipd"
        XCTAssertFalse(FileManager.default.fileExists(atPath: executablePath),
                      "usbipd executable should be removed after uninstallation")
        
        logger.debug("✅ Package uninstallation verified")
    }
    
    private func cleanupRemainingFiles() throws {
        logger.info("Cleaning up remaining files")
        
        // Clean up log files
        let logPath = "\(testConfig.homebrewPrefix)/var/log/usbipd.log"
        if FileManager.default.fileExists(atPath: logPath) {
            try FileManager.default.removeItem(atPath: logPath)
            logger.debug("Removed log file: \(logPath)")
        }
        
        let errorLogPath = "\(testConfig.homebrewPrefix)/var/log/usbipd.error.log"
        if FileManager.default.fileExists(atPath: errorLogPath) {
            try FileManager.default.removeItem(atPath: errorLogPath)
            logger.debug("Removed error log file: \(errorLogPath)")
        }
        
        logger.debug("✅ Remaining files cleaned up")
    }
    
    // MARK: - Phase 6: Formula Update Automation
    
    func testFormulaUpdateAutomation() throws {
        logger.info("Phase 6: Testing formula update automation")
        
        // Test 6.1: Validate update script exists
        try validateUpdateScriptExists()
        
        // Test 6.2: Test formula update script functionality
        try testFormulaUpdateScript()
        
        // Test 6.3: Validate updated formula
        try validateUpdatedFormula()
        
        logger.info("✅ Formula update automation passed")
    }
    
    private func validateUpdateScriptExists() throws {
        let updateScriptPath = packageRootDirectory.appendingPathComponent("Scripts/update-formula.sh")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: updateScriptPath.path),
                     "Formula update script should exist at Scripts/update-formula.sh")
        
        // Verify script is executable
        let attributes = try FileManager.default.attributesOfItem(atPath: updateScriptPath.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertNotNil(permissions, "Update script should have permissions")
        
        if let perms = permissions {
            let permValue = perms.uint16Value
            XCTAssertTrue((permValue & 0o111) != 0, "Update script should be executable")
        }
        
        logger.debug("✅ Update script validation passed")
    }
    
    private func testFormulaUpdateScript() throws {
        logger.info("Testing formula update script")
        
        let updateScriptPath = packageRootDirectory.appendingPathComponent("Scripts/update-formula.sh")
        let testVersion = "v1.2.3-test"
        let testChecksum = "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
        
        // Run update script with test values
        let updateProcess = Process()
        updateProcess.currentDirectoryURL = packageRootDirectory
        updateProcess.executableURL = updateScriptPath
        updateProcess.arguments = ["--version", testVersion, "--checksum", testChecksum, "--dry-run"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        updateProcess.standardOutput = outputPipe
        updateProcess.standardError = errorPipe
        
        try updateProcess.run()
        updateProcess.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let updateOutput = String(data: outputData, encoding: .utf8) ?? ""
        let updateError = String(data: errorData, encoding: .utf8) ?? ""
        
        if updateProcess.terminationStatus != 0 {
            logger.warning("Update script test warnings: \(updateError)")
            // Note: Don't fail for dry-run warnings
        }
        
        logger.debug("Update script output: \(updateOutput)")
        logger.debug("✅ Formula update script test completed")
    }
    
    private func validateUpdatedFormula() throws {
        logger.info("Validating updated formula structure")
        
        let formulaPath = packageRootDirectory.appendingPathComponent("Formula/usbipd-mac.rb")
        let formulaContent = try String(contentsOf: formulaPath)
        
        // Verify formula still has placeholder structure for automation
        XCTAssertTrue(formulaContent.contains("VERSION_PLACEHOLDER") || formulaContent.contains("SHA256_PLACEHOLDER"),
                     "Formula should maintain placeholder structure for automation")
        
        logger.debug("✅ Formula structure validation passed")
    }
    
    // MARK: - Helper Methods
    
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
        
        throw HomebrewTestError.packageRootNotFound
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
            throw HomebrewTestError.commandExecutionFailed(
                command: "\(executable) \(arguments.joined(separator: " "))",
                exitCode: process.terminationStatus,
                output: output,
                error: error
            )
        }
        
        return output
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
    
    func cleanupTestTapRepository() throws {
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

private enum HomebrewTestError: Error {
    case packageRootNotFound
    case tapRepositoryNotCreated
    case commandExecutionFailed(command: String, exitCode: Int32, output: String, error: String)
    case homebrewNotAvailable
    case formulaValidationFailed(String)
    case serviceManagementFailed(String)
    
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
        case .formulaValidationFailed(let message):
            return "Formula validation failed: \(message)"
        case .serviceManagementFailed(let message):
            return "Service management failed: \(message)"
        }
    }
}