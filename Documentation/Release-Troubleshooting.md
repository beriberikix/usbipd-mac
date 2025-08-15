# Release Workflow Troubleshooting Guide

This comprehensive guide provides solutions for common issues encountered during the automated release workflow, including diagnostic procedures, resolution steps, workflow debugging, and manual intervention procedures.

## Overview

The usbipd-mac automated release system consists of multiple interconnected components:

- **GitHub Actions Workflows**: Release, pre-release, monitoring, and security scanning
- **Release Scripts**: Preparation, validation, rollback, and benchmarking utilities
- **Testing Framework**: Environment-specific test execution and validation
- **Documentation System**: Release notes, troubleshooting guides, and user communication
- **Security Integration**: Code signing, vulnerability scanning, and artifact validation
- **Monitoring System**: Status tracking, performance metrics, and alerting

When issues occur, they can cascade across multiple components. This guide helps identify root causes and provides targeted solutions.

## Quick Diagnosis

### Status Check Commands

Use these commands to quickly assess the current state of the release system:

```bash
# Check overall system health
./Scripts/release-status-dashboard.sh --summary

# Verify Git repository state
git status
git log --oneline -5
git describe --tags

# Check GitHub Actions workflow status
gh run list --limit 5
gh workflow list

# Validate release scripts
ls -la Scripts/*.sh | grep -E "(prepare|validate|rollback|benchmark)"

# Check test environment
./Scripts/test-environment-setup.sh validate

# Verify documentation completeness
find Documentation/ -name "*Release*" -o -name "*release*"
```

### Common Symptoms and Quick Fixes

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| Workflow fails immediately | Syntax error in YAML | `yamllint .github/workflows/release.yml` |
| Build fails in workflow | Dependency or environment issue | Check `gh run view --log` for details |
| Tests timeout | Resource constraints or hanging tests | Review test timeouts in workflow |
| Code signing fails | Certificate or secret configuration | Verify `Documentation/Code-Signing-Setup.md` |
| Artifact upload fails | Network or permission issue | Check GitHub storage limits |
| Rollback doesn't work | Git state or permission issue | Verify Git repository integrity |

## GitHub Actions Workflow Issues

### Workflow Execution Failures

#### Workflow Won't Start

**Symptoms:**
- No workflow run appears after pushing tag
- Manual workflow dispatch fails
- Workflow shows as "waiting" indefinitely

**Diagnosis:**
```bash
# Check workflow syntax
yamllint .github/workflows/release.yml
yamllint .github/workflows/pre-release.yml

# Verify trigger conditions
grep -A 10 "^on:" .github/workflows/release.yml

# Check repository settings
gh api repos/{owner}/{repo}/actions/permissions

# Verify branch protection rules
gh api repos/{owner}/{repo}/branches/main/protection
```

**Solutions:**
```bash
# Fix YAML syntax errors
# Edit .github/workflows/release.yml to fix syntax issues

# Re-trigger workflow manually
gh workflow run release.yml -f version=v1.2.3

# Check GitHub Actions permissions
# Go to repository Settings > Actions > General
# Ensure "Allow all actions and reusable workflows" is selected

# Verify tag format
git tag --list | grep -E "^v[0-9]+\.[0-9]+\.[0-9]+$"
```

#### Build Failures in Workflow

**Symptoms:**
- Workflow starts but fails during build step
- "swift build" command fails
- Dependency resolution errors

**Diagnosis:**
```bash
# Check workflow logs
gh run list --limit 1
gh run view [run-id] --log | grep -A 20 -B 20 "error"

# Test build locally
swift package clean
swift build --configuration release --verbose

# Check dependency conflicts
swift package show-dependencies
swift package resolve
```

**Solutions:**
```bash
# Clean build environment
git add .
git commit -m "fix: resolve build dependencies for release workflow"

# Update Package.swift if needed
# Fix any dependency version conflicts

# Test build configuration
swift build --configuration release
swift test --parallel

# Push fixes
git push origin main

# Re-trigger workflow
gh workflow run release.yml -f version=v1.2.3
```

#### Test Failures in Workflow

**Symptoms:**
- Build succeeds but tests fail
- Timeout errors in test execution
- Environment-specific test failures

