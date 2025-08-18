# Requirements Document

## Introduction

The System Extension installation functionality in usbipd-mac is currently broken in production Homebrew installations, preventing users from accessing USB devices through the System Extension. Through comprehensive analysis of the issue, four critical problems have been identified:

1. **Bundle Detection Failure**: The `SystemExtensionBundleDetector` only searches for bundles in `.build/` directories (development environment) but fails to locate bundles in Homebrew installation paths like `/opt/homebrew/Cellar/usbipd-mac/*/Library/SystemExtensions/`
2. **Missing System Extension Submission**: The installation process never actually calls `OSSystemExtensionManager.shared.submitRequest()` to register the System Extension with macOS, preventing security approval dialogs from appearing
3. **Service Management Disconnect**: The launchd service runs but isn't properly managed by `brew services`, leading to orphaned processes and unreliable startup
4. **No Installation Verification**: The system claims success without verifying that the System Extension was actually approved and registered with macOS

This feature will implement a complete fix for System Extension installation and management, ensuring reliable USB device access in production environments.

## Alignment with Product Vision

This feature directly supports the product vision of providing seamless developer productivity by eliminating friction in USB device access workflows. The broken System Extension installation is a critical barrier preventing Docker integration and VM USB passthrough scenarios, which are core use cases for the target user base of developers and hardware engineers.

## Requirements

### Requirement 1: Production Bundle Detection

**User Story:** As a user who installed usbipd-mac via Homebrew, I want the system to automatically detect the System Extension bundle in my Homebrew installation, so that I can use USB device claiming functionality without manual configuration.

#### Acceptance Criteria

1. WHEN usbipd starts in a Homebrew installation environment THEN the system SHALL successfully locate the System Extension bundle at `/opt/homebrew/Cellar/usbipd-mac/*/Library/SystemExtensions/usbipd-mac.systemextension`
2. WHEN the bundle detector searches for bundles THEN it SHALL check both development paths (`.build/` directories) AND production paths (Homebrew installation directories)
3. WHEN a bundle is found in a Homebrew installation THEN the system SHALL validate the bundle structure and load the bundle identifier `com.github.usbipd-mac.systemextension`
4. WHEN no bundle is found in any search path THEN the system SHALL provide clear error messages indicating which paths were searched and suggest installation troubleshooting steps

### Requirement 2: System Extension Registration and Approval

**User Story:** As a user installing the System Extension for the first time, I want macOS to prompt me for security approval so that the System Extension can be properly registered and functional.

#### Acceptance Criteria

1. WHEN a valid System Extension bundle is detected THEN the system SHALL call `OSSystemExtensionManager.shared.submitRequest()` with an activation request for the bundle
2. WHEN the activation request is submitted THEN macOS SHALL display a security dialog asking the user to approve the System Extension
3. WHEN the user approves the System Extension THEN it SHALL appear in `systemextensionsctl list` as an active, enabled extension
4. WHEN the System Extension requires user approval THEN the system SHALL provide clear instructions to check System Preferences > Security & Privacy > General
5. WHEN System Extension installation fails THEN the system SHALL capture and report the specific `OSSystemExtensionError` codes and provide actionable troubleshooting guidance

### Requirement 3: Service Management Integration

**User Story:** As a system administrator managing usbipd-mac services, I want proper launchd integration so that the service can be reliably started, stopped, and monitored through standard macOS service management tools.

#### Acceptance Criteria

1. WHEN `brew services start usbipd-mac` is executed THEN the service SHALL start properly and be reported as "Running" by `brew services list`
2. WHEN the usbipd daemon starts THEN it SHALL register with launchd using the correct service label and maintain proper process lifecycle management
3. WHEN System Extension submission is triggered THEN the daemon SHALL coordinate with the launchd service to ensure proper privilege elevation and service state management
4. WHEN the service stops THEN all System Extension claims SHALL be properly released and the System Extension SHALL remain available for future use
5. WHEN service startup fails THEN clear error messages SHALL be logged to `/opt/homebrew/var/log/usbipd.error.log` with specific failure reasons

### Requirement 4: Installation Verification and Status Reporting

**User Story:** As a user running installation commands, I want accurate feedback about System Extension installation status so that I can confirm the installation succeeded before attempting to use USB device features.

#### Acceptance Criteria

1. WHEN `usbipd-install-extension status` is executed THEN it SHALL report accurate installation status by checking `systemextensionsctl list` output
2. WHEN System Extension installation completes THEN the system SHALL verify the extension appears as "enabled" and "active" in macOS system extension registry
3. WHEN installation verification fails THEN the system SHALL distinguish between "not installed", "pending approval", "installed but not active", and "installation failed" states
4. WHEN `usbipd status` is executed THEN it SHALL report System Extension availability and provide specific guidance for detected issues
5. WHEN the System Extension is properly installed and active THEN USB device binding operations SHALL succeed without fallback to alternative claiming methods

### Requirement 5: Error Recovery and Diagnostics

**User Story:** As a user encountering System Extension installation issues, I want comprehensive diagnostic information and recovery options so that I can resolve problems independently or provide useful information for support.

#### Acceptance Criteria

1. WHEN System Extension installation fails THEN the system SHALL provide detailed error information including OSSystemExtensionError codes, system logs excerpts, and recommended recovery steps
2. WHEN bundle detection fails THEN the system SHALL report all searched paths, permission issues, and file system validation results
3. WHEN installation gets stuck in "pending approval" state THEN the system SHALL detect this condition and provide specific instructions for manual approval in System Preferences
4. WHEN developer mode is required but not enabled THEN the system SHALL detect this condition and provide instructions for enabling `systemextensionsctl developer on`
5. WHEN System Extension conflicts exist THEN the system SHALL detect duplicate or conflicting extensions and provide guidance for resolution

## Non-Functional Requirements

### Code Architecture and Modularity

- **Single Responsibility Principle**: Bundle detection, System Extension submission, service management, and verification SHALL be implemented as separate, focused components
- **Modular Design**: Components SHALL be designed for independent testing and reusability across different installation scenarios (development, Homebrew, manual)
- **Dependency Management**: Minimize interdependencies between detection, installation, and verification modules
- **Clear Interfaces**: Define clean contracts between bundle detection, installation orchestration, and status verification layers

### Performance

- Bundle detection SHALL complete within 2 seconds on typical macOS systems
- System Extension submission SHALL not block the main application thread
- Service startup verification SHALL complete within 5 seconds
- Installation status checks SHALL complete within 1 second

### Security

- All System Extension operations SHALL follow macOS security best practices and sandbox requirements
- Installation processes SHALL properly handle privilege escalation and user consent flows
- Bundle validation SHALL verify code signatures and bundle integrity before submission
- No credential or sensitive information SHALL be logged or exposed during installation processes

### Reliability

- Installation processes SHALL be idempotent - multiple installation attempts SHALL not cause system corruption
- Service management SHALL handle unexpected termination gracefully and support automatic restart
- System Extension claiming SHALL include proper cleanup and release mechanisms
- All installation operations SHALL support rollback and recovery from partial failure states

### Usability

- Installation status reporting SHALL use clear, non-technical language appropriate for developers and system administrators
- Error messages SHALL include specific actions users can take to resolve issues
- Progress indication SHALL be provided for long-running installation operations
- Help and diagnostic commands SHALL be easily discoverable and well-documented