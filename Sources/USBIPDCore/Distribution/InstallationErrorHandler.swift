// InstallationErrorHandler.swift
// Comprehensive error handling and recovery guidance for System Extension installation

import Foundation
import Common

/// Comprehensive error handler for System Extension installation failures
public class InstallationErrorHandler {
    
    // MARK: - Properties
    
    private let logger: Logger
    
    // MARK: - Initialization
    
    /// Initialize error handler with optional custom logger
    /// - Parameter logger: Custom logger instance (uses shared logger if nil)
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger.shared
    }
    
    // MARK: - Error Categorization
    
    /// Categorize installation error and provide recovery guidance
    /// - Parameter error: Installation error to categorize
    /// - Returns: Categorized error with remediation steps
    public func categorizeInstallationError(_ error: Error) -> CategorizedInstallationError {
        logger.info("Categorizing installation error", context: [
            "error_description": error.localizedDescription,
            "error_type": String(describing: type(of: error))
        ])
        
        let errorDescription = error.localizedDescription.lowercased()
        let errorType = String(describing: type(of: error)).lowercased()
        
        // Analyze error patterns and categorize
        let category = determineErrorCategory(description: errorDescription, type: errorType)
        let severity = determineSeverity(for: category, error: error)
        let userMessage = generateUserFriendlyMessage(for: category, originalError: error)
        let remediationSteps = generateRemediationSteps(for: category, error: error)
        let troubleshootingInfo = generateTroubleshootingInfo(for: category)
        let recoveryOptions = generateRecoveryOptions(for: category)
        
        return CategorizedInstallationError(
            originalError: error,
            category: category,
            severity: severity,
            userFriendlyMessage: userMessage,
            technicalDetails: error.localizedDescription,
            remediationSteps: remediationSteps,
            troubleshootingInfo: troubleshootingInfo,
            recoveryOptions: recoveryOptions,
            estimatedResolutionTime: getEstimatedResolutionTime(for: category),
            requiresUserAction: requiresUserAction(for: category),
            canRetryAutomatically: canRetryAutomatically(for: category),
            relatedCommands: getRelatedCommands(for: category),
            helpfulResources: getHelpfulResources(for: category)
        )
    }
    
    /// Generate comprehensive error report for multiple installation failures
    /// - Parameter errors: Array of installation errors
    /// - Returns: Formatted error report with prioritized remediation
    public func generateErrorReport(for errors: [Error]) -> InstallationErrorReport {
        logger.info("Generating error report", context: ["error_count": errors.count])
        
        let categorizedErrors = errors.map { categorizeInstallationError($0) }
        let criticalErrors = categorizedErrors.filter { $0.severity == .critical }
        let majorErrors = categorizedErrors.filter { $0.severity == .major }
        let minorErrors = categorizedErrors.filter { $0.severity == .minor }
        
        // Generate prioritized remediation plan
        let remediationPlan = generatePrioritizedRemediationPlan(from: categorizedErrors)
        
        // Determine overall installation status
        let overallStatus: InstallationStatus
        if !criticalErrors.isEmpty {
            overallStatus = .failed
        } else if !majorErrors.isEmpty {
            overallStatus = .partiallySuccessful
        } else if !minorErrors.isEmpty {
            overallStatus = .successfulWithWarnings
        } else {
            overallStatus = .successful
        }
        
        return InstallationErrorReport(
            overallStatus: overallStatus,
            categorizedErrors: categorizedErrors,
            criticalErrors: criticalErrors,
            majorErrors: majorErrors,
            minorErrors: minorErrors,
            prioritizedRemediationPlan: remediationPlan,
            estimatedTotalResolutionTime: calculateTotalResolutionTime(from: categorizedErrors),
            nextSteps: generateNextSteps(for: overallStatus, errors: categorizedErrors),
            troubleshootingCommands: generateTroubleshootingCommands(from: categorizedErrors),
            contactSupport: shouldContactSupport(for: categorizedErrors),
            timestamp: Date()
        )
    }
    
    // MARK: - Error Category Determination
    
    private func determineErrorCategory(description: String, type: String) -> InstallationErrorCategory {
        // System Extension specific errors
        if description.contains("system extension") || description.contains("systemextension") {
            if description.contains("not approved") || description.contains("approval") {
                return .systemExtensionApprovalRequired
            } else if description.contains("already installed") || description.contains("duplicate") {
                return .systemExtensionConflict
            } else if description.contains("invalid") || description.contains("corrupt") {
                return .bundleIntegrityFailure
            } else {
                return .systemExtensionRegistrationFailure
            }
        }
        
        // Permission and access errors
        if description.contains("permission") || description.contains("access") || description.contains("denied") {
            if description.contains("full disk access") {
                return .insufficientSystemPermissions
            } else if description.contains("developer") || description.contains("unsigned") {
                return .developerModeRequired
            } else {
                return .insufficientSystemPermissions
            }
        }
        
        // Bundle and file system errors
        if description.contains("bundle") || description.contains("not found") || description.contains("missing") {
            return .bundleIntegrityFailure
        }
        
        // Code signing errors
        if description.contains("signature") || description.contains("signing") || description.contains("certificate") {
            return .codeSigningFailure
        }
        
        // IOKit and hardware errors
        if description.contains("iokit") || description.contains("usb") || description.contains("device") {
            return .ioKitIntegrationFailure
        }
        
        // Network and connectivity errors
        if description.contains("network") || description.contains("connection") || description.contains("timeout") {
            return .networkConfigurationError
        }
        
        // System integrity errors
        if description.contains("sip") || description.contains("integrity") || description.contains("policy") {
            return .systemIntegrityProtectionIssue
        }
        
        // Dependency errors
        if description.contains("dependency") || description.contains("framework") || description.contains("library") {
            return .dependencyError
        }
        
        // Environment errors
        if description.contains("environment") || description.contains("configuration") || description.contains("setting") {
            return .environmentConfigurationError
        }
        
        // Default to unknown for unrecognized patterns
        return .unknownError
    }
    
    private func determineSeverity(for category: InstallationErrorCategory, error: Error) -> ErrorSeverity {
        switch category {
        case .systemExtensionRegistrationFailure, .bundleIntegrityFailure, .ioKitIntegrationFailure:
            return .critical
        case .systemExtensionApprovalRequired, .insufficientSystemPermissions, .codeSigningFailure:
            return .major
        case .systemExtensionConflict, .developerModeRequired, .networkConfigurationError:
            return .major
        case .systemIntegrityProtectionIssue, .dependencyError, .environmentConfigurationError:
            return .major
        case .unknownError:
            return .critical // Treat unknown errors as critical until analyzed
        }
    }
    
    // MARK: - User-Friendly Message Generation
    
    private func generateUserFriendlyMessage(for category: InstallationErrorCategory, originalError: Error) -> String {
        switch category {
        case .systemExtensionRegistrationFailure:
            return "The USB/IP System Extension failed to register with macOS. This usually happens when the system can't properly load or initialize the extension."
            
        case .systemExtensionApprovalRequired:
            return "macOS requires your approval to install the USB/IP System Extension. Please check System Preferences for a security notification and approve the extension."
            
        case .systemExtensionConflict:
            return "Another System Extension is conflicting with USB/IP. You may have multiple USB or device management extensions installed that are interfering with each other."
            
        case .bundleIntegrityFailure:
            return "The USB/IP System Extension bundle is corrupted or incomplete. This can happen if the build process was interrupted or files were damaged."
            
        case .insufficientSystemPermissions:
            return "USB/IP doesn't have the necessary system permissions to operate. The application needs Full Disk Access and other security permissions to manage USB devices."
            
        case .codeSigningFailure:
            return "The USB/IP System Extension is not properly code signed. macOS requires System Extensions to be digitally signed for security reasons."
            
        case .developerModeRequired:
            return "Your System Extension is unsigned and requires Developer Mode to be enabled. This is common during development or when using unofficial builds."
            
        case .ioKitIntegrationFailure:
            return "USB/IP can't connect to the macOS USB subsystem (IOKit). This prevents the application from accessing and managing USB devices."
            
        case .networkConfigurationError:
            return "USB/IP encountered a network configuration problem. This affects the ability to share USB devices over the network."
            
        case .systemIntegrityProtectionIssue:
            return "macOS System Integrity Protection (SIP) is preventing USB/IP from installing properly. This is a security feature that restricts system modifications."
            
        case .dependencyError:
            return "USB/IP is missing required system frameworks or dependencies. This can happen if your macOS version is incompatible or system files are damaged."
            
        case .environmentConfigurationError:
            return "Your system environment isn't configured correctly for USB/IP. This includes system settings, user permissions, or development tools configuration."
            
        case .unknownError:
            return "An unexpected error occurred during USB/IP installation. This might be a new issue that needs further investigation."
        }
    }
    
    // MARK: - Remediation Steps Generation
    
    private func generateRemediationSteps(for category: InstallationErrorCategory, error: Error) -> [RemediationStep] {
        switch category {
        case .systemExtensionRegistrationFailure:
            return [
                RemediationStep(
                    stepNumber: 1,
                    description: "Restart the System Extension registration process",
                    command: "sudo systemextensionsctl reset",
                    explanation: "This clears any cached registration state and forces a fresh registration attempt.",
                    riskLevel: .medium,
                    estimatedTime: "1-2 minutes"
                ),
                RemediationStep(
                    stepNumber: 2,
                    description: "Rebuild the System Extension bundle",
                    command: "swift build --product USBIPDSystemExtension",
                    explanation: "Ensures you have a fresh, properly built System Extension bundle.",
                    riskLevel: .low,
                    estimatedTime: "2-5 minutes"
                ),
                RemediationStep(
                    stepNumber: 3,
                    description: "Attempt registration again",
                    command: "Scripts/install-extension.sh",
                    explanation: "Runs the installation script which handles proper System Extension registration.",
                    riskLevel: .low,
                    estimatedTime: "1-3 minutes"
                ),
                RemediationStep(
                    stepNumber: 4,
                    description: "If still failing, restart your computer",
                    command: "sudo reboot",
                    explanation: "A restart can clear system state issues that prevent System Extension registration.",
                    riskLevel: .medium,
                    estimatedTime: "5-10 minutes"
                )
            ]
            
        case .systemExtensionApprovalRequired:
            return [
                RemediationStep(
                    stepNumber: 1,
                    description: "Open System Preferences > Security & Privacy",
                    command: "open 'x-apple.systempreferences:com.apple.preference.security'",
                    explanation: "This opens the Security & Privacy preferences where system extension approvals are managed.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 2,
                    description: "Look for a notification about blocking a system extension",
                    command: nil,
                    explanation: "macOS will show a notification at the bottom of the General tab when a system extension needs approval.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 3,
                    description: "Click 'Allow' to approve the USB/IP System Extension",
                    command: nil,
                    explanation: "This gives permission for the USB/IP System Extension to run on your system.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 4,
                    description: "Restart the computer to complete activation",
                    command: "sudo reboot",
                    explanation: "Some System Extension approvals require a restart to take effect.",
                    riskLevel: .medium,
                    estimatedTime: "5-10 minutes"
                )
            ]
            
        case .systemExtensionConflict:
            return [
                RemediationStep(
                    stepNumber: 1,
                    description: "List all installed System Extensions",
                    command: "systemextensionsctl list",
                    explanation: "This shows all currently installed System Extensions so you can identify conflicts.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 2,
                    description: "Identify conflicting USB or device management extensions",
                    command: nil,
                    explanation: "Look for other extensions that might handle USB devices or hardware management.",
                    riskLevel: .low,
                    estimatedTime: "1-2 minutes"
                ),
                RemediationStep(
                    stepNumber: 3,
                    description: "Uninstall conflicting extensions",
                    command: "systemextensionsctl uninstall <team-id> <bundle-id>",
                    explanation: "Remove extensions that conflict with USB/IP. Note the team-id and bundle-id from the list command.",
                    riskLevel: .medium,
                    estimatedTime: "2-5 minutes"
                ),
                RemediationStep(
                    stepNumber: 4,
                    description: "Restart and reinstall USB/IP System Extension",
                    command: "sudo reboot && Scripts/install-extension.sh",
                    explanation: "A clean restart followed by USB/IP installation should resolve the conflict.",
                    riskLevel: .medium,
                    estimatedTime: "10-15 minutes"
                )
            ]
            
        case .bundleIntegrityFailure:
            return [
                RemediationStep(
                    stepNumber: 1,
                    description: "Clean the build directory",
                    command: "swift package clean",
                    explanation: "Removes any corrupted build artifacts that might be causing integrity issues.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 2,
                    description: "Rebuild the entire project",
                    command: "swift build",
                    explanation: "Creates a fresh build of all components including the System Extension.",
                    riskLevel: .low,
                    estimatedTime: "2-5 minutes"
                ),
                RemediationStep(
                    stepNumber: 3,
                    description: "Verify bundle structure",
                    command: "ls -la .build/debug/USBIPDSystemExtension.systemextension/Contents/",
                    explanation: "Checks that the System Extension bundle has the correct internal structure.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 4,
                    description: "Reinstall with fresh bundle",
                    command: "Scripts/install-extension.sh",
                    explanation: "Installs the newly built, verified System Extension bundle.",
                    riskLevel: .low,
                    estimatedTime: "1-3 minutes"
                )
            ]
            
        case .insufficientSystemPermissions:
            return [
                RemediationStep(
                    stepNumber: 1,
                    description: "Open System Preferences > Security & Privacy > Privacy",
                    command: "open 'x-apple.systempreferences:com.apple.preference.security?Privacy'",
                    explanation: "Opens the Privacy settings where you can grant necessary permissions.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 2,
                    description: "Grant Full Disk Access to USB/IP",
                    command: nil,
                    explanation: "Find 'Full Disk Access' in the left sidebar and add the USB/IP application.",
                    riskLevel: .low,
                    estimatedTime: "1-2 minutes"
                ),
                RemediationStep(
                    stepNumber: 3,
                    description: "Grant Developer Tools access if needed",
                    command: nil,
                    explanation: "For development builds, you may need to grant Developer Tools access as well.",
                    riskLevel: .low,
                    estimatedTime: "1 minute"
                ),
                RemediationStep(
                    stepNumber: 4,
                    description: "Restart the USB/IP application",
                    command: nil,
                    explanation: "Restart the application to ensure it uses the newly granted permissions.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                )
            ]
            
        case .developerModeRequired:
            return [
                RemediationStep(
                    stepNumber: 1,
                    description: "Enable System Extension Developer Mode",
                    command: "sudo systemextensionsctl developer on",
                    explanation: "Allows unsigned System Extensions to be installed for development purposes.",
                    riskLevel: .medium,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 2,
                    description: "Restart your computer",
                    command: "sudo reboot",
                    explanation: "Developer Mode changes require a restart to take effect.",
                    riskLevel: .medium,
                    estimatedTime: "5-10 minutes"
                ),
                RemediationStep(
                    stepNumber: 3,
                    description: "Reinstall the System Extension",
                    command: "Scripts/install-extension.sh",
                    explanation: "With Developer Mode enabled, the unsigned System Extension should install successfully.",
                    riskLevel: .low,
                    estimatedTime: "1-3 minutes"
                )
            ]
            
        case .codeSigningFailure:
            return [
                RemediationStep(
                    stepNumber: 1,
                    description: "Check if you have a valid Developer ID certificate",
                    command: "security find-identity -v -p codesigning",
                    explanation: "Lists available code signing certificates on your system.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 2,
                    description: "Either enable Developer Mode or obtain proper certificates",
                    command: "sudo systemextensionsctl developer on",
                    explanation: "Developer Mode allows unsigned extensions, or you can get Apple Developer certificates.",
                    riskLevel: .medium,
                    estimatedTime: "1-10 minutes"
                ),
                RemediationStep(
                    stepNumber: 3,
                    description: "Rebuild with proper signing configuration",
                    command: "swift build --configuration release",
                    explanation: "Rebuilds the System Extension with any available code signing configuration.",
                    riskLevel: .low,
                    estimatedTime: "2-5 minutes"
                )
            ]
            
        case .ioKitIntegrationFailure:
            return [
                RemediationStep(
                    stepNumber: 1,
                    description: "Check USB subsystem status",
                    command: "ioreg -p IOUSB -l -w 0",
                    explanation: "Verifies that the macOS USB subsystem is functioning properly.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 2,
                    description: "Reset USB subsystem if needed",
                    command: "sudo kextunload -b com.apple.iokit.IOUSBFamily && sudo kextload -b com.apple.iokit.IOUSBFamily",
                    explanation: "Reloads the USB kernel extensions which can resolve integration issues.",
                    riskLevel: .medium,
                    estimatedTime: "1-2 minutes"
                ),
                RemediationStep(
                    stepNumber: 3,
                    description: "Reinstall USB/IP System Extension",
                    command: "Scripts/install-extension.sh",
                    explanation: "Reinstalls the System Extension which should now properly connect to the USB subsystem.",
                    riskLevel: .low,
                    estimatedTime: "1-3 minutes"
                )
            ]
            
        case .networkConfigurationError:
            return [
                RemediationStep(
                    stepNumber: 1,
                    description: "Check network connectivity",
                    command: "ping -c 3 8.8.8.8",
                    explanation: "Verifies basic network connectivity is working.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 2,
                    description: "Check firewall settings",
                    command: "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate",
                    explanation: "Checks if the macOS firewall might be blocking USB/IP network traffic.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 3,
                    description: "Restart network services",
                    command: "sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder",
                    explanation: "Clears network caches which can resolve configuration issues.",
                    riskLevel: .low,
                    estimatedTime: "1 minute"
                )
            ]
            
        case .systemIntegrityProtectionIssue:
            return [
                RemediationStep(
                    stepNumber: 1,
                    description: "Check SIP status",
                    command: "csrutil status",
                    explanation: "Shows whether System Integrity Protection is enabled and which components are protected.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 2,
                    description: "Enable Developer Mode instead of disabling SIP",
                    command: "sudo systemextensionsctl developer on",
                    explanation: "Developer Mode provides necessary access while keeping SIP enabled for security.",
                    riskLevel: .medium,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 3,
                    description: "Restart and reinstall",
                    command: "sudo reboot && Scripts/install-extension.sh",
                    explanation: "Restart to apply changes, then reinstall the System Extension.",
                    riskLevel: .medium,
                    estimatedTime: "10-15 minutes"
                )
            ]
            
        case .dependencyError:
            return [
                RemediationStep(
                    stepNumber: 1,
                    description: "Check macOS version compatibility",
                    command: "sw_vers",
                    explanation: "Verifies your macOS version supports System Extensions (requires 10.15+).",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 2,
                    description: "Verify Swift runtime availability",
                    command: "swift --version",
                    explanation: "Checks that the Swift runtime required by the System Extension is available.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 3,
                    description: "Update macOS if needed",
                    command: "softwareupdate -l",
                    explanation: "Lists available system updates that might resolve dependency issues.",
                    riskLevel: .low,
                    estimatedTime: "1 minute"
                )
            ]
            
        case .environmentConfigurationError:
            return [
                RemediationStep(
                    stepNumber: 1,
                    description: "Check development environment setup",
                    command: "xcode-select --print-path",
                    explanation: "Verifies that Xcode command line tools are properly installed and configured.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 2,
                    description: "Reset development environment if needed",
                    command: "sudo xcode-select --reset",
                    explanation: "Resets the development tools configuration to defaults.",
                    riskLevel: .low,
                    estimatedTime: "30 seconds"
                ),
                RemediationStep(
                    stepNumber: 3,
                    description: "Rebuild with clean environment",
                    command: "swift package clean && swift build",
                    explanation: "Cleans and rebuilds the project with the reset environment.",
                    riskLevel: .low,
                    estimatedTime: "2-5 minutes"
                )
            ]
            
        case .unknownError:
            return [
                RemediationStep(
                    stepNumber: 1,
                    description: "Gather diagnostic information",
                    command: "log show --last 1h --predicate 'subsystem CONTAINS \"systemextensions\" OR subsystem CONTAINS \"usbipd\"'",
                    explanation: "Collects recent system logs related to System Extensions and USB/IP for analysis.",
                    riskLevel: .low,
                    estimatedTime: "1-2 minutes"
                ),
                RemediationStep(
                    stepNumber: 2,
                    description: "Try a general System Extension reset",
                    command: "sudo systemextensionsctl reset",
                    explanation: "Resets the System Extension subsystem which can resolve various unknown issues.",
                    riskLevel: .medium,
                    estimatedTime: "1-2 minutes"
                ),
                RemediationStep(
                    stepNumber: 3,
                    description: "Restart and attempt clean installation",
                    command: "sudo reboot && swift package clean && swift build && Scripts/install-extension.sh",
                    explanation: "Performs a complete restart and clean rebuild to resolve unknown issues.",
                    riskLevel: .medium,
                    estimatedTime: "15-20 minutes"
                )
            ]
        }
    }
    
    // MARK: - Support Information Generation
    
    private func generateTroubleshootingInfo(for category: InstallationErrorCategory) -> TroubleshootingInfo {
        switch category {
        case .systemExtensionRegistrationFailure:
            return TroubleshootingInfo(
                commonCauses: [
                    "System Extension approval was denied by user",
                    "Conflicting System Extensions are installed",
                    "macOS System Extension framework is corrupted",
                    "Insufficient permissions for System Extension installation"
                ],
                diagnosticCommands: [
                    "systemextensionsctl list",
                    "systemextensionsctl developer",
                    "log show --last 1h --predicate 'subsystem CONTAINS \"systemextensions\"'"
                ],
                logLocations: [
                    "/var/log/system.log",
                    "Console.app > System Reports > system_extensions"
                ],
                relatedDocumentation: [
                    "https://developer.apple.com/documentation/systemextensions",
                    "https://support.apple.com/en-us/HT210999"
                ]
            )
            
        case .systemExtensionApprovalRequired:
            return TroubleshootingInfo(
                commonCauses: [
                    "System Extension installation requires user approval",
                    "Security preferences are restricting System Extensions",
                    "System Extension approval notification was missed"
                ],
                diagnosticCommands: [
                    "systemextensionsctl list",
                    "spctl --status"
                ],
                logLocations: [
                    "System Preferences > Security & Privacy > General"
                ],
                relatedDocumentation: [
                    "https://support.apple.com/guide/mac-help/mh40616/mac",
                    "https://support.apple.com/en-us/HT210999"
                ]
            )
            
        case .bundleIntegrityFailure:
            return TroubleshootingInfo(
                commonCauses: [
                    "System Extension bundle was corrupted during build",
                    "Build process was interrupted or incomplete",
                    "File system permissions prevent proper bundle creation",
                    "Insufficient disk space during build"
                ],
                diagnosticCommands: [
                    "ls -la .build/debug/USBIPDSystemExtension.systemextension/",
                    "file .build/debug/USBIPDSystemExtension.systemextension/Contents/MacOS/*",
                    "df -h ."
                ],
                logLocations: [
                    "Build output logs",
                    "Swift Package Manager logs"
                ],
                relatedDocumentation: [
                    "https://developer.apple.com/documentation/bundleresources",
                    "https://swift.org/package-manager/"
                ]
            )
            
        case .insufficientSystemPermissions:
            return TroubleshootingInfo(
                commonCauses: [
                    "Full Disk Access permission not granted",
                    "System Extension access is restricted",
                    "User account lacks administrative privileges",
                    "Privacy settings are blocking system access"
                ],
                diagnosticCommands: [
                    "id",
                    "groups",
                    "dscl . -read /Groups/admin GroupMembership"
                ],
                logLocations: [
                    "System Preferences > Security & Privacy > Privacy",
                    "/var/log/authd.log"
                ],
                relatedDocumentation: [
                    "https://support.apple.com/guide/mac-help/mchld5a35146/mac",
                    "https://developer.apple.com/documentation/security"
                ]
            )
            
        case .developerModeRequired:
            return TroubleshootingInfo(
                commonCauses: [
                    "System Extension is not code signed",
                    "Developer Mode is disabled",
                    "Invalid or expired developer certificates",
                    "System Integrity Protection blocking unsigned code"
                ],
                diagnosticCommands: [
                    "systemextensionsctl developer",
                    "security find-identity -v -p codesigning",
                    "codesign -vv .build/debug/USBIPDSystemExtension.systemextension"
                ],
                logLocations: [
                    "/var/log/install.log",
                    "Console.app > System Reports > security"
                ],
                relatedDocumentation: [
                    "https://developer.apple.com/documentation/xcode/notarizing_macos_software_before_distribution",
                    "https://developer.apple.com/support/compare-memberships/"
                ]
            )
            
        default:
            return TroubleshootingInfo(
                commonCauses: [
                    "System configuration issue",
                    "Software compatibility problem",
                    "Temporary system state conflict"
                ],
                diagnosticCommands: [
                    "systemextensionsctl list",
                    "log show --last 1h --predicate 'subsystem CONTAINS \"systemextensions\"'",
                    "sw_vers"
                ],
                logLocations: [
                    "/var/log/system.log",
                    "Console.app"
                ],
                relatedDocumentation: [
                    "https://developer.apple.com/documentation/systemextensions",
                    "https://support.apple.com/macos"
                ]
            )
        }
    }
    
    private func generateRecoveryOptions(for category: InstallationErrorCategory) -> [RecoveryOption] {
        switch category {
        case .systemExtensionRegistrationFailure:
            return [
                RecoveryOption(
                    title: "Reset and Retry",
                    description: "Reset System Extension state and attempt installation again",
                    recommendedFor: "Most registration failures",
                    riskLevel: .medium,
                    successRate: 0.8
                ),
                RecoveryOption(
                    title: "Enable Developer Mode",
                    description: "Enable System Extension Developer Mode for unsigned extensions",
                    recommendedFor: "Development or unsigned builds",
                    riskLevel: .medium,
                    successRate: 0.9
                ),
                RecoveryOption(
                    title: "Complete System Restart",
                    description: "Restart computer and attempt clean installation",
                    recommendedFor: "Persistent registration failures",
                    riskLevel: .low,
                    successRate: 0.7
                )
            ]
            
        case .systemExtensionApprovalRequired:
            return [
                RecoveryOption(
                    title: "Manual Approval",
                    description: "Manually approve the System Extension in Security preferences",
                    recommendedFor: "All approval-required scenarios",
                    riskLevel: .low,
                    successRate: 0.95
                ),
                RecoveryOption(
                    title: "Restart and Retry",
                    description: "Restart computer and retry installation to trigger new approval prompt",
                    recommendedFor: "When approval notification was missed",
                    riskLevel: .low,
                    successRate: 0.8
                )
            ]
            
        case .bundleIntegrityFailure:
            return [
                RecoveryOption(
                    title: "Clean Rebuild",
                    description: "Clean build directory and rebuild from scratch",
                    recommendedFor: "Most bundle integrity issues",
                    riskLevel: .low,
                    successRate: 0.9
                ),
                RecoveryOption(
                    title: "Fresh Repository Clone",
                    description: "Clone a fresh copy of the repository and build",
                    recommendedFor: "Persistent corruption issues",
                    riskLevel: .low,
                    successRate: 0.85
                )
            ]
            
        default:
            return [
                RecoveryOption(
                    title: "Standard Recovery",
                    description: "Follow the recommended remediation steps",
                    recommendedFor: "Most scenarios",
                    riskLevel: .low,
                    successRate: 0.75
                ),
                RecoveryOption(
                    title: "System Reset",
                    description: "Reset relevant system components and retry",
                    recommendedFor: "Persistent issues",
                    riskLevel: .medium,
                    successRate: 0.6
                )
            ]
        }
    }
    
    // MARK: - Helper Methods
    
    private func getEstimatedResolutionTime(for category: InstallationErrorCategory) -> String {
        switch category {
        case .systemExtensionApprovalRequired:
            return "1-2 minutes"
        case .bundleIntegrityFailure:
            return "3-5 minutes"
        case .insufficientSystemPermissions:
            return "2-3 minutes"
        case .developerModeRequired:
            return "5-10 minutes (includes restart)"
        case .systemExtensionRegistrationFailure:
            return "5-15 minutes"
        case .systemExtensionConflict:
            return "10-20 minutes"
        case .codeSigningFailure:
            return "5-30 minutes (depends on certificate availability)"
        case .ioKitIntegrationFailure:
            return "5-10 minutes"
        case .networkConfigurationError:
            return "2-5 minutes"
        case .systemIntegrityProtectionIssue:
            return "10-15 minutes (includes restart)"
        case .dependencyError:
            return "10-60 minutes (may require system updates)"
        case .environmentConfigurationError:
            return "5-10 minutes"
        case .unknownError:
            return "15-30 minutes (requires investigation)"
        }
    }
    
    private func requiresUserAction(for category: InstallationErrorCategory) -> Bool {
        switch category {
        case .systemExtensionApprovalRequired, .insufficientSystemPermissions:
            return true
        case .developerModeRequired, .systemIntegrityProtectionIssue:
            return true
        case .systemExtensionConflict:
            return true
        default:
            return false
        }
    }
    
    private func canRetryAutomatically(for category: InstallationErrorCategory) -> Bool {
        switch category {
        case .bundleIntegrityFailure, .networkConfigurationError:
            return true
        case .environmentConfigurationError, .dependencyError:
            return true
        default:
            return false
        }
    }
    
    private func getRelatedCommands(for category: InstallationErrorCategory) -> [String] {
        switch category {
        case .systemExtensionRegistrationFailure:
            return ["systemextensionsctl list", "systemextensionsctl reset", "log show --predicate 'subsystem CONTAINS \"systemextensions\"'"]
        case .systemExtensionApprovalRequired:
            return ["systemextensionsctl list", "spctl --status"]
        case .bundleIntegrityFailure:
            return ["swift package clean", "swift build", "ls -la .build/debug/"]
        case .insufficientSystemPermissions:
            return ["id", "groups", "tccutil reset All com.usbipd.mac"]
        case .developerModeRequired:
            return ["systemextensionsctl developer", "codesign -vv", "security find-identity -v -p codesigning"]
        default:
            return ["systemextensionsctl list", "log show --last 1h"]
        }
    }
    
    private func getHelpfulResources(for category: InstallationErrorCategory) -> [String] {
        switch category {
        case .systemExtensionRegistrationFailure, .systemExtensionApprovalRequired:
            return [
                "Apple's System Extensions documentation",
                "macOS Security and Privacy Guide",
                "USB/IP project documentation"
            ]
        case .insufficientSystemPermissions:
            return [
                "macOS Privacy and Security Guide",
                "Full Disk Access setup instructions"
            ]
        case .developerModeRequired, .codeSigningFailure:
            return [
                "Apple Developer Program documentation",
                "Code signing and notarization guide",
                "Xcode and command line tools setup"
            ]
        default:
            return [
                "USB/IP project documentation",
                "macOS troubleshooting guide"
            ]
        }
    }
    
    // MARK: - Report Generation
    
    private func generatePrioritizedRemediationPlan(from errors: [CategorizedInstallationError]) -> [PrioritizedRemediationItem] {
        var plan: [PrioritizedRemediationItem] = []
        
        // Group errors by category and severity
        let criticalErrors = errors.filter { $0.severity == .critical }
        let majorErrors = errors.filter { $0.severity == .major }
        let minorErrors = errors.filter { $0.severity == .minor }
        
        // Add critical errors first
        for (index, error) in criticalErrors.enumerated() {
            plan.append(PrioritizedRemediationItem(
                priority: index + 1,
                category: error.category,
                title: "Critical: \(error.category.displayName)",
                description: error.userFriendlyMessage,
                remediationSteps: error.remediationSteps,
                estimatedTime: error.estimatedResolutionTime,
                blocksOtherTasks: true
            ))
        }
        
        // Add major errors
        let majorStartIndex = criticalErrors.count
        for (index, error) in majorErrors.enumerated() {
            plan.append(PrioritizedRemediationItem(
                priority: majorStartIndex + index + 1,
                category: error.category,
                title: "Major: \(error.category.displayName)",
                description: error.userFriendlyMessage,
                remediationSteps: error.remediationSteps,
                estimatedTime: error.estimatedResolutionTime,
                blocksOtherTasks: false
            ))
        }
        
        // Add minor errors
        let minorStartIndex = criticalErrors.count + majorErrors.count
        for (index, error) in minorErrors.enumerated() {
            plan.append(PrioritizedRemediationItem(
                priority: minorStartIndex + index + 1,
                category: error.category,
                title: "Minor: \(error.category.displayName)",
                description: error.userFriendlyMessage,
                remediationSteps: error.remediationSteps,
                estimatedTime: error.estimatedResolutionTime,
                blocksOtherTasks: false
            ))
        }
        
        return plan
    }
    
    private func calculateTotalResolutionTime(from errors: [CategorizedInstallationError]) -> String {
        // Parse time estimates and calculate total
        var totalMinutes = 0
        
        for error in errors {
            let timeString = error.estimatedResolutionTime
            if let minutes = extractMinutesFromTimeString(timeString) {
                totalMinutes += minutes
            }
        }
        
        if totalMinutes < 60 {
            return "\(totalMinutes) minutes"
        } else {
            let hours = totalMinutes / 60
            let remainingMinutes = totalMinutes % 60
            return "\(hours) hour\(hours > 1 ? "s" : "")\(remainingMinutes > 0 ? " \(remainingMinutes) minutes" : "")"
        }
    }
    
    private func extractMinutesFromTimeString(_ timeString: String) -> Int? {
        // Simple parsing of time strings like "5-10 minutes", "1-2 hours"
        let numbers = timeString.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
        
        if timeString.contains("hour") {
            return numbers.first.map { $0 * 60 } ?? 60
        } else {
            return numbers.last ?? numbers.first ?? 5
        }
    }
    
    private func generateNextSteps(for status: InstallationStatus, errors: [CategorizedInstallationError]) -> [String] {
        switch status {
        case .successful:
            return ["Installation completed successfully. USB/IP is ready to use."]
            
        case .successfulWithWarnings:
            return [
                "Installation completed with warnings. USB/IP should function but may have reduced performance.",
                "Review and resolve warning conditions for optimal operation.",
                "Test USB device sharing functionality."
            ]
            
        case .partiallySuccessful:
            return [
                "Installation partially completed. Some components may not function correctly.",
                "Resolve major errors to ensure full functionality.",
                "Test basic functionality before sharing USB devices."
            ]
            
        case .failed:
            return [
                "Installation failed. USB/IP cannot function in its current state.",
                "Resolve all critical errors before attempting to use USB/IP.",
                "Follow the prioritized remediation plan to fix issues.",
                "Contact support if problems persist after following all remediation steps."
            ]
        }
    }
    
    private func generateTroubleshootingCommands(from errors: [CategorizedInstallationError]) -> [String] {
        let allCommands = errors.flatMap { $0.relatedCommands }
        return Array(Set(allCommands)) // Remove duplicates
    }
    
    private func shouldContactSupport(for errors: [CategorizedInstallationError]) -> Bool {
        return errors.contains { $0.category == .unknownError || $0.severity == .critical }
    }
}

