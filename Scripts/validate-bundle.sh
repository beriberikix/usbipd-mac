#!/bin/bash

# validate-bundle.sh
# System Extension bundle validation script for usbipd-mac  
# Provides detailed bundle structure and integrity checking with comprehensive reporting

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
BUNDLE_PATH=""
VERBOSE=false
JSON_OUTPUT=false
FIX_ISSUES=false
DEEP_VALIDATION=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Validation results
declare -a VALIDATION_ERRORS=()
declare -a VALIDATION_WARNINGS=()
declare -a VALIDATION_INFO=()

# Logging functions
log_info() {
    if [[ $JSON_OUTPUT == false ]]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

log_success() {
    if [[ $JSON_OUTPUT == false ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    fi
}

log_warning() {
    if [[ $JSON_OUTPUT == false ]]; then
        echo -e "${YELLOW}[WARNING]${NC} $1"
    fi
    VALIDATION_WARNINGS+=("$1")
}

log_error() {
    if [[ $JSON_OUTPUT == false ]]; then
        echo -e "${RED}[ERROR]${NC} $1"
    fi
    VALIDATION_ERRORS+=("$1")
}

log_verbose() {
    if [[ $VERBOSE == true && $JSON_OUTPUT == false ]]; then
        echo -e "${CYAN}[VERBOSE]${NC} $1"
    fi
}

# Check if running on macOS
check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is designed for macOS only."
        exit 1
    fi
}

# Determine bundle path
determine_bundle_path() {
    if [[ -z "$BUNDLE_PATH" ]]; then
        BUNDLE_PATH="$PROJECT_ROOT/.build/USBIPDSystemExtension.systemextension"
        log_verbose "Using default bundle path: $BUNDLE_PATH"
    else
        log_verbose "Using specified bundle path: $BUNDLE_PATH"
    fi
    
    if [[ ! -d "$BUNDLE_PATH" ]]; then
        log_error "Bundle not found at: $BUNDLE_PATH"
        exit 1
    fi
}

# Validate bundle structure
validate_bundle_structure() {
    log_info "Validating bundle structure..."
    
    local required_dirs=(
        "Contents"
        "Contents/MacOS"
        "Contents/Resources"
    )
    
    local required_files=(
        "Contents/Info.plist"
    )
    
    # Check required directories
    for dir in "${required_dirs[@]}"; do
        local full_path="$BUNDLE_PATH/$dir"
        if [[ -d "$full_path" ]]; then
            log_verbose "✓ Directory found: $dir"
        else
            log_error "Missing required directory: $dir"
        fi
    done
    
    # Check required files
    for file in "${required_files[@]}"; do
        local full_path="$BUNDLE_PATH/$file"
        if [[ -f "$full_path" ]]; then
            log_verbose "✓ File found: $file"
        else
            log_error "Missing required file: $file"
        fi
    done
    
    # Check for executable
    local macos_dir="$BUNDLE_PATH/Contents/MacOS"
    local executable_count
    executable_count=$(find "$macos_dir" -type f -perm +111 2>/dev/null | wc -l)
    
    if [[ $executable_count -gt 0 ]]; then
        log_verbose "✓ Found $executable_count executable(s) in MacOS directory"
    else
        log_error "No executable files found in Contents/MacOS"
    fi
}

# Validate Info.plist
validate_info_plist() {
    log_info "Validating Info.plist..."
    
    local plist_path="$BUNDLE_PATH/Contents/Info.plist"
    
    if [[ ! -f "$plist_path" ]]; then
        log_error "Info.plist not found"
        return 1
    fi
    
    # Check if plist is valid XML
    if plutil -lint "$plist_path" >/dev/null 2>&1; then
        log_verbose "✓ Info.plist is valid XML"
    else
        log_error "Info.plist is not valid XML"
        return 1
    fi
    
    # Check required keys
    local required_keys=(
        "CFBundleIdentifier"
        "CFBundleName"  
        "CFBundleVersion"
        "CFBundleShortVersionString"
    )
    
    local system_extension_keys=(
        "NSSystemExtensionUsageDescription"
    )
    
    for key in "${required_keys[@]}"; do
        local value
        value=$(plutil -extract "$key" raw "$plist_path" 2>/dev/null || echo "")
        if [[ -n "$value" ]]; then
            log_verbose "✓ $key: $value"
            VALIDATION_INFO+=("$key: $value")
        else
            log_error "Missing required key: $key"
        fi
    done
    
    # Check System Extension specific keys
    for key in "${system_extension_keys[@]}"; do
        local value
        value=$(plutil -extract "$key" raw "$plist_path" 2>/dev/null || echo "")
        if [[ -n "$value" ]]; then
            log_verbose "✓ $key: $value"
            VALIDATION_INFO+=("$key: $value")
        else
            log_warning "Missing System Extension key: $key"
        fi
    done
    
    # Validate bundle identifier format
    local bundle_id
    bundle_id=$(plutil -extract "CFBundleIdentifier" raw "$plist_path" 2>/dev/null || echo "")
    if [[ $bundle_id =~ ^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*)+$ ]]; then
        log_verbose "✓ Bundle identifier format is valid"
    else
        log_warning "Bundle identifier format may be invalid: $bundle_id"
    fi
}

# Validate code signature
validate_code_signature() {
    log_info "Validating code signature..."
    
    # Check if bundle is signed
    if codesign --verify "$BUNDLE_PATH" >/dev/null 2>&1; then
        log_success "Bundle is code signed"
        
        # Get signing information
        local signing_info
        signing_info=$(codesign -dv "$BUNDLE_PATH" 2>&1)
        
        if [[ $VERBOSE == true ]]; then
            echo "Signing details:"
            echo "$signing_info" | sed 's/^/  /'
        fi
        
        # Extract certificate info
        local authority
        authority=$(echo "$signing_info" | grep "Authority=" | head -n1 | cut -d= -f2)
        if [[ -n "$authority" ]]; then
            VALIDATION_INFO+=("Signed by: $authority")
        fi
        
        # Verify deep signature
        if [[ $DEEP_VALIDATION == true ]]; then
            log_verbose "Performing deep signature verification..."
            if codesign --verify --deep "$BUNDLE_PATH" >/dev/null 2>&1; then
                log_success "Deep signature verification passed"
            else
                log_error "Deep signature verification failed"
            fi
        fi
        
    else
        log_warning "Bundle is not code signed"
        log_info "Unsigned bundles can be used in development mode with SIP disabled"
    fi
}

# Validate executable
validate_executable() {
    log_info "Validating executable..."
    
    local macos_dir="$BUNDLE_PATH/Contents/MacOS"
    local executables
    executables=$(find "$macos_dir" -type f -perm +111 2>/dev/null || true)
    
    if [[ -z "$executables" ]]; then
        log_error "No executable files found"
        return 1
    fi
    
    while IFS= read -r executable; do
        if [[ -z "$executable" ]]; then continue; fi
        
        local exec_name
        exec_name=$(basename "$executable")
        log_verbose "Checking executable: $exec_name"
        
        # Check file type
        local file_type
        file_type=$(file "$executable" 2>/dev/null || echo "unknown")
        log_verbose "File type: $file_type"
        
        # Check architecture
        if command -v lipo &> /dev/null; then
            local architectures
            architectures=$(lipo -archs "$executable" 2>/dev/null || echo "unknown")
            log_verbose "Architectures: $architectures"
            VALIDATION_INFO+=("Executable $exec_name architectures: $architectures")
        fi
        
        # Check if executable is signed
        if codesign --verify "$executable" >/dev/null 2>&1; then
            log_verbose "✓ Executable is signed"
        else
            log_warning "Executable is not signed"
        fi
        
        # Check dynamic libraries (if deep validation enabled)
        if [[ $DEEP_VALIDATION == true ]]; then
            log_verbose "Checking dynamic library dependencies..."
            local dylibs
            dylibs=$(otool -L "$executable" 2>/dev/null | tail -n +2 | awk '{print $1}' || true)
            if [[ -n "$dylibs" ]]; then
                while IFS= read -r dylib; do
                    if [[ -n "$dylib" ]]; then
                        log_verbose "  Depends on: $dylib"
                    fi
                done <<< "$dylibs"
            fi
        fi
        
    done <<< "$executables"
}

# Validate entitlements
validate_entitlements() {
    if [[ $DEEP_VALIDATION == false ]]; then
        return 0
    fi
    
    log_info "Validating entitlements..."
    
    # Check for entitlements file
    local entitlements_path="$BUNDLE_PATH/Contents/Resources/entitlements.plist"
    if [[ -f "$entitlements_path" ]]; then
        log_verbose "Found entitlements file"
        
        if plutil -lint "$entitlements_path" >/dev/null 2>&1; then
            log_verbose "✓ Entitlements file is valid XML"
            
            # Extract entitlements
            local entitlements
            entitlements=$(plutil -p "$entitlements_path" 2>/dev/null || echo "")
            if [[ -n "$entitlements" ]]; then
                log_verbose "Entitlements content:"
                echo "$entitlements" | sed 's/^/  /'
            fi
        else
            log_error "Entitlements file is not valid XML"
        fi
    else
        log_info "No entitlements file found (may be embedded in executable)"
    fi
    
    # Check embedded entitlements in executable
    local macos_dir="$BUNDLE_PATH/Contents/MacOS"
    local executables
    executables=$(find "$macos_dir" -type f -perm +111 2>/dev/null | head -n1)
    
    if [[ -n "$executables" ]]; then
        local entitlements
        entitlements=$(codesign -d --entitlements :- "$executables" 2>/dev/null || true)
        if [[ -n "$entitlements" ]]; then
            log_verbose "Found embedded entitlements in executable"
            if [[ $VERBOSE == true ]]; then
                echo "Embedded entitlements:"
                echo "$entitlements" | sed 's/^/  /'
            fi
        else
            log_info "No embedded entitlements found"
        fi
    fi
}

# Generate validation report
generate_report() {
    local total_errors=${#VALIDATION_ERRORS[@]}
    local total_warnings=${#VALIDATION_WARNINGS[@]}
    local total_info=${#VALIDATION_INFO[@]}
    
    if [[ $JSON_OUTPUT == true ]]; then
        # Generate JSON report
        local errors_json warnings_json info_json
        errors_json=$(printf '%s\n' "${VALIDATION_ERRORS[@]}" | jq -R . | jq -s .)
        warnings_json=$(printf '%s\n' "${VALIDATION_WARNINGS[@]}" | jq -R . | jq -s .)
        info_json=$(printf '%s\n' "${VALIDATION_INFO[@]}" | jq -R . | jq -s .)
        
        local overall_status="valid"
        if [[ $total_errors -gt 0 ]]; then
            overall_status="invalid"
        elif [[ $total_warnings -gt 0 ]]; then
            overall_status="warnings"
        fi
        
        cat << EOF
{
  "bundle_path": "$BUNDLE_PATH",
  "validation_status": "$overall_status",
  "errors": $errors_json,
  "warnings": $warnings_json,
  "information": $info_json,
  "summary": {
    "total_errors": $total_errors,
    "total_warnings": $total_warnings,
    "total_information": $total_info
  }
}
EOF
    else
        # Generate human-readable report
        echo
        echo -e "${BOLD}Validation Report${NC}"
        echo "================"
        echo "Bundle: $BUNDLE_PATH"
        echo
        
        if [[ $total_errors -eq 0 && $total_warnings -eq 0 ]]; then
            log_success "Bundle validation passed with no issues"
        elif [[ $total_errors -eq 0 ]]; then
            log_warning "Bundle validation passed with $total_warnings warning(s)"
        else
            log_error "Bundle validation failed with $total_errors error(s) and $total_warnings warning(s)"
        fi
        
        echo
        echo "Summary:"
        echo "  Errors: $total_errors"
        echo "  Warnings: $total_warnings"  
        echo "  Information items: $total_info"
        
        if [[ $total_errors -gt 0 ]]; then
            echo
            echo -e "${RED}Errors:${NC}"
            for error in "${VALIDATION_ERRORS[@]}"; do
                echo "  - $error"
            done
        fi
        
        if [[ $total_warnings -gt 0 ]]; then
            echo
            echo -e "${YELLOW}Warnings:${NC}"
            for warning in "${VALIDATION_WARNINGS[@]}"; do
                echo "  - $warning"
            done
        fi
        
        if [[ $VERBOSE == true && $total_info -gt 0 ]]; then
            echo
            echo -e "${BLUE}Information:${NC}"
            for info in "${VALIDATION_INFO[@]}"; do
                echo "  - $info"
            done
        fi
        
        # Recommendations
        if [[ $total_errors -gt 0 || $total_warnings -gt 0 ]]; then
            echo
            echo "Recommendations:"
            if [[ $total_errors -gt 0 ]]; then
                echo "  - Fix critical errors before attempting to install the extension"
                echo "  - Use './Scripts/install-extension.sh' to recreate the bundle"
            fi
            if [[ $total_warnings -gt 0 ]]; then
                echo "  - Consider addressing warnings for better compatibility"
                echo "  - Review Info.plist for missing optional keys"
            fi
        fi
    fi
}

# Fix common issues
fix_common_issues() {
    if [[ $FIX_ISSUES == false ]]; then
        return 0
    fi
    
    log_info "Attempting to fix common issues..."
    
    # This would implement automatic fixes for common problems
    # For now, just provide guidance
    log_info "Automatic fixes not yet implemented"
    log_info "Use './Scripts/install-extension.sh --force' to recreate bundle"
}

# Show help
show_help() {
    cat << EOF
Usage: $0 [options] [bundle-path]

Arguments:
    bundle-path         Path to System Extension bundle to validate
                        (default: .build/USBIPDSystemExtension.systemextension)

Options:
    -h, --help          Show this help message
    -v, --verbose       Verbose output with detailed information
    -j, --json          Output validation report in JSON format
    -d, --deep          Perform deep validation (includes dependencies, entitlements)
    -f, --fix           Attempt to fix common issues automatically
    -q, --quiet         Minimal output (errors and warnings only)

This script validates System Extension bundle structure, Info.plist, code signatures,
and other integrity checks.

Examples:
    $0                                          Validate default bundle
    $0 /path/to/bundle.systemextension          Validate specific bundle
    $0 --verbose --deep                         Comprehensive validation
    $0 --json > validation-report.json         Generate JSON report
EOF
}

# Main function
main() {
    local quiet=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -j|--json)
                JSON_OUTPUT=true
                shift
                ;;
            -d|--deep)
                DEEP_VALIDATION=true
                shift
                ;;
            -f|--fix)
                FIX_ISSUES=true
                shift
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                BUNDLE_PATH="$1"
                shift
                ;;
        esac
    done
    
    if [[ $quiet == false && $JSON_OUTPUT == false ]]; then
        echo "usbipd-mac System Extension Bundle Validation"
        echo "============================================="
        echo
    fi
    
    check_macos
    determine_bundle_path
    
    # Run validation checks
    validate_bundle_structure
    validate_info_plist
    validate_code_signature
    validate_executable
    validate_entitlements
    
    # Attempt fixes if requested
    fix_common_issues
    
    # Generate final report
    generate_report
    
    # Return appropriate exit code
    if [[ ${#VALIDATION_ERRORS[@]} -gt 0 ]]; then
        exit 1
    elif [[ ${#VALIDATION_WARNINGS[@]} -gt 0 ]]; then
        exit 2
    else
        exit 0
    fi
}

# Run main function with all arguments
main "$@"