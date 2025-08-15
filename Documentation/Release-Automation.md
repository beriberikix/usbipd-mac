# Release Automation Documentation

This document provides comprehensive guidance for the automated production release system for usbipd-mac, including setup requirements, workflows, procedures, and troubleshooting.

## Overview

The usbipd-mac project uses a sophisticated automated release system built on GitHub Actions that provides:

- **Automated Release Pipeline**: Multi-stage validation, building, and publishing
- **Security Integration**: Code signing with Apple Developer certificates
- **Quality Assurance**: Comprehensive testing and validation before release
- **Artifact Management**: Secure artifact building, signing, and distribution
- **Emergency Procedures**: Fast-track releases with safety controls

## System Architecture

### Release Workflows

The release automation consists of three main GitHub Actions workflows:

1. **Production Release** (`.github/workflows/release.yml`)
   - Triggered by version tags (`v*`) or manual dispatch
   - Full release pipeline with validation, building, and publishing
   - Handles code signing and artifact distribution

2. **Pre-Release Validation** (`.github/workflows/pre-release.yml`)
   - Triggered on pull requests and manual dispatch
   - Three validation levels: quick, comprehensive, release-candidate
   - Ensures code quality before merging

3. **Enhanced CI Integration** (`.github/workflows/ci.yml`)
   - Updated to support release pipeline integration
   - Conditional validation steps for release branches

### Release Preparation Tools

- **Release Preparation Script** (`Scripts/prepare-release.sh`)
  - Local release validation and tag creation
  - Environment checks and prerequisite validation
  - Safe release preparation before automation

- **Release Validation Scripts** (`Tests/ReleaseWorkflowTests/`)
  - Comprehensive testing for GitHub Actions workflows
  - Validation of all trigger conditions and scenarios

## Setup Requirements

### Development Environment Prerequisites

Before using the release system, ensure your development environment has:

#### Required Tools
```bash
# Essential tools
swift --version        # Swift 5.9 or later
git --version         # Git 2.30 or later
swiftlint version     # SwiftLint 0.50 or later

# macOS requirements
# - macOS 11.0 or later for development
# - Xcode 14.0 or later (if using Xcode)
```

#### Project Dependencies
```bash
# Install SwiftLint if not available
brew install swiftlint

# Verify project builds successfully
swift build --configuration release
```

### Repository Configuration

#### GitHub Secrets

Configure the following secrets in your GitHub repository settings (`Settings > Secrets and variables > Actions`):

##### Required Secrets
```bash
GITHUB_TOKEN                    # Automatically provided by GitHub
```

##### Code Signing Secrets (Optional but Recommended)
```bash
DEVELOPER_ID_CERTIFICATE        # Base64-encoded .p12 certificate
DEVELOPER_ID_CERTIFICATE_PASSWORD  # Certificate password
NOTARIZATION_USERNAME          # Apple ID for notarization
NOTARIZATION_PASSWORD         # App-specific password for notarization
```

#### Branch Protection Rules

Configure branch protection for the `main` branch:

1. **Required Status Checks**:
   - `Code Quality (SwiftLint)`
   - `Build Validation`
   - `Unit Tests`
   - `Integration Tests (QEMU)`

2. **Pull Request Requirements**:
   - Require review from code owners
   - Require status checks to pass
   - Require branches to be up to date
   - Dismiss stale reviews

3. **Restrictions**:
   - Restrict pushes to administrators and maintainers
   - Allow force pushes by administrators only

### Apple Developer Setup (Code Signing)

For code signing and notarization:

#### Certificate Setup
1. **Generate Developer ID Certificate**:
   - Log in to Apple Developer portal
   - Navigate to Certificates, Identifiers & Profiles
   - Create Developer ID Application certificate
   - Download the certificate (.cer file)

2. **Export Certificate**:
   ```bash
   # Import certificate to Keychain
   # Export as .p12 file with strong password
   # Convert to base64 for GitHub Secrets
   base64 -i certificate.p12 | pbcopy
   ```

3. **App-Specific Password**:
   - Generate app-specific password for Apple ID
   - Use for `NOTARIZATION_PASSWORD` secret

