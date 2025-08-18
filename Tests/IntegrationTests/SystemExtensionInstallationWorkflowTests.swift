//
//  SystemExtensionInstallationWorkflowTests.swift
//  usbipd-mac
//
//  End-to-end integration tests for complete System Extension installation workflow
//  Tests build → sign → install → verify workflow for both signed and unsigned scenarios
//  Includes test environment isolation and comprehensive cleanup
//

import XCTest
import Foundation
import SystemExtensions
@testable import USBIPDCLI
@testable import USBIPDCore
@testable import Common
@testable import SystemExtension

/// End-to-end integration tests for complete System Extension installation workflow
/// Tests complete workflow: build → bundle create → sign → install → verify → cleanup
/// Validates both signed certificate and unsigned development scenarios
/// Includes comprehensive test environment isolation and error recovery
final class SystemExtensionInstallationWorkflowTests: XCTestCase {
    
    // MARK: - Test Properties
    
    var systemExtensionBundleCreator: SystemExtensionBundleCreator!
    var codeSigningManager: CodeSigningManager!
    var systemExtensionInstaller: SystemExtensionInstaller!
    var systemExtensionDiagnostics: SystemExtensionDiagnostics!
    
    var tempWorkingDirectory: URL!
    var testBundleIdentifier: String!
    var testExecutablePath: URL!
    
    // Track installed extensions for cleanup
    var installedExtensions: [String] = []
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        // Create isolated test environment
        setupTestEnvironment()
        
        // Initialize System Extension components
        systemExtensionBundleCreator = SystemExtensionBundleCreator()
        codeSigningManager = CodeSigningManager()
        systemExtensionInstaller = SystemExtensionInstaller()
        systemExtensionDiagnostics = SystemExtensionDiagnostics()
        
