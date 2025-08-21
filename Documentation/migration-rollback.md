# Homebrew-Releaser Migration Rollback Procedures

This document provides comprehensive rollback procedures for the homebrew-releaser migration. These procedures allow reverting from homebrew-releaser back to a webhook-based system if critical issues are encountered.

## Overview

The homebrew-releaser migration can be rolled back at different levels depending on the severity of issues encountered:

1. **Configuration Rollback**: Disable homebrew-releaser while keeping architecture
2. **Partial Rollback**: Re-enable webhook system alongside homebrew-releaser
3. **Full Rollback**: Complete reversion to pre-migration webhook architecture

## Prerequisites for Rollback

Before performing any rollback, ensure you have:

- [ ] **Admin access** to both main repository and tap repository
- [ ] **WEBHOOK_TOKEN** secret available (if performing full rollback)
- [ ] **Backup of working webhook configuration** from previous commits
- [ ] **Current release workflow backup** before migration changes

## Rollback Procedures

### Level 1: Configuration Rollback (Recommended First Step)

This approach disables homebrew-releaser while keeping the simplified architecture.

#### Step 1.1: Disable Homebrew-Releaser in Workflow

```bash
# Edit .github/workflows/release.yml
# Comment out or remove the homebrew-releaser step
```

Edit `.github/workflows/release.yml` and comment out the homebrew-releaser step:

```yaml
# Temporarily disabled - rollback procedure
# - name: Update Homebrew Formula
#   uses: Justintime50/homebrew-releaser@v1
#   with:
#     homebrew_owner: beriberikix
#     homebrew_tap: homebrew-usbipd-mac
#     formula_folder: Formula
#     github_token: ${{ secrets.HOMEBREW_TAP_TOKEN }}
#     install: |
#       bin.install "usbipd"
#     test: |
#       assert_match "usbipd", shell_output("#{bin}/usbipd --version")
#     target_darwin_amd64: true
#     target_darwin_arm64: true
#     commit_owner: github-actions[bot]
#     commit_email: 41898282+github-actions[bot]@users.noreply.github.com
```

#### Step 1.2: Manual Formula Update Process

While disabled, use manual process for formula updates:

```bash
# After each release, manually update tap repository
./Scripts/update-tap-formula.sh --version v1.2.3 --manual
```

#### Step 1.3: Commit Configuration Changes

```bash
git add .github/workflows/release.yml
git commit -m "fix: temporarily disable homebrew-releaser for rollback"
git push origin feature/homebrew-releaser-migration
```

### Level 2: Partial Rollback (Hybrid Approach)

Re-enable webhook system alongside homebrew-releaser for redundancy.

#### Step 2.1: Restore Webhook Infrastructure

Add webhook notification back to release workflow:

```yaml
# Add this job back to .github/workflows/release.yml
  notify-tap-repository:
    name: Notify Tap Repository
    runs-on: ubuntu-latest
    needs: [build-and-sign-artifacts]
    if: success()
    
    steps:
      - name: Trigger Tap Repository Update
        run: |
          curl -X POST \
            -H "Authorization: token ${{ secrets.WEBHOOK_TOKEN }}" \
            -H "Accept: application/vnd.github.v3+json" \
            https://api.github.com/repos/beriberikix/homebrew-usbipd-mac/dispatches \
            -d '{
              "event_type": "release-published",
              "client_payload": {
                "repository": "${{ github.repository }}",
                "release": {
                  "tag_name": "${{ github.event.inputs.version }}",
                  "published_at": "${{ steps.get-time.outputs.time }}"
                }
              }
            }'
```

#### Step 2.2: Re-enable Tap Repository Workflow

In the tap repository, restore the webhook handler:

```bash
cd /path/to/homebrew-usbipd-mac
git checkout main

# Restore archived workflow
git show HEAD~5:.github/workflows/formula-update.yml > .github/workflows/formula-update.yml

git add .github/workflows/formula-update.yml
git commit -m "restore: re-enable webhook handler for rollback redundancy"
git push origin main
```

#### Step 2.3: Configure Dual System Operation

Configure both systems to operate in parallel with conflict prevention:

