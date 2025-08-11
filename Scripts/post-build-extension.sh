#!/bin/bash

# post-build-extension.sh
# Post-build System Extension bundle creation script for usbipd-mac
# Integrates with Swift Package Manager to automatically create properly structured .systemextension bundles

set -e

# Determine script and project directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration - can be overridden by environment variables
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
TARGET_BUILD_DIR="${TARGET_BUILD_DIR:-$PROJECT_ROOT/.build/$BUILD_CONFIGURATION}"
EXTENSION_NAME="${EXTENSION_NAME:-USBIPDSystemExtension}"
BUNDLE_ID="${BUNDLE_ID:-com.example.usbipd-mac.SystemExtension}"
BUNDLE_NAME="${BUNDLE_NAME:-$EXTENSION_NAME.systemextension}"

# Derived paths
EXTENSION_BINARY="$TARGET_BUILD_DIR/$EXTENSION_NAME"
BUNDLE_PATH="$TARGET_BUILD_DIR/$BUNDLE_NAME"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[POST-BUILD]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[POST-BUILD]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[POST-BUILD]${NC} $1"
}

log_error() {
    echo -e "${RED}[POST-BUILD]${NC} $1"
}

log_verbose() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo -e "${BLUE}[POST-BUILD VERBOSE]${NC} $1"
    fi
}

# Validate required inputs
validate_inputs() {
    log_info "Validating post-build environment..."
    
    if [[ ! -f "$EXTENSION_BINARY" ]]; then
        log_error "System Extension binary not found: $EXTENSION_BINARY"
        log_error "This script should be run after successful Swift build"
        return 1
    fi
    
    if [[ ! -d "$TARGET_BUILD_DIR" ]]; then
        log_error "Target build directory not found: $TARGET_BUILD_DIR"
        return 1
    fi
    
    log_verbose "Extension binary: $EXTENSION_BINARY"
    log_verbose "Bundle output path: $BUNDLE_PATH"
    log_verbose "Bundle identifier: $BUNDLE_ID"
    
    log_success "Post-build environment validated"
}

# Create bundle directory structure
create_bundle_structure() {
    log_info "Creating System Extension bundle structure..."
    
    # Remove existing bundle if present
    if [[ -d "$BUNDLE_PATH" ]]; then
        log_verbose "Removing existing bundle: $BUNDLE_PATH"
        rm -rf "$BUNDLE_PATH"
    fi
    
    # Create bundle directory structure
    mkdir -p "$BUNDLE_PATH/Contents/MacOS"
    mkdir -p "$BUNDLE_PATH/Contents/Resources"
    
    log_verbose "Created bundle directory: $BUNDLE_PATH/Contents/"
    log_success "Bundle directory structure created"
}

# Copy executable into bundle
copy_executable() {
    log_info "Copying System Extension executable into bundle..."
    
    local bundle_executable="$BUNDLE_PATH/Contents/MacOS/$EXTENSION_NAME"
    
    cp "$EXTENSION_BINARY" "$bundle_executable"
    
    # Ensure executable permissions
    chmod +x "$bundle_executable"
    
    log_verbose "Copied executable: $EXTENSION_BINARY -> $bundle_executable"
    log_success "Executable copied and permissions set"
}

# Create Info.plist
create_info_plist() {
    log_info "Creating bundle Info.plist..."
    
    local plist_path="$BUNDLE_PATH/Contents/Info.plist"
    local version="1.0.0"
    
    # Try to extract version from project if available
    if [[ -f "$PROJECT_ROOT/Package.swift" ]]; then
        # This is a simplified version extraction - could be enhanced
        log_verbose "Using default version: $version"
    fi
    
    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>USBIPD System Extension</string>
    <key>CFBundleDisplayName</key>
    <string>USB/IP Device Sharing Extension</string>
    <key>CFBundleVersion</key>
    <string>$version</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleExecutable</key>
    <string>$EXTENSION_NAME</string>
    <key>CFBundlePackageType</key>
    <string>SYSX</string>
    <key>NSSystemExtensionUsageDescription</key>
    <string>USB/IP device sharing system extension for network-based USB device access</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024 usbipd-mac contributors</string>
</dict>
</plist>
EOF
    
    log_verbose "Created Info.plist: $plist_path"
    log_success "Info.plist created with bundle metadata"
}

# Copy entitlements if they exist
copy_entitlements() {
    local entitlements_source="$PROJECT_ROOT/Sources/SystemExtension/SystemExtension.entitlements"
    local entitlements_dest="$BUNDLE_PATH/Contents/Resources/SystemExtension.entitlements"
    
    if [[ -f "$entitlements_source" ]]; then
        log_info "Copying entitlements file..."
        cp "$entitlements_source" "$entitlements_dest"
        log_verbose "Copied entitlements: $entitlements_source -> $entitlements_dest"
        log_success "Entitlements file copied"
    else
        log_verbose "No entitlements file found at: $entitlements_source"
        log_info "Creating basic entitlements file..."
        
        cat > "$entitlements_dest" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.system-extension.install</key>
    <true/>
    <key>com.apple.developer.driverkit</key>
    <true/>
    <key>com.apple.developer.driverkit.allow-any-userclient-access</key>
    <true/>
</dict>
</plist>
EOF
        
        log_success "Basic entitlements file created"
    fi
}

