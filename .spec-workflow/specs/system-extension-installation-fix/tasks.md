# Implementation Plan

## Task Overview

The implementation follows a phased approach to fix the four critical System Extension installation issues: bundle detection, System Extension registration, service management, and installation verification. Each task is designed to be atomic and build incrementally on previous work, ensuring the system remains functional throughout the implementation.

The implementation leverages existing components like `SystemExtensionBundleDetector`, `SystemExtensionInstaller`, and service management patterns while adding the missing production environment support and actual macOS System Extension registration.

## Tasks

- [-] 0. Setup git workflow and commit specs
  - Create feature branch and commit specification documents
  - Set up proper git workflow for the implementation
  - _Requirements: All_

- [ ] 0.1 Create feature branch and commit specs
  - Create new git branch `feature/system-extension-installation-fix` from main
  - Add and commit all spec documents (.spec-workflow/specs/system-extension-installation-fix/)
  - Git commit message: "feat: Add System Extension installation fix specification\n\nAdd comprehensive spec for fixing critical System Extension installation\nissues in Homebrew production environments:\n- Bundle detection for production paths\n- Actual System Extension registration with macOS\n- Service management integration\n- Installation verification and diagnostics"
  - Purpose: Set up proper git workflow and preserve specification work
  - _Leverage: Existing git repository structure_
  - _Requirements: All_

- [ ] 1. Enhance bundle detection for production environments
  - Extend existing SystemExtensionBundleDetector to support Homebrew installation paths
  - Add multi-environment detection capabilities (development + production)
  - _Requirements: 1.1, 1.2, 1.3_

- [ ] 1.1 Add Homebrew path detection to SystemExtensionBundleDetector.swift
  - File: Sources/USBIPDCore/SystemExtension/BundleDetection/SystemExtensionBundleDetector.swift (modify existing)
  - Add `getHomebrewSearchPaths()` method to detect `/opt/homebrew/Cellar/usbipd-mac/*/Library/SystemExtensions/`
  - Add `detectProductionBundle()` method for Homebrew-specific validation
  - Extend `detectBundle()` method to search both development and production paths
  - Git commit message: "feat: Add Homebrew bundle detection to SystemExtensionBundleDetector\n\nExtend bundle detection to support production Homebrew installations:\n- Add getHomebrewSearchPaths() for /opt/homebrew/Cellar paths\n- Add detectProductionBundle() for Homebrew validation\n- Extend detectBundle() for multi-environment search"
  - Purpose: Enable bundle detection in Homebrew production environments
  - _Leverage: Existing bundle validation logic, FileManager patterns_
  - _Requirements: 1.1, 1.2_

- [ ] 1.2 Add production bundle metadata handling
  - File: Sources/USBIPDCore/SystemExtension/BundleDetection/SystemExtensionBundleDetector.swift (continue from 1.1)
  - Add `HomebrewMetadata` struct for parsing bundle metadata
  - Add parsing of `Contents/HomebrewMetadata.json` for version and installation info
  - Extend `DetectionResult` to include production environment details
  - Git commit message: "feat: Add production metadata support to bundle detection\n\nAdd HomebrewMetadata parsing and enhanced DetectionResult:\n- Parse Contents/HomebrewMetadata.json for version info\n- Extend DetectionResult with production environment details\n- Support rich diagnostic information for Homebrew installs"
  - Purpose: Provide rich metadata about Homebrew installations for diagnostics
  - _Leverage: Existing DetectionResult struct, JSON parsing patterns_
  - _Requirements: 1.3, 1.4_

- [ ] 1.3 Create unit tests for enhanced bundle detection
  - File: Tests/USBIPDCoreTests/SystemExtension/SystemExtensionBundleDetectorTests.swift (modify existing)
  - Add test cases for Homebrew path detection with mock file system
  - Add test cases for production metadata parsing
  - Add test cases for multi-environment detection priority
  - Git commit message: "test: Add comprehensive tests for enhanced bundle detection\n\nAdd test coverage for production bundle detection:\n- Mock Homebrew file system structure tests\n- Production metadata parsing validation\n- Multi-environment detection priority tests"
  - Purpose: Ensure reliable bundle detection across all environments
  - _Leverage: Existing test utilities, mock file system patterns_
  - _Requirements: 1.1, 1.2, 1.3_

