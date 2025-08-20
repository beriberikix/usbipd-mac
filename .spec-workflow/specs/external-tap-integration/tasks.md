# Implementation Plan

## Task Overview

This implementation plan transforms the usbipd-mac Homebrew distribution from an embedded Formula/ directory to a pull-based external tap repository system. The work follows proper git workflow practices with feature branch development, regular commits, and pull request integration.

The implementation follows a phased approach: first establish the metadata generation in the main repository, then set up the tap repository with webhook handling, finally remove the legacy Formula/ directory and update documentation.

## Tasks

- [x] 1. Create feature branch for external tap integration
  - Git: Create and checkout feature branch `feature/external-tap-integration`
  - Ensure clean working directory and sync with latest main branch
  - Set up branch tracking for collaborative development if needed
  - Purpose: Follow git workflow best practices for feature development
  - _Requirements: Git workflow compliance_

- [x] 2. Create homebrew metadata generation script
  - File: Scripts/generate-homebrew-metadata.sh
  - Create shell script that generates homebrew-metadata.json with version, SHA256, release notes, and timestamp
  - Include JSON schema validation and error handling for malformed inputs
  - Purpose: Generate structured metadata for tap repository consumption
  - _Requirements: 1.1, 1.4_

- [x] 3. Add JSON schema validation utility
  - File: Scripts/validate-homebrew-metadata.sh  
  - Create validation script using jq to verify JSON schema compliance
  - Include comprehensive error messages for schema violations
  - Purpose: Ensure metadata consistency and prevent tap repository failures
  - _Leverage: Scripts/validate-formula.sh patterns_
  - _Requirements: 7.2, 7.4_

- [x] 4. Commit initial metadata generation tools
  - Git: Add and commit Scripts/generate-homebrew-metadata.sh and Scripts/validate-homebrew-metadata.sh
  - Use commit message: "feat: add homebrew metadata generation and validation scripts"
  - Include detailed commit description explaining the new functionality
  - Purpose: Save progress on metadata tooling development
  - _Requirements: Git workflow compliance_

- [x] 5. Modify release workflow to generate metadata
  - File: .github/workflows/release.yml
  - Replace update-homebrew-formula job with generate-homebrew-metadata job
  - Integrate metadata generation after artifact building but before release creation
  - Purpose: Publish structured metadata with each release for tap repository processing
  - _Leverage: existing SHA256 calculation and release notes generation_
  - _Requirements: 1.1, 1.3_

- [x] 6. Update release workflow to upload metadata as asset
  - File: .github/workflows/release.yml (continue from task 5)
  - Add step to upload homebrew-metadata.json as release asset using gh CLI
  - Ensure metadata upload happens after release creation but before completion
  - Purpose: Make metadata available for tap repository webhook processing
  - _Leverage: existing artifact upload patterns_
  - _Requirements: 1.3, 2.3_

- [x] 7. Update CI workflow to validate metadata generation
  - File: .github/workflows/ci.yml (modify existing)
  - Add validation that metadata generation works correctly in CI environment
  - Include tests that verify metadata schema compliance and JSON validation
  - Purpose: Catch metadata generation issues before they affect tap repository
  - _Requirements: 1.4, 7.2_

- [x] 8. Commit release workflow modifications
  - Git: Add and commit .github/workflows/release.yml and .github/workflows/ci.yml changes
  - Use commit message: "feat: replace formula update with metadata generation in release workflow"
  - Include detailed description of workflow changes and their purpose
  - Purpose: Save progress on main repository workflow modifications
  - _Requirements: Git workflow compliance_

- [x] 9. Create tap repository webhook workflow
  - File: .github/workflows/formula-update.yml (new file in tap repository)
  - Implement GitHub Action triggered by release webhooks from main repository
  - Include manual workflow dispatch with version parameter for recovery scenarios
  - Purpose: Automatically update formula when new releases are published
  - _Requirements: 2.1, 2.2, 4.1_

- [x] 10. Implement metadata fetching logic in tap workflow
  - File: .github/workflows/formula-update.yml (continue from task 9)
  - Add steps to download and validate homebrew-metadata.json from release assets
  - Include retry logic with exponential backoff for network failures
  - Purpose: Reliably fetch release metadata for formula updates
  - _Leverage: existing artifact download patterns from main repository_
  - _Requirements: 2.3, 8.3_

