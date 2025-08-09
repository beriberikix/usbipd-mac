# Requirements Document

## Introduction

The usbipd-mac project currently implements System Extension functionality as a Swift library target, but lacks the proper System Extension bundle creation and macOS registration needed for actual deployment. This specification addresses the critical gap between having System Extension **code** (which exists) and having a proper System Extension **bundle** that macOS can install, activate, and manage.

The feature enables:
- Proper macOS System Extension bundle (.systemextension) creation from existing Swift code
- System Extension installation, activation, and lifecycle management
- Integration with macOS security model (entitlements, code signing, user approval)
- Reliable USB device claiming through the macOS System Extension framework

## Alignment with Product Vision

This feature directly supports the **System Integration** product principle by ensuring usbipd-mac "works seamlessly with macOS security and permission models." It addresses the core technical requirement for privileged USB device access on macOS through the proper System Extension deployment mechanism.

## Requirements

### Requirement 1: System Extension Bundle Creation

**User Story:** As a developer building usbipd-mac, I want the build system to automatically generate a proper System Extension bundle, so that the System Extension can be installed and activated by macOS.

#### Acceptance Criteria

1. WHEN `swift build` is executed THEN the build system SHALL generate a complete `.systemextension` bundle in the output directory
2. WHEN the bundle is created THEN it SHALL include the SystemExtensionManager executable as the principal class
3. WHEN the bundle is created THEN it SHALL include a properly configured Info.plist with all required System Extension metadata
4. WHEN the bundle is created THEN it SHALL include the SystemExtension.entitlements file with proper entitlements for USB device access
5. IF the build environment has code signing configured THEN the bundle SHALL be properly code-signed for distribution

### Requirement 2: System Extension Installation

**User Story:** As a system administrator, I want to install the System Extension through standard macOS mechanisms, so that USB device claiming works reliably.

#### Acceptance Criteria

1. WHEN the daemon first needs System Extension functionality THEN it SHALL automatically trigger System Extension installation using OSSystemExtensionRequest
2. WHEN System Extension installation is triggered THEN macOS SHALL display the standard System Extension approval dialog
3. WHEN the user approves the System Extension THEN it SHALL be activated and available for device claiming
4. IF System Extension installation fails THEN the daemon SHALL provide clear error messages with troubleshooting guidance
5. WHEN System Extension is successfully installed THEN `systemextensionsctl list` SHALL show it as "activated enabled"

### Requirement 3: System Extension Lifecycle Management

**User Story:** As a user of usbipd-mac, I want the System Extension to start automatically when needed and shut down cleanly, so that my system remains stable.

#### Acceptance Criteria

1. WHEN the usbipd daemon starts THEN it SHALL automatically activate the System Extension if not already running
2. WHEN device claiming is requested THEN the daemon SHALL verify System Extension is active before proceeding
3. WHEN the daemon shuts down THEN it SHALL properly deactivate the System Extension and release claimed devices
4. IF the System Extension crashes THEN it SHALL be automatically restarted and device claims restored
5. WHEN System Extension updates are available THEN the installation process SHALL handle version transitions gracefully

### Requirement 4: USB Device Access Integration

**User Story:** As a developer using usbipd-mac, I want USB devices to be reliably claimed through the System Extension, so that I can share USB devices over IP networks.

#### Acceptance Criteria

1. WHEN `usbipd bind <device>` is executed THEN the System Extension SHALL successfully claim exclusive access to the USB device
2. WHEN a device is claimed THEN other applications SHALL be unable to access the device until it is released
3. WHEN `usbipd unbind <device>` is executed THEN the System Extension SHALL release the device back to the system
4. IF device claiming fails due to permission issues THEN the error message SHALL guide the user to check System Extension status
5. WHEN the System Extension has claimed devices THEN `usbipd status` SHALL accurately report the claimed device list

### Requirement 5: Development and Distribution Support

**User Story:** As a contributor to usbipd-mac, I want development builds to work with System Extension functionality, so that I can test and develop new features.

#### Acceptance Criteria

1. WHEN building in development mode THEN the System Extension bundle SHALL be created with development signatures
2. WHEN `systemextensionsctl developer on` is enabled THEN development System Extensions SHALL install without full code signing requirements
3. WHEN running integration tests THEN the test suite SHALL properly install and activate the System Extension for testing
4. IF the System Extension needs to be rebuilt THEN the build system SHALL properly replace the existing bundle
5. WHEN preparing for distribution THEN the System Extension SHALL be notarized through Apple's notary service

## Non-Functional Requirements

### Code Architecture and Modularity
- **Bundle Structure**: System Extension bundle must follow Apple's prescribed structure with proper Info.plist, entitlements, and executable organization
- **Build Integration**: Swift Package Manager build process must seamlessly generate System Extension bundles alongside existing targets
- **Error Isolation**: System Extension failures must not crash the main daemon process
- **State Management**: System Extension activation state must be properly tracked and recoverable across restarts

### Performance
- **Installation Time**: System Extension installation must complete within 30 seconds under normal conditions
- **Activation Latency**: System Extension activation must complete within 10 seconds of daemon startup
- **Device Claiming**: USB device claiming through System Extension must complete within 5 seconds per device
- **Memory Footprint**: System Extension process must use less than 50MB of resident memory under normal operation

### Security
- **Entitlements**: System Extension must use minimal required entitlements following principle of least privilege
- **Sandboxing**: System Extension must operate within macOS sandbox restrictions while maintaining required USB device access
- **Code Signing**: Production builds must be properly code-signed with valid Developer ID certificates
- **Permission Model**: System Extension must integrate with macOS permission model requiring explicit user approval

### Reliability
- **Crash Recovery**: System Extension crashes must not require daemon restart or lose device claim state
- **Update Resilience**: System Extension updates must preserve existing device claims and configuration
- **Resource Cleanup**: System Extension deactivation must properly release all claimed USB devices
- **Error Reporting**: System Extension failures must provide detailed logging for troubleshooting

### Usability
- **User Feedback**: System Extension installation must provide clear progress indication and success/failure status
- **Error Messages**: System Extension failures must include actionable troubleshooting steps
- **Status Visibility**: Users must be able to easily check System Extension status through `usbipd status` command
- **Documentation**: System Extension setup must be documented with step-by-step installation and troubleshooting guides