```yaml
# In homebrew-releaser step, add conditional logic
- name: Update Homebrew Formula
  if: ${{ !env.WEBHOOK_ENABLED }}  # Only run if webhook disabled
  uses: Justintime50/homebrew-releaser@v1
  # ... existing configuration
```

### Level 3: Full Rollback (Complete Reversion)

Complete reversion to pre-migration webhook architecture.

#### Step 3.1: Restore Complete Webhook Infrastructure

```bash
# Checkout the commit before homebrew-releaser migration
git log --oneline | grep "remove webhook"
# Note the commit hash BEFORE the webhook removal

# Create rollback branch
git checkout -b rollback/restore-webhooks
git cherry-pick [COMMIT_BEFORE_WEBHOOK_REMOVAL]
```

#### Step 3.2: Restore Webhook Secrets

Add back the WEBHOOK_TOKEN secret:

1. Go to GitHub repository Settings > Secrets and variables > Actions
2. Add `WEBHOOK_TOKEN` secret with appropriate token value
3. Ensure token has `repo` scope for tap repository

#### Step 3.3: Restore Metadata Generation

Restore metadata generation scripts if they were removed:

```bash
# Check if scripts exist
ls Scripts/generate-homebrew-metadata.sh
ls Scripts/validate-homebrew-metadata.sh

# If missing, restore from backup or recreate
git checkout [BACKUP_COMMIT] -- Scripts/generate-homebrew-metadata.sh
git checkout [BACKUP_COMMIT] -- Scripts/validate-homebrew-metadata.sh
```

#### Step 3.4: Update Release Workflow

Restore the complete release workflow with webhook integration:

```bash
# Replace current release.yml with pre-migration version
git checkout [PRE_MIGRATION_COMMIT] -- .github/workflows/release.yml

# Validate workflow syntax
gh workflow validate .github/workflows/release.yml
```

#### Step 3.5: Full Tap Repository Restoration

Restore complete webhook handling in tap repository:

```bash
cd /path/to/homebrew-usbipd-mac

# Restore all workflow files
git checkout [PRE_HOMEBREW_RELEASER_COMMIT] -- .github/workflows/
git checkout [PRE_HOMEBREW_RELEASER_COMMIT] -- Scripts/

# Remove homebrew-releaser documentation
rm README.md
git checkout [PRE_HOMEBREW_RELEASER_COMMIT] -- README.md

git add .
git commit -m "rollback: restore complete webhook infrastructure"
git push origin main
```

## Validation Scripts

### Formula Integrity Validation

Create a script to validate formula integrity after rollback:

```bash
#!/bin/bash
# Scripts/validate-rollback.sh

echo "🔍 Validating rollback procedures..."

# Test 1: Verify workflow syntax
echo "1. Validating workflow syntax..."
gh workflow validate .github/workflows/release.yml
if [ $? -eq 0 ]; then
    echo "✅ Workflow syntax valid"
else
    echo "❌ Workflow syntax invalid"
    exit 1
fi

# Test 2: Check required secrets
echo "2. Checking required secrets..."
if [ "$ROLLBACK_LEVEL" = "full" ]; then
    gh secret list | grep WEBHOOK_TOKEN > /dev/null
    if [ $? -eq 0 ]; then
        echo "✅ WEBHOOK_TOKEN secret present"
    else
        echo "❌ WEBHOOK_TOKEN secret missing"
        exit 1
    fi
fi

# Test 3: Validate tap repository connectivity
echo "3. Testing tap repository connectivity..."
curl -s -f https://api.github.com/repos/beriberikix/homebrew-usbipd-mac > /dev/null
if [ $? -eq 0 ]; then
    echo "✅ Tap repository accessible"
else
    echo "❌ Tap repository not accessible"
    exit 1
fi

# Test 4: Formula syntax validation
echo "4. Validating current formula..."
if [ -d "/tmp/homebrew-test" ]; then rm -rf /tmp/homebrew-test; fi
git clone https://github.com/beriberikix/homebrew-usbipd-mac.git /tmp/homebrew-test
cd /tmp/homebrew-test
ruby -c Formula/usbipd-mac.rb
if [ $? -eq 0 ]; then
    echo "✅ Formula syntax valid"
else
    echo "❌ Formula syntax invalid"
    exit 1
fi

echo "✅ All rollback validations passed"
```