# Validate bundle structure
validate_bundle() {
    log_info "Validating created bundle structure..."
    
    local errors=0
    
    # Check required directories
    if [[ ! -d "$BUNDLE_PATH/Contents" ]]; then
        log_error "Missing Contents directory"
        ((errors++))
    fi
    
    if [[ ! -d "$BUNDLE_PATH/Contents/MacOS" ]]; then
        log_error "Missing MacOS directory"
        ((errors++))
    fi
    
    # Check required files
    if [[ ! -f "$BUNDLE_PATH/Contents/Info.plist" ]]; then
        log_error "Missing Info.plist"
        ((errors++))
    fi
    
    if [[ ! -f "$BUNDLE_PATH/Contents/MacOS/$EXTENSION_NAME" ]]; then
        log_error "Missing executable: $EXTENSION_NAME"
        ((errors++))
    fi
    
    # Check executable permissions
    if [[ ! -x "$BUNDLE_PATH/Contents/MacOS/$EXTENSION_NAME" ]]; then
        log_error "Executable lacks execute permissions"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Bundle structure validation passed"
        return 0
    else
        log_error "Bundle structure validation failed with $errors errors"
        return 1
    fi
}

# Attempt basic code signing if certificates are available
attempt_signing() {
    log_info "Checking for available code signing certificates..."
    
    # Look for suitable signing certificates
    local signing_identity=""
    
    # First try Developer ID Application (for distribution)
    signing_identity=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -n1 | sed -n 's/.*"\(.*\)".*/\1/p' || true)
    
    if [[ -z "$signing_identity" ]]; then
        # Try Mac Developer (for development)
        signing_identity=$(security find-identity -v -p codesigning 2>/dev/null | grep "Mac Developer" | head -n1 | sed -n 's/.*"\(.*\)".*/\1/p' || true)
    fi
    
    if [[ -z "$signing_identity" ]]; then
        # Try Apple Development (newer development certificates)
        signing_identity=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -n1 | sed -n 's/.*"\(.*\)".*/\1/p' || true)
    fi
    
    if [[ -z "$signing_identity" ]]; then
        log_warning "No suitable code signing certificates found"
        log_info "Bundle created unsigned - suitable for development with SIP disabled"
        return 0
    fi
    
    log_info "Found signing certificate: $signing_identity"
    log_info "Signing System Extension bundle..."
    
    # Sign the executable first
    if codesign --force --sign "$signing_identity" --timestamp "$BUNDLE_PATH/Contents/MacOS/$EXTENSION_NAME" 2>/dev/null; then
        log_verbose "Executable signed successfully"
    else
        log_warning "Failed to sign executable, continuing with unsigned bundle"
        return 0
    fi
    
    # Sign the bundle
    if codesign --force --sign "$signing_identity" --timestamp "$BUNDLE_PATH" 2>/dev/null; then
        log_verbose "Bundle signed successfully"
        
        # Verify signature
        if codesign --verify --deep "$BUNDLE_PATH" 2>/dev/null; then
            log_success "Bundle signed and verified with: $signing_identity"
        else
            log_warning "Bundle signature verification failed"
        fi
    else
        log_warning "Failed to sign bundle, continuing with unsigned bundle"
    fi
}

# Display bundle information
show_bundle_info() {
    log_info "System Extension bundle created successfully"
    echo
    echo "Bundle Information:"
    echo "  Path: $BUNDLE_PATH"
    echo "  Identifier: $BUNDLE_ID"
    echo "  Size: $(du -sh "$BUNDLE_PATH" | cut -f1)"
    
    # Check if signed
    if codesign --verify "$BUNDLE_PATH" 2>/dev/null; then
        local signature_info
        signature_info=$(codesign -dv "$BUNDLE_PATH" 2>&1 | grep "Authority=" | head -n1 | sed 's/Authority=//' || echo "Unknown")
        echo "  Signed: Yes ($signature_info)"
    else
        echo "  Signed: No (development mode)"
    fi
    
    echo
    echo "Installation:"
    echo "  Use './Scripts/install-extension.sh --output \"$BUNDLE_PATH\"' to install"
    echo "  Or manually: 'sudo systemextensionsctl install \"$BUNDLE_PATH\"'"
    echo
}

# Error handling
handle_error() {
    local exit_code=$?
    log_error "Post-build script failed with exit code $exit_code"
    
    # Clean up partial bundle if it exists
    if [[ -d "$BUNDLE_PATH" ]]; then
        log_info "Cleaning up partial bundle..."
        rm -rf "$BUNDLE_PATH"
    fi
    
    exit $exit_code
}

# Main execution
main() {
    echo "usbipd-mac Post-Build System Extension Bundle Creation"
    echo "====================================================="
    echo
    
    # Set error trap
    trap handle_error ERR
    
    # Execute bundle creation workflow
    validate_inputs
    create_bundle_structure
    copy_executable
    create_info_plist
    copy_entitlements
    validate_bundle
    attempt_signing
    show_bundle_info
    
    log_success "Post-build bundle creation completed successfully!"
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi