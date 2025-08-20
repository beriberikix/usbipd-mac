#!/bin/bash

# Manual Formula Update Script for usbipd-mac Homebrew Tap
# 
# This script provides standalone formula update capability for testing and emergency recovery.
# It performs the same validation and update logic as the GitHub workflow but can be run locally.
#
# Usage: ./manual-update.sh [OPTIONS]
# 
# Requirements 5.1-5.5:
# - Accept command-line parameters for version and repository URLs
# - Perform same validation and update logic as GitHub workflow  
# - Support dry-run mode to preview changes without modifying files
# - Provide clear status reporting and next steps
# - Provide actionable troubleshooting guidance on errors

set -euo pipefail

# Script metadata
SCRIPT_NAME="manual-update.sh"
SCRIPT_VERSION="1.0.0"
SCRIPT_DESCRIPTION="Standalone formula update script for usbipd-mac Homebrew tap"

# Default configuration
DEFAULT_SOURCE_REPO="beriberikix/usbipd-mac"
DEFAULT_FORMULA_FILE="Formula/usbipd-mac.rb"
METADATA_FILENAME="homebrew-metadata.json"
BACKUP_SUFFIX=".backup"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
VERSION=""
SOURCE_REPO="$DEFAULT_SOURCE_REPO"
FORMULA_FILE="$DEFAULT_FORMULA_FILE"
DRY_RUN=false
FORCE=false
VERBOSE=false
SKIP_VALIDATION=false
TEMP_DIR=""

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  INFO:${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}✅ SUCCESS:${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING:${NC} $1" >&2
}

log_error() {
    echo -e "${RED}❌ ERROR:${NC} $1" >&2
}

log_debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${PURPLE}🔍 DEBUG:${NC} $1" >&2
    fi
}

log_step() {
    echo -e "${CYAN}🔄 STEP:${NC} $1" >&2
}

# Progress tracking
start_timestamp=$(date +%s)
step_count=0
total_steps=8

show_progress() {
    local step_name="$1"
    step_count=$((step_count + 1))
    log_step "[$step_count/$total_steps] $step_name"
}

# Usage and help
show_usage() {
    cat << EOF
${SCRIPT_DESCRIPTION}

USAGE:
    ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
    --version VERSION          Release version to process (e.g., v1.2.3)
                              If not specified, prompts for latest release
    
    --source-repo REPO        Source repository in owner/repo format
                              Default: ${DEFAULT_SOURCE_REPO}
    
    --formula-file FILE       Path to formula file to update
                              Default: ${DEFAULT_FORMULA_FILE}
    
    --dry-run                 Preview changes without modifying files
                              Shows what would be changed without making actual changes
    
    --force                   Force update even if formula already exists for this version
                              Bypasses version existence checks
    
    --skip-validation         Skip comprehensive formula validation
                              Use only for emergency recovery scenarios
    
    --verbose                 Enable verbose debug output
                              Shows detailed information about each operation
    
    --help                    Show this help message and exit
    
    --version-info            Show script version information and exit

EXAMPLES:
    # Update to specific version with dry-run
    ${SCRIPT_NAME} --version v1.2.3 --dry-run
    
    # Force update with verbose output
    ${SCRIPT_NAME} --version v1.2.3 --force --verbose
    
    # Update from different source repository
    ${SCRIPT_NAME} --version v1.2.3 --source-repo myuser/usbipd-mac
    
    # Emergency recovery with minimal validation
    ${SCRIPT_NAME} --version v1.2.3 --force --skip-validation

REQUIREMENTS:
    - curl (for downloading metadata and archives)
    - jq (for JSON processing)
    - git (for repository operations)
    - ruby (for formula validation)
    - sha256sum or shasum (for checksum verification)

TROUBLESHOOTING:
    - Network errors: Check internet connectivity and GitHub availability
    - Validation errors: Review formula syntax and Homebrew requirements
    - Permission errors: Ensure write access to formula file and git repository
    - Version conflicts: Use --force to override existing version checks
    
    For more help, run with --verbose for detailed operation logs.
EOF
}