- [x] 11. Implement archive download and verification
  - File: .github/workflows/formula-update.yml (continue from task 10)
  - Add steps to download GitHub source archive and verify SHA256 checksum against metadata
  - Include detailed error logging for checksum mismatches
  - Purpose: Ensure formula updates use verified source code
  - _Requirements: 3.1, 8.2_

- [x] 12. Create formula update engine script
  - File: Scripts/update-formula.rb (new file in tap repository)
  - Implement Ruby script to update formula template with version and checksum placeholders
  - Include Ruby syntax validation and basic Homebrew formula structure checking
  - Purpose: Perform safe and validated formula updates
  - _Requirements: 3.2, 3.3_

- [x] 13. Integrate formula validation in tap workflow
  - File: .github/workflows/formula-update.yml (continue from task 12)
  - Add validation steps using Ruby syntax check and Homebrew audit if available
  - Include rollback logic to preserve existing formula on validation failures
  - Purpose: Ensure updated formulas are syntactically correct and functional
  - _Requirements: 3.3, 8.4_

- [x] 14. Implement git commit and push logic
  - File: .github/workflows/formula-update.yml (continue from task 13)
  - Add steps to commit updated formula with descriptive message and push to tap repository
  - Include conflict detection and resolution guidance for manual intervention
  - Purpose: Publish updated formula to tap repository for Homebrew users
  - _Requirements: 3.4, 8.1_

- [x] 15. Create standalone recovery script
  - File: Scripts/manual-update.sh (new file in tap repository)
  - Implement command-line script with same logic as webhook workflow for manual operations
  - Include dry-run mode, version parameter, and comprehensive error reporting
  - Purpose: Enable manual formula updates for testing and emergency recovery
  - _Requirements: 5.1, 5.2, 5.3_

- [x] 16. Add comprehensive error handling to all tap workflows
  - File: .github/workflows/formula-update.yml (enhance from previous tasks)
  - Implement detailed error logging with timestamps and context information
  - Add notification mechanisms for critical failures requiring immediate attention
  - Purpose: Ensure formula update failures are quickly identified and resolved
  - _Requirements: 8.1, 8.2, 8.5_

- [x] 17. Commit tap repository workflow implementation
  - Git: Add and commit all tap repository files (workflows, scripts) to tap repository
  - Use commit message: "feat: implement webhook-triggered formula update workflow"
  - Include comprehensive commit description explaining the pull-based architecture
  - Purpose: Save complete tap repository workflow implementation
  - _Requirements: Git workflow compliance_

- [x] 18. Create tap repository formula template
  - File: Formula/usbipd-mac.rb (new file in tap repository)
  - Copy existing formula content from main repository Formula/usbipd-mac.rb
  - Replace hardcoded version and checksum with placeholder tokens for template substitution
  - Purpose: Establish working formula template that preserves all existing functionality
  - _Leverage: Formula/usbipd-mac.rb from main repository_
  - _Requirements: 7.1, 3.2_

- [-] 19. Configure tap repository webhook integration
  - Configuration: GitHub repository settings (performed in GitHub UI)
  - Set up webhook to trigger on release events from main repository
  - Configure webhook URL to target tap repository workflow_dispatch endpoint
  - Purpose: Enable automatic formula updates when main repository publishes releases
  - _Requirements: 2.1, 2.4_

- [x] 20. Commit tap repository formula and configuration
  - Git: Add and commit Formula/usbipd-mac.rb to tap repository
  - Use commit message: "feat: add formula template with placeholder substitution support"
  - Document webhook configuration steps in commit description
  - Purpose: Complete tap repository setup with working formula template
  - _Requirements: Git workflow compliance_

- [ ] 21. Test end-to-end integration
  - Test Environment: Both repositories with webhook configuration
  - Create test release in main repository and verify tap repository formula update
  - Validate complete workflow from metadata generation through formula publication
  - Purpose: Ensure complete workflow functions correctly before production deployment
  - _Requirements: All integration requirements_

- [ ] 22. Remove Formula directory from main repository  
  - Files: Formula/usbipd-mac.rb (delete), Scripts/update-formula.sh (delete)
  - Remove Formula directory and formula-related scripts no longer needed
  - Clean up any references to Formula directory in documentation and scripts
  - Purpose: Eliminate dual formula management and establish tap repository as single source of truth
  - _Requirements: 6.1, 6.2_

