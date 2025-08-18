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
    
    // MARK: - Enhanced Production Bundle Detection Tests
    
    func testDetectProductionBundleInHomebrewPath() throws {
        // Skip System Extension operations in CI environment
        #if CI_ENVIRONMENT
        throw XCTSkip("Skipping Homebrew bundle detection in CI environment")
        #endif
        
        // Given: Mock Homebrew file manager with valid bundle
        let mockFileManager = MockHomebrewFileManager()
        mockFileManager.setupValidHomebrewBundle()
        let detector = SystemExtensionBundleDetector(fileManager: mockFileManager)
        
        // When: Detecting production bundle
        let result = detector.detectProductionBundle()
        
        // Then: Bundle should be found in Homebrew environment
        XCTAssertTrue(result.found, "Bundle should be detected in Homebrew environment")
        XCTAssertNotNil(result.bundlePath, "Bundle path should be provided")
        XCTAssertEqual(result.bundleIdentifier, SystemExtensionBundleDetector.bundleIdentifier)
        
        // Verify environment details
        switch result.detectionEnvironment {
        case .homebrew(let cellarPath, let version):
            XCTAssertTrue(cellarPath.contains("homebrew"), "Should detect Homebrew cellar path")
            XCTAssertEqual(version, "v1.0.0", "Should extract version from path")
        default:
            XCTFail("Should detect Homebrew environment")
        }
    }
    
    func testDetectProductionBundleWithHomebrewMetadata() throws {
        // Skip System Extension operations in CI environment
        #if CI_ENVIRONMENT
        throw XCTSkip("Skipping Homebrew metadata parsing in CI environment")
        #endif
        
        // Given: Mock Homebrew file manager with metadata
        let mockFileManager = MockHomebrewFileManager()
        mockFileManager.setupValidHomebrewBundleWithMetadata()
        let detector = SystemExtensionBundleDetector(fileManager: mockFileManager)
        
        // When: Detecting production bundle
        let result = detector.detectProductionBundle()
        
        // Then: Bundle should be found with metadata
        XCTAssertTrue(result.found, "Bundle should be detected")
        XCTAssertNotNil(result.homebrewMetadata, "Homebrew metadata should be parsed")
        
        let metadata = result.homebrewMetadata!
        XCTAssertEqual(metadata.version, "v1.0.0")
        XCTAssertEqual(metadata.installationPrefix, "/opt/homebrew")
        XCTAssertEqual(metadata.formulaRevision, "abc123")
    }
    
    func testDetectProductionBundleNoHomebrewInstallation() throws {
        // Given: Mock file manager with no Homebrew installation
        let mockFileManager = MockHomebrewFileManager()
        // Don't set up any Homebrew paths
        let detector = SystemExtensionBundleDetector(fileManager: mockFileManager)
        
        // When: Detecting production bundle
        let result = detector.detectProductionBundle()
        
        // Then: Detection should fail appropriately
        XCTAssertFalse(result.found, "Bundle should not be detected without Homebrew installation")
        XCTAssertTrue(result.issues.contains { $0.contains("No Homebrew installation paths found") }, 
                     "Should report missing Homebrew installation")
        XCTAssertEqual(result.detectionEnvironment, .unknown, "Environment should be unknown")
    }
    
    func testMultiEnvironmentDetectionPriority() throws {
        // Skip System Extension operations in CI environment
        #if CI_ENVIRONMENT
        throw XCTSkip("Skipping multi-environment detection in CI environment")
        #endif
        
        // Given: Mock file manager with both Homebrew and development bundles
        let mockFileManager = MockMultiEnvironmentFileManager()
        mockFileManager.setupBothEnvironments()
        let detector = SystemExtensionBundleDetector(fileManager: mockFileManager)
        
        // When: Detecting bundle (should prefer production over development)
        let result = detector.detectBundle()
        
        // Then: Should find Homebrew bundle first (production priority)
        XCTAssertTrue(result.found, "Bundle should be detected")
        switch result.detectionEnvironment {
        case .homebrew:
            // Expected - production has priority
            break
        case .development:
            XCTFail("Should prefer Homebrew bundle over development bundle")
        default:
            XCTFail("Should detect either Homebrew or development environment")
        }
    }
    
    func testDetectBundleWithEnvironmentFallback() throws {
        // Skip System Extension operations in CI environment
        #if CI_ENVIRONMENT
        throw XCTSkip("Skipping environment fallback detection in CI environment")
        #endif
        
        // Given: Mock file manager with only development bundle (no Homebrew)
        let mockFileManager = MockDevelopmentOnlyFileManager()
        mockFileManager.setupDevelopmentBundle(baseDirectory: tempDirectory)
        let detector = SystemExtensionBundleDetector(fileManager: mockFileManager)
        
        // When: Detecting bundle
        let result = detector.detectBundle()
        
        // Then: Should fall back to development environment
        XCTAssertTrue(result.found, "Bundle should be detected in development environment")
        switch result.detectionEnvironment {
        case .development(let buildPath):
            XCTAssertTrue(buildPath.contains(".build"), "Should detect development build path")
        default:
            XCTFail("Should detect development environment")
        }
    }
    
    func testHomebrewMetadataParsingWithInvalidJSON() throws {
        // Given: Mock file manager with invalid metadata file
        let mockFileManager = MockHomebrewFileManager()
        mockFileManager.setupHomebrewBundleWithInvalidMetadata()
        let detector = SystemExtensionBundleDetector(fileManager: mockFileManager)
        
        // When: Detecting production bundle
        let result = detector.detectProductionBundle()
        
        // Then: Should handle parsing error gracefully
        XCTAssertTrue(result.found, "Bundle should still be detected despite metadata parsing error")
        XCTAssertNotNil(result.homebrewMetadata, "Should provide fallback metadata")
        
        let metadata = result.homebrewMetadata!
        XCTAssertEqual(metadata.version, "v1.0.0", "Should extract version from path as fallback")
        XCTAssertTrue(metadata.additionalInfo.keys.contains("parse_error"), "Should include parse error in additional info")
    }
    
    func testDetectionResultEnvironmentDetails() throws {
        // Given: Various detection environments
        let homebrewResult = SystemExtensionBundleDetector.DetectionResult(
            found: true,
            bundlePath: "/opt/homebrew/Cellar/usbipd-mac/v1.0.0/Library/SystemExtensions/test.systemextension",
            bundleIdentifier: SystemExtensionBundleDetector.bundleIdentifier,
            detectionEnvironment: .homebrew(cellarPath: "/opt/homebrew/Cellar/usbipd-mac/v1.0.0", version: "v1.0.0")
        )
        
        let developmentResult = SystemExtensionBundleDetector.DetectionResult(
            found: true,
            bundlePath: "/project/.build/debug/test.systemextension",
            bundleIdentifier: SystemExtensionBundleDetector.bundleIdentifier,
            detectionEnvironment: .development(buildPath: "/project/.build/debug")
        )
        
        // When/Then: Environment details should be preserved
        switch homebrewResult.detectionEnvironment {
        case .homebrew(let cellarPath, let version):
            XCTAssertTrue(cellarPath.contains("homebrew"))
            XCTAssertEqual(version, "v1.0.0")
        default:
            XCTFail("Should maintain Homebrew environment details")
        }
        
        switch developmentResult.detectionEnvironment {
        case .development(let buildPath):
            XCTAssertTrue(buildPath.contains(".build"))
        default:
            XCTFail("Should maintain development environment details")
        }
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

/// Mock file manager for Homebrew environment testing
private class MockHomebrewFileManager: FileManager {
    private var homebrewPaths: [String: Bool] = [:]
    private var directoryContents: [String: [String]] = [:]
    private var fileContents: [String: Data] = [:]
    
    override var currentDirectoryPath: String {
        return "/tmp/test"
    }
    
    func setupValidHomebrewBundle() {
        let homebrewPath = "/opt/homebrew/Cellar/usbipd-mac"
        let versionPath = "\(homebrewPath)/v1.0.0"
        let systemExtensionsPath = "\(versionPath)/Library/SystemExtensions"
        let bundlePath = "\(systemExtensionsPath)/usbipd-mac.systemextension"
        let contentsPath = "\(bundlePath)/Contents"
        let infoPlistPath = "\(contentsPath)/Info.plist"
        let macOSPath = "\(contentsPath)/MacOS"
        let executablePath = "\(macOSPath)/usbipd-mac"
        
        // Set up directory structure
        homebrewPaths[homebrewPath] = true
        homebrewPaths[versionPath] = true
        homebrewPaths[systemExtensionsPath] = true
        homebrewPaths[bundlePath] = true
        homebrewPaths[contentsPath] = true
        homebrewPaths[macOSPath] = true
        homebrewPaths[infoPlistPath] = false
        homebrewPaths[executablePath] = false
        
        // Set up directory contents
        directoryContents[homebrewPath] = ["v1.0.0"]
        directoryContents[versionPath] = ["Library"]
        directoryContents["\(versionPath)/Library"] = ["SystemExtensions"]
        directoryContents[systemExtensionsPath] = ["usbipd-mac.systemextension"]
        directoryContents[bundlePath] = ["Contents"]
        directoryContents[contentsPath] = ["Info.plist", "MacOS"]
        directoryContents[macOSPath] = ["usbipd-mac"]
        
        // Create valid Info.plist content
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "com.usbipd.mac.SystemExtension",
            "CFBundleExecutable": "usbipd-mac",
            "CFBundleVersion": "1.0.0"
        ]
        if let plistData = try? PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0) {
            fileContents[infoPlistPath] = plistData
        }
    }
    
    func setupValidHomebrewBundleWithMetadata() {
        setupValidHomebrewBundle()
        
        // Add Homebrew metadata file
        let metadataPath = "/opt/homebrew/Cellar/usbipd-mac/v1.0.0/Library/SystemExtensions/usbipd-mac.systemextension/Contents/HomebrewMetadata.json"
        homebrewPaths[metadataPath] = false
        
        let metadata = [
            "version": "v1.0.0",
            "installationDate": "2023-01-01T12:00:00Z",
            "formulaRevision": "abc123",
            "installationPrefix": "/opt/homebrew"
        ]
        
        if let metadataData = try? JSONSerialization.data(withJSONObject: metadata, options: []) {
            fileContents[metadataPath] = metadataData
        }
    }
    
    func setupHomebrewBundleWithInvalidMetadata() {
        setupValidHomebrewBundle()
        
        // Add invalid metadata file
        let metadataPath = "/opt/homebrew/Cellar/usbipd-mac/v1.0.0/Library/SystemExtensions/usbipd-mac.systemextension/Contents/HomebrewMetadata.json"
        homebrewPaths[metadataPath] = false
        fileContents[metadataPath] = "{ invalid json".data(using: .utf8)!
    }
    
    override func fileExists(atPath path: String) -> Bool {
        return homebrewPaths[path] ?? false
    }
    
    override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        let exists = homebrewPaths[path] ?? false
        if exists {
            isDirectory?.pointee = ObjCBool(homebrewPaths[path] == true)
        }
        return exists
    }
    
    override func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: DirectoryEnumerationOptions) throws -> [URL] {
        let contents = directoryContents[url.path] ?? []
        return contents.map { url.appendingPathComponent($0) }
    }
    
    override func contents(atPath path: String) -> Data? {
        return fileContents[path]
    }
}

