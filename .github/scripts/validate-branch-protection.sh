#!/bin/bash

# GitHub Branch Protection Validation Script
# This script validates that required status checks are properly configured

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
    echo -e "${BLUE}[CHECK]${NC} $1"
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

print_status "Validating branch protection for $OWNER/$REPO_NAME"

# Expected status checks
EXPECTED_CHECKS=(
    "Code Quality (SwiftLint)"
    "Build Validation"
    "Unit Tests"
    "Integration Tests (QEMU)"
)

# Get current branch protection settings
print_check "Fetching branch protection settings for main branch..."

if ! PROTECTION_DATA=$(gh api "repos/$OWNER/$REPO_NAME/branches/main/protection" 2>/dev/null); then
    print_error "Failed to fetch branch protection settings"
    print_warning "This could mean:"
    echo "  - Branch protection is not configured"
    echo "  - You don't have permission to view settings"
    echo "  - The main branch doesn't exist"
    exit 1
fi

# Parse the protection data
REQUIRED_CHECKS=$(echo "$PROTECTION_DATA" | jq -r '.required_status_checks.contexts[]?' 2>/dev/null || echo "")
STRICT_MODE=$(echo "$PROTECTION_DATA" | jq -r '.required_status_checks.strict' 2>/dev/null || echo "false")
ENFORCE_ADMINS=$(echo "$PROTECTION_DATA" | jq -r '.enforce_admins.enabled' 2>/dev/null || echo "false")
REQUIRED_REVIEWS=$(echo "$PROTECTION_DATA" | jq -r '.required_pull_request_reviews.required_approving_review_count' 2>/dev/null || echo "0")

print_status "Current branch protection configuration:"
echo "  Strict status checks: $STRICT_MODE"
echo "  Enforce for admins: $ENFORCE_ADMINS"
echo "  Required reviews: $REQUIRED_REVIEWS"

# Validate required status checks
print_check "Validating required status checks..."

VALIDATION_PASSED=true

if [ -z "$REQUIRED_CHECKS" ]; then
    print_error "No required status checks configured"
    VALIDATION_PASSED=false
else
    print_status "Currently required status checks:"
    echo "$REQUIRED_CHECKS" | while read -r check; do
        if [ -n "$check" ]; then
            echo "  ✓ $check"
        fi
    done
fi

# Check each expected status check
print_check "Verifying all expected status checks are required..."

for expected_check in "${EXPECTED_CHECKS[@]}"; do
    if echo "$REQUIRED_CHECKS" | grep -q "^$expected_check$"; then
        echo "  ✅ $expected_check - CONFIGURED"
    else
        echo "  ❌ $expected_check - MISSING"
        VALIDATION_PASSED=false
    fi
done

# Check for unexpected status checks
print_check "Checking for unexpected status checks..."
while IFS= read -r check; do
    if [ -n "$check" ]; then
        FOUND=false
        for expected in "${EXPECTED_CHECKS[@]}"; do
            if [ "$check" = "$expected" ]; then
                FOUND=true
                break
            fi
        done
        if [ "$FOUND" = false ]; then
            print_warning "Unexpected status check found: $check"
        fi
    fi
done <<< "$REQUIRED_CHECKS"

# Validate strict mode
print_check "Validating strict mode setting..."
if [ "$STRICT_MODE" = "true" ]; then
    echo "  ✅ Strict mode enabled - branches must be up to date"
else
    echo "  ❌ Strict mode disabled - branches don't need to be up to date"
    VALIDATION_PASSED=false
fi

# Validate review requirements
print_check "Validating review requirements..."
if [ "$REQUIRED_REVIEWS" -ge "1" ]; then
    echo "  ✅ Required reviews: $REQUIRED_REVIEWS"
else
    echo "  ❌ No required reviews configured - maintainer approval required"
    VALIDATION_PASSED=false
fi

# Validate additional approval settings
DISMISS_STALE=$(echo "$PROTECTION_DATA" | jq -r '.required_pull_request_reviews.dismiss_stale_reviews' 2>/dev/null || echo "false")
CODE_OWNER_REVIEWS=$(echo "$PROTECTION_DATA" | jq -r '.required_pull_request_reviews.require_code_owner_reviews' 2>/dev/null || echo "false")
ALLOW_FORCE_PUSHES=$(echo "$PROTECTION_DATA" | jq -r '.allow_force_pushes.enabled' 2>/dev/null || echo "true")
ALLOW_DELETIONS=$(echo "$PROTECTION_DATA" | jq -r '.allow_deletions.enabled' 2>/dev/null || echo "true")

print_check "Validating approval bypass prevention settings..."
if [ "$DISMISS_STALE" = "true" ]; then
    echo "  ✅ Dismiss stale reviews: enabled"
else
    echo "  ❌ Dismiss stale reviews: disabled - should be enabled"
    VALIDATION_PASSED=false
fi

if [ "$CODE_OWNER_REVIEWS" = "true" ]; then
    echo "  ✅ Code owner reviews: required"
else
    echo "  ⚠️  Code owner reviews: not required (acceptable if no CODEOWNERS file)"
fi

if [ "$ALLOW_FORCE_PUSHES" = "false" ]; then
    echo "  ✅ Force pushes: blocked"
else
    echo "  ❌ Force pushes: allowed - should be blocked"
    VALIDATION_PASSED=false
fi

if [ "$ALLOW_DELETIONS" = "false" ]; then
    echo "  ✅ Branch deletions: blocked"
else
    echo "  ❌ Branch deletions: allowed - should be blocked"
    VALIDATION_PASSED=false
fi

# Final validation result
echo ""
if [ "$VALIDATION_PASSED" = true ]; then
    print_status "✅ Branch protection validation PASSED"
    echo "All required status checks are properly configured!"
    echo ""
    echo "Requirements addressed:"
    echo "  ✅ 6.1: PRs with failing checks cannot be merged"
    echo "  ✅ 6.2: PRs with passing checks can be merged (with approval)"
    echo "  ✅ 6.4: Maintainer approval required for bypassing checks"
    echo ""
    echo "Next steps:"
    echo "  1. Create a test PR to verify the configuration works"
    echo "  2. Ensure all team members understand the new requirements"
else
    print_error "❌ Branch protection validation FAILED"
    echo ""
    echo "Issues found that need to be addressed:"
    echo "  - Missing required status checks"
    echo "  - Missing approval requirements"
    echo "  - Incorrect configuration settings"
    echo ""
    echo "To fix these issues:"
    echo "  1. Run: .github/scripts/setup-branch-protection.sh"
    echo "  2. Or manually configure via GitHub Settings → Branches"
    echo "  3. Re-run this validation script to verify"
    exit 1
fi