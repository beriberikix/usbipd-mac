// ReleaseWorkflowTests.swift
// GitHub Actions release workflow validation tests using act framework
// Tests all trigger conditions, error scenarios, and artifact generation

import Foundation
import XCTest
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

class ReleaseWorkflowTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    var environmentConfig: TestEnvironmentConfig {
        return TestEnvironmentDetector.createConfigurationForCurrentEnvironment()
    }
    
    var requiredCapabilities: TestEnvironmentCapabilities {
        return [.networkAccess, .filesystemWrite, .timeIntensiveOperations]
    }
    
    var testCategory: String {
        return "workflow"
    }
    
    // MARK: - Test Properties
    
    private let workflowsPath = ".github/workflows"
    private let testTimeout: TimeInterval = 300.0 // 5 minutes per workflow test
    private var tempTestDirectory: URL!
    
    // MARK: - Setup and Teardown
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Validate environment before running tests
        try validateEnvironment()
        
        // Create temporary test directory
        tempTestDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("release-workflow-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempTestDirectory, withIntermediateDirectories: true)
        
        setUpTestSuite()
    }
    
    override func tearDownWithError() throws {
        tearDownTestSuite()
        
        // Clean up temporary test directory
        if let tempDir = tempTestDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        try super.tearDownWithError()
    }
    
    func setUpTestSuite() {
        // Verify act is available (if needed for actual workflow execution)
        validateActAvailability()
    }
    
    func tearDownTestSuite() {
        // Clean up any workflow test artifacts
        cleanupWorkflowTestArtifacts()
    }
    
    // MARK: - Release Workflow Structure Tests
    
    func testReleaseWorkflowExists() throws {
        let releaseWorkflowPath = "\(workflowsPath)/release.yml"
        let fileExists = FileManager.default.fileExists(atPath: releaseWorkflowPath)
        XCTAssertTrue(fileExists, "Release workflow file should exist at \(releaseWorkflowPath)")
    }
    
    func testPreReleaseWorkflowExists() throws {
        let preReleaseWorkflowPath = "\(workflowsPath)/pre-release.yml"
        let fileExists = FileManager.default.fileExists(atPath: preReleaseWorkflowPath)
        XCTAssertTrue(fileExists, "Pre-release workflow file should exist at \(preReleaseWorkflowPath)")
    }
    
    // MARK: - Release Workflow Configuration Tests
    
    func testReleaseWorkflowConfiguration() throws {
        let workflowContent = try loadWorkflowContent(filename: "release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate workflow name
        XCTAssertEqual(workflow.name, "Production Release", "Release workflow should have correct name")
        
        // Validate triggers
        XCTAssertTrue(workflow.hasTagTrigger(), "Release workflow should trigger on tags")
        XCTAssertTrue(workflow.hasWorkflowDispatch(), "Release workflow should support manual dispatch")
        
        // Validate required jobs
        let expectedJobs = ["validate-release", "lint-and-build", "test-validation", 
                           "build-artifacts", "create-release", "post-release"]
        for job in expectedJobs {
            XCTAssertTrue(workflow.hasJob(named: job), "Release workflow should contain \(job) job")
        }
        
        // Validate secrets usage
        XCTAssertTrue(workflow.usesSecret("GITHUB_TOKEN"), "Release workflow should use GITHUB_TOKEN")
        XCTAssertTrue(workflow.usesSecret("DEVELOPER_ID_CERTIFICATE"), "Release workflow should use signing certificates")
    }
    
    func testPreReleaseWorkflowConfiguration() throws {
        let workflowContent = try loadWorkflowContent(filename: "pre-release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate workflow name
        XCTAssertEqual(workflow.name, "Pre-Release Validation", "Pre-release workflow should have correct name")
        
        // Validate triggers
        XCTAssertTrue(workflow.hasPRTrigger(), "Pre-release workflow should trigger on pull requests")
        XCTAssertTrue(workflow.hasWorkflowDispatch(), "Pre-release workflow should support manual dispatch")
        
        // Validate validation levels
        let expectedJobs = ["determine-validation", "quick-validation", 
                           "comprehensive-validation", "release-candidate-validation"]
        for job in expectedJobs {
            XCTAssertTrue(workflow.hasJob(named: job), "Pre-release workflow should contain \(job) job")
        }
    }
    
    // MARK: - Workflow Job Dependency Tests
    
    func testReleaseWorkflowJobDependencies() throws {
        let workflowContent = try loadWorkflowContent(filename: "release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate job dependency chain
        XCTAssertTrue(workflow.jobDependsOn("lint-and-build", needs: ["validate-release"]),
                     "lint-and-build should depend on validate-release")
        XCTAssertTrue(workflow.jobDependsOn("test-validation", needs: ["validate-release", "lint-and-build"]),
                     "test-validation should depend on validate-release and lint-and-build")
        XCTAssertTrue(workflow.jobDependsOn("build-artifacts", needs: ["validate-release", "lint-and-build", "test-validation"]),
                     "build-artifacts should have proper dependencies")
        XCTAssertTrue(workflow.jobDependsOn("create-release", needs: ["validate-release", "build-artifacts"]),
                     "create-release should depend on validate-release and build-artifacts")
    }
    
    // MARK: - Workflow Input Validation Tests
    
    func testReleaseWorkflowInputs() throws {
        let workflowContent = try loadWorkflowContent(filename: "release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate manual dispatch inputs
        let inputs = workflow.workflowDispatchInputs()
        XCTAssertTrue(inputs.contains("version"), "Release workflow should accept version input")
        XCTAssertTrue(inputs.contains("prerelease"), "Release workflow should accept prerelease input")
        XCTAssertTrue(inputs.contains("skip_tests"), "Release workflow should accept skip_tests input")
        
        // Validate input types and defaults
        XCTAssertEqual(workflow.inputType(for: "version"), "string", "Version input should be string type")
        XCTAssertEqual(workflow.inputType(for: "prerelease"), "boolean", "Prerelease input should be boolean type")
        XCTAssertEqual(workflow.inputDefault(for: "prerelease"), "false", "Prerelease should default to false")
    }
    
    func testPreReleaseWorkflowInputs() throws {
        let workflowContent = try loadWorkflowContent(filename: "pre-release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate validation level input
        let inputs = workflow.workflowDispatchInputs()
        XCTAssertTrue(inputs.contains("validation_level"), "Pre-release workflow should accept validation_level input")
        
        // Validate validation level options
        let validationOptions = workflow.inputOptions(for: "validation_level")
        XCTAssertTrue(validationOptions.contains("quick"), "Should support quick validation")
        XCTAssertTrue(validationOptions.contains("comprehensive"), "Should support comprehensive validation")
        XCTAssertTrue(validationOptions.contains("release-candidate"), "Should support release candidate validation")
    }
    
    // MARK: - Environment and Secrets Tests
    
    func testWorkflowEnvironmentVariables() throws {
        let workflowContent = try loadWorkflowContent(filename: "release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate required environment variables
        let expectedEnvVars = ["GITHUB_TOKEN", "DEVELOPER_ID_CERTIFICATE", 
                              "DEVELOPER_ID_CERTIFICATE_PASSWORD", "NOTARIZATION_USERNAME", 
                              "NOTARIZATION_PASSWORD"]
        
        for envVar in expectedEnvVars {
            XCTAssertTrue(workflow.hasEnvironmentVariable(envVar), 
                         "Release workflow should define \(envVar) environment variable")
        }
    }
    
    // MARK: - Workflow Step Validation Tests
    
    func testReleaseWorkflowSteps() throws {
        let workflowContent = try loadWorkflowContent(filename: "release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate critical steps exist in validate-release job
        let validateJob = workflow.job(named: "validate-release")
        XCTAssertTrue(validateJob.hasStep(containing: "Extract Version Information"),
                     "validate-release job should extract version information")
        
        // Validate critical steps exist in build-artifacts job
        let buildJob = workflow.job(named: "build-artifacts")
        XCTAssertTrue(buildJob.hasStep(containing: "Setup Code Signing"),
                     "build-artifacts job should setup code signing")
        XCTAssertTrue(buildJob.hasStep(containing: "Build Release Artifacts"),
                     "build-artifacts job should build release artifacts")
        XCTAssertTrue(buildJob.hasStep(containing: "Generate Checksums"),
                     "build-artifacts job should generate checksums")
    }
    
    // MARK: - Workflow Trigger Tests
    
    func testReleaseWorkflowTriggers() throws {
        let workflowContent = try loadWorkflowContent(filename: "release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate tag pattern
        let tagPattern = workflow.tagTriggerPattern()
        XCTAssertEqual(tagPattern, "v*", "Release workflow should trigger on v* tags")
        
        // Validate workflow dispatch is properly configured
        XCTAssertTrue(workflow.hasWorkflowDispatch(), "Release workflow should support manual dispatch")
    }
    
    func testPreReleaseWorkflowTriggers() throws {
        let workflowContent = try loadWorkflowContent(filename: "pre-release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate PR trigger configuration
        XCTAssertTrue(workflow.hasPRTrigger(on: "main"), "Pre-release workflow should trigger on PRs to main")
        
        // Validate PR trigger types
        let prTypes = workflow.prTriggerTypes()
        let expectedTypes = ["opened", "synchronize", "reopened"]
        for type in expectedTypes {
            XCTAssertTrue(prTypes.contains(type), "Pre-release workflow should trigger on \(type) PR events")
        }
    }
    
    // MARK: - Caching Strategy Tests
    
    func testWorkflowCaching() throws {
        let workflowContent = try loadWorkflowContent(filename: "release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate Swift package caching
        XCTAssertTrue(workflow.usesCaching(for: "Swift packages"),
                     "Release workflow should cache Swift packages")
        XCTAssertTrue(workflow.usesCaching(for: "SwiftLint"),
                     "Release workflow should cache SwiftLint")
        
        // Validate cache keys contain appropriate file dependencies
        let swiftCacheKey = workflow.cacheKey(for: "Swift packages")
        XCTAssertTrue(swiftCacheKey.contains("Package.swift"),
                     "Swift cache key should depend on Package.swift")
        XCTAssertTrue(swiftCacheKey.contains("Package.resolved"),
                     "Swift cache key should depend on Package.resolved")
    }
    
    // MARK: - Error Handling and Recovery Tests
    
    func testWorkflowErrorHandling() throws {
        let workflowContent = try loadWorkflowContent(filename: "release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate conditional job execution
        let buildArtifactsJob = workflow.job(named: "build-artifacts")
        XCTAssertTrue(buildArtifactsJob.hasConditionalExecution(),
                     "build-artifacts job should execute conditionally based on previous job success")
        
        // Validate skip_tests handling
        let testValidationJob = workflow.job(named: "test-validation")
        XCTAssertTrue(testValidationJob.canBeSkipped(when: "skip_tests"),
                     "test-validation job should be skippable when skip_tests is true")
    }
    
    // MARK: - Security and Permissions Tests
    
    func testWorkflowSecurityConfiguration() throws {
        let workflowContent = try loadWorkflowContent(filename: "release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate that sensitive operations are properly protected
        let codeSigningSteps = workflow.stepsContaining("code sign")
        for step in codeSigningSteps {
            XCTAssertTrue(step.hasConditionalExecution(),
                         "Code signing steps should execute conditionally when certificates are available")
        }
        
        // Validate secret usage patterns
        let secretUsages = workflow.secretUsages()
        for usage in secretUsages {
            XCTAssertFalse(usage.isPlaintext, "Secrets should not be used in plaintext")
            XCTAssertTrue(usage.isFromSecretsContext, "Secrets should be accessed from secrets context")
        }
    }
    
    // MARK: - Performance and Timeout Tests
    
    func testWorkflowPerformanceConfiguration() throws {
        let workflowContent = try loadWorkflowContent(filename: "pre-release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate that long-running operations have appropriate timeouts
        let productionTestSteps = workflow.stepsContaining("run-production-tests")
        for step in productionTestSteps {
            XCTAssertTrue(step.hasTimeout() || step.hasTimeoutArgument(),
                         "Production test steps should have timeout configuration")
        }
        
        // Validate parallel execution where appropriate
        let quickValidationJob = workflow.job(named: "quick-validation")
        XCTAssertTrue(quickValidationJob.isOptimizedForSpeed(),
                     "Quick validation job should be optimized for speed")
    }
    
    // MARK: - Output and Artifact Tests
    
    func testWorkflowOutputs() throws {
        let workflowContent = try loadWorkflowContent(filename: "release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate job outputs
        let validateReleaseJob = workflow.job(named: "validate-release")
        let expectedOutputs = ["version", "is-prerelease"]
        for output in expectedOutputs {
            XCTAssertTrue(validateReleaseJob.hasOutput(output),
                         "validate-release job should output \(output)")
        }
        
        let buildArtifactsJob = workflow.job(named: "build-artifacts")
        let expectedArtifactOutputs = ["artifact-paths", "checksums"]
        for output in expectedArtifactOutputs {
            XCTAssertTrue(buildArtifactsJob.hasOutput(output),
                         "build-artifacts job should output \(output)")
        }
    }
    
    func testArtifactUploadConfiguration() throws {
        let workflowContent = try loadWorkflowContent(filename: "release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Validate artifact upload steps
        let uploadSteps = workflow.stepsUsing(action: "actions/upload-artifact")
        XCTAssertFalse(uploadSteps.isEmpty, "Release workflow should upload artifacts")
        
        for step in uploadSteps {
            XCTAssertTrue(step.hasRetentionDays(), "Artifact upload should specify retention period")
            XCTAssertTrue(step.hasArtifactName(), "Artifact upload should specify artifact name")
        }
    }
    
    // MARK: - Integration Test Scenarios
    
    func testReleaseWorkflowIntegration() throws {
        // This test validates the complete release workflow integration
        // by simulating various scenarios without actually executing the workflow
        
        let scenarios: [ReleaseScenario] = [
            .tagTriggeredRelease(version: "v1.2.3"),
            .manualRelease(version: "v1.2.4", prerelease: false),
            .prereleaseManual(version: "v1.3.0-alpha.1", prerelease: true),
            .emergencyRelease(version: "v1.2.5", skipTests: true)
        ]
        
        for scenario in scenarios {
            try validateReleaseScenario(scenario)
        }
    }
    
    func testPreReleaseWorkflowIntegration() throws {
        // Test various pre-release validation scenarios
        
        let scenarios: [PreReleaseScenario] = [
            .pullRequestValidation(targetBranch: "main"),
            .manualQuickValidation,
            .manualComprehensiveValidation,
            .releaseCandidateValidation
        ]
        
        for scenario in scenarios {
            try validatePreReleaseScenario(scenario)
        }
    }
    
    // MARK: - Act Framework Integration Tests
    
    func testActFrameworkValidation() throws {
        guard environmentConfig.hasCapability(.timeIntensiveOperations) else {
            throw XCTSkip("Act framework validation requires time-intensive operations capability")
        }
        
        // These tests would use the act framework to actually execute workflows locally
        // For now, we validate that the workflow files are act-compatible
        
        let workflowFiles = ["release.yml", "pre-release.yml"]
        
        for workflowFile in workflowFiles {
            try validateActCompatibility(workflowFile: workflowFile)
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadWorkflowContent(filename: String) throws -> String {
        let workflowPath = "\(workflowsPath)/\(filename)"
        return try String(contentsOfFile: workflowPath, encoding: .utf8)
    }
    
    private func parseWorkflowYAML(content: String) throws -> WorkflowConfiguration {
        // Parse YAML content and return structured workflow configuration
        return try WorkflowConfiguration(yamlContent: content)
    }
    
    private func validateActAvailability() {
        // Check if act CLI tool is available for workflow execution testing
        let actAvailable = isActCLIAvailable()
        if !actAvailable {
            print("⚠️ Act CLI not available - workflow execution tests will be skipped")
        }
    }
    
    private func isActCLIAvailable() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = ["act"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private func cleanupWorkflowTestArtifacts() {
        // Clean up any temporary files created during workflow testing
        let tempPaths = [
            ".act",
            "workflow-test-output",
            tempTestDirectory?.path
        ].compactMap { $0 }
        
        for path in tempPaths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
    
    private func validateReleaseScenario(_ scenario: ReleaseScenario) throws {
        // Validate that the release workflow would handle the scenario correctly
        let workflowContent = try loadWorkflowContent(filename: "release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        switch scenario {
        case .tagTriggeredRelease(let version):
            XCTAssertTrue(workflow.canHandleTagTrigger(version: version),
                         "Release workflow should handle tag trigger for \(version)")
        case .manualRelease(let version, let prerelease):
            XCTAssertTrue(workflow.canHandleManualDispatch(version: version, prerelease: prerelease),
                         "Release workflow should handle manual dispatch")
        case .prereleaseManual(let version, let prerelease):
            XCTAssertTrue(workflow.canHandleManualDispatch(version: version, prerelease: prerelease),
                         "Release workflow should handle prerelease manual dispatch")
        case .emergencyRelease(let version, let skipTests):
            XCTAssertTrue(workflow.canHandleEmergencyRelease(version: version, skipTests: skipTests),
                         "Release workflow should handle emergency release")
        }
    }
    
    private func validatePreReleaseScenario(_ scenario: PreReleaseScenario) throws {
        // Validate that the pre-release workflow would handle the scenario correctly
        let workflowContent = try loadWorkflowContent(filename: "pre-release.yml")
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        switch scenario {
        case .pullRequestValidation(let targetBranch):
            XCTAssertTrue(workflow.canHandlePRValidation(targetBranch: targetBranch),
                         "Pre-release workflow should handle PR validation")
        case .manualQuickValidation:
            XCTAssertTrue(workflow.canHandleManualValidation(level: "quick"),
                         "Pre-release workflow should handle quick validation")
        case .manualComprehensiveValidation:
            XCTAssertTrue(workflow.canHandleManualValidation(level: "comprehensive"),
                         "Pre-release workflow should handle comprehensive validation")
        case .releaseCandidateValidation:
            XCTAssertTrue(workflow.canHandleManualValidation(level: "release-candidate"),
                         "Pre-release workflow should handle release candidate validation")
        }
    }
    
    private func validateActCompatibility(workflowFile: String) throws {
        // Validate that the workflow file is compatible with act framework
        let workflowContent = try loadWorkflowContent(filename: workflowFile)
        let workflow = try parseWorkflowYAML(content: workflowContent)
        
        // Check for act-incompatible features
        let actIncompatibilities = workflow.findActIncompatibilities()
        
        if !actIncompatibilities.isEmpty {
            print("⚠️ Act incompatibilities found in \(workflowFile): \(actIncompatibilities.joined(separator: ", "))")
            // Note: These are warnings, not failures, as some features may be GitHub-specific
        }
        
        // Validate that the workflow can be parsed by act
        XCTAssertTrue(workflow.isValidYAML, "Workflow \(workflowFile) should be valid YAML")
        XCTAssertTrue(workflow.hasRequiredStructure, "Workflow \(workflowFile) should have required structure")
    }
}

// MARK: - Supporting Types and Enums

enum ReleaseScenario {
    case tagTriggeredRelease(version: String)
    case manualRelease(version: String, prerelease: Bool)
    case prereleaseManual(version: String, prerelease: Bool)
    case emergencyRelease(version: String, skipTests: Bool)
}

enum PreReleaseScenario {
    case pullRequestValidation(targetBranch: String)
    case manualQuickValidation
    case manualComprehensiveValidation
    case releaseCandidateValidation
}