- [ ] 2. Implement actual System Extension submission to macOS
  - Create System Extension submission manager that calls OSSystemExtensionManager.shared.submitRequest()
  - Add approval monitoring and user guidance capabilities
  - _Requirements: 2.1, 2.2, 2.3_

- [ ] 2.1 Create SystemExtensionSubmissionManager.swift
  - File: Sources/USBIPDCore/SystemExtension/Installation/SystemExtensionSubmissionManager.swift (new file)
  - Implement `SystemExtensionSubmissionManager` class conforming to `OSSystemExtensionRequestDelegate`
  - Add `submitExtension(bundlePath:)` method that calls `OSSystemExtensionManager.shared.submitRequest()`
  - Add `monitorApprovalStatus()` method for tracking approval progress
  - Add proper error handling for all `OSSystemExtensionError` cases
  - Git commit message: "feat: Implement SystemExtensionSubmissionManager for macOS registration\n\nAdd actual System Extension submission to macOS:\n- Create SystemExtensionSubmissionManager with OSSystemExtensionRequestDelegate\n- Implement submitExtension() calling OSSystemExtensionManager.shared.submitRequest()\n- Add approval monitoring and comprehensive error handling"
  - Purpose: Actually submit System Extensions to macOS for approval
  - _Leverage: SystemExtensionInstaller patterns, Logger from Common_
  - _Requirements: 2.1, 2.2_

- [ ] 2.2 Implement OSSystemExtensionRequestDelegate methods
  - File: Sources/USBIPDCore/SystemExtension/Installation/SystemExtensionSubmissionManager.swift (continue from 2.1)
  - Implement `requestNeedsUserApproval(_:)` with clear user instructions
  - Implement `request(_:didFinishWithResult:)` with completion handling
  - Implement `request(_:didFailWithError:)` with comprehensive error mapping
  - Add status tracking and progress reporting capabilities
  - Git commit message: "feat: Complete OSSystemExtensionRequestDelegate implementation\n\nImplement delegate methods for System Extension approval workflow:\n- requestNeedsUserApproval with user guidance\n- request:didFinishWithResult with completion handling\n- request:didFailWithError with comprehensive error mapping"
  - Purpose: Handle macOS System Extension approval workflow
  - _Leverage: Existing OSSystemExtensionRequestDelegate patterns_
  - _Requirements: 2.2, 2.4, 2.5_

- [ ] 2.3 Create submission result types and error handling
  - File: Sources/USBIPDCore/SystemExtension/Installation/SystemExtensionSubmissionTypes.swift (new file)
  - Define `SystemExtensionSubmissionStatus` enum with all possible states
  - Define `SubmissionResult` struct with detailed status information
  - Define `SystemExtensionSubmissionError` enum for specific error types
  - Add user-friendly error messages and recovery instructions
  - Git commit message: "feat: Add System Extension submission types and error handling\n\nDefine comprehensive submission status and error types:\n- SystemExtensionSubmissionStatus enum for all states\n- SubmissionResult struct with detailed status info\n- SystemExtensionSubmissionError with user-friendly messages"
  - Purpose: Provide structured submission status and error reporting
  - _Leverage: Existing error handling patterns from Common_
  - _Requirements: 2.3, 2.5_

- [ ] 2.4 Create unit tests for SystemExtensionSubmissionManager
  - File: Tests/USBIPDCoreTests/SystemExtension/SystemExtensionSubmissionManagerTests.swift (new file)
  - Add test cases for successful submission workflow
  - Add test cases for all OSSystemExtensionError scenarios
  - Add test cases for approval monitoring and status tracking
  - Mock OSSystemExtensionManager for isolated testing
  - Git commit message: "test: Add comprehensive SystemExtensionSubmissionManager tests\n\nAdd test coverage for System Extension submission:\n- Successful submission workflow tests\n- All OSSystemExtensionError scenario tests\n- Approval monitoring and status tracking tests"
  - Purpose: Ensure reliable System Extension submission handling
  - _Leverage: Existing test utilities, mock patterns from test suites_
  - _Requirements: 2.1, 2.2, 2.5_

- [ ] 3. Implement service management integration
  - Create service lifecycle manager for launchd integration
  - Ensure proper coordination with brew services management
  - _Requirements: 3.1, 3.2, 3.3_

