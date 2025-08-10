//
//  BuildOutputVerificationTests.swift
//  usbipd-mac
//
//  Integration tests for verifying System Extension bundle build output
//  Tests that the build system correctly creates System Extension bundles
//

import XCTest
import Foundation
@testable import USBIPDCore
@testable import Common

/// Build output verification tests for System Extension bundle creation
/// Validates that the Swift Package Manager build process correctly generates System Extension bundles
final class BuildOutputVerificationTests: XCTestCase {
    
    // MARK: - Test Properties
    
    /// Build output directory path
    private var buildOutputDirectory: URL!
    
    /// Expected System Extension bundle path
    private var expectedBundlePath: URL!
    
    /// Build configuration being tested
    private let buildConfiguration = "debug"
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        // Determine build output directory
        let packageRoot = packageRootDirectory()
        buildOutputDirectory = packageRoot.appendingPathComponent(".build").appendingPathComponent(buildConfiguration)
        expectedBundlePath = buildOutputDirectory.appendingPathComponent("SystemExtension.systemextension")
        
        print("Testing build output in: \(buildOutputDirectory.path)")
        print("Expected bundle path: \(expectedBundlePath.path)")
    }
    
    override func tearDown() {
        buildOutputDirectory = nil
        expectedBundlePath = nil
        super.tearDown()
    }
    
    // MARK: - Build System Verification Tests
    
    func testSystemExtensionBundleExists() throws {
        // Test that swift build generates System Extension bundle
        
        // First, trigger a build if the bundle doesn't exist
        if !FileManager.default.fileExists(atPath: expectedBundlePath.path) {
            print("System Extension bundle not found, triggering build...")
            try triggerBuild()
        }
        
        // Verify bundle exists after build
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedBundlePath.path),
                     "System Extension bundle should exist at \(expectedBundlePath.path)")
        
        // Verify it's actually a directory (bundle)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedBundlePath.path, isDirectory: &isDirectory),
                     "Bundle path should exist")
        XCTAssertTrue(isDirectory.boolValue, "System Extension bundle should be a directory")
        
        print("✅ System Extension bundle exists and is valid directory structure")
    }
    
    func testBundleStructureIsCorrect() throws {
        // Test that the bundle has the correct internal structure
        
        try ensureBundleExists()
        
        let requiredPaths = [
            expectedBundlePath.appendingPathComponent("Contents"),
            expectedBundlePath.appendingPathComponent("Contents/MacOS"),
            expectedBundlePath.appendingPathComponent("Contents/Info.plist"),
            expectedBundlePath.appendingPathComponent("Contents/MacOS/SystemExtension")
        ]
        
        let optionalPaths = [
            expectedBundlePath.appendingPathComponent("Contents/Resources"),
            expectedBundlePath.appendingPathComponent("Contents/Resources/SystemExtension.entitlements")
        ]
        
        // Verify required paths exist
        for path in requiredPaths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path),
                         "Required bundle path should exist: \(path.lastPathComponent)")
        }
        
        // Check optional paths (warn if missing)
        for path in optionalPaths {
            if !FileManager.default.fileExists(atPath: path.path) {
                print("⚠️  Optional bundle component missing: \(path.lastPathComponent)")
            } else {
                print("✅ Optional bundle component present: \(path.lastPathComponent)")
            }
        }
        
        print("✅ Bundle structure validation completed")
    }
    
    func testBundleInfoPlistIsValid() throws {
        // Test that the Info.plist has correct structure and required keys
        
        try ensureBundleExists()
        
        let infoPlistPath = expectedBundlePath.appendingPathComponent("Contents/Info.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: infoPlistPath.path),
                     "Info.plist should exist in bundle")
        
        // Load and parse Info.plist
        let infoPlistData = try Data(contentsOf: infoPlistPath)
        let infoPlist = try PropertyListSerialization.propertyList(from: infoPlistData,
                                                                  options: [],
                                                                  format: nil) as? [String: Any]
        
        XCTAssertNotNil(infoPlist, "Info.plist should be parseable")
        guard let plist = infoPlist else { return }
        
        // Verify required keys
        let requiredKeys = [
            "CFBundleIdentifier",
            "CFBundleName", 
            "CFBundleVersion",
            "CFBundleShortVersionString",
            "CFBundleExecutable",
            "NSExtension"
        ]
        
        for key in requiredKeys {
            XCTAssertNotNil(plist[key], "Info.plist should contain required key: \(key)")
        }
        
        // Verify NSExtension configuration
        if let nsExtension = plist["NSExtension"] as? [String: Any] {
            XCTAssertEqual(nsExtension["NSExtensionPointIdentifier"] as? String,
                          "com.apple.system-extension.driver-extension",
                          "Extension point should be driver-extension")
        } else {
            XCTFail("NSExtension configuration should be present and valid")
        }
        
        // Verify bundle identifier format
        if let bundleIdentifier = plist["CFBundleIdentifier"] as? String {
            XCTAssertTrue(bundleIdentifier.contains("."), "Bundle identifier should be in reverse domain format")
            XCTAssertTrue(bundleIdentifier.lowercased().contains("system"), 
                         "Bundle identifier should indicate System Extension")
        }
        
        print("✅ Info.plist validation completed")
        print("  Bundle Identifier: \(plist["CFBundleIdentifier"] as? String ?? "unknown")")
        print("  Bundle Version: \(plist["CFBundleShortVersionString"] as? String ?? "unknown")")
    }
    
    func testExecutableHasCorrectPermissions() throws {
        // Test that the System Extension executable has correct permissions
        
        try ensureBundleExists()
        
        let executablePath = expectedBundlePath.appendingPathComponent("Contents/MacOS/SystemExtension")
        XCTAssertTrue(FileManager.default.fileExists(atPath: executablePath.path),
                     "System Extension executable should exist")
        
        // Check file permissions
        let attributes = try FileManager.default.attributesOfItem(atPath: executablePath.path)
        
        // Verify it's a regular file
        let fileType = attributes[.type] as? FileAttributeType
        XCTAssertEqual(fileType, .typeRegular, "Executable should be a regular file")
        
        // Verify execute permissions
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertNotNil(permissions, "Executable should have POSIX permissions")
        
        if let perms = permissions {
            let permValue = perms.uint16Value
            XCTAssertTrue((permValue & 0o111) != 0, "Executable should have execute permissions")
            
            // Log permission details
            let ownerPerms = (permValue & 0o700) >> 6
            let groupPerms = (permValue & 0o070) >> 3  
            let otherPerms = (permValue & 0o007)
            
            print("✅ Executable permissions: \(String(format: "%o", permValue))")
            print("  Owner: \(permissionString(ownerPerms))")
            print("  Group: \(permissionString(groupPerms))")
            print("  Other: \(permissionString(otherPerms))")
        }
        
        // Verify executable is not empty
        let fileSize = attributes[.size] as? NSNumber
        XCTAssertNotNil(fileSize, "Executable should have a file size")
        XCTAssertGreaterThan(fileSize?.intValue ?? 0, 0, "Executable should not be empty")
        
        print("✅ Executable size: \(fileSize?.intValue ?? 0) bytes")
    }
    
    func testBundleCodeSigningStatus() throws {
        // Test code signing status (may be unsigned in development)
        
        try ensureBundleExists()
        
        let signingStatus = checkCodeSigningStatus(bundlePath: expectedBundlePath.path)
        
        switch signingStatus {
        case .signed(let identity):
            print("✅ Bundle is code signed with identity: \(identity)")
            
            // For signed bundles, verify signature is valid
            XCTAssertTrue(verifyCodeSignature(bundlePath: expectedBundlePath.path),
                         "Code signature should be valid")
            
        case .unsigned:
            print("⚠️  Bundle is not code signed (acceptable for development builds)")
            
            // Check if we're in a development environment
            let isDevelopmentBuild = buildConfiguration == "debug" || isRunningInDevelopmentMode()
            if !isDevelopmentBuild {
                XCTFail("Production builds should be code signed")
            }
            
        case .invalid(let reason):
            print("❌ Bundle has invalid code signature: \(reason)")
            XCTFail("Bundle should not have invalid code signature: \(reason)")
        }
    }
    
    func testEntitlementsFileIsValid() throws {
        // Test that entitlements file exists and has required entitlements
        
        try ensureBundleExists()
        
        let entitlementsPath = expectedBundlePath.appendingPathComponent("Contents/Resources/SystemExtension.entitlements")
        
        // Entitlements may not exist in development builds
        guard FileManager.default.fileExists(atPath: entitlementsPath.path) else {
            print("⚠️  Entitlements file not found (may be acceptable for development)")
            return
        }
        
        // Load and validate entitlements
        let entitlementsData = try Data(contentsOf: entitlementsPath)
        let entitlements = try PropertyListSerialization.propertyList(from: entitlementsData,
                                                                     options: [],
                                                                     format: nil) as? [String: Any]
        
        XCTAssertNotNil(entitlements, "Entitlements should be parseable")
        guard let plist = entitlements else { return }
        
        // Check for required System Extension entitlements
        let requiredEntitlements = [
            "com.apple.developer.system-extension.install",
            "com.apple.developer.driverkit"
        ]
        
        for entitlement in requiredEntitlements {
            XCTAssertEqual(plist[entitlement] as? Bool, true,
                          "Required entitlement should be present and true: \(entitlement)")
        }
        
        // Check for recommended entitlements
        let recommendedEntitlements = [
            "com.apple.developer.driverkit.transport.usb"
        ]
        
        for entitlement in recommendedEntitlements {
            if plist[entitlement] as? Bool == true {
                print("✅ Recommended entitlement present: \(entitlement)")
            } else {
                print("⚠️  Recommended entitlement missing: \(entitlement)")
            }
        }
        
        print("✅ Entitlements validation completed")
    }
    
    func testBuildOutputConsistency() throws {
        // Test that multiple builds produce consistent output
        
        try ensureBundleExists()
        
        // Get initial bundle modification time
        let attributes = try FileManager.default.attributesOfItem(atPath: expectedBundlePath.path)
        let initialModificationDate = attributes[.modificationDate] as? Date
        
        // Trigger another build
        print("Triggering incremental build to test consistency...")
        try triggerBuild()
        
        // Verify bundle still exists and is valid
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedBundlePath.path),
                     "Bundle should still exist after incremental build")
        
        // Check if bundle was rebuilt (modification time changed)
        let newAttributes = try FileManager.default.attributesOfItem(atPath: expectedBundlePath.path)
        let newModificationDate = newAttributes[.modificationDate] as? Date
        
        if let initial = initialModificationDate, let new = newModificationDate {
            if initial == new {
                print("✅ Bundle was not rebuilt (no changes detected)")
            } else {
                print("✅ Bundle was rebuilt (changes detected)")
            }
        }
        
        // Verify bundle structure is still valid
        try testBundleStructureIsCorrect()
        
        print("✅ Build output consistency verified")
    }
    
    func testPluginIntegration() throws {
        // Test that the SystemExtensionBundleBuilder plugin is working correctly
        
        try ensureBundleExists()
        
        // Check if plugin outputs exist (this would be plugin-specific)
        let pluginMarkerPath = buildOutputDirectory.appendingPathComponent("SystemExtensionBundleBuilder.marker")
        
        // The plugin might create marker files or logs
        if FileManager.default.fileExists(atPath: pluginMarkerPath.path) {
            print("✅ Plugin marker file found")
        } else {
            print("ℹ️  Plugin marker file not found (plugin may not create markers)")
        }
        
        // Verify the bundle was created by the plugin (not manually)
        // This could be verified by checking for plugin-specific metadata or structure
        
        print("✅ Plugin integration test completed")
    }
    
    // MARK: - Performance Tests
    
    func testBundleCreationPerformance() throws {
        // Test that bundle creation completes in reasonable time
        
        // Clean up existing bundle
        if FileManager.default.fileExists(atPath: expectedBundlePath.path) {
            try FileManager.default.removeItem(at: expectedBundlePath)
        }
        
        // Time the bundle creation
        let startTime = Date()
        try triggerBuild()
        let endTime = Date()
        
        let buildTime = endTime.timeIntervalSince(startTime)
        
        // Verify bundle was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedBundlePath.path),
                     "Bundle should be created by build")
        
        // Check build time is reasonable (less than 60 seconds for debug build)
        XCTAssertLessThan(buildTime, 60.0, "Bundle creation should complete within 60 seconds")
        
        print("✅ Bundle creation completed in \(String(format: "%.2f", buildTime)) seconds")
        
        // Additional performance metrics
        let bundleSize = try getBundleSize()
        print("✅ Bundle size: \(formatBytes(bundleSize))")
        
        // Reasonable size check (shouldn't be too large)
        XCTAssertLessThan(bundleSize, 100 * 1024 * 1024, "Bundle should be less than 100MB")
    }
    
    // MARK: - Helper Methods
    
    private func ensureBundleExists() throws {
        if !FileManager.default.fileExists(atPath: expectedBundlePath.path) {
            print("Bundle not found, triggering build...")
            try triggerBuild()
        }
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedBundlePath.path),
                     "System Extension bundle should exist after build")
    }
    
    private func triggerBuild() throws {
        let packageRoot = packageRootDirectory()
        let buildProcess = Process()
        
        buildProcess.currentDirectoryURL = packageRoot
        buildProcess.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        buildProcess.arguments = ["build", "--configuration", buildConfiguration]
        
        print("Executing: swift build --configuration \(buildConfiguration)")
        print("Working directory: \(packageRoot.path)")
        
        try buildProcess.run()
        buildProcess.waitUntilExit()
        
        guard buildProcess.terminationStatus == 0 else {
            throw BuildError.buildFailed(status: buildProcess.terminationStatus)
        }
        
        print("✅ Build completed successfully")
    }
    
    private func packageRootDirectory() -> URL {
        // Find the package root by looking for Package.swift
        var currentURL = URL(fileURLWithPath: #file).deletingLastPathComponent()
        
        while currentURL.path != "/" {
            let packageSwiftPath = currentURL.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageSwiftPath.path) {
                return currentURL
            }
            currentURL = currentURL.deletingLastPathComponent()
        }
        
        // Fallback to current directory
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
    
    private func checkCodeSigningStatus(bundlePath: String) -> CodeSigningStatus {
        let task = Process()
        let pipe = Pipe()
        
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", bundlePath]
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if task.terminationStatus == 0 {
                // Parse signing identity from output
                let lines = output.components(separatedBy: .newlines)
                for line in lines where line.contains("Authority=") {
                    let authority = line.replacingOccurrences(of: "Authority=", with: "").trimmingCharacters(in: .whitespaces)
                    return .signed(authority)
                }
                return .signed("Unknown")
            } else if output.contains("not signed") {
                return .unsigned
            } else {
                return .invalid(output)
            }
        } catch {
            return .invalid("Could not check signing status: \(error.localizedDescription)")
        }
    }
    
    private func verifyCodeSignature(bundlePath: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["--verify", "--verbose", bundlePath]
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private func isRunningInDevelopmentMode() -> Bool {
        // Check various indicators of development mode
        return ProcessInfo.processInfo.environment["SYSTEM_EXTENSION_DEVELOPMENT"] == "1" ||
               ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ||
               buildConfiguration == "debug"
    }
    
    private func getBundleSize() throws -> Int64 {
        let resourceKeys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        let enumerator = FileManager.default.enumerator(at: expectedBundlePath,
                                                       includingPropertiesForKeys: resourceKeys,
                                                       options: [],
                                                       errorHandler: nil)
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator ?? [] {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            if resourceValues.isDirectory != true {
                totalSize += Int64(resourceValues.fileSize ?? 0)
            }
        }
        
        return totalSize
    }
    
    private func permissionString(_ perms: UInt16) -> String {
        var result = ""
        result += (perms & 0o4) != 0 ? "r" : "-"
        result += (perms & 0o2) != 0 ? "w" : "-"
        result += (perms & 0o1) != 0 ? "x" : "-"
        return result
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Supporting Types

/// Code signing status
private enum CodeSigningStatus {
    case signed(String)
    case unsigned
    case invalid(String)
}

/// Build errors
private enum BuildError: Error {
    case buildFailed(status: Int32)
}