#### Entitlements Configuration
The project includes pre-configured entitlements:
- `usbipd.entitlements`: Main application entitlements
- `Sources/SystemExtension/SystemExtension.entitlements`: System Extension entitlements

## Release Process

### Standard Release Process

#### 1. Prepare Release Locally

Use the release preparation script to validate readiness:

```bash
# Basic release preparation
./Scripts/prepare-release.sh v1.2.3

# Advanced options
./Scripts/prepare-release.sh v1.2.3 \
  --dry-run \                    # Preview actions without execution
  --skip-tests \                 # Skip test validation (emergency use)
  --force \                      # Override safety checks
  --remote upstream              # Use different remote name
```

The script performs:
- Environment validation (tools, Git repository, clean working tree)
- Version validation (semantic versioning compliance)
- Code quality checks (SwiftLint validation)
- Test execution (development, CI, and production tests)
- Tag creation and pushing

#### 2. Automated Release Pipeline

Once tags are pushed, the automated pipeline executes:

##### Stage 1: Release Validation
- Extracts and validates version information
- Determines if release is pre-release based on version suffix
- Validates semantic versioning compliance

##### Stage 2: Code Quality and Build
- Runs SwiftLint with strict validation
- Performs optimized release build with all architectures
- Caches dependencies for performance

##### Stage 3: Test Validation (Conditional)
- Executes CI test suite for rapid validation
- Runs production tests with CI constraints
- Can be skipped for emergency releases (`skip_tests: true`)

##### Stage 4: Artifact Building
- Builds optimized release binaries (universal binaries)
- Code signs with Apple Developer certificates (if available)
- Creates packaged archives with version naming
- Generates SHA256 checksums for all artifacts

##### Stage 5: Release Creation
- Generates release notes from commit history
- Creates GitHub release with proper categorization
- Uploads all artifacts with checksums
- Handles both stable and pre-release versions

##### Stage 6: Post-Release Validation
- Verifies release accessibility and artifact availability
- Provides comprehensive success reporting
- Triggers any post-release notifications

### Manual Release Dispatch

For testing or special circumstances, use manual workflow dispatch:

```bash
# Via GitHub web interface:
# 1. Navigate to Actions > Production Release
# 2. Click "Run workflow"
# 3. Configure parameters:
#    - Version: v1.2.3
#    - Pre-release: true/false
#    - Skip tests: true/false (emergency only)
```

### Pre-Release Testing

Use the pre-release validation workflow for testing:

#### Quick Validation (Pull Requests)
Automatically runs on all pull requests:
- Code quality validation
- Build verification
- Development test suite

#### Comprehensive Validation (Manual)
```bash
# Via GitHub web interface:
# Actions > Pre-Release Validation > Run workflow
# Validation level: comprehensive
```

#### Release Candidate Validation (Pre-Release)
```bash
# Full release preparation testing:
# Actions > Pre-Release Validation > Run workflow
# Validation level: release-candidate
```

## Workflow Configuration

### Release Workflow Features

#### Trigger Options
- **Automatic**: Git tags matching `v*` pattern
- **Manual Dispatch**: Configurable version and options
- **Emergency Mode**: Skip tests for urgent releases

#### Build Configuration
- **Universal Binaries**: ARM64 + x86_64 architectures
- **Optimization**: Release configuration with full optimization
- **Code Signing**: Automatic signing with Developer ID certificates
- **Notarization**: Apple notarization for trusted distribution

#### Artifact Management
- **Versioned Naming**: All artifacts include version numbers
- **Integrity Verification**: SHA256 checksums for all files
- **Archive Creation**: Compressed archives for easy distribution
- **Retention**: 30-day artifact retention for debugging

### Environment Variables

#### GitHub Actions Environment
```yaml
GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
DEVELOPER_ID_CERTIFICATE: ${{ secrets.DEVELOPER_ID_CERTIFICATE }}
DEVELOPER_ID_CERTIFICATE_PASSWORD: ${{ secrets.DEVELOPER_ID_CERTIFICATE_PASSWORD }}
NOTARIZATION_USERNAME: ${{ secrets.NOTARIZATION_USERNAME }}
NOTARIZATION_PASSWORD: ${{ secrets.NOTARIZATION_PASSWORD }}
```