- [ ] 3.1 Create ServiceLifecycleManager.swift
  - File: Sources/USBIPDCore/SystemExtension/Installation/ServiceLifecycleManager.swift (new file)
  - Implement `ServiceLifecycleManager` class for launchd coordination
  - Add `integrateWithLaunchd()` method for service registration verification
  - Add `coordinateInstallationWithService()` method for installation workflow coordination
  - Add `verifyServiceManagement()` method for brew services status validation
  - Git commit message: "feat: Add ServiceLifecycleManager for launchd integration\n\nImplement service management coordination:\n- ServiceLifecycleManager for launchd coordination\n- integrateWithLaunchd() for service registration\n- coordinateInstallationWithService() for workflow sync\n- verifyServiceManagement() for brew services validation"
  - Purpose: Coordinate System Extension installation with service lifecycle
  - _Leverage: Process patterns from main.swift, service management utilities_
  - _Requirements: 3.1, 3.2_

- [ ] 3.2 Implement service status detection and management
  - File: Sources/USBIPDCore/SystemExtension/Installation/ServiceLifecycleManager.swift (continue from 3.1)
  - Add `detectServiceStatus()` method using launchctl and brew services commands
  - Add `resolveServiceConflicts()` method for orphaned process cleanup
  - Add `validateServiceIntegration()` method for end-to-end service verification
  - Git commit message: "feat: Complete service status detection and conflict resolution\n\nAdd comprehensive service management capabilities:\n- detectServiceStatus() using launchctl and brew services\n- resolveServiceConflicts() for orphaned process cleanup\n- validateServiceIntegration() for end-to-end verification"
  - Purpose: Detect and resolve service management issues
  - _Leverage: Process execution patterns, existing service coordination_
  - _Requirements: 3.3, 3.4_

- [ ] 3.3 Create service status types and diagnostic data
  - File: Sources/USBIPDCore/SystemExtension/Installation/ServiceManagementTypes.swift (new file)
  - Define `ServiceIntegrationStatus` struct with launchd and brew services status
  - Define `ServiceIssue` enum for specific service management problems
  - Define `ServiceResult` struct for operation results and recommendations
  - Git commit message: "feat: Add service management types and diagnostic structures\n\nDefine service status and diagnostic types:\n- ServiceIntegrationStatus for launchd/brew services status\n- ServiceIssue enum for specific problems\n- ServiceResult struct with operation results"
  - Purpose: Provide structured service status information
  - _Leverage: Existing result and status patterns from codebase_
  - _Requirements: 3.2, 3.4_

- [ ] 3.4 Create unit tests for ServiceLifecycleManager
  - File: Tests/USBIPDCoreTests/SystemExtension/ServiceLifecycleManagerTests.swift (new file)
  - Add test cases for service status detection with mocked Process execution
  - Add test cases for service conflict resolution scenarios
  - Add test cases for brew services integration validation
  - Git commit message: "test: Add ServiceLifecycleManager comprehensive test suite\n\nAdd test coverage for service management:\n- Service status detection with mocked Process\n- Service conflict resolution scenarios\n- Brew services integration validation"
  - Purpose: Ensure reliable service management coordination
  - _Leverage: Existing Process mocking patterns, test utilities_
  - _Requirements: 3.1, 3.2, 3.3_

- [ ] 4. Implement installation verification and diagnostics
  - Create comprehensive installation verification system
  - Add diagnostic reporting for troubleshooting
  - _Requirements: 4.1, 4.2, 4.3_

- [ ] 4.1 Create InstallationVerificationManager.swift
  - File: Sources/USBIPDCore/SystemExtension/Installation/InstallationVerificationManager.swift (new file)
  - Implement `InstallationVerificationManager` class for status verification
  - Add `verifyInstallation()` method using systemextensionsctl command execution
  - Add `generateDiagnosticReport()` method for comprehensive status analysis
  - Add `detectInstallationIssues()` method for problem identification
  - Git commit message: "feat: Add InstallationVerificationManager for status validation\n\nImplement comprehensive installation verification:\n- InstallationVerificationManager for status checking\n- verifyInstallation() using systemextensionsctl\n- generateDiagnosticReport() for analysis\n- detectInstallationIssues() for problem identification"
  - Purpose: Verify actual System Extension installation success
  - _Leverage: SystemExtensionDiagnostics patterns, Process execution_
  - _Requirements: 4.1, 4.2_

