# Webhook Configuration Guide

This document provides step-by-step instructions for configuring the webhook integration between the main repository (usbipd-mac) and the tap repository (homebrew-usbipd-mac) to enable automatic formula updates when new releases are published.

## Overview

The webhook integration enables the pull-based architecture where:
1. **Main Repository** publishes releases with metadata
2. **GitHub Webhooks** automatically notify the tap repository
3. **Tap Repository** receives the webhook and updates the formula

## Prerequisites

Before configuring webhooks, ensure you have:

- [x] **Admin access** to both repositories (usbipd-mac and homebrew-usbipd-mac)
- [x] **Formula update workflow** deployed to tap repository (`.github/workflows/formula-update.yml`)
- [x] **Formula template** created in tap repository (`Formula/usbipd-mac.rb`)
- [x] **Personal Access Token** with appropriate permissions (if needed for private repositories)

## Webhook Configuration Steps

### Step 1: Access Main Repository Webhook Settings

1. Navigate to the main repository: `https://github.com/beriberikix/usbipd-mac`
2. Click on **Settings** tab
3. In the left sidebar, click **Webhooks**
4. Click **Add webhook** button

### Step 2: Configure Webhook Details

#### Basic Configuration
- **Payload URL**: `https://api.github.com/repos/beriberikix/homebrew-usbipd-mac/dispatches`
- **Content type**: `application/json`
- **Secret**: (Leave empty for public repositories, or use shared secret for enhanced security)

#### Event Selection
- **Which events would you like to trigger this webhook?**
  - Select **Let me select individual events**
  - **Uncheck** "Pushes" (default)
  - **Check** "Releases" 
  - **Uncheck** all other events

#### Active Status
- **Check** "Active" to enable the webhook

### Step 3: Webhook Payload Format

The webhook will send a payload in this format when a release is published:

```json
{
  "action": "published",
  "release": {
    "tag_name": "v1.2.3",
    "name": "Release v1.2.3",
    "published_at": "2025-08-20T12:00:00Z",
    "assets": [
      {
        "name": "homebrew-metadata.json",
        "browser_download_url": "https://github.com/beriberikix/usbipd-mac/releases/download/v1.2.3/homebrew-metadata.json"
      }
    ]
  },
  "repository": {
    "full_name": "beriberikix/usbipd-mac",
    "html_url": "https://github.com/beriberikix/usbipd-mac"
  }
}
```

### Step 4: Configure Repository Dispatch Handler

Since GitHub webhooks cannot directly trigger `workflow_dispatch` events in external repositories, we need to use the repository dispatch mechanism.

#### Option A: Using GitHub Actions (Recommended)

Create a repository dispatch action in the main repository:

```yaml
# In main repository: .github/workflows/release.yml
- name: Trigger Tap Repository Update
  if: github.event_name == 'release'
  run: |
    curl -X POST \
      -H "Authorization: token ${{ secrets.TAP_REPO_TOKEN }}" \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/beriberikix/homebrew-usbipd-mac/dispatches \
      -d '{
        "event_type": "release-published",
        "client_payload": {
          "repository": "${{ github.repository }}",
          "release": {
            "tag_name": "${{ github.event.release.tag_name }}",
            "published_at": "${{ github.event.release.published_at }}"
          }
        }
      }'
```

#### Option B: Using External Webhook Service

For more complex scenarios, you can use services like:
- **GitHub Apps** with webhook endpoints
- **Zapier** or **IFTTT** for webhook forwarding
- **Custom webhook forwarder** deployed to cloud services

### Step 5: Configure Tap Repository to Receive Dispatches

The tap repository is already configured to receive `repository_dispatch` events in the formula update workflow:

```yaml
# .github/workflows/formula-update.yml (already implemented)
on:
  repository_dispatch:
    types: [release-published]
  workflow_dispatch:
    inputs:
      version:
        description: 'Release version to process (e.g., v1.2.3)'
        required: true
        type: string
```

### Step 6: Required Secrets Configuration

#### Main Repository Secrets

If using Option A above, add to main repository secrets:

- **Secret Name**: `TAP_REPO_TOKEN`
- **Secret Value**: Personal Access Token with `repo` scope for tap repository
- **Scope**: `public_repo` (for public tap repository) or `repo` (for private tap repository)

#### Tap Repository Secrets

The tap repository needs these secrets (already configured via `GITHUB_TOKEN`):

- **GITHUB_TOKEN**: Automatically provided by GitHub Actions (no manual configuration needed)
- Permissions: `contents: read` and `actions: write` for the tap repository

### Step 7: Testing the Webhook Integration

#### Manual Testing Steps

1. **Create a test release** in the main repository:
   ```bash
   # Tag and push a test release
   git tag v1.2.4-test
   git push origin v1.2.4-test
   
   # Create release via GitHub CLI
   gh release create v1.2.4-test --generate-notes --prerelease
   ```

