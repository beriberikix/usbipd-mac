# Requirements Document

## Introduction

The System Extension Activation feature addresses a critical architectural gap in the usbipd-mac project where the comprehensive System Extension installation infrastructure exists but is never activated. Currently, the system operates in a "compatibility mode" using direct IOKit access from the main process, while the intended macOS System Extension integration remains dormant. This feature will enable automatic System Extension installation and activation to provide enhanced system-level USB device control, improved security isolation, and full macOS integration without requiring manual user intervention.

The feature bridges the gap between the existing fallback architecture (direct IOKit access) and the intended production architecture (System Extension-based device claiming) by automatically activating the sophisticated installation infrastructure already built into the codebase when first needed.

## Alignment with Product Vision

This feature directly supports the key product objectives outlined in product.md:

- **Developer Experience**: Provides seamless, automatic System Extension activation without manual setup steps
- **System Integration**: Enables "seamless integration with macOS security and permission models" through transparent System Extension deployment
- **Production Ready**: Moves from fallback compatibility mode to production-grade System Extension architecture automatically
- **Platform Parity**: Achieves full macOS System Extension integration without compromising ease of use

## Requirements

### Requirement 1: Automatic System Extension Installation on First Use

**User Story:** As a user running USB/IP operations, I want the System Extension to be automatically installed when first needed, so that I get enhanced functionality without manual setup steps.

#### Acceptance Criteria

1. WHEN the daemon starts for the first time THEN the system SHALL automatically check if System Extension is available and attempt installation if bundle exists
2. WHEN a user first runs `usbipd bind <device>` AND System Extension is not installed THEN the system SHALL automatically trigger System Extension installation
3. WHEN automatic installation is triggered THEN the system SHALL create a properly structured System Extension bundle with correct entitlements
4. IF the installation requires user approval THEN the system SHALL display a single, clear message about checking System Preferences and continue with fallback mode
5. WHEN installation completes successfully THEN the system SHALL seamlessly switch to System Extension mode without user intervention
6. IF automatic installation fails THEN the system SHALL log the failure and continue operating in fallback mode without breaking functionality

### Requirement 2: Transparent Bundle Creation During Build

**User Story:** As a developer building the project, I want the System Extension bundle to be automatically available for installation, so that the runtime system can perform automatic installation when needed.

#### Acceptance Criteria

1. WHEN `swift build` executes THEN the system SHALL automatically create the USBIPDSystemExtension.systemextension bundle in a well-known location
2. WHEN the bundle is created THEN the system SHALL copy the compiled SystemExtension executable to the bundle MacOS directory
3. WHEN bundle creation occurs THEN the system SHALL generate a proper Info.plist with CFBundlePackageType "SYSX" for System Extensions
4. WHEN the build completes THEN the system SHALL make bundle path and identifier available to ServerCoordinator during initialization
5. IF bundle creation fails THEN the system SHALL log the failure but continue building other components

### Requirement 3: Seamless Server Coordinator Integration

**User Story:** As the USB/IP daemon, I want to automatically detect and use System Extension capabilities when available, so that I can provide enhanced device claiming while maintaining transparent operation.

#### Acceptance Criteria  

1. WHEN ServerCoordinator initializes THEN the system SHALL automatically detect available System Extension bundle and configure installation infrastructure
2. WHEN System Extension infrastructure is enabled THEN the system SHALL create SystemExtensionInstaller and SystemExtensionLifecycleManager instances
3. WHEN the first device operation occurs AND System Extension is not installed THEN the system SHALL automatically attempt installation in the background
4. WHEN System Extension installation is in progress THEN the system SHALL continue device operations using fallback mode without blocking
5. WHEN System Extension installation completes THEN the system SHALL automatically begin using System Extension for subsequent operations

### Requirement 4: Intelligent Status Reporting

**User Story:** As a user checking system status, I want to understand whether System Extension is active and if any action is needed, so that I can ensure optimal functionality.

#### Acceptance Criteria

1. WHEN I run `usbipd status` AND System Extension is active THEN the system SHALL report "System Extension: Active" with enhanced functionality available
2. WHEN System Extension is not installed BUT bundle is available THEN the status SHALL indicate "System Extension: Available (will install automatically when needed)"
3. WHEN System Extension installation failed THEN the status SHALL report "System Extension: Installation failed - using compatibility mode" with link to troubleshooting
4. WHEN System Extension is pending user approval THEN the status SHALL show "System Extension: Pending approval in System Preferences" with specific instructions
5. WHEN no System Extension bundle exists THEN the status SHALL report "System Extension: Not available - using direct device access"

### Requirement 5: Graceful Development Mode Handling

**User Story:** As a developer working on the System Extension, I want the system to automatically handle development mode requirements, so that installation works seamlessly in development environments.

#### Acceptance Criteria

1. WHEN System Extension installation is attempted AND development mode is disabled THEN the system SHALL log a helpful message but continue with fallback mode
2. WHEN development certificates are available THEN the system SHALL automatically sign the bundle during installation
3. IF no development certificates exist AND development mode is enabled THEN the system SHALL proceed with unsigned installation
4. WHEN code signing fails THEN the system SHALL log the specific error but continue with unsigned installation if possible
5. WHEN installation succeeds in development mode THEN the system SHALL clearly indicate development mode in status reporting

### Requirement 6: Background Installation with Fallback Continuity

**User Story:** As a user performing USB operations, I want the system to work immediately while any System Extension installation happens transparently in the background, so that I don't experience delays or interruptions.

#### Acceptance Criteria

1. WHEN System Extension installation is triggered THEN the current operation SHALL continue using fallback mode without delay
2. WHEN installation is in progress THEN subsequent operations SHALL use fallback mode until installation completes
3. WHEN installation completes successfully THEN the system SHALL automatically switch to System Extension mode for new operations
4. IF installation takes longer than 30 seconds THEN the system SHALL continue permanently in fallback mode and retry installation on next daemon restart
5. WHEN installation requires user approval THEN the system SHALL show the approval message once and not repeatedly prompt

## Non-Functional Requirements

### Code Architecture and Modularity
- **Single Responsibility Principle**: Automatic installation logic isolated to existing SystemExtensionInstaller with minimal CLI changes
- **Modular Design**: Reuse existing SystemExtensionInstaller, SystemExtensionBundleCreator, and related infrastructure without modification
- **Dependency Management**: Extend ServerCoordinator initialization to provide bundle parameters without breaking existing functionality  
- **Clear Interfaces**: Maintain all existing API contracts while enabling automatic installation capabilities

### Performance
- **Installation Speed**: System Extension installation should not block current operations and complete within 30 seconds
- **Build Impact**: Bundle creation should add less than 5 seconds to total build time and be parallelizable
- **Runtime Overhead**: Zero performance impact on existing operations during installation process

### Security  
- **Code Signing**: Automatic certificate detection and signing when available, graceful fallback to unsigned development mode
- **Privilege Escalation**: Safe handling of System Extension installation without requiring manual administrator actions
- **Sandboxing**: Maintain System Extension security isolation while enabling automatic deployment

### Reliability
- **Graceful Fallback**: System must provide identical functionality whether System Extension installation succeeds or fails
- **Error Recovery**: Robust error handling with automatic fallback and clear logging for troubleshooting
- **State Management**: Seamless transition between fallback and System Extension modes without data loss

### Usability
- **Transparent Operation**: Users should not need to understand or interact with System Extension installation process
- **Immediate Functionality**: All operations work immediately regardless of System Extension installation status
- **Clear Status**: Status reporting provides helpful information without requiring action unless user approval is needed