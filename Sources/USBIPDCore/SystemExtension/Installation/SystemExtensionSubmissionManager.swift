// SystemExtensionSubmissionManager.swift
// System Extension submission manager for actual macOS registration

import Foundation
import SystemExtensions
import Common

/// Manager for submitting System Extensions to macOS for approval and registration
public final class SystemExtensionSubmissionManager: NSObject, @unchecked Sendable {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.github.usbipd-mac", category: "SystemExtensionSubmissionManager")
    
    /// Current submission status
    public private(set) var submissionStatus: SystemExtensionSubmissionStatus = .notSubmitted
    
    /// Submission completion handler
    public typealias SubmissionCompletion = (SubmissionResult) -> Void
    
    private var currentCompletion: SubmissionCompletion?
    private var currentRequest: OSSystemExtensionRequest?
    private var submissionStartTime: Date?
    private var bundleIdentifier: String?
    
    // MARK: - Initialization
    
    /// Initialize submission manager
    override public init() {
        super.init()
        logger.info("SystemExtensionSubmissionManager initialized")
    }
    
    // MARK: - Public Interface
    
    /// Submit System Extension to macOS for approval
    /// - Parameters:
    ///   - bundlePath: Path to the System Extension bundle
    ///   - completion: Completion handler with submission result
    public func submitExtension(bundlePath: String, completion: @escaping SubmissionCompletion) {
        logger.info("Starting System Extension submission", context: [
            "bundlePath": bundlePath
        ])
        
        guard submissionStatus != .submitting else {
            logger.warning("Submission already in progress")
            completion(SubmissionResult(
                status: .failed(error: .requestInProgress),
                submissionTime: Date(),
                userInstructions: ["Wait for current submission to complete"],
                errorDetails: "A submission request is already in progress"
            ))
            return
        }
        
        // Validate bundle path
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            logger.error("Bundle not found at path", context: ["bundlePath": bundlePath])
            completion(SubmissionResult(
                status: .failed(error: .bundleNotFound),
                submissionTime: Date(),
                userInstructions: ["Verify System Extension bundle exists"],
                errorDetails: "Bundle not found at: \(bundlePath)"
            ))
            return
        }
        
        // Extract bundle identifier from bundle
        guard let extractedBundleId = extractBundleIdentifier(from: bundlePath) else {
            logger.error("Failed to extract bundle identifier", context: ["bundlePath": bundlePath])
            completion(SubmissionResult(
                status: .failed(error: .invalidBundle),
                submissionTime: Date(),
                userInstructions: ["Ensure bundle has valid Info.plist with CFBundleIdentifier"],
                errorDetails: "Could not extract bundle identifier from bundle"
            ))
            return
        }
        
        // Store state for delegate callbacks
        self.currentCompletion = completion
        self.bundleIdentifier = extractedBundleId
        self.submissionStartTime = Date()
        self.submissionStatus = .submitting
        
