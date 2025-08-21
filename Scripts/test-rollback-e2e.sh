#!/bin/bash
# Scripts/test-rollback-e2e.sh
#
# End-to-end testing script for rollback procedures
# Usage: ROLLBACK_LEVEL=[configuration|partial|full] [WEBHOOK_TOKEN=token] ./Scripts/test-rollback-e2e.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ROLLBACK_LEVEL=${ROLLBACK_LEVEL:-"configuration"}
TAP_REPO="beriberikix/homebrew-usbipd-mac"
MAIN_REPO="beriberikix/usbipd-mac"
TEST_PREFIX="rollback-test"

echo -e "${BLUE}🧪 Running end-to-end rollback validation...${NC}"
echo -e "${BLUE}Rollback Level: ${ROLLBACK_LEVEL}${NC}"
echo ""

# Function to print success message
success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Function to print error message and exit
error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Function to print warning message
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Function to print info message
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to cleanup test environment
cleanup() {
    echo -e "${BLUE}🧹 Cleaning up test environment...${NC}"
    
    # Remove test tap if added
    if brew tap | grep -q "${TAP_REPO}"; then
        brew untap "${TAP_REPO}" &> /dev/null || true
        success "Test tap removed"
    fi
    
    # Remove any test installations
    if brew list | grep -q "usbipd-mac"; then
        brew uninstall usbipd-mac &> /dev/null || true
        warning "Test installation removed"
    fi
}

# Set up trap for cleanup
trap cleanup EXIT

# Test 1: Installation workflow validation
echo -e "${BLUE}1. Testing installation workflow...${NC}"

# Remove existing tap if present
brew untap "${TAP_REPO}" &> /dev/null || true

# Add tap
if brew tap "${TAP_REPO}"; then
    success "Tap added successfully"
else
    error "Failed to add tap"
fi

# Check if formula is discoverable
if brew info usbipd-mac > /dev/null 2>&1; then
    success "Formula discoverable via tap"
    
    # Get formula info for validation
    FORMULA_INFO=$(brew info usbipd-mac --json | jq -r '.[0]')
    FORMULA_VERSION=$(echo "$FORMULA_INFO" | jq -r '.versions.stable')
    FORMULA_DESC=$(echo "$FORMULA_INFO" | jq -r '.desc')
    
    info "Formula version: $FORMULA_VERSION"
    info "Formula description: $FORMULA_DESC"
    
    if [ "$FORMULA_VERSION" != "null" ] && [ "$FORMULA_VERSION" != "" ]; then
        success "Formula has valid version"
    else
        error "Formula version is invalid or missing"
    fi
else
    error "Formula not discoverable via tap"
fi

# Test 2: Formula syntax and structure validation
echo -e "${BLUE}2. Testing formula syntax and structure...${NC}"

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

if git clone "https://github.com/${TAP_REPO}.git" "$TEMP_DIR/tap-test" &> /dev/null; then
    success "Tap repository cloned for testing"
    
    cd "$TEMP_DIR/tap-test"
    
    # Test Ruby syntax
    if ruby -c Formula/usbipd-mac.rb &> /dev/null; then
        success "Formula Ruby syntax valid"
    else
        error "Formula Ruby syntax invalid"
    fi
    
    # Test Homebrew audit (if available)
    if command -v brew &> /dev/null; then
        if brew audit --formula --strict Formula/usbipd-mac.rb &> /dev/null; then
            success "Formula passes Homebrew audit"
        else
            warning "Formula fails Homebrew audit (may be expected for test)"
        fi
    else
        warning "Homebrew not available for audit testing"
    fi
    
    cd - > /dev/null
else
    error "Failed to clone tap repository for testing"
fi

# Test 3: Workflow trigger testing (based on rollback level)
echo -e "${BLUE}3. Testing workflow trigger capabilities...${NC}"

