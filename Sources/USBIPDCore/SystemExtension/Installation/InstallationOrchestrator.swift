// InstallationOrchestrator.swift
// Installation orchestrator for coordinating complete System Extension installation workflow

import Foundation
import SystemExtensions
import Common

/// Progress reporter protocol for installation status updates
public protocol InstallationProgressReporter {
    /// Report installation progress with current status
    /// - Parameters:
    ///   - phase: Current installation phase
    ///   - progress: Progress percentage (0.0 to 1.0)
    ///   - message: Human-readable status message
    ///   - userActions: Optional user actions required
    func reportProgress(phase: InstallationPhase, progress: Double, message: String, userActions: [String]?)
}

/// Installation phase tracking
public enum InstallationPhase: String, CaseIterable {
    case bundleDetection = "bundle_detection"
    case systemExtensionSubmission = "system_extension_submission" 
    case serviceIntegration = "service_integration"
    case installationVerification = "installation_verification"
    case completed = "completed"
    case failed = "failed"
}

/// Complete installation result
public struct InstallationResult {
    /// Overall installation success
    public let success: Bool
    
    /// Final installation phase reached
    public let finalPhase: InstallationPhase
    
    /// Bundle detection result
    public let bundleDetectionResult: SystemExtensionBundleDetector.DetectionResult?
    
    /// System Extension submission result
    public let submissionResult: SubmissionResult?
    
    /// Service integration result
    public let serviceIntegrationResult: ServiceIntegrationResult?
    
    /// Installation verification result
    public let verificationResult: InstallationVerificationResult?
    
    /// Any issues encountered during installation
    public let issues: [String]
    
    /// Recommendations for the user
    public let recommendations: [String]
    
    /// Installation completion time
    public let completionTime: Date
    
    /// Total installation duration
    public let duration: TimeInterval
    
    public init(
        success: Bool,
        finalPhase: InstallationPhase,
        bundleDetectionResult: SystemExtensionBundleDetector.DetectionResult? = nil,
        submissionResult: SubmissionResult? = nil,
        serviceIntegrationResult: ServiceIntegrationResult? = nil,
        verificationResult: InstallationVerificationResult? = nil,
        issues: [String] = [],
        recommendations: [String] = [],
        completionTime: Date = Date(),
        duration: TimeInterval = 0
    ) {
        self.success = success
        self.finalPhase = finalPhase
        self.bundleDetectionResult = bundleDetectionResult
        self.submissionResult = submissionResult
        self.serviceIntegrationResult = serviceIntegrationResult
        self.verificationResult = verificationResult
        self.issues = issues
        self.recommendations = recommendations
        self.completionTime = completionTime
        self.duration = duration
    }
}

/// Installation error types
public enum InstallationError: Error, LocalizedError {
    case bundleDetectionFailed(details: String)
    case systemExtensionSubmissionFailed(error: SystemExtensionSubmissionError)
    case serviceIntegrationFailed(details: String)
    case verificationFailed(details: String)
    case installationTimeout
    case userCancelled
    case unknownError(underlying: Error)
    
    public var errorDescription: String? {
        switch self {
        case .bundleDetectionFailed(let details):
            return "Bundle detection failed: \(details)"
        case .systemExtensionSubmissionFailed(let error):
            return "System Extension submission failed: \(error.localizedDescription)"
        case .serviceIntegrationFailed(let details):
            return "Service integration failed: \(details)"
        case .verificationFailed(let details):
            return "Installation verification failed: \(details)"
        case .installationTimeout:
            return "Installation timed out"
        case .userCancelled:
            return "Installation was cancelled by user"
        case .unknownError(let underlying):
            return "Unknown installation error: \(underlying.localizedDescription)"
        }
    }
}

