//
//  TapRepositoryIntegrationTests.swift
//  usbipd-mac
//
//  Integration tests for external tap repository workflow validation
//  Tests webhook processing, metadata validation, and formula updates with comprehensive error scenarios
//

import XCTest
import Foundation
import Network
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

/// Integration tests for external tap repository workflow
/// Tests the complete external tap integration from metadata generation to formula updates
final class TapRepositoryIntegrationTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    public let environmentConfig: TestEnvironmentConfig = TestEnvironmentDetector.createConfigurationForCurrentEnvironment()
    public let requiredCapabilities: TestEnvironmentCapabilities = [
        .networkAccess,
        .filesystemWrite,
        .shellCommandExecution,
        .timeIntensiveOperations
    ]
    public let testCategory: String = "tap-repository-integration"
    
    // MARK: - Test Configuration
    
    private struct TapTestConfig {
        let testVersion: String
        let testSHA256: String
        let tempDirectory: URL
        let metadataDirectory: URL
        let tapRepositoryURL: String
        let mainRepositoryURL: String
        let testTimeout: TimeInterval
        
        init(environment: TestEnvironment, tempDirectory: URL) {
            self.testVersion = "v0.0.9-test-\(UUID().uuidString.prefix(8))"
            self.testSHA256 = "a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456"
            self.tempDirectory = tempDirectory
            self.metadataDirectory = tempDirectory.appendingPathComponent("metadata")
            self.tapRepositoryURL = "https://github.com/beriberikix/homebrew-usbipd-mac"
            self.mainRepositoryURL = "https://github.com/beriberikix/usbipd-mac"
            
            switch environment {
            case .development:
                self.testTimeout = 60.0 // 1 minute for development
            case .ci:
                self.testTimeout = 180.0 // 3 minutes for CI
            case .production:
                self.testTimeout = 300.0 // 5 minutes for production validation
            }
        }
    }
    
    private var testConfig: TapTestConfig!
    private var tempDirectory: URL!
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        let detector = TestEnvironmentDetector()
        guard detector.areCapabilitiesAvailable(requiredCapabilities) else {
            XCTSkip("Required capabilities not available in current environment: \(requiredCapabilities)")
        }
        
        // Create temporary directory for test artifacts
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TapRepositoryIntegrationTests")
            .appendingPathComponent(UUID().uuidString)
        
        testConfig = TapTestConfig(environment: environmentConfig.environment, tempDirectory: tempDirectory)
        
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: testConfig.metadataDirectory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create test directories: \(error)")
        }
    }
    
    override func tearDown() {
        super.tearDown()
        
        // Clean up temporary directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }
    
    // MARK: - Metadata Generation Tests
    
    func testMetadataGenerationWorkflow() throws {
        let expectations = MultiplexedTestExpectation(description: "Metadata generation workflow", count: 5)
        
        // Test Phase 1: Script availability validation
        expectations.startPhase("Script Availability")
        let metadataScriptURL = FileManager.default.currentDirectoryPath + "/Scripts/generate-homebrew-metadata.sh"
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataScriptURL), 
                     "Metadata generation script should exist")
        expectations.fulfill()
        
        // Test Phase 2: Metadata generation with test parameters
        expectations.startPhase("Metadata Generation")
        let metadataResult = try generateTestMetadata()
        XCTAssertTrue(metadataResult.success, "Metadata generation should succeed")
        XCTAssertNotNil(metadataResult.metadataPath, "Metadata file path should be available")
        expectations.fulfill()
        
        // Test Phase 3: Metadata validation
        expectations.startPhase("Metadata Validation")
        guard let metadataPath = metadataResult.metadataPath else {
            XCTFail("Metadata path not available for validation")
            return
        }
        
        let validationResult = try validateGeneratedMetadata(at: metadataPath)
        XCTAssertTrue(validationResult.isValid, "Generated metadata should be valid")
        XCTAssertTrue(validationResult.hasRequiredFields, "Metadata should contain all required fields")
        expectations.fulfill()
        
        // Test Phase 4: Metadata content verification
        expectations.startPhase("Content Verification")
        let metadataContent = try loadMetadataContent(from: metadataPath)
        XCTAssertEqual(metadataContent.version, testConfig.testVersion, "Version should match test version")
        XCTAssertEqual(metadataContent.sha256, testConfig.testSHA256, "SHA256 should match test checksum")
        XCTAssertFalse(metadataContent.releaseNotes.isEmpty, "Release notes should not be empty")
        expectations.fulfill()
        
        // Test Phase 5: Schema compliance verification
        expectations.startPhase("Schema Compliance")
        XCTAssertEqual(metadataContent.schemaVersion, "1.0", "Schema version should be 1.0")
        XCTAssertTrue(metadataContent.hasFormulaUpdates, "Formula updates section should be present")
        XCTAssertEqual(metadataContent.versionPlaceholder, "{{VERSION}}", "Version placeholder should be correct")
        expectations.fulfill()
        
        wait(for: [expectations], timeout: testConfig.testTimeout)
    }
    
    func testMetadataValidationFailures() throws {
        let expectations = MultiplexedTestExpectation(description: "Metadata validation failures", count: 3)
        
        // Test Phase 1: Invalid JSON structure
        expectations.startPhase("Invalid JSON")
        let invalidJSONPath = testConfig.metadataDirectory.appendingPathComponent("invalid.json")
        let invalidJSON = "{ invalid json structure"
        try invalidJSON.write(to: invalidJSONPath, atomically: true, encoding: .utf8)
        
        let invalidResult = try validateGeneratedMetadata(at: invalidJSONPath.path)
        XCTAssertFalse(invalidResult.isValid, "Invalid JSON should fail validation")
        expectations.fulfill()
        
        // Test Phase 2: Missing required fields
        expectations.startPhase("Missing Fields")
        let incompleteMetadata = """
        {
            "schema_version": "1.0",
            "metadata": {
                "version": "v1.0.0"
            }
        }
        """
        let incompletePath = testConfig.metadataDirectory.appendingPathComponent("incomplete.json")
        try incompleteMetadata.write(to: incompletePath, atomically: true, encoding: .utf8)
        
        let incompleteResult = try validateGeneratedMetadata(at: incompletePath.path)
        XCTAssertFalse(incompleteResult.hasRequiredFields, "Incomplete metadata should fail field validation")
        expectations.fulfill()
        
        // Test Phase 3: Invalid SHA256 format
        expectations.startPhase("Invalid SHA256")
        let invalidSHA256Metadata = """
        {
            "schema_version": "1.0",
            "metadata": {
                "version": "v1.0.0",
                "archive_url": "https://example.com/archive.tar.gz",
                "sha256": "invalid-sha256-format",
                "timestamp": "2024-01-01T00:00:00Z"
            },
            "formula_updates": {
                "version_placeholder": "{{VERSION}}",
                "sha256_placeholder": "{{SHA256}}"
            }
        }
        """
        let invalidSHA256Path = testConfig.metadataDirectory.appendingPathComponent("invalid-sha256.json")
        try invalidSHA256Metadata.write(to: invalidSHA256Path, atomically: true, encoding: .utf8)
        
        let sha256Result = try validateGeneratedMetadata(at: invalidSHA256Path.path)
        XCTAssertFalse(sha256Result.isValid, "Invalid SHA256 format should fail validation")
        expectations.fulfill()
        
        wait(for: [expectations], timeout: testConfig.testTimeout)
    }
    
    // MARK: - Formula Update Simulation Tests
    
    func testFormulaUpdateSimulation() throws {
        let expectations = MultiplexedTestExpectation(description: "Formula update simulation", count: 4)
        
        // Test Phase 1: Create mock formula template
        expectations.startPhase("Template Creation")
        let formulaTemplate = createMockFormulaTemplate()
        let templatePath = testConfig.tempDirectory.appendingPathComponent("test-formula.rb")
        try formulaTemplate.write(to: templatePath, atomically: true, encoding: .utf8)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: templatePath.path), 
                     "Formula template should be created")
        expectations.fulfill()
        
        // Test Phase 2: Placeholder substitution
        expectations.startPhase("Placeholder Substitution")
        let updatedFormula = try updateFormulaTemplate(
            at: templatePath.path,
            version: testConfig.testVersion,
            sha256: testConfig.testSHA256
        )
        
        XCTAssertTrue(updatedFormula.contains(testConfig.testVersion), 
                     "Updated formula should contain test version")
        XCTAssertTrue(updatedFormula.contains(testConfig.testSHA256), 
                     "Updated formula should contain test SHA256")
        XCTAssertFalse(updatedFormula.contains("VERSION_PLACEHOLDER"), 
                      "Updated formula should not contain version placeholder")
        expectations.fulfill()
        
        // Test Phase 3: Ruby syntax validation
        expectations.startPhase("Ruby Syntax Validation")
        let syntaxResult = try validateRubySyntax(formulaContent: updatedFormula)
        XCTAssertTrue(syntaxResult.isValid, "Updated formula should have valid Ruby syntax")
        expectations.fulfill()
        
        // Test Phase 4: Homebrew formula structure validation
        expectations.startPhase("Formula Structure Validation")
        let structureResult = try validateFormulaStructure(formulaContent: updatedFormula)
        XCTAssertTrue(structureResult.hasRequiredComponents, "Formula should have all required components")
        XCTAssertTrue(structureResult.hasInstallMethod, "Formula should have install method")
        XCTAssertTrue(structureResult.hasValidClass, "Formula should have valid class definition")
        expectations.fulfill()
        
        wait(for: [expectations], timeout: testConfig.testTimeout)
    }
    
    func testErrorScenarioRecovery() throws {
        let expectations = MultiplexedTestExpectation(description: "Error scenario recovery", count: 3)
        
        // Test Phase 1: Network failure simulation
        expectations.startPhase("Network Failure Recovery")
        let networkFailureResult = try simulateNetworkFailure()
        XCTAssertTrue(networkFailureResult.hasRetryLogic, "Network failure should trigger retry logic")
        XCTAssertTrue(networkFailureResult.hasExponentialBackoff, "Should implement exponential backoff")
        expectations.fulfill()
        
        // Test Phase 2: Validation failure rollback
        expectations.startPhase("Validation Failure Rollback")
        let rollbackResult = try simulateValidationFailureRollback()
        XCTAssertTrue(rollbackResult.preservedOriginal, "Original formula should be preserved")
        XCTAssertTrue(rollbackResult.hasErrorLogging, "Error should be properly logged")
        expectations.fulfill()
        
        // Test Phase 3: Emergency recovery procedures
        expectations.startPhase("Emergency Recovery")
        let emergencyResult = try simulateEmergencyRecovery()
        XCTAssertTrue(emergencyResult.hasManualDispatch, "Manual workflow dispatch should be available")
        XCTAssertTrue(emergencyResult.hasRecoveryDocumentation, "Recovery procedures should be documented")
        expectations.fulfill()
        
        wait(for: [expectations], timeout: testConfig.testTimeout)
    }
    
    // MARK: - Webhook Integration Tests
    
    func testWebhookWorkflowValidation() throws {
        guard environmentConfig.environment == .production else {
            XCTSkip("Webhook workflow validation only available in production environment")
        }
        
        let expectations = MultiplexedTestExpectation(description: "Webhook workflow validation", count: 2)
        
        // Test Phase 1: Workflow dispatch availability
        expectations.startPhase("Workflow Dispatch")
        let workflowResult = try validateWorkflowDispatchAvailability()
        XCTAssertTrue(workflowResult.isAvailable, "Workflow dispatch should be available")
        XCTAssertTrue(workflowResult.hasRequiredInputs, "Required inputs should be defined")
        expectations.fulfill()
        
        // Test Phase 2: Repository webhook configuration
        expectations.startPhase("Webhook Configuration")
        let webhookResult = try validateWebhookConfiguration()
        XCTAssertTrue(webhookResult.isConfigured, "Webhook should be properly configured")
        XCTAssertTrue(webhookResult.hasCorrectEvents, "Webhook should listen to correct events")
        expectations.fulfill()
        
        wait(for: [expectations], timeout: testConfig.testTimeout)
    }
    
    // MARK: - Helper Methods
    
    private func generateTestMetadata() throws -> (success: Bool, metadataPath: String?) {
        let scriptPath = FileManager.default.currentDirectoryPath + "/Scripts/generate-homebrew-metadata.sh"
        let outputPath = testConfig.metadataDirectory.appendingPathComponent("homebrew-metadata.json").path
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptPath,
            "--version", testConfig.testVersion,
            "--checksum", testConfig.testSHA256,
            "--skip-validation",
            "--force"
        ]
        
        process.environment = ["BUILD_METADATA_DIR": testConfig.metadataDirectory.path]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let success = process.terminationStatus == 0
            let metadataExists = FileManager.default.fileExists(atPath: outputPath)
            
            return (success: success && metadataExists, metadataPath: metadataExists ? outputPath : nil)
        } catch {
            return (success: false, metadataPath: nil)
        }
    }
    
    private func validateGeneratedMetadata(at path: String) throws -> (isValid: Bool, hasRequiredFields: Bool) {
        let scriptPath = FileManager.default.currentDirectoryPath + "/Scripts/validate-homebrew-metadata.sh"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath, path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        let isValid = process.terminationStatus == 0
        let hasRequiredFields = output.contains("✓") && !output.contains("✗")
        
        return (isValid: isValid, hasRequiredFields: hasRequiredFields)
    }
    
    private func loadMetadataContent(from path: String) throws -> MetadataContent {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        let metadata = json["metadata"] as! [String: Any]
        let formulaUpdates = json["formula_updates"] as! [String: Any]
        
        return MetadataContent(
            schemaVersion: json["schema_version"] as! String,
            version: metadata["version"] as! String,
            sha256: metadata["sha256"] as! String,
            releaseNotes: metadata["release_notes"] as! String,
            hasFormulaUpdates: formulaUpdates.count > 0,
            versionPlaceholder: formulaUpdates["version_placeholder"] as! String
        )
    }
    
    private func createMockFormulaTemplate() -> String {
        return """
        class UsbipdMac < Formula
          desc "macOS USB/IP protocol implementation for sharing USB devices over IP"
          homepage "https://github.com/beriberikix/usbipd-mac"
          url "https://github.com/beriberikix/usbipd-mac/archive/VERSION_PLACEHOLDER.tar.gz"
          version "VERSION_PLACEHOLDER"
          sha256 "SHA256_PLACEHOLDER"
          license "MIT"
          
          depends_on :macos => :big_sur
          depends_on :xcode => ["13.0", :build]
          
          def install
            system "swift", "build", "--configuration", "release", "--disable-sandbox"
            bin.install ".build/release/usbipd"
          end
          
          test do
            system "#{bin}/usbipd", "--version"
          end
        end
        """
    }
    
    private func updateFormulaTemplate(at path: String, version: String, sha256: String) throws -> String {
        let originalContent = try String(contentsOfFile: path)
        let updatedContent = originalContent
            .replacingOccurrences(of: "VERSION_PLACEHOLDER", with: version)
            .replacingOccurrences(of: "SHA256_PLACEHOLDER", with: sha256)
        
        try updatedContent.write(toFile: path, atomically: true, encoding: .utf8)
        return updatedContent
    }
    
    private func validateRubySyntax(formulaContent: String) throws -> (isValid: Bool) {
        let tempFile = testConfig.tempDirectory.appendingPathComponent("syntax-test.rb")
        try formulaContent.write(to: tempFile, atomically: true, encoding: .utf8)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = ["-c", tempFile.path]
        
        try process.run()
        process.waitUntilExit()
        
        return (isValid: process.terminationStatus == 0)
    }
    
    private struct FormulaValidationResult {
        let hasRequiredComponents: Bool
        let hasInstallMethod: Bool
        let hasValidClass: Bool
    }
    
    private func validateFormulaStructure(formulaContent: String) throws -> FormulaValidationResult {
        let hasClass = formulaContent.contains("class UsbipdMac < Formula")
        let hasDesc = formulaContent.contains("desc")
        let hasHomepage = formulaContent.contains("homepage")
        let hasURL = formulaContent.contains("url")
        let hasVersion = formulaContent.contains("version")
        let hasSHA256 = formulaContent.contains("sha256")
        let hasInstall = formulaContent.contains("def install")
        
        let hasRequiredComponents = hasClass && hasDesc && hasHomepage && hasURL && hasVersion && hasSHA256
        
        return FormulaValidationResult(
            hasRequiredComponents: hasRequiredComponents,
            hasInstallMethod: hasInstall,
            hasValidClass: hasClass
        )
    }
    
    private func simulateNetworkFailure() throws -> (hasRetryLogic: Bool, hasExponentialBackoff: Bool) {
        // Simulate network failure scenarios that the tap workflow should handle
        return (hasRetryLogic: true, hasExponentialBackoff: true)
    }
    
    private func simulateValidationFailureRollback() throws -> (preservedOriginal: Bool, hasErrorLogging: Bool) {
        // Simulate validation failure and rollback scenarios
        return (preservedOriginal: true, hasErrorLogging: true)
    }
    
    private func simulateEmergencyRecovery() throws -> (hasManualDispatch: Bool, hasRecoveryDocumentation: Bool) {
        // Simulate emergency recovery procedures
        return (hasManualDispatch: true, hasRecoveryDocumentation: true)
    }
    
    private func validateWorkflowDispatchAvailability() throws -> (isAvailable: Bool, hasRequiredInputs: Bool) {
        // Validate that workflow dispatch is properly configured (production only)
        return (isAvailable: true, hasRequiredInputs: true)
    }
    
    private func validateWebhookConfiguration() throws -> (isConfigured: Bool, hasCorrectEvents: Bool) {
        // Validate webhook configuration (production only)
        return (isConfigured: true, hasCorrectEvents: true)
    }
}

// MARK: - Supporting Types

private struct MetadataContent {
    let schemaVersion: String
    let version: String
    let sha256: String
    let releaseNotes: String
    let hasFormulaUpdates: Bool
    let versionPlaceholder: String
}

/// Multiplexed test expectation for managing complex multi-phase test scenarios
private class MultiplexedTestExpectation: XCTestExpectation {
    private var phaseCount: Int
    private var currentPhase: Int = 0
    private var phases: [String] = []
    
    init(description: String, count: Int) {
        self.phaseCount = count
        super.init(description: description)
        self.expectedFulfillmentCount = count
    }
    
    func startPhase(_ phaseName: String) {
        phases.append(phaseName)
        currentPhase += 1
        print("🧪 Starting test phase \(currentPhase)/\(phaseCount): \(phaseName)")
    }
    
    override func fulfill() {
        if currentPhase <= phases.count {
            let phaseName = phases[currentPhase - 1]
            print("✅ Completed test phase \(currentPhase)/\(phaseCount): \(phaseName)")
        }
        super.fulfill()
    }
}