// MARK: - Supporting Types

/// Installation error categories for user-friendly classification
public enum InstallationErrorCategory: String, CaseIterable {
    case systemExtensionRegistrationFailure = "system_extension_registration_failure"
    case systemExtensionApprovalRequired = "system_extension_approval_required"
    case systemExtensionConflict = "system_extension_conflict"
    case bundleIntegrityFailure = "bundle_integrity_failure"
    case insufficientSystemPermissions = "insufficient_system_permissions"
    case codeSigningFailure = "code_signing_failure"
    case developerModeRequired = "developer_mode_required"
    case ioKitIntegrationFailure = "iokit_integration_failure"
    case networkConfigurationError = "network_configuration_error"
    case systemIntegrityProtectionIssue = "system_integrity_protection_issue"
    case dependencyError = "dependency_error"
    case environmentConfigurationError = "environment_configuration_error"
    case unknownError = "unknown_error"
    
    public var displayName: String {
        switch self {
        case .systemExtensionRegistrationFailure:
            return "System Extension Registration Failure"
        case .systemExtensionApprovalRequired:
            return "System Extension Approval Required"
        case .systemExtensionConflict:
            return "System Extension Conflict"
        case .bundleIntegrityFailure:
            return "Bundle Integrity Failure"
        case .insufficientSystemPermissions:
            return "Insufficient System Permissions"
        case .codeSigningFailure:
            return "Code Signing Failure"
        case .developerModeRequired:
            return "Developer Mode Required"
        case .ioKitIntegrationFailure:
            return "IOKit Integration Failure"
        case .networkConfigurationError:
            return "Network Configuration Error"
        case .systemIntegrityProtectionIssue:
            return "System Integrity Protection Issue"
        case .dependencyError:
            return "Dependency Error"
        case .environmentConfigurationError:
            return "Environment Configuration Error"
        case .unknownError:
            return "Unknown Error"
        }
    }
}

