import XCTest
import Foundation
@testable import USBIPDCore
@testable import Common

final class InstallationVerificationManagerTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol
    
    var environmentConfig: TestEnvironmentConfig {
        return TestEnvironmentDetector.createConfigurationForCurrentEnvironment()
    }
    
    // MARK: - Properties
    
    var manager: InstallationVerificationManager!
    let testBundleIdentifier = "com.github.usbipd-mac.systemextension"
    var tempDirectory: URL!
    var mockSystemExtensionsCtlOutput: String = ""
    
    override func setUp() {
        super.setUp()
        
        // Create temporary directory for test bundles
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallationVerificationManagerTests")
            .appendingPathComponent(UUID().uuidString)
        
        try! FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        
        manager = InstallationVerificationManager(
            bundleIdentifier: testBundleIdentifier,
            expectedPaths: [tempDirectory.path]
        )
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        
        manager = nil
        tempDirectory = nil
        super.tearDown()
    }
    
    // MARK: - Basic Tests
    
    func testInstallationVerificationManager_Initialization() {
        XCTAssertNotNil(manager, "Manager should initialize successfully")
        
        let customManager = InstallationVerificationManager(
            bundleIdentifier: "com.test.extension",
            expectedPaths: ["/test/path/"]
        )
        XCTAssertNotNil(customManager, "Manager should initialize with custom parameters")
    }
    
    func testExtensionState_FromString() {
        XCTAssertEqual(ExtensionState.from(string: "activated enabled"), .activated)
        XCTAssertEqual(ExtensionState.from(string: "waiting for user approval"), .waitingForUserApproval)
        XCTAssertEqual(ExtensionState.from(string: "terminated"), .terminated)
        XCTAssertEqual(ExtensionState.from(string: "enabled"), .enabled)
        XCTAssertEqual(ExtensionState.from(string: "unknown state"), .unknown)
        XCTAssertEqual(ExtensionState.from(string: "invalid"), .unknown)
    }
    
    func testSystemExtensionsCtlError_Description() {
        let error = SystemExtensionsCtlError.commandFailed(
            exitCode: 1,
            output: "Permission denied",
            arguments: ["list"]
        )
        
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("exit code: 1"))
        XCTAssertTrue(description.contains("Permission denied"))
        XCTAssertTrue(description.contains("list"))
    }
    
    // MARK: - Data Structure Tests
    
    func testVerificationInstallationStatus_Properties() {
        XCTAssertEqual(VerificationInstallationStatus.fullyFunctional.description, "Fully Functional")
        XCTAssertEqual(VerificationInstallationStatus.partiallyFunctional.description, "Partially Functional")
        XCTAssertEqual(VerificationInstallationStatus.problematic.description, "Problematic")
        XCTAssertEqual(VerificationInstallationStatus.failed.description, "Failed")
        XCTAssertEqual(VerificationInstallationStatus.unknown.description, "Unknown")
        
        XCTAssertTrue(VerificationInstallationStatus.fullyFunctional.isOperational)
        XCTAssertTrue(VerificationInstallationStatus.partiallyFunctional.isOperational)
        XCTAssertFalse(VerificationInstallationStatus.problematic.isOperational)
        XCTAssertFalse(VerificationInstallationStatus.failed.isOperational)
        XCTAssertFalse(VerificationInstallationStatus.unknown.isOperational)
    }
    
    func testCheckSeverity_Comparison() {
        XCTAssertLessThan(CheckSeverity.info, CheckSeverity.warning)
        XCTAssertLessThan(CheckSeverity.warning, CheckSeverity.error)
        XCTAssertLessThan(CheckSeverity.error, CheckSeverity.critical)
        
        XCTAssertEqual(CheckSeverity.info.description, "Information")
        XCTAssertEqual(CheckSeverity.warning.description, "Warning")
        XCTAssertEqual(CheckSeverity.error.description, "Error")
        XCTAssertEqual(CheckSeverity.critical.description, "Critical")
    }
    
    func testVerificationInstallationIssue_Properties() {
        let bundleNotFoundIssue = VerificationInstallationIssue.bundleNotFound
        XCTAssertEqual(bundleNotFoundIssue.category, .bundle)
        XCTAssertEqual(bundleNotFoundIssue.severity, .critical)
        XCTAssertNotNil(bundleNotFoundIssue.remediation)
        XCTAssertFalse(bundleNotFoundIssue.description.isEmpty)
        XCTAssertFalse(bundleNotFoundIssue.suggestedActions.isEmpty)
        
        let serviceIssue = VerificationInstallationIssue.serviceNotRunning
        XCTAssertEqual(serviceIssue.category, .service)
        XCTAssertEqual(serviceIssue.severity, .error)
        XCTAssertNotNil(serviceIssue.remediation)
        XCTAssertFalse(serviceIssue.description.isEmpty)
    }
    
    func testVerificationCheck_Creation() {
        let check = VerificationCheck(
            checkID: "test_check",
            checkName: "Test Check",
            passed: true,
            message: "Test message",
            severity: .info,
            details: "Test details",
            issues: []
        )
        
        XCTAssertEqual(check.checkID, "test_check")
        XCTAssertEqual(check.checkName, "Test Check")
        XCTAssertTrue(check.passed)
        XCTAssertEqual(check.message, "Test message")
        XCTAssertEqual(check.severity, .info)
        XCTAssertEqual(check.details, "Test details")
        XCTAssertTrue(check.issues.isEmpty)
    }
    
    func testDetectedInstallationIssue_Creation() {
        let issue = DetectedInstallationIssue(
            issue: .bundleNotFound,
            severity: .critical,
            description: "Test description",
            detectionMethod: "Test method",
            affectedComponents: ["Component1", "Component2"],
            suggestedActions: ["Action1", "Action2"]
        )
        
        XCTAssertEqual(issue.issue, .bundleNotFound)
        XCTAssertEqual(issue.severity, .critical)
        XCTAssertEqual(issue.description, "Test description")
        XCTAssertEqual(issue.detectionMethod, "Test method")
        XCTAssertEqual(issue.affectedComponents, ["Component1", "Component2"])
        XCTAssertEqual(issue.suggestedActions, ["Action1", "Action2"])
        XCTAssertTrue(issue.contextData.isEmpty)
    }
    
    // MARK: - SystemExtensionsCtl Output Parsing Tests
    
    func testParseSystemExtensionStatus_FullyFunctional() {
        let output = """
        Loaded system extensions:
        * ABC123 com.github.usbipd-mac.systemextension (1.0.0) [activated enabled]
        """
        
        let status = manager.parseSystemExtensionStatus(output)
        
        XCTAssertTrue(status.isRegistered, "Extension should be registered")
        XCTAssertTrue(status.isEnabled, "Extension should be enabled")
        XCTAssertTrue(status.isActive, "Extension should be active")
        XCTAssertEqual(status.state, .activated)
        XCTAssertEqual(status.teamIdentifier, "ABC123")
        XCTAssertEqual(status.version, "1.0.0")
        XCTAssertEqual(status.allExtensions.count, 1)
    }
    
    func testParseSystemExtensionStatus_WaitingForApproval() {
        let output = """
        Loaded system extensions:
        * ABC123 com.github.usbipd-mac.systemextension (1.0.0) [waiting for user approval]
        """
        
        let status = manager.parseSystemExtensionStatus(output)
        
        XCTAssertTrue(status.isRegistered, "Extension should be registered")
        XCTAssertFalse(status.isEnabled, "Extension should not be enabled")
        XCTAssertFalse(status.isActive, "Extension should not be active")
        XCTAssertEqual(status.state, .waitingForUserApproval)
    }
    
    func testParseSystemExtensionStatus_NotRegistered() {
        let output = """
        Loaded system extensions:
        (none)
        """
        
        let status = manager.parseSystemExtensionStatus(output)
        
        XCTAssertFalse(status.isRegistered, "Extension should not be registered")
        XCTAssertFalse(status.isEnabled, "Extension should not be enabled")
        XCTAssertFalse(status.isActive, "Extension should not be active")
        XCTAssertEqual(status.state, .unknown)
        XCTAssertNil(status.teamIdentifier)
        XCTAssertNil(status.version)
        XCTAssertTrue(status.allExtensions.isEmpty)
    }
    
    func testParseSystemExtensionStatus_Terminated() {
        let output = """
        Loaded system extensions:
        * ABC123 com.github.usbipd-mac.systemextension (1.0.0) [terminated]
        """
        
        let status = manager.parseSystemExtensionStatus(output)
        
        XCTAssertTrue(status.isRegistered, "Extension should be registered")
        XCTAssertFalse(status.isEnabled, "Extension should not be enabled")
        XCTAssertFalse(status.isActive, "Extension should not be active")
        XCTAssertEqual(status.state, .terminated)
    }
    
    func testParseExtensionLine_ValidEntry() {
        let testLine = "* ABC123 com.github.usbipd-mac.systemextension (1.0.0) [activated enabled]"
        
        let parsed = manager.parseExtensionLine(testLine)
        
        XCTAssertNotNil(parsed, "Should parse valid extension line")
        XCTAssertEqual(parsed?.bundleIdentifier, "com.github.usbipd-mac.systemextension")
        XCTAssertEqual(parsed?.teamIdentifier, "ABC123")
        XCTAssertEqual(parsed?.version, "1.0.0")
        XCTAssertEqual(parsed?.state, .activated)
        XCTAssertEqual(parsed?.stateString, "activated enabled")
        XCTAssertTrue(parsed?.isEnabled ?? false)
        XCTAssertTrue(parsed?.isActive ?? false)
    }
    
    func testParseExtensionLine_InvalidEntry() {
        let testLines = [
            "Invalid line format",
            "",
            "  ",
            "Loaded system extensions:"
        ]
        
        for line in testLines {
            let parsed = manager.parseExtensionLine(line)
            XCTAssertNil(parsed, "Should not parse invalid line: \(line)")
        }
    }
    
    func testParseExtensionLine_MultipleStates() {
        let testCases = [
            ("* ABC123 com.test.ext (1.0) [enabled]", ExtensionState.enabled, true, false),
            ("* ABC123 com.test.ext (1.0) [activated]", ExtensionState.activated, true, true),
            ("* ABC123 com.test.ext (1.0) [waiting for user approval]", ExtensionState.waitingForUserApproval, false, false),
            ("* ABC123 com.test.ext (1.0) [terminated]", ExtensionState.terminated, false, false)
        ]
        
        for (line, expectedState, expectedEnabled, expectedActive) in testCases {
            let parsed = manager.parseExtensionLine(line)
            XCTAssertNotNil(parsed, "Should parse line: \(line)")
            XCTAssertEqual(parsed?.state, expectedState, "State mismatch for: \(line)")
            XCTAssertEqual(parsed?.isEnabled, expectedEnabled, "Enabled mismatch for: \(line)")
            XCTAssertEqual(parsed?.isActive, expectedActive, "Active mismatch for: \(line)")
        }
    }
    
    // MARK: - Installation Status Verification Tests
    
    func testVerifyInstallation_Success() async {
        // Create test bundle structure
        createTestSystemExtensionBundle()
        
        let result = await manager.verifyInstallation()
        
        XCTAssertNotNil(result, "Verification result should not be nil")
        XCTAssertEqual(result.bundleIdentifier, testBundleIdentifier)
        XCTAssertFalse(result.verificationChecks.isEmpty, "Should have verification checks")
        XCTAssertNotNil(result.summary, "Should have summary")
        XCTAssertGreaterThan(result.verificationDuration, 0, "Should have positive duration")
    }
    
    func testVerifyInstallation_BundleNotFound() async {
        // Don't create bundle - test when bundle is missing
        let result = await manager.verifyInstallation()
        
        // Should detect bundle not found issue
        let bundleCheck = result.verificationChecks.first { $0.checkID == "bundle_integrity" }
        XCTAssertNotNil(bundleCheck, "Should have bundle integrity check")
        XCTAssertFalse(bundleCheck!.passed, "Bundle check should fail when bundle not found")
        XCTAssertTrue(result.discoveredIssues.contains(.bundleNotFound), "Should detect bundle not found issue")
    }
    
    func testVerifyInstallation_MultipleChecks() async {
        let result = await manager.verifyInstallation()
        
        // Verify all expected check types are present
        let expectedCheckIDs = [
            "registry_status",
            "bundle_integrity", 
            "runtime_status",
            "permissions_entitlements",
            "service_integration"
        ]
        
        let actualCheckIDs = Set(result.verificationChecks.map { $0.checkID })
        
        for expectedID in expectedCheckIDs {
            XCTAssertTrue(actualCheckIDs.contains(expectedID), 
                         "Missing expected check ID: \(expectedID)")
        }
    }
    
    // MARK: - Diagnostic Report Generation Tests
    
    func testGenerateDiagnosticReport() async {
        let report = await manager.generateDiagnosticReport()
        
        XCTAssertNotNil(report, "Diagnostic report should not be nil")
        XCTAssertNotNil(report.verificationResult, "Should include verification result")
        XCTAssertNotNil(report.systemInformation, "Should include system information")
        XCTAssertNotNil(report.configurationAnalysis, "Should include configuration analysis")
        XCTAssertEqual(report.reportVersion, "1.0", "Should have correct report version")
        XCTAssertFalse(report.recommendations.isEmpty, "Should have recommendations")
    }
    
    func testGenerateDiagnosticReport_SystemInformation() async {
        let report = await manager.generateDiagnosticReport()
        let sysInfo = report.systemInformation
        
        XCTAssertFalse(sysInfo.osVersion.isEmpty, "Should have OS version")
        XCTAssertFalse(sysInfo.architecture.isEmpty, "Should have architecture")
        XCTAssertFalse(sysInfo.homebrewPrefix.isEmpty, "Should have Homebrew prefix")
    }
    
    func testGenerateDiagnosticReport_ConfigurationAnalysis() async {
        let report = await manager.generateDiagnosticReport()
        let config = report.configurationAnalysis
        
        // These should be determined by the system
        XCTAssertNotNil(config.homebrewInstalled, "Should check Homebrew installation")
        XCTAssertNotNil(config.xcodeInstalled, "Should check Xcode installation")
        XCTAssertNotNil(config.configurationValid, "Should have overall validity")
    }
    
    // MARK: - Installation Issue Detection Tests
    
    func testDetectInstallationIssues() async {
        let issues = await manager.detectInstallationIssues()
        
        XCTAssertNotNil(issues, "Issues array should not be nil")
        // Should detect at least bundle not found issue since we didn't create a bundle
        XCTAssertFalse(issues.isEmpty, "Should detect some issues")
        
        // Verify issue structure
        for issue in issues {
            XCTAssertFalse(issue.description.isEmpty, "Issue should have description")
            XCTAssertFalse(issue.detectionMethod.isEmpty, "Issue should have detection method")
            XCTAssertFalse(issue.affectedComponents.isEmpty, "Issue should have affected components")
            XCTAssertFalse(issue.suggestedActions.isEmpty, "Issue should have suggested actions")
        }
    }
    
    func testDetectInstallationIssues_BundleNotFound() async {
        let issues = await manager.detectInstallationIssues()
        
        let bundleIssues = issues.filter { $0.issue == .bundleNotFound }
        XCTAssertFalse(bundleIssues.isEmpty, "Should detect bundle not found issue")
        
        let bundleIssue = bundleIssues.first!
        XCTAssertEqual(bundleIssue.severity, .critical, "Bundle not found should be critical")
        XCTAssertTrue(bundleIssue.description.contains("bundle not found"), 
                     "Description should mention bundle not found")
        XCTAssertTrue(bundleIssue.suggestedActions.contains { $0.contains("Reinstall") },
                     "Should suggest reinstallation")
    }
    
    // MARK: - Functionality Verification Tests
    
    func testVerifySystemExtensionFunctionality() async {
        let result = await manager.verifySystemExtensionFunctionality()
        
        XCTAssertNotNil(result, "Functionality result should not be nil")
        XCTAssertFalse(result.functionalityChecks.isEmpty, "Should have functionality checks")
        
        // Verify expected functionality check types
        let checkNames = Set(result.functionalityChecks.map { $0.checkName })
        let expectedChecks = [
            "Extension Loading",
            "Extension Communication", 
            "Device Interaction",
            "Network Capabilities"
        ]
        
        for expectedCheck in expectedChecks {
            XCTAssertTrue(checkNames.contains(expectedCheck), 
                         "Missing expected functionality check: \(expectedCheck)")
        }
    }
    
    func testVerifySystemExtensionFunctionality_AllFailed() async {
        // Since this is a mock/test environment, all functionality checks should fail
        let result = await manager.verifySystemExtensionFunctionality()
        
        XCTAssertFalse(result.isFunctional, "Extension should not be functional in test environment")
        
        // All functionality checks should fail in test environment
        for check in result.functionalityChecks {
            XCTAssertFalse(check.passed, "Functionality check should fail in test: \(check.checkName)")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testSystemExtensionsCtlError() {
        let error = SystemExtensionsCtlError.commandFailed(
            exitCode: 2,
            output: "systemextensionsctl: error: Permission denied",
            arguments: ["list"]
        )
        
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("exit code: 2"))
        XCTAssertTrue(description.contains("Permission denied"))
        XCTAssertTrue(description.contains("list"))
    }
    
    // MARK: - Integration Tests
    
    func testCompleteVerificationWorkflow() async {
        // Create test bundle
        createTestSystemExtensionBundle()
        
        // Run full verification
        let verificationResult = await manager.verifyInstallation()
        
        // Generate diagnostic report
        let diagnosticReport = await manager.generateDiagnosticReport()
        
        // Detect issues
        let detectedIssues = await manager.detectInstallationIssues()
        
        // Verify functionality
        let functionalityResult = await manager.verifySystemExtensionFunctionality()
        
        // Ensure all results are consistent
        XCTAssertEqual(verificationResult.bundleIdentifier, testBundleIdentifier)
        XCTAssertEqual(diagnosticReport.verificationResult.bundleIdentifier, testBundleIdentifier)
        
        // Bundle should be found with test bundle created
        let bundleCheck = verificationResult.verificationChecks.first { $0.checkID == "bundle_integrity" }
        XCTAssertNotNil(bundleCheck, "Should have bundle integrity check")
        
        // All components should be properly initialized
        XCTAssertNotNil(verificationResult)
        XCTAssertNotNil(diagnosticReport)
        XCTAssertNotNil(detectedIssues)
        XCTAssertNotNil(functionalityResult)
    }
    
    // MARK: - Performance Tests
    
    func testVerificationPerformance() {
        measure {
            let expectation = expectation(description: "Verification completion")
            
            Task {
                let _ = await manager.verifyInstallation()
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5.0)
        }
    }
    
    func testDiagnosticReportPerformance() {
        measure {
            let expectation = expectation(description: "Diagnostic report completion")
            
            Task {
                let _ = await manager.generateDiagnosticReport()
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 10.0)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestSystemExtensionBundle() {
        let bundlePath = tempDirectory
            .appendingPathComponent("\(testBundleIdentifier).systemextension")
        let contentsPath = bundlePath.appendingPathComponent("Contents")
        
        try! FileManager.default.createDirectory(
            at: contentsPath,
            withIntermediateDirectories: true
        )
        
        // Create Info.plist
        let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>\(testBundleIdentifier)</string>
            <key>CFBundleVersion</key>
            <string>1.0.0</string>
            <key>NSSystemExtensionUsageDescription</key>
            <string>Test System Extension</string>
        </dict>
        </plist>
        """
        
        try! plistContent.write(to: infoPlistPath, atomically: true, encoding: .utf8)
        
        // Create executable placeholder
        let executablePath = bundlePath.appendingPathComponent(testBundleIdentifier)
        try! "#!/bin/bash\necho 'Test executable'".write(
            to: executablePath,
            atomically: true,
            encoding: .utf8
        )
        
        // Make executable
        try! FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executablePath.path
        )
    }
    
    private func createCorruptedBundle() {
        let bundlePath = tempDirectory
            .appendingPathComponent("\(testBundleIdentifier).systemextension")
        
        try! FileManager.default.createDirectory(
            at: bundlePath,
            withIntermediateDirectories: true
        )
        
        // Create incomplete/corrupted bundle (missing Contents directory)
        let corruptedFile = bundlePath.appendingPathComponent("corrupted")
        try! "corrupted".write(to: corruptedFile, atomically: true, encoding: .utf8)
    }
}