show_version_info() {
    cat << EOF
${SCRIPT_NAME} version ${SCRIPT_VERSION}
${SCRIPT_DESCRIPTION}

Dependencies:
    - curl: $(curl --version 2>/dev/null | head -1 || echo "Not found")
    - jq: $(jq --version 2>/dev/null || echo "Not found")
    - git: $(git --version 2>/dev/null || echo "Not found")
    - ruby: $(ruby --version 2>/dev/null || echo "Not found")
    - shasum: $(shasum --version 2>/dev/null | head -1 || echo "Not found")
EOF
}

# Dependency checking
check_dependencies() {
    show_progress "Checking dependencies"
    
    local missing_deps=()
    
    # Check required tools
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    if ! command -v git >/dev/null 2>&1; then
        missing_deps+=("git")
    fi
    
    if ! command -v ruby >/dev/null 2>&1; then
        missing_deps+=("ruby")
    fi
    
    # Check for checksum tool (prefer sha256sum, fallback to shasum)
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        missing_deps+=("sha256sum or shasum")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        echo
        echo "Installation instructions:"
        echo "  • macOS: brew install curl jq git ruby"
        echo "  • Ubuntu/Debian: apt-get install curl jq git ruby"
        echo "  • RHEL/CentOS: yum install curl jq git ruby"
        echo
        exit 1
    fi
    
    log_success "All dependencies found"
}

# Input validation
validate_version_format() {
    local version="$1"
    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]; then
        log_error "Invalid version format: $version"
        echo "Version must follow semantic versioning (vX.Y.Z or vX.Y.Z-suffix)"
        return 1
    fi
    return 0
}

