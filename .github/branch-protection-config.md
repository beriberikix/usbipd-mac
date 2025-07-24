# Branch Protection Configuration

This document outlines the required GitHub repository settings to implement branch protection and approval requirements for bypassing CI checks.

## Required Branch Protection Settings

The following settings must be configured for the `main` branch through GitHub's repository settings:

### Branch Protection Rules for `main`

1. **Require a pull request before merging**
   - ✅ Enable this setting
   - Require approvals: 1 (minimum)
   - Dismiss stale PR approvals when new commits are pushed: ✅ Recommended

2. **Require status checks to pass before merging**
   - ✅ Enable this setting
   - Require branches to be up to date before merging: ✅ Enable
   - Required status checks:
     - `Code Quality (SwiftLint)`
     - `Build Validation`
     - `Unit Tests`
     - `Integration Tests (QEMU)`

3. **Require conversation resolution before merging**
   - ✅ Enable this setting (recommended)

4. **Require signed commits**
   - ⚠️ Optional (based on project security requirements)

5. **Require linear history**
   - ⚠️ Optional (based on project workflow preferences)

6. **Allow force pushes**
   - ❌ Disable this setting

7. **Allow deletions**
   - ❌ Disable this setting

### Administrator Override Settings

To satisfy requirement 6.4 (maintainer approval for bypassing checks):

1. **Do not allow bypassing the above settings**
   - ❌ Disable this setting to prevent administrators from bypassing protection rules
   - This ensures that even maintainers must follow the same rules

2. **Restrict pushes that create files**
   - ⚠️ Optional additional security measure

## Implementation Steps

### Via GitHub Web Interface

1. Navigate to repository Settings → Branches
2. Click "Add rule" or edit existing rule for `main` branch
3. Configure the settings as outlined above
4. Save the branch protection rule

### Via GitHub CLI (Alternative)

```bash
# Enable branch protection with required status checks
gh api repos/:owner/:repo/branches/main/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["Code Quality (SwiftLint)","Build Validation","Unit Tests","Integration Tests (QEMU)"]}' \
  --field enforce_admins=true \
  --field required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true}' \
  --field restrictions=null
```

### Via GitHub API (Alternative)

```bash
curl -X PUT \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token YOUR_TOKEN" \
  https://api.github.com/repos/OWNER/REPO/branches/main/protection \
  -d '{
    "required_status_checks": {
      "strict": true,
      "contexts": [
        "Code Quality (SwiftLint)",
        "Build Validation", 
        "Unit Tests",
        "Integration Tests (QEMU)"
      ]
    },
    "enforce_admins": true,
    "required_pull_request_reviews": {
      "required_approving_review_count": 1,
      "dismiss_stale_reviews": true
    },
    "restrictions": null
  }'
```

## Verification

After applying these settings, verify the configuration by:

1. Creating a test pull request
2. Confirming that the PR cannot be merged without:
   - All status checks passing
   - At least one approval from a maintainer
3. Verifying that administrators cannot bypass these requirements

## Status Check Names

The following status check names must match exactly with the job names in `.github/workflows/ci.yml`:

- `Code Quality (SwiftLint)` - Maps to the `lint` job
- `Build Validation` - Maps to the `build` job  
- `Unit Tests` - Maps to the `test` job
- `Integration Tests (QEMU)` - Maps to the `integration-test` job

## Maintainer Approval Process

When checks fail or need to be bypassed:

1. **Normal Process**: Fix the failing checks and push new commits
2. **Emergency Bypass**: 
   - Requires explicit approval from repository maintainers
   - Maintainer must review the specific reason for bypass
   - Approval must be documented in PR comments
   - Follow-up issue should be created to address the underlying problem

This configuration ensures compliance with requirement 6.4: "IF checks are skipped or bypassed THEN the system SHALL require explicit approval from maintainers"
</text>
</invoke>