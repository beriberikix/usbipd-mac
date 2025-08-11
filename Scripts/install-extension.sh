#!/bin/bash

# install-extension.sh  
# Automated System Extension installation script for usbipd-mac
# This script integrates bundle creation, signing, and installation in a single workflow

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CLI_BINARY="$PROJECT_ROOT/.build/debug/usbipd"
EXTENSION_BINARY="$PROJECT_ROOT/.build/debug/USBIPDSystemExtension"

# Default values
BUNDLE_PATH=""
FORCE_REINSTALL=false
SKIP_SIGNING=false
VERBOSE=false
DRY_RUN=false
BUNDLE_ID="com.example.usbipd-mac.SystemExtension"

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

log_verbose() {
    if [[ $VERBOSE == true ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1"
    fi
}

# Check if running on macOS
check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is designed for macOS only."
        exit 1
    fi
}

# Build the project if binaries don't exist
build_project() {
    log_info "Checking project build status..."
    
    local needs_build=false
    
    if [[ ! -f "$CLI_BINARY" ]]; then
        log_info "CLI binary not found, build required"
        needs_build=true
    fi
    
    if [[ ! -f "$EXTENSION_BINARY" ]]; then
        log_info "System Extension binary not found, build required"
        needs_build=true
    fi
    
    if [[ $needs_build == true ]]; then
        log_info "Building project..."
        cd "$PROJECT_ROOT"
        
        if [[ $VERBOSE == true ]]; then
            swift build --verbose
        else
            swift build
        fi
        
        if [[ $? -ne 0 ]]; then
            log_error "Failed to build project"
            exit 1
        fi
        
        log_success "Project built successfully"
    else
        log_success "Project binaries are up to date"
    fi
}

# Determine bundle path
determine_bundle_path() {
    if [[ -z "$BUNDLE_PATH" ]]; then
        BUNDLE_PATH="$PROJECT_ROOT/.build/USBIPDSystemExtension.systemextension"
        log_info "Using default bundle path: $BUNDLE_PATH"
    else
        log_info "Using specified bundle path: $BUNDLE_PATH"
    fi
}

# Create System Extension bundle
create_bundle() {
    log_info "Creating System Extension bundle..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY RUN] Would create bundle at: $BUNDLE_PATH"
        return 0
    fi
    
    # Remove existing bundle if force reinstall is requested
    if [[ $FORCE_REINSTALL == true && -d "$BUNDLE_PATH" ]]; then
        log_info "Removing existing bundle for force reinstall..."
        rm -rf "$BUNDLE_PATH"
    fi
    
    # Use CLI binary to create bundle (integrates with SystemExtensionBundleCreator)
    local create_command
    if [[ $VERBOSE == true ]]; then
        create_command="$CLI_BINARY create-bundle --output '$BUNDLE_PATH' --executable '$EXTENSION_BINARY' --bundle-id '$BUNDLE_ID' --verbose"
    else
        create_command="$CLI_BINARY create-bundle --output '$BUNDLE_PATH' --executable '$EXTENSION_BINARY' --bundle-id '$BUNDLE_ID'"
    fi
    
    log_verbose "Running: $create_command"
    
    # For now, simulate bundle creation since CLI integration isn't implemented yet
    # This would be replaced with actual CLI call once the create-bundle command is implemented
    log_warning "Bundle creation through CLI not yet implemented. Creating basic bundle structure..."
    
    # Create basic bundle structure manually
    mkdir -p "$BUNDLE_PATH/Contents/MacOS"
    mkdir -p "$BUNDLE_PATH/Contents/Resources"
    
    # Copy executable
    cp "$EXTENSION_BINARY" "$BUNDLE_PATH/Contents/MacOS/"
    
    # Create basic Info.plist
    cat > "$BUNDLE_PATH/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>USBIPD System Extension</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>NSSystemExtensionUsageDescription</key>
    <string>USB/IP device sharing system extension</string>
</dict>
</plist>
EOF
    
    log_success "Bundle created at: $BUNDLE_PATH"
}

# Sign the bundle
sign_bundle() {
    if [[ $SKIP_SIGNING == true ]]; then
        log_warning "Skipping code signing (development mode)"
        return 0
    fi
    
    log_info "Signing System Extension bundle..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY RUN] Would sign bundle at: $BUNDLE_PATH"
        return 0
    fi
    
    # Find suitable signing certificate
    local signing_identity
    signing_identity=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n1 | cut -d '"' -f 2)
    
    if [[ -z "$signing_identity" ]]; then
        # Try Mac Developer certificate
        signing_identity=$(security find-identity -v -p codesigning | grep "Mac Developer" | head -n1 | cut -d '"' -f 2)
    fi
    
    if [[ -z "$signing_identity" ]]; then
        log_warning "No suitable signing certificate found. Continuing with unsigned bundle."
        log_info "For development, you can install unsigned bundles with SIP disabled."
        return 0
    fi
    
    log_info "Using signing identity: $signing_identity"
    
    # Sign the executable first
    log_verbose "Signing executable..."
    codesign --force --sign "$signing_identity" --timestamp "$BUNDLE_PATH/Contents/MacOS/USBIPDSystemExtension"
    
    # Sign the bundle
    log_verbose "Signing bundle..."  
    codesign --force --sign "$signing_identity" --timestamp "$BUNDLE_PATH"
    
    # Verify signature
    log_verbose "Verifying signature..."
    if codesign --verify --deep "$BUNDLE_PATH"; then
        log_success "Bundle signed and verified successfully"
    else
        log_error "Bundle signature verification failed"
        return 1
    fi
}