**Diagnosis:**
```bash
# Check test output in workflow logs
gh run view [run-id] --log | grep -A 30 "test.*failed"

# Run tests locally with same configuration
./Scripts/run-ci-tests.sh

# Check test environment
TEST_ENVIRONMENT=ci swift test --parallel --verbose

# Verify test timeouts
grep -r "timeout" Tests/ | grep -v ".git"
```

**Solutions:**
```bash
# Fix test issues locally first
swift test --parallel --verbose

# Address environment-specific failures
# Update test configurations in Tests/SharedUtilities/TestEnvironmentConfig.swift

# Adjust test timeouts if needed
# Edit .github/workflows/release.yml to increase timeout values

# Skip problematic tests temporarily (emergency only)
swift test --filter "^(?!.*ProblematicTest).*$"

# Commit fixes
git add Tests/
git commit -m "fix: resolve test failures in release workflow"
git push origin main
```

### Code Signing and Security Issues

#### Code Signing Failures

**Symptoms:**
- Workflow fails at code signing step
- "codesign failed" errors
- Certificate validation errors

**Diagnosis:**
```bash
# Check certificate availability in workflow
# Review GitHub Secrets configuration

# Verify local code signing capability
codesign --display --verbose=4 .build/release/usbipd

# Check certificate validity
security find-identity -v -p codesigning

# Review code signing setup documentation
cat Documentation/Code-Signing-Setup.md
```

**Solutions:**
```bash
# Update GitHub Secrets
# Go to repository Settings > Secrets and variables > Actions
# Verify these secrets exist and are current:
# - DEVELOPER_ID_CERTIFICATE
# - DEVELOPER_ID_CERTIFICATE_PASSWORD
# - NOTARIZATION_USERNAME
# - NOTARIZATION_PASSWORD

# Test code signing locally
codesign --force --sign "Developer ID Application: Your Name" .build/release/usbipd

# For emergency releases, skip code signing temporarily
gh workflow run release.yml -f version=v1.2.3 -f skip_code_signing=true

# Update certificate if expired
# Follow Documentation/Code-Signing-Setup.md procedures
```

#### Security Scanning Failures

**Symptoms:**
- Security scanning workflow fails
- Vulnerability detection errors
- Dependency scanning timeouts

**Diagnosis:**
```bash
# Check security workflow logs
gh run view [security-run-id] --log

# Run security scan locally
if command -v safety >/dev/null; then
    safety check
fi

# Check for known vulnerabilities
npm audit # if package.json exists
swift package audit # if available

# Review dependency versions
swift package show-dependencies
```

**Solutions:**
```bash
# Update vulnerable dependencies
swift package update

# Address specific vulnerabilities
# Review and update Package.swift dependencies

# Temporarily skip security scanning (emergency only)
gh workflow run release.yml -f version=v1.2.3 -f skip_security_scan=true

# Document security scan bypasses
git add Documentation/
git commit -m "docs: document security scan bypass for emergency release"
```

### Artifact and Release Issues

#### Artifact Upload Failures

**Symptoms:**
- Workflow completes but no artifacts uploaded
- "Upload failed" errors
- GitHub release not created

**Diagnosis:**
```bash
# Check workflow artifact upload logs
gh run view [run-id] --log | grep -A 10 -B 10 "upload"

# Verify artifact generation
ls -la .build/release/

# Check GitHub storage limits
gh api user/installations | jq '.installations[0].account.plan'

# Verify release workflow permissions
gh api repos/{owner}/{repo}/actions/permissions
```

**Solutions:**
```bash
# Manually create release if workflow succeeded
gh release create v1.2.3 \
  --title "Release v1.2.3" \
  --notes "$(cat RELEASE_NOTES.md)" \
  .build/release/usbipd \
  .build/release/QEMUTestServer

# Check artifact sizes
find .build/release -type f -exec ls -lh {} \; | sort -k5 -hr

# Clean up large artifacts if needed
# Remove unnecessary debug symbols or temporary files

# Re-run workflow with artifact debugging
gh workflow run release.yml -f version=v1.2.3 -f debug_artifacts=true
```

#### Release Notes Generation Issues

**Symptoms:**
- Release created without proper notes
- Changelog generation fails
- Missing or incorrect version information

