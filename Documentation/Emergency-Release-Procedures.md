# Emergency Release Procedures

This document provides comprehensive procedures for handling emergency releases of usbipd-mac, including fast-track workflows, validation bypasses, rollback procedures, and failure recovery steps.

## Overview

Emergency releases are special procedures designed for critical situations where standard release processes may be too slow or when normal validation steps need to be bypassed due to security vulnerabilities, system compatibility issues, or other urgent circumstances.

**⚠️ IMPORTANT:** Emergency procedures should only be used when absolutely necessary, as they bypass safety checks that ensure release quality and stability.

## When to Use Emergency Procedures

### Critical Scenarios

Use emergency release procedures only in these situations:

1. **Security Vulnerabilities**: Critical security flaws requiring immediate patching
2. **System Compatibility**: macOS updates breaking existing functionality
3. **Data Loss Issues**: Bugs causing user data corruption or loss
4. **Service Disruption**: Issues preventing normal USB/IP functionality
5. **Regulatory Compliance**: Legal or compliance requirements mandating immediate fixes

### Risk Assessment

Before initiating emergency procedures, assess:

- **Severity**: How critical is the issue?
- **User Impact**: How many users are affected?
- **Risk vs. Benefit**: Does the risk of bypassing validation outweigh the benefit of rapid deployment?
- **Rollback Plan**: Can changes be safely reverted if needed?

## Emergency Release Workflows

### Option 1: Accelerated Standard Release

For less critical emergencies, use the standard workflow with reduced validation:

```bash
# 1. Prepare emergency release locally
./Scripts/prepare-release.sh --version v1.2.4 --skip-tests --force

# 2. Push tag to trigger workflow with emergency flag
git push origin v1.2.4

# 3. Monitor workflow and manually approve bypasses
# GitHub Actions workflow will prompt for emergency approval
```

**Validation Bypasses Available:**
- ✅ Code quality checks (SwiftLint) - still required
- ⚠️ Build verification - still required  
- ❌ Development test suite - can be skipped
- ❌ CI test suite - can be skipped
- ❌ Production test suite - can be skipped
- ❌ QEMU integration tests - can be skipped

### Option 2: Manual Emergency Release

For critical emergencies requiring maximum speed:

```bash
# 1. Create emergency branch
git checkout -b emergency/critical-fix-v1.2.4

# 2. Apply minimal necessary changes
git add [critical-files-only]
git commit -m "fix: critical security vulnerability (emergency release)"

# 3. Build artifacts locally
swift build --configuration release

# 4. Package artifacts manually
mkdir -p .build/emergency-release
cp .build/release/usbipd .build/emergency-release/
cp -r .build/release/USBIPDSystemExtension.app .build/emergency-release/

# 5. Generate checksums
cd .build/emergency-release
shasum -a 256 * > SHA256SUMS

# 6. Create GitHub release manually
gh release create v1.2.4 \
  --title "Emergency Release v1.2.4" \
  --notes "Critical security fix - emergency release with limited validation" \
  --prerelease \
  .build/emergency-release/*

# 7. Document and communicate
./Scripts/emergency-notification.sh v1.2.4
```

### Option 3: Hotfix with Validation Bypass

For situations requiring some validation but with time pressure:

```bash
# 1. Use release preparation with emergency mode
./Scripts/prepare-release.sh --version v1.2.4 --emergency --skip-production-tests

# 2. Trigger workflow with emergency dispatch
gh workflow run release.yml \
  --field version=v1.2.4 \
  --field emergency=true \
  --field bypass_validation=development,ci

# 3. Monitor and approve emergency workflow steps
```

## Validation Bypass Procedures

### Code Quality Bypass

**⚠️ Generally NOT recommended - code quality issues can cause instability**

```bash
# If absolutely necessary for emergency situations
./Scripts/prepare-release.sh --skip-lint --force
```

**Required Justification:**
- Document why linting must be bypassed
- Commit to fixing violations in next regular release
- Include linting bypass in emergency communication

### Test Suite Bypass

**Available bypass levels:**

```bash
# Skip only development tests (fastest validation)
./Scripts/prepare-release.sh --emergency --skip-development-tests

# Skip development and CI tests (moderate risk)
./Scripts/prepare-release.sh --emergency --skip-ci-tests

# Skip all tests (highest risk - emergency only)
./Scripts/prepare-release.sh --emergency --skip-all-tests
```

**Risk Mitigation:**
- Review test failures from last successful run
- Manual smoke testing of core functionality
- Immediate post-release validation

### Security Scanning Bypass

**For time-critical releases only:**

```bash
# Skip dependency vulnerability scanning
./Scripts/prepare-release.sh --emergency --skip-security-scan

# Skip code signing verification
./Scripts/prepare-release.sh --emergency --skip-signature-validation
```

**Mandatory Follow-up:**
- Run full security scan within 24 hours
- Report any findings immediately
- Plan remediation release if issues found

## Rollback Procedures

### GitHub Release Rollback

