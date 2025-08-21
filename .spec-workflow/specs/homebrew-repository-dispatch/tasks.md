# Implementation Plan

## Task Overview

This implementation plan converts the homebrew-releaser approach to a repository dispatch-based system. The work is organized into four phases: removing homebrew-releaser from the main repository, creating the tap repository workflow, implementing the binary validation and formula update scripts, and testing the complete end-to-end workflow.

## Tasks

- [ ] 1. Remove homebrew-releaser from main repository workflow
  - File: .github/workflows/release.yml
  - Remove the entire update-homebrew-formula job (lines 479-623)
  - Remove homebrew-releaser dependency and configuration
  - Purpose: Clean up existing implementation to prepare for new approach
  - _Requirements: 1.1, 5.1_

- [ ] 2. Add repository dispatch step to release workflow
  - File: .github/workflows/release.yml
  - Add new job to send repository_dispatch event after create-release job succeeds
  - Use peter-evans/repository-dispatch action with structured payload
  - Include version, binary URL, SHA256, and release metadata
  - Purpose: Trigger tap repository updates via dispatch events
  - _Requirements: 1.1, 1.2, 5.1, 5.3_

- [ ] 3. Create tap repository workflow file
  - File: /Users/jberi/code/homebrew-usbipd-mac/.github/workflows/formula-update.yml
  - Create GitHub Actions workflow triggered by repository_dispatch events
  - Set up environment with necessary tools (git, curl, GitHub CLI)
  - Add job to process formula_update event type
  - Purpose: Establish workflow infrastructure for receiving dispatch events
  - _Requirements: 1.3, 3.1_

- [ ] 4. Create binary download and validation script
  - File: /Users/jberi/code/homebrew-usbipd-mac/Scripts/validate-binary.sh
  - Implement binary download with retry logic and timeout handling
  - Add SHA256 checksum verification against expected value
  - Include file size validation and basic malware detection
  - Purpose: Ensure binary integrity before formula updates
  - _Requirements: 2.2, 3.2, 3.3, 4.1, 4.3_

- [ ] 5. Create formula update script
  - File: /Users/jberi/code/homebrew-usbipd-mac/Scripts/update-formula-from-dispatch.sh
  - Parse repository dispatch payload and extract release metadata
  - Update formula file with new version, URL, and SHA256 values
  - Validate Ruby syntax after updates using ruby -c
  - Purpose: Automate formula file updates with proper validation
  - _Leverage: /Users/jberi/code/homebrew-usbipd-mac/Scripts/manual-update.sh_
  - _Requirements: 2.1, 2.2, 2.3, 4.2_

- [ ] 6. Implement error handling and issue creation
  - File: /Users/jberi/code/homebrew-usbipd-mac/Scripts/create-update-issue.sh
  - Create GitHub issues for failed formula updates with detailed context
  - Include error stage, release metadata, and troubleshooting information
  - Add issue templates for different failure scenarios
  - Purpose: Provide visibility and actionable information for failed updates
  - _Requirements: 3.4, 3.5_

- [ ] 7. Add atomic formula update with rollback
  - File: /Users/jberi/code/homebrew-usbipd-mac/Scripts/update-formula-from-dispatch.sh (extend from task 5)
  - Create backup of formula file before making changes
  - Implement rollback mechanism for failed updates
  - Ensure git repository is left in clean state after failures
  - Purpose: Prevent corrupted formula files and maintain repository integrity
  - _Requirements: 3.1, 3.5_

- [ ] 8. Configure GitHub secrets for repository dispatch
  - Configure HOMEBREW_TAP_DISPATCH_TOKEN secret in main repository
  - Set up token with minimal permissions for repository dispatch events
  - Document token requirements and rotation procedures
  - Purpose: Enable secure communication between repositories
  - _Requirements: 5.2_

- [ ] 9. Create integration test script for dispatch workflow
  - File: /Users/jberi/code/usbipd-mac/Scripts/test-homebrew-dispatch.sh
  - Test repository dispatch sending with mock payloads
  - Validate payload structure and required fields
  - Test error handling for malformed dispatch events
  - Purpose: Ensure dispatch mechanism works correctly before production use
  - _Requirements: All_

- [ ] 10. Create validation script for tap repository workflow
  - File: /Users/jberi/code/homebrew-usbipd-mac/Scripts/test-formula-update.sh
  - Test formula update workflow with mock dispatch events
  - Validate binary download, checksum verification, and formula updates
  - Test error scenarios and rollback mechanisms
  - Purpose: Ensure tap repository workflow handles all scenarios correctly
  - _Requirements: All_

- [ ] 11. Update workflow documentation and README files
  - File: /Users/jberi/code/usbipd-mac/CLAUDE.md
  - Document new repository dispatch workflow and troubleshooting procedures
  - Update release automation section with new approach
  - Add emergency procedures for manual formula updates
  - Purpose: Ensure maintainers understand new workflow and can troubleshoot issues
  - _Requirements: 5.4_

- [ ] 12. Perform end-to-end testing with development release
  - Create test release in development environment
  - Trigger complete workflow from release creation to formula update
  - Validate Homebrew installation works with updated formula
  - Test error scenarios and issue creation
  - Purpose: Validate complete workflow before production deployment
  - _Requirements: All_