**Diagnosis:**
```bash
# Check changelog generation
./Scripts/update-changelog.sh --dry-run v1.2.3

# Verify Git history
git log --oneline $(git describe --tags --abbrev=0)..HEAD

# Check release notes template
cat .github/RELEASE_TEMPLATE.md 2>/dev/null || echo "Template not found"
```

**Solutions:**
```bash
# Generate changelog manually
git log --pretty=format:"- %s" $(git describe --tags --abbrev=0)..HEAD > CHANGELOG.md

# Update release with proper notes
gh release edit v1.2.3 --notes-file CHANGELOG.md

# Fix changelog script
./Scripts/update-changelog.sh v1.2.3

# Commit changelog updates
git add CHANGELOG.md
git commit -m "docs: update changelog for v1.2.3"
```

## Release Script Issues

### Script Execution Failures

#### Permission and Executable Issues

**Symptoms:**
- "Permission denied" when running scripts
- Scripts not found or not executable
- Import/dependency errors in scripts

**Diagnosis:**
```bash
# Check script permissions
ls -la Scripts/ | grep -E "(prepare|validate|rollback)"

# Verify script syntax
bash -n Scripts/prepare-release.sh
bash -n Scripts/validate-release-artifacts.sh

# Check script dependencies
which gh
which git
which shasum
which tar
```

**Solutions:**
```bash
# Fix script permissions
chmod +x Scripts/*.sh

# Repair specific scripts
chmod +x Scripts/prepare-release.sh
chmod +x Scripts/validate-release-artifacts.sh
chmod +x Scripts/rollback-release.sh

# Commit permission fixes
git add Scripts/
git commit -m "fix: restore executable permissions for release scripts"

# Install missing dependencies
brew install gh  # GitHub CLI
# Ensure other tools are available in PATH
```

#### Script Parameter and Validation Errors

**Symptoms:**
- Scripts reject valid parameters
- Version validation fails
- Environment detection errors

**Diagnosis:**
```bash
# Test script help output
./Scripts/prepare-release.sh --help
./Scripts/validate-release-artifacts.sh --help

# Test with dry-run
./Scripts/prepare-release.sh --dry-run v1.2.3

# Check environment detection
./Scripts/test-environment-setup.sh validate

# Verify version format
echo "v1.2.3" | grep -E "^v[0-9]+\.[0-9]+\.[0-9]+$"
```

**Solutions:**
```bash
# Fix version format issues
# Use semantic versioning: v1.2.3, not 1.2.3 or v1.2.3-beta

# Update script parameter handling
# Edit Scripts/prepare-release.sh to fix validation logic

# Test environment setup
./Scripts/test-environment-setup.sh install-help

# Run scripts with verbose output
./Scripts/prepare-release.sh --verbose v1.2.3
```

### Git and Version Control Issues

#### Tag and Branch Problems

**Symptoms:**
- Git tag already exists
- Branch conflicts during release
- Merge conflicts in release branch

**Diagnosis:**
```bash
# Check existing tags
git tag --list | grep v1.2.3

# Verify current branch state
git status
git branch -v

# Check for conflicts
git log --oneline --graph main..HEAD

# Verify remote synchronization
git fetch origin
git status
```

**Solutions:**
```bash
# Remove conflicting tag
git tag -d v1.2.3
git push origin --delete v1.2.3

# Clean up branch state
git checkout main
git pull origin main
git branch -D feature/release-branch  # if needed

# Resolve merge conflicts
git merge main
# Edit conflicting files
git add .
git commit -m "fix: resolve merge conflicts for release"

# Create clean release
./Scripts/prepare-release.sh v1.2.4  # increment version
```

#### Repository State Issues

**Symptoms:**
- Uncommitted changes blocking release
- Dirty working directory
- Missing required files

**Diagnosis:**
```bash
# Check repository cleanliness
git status --porcelain

# Verify required files exist
find . -name "Package.swift" -o -name "README.md" -o -name "LICENSE"

# Check for untracked important files
git ls-files --others --exclude-standard
```

**Solutions:**
```bash
# Commit pending changes
git add .
git commit -m "fix: commit pending changes before release"

# Stash temporary changes
git stash push -m "temporary changes during release"

# Clean untracked files (be careful!)
git clean -fd  # Remove untracked files and directories

# Restore repository to clean state
git checkout .
git pull origin main
```

