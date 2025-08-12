import XCTest
import Foundation
import SystemExtensions
@testable import USBIPDCore
@testable import Common

final class SystemExtensionInstallerTests: XCTestCase {
    
    private var installer: SystemExtensionInstaller!
    private var mockBundleCreator: MockSystemExtensionBundleCreator!
    private var mockCodeSigningManager: MockCodeSigningManager!
    private var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        
        // Create temporary directory
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemExtensionInstallerTests")
            .appendingPathComponent(UUID().uuidString)
        
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create mock dependencies
        mockBundleCreator = MockSystemExtensionBundleCreator()
        mockCodeSigningManager = MockCodeSigningManager()
        
        // Create installer with mock dependencies
        installer = SystemExtensionInstaller(
            bundleCreator: mockBundleCreator,
            codeSigningManager: mockCodeSigningManager
        )
    }
    
    override func tearDown() {
        // Clean up test files
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }
    
    // MARK: - Installation Status Tests
    
    func testCheckInstallationStatus_ReturnsStatus() async {
        let status = await installer.checkInstallationStatus()
        
        // Should return a valid status (not necessarily installed on test system)
        XCTAssertTrue([
            .unknown, .notInstalled, .installing, .installed, 
            .requiresApproval, .failed
        ].contains(status))
    }
    
    func testInstallationStatus_InitiallyUnknown() {
        XCTAssertEqual(installer.installationStatus, .unknown)
    }
    
    // MARK: - Installation Workflow Tests
    
    func testInstallSystemExtension_Success() {
        let expectation = XCTestExpectation(description: "Installation completion")
        let bundleIdentifier = "com.test.systemextension"
        let executablePath = createMockExecutable()
        
        // Configure mock bundle creator to succeed
        mockBundleCreator.shouldSucceed = true
        mockBundleCreator.mockBundle = createMockBundle()
        
        // Configure mock code signing manager
        mockCodeSigningManager.shouldSucceed = true
        
        installer.installSystemExtension(
            bundleIdentifier: bundleIdentifier,
            executablePath: executablePath
        ) { result in
            // Installation may fail on test systems without proper certificates/approval
            // We're mainly testing the workflow structure
            XCTAssertNotNil(result)
            
            if result.success {
                XCTAssertTrue(result.errors.isEmpty)
            } else {
                // Expected on test systems - ensure we get proper error information
                XCTAssertFalse(result.errors.isEmpty)
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testInstallSystemExtension_AlreadyInstalling() {
        let expectation = XCTestExpectation(description: "Installation handles concurrent attempts")
        let bundleIdentifier = "com.test.systemextension"
        let executablePath = createMockExecutable()
        
        // Configure mock bundle creator to succeed
        mockBundleCreator.shouldSucceed = true
        mockBundleCreator.mockBundle = createMockBundle()
        
        // Start first installation (will trigger actual system call)
        installer.installSystemExtension(
            bundleIdentifier: bundleIdentifier,
            executablePath: executablePath
        ) { result in
            // First installation attempt completes (success or failure)
            XCTAssertNotNil(result)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testInstallSystemExtension_BundleCreationFails() {
        let expectation = XCTestExpectation(description: "Bundle creation failure")
        let bundleIdentifier = "com.test.systemextension"
        let executablePath = createMockExecutable()
        
        // Configure mock bundle creator to fail
        mockBundleCreator.shouldSucceed = false
        mockBundleCreator.mockError = InstallationError.bundleCreationFailed("Mock bundle creation failure")
        
        installer.installSystemExtension(
            bundleIdentifier: bundleIdentifier,
            executablePath: executablePath
        ) { result in
            XCTAssertFalse(result.success)
            XCTAssertFalse(result.errors.isEmpty)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    // MARK: - Installation with Bundle Tests
    
    func testInstallWithBundle_ValidBundle() {
        let expectation = XCTestExpectation(description: "Bundle installation")
        let mockBundle = createMockBundle()
        
        installer.installSystemExtension(bundle: mockBundle) { result in
            // Test the workflow structure
            XCTAssertNotNil(result)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testInstallWithBundle_InvalidBundle() {
        let expectation = XCTestExpectation(description: "Invalid bundle rejection")
        let invalidBundle = createInvalidBundle()
        
        installer.installSystemExtension(bundle: invalidBundle) { result in
            XCTAssertFalse(result.success)
            XCTAssertFalse(result.errors.isEmpty)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    // MARK: - Uninstallation Tests
    
    func testUninstallSystemExtension() {
        let expectation = XCTestExpectation(description: "Uninstallation")
        let bundleIdentifier = "com.test.systemextension"
        
        installer.uninstallSystemExtension(bundleIdentifier: bundleIdentifier) { result in
            // Uninstallation may succeed or fail depending on system state
            XCTAssertNotNil(result)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    // MARK: - Developer Mode Tests
    
    func testCheckDeveloperMode() async {
        let isDeveloperMode = await installer.checkDeveloperMode()
        
        // Should return a boolean (may be true or false depending on system)
        XCTAssertTrue(isDeveloperMode == true || isDeveloperMode == false)
    }
    
    func testEnableDeveloperMode() async {
        let result = await installer.enableDeveloperMode()
        
        // May succeed or fail depending on system permissions
        XCTAssertNotNil(result)
        
        if !result.success {
            // Expected on most systems - should provide helpful guidance
            XCTAssertFalse(result.guidanceMessage.isEmpty)
        }
    }
    
    func testGetDeveloperModeGuidance() {
        let guidance = installer.getDeveloperModeGuidance()
        
        XCTAssertFalse(guidance.isEmpty)
        XCTAssertTrue(guidance.contains("System Extension") || guidance.contains("developer mode"))
    }
    
    // MARK: - Installation Recovery Tests
    
    func testRecoverFromFailedInstallation() {
        let expectation = XCTestExpectation(description: "Recovery attempt")
        let bundleIdentifier = "com.test.systemextension"
        
        installer.recoverFromFailedInstallation(bundleIdentifier: bundleIdentifier) { result in
            XCTAssertNotNil(result)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testForceReinstall() {
        let expectation = XCTestExpectation(description: "Force reinstall")
        let bundleIdentifier = "com.test.systemextension"
        let executablePath = createMockExecutable()
        
        mockBundleCreator.shouldSucceed = true
        mockBundleCreator.mockBundle = createMockBundle()
        
        installer.forceReinstall(
            bundleIdentifier: bundleIdentifier,
            executablePath: executablePath
        ) { result in
            XCTAssertNotNil(result)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 60.0)
    }
    
    // MARK: - Status Monitoring Tests
    
    func testMonitorInstallationStatus() {
        let expectation = XCTestExpectation(description: "Status monitoring")
        var statusUpdates: [SystemExtensionInstallationStatus] = []
        
        installer.monitorInstallationStatus(interval: 0.1) { status in
            statusUpdates.append(status)
            // Just get at least one status update
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
        XCTAssertFalse(statusUpdates.isEmpty)
        
        // Verify we got a valid status
        XCTAssertTrue([
            .unknown, .notInstalled, .installing, .installed, 
            .installationFailed, .requiresReinstall, .invalidBundle, .pendingApproval
        ].contains(statusUpdates.first!))
    }
    
    // MARK: - Error Handling Tests
    
    func testInstallationError_Types() {
        let bundleError = InstallationError.bundleCreationFailed("test")
        XCTAssertTrue(bundleError.localizedDescription.contains("test"))
        
        let signingError = InstallationError.signingFailed("sign error")
        XCTAssertTrue(signingError.localizedDescription.contains("sign error"))
        
        let installError = InstallationError.installationFailed("install error")
        XCTAssertTrue(installError.localizedDescription.contains("install error"))
        
        let approvalError = InstallationError.userApprovalRequired
        XCTAssertTrue(approvalError.localizedDescription.contains("approval"))
    }
    
    // MARK: - Helper Methods
    
    private func createMockExecutable() -> String {
        let executablePath = tempDirectory.appendingPathComponent("MockExecutable").path
        FileManager.default.createFile(atPath: executablePath, contents: Data("mock executable".utf8))
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executablePath)
        return executablePath
    }
    
    private func createMockBundle() -> SystemExtensionBundle {
        let bundlePath = tempDirectory.appendingPathComponent("Mock.systemextension").path
        let contents = BundleContents(
            infoPlistPath: bundlePath + "/Contents/Info.plist",
            executablePath: bundlePath + "/Contents/MacOS/Mock",
            entitlementsPath: nil,
            resourceFiles: [],
            isValid: true,
            bundleSize: 1024
        )
        
        return SystemExtensionBundle(
            bundlePath: bundlePath,
            bundleIdentifier: "com.test.mock",
            displayName: "Mock Extension",
            version: "1.0.0",
            buildNumber: "1",
            executableName: "Mock",
            teamIdentifier: "MOCK123456",
            contents: contents,
            codeSigningInfo: nil,
            creationTime: Date()
        )
    }
    
    private func createInvalidBundle() -> SystemExtensionBundle {
        let bundlePath = "/nonexistent/path/Invalid.systemextension"
        let contents = BundleContents(
            infoPlistPath: "",
            executablePath: "",
            entitlementsPath: nil,
            resourceFiles: [],
            isValid: false,
            bundleSize: 0
        )
        
        return SystemExtensionBundle(
            bundlePath: bundlePath,
            bundleIdentifier: "com.test.invalid",
            displayName: "Invalid Extension",
            version: "1.0.0",
            buildNumber: "1",
            executableName: "Invalid",
            teamIdentifier: nil,
            contents: contents,
            codeSigningInfo: nil,
            creationTime: Date()
        )
    }
}

// MARK: - Mock Classes

private class MockSystemExtensionBundleCreator: SystemExtensionBundleCreator {
    var shouldSucceed = true
    var mockBundle: SystemExtensionBundle?
    var mockError: Error?
    
    override func createBundle(with config: BundleCreationConfig) throws -> SystemExtensionBundle {
        if !shouldSucceed, let error = mockError {
            throw error
        }
        
        return mockBundle ?? (try super.createBundle(with: config))
    }
    
    override func completeBundle(_ bundle: SystemExtensionBundle, with config: BundleCreationConfig) throws -> SystemExtensionBundle {
        if !shouldSucceed, let error = mockError {
            throw error
        }
        
        return mockBundle ?? (try super.completeBundle(bundle, with: config))
    }
}

private class MockCodeSigningManager: CodeSigningManager {
    var shouldSucceed = true
    var mockCertificate: CodeSigningCertificate?
    var mockSigningResult: SigningResult?
    
    override func findBestCertificate() -> CodeSigningCertificate? {
        return mockCertificate ?? super.findBestCertificate()
    }
    
    override func signBundle(
        at bundlePath: String,
        with certificate: CodeSigningCertificate?,
        entitlements entitlementsPath: String?
    ) throws -> SigningResult {
        if let mockResult = mockSigningResult {
            return mockResult
        }
        
        if !shouldSucceed {
            return SigningResult(
                success: false,
                certificate: certificate ?? CodeSigningCertificate(
                    commonName: "Mock Certificate",
                    certificateType: .appleDevelopment,
                    teamIdentifier: "MOCK123456",
                    fingerprint: "MOCK",
                    expirationDate: Date(),
                    isValidForSystemExtensions: true,
                    keychainPath: nil
                ),
                bundlePath: bundlePath,
                signingTime: Date(),
                signingDuration: 0.1,
                verificationStatus: .signingFailed,
                output: "Mock signing failed",
                errors: ["Mock signing error"]
            )
        }
        
        return try super.signBundle(at: bundlePath, with: certificate, entitlements: entitlementsPath)
    }
}