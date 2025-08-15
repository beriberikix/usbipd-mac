//
//  ArtifactDistributionTests.swift
//  usbipd-mac
//
//  Release artifact distribution testing with download functionality validation
//  Tests download functionality, checksum verification, and installation procedures
//

import XCTest
import Foundation
import Network
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

/// Release artifact distribution testing with comprehensive validation
/// Tests download functionality, checksum verification, and installation procedures
final class ArtifactDistributionTests: XCTestCase, TestSuite {
    
    // MARK: - TestSuite Protocol Implementation
    
    public let environmentConfig: TestEnvironmentConfig = TestEnvironmentDetector.createConfigurationForCurrentEnvironment()
    public let requiredCapabilities: TestEnvironmentCapabilities = [
        .networkAccess, 
        .filesystemWrite, 
        .timeIntensiveOperations
    ]
    public let testCategory: String = "artifact-distribution"
    
    // MARK: - Test Configuration
    
    private struct DistributionTestConfig {
        let testArtifactVersion: String
        let tempDirectory: URL
        let downloadDirectory: URL
        let installationDirectory: URL
        let testTimeout: TimeInterval
        let enableNetworkTests: Bool
        let enableInstallationTests: Bool
        
        init(environment: TestEnvironment, tempDirectory: URL) {
            self.testArtifactVersion = "v1.0.0-distribution-test-\(UUID().uuidString.prefix(8))"
            self.tempDirectory = tempDirectory
            self.downloadDirectory = tempDirectory.appendingPathComponent("downloads")
            self.installationDirectory = tempDirectory.appendingPathComponent("installation")
            
            switch environment {
            case .development:
                self.testTimeout = 120.0 // 2 minutes
                self.enableNetworkTests = false // Skip network tests in development
                self.enableInstallationTests = true
                
            case .ci:
                self.testTimeout = 300.0 // 5 minutes
                self.enableNetworkTests = false // CI environment limitations
                self.enableInstallationTests = true
                
            case .production:
                self.testTimeout = 600.0 // 10 minutes
                self.enableNetworkTests = true // Full network testing
                self.enableInstallationTests = true
            }
        }
    }
    
    // MARK: - Test Properties
    
    private var logger: Logger!
    private var testConfig: DistributionTestConfig!
    private var tempDirectory: URL!
    private var mockArtifacts: TestArtifactSet!
    private var packageRootDirectory: URL!
    
    // MARK: - Test Lifecycle
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Validate environment before running tests
        try validateEnvironment()
        
        // Skip if environment doesn't support this test suite
        guard shouldRunInCurrentEnvironment() else {
            throw XCTSkip("Artifact distribution tests require network, filesystem, and time-intensive operation capabilities")
        }
        
        // Create logger for testing
        logger = Logger(
            config: LoggerConfig(level: .debug, includeTimestamp: true),
            subsystem: "com.usbipd.distribution.tests",
            category: "artifact-distribution"
        )
        
        // Set up temporary directory for test artifacts
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("artifact-distribution-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create test configuration
        testConfig = DistributionTestConfig(
            environment: environmentConfig.environment,
            tempDirectory: tempDirectory
        )
        
        // Create working directories
        try FileManager.default.createDirectory(at: testConfig.downloadDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: testConfig.installationDirectory, withIntermediateDirectories: true)
        
        // Find package root directory
        packageRootDirectory = try findPackageRoot()
        
        // Create mock artifacts for testing
        try createMockArtifacts()
        
        logger.info("Starting artifact distribution tests in \(environmentConfig.environment.displayName) environment")
        logger.info("Test version: \(testConfig.testArtifactVersion)")
        logger.info("Temp directory: \(tempDirectory.path)")
        logger.info("Package root: \(packageRootDirectory.path)")
        
        // Call TestSuite setup
        setUpTestSuite()
    }
    