validate_repository_format() {
    local repo="$1"
    if [[ ! "$repo" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
        log_error "Invalid repository format: $repo"
        echo "Repository must be in owner/repo format"
        return 1
    fi
    return 0
}

# Metadata operations
download_metadata() {
    local version="$1"
    local source_repo="$2"
    local metadata_file="$3"
    
    show_progress "Downloading metadata for $version"
    
    local metadata_url="https://github.com/$source_repo/releases/download/$version/$METADATA_FILENAME"
    log_debug "Metadata URL: $metadata_url"
    
    # Download with retry logic and exponential backoff
    local max_attempts=3
    for attempt in 1 2 3; do
        log_debug "Download attempt $attempt of $max_attempts"
        
        if curl -L -f -s "$metadata_url" -o "$metadata_file"; then
            log_success "Metadata downloaded successfully"
            return 0
        else
            log_warning "Download attempt $attempt failed"
            if [ $attempt -eq $max_attempts ]; then
                log_error "Could not download metadata after $max_attempts attempts"
                log_error "URL: $metadata_url"
                echo
                echo "Troubleshooting steps:"
                echo "  1. Verify the release $version exists in $source_repo"
                echo "  2. Check that $METADATA_FILENAME is uploaded as a release asset"
                echo "  3. Verify internet connectivity"
                echo "  4. Check GitHub status at https://status.github.com"
                return 1
            fi
            
            # Exponential backoff: 2^attempt seconds
            local backoff_delay=$((2 ** attempt))
            log_debug "Retrying in $backoff_delay seconds (exponential backoff)"
            sleep $backoff_delay
        fi
    done
    
    return 1
}

validate_metadata() {
    local metadata_file="$1"
    local expected_version="$2"
    
    show_progress "Validating metadata structure and content"
    
    # Check file exists and is not empty
    if [ ! -f "$metadata_file" ] || [ ! -s "$metadata_file" ]; then
        log_error "Metadata file is missing or empty"
        return 1
    fi
    
    # Validate JSON syntax
    if ! jq empty "$metadata_file" >/dev/null 2>&1; then
        log_error "Metadata file contains invalid JSON"
        log_debug "JSON validation error: $(jq empty "$metadata_file" 2>&1)"
        return 1
    fi
    
    log_success "JSON syntax is valid"
    
    # Check required fields
    local validation_errors=0
    local required_fields=("schema_version" "metadata.version" "metadata.archive_url" "metadata.sha256" "formula_updates")
    
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$metadata_file" >/dev/null 2>&1; then
            log_error "Missing required field: $field"
            validation_errors=$((validation_errors + 1))
        fi
    done
    
    if [ $validation_errors -gt 0 ]; then
        log_error "Metadata validation failed with $validation_errors errors"
        return 1
    fi
    
    # Validate version consistency
    local metadata_version
    metadata_version=$(jq -r '.metadata.version' "$metadata_file")
    
    if [ "$metadata_version" != "$expected_version" ]; then
        log_error "Version mismatch in metadata"
        echo "  Expected: $expected_version"
        echo "  Found: $metadata_version"
        return 1
    fi
    
    log_success "All required fields validated"
    log_success "Version consistency verified"
    
    # Display metadata summary
    log_info "Metadata Summary:"
    echo "  • Schema Version: $(jq -r '.schema_version' "$metadata_file")"
    echo "  • Version: $(jq -r '.metadata.version' "$metadata_file")"
    echo "  • Archive URL: $(jq -r '.metadata.archive_url' "$metadata_file")"
    echo "  • SHA256: $(jq -r '.metadata.sha256' "$metadata_file" | head -c 16)..."
    echo "  • Timestamp: $(jq -r '.metadata.timestamp' "$metadata_file")"
    
    return 0
}

# Archive verification
verify_archive() {
    local metadata_file="$1"
    
    show_progress "Verifying source archive integrity"
    
    # Extract archive information
    local archive_url
    local expected_sha256
    archive_url=$(jq -r '.metadata.archive_url' "$metadata_file")
    expected_sha256=$(jq -r '.metadata.sha256' "$metadata_file")
    
    log_debug "Archive URL: $archive_url"
    log_debug "Expected SHA256: $expected_sha256"
    
    # Download archive with retry logic
    local archive_file="$TEMP_DIR/source-archive.tar.gz"
    local max_attempts=3
    
    for attempt in 1 2 3; do
        log_debug "Archive download attempt $attempt of $max_attempts"
        
        if curl -L -f -s "$archive_url" -o "$archive_file"; then
            log_success "Source archive downloaded"
            break
        else
            log_warning "Archive download attempt $attempt failed"
            if [ $attempt -eq $max_attempts ]; then
                log_error "Could not download source archive after $max_attempts attempts"
                log_error "URL: $archive_url"
                echo
                echo "Troubleshooting steps:"
                echo "  1. Verify the archive URL is accessible"
                echo "  2. Check internet connectivity"
                echo "  3. Verify the release exists and is published"
                return 1
            fi
            
            local backoff_delay=$((2 ** attempt))
            log_debug "Retrying in $backoff_delay seconds"
            sleep $backoff_delay
        fi
    done
    
    # Calculate checksum
    log_debug "Calculating SHA256 checksum"
    local actual_sha256
    if command -v sha256sum >/dev/null 2>&1; then
        actual_sha256=$(sha256sum "$archive_file" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
        actual_sha256=$(shasum -a 256 "$archive_file" | cut -d' ' -f1)
    else
        log_error "No checksum tool available"
        return 1
    fi
    
    # Verify checksum
    if [ "$actual_sha256" = "$expected_sha256" ]; then
        log_success "Checksum verification passed"
        log_debug "SHA256: $actual_sha256"
        
        # Get archive size for logging
        local archive_size
        archive_size=$(wc -c < "$archive_file")
        log_info "Archive verified: $archive_size bytes"
        
        return 0
    else
        log_error "Checksum verification failed"
        echo "  Expected: $expected_sha256"
        echo "  Actual:   $actual_sha256"
        echo "  Archive:  $archive_url"
        echo "  Size:     $(wc -c < "$archive_file") bytes"
        echo
        echo "This indicates:"
        echo "  1. The archive was corrupted during download"
        echo "  2. The metadata contains an incorrect checksum"
        echo "  3. The wrong archive version was downloaded"
        echo
        echo "Please verify the release metadata and try again"
        return 1
    fi
}

# Formula operations
update_formula() {
    local metadata_file="$1"
    local formula_file="$2"
    local dry_run="$3"
    
    if [ "$dry_run" = true ]; then
        show_progress "Previewing formula changes (dry-run mode)"
    else
        show_progress "Updating formula file"
    fi
    
    # Check if formula file exists
    if [ ! -f "$formula_file" ]; then
        log_error "Formula file not found: $formula_file"
        echo
        echo "Troubleshooting steps:"
        echo "  1. Verify you're in the correct tap repository directory"
        echo "  2. Check that $formula_file exists"
        echo "  3. Use --formula-file to specify a different path"
        return 1
    fi
    
    # Extract values from metadata
    local version
    local archive_url
    local sha256_checksum
    local version_placeholder
    local sha256_placeholder
    
    version=$(jq -r '.metadata.version' "$metadata_file")
    archive_url=$(jq -r '.metadata.archive_url' "$metadata_file")
    sha256_checksum=$(jq -r '.metadata.sha256' "$metadata_file")
    version_placeholder=$(jq -r '.formula_updates.version_placeholder // null' "$metadata_file")
    sha256_placeholder=$(jq -r '.formula_updates.sha256_placeholder // null' "$metadata_file")
    
    log_info "Formula Update Details:"
    echo "  • Version: $version"
    echo "  • Archive URL: $archive_url"
    echo "  • SHA256: $sha256_checksum"
    echo "  • Version Placeholder: $version_placeholder"
    echo "  • SHA256 Placeholder: $sha256_placeholder"
    
    if [ "$dry_run" = true ]; then
        log_info "DRY-RUN: Would make the following changes to $formula_file:"
        
        # Show what would change (create temporary file for preview)
        local temp_formula="$TEMP_DIR/formula-preview.rb"
        cp "$formula_file" "$temp_formula"
        
        # Apply the same substitutions that would be made
        sed -i.bak "s|archive/v[0-9][0-9.]*\.tar\.gz|archive/$version.tar.gz|g" "$temp_formula"
        sed -i.bak "s|version \"v[0-9][0-9.]*\"|version \"$version\"|g" "$temp_formula"
        sed -i.bak "s|sha256 \"[a-f0-9]\{64\}\"|sha256 \"$sha256_checksum\"|g" "$temp_formula"
        
        if [ "$version_placeholder" != "null" ]; then
            sed -i.bak "s|$version_placeholder|$version|g" "$temp_formula"
        fi
        
        if [ "$sha256_placeholder" != "null" ]; then
            sed -i.bak "s|$sha256_placeholder|$sha256_checksum|g" "$temp_formula"
        fi
        
        # Show differences
        echo
        echo "--- Current Formula ---"
        grep -E "(version|sha256|archive)" "$formula_file" | head -5
        echo
        echo "--- Proposed Changes ---"
        grep -E "(version|sha256|archive)" "$temp_formula" | head -5
        echo
        
        log_success "DRY-RUN: Preview completed. No files were modified."
        return 0
    fi
    
    # Create backup
    local backup_file="$formula_file$BACKUP_SUFFIX"
    cp "$formula_file" "$backup_file"
    log_info "Created backup: $backup_file"
    
    # Update formula with actual values
    log_debug "Applying formula updates"
    
    # Use regex patterns to update version and checksum
    sed -i.tmp "s|archive/v[0-9][0-9.]*\.tar\.gz|archive/$version.tar.gz|g" "$formula_file"
    sed -i.tmp "s|version \"v[0-9][0-9.]*\"|version \"$version\"|g" "$formula_file"
    sed -i.tmp "s|sha256 \"[a-f0-9]\{64\}\"|sha256 \"$sha256_checksum\"|g" "$formula_file"
    
    # Handle placeholder-based updates if they exist
    if [ "$version_placeholder" != "null" ]; then
        sed -i.tmp "s|$version_placeholder|$version|g" "$formula_file"
    fi
    
    if [ "$sha256_placeholder" != "null" ]; then
        sed -i.tmp "s|$sha256_placeholder|$sha256_checksum|g" "$formula_file"
    fi
    
    # Clean up temporary files
    rm -f "$formula_file.tmp"
    
    log_success "Formula file updated successfully"
    return 0
}

validate_formula() {
    local formula_file="$1"
    local version="$2"
    local expected_sha256="$3"
    local skip_validation="$4"
    
    if [ "$skip_validation" = true ]; then
        log_warning "Skipping comprehensive formula validation (--skip-validation)"
        return 0
    fi
    
    show_progress "Validating updated formula"
    
    local validation_failed=false
    
    log_debug "Starting comprehensive formula validation"
    log_debug "Formula file: $formula_file"
    log_debug "Expected version: $version"
    log_debug "Expected SHA256: $expected_sha256"
    
    # Step 1: Ruby syntax validation
    log_debug "Validating Ruby syntax"
    if ruby -c "$formula_file" >/dev/null 2>&1; then
        log_success "Ruby syntax is valid"
    else
        log_error "Formula has Ruby syntax errors"
        echo "Ruby syntax validation failed:"
        ruby -c "$formula_file" 2>&1 | sed 's/^/  /'
        validation_failed=true
    fi
    
    # Step 2: Formula structure validation
    log_debug "Validating Homebrew formula structure"
    
    local required_components=(
        "class.*Formula"
        "desc.*\""
        "homepage.*\""
        "url.*\""
        "version.*\""
        "sha256.*\""
        "def install"
    )
    
    local component_names=(
        "Formula class definition"
        "Description field"
        "Homepage field"
        "URL field"
        "Version field"
        "SHA256 field"
        "Install method"
    )
    
    for i in "${!required_components[@]}"; do
        local pattern="${required_components[i]}"
        local name="${component_names[i]}"
        if grep -q "$pattern" "$formula_file"; then
            log_debug "✓ Found: $name"
        else
            log_error "✗ Missing: $name"
            validation_failed=true
        fi
    done
    
    # Step 3: Verify updated values
    log_debug "Verifying formula content updates"
    
    if grep -q "version \"$version\"" "$formula_file"; then
        log_debug "✓ Version $version found in formula"
    else
        log_error "✗ Version $version not found in updated formula"
        validation_failed=true
    fi
    
    if grep -q "sha256 \"$expected_sha256\"" "$formula_file"; then
        log_debug "✓ SHA256 checksum found in formula"
    else
        log_error "✗ SHA256 checksum not found in updated formula"
        validation_failed=true
    fi
    
    if grep -q "archive/$version.tar.gz" "$formula_file"; then
        log_debug "✓ Archive URL with version $version found"
    else
        log_error "✗ Archive URL with version $version not found"
        validation_failed=true
    fi
    
    # Step 4: Check for remaining placeholders
    log_debug "Checking for unreplaced placeholders"
    local placeholder_patterns=(
        "VERSION_PLACEHOLDER"
        "SHA256_PLACEHOLDER"
        "{{VERSION}}"
        "{{SHA256}}"
        "{{CHECKSUM}}"
    )
    
    local placeholders_found=false
    for pattern in "${placeholder_patterns[@]}"; do
        if grep -q "$pattern" "$formula_file"; then
            log_warning "Found unreplaced placeholder: $pattern"
            grep -n "$pattern" "$formula_file" | sed 's/^/    /'
            placeholders_found=true
        fi
    done
    
    if [ "$placeholders_found" = true ]; then
        log_warning "Formula contains unreplaced placeholders that may need manual attention"
    else
        log_debug "✓ No unreplaced placeholders found"
    fi
    
    # Step 5: Additional integrity checks
    log_debug "Running additional integrity checks"
    
    # Check for license field
    if grep -q "license.*\"" "$formula_file"; then
        log_debug "✓ License field found"
    else
        log_warning "License field not found (recommended but not required)"
    fi
    
    # Validate formula naming
    if grep -q "class UsbipdMac.*Formula" "$formula_file"; then
        log_debug "✓ Formula class name is correct"
    else
        log_warning "Formula class name may be incorrect"
    fi
    
    # Final validation result
    if [ "$validation_failed" = true ]; then
        log_error "Formula validation failed with critical errors"
        
        # Restore backup on validation failure
        local backup_file="$formula_file$BACKUP_SUFFIX"
        if [ -f "$backup_file" ]; then
            log_warning "Restoring formula from backup due to validation failure"
            cp "$backup_file" "$formula_file"
            log_success "Formula restored from backup"
        else
            log_error "No backup file found for restoration"
        fi
        
        return 1
    else
        log_success "Updated formula passed all validation checks"
        return 0
    fi
}

# Git operations
commit_and_show_status() {
    local formula_file="$1"
    local version="$2"
    local source_repo="$3"
    local dry_run="$4"
    
    if [ "$dry_run" = true ]; then
        log_info "DRY-RUN: Would commit and push changes (skipped)"
        return 0
    fi
    
    show_progress "Committing changes and showing status"
    
    # Check if there are changes to commit
    if git diff --quiet "$formula_file"; then
        log_warning "No changes detected in formula file"
        log_info "Current formula content is already up to date"
        return 0
    fi
    
    log_info "Changes detected in formula file"
    
    # Show git status
    log_debug "Git repository status:"
    git status --porcelain | sed 's/^/  /'
    
    # Show changes summary
    log_info "Changes summary:"
    git diff --stat "$formula_file" | sed 's/^/  /' || log_debug "Unable to show diff stats"
    
    # Show what changed
    echo
    log_info "Formula changes:"
    git diff "$formula_file" | head -20 | sed 's/^/  /'
    echo
    
    log_success "Changes ready for commit"
    log_info "Next steps:"
    echo "  1. Review the changes above"
    echo "  2. If satisfied, commit with: git add $formula_file && git commit -m \"feat: update formula to $version\""
    echo "  3. Push changes with: git push origin main"
    echo
    echo "Manual commit message suggestion:"
    echo "  git commit -m \"feat: update formula to $version - manual update"
    echo ""
    echo "Manual formula update from $source_repo release $version"
    echo "Updated via $SCRIPT_NAME for manual recovery/testing"
    echo ""
    echo "✅ Formula validation passed"
    echo "🔧 Manual update via standalone script\""
    echo
    
    return 0
}

# Cleanup function
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        log_debug "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    
    log_error "Script failed on line $line_number with exit code $exit_code"
    
    # Show execution time
    local end_timestamp=$(date +%s)
    local duration=$((end_timestamp - start_timestamp))
    log_info "Script execution time: ${duration}s"
    
    echo
    echo "🛠️ Troubleshooting Guide:"
    echo
    echo "Common Issues and Solutions:"
    echo "  • Network errors: Check internet connectivity and GitHub status"
    echo "  • Validation errors: Review formula syntax and Homebrew requirements"
    echo "  • Permission errors: Ensure write access to formula file and git repository"
    echo "  • Dependency errors: Install missing tools (curl, jq, git, ruby, shasum)"
    echo "  • Version conflicts: Use --force to override existing version checks"
    echo
    echo "Recovery Options:"
    echo "  • Run with --dry-run to preview changes without modifications"
    echo "  • Use --verbose for detailed debugging information"
    echo "  • Check backup files with $BACKUP_SUFFIX extension"
    echo "  • Use --skip-validation for emergency recovery scenarios"
    echo
    echo "For more help:"
    echo "  • Run: $SCRIPT_NAME --help"
    echo "  • Check GitHub workflow logs for similar issues"
    echo "  • Review the formula file manually for syntax issues"
    
    cleanup
    exit $exit_code
}

# Trap errors
trap 'handle_error $LINENO' ERR
trap cleanup EXIT

# Argument parsing
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                VERSION="$2"
                shift 2
                ;;
            --source-repo)
                SOURCE_REPO="$2"
                shift 2
                ;;
            --formula-file)
                FORMULA_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            --version-info)
                show_version_info
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Interactive version selection
prompt_for_version() {
    if [ -z "$VERSION" ]; then
        log_info "No version specified. Fetching latest release from $SOURCE_REPO..."
        
        # Try to get the latest release
        local latest_version
        latest_version=$(curl -s "https://api.github.com/repos/$SOURCE_REPO/releases/latest" | jq -r '.tag_name // empty')
        
        if [ -n "$latest_version" ] && [ "$latest_version" != "null" ]; then
            log_info "Latest release found: $latest_version"
            echo
            read -p "Use latest release $latest_version? [Y/n]: " -r response
            if [[ $response =~ ^[Nn]$ ]]; then
                read -p "Enter version to process (e.g., v1.2.3): " -r VERSION
            else
                VERSION="$latest_version"
            fi
        else
            log_warning "Could not fetch latest release"
            read -p "Enter version to process (e.g., v1.2.3): " -r VERSION
        fi
        
        if [ -z "$VERSION" ]; then
            log_error "Version is required"
            exit 1
        fi
    fi
}

