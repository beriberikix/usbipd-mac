#!/bin/bash

#
# check-test-branches.sh
# usbipd-mac
#
# Script to check the CI status of test branches for verification

set -e

echo "🔍 Checking CI status for test branches..."
echo "=========================================="

# Test branches to check
TEST_BRANCHES=(
    "test/swiftlint-violations"
    "test/build-errors"
    "test/test-failures"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📋 Test Branches Status:${NC}"
echo ""

for branch in "${TEST_BRANCHES[@]}"; do
    echo -e "${YELLOW}Branch: ${branch}${NC}"
    
    # Check if branch exists locally
    if git show-ref --verify --quiet refs/heads/"$branch"; then
        echo -e "  ${GREEN}✅ Local branch exists${NC}"
    else
        echo -e "  ${RED}❌ Local branch missing${NC}"
    fi
    
    # Check if branch exists remotely
    if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Remote branch exists${NC}"
        
        # Get the latest commit info
        COMMIT_HASH=$(git ls-remote origin "$branch" | cut -f1 | cut -c1-8)
        echo -e "  📝 Latest commit: ${COMMIT_HASH}"
        
        # Check if there are any recent workflow runs
        echo -e "  🔗 GitHub Actions: https://github.com/beriberikix/usbipd-mac/actions"
        
    else
        echo -e "  ${RED}❌ Remote branch missing${NC}"
    fi
    
    echo ""
done

echo -e "${BLUE}📊 Expected CI Behavior:${NC}"
echo ""
echo -e "${YELLOW}test/swiftlint-violations:${NC}"
echo "  • SwiftLint job should FAIL with 16+ violations"
echo "  • Build and test jobs should run in parallel"
echo "  • PR merge should be blocked"
echo ""
echo -e "${YELLOW}test/build-errors:${NC}"
echo "  • Build job should FAIL with compilation errors"
echo "  • SwiftLint job should run in parallel"
echo "  • Test jobs should not run (build dependency)"
echo "  • PR merge should be blocked"
echo ""
echo -e "${YELLOW}test/test-failures:${NC}"
echo "  • Test job should FAIL with 9/10 test failures"
echo "  • SwiftLint and build jobs should run in parallel"
echo "  • PR merge should be blocked"
echo ""

echo -e "${BLUE}🔗 Useful Links:${NC}"
echo "  • GitHub Actions: https://github.com/beriberikix/usbipd-mac/actions"
echo "  • Pull Requests: https://github.com/beriberikix/usbipd-mac/pulls"
echo "  • Branch Protection: https://github.com/beriberikix/usbipd-mac/settings/branches"
echo ""

echo -e "${GREEN}✅ Test branch verification setup complete!${NC}"
echo "Next steps:"
echo "1. Monitor GitHub Actions for each test branch"
echo "2. Create pull requests to test branch protection"
echo "3. Verify proper error reporting and merge blocking"
echo "4. Clean up test branches after verification"