/// Error severity levels for prioritization
public enum ErrorSeverity: String, CaseIterable {
    case critical = "critical"
    case major = "major"
    case minor = "minor"
    
    public var displayName: String {
        switch self {
        case .critical: return "Critical"
        case .major: return "Major"
        case .minor: return "Minor"
        }
    }
}

/// Risk level for remediation steps
public enum RiskLevel: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    public var displayName: String {
        switch self {
        case .low: return "Low Risk"
        case .medium: return "Medium Risk"
        case .high: return "High Risk"
        }
    }
}

/// Overall installation status
public enum InstallationStatus: String, CaseIterable {
    case successful = "successful"
    case successfulWithWarnings = "successful_with_warnings"
    case partiallySuccessful = "partially_successful"
    case failed = "failed"
    
    public var displayName: String {
        switch self {
        case .successful: return "Successful"
        case .successfulWithWarnings: return "Successful with Warnings"
        case .partiallySuccessful: return "Partially Successful"
        case .failed: return "Failed"
        }
    }
}

/// Categorized installation error with comprehensive remediation information
public struct CategorizedInstallationError {
    /// Original error that was categorized
    public let originalError: Error
    
    /// Category of the installation error
    public let category: InstallationErrorCategory
    
    /// Severity level of the error
    public let severity: ErrorSeverity
    