- [ ] 4.2 Implement systemextensionsctl integration and parsing
  - File: Sources/USBIPDCore/SystemExtension/Installation/InstallationVerificationManager.swift (continue from 4.1)
  - Add `executeSystemExtensionsCtl()` method for command execution
  - Add `parseSystemExtensionStatus()` method for output parsing
  - Add `validateExtensionRegistration()` method for registration verification
  - Add mapping of systemextensionsctl output to structured status data
  - Git commit message: "feat: Complete systemextensionsctl integration and parsing\n\nAdd systemextensionsctl command integration:\n- executeSystemExtensionsCtl() for command execution\n- parseSystemExtensionStatus() for output parsing\n- validateExtensionRegistration() for verification\n- Structured status data mapping"
  - Purpose: Parse and validate actual macOS System Extension registry status
  - _Leverage: Process execution patterns, string parsing utilities_
  - _Requirements: 4.1, 4.3_

- [ ] 4.3 Create installation verification types and diagnostic data
  - File: Sources/USBIPDCore/SystemExtension/Installation/InstallationVerificationTypes.swift (new file)
  - Define `InstallationVerificationResult` struct with comprehensive status
  - Define `InstallationStatus` enum for overall functional status
  - Define `VerificationCheck` struct for individual check results
  - Define `InstallationIssue` enum for specific problems and remediation
  - Git commit message: "feat: Add installation verification types and diagnostic structures\n\nDefine verification and diagnostic data types:\n- InstallationVerificationResult with comprehensive status\n- InstallationStatus enum for functional status\n- VerificationCheck struct for individual results\n- InstallationIssue enum with remediation guidance"
  - Purpose: Provide detailed installation status and diagnostic information
  - _Leverage: Existing diagnostic patterns from SystemExtensionDiagnostics_
  - _Requirements: 4.2, 4.3_

- [ ] 4.4 Create unit tests for InstallationVerificationManager
  - File: Tests/USBIPDCoreTests/SystemExtension/InstallationVerificationManagerTests.swift (new file)
  - Add test cases for systemextensionsctl output parsing
  - Add test cases for installation status verification
  - Add test cases for diagnostic report generation
  - Mock systemextensionsctl command execution for isolated testing
  - Git commit message: "test: Add InstallationVerificationManager comprehensive tests\n\nAdd test coverage for installation verification:\n- systemextensionsctl output parsing tests\n- Installation status verification tests\n- Diagnostic report generation tests"
  - Purpose: Ensure accurate installation status reporting
  - _Leverage: Existing test utilities, Process mocking patterns_
  - _Requirements: 4.1, 4.2, 4.3_

- [ ] 5. Create installation orchestration and integration
  - Integrate all components into unified installation workflow
  - Update CLI commands and service coordination
  - _Requirements: 5.1, 5.2_

- [ ] 5.1 Create InstallationOrchestrator.swift
  - File: Sources/USBIPDCore/SystemExtension/Installation/InstallationOrchestrator.swift (new file)
  - Implement `InstallationOrchestrator` class coordinating all installation components
  - Add `performCompleteInstallation()` method for end-to-end installation workflow
  - Add `handleInstallationFailure()` method for error recovery and rollback
  - Add `reportInstallationProgress()` method for progress reporting
  - Integrate ProductionBundleDetector, SystemExtensionSubmissionManager, ServiceLifecycleManager, and InstallationVerificationManager
  - Git commit message: "feat: Add InstallationOrchestrator for unified workflow coordination\n\nImplement end-to-end installation orchestration:\n- InstallationOrchestrator coordinating all components\n- performCompleteInstallation() for workflow management\n- handleInstallationFailure() for error recovery\n- reportInstallationProgress() for user feedback\n- Integration of all installation components"
  - Purpose: Coordinate complete System Extension installation workflow
  - _Leverage: ServerCoordinator patterns, existing component integration_
  - _Requirements: 5.1, 5.2_

