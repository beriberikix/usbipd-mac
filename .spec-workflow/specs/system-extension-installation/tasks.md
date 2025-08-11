# Implementation Plan

## Task Overview

This implementation plan converts the System Extension installation design into atomic, executable tasks organized in logical sections. The implementation follows proper git workflow practices with feature branching, regular commits, and CI validation. Rather than extending the CLI (to maintain Linux compatibility), the solution uses shell scripts for development workflows while focusing on robust core infrastructure.

Each task is designed to be completable in 15-30 minutes, focuses on specific files, and includes proper git commits. The implementation systematically replaces the broken plugin system with a comprehensive post-build solution.

## Tasks

### Section 1: Project Setup and Foundation

- [x] 1.1 Create feature branch and commit specifications
  - Create feature branch: `git checkout -b feature/system-extension-installation`
  - Commit the approved specification documents to the feature branch
  - Initialize the implementation tracking and documentation
  - Purpose: Establish proper git workflow and track specification approval
  - Git commit: "feat: add System Extension installation specification"
  - _Requirements: All_

- [-] 1.2 Remove broken plugin system
  - Remove Plugins/SystemExtensionBundleBuilder directory completely
  - Remove plugin references from Package.swift
  - Clean up any plugin-related build artifacts and configurations
  - Purpose: Remove non-functional plugin system that creates broken bundles
  - Git commit: "fix: remove broken SystemExtensionBundleBuilder plugin"
  - _Requirements: 1.1, 2.2_

- [ ] 1.3 Create SystemExtension core directory structure
  - Create Sources/USBIPDCore/SystemExtension/BundleCreation/ directory
  - Create Sources/USBIPDCore/SystemExtension/CodeSigning/ directory
  - Create Sources/USBIPDCore/SystemExtension/Installation/ directory
  - Purpose: Establish organized structure for new System Extension functionality
  - Git commit: "feat: create System Extension implementation directory structure"
  - _Requirements: 1.1, 2.1_

### Section 2: Data Models and Core Types

- [ ] 2.1 Extend SystemExtensionModels with bundle types
  - File: Sources/USBIPDCore/SystemExtension/SystemExtensionModels.swift (modify existing)
  - Add SystemExtensionBundle and BundleContents data structures
  - Add CodeSigningCertificate and CertificateType enums
  - Purpose: Establish type safety for bundle creation and management
  - Git commit: "feat: add System Extension bundle and certificate data models"
  - _Leverage: Sources/Common/USBDeviceTypes.swift_
  - _Requirements: 1.1, 1.2, 4.1_

- [ ] 2.2 Add installation and status models
  - File: Sources/USBIPDCore/SystemExtension/SystemExtensionModels.swift (continue)
  - Add InstallationResult, SystemExtensionStatus, and HealthStatus types
  - Extend existing SystemExtensionStatus with health and validation properties
  - Add InstallationError and diagnostic result types
  - Purpose: Complete data model foundation for installation workflows
  - Git commit: "feat: add System Extension installation and status models"
  - _Requirements: 3.1, 5.1_

### Section 3: Bundle Creation Infrastructure

- [ ] 3.1 Create SystemExtensionBundleCreator foundation
  - File: Sources/USBIPDCore/SystemExtension/BundleCreation/SystemExtensionBundleCreator.swift
  - Create class structure with bundle creation interface
  - Add bundle directory structure creation logic
  - Implement Info.plist template processing foundation
  - Purpose: Foundation for proper bundle creation replacing broken plugin
  - Git commit: "feat: create SystemExtensionBundleCreator foundation"
  - _Leverage: Sources/Common/Logger.swift, Sources/Common/Errors.swift_
  - _Requirements: 1.1, 1.2_

- [ ] 3.2 Implement executable integration and bundle completion
  - File: Sources/USBIPDCore/SystemExtension/BundleCreation/SystemExtensionBundleCreator.swift (continue)
  - Add logic to copy compiled executable into bundle MacOS directory
  - Implement entitlements and resource file copying
  - Add comprehensive bundle structure validation
  - Purpose: Complete functional bundle creation with proper executable integration
  - Git commit: "feat: implement executable integration in bundle creation"
  - _Requirements: 1.1, 1.3_

- [ ] 3.3 Add bundle creation error handling and validation
  - File: Sources/USBIPDCore/SystemExtension/BundleCreation/SystemExtensionBundleCreator.swift (continue)
  - Implement comprehensive error handling for bundle creation failures
  - Add bundle structure validation and integrity checking
  - Create detailed error reporting with specific remediation steps
  - Purpose: Robust error handling for bundle creation process
  - Git commit: "feat: add comprehensive bundle creation error handling"
  - _Requirements: 1.2, 1.3_

### Section 4: Code Signing System

- [ ] 4.1 Create CodeSigningManager certificate detection
  - File: Sources/USBIPDCore/SystemExtension/CodeSigning/CodeSigningManager.swift
  - Implement Security framework integration for certificate detection
  - Add certificate enumeration and validation logic
  - Create certificate type classification and expiration checking
  - Purpose: Automated certificate detection for development workflows
  - Git commit: "feat: implement certificate detection in CodeSigningManager"
  - _Leverage: Sources/Common/Logger.swift_
  - _Requirements: 2.1, 2.2, 4.1_

- [ ] 4.2 Implement code signing workflows
  - File: Sources/USBIPDCore/SystemExtension/CodeSigning/CodeSigningManager.swift (continue)
  - Add codesign command generation and execution
  - Implement bundle and executable signing methods
  - Create signature verification and validation logic
  - Purpose: Complete automated signing workflows for all certificate types
  - Git commit: "feat: implement code signing and verification workflows"
  - _Requirements: 1.2, 4.2, 4.3_

- [ ] 4.3 Add development mode and unsigned bundle support
  - File: Sources/USBIPDCore/SystemExtension/CodeSigning/CodeSigningManager.swift (continue)
  - Implement fallback logic for unsigned development bundles
  - Add development mode detection and guidance
  - Create signing status reporting and diagnostics
  - Purpose: Support unsigned development workflows when certificates unavailable
  - Git commit: "feat: add development mode and unsigned bundle support"
  - _Requirements: 2.3, 4.4_

### Section 5: Installation System

- [ ] 5.1 Create SystemExtensionInstaller foundation
  - File: Sources/USBIPDCore/SystemExtension/Installation/SystemExtensionInstaller.swift
  - Create installer class with systemextensionsctl integration
  - Implement installation status detection and monitoring
  - Add basic installation workflow structure
  - Purpose: Foundation for automated System Extension installation
  - Git commit: "feat: create SystemExtensionInstaller foundation"
  - _Leverage: Sources/USBIPDCore/SystemExtension/SystemExtensionManager.swift_
  - _Requirements: 3.1, 3.2_

- [ ] 5.2 Implement installation workflows and status monitoring
  - File: Sources/USBIPDCore/SystemExtension/Installation/SystemExtensionInstaller.swift (continue)
  - Add automated installation with user approval handling
  - Implement installation verification and health checking
  - Create installation retry logic and error recovery
  - Purpose: Complete automated installation with proper error handling
  - Git commit: "feat: implement installation workflows and monitoring"
  - _Requirements: 3.1, 3.3, 3.4_

- [ ] 5.3 Add developer mode management
  - File: Sources/USBIPDCore/SystemExtension/Installation/SystemExtensionInstaller.swift (continue)
  - Implement developer mode detection and enablement
  - Add developer mode guidance and validation
  - Create development environment setup assistance
  - Purpose: Automated developer mode management for development workflows
  - Git commit: "feat: add developer mode management and guidance"
  - _Requirements: 2.3, 2.4_

### Section 6: Environment and Diagnostics

