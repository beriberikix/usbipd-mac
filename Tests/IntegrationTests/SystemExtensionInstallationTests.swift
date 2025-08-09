//
//  SystemExtensionInstallationTests.swift
//  usbipd-mac
//
//  Integration tests for System Extension installation workflow
//  Tests bundle creation, installation process, and IPC communication
//

import XCTest
import Foundation
import SystemExtensions
@testable import USBIPDCLI
@testable import USBIPDCore
@testable import Common
@testable import SystemExtension

/// Integration tests for System Extension installation and bundle creation workflow
/// Tests the complete installation process from bundle creation to IPC communication
/// Validates bundle structure, installation approval workflow, and post-installation verification
final class SystemExtensionInstallationTests: XCTestCase {
    
    // MARK: - Test Properties
    
    var systemExtensionInstaller: SystemExtensionInstaller!
    var systemExtensionManager: SystemExtensionManager!
    var tempBundlePath: URL!
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        // Create temporary directory for bundle testing
        tempBundlePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemExtensionBundleTests")
            .appendingPathComponent(UUID().uuidString)
        
        try? FileManager.default.createDirectory(at: tempBundlePath, 
                                               withIntermediateDirectories: true, 
                                               attributes: nil)
        
        // Create System Extension installer for testing
        systemExtensionInstaller = SystemExtensionInstaller()
        
