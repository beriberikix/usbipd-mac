// SystemExtensionBundleDetectorTests.swift
// CI-compatible unit tests for System Extension bundle detection logic

import XCTest
import Foundation
@testable import USBIPDCore
@testable import Common

final class SystemExtensionBundleDetectorTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol
    
    var environmentConfig: TestEnvironmentConfig {
        return TestEnvironmentDetector.createConfigurationForCurrentEnvironment()
    }
    
    var requiredCapabilities: TestEnvironmentCapabilities {
        return [.filesystemWrite]
    }
    
    var testCategory: String {
        return "unit"
    }
    
    // MARK: - Test Infrastructure
    
    private var tempDirectory: URL!
    private var buildDirectory: URL!
    private var mockFileManager: MockFileManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        try validateEnvironment()
        
        // Create temporary directory structure for testing
        tempDirectory = TestEnvironmentFixtures.createTemporaryDirectory()
        buildDirectory = tempDirectory.appendingPathComponent(".build")
        
        // Set up mock file manager
        mockFileManager = MockFileManager()
        
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    override func tearDownWithError() throws {
        TestEnvironmentFixtures.cleanupTemporaryDirectory(tempDirectory)
        tempDirectory = nil
        buildDirectory = nil
        mockFileManager = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Bundle Detection Tests
    
    func testDetectBundleSuccessWithValidBundle() throws {
        // Skip System Extension operations in CI environment
        #if CI_ENVIRONMENT
        throw XCTSkip("Skipping System Extension bundle detection in CI environment")
        #endif
        
        // Given: A valid System Extension bundle in debug build directory
        let debugPath = buildDirectory.appendingPathComponent("debug")
        let bundlePath = debugPath.appendingPathComponent("TestExtension.systemextension")
        let contentsPath = bundlePath.appendingPathComponent("Contents")
        let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
        let macOSPath = contentsPath.appendingPathComponent("MacOS")
        let executablePath = macOSPath.appendingPathComponent("TestExtension")
        
        try FileManager.default.createDirectory(at: debugPath, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: contentsPath, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: macOSPath, withIntermediateDirectories: true, attributes: nil)
        
        // Create valid Info.plist
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": SystemExtensionBundleDetector.bundleIdentifier,
            "CFBundleExecutable": "TestExtension",
            "CFBundleVersion": "1.0.0",
            "CFBundleName": "Test System Extension"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: infoPlistPath)
        
        // Create executable file
        try "#!/bin/bash\necho 'test executable'".write(to: executablePath, atomically: true, encoding: .utf8)
        
        // When: Detecting bundle with custom file manager that uses our temp directory
        let customFileManager = TestFileManagerAdapter(baseDirectory: tempDirectory)
        let detector = SystemExtensionBundleDetector(fileManager: customFileManager)
        let result = detector.detectBundle()
        
        // Then: Bundle should be found successfully
        XCTAssertTrue(result.found, "Bundle should be detected")
        XCTAssertNotNil(result.bundlePath, "Bundle path should be provided")
        XCTAssertEqual(result.bundleIdentifier, SystemExtensionBundleDetector.bundleIdentifier)
        XCTAssertTrue(result.issues.isEmpty || result.issues.allSatisfy { !$0.contains("Missing") }, "Should not have critical missing component issues")
    }
    
    func testDetectBundleFailureWithMissingBuildDirectory() throws {
        // Given: No .build directory exists
        let customFileManager = TestFileManagerAdapter(baseDirectory: tempDirectory, buildDirectoryExists: false)
        let detector = SystemExtensionBundleDetector(fileManager: customFileManager)
        
        // When: Attempting to detect bundle
        let result = detector.detectBundle()
        
        // Then: Detection should fail with appropriate error
        XCTAssertFalse(result.found, "Bundle should not be detected when build directory is missing")
        XCTAssertNil(result.bundlePath, "Bundle path should be nil")
        XCTAssertTrue(result.issues.contains { $0.contains("No .build directory found") }, "Should report missing build directory")
    }
    
    func testDetectBundleFailureWithInvalidBundle() throws {
        // Skip System Extension operations in CI environment
        #if CI_ENVIRONMENT
        throw XCTSkip("Skipping System Extension bundle validation in CI environment")
        #endif
        
        // Given: An invalid bundle (missing Info.plist)
        let debugPath = buildDirectory.appendingPathComponent("debug")
        let bundlePath = debugPath.appendingPathComponent("InvalidExtension.systemextension")
        let contentsPath = bundlePath.appendingPathComponent("Contents")
        
        try FileManager.default.createDirectory(at: debugPath, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: contentsPath, withIntermediateDirectories: true, attributes: nil)
        
        // When: Detecting bundle
        let customFileManager = TestFileManagerAdapter(baseDirectory: tempDirectory)
        let detector = SystemExtensionBundleDetector(fileManager: customFileManager)
        let result = detector.detectBundle()
        
        // Then: Detection should fail due to invalid bundle
        XCTAssertFalse(result.found, "Invalid bundle should not be detected")
        XCTAssertNil(result.bundlePath, "Bundle path should be nil for invalid bundle")
        XCTAssertTrue(result.issues.contains { $0.contains("No valid System Extension bundle found") }, "Should report no valid bundle found")
    }
    
    func testDetectBundleWithMissingExecutable() throws {
        // Skip System Extension operations in CI environment
        #if CI_ENVIRONMENT
        throw XCTSkip("Skipping System Extension executable validation in CI environment")
        #endif
        
        // Given: Bundle with Info.plist but missing executable
        let debugPath = buildDirectory.appendingPathComponent("debug")
        let bundlePath = debugPath.appendingPathComponent("TestExtension.systemextension")
        let contentsPath = bundlePath.appendingPathComponent("Contents")
        let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
        let macOSPath = contentsPath.appendingPathComponent("MacOS")
        
        try FileManager.default.createDirectory(at: debugPath, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: contentsPath, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: macOSPath, withIntermediateDirectories: true, attributes: nil)
        
        // Create Info.plist with executable reference
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": SystemExtensionBundleDetector.bundleIdentifier,
            "CFBundleExecutable": "MissingExecutable",
            "CFBundleVersion": "1.0.0"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: infoPlistPath)
        
        // When: Detecting bundle
        let customFileManager = TestFileManagerAdapter(baseDirectory: tempDirectory)
        let detector = SystemExtensionBundleDetector(fileManager: customFileManager)
        let result = detector.detectBundle()
        
        // Then: Detection should fail due to missing executable
        XCTAssertFalse(result.found, "Bundle with missing executable should not be valid")
        XCTAssertTrue(result.issues.contains { $0.contains("No valid System Extension bundle found") }, "Should report validation failure")
    }
    
    func testDetectBundleWithIncorrectBundleIdentifier() throws {
        // Skip System Extension operations in CI environment
        #if CI_ENVIRONMENT
        throw XCTSkip("Skipping System Extension bundle identifier validation in CI environment")
        #endif
        
        // Given: Bundle with incorrect bundle identifier
        let debugPath = buildDirectory.appendingPathComponent("debug")
        let bundlePath = debugPath.appendingPathComponent("WrongExtension.systemextension")
        let contentsPath = bundlePath.appendingPathComponent("Contents")
        let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
        let macOSPath = contentsPath.appendingPathComponent("MacOS")
        let executablePath = macOSPath.appendingPathComponent("WrongExtension")
        
        try FileManager.default.createDirectory(at: debugPath, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: contentsPath, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: macOSPath, withIntermediateDirectories: true, attributes: nil)
        
        // Create Info.plist with wrong bundle identifier
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "com.wrong.bundle.identifier",
            "CFBundleExecutable": "WrongExtension",
            "CFBundleVersion": "1.0.0"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: infoPlistPath)
        
        // Create executable
        try "test".write(to: executablePath, atomically: true, encoding: .utf8)
        
        // When: Detecting bundle
        let customFileManager = TestFileManagerAdapter(baseDirectory: tempDirectory)
        let detector = SystemExtensionBundleDetector(fileManager: customFileManager)
        let result = detector.detectBundle()
        
        // Then: Detection should succeed but report bundle identifier mismatch
        XCTAssertTrue(result.found, "Bundle should be detected despite identifier mismatch")
        XCTAssertNotNil(result.bundlePath, "Bundle path should be provided")
        XCTAssertTrue(result.issues.contains { $0.contains("Bundle identifier mismatch") }, "Should report bundle identifier mismatch")
    }
    
    func testDetectBundleSearchesMultiplePaths() throws {
        // Skip System Extension operations in CI environment
        #if CI_ENVIRONMENT
        throw XCTSkip("Skipping System Extension multi-path search in CI environment")
        #endif
        
        // Given: Bundle in arm64 release directory (not the first search path)
        let arm64ReleasePath = buildDirectory.appendingPathComponent("arm64-apple-macosx/release")
        let bundlePath = arm64ReleasePath.appendingPathComponent("TestExtension.systemextension")
        let contentsPath = bundlePath.appendingPathComponent("Contents")
        let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
        let macOSPath = contentsPath.appendingPathComponent("MacOS")
        let executablePath = macOSPath.appendingPathComponent("TestExtension")
        
        try FileManager.default.createDirectory(at: arm64ReleasePath, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: contentsPath, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: macOSPath, withIntermediateDirectories: true, attributes: nil)
        
        // Create valid bundle
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": SystemExtensionBundleDetector.bundleIdentifier,
            "CFBundleExecutable": "TestExtension",
            "CFBundleVersion": "1.0.0"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: infoPlistPath)
        try "test executable".write(to: executablePath, atomically: true, encoding: .utf8)
        
        // When: Detecting bundle
        let customFileManager = TestFileManagerAdapter(baseDirectory: tempDirectory)
        let detector = SystemExtensionBundleDetector(fileManager: customFileManager)
        let result = detector.detectBundle()
        
        // Then: Bundle should be found in the specific path
        XCTAssertTrue(result.found, "Bundle should be detected in arm64 release path")
        XCTAssertNotNil(result.bundlePath, "Bundle path should be provided")
        XCTAssertTrue(result.bundlePath?.contains("arm64-apple-macosx/release") == true, "Should find bundle in correct subdirectory")
    }
    
    // MARK: - Bundle Configuration Creation Tests
    
    func testBundleConfigCreationFromValidDetectionResult() throws {
        // Given: Valid detection result
        let bundlePath = "/tmp/test.systemextension"
        let detectionResult = SystemExtensionBundleDetector.DetectionResult(
            found: true,
            bundlePath: bundlePath,
            bundleIdentifier: SystemExtensionBundleDetector.bundleIdentifier,
            issues: ["Bundle identifier mismatch: expected com.usbipd.mac.SystemExtension, found com.test.bundle"],
            detectionTime: Date()
        )
        
        // When: Creating bundle config from detection result
        let bundleConfig = SystemExtensionBundleConfig.from(detectionResult: detectionResult)
        
        // Then: Config should be created successfully
        XCTAssertNotNil(bundleConfig, "Bundle config should be created")
        XCTAssertEqual(bundleConfig?.bundlePath, bundlePath)
        XCTAssertEqual(bundleConfig?.bundleIdentifier, SystemExtensionBundleDetector.bundleIdentifier)
        XCTAssertTrue(bundleConfig?.isValid == true)
        XCTAssertEqual(bundleConfig?.installationStatus, .unknown)
        XCTAssertEqual(bundleConfig?.detectionIssues, detectionResult.issues)
    }
    
    func testBundleConfigCreationFromInvalidDetectionResult() throws {
        // Given: Invalid detection result (not found)
        let detectionResult = SystemExtensionBundleDetector.DetectionResult(
            found: false,
            bundlePath: nil,
            bundleIdentifier: nil,
            issues: ["No .build directory found"],
            detectionTime: Date()
        )
        
        // When: Attempting to create bundle config
        let bundleConfig = SystemExtensionBundleConfig.from(detectionResult: detectionResult)
        
        // Then: Config should not be created
        XCTAssertNil(bundleConfig, "Bundle config should not be created for invalid detection result")
    }
    
    // MARK: - Static Properties Tests
    
    func testBundleIdentifierConstant() {
        // Then: Bundle identifier should be consistent
        XCTAssertEqual(SystemExtensionBundleDetector.bundleIdentifier, "com.usbipd.mac.SystemExtension")
    }
}

