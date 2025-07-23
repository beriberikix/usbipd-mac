#!/bin/bash

# GitHub Branch Protection Setup Script
# This script configures required status checks for the main branch

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    print_error "GitHub CLI (gh) is not installed. Please install it first:"
    echo "  brew install gh"
    echo "  or visit: https://cli.github.com/"
    exit 1
fi

# Check if user is authenticated
if ! gh auth status &> /dev/null; then
    print_error "Not authenticated with GitHub CLI. Please run:"
    echo "  gh auth login"
    exit 1
fi

# Get repository information
REPO_INFO=$(gh repo view --json owner,name)
OWNER=$(echo "$REPO_INFO" | jq -r '.owner.login')
REPO_NAME=$(echo "$REPO_INFO" | jq -r '.name')

print_status "Configuring branch protection for $OWNER/$REPO_NAME"

# Required status checks based on CI workflow
STATUS_CHECKS=(
    "Code Quality (SwiftLint)"
    "Build Validation"
    "Unit Tests"
    "Integration Tests (QEMU)"
)

print_status "Required status checks:"
for check in "${STATUS_CHECKS[@]}"; do
    echo "  - $check"
done

# Create JSON array for status checks
STATUS_CHECKS_JSON=$(printf '%s\n' "${STATUS_CHECKS[@]}" | jq -R . | jq -s .)

# Configure branch protection
print_status "Applying branch protection rules to main branch..."

# Create the branch protection configuration
PROTECTION_CONFIG=$(cat <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": $STATUS_CHECKS_JSON
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
)

# Apply the configuration using GitHub API
if gh api "repos/$OWNER/$REPO_NAME/branches/main/protection" \
    --method PUT \
    --input - <<< "$PROTECTION_CONFIG"; then
    print_status "Branch protection configured successfully!"
else
    print_error "Failed to configure branch protection"
    exit 1
fi

print_status "Branch protection summary:"
echo "  ✅ Required status checks: ${#STATUS_CHECKS[@]} checks configured"
echo "  ✅ Require branches to be up to date: enabled"
echo "  ✅ Required pull request reviews: 1 approval required"
echo "  ✅ Dismiss stale reviews: enabled"
echo "  ✅ Force pushes: disabled"
echo "  ✅ Branch deletions: disabled"

print_status "Verification steps:"
echo "  1. Create a test pull request"
echo "  2. Verify that merging is blocked until all checks pass"
echo "  3. Confirm all 4 status checks appear in the PR"
echo "  4. Test that PR can only be merged when checks are green"

print_warning "Note: Admin enforcement is disabled to allow repository maintainers to bypass restrictions if needed"
print_status "Branch protection setup complete!"