- [ ] 5.2 Update CLI integration in main.swift for installation support
  - File: Sources/USBIPDCLI/main.swift (modify existing)
  - Add `--install-system-extension` command line option
  - Add installation workflow integration with InstallationOrchestrator
  - Add progress reporting and user feedback during installation
  - Update daemon startup to use enhanced bundle detection
  - Git commit message: "feat: Add CLI installation command and daemon integration\n\nIntegrate installation capabilities with CLI:\n- Add --install-system-extension command option\n- Integrate InstallationOrchestrator workflow\n- Add progress reporting and user feedback\n- Update daemon startup with enhanced bundle detection"
  - Purpose: Provide CLI interface for System Extension installation
  - _Leverage: Existing command parsing patterns, daemon startup logic_
  - _Requirements: 2.4, 5.1, 5.2_

- [ ] 5.3 Update SystemExtensionManager integration
  - File: Sources/USBIPDCore/SystemExtension/SystemExtensionManager.swift (modify existing)
  - Update initialization to use enhanced bundle detection
  - Integrate installation orchestrator for automatic installation workflows
  - Add installation status reporting in `getStatus()` method
  - Git commit message: "feat: Integrate enhanced installation with SystemExtensionManager\n\nUpdate SystemExtensionManager with new capabilities:\n- Enhanced bundle detection integration\n- InstallationOrchestrator integration for automatic workflows\n- Installation status reporting in getStatus() method"
  - Purpose: Integrate enhanced installation capabilities with existing System Extension management
  - _Leverage: Existing SystemExtensionManager patterns, service coordination_
  - _Requirements: 1.4, 5.1_

- [ ] 5.4 Create integration tests for complete installation workflow
  - File: Tests/IntegrationTests/SystemExtensionInstallationWorkflowTests.swift (modify existing)
  - Add test cases for complete installation workflow from bundle detection to verification
  - Add test cases for error recovery and rollback scenarios
  - Add test cases for service management integration
  - Add test cases for Homebrew environment simulation
  - Git commit message: "test: Add comprehensive installation workflow integration tests\n\nAdd end-to-end installation testing:\n- Complete workflow from detection to verification\n- Error recovery and rollback scenarios\n- Service management integration testing\n- Homebrew environment simulation"
  - Purpose: Validate end-to-end installation functionality
  - _Leverage: Existing integration test patterns, environment simulation_
  - _Requirements: All requirements_

- [ ] 6. Update external installation tools and documentation
  - Update Homebrew installation script and CLI tools
  - Add comprehensive diagnostic capabilities
  - _Requirements: 4.4, 5.3_

- [ ] 6.1 Update homebrew-install-extension.rb script
  - File: Scripts/homebrew-install-extension.rb (modify existing)
  - Update `attempt_automatic_installation` to call actual CLI installation command
  - Add integration with new InstallationOrchestrator for automatic installation
  - Add enhanced status reporting using new verification capabilities
  - Update diagnostic reporting to use comprehensive installation verification
  - Git commit message: "fix: Update homebrew-install-extension.rb with functional installation\n\nFix broken Homebrew installation script:\n- Update attempt_automatic_installation to call CLI command\n- Integrate with InstallationOrchestrator for automatic installation\n- Add enhanced status reporting with new verification\n- Update diagnostics with comprehensive verification"
  - Purpose: Enable functional automatic installation from Homebrew script
  - _Leverage: Existing Ruby script patterns, CLI integration_
  - _Requirements: 2.3, 5.2_

- [ ] 6.2 Add comprehensive diagnostic command to CLI
  - File: Sources/USBIPDCLI/Commands.swift (modify existing)
  - Add `diagnose` command that runs comprehensive installation diagnostics
  - Add `--verbose` option for detailed diagnostic output
  - Add specific diagnostic modes for bundle detection, installation status, and service management
  - Git commit message: "feat: Add comprehensive diagnostic CLI command\n\nAdd diagnostic capabilities to CLI:\n- diagnose command with comprehensive installation diagnostics\n- --verbose option for detailed output\n- Specific modes for bundle detection, installation, service management"
  - Purpose: Provide users with detailed troubleshooting capabilities
  - _Leverage: Existing command patterns, diagnostic infrastructure_
  - _Requirements: 4.3, 5.3_