// MARK: - Test Helper Classes

/// Mock file manager for controlled testing
private class MockFileManager: FileManager {
    var mockDirectoryContents: [URL: [URL]] = [:]
    var mockFileExists: [String: Bool] = [:]
    var mockIsDirectory: [String: Bool] = [:]
    var mockCurrentDirectory = "/tmp/test"
    
    override var currentDirectoryPath: String {
        return mockCurrentDirectory
    }
    
    override func fileExists(atPath path: String) -> Bool {
        return mockFileExists[path] ?? false
    }
    
    override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        isDirectory?.pointee = ObjCBool(mockIsDirectory[path] ?? false)
        return mockFileExists[path] ?? false
    }
    
    override func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: DirectoryEnumerationOptions) throws -> [URL] {
        return mockDirectoryContents[url] ?? []
    }
}

/// Test file manager adapter that works with real filesystem in temporary directory
private class TestFileManagerAdapter: FileManager {
    private let baseDirectory: URL
    private let buildDirectoryExists: Bool
    
    init(baseDirectory: URL, buildDirectoryExists: Bool = true) {
        self.baseDirectory = baseDirectory
        self.buildDirectoryExists = buildDirectoryExists
        super.init()
    }
    
    override var currentDirectoryPath: String {
        return baseDirectory.path
    }
    
    override func fileExists(atPath path: String) -> Bool {
        if path.hasSuffix(".build") && !buildDirectoryExists {
            return false
        }
        return super.fileExists(atPath: path)
    }
    
    override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        if path.hasSuffix(".build") && !buildDirectoryExists {
            return false
        }
        return super.fileExists(atPath: path, isDirectory: isDirectory)
    }
}