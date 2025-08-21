#!/bin/bash
# Scripts/validate-rollback.sh
#
# Validates rollback procedures for homebrew-releaser migration
# Usage: ROLLBACK_LEVEL=[configuration|partial|full] ./Scripts/validate-rollback.sh

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

echo -e "${BLUE}🔍 Validating rollback procedures...${NC}"
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

# Test 1: Verify workflow syntax
echo -e "${BLUE}1. Validating workflow syntax...${NC}"
if command -v gh &> /dev/null; then
    # Check if workflow can be viewed (indicates valid syntax)
    if gh workflow view .github/workflows/release.yml &> /dev/null; then
        success "Workflow syntax valid"
    else
        warning "Workflow syntax may be invalid (check manually with 'gh workflow view')"
    fi
else
    warning "GitHub CLI not available, skipping workflow validation"
fi

# Additional YAML syntax check if available
if command -v yamllint &> /dev/null; then
    if yamllint .github/workflows/release.yml &> /dev/null; then
        success "YAML syntax valid (yamllint)"
    else
        warning "YAML syntax issues detected (yamllint)"
    fi
fi

# Test 2: Check required secrets based on rollback level
echo -e "${BLUE}2. Checking required secrets for rollback level: ${ROLLBACK_LEVEL}...${NC}"

if [ "$ROLLBACK_LEVEL" = "partial" ] || [ "$ROLLBACK_LEVEL" = "full" ]; then
    if command -v gh &> /dev/null; then
        if gh secret list 2>/dev/null | grep -q "WEBHOOK_TOKEN"; then
            success "WEBHOOK_TOKEN secret present"
        else
            warning "WEBHOOK_TOKEN secret missing - required for ${ROLLBACK_LEVEL} rollback"
            info "Add WEBHOOK_TOKEN secret with repo permissions for ${TAP_REPO}"
        fi
    else
        warning "Cannot verify secrets without GitHub CLI"
    fi
fi

if gh secret list 2>/dev/null | grep -q "HOMEBREW_TAP_TOKEN"; then
    success "HOMEBREW_TAP_TOKEN secret present"
else
    warning "HOMEBREW_TAP_TOKEN secret missing or cannot be verified - required for homebrew-releaser"
    info "This is expected when running locally; secrets are only accessible in GitHub Actions"
fi

# Test 3: Validate repository connectivity
echo -e "${BLUE}3. Testing repository connectivity...${NC}"

# Test main repository
if curl -s -f "https://api.github.com/repos/${MAIN_REPO}" > /dev/null; then
    success "Main repository (${MAIN_REPO}) accessible"
else
    error "Main repository (${MAIN_REPO}) not accessible"
fi

# Test tap repository
if curl -s -f "https://api.github.com/repos/${TAP_REPO}" > /dev/null; then
    success "Tap repository (${TAP_REPO}) accessible"
else
    error "Tap repository (${TAP_REPO}) not accessible"
fi

# Test 4: Validate current formula in tap repository
echo -e "${BLUE}4. Validating current formula...${NC}"

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

if git clone "https://github.com/${TAP_REPO}.git" "$TEMP_DIR/tap-repo" &> /dev/null; then
    success "Tap repository cloned successfully"
    
    cd "$TEMP_DIR/tap-repo"
    
    if [ -f "Formula/usbipd-mac.rb" ]; then
        success "Formula file exists"
        
        # Check Ruby syntax
        if ruby -c "Formula/usbipd-mac.rb" &> /dev/null; then
            success "Formula syntax valid"
        else
            error "Formula syntax invalid"
        fi
        
        # Check for required formula components
        if grep -q "class UsbipDAcMac < Formula" "Formula/usbipd-mac.rb"; then
            success "Formula class definition found"
        else
            error "Formula class definition missing"
        fi
        
        if grep -q "desc" "Formula/usbipd-mac.rb" && 
           grep -q "homepage" "Formula/usbipd-mac.rb" && 
           grep -q "url" "Formula/usbipd-mac.rb"; then
            success "Required formula metadata present"
        else
            error "Required formula metadata missing"
        fi
    else
        error "Formula file not found"
    fi
else
    error "Failed to clone tap repository"
fi

# Test 5: Validate rollback-specific components
echo -e "${BLUE}5. Validating rollback-specific components...${NC}"

