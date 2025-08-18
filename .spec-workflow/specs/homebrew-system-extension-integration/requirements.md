# Requirements Document

## Introduction

This specification addresses a critical gap in the usbipd-mac Homebrew installation where the System Extension component is not properly built, packaged, or installed during the `brew install` process. Currently, users install usbipd-mac via Homebrew but the System Extension functionality is completely non-functional, requiring manual complex setup procedures that most users cannot complete successfully.

The feature will enhance the Homebrew formula to automatically build, package, and provide installation tooling for the macOS System Extension during the standard Homebrew installation workflow, enabling a complete out-of-the-box experience for USB/IP functionality.

## Alignment with Product Vision

This feature directly supports the product vision goals outlined in product.md by addressing critical user pain points:

- **Developer Productivity**: Eliminates the complex manual System Extension setup barrier that currently prevents most users from accessing core USB device sharing functionality
- **Platform Parity**: Brings macOS installation experience to parity with Linux distributions where USB/IP functionality works immediately after installation
- **Community Growth**: Removes the primary adoption barrier preventing developers from successfully using usbipd-mac
- **Enterprise Adoption**: Enables standardized deployment across development teams without requiring deep macOS System Extension expertise

## Requirements

### Requirement 1

**User Story:** As a developer installing usbipd-mac via Homebrew, I want the System Extension to be automatically built and made available during installation, so that I can access USB device sharing functionality without complex manual setup.

#### Acceptance Criteria

1. WHEN user runs `brew install usbipd-mac` THEN the formula SHALL build both the CLI executable and System Extension bundle during the installation process
2. WHEN the Homebrew build process completes THEN a properly structured `.systemextension` bundle SHALL exist in the installation directory with correct Info.plist and executable
3. WHEN user runs `brew install usbipd-mac` THEN the installation SHALL include a working `usbipd-install-extension` command that can install the System Extension
4. WHEN the System Extension bundle is created THEN it SHALL have proper macOS bundle structure with Contents/MacOS/ directory and CFBundlePackageType set to "SYSX"

### Requirement 2

**User Story:** As a user who has installed usbipd-mac via Homebrew, I want the System Extension to be automatically activated during Homebrew installation if developer mode is enabled, so that USB device claiming functionality works immediately without requiring additional manual steps.

#### Acceptance Criteria

1. WHEN user runs `brew install usbipd-mac` AND developer mode is enabled THEN the formula SHALL automatically attempt to install the System Extension using systemextensionsctl
2. WHEN automatic System Extension installation succeeds THEN `systemextensionsctl list` SHALL show the extension as "activated enabled" immediately after Homebrew installation completes
3. WHEN automatic System Extension installation fails THEN the installation SHALL provide the `usbipd-install-extension` fallback command with clear error messages and remediation steps
4. WHEN developer mode is not enabled THEN the installation SHALL provide clear instructions for enabling developer mode and manually installing the System Extension via `usbipd-install-extension`
5. WHEN user runs `usbipd status` after successful automatic installation THEN it SHALL report "System Extension: Available" instead of "Not Available"

### Requirement 3

**User Story:** As a user who needs to manually install the System Extension (when automatic installation fails or developer mode is not enabled), I want a simple command to install the System Extension, so that I can enable USB device claiming functionality without manually managing bundle creation or systemextensionsctl commands.

#### Acceptance Criteria

1. WHEN user runs `usbipd-install-extension` command THEN the system SHALL install the System Extension bundle using systemextensionsctl with proper error handling
2. IF developer mode is not enabled THEN the installation command SHALL provide clear instructions for enabling developer mode with `sudo systemextensionsctl developer on`
3. WHEN System Extension installation completes successfully THEN `systemextensionsctl list` SHALL show the extension as "activated enabled"
4. WHEN System Extension installation fails THEN the command SHALL provide specific error messages and remediation steps based on the failure type
5. WHEN user runs `usbipd status` after successful manual installation THEN it SHALL report "System Extension: Available" instead of "Not Available"

### Requirement 4

**User Story:** As a developer maintaining multiple macOS development machines, I want the Homebrew installation to work consistently across different macOS versions and architectures, so that I can standardize my development environment setup.

#### Acceptance Criteria

1. WHEN installing on Apple Silicon Macs THEN the System Extension bundle SHALL be built for arm64 architecture and function correctly
2. WHEN installing on Intel Macs THEN the System Extension bundle SHALL be built for x86_64 architecture and function correctly
3. WHEN installing on macOS 11.0 through current versions THEN the System Extension SHALL be compatible and installable on all supported macOS versions
4. WHEN System Extension bundle is created THEN it SHALL include proper LSMinimumSystemVersion setting of "11.0" for maximum compatibility