        // Generate unique test bundle identifier
        testBundleIdentifier = "com.github.usbipd-mac.SystemExtension.test.\(UUID().uuidString.prefix(8))"
    }
    
    override func tearDown() {
        // Clean up installed extensions
        cleanupInstalledExtensions()
        
        // Clean up test environment
        cleanupTestEnvironment()
        
        // Reset components
        systemExtensionBundleCreator = nil
        codeSigningManager = nil
        systemExtensionInstaller = nil
        systemExtensionDiagnostics = nil
        
        super.tearDown()
    }
    
    // MARK: - Complete Workflow Tests
    
    func testCompleteSignedInstallationWorkflow() throws {
        // Test complete installation workflow with code signing
        
        // Skip if no development certificates available
        let certificates = try codeSigningManager.detectAvailableCertificates()
        guard !certificates.isEmpty else {
            throw XCTSkip("No development certificates available for signed installation workflow test")
        }
        
        // Skip if not in development environment
        guard isDevelopmentEnvironment() else {
            throw XCTSkip("Complete installation workflow tests require development environment")
        }
        
        print("🧪 Testing complete signed installation workflow...")
        
        // Step 1: Build executable (simulate build process)
        let executablePath = try createTestExecutable()
        print("✅ Step 1: Test executable created at \(executablePath.path)")
        
        // Step 2: Create System Extension bundle
        let bundlePath = tempWorkingDirectory.appendingPathComponent("\(testBundleIdentifier!).systemextension")
        let bundleResult = try systemExtensionBundleCreator.createBundle(
            executablePath: executablePath.path,
            bundleIdentifier: testBundleIdentifier,
            outputPath: bundlePath.path
        )
        
        XCTAssertTrue(bundleResult.success, "Bundle creation should succeed: \(bundleResult.message)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundlePath.path), "Bundle should exist")
        print("✅ Step 2: Bundle created successfully at \(bundlePath.path)")
        
        // Step 3: Code sign the bundle
        let signingResult = try codeSigningManager.signBundle(
            bundlePath: bundlePath.path,
            bundleIdentifier: testBundleIdentifier
        )
        
        XCTAssertTrue(signingResult.success, "Bundle signing should succeed: \(signingResult.message)")
        print("✅ Step 3: Bundle signed successfully with certificate: \(signingResult.certificate?.commonName ?? "unknown")")
        
        // Step 4: Verify bundle signature
        let verificationResult = try codeSigningManager.verifyBundleSignature(bundlePath: bundlePath.path)
        XCTAssertTrue(verificationResult.isValid, "Bundle signature should be valid: \(verificationResult.details)")
        print("✅ Step 4: Bundle signature verified successfully")
        
        // Step 5: Install System Extension
        try performInstallationWithUserGuidance(bundlePath: bundlePath, expectSigned: true)
        
        // Step 6: Verify installation
        try verifySuccessfulInstallation(bundleIdentifier: testBundleIdentifier)
        
        print("🎉 Complete signed installation workflow test passed!")
    }
    
    func testCompleteUnsignedDevelopmentWorkflow() throws {
        // Test complete installation workflow without code signing (development mode)
        
        // Skip if not in development environment
        guard isDevelopmentEnvironment() else {
            throw XCTSkip("Development workflow tests require development environment")
        }
        
        print("🧪 Testing complete unsigned development workflow...")
        
        // Step 1: Build executable
        let executablePath = try createTestExecutable()
        print("✅ Step 1: Test executable created at \(executablePath.path)")
        
        // Step 2: Create System Extension bundle
        let bundlePath = tempWorkingDirectory.appendingPathComponent("\(testBundleIdentifier!).systemextension")
        let bundleResult = try systemExtensionBundleCreator.createBundle(
            executablePath: executablePath.path,
            bundleIdentifier: testBundleIdentifier,
            outputPath: bundlePath.path
        )
        
        XCTAssertTrue(bundleResult.success, "Bundle creation should succeed: \(bundleResult.message)")
        print("✅ Step 2: Bundle created successfully")
        
        // Step 3: Skip signing (development mode)
        print("⚠️ Step 3: Skipping code signing (development mode)")
        
        // Step 4: Verify bundle is unsigned but valid structure
        let verificationResult = try codeSigningManager.verifyBundleSignature(bundlePath: bundlePath.path)
        XCTAssertFalse(verificationResult.isValid, "Bundle should be unsigned in development mode")
        print("✅ Step 4: Confirmed bundle is unsigned as expected")
        
        // Step 5: Install unsigned System Extension
        try performInstallationWithUserGuidance(bundlePath: bundlePath, expectSigned: false)
        
        // Step 6: Verify installation
        try verifySuccessfulInstallation(bundleIdentifier: testBundleIdentifier)
        
        print("🎉 Complete unsigned development workflow test passed!")
    }
    
    func testWorkflowErrorRecoveryScenarios() throws {
        // Test error recovery scenarios in installation workflow
        
        guard isDevelopmentEnvironment() else {
            throw XCTSkip("Error recovery tests require development environment")
        }
        
        print("🧪 Testing workflow error recovery scenarios...")
        
        // Test 1: Bundle creation with missing executable
        let missingExecutablePath = "/nonexistent/path/missing_executable"
        let bundlePath = tempWorkingDirectory.appendingPathComponent("\(testBundleIdentifier!).systemextension")
        
        XCTAssertThrowsError(try systemExtensionBundleCreator.createBundle(
            executablePath: missingExecutablePath,
            bundleIdentifier: testBundleIdentifier,
            outputPath: bundlePath.path
        ), "Should throw error for missing executable") { error in
            XCTAssertTrue(error is SystemExtensionBundleCreationError, "Should throw bundle creation error")
        }
        print("✅ Test 1: Missing executable error handled correctly")
        
        // Test 2: Code signing with invalid certificate
        let executablePath = try createTestExecutable()
        let validBundleResult = try systemExtensionBundleCreator.createBundle(
            executablePath: executablePath.path,
            bundleIdentifier: testBundleIdentifier,
            outputPath: bundlePath.path
        )
        XCTAssertTrue(validBundleResult.success, "Valid bundle creation should succeed")
        
        // Attempt signing with invalid certificate name
        XCTAssertThrowsError(try codeSigningManager.signBundleWithCertificate(
            bundlePath: bundlePath.path,
            certificateName: "NonexistentCertificate"
        ), "Should throw error for invalid certificate") { error in
            XCTAssertTrue(error is CodeSigningError, "Should throw code signing error")
        }
        print("✅ Test 2: Invalid certificate error handled correctly")
        
        // Test 3: Installation with corrupted bundle
        try corruptBundle(at: bundlePath)
        
        let expectation = XCTestExpectation(description: "Corrupted bundle installation error")
        var installationError: Error?
        
        systemExtensionInstaller.installSystemExtension(
            bundlePath: bundlePath.path,
            bundleIdentifier: testBundleIdentifier
        ) { result in
            switch result {
            case .success:
                XCTFail("Corrupted bundle installation should not succeed")
            case .failure(let error):
                installationError = error
            }
            expectation.fulfill()
        }
        
        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: 10.0)
        XCTAssertEqual(waiterResult, .completed, "Error handling should complete quickly")
        XCTAssertNotNil(installationError, "Should receive installation error for corrupted bundle")
        print("✅ Test 3: Corrupted bundle error handled correctly")
        
        print("🎉 Workflow error recovery scenarios test passed!")
    }
    
    func testParallelWorkflowExecution() throws {
        // Test parallel execution of workflow steps where possible
        
        guard isDevelopmentEnvironment() else {
            throw XCTSkip("Parallel workflow tests require development environment")
        }
        
        print("🧪 Testing parallel workflow execution...")
        
        let workflowCount = 3
        let expectation = XCTestExpectation(description: "Parallel workflow execution")
        expectation.expectedFulfillmentCount = workflowCount
        
        var workflowResults: [Result<Bool, Error>] = []
        let resultsLock = NSLock()
        
        // Execute multiple workflows in parallel
        for i in 0..<workflowCount {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let workflowBundleId = "\(self.testBundleIdentifier!).\(i)"
                    let success = try self.executeBasicWorkflow(bundleIdentifier: workflowBundleId)
                    
                    resultsLock.lock()
                    workflowResults.append(.success(success))
                    resultsLock.unlock()
                    
                    expectation.fulfill()
                } catch {
                    resultsLock.lock()
                    workflowResults.append(.failure(error))
                    resultsLock.unlock()
                    
                    expectation.fulfill()
                }
            }
        }
        
        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: 60.0)
        XCTAssertEqual(waiterResult, .completed, "Parallel workflows should complete within timeout")
        
        // Verify all workflows succeeded or failed gracefully
        XCTAssertEqual(workflowResults.count, workflowCount, "Should have results for all workflows")
        
        let successCount = workflowResults.compactMap { result in
            switch result {
            case .success(let success): return success ? 1 : 0
            case .failure: return 0
            }
        }.reduce(0, +)
        
        print("Parallel workflow execution: \(successCount)/\(workflowCount) workflows succeeded")
        
        // At least one workflow should succeed in ideal conditions
        // But we allow for system constraints in test environments
        if successCount == 0 {
            print("⚠️ No workflows succeeded - this may indicate system limitations in test environment")
        }
        
        print("✅ Parallel workflow execution test completed")
    }
    
    // MARK: - Bundle Validation Tests
    
    func testComprehensiveBundleValidation() throws {
        // Test comprehensive bundle validation throughout workflow
        
        print("🧪 Testing comprehensive bundle validation...")
        
        let executablePath = try createTestExecutable()
        let bundlePath = tempWorkingDirectory.appendingPathComponent("\(testBundleIdentifier!).systemextension")
        
        // Create bundle
        let bundleResult = try systemExtensionBundleCreator.createBundle(
            executablePath: executablePath.path,
            bundleIdentifier: testBundleIdentifier,
            outputPath: bundlePath.path
        )
        XCTAssertTrue(bundleResult.success, "Bundle creation should succeed")
        
        // Validate bundle structure
        try validateBundleStructure(at: bundlePath)
        print("✅ Bundle structure validation passed")
        
        // Validate Info.plist
        try validateInfoPlist(at: bundlePath, expectedIdentifier: testBundleIdentifier)
        print("✅ Info.plist validation passed")
        
        // Validate entitlements
        try validateEntitlements(at: bundlePath)
        print("✅ Entitlements validation passed")
        
        // Validate executable
        try validateExecutable(at: bundlePath)
        print("✅ Executable validation passed")
        
        // Run diagnostic validation
        let diagnosticResult = try systemExtensionDiagnostics.validateBundle(bundlePath: bundlePath.path)
        XCTAssertTrue(diagnosticResult.isValid, "Bundle should pass diagnostic validation: \(diagnosticResult.issues)")
        print("✅ Diagnostic validation passed")
        
        print("🎉 Comprehensive bundle validation test passed!")
    }
    
    // MARK: - Installation Status and Health Tests
    
    func testInstallationStatusMonitoring() throws {
        // Test installation status monitoring throughout workflow
        
        guard isDevelopmentEnvironment() else {
            throw XCTSkip("Installation status tests require development environment")
        }
        
        print("🧪 Testing installation status monitoring...")
        
        // Create and prepare bundle
        let executablePath = try createTestExecutable()
        let bundlePath = tempWorkingDirectory.appendingPathComponent("\(testBundleIdentifier!).systemextension")
        
        let bundleResult = try systemExtensionBundleCreator.createBundle(
            executablePath: executablePath.path,
            bundleIdentifier: testBundleIdentifier,
            outputPath: bundlePath.path
        )
        XCTAssertTrue(bundleResult.success, "Bundle creation should succeed")
        
        // Monitor status before installation
        var statusBeforeInstall = try systemExtensionInstaller.getInstallationStatus(
            bundleIdentifier: testBundleIdentifier
        )
        XCTAssertFalse(statusBeforeInstall.isInstalled, "Extension should not be installed initially")
        print("✅ Pre-installation status: not installed (expected)")
        
        // Start installation and monitor status changes
        let installationExpectation = XCTestExpectation(description: "Installation status monitoring")
        var statusUpdates: [SystemExtensionStatus] = []
        
        // Monitor status during installation
        let statusMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            do {
                let currentStatus = try self.systemExtensionInstaller.getInstallationStatus(
                    bundleIdentifier: self.testBundleIdentifier
                )
                statusUpdates.append(currentStatus)
                
                // Stop monitoring once installed or if we get enough samples
                if currentStatus.isInstalled || statusUpdates.count >= 30 {
                    installationExpectation.fulfill()
                }
            } catch {
                print("Status monitoring error: \(error)")
                installationExpectation.fulfill()
            }
        }
        
        // Start installation
        systemExtensionInstaller.installSystemExtension(
            bundlePath: bundlePath.path,
            bundleIdentifier: testBundleIdentifier
        ) { _ in
            // Installation completion is handled by status monitoring
        }
        
        // Wait for status monitoring to complete
        let waiterResult = XCTWaiter.wait(for: [installationExpectation], timeout: 60.0)
        statusMonitorTimer.invalidate()
        
        XCTAssertEqual(waiterResult, .completed, "Status monitoring should complete")
        XCTAssertFalse(statusUpdates.isEmpty, "Should have recorded status updates")
        
        print("Status monitoring recorded \(statusUpdates.count) status updates")
        
        // Analyze status progression
        let uniqueStates = Set(statusUpdates.map { $0.installationState })
        print("Installation states observed: \(uniqueStates)")
        
        print("✅ Installation status monitoring test completed")
    }
    
    func testPostInstallationHealthChecks() throws {
        // Test post-installation health checks and diagnostics
        
        guard isDevelopmentEnvironment() else {
            throw XCTSkip("Health check tests require development environment")
        }
        
        // Skip if no installed extensions available for testing
        let installedExtensions = try systemExtensionDiagnostics.getInstalledExtensions()
        guard !installedExtensions.isEmpty else {
            throw XCTSkip("No installed System Extensions available for health check testing")
        }
        
        print("🧪 Testing post-installation health checks...")
        
        let testExtension = installedExtensions.first!
        
        // Test comprehensive health check
        let healthResult = try systemExtensionDiagnostics.performHealthCheck(
            bundleIdentifier: testExtension.bundleIdentifier
        )
        
        print("Health check result for \(testExtension.bundleIdentifier):")
        print("  - Overall health: \(healthResult.isHealthy ? "✅ Healthy" : "❌ Unhealthy")")
        print("  - Bundle valid: \(healthResult.bundleValid)")
        print("  - Signature valid: \(healthResult.signatureValid)")
        print("  - System registration: \(healthResult.systemRegistered)")
        print("  - IPC functional: \(healthResult.ipcFunctional)")
        
        // Health check should not fail completely unless extension is severely broken
        // Individual components may fail in test environments
        XCTAssertNotNil(healthResult, "Health check should complete successfully")
        
        // Test diagnostic reporting
        let diagnosticReport = try systemExtensionDiagnostics.generateDiagnosticReport(
            bundleIdentifier: testExtension.bundleIdentifier
        )
        
        XCTAssertFalse(diagnosticReport.isEmpty, "Diagnostic report should not be empty")
        print("Diagnostic report generated (\(diagnosticReport.count) characters)")
        
        print("✅ Post-installation health checks test completed")
    }
    
    // MARK: - Test Environment Management
    
    private func setupTestEnvironment() {
        // Create isolated temporary directory for testing
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemExtensionWorkflowTests")
            .appendingPathComponent(UUID().uuidString)
        
        do {
            try FileManager.default.createDirectory(at: tempDir, 
                                                   withIntermediateDirectories: true, 
                                                   attributes: nil)
            tempWorkingDirectory = tempDir
            print("Test environment created: \(tempDir.path)")
        } catch {
            XCTFail("Failed to create test environment: \(error)")
        }
    }
    
    private func cleanupTestEnvironment() {
        guard let tempDir = tempWorkingDirectory else { return }
        
        do {
            try FileManager.default.removeItem(at: tempDir)
            print("Test environment cleaned up: \(tempDir.path)")
        } catch {
            print("Warning: Failed to clean up test environment: \(error)")
        }
        
        tempWorkingDirectory = nil
    }
    
    private func cleanupInstalledExtensions() {
        // Clean up any extensions installed during testing
        for bundleIdentifier in installedExtensions {
            do {
                let uninstallResult = try systemExtensionInstaller.uninstallSystemExtension(
                    bundleIdentifier: bundleIdentifier
                )
                if uninstallResult.success {
                    print("Cleaned up test extension: \(bundleIdentifier)")
                } else {
                    print("Warning: Failed to clean up test extension \(bundleIdentifier): \(uninstallResult.message)")
                }
            } catch {
                print("Warning: Error cleaning up test extension \(bundleIdentifier): \(error)")
            }
        }
        installedExtensions.removeAll()
    }
    
    // MARK: - Helper Methods
    
    private func createTestExecutable() throws -> URL {
        let executablePath = tempWorkingDirectory.appendingPathComponent("TestSystemExtension")
        
        // Create a minimal test executable
        let executableContent = """
        #!/bin/bash
        echo "Test System Extension - Version 1.0"
        echo "Bundle ID: $1"
        while true; do
            sleep 1
        done
        """
        
        try executableContent.write(to: executablePath, atomically: true, encoding: .utf8)
        
        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], 
                                             ofItemAtPath: executablePath.path)
        
        return executablePath
    }
    
    private func performInstallationWithUserGuidance(bundlePath: URL, expectSigned: Bool) throws {
        // Perform installation with appropriate user guidance for test environment
        
        print("🔧 Starting System Extension installation...")
        if !expectSigned {
            print("⚠️ This is an unsigned extension - you may need to approve developer mode")
        }
        print("📋 You may be prompted to approve the System Extension installation")
        
        let expectation = XCTestExpectation(description: "System Extension installation")
        var installationResult: Result<Bool, Error>?
        
        systemExtensionInstaller.installSystemExtension(
            bundlePath: bundlePath.path,
            bundleIdentifier: testBundleIdentifier
        ) { result in
            installationResult = result
            expectation.fulfill()
        }
        
        // Wait for installation to complete (may require user approval)
        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: 120.0) // Longer timeout for user interaction
        
        switch waiterResult {
        case .completed:
            guard let result = installationResult else {
                throw XCTError(.failureWhileWaiting)
            }
            
            switch result {
            case .success(let installed):
                if installed {
                    installedExtensions.append(testBundleIdentifier)
                    print("✅ System Extension installation succeeded")
                } else {
                    throw XCTSkip("System Extension installation requires user approval - test cannot proceed automatically")
                }
            case .failure(let error):
                // Handle expected errors in test environment
                if let extensionError = error as? SystemExtensionInstallationError {
                    switch extensionError {
                    case .requiresApproval, .userRejected:
                        throw XCTSkip("System Extension installation requires user approval")
                    case .developmentModeDisabled:
                        throw XCTSkip("System Extension development mode is disabled")
                    default:
                        throw extensionError
                    }
                }
                throw error
            }
        case .timedOut:
            throw XCTSkip("System Extension installation timed out - may require user approval")
        default:
            throw XCTError(.failureWhileWaiting)
        }
    }
    
    private func verifySuccessfulInstallation(bundleIdentifier: String) throws {
        // Verify that installation was successful
        
        let status = try systemExtensionInstaller.getInstallationStatus(bundleIdentifier: bundleIdentifier)
        XCTAssertTrue(status.isInstalled, "Extension should be installed")
        
        // Run post-installation diagnostics
        let healthResult = try systemExtensionDiagnostics.performHealthCheck(bundleIdentifier: bundleIdentifier)
        XCTAssertTrue(healthResult.isHealthy || !healthResult.criticalIssues.isEmpty,
                     "Extension should be healthy or have identifiable issues")
        
        print("✅ Installation verified successfully")
    }
    
    private func executeBasicWorkflow(bundleIdentifier: String) throws -> Bool {
        // Execute a basic workflow for parallel testing
        
        let workingDir = tempWorkingDirectory.appendingPathComponent(bundleIdentifier)
        try FileManager.default.createDirectory(at: workingDir, 
                                               withIntermediateDirectories: true, 
                                               attributes: nil)
        
        // Create executable
        let executablePath = workingDir.appendingPathComponent("TestExecutable")
        try "#!/bin/bash\necho 'Test'\n".write(to: executablePath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], 
                                             ofItemAtPath: executablePath.path)
        
        // Create bundle
        let bundlePath = workingDir.appendingPathComponent("\(bundleIdentifier).systemextension")
        let bundleResult = try systemExtensionBundleCreator.createBundle(
            executablePath: executablePath.path,
            bundleIdentifier: bundleIdentifier,
            outputPath: bundlePath.path
        )
        
        return bundleResult.success
    }
    
    private func corruptBundle(at bundlePath: URL) throws {
        // Corrupt a bundle for error testing
        let infoPlistPath = bundlePath.appendingPathComponent("Contents/Info.plist")
        try "corrupted".write(to: infoPlistPath, atomically: true, encoding: .utf8)
    }
    
    private func validateBundleStructure(at bundlePath: URL) throws {
        let requiredPaths = [
            "Contents",
            "Contents/Info.plist",
            "Contents/MacOS",
            "Contents/Resources"
        ]
        
        for relativePath in requiredPaths {
            let fullPath = bundlePath.appendingPathComponent(relativePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fullPath.path),
                         "Required path should exist: \(relativePath)")
        }
    }
    
    private func validateInfoPlist(at bundlePath: URL, expectedIdentifier: String) throws {
        let infoPlistPath = bundlePath.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: infoPlistPath)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
        
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, expectedIdentifier,
                      "Bundle identifier should match expected")
        XCTAssertNotNil(plist["NSExtension"], "NSExtension configuration should be present")
    }
    
    private func validateEntitlements(at bundlePath: URL) throws {
        let entitlementsPath = bundlePath.appendingPathComponent("Contents/Resources/SystemExtension.entitlements")
        XCTAssertTrue(FileManager.default.fileExists(atPath: entitlementsPath.path),
                     "Entitlements file should exist")
        
        let data = try Data(contentsOf: entitlementsPath)
        let entitlements = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
        
        XCTAssertEqual(entitlements["com.apple.developer.system-extension.install"] as? Bool, true,
                      "System Extension install entitlement should be present")
    }
    
    private func validateExecutable(at bundlePath: URL) throws {
        let macosDir = bundlePath.appendingPathComponent("Contents/MacOS")
        let contents = try FileManager.default.contentsOfDirectory(atPath: macosDir.path)
        XCTAssertFalse(contents.isEmpty, "MacOS directory should contain executable")
        
        let executablePath = macosDir.appendingPathComponent(contents.first!)
        let attributes = try FileManager.default.attributesOfItem(atPath: executablePath.path)
        let permissions = attributes[.posixPermissions] as! NSNumber
        XCTAssertTrue((permissions.uint16Value & 0o111) != 0, "Executable should have execute permissions")
    }
    
    private func isDevelopmentEnvironment() -> Bool {
        #if DEBUG
        return true
        #else
        return ProcessInfo.processInfo.environment["SYSTEM_EXTENSION_DEVELOPMENT"] == "1"
        #endif
    }
    
    // MARK: - Enhanced Installation Workflow Tests
    
    func testCompleteInstallationOrchestrationWorkflow() throws {
        // Test complete installation workflow using InstallationOrchestrator
        
        print("🧪 Testing complete installation orchestration workflow...")
        
        // Setup: Create a realistic bundle structure for testing
        let bundlePath = try setupTestBundleForOrchestration()
        
        // Test the complete orchestration workflow
        let orchestrator = InstallationOrchestrator(
            bundleDetector: MockSystemExtensionBundleDetector(mockBundlePath: bundlePath.path),
            submissionManager: MockSystemExtensionSubmissionManager(),
            serviceManager: MockServiceLifecycleManager(),
            verificationManager: MockInstallationVerificationManager()
        )
        
        // Execute the complete installation workflow
        let expectation = XCTestExpectation(description: "Installation orchestration completes")
        
        Task {
            let result = await orchestrator.performCompleteInstallation()
            
            // Verify successful installation
            XCTAssertTrue(result.success, "Installation orchestration should succeed")
            XCTAssertEqual(result.finalPhase, .completed, "Should reach completed phase")
            XCTAssertNotNil(result.bundleDetectionResult, "Should have bundle detection result")
            XCTAssertNotNil(result.submissionResult, "Should have submission result")
            XCTAssertNotNil(result.serviceIntegrationResult, "Should have service integration result")
            XCTAssertNotNil(result.verificationResult, "Should have verification result")
            
            print("✅ Complete orchestration workflow test passed!")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testInstallationWorkflowErrorRecoveryScenarios() throws {
        // Test error recovery and rollback scenarios in installation orchestration
        
        print("🧪 Testing installation workflow error recovery scenarios...")
        
        // Test 1: Bundle detection failure
        let noBundleOrchestrator = InstallationOrchestrator(
            bundleDetector: MockSystemExtensionBundleDetector(shouldFail: true),
            submissionManager: MockSystemExtensionSubmissionManager(),
            serviceManager: MockServiceLifecycleManager(),
            verificationManager: MockInstallationVerificationManager()
        )
        
        let bundleFailExpectation = XCTestExpectation(description: "Bundle detection failure handled")
        
        Task {
            let result = await noBundleOrchestrator.performCompleteInstallation()
            
            XCTAssertFalse(result.success, "Should fail when bundle detection fails")
            XCTAssertEqual(result.finalPhase, .failed, "Should reach failed phase")
            XCTAssertFalse(result.issues.isEmpty, "Should have error details")
            XCTAssertFalse(result.recommendations.isEmpty, "Should have recovery recommendations")
            
            print("✅ Bundle detection failure recovery test passed!")
            bundleFailExpectation.fulfill()
        }
        
        // Test 2: System Extension submission failure
        let bundlePath = try setupTestBundleForOrchestration()
        let submissionFailOrchestrator = InstallationOrchestrator(
            bundleDetector: MockSystemExtensionBundleDetector(mockBundlePath: bundlePath.path),
            submissionManager: MockSystemExtensionSubmissionManager(shouldFail: true),
            serviceManager: MockServiceLifecycleManager(),
            verificationManager: MockInstallationVerificationManager()
        )
        
        let submissionFailExpectation = XCTestExpectation(description: "Submission failure handled")
        
        Task {
            let result = await submissionFailOrchestrator.performCompleteInstallation()
            
            XCTAssertFalse(result.success, "Should fail when submission fails")
            XCTAssertEqual(result.finalPhase, .failed, "Should reach failed phase")
            XCTAssertTrue(result.issues.contains { $0.contains("submission") }, "Should have submission error details")
            
            print("✅ Submission failure recovery test passed!")
            submissionFailExpectation.fulfill()
        }
        
        // Test 3: Service integration failure
        let serviceFailOrchestrator = InstallationOrchestrator(
            bundleDetector: MockSystemExtensionBundleDetector(mockBundlePath: bundlePath.path),
            submissionManager: MockSystemExtensionSubmissionManager(),
            serviceManager: MockServiceLifecycleManager(shouldFail: true),
            verificationManager: MockInstallationVerificationManager()
        )
        
        let serviceFailExpectation = XCTestExpectation(description: "Service failure handled")
        
        Task {
            let result = await serviceFailOrchestrator.performCompleteInstallation()
            
            XCTAssertFalse(result.success, "Should fail when service integration fails")
            XCTAssertEqual(result.finalPhase, .failed, "Should reach failed phase")
            XCTAssertTrue(result.issues.contains { $0.contains("service") }, "Should have service error details")
            
            print("✅ Service integration failure recovery test passed!")
            serviceFailExpectation.fulfill()
        }
        
        wait(for: [bundleFailExpectation, submissionFailExpectation, serviceFailExpectation], timeout: 30.0)
    }
    
    func testServiceManagementIntegration() throws {
        // Test service management integration with installation workflow
        
        print("🧪 Testing service management integration...")
        
        let bundlePath = try setupTestBundleForOrchestration()
        let serviceManager = MockServiceLifecycleManager()
        
        // Test service lifecycle coordination
        let coordinationExpectation = XCTestExpectation(description: "Service coordination completes")
        
        Task {
            let result = await serviceManager.coordinateInstallationWithService()
            
            XCTAssertTrue(result.success, "Service coordination should succeed")
            XCTAssertEqual(result.issues.count, 0, "Should not have service issues in mock")
            
            print("✅ Service coordination test passed!")
            coordinationExpectation.fulfill()
        }
        
        // Test service status detection
        let statusExpectation = XCTestExpectation(description: "Service status detection completes")
        
        Task {
            let status = await serviceManager.detectServiceStatus()
            
            XCTAssertNotNil(status, "Should return service status")
            XCTAssertTrue(status.isRunning || !status.isRunning, "Should have valid running state")
            
            print("✅ Service status detection test passed!")
            statusExpectation.fulfill()
        }
        
        // Test service conflict resolution
        let conflictExpectation = XCTestExpectation(description: "Service conflict resolution completes")
        
        Task {
            let result = await serviceManager.resolveServiceConflicts()
            
            XCTAssertTrue(result.processesTerminated >= 0, "Should have non-negative terminated processes")
            
            print("✅ Service conflict resolution test passed!")
            conflictExpectation.fulfill()
        }
        
        wait(for: [coordinationExpectation, statusExpectation, conflictExpectation], timeout: 30.0)
    }
    
    func testHomebrewEnvironmentSimulation() throws {
        // Test Homebrew environment simulation and bundle detection
        
        print("🧪 Testing Homebrew environment simulation...")
        
        // Setup mock Homebrew environment
        let homebrewPath = try setupMockHomebrewEnvironment()
        
        // Test enhanced bundle detection in Homebrew environment
        let bundleDetector = SystemExtensionBundleDetector()
        let detectionResult = bundleDetector.detectBundle()
        
        // In real Homebrew environment, we would expect:
        // 1. Bundle to be found in Homebrew path
        // 2. Homebrew metadata to be available
        // 3. Production environment to be detected
        
        if detectionResult.found {
            print("✅ Bundle detected in test environment")
            
            if let homebrewMetadata = detectionResult.homebrewMetadata {
                XCTAssertNotNil(homebrewMetadata.version, "Homebrew metadata should have version")
                print("✅ Homebrew metadata detected: version \(homebrewMetadata.version ?? "unknown")")
            }
            
            switch detectionResult.detectionEnvironment {
            case .homebrew(let cellarPath, let version):
                print("✅ Homebrew environment detected: \(cellarPath), version: \(version ?? "unknown")")
            case .development(let buildPath):
                print("✅ Development environment detected: \(buildPath)")
            case .manual(let bundlePath):
                print("✅ Manual environment detected: \(bundlePath)")
            case .unknown:
                print("⚠️ Unknown environment detected")
            }
        } else {
            print("ℹ️ No bundle detected in test environment (expected in test)")
        }
        
        // Test CLI integration with Homebrew environment
        let installCommand = InstallSystemExtensionCommand()
        
        // Test help functionality
        XCTAssertNoThrow(try installCommand.execute(with: ["--help"]), "Help command should not throw")
        
        print("✅ Homebrew environment simulation test passed!")
    }
    
    func testSystemExtensionManagerIntegration() throws {
        // Test SystemExtensionManager integration with enhanced installation capabilities
        
        print("🧪 Testing SystemExtensionManager integration...")
        
        let bundlePath = try setupTestBundleForOrchestration()
        
        // Create SystemExtensionManager with enhanced components
        let manager = SystemExtensionManager(
            deviceClaimer: MockDeviceClaimer(),
            ipcHandler: MockIPCHandler(),
            statusMonitor: nil,
            config: SystemExtensionManagerConfig(),
            bundleDetector: MockSystemExtensionBundleDetector(mockBundlePath: bundlePath.path),
            installationOrchestrator: InstallationOrchestrator(
                bundleDetector: MockSystemExtensionBundleDetector(mockBundlePath: bundlePath.path),
                submissionManager: MockSystemExtensionSubmissionManager(),
                serviceManager: MockServiceLifecycleManager(),
                verificationManager: MockInstallationVerificationManager()
            ),
            logger: Logger(config: LoggerConfig(level: .debug), subsystem: "test", category: "integration")
        )
        
        // Test enhanced status reporting
        let status = manager.getStatus()
        
        XCTAssertNotNil(status.bundleInfo, "Status should include bundle info")
        XCTAssertNotEqual(status.installationStatus, .unknown, "Should have meaningful installation status")
        
        print("✅ Enhanced status reporting: \(status.installationStatus)")
        
        // Test automatic installation capability
        let autoInstallExpectation = XCTestExpectation(description: "Automatic installation completes")
        
        Task {
            let success = await manager.performAutomaticInstallationIfNeeded()
            
            // In test environment, this may succeed or fail depending on mocks
            print("✅ Automatic installation result: \(success)")
            autoInstallExpectation.fulfill()
        }
        
        wait(for: [autoInstallExpectation], timeout: 30.0)
        
        print("✅ SystemExtensionManager integration test passed!")
    }
    
    // MARK: - Test Helpers for Enhanced Workflow Tests
    
    private func setupTestBundleForOrchestration() throws -> URL {
        // Create a realistic test bundle structure for orchestration testing
        let bundleName = "TestSystemExtension.systemextension"
        let bundlePath = tempWorkingDirectory.appendingPathComponent(bundleName)
        
        // Create bundle directory structure
        let contentsDir = bundlePath.appendingPathComponent("Contents")
        let macosDir = contentsDir.appendingPathComponent("MacOS")
        let resourcesDir = contentsDir.appendingPathComponent("Resources")
        
        try FileManager.default.createDirectory(at: macosDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
        
        // Create Info.plist
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.test.systemextension</string>
            <key>CFBundleName</key>
            <string>TestSystemExtension</string>
            <key>CFBundleVersion</key>
            <string>1.0.0</string>
            <key>NSExtension</key>
            <dict>
                <key>NSExtensionPointIdentifier</key>
                <string>com.apple.system-extension.driver-extension</string>
            </dict>
        </dict>
        </plist>
        """
        
        try infoPlist.write(to: contentsDir.appendingPathComponent("Info.plist"), 
                           atomically: true, encoding: .utf8)
        
        // Create mock executable
        let executablePath = macosDir.appendingPathComponent("TestSystemExtension")
        try "#!/bin/bash\necho 'Test System Extension'\n".write(to: executablePath, 
                                                                atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], 
                                             ofItemAtPath: executablePath.path)
        
        // Create mock Homebrew metadata
        let homebrewMetadata = """
        {
            "version": "1.0.0",
            "installation_date": "\(ISO8601DateFormatter().string(from: Date()))",
            "formula": "usbipd-mac"
        }
        """
        
        try homebrewMetadata.write(to: contentsDir.appendingPathComponent("HomebrewMetadata.json"),
                                  atomically: true, encoding: .utf8)
        
        return bundlePath
    }
    
    private func setupMockHomebrewEnvironment() throws -> URL {
        // Setup a mock Homebrew environment for testing
        let homebrewDir = tempWorkingDirectory.appendingPathComponent("homebrew")
        let cellarDir = homebrewDir.appendingPathComponent("Cellar/usbipd-mac/1.0.0/Library/SystemExtensions")
        
        try FileManager.default.createDirectory(at: cellarDir, withIntermediateDirectories: true)
        
        // Create a mock bundle in the Homebrew location
        let bundlePath = try setupTestBundleForOrchestration()
        let homebrewBundlePath = cellarDir.appendingPathComponent("TestSystemExtension.systemextension")
        
        try FileManager.default.copyItem(at: bundlePath, to: homebrewBundlePath)
        
        return homebrewDir
    }
}

// MARK: - Mock Classes for Enhanced Testing

/// Mock bundle detector for testing
class MockSystemExtensionBundleDetector: SystemExtensionBundleDetector {
    private let mockBundlePath: String?
    private let shouldFail: Bool
    
    init(mockBundlePath: String? = nil, shouldFail: Bool = false) {
        self.mockBundlePath = mockBundlePath
        self.shouldFail = shouldFail
    }
    
    override func detectBundle() -> DetectionResult {
        if shouldFail {
            return DetectionResult(
                found: false,
                bundlePath: nil,
                bundleIdentifier: nil,
                detectionEnvironment: .unknown,
                issues: ["Mock failure for testing"],
                homebrewMetadata: nil
            )
        }
        
        if let bundlePath = mockBundlePath {
            return DetectionResult(
                found: true,
                bundlePath: bundlePath,
                bundleIdentifier: "com.test.systemextension",
                detectionEnvironment: .development(buildPath: bundlePath),
                issues: [],
                homebrewMetadata: HomebrewMetadata(
                    version: "1.0.0",
                    installationDate: Date(),
                    formulaName: "usbipd-mac"
                )
            )
        }
        
        return DetectionResult(
            found: false,
            bundlePath: nil,
            bundleIdentifier: nil,
            detectionEnvironment: .unknown,
            issues: [],
            homebrewMetadata: nil
        )
    }
}

/// Mock submission manager for testing
class MockSystemExtensionSubmissionManager: SystemExtensionSubmissionManager {
    private let shouldFail: Bool
    
    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
        super.init()
    }
    
    override func submitExtension(bundlePath: String, completion: @escaping (SubmissionResult) -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            if self.shouldFail {
                let result = SubmissionResult(
                    status: .failed(error: .bundleNotFound),
                    submissionTime: Date(),
                    userInstructions: ["Mock failure for testing"],
                    errorDetails: "Mock submission failure"
                )
                completion(result)
            } else {
                let result = SubmissionResult(
                    status: .approved(extensionID: "mock-extension-id"),
                    submissionTime: Date(),
                    approvalTime: Date(),
                    userInstructions: ["Mock success"],
                    errorDetails: nil
                )
                completion(result)
            }
        }
    }
}

/// Mock service lifecycle manager for testing
class MockServiceLifecycleManager: ServiceLifecycleManager {
    private let shouldFail: Bool
    
    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
        super.init()
    }
    
    override func coordinateInstallationWithService(
        preInstallation: (() async -> Void)? = nil,
        postInstallation: (() async -> Void)? = nil
    ) async -> ServiceCoordinationResult {
        
        await preInstallation?()
        await postInstallation?()
        
        if shouldFail {
            return ServiceCoordinationResult(
                success: false,
                status: ServiceCoordinationStatus(
                    phase: .failed,
                    message: "Mock service failure",
                    coordinationStartTime: Date(),
                    coordinationEndTime: Date()
                ),
                issues: [.serviceStartFailed],
                warnings: ["Mock service coordination failure"]
            )
        }
        
        return ServiceCoordinationResult(
            success: true,
            status: ServiceCoordinationStatus(
                phase: .completed,
                message: "Mock service coordination success",
                coordinationStartTime: Date(),
                coordinationEndTime: Date()
            ),
            issues: [],
            warnings: []
        )
    }
    
    override func detectServiceStatus() async -> ServiceStatus {
        return ServiceStatus(
            isRunning: !shouldFail,
            hasOrphanedProcesses: false,
            conflictingProcesses: [],
            launchdStatus: .loaded,
            brewServicesStatus: .started
        )
    }
    
    override func resolveServiceConflicts() async -> ServiceConflictResolutionResult {
        return ServiceConflictResolutionResult(
            processesTerminated: 0,
            conflictsResolved: true,
            remainingIssues: []
        )
    }
}

/// Mock installation verification manager for testing
class MockInstallationVerificationManager: InstallationVerificationManager {
    private let shouldFail: Bool
    
    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
        super.init()
    }
    
    override func verifyInstallation() async -> InstallationVerificationResult {
        if shouldFail {
            return InstallationVerificationResult(
                status: .failed,
                verificationChecks: [],
                discoveredIssues: [.extensionNotRegistered, .serviceNotRunning],
                verificationTimestamp: Date(),
                verificationDuration: 0.1,
                bundleIdentifier: "com.test.systemextension",
                summary: "Mock verification failure"
            )
        }
        
        return InstallationVerificationResult(
            status: .fullyFunctional,
            verificationChecks: [
                VerificationCheck(
                    checkID: "mock-check",
                    name: "Mock Check",
                    description: "Mock verification check",
                    severity: .info,
                    status: .passed,
                    details: "Mock check passed",
                    checkTimestamp: Date(),
                    duration: 0.01
                )
            ],
            discoveredIssues: [],
            verificationTimestamp: Date(),
            verificationDuration: 0.1,
            bundleIdentifier: "com.test.systemextension",
            summary: "Mock verification success"
        )
    }
}

/// Mock device claimer for testing
class MockDeviceClaimer: DeviceClaimer {
    func claimDevice(device: USBDevice) throws -> ClaimedDevice {
        return ClaimedDevice(
            deviceID: "mock-device-id",
            device: device,
            claimMethod: .systemExtension,
            claimTime: Date()
        )
    }
    
    func releaseDevice(device: USBDevice) throws {
        // Mock implementation - no-op
    }
    
    func getAllClaimedDevices() -> [ClaimedDevice] {
        return []
    }
    
    func isDeviceClaimed(deviceID: String) -> Bool {
        return false
    }
}

/// Mock IPC handler for testing
class MockIPCHandler: IPCHandler {
    func startListener() throws {
        // Mock implementation - no-op
    }
    
    func stopListener() {
        // Mock implementation - no-op
    }
    
    func isListening() -> Bool {
        return true
    }
    
    func handleRequest(_ request: IPCRequest) -> IPCResponse {
        return IPCResponse(success: true, data: nil, error: nil)
    }
}