/// Orchestrator for coordinating complete System Extension installation workflow
public final class InstallationOrchestrator: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.github.usbipd-mac", category: "InstallationOrchestrator")
    
    /// Bundle detector for finding System Extension bundles
    private let bundleDetector: SystemExtensionBundleDetector
    
    /// Submission manager for System Extension registration
    private let submissionManager: SystemExtensionSubmissionManager
    
    /// Service lifecycle manager for launchd integration
    private let serviceManager: ServiceLifecycleManager
    
    /// Installation verification manager
    private let verificationManager: InstallationVerificationManager
    
    /// Progress reporter for user feedback
    public weak var progressReporter: InstallationProgressReporter?
    
    /// Installation timeout (default: 300 seconds / 5 minutes)
    public var installationTimeout: TimeInterval = 300.0
    
    /// Current installation phase
    public private(set) var currentPhase: InstallationPhase = .bundleDetection
    
    /// Installation start time
    private var installationStartTime: Date?
    
    // MARK: - Initialization
    
    /// Initialize installation orchestrator with component managers
    /// - Parameters:
    ///   - bundleDetector: Bundle detector for System Extension discovery
    ///   - submissionManager: Manager for System Extension submission
    ///   - serviceManager: Manager for service lifecycle coordination
    ///   - verificationManager: Manager for installation verification
    public init(
        bundleDetector: SystemExtensionBundleDetector = SystemExtensionBundleDetector(),
        submissionManager: SystemExtensionSubmissionManager = SystemExtensionSubmissionManager(),
        serviceManager: ServiceLifecycleManager = ServiceLifecycleManager(),
        verificationManager: InstallationVerificationManager = InstallationVerificationManager()
    ) {
        self.bundleDetector = bundleDetector
        self.submissionManager = submissionManager
        self.serviceManager = serviceManager
        self.verificationManager = verificationManager
        
        logger.info("InstallationOrchestrator initialized")
    }
    
    // MARK: - Public Interface
    
    /// Perform complete System Extension installation workflow
    /// - Returns: Complete installation result
    public func performCompleteInstallation() async -> InstallationResult {
        logger.info("Starting complete System Extension installation workflow")
        
        let startTime = Date()
        installationStartTime = startTime
        var collectedIssues: [String] = []
        var collectedRecommendations: [String] = []
        
        var bundleResult: SystemExtensionBundleDetector.DetectionResult?
        var submissionResult: SubmissionResult?
        var serviceResult: ServiceIntegrationResult?
        var verificationResult: InstallationVerificationResult?
        
        do {
            // Phase 1: Bundle Detection
            currentPhase = .bundleDetection
            reportInstallationProgress(phase: .bundleDetection, progress: 0.1, 
                                     message: "Detecting System Extension bundle...")
            
            bundleResult = try await performBundleDetection()
            
            guard let bundlePath = bundleResult?.bundlePath else {
                throw InstallationError.bundleDetectionFailed(details: "No valid bundle found")
            }
            
            // Phase 2: System Extension Submission
            currentPhase = .systemExtensionSubmission
            reportInstallationProgress(phase: .systemExtensionSubmission, progress: 0.3,
                                     message: "Submitting System Extension to macOS for approval...")
            
            submissionResult = try await performSystemExtensionSubmission(bundlePath: bundlePath)
            
            // Phase 3: Service Integration
            currentPhase = .serviceIntegration
            reportInstallationProgress(phase: .serviceIntegration, progress: 0.6,
                                     message: "Integrating with service management...")
            
            serviceResult = try await performServiceIntegration()
            
            // Phase 4: Installation Verification
            currentPhase = .installationVerification
            reportInstallationProgress(phase: .installationVerification, progress: 0.8,
                                     message: "Verifying installation status...")
            
            verificationResult = try await performInstallationVerification()
            
            // Phase 5: Completion
            currentPhase = .completed
            reportInstallationProgress(phase: .completed, progress: 1.0,
                                     message: "System Extension installation completed successfully!")
            
            // Collect all recommendations
            collectedRecommendations.append(contentsOf: bundleResult?.issues ?? [])
            if let serviceRecs = serviceResult?.recommendations {
                collectedRecommendations.append(contentsOf: serviceRecs)
            }
            if let verificationRecs = verificationResult?.recommendations {
                collectedRecommendations.append(contentsOf: verificationRecs)
            }
            
            let result = InstallationResult(
                success: true,
                finalPhase: .completed,
                bundleDetectionResult: bundleResult,
                submissionResult: submissionResult,
                serviceIntegrationResult: serviceResult,
                verificationResult: verificationResult,
                issues: collectedIssues,
                recommendations: collectedRecommendations,
                completionTime: Date(),
                duration: Date().timeIntervalSince(startTime)
            )
            
            logger.info("Complete installation workflow succeeded", context: [
                "duration": result.duration
            ])
            
            return result
            
        } catch {
            return await handleInstallationFailure(
                error: error,
                bundleResult: bundleResult,
                submissionResult: submissionResult,
                serviceResult: serviceResult,
                verificationResult: verificationResult,
                startTime: startTime,
                collectedIssues: collectedIssues,
                collectedRecommendations: collectedRecommendations
            )
        }
    }
    
    /// Handle installation failure with proper error recovery
    /// - Parameters:
    ///   - error: The error that caused the failure
    ///   - bundleResult: Bundle detection result (if completed)
    ///   - submissionResult: Submission result (if completed)
    ///   - serviceResult: Service integration result (if completed)
    ///   - verificationResult: Verification result (if completed)
    ///   - startTime: Installation start time
    ///   - collectedIssues: Issues collected during installation
    ///   - collectedRecommendations: Recommendations collected during installation
    /// - Returns: Installation result with failure details
    public func handleInstallationFailure(
        error: Error,
        bundleResult: SystemExtensionBundleDetector.DetectionResult?,
        submissionResult: SubmissionResult?,
        serviceResult: ServiceIntegrationResult?,
        verificationResult: InstallationVerificationResult?,
        startTime: Date,
        collectedIssues: [String],
        collectedRecommendations: [String]
    ) async -> InstallationResult {
        
        logger.error("Installation workflow failed", context: [
            "error": error.localizedDescription,
            "phase": currentPhase.rawValue
        ])
        
        currentPhase = .failed
        
        var issues = collectedIssues
        var recommendations = collectedRecommendations
        
        // Add error-specific details
        issues.append(error.localizedDescription)
        
        // Add recovery recommendations based on failure phase and type
        recommendations.append(contentsOf: generateRecoveryRecommendations(for: error))
        
        reportInstallationProgress(
            phase: .failed, 
            progress: 0.0,
            message: "Installation failed: \(error.localizedDescription)",
            userActions: recommendations.isEmpty ? nil : Array(recommendations.prefix(3))
        )
        
        return InstallationResult(
            success: false,
            finalPhase: .failed,
            bundleDetectionResult: bundleResult,
            submissionResult: submissionResult,
            serviceIntegrationResult: serviceResult,
            verificationResult: verificationResult,
            issues: issues,
            recommendations: recommendations,
            completionTime: Date(),
            duration: Date().timeIntervalSince(startTime)
        )
    }
    
    /// Report installation progress to registered reporter
    /// - Parameters:
    ///   - phase: Current installation phase
    ///   - progress: Progress percentage (0.0 to 1.0)
    ///   - message: Status message
    ///   - userActions: Optional user actions required
    public func reportInstallationProgress(
        phase: InstallationPhase, 
        progress: Double, 
        message: String, 
        userActions: [String]? = nil
    ) {
        logger.info("Installation progress", context: [
            "phase": phase.rawValue,
            "progress": progress,
            "message": message
        ])
        
        progressReporter?.reportProgress(
            phase: phase,
            progress: progress,
            message: message,
            userActions: userActions
        )
    }
    
    // MARK: - Private Implementation
    
    /// Perform bundle detection phase
    private func performBundleDetection() async throws -> SystemExtensionBundleDetector.DetectionResult {
        logger.info("Performing bundle detection")
        
        let result = bundleDetector.detectBundle()
        
        guard result.found, let bundlePath = result.bundlePath else {
            let error = "Bundle detection failed: \(result.issues.joined(separator: ", "))"
            logger.error(error)
            throw InstallationError.bundleDetectionFailed(details: error)
        }
        
        logger.info("Bundle detection succeeded", context: [
            "bundlePath": bundlePath,
            "environment": "\(result.detectionEnvironment)"
        ])
        
        return result
    }
    
    /// Perform System Extension submission phase
    private func performSystemExtensionSubmission(bundlePath: String) async throws -> SubmissionResult {
        logger.info("Performing System Extension submission", context: [
            "bundlePath": bundlePath
        ])
        
        return try await withCheckedThrowingContinuation { continuation in
            submissionManager.submitExtension(bundlePath: bundlePath) { result in
                switch result.status {
                case .approved:
                    self.logger.info("System Extension submission succeeded")
                    continuation.resume(returning: result)
                case .failed(let error):
                    self.logger.error("System Extension submission failed", context: [
                        "error": error.localizedDescription
                    ])
                    continuation.resume(throwing: InstallationError.systemExtensionSubmissionFailed(error: error))
                default:
                    // For other statuses, we consider this a failure for now
                    self.logger.warning("System Extension submission incomplete", context: [
                        "status": "\(result.status)"
                    ])
                    continuation.resume(throwing: InstallationError.systemExtensionSubmissionFailed(error: .requestFailed))
                }
            }
        }
    }
    
    /// Perform service integration phase
    private func performServiceIntegration() async throws -> ServiceIntegrationResult {
        logger.info("Performing service integration")
        
        let result = await serviceManager.coordinateInstallationWithService()
        
        if !result.serviceIntegrationStatus.hasServiceManagementIssues {
            logger.info("Service integration succeeded")
            return result
        } else {
            let error = "Service integration issues: \(result.issues.map { $0.description }.joined(separator: ", "))"
            logger.error(error)
            throw InstallationError.serviceIntegrationFailed(details: error)
        }
    }
    
    /// Perform installation verification phase
    private func performInstallationVerification() async throws -> InstallationVerificationResult {
        logger.info("Performing installation verification")
        
        let result = await verificationManager.verifyInstallation()
        
        switch result.overallStatus {
        case .fullyFunctional, .functionalWithIssues:
            logger.info("Installation verification succeeded", context: [
                "status": "\(result.overallStatus)"
            ])
            return result
        case .nonFunctional, .notInstalled, .unknown:
            let error = "Installation verification failed: \(result.overallStatus)"
            logger.error(error)
            throw InstallationError.verificationFailed(details: error)
        }
    }
    
    /// Generate recovery recommendations based on error type
    private func generateRecoveryRecommendations(for error: Error) -> [String] {
        var recommendations: [String] = []
        
        switch error {
        case InstallationError.bundleDetectionFailed:
            recommendations.append("Ensure System Extension bundle is built (run: swift build)")
            recommendations.append("Check if running from Homebrew installation")
            recommendations.append("Verify bundle permissions and file system access")
            
        case InstallationError.systemExtensionSubmissionFailed(let submissionError):
            switch submissionError {
            case .userApprovalRequired:
                recommendations.append("Open System Preferences > Security & Privacy")
                recommendations.append("Allow system extension from developer")
                recommendations.append("Restart installation after approval")
            case .requestInProgress:
                recommendations.append("Wait for current submission to complete")
                recommendations.append("Check System Preferences for pending approvals")
            default:
                recommendations.append("Check System Preferences > Security & Privacy")
                recommendations.append("Restart macOS and try again")
                recommendations.append("Contact support if issue persists")
            }
            
        case InstallationError.serviceIntegrationFailed:
            recommendations.append("Check if usbipd-mac service is running (brew services list)")
            recommendations.append("Restart service: brew services restart usbipd-mac")
            recommendations.append("Check launchd service registration")
            
        case InstallationError.verificationFailed:
            recommendations.append("Run diagnostic: usbipd diagnose --verbose")
            recommendations.append("Check systemextensionsctl list for registration")
            recommendations.append("Restart System Extension: systemextensionsctl reset")
            
        default:
            recommendations.append("Try running installation again")
            recommendations.append("Check system logs for detailed error information")
            recommendations.append("Contact support if issue persists")
        }
        
        return recommendations
    }
}