    /// User-friendly error message
    public let userFriendlyMessage: String
    
    /// Technical details for developers
    public let technicalDetails: String
    
    /// Step-by-step remediation instructions
    public let remediationSteps: [RemediationStep]
    
    /// Troubleshooting information
    public let troubleshootingInfo: TroubleshootingInfo
    
    /// Recovery options available
    public let recoveryOptions: [RecoveryOption]
    
    /// Estimated time to resolve this error
    public let estimatedResolutionTime: String
    
    /// Whether this error requires user action
    public let requiresUserAction: Bool
    
    /// Whether this error can be retried automatically
    public let canRetryAutomatically: Bool
    
    /// Related command line tools for troubleshooting
    public let relatedCommands: [String]
    
    /// Helpful resources and documentation
    public let helpfulResources: [String]
}

/// Individual remediation step with risk assessment
public struct RemediationStep {
    /// Step number in the remediation sequence
    public let stepNumber: Int
    
    /// Description of what this step does
    public let description: String
    
    /// Command to execute (nil if manual action required)
    public let command: String?
    
    /// Explanation of why this step is necessary
    public let explanation: String
    
    /// Risk level of performing this step
    public let riskLevel: RiskLevel
    
    /// Estimated time to complete this step
    public let estimatedTime: String
}

