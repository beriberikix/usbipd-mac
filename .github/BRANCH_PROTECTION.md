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
7. Enable **Restrict pushes that create files that do not exist in the current branch**
8. Save the branch protection rule

### Via GitHub CLI (Alternative)

If you have GitHub CLI installed, you can configure branch protection using:

```bash
# Enable branch protection with required status checks
gh api repos/:owner/:repo/branches/main/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["Code Quality (SwiftLint)","Build Validation","Unit Tests","Integration Tests (QEMU)"]}' \
  --field enforce_admins=true \
  --field required_pull_request_reviews='{"required_approving_review_count":1}' \
  --field restrictions=null
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
      "required_approving_review_count": 1
    },
    "restrictions": null
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
- **Status is clearly visible** in the PR interface showing which checks are pending/passing/failing

## Troubleshooting

If status checks are not appearing:
1. Ensure the workflow has run at least once on a PR
2. Check that job names in the workflow match the configured status check names exactly
3. Verify the workflow is triggered on `pull_request` events
4. Confirm the workflow file is in the correct location (`.github/workflows/ci.yml`)

## Requirements Addressed

This configuration addresses the following requirements:

- **Requirement 6.1**: Pull requests with failing checks are prevented from merging
- **Requirement 6.2**: Pull requests with passing checks are allowed to merge
- **Requirement 6.3**: Check status is clearly reported during execution (handled by workflow design)
- **Requirement 6.4**: Maintainer approval can bypass checks (configurable via branch protection settings)