## Testing Framework Issues

### Test Environment Problems

#### Environment Detection Failures

**Symptoms:**
- Tests skip due to environment detection
- Capability detection errors
- Mock system not working correctly

**Diagnosis:**
```bash
# Check environment detection
swift run -c debug --package-path Tests/SharedUtilities TestEnvironmentDetector

# Verify environment variables
env | grep -E "(CI|GITHUB|TEST_)"

# Test capability detection
./Scripts/test-environment-setup.sh validate

# Check test environment configuration
cat Tests/SharedUtilities/TestEnvironmentConfig.swift | grep -A 20 "detectCurrentEnvironment"
```

**Solutions:**
```bash
# Override environment detection
export TEST_ENVIRONMENT=production
swift test --parallel

# Fix capability detection
# Edit Tests/SharedUtilities/TestEnvironmentConfig.swift

# Force environment for testing
TEST_ENVIRONMENT=ci ./Scripts/run-ci-tests.sh

# Update environment configuration
git add Tests/SharedUtilities/
git commit -m "fix: improve test environment detection"
```

#### Test Execution Timeouts

**Symptoms:**
- Tests timeout in CI environment
- Long-running integration tests fail
- QEMU tests hang

**Diagnosis:**
```bash
# Check test execution times
swift test --parallel --verbose 2>&1 | grep "Test Case.*passed" | sort -k4 -n

# Identify slow tests
./Scripts/benchmark-release-performance.sh --test-analysis

# Check timeout configurations
grep -r "timeout" .github/workflows/
grep -r "timeout" Tests/
```

**Solutions:**
```bash
# Increase timeout in workflows
# Edit .github/workflows/release.yml
# Change: timeout-minutes: 30 to timeout-minutes: 45

# Optimize slow tests
# Review and optimize test implementations
# Add parallel execution where appropriate

# Skip time-intensive tests in CI (temporary)
swift test --filter "^(?!.*QEMUIntegrationTests).*$"

# Update test timeouts
# Edit Tests/SharedUtilities/TestEnvironmentConfig.swift
# Increase timeout values for specific test categories
```

### Mock and Integration Test Issues

#### Mock System Failures

**Symptoms:**
- Mock objects not working as expected
- Integration tests failing in CI
- Inconsistent test results

**Diagnosis:**
```bash
# Check mock implementation
find Tests/TestMocks/ -name "*.swift" -exec grep -l "Mock" {} \;

# Verify mock configuration for environment
ls Tests/TestMocks/CI/
ls Tests/TestMocks/Development/
ls Tests/TestMocks/Production/

# Test mock system directly
swift test --filter "MockTests" --verbose
```

**Solutions:**
```bash
# Update mock implementations
# Edit Tests/TestMocks/CI/MockSystemExtension.swift
# Ensure mocks properly simulate real behavior

# Fix mock configuration
# Edit Tests/SharedUtilities/TestEnvironmentConfig.swift
# Update mock selection logic

# Test mock system independently
swift test --filter "TestMocks" --parallel

# Commit mock fixes
git add Tests/TestMocks/
git commit -m "fix: improve mock system reliability"
```

## Documentation and Communication Issues

### Documentation Completeness

#### Missing or Outdated Documentation

**Symptoms:**
- Links to non-existent documentation
- Outdated installation instructions
- Missing troubleshooting information

**Diagnosis:**
```bash
# Check documentation completeness
find Documentation/ -name "*.md" -exec wc -l {} \; | sort -n

# Verify links in documentation
grep -r "http" Documentation/ | grep -v "localhost"

# Check for TODO or FIXME markers
grep -r -i "todo\|fixme\|xxx" Documentation/

# Validate markdown syntax
if command -v markdownlint >/dev/null; then
    markdownlint Documentation/
fi
```

**Solutions:**
```bash
# Update documentation
# Edit relevant .md files in Documentation/

# Fix broken links
# Update URLs and paths in documentation

# Add missing documentation
cp Documentation/template.md Documentation/New-Feature.md
# Edit new documentation file

# Commit documentation updates
git add Documentation/
git commit -m "docs: update release documentation and fix broken links"
```

### Release Communication Issues

#### GitHub Release Notes Problems

