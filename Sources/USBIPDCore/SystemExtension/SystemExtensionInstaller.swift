import Foundation
import SystemExtensions
import Common

/// Manages System Extension installation and lifecycle
public class SystemExtensionInstaller: NSObject {
    
    /// Installation status
    public enum InstallationStatus: Equatable {
        case notInstalled
        case installing
        case installed
        case requiresApproval
        case failed(String)
        
        public static func == (lhs: InstallationStatus, rhs: InstallationStatus) -> Bool {
            switch (lhs, rhs) {
            case (.notInstalled, .notInstalled),
                 (.installing, .installing),
                 (.installed, .installed),
                 (.requiresApproval, .requiresApproval):
                return true
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError == rhsError
            default:
                return false
            }
        }
    }
    
    /// Installation completion handler
    public typealias InstallationCompletion = (Result<Void, SystemExtensionInstallationError>) -> Void
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.github.usbipd-mac", category: "SystemExtensionInstaller")
    private let bundleIdentifier: String
    private let bundlePath: String
    
    private var installationCompletion: InstallationCompletion?
    private var currentRequest: OSSystemExtensionRequest?
    
    /// Current installation status
    public private(set) var status: InstallationStatus = .notInstalled
    
    // MARK: - Initialization
    
    /// Initialize with System Extension bundle information
    /// - Parameters:
    ///   - bundleIdentifier: The bundle identifier of the System Extension
    ///   - bundlePath: Path to the System Extension bundle
    public init(bundleIdentifier: String, bundlePath: String) {
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        super.init()
        
        logger.info("SystemExtensionInstaller initialized", context: [
            "bundleIdentifier": bundleIdentifier,
            "bundlePath": bundlePath
        ])
    }
    
    // MARK: - Installation Management
    
    /// Install or activate the System Extension
    /// - Parameter completion: Completion handler called when installation completes
    public func install(completion: @escaping InstallationCompletion) {
        logger.info("Starting System Extension installation")
        
        guard status != .installing else {
            logger.warning("Installation already in progress")
            completion(.failure(.internalError("Installation already in progress")))
            return
        }
        
        // Verify bundle exists
        guard Bundle(path: bundlePath) != nil else {
            logger.error("System Extension bundle not found", context: ["path": bundlePath])
            let error = SystemExtensionInstallationError.bundleNotFound(bundlePath)
            status = .failed(error.localizedDescription)
            completion(.failure(error))
            return
        }
        
        self.installationCompletion = completion
        status = .installing
        
        // Create and submit activation request
        do {
            let request = try createActivationRequest()
            currentRequest = request
            
            logger.info("Submitting System Extension activation request")
            OSSystemExtensionManager.shared.submitRequest(request)
        } catch {
            logger.error("Failed to create activation request", context: ["error": error.localizedDescription])
            let installError = SystemExtensionInstallationError.internalError("Request creation failed: \(error.localizedDescription)")
            status = .failed(installError.localizedDescription)
            completion(.failure(installError))
        }
    }
    
    /// Uninstall the System Extension
    /// - Parameter completion: Completion handler called when uninstallation completes
    public func uninstall(completion: @escaping InstallationCompletion) {
        logger.info("Starting System Extension uninstallation")
        
        guard status != .installing else {
            logger.warning("Cannot uninstall during active installation")
            completion(.failure(.internalError("Installation in progress")))
            return
        }
        
        self.installationCompletion = completion
        status = .installing
        
        // Create and submit deactivation request
        do {
            let request = try createDeactivationRequest()
            currentRequest = request
            
            logger.info("Submitting System Extension deactivation request")
            OSSystemExtensionManager.shared.submitRequest(request)
        } catch {
            logger.error("Failed to create deactivation request", context: ["error": error.localizedDescription])
            let installError = SystemExtensionInstallationError.internalError("Request creation failed: \(error.localizedDescription)")
            status = .failed(installError.localizedDescription)
            completion(.failure(installError))
        }
    }
    
    /// Check if System Extension is currently installed
    public func checkInstallationStatus() {
        // Note: In a complete implementation, this would query the system
        // for the actual installation status of the System Extension
        logger.debug("Checking System Extension installation status")
        
        // For now, we'll rely on the tracked status
        // In a real implementation, you might use:
        // - Query system extension registry
        // - Check if system extension is loaded
        // - Verify bundle presence and validity
    }
    
    // MARK: - Request Creation
    