#### Local Development Environment
```bash
# Test environment configuration
export TEST_ENVIRONMENT=ci
export QEMU_TEST_MODE=mock
export ENABLE_QEMU_TESTS=false

# Release preparation options
export RELEASE_DRY_RUN=true
export SKIP_CODE_SIGNING=true  # For testing without certificates
```

## Version Management

### Semantic Versioning

The project follows strict semantic versioning (SemVer):

#### Version Format
```bash
# Stable releases
v1.2.3          # Major.Minor.Patch

# Pre-releases
v1.2.3-alpha.1  # Alpha version
v1.2.3-beta.2   # Beta version
v1.2.3-rc.1     # Release candidate
```

#### Version Rules
- **Major** (X): Breaking changes
- **Minor** (Y): New features (backward compatible)
- **Patch** (Z): Bug fixes (backward compatible)
- **Pre-release**: Development versions with suffixes

#### Pre-release Detection
The system automatically detects pre-releases based on version suffixes:
- Versions containing `-alpha`, `-beta`, or `-rc` are marked as pre-releases
- Pre-releases are published with the "pre-release" flag in GitHub

### Changelog Management

#### Automatic Generation
Release notes are automatically generated from Git commit history:
- Includes commits since the previous release
- Limited to 20 most recent commits for readability
- Uses conventional commit messages for better formatting

#### Manual Enhancement
For important releases, enhance auto-generated notes:
1. Create release locally using preparation script
2. Edit release notes in GitHub after creation
3. Add detailed feature descriptions and breaking changes

## Testing Strategy

### Test Environment Integration

The release system integrates with the project's three-tier testing strategy:

#### Development Tests (Fast Feedback)
```bash
# Executed during: Local preparation, quick validation
./Scripts/run-development-tests.sh
# Duration: <1 minute
# Purpose: Rapid feedback during development
```

#### CI Tests (Automation Compatible)
```bash
# Executed during: All validation levels, release pipeline
./Scripts/run-ci-tests.sh
# Duration: <3 minutes  
# Purpose: Reliable automated validation
```

#### Production Tests (Comprehensive)
```bash
# Executed during: Release candidate validation, full releases
./Scripts/run-production-tests.sh --no-qemu --no-system-extension --no-hardware --timeout 300
# Duration: <5 minutes (with CI constraints)
# Purpose: Release readiness validation
```

### Release-Specific Testing

#### Workflow Validation Tests
Comprehensive testing of GitHub Actions workflows:
- **Location**: `Tests/ReleaseWorkflowTests/`
- **Framework**: Uses `act` for local GitHub Actions testing
- **Coverage**: All trigger conditions, error scenarios, artifact generation

#### Shell Script Testing
Testing of release preparation scripts:
- **Location**: `Tests/Scripts/prepare-release-tests.sh`
- **Coverage**: Version validation, environment checks, Git operations

#### Integration Testing
End-to-end release pipeline testing:
- **Manual Testing**: Using test repositories and branches
- **Automated Validation**: Workflow configuration validation
- **Error Scenario Testing**: Intentional failures to validate error handling

## Troubleshooting

### Common Issues

#### Release Preparation Failures

**Issue**: `prepare-release.sh` fails with "dirty working tree"
```bash
# Solution: Commit or stash pending changes
git status                    # Check working tree status
git stash                    # Stash changes temporarily
./Scripts/prepare-release.sh v1.2.3
git stash pop               # Restore changes after release
```

**Issue**: SwiftLint violations prevent release
```bash
# Solution: Fix violations or use emergency bypass
swiftlint lint --strict     # Identify violations
swiftlint --fix            # Auto-fix where possible
# Or for emergency:
./Scripts/prepare-release.sh v1.2.3 --skip-lint --force
```

**Issue**: Test failures block release
```bash
# Solution: Fix tests or use emergency bypass
./Scripts/run-ci-tests.sh   # Run tests locally
# Fix failing tests, or for emergency:
./Scripts/prepare-release.sh v1.2.3 --skip-tests --force
```

#### GitHub Actions Failures