case "$ROLLBACK_LEVEL" in
    "configuration")
        info "Configuration rollback: Checking homebrew-releaser configuration"
        if grep -q "homebrew-releaser" .github/workflows/release.yml; then
            success "Homebrew-releaser configuration found in workflow"
        else
            error "Homebrew-releaser configuration not found in workflow"
        fi
        ;;
    
    "partial")
        info "Partial rollback: Checking hybrid system components"
        # Check if both webhook and homebrew-releaser components are available
        if [ -f "Scripts/generate-homebrew-metadata.sh" ] || 
           [ -f "Scripts/generate-homebrew-metadata.sh.archived" ]; then
            success "Metadata generation capability available"
        else
            warning "Metadata generation scripts not found - may need restoration"
        fi
        ;;
    
    "full")
        info "Full rollback: Checking complete webhook infrastructure"
        
        # Check for webhook-related scripts
        if [ -f "Scripts/generate-homebrew-metadata.sh" ]; then
            success "Metadata generation script present"
        else
            warning "Metadata generation script missing - needs restoration"
        fi
        
        if [ -f "Scripts/validate-homebrew-metadata.sh" ]; then
            success "Metadata validation script present"
        else
            warning "Metadata validation script missing - needs restoration"
        fi
        
        # Check if webhook configuration documentation exists
        if [ -f "Documentation/webhook-configuration.md" ] || 
           [ -f "Documentation/webhook-configuration.md.archived" ]; then
            success "Webhook configuration documentation available"
        else
            warning "Webhook configuration documentation missing"
        fi
        ;;
    
    *)
        error "Unknown rollback level: $ROLLBACK_LEVEL"
        ;;
esac

# Test 6: Validate current branch and Git state
echo -e "${BLUE}6. Validating Git repository state...${NC}"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" = "feature/homebrew-releaser-migration" ]; then
    success "On migration feature branch"
else
    warning "Not on migration feature branch (current: $CURRENT_BRANCH)"
fi

# Check for uncommitted changes
if git diff-index --quiet HEAD --; then
    success "No uncommitted changes"
else
    warning "Uncommitted changes detected - commit before rollback"
fi

# Test 7: Validate backup availability
echo -e "${BLUE}7. Checking backup availability...${NC}"

# Check if we can find commits before migration
PRE_MIGRATION_COMMIT=$(git log --oneline | grep -E "(webhook.*removal|remove.*webhook)" | head -1 | cut -d' ' -f1)
if [ -n "$PRE_MIGRATION_COMMIT" ]; then
    success "Pre-migration commit identified: $PRE_MIGRATION_COMMIT"
else
    warning "Pre-migration commit not clearly identified"
fi

# Check if critical files have backup history
if git log --oneline --follow .github/workflows/release.yml | wc -l | awk '{if($1 > 5) print "sufficient"; else print "insufficient"}' | grep -q "sufficient"; then
    success "Sufficient workflow history for rollback"
else
    warning "Limited workflow history - rollback may be complex"
fi

echo ""
echo -e "${GREEN}✅ Rollback validation completed${NC}"
echo ""

# Summary and recommendations
echo -e "${BLUE}📋 Rollback Validation Summary:${NC}"
echo -e "${BLUE}Rollback Level: ${ROLLBACK_LEVEL}${NC}"

case "$ROLLBACK_LEVEL" in
    "configuration")
        echo -e "${GREEN}✅ Configuration rollback ready${NC}"
        echo "   - Can disable homebrew-releaser in workflow"
        echo "   - Manual formula updates will be needed"
        ;;
    "partial")
        echo -e "${YELLOW}⚠️  Partial rollback needs preparation${NC}"
        echo "   - Restore webhook secrets if missing"
        echo "   - Re-enable webhook workflows in tap repository"
        ;;
    "full")
        echo -e "${YELLOW}⚠️  Full rollback needs extensive preparation${NC}"
        echo "   - Restore metadata generation scripts"
        echo "   - Restore webhook infrastructure completely"
        echo "   - Restore tap repository webhook handlers"
        ;;
esac

echo ""
info "Run this script with different ROLLBACK_LEVEL values to validate other rollback scenarios"
info "Example: ROLLBACK_LEVEL=full ./Scripts/validate-rollback.sh"