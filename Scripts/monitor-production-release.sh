#!/bin/bash

# monitor-production-release.sh - Automated release monitoring for external tap integration
# This script monitors the complete workflow from main repository release to tap repository formula update

set -e

# Configuration
VERSION=${1:-"latest"}
MAIN_REPO="beriberikix/usbipd-mac"
TAP_REPO="beriberikix/homebrew-usbipd-mac"
LOG_FILE="/tmp/release-monitoring-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "${BLUE}$1${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$1${NC}"; }
log_warning() { log "WARNING" "${YELLOW}$1${NC}"; }
log_error() { log "ERROR" "${RED}$1${NC}"; }

# Check prerequisites
check_prerequisites() {
    log_info "🔍 Checking monitoring prerequisites..."
    
    local missing_tools=()
    for tool in gh curl jq brew; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Install missing tools and try again"
        exit 1
    fi
    
    log_success "✓ All prerequisite tools found"
}

# Monitor release workflow
monitor_release_workflow() {
    log_info "📋 Monitoring main repository release workflow for version $VERSION..."
    
    # Check if release exists
    if ! gh release view "$VERSION" --repo "$MAIN_REPO" &>/dev/null; then
        log_error "Release $VERSION not found in $MAIN_REPO"
        return 1
    fi
    
    log_success "✓ Release $VERSION found"
    
    # Check for metadata asset
    log_info "🏺 Checking for homebrew-metadata.json asset..."
    local assets=$(gh release view "$VERSION" --repo "$MAIN_REPO" --json assets -q '.assets[].name')
    
    if echo "$assets" | grep -q "homebrew-metadata.json"; then
        log_success "✓ Metadata asset found"
        
        # Download and validate metadata
        local temp_dir=$(mktemp -d)
        cd "$temp_dir"
        
        if gh release download "$VERSION" --pattern "homebrew-metadata.json" --repo "$MAIN_REPO" &>/dev/null; then
            log_success "✓ Metadata downloaded successfully"
            
            # Validate metadata schema
            if jq empty homebrew-metadata.json 2>/dev/null; then
                log_success "✓ Metadata has valid JSON syntax"
                
                # Extract and display key metadata
                local meta_version=$(jq -r '.version' homebrew-metadata.json)
                local meta_sha256=$(jq -r '.sha256' homebrew-metadata.json)
                local meta_timestamp=$(jq -r '.timestamp' homebrew-metadata.json)
                
                log_info "  Version: $meta_version"
                log_info "  SHA256: ${meta_sha256:0:16}..."
                log_info "  Timestamp: $meta_timestamp"
            else
                log_error "✗ Metadata has invalid JSON syntax"
                return 1
            fi
        else
            log_error "✗ Failed to download metadata asset"
            return 1
        fi
        
        rm -rf "$temp_dir"
    else
        log_error "✗ homebrew-metadata.json asset not found"
        log_error "Available assets: $assets"
        return 1
    fi
}

# Monitor webhook delivery
monitor_webhook_delivery() {
    log_info "📡 Monitoring webhook delivery to tap repository..."
    
    # Check recent workflow runs in tap repository
    log_info "Checking recent workflow runs in $TAP_REPO..."
    local runs=$(gh run list --repo "$TAP_REPO" --limit 5 --json status,conclusion,createdAt,displayTitle)
    
    if [ -n "$runs" ] && [ "$runs" != "[]" ]; then
        log_info "Recent workflow runs found:"
        echo "$runs" | jq -r '.[] | "  • \(.displayTitle) - \(.status) - \(.createdAt)"' | head -3
        
        # Check if there's a recent successful run
        local recent_success=$(echo "$runs" | jq -r '.[] | select(.conclusion == "success" and (.createdAt | fromdateiso8601) > (now - 3600)) | .displayTitle' | head -1)
        
        if [ -n "$recent_success" ]; then
            log_success "✓ Recent successful workflow found: $recent_success"
        else
            log_warning "⚠ No recent successful workflows found (within 1 hour)"
        fi
    else
        log_warning "⚠ No recent workflow runs found in tap repository"
    fi
}

# Monitor formula update
monitor_formula_update() {
    log_info "🍺 Monitoring formula update in tap repository..."
    
    # Download current formula
    local temp_file=$(mktemp)
    
    if curl -s "https://raw.githubusercontent.com/beriberikix/homebrew-usbipd-mac/main/Formula/usbipd-mac.rb" -o "$temp_file"; then
        log_success "✓ Formula downloaded successfully"
        
        # Extract version and SHA256 from formula
        local formula_version=$(grep -E '^\s*version' "$temp_file" | head -1 | sed 's/.*"\(.*\)".*/\1/')
        local formula_sha256=$(grep -E '^\s*sha256' "$temp_file" | head -1 | sed 's/.*"\(.*\)".*/\1/')
        
        log_info "Formula information:"
        log_info "  Version: $formula_version"
        log_info "  SHA256: ${formula_sha256:0:16}..."
        
        # Compare with expected version
        if [ "$VERSION" != "latest" ]; then
            if [ "$formula_version" = "${VERSION#v}" ]; then
                log_success "✓ Formula version matches expected version"
            else
                log_warning "⚠ Formula version ($formula_version) does not match expected ($VERSION)"
            fi
        fi
        
        # Validate formula syntax
        log_info "🧪 Validating formula syntax..."
        if ruby -c "$temp_file" &>/dev/null; then
            log_success "✓ Formula has valid Ruby syntax"
        else
            log_error "✗ Formula has syntax errors"
        fi
        
    else
        log_error "✗ Failed to download formula"
        return 1
    fi
    
    rm -f "$temp_file"
}

# Test end-user experience
test_user_experience() {
    log_info "👤 Testing end-user installation experience..."
    
    # Check if tap can be added
    log_info "Testing tap addition..."
    if brew tap beriberikix/usbipd-mac &>/dev/null; then
        log_success "✓ Tap addition successful"
        
        # Check if formula is discoverable
        log_info "Testing formula discovery..."
        if brew info usbipd-mac &>/dev/null; then
            log_success "✓ Formula discovered successfully"
            
            # Get formula information
            local formula_info=$(brew info usbipd-mac --json | jq -r '.[0] | "Version: \(.versions.stable), Description: \(.desc)"')
            log_info "Formula info: $formula_info"
            
        else
            log_error "✗ Formula not discoverable"
        fi
        
        # Clean up tap
        log_info "Cleaning up test tap..."
        brew untap beriberikix/usbipd-mac &>/dev/null || true
        
    else
        log_error "✗ Tap addition failed"
        return 1
    fi
}

# Generate monitoring report
generate_report() {
    local report_file="/tmp/production-monitoring-report-$(date +%Y%m%d-%H%M%S).txt"
    
    log_info "📊 Generating monitoring report..."
    
    cat << EOF > "$report_file"
Production Release Monitoring Report
===================================

Monitoring Session: $(date '+%Y-%m-%d %H:%M:%S')
Version Monitored: $VERSION
Main Repository: $MAIN_REPO
Tap Repository: $TAP_REPO

Summary:
$(grep -E "\[(SUCCESS|ERROR|WARNING)\]" "$LOG_FILE" | sed 's/^.*\[\([^]]*\)\] /  \1: /')

Detailed Log: $LOG_FILE

Next Actions:
- Review any ERROR or WARNING items above
- Follow up on failed validations
- Monitor user feedback for issues
- Update documentation as needed

Generated by: monitor-production-release.sh
EOF
    
    log_success "✓ Monitoring report generated: $report_file"
    echo
    cat "$report_file"
}

# Main monitoring workflow
main() {
    echo "=================================================================="
    echo "🔍 External Tap Integration - Production Release Monitoring"
    echo "=================================================================="
    echo "Version: $VERSION"
    echo "Main Repository: $MAIN_REPO"
    echo "Tap Repository: $TAP_REPO"
    echo "Log File: $LOG_FILE"
    echo "=================================================================="
    echo
    
    check_prerequisites
    echo
    
    log_info "🚀 Starting production release monitoring workflow..."
    
    # Phase 1: Release workflow monitoring
    log_info "Phase 1: Release Workflow Monitoring"
    monitor_release_workflow
    echo
    
    # Phase 2: Webhook delivery monitoring
    log_info "Phase 2: Webhook Delivery Monitoring"
    monitor_webhook_delivery
    echo
    
    # Phase 3: Formula update monitoring
    log_info "Phase 3: Formula Update Monitoring"
    monitor_formula_update
    echo
    
    # Phase 4: User experience testing
    log_info "Phase 4: User Experience Testing"
    test_user_experience
    echo
    
    # Generate final report
    generate_report
    
    log_success "🎉 Production release monitoring completed!"
    log_info "Review the monitoring report above for any issues that need attention."
}

# Run main function
main "$@"