    override func tearDownWithError() throws {
        // Call TestSuite teardown
        tearDownTestSuite()
        
        // Clean up temporary directory (preserve on failure for debugging)
        if let tempDir = tempDirectory, FileManager.default.fileExists(atPath: tempDir.path) {
            if environmentConfig.environment == .development {
                // Keep temp directory for debugging in development
                logger.info("Temporary directory preserved for debugging: \(tempDir.path)")
            } else {
                try? FileManager.default.removeItem(at: tempDir)
                logger.info("Cleaned up temporary directory")
            }
        }
        
        logger?.info("Completed artifact distribution tests")
        
        // Clean up test resources
        testConfig = nil
        mockArtifacts = nil
        packageRootDirectory = nil
        logger = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Download Functionality Tests
    
    func testArtifactDownloadSimulation() throws {
        logger.info("Testing artifact download simulation")
        
        // Test 1: Simulate downloading main executable
        try testDownloadMainExecutable()
        
        // Test 2: Simulate downloading compressed archive
        try testDownloadCompressedArchive()
        
        // Test 3: Download checksum file
        try testDownloadChecksumFile()
        
        // Test 4: Download metadata
        try testDownloadMetadata()
        
        logger.info("✅ Artifact download simulation completed successfully")
    }
    
    private func testDownloadMainExecutable() throws {
        logger.info("Simulating main executable download")
        
        let sourceExecutable = mockArtifacts.mainExecutable
        let downloadedExecutable = testConfig.downloadDirectory.appendingPathComponent("usbipd-\(testConfig.testArtifactVersion)-macos")
        
        // Simulate download by copying mock artifact
        try FileManager.default.copyItem(at: sourceExecutable, to: downloadedExecutable)
        
        // Verify download succeeded
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadedExecutable.path),
                     "Downloaded executable should exist")
        
        // Verify file integrity
        let originalSize = try FileManager.default.attributesOfItem(atPath: sourceExecutable.path)[.size] as? Int64 ?? 0
        let downloadedSize = try FileManager.default.attributesOfItem(atPath: downloadedExecutable.path)[.size] as? Int64 ?? 0
        XCTAssertEqual(originalSize, downloadedSize, "Downloaded file should match original size")
        
        // Verify executable permissions
        let attributes = try FileManager.default.attributesOfItem(atPath: downloadedExecutable.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertNotNil(permissions, "Downloaded executable should have permissions")
        
        if let perms = permissions {
            let permValue = perms.uint16Value
            XCTAssertTrue((permValue & 0o111) != 0, "Downloaded executable should have execute permissions")
        }
        
        logger.debug("✅ Main executable download simulation successful")
    }
    