- [ ] 6.1 Create EnvironmentSetupManager
  - File: Sources/USBIPDCore/SystemExtension/Installation/EnvironmentSetupManager.swift
  - Implement development environment validation
  - Add SIP status checking and Xcode Command Line Tools detection
  - Create environment setup guidance and automation
  - Purpose: Streamlined first-time developer setup experience
  - Git commit: "feat: create EnvironmentSetupManager for development setup"
  - _Leverage: Sources/Common/Logger.swift_
  - _Requirements: 2.1, 2.2, 2.3_

- [ ] 6.2 Create SystemExtensionDiagnostics foundation
  - File: Sources/USBIPDCore/SystemExtension/Installation/SystemExtensionDiagnostics.swift
  - Create diagnostic framework with health checking
  - Implement bundle validation and integrity checking
  - Add system log parsing foundation for extension issues
  - Purpose: Comprehensive troubleshooting and validation capabilities foundation
  - Git commit: "feat: create SystemExtensionDiagnostics foundation"
  - _Requirements: 5.1, 5.2_

- [ ] 6.3 Implement comprehensive diagnostic reporting
  - File: Sources/USBIPDCore/SystemExtension/Installation/SystemExtensionDiagnostics.swift (continue)
  - Add detailed diagnostic reporting with specific remediation steps
  - Implement system extension conflict detection
  - Create diagnostic report formatting and output
  - Purpose: Complete diagnostic system with actionable troubleshooting
  - Git commit: "feat: implement comprehensive diagnostic reporting"
  - _Leverage: Sources/USBIPDCore/Device/IOKitDeviceDiscovery.swift, Sources/Common/Logger.swift_
  - _Requirements: 5.3, 5.4_

### Section 7: Shell Scripts (Linux CLI Compatibility)

- [ ] 7.1 Create setup-dev-environment.sh script
  - File: Scripts/setup-dev-environment.sh
  - Create shell script for automated development environment setup
  - Add interactive guidance for certificate installation and developer mode
  - Integrate with EnvironmentSetupManager through CLI calls
  - Purpose: Linux-compatible development environment setup script
  - Git commit: "feat: add setup-dev-environment.sh for development setup"
  - _Leverage: Scripts/ directory patterns, existing CLI integration_
  - _Requirements: 2.1, 2.2, 2.4_

- [ ] 7.2 Create install-extension.sh script
  - File: Scripts/install-extension.sh
  - Create shell script for automated System Extension installation
  - Add support for force reinstallation and bundle path specification
  - Integrate bundle creation, signing, and installation in single workflow
  - Purpose: Complete automated installation workflow script
  - Git commit: "feat: add install-extension.sh for automated installation"
  - _Requirements: 1.3, 3.1, 3.2_

- [ ] 7.3 Create system extension status and validation scripts
  - File: Scripts/extension-status.sh
  - File: Scripts/validate-bundle.sh
  - Create status reporting script with comprehensive System Extension information
  - Create bundle validation script with detailed reporting
  - Add formatted output and diagnostic information display
  - Purpose: Status and validation tools compatible with Linux workflow
  - Git commit: "feat: add extension status and bundle validation scripts"
  - _Requirements: 5.1, 5.2, 5.3_

### Section 8: Build Integration

- [ ] 8.1 Create post-build integration script
  - File: Scripts/post-build-extension.sh
  - Create bash script for post-build System Extension bundle creation
  - Integrate with Swift build system using build phases
  - Add proper error handling and logging for build integration
  - Purpose: Seamless integration with existing build workflow
  - Git commit: "feat: add post-build extension bundle creation script"
  - _Leverage: Scripts/ directory patterns, existing build scripts_
  - _Requirements: 1.1, 1.5_

- [ ] 8.2 Update Package.swift configuration
  - File: Package.swift (modify existing)
  - Clean up remaining plugin references
  - Update SystemExtension target dependencies and resources
  - Add proper linker settings and framework dependencies for new functionality
  - Purpose: Clean Package.swift and support new System Extension functionality
  - Git commit: "feat: update Package.swift for new System Extension system"
  - _Leverage: existing Package.swift structure and patterns_
  - _Requirements: 1.1, 2.2_

### Section 9: Testing Infrastructure