### End-to-End Testing Script

```bash
#!/bin/bash
# Scripts/test-rollback-e2e.sh

echo "🧪 Running end-to-end rollback validation..."

# Test installation workflow
echo "1. Testing installation workflow..."
brew untap beriberikix/usbipd-mac 2>/dev/null || true
brew tap beriberikix/usbipd-mac

if brew info usbipd-mac > /dev/null 2>&1; then
    echo "✅ Formula discoverable via tap"
else
    echo "❌ Formula not discoverable"
    exit 1
fi

# Test workflow trigger (dry run)
echo "2. Testing workflow trigger..."
if [ "$ROLLBACK_LEVEL" = "full" ]; then
    # Test webhook dispatch
    curl -X POST \
      -H "Authorization: token $WEBHOOK_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/beriberikix/homebrew-usbipd-mac/dispatches \
      -d '{"event_type": "test-rollback"}' \
      --fail --silent
    
    if [ $? -eq 0 ]; then
        echo "✅ Webhook dispatch successful"
    else
        echo "❌ Webhook dispatch failed"
        exit 1
    fi
fi

echo "✅ End-to-end rollback validation passed"
```

## Testing Rollback Procedures

### Safe Testing Environment

Before applying rollback in production:

1. **Fork Testing**: Test rollback procedures on repository forks
2. **Branch Testing**: Use feature branches for rollback testing
3. **Local Validation**: Run validation scripts locally first

### Testing Checklist

- [ ] **Workflow Validation**: YAML syntax and GitHub Actions validation
- [ ] **Secret Validation**: Required secrets are present and functional
- [ ] **Network Connectivity**: API endpoints and repositories accessible
- [ ] **Formula Integrity**: Formula syntax and Homebrew compatibility
- [ ] **End-to-End Flow**: Complete installation workflow functional

### Rollback Testing Commands

```bash
# Run validation suite
chmod +x Scripts/validate-rollback.sh
ROLLBACK_LEVEL=full ./Scripts/validate-rollback.sh

# Run end-to-end testing
chmod +x Scripts/test-rollback-e2e.sh
ROLLBACK_LEVEL=full WEBHOOK_TOKEN=your_token ./Scripts/test-rollback-e2e.sh

# Test formula installation
brew tap beriberikix/usbipd-mac
brew install --dry-run usbipd-mac
```

## Monitoring Post-Rollback

After performing rollback, monitor these metrics:

### Success Metrics
- [ ] **Workflow Success Rate**: >95% successful workflow executions
- [ ] **Formula Update Latency**: <10 minutes from release to formula update
- [ ] **User Installation Success**: No increase in installation failures
- [ ] **Error Rates**: No increase in GitHub Actions errors

### Monitoring Commands

```bash
# Monitor workflow executions
gh run list --workflow=release.yml --limit 5

# Check tap repository update frequency
gh api repos/beriberikix/homebrew-usbipd-mac/commits | jq '.[0:3] | .[] | {date: .commit.author.date, message: .commit.message}'

# Monitor user experience
brew tap beriberikix/usbipd-mac
brew info usbipd-mac
```

## Recovery and Re-Migration

If rollback is successful and issues are resolved, re-migration can be attempted:

1. **Fix Root Cause**: Address the issues that necessitated rollback
2. **Update Migration Plan**: Incorporate lessons learned
3. **Enhanced Testing**: More comprehensive testing before re-migration
4. **Gradual Re-Migration**: Consider phased approach for re-migration

## Emergency Contacts

For rollback-related emergencies:

- **Primary Maintainer**: For architectural decisions
- **DevOps Engineer**: For GitHub Actions and repository issues  
- **Community Manager**: For user communication during rollback

## Documentation Updates Post-Rollback

After rollback, update:

- [ ] **README.md**: Reflect current installation method
- [ ] **troubleshooting guides**: Update for current architecture
- [ ] **Release documentation**: Document rollback in release notes
- [ ] **Migration lessons learned**: Document issues and solutions

---

**Important**: This rollback documentation should be thoroughly tested in a safe environment before applying to production. Always have a backup plan and communicate with users about any temporary changes in installation procedures.