**Symptoms:**
- Release created without proper description
- Missing installation instructions
- Broken links in release notes

**Diagnosis:**
```bash
# Check recent releases
gh release list --limit 5

# View specific release
gh release view v1.2.3

# Check release template
cat .github/RELEASE_TEMPLATE.md 2>/dev/null
```

**Solutions:**
```bash
# Update release notes
gh release edit v1.2.3 --notes "$(cat UPDATED_RELEASE_NOTES.md)"

# Create release template
cat > .github/RELEASE_TEMPLATE.md << 'EOF'
## Changes
- [List of changes]

## Installation
```bash
curl -sSL https://github.com/user/repo/releases/download/{{VERSION}}/install.sh | bash
```

## Verification
```bash
usbipd --version
```
EOF

# Set default release notes
gh release edit v1.2.3 --notes-file .github/RELEASE_TEMPLATE.md
```

## Performance and Resource Issues

### Build Performance Problems

#### Slow Build Times

**Symptoms:**
- Builds take longer than expected
- Workflow timeouts due to slow builds
- Resource exhaustion errors

**Diagnosis:**
```bash
# Measure build time
time swift build --configuration release

# Check build cache effectiveness
du -sh .build/

# Monitor resource usage during build
top -pid $(pgrep swift)

# Analyze build performance
./Scripts/benchmark-release-performance.sh --build-analysis
```

**Solutions:**
```bash
# Clean and rebuild
swift package clean
swift build --configuration release

# Optimize build configuration
# Edit Package.swift to improve build settings

# Use build caching in workflows
# Update .github/workflows/release.yml
# Add caching steps for .build directory

# Parallelize build where possible
swift build --configuration release --jobs 4
```

### Memory and Storage Issues

#### Insufficient Resources

**Symptoms:**
- "Out of memory" errors during build
- Disk space warnings
- Workflow fails due to resource limits

**Diagnosis:**
```bash
# Check disk space
df -h .
du -sh .build/

# Monitor memory usage
vm_stat | grep "Pages free"

# Check GitHub Actions runner limits
# Review workflow logs for resource warnings
```

**Solutions:**
```bash
# Clean up build artifacts
swift package clean
rm -rf .build/

# Remove unnecessary files
git clean -fdx

# Optimize artifact sizes
# Remove debug symbols from release builds
strip .build/release/usbipd

# Update workflow to use larger runners
# Edit .github/workflows/release.yml
# Change: runs-on: macos-latest
# To: runs-on: macos-latest-large
```

## Emergency Procedures

### Immediate Release Issues

#### Critical Workflow Failures

When standard troubleshooting doesn't resolve the issue and you need an immediate release:

```bash
# 1. Assess the situation
echo "Critical workflow failure - implementing emergency procedures"

# 2. Build artifacts locally
swift package clean
swift build --configuration release --verbose

# 3. Create release manually
VERSION="v1.2.3"
gh release create $VERSION \
  --title "Emergency Release $VERSION" \
  --notes "Emergency release due to workflow issues. Full validation pending." \
  --prerelease \
  .build/release/usbipd \
  .build/release/QEMUTestServer

# 4. Generate checksums
cd .build/release
shasum -a 256 * > SHA256SUMS
gh release upload $VERSION SHA256SUMS

# 5. Document emergency procedure
echo "Emergency release $VERSION created due to workflow failure" > emergency-log.txt
git add emergency-log.txt
git commit -m "docs: log emergency release procedure for $VERSION"
```

#### Rollback Procedures

When a release needs to be immediately rolled back:

```bash
# 1. Delete problematic release
VERSION="v1.2.3"
gh release delete $VERSION --yes

# 2. Remove problematic tag
git tag -d $VERSION
git push origin --delete $VERSION

# 3. Notify users
gh issue create \
  --title "URGENT: Release $VERSION Rolled Back" \
  --body "Release $VERSION has been rolled back due to critical issues. Please update to the previous stable version."

# 4. Prepare hotfix
git checkout -b hotfix/rollback-$VERSION
git revert [problematic-commit-hash]
git push origin hotfix/rollback-$VERSION

# 5. Create replacement release
NEW_VERSION="v1.2.4"
./Scripts/prepare-release.sh $NEW_VERSION
```

## Monitoring and Alerting