/// Mock file manager for multi-environment testing
private class MockMultiEnvironmentFileManager: FileManager {
    private var allPaths: [String: Bool] = [:]
    private var directoryContents: [String: [String]] = [:]
    private var fileContents: [String: Data] = [:]
    
    override var currentDirectoryPath: String {
        return "/tmp/test"
    }
    
    func setupBothEnvironments() {
        // Set up Homebrew environment
        setupHomebrewEnvironment()
        // Set up development environment
        setupDevelopmentEnvironment()
    }
    
    private func setupHomebrewEnvironment() {
        let homebrewPath = "/opt/homebrew/Cellar/usbipd-mac"
        let versionPath = "\(homebrewPath)/v1.0.0"
        let systemExtensionsPath = "\(versionPath)/Library/SystemExtensions"
        let bundlePath = "\(systemExtensionsPath)/usbipd-mac.systemextension"
        let contentsPath = "\(bundlePath)/Contents"
        let infoPlistPath = "\(contentsPath)/Info.plist"
        let macOSPath = "\(contentsPath)/MacOS"
        let executablePath = "\(macOSPath)/usbipd-mac"
        
        allPaths[homebrewPath] = true
        allPaths[versionPath] = true
        allPaths[systemExtensionsPath] = true
        allPaths[bundlePath] = true
        allPaths[contentsPath] = true
        allPaths[macOSPath] = true
        allPaths[infoPlistPath] = false
        allPaths[executablePath] = false
        
        directoryContents[homebrewPath] = ["v1.0.0"]
        directoryContents[versionPath] = ["Library"]
        directoryContents["\(versionPath)/Library"] = ["SystemExtensions"]
        directoryContents[systemExtensionsPath] = ["usbipd-mac.systemextension"]
        directoryContents[bundlePath] = ["Contents"]
        directoryContents[contentsPath] = ["Info.plist", "MacOS"]
        directoryContents[macOSPath] = ["usbipd-mac"]
        
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "com.usbipd.mac.SystemExtension",
            "CFBundleExecutable": "usbipd-mac",
            "CFBundleVersion": "1.0.0"
        ]
        if let plistData = try? PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0) {
            fileContents[infoPlistPath] = plistData
        }
    }
    
    private func setupDevelopmentEnvironment() {
        let buildPath = "/tmp/test/.build"
        let debugPath = "\(buildPath)/debug"
        let bundlePath = "\(debugPath)/usbipd-mac.systemextension"
        let contentsPath = "\(bundlePath)/Contents"
        let infoPlistPath = "\(contentsPath)/Info.plist"
        let macOSPath = "\(contentsPath)/MacOS"
        let executablePath = "\(macOSPath)/usbipd-mac"
        
        allPaths[buildPath] = true
        allPaths[debugPath] = true
        allPaths[bundlePath] = true
        allPaths[contentsPath] = true
        allPaths[macOSPath] = true
        allPaths[infoPlistPath] = false
        allPaths[executablePath] = false
        
        directoryContents[buildPath] = ["debug"]
        directoryContents[debugPath] = ["usbipd-mac.systemextension"]
        directoryContents[bundlePath] = ["Contents"]
        directoryContents[contentsPath] = ["Info.plist", "MacOS"]
        directoryContents[macOSPath] = ["usbipd-mac"]
        
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "com.usbipd.mac.SystemExtension",
            "CFBundleExecutable": "usbipd-mac",
            "CFBundleVersion": "1.0.0"
        ]
        if let plistData = try? PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0) {
            fileContents[infoPlistPath] = plistData
        }
    }
    
    override func fileExists(atPath path: String) -> Bool {
        return allPaths[path] ?? false
    }
    
    override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        let exists = allPaths[path] ?? false
        if exists {
            isDirectory?.pointee = ObjCBool(allPaths[path] == true)
        }
        return exists
    }
    
    override func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: DirectoryEnumerationOptions) throws -> [URL] {
        let contents = directoryContents[url.path] ?? []
        return contents.map { url.appendingPathComponent($0) }
    }
    
    override func contents(atPath path: String) -> Data? {
        return fileContents[path]
    }
}

