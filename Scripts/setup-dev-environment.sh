#!/bin/bash

# setup-dev-environment.sh
# Automated development environment setup script for usbipd-mac System Extension development
# This script provides Linux-compatible development environment setup with interactive guidance

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CLI_BINARY="$PROJECT_ROOT/.build/debug/usbipd"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on macOS
check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is designed for macOS development environments only."
        exit 1
    fi
}

# Build the CLI binary if it doesn't exist
ensure_cli_binary() {
    if [[ ! -f "$CLI_BINARY" ]]; then
        log_info "Building usbipd CLI binary..."
        cd "$PROJECT_ROOT"
        swift build --product usbipd
        if [[ $? -ne 0 ]]; then
            log_error "Failed to build usbipd CLI binary"
            exit 1
        fi
        log_success "CLI binary built successfully"
    fi
}

# Check SIP status
check_sip_status() {
    log_info "Checking System Integrity Protection (SIP) status..."
    
    local sip_status
    sip_status=$(csrutil status)
    
    if echo "$sip_status" | grep -q "disabled"; then
        log_success "SIP is disabled - required for System Extension development"
        return 0
    elif echo "$sip_status" | grep -q "enabled"; then
        log_warning "SIP is enabled. System Extension development requires SIP to be disabled."
        echo
        echo "To disable SIP:"
        echo "1. Restart your Mac and hold down Command + R to enter Recovery Mode"
        echo "2. Open Terminal from the Utilities menu"
        echo "3. Run: csrutil disable"
        echo "4. Restart your Mac"
        echo
        read -p "Would you like to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Setup cancelled. Please disable SIP and run this script again."
            exit 0
        fi
        return 1
    else
        log_warning "Could not determine SIP status"
        return 1
    fi
}

# Check for Xcode Command Line Tools
check_xcode_tools() {
    log_info "Checking for Xcode Command Line Tools..."
    
    if xcode-select -p &> /dev/null; then
        log_success "Xcode Command Line Tools are installed"
        return 0
    else
        log_warning "Xcode Command Line Tools not found"
        echo "Installing Xcode Command Line Tools..."
        xcode-select --install
        
        echo "Please complete the Xcode Command Line Tools installation and run this script again."
        exit 0
    fi
}

# Check developer mode status
check_developer_mode() {
    log_info "Checking developer mode status..."
    
    # Use the CLI binary to check environment setup
    ensure_cli_binary
    
    # This would call the EnvironmentSetupManager through the CLI
    # For now, we'll check manually using system calls
    if spctl --status 2>/dev/null | grep -q "assessments disabled"; then
        log_success "Developer mode appears to be enabled"
        return 0
    else
        log_warning "Developer mode may not be enabled"
        echo
        echo "To enable developer mode:"
        echo "1. Go to System Preferences > Privacy & Security"
        echo "2. Scroll down to 'Developer Tools' section"
        echo "3. Enable developer mode if available"
        echo "4. Or run: sudo spctl --master-disable (not recommended for production)"
        echo
        read -p "Would you like to attempt automatic enablement? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Attempting to enable developer mode..."
            sudo spctl --master-disable
            log_success "Developer mode enabled (assessments disabled)"
        fi
        return 0
    fi
}

# Check for development certificates
check_certificates() {
    log_info "Checking for development certificates..."
    
    # Check for development certificates in keychain
    local dev_certs
    dev_certs=$(security find-identity -v -p codesigning | grep "Developer ID Application" | wc -l)
    
    if [[ $dev_certs -gt 0 ]]; then
        log_success "Found $dev_certs Developer ID certificate(s)"
        security find-identity -v -p codesigning | grep "Developer ID Application"
    else
        log_warning "No Developer ID certificates found"
        echo
        echo "For proper code signing, you'll need:"
        echo "1. A Developer ID Application certificate from Apple Developer Program"
        echo "2. Or you can develop with unsigned bundles (development mode only)"
        echo
    fi
    
    # Check for Mac Developer certificates
    local mac_dev_certs
    mac_dev_certs=$(security find-identity -v -p codesigning | grep "Mac Developer" | wc -l)
    
    if [[ $mac_dev_certs -gt 0 ]]; then
        log_success "Found $mac_dev_certs Mac Developer certificate(s)"
        security find-identity -v -p codesigning | grep "Mac Developer"
    else
        log_info "No Mac Developer certificates found (optional for System Extension development)"
    fi
}