- [ ] 23. Remove formula-related scripts from main repository
  - Files: Scripts/validate-formula.sh, Scripts/rollback-formula.sh, Scripts/validate-homebrew-installation.sh (delete or update)
  - Remove or update scripts that are specific to local Formula directory management
  - Preserve any functionality needed for release automation or testing
  - Purpose: Clean up main repository from formula-specific tooling
  - _Requirements: 6.2, 6.4_

- [ ] 24. Commit removal of legacy Formula directory and scripts
  - Git: Add deleted files and commit with message: "feat: remove local Formula directory, migrated to external tap"
  - Include detailed commit description explaining the migration and new installation method
  - Reference the tap repository URL in the commit message
  - Purpose: Complete removal of legacy formula management from main repository
  - _Requirements: Git workflow compliance_

- [ ] 25. Update documentation for tap-based installation
  - Files: README.md, Documentation/, CLAUDE.md
  - Update all installation instructions to use `brew tap beriberikix/usbipd-mac && brew install usbipd-mac`
  - Remove references to Formula directory and local formula installation
  - Purpose: Guide users to correct installation method using tap repository
  - _Requirements: 6.3, 6.5_

- [ ] 26. Add troubleshooting documentation for tap repository
  - File: Documentation/homebrew-troubleshooting.md (update existing)
  - Add sections covering webhook failures, metadata issues, and formula validation problems
  - Include manual workflow dispatch instructions and recovery procedures
  - Purpose: Provide comprehensive troubleshooting guidance for new architecture
  - _Requirements: 8.2, 5.4_

- [ ] 27. Commit documentation updates
  - Git: Add and commit all documentation changes
  - Use commit message: "docs: update installation instructions for external tap repository"
  - Include description of new installation method and troubleshooting additions
  - Purpose: Complete documentation update for new architecture
  - _Requirements: Git workflow compliance_

- [ ] 28. Create integration tests for tap workflow
  - File: Tests/Integration/TapRepositoryIntegrationTests.swift
  - Implement tests that verify webhook processing, metadata validation, and formula updates
  - Include tests for error scenarios and recovery procedures
  - Purpose: Ensure tap repository workflows remain reliable through future changes
  - _Requirements: 8.1, 8.4_

- [ ] 29. Validate tap repository formula installation
  - Test Environment: Clean macOS system with Homebrew
  - Perform complete installation test using tap repository: brew tap && brew install
  - Verify System Extension functionality and service management work correctly
  - Purpose: Ensure end-user installation experience matches existing functionality
  - _Requirements: 3.4, formula preservation requirements_

- [ ] 30. Commit integration tests and validation results
  - Git: Add and commit Tests/Integration/TapRepositoryIntegrationTests.swift
  - Use commit message: "test: add integration tests for tap repository workflow"
  - Include test results and validation notes in commit description
  - Purpose: Complete testing infrastructure for external tap integration
  - _Requirements: Git workflow compliance_

- [ ] 31. Create deployment checklist and rollback procedures
  - File: Documentation/deployment-checklist.md (new)
  - Document step-by-step deployment process and validation checkpoints
  - Include rollback procedures if tap repository integration fails
  - Purpose: Ensure safe and reversible deployment of new architecture
  - _Requirements: 8.4, comprehensive error handling_

- [ ] 32. Final commit and prepare pull request
  - Git: Add and commit Documentation/deployment-checklist.md and any remaining changes
  - Use commit message: "docs: add deployment checklist and rollback procedures for tap integration"
  - Ensure all changes are committed and branch is ready for pull request
  - Purpose: Prepare feature branch for code review and integration
  - _Requirements: Git workflow compliance_

- [ ] 33. Create pull request for external tap integration
  - Git: Create pull request from feature/external-tap-integration to main branch
  - Include comprehensive PR description explaining the architecture change
  - Add checklist of completed tasks and validation steps performed
  - Purpose: Submit feature for code review and integration into main branch
  - _Requirements: Git workflow compliance_

- [ ] 34. Address CI failures and code review feedback
  - Git: Fix any CI test failures or linting issues identified by automated checks
  - Respond to code review feedback and implement requested changes
  - Update documentation or tests as needed based on reviewer suggestions
  - Purpose: Ensure pull request meets all quality standards for integration
  - _Requirements: Git workflow compliance_

- [ ] 35. Monitor and validate first production release
  - Operational task: After PR merge, monitor first release using new workflow
  - Verify metadata generation, webhook delivery, and formula update completion
  - Document any issues encountered and create follow-up issues as needed
  - Purpose: Ensure production deployment works correctly and identify optimization opportunities
  - _Requirements: 8.5, operational requirements_