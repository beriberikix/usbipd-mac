# Implementation Plan

## Task Overview

The implementation focuses on fixing the System Extension bundle detection bugs by modifying the existing `SystemExtensionBundleDetector` to exclude dSYM paths and enhance bundle validation for both development and production environments. The approach maintains backward compatibility while providing clear diagnostic information for troubleshooting.

## Tasks

- [x] 1. Create a feature branch named `feature/system-extension-bundle-fix`.
  - Run `git checkout -b feature/system-extension-bundle-fix`
  - Purpose: Isolate development work for the new feature.

- [x] 2. Commit the spec documents to the feature branch.
  - Add `requirements.md`, `design.md`, and `tasks.md` to staging.
  - Commit with a message such as "docs: add spec for system extension bundle fix".
  - Purpose: Version control the specification documents.

- [x] 3. Add dSYM path detection utility method in SystemExtensionBundleDetector.swift
  - File: Sources/USBIPDCore/SystemExtension/BundleDetection/SystemExtensionBundleDetector.swift
  - Add private method `isDSYMPath(_ path: URL) -> Bool` to detect .dSYM directories
  - Implement logic to check if path contains ".dSYM" component anywhere in the path
  - Purpose: Provide utility to exclude debug symbol directories from bundle detection
  - _Leverage: Existing URL path component analysis patterns_
  - _Requirements: 1.1, 1.2_

- [x] 4. Enhance findBundleInPath method to exclude dSYM directories
  - File: Sources/USBIPDCore/SystemExtension/BundleDetection/SystemExtensionBundleDetector.swift (continue from task 3)
  - Modify `findBundleInPath(_ path: URL) -> URL?` method to call `isDSYMPath` before processing directories
  - Add early return when dSYM paths are encountered to skip recursive search
  - Add debug logging when dSYM paths are skipped for diagnostic purposes
  - Purpose: Fix the core bug where dSYM directories are incorrectly identified as bundle paths
  - _Leverage: Existing recursive search logic and Logger infrastructure_
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 5. Add bundle type enumeration and rejection reason types
  - File: Sources/USBIPDCore/SystemExtension/BundleDetection/SystemExtensionBundleDetector.swift (continue from task 4)
  - Add `BundleType` enum with `.development` and `.production` cases
  - Add `RejectionReason` enum with `.dSYMPath`, `.missingExecutable`, `.invalidBundleStructure`, `.missingInfoPlist` cases
  - Update `BundleValidationResult` struct to include `bundleType` and `rejectionReason` properties
  - Purpose: Provide structured error information for enhanced diagnostics and troubleshooting
  - _Leverage: Existing Swift enum patterns and error handling structures_
  - _Requirements: 3.1, 3.2, 3.3_

- [x] 6. Enhance validateBundle method with improved development bundle support
  - File: Sources/USBIPDCore/SystemExtension/BundleDetection/SystemExtensionBundleDetector.swift (continue from task 5)
  - Modify `validateBundle(at bundlePath: URL) -> BundleValidationResult` to properly detect bundle type
  - Add logic to determine if bundle is development (contains USBIPDSystemExtension executable) or production (.systemextension)
  - Update validation rules to accept development bundles with executable in build directory
  - Add specific rejection reasons for different validation failure scenarios
  - Purpose: Fix validation issues that prevent development System Extension installation
  - _Leverage: Existing bundle validation framework and file system checks_
  - _Requirements: 2.1, 2.2, 2.3_

- [x] 7. Update DetectionResult structure with enhanced diagnostic information
  - File: Sources/USBIPDCore/SystemExtension/BundleDetection/SystemExtensionBundleDetector.swift (continue from task 6)
  - Add `skippedPaths: [String]` property to `DetectionResult` struct to track paths that were skipped during detection
  - Add `rejectionReasons: [String: RejectionReason]` property to map paths to their rejection reasons
  - Update `detectBundle()` method to populate these new diagnostic fields during search process
  - Purpose: Provide comprehensive diagnostic information for troubleshooting bundle detection issues
  - _Leverage: Existing DetectionResult structure and detection workflow_
  - _Requirements: 3.1, 3.2, 3.3_

- [x] 8. Create unit tests for dSYM path detection and exclusion logic
  - File: Tests/USBIPDCoreTests/SystemExtensionBundleDetectorTests.swift
  - Add test method `testDSYMPathDetection()` to verify `isDSYMPath` correctly identifies dSYM directories
  - Add test method `testDSYMPathExclusion()` to verify `findBundleInPath` skips dSYM directories during search
  - Create mock file system structure with dSYM directories and verify they are excluded from results
  - Purpose: Ensure dSYM path detection and exclusion logic works correctly across different directory structures
  - _Leverage: Existing test framework patterns and mock file system utilities_
  - _Requirements: 1.1, 1.2_

