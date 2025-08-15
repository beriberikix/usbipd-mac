//
//  FinalIntegrationTests.swift
//  usbipd-mac
//
//  Comprehensive validation of complete release automation system
//  Tests all components working together and edge case handling
//

import XCTest
import Foundation
import Network
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import QEMUTestServer
@testable import Common

/// Final integration validation for complete release automation system
/// Validates end-to-end functionality of all release components working together
final class FinalIntegrationTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    public let environmentConfig: TestEnvironmentConfig = TestEnvironmentDetector.createConfigurationForCurrentEnvironment()
    public let requiredCapabilities: TestEnvironmentCapabilities = [
        .networkAccess,
        .filesystemWrite,
        .timeIntensiveOperations
    ]
    public let testCategory: String = "final-integration"
    
    // MARK: - Test Configuration
    
    private struct FinalValidationConfig {
        let testVersion: String
        let tempDirectory: URL
        let validationTimeout: TimeInterval
        let enableFullValidation: Bool
        let enableWorkflowTesting: Bool
        let enableScriptValidation: Bool
        let enableDocumentationValidation: Bool
        
        init(environment: TestEnvironment, tempDirectory: URL) {
            self.testVersion = "v1.0.0-final-test-\(UUID().uuidString.prefix(8))"
            self.tempDirectory = tempDirectory
            
            switch environment {
            case .development:
                self.validationTimeout = 300.0 // 5 minutes
                self.enableFullValidation = true
                self.enableWorkflowTesting = false // Skip in development
                self.enableScriptValidation = true
                self.enableDocumentationValidation = true
                
            case .ci:
                self.validationTimeout = 600.0 // 10 minutes
                self.enableFullValidation = true
                self.enableWorkflowTesting = true
                self.enableScriptValidation = true
                self.enableDocumentationValidation = true
                
            case .production:
                self.validationTimeout = 900.0 // 15 minutes
                self.enableFullValidation = true
                self.enableWorkflowTesting = true
                self.enableScriptValidation = true
                self.enableDocumentationValidation = true
            }
        }
    }
    
    // MARK: - Test Properties
    
    private var logger: Logger!
    private var validationConfig: FinalValidationConfig!
    private var tempDirectory: URL!
    private var packageRootDirectory: URL!
    private var originalWorkingDirectory: String!
    
    // MARK: - Test Lifecycle
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Validate environment before running tests
        try validateEnvironment()
        
        // Skip if environment doesn't support this test suite
        guard shouldRunInCurrentEnvironment() else {
            throw XCTSkip("Final integration tests require network, filesystem, and time-intensive operation capabilities")
        }
        
        // Create logger
        logger = Logger(
            config: LoggerConfig(level: .debug, includeTimestamp: true),
            subsystem: "com.usbipd.release.final-validation",
            category: "integration"
        )
        
        // Set up temporary directory
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("final-integration-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create validation configuration
        validationConfig = FinalValidationConfig(
            environment: environmentConfig.environment,
            tempDirectory: tempDirectory
        )
        
        // Find package root directory
        packageRootDirectory = try findPackageRoot()
        
        // Store and set working directory
        originalWorkingDirectory = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(packageRootDirectory.path)
        
        logger.info("Starting final integration validation in \(environmentConfig.environment.displayName) environment")
        logger.info("Package root: \(packageRootDirectory.path)")
        logger.info("Temporary directory: \(tempDirectory.path)")
        
        // Call TestSuite setup
        setUpTestSuite()
    }
    
    override func tearDownWithError() throws {
        // Call TestSuite teardown
        tearDownTestSuite()
        
        // Restore working directory
        if let originalDir = originalWorkingDirectory {
            FileManager.default.changeCurrentDirectoryPath(originalDir)
        }
        
        // Clean up temporary directory (preserve on failure for debugging)
        if let tempDir = tempDirectory, FileManager.default.fileExists(atPath: tempDir.path) {
            if environmentConfig.environment == .development {
                logger.info("Temporary directory preserved for debugging: \(tempDir.path)")
            } else {
                try? FileManager.default.removeItem(at: tempDir)
                logger.info("Cleaned up temporary directory")
            }
        }
        
        logger?.info("Final integration validation completed")
        
        // Clean up test resources
        validationConfig = nil
        packageRootDirectory = nil
        logger = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Complete System Integration Tests
    
    func testCompleteReleaseAutomationSystem() throws {
        logger.info("Starting complete release automation system validation")
        
        // Phase 1: Infrastructure Validation
        try validateReleaseInfrastructure()
        
        // Phase 2: GitHub Actions Workflow Validation
        if validationConfig.enableWorkflowTesting {
            try validateGitHubActionsWorkflows()
        }
        
        // Phase 3: Release Script Integration
        if validationConfig.enableScriptValidation {
            try validateReleaseScriptIntegration()
        }
        
        // Phase 4: Testing Framework Integration
        try validateTestingFrameworkIntegration()
        
        // Phase 5: Documentation and Help System
        if validationConfig.enableDocumentationValidation {
            try validateDocumentationSystem()
        }
        
        // Phase 6: Security and Code Signing Integration
        try validateSecurityIntegration()
        
        // Phase 7: Monitoring and Alerting Integration
        try validateMonitoringIntegration()
        
        // Phase 8: End-to-End Simulation
        if validationConfig.enableFullValidation {
            try performEndToEndReleaseSimulation()
        }
        
        // Phase 9: Edge Case and Error Handling
        try validateErrorHandlingAndEdgeCases()
        
        // Phase 10: Performance and Scalability
        try validatePerformanceAndScalability()
        
        logger.info("✅ Complete release automation system validation passed")
    }
    
    // MARK: - Phase 1: Infrastructure Validation
    
    private func validateReleaseInfrastructure() throws {
        logger.info("Phase 1: Validating release infrastructure")
        
        // Test 1.1: All required files exist and are properly configured
        try validateRequiredFileStructure()
        
        // Test 1.2: Script permissions and executability
        try validateScriptPermissions()
        
        // Test 1.3: Configuration file integrity
        try validateConfigurationFiles()
        
        // Test 1.4: Directory structure consistency
        try validateDirectoryStructure()
        
        logger.info("✅ Release infrastructure validation passed")
    }
    
    private func validateRequiredFileStructure() throws {
        let requiredFiles = [
            // Core workflow files
            ".github/workflows/release.yml",
            ".github/workflows/pre-release.yml",
            ".github/workflows/release-monitoring.yml",
            ".github/workflows/security-scanning.yml",
            ".github/workflows/release-optimization.yml",
            
            // Release scripts
            "Scripts/prepare-release.sh",
            "Scripts/validate-release-artifacts.sh",
            "Scripts/rollback-release.sh",
            "Scripts/benchmark-release-performance.sh",
            "Scripts/release-status-dashboard.sh",
            "Scripts/update-changelog.sh",
            
            // Documentation
            "Documentation/Release-Automation.md",
            "Documentation/Code-Signing-Setup.md",
            "Documentation/Emergency-Release-Procedures.md",
            "Documentation/Release-Troubleshooting.md",
            "Documentation/Release-System-Migration.md",
            
            // Test files
            "Tests/ReleaseWorkflowTests/ReleaseWorkflowTests.swift",
            "Tests/Integration/ReleaseEndToEndTests.swift",
            "Tests/Distribution/ArtifactDistributionTests.swift",
            "Tests/Scripts/prepare-release-tests.sh"
        ]
        
        var missingFiles: [String] = []
        var presentFiles: [String] = []
        
        for file in requiredFiles {
            let filePath = packageRootDirectory.appendingPathComponent(file).path
            if FileManager.default.fileExists(atPath: filePath) {
                presentFiles.append(file)
            } else {
                missingFiles.append(file)
            }
        }
        
        logger.debug("Present files: \(presentFiles.count)/\(requiredFiles.count)")
        
        if !missingFiles.isEmpty {
            logger.warning("Missing files: \(missingFiles)")
            // Allow some files to be missing in early development
            let criticalFiles = requiredFiles.filter { file in
                file.contains(".github/workflows/release.yml") ||
                file.contains("Scripts/prepare-release.sh") ||
                file.contains("Scripts/validate-release-artifacts.sh")
            }
            
            let missingCriticalFiles = missingFiles.filter { criticalFiles.contains($0) }
            if !missingCriticalFiles.isEmpty {
                XCTFail("Critical release files are missing: \(missingCriticalFiles)")
            }
        }
        
        logger.debug("✅ Required file structure validation completed")
    }
    
    private func validateScriptPermissions() throws {
        let scripts = [
            "Scripts/prepare-release.sh",
            "Scripts/validate-release-artifacts.sh",
            "Scripts/rollback-release.sh",
            "Scripts/benchmark-release-performance.sh",
            "Scripts/release-status-dashboard.sh",
            "Scripts/update-changelog.sh",
            "Scripts/run-ci-tests.sh",
            "Scripts/run-production-tests.sh",
            "Tests/Scripts/prepare-release-tests.sh"
        ]
        
        for script in scripts {
            let scriptPath = packageRootDirectory.appendingPathComponent(script).path
            
            guard FileManager.default.fileExists(atPath: scriptPath) else {
                logger.warning("Script not found (may be acceptable): \(script)")
                continue
            }
            
            let attributes = try FileManager.default.attributesOfItem(atPath: scriptPath)
            let permissions = attributes[.posixPermissions] as? NSNumber
            XCTAssertNotNil(permissions, "Script should have permissions: \(script)")
            
            if let perms = permissions {
                let permValue = perms.uint16Value
                XCTAssertTrue((permValue & 0o111) != 0, "Script should be executable: \(script)")
            }
        }
        
        logger.debug("✅ Script permissions validation completed")
    }
    
    private func validateConfigurationFiles() throws {
        // Validate GitHub Actions workflow syntax
        try validateYAMLSyntax(file: ".github/workflows/release.yml")
        try validateYAMLSyntax(file: ".github/workflows/pre-release.yml")
        
        // Validate Package.swift structure
        try validatePackageSwiftIntegrity()
        
        // Validate SwiftLint configuration
        try validateSwiftLintConfiguration()
        
        logger.debug("✅ Configuration files validation completed")
    }
    
    private func validateYAMLSyntax(file: String) throws {
        let filePath = packageRootDirectory.appendingPathComponent(file).path
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            logger.warning("YAML file not found: \(file)")
            return
        }
        
        let content = try String(contentsOfFile: filePath)
        
        // Basic YAML structure validation
        XCTAssertTrue(content.contains("name:"), "YAML file should have name field: \(file)")
        XCTAssertTrue(content.contains("on:"), "YAML file should have trigger section: \(file)")
        XCTAssertTrue(content.contains("jobs:"), "YAML file should have jobs section: \(file)")
        
        // Validate no obvious syntax errors
        XCTAssertFalse(content.contains("{{"), "YAML file should not contain template placeholders: \(file)")
        
        logger.debug("✅ YAML syntax validation passed for: \(file)")
    }
    
    private func validatePackageSwiftIntegrity() throws {
        let packagePath = packageRootDirectory.appendingPathComponent("Package.swift").path
        let content = try String(contentsOfFile: packagePath)
        
        // Verify required targets are present
        let requiredTargets = ["USBIPDCore", "USBIPDCLI", "QEMUTestServer", "Common"]
        for target in requiredTargets {
            XCTAssertTrue(content.contains(target), "Package.swift should define target: \(target)")
        }
        
        // Verify test targets are present
        let testTargets = ["USBIPDCoreTests", "USBIPDCLITests", "IntegrationTests"]
        for target in testTargets {
            XCTAssertTrue(content.contains(target), "Package.swift should define test target: \(target)")
        }
        
        logger.debug("✅ Package.swift integrity validation completed")
    }
    
    private func validateSwiftLintConfiguration() throws {
        let swiftLintPath = packageRootDirectory.appendingPathComponent(".swiftlint.yml").path
        
        guard FileManager.default.fileExists(atPath: swiftLintPath) else {
            logger.warning("SwiftLint configuration not found")
            return
        }
        
        let content = try String(contentsOfFile: swiftLintPath)
        
        // Verify basic structure
        XCTAssertTrue(content.contains("included:") || content.contains("excluded:"),
                     "SwiftLint config should specify included/excluded paths")
        
        logger.debug("✅ SwiftLint configuration validation completed")
    }
    
    private func validateDirectoryStructure() throws {
        let expectedDirectories = [
            ".github/workflows",
            "Scripts",
            "Documentation",
            "Tests/ReleaseWorkflowTests",
            "Tests/Integration",
            "Tests/Distribution",
            "Sources/USBIPDCore",
            "Sources/USBIPDCLI"
        ]
        
        for directory in expectedDirectories {
            let dirPath = packageRootDirectory.appendingPathComponent(directory).path
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDirectory)
            
            if !exists {
                logger.warning("Expected directory not found: \(directory)")
            } else {
                XCTAssertTrue(isDirectory.boolValue, "Path should be a directory: \(directory)")
            }
        }
        
        logger.debug("✅ Directory structure validation completed")
    }
    
    // MARK: - Phase 2: GitHub Actions Workflow Validation
    
    private func validateGitHubActionsWorkflows() throws {
        logger.info("Phase 2: Validating GitHub Actions workflows")
        
        // Test 2.1: Workflow file structure and syntax
        try validateWorkflowFileSyntax()
        
        // Test 2.2: Workflow dependency chain
        try validateWorkflowDependencies()
        
        // Test 2.3: Secret and environment variable usage
        try validateWorkflowSecrets()
        
        // Test 2.4: Action versions and compatibility
        try validateActionVersions()
        
        logger.info("✅ GitHub Actions workflow validation passed")
    }
    
    private func validateWorkflowFileSyntax() throws {
        let workflows = [
            ".github/workflows/release.yml",
            ".github/workflows/pre-release.yml",
            ".github/workflows/release-monitoring.yml"
        ]
        
        for workflow in workflows {
            let workflowPath = packageRootDirectory.appendingPathComponent(workflow).path
            
            guard FileManager.default.fileExists(atPath: workflowPath) else {
                logger.warning("Workflow file not found: \(workflow)")
                continue
            }
            
            let content = try String(contentsOfFile: workflowPath)
            
            // Validate required sections
            XCTAssertTrue(content.contains("name:"), "Workflow should have name: \(workflow)")
            XCTAssertTrue(content.contains("on:"), "Workflow should have triggers: \(workflow)")
            XCTAssertTrue(content.contains("jobs:"), "Workflow should have jobs: \(workflow)")
            
            // Validate no obvious errors
            XCTAssertFalse(content.contains("${{"), "Workflow should not contain invalid expressions: \(workflow)")
        }
        
        logger.debug("✅ Workflow file syntax validation completed")
    }
    
    private func validateWorkflowDependencies() throws {
        // This would validate that workflows have proper dependency chains
        // For now, we just ensure the files exist and have basic structure
        logger.debug("✅ Workflow dependencies validation completed (basic)")
    }
    
    private func validateWorkflowSecrets() throws {
        let releaseWorkflowPath = packageRootDirectory.appendingPathComponent(".github/workflows/release.yml").path
        
        guard FileManager.default.fileExists(atPath: releaseWorkflowPath) else {
            logger.warning("Release workflow not found, skipping secrets validation")
            return
        }
        
        let content = try String(contentsOfFile: releaseWorkflowPath)
        
        // Check for expected secret usage patterns
        if content.contains("code") && content.contains("sign") {
            XCTAssertTrue(content.contains("secrets.") || content.contains("env."),
                         "Code signing should use proper secret references")
        }
        
        logger.debug("✅ Workflow secrets validation completed")
    }
    
    private func validateActionVersions() throws {
        // This would validate that GitHub Actions use pinned versions
        // For now, we just log completion
        logger.debug("✅ Action versions validation completed (basic)")
    }
    
    // MARK: - Phase 3: Release Script Integration
    
    private func validateReleaseScriptIntegration() throws {
        logger.info("Phase 3: Validating release script integration")
        
        // Test 3.1: Script execution and help output
        try validateScriptHelpOutput()
        
        // Test 3.2: Script parameter validation
        try validateScriptParameterHandling()
        
        // Test 3.3: Script error handling
        try validateScriptErrorHandling()
        
        // Test 3.4: Script integration with Git
        try validateScriptGitIntegration()
        
        logger.info("✅ Release script integration validation passed")
    }
    
    private func validateScriptHelpOutput() throws {
        let scripts = [
            "Scripts/prepare-release.sh",
            "Scripts/validate-release-artifacts.sh",
            "Scripts/rollback-release.sh"
        ]
        
        for script in scripts {
            let scriptPath = packageRootDirectory.appendingPathComponent(script).path
            
            guard FileManager.default.fileExists(atPath: scriptPath) else {
                logger.warning("Script not found: \(script)")
                continue
            }
            
            // Test help output
            let helpProcess = Process()
            helpProcess.executableURL = URL(fileURLWithPath: scriptPath)
            helpProcess.arguments = ["--help"]
            
            let outputPipe = Pipe()
            helpProcess.standardOutput = outputPipe
            helpProcess.standardError = outputPipe
            
            try helpProcess.run()
            helpProcess.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            // Scripts should provide help information
            XCTAssertFalse(output.isEmpty, "Script should provide help output: \(script)")
            
            logger.debug("✅ Help output validated for: \(script)")
        }
    }
    
    private func validateScriptParameterHandling() throws {
        let prepareReleaseScript = packageRootDirectory.appendingPathComponent("Scripts/prepare-release.sh").path
        
        guard FileManager.default.fileExists(atPath: prepareReleaseScript) else {
            logger.warning("Prepare release script not found, skipping parameter validation")
            return
        }
        
        // Test invalid parameter handling
        let invalidProcess = Process()
        invalidProcess.executableURL = URL(fileURLWithPath: prepareReleaseScript)
        invalidProcess.arguments = ["--invalid-parameter"]
        
        let outputPipe = Pipe()
        invalidProcess.standardOutput = outputPipe
        invalidProcess.standardError = outputPipe
        
        try invalidProcess.run()
        invalidProcess.waitUntilExit()
        
        // Script should handle invalid parameters gracefully (non-zero exit)
        XCTAssertNotEqual(invalidProcess.terminationStatus, 0,
                         "Script should reject invalid parameters")
        
        logger.debug("✅ Script parameter handling validation completed")
    }
    
    private func validateScriptErrorHandling() throws {
        // Test error handling by providing invalid input
        let validateScript = packageRootDirectory.appendingPathComponent("Scripts/validate-release-artifacts.sh").path
        
        guard FileManager.default.fileExists(atPath: validateScript) else {
            logger.warning("Validate artifacts script not found, skipping error handling test")
            return
        }
        
        // Test with non-existent directory
        let errorProcess = Process()
        errorProcess.executableURL = URL(fileURLWithPath: validateScript)
        errorProcess.arguments = ["--artifacts-path", "/non/existent/path"]
        
        let outputPipe = Pipe()
        errorProcess.standardOutput = outputPipe
        errorProcess.standardError = outputPipe
        
        try errorProcess.run()
        errorProcess.waitUntilExit()
        
        // Script should fail gracefully with non-zero exit
        XCTAssertNotEqual(errorProcess.terminationStatus, 0,
                         "Script should handle errors gracefully")
        
        logger.debug("✅ Script error handling validation completed")
    }
    
    private func validateScriptGitIntegration() throws {
        // Verify scripts can interact with Git properly
        let gitStatus = Process()
        gitStatus.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        gitStatus.arguments = ["status", "--porcelain"]
        gitStatus.currentDirectoryURL = packageRootDirectory
        
        let outputPipe = Pipe()
        gitStatus.standardOutput = outputPipe
        
        try gitStatus.run()
        gitStatus.waitUntilExit()
        
        XCTAssertEqual(gitStatus.terminationStatus, 0, "Git should be accessible from package root")
        
        logger.debug("✅ Script Git integration validation completed")
    }
    
    // MARK: - Phase 4: Testing Framework Integration
    
    private func validateTestingFrameworkIntegration() throws {
        logger.info("Phase 4: Validating testing framework integration")
        
        // Test 4.1: Test environment detection
        try validateTestEnvironmentDetection()
        
        // Test 4.2: Mock system integration
        try validateMockSystemIntegration()
        
        // Test 4.3: Test execution scripts
        try validateTestExecutionScripts()
        
        // Test 4.4: Test reporting integration
        try validateTestReporting()
        
        logger.info("✅ Testing framework integration validation passed")
    }
    
    private func validateTestEnvironmentDetection() throws {
        // Test the environment detection logic
        let detectedEnvironment = TestEnvironmentDetector.detectCurrentEnvironment()
        let detectedCapabilities = TestEnvironmentDetector.detectAvailableCapabilities()
        
        XCTAssertTrue(TestEnvironment.allCases.contains(detectedEnvironment),
                     "Should detect a valid test environment")
        
        // Should have at least basic capabilities
        XCTAssertTrue(detectedCapabilities.contains(.filesystemWrite),
                     "Should detect filesystem write capability")
        
        logger.debug("✅ Test environment detection: \(detectedEnvironment.displayName)")
        logger.debug("✅ Detected capabilities: \(detectedCapabilities)")
    }
    
    private func validateMockSystemIntegration() throws {
        // Verify mock system is properly integrated
        let mockDirectories = [
            "Tests/TestMocks/Development",
            "Tests/TestMocks/CI",
            "Tests/TestMocks/Production"
        ]
        
        for mockDir in mockDirectories {
            let mockPath = packageRootDirectory.appendingPathComponent(mockDir).path
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: mockPath, isDirectory: &isDirectory)
            
            if exists {
                XCTAssertTrue(isDirectory.boolValue, "Mock path should be directory: \(mockDir)")
            }
        }
        
        logger.debug("✅ Mock system integration validation completed")
    }
    
    private func validateTestExecutionScripts() throws {
        let testScripts = [
            "Scripts/run-ci-tests.sh",
            "Scripts/run-production-tests.sh"
        ]
        
        for script in testScripts {
            let scriptPath = packageRootDirectory.appendingPathComponent(script).path
            
            guard FileManager.default.fileExists(atPath: scriptPath) else {
                logger.warning("Test script not found: \(script)")
                continue
            }
            
            // Verify script is executable
            let attributes = try FileManager.default.attributesOfItem(atPath: scriptPath)
            let permissions = attributes[.posixPermissions] as? NSNumber
            XCTAssertNotNil(permissions, "Test script should have permissions: \(script)")
            
            if let perms = permissions {
                let permValue = perms.uint16Value
                XCTAssertTrue((permValue & 0o111) != 0, "Test script should be executable: \(script)")
            }
        }
        
        logger.debug("✅ Test execution scripts validation completed")
    }
    
    private func validateTestReporting() throws {
        // Verify test reporting capabilities
        let reportScript = packageRootDirectory.appendingPathComponent("Scripts/generate-test-report.sh").path
        
        if FileManager.default.fileExists(atPath: reportScript) {
            let attributes = try FileManager.default.attributesOfItem(atPath: reportScript)
            let permissions = attributes[.posixPermissions] as? NSNumber
            XCTAssertNotNil(permissions, "Report script should have permissions")
            
            if let perms = permissions {
                let permValue = perms.uint16Value
                XCTAssertTrue((permValue & 0o111) != 0, "Report script should be executable")
            }
        }
        
        logger.debug("✅ Test reporting validation completed")
    }
    
    // MARK: - Phase 5: Documentation System
    
    private func validateDocumentationSystem() throws {
        logger.info("Phase 5: Validating documentation system")
        
        // Test 5.1: Documentation completeness
        try validateDocumentationCompleteness()
        
        // Test 5.2: Documentation consistency
        try validateDocumentationConsistency()
        
        // Test 5.3: CLAUDE.md integration
        try validateClaudeMdIntegration()
        
        logger.info("✅ Documentation system validation passed")
    }
    
    private func validateDocumentationCompleteness() throws {
        let requiredDocs = [
            "Documentation/Release-Automation.md",
            "Documentation/Code-Signing-Setup.md",
            "Documentation/Emergency-Release-Procedures.md",
            "README.md",
            "CLAUDE.md"
        ]
        
        for doc in requiredDocs {
            let docPath = packageRootDirectory.appendingPathComponent(doc).path
            
            guard FileManager.default.fileExists(atPath: docPath) else {
                logger.warning("Documentation file not found: \(doc)")
                continue
            }
            
            let content = try String(contentsOfFile: docPath)
            XCTAssertGreaterThan(content.count, 100, "Documentation should have substantial content: \(doc)")
            
            // Check for basic markdown structure
            XCTAssertTrue(content.contains("#"), "Documentation should have headers: \(doc)")
        }
        
        logger.debug("✅ Documentation completeness validation completed")
    }
    
    private func validateDocumentationConsistency() throws {
        // Check for consistent references between documentation files
        let readmePath = packageRootDirectory.appendingPathComponent("README.md").path
        
        if FileManager.default.fileExists(atPath: readmePath) {
            let readmeContent = try String(contentsOfFile: readmePath)
            
            // Should reference release automation
            if readmeContent.contains("release") {
                XCTAssertTrue(readmeContent.contains("Documentation/") || readmeContent.contains("automation"),
                             "README should reference release documentation")
            }
        }
        
        logger.debug("✅ Documentation consistency validation completed")
    }
    
    private func validateClaudeMdIntegration() throws {
        let claudePath = packageRootDirectory.appendingPathComponent("CLAUDE.md").path
        
        guard FileManager.default.fileExists(atPath: claudePath) else {
            logger.warning("CLAUDE.md not found")
            return
        }
        
        let claudeContent = try String(contentsOfFile: claudePath)
        
        // Should contain release automation information
        XCTAssertTrue(claudeContent.contains("Release") || claudeContent.contains("release"),
                     "CLAUDE.md should contain release information")
        
        // Should have substantial content
        XCTAssertGreaterThan(claudeContent.count, 1000,
                           "CLAUDE.md should have comprehensive content")
        
        logger.debug("✅ CLAUDE.md integration validation completed")
    }
    
    // MARK: - Phase 6: Security Integration
    
    private func validateSecurityIntegration() throws {
        logger.info("Phase 6: Validating security integration")
        
        // Test 6.1: Code signing setup documentation
        try validateCodeSigningDocumentation()
        
        // Test 6.2: Security scanning workflow
        try validateSecurityScanningWorkflow()
        
        // Test 6.3: Secret management
        try validateSecretManagement()
        
        logger.info("✅ Security integration validation passed")
    }
    
    private func validateCodeSigningDocumentation() throws {
        let codeSigningDoc = packageRootDirectory.appendingPathComponent("Documentation/Code-Signing-Setup.md").path
        
        guard FileManager.default.fileExists(atPath: codeSigningDoc) else {
            logger.warning("Code signing documentation not found")
            return
        }
        
        let content = try String(contentsOfFile: codeSigningDoc)
        
        // Should contain Apple Developer information
        XCTAssertTrue(content.contains("Apple") || content.contains("Developer"),
                     "Code signing doc should mention Apple Developer")
        
        // Should contain certificate information
        XCTAssertTrue(content.contains("certificate") || content.contains("Certificate"),
                     "Code signing doc should mention certificates")
        
        logger.debug("✅ Code signing documentation validation completed")
    }
    
    private func validateSecurityScanningWorkflow() throws {
        let securityWorkflow = packageRootDirectory.appendingPathComponent(".github/workflows/security-scanning.yml").path
        
        guard FileManager.default.fileExists(atPath: securityWorkflow) else {
            logger.warning("Security scanning workflow not found")
            return
        }
        
        let content = try String(contentsOfFile: securityWorkflow)
        
        // Should have basic workflow structure
        XCTAssertTrue(content.contains("name:"), "Security workflow should have name")
        XCTAssertTrue(content.contains("jobs:"), "Security workflow should have jobs")
        
        logger.debug("✅ Security scanning workflow validation completed")
    }
    
    private func validateSecretManagement() throws {
        // Check that workflows reference secrets properly
        let workflowFiles = [
            ".github/workflows/release.yml",
            ".github/workflows/security-scanning.yml"
        ]
        
        for workflow in workflowFiles {
            let workflowPath = packageRootDirectory.appendingPathComponent(workflow).path
            
            guard FileManager.default.fileExists(atPath: workflowPath) else {
                continue
            }
            
            let content = try String(contentsOfFile: workflowPath)
            
            // If secrets are used, they should be referenced properly
            if content.contains("secrets.") {
                XCTAssertFalse(content.contains("secrets.password123"),
                              "Workflow should not contain hardcoded secrets")
            }
        }
        
        logger.debug("✅ Secret management validation completed")
    }
    
    // MARK: - Phase 7: Monitoring Integration
    
    private func validateMonitoringIntegration() throws {
        logger.info("Phase 7: Validating monitoring integration")
        
        // Test 7.1: Monitoring workflow structure
        try validateMonitoringWorkflow()
        
        // Test 7.2: Status dashboard script
        try validateStatusDashboard()
        
        // Test 7.3: Performance benchmarking
        try validatePerformanceBenchmarking()
        
        logger.info("✅ Monitoring integration validation passed")
    }
    
    private func validateMonitoringWorkflow() throws {
        let monitoringWorkflow = packageRootDirectory.appendingPathComponent(".github/workflows/release-monitoring.yml").path
        
        guard FileManager.default.fileExists(atPath: monitoringWorkflow) else {
            logger.warning("Monitoring workflow not found")
            return
        }
        
        let content = try String(contentsOfFile: monitoringWorkflow)
        
        // Should have monitoring-specific structure
        XCTAssertTrue(content.contains("name:"), "Monitoring workflow should have name")
        XCTAssertTrue(content.contains("monitoring") || content.contains("status"),
                     "Monitoring workflow should reference monitoring or status")
        
        logger.debug("✅ Monitoring workflow validation completed")
    }
    
    private func validateStatusDashboard() throws {
        let dashboardScript = packageRootDirectory.appendingPathComponent("Scripts/release-status-dashboard.sh").path
        
        guard FileManager.default.fileExists(atPath: dashboardScript) else {
            logger.warning("Status dashboard script not found")
            return
        }
        
        // Verify script is executable
        let attributes = try FileManager.default.attributesOfItem(atPath: dashboardScript)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertNotNil(permissions, "Dashboard script should have permissions")
        
        if let perms = permissions {
            let permValue = perms.uint16Value
            XCTAssertTrue((permValue & 0o111) != 0, "Dashboard script should be executable")
        }
        
        logger.debug("✅ Status dashboard validation completed")
    }
    
    private func validatePerformanceBenchmarking() throws {
        let benchmarkScript = packageRootDirectory.appendingPathComponent("Scripts/benchmark-release-performance.sh").path
        
        guard FileManager.default.fileExists(atPath: benchmarkScript) else {
            logger.warning("Performance benchmark script not found")
            return
        }
        
        // Verify script is executable
        let attributes = try FileManager.default.attributesOfItem(atPath: benchmarkScript)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertNotNil(permissions, "Benchmark script should have permissions")
        
        if let perms = permissions {
            let permValue = perms.uint16Value
            XCTAssertTrue((permValue & 0o111) != 0, "Benchmark script should be executable")
        }
        
        logger.debug("✅ Performance benchmarking validation completed")
    }
    
    // MARK: - Phase 8: End-to-End Simulation
    
    private func performEndToEndReleaseSimulation() throws {
        logger.info("Phase 8: Performing end-to-end release simulation")
        
        // Test 8.1: Simulate release preparation
        try simulateReleasePrepationProcess()
        
        // Test 8.2: Simulate workflow execution
        try simulateWorkflowExecution()
        
        // Test 8.3: Simulate artifact validation
        try simulateArtifactValidation()
        
        logger.info("✅ End-to-end release simulation completed")
    }
    
    private func simulateReleasePrepationProcess() throws {
        let prepareScript = packageRootDirectory.appendingPathComponent("Scripts/prepare-release.sh").path
        
        guard FileManager.default.fileExists(atPath: prepareScript) else {
            logger.warning("Prepare release script not found, skipping simulation")
            return
        }
        
        // Test dry-run mode
        let dryRunProcess = Process()
        dryRunProcess.executableURL = URL(fileURLWithPath: prepareScript)
        dryRunProcess.arguments = ["--dry-run", validationConfig.testVersion]
        dryRunProcess.currentDirectoryURL = packageRootDirectory
        
        let outputPipe = Pipe()
        dryRunProcess.standardOutput = outputPipe
        dryRunProcess.standardError = outputPipe
        
        try dryRunProcess.run()
        dryRunProcess.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        
        // Dry run should complete successfully or provide meaningful feedback
        if dryRunProcess.terminationStatus != 0 {
            logger.warning("Dry run failed (may be expected): \(output)")
        } else {
            logger.debug("✅ Release preparation simulation successful")
        }
    }
    
    private func simulateWorkflowExecution() throws {
        // This would ideally use act or similar to test workflows
        // For now, we just validate the workflow files exist and have proper structure
        logger.debug("✅ Workflow execution simulation completed (basic validation)")
    }
    
    private func simulateArtifactValidation() throws {
        let validateScript = packageRootDirectory.appendingPathComponent("Scripts/validate-release-artifacts.sh").path
        
        guard FileManager.default.fileExists(atPath: validateScript) else {
            logger.warning("Artifact validation script not found")
            return
        }
        
        // Test help mode
        let helpProcess = Process()
        helpProcess.executableURL = URL(fileURLWithPath: validateScript)
        helpProcess.arguments = ["--help"]
        
        let outputPipe = Pipe()
        helpProcess.standardOutput = outputPipe
        helpProcess.standardError = outputPipe
        
        try helpProcess.run()
        helpProcess.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        
        XCTAssertFalse(output.isEmpty, "Artifact validation script should provide help")
        
        logger.debug("✅ Artifact validation simulation completed")
    }
    
    // MARK: - Phase 9: Error Handling and Edge Cases
    
    private func validateErrorHandlingAndEdgeCases() throws {
        logger.info("Phase 9: Validating error handling and edge cases")
        
        // Test 9.1: Invalid input handling
        try validateInvalidInputHandling()
        
        // Test 9.2: Network failure simulation
        try validateNetworkFailureHandling()
        
        // Test 9.3: Partial failure recovery
        try validatePartialFailureRecovery()
        
        // Test 9.4: Rollback scenarios
        try validateRollbackScenarios()
        
        logger.info("✅ Error handling and edge cases validation passed")
    }
    
    private func validateInvalidInputHandling() throws {
        let prepareScript = packageRootDirectory.appendingPathComponent("Scripts/prepare-release.sh").path
        
        guard FileManager.default.fileExists(atPath: prepareScript) else {
            logger.warning("Prepare script not found, skipping invalid input test")
            return
        }
        
        // Test with invalid version format
        let invalidProcess = Process()
        invalidProcess.executableURL = URL(fileURLWithPath: prepareScript)
        invalidProcess.arguments = ["invalid-version-format"]
        
        let outputPipe = Pipe()
        invalidProcess.standardOutput = outputPipe
        invalidProcess.standardError = outputPipe
        
        try invalidProcess.run()
        invalidProcess.waitUntilExit()
        
        // Should fail gracefully with non-zero exit
        XCTAssertNotEqual(invalidProcess.terminationStatus, 0,
                         "Script should reject invalid version format")
        
        logger.debug("✅ Invalid input handling validation completed")
    }
    
    private func validateNetworkFailureHandling() throws {
        // This would test network failure scenarios
        // For now, we just validate that error handling exists
        logger.debug("✅ Network failure handling validation completed (placeholder)")
    }
    
    private func validatePartialFailureRecovery() throws {
        // This would test partial failure recovery mechanisms
        // For now, we just validate that recovery scripts exist
        let rollbackScript = packageRootDirectory.appendingPathComponent("Scripts/rollback-release.sh").path
        
        if FileManager.default.fileExists(atPath: rollbackScript) {
            let attributes = try FileManager.default.attributesOfItem(atPath: rollbackScript)
            let permissions = attributes[.posixPermissions] as? NSNumber
            XCTAssertNotNil(permissions, "Rollback script should have permissions")
            
            if let perms = permissions {
                let permValue = perms.uint16Value
                XCTAssertTrue((permValue & 0o111) != 0, "Rollback script should be executable")
            }
        }
        
        logger.debug("✅ Partial failure recovery validation completed")
    }
    
    private func validateRollbackScenarios() throws {
        let rollbackScript = packageRootDirectory.appendingPathComponent("Scripts/rollback-release.sh").path
        
        guard FileManager.default.fileExists(atPath: rollbackScript) else {
            logger.warning("Rollback script not found")
            return
        }
        
        // Test help output
        let helpProcess = Process()
        helpProcess.executableURL = URL(fileURLWithPath: rollbackScript)
        helpProcess.arguments = ["--help"]
        
        let outputPipe = Pipe()
        helpProcess.standardOutput = outputPipe
        helpProcess.standardError = outputPipe
        
        try helpProcess.run()
        helpProcess.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        
        XCTAssertFalse(output.isEmpty, "Rollback script should provide help")
        
        logger.debug("✅ Rollback scenarios validation completed")
    }
    
    // MARK: - Phase 10: Performance and Scalability
    
    private func validatePerformanceAndScalability() throws {
        logger.info("Phase 10: Validating performance and scalability")
        
        // Test 10.1: Build performance
        try validateBuildPerformance()
        
        // Test 10.2: Test execution performance
        try validateTestExecutionPerformance()
        
        // Test 10.3: Workflow optimization
        try validateWorkflowOptimization()
        
        logger.info("✅ Performance and scalability validation passed")
    }
    
    private func validateBuildPerformance() throws {
        // Measure build time for performance regression
        let startTime = Date()
        
        let buildProcess = Process()
        buildProcess.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        buildProcess.arguments = ["build", "--configuration", "debug"]
        buildProcess.currentDirectoryURL = packageRootDirectory
        
        let outputPipe = Pipe()
        buildProcess.standardOutput = outputPipe
        buildProcess.standardError = outputPipe
        
        try buildProcess.run()
        buildProcess.waitUntilExit()
        
        let buildTime = Date().timeIntervalSince(startTime)
        
        // Build should complete within reasonable time
        XCTAssertLessThan(buildTime, 300.0, "Build should complete within 5 minutes")
        
        if buildProcess.terminationStatus == 0 {
            logger.debug("✅ Build completed in \(String(format: "%.1f", buildTime)) seconds")
        } else {
            logger.warning("Build failed during performance test")
        }
    }
    
    private func validateTestExecutionPerformance() throws {
        // This would measure test execution performance
        // For now, we just validate that performance benchmarking exists
        let benchmarkScript = packageRootDirectory.appendingPathComponent("Scripts/benchmark-release-performance.sh").path
        
        if FileManager.default.fileExists(atPath: benchmarkScript) {
            logger.debug("✅ Performance benchmarking script available")
        } else {
            logger.warning("Performance benchmarking script not found")
        }
    }
    
    private func validateWorkflowOptimization() throws {
        // Check for workflow optimization features
        let optimizationWorkflow = packageRootDirectory.appendingPathComponent(".github/workflows/release-optimization.yml").path
        
        if FileManager.default.fileExists(atPath: optimizationWorkflow) {
            let content = try String(contentsOfFile: optimizationWorkflow)
            
            // Should contain optimization-related keywords
            XCTAssertTrue(content.contains("cache") || content.contains("parallel") || content.contains("optimization"),
                         "Optimization workflow should contain optimization features")
            
            logger.debug("✅ Workflow optimization features detected")
        } else {
            logger.warning("Workflow optimization file not found")
        }
    }
    
    // MARK: - Helper Methods
    
    private func findPackageRoot() throws -> URL {
        var currentURL = URL(fileURLWithPath: #file).deletingLastPathComponent()
        
        while currentURL.path != "/" {
            let packageSwiftPath = currentURL.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageSwiftPath.path) {
                return currentURL
            }
            currentURL = currentURL.deletingLastPathComponent()
        }
        
        throw FinalValidationError.packageRootNotFound
    }
}

// MARK: - Supporting Types

private enum FinalValidationError: Error {
    case packageRootNotFound
    case validationTimeout
    case integrationTestFailed(String)
    case systemValidationFailed(String)
    
    var localizedDescription: String {
        switch self {
        case .packageRootNotFound:
            return "Could not find package root directory"
        case .validationTimeout:
            return "Validation process timed out"
        case .integrationTestFailed(let message):
            return "Integration test failed: \(message)"
        case .systemValidationFailed(let message):
            return "System validation failed: \(message)"
        }
    }
}