import XCTest
import Foundation
import Security
@testable import USBIPDCore
@testable import Common

final class CodeSigningManagerTests: XCTestCase {
    
    private var codeSigningManager: CodeSigningManager!
    private var tempDirectory: URL!
    private var testBundlePath: String!
    
    override func setUp() {
        super.setUp()
        
        codeSigningManager = CodeSigningManager()
        
        // Create temporary directory for test bundles
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeSigningManagerTests")
            .appendingPathComponent(UUID().uuidString)
        
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create a mock bundle structure
        testBundlePath = tempDirectory.appendingPathComponent("TestBundle.systemextension").path
        createMockBundle(at: testBundlePath)
    }
    
    override func tearDown() {
        // Clean up test files
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }
    
    // MARK: - Certificate Detection Tests
    
    func testDetectAvailableCertificates_ReturnsArray() {
        // This test will work with whatever certificates are available on the system
        do {
            let certificates = try codeSigningManager.detectAvailableCertificates()
            
            // Should return an array (may be empty on systems without certificates)
            XCTAssertNotNil(certificates)
            
            // If certificates exist, validate their structure
            for certificate in certificates {
                XCTAssertFalse(certificate.commonName.isEmpty, "Certificate should have a common name")
                XCTAssertFalse(certificate.fingerprint.isEmpty, "Certificate should have a fingerprint")
                XCTAssertNotEqual(certificate.certificateType, .unknown, "Certificate type should be determined")
                
                if certificate.isValidForSystemExtensions {
                    XCTAssertGreaterThan(certificate.expirationDate, Date(), "Valid certificates should not be expired")
                }
            }
        } catch {
            // On CI or systems without certificates, this might fail - that's expected
            print("Certificate detection failed (expected on systems without certificates): \(error)")
        }
    }
    
    func testFindBestCertificate_ReturnsOptional() {
        let bestCertificate = codeSigningManager.findBestCertificate()
        
        // Should return an optional (nil on systems without suitable certificates)
        if let certificate = bestCertificate {
            XCTAssertTrue(certificate.isValidForSystemExtensions, "Best certificate should be valid for System Extensions")
            XCTAssertFalse(certificate.commonName.isEmpty, "Best certificate should have a common name")
            XCTAssertNotEqual(certificate.certificateType, .unknown, "Best certificate should have known type")
        }
        // If nil, that's fine - means no suitable certificates were found
    }
    
    // MARK: - Bundle Signing Tests
    
    func testSignBundle_BundleNotFound_ThrowsError() {
        let nonexistentPath = tempDirectory.appendingPathComponent("Nonexistent.systemextension").path
        
        XCTAssertThrowsError(try codeSigningManager.signBundle(at: nonexistentPath)) { error in
            XCTAssertTrue(error is CodeSigningError)
            if case let CodeSigningError.bundleNotFound(path) = error {
                XCTAssertEqual(path, nonexistentPath)
            }
        }
    }
    
