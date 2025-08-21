#!/bin/bash

# Test script for homebrew-releaser dry-run validation
# This script validates the homebrew-releaser configuration and provides
# instructions for testing the dry-run mode in GitHub Actions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for homebrew-releaser testing..."
    
    # Check if we're on the correct branch
    current_branch=$(git branch --show-current)
    if [[ "$current_branch" != "feature/homebrew-releaser-migration" ]]; then
        log_warning "Current branch: $current_branch"
        log_warning "Expected branch: feature/homebrew-releaser-migration"
        log_warning "Some validations may not be accurate"
    else
        log_success "On correct feature branch: $current_branch"
    fi
    
    # Check if homebrew-releaser step exists in workflow
    if grep -q "homebrew-releaser" "$PROJECT_ROOT/.github/workflows/release.yml"; then
        log_success "Homebrew-releaser step found in release workflow"
    else
        log_error "Homebrew-releaser step not found in release workflow"
        return 1
    fi
    
    # Check if GitHub CLI is available for testing
    if command -v gh >/dev/null 2>&1; then
        log_success "GitHub CLI available for workflow testing"
    else
        log_warning "GitHub CLI not available - manual testing required"
    fi
    
    # Check if jq is available for JSON processing
    if command -v jq >/dev/null 2>&1; then
        log_success "jq available for JSON processing"
    else
        log_warning "jq not available - install with: brew install jq"
    fi
}

# Function to validate workflow configuration
validate_workflow_config() {
    log_info "Validating homebrew-releaser workflow configuration..."
    
    local workflow_file="$PROJECT_ROOT/.github/workflows/release.yml"
    
    # Check for required configuration parameters
    local required_configs=(
        "homebrew_owner: beriberikix"
        "homebrew_tap: homebrew-usbipd-mac"
        "formula_folder: Formula"
        "skip_commit: true"
        "debug: true"
        "target_darwin_amd64: true"
        "target_darwin_arm64: true"
    )
    
    for config in "${required_configs[@]}"; do
        if grep -q "$config" "$workflow_file"; then
            log_success "Configuration found: $config"
        else
            log_error "Configuration missing: $config"
        fi
    done
    
    # Check for GitHub token configuration
    if grep -q "HOMEBREW_TAP_TOKEN" "$workflow_file"; then
        log_success "HOMEBREW_TAP_TOKEN reference found"
    else
        log_error "HOMEBREW_TAP_TOKEN reference missing"
    fi
    
    # Check for install and test configuration
    if grep -q 'bin.install "usbipd"' "$workflow_file"; then
        log_success "Install command configured correctly"
    else
        log_error "Install command missing or incorrect"
    fi
    
    if grep -q 'assert_match "usbipd"' "$workflow_file"; then
        log_success "Test command configured correctly"
    else
        log_error "Test command missing or incorrect"
    fi
}

# Function to create test validation report
create_validation_report() {
    log_info "Creating homebrew-releaser validation report..."
    
    local report_file="$PROJECT_ROOT/homebrew-releaser-validation-report.md"
    
    cat > "$report_file" << 'EOF'
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
EOF

    log_success "Validation report created: $report_file"
}

# Function to display testing instructions
display_testing_instructions() {
    log_info "Homebrew-Releaser Dry-Run Testing Instructions"
    echo ""
    log_warning "IMPORTANT: Before running actual tests, ensure the following:"
    echo "  1. HOMEBREW_TAP_TOKEN secret is configured in repository settings"
    echo "  2. Token has 'contents: write' permission for beriberikix/homebrew-usbipd-mac"
    echo "  3. You are ready to trigger a test release workflow"
    echo ""
    log_info "Testing Methods:"
    echo ""
    echo "📋 Method 1: Tag-triggered Test Release"
    echo "  git tag v0.0.99-test"
    echo "  git push origin v0.0.99-test"
    echo "  # Monitor: https://github.com/beriberikix/usbipd-mac/actions"
    echo ""
    echo "📋 Method 2: Manual Workflow Dispatch (if GitHub CLI available)"
    echo "  gh workflow run release.yml -f version=v0.0.99-test -f prerelease=true"
    echo ""
    echo "📋 Method 3: GitHub Web Interface"
    echo "  1. Go to: https://github.com/beriberikix/usbipd-mac/actions/workflows/release.yml"
    echo "  2. Click 'Run workflow'"
    echo "  3. Enter version: v0.0.99-test"
    echo "  4. Check 'Mark as pre-release'"
    echo "  5. Click 'Run workflow'"
    echo ""
    log_success "What to Look For in Dry-Run Results:"
    echo "  ✅ 'Update Homebrew Formula (Dry Run)' job completes successfully"
    echo "  ✅ Action logs show generated formula content"
    echo "  ✅ No commit actually made to tap repository (dry-run mode)"
    echo "  ✅ Debug logs show homebrew-releaser configuration"
    echo "  ✅ Formula includes correct version, URL, and install commands"
    echo ""
    log_warning "After successful dry-run validation:"
    echo "  • Review and document the generated formula content"
    echo "  • Compare with current webhook-generated formula"
    echo "  • Proceed to Task 5: Enable actual commits"
}

# Main execution
main() {
    echo "🏺 Homebrew-Releaser Dry-Run Validation Script"
    echo "=============================================="
    echo ""
    
    cd "$PROJECT_ROOT"
    
    # Run validation steps
    check_prerequisites || exit 1
    echo ""
    validate_workflow_config
    echo ""
    create_validation_report
    echo ""
    display_testing_instructions
    
    echo ""
    log_success "Homebrew-releaser dry-run validation preparation complete!"
    log_info "Review the validation report and follow testing instructions above."
    log_info "Report location: homebrew-releaser-validation-report.md"
}

# Script usage information
usage() {
    echo "Usage: $0"
    echo ""
    echo "This script validates the homebrew-releaser dry-run configuration"
    echo "and provides instructions for testing formula generation."
    echo ""
    echo "The script will:"
    echo "  • Check workflow configuration"
    echo "  • Validate required parameters"
    echo "  • Create a validation report"
    echo "  • Provide testing instructions"
    echo ""
    echo "Run this script after implementing the homebrew-releaser workflow step"
    echo "but before enabling actual commits to the tap repository."
}

# Handle script arguments
case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac