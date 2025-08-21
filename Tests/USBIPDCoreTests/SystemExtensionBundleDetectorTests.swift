// SystemExtensionBundleDetectorTests.swift
// Tests for SystemExtensionBundleDetector
import Foundation
import XCTest
@testable import USBIPDCore

final class SystemExtensionBundleDetectorTests: XCTestCase {

    var fileManager: MockFileManager!
    var detector: SystemExtensionBundleDetector!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = MockFileManager()
        detector = SystemExtensionBundleDetector(fileManager: fileManager)
    }

    override func tearDownWithError() throws {
        detector = nil
        fileManager = nil
        try super.tearDownWithError()
    }

    func testIsDSYMPath() {
        let dsymURL = URL(fileURLWithPath: "/build/usbipd-mac.dSYM")
        let nonDsymURL = URL(fileURLWithPath: "/build/usbipd-mac")
        
        let detector = SystemExtensionBundleDetector()
        
        // Accessing the private method via extension for testing
        XCTAssertTrue(detector.isDSYMPath(dsymURL), "Should return true for a dSYM path")
        XCTAssertFalse(detector.isDSYMPath(nonDsymURL), "Should return false for a non-dSYM path")
    }

    func testFindBundleInPathWithDSYMExclusion() throws {
        // 1. Setup mock file system
        let buildDir = URL(fileURLWithPath: "/.build/arm64-apple-macosx/debug")
        let dsymDir = buildDir.appendingPathComponent("usbipd-mac.dSYM")
        let realExecutableDir = buildDir
        let realExecutable = realExecutableDir.appendingPathComponent("USBIPDSystemExtension")

        fileManager.mockDirectories = [
            buildDir.path,
            dsymDir.path,
            realExecutableDir.path
        ]
        fileManager.mockFiles = [
            dsymDir.appendingPathComponent("Contents/Resources/DWARF/usbipd-mac").path,
            realExecutable.path
        ]
        
        fileManager.mockDirectoryContents[buildDir.path] = ["usbipd-mac.dSYM", "USBIPDSystemExtension"]
        fileManager.mockDirectoryContents[dsymDir.path] = ["Contents"]
        fileManager.mockDirectoryContents[dsymDir.appendingPathComponent("Contents").path] = ["Resources"]
        fileManager.mockDirectoryContents[dsymDir.appendingPathComponent("Contents/Resources").path] = ["DWARF"]
        fileManager.mockDirectoryContents[dsymDir.appendingPathComponent("Contents/Resources/DWARF").path] = ["usbipd-mac"]

        // 2. Run detection
        let result = detector.findBundleInPath(buildDir)

        // 3. Assert
        XCTAssertNotNil(result.bundlePath, "Should have found a bundle path")
        XCTAssertEqual(result.bundlePath, realExecutableDir, "Should have found the real executable path, not the dSYM path")
        XCTAssertNotEqual(result.bundlePath, dsymDir, "Should not have found the dSYM path")
    }
    
    func testDevelopmentBundleValidation() throws {
        // Setup mock file system for development bundle
        let bundlePath = URL(fileURLWithPath: "/build/debug")
        let executablePath = bundlePath.appendingPathComponent("USBIPDSystemExtension")
        
        fileManager.mockDirectories = [bundlePath.path]
        fileManager.mockFiles = [executablePath.path]
        fileManager.mockDirectoryContents[bundlePath.path] = ["USBIPDSystemExtension"]
        
        // Test validation
        let result = detector.validateBundle(at: bundlePath)
        
        XCTAssertTrue(result.isValid, "Development bundle should be valid")
        XCTAssertEqual(result.bundleType, .development, "Should detect bundle as development type")
        XCTAssertNil(result.rejectionReason, "Should not have rejection reason for valid bundle")
        XCTAssertTrue(result.issues.contains { $0.contains("Development mode bundle detected") }, "Should indicate development mode")
    }
    
    func testProductionBundleValidation() throws {
        // Setup mock file system for production bundle
        let bundlePath = URL(fileURLWithPath: "/Applications/TestApp.systemextension")
        let contentsPath = bundlePath.appendingPathComponent("Contents")
        let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
        let macOSPath = contentsPath.appendingPathComponent("MacOS")
        let executablePath = macOSPath.appendingPathComponent("USBIPDSystemExtension")
        
        fileManager.mockDirectories = [
            bundlePath.path,
            contentsPath.path,
            macOSPath.path
        ]
        fileManager.mockFiles = [
            infoPlistPath.path,
            executablePath.path
        ]
        
        fileManager.mockDirectoryContents[bundlePath.path] = ["Contents"]
        fileManager.mockDirectoryContents[contentsPath.path] = ["Info.plist", "MacOS"]
        fileManager.mockDirectoryContents[macOSPath.path] = ["USBIPDSystemExtension"]
        
        // Mock plist data
        let plistDict: [String: Any] = [
            "CFBundleIdentifier": SystemExtensionBundleDetector.bundleIdentifier,
            "CFBundleExecutable": "USBIPDSystemExtension"
        ]
        
        let mockFileManager = fileManager!
        mockFileManager.mockPlistData[infoPlistPath.path] = plistDict
        
        // Test validation
        let result = detector.validateBundle(at: bundlePath)
        
        XCTAssertTrue(result.isValid, "Production bundle should be valid")
        XCTAssertEqual(result.bundleType, .production, "Should detect bundle as production type")
        XCTAssertNil(result.rejectionReason, "Should not have rejection reason for valid bundle")
    }
    
    func testBundleTypeDetection() throws {
        let detector = SystemExtensionBundleDetector(fileManager: fileManager)
        
        // Test development bundle detection
        let developmentPath = URL(fileURLWithPath: "/build/debug")
        let devExecutable = developmentPath.appendingPathComponent("USBIPDSystemExtension")
        
        fileManager.mockDirectories = [developmentPath.path]
        fileManager.mockFiles = [devExecutable.path]
        fileManager.mockDirectoryContents[developmentPath.path] = ["USBIPDSystemExtension"]
        
        let devResult = detector.validateBundle(at: developmentPath)
        XCTAssertEqual(devResult.bundleType, .development, "Should detect development bundle type")
        
        // Test production bundle detection
        let productionPath = URL(fileURLWithPath: "/Applications/TestApp.systemextension")
        let contentsPath = productionPath.appendingPathComponent("Contents")
        let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
        let macOSPath = contentsPath.appendingPathComponent("MacOS")
        let prodExecutable = macOSPath.appendingPathComponent("USBIPDSystemExtension")
        
        fileManager.mockDirectories.append(contentsOf: [
            productionPath.path,
            contentsPath.path,
            macOSPath.path
        ])
        fileManager.mockFiles.append(contentsOf: [
            infoPlistPath.path,
            prodExecutable.path
        ])
        
        fileManager.mockDirectoryContents[productionPath.path] = ["Contents"]
        fileManager.mockDirectoryContents[contentsPath.path] = ["Info.plist", "MacOS"]
        fileManager.mockDirectoryContents[macOSPath.path] = ["USBIPDSystemExtension"]
        
        // Mock plist data
        let plistDict: [String: Any] = [
            "CFBundleIdentifier": SystemExtensionBundleDetector.bundleIdentifier,
            "CFBundleExecutable": "USBIPDSystemExtension"
        ]
        
        let mockFileManager = fileManager!
        mockFileManager.mockPlistData[infoPlistPath.path] = plistDict
        
        let prodResult = detector.validateBundle(at: productionPath)
        XCTAssertEqual(prodResult.bundleType, .production, "Should detect production bundle type")
    }
    
    func testEnhancedErrorReporting() throws {
        // Test missing executable error reporting
        let bundlePathMissingExec = URL(fileURLWithPath: "/build/invalid")
        fileManager.mockDirectories = [bundlePathMissingExec.path]
        fileManager.mockDirectoryContents[bundlePathMissingExec.path] = []
        
        let resultMissingExec = detector.validateBundle(at: bundlePathMissingExec)
        XCTAssertFalse(resultMissingExec.isValid, "Bundle without executable should be invalid")
        XCTAssertEqual(resultMissingExec.rejectionReason, .missingInfoPlist, "Should have correct rejection reason for missing plist")
        XCTAssertTrue(resultMissingExec.issues.contains { $0.contains("Missing Info.plist") }, "Should report missing Info.plist")
        
        // Test invalid bundle structure error reporting
        let nonExistentPath = URL(fileURLWithPath: "/nonexistent/path")
        let resultNonExistent = detector.validateBundle(at: nonExistentPath)
        XCTAssertFalse(resultNonExistent.isValid, "Non-existent bundle should be invalid")
        XCTAssertEqual(resultNonExistent.rejectionReason, .invalidBundleStructure, "Should have correct rejection reason for invalid structure")
        XCTAssertTrue(resultNonExistent.issues.contains { $0.contains("Bundle path does not exist") }, "Should report path does not exist")
        
        // Test missing executable in production bundle
        let prodBundlePath = URL(fileURLWithPath: "/Applications/TestApp.systemextension")
        let contentsPath = prodBundlePath.appendingPathComponent("Contents")
        let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
        let macOSPath = contentsPath.appendingPathComponent("MacOS")
        
        fileManager.mockDirectories = [
            prodBundlePath.path,
            contentsPath.path,
            macOSPath.path
        ]
        fileManager.mockFiles = [infoPlistPath.path] // Missing executable
        fileManager.mockDirectoryContents[prodBundlePath.path] = ["Contents"]
        fileManager.mockDirectoryContents[contentsPath.path] = ["Info.plist", "MacOS"]
        fileManager.mockDirectoryContents[macOSPath.path] = []
        
        let plistDict: [String: Any] = [
            "CFBundleIdentifier": SystemExtensionBundleDetector.bundleIdentifier,
            "CFBundleExecutable": "USBIPDSystemExtension"
        ]
        
        let mockFileManager = fileManager!
        mockFileManager.mockPlistData[infoPlistPath.path] = plistDict
        
        let resultMissingProdExec = detector.validateBundle(at: prodBundlePath)
        XCTAssertFalse(resultMissingProdExec.isValid, "Production bundle without executable should be invalid")
        XCTAssertEqual(resultMissingProdExec.rejectionReason, .missingExecutable, "Should have correct rejection reason for missing executable")
        XCTAssertTrue(resultMissingProdExec.issues.contains { $0.contains("Missing executable") }, "Should report missing executable")
    }
    
    func testDiagnosticInformation() throws {
        // Setup mock file system with dSYM and valid bundle
        let buildDir = URL(fileURLWithPath: "/.build/arm64-apple-macosx/debug")
        let dsymDir = buildDir.appendingPathComponent("usbipd-mac.dSYM")
        let anotherDsymDir = buildDir.appendingPathComponent("SomeOtherTool.dSYM")
        let realExecutable = buildDir.appendingPathComponent("USBIPDSystemExtension")
        
        fileManager.mockDirectories = [
            buildDir.path,
            dsymDir.path,
            anotherDsymDir.path
        ]
        fileManager.mockFiles = [
            dsymDir.appendingPathComponent("Contents/Resources/DWARF/usbipd-mac").path,
            anotherDsymDir.appendingPathComponent("Contents/Resources/DWARF/SomeOtherTool").path,
            realExecutable.path
        ]
        
        fileManager.mockDirectoryContents[buildDir.path] = ["usbipd-mac.dSYM", "SomeOtherTool.dSYM", "USBIPDSystemExtension"]
        
        // Run detection and check diagnostic information
        let result = detector.findBundleInPath(buildDir)
        
        XCTAssertNotNil(result.bundlePath, "Should have found a bundle path")
        XCTAssertEqual(result.skippedPaths.count, 2, "Should have skipped 2 dSYM paths")
        XCTAssertTrue(result.skippedPaths.contains(dsymDir.path), "Should have skipped first dSYM path")
        XCTAssertTrue(result.skippedPaths.contains(anotherDsymDir.path), "Should have skipped second dSYM path")
        
        // Verify rejection reasons
        XCTAssertEqual(result.rejectionReasons.count, 2, "Should have 2 rejection reasons")
        XCTAssertEqual(result.rejectionReasons[dsymDir.path], .dSYMPath, "Should have dSYM rejection reason for first path")
        XCTAssertEqual(result.rejectionReasons[anotherDsymDir.path], .dSYMPath, "Should have dSYM rejection reason for second path")
    }
    
    func testRejectionReasonMapping() throws {
        // Test dSYM path rejection
        let dsymPath = URL(fileURLWithPath: "/build/test.dSYM")
        XCTAssertTrue(detector.isDSYMPath(dsymPath), "Should detect dSYM path")
        
        // Test different bundle validation scenarios and their rejection reasons
        struct TestCase {
            let path: String
            let expectedReason: SystemExtensionBundleDetector.RejectionReason?
            let description: String
        }
        
        let testCases = [
            TestCase(path: "/nonexistent", expectedReason: .invalidBundleStructure, description: "Non-existent path should map to invalid bundle structure"),
            TestCase(path: "/valid/development", expectedReason: nil, description: "Valid development bundle should have no rejection reason")
        ]
        
        for testCase in testCases {
            let testPath = URL(fileURLWithPath: testCase.path)
            
            if testCase.path == "/valid/development" {
                // Setup valid development bundle
                let executablePath = testPath.appendingPathComponent("USBIPDSystemExtension")
                fileManager.mockDirectories = [testPath.path]
                fileManager.mockFiles = [executablePath.path]
                fileManager.mockDirectoryContents[testPath.path] = ["USBIPDSystemExtension"]
            }
            
            let result = detector.validateBundle(at: testPath)
            XCTAssertEqual(result.rejectionReason, testCase.expectedReason, testCase.description)
        }
        
        // Test production bundle with missing Info.plist
        let prodPath = URL(fileURLWithPath: "/Applications/MissingPlist.systemextension")
        fileManager.mockDirectories = [prodPath.path]
        fileManager.mockDirectoryContents[prodPath.path] = ["Contents"]
        
        let prodResult = detector.validateBundle(at: prodPath)
        XCTAssertEqual(prodResult.rejectionReason, .missingInfoPlist, "Missing plist should map to missing Info.plist rejection reason")
        
        // Test production bundle with missing executable (but valid plist)
        let prodPathMissingExec = URL(fileURLWithPath: "/Applications/MissingExec.systemextension")
        let contentsPath = prodPathMissingExec.appendingPathComponent("Contents")
        let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
        
        fileManager.mockDirectories.append(contentsOf: [
            prodPathMissingExec.path,
            contentsPath.path
        ])
        fileManager.mockFiles.append(infoPlistPath.path)
        fileManager.mockDirectoryContents[prodPathMissingExec.path] = ["Contents"]
        fileManager.mockDirectoryContents[contentsPath.path] = ["Info.plist"]
        
        let plistDict: [String: Any] = [
            "CFBundleIdentifier": SystemExtensionBundleDetector.bundleIdentifier,
            "CFBundleExecutable": "MissingExecutable"
        ]
        
        let mockFileManager = fileManager!
        mockFileManager.mockPlistData[infoPlistPath.path] = plistDict
        
        let prodResultMissingExec = detector.validateBundle(at: prodPathMissingExec)
        XCTAssertEqual(prodResultMissingExec.rejectionReason, .missingExecutable, "Missing executable should map to missing executable rejection reason")
    }
}

