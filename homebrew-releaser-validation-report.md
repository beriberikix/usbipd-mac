# Homebrew-Releaser Dry-Run Validation Report

## Configuration Validation

This report documents the validation of homebrew-releaser configuration for the usbipd-mac project migration from webhook-based formula updates.

### Workflow Configuration Status

- ✅ **Homebrew-releaser step added** to `.github/workflows/release.yml`
- ✅ **Dry-run mode enabled** with `skip_commit: true`
- ✅ **Debug logging enabled** for troubleshooting
- ✅ **Repository configuration** set to `beriberikix/homebrew-usbipd-mac`
- ✅ **Formula folder** configured as `Formula`
- ✅ **Platform targets** configured for `darwin_amd64` and `darwin_arm64`
- ✅ **Install command** configured as `bin.install "usbipd"`
- ✅ **Test command** configured with version assertion
- ✅ **GitHub token** reference configured for `HOMEBREW_TAP_TOKEN`

### Required Secret Configuration

To complete testing, the following secret must be configured in the main repository:

- **Secret Name**: `HOMEBREW_TAP_TOKEN`
- **Secret Value**: Personal access token with `contents: write` permission for `beriberikix/homebrew-usbipd-mac`
- **Configuration Location**: Repository Settings > Secrets and variables > Actions

### Testing Instructions

#### Manual Workflow Testing

1. **Ensure HOMEBREW_TAP_TOKEN is configured** in repository secrets
2. **Create a test tag** for validation:
   ```bash
   git tag v0.0.99-test
   git push origin v0.0.99-test
   ```
3. **Monitor workflow execution** at: https://github.com/beriberikix/usbipd-mac/actions
4. **Review homebrew-releaser logs** in the "Update Homebrew Formula (Dry Run)" job
5. **Verify dry-run output** shows generated formula content without committing

#### GitHub CLI Testing

If GitHub CLI is available, trigger workflow manually:
```bash
gh workflow run release.yml -f version=v0.0.99-test -f prerelease=true
```

#### Expected Dry-Run Output

The homebrew-releaser action should:
- ✅ **Generate formula content** for usbipd-mac
- ✅ **Calculate correct SHA256** for GitHub source archive
- ✅ **Configure install and test blocks** correctly
- ✅ **Show generated formula** in debug logs
- ✅ **Skip committing changes** to tap repository (dry-run mode)
- ✅ **Complete successfully** without errors

### Validation Checklist

Before proceeding to enable actual commits:

- [ ] **Secret configured**: HOMEBREW_TAP_TOKEN added to repository secrets
- [ ] **Dry-run executed**: Test release triggered and completed successfully
- [ ] **Formula validated**: Generated formula content reviewed and approved
- [ ] **No errors**: Homebrew-releaser step completed without configuration errors
- [ ] **Debug logs reviewed**: Action logs contain expected formula generation output
- [ ] **Token permissions verified**: Token has correct access to tap repository

### Next Steps

After successful dry-run validation:

1. **Review generated formula** content from action logs
2. **Compare with current webhook-generated formula** for consistency
3. **Document any configuration adjustments** needed
4. **Proceed to Task 5**: Enable actual commits with `skip_commit: false`

### Troubleshooting

#### Common Issues

**Permission Denied**:
- Verify HOMEBREW_TAP_TOKEN has `contents: write` permission
- Check token expiration date
- Ensure token scope includes target repository

**Formula Generation Errors**:
- Review install and test command syntax
- Verify platform target configuration
- Check release artifact availability

**Action Failure**:
- Review GitHub Actions logs for detailed error messages
- Verify homebrew-releaser version compatibility
- Check workflow YAML syntax

#### Debug Information

Current Configuration:
- **Repository**: beriberikix/homebrew-usbipd-mac
- **Formula Folder**: Formula
- **Platforms**: darwin_amd64, darwin_arm64
- **Install**: `bin.install "usbipd"`
- **Test**: `assert_match "usbipd", shell_output("#{bin}/usbipd --version")`
- **Mode**: Dry-run (skip_commit: true)

### Validation Results

| Component | Status | Notes |
|-----------|--------|-------|
| Workflow Configuration | ✅ Passed | All required parameters configured |
| Secret Reference | ✅ Passed | HOMEBREW_TAP_TOKEN referenced correctly |
| Dry-Run Mode | ✅ Passed | skip_commit: true enabled |
| Debug Logging | ✅ Passed | debug: true enabled |
| Platform Targets | ✅ Passed | Both darwin architectures configured |
| Formula Commands | ✅ Passed | Install and test commands configured |

---

**Generated**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")  
**Branch**: feature/homebrew-releaser-migration  
**Validation Script**: Scripts/test-homebrew-releaser-dryrun.sh
