# Requirements Document

## Introduction

This specification defines the requirements for migrating the usbipd-mac Homebrew formula distribution from the main repository's Formula/ directory to a pull-based external tap repository at https://github.com/beriberikix/homebrew-usbipd-mac. This migration establishes a clean separation of concerns where the main repository publishes releases with metadata, and the tap repository independently monitors and updates the formula.

The pull-based architecture eliminates security complexity by removing the need for the main repository to have write access to the tap repository. Instead, the tap repository monitors releases via webhooks and pulls the necessary information to update the formula, creating a more resilient and maintainable distribution system.

## Alignment with Product Vision

This requirement supports the project's goals of simplified distribution, improved security, and reduced maintenance overhead. By implementing a pull-based model, the project eliminates complex cross-repository authentication while providing users with a standard Homebrew installation experience through `brew tap beriberikix/usbipd-mac`.

## Requirements

### Requirement 1: Release Metadata Publication

**User Story:** As a release automation system, I want to publish structured metadata with each release, so that the tap repository can automatically discover and process new versions.

#### Acceptance Criteria

1. WHEN a release is created THEN the workflow SHALL generate a `homebrew-metadata.json` file containing version, SHA256, and release information
2. WHEN generating metadata THEN the file SHALL include the calculated SHA256 checksum for the GitHub source archive
3. WHEN creating the release THEN the metadata file SHALL be included as a release asset alongside binaries
4. WHEN metadata is generated THEN it SHALL follow a defined JSON schema for consistency
5. IF metadata generation fails THEN the release workflow SHALL fail with clear error messaging

### Requirement 2: Tap Repository Webhook Integration

**User Story:** As a tap repository, I want to be automatically notified of new releases, so that I can update the formula immediately when versions are published.

#### Acceptance Criteria

1. WHEN a release is published in the main repository THEN a webhook SHALL trigger the tap repository update workflow
2. WHEN the webhook is received THEN the tap repository SHALL validate the release contains required metadata
3. WHEN processing a webhook THEN the tap repository SHALL fetch the homebrew-metadata.json from release assets
4. WHEN the webhook payload is invalid THEN the tap repository SHALL log the error and not update the formula
5. IF webhook delivery fails THEN the tap repository SHALL support manual triggering as a fallback

### Requirement 3: Formula Update Automation

**User Story:** As a tap repository workflow, I want to automatically update the formula using release metadata, so that users receive new versions without manual intervention.

#### Acceptance Criteria

1. WHEN processing release metadata THEN the workflow SHALL download the GitHub source archive and verify the SHA256 checksum against metadata
2. WHEN updating the formula THEN the workflow SHALL replace version and checksum placeholders with values from metadata
3. WHEN the formula is updated THEN the workflow SHALL validate Ruby syntax and Homebrew formula structure
4. WHEN validation passes THEN the workflow SHALL commit and push the updated formula to the tap repository
5. IF checksum verification fails THEN the workflow SHALL abort the update and log detailed error information

### Requirement 4: Manual Workflow Operations

**User Story:** As a project maintainer, I want to manually trigger formula updates, so that I can recover from webhook failures or test formula changes.

#### Acceptance Criteria

1. WHEN manual workflow dispatch is triggered THEN the workflow SHALL accept a version parameter to specify which release to process
2. WHEN running manually THEN the workflow SHALL support processing any existing release from the main repository
3. WHEN manual execution completes THEN the workflow SHALL provide detailed status information about the update process
4. WHEN no version is specified THEN the workflow SHALL process the latest release by default
5. IF manual workflow fails THEN detailed error logs SHALL be available for troubleshooting

### Requirement 5: Standalone Recovery Script

**User Story:** As a project maintainer, I want a standalone script for formula updates, so that I can perform local testing and emergency recovery operations.

#### Acceptance Criteria