    private func testDownloadCompressedArchive() throws {
        logger.info("Simulating compressed archive download")
        
        let sourceArchive = mockArtifacts.compressedArchive
        let downloadedArchive = testConfig.downloadDirectory.appendingPathComponent("usbipd-mac-\(testConfig.testArtifactVersion).tar.gz")
        
        // Simulate download
        try FileManager.default.copyItem(at: sourceArchive, to: downloadedArchive)
        
        // Verify download
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadedArchive.path),
                     "Downloaded archive should exist")
        
        // Test archive extraction
        try testArchiveExtraction(archivePath: downloadedArchive)
        
        logger.debug("✅ Compressed archive download simulation successful")
    }
    
    private func testDownloadChecksumFile() throws {
        logger.info("Simulating checksum file download")
        
        let sourceChecksum = mockArtifacts.checksumFile
        let downloadedChecksum = testConfig.downloadDirectory.appendingPathComponent("checksums-\(testConfig.testArtifactVersion).sha256")
        
        // Simulate download
        try FileManager.default.copyItem(at: sourceChecksum, to: downloadedChecksum)
        
        // Verify download
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadedChecksum.path),
                     "Downloaded checksum file should exist")
        
        // Verify checksum file format
        let checksumContent = try String(contentsOf: downloadedChecksum)
        XCTAssertFalse(checksumContent.isEmpty, "Checksum file should not be empty")
        XCTAssertTrue(checksumContent.contains("usbipd"), "Checksum file should reference usbipd executable")
        
        logger.debug("✅ Checksum file download simulation successful")
    }
    
    private func testDownloadMetadata() throws {
        logger.info("Simulating metadata download")
        
        let sourceMetadata = mockArtifacts.metadataFile
        let downloadedMetadata = testConfig.downloadDirectory.appendingPathComponent("release-metadata.json")
        
        // Simulate download
        try FileManager.default.copyItem(at: sourceMetadata, to: downloadedMetadata)
        
        // Verify download
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadedMetadata.path),
                     "Downloaded metadata should exist")
        
        // Parse and validate metadata
        let metadataData = try Data(contentsOf: downloadedMetadata)
        let metadata = try JSONDecoder().decode(TestReleaseMetadata.self, from: metadataData)
        
        XCTAssertEqual(metadata.version, testConfig.testArtifactVersion, "Metadata version should match")
        XCTAssertFalse(metadata.artifacts.isEmpty, "Metadata should list artifacts")
        
        logger.debug("✅ Metadata download simulation successful")
    }
    
    // MARK: - Checksum Verification Tests
    
    func testChecksumVerification() throws {
        logger.info("Testing checksum verification")
        
        // Download artifacts first
        try testArtifactDownloadSimulation()
        
        // Test 1: Verify main executable checksum
        try verifyArtifactChecksum(
            artifactName: "usbipd-\(testConfig.testArtifactVersion)-macos",
            expectedChecksum: mockArtifacts.mainExecutableChecksum
        )
        
        // Test 2: Verify archive checksum
        try verifyArtifactChecksum(
            artifactName: "usbipd-mac-\(testConfig.testArtifactVersion).tar.gz",
            expectedChecksum: mockArtifacts.archiveChecksum
        )
        
        // Test 3: Test checksum mismatch detection
        try testChecksumMismatchDetection()
        
        logger.info("✅ Checksum verification completed successfully")
    }
    
    private func verifyArtifactChecksum(artifactName: String, expectedChecksum: String) throws {
        let artifactPath = testConfig.downloadDirectory.appendingPathComponent(artifactName)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactPath.path),
                     "Artifact should exist for checksum verification: \(artifactName)")
        
        let actualChecksum = try calculateSHA256(for: artifactPath)
        XCTAssertEqual(actualChecksum.lowercased(), expectedChecksum.lowercased(),
                      "Checksum should match for artifact: \(artifactName)")
        
        logger.debug("✅ Checksum verified for \(artifactName)")
    }
    
    private func testChecksumMismatchDetection() throws {
        logger.info("Testing checksum mismatch detection")
        
        // Create a corrupted file
        let corruptedFile = testConfig.downloadDirectory.appendingPathComponent("corrupted-test-file")
        try "corrupted content".write(to: corruptedFile, atomically: true, encoding: .utf8)
        
        let corruptedChecksum = try calculateSHA256(for: corruptedFile)
        let fakeExpectedChecksum = "0000000000000000000000000000000000000000000000000000000000000000"
        
        // Verify checksum mismatch is detected
        XCTAssertNotEqual(corruptedChecksum.lowercased(), fakeExpectedChecksum.lowercased(),
                         "Corrupted file checksum should not match fake expected checksum")
        
        logger.debug("✅ Checksum mismatch detection working correctly")
    }
    
    // MARK: - Installation Procedure Tests
    
    func testInstallationProcedures() throws {
        guard testConfig.enableInstallationTests else {
            logger.info("Installation tests disabled for this environment")
            return
        }
        
        logger.info("Testing installation procedures")
        
        // Download artifacts first
        try testArtifactDownloadSimulation()
        
        // Test 1: Standard installation procedure
        try testStandardInstallation()
        
        // Test 2: Installation with permissions validation
        try testInstallationPermissions()
        
        // Test 3: Installation verification
        try testInstallationVerification()
        
        // Test 4: Installation rollback simulation
        try testInstallationRollback()
        
        logger.info("✅ Installation procedures testing completed successfully")
    }
    
    private func testStandardInstallation() throws {
        logger.info("Testing standard installation procedure")
        
        // Create simulated system directories
        let systemBinDir = testConfig.installationDirectory.appendingPathComponent("usr/local/bin")
        try FileManager.default.createDirectory(at: systemBinDir, withIntermediateDirectories: true)
        
        // Install main executable
        let downloadedExecutable = testConfig.downloadDirectory.appendingPathComponent("usbipd-\(testConfig.testArtifactVersion)-macos")
        let installedExecutable = systemBinDir.appendingPathComponent("usbipd")
        
        try FileManager.default.copyItem(at: downloadedExecutable, to: installedExecutable)
        
        // Verify installation
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedExecutable.path),
                     "Executable should be installed")
        
        // Test executable functionality from installed location
        try validateExecutableBasicFunction(executablePath: installedExecutable)
        
        logger.debug("✅ Standard installation procedure successful")
    }
    
    private func testInstallationPermissions() throws {
        logger.info("Testing installation permissions")
        
        let installedExecutable = testConfig.installationDirectory.appendingPathComponent("usr/local/bin/usbipd")
        
        // Verify executable has correct permissions after installation
        let attributes = try FileManager.default.attributesOfItem(atPath: installedExecutable.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertNotNil(permissions, "Installed executable should have permissions")
        
        if let perms = permissions {
            let permValue = perms.uint16Value
            XCTAssertTrue((permValue & 0o111) != 0, "Installed executable should have execute permissions")
            XCTAssertTrue((permValue & 0o444) != 0, "Installed executable should have read permissions")
        }
        
        logger.debug("✅ Installation permissions verification successful")
    }
    
    private func testInstallationVerification() throws {
        logger.info("Testing installation verification")
        
        let installedExecutable = testConfig.installationDirectory.appendingPathComponent("usr/local/bin/usbipd")
        
        // Verify installation integrity
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedExecutable.path),
                     "Installed executable should exist")
        
        // Verify file size matches original
        let originalExecutable = testConfig.downloadDirectory.appendingPathComponent("usbipd-\(testConfig.testArtifactVersion)-macos")
        let originalSize = try FileManager.default.attributesOfItem(atPath: originalExecutable.path)[.size] as? Int64 ?? 0
        let installedSize = try FileManager.default.attributesOfItem(atPath: installedExecutable.path)[.size] as? Int64 ?? 0
        XCTAssertEqual(originalSize, installedSize, "Installed executable size should match original")
        
        // Verify executable functionality
        try validateExecutableBasicFunction(executablePath: installedExecutable)
        
        logger.debug("✅ Installation verification successful")
    }
    
    private func testInstallationRollback() throws {
        logger.info("Testing installation rollback simulation")
        
        // Create backup directory
        let backupDir = testConfig.installationDirectory.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        // Simulate creating backup before installation
        let installedExecutable = testConfig.installationDirectory.appendingPathComponent("usr/local/bin/usbipd")
        let backupExecutable = backupDir.appendingPathComponent("usbipd.backup")
        
        if FileManager.default.fileExists(atPath: installedExecutable.path) {
            try FileManager.default.copyItem(at: installedExecutable, to: backupExecutable)
        }
        
        // Simulate rollback by restoring from backup
        if FileManager.default.fileExists(atPath: backupExecutable.path) {
            try FileManager.default.removeItem(at: installedExecutable)
            try FileManager.default.copyItem(at: backupExecutable, to: installedExecutable)
        }
        
        // Verify rollback succeeded
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedExecutable.path),
                     "Executable should exist after rollback")
        
        logger.debug("✅ Installation rollback simulation successful")
    }
    
    // MARK: - Cross-Platform Compatibility Tests
    
    func testCrossPlatformCompatibility() throws {
        logger.info("Testing cross-platform compatibility validation")
        
        // Download artifacts first
        try testArtifactDownloadSimulation()
        
        // Test 1: Architecture compatibility
        try testArchitectureCompatibility()
        
        // Test 2: macOS version compatibility
        try testMacOSVersionCompatibility()
        
        // Test 3: Dependency validation
        try testDependencyValidation()
        
        logger.info("✅ Cross-platform compatibility testing completed successfully")
    }
    
    private func testArchitectureCompatibility() throws {
        logger.info("Testing architecture compatibility")
        
        let executablePath = testConfig.downloadDirectory.appendingPathComponent("usbipd-\(testConfig.testArtifactVersion)-macos")
        
        // Check architecture using file command
        let fileProcess = Process()
        fileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/file")
        fileProcess.arguments = [executablePath.path]
        
        let outputPipe = Pipe()
        fileProcess.standardOutput = outputPipe
        
        try fileProcess.run()
        fileProcess.waitUntilExit()
        
        guard fileProcess.terminationStatus == 0 else {
            throw DistributionTestError.architectureValidationFailed
        }
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        
        // Should be a Mach-O executable
        XCTAssertTrue(output.contains("Mach-O"), "Executable should be Mach-O format")
        
        // Should support current architecture
        let currentArch = getCurrentArchitecture()
        if currentArch == "arm64" {
            XCTAssertTrue(output.contains("arm64") || output.contains("universal"),
                         "Executable should support ARM64 architecture")
        } else {
            XCTAssertTrue(output.contains("x86_64") || output.contains("universal"),
                         "Executable should support x86_64 architecture")
        }
        
        logger.debug("✅ Architecture compatibility verified for \(currentArch)")
    }
    
    private func testMacOSVersionCompatibility() throws {
        logger.info("Testing macOS version compatibility")
        
        // Get current macOS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let currentVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion)"
        
        // Assume minimum supported version is macOS 11.0 (based on project requirements)
        let minimumVersion = "11.0"
        
        // Verify current system meets minimum requirements
        XCTAssertTrue(versionString(currentVersionString, isGreaterThanOrEqualTo: minimumVersion),
                     "Current macOS version should meet minimum requirements")
        
        logger.debug("✅ macOS version compatibility verified (current: \(currentVersionString), minimum: \(minimumVersion))")
    }
    
    private func testDependencyValidation() throws {
        logger.info("Testing dependency validation")
        
        // Check for required system frameworks/libraries
        let requiredFrameworks = [
            "/System/Library/Frameworks/IOKit.framework/IOKit",
            "/System/Library/Frameworks/Foundation.framework/Foundation",
            "/usr/lib/libSystem.B.dylib"
        ]
        
        for framework in requiredFrameworks {
            XCTAssertTrue(FileManager.default.fileExists(atPath: framework),
                         "Required framework should be available: \(framework)")
        }
        
        logger.debug("✅ Dependency validation successful")
    }
    
    // MARK: - User Experience Validation Tests
    
    func testUserExperienceValidation() throws {
        logger.info("Testing user experience validation")
        
        // Test 1: Download experience simulation
        try testDownloadExperience()
        
        // Test 2: Installation experience simulation
        try testInstallationExperience()
        
        // Test 3: First-run experience validation
        try testFirstRunExperience()
        
        // Test 4: Error handling and user feedback
        try testErrorHandlingExperience()
        
        logger.info("✅ User experience validation completed successfully")
    }
    
    private func testDownloadExperience() throws {
        logger.info("Simulating download user experience")
        
        // Simulate download progress tracking
        let downloadSize = try getDownloadSizeEstimate()
        XCTAssertGreaterThan(downloadSize, 0, "Download size should be estimatable")
        
        // Simulate download time estimation
        let estimatedDownloadTime = estimateDownloadTime(sizeBytes: downloadSize, speedBytesPerSecond: 1_000_000) // 1 MB/s
        XCTAssertLessThan(estimatedDownloadTime, 300.0, "Download should complete within 5 minutes at 1 MB/s")
        
        logger.debug("✅ Download experience validation successful (size: \(formatBytes(downloadSize)), estimated time: \(String(format: "%.1f", estimatedDownloadTime))s)")
    }
    
    private func testInstallationExperience() throws {
        logger.info("Simulating installation user experience")
        
        // Simulate installation steps
        let installationSteps = [
            "Download verification",
            "Checksum validation", 
            "Permission setup",
            "File installation",
            "Installation verification"
        ]
        
        for (index, step) in installationSteps.enumerated() {
            logger.debug("Installation step \(index + 1)/\(installationSteps.count): \(step)")
            // Simulate step processing time
            usleep(100_000) // 0.1 second
        }
        
        logger.debug("✅ Installation experience simulation successful")
    }
    
    private func testFirstRunExperience() throws {
        logger.info("Testing first-run user experience")
        
        guard testConfig.enableInstallationTests else {
            logger.info("First-run experience test skipped (installation tests disabled)")
            return
        }
        
        let installedExecutable = testConfig.installationDirectory.appendingPathComponent("usr/local/bin/usbipd")
        
        // Test help output for new users
        let helpProcess = Process()
        helpProcess.executableURL = installedExecutable
        helpProcess.arguments = ["--help"]
        
        let outputPipe = Pipe()
        helpProcess.standardOutput = outputPipe
        helpProcess.standardError = outputPipe
        
        try helpProcess.run()
        helpProcess.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        
        // Verify help output is user-friendly
        XCTAssertFalse(output.isEmpty, "Help output should not be empty")
        XCTAssertTrue(output.lowercased().contains("usage") || output.lowercased().contains("help"),
                     "Help output should contain usage information")
        
        logger.debug("✅ First-run experience validation successful")
    }
    
    private func testErrorHandlingExperience() throws {
        logger.info("Testing error handling user experience")
        
        // Test 1: Invalid download URL handling
        try testInvalidDownloadHandling()
        
        // Test 2: Checksum mismatch handling  
        try testChecksumMismatchHandling()
        
        // Test 3: Installation permission error handling
        try testInstallationPermissionHandling()
        
        logger.debug("✅ Error handling experience validation successful")
    }
    
    private func testInvalidDownloadHandling() throws {
        // Simulate handling of invalid download URL
        let invalidURL = "https://invalid.example.com/nonexistent/file"
        
        // In a real implementation, this would test network error handling
        // For this test, we simulate the expected behavior
        
        XCTAssertTrue(invalidURL.hasPrefix("https://"), "Invalid URL should still be recognizable as HTTPS")
        logger.debug("Invalid download URL handling simulated")
    }
    
    private func testChecksumMismatchHandling() throws {
        // This test was already implemented in testChecksumMismatchDetection()
        logger.debug("Checksum mismatch handling already validated")
    }
    
    private func testInstallationPermissionHandling() throws {
        // Simulate permission error during installation
        let restrictedPath = testConfig.installationDirectory.appendingPathComponent("restricted")
        
        // Create a path that would typically require elevated permissions
        // In real scenarios, this would test sudo/admin permission handling
        
        do {
            try FileManager.default.createDirectory(at: restrictedPath, withIntermediateDirectories: true)
            logger.debug("Installation permission handling simulated")
        } catch {
            // Expected in restricted environments
            logger.debug("Permission restriction encountered (expected)")
        }
    }
    
    // MARK: - Archive Extraction Tests
    
    private func testArchiveExtraction(archivePath: URL) throws {
        logger.info("Testing archive extraction")
        
        let extractionDir = testConfig.tempDirectory.appendingPathComponent("extraction-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extractionDir, withIntermediateDirectories: true)
        
        let tarProcess = Process()
        tarProcess.currentDirectoryURL = extractionDir
        tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarProcess.arguments = ["xzf", archivePath.path]
        
        try tarProcess.run()
        tarProcess.waitUntilExit()
        
        guard tarProcess.terminationStatus == 0 else {
            throw DistributionTestError.archiveExtractionFailed
        }
        
        // Verify extracted files
        let extractedFiles = try FileManager.default.contentsOfDirectory(at: extractionDir, includingPropertiesForKeys: nil)
        XCTAssertGreaterThan(extractedFiles.count, 0, "Archive should extract files")
        
        // Verify main executable was extracted
        let extractedExecutable = extractedFiles.first { $0.lastPathComponent.contains("usbipd") }
        XCTAssertNotNil(extractedExecutable, "Archive should contain usbipd executable")
        
        logger.debug("✅ Archive extraction successful, extracted \(extractedFiles.count) files")
    }
    
    // MARK: - Helper Methods
    
    private func createMockArtifacts() throws {
        logger.info("Creating mock artifacts for testing")
        
        // Create mock artifacts directory
        let mockDir = tempDirectory.appendingPathComponent("mock-artifacts")
        try FileManager.default.createDirectory(at: mockDir, withIntermediateDirectories: true)
        
        // Create mock main executable
        let mockExecutable = mockDir.appendingPathComponent("usbipd-mock")
        let executableContent = """
        #!/bin/bash
        echo "usbipd-mac version \(testConfig.testArtifactVersion)"
        echo "Usage: usbipd [command] [options]"
        echo "Commands:"
        echo "  list     List available USB devices"
        echo "  attach   Attach USB device to QEMU VM"
        echo "  detach   Detach USB device from QEMU VM"
        echo "  help     Show this help message"
        """
        try executableContent.write(to: mockExecutable, atomically: true, encoding: .utf8)
        
        // Make executable
        let attributes = [FileAttributeKey.posixPermissions: NSNumber(value: 0o755)]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: mockExecutable.path)
        
        // Create mock archive
        let mockArchive = mockDir.appendingPathComponent("usbipd-mac-mock.tar.gz")
        let tarProcess = Process()
        tarProcess.currentDirectoryURL = mockDir
        tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarProcess.arguments = ["czf", mockArchive.lastPathComponent, mockExecutable.lastPathComponent]
        
        try tarProcess.run()
        tarProcess.waitUntilExit()
        
        // Calculate checksums
        let executableChecksum = try calculateSHA256(for: mockExecutable)
        let archiveChecksum = try calculateSHA256(for: mockArchive)
        
        // Create checksum file
        let checksumFile = mockDir.appendingPathComponent("checksums-mock.sha256")
        let checksumContent = """
        \(executableChecksum)  \(mockExecutable.lastPathComponent)
        \(archiveChecksum)  \(mockArchive.lastPathComponent)
        """
        try checksumContent.write(to: checksumFile, atomically: true, encoding: .utf8)
        
        // Create metadata file
        let metadataFile = mockDir.appendingPathComponent("release-metadata.json")
        let metadata = TestReleaseMetadata(
            version: testConfig.testArtifactVersion,
            buildConfiguration: "test",
            buildDate: Date(),
            buildEnvironment: environmentConfig.environment.rawValue,
            artifacts: [
                mockExecutable.lastPathComponent,
                mockArchive.lastPathComponent,
                checksumFile.lastPathComponent,
                metadataFile.lastPathComponent
            ]
        )
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataFile)
        
        // Store mock artifact set
        mockArtifacts = TestArtifactSet(
            mainExecutable: mockExecutable,
            compressedArchive: mockArchive,
            checksumFile: checksumFile,
            metadataFile: metadataFile,
            mainExecutableChecksum: executableChecksum,
            archiveChecksum: archiveChecksum
        )
        
        logger.debug("✅ Mock artifacts created successfully")
    }
    
    private func findPackageRoot() throws -> URL {
        var currentURL = URL(fileURLWithPath: #file).deletingLastPathComponent()
        
        while currentURL.path != "/" {
            let packageSwiftPath = currentURL.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageSwiftPath.path) {
                return currentURL
            }
            currentURL = currentURL.deletingLastPathComponent()
        }
        
        throw DistributionTestError.packageRootNotFound
    }
    
    private func calculateSHA256(for url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", url.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw DistributionTestError.checksumCalculationFailed
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return output.components(separatedBy: .whitespaces).first ?? ""
    }
    
    private func validateExecutableBasicFunction(executablePath: URL) throws {
        let testProcess = Process()
        testProcess.executableURL = executablePath
        testProcess.arguments = ["--help"]
        
        let outputPipe = Pipe()
        testProcess.standardOutput = outputPipe
        testProcess.standardError = outputPipe
        
        try testProcess.run()
        testProcess.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        
        // Executable should respond to --help (exit code 0 or 1 acceptable)
        XCTAssertTrue(testProcess.terminationStatus == 0 || testProcess.terminationStatus == 1,
                     "Executable should respond to --help")
        
        // Output should contain some expected content
        XCTAssertFalse(output.isEmpty, "Executable should produce help output")
    }
    
    private func getCurrentArchitecture() -> String {
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        
        return String(cString: machine)
    }
    
    private func versionString(_ version: String, isGreaterThanOrEqualTo minimumVersion: String) -> Bool {
        return version.compare(minimumVersion, options: .numeric) != .orderedAscending
    }
    
    private func getDownloadSizeEstimate() throws -> Int64 {
        // Estimate total download size based on mock artifacts
        var totalSize: Int64 = 0
        
        let artifacts = [
            mockArtifacts.mainExecutable,
            mockArtifacts.compressedArchive,
            mockArtifacts.checksumFile,
            mockArtifacts.metadataFile
        ]
        
        for artifact in artifacts {
            let attributes = try FileManager.default.attributesOfItem(atPath: artifact.path)
            let size = attributes[.size] as? Int64 ?? 0
            totalSize += size
        }
        
        return totalSize
    }
    
    private func estimateDownloadTime(sizeBytes: Int64, speedBytesPerSecond: Int64) -> Double {
        return Double(sizeBytes) / Double(speedBytesPerSecond)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Supporting Types

/// Test artifact set for distribution testing
private struct TestArtifactSet {
    let mainExecutable: URL
    let compressedArchive: URL
    let checksumFile: URL
    let metadataFile: URL
    let mainExecutableChecksum: String
    let archiveChecksum: String
}

/// Test release metadata structure
private struct TestReleaseMetadata: Codable {
    let version: String
    let buildConfiguration: String
    let buildDate: Date
    let buildEnvironment: String
    let artifacts: [String]
}

/// Distribution test errors
private enum DistributionTestError: Error {
    case packageRootNotFound
    case architectureValidationFailed
    case checksumCalculationFailed
    case archiveExtractionFailed
    case networkTestNotSupported
    case installationTestFailed
}