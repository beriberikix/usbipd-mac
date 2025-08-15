// ActIntegrationTests.swift
// Integration tests for GitHub Actions workflows using act framework
// Tests actual workflow execution in local environment

import Foundation
import XCTest
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

class ActIntegrationTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    var environmentConfig: TestEnvironmentConfig {
        return TestEnvironmentDetector.createConfigurationForCurrentEnvironment()
    }
    
    var requiredCapabilities: TestEnvironmentCapabilities {
        return [.networkAccess, .filesystemWrite, .timeIntensiveOperations, .privilegedOperations]
    }
    
    var testCategory: String {
        return "integration"
    }
    
    // MARK: - Test Properties
    
    private var tempWorkingDirectory: URL!
    private let actTimeout: TimeInterval = 600.0 // 10 minutes for act execution
    
    // MARK: - Setup and Teardown
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Skip if act is not available
        guard isActAvailable() else {
            throw XCTSkip("Act CLI not available - install with 'brew install act'")
        }
        
        // Skip if we don't have required capabilities
        guard shouldRunInCurrentEnvironment() else {
            throw XCTSkip("Environment doesn't support act integration tests")
        }
        
        try validateEnvironment()
        setUpTestSuite()
    }
    
    override func tearDownWithError() throws {
        tearDownTestSuite()
        try super.tearDownWithError()
    }
    
    func setUpTestSuite() {
        // Create temporary working directory for act execution
        tempWorkingDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("act-integration-tests-\(UUID().uuidString)")
        
        do {
            try FileManager.default.createDirectory(at: tempWorkingDirectory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create temporary working directory: \(error)")
        }
    }
    
    func tearDownTestSuite() {
        // Clean up temporary directory
        if let tempDir = tempWorkingDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Clean up any act artifacts
        cleanupActArtifacts()
    }
    
    // MARK: - Pre-Release Workflow Tests
    
    func testPreReleaseQuickValidation() throws {
        let testEvent = ActTestEvent.pullRequest(
            action: "opened",
            targetBranch: "main",
            sourceBranch: "feature/test-branch"
        )
        
        let result = try executeWorkflowWithAct(
            workflow: "pre-release.yml",
            event: testEvent,
            timeout: 180.0 // 3 minutes for quick validation
        )
        
        XCTAssertTrue(result.success, "Quick validation should succeed")
        XCTAssertTrue(result.jobsExecuted.contains("quick-validation"), "Should execute quick validation job")
        XCTAssertFalse(result.jobsExecuted.contains("comprehensive-validation"), "Should not execute comprehensive validation")
        XCTAssertTrue(result.executionTime < 180.0, "Quick validation should complete within 3 minutes")
    }
    
    func testPreReleaseComprehensiveValidation() throws {
        let testEvent = ActTestEvent.workflowDispatch(
            inputs: [
                "validation_level": "comprehensive",
                "target_branch": "main"
            ]
        )
        
        let result = try executeWorkflowWithAct(
            workflow: "pre-release.yml",
            event: testEvent,
            timeout: 300.0 // 5 minutes for comprehensive validation
        )
        
        XCTAssertTrue(result.success, "Comprehensive validation should succeed")
        XCTAssertTrue(result.jobsExecuted.contains("quick-validation"), "Should execute quick validation job")
        XCTAssertTrue(result.jobsExecuted.contains("comprehensive-validation"), "Should execute comprehensive validation job")
        XCTAssertFalse(result.jobsExecuted.contains("release-candidate-validation"), "Should not execute release candidate validation")
    }
    
    func testPreReleaseReleaseCandidateValidation() throws {
        let testEvent = ActTestEvent.workflowDispatch(
            inputs: [
                "validation_level": "release-candidate",
                "target_branch": "main"
            ]
        )
        
        let result = try executeWorkflowWithAct(
            workflow: "pre-release.yml",
            event: testEvent,
            timeout: actTimeout
        )
        
        XCTAssertTrue(result.success, "Release candidate validation should succeed")
        XCTAssertTrue(result.jobsExecuted.contains("quick-validation"), "Should execute quick validation job")
        XCTAssertTrue(result.jobsExecuted.contains("comprehensive-validation"), "Should execute comprehensive validation job")
        XCTAssertTrue(result.jobsExecuted.contains("release-candidate-validation"), "Should execute release candidate validation job")
    }
    
    // MARK: - Release Workflow Tests
    
    func testReleaseWorkflowTagTrigger() throws {
        let testEvent = ActTestEvent.push(
            ref: "refs/tags/v1.2.3-test",
            tags: ["v1.2.3-test"]
        )
        
        let result = try executeWorkflowWithAct(
            workflow: "release.yml",
            event: testEvent,
            timeout: actTimeout,
            environment: createReleaseTestEnvironment()
        )
        
        XCTAssertTrue(result.success, "Release workflow should succeed for tag trigger")
        
        // Verify job execution order
        let expectedJobOrder = ["validate-release", "lint-and-build", "test-validation", "build-artifacts"]
        verifyJobExecutionOrder(result: result, expectedOrder: expectedJobOrder)
        
        // Verify version extraction
        XCTAssertTrue(result.outputs["version"] == "v1.2.3-test", "Should extract correct version from tag")
        XCTAssertTrue(result.outputs["is-prerelease"] == "true", "Should detect prerelease from version")
    }
    
    func testReleaseWorkflowManualDispatch() throws {
        let testEvent = ActTestEvent.workflowDispatch(
            inputs: [
                "version": "v1.2.4-test",
                "prerelease": "false",
                "skip_tests": "false"
            ]
        )
        
        let result = try executeWorkflowWithAct(
            workflow: "release.yml",
            event: testEvent,
            timeout: actTimeout,
            environment: createReleaseTestEnvironment()
        )
        
        XCTAssertTrue(result.success, "Release workflow should succeed for manual dispatch")
        XCTAssertTrue(result.jobsExecuted.contains("test-validation"), "Should execute test validation when skip_tests is false")
        XCTAssertTrue(result.outputs["prerelease"] == "false", "Should respect manual prerelease setting")
    }
    
    func testReleaseWorkflowEmergencyMode() throws {
        let testEvent = ActTestEvent.workflowDispatch(
            inputs: [
                "version": "v1.2.5-test",
                "prerelease": "false",
                "skip_tests": "true"
            ]
        )
        
        let result = try executeWorkflowWithAct(
            workflow: "release.yml",
            event: testEvent,
            timeout: 300.0, // Shorter timeout for emergency mode
            environment: createReleaseTestEnvironment()
        )
        
        XCTAssertTrue(result.success, "Release workflow should succeed in emergency mode")
        XCTAssertFalse(result.jobsExecuted.contains("test-validation"), "Should skip test validation when skip_tests is true")
        XCTAssertTrue(result.executionTime < 300.0, "Emergency mode should be faster")
    }
    
    // MARK: - Error Scenario Tests
    
    func testWorkflowFailureHandling() throws {
        // Test workflow behavior when build fails
        let testEvent = ActTestEvent.push(
            ref: "refs/tags/v1.0.0-fail-test",
            tags: ["v1.0.0-fail-test"]
        )
        
        // Inject build failure by modifying environment
        var failureEnvironment = createReleaseTestEnvironment()
        failureEnvironment["FORCE_BUILD_FAILURE"] = "true"
        
        let result = try executeWorkflowWithAct(
            workflow: "release.yml",
            event: testEvent,
            timeout: 120.0, // Shorter timeout for failure case
            environment: failureEnvironment,
            expectSuccess: false
        )
        
        XCTAssertFalse(result.success, "Release workflow should fail when build fails")
        XCTAssertTrue(result.jobsExecuted.contains("validate-release"), "Should execute validation job")
        XCTAssertTrue(result.jobsExecuted.contains("lint-and-build"), "Should execute build job (and fail)")
        XCTAssertFalse(result.jobsExecuted.contains("create-release"), "Should not create release on build failure")
    }
    
    func testInvalidVersionHandling() throws {
        let testEvent = ActTestEvent.workflowDispatch(
            inputs: [
                "version": "invalid-version",
                "prerelease": "false"
            ]
        )
        
        let result = try executeWorkflowWithAct(
            workflow: "release.yml",
            event: testEvent,
            timeout: 60.0, // Should fail quickly
            environment: createReleaseTestEnvironment(),
            expectSuccess: false
        )
        
        XCTAssertFalse(result.success, "Release workflow should fail for invalid version")
        XCTAssertTrue(result.jobsExecuted.contains("validate-release"), "Should execute validation job (and fail)")
        XCTAssertFalse(result.jobsExecuted.contains("lint-and-build"), "Should not proceed to build on version validation failure")
    }
    
    // MARK: - Performance and Timeout Tests
    
    func testWorkflowPerformance() throws {
        let testEvent = ActTestEvent.pullRequest(
            action: "opened",
            targetBranch: "main",
            sourceBranch: "feature/performance-test"
        )
        
        let startTime = Date()
        let result = try executeWorkflowWithAct(
            workflow: "pre-release.yml",
            event: testEvent,
            timeout: 120.0 // 2 minutes for performance test
        )
        let executionTime = Date().timeIntervalSince(startTime)
        
        XCTAssertTrue(result.success, "Quick validation should succeed")
        XCTAssertTrue(executionTime < 120.0, "Quick validation should complete within 2 minutes")
        
        // Performance benchmarks
        XCTAssertTrue(executionTime < 90.0, "Quick validation should complete within 90 seconds for good performance")
        
        // Log performance metrics
        print("📊 Performance Metrics:")
        print("   • Total execution time: \(String(format: "%.2f", executionTime))s")
        print("   • Jobs executed: \(result.jobsExecuted.count)")
        print("   • Average time per job: \(String(format: "%.2f", executionTime / Double(result.jobsExecuted.count)))s")
    }
    
    // MARK: - Artifact and Output Tests
    
    func testArtifactGeneration() throws {
        let testEvent = ActTestEvent.workflowDispatch(
            inputs: [
                "version": "v1.0.0-artifact-test",
                "prerelease": "true"
            ]
        )
        
        let result = try executeWorkflowWithAct(
            workflow: "release.yml",
            event: testEvent,
            timeout: actTimeout,
            environment: createReleaseTestEnvironment()
        )
        
        XCTAssertTrue(result.success, "Release workflow should succeed")
        
        // Verify artifacts were generated
        XCTAssertTrue(result.artifactsGenerated.contains { $0.contains("usbipd") }, 
                     "Should generate usbipd binary artifact")
        XCTAssertTrue(result.artifactsGenerated.contains { $0.contains("checksums") }, 
                     "Should generate checksums file")
        XCTAssertTrue(result.artifactsGenerated.contains { $0.contains(".tar.gz") }, 
                     "Should generate archive artifact")
        
        // Verify outputs
        XCTAssertNotNil(result.outputs["artifact-paths"], "Should output artifact paths")
        XCTAssertNotNil(result.outputs["checksums"], "Should output checksums file path")
    }
    
    // MARK: - Helper Methods
    
    private func executeWorkflowWithAct(
        workflow: String,
        event: ActTestEvent,
        timeout: TimeInterval = 300.0,
        environment: [String: String] = [:],
        expectSuccess: Bool = true
    ) throws -> ActExecutionResult {
        
        // Prepare act command
        let actCommand = buildActCommand(
            workflow: workflow,
            event: event,
            environment: environment
        )
        
        // Execute workflow with act
        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = ["act"] + actCommand.arguments
        process.currentDirectoryPath = FileManager.default.currentDirectoryPath
        
        // Set up environment variables
        var processEnvironment = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            processEnvironment[key] = value
        }
        process.environment = processEnvironment
        
        // Capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Execute with timeout
        let startTime = Date()
        process.launch()
        
        var completed = false
        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            if !completed {
                process.terminate()
            }
        }
        
        process.waitUntilExit()
        completed = true
        timeoutTimer.invalidate()
        
        let executionTime = Date().timeIntervalSince(startTime)
        
        // Parse output
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        
        // Parse results
        let result = parseActExecutionResult(
            output: output,
            error: error,
            exitCode: process.terminationStatus,
            executionTime: executionTime
        )
        
        // Log results for debugging
        if !expectSuccess || !result.success {
            print("🔍 Act Execution Details:")
            print("   • Workflow: \(workflow)")
            print("   • Event: \(event)")
            print("   • Exit Code: \(process.terminationStatus)")
            print("   • Execution Time: \(String(format: "%.2f", executionTime))s")
            print("   • Success: \(result.success)")
            if !output.isEmpty {
                print("   • Output: \(output.prefix(500))...")
            }
            if !error.isEmpty {
                print("   • Error: \(error.prefix(500))...")
            }
        }
        
        return result
    }
    
    private func buildActCommand(
        workflow: String,
        event: ActTestEvent,
        environment: [String: String]
    ) -> ActCommand {
        
        var arguments: [String] = []
        
        // Add workflow file
        arguments.append("-W")
        arguments.append(".github/workflows/\(workflow)")
        
        // Add event type
        switch event {
        case .pullRequest:
            arguments.append("pull_request")
        case .push:
            arguments.append("push")
        case .workflowDispatch:
            arguments.append("workflow_dispatch")
        }
        
        // Add event payload if needed
        if let eventFile = try? createEventPayloadFile(for: event) {
            arguments.append("--eventpath")
            arguments.append(eventFile.path)
        }
        
        // Add environment variables
        for (key, value) in environment {
            arguments.append("--env")
            arguments.append("\(key)=\(value)")
        }
        
        // Add common act options
        arguments.append("--verbose")
        arguments.append("--rm") // Remove containers after execution
        
        return ActCommand(arguments: arguments)
    }
    
    private func createEventPayloadFile(for event: ActTestEvent) throws -> URL {
        let eventPayload = try createEventPayload(for: event)
        let eventFile = tempWorkingDirectory.appendingPathComponent("event-\(UUID().uuidString).json")
        
        try eventPayload.write(to: eventFile, atomically: true, encoding: .utf8)
        return eventFile
    }
    
    private func createEventPayload(for event: ActTestEvent) throws -> String {
        switch event {
        case .pullRequest(let action, let targetBranch, let sourceBranch):
            let payload = [
                "action": action,
                "pull_request": [
                    "base": ["ref": targetBranch],
                    "head": ["ref": sourceBranch]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            return String(data: data, encoding: .utf8) ?? "{}"
            
        case .push(let ref, let tags):
            let payload = [
                "ref": ref,
                "created": true,
                "head_commit": [
                    "id": "test-commit-sha",
                    "message": "Test commit for act integration"
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            return String(data: data, encoding: .utf8) ?? "{}"
            
        case .workflowDispatch(let inputs):
            let payload = [
                "inputs": inputs
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
    
    private func parseActExecutionResult(
        output: String,
        error: String,
        exitCode: Int32,
        executionTime: TimeInterval
    ) -> ActExecutionResult {
        
        // Parse executed jobs from output
        let jobsExecuted = extractExecutedJobs(from: output)
        
        // Parse outputs
        let outputs = extractWorkflowOutputs(from: output)
        
        // Parse generated artifacts
        let artifacts = extractGeneratedArtifacts(from: output)
        
        return ActExecutionResult(
            success: exitCode == 0,
            executionTime: executionTime,
            jobsExecuted: jobsExecuted,
            outputs: outputs,
            artifactsGenerated: artifacts,
            fullOutput: output,
            errorOutput: error
        )
    }
    
    private func extractExecutedJobs(from output: String) -> [String] {
        let lines = output.components(separatedBy: .newlines)
        var jobs: [String] = []
        
        for line in lines {
            // Look for act job execution patterns
            if line.contains("| Job") || line.contains("Running job") {
                // Extract job name from act output format
                let components = line.components(separatedBy: " ")
                for component in components {
                    if component.contains("-") && !component.contains("|") {
                        jobs.append(component)
                        break
                    }
                }
            }
        }
        
        return Array(Set(jobs)) // Remove duplicates
    }
    
    private func extractWorkflowOutputs(from output: String) -> [String: String] {
        var outputs: [String: String] = [:]
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            // Look for GitHub Actions output patterns
            if line.contains("::set-output") || line.contains(">> $GITHUB_OUTPUT") {
                if let output = parseOutputLine(line) {
                    outputs[output.key] = output.value
                }
            }
        }
        
        return outputs
    }
    
    private func parseOutputLine(_ line: String) -> (key: String, value: String)? {
        // Parse different output formats
        if line.contains("::set-output") {
            // Legacy format: ::set-output name=key::value
            let pattern = #"::set-output name=(.+?)::(.+)"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                let key = String(line[Range(match.range(at: 1), in: line)!])
                let value = String(line[Range(match.range(at: 2), in: line)!])
                return (key: key, value: value)
            }
        } else if line.contains(">> $GITHUB_OUTPUT") {
            // New format: key=value >> $GITHUB_OUTPUT
            let parts = line.components(separatedBy: "=")
            if parts.count >= 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].components(separatedBy: " >>").first?.trimmingCharacters(in: .whitespaces) ?? ""
                return (key: key, value: value)
            }
        }
        
        return nil
    }
    
    private func extractGeneratedArtifacts(from output: String) -> [String] {
        let lines = output.components(separatedBy: .newlines)
        var artifacts: [String] = []
        
        for line in lines {
            // Look for artifact creation patterns
            if line.contains("artifact") && (line.contains("created") || line.contains("upload")) {
                // Extract artifact names/paths
                let components = line.components(separatedBy: " ")
                for component in components {
                    if component.contains(".") && (component.contains("-") || component.contains("_")) {
                        artifacts.append(component)
                    }
                }
            }
        }
        
        return artifacts
    }
    
    private func verifyJobExecutionOrder(result: ActExecutionResult, expectedOrder: [String]) {
        // Verify that jobs were executed in the expected dependency order
        // This is a simplified check - in practice you might parse timestamps
        
        let executedJobs = result.jobsExecuted
        var lastFoundIndex = -1
        
        for expectedJob in expectedOrder {
            if let index = executedJobs.firstIndex(of: expectedJob) {
                XCTAssertTrue(index >= lastFoundIndex, 
                             "Job \(expectedJob) should execute after previous jobs in dependency order")
                lastFoundIndex = index
            }
        }
    }
    
    private func createReleaseTestEnvironment() -> [String: String] {
        return [
            "GITHUB_TOKEN": "test-token",
            "DEVELOPER_ID_CERTIFICATE": "",
            "DEVELOPER_ID_CERTIFICATE_PASSWORD": "",
            "NOTARIZATION_USERNAME": "",
            "NOTARIZATION_PASSWORD": "",
            "TEST_MODE": "true"
        ]
    }
    
    private func isActAvailable() -> Bool {
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
    
    private func cleanupActArtifacts() {
        // Clean up act-specific artifacts
        let artifactPaths = [
            ".actrc",
            ".act",
            "event-*.json"
        ]
        
        for pattern in artifactPaths {
            if pattern.contains("*") {
                // Handle glob patterns
                let directory = tempWorkingDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) {
                    for case let fileURL as URL in enumerator {
                        if fileURL.lastPathComponent.hasPrefix(pattern.replacingOccurrences(of: "*", with: "")) {
                            try? FileManager.default.removeItem(at: fileURL)
                        }
                    }
                }
            } else {
                try? FileManager.default.removeItem(atPath: pattern)
            }
        }
    }
}

// MARK: - Supporting Types

enum ActTestEvent {
    case pullRequest(action: String, targetBranch: String, sourceBranch: String)
    case push(ref: String, tags: [String])
    case workflowDispatch(inputs: [String: String])
}

struct ActCommand {
    let arguments: [String]
}

struct ActExecutionResult {
    let success: Bool
    let executionTime: TimeInterval
    let jobsExecuted: [String]
    let outputs: [String: String]
    let artifactsGenerated: [String]
    let fullOutput: String
    let errorOutput: String
}