- [x] 9. Create unit tests for enhanced bundle validation logic
  - File: Tests/USBIPDCoreTests/SystemExtensionBundleDetectorTests.swift (continue from task 8)
  - Add test method `testDevelopmentBundleValidation()` to verify development bundle validation accepts valid structures
  - Add test method `testProductionBundleValidation()` to verify production bundle validation works correctly
  - Add test method `testBundleTypeDetection()` to verify bundle type detection logic correctly identifies development vs production
  - Create test fixtures for both development and production bundle structures
  - Purpose: Ensure enhanced validation logic correctly handles both bundle types and provides appropriate error information
  - _Leverage: Existing test utilities and bundle validation test patterns_
  - _Requirements: 2.1, 2.2, 2.3_

- [x] 10. Create unit tests for enhanced error reporting and diagnostics
  - File: Tests/USBIPDCoreTests/SystemExtensionBundleDetectorTests.swift (continue from task 9)
  - Add test method `testEnhancedErrorReporting()` to verify detailed error messages are generated for different failure scenarios
  - Add test method `testDiagnosticInformation()` to verify skipped paths and rejection reasons are properly tracked
  - Add test method `testRejectionReasonMapping()` to verify different failure types map to correct rejection reasons
  - Purpose: Ensure diagnostic information is comprehensive and actionable for troubleshooting
  - _Leverage: Existing error handling test patterns and logging verification utilities_
  - _Requirements: 3.1, 3.2, 3.3_

- [x] 11. Create integration test for end-to-end System Extension installation workflow
  - File: Tests/IntegrationTests/SystemExtensionInstallationFixTests.swift
  - Create integration test that builds actual System Extension, runs bundle detection, and verifies installation succeeds
  - Test full workflow from `swift build` through bundle detection to installation attempt
  - Verify that corrected bundle detection enables successful System Extension installation
  - Mock System Extension submission to focus on bundle detection and validation workflow
  - Purpose: Ensure the complete fix resolves the original SystemExtensionSubmissionError issue
  - _Leverage: Existing integration test framework and System Extension testing utilities_
  - _Requirements: 1.4, 2.3, 4.3_

- [x] 12. Update diagnostic command output to include enhanced bundle information
  - File: Sources/USBIPDCLI/Commands.swift
  - Modify `diagnose` command implementation to display detailed bundle detection results
  - Add output formatting for skipped paths, rejection reasons, and bundle type information
  - Include recommendations based on detected issues (e.g., "Run swift build" for missing bundles)
  - Purpose: Provide users with actionable diagnostic information for troubleshooting System Extension issues
  - _Leverage: Existing command output formatting utilities and diagnostic reporting patterns_
  - _Requirements: 3.3, 4.4_

- [x] 13. Add enhanced logging for bundle detection workflow
  - File: Sources/USBIPDCore/SystemExtension/BundleDetection/SystemExtensionBundleDetector.swift (final enhancement)
  - Add debug-level logging when dSYM paths are encountered and skipped
  - Add info-level logging for successful bundle detection with bundle type information
  - Add warning-level logging for validation failures with specific rejection reasons
  - Ensure logging provides clear context for troubleshooting without being verbose in normal operation
  - Purpose: Enable comprehensive troubleshooting through log analysis while maintaining clean user experience
  - _Leverage: Existing Logger infrastructure and logging patterns throughout the codebase_
  - _Requirements: 3.1, 3.2_

- [x] 14. Manual validation testing of the complete fix
  - Test the complete fix by building the project and running System Extension installation
  - Verify `usbipd install-system-extension` succeeds with corrected bundle detection
  - Test `usbipd diagnose` output shows enhanced diagnostic information
  - Confirm System Extension installation no longer fails with SystemExtensionSubmissionError
  - Document any remaining issues or edge cases discovered during testing
  - Purpose: Validate that the implemented fix resolves the original issue and provides enhanced user experience
  - _Leverage: Existing manual testing procedures and System Extension validation workflows_
  - _Requirements: All_

- [-] 15. Create a pull request from the feature branch to the main branch.
  - Push the feature branch to the remote repository.
  - Create a pull request in the repository's web interface.
  - Purpose: Initiate code review and merge process.

- [ ] 16. Address any CI/CD issues that arise from the pull request.
  - Monitor the CI/CD pipeline for the pull request.
  - Fix any build, test, or linting errors.
  - Push fixes to the feature branch to update the pull request.
  - Purpose: Ensure the changes meet the project's quality standards.