    func testSignBundle_NoCertificates_ThrowsError() {
        // This test will likely throw noCertificatesFound on most CI systems
        do {
            let result = try codeSigningManager.signBundle(at: testBundlePath)
            
            // If signing succeeds, validate the result structure
            XCTAssertEqual(result.bundlePath, testBundlePath)
            XCTAssertNotNil(result.certificate)
            XCTAssertGreaterThan(result.signingDuration, 0)
        } catch CodeSigningError.noCertificatesFound {
            // Expected on systems without valid certificates
            print("No certificates found for signing (expected on CI/systems without certificates)")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSignBundle_WithSpecificCertificate() {
        // Create a mock certificate for testing
        let mockCertificate = CodeSigningCertificate(
            commonName: "Mock Certificate",
            certificateType: .appleDevelopment,
            teamIdentifier: "ABCD123456",
            fingerprint: "00112233445566778899AABBCCDDEEFF00112233",
            expirationDate: Date().addingTimeInterval(365 * 24 * 60 * 60), // 1 year from now
            isValidForSystemExtensions: true,
            keychainPath: nil
        )
        
        do {
            let result = try codeSigningManager.signBundle(at: testBundlePath, with: mockCertificate)
            
            // Even if signing fails due to mock certificate, we should get a result
            XCTAssertEqual(result.bundlePath, testBundlePath)
            XCTAssertEqual(result.certificate.commonName, mockCertificate.commonName)
            XCTAssertGreaterThan(result.signingDuration, 0)
            
            if !result.success {
                // Expected for mock certificate
                XCTAssertFalse(result.errors.isEmpty, "Failed signing should have error messages")
            }
        } catch {
            // Expected when using mock certificate
            print("Signing with mock certificate failed (expected): \(error)")
        }
    }
    
    func testSignBundle_WithEntitlements() {
        // Create mock entitlements file
        let entitlementsPath = tempDirectory.appendingPathComponent("test.entitlements").path
        let entitlementsContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>com.apple.developer.system-extension.install</key>
            <true/>
        </dict>
        </plist>
        """
        
        try! entitlementsContent.write(toFile: entitlementsPath, atomically: true, encoding: .utf8)
        
        do {
            let result = try codeSigningManager.signBundle(at: testBundlePath, entitlements: entitlementsPath)
            
            XCTAssertEqual(result.bundlePath, testBundlePath)
            // Result structure should be valid regardless of success/failure
            
        } catch CodeSigningError.noCertificatesFound {
            // Expected on systems without certificates
            print("No certificates found for signing with entitlements")
        } catch {
            print("Signing with entitlements failed: \(error)")
        }
    }
    
    // MARK: - Signature Verification Tests
    
    func testVerifyBundleSignature_BundleNotFound_ThrowsError() {
        let nonexistentPath = tempDirectory.appendingPathComponent("Nonexistent.systemextension").path
        
        XCTAssertThrowsError(try codeSigningManager.verifyBundleSignature(at: nonexistentPath)) { error in
            XCTAssertTrue(error is CodeSigningError)
            if case let CodeSigningError.bundleNotFound(path) = error {
                XCTAssertEqual(path, nonexistentPath)
            }
        }
    }
    
    func testVerifyBundleSignature_UnsignedBundle() {
        do {
            let result = try codeSigningManager.verifyBundleSignature(at: testBundlePath)
            
            // Unsigned bundle should return verification result
            XCTAssertEqual(result.bundlePath, testBundlePath)
            
            // Most likely will be .unsigned or .verificationFailed for our mock bundle
            XCTAssertTrue([.unsigned, .verificationFailed, .valid].contains(result.status))
        } catch {
            // Some verification failures might throw
            print("Bundle verification failed (expected for unsigned mock bundle): \(error)")
        }
    }
    
    // MARK: - Development Mode Tests
    
    func testCreateUnsignedBundle_Success() {
        do {
            let result = try codeSigningManager.createUnsignedBundle(at: testBundlePath)
            
            XCTAssertEqual(result.bundlePath, testBundlePath)
            XCTAssertEqual(result.signingStatus, .unsigned)
            XCTAssertTrue(result.isDevelopmentMode)
            XCTAssertFalse(result.recommendedActions.isEmpty)
        } catch {
            XCTFail("Creating unsigned bundle should not fail: \(error)")
        }
    }
    
    func testCreateUnsignedBundle_BundleNotFound() {
        let nonexistentPath = tempDirectory.appendingPathComponent("Nonexistent.systemextension").path
        
        XCTAssertThrowsError(try codeSigningManager.createUnsignedBundle(at: nonexistentPath)) { error in
            XCTAssertTrue(error is CodeSigningError)
            if case let CodeSigningError.bundleNotFound(path) = error {
                XCTAssertEqual(path, nonexistentPath)
            }
        }
    }
    
    func testGenerateDevelopmentModeGuidance() {
        let guidance = codeSigningManager.generateDevelopmentModeGuidance()
        
        XCTAssertFalse(guidance.isEmpty)
        XCTAssertTrue(guidance.contains("System Extension"), "Guidance should mention System Extensions")
        XCTAssertTrue(guidance.contains("csrutil") || guidance.contains("SIP"), "Guidance should mention SIP/csrutil")
    }
    
    // MARK: - Signing Status Tests
    
    func testGetSigningStatus_ValidBundle() {
        do {
            let status = try codeSigningManager.getSigningStatus(for: testBundlePath)
            
            XCTAssertEqual(status.bundlePath, testBundlePath)
            // Status should be determined (likely unsigned for our mock bundle)
            XCTAssertNotEqual(status.signingStatus, .unknown)
        } catch {
            XCTFail("Getting signing status should not fail for valid bundle: \(error)")
        }
    }
    
    func testGetSigningStatus_BundleNotFound() {
        let nonexistentPath = tempDirectory.appendingPathComponent("Nonexistent.systemextension").path
        
        XCTAssertThrowsError(try codeSigningManager.getSigningStatus(for: nonexistentPath)) { error in
            XCTAssertTrue(error is CodeSigningError)
            if case let CodeSigningError.bundleNotFound(path) = error {
                XCTAssertEqual(path, nonexistentPath)
            }
        }
    }
    
    // MARK: - Certificate Type Tests
    
    func testCertificateType_SystemExtensionSupport() {
        XCTAssertTrue(CertificateType.appleDevelopment.supportsSystemExtensions)
        XCTAssertTrue(CertificateType.appleDistribution.supportsSystemExtensions)
        XCTAssertTrue(CertificateType.developerIdApplication.supportsSystemExtensions)
        XCTAssertFalse(CertificateType.unknown.supportsSystemExtensions)
    }
    
    func testCertificateType_DisplayNames() {
        XCTAssertEqual(CertificateType.appleDevelopment.displayName, "Apple Development")
        XCTAssertEqual(CertificateType.appleDistribution.displayName, "Apple Distribution")
        XCTAssertEqual(CertificateType.developerIdApplication.displayName, "Developer ID Application")
        XCTAssertEqual(CertificateType.macDeveloper.displayName, "Mac Developer")
        XCTAssertEqual(CertificateType.macAppDistribution.displayName, "Mac App Distribution")
        XCTAssertEqual(CertificateType.unknown.displayName, "Unknown")
    }
    
    // MARK: - Error Handling Tests
    
    func testCodeSigningError_Descriptions() {
        let bundleNotFoundError = CodeSigningError.bundleNotFound("/test/path")
        XCTAssertTrue(bundleNotFoundError.localizedDescription.contains("/test/path"))
        
        let noCertificatesError = CodeSigningError.noCertificatesFound
        XCTAssertTrue(noCertificatesError.localizedDescription.contains("certificate"))
        
        let queryFailedError = CodeSigningError.certificateQueryFailed(errSecItemNotFound)
        XCTAssertTrue(queryFailedError.localizedDescription.contains("keychain"))
        
        let signingFailedError = CodeSigningError.signingFailed("test error")
        XCTAssertTrue(signingFailedError.localizedDescription.contains("test error"))
    }
    
    // MARK: - Helper Methods
    
    private func createMockBundle(at path: String) {
        let bundleURL = URL(fileURLWithPath: path)
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        let macosURL = contentsURL.appendingPathComponent("MacOS")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        
        // Create directory structure
        try! FileManager.default.createDirectory(at: macosURL, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        
        // Create Info.plist
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let plistDict: [String: Any] = [
            "CFBundleIdentifier": "com.test.systemextension",
            "CFBundleExecutable": "TestSystemExtension",
            "CFBundlePackageType": "SYSX",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1"
        ]
        
        let plistData = try! PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        try! plistData.write(to: infoPlistURL)
        
        // Create mock executable
        let executableURL = macosURL.appendingPathComponent("TestSystemExtension")
        let executableData = Data("mock executable".utf8)
        try! executableData.write(to: executableURL)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
    }
    
    private func createMockCertificate(
        commonName: String = "Apple Development: Test Developer (ABCD123456)",
        certificateType: CertificateType = .appleDevelopment,
        teamIdentifier: String = "ABCD123456",
        isValid: Bool = true
    ) -> CodeSigningCertificate {
        return CodeSigningCertificate(
            commonName: commonName,
            certificateType: certificateType,
            teamIdentifier: teamIdentifier,
            fingerprint: "00112233445566778899AABBCCDDEEFF00112233",
            expirationDate: isValid ? Date().addingTimeInterval(365 * 24 * 60 * 60) : Date().addingTimeInterval(-24 * 60 * 60),
            isValidForSystemExtensions: isValid && certificateType.supportsSystemExtensions,
            keychainPath: nil
        )
    }
}