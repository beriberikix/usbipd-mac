# Branch Protection Configuration

This document outlines the required GitHub repository settings for branch protection and status checks to ensure code quality and prevent broken code from being merged to the main branch.

## Required Branch Protection Rules

The following branch protection rules must be configured for the `main` branch in the GitHub repository settings:

### 1. Require Status Checks to Pass Before Merging

Enable the following required status checks:
- `Code Quality (SwiftLint)` - Ensures code style compliance
- `Build Validation` - Validates project compilation
- `Unit Tests` - Ensures all unit tests pass
- `Integration Tests (QEMU)` - Validates end-to-end functionality

### 2. Require Branches to be Up to Date Before Merging

This ensures that pull requests are tested against the latest version of the main branch.

### 3. Require Pull Request Reviews Before Merging

Configure the following review requirements:
- **Required number of reviewers**: 1
- **Dismiss stale reviews when new commits are pushed**: Enabled
- **Require review from code owners**: Enabled (if CODEOWNERS file exists)

### 4. Restrict Pushes that Create Files

- **Restrict pushes that create files**: Enabled
- This prevents direct pushes to main branch

### 5. Allow Force Pushes

- **Allow force pushes**: Disabled
- This prevents force pushes that could overwrite history

### 6. Allow Deletions

- **Allow deletions**: Disabled
- This prevents accidental branch deletion

### 7. Bypass Settings for Administrators

Configure bypass permissions for repository administrators:
- **Allow administrators to bypass these settings**: Enabled
- **Require administrator approval for bypassing**: Enabled

This ensures that even administrators need explicit approval to bypass protection rules, maintaining code quality standards while allowing emergency fixes when necessary.

## Manual Configuration Steps

To configure these settings manually in GitHub:

1. Navigate to your repository on GitHub
2. Go to **Settings** → **Branches**
3. Click **Add rule** or edit existing rule for `main` branch
4. Configure the settings as outlined above
5. Save the branch protection rule

## Automated Configuration

Use the provided script to configure branch protection rules automatically:

```bash
# Make the script executable
chmod +x .github/scripts/configure-branch-protection.sh

# Run the configuration script
./.github/scripts/configure-branch-protection.sh
```

## Verification

After configuration, verify the settings by:

1. Creating a test pull request with failing checks
2. Confirming that merge is blocked until checks pass
3. Verifying that administrator approval is required for bypassing checks
4. Testing that all required status checks are enforced

## Status Check Names

The following status check names should be configured as required:
- `Code Quality (SwiftLint)`
- `Build Validation`
- `Unit Tests`
- `Integration Tests (QEMU)`

These names correspond to the job names defined in the CI workflow (`.github/workflows/ci.yml`).