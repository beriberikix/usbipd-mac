#!/bin/bash

# Script to check the status of CI test branches
# This script helps verify that the CI pipeline properly catches different types of failures

set -e

echo "🔍 Checking CI Test Branch Status"
echo "=================================="
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if a branch exists
check_branch_exists() {
    local branch=$1
    if git show-ref --verify --quiet refs/remotes/origin/$branch; then
        return 0
    else
        return 1
    fi
}

# Function to get the latest commit for a branch
get_latest_commit() {
    local branch=$1
    git log --format="%h %s" -n 1 origin/$branch 2>/dev/null || echo "No commits found"
}

# Test branches to check
TEST_BRANCHES=(
    "test/swiftlint-violations"
    "test/build-errors" 
    "test/test-failures"
)

echo "📋 Test Branch Summary:"
echo "----------------------"

for branch in "${TEST_BRANCHES[@]}"; do
    echo
    if check_branch_exists "$branch"; then
        echo -e "${GREEN}✅ Branch exists:${NC} $branch"
        latest_commit=$(get_latest_commit "$branch")
        echo -e "   ${BLUE}Latest commit:${NC} $latest_commit"
        
        # Determine expected failure type
        case $branch in
            "test/swiftlint-violations")
                echo -e "   ${YELLOW}Expected failure:${NC} SwiftLint violations (code style)"
                ;;
            "test/build-errors")
                echo -e "   ${YELLOW}Expected failure:${NC} Build/compilation errors"
                ;;
            "test/test-failures")
                echo -e "   ${YELLOW}Expected failure:${NC} Unit test failures"
                ;;
        esac
    else
        echo -e "${RED}❌ Branch missing:${NC} $branch"
    fi
done

echo
echo "🔗 Next Steps:"
echo "-------------"
echo "1. Check GitHub Actions workflow runs at:"
echo "   https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/actions"
echo
echo "2. Create pull requests for each test branch to verify merge blocking:"
for branch in "${TEST_BRANCHES[@]}"; do
    if check_branch_exists "$branch"; then
        repo_url=$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')
        echo "   - https://github.com/$repo_url/compare/main...$branch"
    fi
done

echo
echo "3. Verify that each PR shows failing CI checks and blocks merging"
echo
echo "4. Check that error messages are clear and actionable"
echo
echo "📊 Expected CI Behavior:"
echo "------------------------"
echo -e "${RED}test/swiftlint-violations${NC} → SwiftLint job should FAIL"
echo -e "${RED}test/build-errors${NC}        → Build job should FAIL"  
echo -e "${RED}test/test-failures${NC}       → Unit Test job should FAIL"
echo
echo "All failing PRs should be blocked from merging by branch protection rules."
echo
echo "🧹 Cleanup (after verification):"
echo "--------------------------------"
echo "Run the following commands to clean up test branches:"
echo
for branch in "${TEST_BRANCHES[@]}"; do
    echo "git push origin --delete $branch"
done
echo
echo "git branch -D test/swiftlint-violations test/build-errors test/test-failures"