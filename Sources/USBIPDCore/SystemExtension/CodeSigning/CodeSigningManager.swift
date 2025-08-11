import Foundation
import Security
import Common

/// Manages code signing operations for System Extension bundles
public class CodeSigningManager {
    
    private let logger = Logger(
        config: LoggerConfig(level: .info),
        subsystem: "com.usbipd.mac",
        category: "CodeSigning"
    )
    
    // MARK: - Certificate Detection
    
    /// Detects available code signing certificates in the keychain
    /// - Returns: Array of available certificates sorted by expiration date (newest first)
    /// - Throws: CodeSigningError if certificate detection fails
    public func detectAvailableCertificates() throws -> [CodeSigningCertificate] {
        logger.info("Starting certificate detection")
        
        var certificates: [CodeSigningCertificate] = []
        
        // Query for all code signing certificates
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
            kSecReturnAttributes as String: true
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            let error = CodeSigningError.certificateQueryFailed(status)
            logger.error(error, message: "Failed to query certificates from keychain")
            throw error
        }
        
        guard let items = result as? [[String: Any]] else {
            logger.warning("No certificates found in keychain")
            return []
        }
        
        logger.debug("Found \(items.count) certificate(s) in keychain")
        
        for item in items {
            do {
                if let certificate = try parseCertificate(from: item) {
                    certificates.append(certificate)
                }
            } catch {
                logger.warning("Failed to parse certificate", context: ["error": error.localizedDescription])
            }
        }
        
        // Filter for code signing certificates and sort by expiration date
        let codeSigningCertificates = certificates
            .filter { $0.isValidForSystemExtensions }
            .sorted { $0.expirationDate > $1.expirationDate }
        
        logger.info("Found \(codeSigningCertificates.count) valid code signing certificate(s)")
        
        for cert in codeSigningCertificates {
            logger.debug("Certificate found", context: [
                "name": cert.commonName,
                "type": cert.certificateType.displayName,
                "team": cert.teamIdentifier,
                "expires": cert.expirationDate
            ])
        }
        