    private func createActivationRequest() throws -> OSSystemExtensionRequest {
        logger.debug("Creating System Extension activation request")
        
        guard !bundleIdentifier.isEmpty else {
            throw SystemExtensionInstallationError.invalidBundle("Empty bundle identifier")
        }
        
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: bundleIdentifier,
            queue: .main
        )
        
        request.delegate = self
        
        logger.debug("Activation request created successfully")
        return request
    }
    
    private func createDeactivationRequest() throws -> OSSystemExtensionRequest {
        logger.debug("Creating System Extension deactivation request")
        
        guard !bundleIdentifier.isEmpty else {
            throw SystemExtensionInstallationError.invalidBundle("Empty bundle identifier")
        }
        
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: bundleIdentifier,
            queue: .main
        )
        
        request.delegate = self
        
        logger.debug("Deactivation request created successfully")
        return request
    }
    
    // MARK: - Completion Handling
    
    private func completeInstallation(with result: Result<Void, SystemExtensionInstallationError>) {
        guard let completion = installationCompletion else { return }
        
        installationCompletion = nil
        currentRequest = nil
        
        switch result {
        case .success:
            status = .installed
            logger.info("System Extension installation completed successfully")
        case .failure(let error):
            status = .failed(error.localizedDescription)
            logger.error("System Extension installation failed", context: ["error": error.localizedDescription])
        }
        
        completion(result)
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension SystemExtensionInstaller: OSSystemExtensionRequestDelegate {
    
    public func request(_ request: OSSystemExtensionRequest, 
                       actionForReplacingExtension existing: OSSystemExtensionProperties, 
                       withExtension extension: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        
        logger.info("System Extension replacement requested", context: [
            "existing": existing.bundleIdentifier,
            "new": `extension`.bundleIdentifier,
            "existingVersion": existing.bundleVersion,
            "newVersion": `extension`.bundleVersion
        ])
        
        // Allow replacement of existing extension
        return .replace
    }
    
    public func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.info("System Extension requires user approval")
        status = .requiresApproval
        
        // Note: Don't complete here - wait for final approval or denial
        logger.info("Waiting for user approval in System Preferences")
    }
    
    public func request(_ request: OSSystemExtensionRequest, 
                       didFinishWithResult result: OSSystemExtensionRequest.Result) {
        
        switch result {
        case .completed:
            logger.info("System Extension request completed successfully")
            completeInstallation(with: .success(()))
            
        case .willCompleteAfterReboot:
            logger.info("System Extension installation will complete after reboot")
            completeInstallation(with: .success(()))
            
        @unknown default:
            logger.warning("Unknown System Extension request result", context: ["result": String(describing: result)])
            completeInstallation(with: .failure(.unknownSystemError(OSStatus(-1), "Unknown result: \(result)")))
        }
    }
    
    public func request(_ request: OSSystemExtensionRequest, 
                       didFailWithError error: Error) {
        
        logger.error("System Extension request failed", context: ["error": error.localizedDescription])
        
        let installationError: SystemExtensionInstallationError
        
        if let osError = error as? OSSystemExtensionError {
            switch osError.code {
            case .unknown:
                installationError = .unknownSystemError(OSStatus(osError.code.rawValue), "Unknown system extension error")
            case .authorizationRequired:
                installationError = .requiresApproval
            case .unsupportedParentBundleLocation:
                installationError = .invalidBundle("Unsupported parent bundle location")
            case .extensionMissingIdentifier:
                installationError = .invalidBundle("Extension missing identifier")
            case .duplicateExtensionIdentifer:
                installationError = .conflictingInstallation("Extension with same identifier already exists")
            case .missingEntitlement:
                installationError = .missingEntitlements(["Required system extension entitlement"])
            case .extensionNotFound:
                installationError = .bundleNotFound(bundlePath)
            case .unknownExtensionCategory:
                installationError = .invalidConfiguration("Unknown extension category")
            case .codeSignatureInvalid:
                installationError = .invalidCodeSignature("Invalid code signature")
            case .validationFailed:
                installationError = .invalidBundle("Extension validation failed")
            case .forbiddenBySystemPolicy:
                installationError = .policyViolation("Forbidden by system policy")
            case .requestCanceled:
                installationError = .installationCancelled
            case .requestSuperseded:
                installationError = .internalError("Request was superseded")
            @unknown default:
                installationError = .unknownSystemError(OSStatus(osError.code.rawValue), osError.localizedDescription)
            }
        } else {
            installationError = .internalError(error.localizedDescription)
        }
        
        completeInstallation(with: .failure(installationError))
    }
}