### Release Monitoring Setup

#### Workflow Status Monitoring

```bash
# Check current workflow status
./Scripts/release-status-dashboard.sh --summary

# Monitor specific workflow
gh run watch [run-id]

# Set up monitoring alerts
# Edit .github/workflows/release-monitoring.yml
# Configure notification preferences
```

#### Performance Monitoring

```bash
# Benchmark current performance
./Scripts/benchmark-release-performance.sh

# Compare with historical data
./Scripts/benchmark-release-performance.sh --compare

# Generate performance report
./Scripts/benchmark-release-performance.sh --report > performance-report.txt
```

### Health Checks

#### System Health Validation

```bash
# Complete system health check
./Scripts/release-health-check.sh

# Validate individual components
./Scripts/prepare-release.sh --health-check
./Scripts/validate-release-artifacts.sh --health-check

# Check documentation integrity
find Documentation/ -name "*.md" -exec markdown-link-check {} \;
```

## Prevention and Best Practices

### Regular Maintenance

#### Weekly Maintenance Tasks

```bash
# Update dependencies
swift package update

# Run full test suite
./Scripts/run-production-tests.sh

# Validate documentation
markdownlint Documentation/

# Check for security vulnerabilities
# Run security scanning tools

# Performance benchmark
./Scripts/benchmark-release-performance.sh --baseline
```

#### Monthly Review Tasks

```bash
# Review and update emergency procedures
# Test emergency procedures with simulation

# Update troubleshooting documentation
# Add new issues and solutions discovered

# Review workflow performance metrics
./Scripts/benchmark-release-performance.sh --monthly-report

# Validate backup and recovery procedures
# Test rollback capabilities
```

### Automation Improvements

#### Proactive Monitoring

```bash
# Set up automated health checks
# Configure .github/workflows/health-check.yml

# Implement performance regression detection
# Add performance benchmarks to CI

# Create automated documentation validation
# Add link checking and content validation
```

#### Workflow Optimization

```bash
# Optimize build caching
# Update .github/workflows/release.yml with better caching

# Implement parallel execution
# Configure workflows for parallel test execution

# Add automated rollback triggers
# Set up automatic rollback on critical failures
```

## Getting Help

### Support Channels

1. **Internal Documentation**:
   - This troubleshooting guide
   - `Documentation/Release-Automation.md`
   - `Documentation/Emergency-Release-Procedures.md`

2. **Diagnostic Tools**:
   ```bash
   ./Scripts/release-status-dashboard.sh --help
   ./Scripts/benchmark-release-performance.sh --diagnostics
   ./Scripts/release-health-check.sh --verbose
   ```

3. **Community Resources**:
   - GitHub Issues for public discussion
   - Project maintainers for escalation
   - GitHub Actions documentation for workflow issues

### Escalation Procedures

#### When to Escalate

- Multiple troubleshooting attempts failed
- Security implications of the issue
- Critical user impact requiring immediate attention
- Infrastructure problems beyond project scope

#### How to Escalate

```bash
# Document the issue thoroughly
./Scripts/generate-issue-report.sh > issue-report.txt

# Create detailed GitHub issue
gh issue create \
  --title "Release Workflow Issue: [Brief Description]" \
  --body-file issue-report.txt \
  --label "release,bug,help-wanted"

# Gather diagnostic information
./Scripts/collect-diagnostics.sh > diagnostics.txt

# Contact maintainers with full context
# Include issue link, diagnostics, and attempted solutions
```

### Continuous Improvement

#### Learning from Issues

```bash
# Document lessons learned
echo "Issue: [description]" >> release-lessons-learned.md
echo "Solution: [solution]" >> release-lessons-learned.md
echo "Prevention: [prevention steps]" >> release-lessons-learned.md

# Update troubleshooting guide
git add Documentation/Release-Troubleshooting.md
git commit -m "docs: add troubleshooting info for [issue description]"

# Share knowledge with team
# Create team documentation or training materials
```

---

**Remember**: This troubleshooting guide is a living document. When you encounter new issues or find new solutions, please update this guide to help future maintainers and users.

For emergency situations that require immediate attention, refer to `Documentation/Emergency-Release-Procedures.md`.

For standard release procedures, see `Documentation/Release-Automation.md`.