        return codeSigningCertificates
    }
    
    /// Finds the best certificate for System Extension signing
    /// - Returns: Best available certificate or nil if none found
    public func findBestCertificate() -> CodeSigningCertificate? {
        do {
            let certificates = try detectAvailableCertificates()
            
            // Prefer Apple Development certificates for local development
            if let developmentCert = certificates.first(where: { $0.certificateType == .appleDevelopment }) {
                logger.info("Selected Apple Development certificate", context: ["name": developmentCert.commonName])
                return developmentCert
            }
            
            // Fall back to Developer ID Application for distribution
            if let developerIdCert = certificates.first(where: { $0.certificateType == .developerIdApplication }) {
                logger.info("Selected Developer ID Application certificate", context: ["name": developerIdCert.commonName])
                return developerIdCert
            }
            
            // Return the first valid certificate if available
            if let firstCert = certificates.first {
                logger.info("Selected first available certificate", context: ["name": firstCert.commonName])
                return firstCert
            }
            
            logger.warning("No suitable certificates found for System Extension signing")
            return nil
            
        } catch {
            logger.error(error, message: "Failed to detect certificates")
            return nil
        }
    }
    
    // MARK: - Private Certificate Parsing
    
    private func parseCertificate(from item: [String: Any]) throws -> CodeSigningCertificate? {
        guard let certRef = item[kSecValueRef as String] as? SecCertificate else {
            return nil
        }
        
        // Get certificate summary (common name)
        let commonName = SecCertificateCopySubjectSummary(certRef) as String? ?? "Unknown"
        
        // Get certificate data for parsing
        let certData = SecCertificateCopyData(certRef)
        let data = CFDataGetBytePtr(certData)
        let length = CFDataGetLength(certData)
        let certificateData = Data(bytes: data!, count: length)
        
        // Parse certificate properties
        guard let certDict = SecCertificateCopyValues(certRef, nil, nil) as? [String: Any] else {
            logger.warning("Failed to get certificate properties for: \(commonName)")
            return nil
        }
        
        // Extract certificate type from common name and subject
        let certificateType = determineCertificateType(commonName: commonName, properties: certDict)
        
        // Extract team identifier
        let teamIdentifier = extractTeamIdentifier(from: certDict) ?? ""
        
        // Calculate SHA-1 fingerprint
        let fingerprint = calculateFingerprint(from: certificateData)
        
        // Extract expiration date
        let expirationDate = extractExpirationDate(from: certDict) ?? Date.distantFuture
        
        // Determine if valid for System Extensions
        let isValidForSystemExtensions = certificateType.supportsSystemExtensions && 
                                        expirationDate > Date() &&
                                        isCodeSigningCertificate(commonName: commonName, properties: certDict)
        
        // Get keychain path (if available)
        let keychainPath = extractKeychainPath(from: item)
        
        return CodeSigningCertificate(
            commonName: commonName,
            certificateType: certificateType,
            teamIdentifier: teamIdentifier,
            fingerprint: fingerprint,
            expirationDate: expirationDate,
            isValidForSystemExtensions: isValidForSystemExtensions,
            keychainPath: keychainPath
        )
    }
    
    private func determineCertificateType(commonName: String, properties: [String: Any]) -> CertificateType {
        let name = commonName.lowercased()
        
        if name.contains("apple development") {
            return .appleDevelopment
        } else if name.contains("apple distribution") {
            return .appleDistribution
        } else if name.contains("developer id application") {
            return .developerIdApplication
        } else if name.contains("mac developer") {
            return .macDeveloper
        } else if name.contains("mac app distribution") {
            return .macAppDistribution
        } else {
            return .unknown
        }
    }
    
    private func extractTeamIdentifier(from properties: [String: Any]) -> String? {
        // Try to extract team identifier from certificate subject
        if let subject = properties[kSecOIDX509V1SubjectName as String] as? [String: Any],
           let subjectDict = subject[kSecPropertyKeyValue as String] as? [[String: Any]] {
            
            for item in subjectDict {
                if let oid = item[kSecPropertyKeyLabel as String] as? String,
                   let value = item[kSecPropertyKeyValue as String] as? String,
                   oid.contains("Organizational Unit") {
                    return value
                }
            }
        }
        
        return nil
    }
    
    private func calculateFingerprint(from data: Data) -> String {
        let digest = data.withUnsafeBytes { bytes in
            var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            CC_SHA1(bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(data.count), &digest)
            return digest
        }
        
        return digest.map { String(format: "%02x", $0) }.joined().uppercased()
    }
    
    private func extractExpirationDate(from properties: [String: Any]) -> Date? {
        if let validity = properties[kSecOIDX509V1ValidityNotAfter as String] as? [String: Any],
           let dateValue = validity[kSecPropertyKeyValue as String] as? NSNumber {
            return Date(timeIntervalSinceReferenceDate: dateValue.doubleValue)
        }
        
        return nil
    }
    
    private func isCodeSigningCertificate(commonName: String, properties: [String: Any]) -> Bool {
        // Check if certificate has code signing capability
        // This is a simplified check - real implementation might need more sophisticated parsing
        let name = commonName.lowercased()
        return name.contains("developer") || 
               name.contains("distribution") || 
               name.contains("application")
    }
    
    private func extractKeychainPath(from item: [String: Any]) -> String? {
        // Extract keychain information if available
        return item[kSecAttrPath as String] as? String
    }
}

// MARK: - Code Signing Errors

public enum CodeSigningError: Error, LocalizedError {
    case certificateQueryFailed(OSStatus)
    case noCertificatesFound
    case certificateParsingFailed(String)
    case securityFrameworkError(OSStatus, String)
    
    public var errorDescription: String? {
        switch self {
        case .certificateQueryFailed(let status):
            return "Failed to query certificates from keychain (OSStatus: \(status))"
        case .noCertificatesFound:
            return "No code signing certificates found in keychain"
        case .certificateParsingFailed(let details):
            return "Failed to parse certificate: \(details)"
        case .securityFrameworkError(let status, let operation):
            return "Security framework error during \(operation) (OSStatus: \(status))"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .certificateQueryFailed, .securityFrameworkError:
            return "Check keychain access permissions and try again"
        case .noCertificatesFound:
            return "Install Apple Developer certificates using Xcode or Apple Developer portal"
        case .certificateParsingFailed:
            return "Certificate may be corrupted or in unsupported format"
        }
    }
}

// MARK: - CommonCrypto Import

#if canImport(CommonCrypto)
import CommonCrypto
#else
// Fallback implementation if CommonCrypto is not available
private let CC_SHA1_DIGEST_LENGTH: Int32 = 20

private func CC_SHA1(_ data: UnsafeRawPointer?, _ len: CC_LONG, _ md: UnsafeMutablePointer<UInt8>?) -> UnsafeMutablePointer<UInt8>? {
    // This is a placeholder - in real implementation would need proper SHA1 calculation
    return md
}
#endif