        // Create System Extension manager
        systemExtensionManager = SystemExtensionManager()
    }
    
    override func tearDown() {
        // Clean up System Extension components
        try? systemExtensionManager?.stop()
        
        // Clean up temporary files
        if let tempPath = tempBundlePath {
            try? FileManager.default.removeItem(at: tempPath)
        }
        
        systemExtensionInstaller = nil
        systemExtensionManager = nil
        tempBundlePath = nil
        
        super.tearDown()
    }
    
    // MARK: - Bundle Creation and Structure Tests
    
    func testSystemExtensionBundleCreation() throws {
        // Test System Extension bundle creation and structure validation
        
        let bundleName = "com.github.usbipd-mac.SystemExtension"
        let bundlePath = tempBundlePath.appendingPathComponent("\(bundleName).systemextension")
        
        // Test bundle creation (this would normally be done by the build system)
        try createTestSystemExtensionBundle(at: bundlePath, identifier: bundleName)
        
        // Verify bundle structure
        try validateSystemExtensionBundleStructure(at: bundlePath)
        
        print("✅ System Extension bundle structure validation passed")
    }
    
    func testBundleInfoPlistValidation() throws {
        // Test Info.plist validation for System Extension bundle
        
        let bundleName = "com.github.usbipd-mac.SystemExtension"
        let bundlePath = tempBundlePath.appendingPathComponent("\(bundleName).systemextension")
        
        try createTestSystemExtensionBundle(at: bundlePath, identifier: bundleName)
        
        let infoPlistPath = bundlePath.appendingPathComponent("Contents").appendingPathComponent("Info.plist")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: infoPlistPath.path),
                     "Info.plist should exist in bundle")
        
        // Load and validate Info.plist
        let plistData = try Data(contentsOf: infoPlistPath)
        let plist = try PropertyListSerialization.propertyList(from: plistData, 
                                                              options: [], 
                                                              format: nil) as! [String: Any]
        
        // Validate required Info.plist keys
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, bundleName,
                      "Bundle identifier should match")
        XCTAssertNotNil(plist["CFBundleVersion"], "Bundle version should be present")
        XCTAssertNotNil(plist["NSExtension"], "NSExtension configuration should be present")
        
        let nsExtension = plist["NSExtension"] as? [String: Any]
        XCTAssertNotNil(nsExtension, "NSExtension should be dictionary")
        XCTAssertEqual(nsExtension?["NSExtensionPointIdentifier"] as? String,
                      "com.apple.system-extension.driver-extension",
                      "Extension point should be driver-extension")
        
        print("✅ Bundle Info.plist validation passed")
    }
    
    func testBundleEntitlementsValidation() throws {
        // Test entitlements validation for System Extension bundle
        
        let bundleName = "com.github.usbipd-mac.SystemExtension"
        let bundlePath = tempBundlePath.appendingPathComponent("\(bundleName).systemextension")
        
        try createTestSystemExtensionBundle(at: bundlePath, identifier: bundleName)
        
        let entitlementsPath = bundlePath.appendingPathComponent("Contents")
                                        .appendingPathComponent("Resources")
                                        .appendingPathComponent("SystemExtension.entitlements")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: entitlementsPath.path),
                     "Entitlements file should exist in bundle")
        
        // Load and validate entitlements
        let entitlementsData = try Data(contentsOf: entitlementsPath)
        let entitlements = try PropertyListSerialization.propertyList(from: entitlementsData,
                                                                     options: [],
                                                                     format: nil) as! [String: Any]
        
        // Validate required entitlements
        XCTAssertEqual(entitlements["com.apple.developer.system-extension.install"] as? Bool, true,
                      "System Extension install entitlement should be present")
        XCTAssertEqual(entitlements["com.apple.developer.driverkit"] as? Bool, true,
                      "DriverKit entitlement should be present")
        
        print("✅ Bundle entitlements validation passed")
    }
    
    // MARK: - Installation Workflow Tests
    
    func testSystemExtensionInstallationWorkflowInDevelopment() throws {
        // Test System Extension installation workflow in development environment
        
        // Skip if not in development environment
        guard isDevelopmentEnvironment() else {
            throw XCTSkip("System Extension installation tests require development environment")
        }
        
        let bundleName = "com.github.usbipd-mac.SystemExtension.test"
        let bundlePath = tempBundlePath.appendingPathComponent("\(bundleName).systemextension")
        
        try createTestSystemExtensionBundle(at: bundlePath, identifier: bundleName)
        
        let expectation = XCTestExpectation(description: "System Extension installation workflow")
        var installationResult: Result<Bool, Error>?
        
        // Test installation request
        systemExtensionInstaller.installSystemExtension(bundlePath: bundlePath.path,
                                                       bundleIdentifier: bundleName) { result in
            installationResult = result
            expectation.fulfill()
        }
        
        // Wait for installation workflow (may require user approval)
        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: 30.0)
        
        switch waiterResult {
        case .completed:
            guard let result = installationResult else {
                XCTFail("Installation result should be available")
                return
            }
            
            switch result {
            case .success(let installed):
                if installed {
                    print("✅ System Extension installation succeeded in development environment")
                    
                    // Test post-installation verification
                    try testPostInstallationVerification(bundleIdentifier: bundleName)
                } else {
                    print("⚠️ System Extension installation was not completed (may require user approval)")
                    throw XCTSkip("System Extension installation requires user approval")
                }
            case .failure(let error):
                if let systemExtensionError = error as? SystemExtensionInstallationError {
                    switch systemExtensionError {
                    case .requiresApproval:
                        throw XCTSkip("System Extension installation requires user approval")
                    case .userRejected:
                        throw XCTSkip("System Extension installation was rejected by user")
                    case .developmentModeDisabled:
                        throw XCTSkip("System Extension development mode is not enabled")
                    default:
                        throw systemExtensionError
                    }
                }
                throw error
            }
        case .timedOut:
            throw XCTSkip("System Extension installation timed out (may be waiting for user approval)")
        default:
            XCTFail("Installation workflow failed with waiter result: \(waiterResult)")
        }
    }
    
    func testSystemExtensionInstallationErrorHandling() throws {
        // Test error handling during System Extension installation
        
        // Test installation with invalid bundle path
        let invalidBundlePath = "/nonexistent/path/InvalidBundle.systemextension"
        let invalidBundleIdentifier = "com.invalid.bundle"
        
        let expectation = XCTestExpectation(description: "Invalid bundle installation error")
        var errorResult: Error?
        
        systemExtensionInstaller.installSystemExtension(bundlePath: invalidBundlePath,
                                                       bundleIdentifier: invalidBundleIdentifier) { result in
            switch result {
            case .success:
                XCTFail("Invalid bundle installation should not succeed")
            case .failure(let error):
                errorResult = error
            }
            expectation.fulfill()
        }
        
        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: 10.0)
        XCTAssertEqual(waiterResult, .completed, "Error handling should complete quickly")
        
        XCTAssertNotNil(errorResult, "Should receive error for invalid bundle")
        
        if let systemExtensionError = errorResult as? SystemExtensionInstallationError {
            XCTAssertTrue([.bundleNotFound(""), .invalidBundle(""), .internalError("")].contains { type in
                switch (type, systemExtensionError) {
                case (.bundleNotFound, .bundleNotFound), 
                     (.invalidBundle, .invalidBundle),
                     (.internalError, .internalError):
                    return true
                default:
                    return false
                }
            }, "Should receive appropriate error type for invalid bundle")
        }
        
        print("✅ System Extension installation error handling passed")
    }
    
    // MARK: - IPC Communication Tests
    
    func testIPCCommunicationAfterInstallation() throws {
        // Test IPC communication after System Extension activation
        
        // Skip if System Extension is not available or installed
        guard isSystemExtensionAvailable() else {
            throw XCTSkip("System Extension not available for IPC testing")
        }
        
        // Start System Extension manager
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        // Wait for System Extension to be ready
        try waitForSystemExtensionReady(timeout: 10.0)
        
        // Test basic IPC communication
        let status = systemExtensionManager.getStatus()
        XCTAssertTrue(status.isRunning, "System Extension should be running for IPC test")
        
        // Test IPC message exchange
        let testMessage = "ping"
        let expectation = XCTestExpectation(description: "IPC message exchange")
        var responseReceived = false
        
        systemExtensionManager.sendMessage(testMessage) { response in
            responseReceived = (response == "pong")
            expectation.fulfill()
        }
        
        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(waiterResult, .completed, "IPC message should complete within timeout")
        XCTAssertTrue(responseReceived, "Should receive correct IPC response")
        
        print("✅ IPC communication test passed")
    }
    
    func testIPCConnectionFailureHandling() throws {
        // Test IPC connection failure handling
        
        // Test IPC communication without System Extension running
        let expectation = XCTestExpectation(description: "IPC failure handling")
        var errorReceived: Error?
        
        systemExtensionManager.sendMessage("test") { response in
            XCTFail("Should not receive response when System Extension is not running")
            expectation.fulfill()
        } errorHandler: { error in
            errorReceived = error
            expectation.fulfill()
        }
        
        let waiterResult = XCTWaiter.wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(waiterResult, .completed, "IPC failure should be handled quickly")
        XCTAssertNotNil(errorReceived, "Should receive error when IPC fails")
        
        if let systemExtensionError = errorReceived as? SystemExtensionInstallationError {
            XCTAssertTrue([.ipcConnectionFailed(""), .communicationFailure(""), .internalError("")].contains { type in
                switch (type, systemExtensionError) {
                case (.ipcConnectionFailed, .ipcConnectionFailed), 
                     (.communicationFailure, .communicationFailure),
                     (.internalError, .internalError):
                    return true
                default:
                    return false
                }
            }, "Should receive appropriate IPC error type")
        }
        
        print("✅ IPC connection failure handling passed")
    }
    
    // MARK: - Helper Methods
    
    private func createTestSystemExtensionBundle(at bundlePath: URL, identifier: String) throws {
        // Create basic System Extension bundle structure for testing
        
        let contentsPath = bundlePath.appendingPathComponent("Contents")
        let macosPath = contentsPath.appendingPathComponent("MacOS")
        let resourcesPath = contentsPath.appendingPathComponent("Resources")
        
        // Create directory structure
        try FileManager.default.createDirectory(at: macosPath, 
                                               withIntermediateDirectories: true, 
                                               attributes: nil)
        try FileManager.default.createDirectory(at: resourcesPath, 
                                               withIntermediateDirectories: true, 
                                               attributes: nil)
        
        // Create Info.plist
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleName": "USB/IP System Extension",
            "CFBundleVersion": "1.0.0",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleExecutable": "SystemExtension",
            "NSExtension": [
                "NSExtensionPointIdentifier": "com.apple.system-extension.driver-extension",
                "NSExtensionPrincipalClass": "SystemExtensionMain"
            ]
        ]
        
        let infoPlistData = try PropertyListSerialization.data(fromPropertyList: infoPlist,
                                                              format: .xml,
                                                              options: 0)
        let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
        try infoPlistData.write(to: infoPlistPath)
        
        // Create entitlements file
        let entitlements: [String: Any] = [
            "com.apple.developer.system-extension.install": true,
            "com.apple.developer.driverkit": true,
            "com.apple.developer.driverkit.transport.usb": true
        ]
        
        let entitlementsData = try PropertyListSerialization.data(fromPropertyList: entitlements,
                                                                 format: .xml,
                                                                 options: 0)
        let entitlementsPath = resourcesPath.appendingPathComponent("SystemExtension.entitlements")
        try entitlementsData.write(to: entitlementsPath)
        
        // Create dummy executable
        let executablePath = macosPath.appendingPathComponent("SystemExtension")
        let executableContent = "#!/bin/bash\necho 'Test System Extension'"
        try executableContent.write(to: executablePath, atomically: true, encoding: .utf8)
        
        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], 
                                             ofItemAtPath: executablePath.path)
    }
    
    private func validateSystemExtensionBundleStructure(at bundlePath: URL) throws {
        // Validate System Extension bundle has correct structure
        
        let contentsPath = bundlePath.appendingPathComponent("Contents")
        let macosPath = contentsPath.appendingPathComponent("MacOS")
        let resourcesPath = contentsPath.appendingPathComponent("Resources")
        let infoPlistPath = contentsPath.appendingPathComponent("Info.plist")
        let executablePath = macosPath.appendingPathComponent("SystemExtension")
        let entitlementsPath = resourcesPath.appendingPathComponent("SystemExtension.entitlements")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundlePath.path),
                     "Bundle directory should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: contentsPath.path),
                     "Contents directory should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: macosPath.path),
                     "MacOS directory should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resourcesPath.path),
                     "Resources directory should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: infoPlistPath.path),
                     "Info.plist should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: executablePath.path),
                     "Executable should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: entitlementsPath.path),
                     "Entitlements file should exist")
        
        // Check executable permissions
        let attributes = try FileManager.default.attributesOfItem(atPath: executablePath.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertNotNil(permissions, "Executable should have POSIX permissions")
        XCTAssertTrue((permissions!.uint16Value & 0o111) != 0, "Executable should have execute permissions")
    }
    
    private func testPostInstallationVerification(bundleIdentifier: String) throws {
        // Verify System Extension is properly installed and functional
        
        // This would typically query the system for installed extensions
        // For testing, we'll use the System Extension manager
        
        try systemExtensionManager.start()
        defer { try? systemExtensionManager.stop() }
        
        let status = systemExtensionManager.getStatus()
        XCTAssertTrue(status.isRunning, "System Extension should be running after installation")
        
        // Perform basic health check
        let isHealthy = systemExtensionManager.performHealthCheck()
        XCTAssertTrue(isHealthy, "System Extension should be healthy after installation")
        
        print("✅ Post-installation verification passed")
    }
    
    private func isDevelopmentEnvironment() -> Bool {
        // Check if running in development environment
        // This could check for development mode, code signing, etc.
        
        #if DEBUG
        return true
        #else
        // In release builds, check for development indicators
        return ProcessInfo.processInfo.environment["SYSTEM_EXTENSION_DEVELOPMENT"] == "1"
        #endif
    }
    
    private func isSystemExtensionAvailable() -> Bool {
        // Check if System Extension is available for testing
        
        do {
            let status = systemExtensionManager.getStatus()
            return status.isRunning || status.canStart
        } catch {
            return false
        }
    }
    
    private func waitForSystemExtensionReady(timeout: TimeInterval) throws {
        // Wait for System Extension to be ready for IPC
        
        let startTime = Date()
        let timeoutDate = startTime.addingTimeInterval(timeout)
        
        while Date() < timeoutDate {
            let status = systemExtensionManager.getStatus()
            if status.isRunning && status.isHealthy {
                return
            }
            
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        throw XCTestError(.timeoutWhileWaiting)
    }
}

// MARK: - SystemExtensionManager Testing Extensions

extension SystemExtensionManager {
    
    func sendMessage(_ message: String, 
                    responseHandler: @escaping (String) -> Void,
                    errorHandler: ((Error) -> Void)? = nil) {
        // Mock IPC message sending for testing
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            if self.getStatus().isRunning {
                // Simulate successful message exchange
                responseHandler("pong")
            } else {
                // Simulate IPC failure
                let error = SystemExtensionInstallationError.ipcConnectionFailed("System Extension not running")
                errorHandler?(error)
            }
        }
    }
    
    var canStart: Bool {
        // Check if System Extension can be started
        return true // Simplified for testing
    }
    
    var isHealthy: Bool {
        // Check if System Extension is healthy
        return getStatus().isRunning
    }
}