### Requirement 5

**User Story:** As a user following the Homebrew installation caveats, I want clear step-by-step instructions that lead to a working System Extension, so that I don't get stuck in complex troubleshooting scenarios.

#### Acceptance Criteria

1. WHEN user completes `brew install usbipd-mac` THEN the caveats message SHALL provide a clear numbered sequence of required post-installation steps differentiated by whether automatic installation succeeded or failed
2. WHEN user follows the caveats instructions THEN each step SHALL include the exact command to run and expected outcome
3. WHEN user encounters errors during System Extension installation THEN the caveats SHALL reference troubleshooting resources and common solutions
4. WHEN System Extension installation is complete THEN the caveats SHALL include verification commands to confirm successful setup

### Requirement 6

**User Story:** As a system administrator deploying usbipd-mac across development teams, I want the installation process to clearly indicate System Extension requirements and security implications, so that I can properly evaluate and authorize the deployment.

#### Acceptance Criteria

1. WHEN viewing Homebrew formula information THEN the dependencies SHALL clearly list System Extension requirements and administrator privileges needed
2. WHEN System Extension installation is attempted THEN the process SHALL require explicit sudo privileges and explain why administrator access is needed
3. WHEN System Extension is installed THEN the system SHALL properly integrate with macOS security framework and appear in System Preferences/Settings
4. WHEN uninstalling via Homebrew THEN the process SHALL provide instructions for properly removing the System Extension component

### Requirement 7

**User Story:** As a continuous integration system validating usbipd-mac functionality, I want GitHub Actions workflows to properly test System Extension bundle creation and validation, so that System Extension integration issues are caught before release.

#### Acceptance Criteria

1. WHEN GitHub Actions CI workflow runs THEN it SHALL build the System Extension bundle as part of the standard build process
2. WHEN System Extension bundle is built in CI THEN the workflow SHALL validate bundle structure, Info.plist correctness, and executable presence
3. WHEN Homebrew formula changes are made THEN CI SHALL test the formula installation process including System Extension bundle creation
4. WHEN CI tests System Extension functionality THEN it SHALL use appropriate mocking for System Extension APIs that require elevated privileges
5. WHEN CI builds complete successfully THEN they SHALL produce artifacts that include both CLI executables and System Extension bundles for testing

## Non-Functional Requirements

### Code Architecture and Modularity
- **Single Responsibility Principle**: System Extension bundle creation logic should be isolated from general Homebrew formula installation logic
- **Modular Design**: Bundle creation utilities should be reusable for development workflows beyond Homebrew installation
- **Dependency Management**: Minimize additional dependencies in Homebrew formula while leveraging existing Swift Package Manager build capabilities
- **Clear Interfaces**: Define clean separation between Swift package build system and Homebrew packaging requirements

### Performance
- **Build Time**: System Extension bundle creation should add no more than 30 seconds to total Homebrew installation time
- **Binary Size**: Combined CLI and System Extension installation should remain under 50MB total disk usage
- **Installation Speed**: Complete Homebrew installation including System Extension setup should complete within 5 minutes on typical development machines

### Security
- **Code Signing**: System Extension bundle must be prepared for code signing workflow (even if unsigned for development use)
- **Privilege Escalation**: Installation commands must clearly separate user-level and administrator-level operations
- **Bundle Validation**: System Extension bundle must pass macOS bundle validation and include proper entitlements structure
- **Secure Installation**: System Extension installation must follow macOS security best practices and integrate with existing security frameworks

### Reliability
- **Error Recovery**: Failed System Extension installations must not leave the system in an inconsistent state and must provide clear recovery instructions
- **Version Compatibility**: System Extension bundle must maintain compatibility across Swift toolchain updates and macOS version changes
- **Dependency Isolation**: Homebrew installation must work reliably regardless of user's existing Xcode or Swift development environment setup
- **CI Validation**: All System Extension functionality must be testable in CI environments with appropriate mocking and validation

### Usability
- **Clear Feedback**: Installation process must provide clear progress indicators and success/failure feedback at each step
- **Self-Documenting**: Commands and processes should be self-documenting with help text and examples readily available
- **Troubleshooting Support**: Common failure scenarios must have documented troubleshooting steps and error message guidance
- **Automatic vs Manual**: Installation process must gracefully handle both automatic installation scenarios (when possible) and manual fallback scenarios