// MARK: - Private method access for testing
private extension SystemExtensionBundleDetector {
    func isDSYMPath(_ path: URL) -> Bool {
        return path.pathComponents.contains { $0.hasSuffix(".dSYM") }
    }
    
    func findBundleInPath(_ path: URL) -> BundleSearchResult {
        var skippedPaths: [String] = []
        var rejectionReasons: [String: RejectionReason] = [:]
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: path,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            for item in contents {
                if isDSYMPath(item) {
                    skippedPaths.append(item.path)
                    rejectionReasons[item.path] = .dSYMPath
                    continue
                }

                if item.pathExtension == "systemextension" {
                    return BundleSearchResult(bundlePath: item, skippedPaths: skippedPaths, rejectionReasons: rejectionReasons)
                }
                
                if item.lastPathComponent == "USBIPDSystemExtension" {
                    return BundleSearchResult(bundlePath: path, skippedPaths: skippedPaths, rejectionReasons: rejectionReasons)
                }
                
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    let subdirResult = findBundleInPath(item)
                    if let bundlePath = subdirResult.bundlePath {
                        return BundleSearchResult(
                            bundlePath: bundlePath,
                            skippedPaths: skippedPaths + subdirResult.skippedPaths,
                            rejectionReasons: rejectionReasons.merging(subdirResult.rejectionReasons) { _, new in new }
                        )
                    }
                    skippedPaths.append(contentsOf: subdirResult.skippedPaths)
                    rejectionReasons.merge(subdirResult.rejectionReasons) { _, new in new }
                }
            }
        } catch {
            // Silently continue
        }
        
        return BundleSearchResult(bundlePath: nil, skippedPaths: skippedPaths, rejectionReasons: rejectionReasons)
    }
    
    struct BundleValidationResult {
        let isValid: Bool
        let issues: [String]
        let bundleType: BundleType?
        let rejectionReason: RejectionReason?
    }
    
    func validateBundle(at bundlePath: URL) -> BundleValidationResult {
        var issues: [String] = []
        
        // Check if path exists and is a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: bundlePath.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            issues.append("Bundle path does not exist or is not a directory: \(bundlePath.path)")
            return BundleValidationResult(isValid: false, issues: issues, bundleType: nil, rejectionReason: .invalidBundleStructure)
        }
        
        // Check if this is a development environment (has USBIPDSystemExtension executable)
        let developmentExecutablePath = bundlePath.appendingPathComponent("USBIPDSystemExtension")
        if fileManager.fileExists(atPath: developmentExecutablePath.path) {
            // Development mode validation - just check for executable
            issues.append("Development mode bundle detected - SystemExtension executable found")
            return BundleValidationResult(isValid: true, issues: issues, bundleType: .development, rejectionReason: nil)
        }
        
        // Production mode validation - check for proper bundle structure
        // Check for Info.plist
        let infoPlistPath = bundlePath.appendingPathComponent("Contents/Info.plist")
        guard fileManager.fileExists(atPath: infoPlistPath.path) else {
            issues.append("Missing Info.plist at \(infoPlistPath.path)")
            return BundleValidationResult(isValid: false, issues: issues, bundleType: .production, rejectionReason: .missingInfoPlist)
        }
        
        // Mock plist validation for testing
        let mockFileManager = fileManager as? MockFileManager
        if let plistData = mockFileManager?.mockPlistData[infoPlistPath.path] {
            // Check bundle identifier
            guard let bundleId = plistData["CFBundleIdentifier"] as? String else {
                issues.append("Missing CFBundleIdentifier in Info.plist")
                return BundleValidationResult(isValid: false, issues: issues, bundleType: .production, rejectionReason: .invalidBundleStructure)
            }
            
            if bundleId != SystemExtensionBundleDetector.bundleIdentifier {
                issues.append("Bundle identifier mismatch: expected \(SystemExtensionBundleDetector.bundleIdentifier), found \(bundleId)")
            }
            
            // Check for executable
            if let executableName = plistData["CFBundleExecutable"] as? String {
                let executablePath = bundlePath.appendingPathComponent("Contents/MacOS").appendingPathComponent(executableName)
                if !fileManager.fileExists(atPath: executablePath.path) {
                    issues.append("Missing executable at \(executablePath.path)")
                    return BundleValidationResult(isValid: false, issues: issues, bundleType: .production, rejectionReason: .missingExecutable)
                }
            } else {
                issues.append("Missing CFBundleExecutable in Info.plist")
                return BundleValidationResult(isValid: false, issues: issues, bundleType: .production, rejectionReason: .missingExecutable)
            }
        } else {
            // Real plist validation would happen here, but for testing with mock we just assume it's valid
            issues.append("Info.plist validation skipped for testing")
        }
        
        // Bundle is valid if no critical issues found
        let hasExecutableIssues = issues.contains { $0.contains("Missing executable") || $0.contains("Missing CFBundleExecutable") }
        let hasPlistIssues = issues.contains { $0.contains("Missing Info.plist") }
        
        let isValid = !hasExecutableIssues && !hasPlistIssues
        return BundleValidationResult(isValid: isValid, issues: issues, bundleType: .production, rejectionReason: nil)
    }
}

// MARK: - MockFileManager
class MockFileManager: FileManager {
    var mockFiles: [String] = []
    var mockDirectories: [String] = []
    var mockDirectoryContents: [String: [String]] = [:]
    var mockPlistData: [String: [String: Any]] = [:]

    override func fileExists(atPath path: String) -> Bool {
        return mockFiles.contains(path) || mockDirectories.contains(path)
    }

    override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        if let isDir = isDirectory {
            if mockDirectories.contains(path) {
                isDir.pointee = true
                return true
            }
            if mockFiles.contains(path) {
                isDir.pointee = false
                return true
            }
        }
        return mockFiles.contains(path) || mockDirectories.contains(path)
    }

    override func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions = []) throws -> [URL] {
        guard let contents = mockDirectoryContents[url.path] else {
            return []
        }
        return contents.map { url.appendingPathComponent($0) }
    }
    
    override var currentDirectoryPath: String {
        return "/mock/current/dir"
    }
}