        // Create activation request
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extractedBundleId,
            queue: .main
        )
        request.delegate = self
        self.currentRequest = request
        
        logger.info("Submitting activation request to macOS", context: [
            "bundleIdentifier": extractedBundleId
        ])
        
        // Submit to OSSystemExtensionManager
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    
    /// Monitor approval status for ongoing submission
    /// - Parameter statusHandler: Handler called with status updates
    public func monitorApprovalStatus(statusHandler: @escaping (SystemExtensionSubmissionStatus) -> Void) {
        // Immediately provide current status
        statusHandler(submissionStatus)
        
        // For ongoing monitoring, we rely on the delegate callbacks
        // This method provides a way for callers to get status updates
        logger.debug("Started approval status monitoring", context: [
            "currentStatus": String(describing: submissionStatus)
        ])
    }
    
    // MARK: - Private Helpers
    
    /// Extract bundle identifier from System Extension bundle
    /// - Parameter bundlePath: Path to the bundle
    /// - Returns: Bundle identifier if found
    private func extractBundleIdentifier(from bundlePath: String) -> String? {
        let bundleURL = URL(fileURLWithPath: bundlePath)
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        
        guard let plistData = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let bundleId = plist["CFBundleIdentifier"] as? String else {
            return nil
        }
        
        return bundleId
    }
    
    /// Handle completion of submission process
    /// - Parameter result: Final submission result
    private func completeSubmission(with result: SubmissionResult) {
        logger.info("Completing submission", context: [
            "status": String(describing: result.status),
            "duration": String(result.submissionTime.timeIntervalSince(submissionStartTime ?? Date()))
        ])
        
        submissionStatus = result.status
        currentRequest = nil
        
        let completion = currentCompletion
        currentCompletion = nil
        
        completion?(result)
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension SystemExtensionSubmissionManager: OSSystemExtensionRequestDelegate {
    
    public func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        logger.info("System Extension replacement requested", context: [
            "existingVersion": existing.bundleVersion,
            "newVersion": ext.bundleVersion
        ])
        
        // Allow replacement - this handles updates and reinstalls
        return .replace
    }
    
    public func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.info("System Extension requires user approval")
        
        submissionStatus = .pendingApproval(requestID: UUID())
        
        // Provide user instructions for approval
        let instructions = [
            "Open System Preferences > Security & Privacy > General",
            "Look for a message about blocked system extension",
            "Click 'Allow' to approve the System Extension",
            "The extension should then become active"
        ]
        
        logger.info("User approval required", context: [
            "instructions": instructions.joined(separator: "; ")
        ])
    }
    
    public func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let submissionTime = Date()
        let duration = submissionTime.timeIntervalSince(submissionStartTime ?? submissionTime)
        
        logger.info("System Extension request completed", context: [
            "result": String(describing: result),
            "duration": String(duration),
            "bundleIdentifier": bundleIdentifier ?? "unknown"
        ])
        
        switch result {
        case .completed:
            logger.info("System Extension successfully activated")
            completeSubmission(with: SubmissionResult(
                status: .approved(extensionID: bundleIdentifier ?? "unknown"),
                submissionTime: submissionTime,
                userInstructions: ["System Extension is now active and ready to use"],
                errorDetails: nil
            ))
            
        case .willCompleteAfterReboot:
            logger.info("System Extension will complete after reboot")
            completeSubmission(with: SubmissionResult(
                status: .requiresUserAction(instructions: "System will complete installation after reboot"),
                submissionTime: submissionTime,
                userInstructions: [
                    "System Extension installation will complete after next reboot",
                    "Restart your system to finish installation",
                    "Extension will be active after restart"
                ],
                errorDetails: "Reboot required to complete installation"
            ))
            
        @unknown default:
            logger.warning("Unknown System Extension result", context: ["result": String(describing: result)])
            completeSubmission(with: SubmissionResult(
                status: .failed(error: .unknownError),
                submissionTime: submissionTime,
                userInstructions: ["Check system logs for more information"],
                errorDetails: "Unknown result: \(result)"
            ))
        }
    }
    
    public func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let submissionTime = Date()
        let duration = submissionTime.timeIntervalSince(submissionStartTime ?? submissionTime)
        
        logger.error("System Extension request failed", context: [
            "error": error.localizedDescription,
            "duration": String(duration),
            "bundleIdentifier": bundleIdentifier ?? "unknown"
        ])
        
        // Map OSSystemExtensionError to our error types
        let submissionError: SystemExtensionSubmissionError
        var userInstructions: [String] = []
        
        if let osError = error as? OSSystemExtensionError {
            switch osError.code {
            case .unknown:
                submissionError = .unknownError
                userInstructions = ["Check system logs for more details", "Ensure System Extension is properly signed"]
                
            case .missingEntitlement:
                submissionError = .missingEntitlement
                userInstructions = [
                    "Ensure System Extension has proper entitlements",
                    "Check code signing configuration",
                    "Verify bundle is built for distribution"
                ]
                
            // Note: unsignedExtension and invalidSignature are not available in OSSystemExtensionError.Code
            // They would be handled under .unknown or other available cases
                
            case .authorizationRequired:
                submissionError = .authorizationRequired
                userInstructions = [
                    "User authorization required",
                    "Check System Preferences > Security & Privacy",
                    "Approve the System Extension if prompted"
                ]
                
            case .requestCanceled:
                submissionError = .requestCanceled
                userInstructions = ["Installation was canceled", "Try installation again if needed"]
                
            case .requestSuperseded:
                submissionError = .requestSuperseded
                userInstructions = ["Request was superseded by newer request", "This is usually not an error"]
                
            case .extensionNotFound:
                submissionError = .extensionNotFound
                userInstructions = [
                    "System Extension bundle not found",
                    "Verify bundle path is correct",
                    "Ensure bundle is properly built"
                ]
                
            case .duplicateExtensionIdentifer:
                submissionError = .duplicateExtensionIdentifier
                userInstructions = [
                    "Extension with this identifier already exists",
                    "Uninstall existing extension first",
                    "Use unique bundle identifier"
                ]
                
            case .unsupportedParentBundleLocation:
                submissionError = .invalidBundle
                userInstructions = [
                    "System Extension is in unsupported location",
                    "Move extension to supported location",
                    "Check bundle packaging"
                ]
                
            case .extensionMissingIdentifier:
                submissionError = .invalidBundle
                userInstructions = [
                    "System Extension missing bundle identifier",
                    "Add CFBundleIdentifier to Info.plist",
                    "Rebuild the extension"
                ]
                
            case .unknownExtensionCategory:
                submissionError = .invalidBundle
                userInstructions = [
                    "Unknown System Extension category",
                    "Check extension type configuration",
                    "Verify entitlements"
                ]
                
            case .codeSignatureInvalid:
                submissionError = .invalidSignature
                userInstructions = [
                    "System Extension signature is invalid",
                    "Re-sign with valid certificate",
                    "Check certificate validity"
                ]
                
            case .validationFailed:
                submissionError = .invalidBundle
                userInstructions = [
                    "System Extension validation failed",
                    "Check bundle structure",
                    "Verify all required components"
                ]
                
            case .forbiddenBySystemPolicy:
                submissionError = .authorizationRequired
                userInstructions = [
                    "Installation forbidden by system policy",
                    "Check system security settings",
                    "May require admin approval"
                ]
                
            @unknown default:
                submissionError = .unknownError
                userInstructions = ["Unknown System Extension error", "Check system logs for details"]
            }
        } else {
            submissionError = .unknownError
            userInstructions = ["Unknown error occurred", "Check system logs for more information"]
        }
        
        completeSubmission(with: SubmissionResult(
            status: .failed(error: submissionError),
            submissionTime: submissionTime,
            userInstructions: userInstructions,
            errorDetails: error.localizedDescription
        ))
    }
}