# Interactive setup guidance
interactive_setup() {
    echo
    echo "=== Development Environment Setup ==="
    echo
    
    read -p "Would you like to run automated environment checks? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        check_sip_status
        check_xcode_tools  
        check_developer_mode
        check_certificates
    fi
    
    echo
    echo "=== Next Steps ==="
    echo
    echo "1. Build the project: swift build"
    echo "2. Create System Extension bundle: ./Scripts/install-extension.sh"
    echo "3. Install the System Extension: sudo systemextensionsctl install [bundle-path]"
    echo "4. Check status: ./Scripts/extension-status.sh"
    echo
    
    read -p "Would you like to build the project now? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        log_info "Building project..."
        cd "$PROJECT_ROOT"
        swift build --verbose
        log_success "Project built successfully"
    fi
}

# Validate environment
validate_environment() {
    log_info "Validating development environment..."
    
    local issues=0
    
    # Check macOS version
    local macos_version
    macos_version=$(sw_vers -productVersion)
    local major_version
    major_version=$(echo "$macos_version" | cut -d. -f1)
    
    if [[ $major_version -lt 11 ]]; then
        log_error "macOS 11 or later is required for System Extension development"
        ((issues++))
    else
        log_success "macOS version: $macos_version (compatible)"
    fi
    
    # Check Swift version
    if command -v swift &> /dev/null; then
        local swift_version
        swift_version=$(swift --version | head -n1)
        log_success "Swift found: $swift_version"
    else
        log_error "Swift not found in PATH"
        ((issues++))
    fi
    
    # Check for required tools
    local tools=("codesign" "security" "systemextensionsctl" "csrutil")
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_success "$tool found"
        else
            log_error "$tool not found in PATH"
            ((issues++))
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        log_success "Environment validation completed successfully"
        return 0
    else
        log_warning "Found $issues environment issues"
        return 1
    fi
}

# Show help
show_help() {
    cat << EOF
Usage: $0 [options]

Options:
    -h, --help          Show this help message
    -v, --validate      Validate environment only (no interactive setup)
    -q, --quiet         Quiet mode (minimal output)
    --check-sip         Check SIP status only
    --check-certs       Check certificates only

This script helps set up a development environment for usbipd-mac System Extension development.
It checks for required tools, certificates, and system configuration.

Examples:
    $0                  Run interactive setup
    $0 --validate       Validate environment only
    $0 --check-sip      Check SIP status only
EOF
}

# Main function
main() {
    local validate_only=false
    local quiet=false
    local check_sip_only=false
    local check_certs_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--validate)
                validate_only=true
                shift
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            --check-sip)
                check_sip_only=true
                shift
                ;;
            --check-certs)
                check_certs_only=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    if [[ $quiet == false ]]; then
        echo "usbipd-mac Development Environment Setup"
        echo "========================================"
        echo
    fi
    
    check_macos
    
    if [[ $check_sip_only == true ]]; then
        check_sip_status
        exit 0
    fi
    
    if [[ $check_certs_only == true ]]; then
        check_certificates
        exit 0
    fi
    
    if [[ $validate_only == true ]]; then
        validate_environment
        exit $?
    fi
    
    # Run interactive setup
    interactive_setup
    
    if [[ $quiet == false ]]; then
        echo
        log_success "Development environment setup completed!"
        echo "You can now proceed with System Extension development."
    fi
}

# Run main function with all arguments
main "$@"