2. **Verify webhook delivery**:
   - Go to main repository Settings > Webhooks
   - Click on the webhook you created
   - Check **Recent Deliveries** tab
   - Verify successful delivery (green checkmark)

3. **Check tap repository workflow**:
   - Go to tap repository Actions tab
   - Look for "Formula Update" workflow run
   - Verify it was triggered by the repository dispatch

4. **Verify formula update**:
   - Check that `Formula/usbipd-mac.rb` was updated with new version
   - Verify commit was created with automatic message

#### Automated Testing Script

Create a test script to validate the integration:

```bash
#!/bin/bash
# Test webhook integration

echo "Testing webhook integration..."

# Check main repository webhook status
echo "1. Checking main repository webhook configuration..."
gh api repos/beriberikix/usbipd-mac/hooks

# Check tap repository workflow file
echo "2. Verifying tap repository workflow..."
gh api repos/beriberikix/homebrew-usbipd-mac/contents/.github/workflows/formula-update.yml

# Test repository dispatch (requires TAP_REPO_TOKEN)
echo "3. Testing repository dispatch..."
gh api repos/beriberikix/homebrew-usbipd-mac/dispatches \
  -f event_type=release-published \
  -f client_payload='{"repository":"beriberikix/usbipd-mac","release":{"tag_name":"v1.2.4-test"}}'

echo "✅ Webhook integration test completed"
```

## Monitoring and Troubleshooting

### Webhook Delivery Monitoring

1. **Main Repository**: Settings > Webhooks > [Your Webhook] > Recent Deliveries
2. **Tap Repository**: Actions tab > Formula Update workflow runs
3. **Logs**: Check workflow run logs for detailed error information

### Common Issues and Solutions

#### Issue: Webhook not triggering
- **Cause**: Webhook URL incorrect or repository dispatch not configured
- **Solution**: Verify webhook URL and ensure `repository_dispatch` trigger is in workflow

#### Issue: Authentication errors  
- **Cause**: Missing or invalid `TAP_REPO_TOKEN`
- **Solution**: Generate new personal access token with correct scopes

#### Issue: Workflow not running
- **Cause**: Workflow file syntax errors or missing trigger configuration
- **Solution**: Validate YAML syntax and check workflow triggers

#### Issue: Formula not updating
- **Cause**: Metadata not found or validation failures
- **Solution**: Check metadata generation in main repository and validation logs

### Webhook Security Considerations

1. **Secret Validation**: Use webhook secrets to validate payload authenticity
2. **Token Permissions**: Use minimal required permissions for personal access tokens
3. **Repository Visibility**: Consider private repositories for sensitive configurations
4. **Audit Logging**: Monitor webhook deliveries and workflow executions

## Advanced Configuration

### Custom Event Types

You can create custom event types for different scenarios:

```yaml
on:
  repository_dispatch:
    types: 
      - release-published    # Production releases
      - prerelease-published # Beta/RC releases  
      - hotfix-published     # Emergency hotfixes
```

### Conditional Processing

Add conditions to handle different release types:

```yaml
jobs:
  update-formula:
    if: github.event.client_payload.release.prerelease != true
    # Only process non-prerelease versions
```

### Multi-Repository Support

Scale to support multiple tap repositories:

```yaml
strategy:
  matrix:
    tap_repo: 
      - beriberikix/homebrew-usbipd-mac
      - beriberikix/homebrew-experimental
```

## Deployment Checklist

Before deploying to production:

- [ ] Webhook configured in main repository
- [ ] Repository dispatch integration tested
- [ ] Personal access token configured with minimal permissions
- [ ] Tap repository workflow validates incoming events
- [ ] Formula template contains proper placeholder tokens
- [ ] End-to-end integration tested with test release
- [ ] Monitoring and alerting configured
- [ ] Rollback procedures documented
- [ ] Team access and permissions reviewed

## Maintenance

### Regular Tasks

1. **Monthly**: Review webhook delivery logs and success rates
2. **Quarterly**: Rotate personal access tokens for security
3. **Per Release**: Monitor first few automatic updates after major changes
4. **Annual**: Review and update webhook configuration documentation

### Updates and Changes

When updating the webhook configuration:

1. Test changes in a fork or staging environment first
2. Coordinate with team members about downtime during updates
3. Update this documentation with any configuration changes
4. Verify integration still works after GitHub API changes

## Support and Documentation

- **GitHub Webhooks Documentation**: https://docs.github.com/en/developers/webhooks-and-events/webhooks
- **Repository Dispatch Documentation**: https://docs.github.com/en/rest/repos/repos#create-a-repository-dispatch-event
- **GitHub Actions Workflow Syntax**: https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions
- **Project Issues**: https://github.com/beriberikix/usbipd-mac/issues
- **Formula Update Workflow**: `.github/workflows/formula-update.yml`

---

**Note**: This configuration establishes the webhook integration for automatic formula updates. The actual webhook setup must be performed in the GitHub UI following the steps above. Manual testing should be performed to verify the integration before relying on it for production releases.