/// Mock file manager for development-only environment testing
private class MockDevelopmentOnlyFileManager: FileManager {
    private var developmentPaths: [String: Bool] = [:]
    private var directoryContents: [String: [String]] = [:]
    private var fileContents: [String: Data] = [:]
    private var baseDirectory = "/tmp/test"
    
    override var currentDirectoryPath: String {
        return baseDirectory
    }
    
    func setupDevelopmentBundle(baseDirectory: URL) {
        self.baseDirectory = baseDirectory.path
        let buildPath = "\(baseDirectory.path)/.build"
        let debugPath = "\(buildPath)/debug"
        let bundlePath = "\(debugPath)/usbipd-mac.systemextension"
        let contentsPath = "\(bundlePath)/Contents"
        let infoPlistPath = "\(contentsPath)/Info.plist"
        let macOSPath = "\(contentsPath)/MacOS"
        let executablePath = "\(macOSPath)/usbipd-mac"
        
        developmentPaths[buildPath] = true
        developmentPaths[debugPath] = true
        developmentPaths[bundlePath] = true
        developmentPaths[contentsPath] = true
        developmentPaths[macOSPath] = true
        developmentPaths[infoPlistPath] = false
        developmentPaths[executablePath] = false
        
        // No Homebrew paths - will return false for /opt/homebrew/Cellar/usbipd-mac
        
        directoryContents[buildPath] = ["debug"]
        directoryContents[debugPath] = ["usbipd-mac.systemextension"]
        directoryContents[bundlePath] = ["Contents"]
        directoryContents[contentsPath] = ["Info.plist", "MacOS"]
        directoryContents[macOSPath] = ["usbipd-mac"]
        
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "com.usbipd.mac.SystemExtension",
            "CFBundleExecutable": "usbipd-mac",
            "CFBundleVersion": "1.0.0"
        ]
        if let plistData = try? PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0) {
            fileContents[infoPlistPath] = plistData
        }
    }
    
    override func fileExists(atPath path: String) -> Bool {
        return developmentPaths[path] ?? false
    }
    
    override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        let exists = developmentPaths[path] ?? false
        if exists {
            isDirectory?.pointee = ObjCBool(developmentPaths[path] == true)
        }
        return exists
    }
    
    override func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: DirectoryEnumerationOptions) throws -> [URL] {
        let contents = directoryContents[url.path] ?? []
        return contents.map { url.appendingPathComponent($0) }
    }
    
    override func contents(atPath path: String) -> Data? {
        return fileContents[path]
    }
}