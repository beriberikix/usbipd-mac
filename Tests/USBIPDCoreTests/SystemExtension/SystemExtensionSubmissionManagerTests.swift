// SystemExtensionSubmissionManagerTests.swift
// Tests for System Extension submission manager

import XCTest
import SystemExtensions
@testable import USBIPDCore

final class SystemExtensionSubmissionManagerTests: XCTestCase {
    
    // MARK: - Properties
    
    var submissionManager: SystemExtensionSubmissionManager!
    var mockFileManager: MockFileManager!
    var tempDirectory: URL!
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        // Create temporary directory for test bundles
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemExtensionSubmissionManagerTests")
            .appendingPathComponent(UUID().uuidString)
        
        try! FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        
        // Setup mock file manager
        mockFileManager = MockFileManager()
        
        // Initialize submission manager
        submissionManager = SystemExtensionSubmissionManager()
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        
        submissionManager = nil
        mockFileManager = nil
        tempDirectory = nil
        
        super.tearDown()
    }
    
    // MARK: - Successful Submission Workflow Tests
    
    func testSuccessfulSubmissionWorkflow() throws {
        // Create test bundle with valid Info.plist
        let bundlePath = createTestBundle(
            bundleIdentifier: "com.test.SystemExtension",
            version: "1.0.0"
        )
        
        let expectation = expectation(description: "Submission completion")
        var completionResult: SubmissionResult?
        
        // Test submission
        submissionManager.submitExtension(bundlePath: bundlePath) { result in
            completionResult = result
            expectation.fulfill()
        }
        
        // Verify initial status
        XCTAssertEqual(submissionManager.submissionStatus, .submitting)
        
        // Simulate successful completion via delegate
        let mockRequest = MockOSSystemExtensionRequest()
        submissionManager.request(mockRequest, didFinishWithResult: .completed)
        
        waitForExpectations(timeout: 1.0)
        
        // Verify final result
        XCTAssertNotNil(completionResult)
        if case .approved(let extensionID) = completionResult!.status {
            XCTAssertEqual(extensionID, "com.test.SystemExtension")
        } else {
            XCTFail("Expected approved status, got: \(completionResult!.status)")
        }
        
        XCTAssertTrue(completionResult!.userInstructions.contains("System Extension is now active and ready to use"))
        XCTAssertNil(completionResult!.errorDetails)
    }
    
    func testSubmissionWithRebootRequired() throws {
        let bundlePath = createTestBundle(
            bundleIdentifier: "com.test.SystemExtension",
            version: "1.0.0"
        )
        
        let expectation = expectation(description: "Submission completion")
        var completionResult: SubmissionResult?
        
        submissionManager.submitExtension(bundlePath: bundlePath) { result in
            completionResult = result
            expectation.fulfill()
        }
        
        // Simulate reboot required completion
        let mockRequest = MockOSSystemExtensionRequest()
        submissionManager.request(mockRequest, didFinishWithResult: .willCompleteAfterReboot)
        
        waitForExpectations(timeout: 1.0)
        
        // Verify reboot required status
        XCTAssertNotNil(completionResult)
        if case .requiresUserAction(let instructions) = completionResult!.status {
            XCTAssertEqual(instructions, "System will complete installation after reboot")
        } else {
            XCTFail("Expected requiresUserAction status, got: \(completionResult!.status)")
        }
        
        XCTAssertTrue(completionResult!.userInstructions.contains("Restart your system to finish installation"))
    }
    
    func testUserApprovalRequired() throws {
        let bundlePath = createTestBundle(
            bundleIdentifier: "com.test.SystemExtension",
            version: "1.0.0"
        )
        
        submissionManager.submitExtension(bundlePath: bundlePath) { _ in }
        
        // Simulate user approval required
        let mockRequest = MockOSSystemExtensionRequest()
        submissionManager.requestNeedsUserApproval(mockRequest)
        
        // Verify status change
        if case .pendingApproval = submissionManager.submissionStatus {
            // Expected
        } else {
            XCTFail("Expected pendingApproval status, got: \(submissionManager.submissionStatus)")
        }
    }
    
    // MARK: - OSSystemExtensionError Scenario Tests
    
    func testSubmissionErrorUnknown() {
        testSubmissionError(
            errorCode: .unknown,
            expectedError: .unknownError,
            expectedInstructions: ["Check system logs for more details", "Ensure System Extension is properly signed"]
        )
    }
    
    func testSubmissionErrorMissingEntitlement() {
        testSubmissionError(
            errorCode: .missingEntitlement,
            expectedError: .missingEntitlement,
            expectedInstructions: [
                "Ensure System Extension has proper entitlements",
                "Check code signing configuration",
                "Verify bundle is built for distribution"
            ]
        )
    }
    
    func testSubmissionErrorAuthorizationRequired() {
        testSubmissionError(
            errorCode: .authorizationRequired,
            expectedError: .authorizationRequired,
            expectedInstructions: [
                "User authorization required",
                "Check System Preferences > Security & Privacy",
                "Approve the System Extension if prompted"
            ]
        )
    }
    
    func testSubmissionErrorRequestCanceled() {
        testSubmissionError(
            errorCode: .requestCanceled,
            expectedError: .requestCanceled,
            expectedInstructions: ["Installation was canceled", "Try installation again if needed"]
        )
    }
    
    func testSubmissionErrorRequestSuperseded() {
        testSubmissionError(
            errorCode: .requestSuperseded,
            expectedError: .requestSuperseded,
            expectedInstructions: ["Request was superseded by newer request", "This is usually not an error"]
        )
    }
    
    func testSubmissionErrorExtensionNotFound() {
        testSubmissionError(
            errorCode: .extensionNotFound,
            expectedError: .extensionNotFound,
            expectedInstructions: [
                "System Extension bundle not found",
                "Verify bundle path is correct",
                "Ensure bundle is properly built"
            ]
        )
    }
    
    func testSubmissionErrorDuplicateExtensionIdentifier() {
        testSubmissionError(
            errorCode: .duplicateExtensionIdentifer,
            expectedError: .duplicateExtensionIdentifier,
            expectedInstructions: [
                "Extension with this identifier already exists",
                "Uninstall existing extension first",
                "Use unique bundle identifier"
            ]
        )
    }
    
    func testSubmissionErrorUnsupportedParentBundleLocation() {
        testSubmissionError(
            errorCode: .unsupportedParentBundleLocation,
            expectedError: .invalidBundle,
            expectedInstructions: [
                "System Extension is in unsupported location",
                "Move extension to supported location",
                "Check bundle packaging"
            ]
        )
    }
    
    func testSubmissionErrorExtensionMissingIdentifier() {
        testSubmissionError(
            errorCode: .extensionMissingIdentifier,
            expectedError: .invalidBundle,
            expectedInstructions: [
                "System Extension missing bundle identifier",
                "Add CFBundleIdentifier to Info.plist",
                "Rebuild the extension"
            ]
        )
    }
    
    func testSubmissionErrorCodeSignatureInvalid() {
        testSubmissionError(
            errorCode: .codeSignatureInvalid,
            expectedError: .invalidSignature,
            expectedInstructions: [
                "System Extension signature is invalid",
                "Re-sign with valid certificate",
                "Check certificate validity"
            ]
        )
    }
    
    func testSubmissionErrorValidationFailed() {
        testSubmissionError(
            errorCode: .validationFailed,
            expectedError: .invalidBundle,
            expectedInstructions: [
                "System Extension validation failed",
                "Check bundle structure",
                "Verify all required components"
            ]
        )
    }
    
    func testSubmissionErrorForbiddenBySystemPolicy() {
        testSubmissionError(
            errorCode: .forbiddenBySystemPolicy,
            expectedError: .authorizationRequired,
            expectedInstructions: [
                "Installation forbidden by system policy",
                "Check system security settings",
                "May require admin approval"
            ]
        )
    }
    
    // MARK: - Bundle Validation Tests
    
    func testSubmissionBundleNotFound() {
        let nonExistentPath = "/path/that/does/not/exist"
        
        let expectation = expectation(description: "Submission completion")
        var completionResult: SubmissionResult?
        
        submissionManager.submitExtension(bundlePath: nonExistentPath) { result in
            completionResult = result
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
        
        // Verify bundle not found error
        XCTAssertNotNil(completionResult)
        if case .failed(let error) = completionResult!.status {
            XCTAssertEqual(error, .bundleNotFound)
        } else {
            XCTFail("Expected failed status with bundleNotFound error")
        }
        
        XCTAssertTrue(completionResult!.userInstructions.contains("Verify System Extension bundle exists"))
        XCTAssertTrue(completionResult!.errorDetails!.contains(nonExistentPath))
    }
    
    func testSubmissionInvalidBundle() throws {
        // Create bundle without Info.plist
        let bundlePath = tempDirectory.appendingPathComponent("InvalidBundle.appex").path
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
        
        let expectation = expectation(description: "Submission completion")
        var completionResult: SubmissionResult?
        
        submissionManager.submitExtension(bundlePath: bundlePath) { result in
            completionResult = result
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
        
        // Verify invalid bundle error
        XCTAssertNotNil(completionResult)
        if case .failed(let error) = completionResult!.status {
            XCTAssertEqual(error, .invalidBundle)
        } else {
            XCTFail("Expected failed status with invalidBundle error")
        }
        
        XCTAssertTrue(completionResult!.userInstructions.contains("Ensure bundle has valid Info.plist with CFBundleIdentifier"))
    }
    
    func testSubmissionRequestInProgress() throws {
        let bundlePath = createTestBundle(
            bundleIdentifier: "com.test.SystemExtension",
            version: "1.0.0"
        )
        
        // Start first submission
        submissionManager.submitExtension(bundlePath: bundlePath) { _ in }
        
        // Try to start second submission
        let expectation = expectation(description: "Second submission completion")
        var completionResult: SubmissionResult?
        
        submissionManager.submitExtension(bundlePath: bundlePath) { result in
            completionResult = result
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
        
        // Verify request in progress error
        XCTAssertNotNil(completionResult)
        if case .failed(let error) = completionResult!.status {
            XCTAssertEqual(error, .requestInProgress)
        } else {
            XCTFail("Expected failed status with requestInProgress error")
        }
        
        XCTAssertTrue(completionResult!.userInstructions.contains("Wait for current submission to complete"))
    }
    
    // MARK: - Approval Monitoring Tests
    
    func testApprovalStatusMonitoring() throws {
        let bundlePath = createTestBundle(
            bundleIdentifier: "com.test.SystemExtension",
            version: "1.0.0"
        )
        
        let statusExpectation = expectation(description: "Status monitoring")
        var receivedStatuses: [SystemExtensionSubmissionStatus] = []
        
        // Start monitoring
        submissionManager.monitorApprovalStatus { status in
            receivedStatuses.append(status)
            if receivedStatuses.count >= 3 {
                statusExpectation.fulfill()
            }
        }
        
        // Verify initial status
        XCTAssertEqual(receivedStatuses.first, .notSubmitted)
        
        // Start submission
        submissionManager.submitExtension(bundlePath: bundlePath) { _ in }
        
        // Simulate status changes
        let mockRequest = MockOSSystemExtensionRequest()
        submissionManager.requestNeedsUserApproval(mockRequest)
        submissionManager.request(mockRequest, didFinishWithResult: .completed)
        
        waitForExpectations(timeout: 1.0)
        
        // Verify status progression
        XCTAssertTrue(receivedStatuses.contains { status in
            if case .submitting = status { return true }
            return false
        })
        
        XCTAssertTrue(receivedStatuses.contains { status in
            if case .pendingApproval = status { return true }
            return false
        })
        
        XCTAssertTrue(receivedStatuses.contains { status in
            if case .approved = status { return true }
            return false
        })
    }
    
    func testReplacementActionHandling() throws {
        let bundlePath = createTestBundle(
            bundleIdentifier: "com.test.SystemExtension",
            version: "1.0.0"
        )
        
        submissionManager.submitExtension(bundlePath: bundlePath) { _ in }
        
        // Create mock extension properties
        let existingExtension = MockOSSystemExtensionProperties(
            bundleIdentifier: "com.test.SystemExtension",
            bundleVersion: "1.0.0"
        )
        
        let newExtension = MockOSSystemExtensionProperties(
            bundleIdentifier: "com.test.SystemExtension",
            bundleVersion: "1.1.0"
        )
        
        let mockRequest = MockOSSystemExtensionRequest()
        
        // Test replacement action
        let action = submissionManager.request(
            mockRequest,
            actionForReplacingExtension: existingExtension,
            withExtension: newExtension
        )
        
        XCTAssertEqual(action, .replace)
    }
    
    // MARK: - Helper Methods
    
    private func testSubmissionError(
        errorCode: OSSystemExtensionError.Code,
        expectedError: SystemExtensionSubmissionError,
        expectedInstructions: [String]
    ) {
        let bundlePath = createTestBundle(
            bundleIdentifier: "com.test.SystemExtension",
            version: "1.0.0"
        )
        
        let expectation = expectation(description: "Submission completion")
        var completionResult: SubmissionResult?
        
        submissionManager.submitExtension(bundlePath: bundlePath) { result in
            completionResult = result
            expectation.fulfill()
        }
        
        // Simulate error
        let mockRequest = MockOSSystemExtensionRequest()
        let osError = OSSystemExtensionError(errorCode)
        submissionManager.request(mockRequest, didFailWithError: osError)
        
        waitForExpectations(timeout: 1.0)
        
        // Verify error mapping
        XCTAssertNotNil(completionResult)
        if case .failed(let error) = completionResult!.status {
            XCTAssertEqual(error, expectedError)
        } else {
            XCTFail("Expected failed status with \(expectedError), got: \(completionResult!.status)")
        }
        
        // Verify instructions
        for instruction in expectedInstructions {
            XCTAssertTrue(
                completionResult!.userInstructions.contains(instruction),
                "Missing instruction: \(instruction)"
            )
        }
    }
    
    private func createTestBundle(bundleIdentifier: String, version: String) -> String {
        let bundlePath = tempDirectory.appendingPathComponent("\(bundleIdentifier).appex")
        let contentsPath = bundlePath.appendingPathComponent("Contents")
        
        try! FileManager.default.createDirectory(at: contentsPath, withIntermediateDirectories: true)
        
        // Create Info.plist
        let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
        let infoPlist = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleVersion": version,
            "CFBundleShortVersionString": version,
            "CFBundleExecutable": "SystemExtension"
        ]
        
        let plistData = try! PropertyListSerialization.data(
            fromPropertyList: infoPlist,
            format: .xml,
            options: 0
        )
        
        try! plistData.write(to: infoPlistPath)
        
        return bundlePath.path
    }
}

// MARK: - Mock Classes

private class MockFileManager {
    var fileExistsReturnValue = true
    var fileExistsPath: String?
    
    func fileExists(atPath path: String) -> Bool {
        fileExistsPath = path
        return fileExistsReturnValue
    }
}

private class MockOSSystemExtensionRequest: OSSystemExtensionRequest {
    // Mock implementation for testing
}

private class MockOSSystemExtensionProperties: OSSystemExtensionProperties {
    private let _bundleIdentifier: String
    private let _bundleVersion: String
    
    init(bundleIdentifier: String, bundleVersion: String) {
        self._bundleIdentifier = bundleIdentifier
        self._bundleVersion = bundleVersion
    }
    
    override var bundleIdentifier: String {
        return _bundleIdentifier
    }
    
    override var bundleVersion: String {
        return _bundleVersion
    }
}

// MARK: - OSSystemExtensionError Extension

extension OSSystemExtensionError {
    convenience init(_ code: OSSystemExtensionError.Code) {
        self.init(.init(rawValue: code.rawValue)!)
    }
}