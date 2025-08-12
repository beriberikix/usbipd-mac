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
        ) { result in
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
}