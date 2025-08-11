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
    
    // MARK: - Code Signing Operations
    
    /// Signs a System Extension bundle with the specified certificate
    /// - Parameters:
    ///   - bundlePath: Path to the .systemextension bundle
    ///   - certificate: Certificate to use for signing (nil for best available)
    ///   - entitlementsPath: Optional path to entitlements file
    /// - Returns: Code signing result with verification status
    /// - Throws: CodeSigningError if signing fails
    public func signBundle(
        at bundlePath: String,
        with certificate: CodeSigningCertificate? = nil,
        entitlements entitlementsPath: String? = nil
    ) throws -> SigningResult {
        logger.info("Starting bundle signing", context: ["bundle": bundlePath])
        
        // Validate bundle path
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            throw CodeSigningError.bundleNotFound(bundlePath)
        }
        
        // Select certificate to use
        let signingCertificate: CodeSigningCertificate
        if let providedCert = certificate {
            signingCertificate = providedCert
        } else {
            guard let bestCert = findBestCertificate() else {
                throw CodeSigningError.noCertificatesFound
            }
            signingCertificate = bestCert
        }
        
        logger.info("Using certificate for signing", context: [
            "certificate": signingCertificate.commonName,
            "type": signingCertificate.certificateType.displayName
        ])
        
        let startTime = Date()
        
        do {
            // Build codesign command
            let codesignArgs = buildCodesignArguments(
                bundlePath: bundlePath,
                certificate: signingCertificate,
                entitlementsPath: entitlementsPath
            )
            
            // Execute codesign command
            let result = try executeCodesignCommand(arguments: codesignArgs)
            
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            
            if result.success {
                logger.info("Bundle signing completed successfully", context: [
                    "duration": String(format: "%.2f", duration)
                ])
                
                // Verify the signature
                let verificationResult = try verifyBundleSignature(at: bundlePath)
                
                return SigningResult(
                    success: true,
                    certificate: signingCertificate,
                    bundlePath: bundlePath,
                    signingTime: startTime,
                    signingDuration: duration,
                    verificationStatus: verificationResult.status,
                    output: result.output,
                    errors: []
                )
            } else {
                logger.error("Bundle signing failed", context: [
                    "output": result.output,
                    "error": result.error ?? "Unknown error"
                ])
                
                return SigningResult(
                    success: false,
                    certificate: signingCertificate,
                    bundlePath: bundlePath,
                    signingTime: startTime,
                    signingDuration: duration,
                    verificationStatus: .signingFailed,
                    output: result.output,
                    errors: [result.error ?? "Signing failed with unknown error"]
                )
            }
            
        } catch {
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            
            logger.error(error, message: "Exception during bundle signing")
            
            return SigningResult(
                success: false,
                certificate: signingCertificate,
                bundlePath: bundlePath,
                signingTime: startTime,
                signingDuration: duration,
                verificationStatus: .signingFailed,
                output: "",
                errors: [error.localizedDescription]
            )
        }
    }
    
    /// Verifies the signature of a System Extension bundle
    /// - Parameter bundlePath: Path to the bundle to verify
    /// - Returns: Verification result with detailed status
    /// - Throws: CodeSigningError if verification fails
    public func verifyBundleSignature(at bundlePath: String) throws -> SignatureVerificationResult {
        logger.debug("Verifying bundle signature", context: ["bundle": bundlePath])
        
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            throw CodeSigningError.bundleNotFound(bundlePath)
        }
        
        // Use codesign --verify to check signature
        let verifyArgs = [
            "--verify",
            "--verbose=4",  // Maximum verbosity for detailed output
            "--strict",     // Strict verification
            bundlePath
        ]
        
        let result = try executeCodesignCommand(arguments: verifyArgs)
        let status = determineVerificationStatus(from: result)
        
        logger.debug("Signature verification completed", context: [
            "status": status.rawValue,
            "success": result.success
        ])
        
        return SignatureVerificationResult(
            bundlePath: bundlePath,
            status: status,
            details: result.output,
            verificationTime: Date(),
            isValid: status == .valid
        )
    }
    
    /// Gets detailed information about a signed bundle
    /// - Parameter bundlePath: Path to the bundle
    /// - Returns: Detailed signing information
    /// - Throws: CodeSigningError if information cannot be retrieved
    public func getBundleSigningInfo(at bundlePath: String) throws -> BundleSigningInfo {
        logger.debug("Getting bundle signing information", context: ["bundle": bundlePath])
        
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            throw CodeSigningError.bundleNotFound(bundlePath)
        }
        
        // Use codesign --display to get signing info
        let displayArgs = [
            "--display",
            "--verbose=4",
            "--entitlements", "-",  // Display entitlements
            bundlePath
        ]
        
        let result = try executeCodesignCommand(arguments: displayArgs)
        
        return BundleSigningInfo(
            bundlePath: bundlePath,
            isSigned: result.success,
            signingIdentity: extractSigningIdentity(from: result.output),
            teamIdentifier: extractTeamIdentifierFromDisplay(from: result.output),
            signingTime: extractSigningTime(from: result.output),
            entitlements: extractEntitlements(from: result.output),
            codeSigningFlags: extractCodeSigningFlags(from: result.output),
            rawOutput: result.output
        )
    }
    
    // MARK: - Private Code Signing Methods
    
    private func buildCodesignArguments(
        bundlePath: String,
        certificate: CodeSigningCertificate,
        entitlementsPath: String?
    ) -> [String] {
        var args = [
            "--sign", certificate.commonName,
            "--force",  // Replace existing signature
            "--timestamp",  // Include timestamp
            "--options", "runtime"  // Enable hardened runtime
        ]
        
        // Add entitlements if provided
        if let entitlementsPath = entitlementsPath,
           FileManager.default.fileExists(atPath: entitlementsPath) {
            args.append(contentsOf: ["--entitlements", entitlementsPath])
        }
        
        // Add bundle path
        args.append(bundlePath)
        
        return args
    }
    
    private func executeCodesignCommand(arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.launchPath = "/usr/bin/codesign"
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        logger.debug("Executing codesign command", context: ["args": arguments.joined(separator: " ")])
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            let combinedOutput = [output, errorOutput].filter { !$0.isEmpty }.joined(separator: "\n")
            
            return CommandResult(
                success: process.terminationStatus == 0,
                output: combinedOutput,
                error: process.terminationStatus != 0 ? errorOutput : nil
            )
            
        } catch {
            logger.error(error, message: "Failed to execute codesign command")
            throw CodeSigningError.commandExecutionFailed(error.localizedDescription)
        }
    }
    
    private func determineVerificationStatus(from result: CommandResult) -> SigningVerificationStatus {
        if !result.success {
            let output = result.output.lowercased()
            
            if output.contains("certificate") && output.contains("expired") {
                return .certificateExpired
            } else if output.contains("untrusted") || output.contains("not trusted") {
                return .certificateUntrusted
            } else if output.contains("not signed") {
                return .notSigned
            } else {
                return .invalid
            }
        }
        
        return .valid
    }
    
    private func extractSigningIdentity(from output: String) -> String? {
        // Parse output for signing identity
        for line in output.components(separatedBy: .newlines) {
            if line.contains("Authority=") {
                let components = line.components(separatedBy: "Authority=")
                if components.count > 1 {
                    return components[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
    
    private func extractTeamIdentifierFromDisplay(from output: String) -> String? {
        // Parse output for team identifier
        for line in output.components(separatedBy: .newlines) {
            if line.contains("TeamIdentifier=") {
                let components = line.components(separatedBy: "TeamIdentifier=")
                if components.count > 1 {
                    return components[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
    
    private func extractSigningTime(from output: String) -> Date? {
        // Parse output for signing timestamp
        for line in output.components(separatedBy: .newlines) {
            if line.contains("Timestamp=") {
                let components = line.components(separatedBy: "Timestamp=")
                if components.count > 1 {
                    let timestampString = components[1].trimmingCharacters(in: .whitespaces)
                    let formatter = ISO8601DateFormatter()
                    return formatter.date(from: timestampString)
                }
            }
        }
        return nil
    }
    
    private func extractEntitlements(from output: String) -> [String: Any] {
        // Parse entitlements from output (simplified implementation)
        var entitlements: [String: Any] = [:]
        
        let lines = output.components(separatedBy: .newlines)
        var inEntitlements = false
        
        for line in lines {
            if line.contains("<plist") {
                inEntitlements = true
                continue
            }
            if line.contains("</plist>") {
                break
            }
            if inEntitlements {
                // Simplified entitlements parsing
                if line.contains("<key>") && line.contains("</key>") {
                    let key = extractValueBetween(line, start: "<key>", end: "</key>")
                    entitlements[key] = true // Simplified - real implementation would parse values
                }
            }
        }
        
        return entitlements
    }
    
    private func extractCodeSigningFlags(from output: String) -> [String] {
        var flags: [String] = []
        
        for line in output.components(separatedBy: .newlines) {
            if line.contains("CodeDirectory") {
                if line.contains("runtime") {
                    flags.append("runtime")
                }
                if line.contains("library-validation") {
                    flags.append("library-validation")
                }
            }
        }
        
        return flags
    }
    
    // MARK: - Development Mode Support
    
    /// Checks if macOS Developer Mode is enabled for System Extensions
    /// - Returns: True if developer mode is enabled, false otherwise
    public func isDeveloperModeEnabled() -> Bool {
        logger.debug("Checking developer mode status")
        
        // Use systemextensionsctl to check developer mode status
        let process = Process()
        process.launchPath = "/usr/bin/systemextensionsctl"
        process.arguments = ["developer"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            let isDeveloperMode = output.lowercased().contains("developer mode: on") || 
                                 output.lowercased().contains("enabled")
            
            logger.debug("Developer mode status", context: ["enabled": isDeveloperMode])
            return isDeveloperMode
            
        } catch {
            logger.warning("Failed to check developer mode status", context: ["error": error.localizedDescription])
            return false
        }
    }
    
    /// Creates an unsigned bundle for development when no certificates are available
    /// - Parameters:
    ///   - bundlePath: Path to the System Extension bundle
    ///   - skipSigning: Whether to skip signing entirely
    /// - Returns: Development signing result
    /// - Throws: CodeSigningError if bundle preparation fails
    public func createDevelopmentBundle(
        at bundlePath: String,
        skipSigning: Bool = false
    ) throws -> DevelopmentBundleResult {
        logger.info("Creating development bundle", context: ["bundle": bundlePath, "skipSigning": skipSigning])
        
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            throw CodeSigningError.bundleNotFound(bundlePath)
        }
        
        let startTime = Date()
        var warnings: [String] = []
        
        // Check if developer mode is enabled
        let developerModeEnabled = isDeveloperModeEnabled()
        if !developerModeEnabled {
            warnings.append("Developer mode is not enabled. Enable with: systemextensionsctl developer on")
        }
        
        // Try to find certificates even for development
        let availableCertificates = (try? detectAvailableCertificates()) ?? []
        
        let result: DevelopmentBundleResult
        
        if skipSigning || availableCertificates.isEmpty {
            // Create unsigned bundle
            logger.info("Creating unsigned development bundle")
            
            warnings.append("Bundle will be unsigned - only suitable for development with SIP disabled")
            warnings.append("For production use, install proper Apple Developer certificates")
            
            result = DevelopmentBundleResult(
                bundlePath: bundlePath,
                isSigned: false,
                certificate: nil,
                developerModeEnabled: developerModeEnabled,
                preparationTime: Date().timeIntervalSince(startTime),
                warnings: warnings,
                signingStatus: .unsigned,
                recommendedActions: generateRecommendedActions(
                    developerModeEnabled: developerModeEnabled,
                    hasCertificates: false
                )
            )
            
        } else {
            // Try to sign with available certificate for better development experience
            logger.info("Attempting to sign development bundle with available certificate")
            
            do {
                let signingResult = try signBundle(at: bundlePath)
                
                result = DevelopmentBundleResult(
                    bundlePath: bundlePath,
                    isSigned: signingResult.success,
                    certificate: signingResult.certificate,
                    developerModeEnabled: developerModeEnabled,
                    preparationTime: Date().timeIntervalSince(startTime),
                    warnings: warnings,
                    signingStatus: signingResult.success ? .signed : .signingFailed,
                    recommendedActions: generateRecommendedActions(
                        developerModeEnabled: developerModeEnabled,
                        hasCertificates: true,
                        signingSucceeded: signingResult.success
                    )
                )
                
            } catch {
                logger.warning("Signing failed, creating unsigned bundle", context: ["error": error.localizedDescription])
                
                warnings.append("Code signing failed: \(error.localizedDescription)")
                warnings.append("Bundle will be unsigned - only suitable for development with SIP disabled")
                
                result = DevelopmentBundleResult(
                    bundlePath: bundlePath,
                    isSigned: false,
                    certificate: nil,
                    developerModeEnabled: developerModeEnabled,
                    preparationTime: Date().timeIntervalSince(startTime),
                    warnings: warnings,
                    signingStatus: .signingFailed,
                    recommendedActions: generateRecommendedActions(
                        developerModeEnabled: developerModeEnabled,
                        hasCertificates: true,
                        signingSucceeded: false
                    )
                )
            }
        }
        
        logger.info("Development bundle preparation completed", context: [
            "signed": result.isSigned,
            "developerMode": result.developerModeEnabled,
            "warnings": result.warnings.count
        ])
        
        return result
    }
    
    /// Generates comprehensive signing status report for development workflows
    /// - Returns: Development environment status report
    public func getDevelopmentStatus() -> DevelopmentStatusReport {
        logger.debug("Generating development status report")
        
        let startTime = Date()
        
        // Check developer mode
        let developerModeEnabled = isDeveloperModeEnabled()
        
        // Detect certificates
        let certificates = (try? detectAvailableCertificates()) ?? []
        
        // Check SIP status
        let sipStatus = getSIPStatus()
        
        // Generate recommendations
        let recommendations = generateDevelopmentRecommendations(
            developerMode: developerModeEnabled,
            certificates: certificates,
            sipStatus: sipStatus
        )
        
        return DevelopmentStatusReport(
            developerModeEnabled: developerModeEnabled,
            availableCertificates: certificates,
            sipStatus: sipStatus,
            canInstallUnsigned: !sipStatus.isEnabled,
            canInstallSigned: !certificates.isEmpty,
            recommendations: recommendations,
            generationTime: Date().timeIntervalSince(startTime)
        )
    }
    
    // MARK: - Private Development Mode Methods
    
    private func generateRecommendedActions(
        developerModeEnabled: Bool,
        hasCertificates: Bool,
        signingSucceeded: Bool? = nil
    ) -> [String] {
        var actions: [String] = []
        
        if !developerModeEnabled {
            actions.append("Enable Developer Mode: sudo systemextensionsctl developer on")
        }
        
        if !hasCertificates {
            actions.append("Install Apple Developer certificates through Xcode or Apple Developer portal")
            actions.append("Consider disabling SIP for unsigned development: csrutil disable")
        } else if let signingSucceeded = signingSucceeded, !signingSucceeded {
            actions.append("Check certificate validity and keychain access permissions")
            actions.append("Verify certificate is suitable for System Extension signing")
        }
        
        if !developerModeEnabled || !hasCertificates {
            actions.append("Review System Extension setup documentation")
        }
        
        return actions
    }
    
    private func generateDevelopmentRecommendations(
        developerMode: Bool,
        certificates: [CodeSigningCertificate],
        sipStatus: SIPStatus
    ) -> [DevelopmentRecommendation] {
        var recommendations: [DevelopmentRecommendation] = []
        
        if !developerMode {
            recommendations.append(DevelopmentRecommendation(
                priority: .high,
                category: .developerMode,
                title: "Enable Developer Mode",
                description: "System Extension developer mode is not enabled",
                action: "Run: sudo systemextensionsctl developer on",
                impact: "Required for loading unsigned System Extensions during development"
            ))
        }
        
        if certificates.isEmpty {
            recommendations.append(DevelopmentRecommendation(
                priority: .medium,
                category: .certificates,
                title: "Install Development Certificates",
                description: "No code signing certificates found in keychain",
                action: "Install Apple Developer certificates through Xcode",
                impact: "Enables proper code signing for System Extensions"
            ))
        } else {
            // Check certificate expiration
            let expiredCerts = certificates.filter { $0.expirationDate < Date() }
            if !expiredCerts.isEmpty {
                recommendations.append(DevelopmentRecommendation(
                    priority: .high,
                    category: .certificates,
                    title: "Renew Expired Certificates",
                    description: "\(expiredCerts.count) certificate(s) have expired",
                    action: "Renew certificates through Apple Developer portal",
                    impact: "Prevents signing failures and enables proper System Extension deployment"
                ))
            }
        }
        
        if sipStatus.isEnabled && certificates.isEmpty {
            recommendations.append(DevelopmentRecommendation(
                priority: .low,
                category: .systemConfiguration,
                title: "Consider SIP Configuration",
                description: "SIP is enabled but no signing certificates available",
                action: "Either install certificates OR disable SIP for unsigned development",
                impact: "Enables unsigned System Extension loading for development"
            ))
        }
        
        return recommendations
    }
    
    private func getSIPStatus() -> SIPStatus {
        let process = Process()
        process.launchPath = "/usr/bin/csrutil"
        process.arguments = ["status"]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            let isEnabled = output.lowercased().contains("enabled")
            let details = output.trimmingCharacters(in: .whitespacesAndNewlines)
            
            return SIPStatus(isEnabled: isEnabled, details: details)
            
        } catch {
            logger.warning("Failed to check SIP status", context: ["error": error.localizedDescription])
            return SIPStatus(isEnabled: true, details: "Unable to determine SIP status")
        }
    }
    
    private func extractValueBetween(_ string: String, start: String, end: String) -> String {
        guard let startRange = string.range(of: start),
              let endRange = string.range(of: end, range: startRange.upperBound..<string.endIndex) else {
            return ""
        }
        
        return String(string[startRange.upperBound..<endRange.lowerBound])
    }
}

// MARK: - Supporting Types

/// Result of a code signing operation
public struct SigningResult {
    public let success: Bool
    public let certificate: CodeSigningCertificate
    public let bundlePath: String
    public let signingTime: Date
    public let signingDuration: TimeInterval
    public let verificationStatus: SigningVerificationStatus
    public let output: String
    public let errors: [String]
    
    public init(
        success: Bool,
        certificate: CodeSigningCertificate,
        bundlePath: String,
        signingTime: Date,
        signingDuration: TimeInterval,
        verificationStatus: SigningVerificationStatus,
        output: String,
        errors: [String]
    ) {
        self.success = success
        self.certificate = certificate
        self.bundlePath = bundlePath
        self.signingTime = signingTime
        self.signingDuration = signingDuration
        self.verificationStatus = verificationStatus
        self.output = output
        self.errors = errors
    }
}

/// Result of signature verification
public struct SignatureVerificationResult {
    public let bundlePath: String
    public let status: SigningVerificationStatus
    public let details: String
    public let verificationTime: Date
    public let isValid: Bool
    
    public init(
        bundlePath: String,
        status: SigningVerificationStatus,
        details: String,
        verificationTime: Date,
        isValid: Bool
    ) {
        self.bundlePath = bundlePath
        self.status = status
        self.details = details
        self.verificationTime = verificationTime
        self.isValid = isValid
    }
}

/// Detailed bundle signing information
public struct BundleSigningInfo {
    public let bundlePath: String
    public let isSigned: Bool
    public let signingIdentity: String?
    public let teamIdentifier: String?
    public let signingTime: Date?
    public let entitlements: [String: Any]
    public let codeSigningFlags: [String]
    public let rawOutput: String
    
    public init(
        bundlePath: String,
        isSigned: Bool,
        signingIdentity: String?,
        teamIdentifier: String?,
        signingTime: Date?,
        entitlements: [String: Any],
        codeSigningFlags: [String],
        rawOutput: String
    ) {
        self.bundlePath = bundlePath
        self.isSigned = isSigned
        self.signingIdentity = signingIdentity
        self.teamIdentifier = teamIdentifier
        self.signingTime = signingTime
        self.entitlements = entitlements
        self.codeSigningFlags = codeSigningFlags
        self.rawOutput = rawOutput
    }
}

/// Result of development bundle preparation
public struct DevelopmentBundleResult {
    public let bundlePath: String
    public let isSigned: Bool
    public let certificate: CodeSigningCertificate?
    public let developerModeEnabled: Bool
    public let preparationTime: TimeInterval
    public let warnings: [String]
    public let signingStatus: DevelopmentSigningStatus
    public let recommendedActions: [String]
    
    public init(
        bundlePath: String,
        isSigned: Bool,
        certificate: CodeSigningCertificate?,
        developerModeEnabled: Bool,
        preparationTime: TimeInterval,
        warnings: [String],
        signingStatus: DevelopmentSigningStatus,
        recommendedActions: [String]
    ) {
        self.bundlePath = bundlePath
        self.isSigned = isSigned
        self.certificate = certificate
        self.developerModeEnabled = developerModeEnabled
        self.preparationTime = preparationTime
        self.warnings = warnings
        self.signingStatus = signingStatus
        self.recommendedActions = recommendedActions
    }
}

/// Development environment status report
public struct DevelopmentStatusReport {
    public let developerModeEnabled: Bool
    public let availableCertificates: [CodeSigningCertificate]
    public let sipStatus: SIPStatus
    public let canInstallUnsigned: Bool
    public let canInstallSigned: Bool
    public let recommendations: [DevelopmentRecommendation]
    public let generationTime: TimeInterval
    
    public init(
        developerModeEnabled: Bool,
        availableCertificates: [CodeSigningCertificate],
        sipStatus: SIPStatus,
        canInstallUnsigned: Bool,
        canInstallSigned: Bool,
        recommendations: [DevelopmentRecommendation],
        generationTime: TimeInterval
    ) {
        self.developerModeEnabled = developerModeEnabled
        self.availableCertificates = availableCertificates
        self.sipStatus = sipStatus
        self.canInstallUnsigned = canInstallUnsigned
        self.canInstallSigned = canInstallSigned
        self.recommendations = recommendations
        self.generationTime = generationTime
    }
}

/// Development bundle signing status
public enum DevelopmentSigningStatus: String, CaseIterable {
    /// Bundle is properly signed
    case signed = "signed"
    
    /// Bundle is unsigned (for development)
    case unsigned = "unsigned"
    
    /// Signing process failed
    case signingFailed = "signing_failed"
}

/// System Integrity Protection status
public struct SIPStatus {
    public let isEnabled: Bool
    public let details: String
    
    public init(isEnabled: Bool, details: String) {
        self.isEnabled = isEnabled
        self.details = details
    }
}

/// Development environment recommendation
public struct DevelopmentRecommendation {
    public let priority: RecommendationPriority
    public let category: RecommendationCategory
    public let title: String
    public let description: String
    public let action: String
    public let impact: String
    
    public init(
        priority: RecommendationPriority,
        category: RecommendationCategory,
        title: String,
        description: String,
        action: String,
        impact: String
    ) {
        self.priority = priority
        self.category = category
        self.title = title
        self.description = description
        self.action = action
        self.impact = impact
    }
}

/// Recommendation priority levels
public enum RecommendationPriority: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

/// Recommendation categories
public enum RecommendationCategory: String, CaseIterable {
    case developerMode = "developer_mode"
    case certificates = "certificates"
    case systemConfiguration = "system_configuration"
    case permissions = "permissions"
}

/// Command execution result
private struct CommandResult {
    let success: Bool
    let output: String
    let error: String?
}

// MARK: - Code Signing Errors

public enum CodeSigningError: Error, LocalizedError {
    case certificateQueryFailed(OSStatus)
    case noCertificatesFound
    case certificateParsingFailed(String)
    case securityFrameworkError(OSStatus, String)
    case bundleNotFound(String)
    case commandExecutionFailed(String)
    case signingFailed(String)
    
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
        case .bundleNotFound(let path):
            return "System Extension bundle not found at path: \(path)"
        case .commandExecutionFailed(let details):
            return "Failed to execute codesign command: \(details)"
        case .signingFailed(let reason):
            return "Code signing failed: \(reason)"
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
        case .bundleNotFound:
            return "Ensure the System Extension bundle has been created and exists at the specified path"
        case .commandExecutionFailed:
            return "Check that codesign tool is available and accessible in /usr/bin/codesign"
        case .signingFailed:
            return "Verify certificate is valid and has appropriate permissions for System Extension signing"
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