- [ ] 9.1 Create SystemExtensionBundleCreator unit tests
  - File: Tests/USBIPDCoreTests/SystemExtension/SystemExtensionBundleCreatorTests.swift
  - Write tests for bundle creation and template processing
  - Mock file system operations and verify bundle structure creation
  - Test error handling for missing executables and template failures
  - Purpose: Ensure reliable bundle creation functionality
  - Git commit: "test: add SystemExtensionBundleCreator unit tests"
  - _Leverage: existing test patterns and XCTest framework_
  - _Requirements: 1.1, 1.2_

- [ ] 9.2 Create CodeSigningManager unit tests
  - File: Tests/USBIPDCoreTests/SystemExtension/CodeSigningManagerTests.swift
  - Write tests for certificate detection and signing workflows
  - Mock Security framework calls and codesign subprocess execution
  - Test fallback logic for missing certificates and development mode
  - Purpose: Ensure reliable code signing functionality across environments
  - Git commit: "test: add CodeSigningManager unit tests"
  - _Requirements: 2.1, 4.1, 4.2_

- [ ] 9.3 Create installation and diagnostic tests
  - File: Tests/USBIPDCoreTests/SystemExtension/SystemExtensionInstallerTests.swift
  - File: Tests/USBIPDCoreTests/SystemExtension/SystemExtensionDiagnosticsTests.swift
  - Write tests for installation workflow and status monitoring
  - Test diagnostic functionality and error reporting
  - Add test coverage for installation failure scenarios and recovery
  - Purpose: Ensure robust installation and diagnostic functionality
  - Git commit: "test: add installation and diagnostic unit tests"
  - _Requirements: 3.1, 3.3, 5.1_

### Section 10: Integration Testing

- [ ] 10.1 Create complete installation workflow integration test
  - File: Tests/IntegrationTests/SystemExtensionInstallationWorkflowTests.swift
  - Write end-to-end test covering build, sign, install, and verify workflow
  - Test both signed and unsigned development scenarios
  - Add cleanup and test environment isolation
  - Purpose: Ensure complete workflow functions in realistic scenarios
  - Git commit: "test: add end-to-end installation workflow integration tests"
  - _Leverage: existing integration test infrastructure_
  - _Requirements: 3.4, 6.1_

- [ ] 10.2 Run SwiftLint and fix any violations
  - Run `swiftlint lint --strict` to identify code style issues
  - Fix all SwiftLint violations in new code
  - Ensure consistent code style with existing codebase
  - Purpose: Maintain code quality and consistency standards
  - Git commit: "fix: resolve SwiftLint violations in System Extension code"
  - _Requirements: All (code quality)_

### Section 11: Documentation and CI

- [ ] 11.1 Update SYSTEM_EXTENSION_SETUP.md documentation
  - File: Sources/SystemExtension/SYSTEM_EXTENSION_SETUP.md (modify existing)
  - Replace outdated plugin-based instructions with new workflow documentation
  - Add comprehensive setup instructions for new shell scripts
  - Update troubleshooting sections with new diagnostic capabilities
  - Purpose: Accurate documentation for new installation system
  - Git commit: "docs: update System Extension setup documentation for new system"
  - _Leverage: existing documentation structure and style_
  - _Requirements: All requirements (documentation support)_

- [ ] 11.2 Run full CI validation and fix issues
  - Run complete CI validation sequence locally: `swift build --verbose && swift test --parallel --verbose && swiftlint lint --strict`
  - Fix any build errors, test failures, or linting issues
  - Ensure all tests pass and code builds successfully
  - Purpose: Ensure CI compatibility and fix any integration issues
  - Git commit: "fix: resolve CI issues and ensure full test suite passes"
  - _Requirements: All_

- [ ] 11.3 Create pull request with CI validation
  - Create pull request from feature branch to main
  - Ensure CI pipeline completes successfully without errors
  - Address any CI failures by fixing code and recommitting
  - Continue fixing until CI is completely green
  - Purpose: Complete feature integration with full CI validation
  - Git commit: N/A (PR creation)
  - _Requirements: All_