1. WHEN running the standalone script THEN it SHALL accept command-line parameters for version and repository URLs
2. WHEN executing locally THEN the script SHALL perform the same validation and update logic as the GitHub workflow
3. WHEN running in dry-run mode THEN the script SHALL preview changes without modifying files
4. WHEN the script completes THEN it SHALL provide clear status reporting and next steps
5. IF the script encounters errors THEN it SHALL provide actionable troubleshooting guidance

### Requirement 6: Main Repository Formula Removal

**User Story:** As a project maintainer, I want the Formula/ directory removed from the main repository, so that there is a single source of truth for formula distribution.

#### Acceptance Criteria

1. WHEN the migration is complete THEN the Formula/ directory SHALL be completely removed from the main repository
2. WHEN the migration is complete THEN all formula-related scripts in Scripts/ SHALL be removed or updated appropriately
3. WHEN the migration is complete THEN documentation SHALL be updated to reflect the new tap-based installation process
4. WHEN removing formula scripts THEN any functionality needed for release automation SHALL be preserved
5. IF documentation references the old installation method THEN it SHALL be updated to use the tap repository

### Requirement 7: Metadata Schema Definition

**User Story:** As a system integrator, I want a well-defined metadata schema, so that both repositories can reliably exchange release information.

#### Acceptance Criteria

1. WHEN defining the schema THEN it SHALL include version, sha256, release_notes, and timestamp fields
2. WHEN validating metadata THEN both repositories SHALL enforce the schema requirements
3. WHEN the schema evolves THEN it SHALL maintain backward compatibility with existing releases
4. WHEN schema validation fails THEN clear error messages SHALL indicate the specific validation issues
5. IF metadata is missing required fields THEN the tap repository SHALL reject the update with detailed error information

### Requirement 8: Error Handling and Monitoring

**User Story:** As a project maintainer, I want comprehensive error handling and monitoring, so that formula update failures are quickly identified and resolved.

#### Acceptance Criteria

1. WHEN webhook processing fails THEN the tap repository SHALL log detailed error information with timestamps
2. WHEN formula updates fail THEN the workflow SHALL provide specific error messages for each failure type
3. WHEN network operations fail THEN the workflow SHALL implement retry logic with exponential backoff
4. WHEN validation errors occur THEN the workflow SHALL preserve the existing formula state
5. IF critical errors occur THEN the workflow SHALL support notification mechanisms for immediate attention

## Non-Functional Requirements

### Code Architecture and Modularity
- **Single Responsibility Principle**: Each workflow step should have a single, well-defined purpose for metadata processing or formula updates
- **Modular Design**: Tap repository operations should be isolated into reusable components that can be used by both webhook and manual workflows
- **Dependency Management**: Minimize dependencies between repositories - main repo only publishes metadata, tap repo handles all formula logic
- **Clear Interfaces**: Define clean JSON schema contract between repositories with comprehensive validation

### Performance
- Webhook processing should complete within 60 seconds under normal conditions
- Formula update operations should complete within 2 minutes including validation and push
- Metadata file size should be minimal (<10KB) to ensure fast download and processing
- Repository cloning should use shallow clones to minimize bandwidth usage

### Security
- Tap repository workflows must not require any secrets from the main repository
- Webhook payload validation must prevent malicious or malformed data from corrupting the formula
- All external downloads must verify checksums before processing
- Formula updates must preserve the existing security model and System Extension functionality

### Reliability
- Webhook processing must include retry logic for transient network failures (3 retries with exponential backoff)
- Formula updates must be atomic (either fully succeed or leave the tap repository unchanged)
- Manual workflow dispatch must always be available as a fallback mechanism
- All operations must be idempotent to support safe workflow reruns and recovery scenarios

### Usability
- Error messages must clearly indicate whether the issue is in metadata, network connectivity, or formula validation
- Documentation must provide simple installation instructions: `brew tap beriberikix/usbipd-mac && brew install usbipd-mac`
- Manual workflow dispatch must be accessible through GitHub Actions UI with clear parameter descriptions
- Troubleshooting guides must cover webhook failures, metadata issues, and formula validation problems