**Issue**: Code signing failures
```bash
# Check secrets configuration:
# 1. Verify DEVELOPER_ID_CERTIFICATE is valid base64
# 2. Confirm certificate password is correct
# 3. Ensure certificate hasn't expired
# 4. Check Apple Developer account status
```

**Issue**: Artifact upload failures
```bash
# Solutions:
# 1. Retry the workflow (temporary GitHub issues)
# 2. Check artifact size limits
# 3. Verify repository permissions
# 4. Review GitHub Actions status page
```

**Issue**: Test timeout in CI environment
```bash
# Solutions:
# 1. Increase timeout values in workflow
# 2. Optimize test execution for CI constraints
# 3. Use emergency release with skip_tests for urgent fixes
```

#### Version and Tagging Issues

**Issue**: Tag already exists
```bash
# Solution: Use different version or force update
git tag -d v1.2.3           # Delete local tag
git push origin :refs/tags/v1.2.3  # Delete remote tag
./Scripts/prepare-release.sh v1.2.4  # Use new version
```

**Issue**: Invalid version format
```bash
# Ensure semantic versioning compliance:
✓ v1.2.3                   # Correct format
✓ v1.2.3-alpha.1          # Pre-release format
✗ 1.2.3                   # Missing 'v' prefix
✗ v1.2                    # Missing patch version
✗ v1.2.3.4                # Too many version segments
```

### Emergency Procedures

#### Emergency Release Process

For critical security fixes or urgent bug fixes:

1. **Bypass Safety Checks (Use Carefully)**:
```bash
# Local preparation with safety bypasses
./Scripts/prepare-release.sh v1.2.4 \
  --skip-tests \
  --skip-lint \
  --force
```

2. **Manual Workflow Dispatch**:
   - Use GitHub Actions web interface
   - Set `skip_tests: true` for faster release
   - Monitor workflow execution closely

3. **Post-Emergency Validation**:
   - Verify release artifacts integrity
   - Test critical functionality manually
   - Create follow-up issues for any bypassed validations

#### Rollback Procedures

**If Release Fails Mid-Pipeline**:
```bash
# 1. Delete failed release if created
gh release delete v1.2.3 --yes

# 2. Delete tag if pushed
git push origin :refs/tags/v1.2.3
git tag -d v1.2.3

# 3. Fix issues and retry
# Address root cause, then re-run preparation
```

**If Release Succeeds but Has Issues**:
```bash
# 1. Create hotfix release
./Scripts/prepare-release.sh v1.2.4

# 2. Mark problematic release as pre-release (if applicable)
gh release edit v1.2.3 --prerelease

# 3. Document issues in release notes
gh release edit v1.2.3 --notes "⚠️ Known Issues: [describe issues]"
```

### Debugging Workflow Issues

#### Local Workflow Testing

Use `act` to test GitHub Actions locally:
```bash
# Install act (if not available)
brew install act

# Test release workflow
act push --secret-file .secrets

# Test pre-release workflow  
act pull_request
```

#### Workflow Logs Analysis

Key areas to examine in failed workflows:
1. **Job Dependencies**: Check if jobs are properly dependent
2. **Environment Setup**: Verify tool installations and caching
3. **Secret Access**: Confirm secrets are available and valid
4. **Artifact Paths**: Check file paths and permissions
5. **Network Issues**: Look for timeout or connectivity problems

#### Performance Monitoring

Monitor workflow performance:
- **Expected Duration**: Complete pipeline ~10-15 minutes
- **Performance Bottlenecks**: 
  - SwiftLint: ~30 seconds
  - Build: ~2-3 minutes
  - Tests: ~3-5 minutes
  - Artifacts: ~1-2 minutes

## Security Considerations

### Code Signing Security

#### Certificate Management
- Store certificates as encrypted secrets only
- Use strong passwords for certificate protection
- Rotate certificates before expiration
- Monitor Apple Developer account for security alerts

#### Signing Process
- Code signing occurs in isolated GitHub Actions environment
- Certificates are loaded only during signing process
- No certificate data is logged or persisted
- Failed signing produces warnings, not failures (graceful degradation)

### Access Control

