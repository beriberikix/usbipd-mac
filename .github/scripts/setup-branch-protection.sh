#!/bin/bash

# GitHub Branch Protection Setup Script
# This script configures branch protection rules for the main branch
# to enforce CI checks and require maintainer approval for bypassing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BRANCH="main"
REQUIRED_CHECKS=(
    "Code Quality (SwiftLint)"
    "Build Validation"
    "Unit Tests"
    "Integration Tests (QEMU)"
)

echo -e "${BLUE}🔒 GitHub Branch Protection Setup${NC}"
echo "=================================================="

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ GitHub CLI (gh) is not installed${NC}"
    echo "Please install GitHub CLI: https://cli.github.com/"
    exit 1
fi

# Check if user is authenticated
if ! gh auth status &> /dev/null; then
    echo -e "${RED}❌ Not authenticated with GitHub CLI${NC}"
    echo "Please run: gh auth login"
    exit 1
fi

# Get repository information
REPO_INFO=$(gh repo view --json owner,name)
OWNER=$(echo "$REPO_INFO" | jq -r '.owner.login')
REPO_NAME=$(echo "$REPO_INFO" | jq -r '.name')

echo -e "${BLUE}📋 Repository: ${OWNER}/${REPO_NAME}${NC}"
echo -e "${BLUE}🌿 Branch: ${BRANCH}${NC}"

# Check current branch protection status
echo -e "\n${YELLOW}🔍 Checking current branch protection status...${NC}"
if gh api "repos/${OWNER}/${REPO_NAME}/branches/${BRANCH}/protection" &> /dev/null; then
    echo -e "${YELLOW}⚠️  Branch protection already exists. This will update the configuration.${NC}"
else
    echo -e "${GREEN}✅ No existing branch protection found. Creating new configuration.${NC}"
fi

# Prepare required status checks JSON
CONTEXTS_JSON=$(printf '%s\n' "${REQUIRED_CHECKS[@]}" | jq -R . | jq -s .)

echo -e "\n${BLUE}📝 Required Status Checks:${NC}"
for check in "${REQUIRED_CHECKS[@]}"; do
    echo "   • $check"
done

# Create branch protection configuration
echo -e "\n${YELLOW}🔧 Applying branch protection rules...${NC}"

# Build the protection configuration
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
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
)

# Apply the branch protection
if echo "$PROTECTION_CONFIG" | gh api "repos/${OWNER}/${REPO_NAME}/branches/${BRANCH}/protection" --method PUT --input -; then
    echo -e "${GREEN}✅ Branch protection rules applied successfully!${NC}"
else
    echo -e "${RED}❌ Failed to apply branch protection rules${NC}"
    exit 1
fi

echo -e "\n${GREEN}🎉 Branch Protection Configuration Complete!${NC}"
echo "=================================================="
echo -e "${BLUE}📋 Applied Settings:${NC}"
echo "   • Require pull request reviews (1 approval minimum)"
echo "   • Require status checks to pass before merging"
echo "   • Require branches to be up to date before merging"
echo "   • Enforce restrictions for administrators"
echo "   • Dismiss stale reviews when new commits are pushed"
echo "   • Prevent force pushes and branch deletions"

echo -e "\n${BLUE}🔒 Required Status Checks:${NC}"
for check in "${REQUIRED_CHECKS[@]}"; do
    echo "   ✓ $check"
done

echo -e "\n${YELLOW}⚠️  Important Notes:${NC}"
echo "   • Administrators cannot bypass these protection rules"
echo "   • All CI checks must pass before merging"
echo "   • At least 1 maintainer approval is required"
echo "   • This satisfies requirement 6.4 for maintainer approval"

echo -e "\n${BLUE}🔍 Verification:${NC}"
echo "   1. Create a test pull request"
echo "   2. Verify CI checks are required"
echo "   3. Confirm maintainer approval is needed"
echo "   4. Test that failed checks block merging"

echo -e "\n${GREEN}✅ Setup complete! Branch protection is now active.${NC}"
</text>
</invoke>