case "$ROLLBACK_LEVEL" in
    "configuration")
        info "Configuration rollback: Testing manual update capabilities"
        
        # Check if we can access the tap repository for manual updates
        if curl -s -f "https://api.github.com/repos/${TAP_REPO}" > /dev/null; then
            success "Tap repository accessible for manual updates"
        else
            error "Cannot access tap repository for manual updates"
        fi
        
        info "Manual update process would be functional"
        ;;
    
    "partial"|"full")
        info "${ROLLBACK_LEVEL^} rollback: Testing webhook dispatch capabilities"
        
        if [ -z "$WEBHOOK_TOKEN" ]; then
            warning "WEBHOOK_TOKEN not provided, skipping webhook dispatch test"
            info "Set WEBHOOK_TOKEN environment variable to test webhook dispatch"
        else
            # Test webhook dispatch with a test event
            info "Testing webhook dispatch to tap repository..."
            
            DISPATCH_PAYLOAD=$(cat <<EOF
{
  "event_type": "${TEST_PREFIX}-validation",
  "client_payload": {
    "test": true,
    "rollback_level": "${ROLLBACK_LEVEL}",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
}
EOF
)
            
            HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                -X POST \
                -H "Authorization: token $WEBHOOK_TOKEN" \
                -H "Accept: application/vnd.github.v3+json" \
                -H "Content-Type: application/json" \
                "https://api.github.com/repos/${TAP_REPO}/dispatches" \
                -d "$DISPATCH_PAYLOAD")
            
            if [ "$HTTP_STATUS" = "204" ]; then
                success "Webhook dispatch successful (HTTP $HTTP_STATUS)"
                
                # Wait a moment and check if workflow was triggered
                sleep 5
                
                if command -v gh &> /dev/null; then
                    RECENT_RUNS=$(gh run list --repo "${TAP_REPO}" --limit 3 --json conclusion,status,event 2>/dev/null || echo "[]")
                    if echo "$RECENT_RUNS" | jq -r '.[].event' | grep -q "repository_dispatch"; then
                        success "Repository dispatch event triggered workflow"
                    else
                        warning "No recent repository_dispatch workflows found"
                    fi
                else
                    warning "Cannot verify workflow trigger without GitHub CLI"
                fi
            else
                error "Webhook dispatch failed (HTTP $HTTP_STATUS)"
            fi
        fi
        ;;
esac

# Test 4: Homebrew-releaser configuration validation
echo -e "${BLUE}4. Testing homebrew-releaser configuration...${NC}"

if grep -q "homebrew-releaser" .github/workflows/release.yml; then
    success "Homebrew-releaser configuration found in workflow"
    
    # Extract and validate configuration
    HOMEBREW_OWNER=$(grep -A 20 "homebrew-releaser" .github/workflows/release.yml | grep "homebrew_owner:" | sed 's/.*homebrew_owner: *//' | tr -d '"' || echo "")
    HOMEBREW_TAP=$(grep -A 20 "homebrew-releaser" .github/workflows/release.yml | grep "homebrew_tap:" | sed 's/.*homebrew_tap: *//' | tr -d '"' || echo "")
    
    if [ "$HOMEBREW_OWNER" = "beriberikix" ]; then
        success "Homebrew owner correctly configured"
    else
        warning "Homebrew owner configuration may be incorrect: $HOMEBREW_OWNER"
    fi
    
    if [ "$HOMEBREW_TAP" = "homebrew-usbipd-mac" ]; then
        success "Homebrew tap correctly configured"
    else
        warning "Homebrew tap configuration may be incorrect: $HOMEBREW_TAP"
    fi
else
    warning "Homebrew-releaser configuration not found in workflow"
fi

# Test 5: Secret validation
echo -e "${BLUE}5. Testing secret configuration...${NC}"

if command -v gh &> /dev/null; then
    # Check for required secrets
    SECRETS=$(gh secret list 2>/dev/null || echo "")
    
    if echo "$SECRETS" | grep -q "HOMEBREW_TAP_TOKEN"; then
        success "HOMEBREW_TAP_TOKEN secret configured"
    else
        error "HOMEBREW_TAP_TOKEN secret missing"
    fi
    
    case "$ROLLBACK_LEVEL" in
        "partial"|"full")
            if echo "$SECRETS" | grep -q "WEBHOOK_TOKEN"; then
                success "WEBHOOK_TOKEN secret configured for $ROLLBACK_LEVEL rollback"
            else
                warning "WEBHOOK_TOKEN secret missing for $ROLLBACK_LEVEL rollback"
            fi
            ;;
    esac
else
    warning "Cannot validate secrets without GitHub CLI"
fi

# Test 6: Rollback readiness assessment
echo -e "${BLUE}6. Assessing rollback readiness...${NC}"