/// Troubleshooting information for error category
public struct TroubleshootingInfo {
    /// Common causes of this type of error
    public let commonCauses: [String]
    
    /// Diagnostic commands to gather more information
    public let diagnosticCommands: [String]
    
    /// Log file locations to check
    public let logLocations: [String]
    
    /// Related documentation and resources
    public let relatedDocumentation: [String]
}

/// Recovery option with success rate estimation
public struct RecoveryOption {
    /// Title of the recovery option
    public let title: String
    
    /// Description of what this option does
    public let description: String
    
    /// What scenarios this option is recommended for
    public let recommendedFor: String
    
    /// Risk level of this recovery option
    public let riskLevel: RiskLevel
    
    /// Estimated success rate (0.0 to 1.0)
    public let successRate: Double
}

/// Prioritized remediation item in overall plan
public struct PrioritizedRemediationItem {
    /// Priority order (1 = highest priority)
    public let priority: Int
    
    /// Error category being addressed
    public let category: InstallationErrorCategory
    
    /// Title of this remediation item
    public let title: String
    
    /// Description of the issue
    public let description: String
    
    /// Remediation steps to perform
    public let remediationSteps: [RemediationStep]
    
    /// Estimated time to complete
    public let estimatedTime: String
    
    /// Whether this blocks other tasks from proceeding
    public let blocksOtherTasks: Bool
}

/// Comprehensive installation error report
public struct InstallationErrorReport {
    /// Overall installation status
    public let overallStatus: InstallationStatus
    
    /// All categorized errors found
    public let categorizedErrors: [CategorizedInstallationError]
    
    /// Critical errors that prevent installation
    public let criticalErrors: [CategorizedInstallationError]
    
    /// Major errors that affect functionality
    public let majorErrors: [CategorizedInstallationError]
    
    /// Minor errors and warnings
    public let minorErrors: [CategorizedInstallationError]
    
    /// Prioritized plan for fixing all issues
    public let prioritizedRemediationPlan: [PrioritizedRemediationItem]
    
    /// Total estimated time to resolve all issues
    public let estimatedTotalResolutionTime: String
    
    /// Immediate next steps to take
    public let nextSteps: [String]
    
    /// Useful troubleshooting commands
    public let troubleshootingCommands: [String]
    
    /// Whether to contact support
    public let contactSupport: Bool
    
    /// Report generation timestamp
    public let timestamp: Date
}