# Install the System Extension
install_extension() {
    log_info "Installing System Extension..."
    
    if [[ $DRY_RUN == true ]]; then
        log_info "[DRY RUN] Would install bundle: $BUNDLE_PATH"
        return 0
    fi
    
    # Check if already installed and force reinstall is requested
    if [[ $FORCE_REINSTALL == true ]]; then
        log_info "Checking for existing installation..."
        local existing_extensions
        existing_extensions=$(systemextensionsctl list | grep "$BUNDLE_ID" || true)
        
        if [[ -n "$existing_extensions" ]]; then
            log_info "Found existing installation, uninstalling..."
            sudo systemextensionsctl uninstall "$BUNDLE_ID" || true
            sleep 2
        fi
    fi
    
    # Install the extension
    log_info "Installing System Extension (requires sudo)..."
    log_warning "You may be prompted for admin credentials and user approval"
    
    if [[ $VERBOSE == true ]]; then
        sudo systemextensionsctl install "$BUNDLE_PATH" -verbose
    else
        sudo systemextensionsctl install "$BUNDLE_PATH"
    fi
    
    if [[ $? -eq 0 ]]; then
        log_success "System Extension installation initiated"
        log_info "Check System Preferences > Privacy & Security to approve the extension if needed"
    else
        log_error "System Extension installation failed"
        return 1
    fi
}

# Verify installation
verify_installation() {
    log_info "Verifying System Extension installation..."
    
    sleep 3  # Wait for installation to register
    
    local extension_status
    extension_status=$(systemextensionsctl list | grep "$BUNDLE_ID" || true)
    
    if [[ -n "$extension_status" ]]; then
        log_success "System Extension found in system registry:"
        echo "$extension_status"
        
        # Check if activated
        if echo "$extension_status" | grep -q "\[activated enabled\]"; then
            log_success "System Extension is activated and enabled"
            return 0
        elif echo "$extension_status" | grep -q "\[awaiting user approval\]"; then
            log_warning "System Extension is awaiting user approval"
            log_info "Go to System Preferences > Privacy & Security to approve"
            return 0
        else
            log_warning "System Extension status: $extension_status"
            return 1
        fi
    else
        log_error "System Extension not found in system registry"
        return 1
    fi
}

# Show installation status
show_status() {
    log_info "Current System Extension status:"
    echo
    systemextensionsctl list | head -n1  # Header
    systemextensionsctl list | grep "$BUNDLE_ID" || log_info "No extensions found with bundle ID: $BUNDLE_ID"
    echo
}

# Cleanup function
cleanup() {
    if [[ $DRY_RUN == false && -d "$BUNDLE_PATH" && $KEEP_BUNDLE != true ]]; then
        read -p "Remove created bundle? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$BUNDLE_PATH"
            log_info "Bundle removed"
        fi
    fi
}

# Show help
show_help() {
    cat << EOF
Usage: $0 [options]

Options:
    -h, --help              Show this help message
    -o, --output PATH       Specify bundle output path
    -f, --force             Force reinstall (uninstall existing first)
    -s, --skip-signing      Skip code signing (for development)  
    -v, --verbose           Verbose output
    -n, --dry-run          Show what would be done without executing
    -k, --keep-bundle      Don't prompt to remove bundle after installation
    -b, --bundle-id ID     Specify bundle identifier (default: $BUNDLE_ID)
    --status               Show current System Extension status only

This script automates the complete System Extension installation workflow:
1. Build project (if needed)
2. Create System Extension bundle
3. Sign bundle (unless --skip-signing)
4. Install System Extension
5. Verify installation

Examples:
    $0                         Install with default settings
    $0 --force --verbose       Force reinstall with verbose output
    $0 --skip-signing         Install unsigned bundle (development mode)
    $0 --dry-run              Show what would be done
    $0 --status               Show current status only
EOF
}

# Main function
main() {
    local status_only=false
    local keep_bundle=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -o|--output)
                BUNDLE_PATH="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_REINSTALL=true
                shift
                ;;
            -s|--skip-signing)
                SKIP_SIGNING=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -k|--keep-bundle)
                keep_bundle=true
                shift
                ;;
            -b|--bundle-id)
                BUNDLE_ID="$2"
                shift 2
                ;;
            --status)
                status_only=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo "usbipd-mac System Extension Installation"
    echo "======================================="
    echo
    
    check_macos
    
    if [[ $status_only == true ]]; then
        show_status
        exit 0
    fi
    
    # Set cleanup trap
    trap cleanup EXIT
    KEEP_BUNDLE=$keep_bundle
    
    # Execute installation workflow
    build_project
    determine_bundle_path
    create_bundle
    sign_bundle
    install_extension
    verify_installation
    
    echo
    log_success "System Extension installation workflow completed!"
    
    if [[ $DRY_RUN == false ]]; then
        echo
        echo "Next steps:"
        echo "1. Check System Preferences > Privacy & Security for approval prompts"
        echo "2. Use './Scripts/extension-status.sh' to monitor status"
        echo "3. Test the extension with 'usbipd list' command"
    fi
}

# Run main function with all arguments
main "$@"