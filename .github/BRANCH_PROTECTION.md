# Branch Protection and Status Checks

This document describes the branch protection rules and approval requirements configured for the usbipd-mac repository to ensure code quality and prevent broken code from being merged.

## Overview

The `main` branch is protected with comprehensive rules that require all code changes to pass automated checks before merging. These protections ensure that:

- Code meets quality standards (SwiftLint validation)
- Project builds successfully on macOS
- All unit tests pass
- Integration tests with QEMU validate end-to-end functionality
- Pull requests are reviewed before merging
- Administrators cannot bypass checks without explicit approval

## Required Status Checks

All pull requests must pass the following status checks before merging:

### 1. Code Quality (SwiftLint)
- **Purpose**: Validates Swift code style and quality
- **Requirements**: No SwiftLint violations in strict mode
- **Configuration**: Uses project's `.swiftlint.yml` rules
- **Failure Action**: Merge blocked until violations are fixed

### 2. Build Validation
- **Purpose**: Ensures project compiles successfully
- **Requirements**: Swift Package Manager build must succeed
- **Environment**: Latest macOS and Swift versions
- **Failure Action**: Merge blocked until build errors are resolved

### 3. Unit Tests
- **Purpose**: Validates functionality through automated tests
- **Requirements**: All unit tests must pass
- **Coverage**: USBIPDCore and USBIPDCLI test suites
- **Failure Action**: Merge blocked until failing tests are fixed

### 4. Integration Tests (QEMU)
- **Purpose**: Validates end-to-end system functionality
- **Requirements**: QEMU test server validation must succeed
- **Coverage**: Complete protocol flow and network communication
- **Failure Action**: Merge blocked until integration issues are resolved

## Pull Request Requirements

### Review Requirements
- **Minimum reviewers**: 1 approved review required
- **Stale review dismissal**: Enabled (reviews dismissed on new commits)
- **Code owner reviews**: Enabled if CODEOWNERS file exists
- **Last push approval**: Not required (allows self-approval after addressing feedback)

### Branch Requirements
- **Up-to-date requirement**: Branches must be current with main before merging
- **Linear history**: Merge commits or squash merging preferred
- **Force push protection**: Force pushes to main branch are blocked

## Administrator Bypass Rules

### Bypass Permissions
- **Administrator bypass**: Enabled for emergency situations
- **Approval requirement**: Administrator approval required for bypassing checks
- **Audit trail**: All bypass actions are logged and tracked

### When Bypass May Be Used
- Critical security fixes requiring immediate deployment
- Infrastructure emergencies affecting CI/CD pipeline
- Hotfixes for production-breaking issues

### Bypass Process
1. Administrator identifies need for bypass
2. Documents reason for bypass in pull request
3. Obtains explicit approval from another administrator
4. Merges with bypass, ensuring immediate follow-up to address any issues

## Configuration Management

### Automated Configuration
Use the provided script to configure branch protection rules:

```bash
# Configure branch protection rules automatically
./.github/scripts/configure-branch-protection.sh
```

### Manual Configuration
1. Navigate to repository **Settings** → **Branches**
2. Add or edit rule for `main` branch
3. Configure settings as documented in `.github/branch-protection-config.md`
4. Save and verify configuration

### Validation
Validate current configuration using the validation workflow:

```bash
# Trigger validation workflow manually
gh workflow run validate-branch-protection.yml
```

## Status Check Integration

### GitHub Actions Integration
- Status checks are automatically reported by CI workflow
- Check names match job names in `.github/workflows/ci.yml`
- Detailed status messages provide actionable feedback
- Parallel execution optimizes feedback time

### Status Reporting
Each status check provides:
- **Clear success/failure indication**
- **Detailed error messages with line numbers**
- **Actionable guidance for fixing issues**
- **Links to relevant documentation**

## Troubleshooting

### Common Issues

#### Status Checks Not Required
**Problem**: Pull requests can be merged despite failing checks
**Solution**: Verify required status checks are configured correctly
```bash
# Validate configuration
./.github/workflows/validate-branch-protection.yml
```

#### Missing Status Checks
**Problem**: Some CI jobs don't appear as required checks
**Solution**: Ensure job names in workflow match required check names
- Check `.github/workflows/ci.yml` job names
- Verify names in branch protection settings match exactly

#### Administrator Bypass Not Working
**Problem**: Administrators cannot bypass checks when needed
**Solution**: Verify bypass settings are properly configured
- Ensure "Allow administrators to bypass" is enabled
- Confirm approval requirements are set appropriately

### Getting Help

1. **Documentation**: Review `.github/branch-protection-config.md`
2. **Validation**: Run validation workflow to check configuration
3. **Manual Check**: Visit GitHub Settings → Branches to verify rules
4. **Support**: Contact repository administrators for assistance

## Best Practices

### For Developers
- Run checks locally before pushing: `swift test && swiftlint`
- Keep pull requests focused and atomic
- Address feedback promptly to avoid stale review dismissal
- Ensure branches are up-to-date before requesting review

### For Reviewers
- Verify all status checks pass before approving
- Review both code changes and test coverage
- Consider impact on system integration and compatibility
- Provide constructive feedback for improvement

### For Administrators
- Use bypass sparingly and only for genuine emergencies
- Document bypass reasons thoroughly
- Follow up on bypassed changes to ensure quality
- Regularly review and update protection rules as needed

## Compliance and Auditing

### Audit Trail
- All merge attempts are logged with status check results
- Bypass actions are recorded with administrator approval
- Pull request history maintains complete change tracking
- CI workflow logs provide detailed execution records

### Compliance Verification
- Regular validation of branch protection configuration
- Monitoring of bypass usage and justification
- Review of status check effectiveness and coverage
- Assessment of code quality trends and improvements