- [ ] 6.3 Create end-to-end validation tests
  - File: Tests/IntegrationTests/ProductionEnvironmentTests.swift (new file)
  - Add test cases simulating complete Homebrew installation environment
  - Add test cases for System Extension submission and approval simulation
  - Add test cases for service management integration validation
  - Add test cases for diagnostic accuracy in various failure scenarios
  - Git commit message: "test: Add production environment validation tests\n\nAdd comprehensive production testing:\n- Homebrew installation environment simulation\n- System Extension submission and approval simulation\n- Service management integration validation\n- Diagnostic accuracy in failure scenarios"
  - Purpose: Validate complete functionality in production-like environments
  - _Leverage: Existing integration test infrastructure, environment mocking_
  - _Requirements: All requirements_

- [ ] 7. Create test release and validation
  - Build and test a release version before final integration
  - Validate all functionality in release environment
  - _Requirements: All_

- [ ] 7.1 Build and test release candidate
  - Run swift build --configuration release to build release version
  - Run complete test suite with ./Scripts/run-production-tests.sh
  - Validate SwiftLint compliance with swiftlint lint --strict
  - Test manual installation workflow with built release binaries
  - Test Homebrew script integration with release build
  - Git commit message: "build: Create and validate release candidate\n\nBuild and test release version:\n- Release configuration build validation\n- Complete production test suite execution\n- SwiftLint compliance validation\n- Manual installation workflow testing\n- Homebrew script integration testing"
  - Purpose: Validate complete functionality in release build before final integration
  - _Leverage: Existing build and test infrastructure_
  - _Requirements: All_

- [ ] 7.2 Create test Homebrew formula for validation
  - Create temporary test formula in Scripts/test-formula/ directory
  - Build and test installation using test formula with release candidate
  - Validate System Extension installation workflow end-to-end
  - Test service management integration with test installation
  - Document any discovered issues and create fixes
  - Git commit message: "test: Add test Homebrew formula for installation validation\n\nCreate test formula for end-to-end validation:\n- Temporary test formula for release candidate\n- Complete installation workflow testing\n- System Extension installation validation\n- Service management integration testing"
  - Purpose: Test complete Homebrew installation workflow before production release
  - _Leverage: Existing Homebrew formula patterns from Scripts/_
  - _Requirements: All_

- [ ] 8. Final integration, cleanup and PR creation
  - Complete integration testing and documentation updates
  - Ensure backward compatibility with existing workflows
  - Create pull request and validate CI pipeline
  - _Requirements: All_

- [ ] 8.1 Run comprehensive test suite and fix any integration issues
  - Execute all unit tests, integration tests, and end-to-end tests
  - Fix any compilation errors, test failures, or integration issues
  - Validate SwiftLint compliance and code quality standards
  - Test complete workflow with both development and Homebrew environments
  - Git commit message: "test: Complete comprehensive testing and fix integration issues\n\nFinal testing and integration validation:\n- All unit, integration, and end-to-end test execution\n- Compilation error and test failure fixes\n- SwiftLint compliance and code quality validation\n- Development and Homebrew environment workflow testing"
  - Purpose: Ensure all components work together reliably
  - _Leverage: Existing test infrastructure, CI pipeline patterns_
  - _Requirements: All_

- [ ] 8.2 Update project documentation and help text
  - File: README.md, Documentation/ (modify existing)
  - Update installation instructions to reflect enhanced capabilities
  - Add troubleshooting section for System Extension installation issues
  - Update CLI help text to include new installation and diagnostic commands
  - Git commit message: "docs: Update documentation for enhanced System Extension installation\n\nUpdate project documentation:\n- Enhanced installation instructions\n- Troubleshooting section for System Extension issues\n- Updated CLI help text with new commands\n- Comprehensive user guidance"
  - Purpose: Provide clear guidance for users on enhanced installation capabilities
  - _Leverage: Existing documentation structure and patterns_
  - _Requirements: 4.4, 5.3_

- [ ] 8.3 Create pull request and validate CI pipeline
  - Create pull request from feature/system-extension-installation-fix to main
  - Ensure all CI pipeline checks pass (build, tests, linting)
  - Add comprehensive PR description with testing instructions
  - Address any CI failures or feedback from automated checks
  - Git commit message (if fixes needed): "ci: Fix CI pipeline issues and finalize PR\n\nComplete CI pipeline validation:\n- Address any build or test failures\n- Fix linting issues and code quality concerns\n- Validate all GitHub Actions workflows pass\n- Ensure clean merge with main branch"
  - Purpose: Complete development workflow and prepare for merge
  - _Leverage: Existing CI pipeline configuration, GitHub workflow patterns_
  - _Requirements: All_