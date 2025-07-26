#!/bin/bash

# GitHub Branch Protection Configuration Script
# This script configures branch protection rules for the main branch
# Requires GitHub CLI (gh) to be installed and authenticated

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
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
    print_error "  brew install gh"
    print_error "  or visit: https://cli.github.com/"
    exit 1
fi

# Check if user is authenticated
if ! gh auth status &> /dev/null; then
    print_error "Not authenticated with GitHub CLI. Please run:"
    print_error "  gh auth login"
    exit 1
fi

print_status "Configuring branch protection rules for main branch..."

# Get repository information
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
print_status "Repository: $REPO"

# Configure branch protection rule
print_status "Setting up branch protection rule..."

# Create the branch protection rule with all required settings
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$REPO/branches/main/protection" \
  -f required_status_checks='{"strict":true,"contexts":["Code Quality (SwiftLint)","Build Validation","Unit Tests","Integration Tests (QEMU)"]}' \
  -f enforce_admins=true \
  -f required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true,"require_code_owner_reviews":false,"require_last_push_approval":false}' \
  -f restrictions=null \
  -f allow_force_pushes=false \
  -f allow_deletions=false \
  -f block_creations=false

if [ $? -eq 0 ]; then
    print_success "Branch protection rule configured successfully!"
else
    print_error "Failed to configure branch protection rule"
    exit 1
fi

print_status "Verifying branch protection configuration..."

# Verify the configuration
PROTECTION_STATUS=$(gh api "/repos/$REPO/branches/main/protection" --jq '.required_status_checks.contexts | length')

if [ "$PROTECTION_STATUS" -eq 4 ]; then
    print_success "All 4 required status checks are configured"
else
    print_warning "Expected 4 status checks, found $PROTECTION_STATUS"
fi

print_success "Branch protection configuration completed!"
print_status ""
print_status "Configured settings:"
print_status "  ✓ Required status checks: Code Quality, Build Validation, Unit Tests, Integration Tests"
print_status "  ✓ Require branches to be up to date before merging"
print_status "  ✓ Require pull request reviews (1 reviewer minimum)"
print_status "  ✓ Dismiss stale reviews when new commits are pushed"
print_status "  ✓ Enforce restrictions for administrators"
print_status "  ✓ Prevent force pushes"
print_status "  ✓ Prevent branch deletion"
print_status ""
print_status "To verify the configuration, visit:"
print_status "  https://github.com/$REPO/settings/branches"
print_status ""
print_warning "Note: Administrator approval is required to bypass these protection rules"
print_warning "This ensures code quality standards are maintained even for emergency fixes"