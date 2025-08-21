# Homebrew-Releaser Setup Guide

This document provides instructions for the homebrew-releaser GitHub Action configuration used for automated Homebrew formula updates.

## Overview

The homebrew-releaser action automates formula updates directly within the release workflow. This system has replaced the previous webhook-based infrastructure, providing a more reliable and simpler architecture for formula updates.

## Required GitHub Repository Secrets

### HOMEBREW_TAP_TOKEN

A personal access token (PAT) or fine-grained personal access token that grants the homebrew-releaser action permission to commit formula updates to the tap repository.

#### Token Requirements

**Repository**: `beriberikix/homebrew-usbipd-mac`
**Required Permissions**:
- `contents: write` - To update formula files
- `pull_requests: write` - To create/update pull requests (if using PR mode)
- `metadata: read` - To read repository metadata

#### Creating the Token

1. **Navigate to GitHub Settings**:
   - Go to GitHub.com > Settings > Developer settings > Personal access tokens

2. **Create Fine-Grained Token** (Recommended):
   - Click "Fine-grained tokens" > "Generate new token"
   - **Token name**: `homebrew-releaser-usbipd-mac`
   - **Expiration**: 1 year (or as per organization policy)
   - **Resource owner**: Select your account or organization
   - **Selected repositories**: Only `beriberikix/homebrew-usbipd-mac`
   - **Repository permissions**:
     - Contents: Write
     - Pull requests: Write (if using PR mode)
     - Metadata: Read

3. **Alternative: Classic Token**:
   - Click "Tokens (classic)" > "Generate new token (classic)"
   - **Note**: `homebrew-releaser-usbipd-mac`
   - **Expiration**: 1 year (or as per organization policy)
   - **Scopes**: 
     - `public_repo` (for public tap repository)
     - Or `repo` (if tap repository is private)

#### Adding Secret to Repository

1. **Navigate to Main Repository Settings**:
   - Go to `beriberikix/usbipd-mac` > Settings > Secrets and variables > Actions

2. **Add Repository Secret**:
   - Click "New repository secret"
   - **Name**: `HOMEBREW_TAP_TOKEN`
   - **Secret**: Paste the generated token value
   - Click "Add secret"

## Homebrew-Releaser Configuration

### Basic Configuration

The homebrew-releaser action will be configured in `.github/workflows/release.yml` with these parameters:

```yaml
- name: Update Homebrew Formula
  uses: Justintime50/homebrew-releaser@v1
  with:
    # Required
    homebrew_owner: beriberikix
    homebrew_tap: homebrew-usbipd-mac
    formula_folder: Formula
    github_token: ${{ secrets.HOMEBREW_TAP_TOKEN }}
    
    # Formula configuration
    install: |
      bin.install "usbipd"
    test: |
      assert_match "usbipd", shell_output("#{bin}/usbipd --version")
    
    # Release configuration
    target_darwin_amd64: true
    target_darwin_arm64: true
    update_readme_table: false
    
    # Commit configuration
    commit_owner: github-actions[bot]
    commit_email: 41898282+github-actions[bot]@users.noreply.github.com
```

### Advanced Configuration Options

**Dry Run Mode** (for testing):
```yaml
skip_commit: true  # Test formula generation without committing
debug: true        # Enable debug logging
```

**Pull Request Mode** (for review workflows):
```yaml
create_pullrequest: true
pullrequest_reviewer: maintainer-username
```

## Configuration Status

### Configuration Checklist

- [x] `HOMEBREW_TAP_TOKEN` created with required permissions
- [x] Token added to main repository secrets
- [x] Token permissions verified against tap repository
- [x] Homebrew-releaser configured in release workflow
- [x] Webhook system removed from main repository

### Testing and Validation

1. **Test Token Access**:
```bash
# Test token permissions (run locally with token)
curl -H "Authorization: token YOUR_TOKEN" \
  https://api.github.com/repos/beriberikix/homebrew-usbipd-mac
```

2. **Dry Run Testing**:
   - Configure homebrew-releaser with `skip_commit: true`
   - Trigger test release to validate formula generation
   - Review generated formula output in action logs

3. **Production Validation**:
   - Monitor release workflow execution
   - Verify formula updates in tap repository
   - Test user installation: `brew upgrade usbipd-mac`

## Security Considerations

### Token Security

- **Minimal Permissions**: Use fine-grained tokens with minimal required permissions
- **Repository Scope**: Limit token access to only the tap repository
- **Regular Rotation**: Rotate tokens annually or per security policy
- **Audit Access**: Monitor token usage through GitHub audit logs

### Commit Attribution

- **Bot Attribution**: Use GitHub Actions bot email for commit attribution
- **Signed Commits**: Consider enabling commit signing for tap repository
- **Audit Trail**: Maintain clear audit trail for formula updates

## Troubleshooting and Recovery

### Formula Update Failures

If homebrew-releaser fails or causes issues:

1. **Review Action Logs**:
   - Check GitHub Actions logs for homebrew-releaser step
   - Review token permissions and repository access
   - Validate formula syntax and configuration

2. **Manual Formula Updates**:
   - Clone tap repository locally
   - Update formula manually with correct version and SHA256
   - Commit and push changes directly

3. **Temporary Workarounds**:
   - Comment out homebrew-releaser step in workflow
   - Update formula manually until issues are resolved
   - Re-enable automated updates after fixes

### Recovery Procedures

For persistent issues with homebrew-releaser:

1. **Validate Configuration**:
   - Check `HOMEBREW_TAP_TOKEN` permissions
   - Verify homebrew-releaser action version
   - Review formula template parameters

2. **Manual Intervention**:
   - Update formula directly in tap repository
   - Use workflow_dispatch to manually trigger updates
   - Monitor for resolution of underlying issues

## Monitoring and Maintenance

### Success Monitoring

- **Release Workflow Logs**: Monitor homebrew-releaser step execution
- **Tap Repository**: Verify formula commits appear correctly
- **Formula Validation**: Test `brew install usbipd-mac` after updates

### Failure Handling

- **Action Failures**: Review GitHub Actions logs for homebrew-releaser errors
- **Permission Issues**: Check token permissions and expiration
- **Formula Errors**: Validate generated formula syntax and dependencies

### Regular Maintenance

- **Token Rotation**: Schedule annual token rotation
- **Permission Review**: Quarterly review of token permissions
- **Configuration Updates**: Update homebrew-releaser version and configuration as needed

## Troubleshooting

### Common Issues

**Token Permission Errors**:
- Verify token has `contents: write` permission
- Check token expiration date
- Ensure token scope includes target repository

**Formula Generation Errors**:
- Review homebrew-releaser configuration syntax
- Validate formula template parameters
- Check release artifact availability

**Commit Failures**:
- Verify commit author configuration
- Check for branch protection rules
- Ensure no conflicts with concurrent updates

### Debug Mode

Enable debug logging for troubleshooting:
```yaml
debug: true
skip_commit: true  # For safe debugging
```

## Documentation References

- **Homebrew-Releaser**: https://github.com/Justintime50/homebrew-releaser
- **GitHub Personal Access Tokens**: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token
- **GitHub Actions Secrets**: https://docs.github.com/en/actions/security-guides/encrypted-secrets
- **Homebrew Formula**: https://docs.brew.sh/Formula-Cookbook

---

**Implementation Status**: Completed - homebrew-releaser is active and webhook system has been fully removed.