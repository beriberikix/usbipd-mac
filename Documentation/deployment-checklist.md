# Deployment Checklist and Rollback Procedures

## Homebrew-Releaser Integration Deployment Guide

This document provides comprehensive deployment procedures for the homebrew-releaser GitHub Action integration. It includes validation checkpoints, rollback procedures, and troubleshooting guidance for safe production deployment.

**Note**: This document is archived as it was created for the webhook-based architecture. The current architecture uses homebrew-releaser which is simpler and more reliable. See [homebrew-releaser-setup.md](homebrew-releaser-setup.md) for current configuration.

## Table of Contents

- [Pre-Deployment Validation](#pre-deployment-validation)
- [Deployment Process](#deployment-process)
- [Post-Deployment Validation](#post-deployment-validation)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)
- [Emergency Contacts](#emergency-contacts)

## Pre-Deployment Validation

### 📋 Prerequisites Checklist

Before initiating deployment, verify all prerequisites are met:

#### Main Repository Requirements
- [ ] **Feature branch tested**: `feature/external-tap-integration` fully tested and validated
- [ ] **CI/CD passing**: All GitHub Actions workflows passing on feature branch
- [ ] **Code review completed**: Feature branch has received thorough code review
- [ ] **Documentation updated**: All documentation reflects new architecture
- [ ] **Integration tests passing**: TapRepositoryIntegrationTests validated

#### Tap Repository Requirements
- [ ] **Tap repository created**: https://github.com/beriberikix/homebrew-usbipd-mac exists
- [ ] **Workflows deployed**: Formula update workflow and scripts deployed to tap repository
- [ ] **Formula template ready**: Formula template with placeholders committed
- [ ] **Repository permissions**: Proper access controls and webhook permissions configured

#### Infrastructure Requirements
- [ ] **GitHub Actions quota**: Sufficient quota available for workflow executions
- [ ] **Webhook endpoints**: Webhook URLs accessible and properly configured
- [ ] **Network connectivity**: GitHub API and repository access validated
- [ ] **Release assets**: Release asset upload capabilities verified

### 🧪 Pre-Deployment Testing

#### Test Scenarios
1. **Metadata Generation Test**
   ```bash
   ./Scripts/generate-homebrew-metadata.sh --version v0.0.9-test --dry-run
   ```
   - [ ] ✅ Script executes successfully
   - [ ] ✅ Valid JSON metadata generated
   - [ ] ✅ All required fields present

2. **Tap Repository Access Test**
   ```bash
   brew tap beriberikix/usbipd-mac
   brew info usbipd-mac
   brew untap beriberikix/usbipd-mac
   ```
   - [ ] ✅ Tap successfully added
   - [ ] ✅ Formula discovered and parsed
   - [ ] ✅ No installation errors with template

3. **Integration Test Execution**
   ```bash
   # When IntegrationTests target is enabled
   swift test --filter TapRepositoryIntegrationTests
   ```
   - [ ] ✅ All integration tests pass
   - [ ] ✅ Error scenarios handled correctly
   - [ ] ✅ Recovery procedures validated

## Deployment Process

### Phase 1: Main Repository Deployment

#### Step 1.1: Merge Feature Branch
```bash
# Ensure feature branch is up-to-date with main
git checkout main
git pull origin main
git checkout feature/external-tap-integration
git rebase main

# Resolve any conflicts if present
# Run final tests
./Scripts/run-ci-tests.sh

# Merge to main
git checkout main
git merge feature/external-tap-integration
```

**Validation Checkpoint 1.1:**
- [ ] ✅ Merge completed without conflicts
- [ ] ✅ CI pipeline triggered and passing
- [ ] ✅ No Formula/ directory in main branch
- [ ] ✅ Metadata generation scripts present

#### Step 1.2: Tag and Release
```bash
# Create and push release tag
git tag v[VERSION]
git push origin v[VERSION]

# Monitor release workflow
gh workflow list --repo beriberikix/usbipd-mac
gh run watch [RUN_ID]
```

**Validation Checkpoint 1.2:**
- [ ] ✅ Release workflow triggered
- [ ] ✅ Metadata generated and uploaded as asset
- [ ] ✅ Release published successfully
- [ ] ✅ No errors in workflow logs

### Phase 2: Tap Repository Webhook Validation

#### Step 2.1: Webhook Configuration
```bash
# Verify webhook is configured (requires admin access)
gh api repos/beriberikix/usbipd-mac/hooks

# Check webhook deliveries
gh api repos/beriberikix/usbipd-mac/hooks/[HOOK_ID]/deliveries
```

**Validation Checkpoint 2.1:**
- [ ] ✅ Webhook configured and active
- [ ] ✅ Proper event triggers (release published)
- [ ] ✅ Correct target URL for tap repository

#### Step 2.2: Formula Update Verification
```bash
# Monitor tap repository for automatic update
gh run list --repo beriberikix/homebrew-usbipd-mac

# Verify formula was updated
curl -s https://raw.githubusercontent.com/beriberikix/homebrew-usbipd-mac/main/Formula/usbipd-mac.rb | grep -E "(version|sha256)"
```

**Validation Checkpoint 2.2:**
- [ ] ✅ Webhook delivery successful
- [ ] ✅ Formula update workflow triggered
- [ ] ✅ Placeholders replaced with actual values
- [ ] ✅ Formula syntax validation passed

### Phase 3: End-User Experience Validation

#### Step 3.1: Fresh Installation Test
```bash
# Test complete user workflow
brew tap beriberikix/usbipd-mac
brew install usbipd-mac

# Verify installation
usbipd --version
usbipd-install-extension status
```

**Validation Checkpoint 3.1:**
- [ ] ✅ Tap addition successful
- [ ] ✅ Formula installation completes
- [ ] ✅ Binary executable and functional
- [ ] ✅ System Extension components installed

#### Step 3.2: Service Management Test
```bash
# Test service lifecycle
sudo brew services start usbipd-mac
brew services list | grep usbipd-mac
sudo brew services stop usbipd-mac

# Test System Extension
usbipd-install-extension install
usbipd-install-extension status
```

**Validation Checkpoint 3.2:**
- [ ] ✅ Service starts and stops correctly
- [ ] ✅ System Extension installation guided properly
- [ ] ✅ All management commands functional
- [ ] ✅ Logs and diagnostics accessible

## Post-Deployment Validation

### 📊 Monitoring and Health Checks

#### Daily Health Checks (First Week)
- [ ] **Webhook Health**: Monitor webhook delivery success rate
- [ ] **Formula Updates**: Verify automatic updates on new releases
- [ ] **User Installations**: Monitor installation success metrics
- [ ] **Error Rates**: Track GitHub Actions workflow failure rates
- [ ] **Community Feedback**: Monitor issues and support requests

#### Weekly Health Checks (Ongoing)
- [ ] **Repository Activity**: Ensure tap repository stays active
- [ ] **Dependency Updates**: Monitor for Homebrew ecosystem changes
- [ ] **Security Scanning**: Review security scan results
- [ ] **Performance Metrics**: Track workflow execution times

### 🔄 Continuous Validation

#### Automated Monitoring Setup
```bash
# Set up GitHub Actions monitoring
gh workflow run monitor-tap-health.yml --repo beriberikix/homebrew-usbipd-mac

# Configure alerts for failures
gh api repos/beriberikix/usbipd-mac/issues --data '{
  "title": "Webhook Health Monitor",
  "body": "Automated monitoring of tap repository webhook health"
}'
```

## Rollback Procedures

### 🚨 Emergency Rollback Scenarios

#### Scenario 1: Webhook Integration Failure
**Symptoms**: Webhook not triggering, formula not updating
**Immediate Actions**:
1. **Manual Formula Update**:
   ```bash
   # Clone tap repository
   git clone https://github.com/beriberikix/homebrew-usbipd-mac.git
   cd homebrew-usbipd-mac
   
   # Manual update with latest release
   ./Scripts/manual-update.sh --version v[LATEST] --force
   
   # Commit and push
   git add Formula/usbipd-mac.rb
   git commit -m "emergency: manual formula update for v[LATEST]"
   git push origin main
   ```

2. **User Communication**:
   ```bash
   # Update users via GitHub issue/announcement
   gh issue create --repo beriberikix/usbipd-mac \
     --title "Temporary Installation Instructions" \
     --body "Temporary manual update in progress..."
   ```

#### Scenario 2: Formula Installation Failures
**Symptoms**: Users cannot install via tap, build failures
**Immediate Actions**:
1. **Revert Formula Changes**:
   ```bash
   cd homebrew-usbipd-mac
   git log --oneline -5
   git revert [COMMIT_HASH]
   git push origin main
   ```

2. **Emergency Formula Fix**:
   ```bash
   # Quick syntax fix if needed
   ruby -c Formula/usbipd-mac.rb
   # Fix issues and commit immediately
   ```

#### Scenario 3: Complete Architecture Rollback
**Symptoms**: Fundamental issues requiring full rollback
**Immediate Actions**:
1. **Restore Formula Directory**:
   ```bash
   # In main repository
   git checkout main
   git revert [MERGE_COMMIT] --no-edit
   
   # Restore Formula directory from backup or recreate
   mkdir Formula
   # Copy working formula from tap repository
   curl -o Formula/usbipd-mac.rb \
     https://raw.githubusercontent.com/beriberikix/homebrew-usbipd-mac/main/Formula/usbipd-mac.rb
   
   # Update placeholders with current version
   sed -i 's/VERSION_PLACEHOLDER/v[CURRENT]/g' Formula/usbipd-mac.rb
   sed -i 's/SHA256_PLACEHOLDER/[CURRENT_SHA]/g' Formula/usbipd-mac.rb
   
   git add Formula/
   git commit -m "emergency: restore embedded Formula directory"
   git push origin main
   ```

2. **Update Release Workflow**:
   ```bash
   # Restore original formula update workflow
   git checkout [BACKUP_COMMIT] -- .github/workflows/release.yml
   git commit -m "emergency: restore original release workflow"
   git push origin main
   ```

3. **User Communication**:
   ```bash
   # Immediate user notification
   gh issue create --repo beriberikix/usbipd-mac \
     --title "🚨 Emergency: Installation Method Temporarily Reverted" \
     --body "Due to technical issues, we have temporarily reverted to the original installation method..."
   ```

### 📋 Rollback Validation Checklist

After any rollback procedure:
- [ ] **CI Pipeline**: Verify CI passes with rollback changes
- [ ] **Installation Test**: Confirm users can install successfully
- [ ] **Existing Users**: Verify existing installations unaffected
- [ ] **Documentation**: Update documentation to reflect temporary changes
- [ ] **Communication**: Notify users of rollback and timeline for resolution
- [ ] **Root Cause Analysis**: Document what went wrong and prevention measures

## Troubleshooting

### Common Issues and Solutions

#### Issue: Webhook Not Triggering
**Diagnosis**:
```bash
# Check webhook configuration
gh api repos/beriberikix/usbipd-mac/hooks

# Check recent deliveries
gh api repos/beriberikix/usbipd-mac/hooks/[HOOK_ID]/deliveries | jq '.[0]'
```

**Solutions**:
1. Verify webhook URL is correct
2. Check repository permissions
3. Validate event triggers (release, published)
4. Use manual workflow dispatch as workaround

#### Issue: Formula Validation Failures
**Diagnosis**:
```bash
# Check formula syntax
ruby -c Formula/usbipd-mac.rb

# Validate with Homebrew
brew audit --strict Formula/usbipd-mac.rb
```

**Solutions**:
1. Fix Ruby syntax errors
2. Update formula structure
3. Verify all required fields present
4. Test with clean Homebrew installation

#### Issue: Metadata Generation Failures
**Diagnosis**:
```bash
# Test metadata generation locally
./Scripts/generate-homebrew-metadata.sh --version v[TEST] --dry-run --verbose

# Check for missing dependencies
which jq curl shasum
```

**Solutions**:
1. Install missing dependencies
2. Fix script permissions
3. Verify Git tag exists
4. Check network connectivity for downloads

### 📞 Escalation Procedures

#### Severity Levels

**🔴 Critical (Immediate Response Required)**
- Complete installation failures for all users
- Security vulnerabilities in tap repository
- Data corruption or loss scenarios
- Webhook delivering malicious updates

**🟡 High (Response within 4 hours)**
- Partial installation failures affecting significant user base
- Webhook integration not working for new releases
- Formula validation failures blocking releases

**🟢 Medium (Response within 24 hours)**
- Individual user installation issues
- Documentation gaps or errors
- Minor workflow optimization needs

#### Contact Information

**Primary Maintainer**: [Maintainer Name]
- GitHub: @[username]
- Email: [email]
- Availability: [timezone/hours]

**Backup Maintainer**: [Backup Name]
- GitHub: @[username]
- Email: [email]
- Availability: [timezone/hours]

**Community Support**:
- GitHub Issues: https://github.com/beriberikix/usbipd-mac/issues
- GitHub Discussions: https://github.com/beriberikix/usbipd-mac/discussions

## Emergency Contacts

### Immediate Response Team
- **Project Lead**: Available for critical architectural decisions
- **DevOps Engineer**: Repository and CI/CD infrastructure
- **Community Manager**: User communication and issue triage

### External Dependencies
- **GitHub Support**: For platform-level issues with Actions or webhooks
- **Homebrew Team**: For tap repository or formula specification issues

## Documentation Updates

After deployment, ensure these documents are updated:
- [ ] **README.md**: Installation instructions point to tap repository
- [ ] **Documentation/homebrew-troubleshooting.md**: Includes tap-specific troubleshooting
- [ ] **CLAUDE.md**: Reflects new development workflows
- [ ] **Release notes**: Document the architecture change for users

## Success Criteria

The deployment is considered successful when:
- [ ] ✅ New releases automatically trigger formula updates
- [ ] ✅ Users can install via `brew tap beriberikix/usbipd-mac && brew install usbipd-mac`
- [ ] ✅ System Extension functionality preserved and working
- [ ] ✅ No increase in user-reported installation issues
- [ ] ✅ Webhook delivery success rate > 95%
- [ ] ✅ Formula update latency < 5 minutes after release

---

**Document Version**: 1.0  
**Last Updated**: 2024-08-19  
**Next Review**: 2024-09-19  

*This document should be reviewed and updated after each deployment and quarterly thereafter.*