```bash
# 1. Delete problematic release
gh release delete v1.2.4 --yes

# 2. Delete problematic tag
git tag -d v1.2.4
git push origin --delete v1.2.4

# 3. Notify users about rollback
./Scripts/emergency-notification.sh rollback-v1.2.4
```

### Git History Rollback

For releases that introduced breaking changes:

```bash
# 1. Create rollback branch
git checkout -b rollback/v1.2.4

# 2. Revert problematic commits
git revert [commit-hash-1] [commit-hash-2]

# 3. Create rollback release
./Scripts/prepare-release.sh --version v1.2.5 --emergency

# 4. Communicate rollback
echo "v1.2.5 rolls back changes from v1.2.4 due to compatibility issues"
```

### System Extension Rollback

For System Extension issues:

```bash
# 1. Unload current extension
sudo systemextensionsctl uninstall [team-id] [bundle-id]

# 2. Install previous version
sudo usbipd daemon --install-extension --version v1.2.3

# 3. Verify rollback
usbipd status
systemextensionsctl list
```

## Failure Recovery

### GitHub Actions Workflow Failures

#### Build Failures During Emergency

```bash
# 1. Check build logs for specific errors
gh run view [run-id] --log

# 2. For dependency issues
git checkout -b emergency/fix-dependencies
# Fix Package.swift or dependency issues
swift package resolve
swift build --configuration release

# 3. For compilation errors
# Apply minimal fix and retry
git add [fixed-files]
git commit -m "fix: emergency compilation fix"
git push origin emergency/fix-dependencies

# 4. Retry release workflow
gh workflow run release.yml --field version=v1.2.4
```

#### Artifact Upload Failures

```bash
# 1. Download artifacts from failed workflow
gh run download [run-id]

# 2. Create release manually
gh release create v1.2.4 \
  --title "Emergency Release v1.2.4" \
  --notes "$(cat RELEASE_NOTES.md)" \
  --prerelease \
  ./artifacts/*

# 3. Verify artifact integrity
./Scripts/validate-release-artifacts.sh --artifacts-path ./artifacts
```

### Code Signing Failures

#### Development Signing Fallback

```bash
# 1. Build with development signing
swift build --configuration release

# 2. Create release with warnings
gh release create v1.2.4 \
  --title "Emergency Release v1.2.4 (Development Signed)" \
  --notes "⚠️ This emergency release uses development signing. Install with: sudo spctl --master-disable" \
  --prerelease \
  .build/release/*
```

#### Certificate Renewal Emergency

```bash
# 1. Generate new certificate request
# Follow Documentation/Code-Signing-Setup.md

# 2. Use temporary developer certificate
# Export from Xcode keychain
security find-identity -v -p codesigning

# 3. Sign artifacts manually
codesign --force --sign "Developer ID Application: Your Name" .build/release/usbipd
```

### Network/GitHub API Failures

#### Local Release Creation

```bash
# 1. Create release archive locally
tar -czf usbipd-mac-v1.2.4.tar.gz -C .build/release .

# 2. Generate release notes
git log --oneline $(git describe --tags --abbrev=0)..HEAD > RELEASE_NOTES.txt

# 3. Upload via alternative methods
# - Direct GitHub web interface upload
# - Third-party release tools
# - Manual distribution channels
```

#### Alternative Distribution

```bash
# 1. Create distribution package
mkdir -p dist/v1.2.4
cp .build/release/* dist/v1.2.4/
shasum -a 256 dist/v1.2.4/* > dist/v1.2.4/SHA256SUMS

# 2. Upload to alternative locations
# - Project website
# - CDN endpoints
# - Mirror repositories

# 3. Update documentation with alternative links
```

## Communication Procedures

### Emergency Release Notification

Create immediate user communication:

```bash
# 1. GitHub issue announcement
gh issue create \
  --title "Emergency Release v1.2.4 Available" \
  --body "$(cat emergency-release-template.md)"

# 2. Update README with urgent notice
git add README.md
git commit -m "docs: add emergency release notice for v1.2.4"
git push origin main

# 3. Social media/community notifications
# Post to relevant channels, forums, etc.
```

### Rollback Notification

```bash
# 1. GitHub issue for rollback
gh issue create \
  --title "URGENT: v1.2.4 Rolled Back - Please Update to v1.2.5" \
  --body "$(cat rollback-notification-template.md)"

# 2. Pin rollback notice
gh issue pin [issue-number]

# 3. Update release with deprecation warning
gh release edit v1.2.4 \
  --notes "⚠️ DEPRECATED: This release has been rolled back. Please update to v1.2.5 immediately."
```

## Post-Emergency Procedures

### Immediate Actions (Within 4 hours)

1. **Verify Release Function**: Test core functionality with emergency release
2. **Monitor Issues**: Watch for bug reports and compatibility issues
3. **Prepare Hotfix**: Begin work on fixes for bypassed validation
4. **Document Decisions**: Record what was bypassed and why

### Short-term Actions (Within 24 hours)

1. **Full Validation**: Run complete test suite against emergency release
2. **Security Scan**: Perform full security analysis
3. **Code Quality Review**: Address any linting or quality issues
4. **User Communication**: Provide detailed status update