case "$ROLLBACK_LEVEL" in
    "configuration")
        READINESS_SCORE=0
        TOTAL_CHECKS=3
        
        # Check 1: Can disable homebrew-releaser
        if grep -q "homebrew-releaser" .github/workflows/release.yml; then
            READINESS_SCORE=$((READINESS_SCORE + 1))
            success "Can disable homebrew-releaser in workflow"
        else
            error "Cannot find homebrew-releaser configuration to disable"
        fi
        
        # Check 2: Manual update capability
        if curl -s -f "https://api.github.com/repos/${TAP_REPO}" > /dev/null; then
            READINESS_SCORE=$((READINESS_SCORE + 1))
            success "Manual update capability available"
        else
            error "Manual update capability not available"
        fi
        
        # Check 3: Formula is functional
        if brew info usbipd-mac > /dev/null 2>&1; then
            READINESS_SCORE=$((READINESS_SCORE + 1))
            success "Current formula is functional"
        else
            error "Current formula is not functional"
        fi
        ;;
        
    "partial")
        READINESS_SCORE=0
        TOTAL_CHECKS=4
        
        # Include configuration checks
        if grep -q "homebrew-releaser" .github/workflows/release.yml; then
            READINESS_SCORE=$((READINESS_SCORE + 1))
        fi
        if brew info usbipd-mac > /dev/null 2>&1; then
            READINESS_SCORE=$((READINESS_SCORE + 1))
        fi
        
        # Check webhook infrastructure
        if [ -n "$WEBHOOK_TOKEN" ]; then
            READINESS_SCORE=$((READINESS_SCORE + 1))
            success "Webhook token available for partial rollback"
        else
            warning "Webhook token needed for partial rollback"
        fi
        
        # Check if we can restore webhook workflows
        if [ -f "Documentation/webhook-configuration.md.archived" ] || 
           git log --oneline | grep -q "webhook"; then
            READINESS_SCORE=$((READINESS_SCORE + 1))
            success "Webhook configuration can be restored"
        else
            warning "Webhook configuration restoration may be difficult"
        fi
        ;;
        
    "full")
        READINESS_SCORE=0
        TOTAL_CHECKS=5
        
        # All previous checks plus full rollback requirements
        if brew info usbipd-mac > /dev/null 2>&1; then
            READINESS_SCORE=$((READINESS_SCORE + 1))
        fi
        
        if [ -n "$WEBHOOK_TOKEN" ]; then
            READINESS_SCORE=$((READINESS_SCORE + 1))
        fi
        
        # Check for metadata generation scripts backup
        if git log --oneline --follow Scripts/ | grep -q "metadata"; then
            READINESS_SCORE=$((READINESS_SCORE + 1))
            success "Metadata generation scripts can be restored"
        else
            warning "Metadata generation scripts may need recreation"
        fi
        
        # Check for webhook documentation
        if [ -f "Documentation/webhook-configuration.md.archived" ]; then
            READINESS_SCORE=$((READINESS_SCORE + 1))
            success "Webhook documentation available"
        else
            warning "Webhook documentation missing"
        fi
        
        # Check for workflow backup
        if git log --oneline --follow .github/workflows/release.yml | wc -l | awk '{if($1 > 5) print "1"; else print "0"}' | grep -q "1"; then
            READINESS_SCORE=$((READINESS_SCORE + 1))
            success "Workflow history sufficient for restoration"
        else
            warning "Limited workflow history for restoration"
        fi
        ;;
esac

# Calculate readiness percentage
READINESS_PERCENT=$((READINESS_SCORE * 100 / TOTAL_CHECKS))

echo ""
echo -e "${BLUE}📊 Rollback Readiness Assessment:${NC}"
echo -e "${BLUE}Level: ${ROLLBACK_LEVEL}${NC}"
echo -e "${BLUE}Score: ${READINESS_SCORE}/${TOTAL_CHECKS} (${READINESS_PERCENT}%)${NC}"

if [ $READINESS_PERCENT -ge 80 ]; then
    echo -e "${GREEN}✅ Rollback is ready to proceed${NC}"
elif [ $READINESS_PERCENT -ge 60 ]; then
    echo -e "${YELLOW}⚠️  Rollback may proceed with caution${NC}"
else
    echo -e "${RED}❌ Rollback needs preparation before proceeding${NC}"
fi

echo ""
echo -e "${GREEN}✅ End-to-end rollback validation completed${NC}"
echo ""

# Final recommendations
echo -e "${BLUE}📋 Recommendations:${NC}"
case "$ROLLBACK_LEVEL" in
    "configuration")
        echo "• Configuration rollback is the safest option"
        echo "• Prepare for manual formula updates during rollback period"
        echo "• Monitor user installation success rates"
        ;;
    "partial")
        echo "• Ensure WEBHOOK_TOKEN is configured before rollback"
        echo "• Test webhook infrastructure in isolation first"
        echo "• Plan for dual system coordination"
        ;;
    "full")
        echo "• Full rollback requires significant preparation"
        echo "• Restore all webhook infrastructure components"
        echo "• Plan for extended rollback time"
        echo "• Prepare user communication about changes"
        ;;
esac

info "Re-run with different ROLLBACK_LEVEL values to test other scenarios"
info "Example: ROLLBACK_LEVEL=full WEBHOOK_TOKEN=your_token ./Scripts/test-rollback-e2e.sh"