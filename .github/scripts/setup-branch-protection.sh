#!/bin/bash

# GitHub Branch Protection Setup Script
# This script configures branch protection with required status checks and approval requirements

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_check() {
    echo -e "${BLUE}[SETUP]${NC} $1"
}

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    print_error "GitHub CLI (gh) is not installed. Please install it first:"
    echo "  brew install gh"
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

print_status "Setting up branch protection for $OWNER/$REPO_NAME"

# Required status checks based on CI workflow job names
REQUIRED_CHECKS=(
    "Code Quality (SwiftLint)"
    "Build Validation"
    "Unit Tests"
    "Integration Tests (QEMU)"
)

print_check "Configuring branch protection with the following settings:"
echo "  Branch: main"
echo "  Required status checks: ${#REQUIRED_CHECKS[@]} checks"
for check in "${REQUIRED_CHECKS[@]}"; do
    echo "    - $check"
done
echo "  Strict status checks: enabled (branches must be up to date)"
echo "  Required reviews: 1 (maintainer approval required)"
echo "  Dismiss stale reviews: enabled"
echo "  Require review from code owners: enabled"
echo "  Enforce for administrators: enabled (admins cannot bypass without approval)"
echo "  Allow force pushes: disabled"
echo "  Allow deletions: disabled"

# Confirm before proceeding
echo ""
read -p "Do you want to proceed with this configuration? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Branch protection setup cancelled by user"
    exit 0
fi

# Build the contexts array for the API call
CONTEXTS_JSON=$(printf '%s\n' "${REQUIRED_CHECKS[@]}" | jq -R . | jq -s .)

print_check "Applying branch protection settings..."

# Configure branch protection using GitHub API
PROTECTION_CONFIG=$(cat <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": $CONTEXTS_JSON
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
}
EOF
)

if gh api "repos/$OWNER/$REPO_NAME/branches/main/protection" \
    --method PUT \
    --input - <<< "$PROTECTION_CONFIG"; then
    
    print_status "✅ Branch protection configured successfully!"
    echo ""
    echo "Configuration summary:"
    echo "  ✅ Required status checks: ${#REQUIRED_CHECKS[@]} checks configured"
    echo "  ✅ Strict mode: enabled (branches must be up to date)"
    echo "  ✅ Required reviews: 1 maintainer approval required"
    echo "  ✅ Dismiss stale reviews: enabled"
    echo "  ✅ Code owner reviews: required when applicable"
    echo "  ✅ Enforce for admins: enabled"
    echo "  ✅ Force pushes: blocked"
    echo "  ✅ Branch deletions: blocked"
    echo ""
    echo "Requirements addressed:"
    echo "  ✅ 6.1: PRs with failing checks cannot be merged"
    echo "  ✅ 6.2: PRs with passing checks can be merged"
    echo "  ✅ 6.3: Check status is clearly reported (handled by workflow)"
    echo "  ✅ 6.4: Maintainer approval required for bypassing checks"
    echo ""
    echo "Next steps:"
    echo "  1. Run validation: .github/scripts/validate-branch-protection.sh"
    echo "  2. Create a test PR to verify the configuration"
    echo "  3. Ensure team members understand the new requirements"
    
else
    print_error "❌ Failed to configure branch protection"
    echo ""
    echo "Possible causes:"
    echo "  - Insufficient permissions (admin access required)"
    echo "  - Repository settings prevent branch protection changes"
    echo "  - Network connectivity issues"
    echo "  - Invalid configuration format"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify you have admin access to the repository"
    echo "  2. Check repository settings for any restrictions"
    echo "  3. Try running the command again"
    echo "  4. Configure manually via GitHub Settings → Branches"
    exit 1
fi