# Main execution function
main() {
    # Show script header
    echo "============================================================"
    echo "${SCRIPT_DESCRIPTION}"
    echo "Version: ${SCRIPT_VERSION}"
    echo "============================================================"
    echo
    
    # Parse arguments
    parse_arguments "$@"
    
    # Check dependencies first
    check_dependencies
    
    # Interactive version selection if not provided
    prompt_for_version
    
    # Validate inputs
    if ! validate_version_format "$VERSION"; then
        exit 1
    fi
    
    if ! validate_repository_format "$SOURCE_REPO"; then
        exit 1
    fi
    
    # Show configuration
    log_info "Configuration:"
    echo "  • Version: $VERSION"
    echo "  • Source Repository: $SOURCE_REPO"
    echo "  • Formula File: $FORMULA_FILE"
    echo "  • Dry Run: $DRY_RUN"
    echo "  • Force: $FORCE"
    echo "  • Skip Validation: $SKIP_VALIDATION"
    echo "  • Verbose: $VERBOSE"
    echo
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    log_debug "Created temporary directory: $TEMP_DIR"
    
    # Check if formula already has this version (unless forced)
    if [ "$FORCE" != true ] && [ -f "$FORMULA_FILE" ]; then
        if grep -q "version \"$VERSION\"" "$FORMULA_FILE"; then
            log_warning "Formula already contains version $VERSION"
            echo "Use --force to override this check, or specify a different version"
            exit 1
        fi
    fi
    
    # Main workflow steps
    local metadata_file="$TEMP_DIR/$METADATA_FILENAME"
    
    # Step 1: Download metadata
    if ! download_metadata "$VERSION" "$SOURCE_REPO" "$metadata_file"; then
        exit 1
    fi
    
    # Step 2: Validate metadata
    if ! validate_metadata "$metadata_file" "$VERSION"; then
        exit 1
    fi
    
    # Step 3: Verify archive (unless dry-run)
    if [ "$DRY_RUN" != true ]; then
        if ! verify_archive "$metadata_file"; then
            exit 1
        fi
    else
        log_info "DRY-RUN: Skipping archive verification"
    fi
    
    # Step 4: Update formula
    if ! update_formula "$metadata_file" "$FORMULA_FILE" "$DRY_RUN"; then
        exit 1
    fi
    
    # Step 5: Validate formula (unless dry-run)
    if [ "$DRY_RUN" != true ]; then
        local expected_sha256
        expected_sha256=$(jq -r '.metadata.sha256' "$metadata_file")
        if ! validate_formula "$FORMULA_FILE" "$VERSION" "$expected_sha256" "$SKIP_VALIDATION"; then
            exit 1
        fi
    else
        log_info "DRY-RUN: Skipping formula validation"
    fi
    
    # Step 6: Show git status and next steps
    if ! commit_and_show_status "$FORMULA_FILE" "$VERSION" "$SOURCE_REPO" "$DRY_RUN"; then
        exit 1
    fi
    
    # Success summary
    local end_timestamp=$(date +%s)
    local duration=$((end_timestamp - start_timestamp))
    
    echo "============================================================"
    if [ "$DRY_RUN" = true ]; then
        log_success "DRY-RUN completed successfully in ${duration}s"
        echo
        echo "✅ Preview Summary:"
        echo "  • Metadata downloaded and validated"
        echo "  • Formula changes previewed"
        echo "  • No files were modified"
        echo
        echo "To apply changes, run without --dry-run:"
        echo "  $SCRIPT_NAME --version $VERSION"
    else
        log_success "Formula update completed successfully in ${duration}s"
        echo
        echo "✅ Update Summary:"
        echo "  • Metadata downloaded and validated"
        echo "  • Source archive verified"
        echo "  • Formula updated to $VERSION"
        echo "  • Formula validation passed"
        echo "  • Backup created: $FORMULA_FILE$BACKUP_SUFFIX"
        echo
        echo "📋 Next Steps:"
        echo "  1. Review the changes in $FORMULA_FILE"
        echo "  2. Test the formula locally if needed"
        echo "  3. Commit and push the changes to complete the update"
        echo
        echo "🔧 Git Commands:"
        echo "  git add $FORMULA_FILE"
        echo "  git commit -m \"feat: update formula to $VERSION - manual update\""
        echo "  git push origin main"
    fi
    echo "============================================================"
}

# Execute main function
main "$@"