#### Repository Permissions
- Only maintainers can trigger manual releases
- Branch protection prevents unauthorized releases
- All release actions are logged and auditable

#### Secret Management
- Secrets are scoped to specific workflows
- No secret data appears in logs
- Regular rotation of app-specific passwords
- Two-factor authentication required for Apple ID

### Artifact Security

#### Integrity Verification
- SHA256 checksums for all release artifacts
- Code signing with Apple Developer certificates
- Notarization for additional trust validation

#### Distribution Security
- GitHub Releases provide secure distribution
- HTTPS-only download links
- Artifact retention limits reduce exposure window

## Maintenance and Updates

### Regular Maintenance Tasks

#### Monthly Reviews
- Review workflow performance metrics
- Update dependencies in GitHub Actions
- Verify code signing certificate status
- Check Apple Developer account standing

#### Quarterly Updates
- Update macOS runner versions as available
- Review and update Swift version requirements
- Audit branch protection rules
- Review and clean up old releases

### System Updates

#### GitHub Actions Updates
Monitor and update action versions:
```yaml
# Regular updates needed:
- uses: actions/checkout@v4      # Keep current
- uses: actions/cache@v3         # Monitor for v4
- uses: actions/upload-artifact@v4  # Keep current
```

#### Tool Version Updates
```bash
# Swift updates
# Update Package.swift tools version when needed
# Test compatibility before updating CI

# SwiftLint updates  
# Update .swiftlint.yml configuration as needed
# Test rule changes impact on codebase
```

### Performance Optimization

#### Workflow Optimization
- Monitor cache hit rates and adjust cache keys
- Optimize parallel job execution
- Review artifact retention policies
- Consider workflow concurrency limits

#### Testing Optimization
- Profile test execution times
- Optimize slow tests for CI environment
- Balance test coverage with execution time
- Monitor QEMU integration performance

## Best Practices

### Release Planning

#### Version Planning
- Plan version numbers in advance
- Coordinate with feature development cycles  
- Consider semantic versioning impact on users
- Document breaking changes thoroughly

#### Release Timing
- Avoid releases on Fridays or before holidays
- Coordinate with major dependency updates
- Plan for sufficient testing and validation time
- Consider user adoption patterns

### Quality Assurance

#### Pre-Release Validation
- Always run comprehensive validation before releases
- Test on clean environments when possible
- Validate with different macOS versions
- Test installation and upgrade scenarios

#### Documentation
- Keep release notes informative and user-focused
- Document breaking changes and migration steps
- Include installation and upgrade instructions
- Maintain changelog with detailed history

### Team Coordination

#### Release Responsibilities
- Designate release managers for coordination
- Document release procedures for team members
- Establish communication channels for release status
- Plan for coverage during absences

#### Emergency Response
- Define escalation procedures for failed releases
- Maintain emergency contact information
- Document rollback procedures and responsibilities
- Practice emergency scenarios periodically

---

## Quick Reference

### Essential Commands

```bash
# Release preparation
./Scripts/prepare-release.sh v1.2.3

# Local validation
swiftlint lint --strict
swift build --configuration release  
./Scripts/run-ci-tests.sh

# Emergency release
./Scripts/prepare-release.sh v1.2.4 --skip-tests --force

# Release management
gh release list
gh release view v1.2.3
gh release delete v1.2.3
```

### Key Files and Locations

```
.github/workflows/
├── release.yml              # Main production release workflow
├── pre-release.yml         # Pre-release validation workflow
└── ci.yml                 # Enhanced CI with release integration

Scripts/
├── prepare-release.sh      # Release preparation script
├── run-ci-tests.sh        # CI test execution
└── run-production-tests.sh # Production test execution

Documentation/
├── Release-Automation.md   # This document
└── Code-Signing-Setup.md  # Code signing documentation (planned)
```

### Support and Resources

- **GitHub Actions Status**: https://www.githubstatus.com/
- **Apple Developer Portal**: https://developer.apple.com/
- **Swift Package Manager**: https://swift.org/package-manager/
- **SwiftLint Configuration**: https://realm.github.io/SwiftLint/

For project-specific questions or issues, consult project maintainers or create issues in the repository.