### Long-term Actions (Within 1 week)

1. **Regular Release**: Prepare follow-up release with full validation
2. **Process Review**: Analyze emergency procedure effectiveness
3. **Documentation Update**: Improve emergency procedures based on experience
4. **Team Debrief**: Review decisions and improve future responses

## Emergency Contacts and Resources

### Key Personnel

- **Release Manager**: Primary contact for release decisions
- **Security Team**: For security-related emergencies  
- **DevOps Lead**: For infrastructure and deployment issues
- **Product Owner**: For user impact and communication decisions

### Essential Resources

- **Emergency Runbook**: This document
- **Release Automation Guide**: `Documentation/Release-Automation.md`
- **Code Signing Setup**: `Documentation/Code-Signing-Setup.md`
- **Build Troubleshooting**: `Documentation/troubleshooting/build-troubleshooting.md`

### Communication Channels

- **Internal**: Team chat, emergency phone numbers
- **External**: GitHub issues, project website, social media
- **Users**: Release announcements, security advisories

## Emergency Release Templates

### GitHub Release Template (Emergency)

```markdown
## 🚨 Emergency Release v1.2.4

This is an emergency release addressing [critical issue description].

### ⚠️ Important Notes
- This release bypassed [specific validation steps] due to urgency
- Full validation will be completed and reported within 24 hours
- Follow-up release v1.2.5 is planned for [date] with full validation

### Critical Fix
- [Description of emergency fix]
- [Impact and affected systems]

### Installation
```bash
# Standard installation
curl -sSL https://github.com/[owner]/usbipd-mac/releases/download/v1.2.4/install.sh | bash

# Manual installation
wget https://github.com/[owner]/usbipd-mac/releases/download/v1.2.4/usbipd-mac-v1.2.4.tar.gz
tar -xzf usbipd-mac-v1.2.4.tar.gz
sudo ./install.sh
```

### Verification
```bash
# Verify installation
usbipd --version  # Should show v1.2.4
usbipd status     # Should show system ready
```

### Support
If you experience issues with this emergency release:
1. Check [troubleshooting guide](link)
2. Report issues at [GitHub Issues](link)
3. For urgent issues, contact [emergency contact]

### Next Steps
- Full validation results will be published at [link]
- Regular release v1.2.5 planned for [date]
- Subscribe to releases for updates
```

### Rollback Notification Template

```markdown
## ⚠️ URGENT: v1.2.4 Rollback Notice

**IMMEDIATE ACTION REQUIRED**: Please update to v1.2.5 immediately.

### Issue Summary
v1.2.4 has been rolled back due to [specific issue description].

### Affected Versions
- ❌ v1.2.4 - ROLLED BACK
- ✅ v1.2.3 - Safe to use
- ✅ v1.2.5 - Recommended update

### Immediate Actions
1. **Do not install v1.2.4** if you haven't already
2. **If you have v1.2.4 installed**:
   ```bash
   # Update immediately
   curl -sSL https://github.com/[owner]/usbipd-mac/releases/download/v1.2.5/install.sh | bash
   ```
3. **Verify your version**:
   ```bash
   usbipd --version  # Should NOT show v1.2.4
   ```

### Support
- **Immediate help**: [emergency contact]
- **Report issues**: [GitHub Issues link]
- **Status updates**: [status page link]

This rollback ensures your system stability and security.
```

## Testing Emergency Procedures

### Simulation Exercises

Regularly test emergency procedures:

```bash
# 1. Create test emergency scenario
git checkout -b test-emergency/simulation
echo "Simulated critical fix" > emergency-test.txt
git add emergency-test.txt
git commit -m "test: emergency procedure simulation"

# 2. Practice emergency workflow
./Scripts/prepare-release.sh --version v0.0.1-emergency-test --emergency --dry-run

# 3. Test rollback procedures  
git tag v0.0.1-emergency-test
git push origin v0.0.1-emergency-test
# Practice rollback steps

# 4. Clean up test
git tag -d v0.0.1-emergency-test
git push origin --delete v0.0.1-emergency-test
git branch -D test-emergency/simulation
```

### Validation Checklist

Before using emergency procedures in production:

- [ ] Team members trained on emergency procedures
- [ ] Emergency contact information current
- [ ] All tools and scripts tested and functional
- [ ] Communication templates reviewed and current
- [ ] Rollback procedures verified
- [ ] Alternative distribution methods tested
- [ ] Post-emergency review process established

## Legal and Compliance Considerations

### Documentation Requirements

For emergency releases:

- Document decision rationale
- Record bypassed validations
- Maintain audit trail of changes
- Log communication timeline

### Risk Management

- Assess legal implications of emergency changes
- Consider compliance requirements
- Document risk mitigation steps
- Plan validation catch-up timeline

---

**Remember**: Emergency procedures are powerful tools that trade speed for safety. Use them judiciously and always follow up with proper validation and documentation.

For non-emergency releases, always use the standard procedures documented in `Documentation/Release-Automation.md`.