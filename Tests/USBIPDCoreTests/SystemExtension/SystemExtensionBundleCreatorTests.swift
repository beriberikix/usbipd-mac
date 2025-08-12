import XCTest
import Foundation
@testable import USBIPDCore
@testable import Common

final class SystemExtensionBundleCreatorTests: XCTestCase {
    
    private var tempDirectory: URL!
    private var bundleCreator: SystemExtensionBundleCreator!
    private var mockLogger: MockLogger!
    private var testExecutablePath: String!
    
    override func setUp() {
        super.setUp()
        
        // Create temporary directory for test bundles
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemExtensionBundleCreatorTests")
            .appendingPathComponent(UUID().uuidString)
        
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create mock logger
        mockLogger = MockLogger()
        bundleCreator = SystemExtensionBundleCreator(logger: mockLogger)
        
        // Create a test executable file
        testExecutablePath = tempDirectory.appendingPathComponent("TestExecutable").path
        FileManager.default.createFile(atPath: testExecutablePath, contents: Data("test executable".utf8))
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: testExecutablePath)
    }
    
    override func tearDown() {
        // Clean up test files
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }
    
    // MARK: - Bundle Creation Tests
    
    func testCreateBundle_Success() throws {
        let config = createTestConfig()
        
        let bundle = try bundleCreator.createBundle(with: config)
        
        XCTAssertEqual(bundle.bundleIdentifier, config.bundleIdentifier)
        XCTAssertEqual(bundle.displayName, config.displayName)
        XCTAssertEqual(bundle.version, config.version)
        XCTAssertEqual(bundle.buildNumber, config.buildNumber)
        XCTAssertEqual(bundle.executableName, config.executableName)
        XCTAssertEqual(bundle.teamIdentifier, config.teamIdentifier)
        XCTAssertEqual(bundle.bundlePath, config.bundlePath)
        XCTAssertFalse(bundle.contents.isValid) // Not valid until completion
        
        // Verify bundle directory structure was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.bundlePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.bundlePath + "/Contents"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.bundlePath + "/Contents/MacOS"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.bundlePath + "/Contents/Resources"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.contents.infoPlistPath))
    }
    
    func testCreateBundle_InvalidPath() {
        let config = SystemExtensionBundleCreator.BundleCreationConfig(
            bundlePath: "/invalid/readonly/path/test.app",
            bundleIdentifier: "com.test.app",
            displayName: "Test App",
            version: "1.0",
            buildNumber: "1",
            executableName: "TestApp",
            teamIdentifier: "ABCD123456",
            executablePath: testExecutablePath
        )
        
        XCTAssertThrowsError(try bundleCreator.createBundle(with: config)) { error in
            XCTAssertTrue(error is InstallationError)
            if case let InstallationError.bundleCreationFailed(message) = error {
                XCTAssertTrue(message.contains("Failed to create bundle directory"))
            }
        }
    }
    
    func testCompleteBundle_Success() throws {
        let config = createTestConfig()
        let bundle = try bundleCreator.createBundle(with: config)
        
        let completedBundle = try bundleCreator.completeBundle(bundle, with: config)
        
        XCTAssertTrue(completedBundle.contents.isValid)
        XCTAssertFalse(completedBundle.contents.executablePath.isEmpty)
        XCTAssertGreaterThan(completedBundle.contents.bundleSize, 0)
        
        // Verify executable was copied
        XCTAssertTrue(FileManager.default.fileExists(atPath: completedBundle.contents.executablePath))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: completedBundle.contents.executablePath))
    }
    
    func testCompleteBundle_MissingExecutable() throws {
        let config = SystemExtensionBundleCreator.BundleCreationConfig(
            bundlePath: tempDirectory.appendingPathComponent("TestBundle.app").path,
            bundleIdentifier: "com.test.bundle",
            displayName: "Test Bundle",
            version: "1.0",
            buildNumber: "1",
            executableName: "TestBundle",
            teamIdentifier: "ABCD123456",
            executablePath: "/nonexistent/path/executable"
        )
        
        let bundle = try bundleCreator.createBundle(with: config)
        
        XCTAssertThrowsError(try bundleCreator.completeBundle(bundle, with: config)) { error in
            XCTAssertTrue(error is InstallationError)
            if case let InstallationError.bundleCreationFailed(message) = error {
                XCTAssertTrue(message.contains("Source executable not found"))
            }
        }
    }
    
    // MARK: - Info.plist Tests
    
    func testInfoPlistGeneration() throws {
        let config = createTestConfig()
        let bundle = try bundleCreator.createBundle(with: config)
        
        // Read and validate Info.plist
        let plistData = try Data(contentsOf: URL(fileURLWithPath: bundle.contents.infoPlistPath))
        let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
        
        guard let plistDict = plist as? [String: Any] else {
            XCTFail("Info.plist should be a dictionary")
            return
        }
        
        XCTAssertEqual(plistDict["CFBundleIdentifier"] as? String, config.bundleIdentifier)
        XCTAssertEqual(plistDict["CFBundleDisplayName"] as? String, config.displayName)
        XCTAssertEqual(plistDict["CFBundleExecutable"] as? String, config.executableName)
        XCTAssertEqual(plistDict["CFBundleShortVersionString"] as? String, config.version)
        XCTAssertEqual(plistDict["CFBundleVersion"] as? String, config.buildNumber)
        XCTAssertEqual(plistDict["CFBundlePackageType"] as? String, "SYSX")
        XCTAssertEqual(plistDict["LSMinimumSystemVersion"] as? String, "11.0")
        XCTAssertNotNil(plistDict["NSSystemExtensionUsageDescription"])
    }
    
    // MARK: - Bundle Validation Tests
    
    func testValidateBundleStructure_ValidBundle() throws {
        let config = createTestConfig()
        let bundle = try bundleCreator.createBundle(with: config)
        
        let issues = bundleCreator.validateBundleStructure(at: bundle.bundlePath)
        
        XCTAssertTrue(issues.isEmpty, "Valid bundle should have no validation issues: \(issues)")
    }
    
    func testValidateBundleStructure_MissingBundle() {
        let nonexistentPath = tempDirectory.appendingPathComponent("Nonexistent.app").path
        
        let issues = bundleCreator.validateBundleStructure(at: nonexistentPath)
        
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("Bundle directory does not exist"))
    }
    
    func testValidateBundleStructure_MissingContents() throws {
        let bundlePath = tempDirectory.appendingPathComponent("TestBundle.app").path
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
        
        let issues = bundleCreator.validateBundleStructure(at: bundlePath)
        
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("Contents directory missing"))
    }
    
    func testValidateCompletedBundle_ValidBundle() throws {
        let config = createTestConfig()
        let bundle = try bundleCreator.createBundle(with: config)
        let completedBundle = try bundleCreator.completeBundle(bundle, with: config)
        
        let issues = bundleCreator.validateCompletedBundle(at: completedBundle.bundlePath)
        
        XCTAssertTrue(issues.isEmpty, "Valid completed bundle should have no issues: \(issues)")
    }
    
    func testValidateCompletedBundle_MissingExecutable() throws {
        let config = createTestConfig()
        let bundle = try bundleCreator.createBundle(with: config)
        
        let issues = bundleCreator.validateCompletedBundle(at: bundle.bundlePath)
        
        XCTAssertTrue(issues.contains { $0.contains("MacOS directory is empty") })
    }
    
    // MARK: - Integrity Check Tests
    
    func testPerformIntegrityCheck_ValidBundle() throws {
        let config = createTestConfig()
        let bundle = try bundleCreator.createBundle(with: config)
        let completedBundle = try bundleCreator.completeBundle(bundle, with: config)
        
        let results = bundleCreator.performIntegrityCheck(on: completedBundle)
        
        XCTAssertFalse(results.isEmpty)
        
        let failures = results.filter { !$0.passed }
        if !failures.isEmpty {
            let report = bundleCreator.generateRemediationReport(from: results)
            print("Integrity check failures:\n\(report)")
        }
        
        // Should have mostly passing checks for a valid bundle
        let passedCount = results.filter { $0.passed }.count
        XCTAssertGreaterThan(passedCount, results.count / 2, "Majority of checks should pass for valid bundle")
    }
    
    func testPerformIntegrityCheck_InvalidBundle() throws {
        let config = createTestConfig()
        let bundle = try bundleCreator.createBundle(with: config)
        
        // Create an incomplete bundle (no executable)
        let results = bundleCreator.performIntegrityCheck(on: bundle)
        
        let failures = results.filter { !$0.passed }
        XCTAssertGreaterThan(failures.count, 0, "Incomplete bundle should have validation failures")
        
        let report = bundleCreator.generateRemediationReport(from: results)
        XCTAssertTrue(report.contains("issue(s) found"))
    }
    
    func testGenerateRemediationReport_NoIssues() {
        let validResults = [
            ValidationResult(
                checkID: "test.check",
                checkName: "Test Check",
                passed: true,
                message: "Test passed",
                severity: .info,
                timestamp: Date()
            )
        ]
        
        let report = bundleCreator.generateRemediationReport(from: validResults)
        
        XCTAssertTrue(report.contains("no issues found"))
        XCTAssertTrue(report.contains("✅"))
    }
    
    func testGenerateRemediationReport_WithIssues() {
        let failedResults = [
            ValidationResult(
                checkID: "test.critical",
                checkName: "Critical Test",
                passed: false,
                message: "Critical failure",
                severity: .critical,
                recommendedActions: ["Fix critical issue"],
                timestamp: Date()
            ),
            ValidationResult(
                checkID: "test.warning",
                checkName: "Warning Test", 
                passed: false,
                message: "Warning issue",
                severity: .warning,
                recommendedActions: ["Fix warning issue"],
                timestamp: Date()
            )
        ]
        
        let report = bundleCreator.generateRemediationReport(from: failedResults)
        
        XCTAssertTrue(report.contains("2 issue(s) found"))
        XCTAssertTrue(report.contains("🚨 CRITICAL ISSUES"))
        XCTAssertTrue(report.contains("⚠️  WARNINGS"))
        XCTAssertTrue(report.contains("Fix critical issue"))
        XCTAssertTrue(report.contains("Fix warning issue"))
    }
    
    // MARK: - Helper Methods
    
    private func createTestConfig() -> SystemExtensionBundleCreator.BundleCreationConfig {
        return SystemExtensionBundleCreator.BundleCreationConfig(
            bundlePath: tempDirectory.appendingPathComponent("TestBundle.app").path,
            bundleIdentifier: "com.test.bundle",
            displayName: "Test Bundle",
            version: "1.0.0",
            buildNumber: "1",
            executableName: "TestBundle",
            teamIdentifier: "ABCD123456",
            executablePath: testExecutablePath
        )
    }
}

// MARK: - Mock Logger

private struct LoggedMessage {
    let level: LogLevel
    let message: String
    let context: [String: Any]?
}

private class MockLogger: Logger {
    var loggedMessages: [LoggedMessage] = []
    
    override func log(_ level: LogLevel, _ message: String, context: [String: Any]? = nil) {
        loggedMessages.append(LoggedMessage(level: level, message: message, context: context))
    }
    
    override func debug(_ message: String, context: [String: Any]? = nil) {
        log(.debug, message, context: context)
    }
    
    override func info(_ message: String, context: [String: Any]? = nil) {
        log(.info, message, context: context)
    }
    
    override func warning(_ message: String, context: [String: Any]? = nil) {
        log(.warning, message, context: context)
    }
    
    override func error(_ message: String, context: [String: Any]? = nil) {
        log(.error, message, context: context)
    }
    
    override func critical(_ message: String, context: [String: Any]? = nil) {
        log(.critical, message, context: context)
    }
}