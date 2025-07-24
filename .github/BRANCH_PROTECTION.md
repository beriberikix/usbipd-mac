# Branch Protection Configuration

This document provides instructions for configuring required status checks for the GitHub Actions CI pipeline.

## Required Status Checks

The following status checks must be configured as required in the GitHub repository settings to ensure pull requests cannot be merged with failing checks:

### Status Check Names
Based on the CI workflow (`.github/workflows/ci.yml`), the following job names should be configured as required status checks:

1. **Code Quality (SwiftLint)** - `lint`
2. **Build Validation** - `build` 
3. **Unit Tests** - `test`
4. **Integration Tests (QEMU)** - `integration-test`

## Configuration Steps

### Via GitHub Web Interface

1. Navigate to your repository on GitHub
2. Go to **Settings** → **Branches**
3. Click **Add rule** or edit the existing rule for the `main` branch
4. Enable **Require status checks to pass before merging**
5. Enable **Require branches to be up to date before merging**
6. In the status checks search box, add each of the following:
   - `Code Quality (SwiftLint)`
   - `Build Validation`
   - `Unit Tests`
   - `Integration Tests (QEMU)`
7. Enable **Require pull request reviews before merging**
   - Set **Required number of reviewers before merging** to **1**
   - Enable **Dismiss stale pull request approvals when new commits are pushed**
   - Enable **Require review from code owners** (if CODEOWNERS file exists)
8. Enable **Restrict pushes that create files that do not exist in the current branch**
9. Enable **Do not allow bypassing the above settings** (enforces rules for administrators)
10. Disable **Allow force pushes** and **Allow deletions** for additional protection
11. Save the branch protection rule

### Via Setup Script (Recommended)

The easiest way to configure branch protection is using the provided setup script:

```bash
# Run the automated setup script
./.github/scripts/setup-branch-protection.sh

# Validate the configuration
./.github/scripts/validate-branch-protection.sh
```

### Via GitHub CLI (Alternative)

If you have GitHub CLI installed, you can configure branch protection using:

```bash
# Enable branch protection with required status checks and approval requirements
gh api repos/:owner/:repo/branches/main/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["Code Quality (SwiftLint)","Build Validation","Unit Tests","Integration Tests (QEMU)"]}' \
  --field enforce_admins=true \
  --field required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_code_owner_reviews":true}' \
  --field restrictions=null \
  --field allow_force_pushes=false \
  --field allow_deletions=false
```

### Via GitHub API (Alternative)

You can also configure branch protection using the GitHub REST API:

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
      "dismiss_stale_reviews": true,
      "require_code_owner_reviews": true,
      "require_last_push_approval": false
    },
    "restrictions": null,
    "allow_force_pushes": false,
    "allow_deletions": false,
    "block_creations": false
  }'
```

## Verification

After configuring branch protection:

1. Create a test pull request
2. Verify that the PR shows "Merging is blocked" until all checks pass
3. Confirm that each of the 4 status checks appears in the PR status section
4. Test that the PR can only be merged when all checks are green

## Status Check Behavior

With these settings configured:

- **Pull requests cannot be merged** if any of the 4 required checks fail
- **Branches must be up to date** with main before merging
- **All 4 checks must pass** for the merge button to become available
- **At least 1 maintainer approval** is required before merging
- **Administrators cannot bypass** these requirements without explicit approval
- **Stale reviews are dismissed** when new commits are pushed
- **Status is clearly visible** in the PR interface showing which checks are pending/passing/failing
- **Force pushes and branch deletions** are blocked for additional protection

## Troubleshooting

If status checks are not appearing:
1. Ensure the workflow has run at least once on a PR
2. Check that job names in the workflow match the configured status check names exactly
3. Verify the workflow is triggered on `pull_request` events
4. Confirm the workflow file is in the correct location (`.github/workflows/ci.yml`)

## Requirements Addressed

This configuration addresses the following requirements:

- **Requirement 6.1**: Pull requests with failing checks are prevented from merging
- **Requirement 6.2**: Pull requests with passing checks are allowed to merge (with maintainer approval)
- **Requirement 6.3**: Check status is clearly reported during execution (handled by workflow design)
- **Requirement 6.4**: Maintainer approval is required for bypassing checks (enforced via branch protection)

## Approval Requirements for Bypassing Checks

The branch protection configuration includes specific settings to ensure maintainer oversight:

### Review Requirements
- **Required approving reviews**: 1 maintainer must approve before merging
- **Dismiss stale reviews**: Approvals are dismissed when new commits are pushed
- **Code owner reviews**: Required when CODEOWNERS file is present
- **Administrator enforcement**: Admins cannot bypass without following the approval process

### Bypass Prevention
- **Enforce for administrators**: Prevents admins from bypassing protection rules
- **Force push protection**: Blocks force pushes that could bypass checks
- **Branch deletion protection**: Prevents accidental or malicious branch deletion

### Approval Workflow
1. Developer creates pull request
2. All 4 status checks must pass (lint, build, unit tests, integration tests)
3. At least 1 maintainer must review and approve the changes
4. Branch must be up to date with main before merging
5. Only then can the pull request be merged

This ensures that even if checks could theoretically be bypassed, maintainer approval acts as a safeguard to maintain code quality and project stability.