# Requirements Document

## Introduction

This specification defines the requirements for migrating from the current webhook-based Homebrew formula update system to using the Justintime50/homebrew-releaser GitHub Action. The current implementation requires complex cross-repository communication, custom retry logic, and manual payload construction, which has proven unreliable. The migration will simplify the release automation by eliminating webhook dependencies and leveraging a proven third-party action for Homebrew formula management.

The homebrew-releaser action is specifically designed to work with external tap repositories by using `homebrew_owner` and `homebrew_tap` parameters to target any GitHub repository, making it fully compatible with the existing `beriberikix/homebrew-usbipd-mac` tap repository structure.

## Alignment with Product Vision

This feature supports the product objectives of reliable automated release processes and developer productivity by:
- Eliminating manual formula update tasks and reducing release friction
- Improving release reliability through battle-tested automation
- Reducing maintenance overhead of custom webhook infrastructure
- Enabling faster recovery from failed releases through simplified workflows

## Requirements

### Requirement 1

**User Story:** As a project maintainer, I want automated Homebrew formula updates that don't depend on webhook reliability, so that releases are published consistently without manual intervention

#### Acceptance Criteria

1. WHEN a new release is tagged THEN the system SHALL automatically update the Homebrew formula using homebrew-releaser action
2. WHEN homebrew-releaser executes THEN the system SHALL target `beriberikix/homebrew-usbipd-mac` repository using homebrew_owner and homebrew_tap parameters
3. WHEN homebrew-releaser executes THEN the system SHALL generate proper formula syntax with correct version, URL, and SHA256
4. WHEN formula updates complete THEN the system SHALL commit changes directly to the homebrew-usbipd-mac repository
5. IF homebrew-releaser fails THEN the system SHALL provide clear error messages and recovery instructions

### Requirement 2

**User Story:** As a project maintainer, I want to remove webhook infrastructure complexity, so that the release system is more maintainable and reliable

#### Acceptance Criteria

1. WHEN migration is complete THEN the system SHALL no longer use repository_dispatch webhooks for formula updates
2. WHEN migration is complete THEN the system SHALL no longer require WEBHOOK_TOKEN secret management
3. WHEN migration is complete THEN the system SHALL remove webhook retry logic and exponential backoff code
4. WHEN migration is complete THEN the system SHALL eliminate cross-repository communication dependencies
5. WHEN migration is complete THEN the system SHALL remove the external tap repository's formula-update.yml workflow

### Requirement 3

**User Story:** As a project maintainer, I want homebrew-releaser integration that follows the existing release workflow patterns, so that the change is transparent to the release process

#### Acceptance Criteria

1. WHEN homebrew-releaser is integrated THEN the system SHALL execute within the existing GitHub Actions release workflow
2. WHEN homebrew-releaser executes THEN the system SHALL use the same release artifacts (binary checksums) as the current system  
3. WHEN homebrew-releaser completes THEN the system SHALL maintain compatibility with existing user installation commands (`brew tap beriberikix/usbipd-mac && brew install usbipd-mac`)
4. WHEN homebrew-releaser targets the tap repository THEN the system SHALL preserve the existing formula structure and naming conventions
5. IF homebrew-releaser fails THEN the system SHALL not block the main release from completing successfully

### Requirement 4

**User Story:** As a developer, I want to validate the migration locally before deployment, so that I can ensure the new system works correctly

#### Acceptance Criteria

1. WHEN testing the migration THEN the system SHALL provide a dry-run mode for homebrew-releaser validation using skip_commit parameter
2. WHEN testing the migration THEN the system SHALL allow validation of formula generation without committing changes to the tap repository
3. WHEN testing the migration THEN the system SHALL enable comparison between old webhook approach and new homebrew-releaser output
4. WHEN testing the migration THEN the system SHALL provide rollback procedures if issues are discovered

### Requirement 5

**User Story:** As a project maintainer, I want proper authentication and permissions configured for homebrew-releaser, so that formula updates can be committed to the tap repository

#### Acceptance Criteria

1. WHEN homebrew-releaser executes THEN the system SHALL authenticate using HOMEBREW_TAP_TOKEN secret with repo permissions
2. WHEN homebrew-releaser executes THEN the system SHALL have write permissions to beriberikix/homebrew-usbipd-mac repository
3. WHEN homebrew-releaser commits changes THEN the system SHALL use appropriate commit author information configured via commit_owner and commit_email parameters
4. WHEN homebrew-releaser accesses the tap repository THEN the system SHALL target the correct repository using homebrew_owner: "beriberikix" and homebrew_tap: "homebrew-usbipd-mac"
5. IF authentication fails THEN the system SHALL provide clear error messages about token configuration

### Requirement 6

**User Story:** As a user installing via Homebrew, I want the tap repository to remain discoverable and functional after the migration, so that installation commands work seamlessly

#### Acceptance Criteria

1. WHEN homebrew-releaser updates the formula THEN the system SHALL maintain the existing tap repository URL structure (github.com/beriberikix/homebrew-usbipd-mac)
2. WHEN users run `brew tap beriberikix/usbipd-mac` THEN the system SHALL continue to work exactly as before the migration
3. WHEN homebrew-releaser commits formula updates THEN the system SHALL preserve the existing Formula/usbipd-mac.rb file location
4. WHEN the migration is complete THEN the system SHALL ensure Homebrew can discover and install the formula without any user-visible changes

## Non-Functional Requirements

### Code Architecture and Modularity
- **Single Responsibility Principle**: Homebrew-releaser integration should be isolated to the release workflow
- **Modular Design**: Formula update logic should be encapsulated within the homebrew-releaser action step
- **Dependency Management**: Minimize dependencies on external services beyond GitHub APIs
- **Clear Interfaces**: Well-defined inputs and outputs for the homebrew-releaser step

### Performance
- Formula updates must complete within 5 minutes of release completion
- No performance degradation to the main release workflow execution time
- Efficient resource usage within GitHub Actions runner limits

### Security
- Secure handling of HOMEBREW_TAP_TOKEN with minimal required permissions (repo scope)
- No exposure of sensitive information in workflow logs or outputs
- Proper secret rotation procedures documented for HOMEBREW_TAP_TOKEN

### Reliability
- 99%+ success rate for formula updates when main release succeeds
- Graceful handling of temporary GitHub API failures
- Clear failure modes that don't affect main release success
- Automated retry capabilities built into homebrew-releaser action