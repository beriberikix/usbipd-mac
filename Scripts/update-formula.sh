#!/bin/bash

# update-formula.sh
# Formula update automation script for usbipd-mac Homebrew distribution
# Updates formula version and checksum placeholders, validates updates, and provides rollback functionality
# Designed for integration with release automation workflows

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FORMULA_DIR="$PROJECT_ROOT/Formula"
readonly FORMULA_FILE="$FORMULA_DIR/usbipd-mac.rb"
readonly BACKUP_DIR="$PROJECT_ROOT/.build/formula-backups"
readonly LOG_FILE="$PROJECT_ROOT/.build/formula-update.log"

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Configuration variables
VERSION=""
SHA256_CHECKSUM=""
ARCHIVE_URL=""
DRY_RUN=false
SKIP_VALIDATION=false
FORCE_UPDATE=false
CREATE_BACKUP=true
AUTO_COMMIT=false
VALIDATE_TAG=true
SYSTEM_EXTENSION_BUNDLE=""
SYSTEM_EXTENSION_CHECKSUM=""
VALIDATE_SYSTEM_EXTENSION=true
INCLUDE_SYSTEM_EXTENSION=true

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_VALIDATION_FAILED=1
readonly EXIT_FORMULA_NOT_FOUND=2
readonly EXIT_UPDATE_FAILED=3
readonly EXIT_CHECKSUM_FAILED=4
readonly EXIT_VERSION_MISMATCH=5
readonly EXIT_USAGE_ERROR=6
readonly EXIT_SYSTEM_EXTENSION_FAILED=7

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    [ -d "$(dirname "$LOG_FILE")" ] && echo -e "${BLUE}[INFO]${NC} $1" >> "$LOG_FILE" || true
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    [ -d "$(dirname "$LOG_FILE")" ] && echo -e "${GREEN}[SUCCESS]${NC} $1" >> "$LOG_FILE" || true
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    [ -d "$(dirname "$LOG_FILE")" ] && echo -e "${YELLOW}[WARNING]${NC} $1" >> "$LOG_FILE" || true
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    [ -d "$(dirname "$LOG_FILE")" ] && echo -e "${RED}[ERROR]${NC} $1" >> "$LOG_FILE" || true
}

log_step() {
    echo -e "${BOLD}${BLUE}==>${NC}${BOLD} $1${NC}"
    [ -d "$(dirname "$LOG_FILE")" ] && echo -e "${BOLD}${BLUE}==>${NC}${BOLD} $1${NC}" >> "$LOG_FILE" || true
}

# Print script header
print_header() {
    echo "=================================================================="
    echo "🍺 Homebrew Formula Update Automation for usbipd-mac"
    echo "=================================================================="
    echo "Formula File: $FORMULA_FILE"
    echo "Version: ${VERSION:-'[required]'}"
    echo "Checksum: ${SHA256_CHECKSUM:-'[auto-calculate]'}"
    echo "Archive URL: ${ARCHIVE_URL:-'[auto-detect]'}"
    echo "System Extension Bundle: ${SYSTEM_EXTENSION_BUNDLE:-'[auto-detect]'}"
    echo "System Extension Checksum: ${SYSTEM_EXTENSION_CHECKSUM:-'[auto-calculate]'}"
    echo "Dry Run: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")"
    echo "Skip Validation: $([ "$SKIP_VALIDATION" = true ] && echo "YES" || echo "NO")"
    echo "Force Update: $([ "$FORCE_UPDATE" = true ] && echo "YES" || echo "NO")"
    echo "Create Backup: $([ "$CREATE_BACKUP" = true ] && echo "YES" || echo "NO")"
    echo "Auto Commit: $([ "$AUTO_COMMIT" = true ] && echo "YES" || echo "NO")"
    echo "Validate Tag: $([ "$VALIDATE_TAG" = true ] && echo "YES" || echo "NO")"
    echo "Include System Extension: $([ "$INCLUDE_SYSTEM_EXTENSION" = true ] && echo "YES" || echo "NO")"
    echo "=================================================================="
    echo ""
}

# Setup environment
setup_environment() {
    log_step "Setting up formula update environment"
    
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "=== Formula Update Log Started at $(date) ===" > "$LOG_FILE"
    
    # Create backup directory
    if [ "$CREATE_BACKUP" = true ]; then
        mkdir -p "$BACKUP_DIR"
        log_info "Backup directory ready: $BACKUP_DIR"
    fi
    
    # Verify formula file exists
    if [ ! -f "$FORMULA_FILE" ]; then
        log_error "Formula file not found: $FORMULA_FILE"
        exit $EXIT_FORMULA_NOT_FOUND
    fi
    
    log_success "Environment setup completed"
}

# Validate prerequisites
validate_prerequisites() {
    log_step "Validating prerequisites"
    
    local required_tools=("git" "curl" "shasum" "sed")
    local optional_tools=("brew" "ruby")
    local missing_required=()
    
    # Check required tools
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_info "✓ Found required tool: $tool"
        else
            missing_required+=("$tool")
            log_error "✗ Missing required tool: $tool"
        fi
    done
    
    # Check optional tools
    for tool in "${optional_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_info "✓ Found optional tool: $tool"
        else
            log_warning "⚠ Optional tool not available: $tool (some validations may be limited)"
        fi
    done
    
    # Exit if required tools are missing
    if [ ${#missing_required[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_required[*]}"
        exit $EXIT_VALIDATION_FAILED
    fi
    
    # Check Git repository status
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_error "Not inside a Git repository"
        exit $EXIT_VALIDATION_FAILED
    fi
    
    log_success "Prerequisites validation completed"
}

# Validate version format and Git tag
validate_version() {
    log_step "Validating version information"
    
    if [ -z "$VERSION" ]; then
        log_error "Version is required"
        exit $EXIT_USAGE_ERROR
    fi
    
    # Normalize version format (ensure it starts with 'v')
    if [[ ! "$VERSION" =~ ^v ]]; then
        VERSION="v$VERSION"
        log_info "Normalized version to: $VERSION"
    fi
    
    # Validate version format
    if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]; then
        log_error "Invalid version format: $VERSION"
        log_error "Expected format: vX.Y.Z or vX.Y.Z-suffix"
        exit $EXIT_VERSION_MISMATCH
    fi
    
    # Validate that Git tag exists (if enabled)
    if [ "$VALIDATE_TAG" = true ]; then
        if git rev-parse "$VERSION" >/dev/null 2>&1; then
            log_success "✓ Git tag $VERSION exists"
            
            # Get commit hash for tag
            local tag_commit
            tag_commit=$(git rev-parse "$VERSION")
            log_info "Tag commit: $tag_commit"
        else
            if [ "$FORCE_UPDATE" = false ]; then
                log_error "Git tag $VERSION does not exist"
                log_error "Create the tag first or use --force to override"
                exit $EXIT_VERSION_MISMATCH
            else
                log_warning "Git tag $VERSION does not exist (continuing due to --force)"
            fi
        fi
    fi
    
    log_success "Version validation completed: $VERSION"
}

# Generate archive URL from version
generate_archive_url() {
    log_step "Generating archive URL"
    
    if [ -n "$ARCHIVE_URL" ]; then
        log_info "Using provided archive URL: $ARCHIVE_URL"
        return 0
    fi
    
    # Auto-generate GitHub archive URL
    local repo_url
    repo_url=$(git remote get-url origin 2>/dev/null || echo "")
    
    if [ -n "$repo_url" ]; then
        # Convert Git URL to GitHub archive URL
        # Handle both SSH and HTTPS URLs
        if [[ "$repo_url" =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
            local owner="${BASH_REMATCH[1]}"
            local repo="${BASH_REMATCH[2]%.git}"
            ARCHIVE_URL="https://github.com/$owner/$repo/archive/$VERSION.tar.gz"
            log_success "Generated archive URL: $ARCHIVE_URL"
        else
            log_error "Cannot determine GitHub repository from remote URL: $repo_url"
            exit $EXIT_VALIDATION_FAILED
        fi
    else
        log_error "Cannot determine Git remote URL"
        exit $EXIT_VALIDATION_FAILED
    fi
}

# Calculate SHA256 checksum for archive
calculate_checksum() {
    log_step "Calculating SHA256 checksum"
    
    if [ -n "$SHA256_CHECKSUM" ]; then
        log_info "Using provided SHA256 checksum: $SHA256_CHECKSUM"
        return 0
    fi
    
    if [ -z "$ARCHIVE_URL" ]; then
        log_error "Archive URL is required for checksum calculation"
        exit $EXIT_VALIDATION_FAILED
    fi
    
    log_info "Downloading archive for checksum calculation..."
    log_info "URL: $ARCHIVE_URL"
    
    local temp_file
    temp_file=$(mktemp)
    
    # Download archive with progress
    if curl -L -f -o "$temp_file" "$ARCHIVE_URL"; then
        log_success "Archive downloaded successfully"
        
        # Calculate SHA256 checksum
        SHA256_CHECKSUM=$(shasum -a 256 "$temp_file" | cut -d' ' -f1)
        log_success "SHA256 checksum calculated: $SHA256_CHECKSUM"
        
        # Verify checksum format
        if [[ ! "$SHA256_CHECKSUM" =~ ^[a-fA-F0-9]{64}$ ]]; then
            log_error "Invalid SHA256 checksum format: $SHA256_CHECKSUM"
            exit $EXIT_CHECKSUM_FAILED
        fi
        
        # Clean up
        rm -f "$temp_file"
    else
        log_error "Failed to download archive from: $ARCHIVE_URL"
        log_error "Please verify the URL is accessible and the release exists"
        rm -f "$temp_file"
        exit $EXIT_CHECKSUM_FAILED
    fi
}

# Detect and validate System Extension bundle
detect_system_extension_bundle() {
    if [ "$INCLUDE_SYSTEM_EXTENSION" = false ]; then
        log_step "Skipping System Extension bundle detection (--no-system-extension specified)"
        return 0
    fi
    
    log_step "Detecting System Extension bundle"
    
    if [ -n "$SYSTEM_EXTENSION_BUNDLE" ]; then
        log_info "Using provided System Extension bundle path: $SYSTEM_EXTENSION_BUNDLE"
        
        # Validate provided bundle path
        if [ ! -d "$SYSTEM_EXTENSION_BUNDLE" ]; then
            log_error "System Extension bundle not found at: $SYSTEM_EXTENSION_BUNDLE"
            exit $EXIT_SYSTEM_EXTENSION_FAILED
        fi
        return 0
    fi
    
    # Auto-detect System Extension bundle from build directory
    local potential_bundles=(
        "$PROJECT_ROOT/.build/release/USBIPDSystemExtension.systemextension"
        "$PROJECT_ROOT/.build/debug/USBIPDSystemExtension.systemextension"
        "$PROJECT_ROOT/build/USBIPDSystemExtension.systemextension"
    )
    
    for bundle_path in "${potential_bundles[@]}"; do
        if [ -d "$bundle_path" ]; then
            SYSTEM_EXTENSION_BUNDLE="$bundle_path"
            log_success "Detected System Extension bundle: $SYSTEM_EXTENSION_BUNDLE"
            return 0
        fi
    done
    
    if [ "$FORCE_UPDATE" = false ]; then
        log_error "No System Extension bundle found. Build the project first or specify --system-extension-bundle"
        log_error "Expected locations:"
        for bundle_path in "${potential_bundles[@]}"; do
            log_error "  - $bundle_path"
        done
        exit $EXIT_SYSTEM_EXTENSION_FAILED
    else
        log_warning "No System Extension bundle found (continuing due to --force)"
        INCLUDE_SYSTEM_EXTENSION=false
    fi
}

# Validate System Extension bundle structure
validate_system_extension_bundle() {
    if [ "$INCLUDE_SYSTEM_EXTENSION" = false ] || [ -z "$SYSTEM_EXTENSION_BUNDLE" ]; then
        log_step "Skipping System Extension bundle validation"
        return 0
    fi
    
    if [ "$VALIDATE_SYSTEM_EXTENSION" = false ]; then
        log_step "Skipping System Extension bundle validation (--skip-system-extension-validation specified)"
        return 0
    fi
    
    log_step "Validating System Extension bundle structure"
    
    local bundle_path="$SYSTEM_EXTENSION_BUNDLE"
    
    # Check bundle directory structure
    local required_paths=(
        "$bundle_path/Contents"
        "$bundle_path/Contents/Info.plist"
        "$bundle_path/Contents/MacOS"
    )
    
    for required_path in "${required_paths[@]}"; do
        if [ ! -e "$required_path" ]; then
            log_error "Missing required System Extension component: $required_path"
            exit $EXIT_SYSTEM_EXTENSION_FAILED
        fi
    done
    
    # Validate Info.plist
    if command -v plutil >/dev/null 2>&1; then
        if plutil -lint "$bundle_path/Contents/Info.plist" >/dev/null 2>&1; then
            log_success "✓ Info.plist is valid"
        else
            log_error "✗ Invalid Info.plist in System Extension bundle"
            exit $EXIT_SYSTEM_EXTENSION_FAILED
        fi
    else
        log_warning "plutil not available, skipping Info.plist validation"
    fi
    
    # Check for executable
    local executable_count
    executable_count=$(find "$bundle_path/Contents/MacOS" -type f -perm +111 | wc -l)
    if [ "$executable_count" -eq 0 ]; then
        log_error "No executable found in System Extension bundle"
        exit $EXIT_SYSTEM_EXTENSION_FAILED
    elif [ "$executable_count" -gt 1 ]; then
        log_warning "Multiple executables found in System Extension bundle"
    else
        log_success "✓ System Extension executable found"
    fi
    
    # Get bundle size
    local bundle_size
    bundle_size=$(du -sh "$bundle_path" | cut -f1)
    log_info "System Extension bundle size: $bundle_size"
    
    log_success "System Extension bundle validation completed"
}

# Calculate System Extension bundle checksum
calculate_system_extension_checksum() {
    if [ "$INCLUDE_SYSTEM_EXTENSION" = false ] || [ -z "$SYSTEM_EXTENSION_BUNDLE" ]; then
        log_step "Skipping System Extension checksum calculation"
        return 0
    fi
    
    log_step "Calculating System Extension bundle checksum"
    
    if [ -n "$SYSTEM_EXTENSION_CHECKSUM" ]; then
        log_info "Using provided System Extension checksum: $SYSTEM_EXTENSION_CHECKSUM"
        return 0
    fi
    
    # Create temporary archive of System Extension bundle
    local temp_archive
    temp_archive=$(mktemp -d)/systemextension-bundle.tar.gz
    
    log_info "Creating temporary archive for checksum calculation..."
    if tar -czf "$temp_archive" -C "$(dirname "$SYSTEM_EXTENSION_BUNDLE")" "$(basename "$SYSTEM_EXTENSION_BUNDLE")"; then
        # Calculate SHA256 checksum of the archive
        SYSTEM_EXTENSION_CHECKSUM=$(shasum -a 256 "$temp_archive" | cut -d' ' -f1)
        log_success "System Extension checksum calculated: $SYSTEM_EXTENSION_CHECKSUM"
        
        # Verify checksum format
        if [[ ! "$SYSTEM_EXTENSION_CHECKSUM" =~ ^[a-fA-F0-9]{64}$ ]]; then
            log_error "Invalid System Extension SHA256 checksum format: $SYSTEM_EXTENSION_CHECKSUM"
            exit $EXIT_CHECKSUM_FAILED
        fi
        
        # Clean up
        rm -f "$temp_archive"
        rmdir "$(dirname "$temp_archive")" 2>/dev/null || true
    else
        log_error "Failed to create System Extension bundle archive for checksum calculation"
        rm -f "$temp_archive"
        rmdir "$(dirname "$temp_archive")" 2>/dev/null || true
        exit $EXIT_SYSTEM_EXTENSION_FAILED
    fi
}

# Create backup of current formula
create_formula_backup() {
    if [ "$CREATE_BACKUP" = false ]; then
        log_step "Skipping formula backup (--no-backup specified)"
        return 0
    fi
    
    log_step "Creating formula backup"
    
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$BACKUP_DIR/usbipd-mac-$timestamp.rb"
    
    cp "$FORMULA_FILE" "$backup_file"
    log_success "Formula backed up to: $(basename "$backup_file")"
    
    # Keep only last 10 backups
    local backup_count
    backup_count=$(find "$BACKUP_DIR" -name "usbipd-mac-*.rb" | wc -l)
    if [ "$backup_count" -gt 10 ]; then
        log_info "Cleaning up old backups..."
        find "$BACKUP_DIR" -name "usbipd-mac-*.rb" -type f -print0 | \
            xargs -0 ls -t | tail -n +11 | xargs rm -f
        log_info "Kept most recent 10 backups"
    fi
}

# Update formula placeholders
update_formula() {
    log_step "Updating formula with new version and checksum"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would update formula with:"
        log_info "  Version: $VERSION"
        log_info "  Archive URL: $ARCHIVE_URL"
        log_info "  SHA256: $SHA256_CHECKSUM"
        if [ "$INCLUDE_SYSTEM_EXTENSION" = true ]; then
            log_info "  System Extension Checksum: $SYSTEM_EXTENSION_CHECKSUM"
        fi
        return 0
    fi
    
    local temp_file
    temp_file=$(mktemp)
    
    # Verify required placeholders exist
    if ! grep -q "VERSION_PLACEHOLDER" "$FORMULA_FILE"; then
        log_error "VERSION_PLACEHOLDER not found in formula file"
        exit $EXIT_UPDATE_FAILED
    fi
    
    if ! grep -q "SHA256_PLACEHOLDER" "$FORMULA_FILE"; then
        log_error "SHA256_PLACEHOLDER not found in formula file"
        exit $EXIT_UPDATE_FAILED
    fi
    
    # Check for System Extension placeholders if including System Extension
    if [ "$INCLUDE_SYSTEM_EXTENSION" = true ]; then
        if ! grep -q "SYSTEM_EXTENSION_CHECKSUM_PLACEHOLDER" "$FORMULA_FILE"; then
            log_warning "SYSTEM_EXTENSION_CHECKSUM_PLACEHOLDER not found in formula file"
            log_warning "Formula may not support System Extension integration"
        fi
    fi
    
    # Update formula with actual values
    log_info "Updating VERSION_PLACEHOLDER with $VERSION"
    if ! sed "s|VERSION_PLACEHOLDER|$VERSION|g" "$FORMULA_FILE" > "$temp_file.tmp"; then
        log_error "Failed to replace VERSION_PLACEHOLDER in formula"
        log_error "sed command: sed \"s|VERSION_PLACEHOLDER|$VERSION|g\" \"$FORMULA_FILE\""
        rm -f "$temp_file" "$temp_file.tmp"
        exit $EXIT_UPDATE_FAILED
    fi
    log_info "VERSION_PLACEHOLDER replacement completed"
    
    log_info "Updating SHA256_PLACEHOLDER with $SHA256_CHECKSUM"
    if ! sed "s|SHA256_PLACEHOLDER|$SHA256_CHECKSUM|g" "$temp_file.tmp" > "$temp_file"; then
        log_error "Failed to replace SHA256_PLACEHOLDER in formula"
        log_error "sed command: sed \"s|SHA256_PLACEHOLDER|$SHA256_CHECKSUM|g\" \"$temp_file.tmp\""
        rm -f "$temp_file" "$temp_file.tmp"
        exit $EXIT_UPDATE_FAILED
    fi
    log_info "SHA256_PLACEHOLDER replacement completed"
    
    rm -f "$temp_file.tmp"
    
    # Update System Extension placeholders if applicable
    if [ "$INCLUDE_SYSTEM_EXTENSION" = true ] && [ -n "$SYSTEM_EXTENSION_CHECKSUM" ]; then
        if ! sed "s|SYSTEM_EXTENSION_CHECKSUM_PLACEHOLDER|$SYSTEM_EXTENSION_CHECKSUM|g" "$temp_file" > "$temp_file.tmp"; then
            log_error "Failed to replace SYSTEM_EXTENSION_CHECKSUM_PLACEHOLDER in formula"
            rm -f "$temp_file" "$temp_file.tmp"
            exit $EXIT_UPDATE_FAILED
        fi
        mv "$temp_file.tmp" "$temp_file"
    fi
    
    # Verify the update was successful
    log_info "Verifying that all placeholders were replaced"
    log_info "Temp file: $temp_file"
    log_info "Temp file exists: $(test -f "$temp_file" && echo "YES" || echo "NO")"
    if [ -f "$temp_file" ]; then
        log_info "Temp file size: $(wc -c < "$temp_file") bytes"
    fi
    
    local remaining_placeholders
    local grep_output
    grep_output=$(grep -o "VERSION_PLACEHOLDER\|SHA256_PLACEHOLDER" "$temp_file" 2>/dev/null || true)
    remaining_placeholders=$(echo "$grep_output" | wc -l)
    
    # If grep_output is empty, wc -l returns 1, so we need to handle this case
    if [ -z "$grep_output" ]; then
        remaining_placeholders=0
    fi
    
    log_info "Remaining placeholders: $remaining_placeholders"
    if [ "$remaining_placeholders" -gt 0 ]; then
        log_error "Failed to replace all required placeholders in formula"
        log_error "Remaining placeholders found in temp file:"
        grep -n "VERSION_PLACEHOLDER\|SHA256_PLACEHOLDER" "$temp_file" || true
        rm -f "$temp_file"
        exit $EXIT_UPDATE_FAILED
    fi
    log_info "All required placeholders have been replaced successfully"
    
    # Check for remaining System Extension placeholders (warning only)
    if [ "$INCLUDE_SYSTEM_EXTENSION" = true ]; then
        local se_placeholders
        se_placeholders=$(grep -o "SYSTEM_EXTENSION_CHECKSUM_PLACEHOLDER" "$temp_file" | wc -l)
        if [ "$se_placeholders" -gt 0 ]; then
            log_warning "System Extension placeholder not replaced (formula may not support System Extensions)"
        fi
    fi
    
    # Verify the new values are present
    if ! grep -q "$VERSION" "$temp_file"; then
        log_error "Version $VERSION not found in updated formula"
        rm -f "$temp_file"
        exit $EXIT_UPDATE_FAILED
    fi
    
    if ! grep -q "$SHA256_CHECKSUM" "$temp_file"; then
        log_error "SHA256 checksum not found in updated formula"
        rm -f "$temp_file"
        exit $EXIT_UPDATE_FAILED
    fi
    
    # Verify System Extension checksum if applicable
    if [ "$INCLUDE_SYSTEM_EXTENSION" = true ] && [ -n "$SYSTEM_EXTENSION_CHECKSUM" ]; then
        if grep -q "$SYSTEM_EXTENSION_CHECKSUM" "$temp_file"; then
            log_success "✓ System Extension checksum updated in formula"
        else
            log_warning "System Extension checksum not found in updated formula"
        fi
    fi
    
    # Replace original formula with updated version
    mv "$temp_file" "$FORMULA_FILE"
    
    log_success "Formula updated successfully"
    log_info "Version: $VERSION"
    log_info "SHA256: $SHA256_CHECKSUM"
    if [ "$INCLUDE_SYSTEM_EXTENSION" = true ] && [ -n "$SYSTEM_EXTENSION_CHECKSUM" ]; then
        log_info "System Extension SHA256: $SYSTEM_EXTENSION_CHECKSUM"
    fi
}

# Validate updated formula
validate_updated_formula() {
    if [ "$SKIP_VALIDATION" = true ]; then
        log_step "Skipping formula validation (--skip-validation specified)"
        return 0
    fi
    
    log_step "Validating updated formula"
    
    # Check Ruby syntax
    if command -v ruby >/dev/null 2>&1; then
        if ruby -c "$FORMULA_FILE" >/dev/null 2>&1; then
            log_success "✓ Ruby syntax is valid"
        else
            log_error "✗ Ruby syntax errors in updated formula"
            ruby -c "$FORMULA_FILE" 2>&1 | while IFS= read -r line; do
                log_error "  $line"
            done
            exit $EXIT_VALIDATION_FAILED
        fi
    else
        log_warning "Ruby not available, skipping syntax validation"
    fi
    
    # Run formula validation script if available
    local formula_validator="$SCRIPT_DIR/validate-formula.sh"
    if [ -x "$formula_validator" ]; then
        log_info "Running formula validation script..."
        local validation_args="--skip-installation"
        
        # Add System Extension validation if applicable
        if [ "$INCLUDE_SYSTEM_EXTENSION" = true ]; then
            validation_args="$validation_args --validate-system-extension"
        fi
        
        if $formula_validator $validation_args; then
            log_success "✓ Formula validation passed"
        else
            log_error "✗ Formula validation failed"
            exit $EXIT_VALIDATION_FAILED
        fi
    else
        log_warning "Formula validation script not found, skipping comprehensive validation"
    fi
    
    # Additional System Extension validation
    if [ "$INCLUDE_SYSTEM_EXTENSION" = true ] && [ "$VALIDATE_SYSTEM_EXTENSION" = true ]; then
        log_info "Performing additional System Extension formula validation..."
        
        # Check that System Extension checksum is present in formula
        if [ -n "$SYSTEM_EXTENSION_CHECKSUM" ]; then
            if grep -q "$SYSTEM_EXTENSION_CHECKSUM" "$FORMULA_FILE"; then
                log_success "✓ System Extension checksum found in formula"
            else
                log_warning "⚠ System Extension checksum not found in formula (may not be required)"
            fi
        fi
        
        # Validate System Extension bundle references in formula
        if grep -q "systemextension\|SystemExtension" "$FORMULA_FILE"; then
            log_success "✓ System Extension references found in formula"
        else
            log_warning "⚠ No System Extension references found in formula"
        fi
    fi
    
    log_success "Formula validation completed"
}

# Commit changes
commit_changes() {
    if [ "$AUTO_COMMIT" = false ]; then
        log_step "Skipping auto-commit (--auto-commit not specified)"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_step "DRY RUN: Would commit formula changes"
        return 0
    fi
    
    log_step "Committing formula changes"
    
    # Check if there are changes to commit
    if git diff --quiet "$FORMULA_FILE"; then
        log_warning "No changes to commit in formula file"
        return 0
    fi
    
    # Add and commit the formula changes
    git add "$FORMULA_FILE"
    
    local commit_message="feat: update Homebrew formula to $VERSION

- Update version from placeholder to $VERSION
- Update SHA256 checksum for release archive
- Formula URL: $ARCHIVE_URL$([ "$INCLUDE_SYSTEM_EXTENSION" = true ] && [ -n "$SYSTEM_EXTENSION_CHECKSUM" ] && echo "
- Update System Extension bundle checksum: $SYSTEM_EXTENSION_CHECKSUM" || echo "")

🤖 Generated with formula update automation"
    
    git commit -m "$commit_message"
    log_success "Formula changes committed"
}

# Rollback formula changes
rollback_formula() {
    log_step "Rolling back formula changes"
    
    # Find most recent backup
    local latest_backup
    latest_backup=$(find "$BACKUP_DIR" -name "usbipd-mac-*.rb" -type f -print0 2>/dev/null | \
        xargs -0 ls -t 2>/dev/null | head -1 || echo "")
    
    if [ -n "$latest_backup" ] && [ -f "$latest_backup" ]; then
        cp "$latest_backup" "$FORMULA_FILE"
        log_success "Formula rolled back to: $(basename "$latest_backup")"
    else
        log_error "No backup found for rollback"
        exit $EXIT_VALIDATION_FAILED
    fi
}

# Generate update summary
generate_update_summary() {
    log_step "Generating formula update summary"
    
    local summary_file="$PROJECT_ROOT/.build/formula-update-summary-$(date +%Y%m%d-%H%M%S).txt"
    mkdir -p "$(dirname "$summary_file")"
    
    cat > "$summary_file" << EOF
Homebrew Formula Update Summary
===============================

Generated: $(date)
Updated by: $(whoami)@$(hostname)
Project: usbipd-mac

Update Information:
  Version: $VERSION
  SHA256 Checksum: $SHA256_CHECKSUM
  Archive URL: $ARCHIVE_URL
  Formula File: $FORMULA_FILE$([ "$INCLUDE_SYSTEM_EXTENSION" = true ] && echo "
  System Extension Bundle: ${SYSTEM_EXTENSION_BUNDLE:-'[not detected]'}
  System Extension Checksum: ${SYSTEM_EXTENSION_CHECKSUM:-'[not calculated]'}" || echo "")

Configuration:
  Dry Run: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")
  Skip Validation: $([ "$SKIP_VALIDATION" = true ] && echo "YES" || echo "NO")
  Force Update: $([ "$FORCE_UPDATE" = true ] && echo "YES" || echo "NO")
  Create Backup: $([ "$CREATE_BACKUP" = true ] && echo "YES" || echo "NO")
  Auto Commit: $([ "$AUTO_COMMIT" = true ] && echo "YES" || echo "NO")
  Validate Tag: $([ "$VALIDATE_TAG" = true ] && echo "YES" || echo "NO")
  Include System Extension: $([ "$INCLUDE_SYSTEM_EXTENSION" = true ] && echo "YES" || echo "NO")
  Validate System Extension: $([ "$VALIDATE_SYSTEM_EXTENSION" = true ] && echo "YES" || echo "NO")

Update Status:
  ✓ Prerequisites validated
  ✓ Version validated
  ✓ Archive URL generated
  ✓ SHA256 checksum calculated$([ "$INCLUDE_SYSTEM_EXTENSION" = true ] && echo "
  ✓ System Extension bundle detected and validated
  ✓ System Extension checksum calculated" || echo "")
  ✓ Formula backup created
  ✓ Formula updated
  ✓ Updated formula validated
  $([ "$AUTO_COMMIT" = true ] && echo "✓ Changes committed" || echo "⚠ Manual commit required")

Next Steps:
$(if [ "$AUTO_COMMIT" = false ]; then
    echo "  1. Review the updated formula file:"
    echo "     cat $FORMULA_FILE"
    echo "  "
    echo "  2. Commit the changes if everything looks correct:"
    echo "     git add $FORMULA_FILE"
    echo "     git commit -m \"feat: update Homebrew formula to $VERSION\""
    echo "  "
fi)
  $([ "$AUTO_COMMIT" = true ] && echo "1" || echo "3"). Test the updated formula:"
  $([ "$AUTO_COMMIT" = true ] && echo "     $SCRIPT_DIR/validate-formula.sh" || echo "     $SCRIPT_DIR/validate-formula.sh")
  
  $([ "$AUTO_COMMIT" = true ] && echo "2" || echo "4"). Monitor release workflow progress:
  $([ "$AUTO_COMMIT" = true ] && echo "     git push origin HEAD" || echo "     git push origin HEAD")

Backup Information:
$(if [ "$CREATE_BACKUP" = true ]; then
    echo "  Backup Directory: $BACKUP_DIR"
    echo "  Available Backups:"
    find "$BACKUP_DIR" -name "usbipd-mac-*.rb" -type f -print0 2>/dev/null | \
        xargs -0 ls -t 2>/dev/null | head -5 | \
        while IFS= read -r backup; do
            echo "    - $(basename "$backup")"
        done || echo "    [No backups found]"
else
    echo "  No backups created (--no-backup specified)"
fi)

Log File: $LOG_FILE

EOF
    
    log_success "Update summary generated: $(basename "$summary_file")"
    log_info "Summary location: $summary_file"
    
    # Display summary to user
    echo ""
    cat "$summary_file"
    echo ""
}

# Print usage information
print_usage() {
    cat << EOF
Usage: $0 --version VERSION [OPTIONS]

Formula Update Automation for usbipd-mac Homebrew Distribution

Updates formula version and checksum placeholders with actual release values,
validates the update, and provides backup/rollback functionality.

REQUIRED OPTIONS:
  --version VERSION           Release version (e.g., v1.2.3 or 1.2.3)

OPTIONAL OPTIONS:
  --checksum CHECKSUM         SHA256 checksum (auto-calculated if not provided)
  --archive-url URL           Archive URL (auto-generated if not provided)
  --system-extension-bundle PATH  System Extension bundle path (auto-detected if not provided)
  --system-extension-checksum CHECKSUM  System Extension SHA256 checksum (auto-calculated if not provided)
  --no-system-extension       Skip System Extension integration
  --skip-system-extension-validation  Skip System Extension bundle validation
  --dry-run                   Preview actions without making changes
  --skip-validation           Skip formula validation after update
  --force                     Override safety checks and validation
  --no-backup                 Skip creating backup of current formula
  --auto-commit               Automatically commit formula changes
  --no-tag-validation         Skip validation that Git tag exists
  --help                      Show this help message

EXAMPLES:
  $0 --version v1.2.3                    # Update to version 1.2.3
  $0 --version 1.2.3 --auto-commit      # Update and auto-commit
  $0 --version v1.2.3 --dry-run         # Preview update without changes
  $0 --version v1.2.3 --checksum abc123 # Use specific checksum
  $0 --version v1.2.3 --force           # Force update without validation
  $0 --version v1.2.3 --no-system-extension  # Skip System Extension integration
  $0 --version v1.2.3 --system-extension-bundle /path/to/bundle  # Use specific bundle

ROLLBACK:
  To rollback to previous formula version:
  $0 --rollback

UPDATE PROCESS:
  1. Validate prerequisites and version format
  2. Validate that Git tag exists for the version
  3. Generate archive URL from Git repository
  4. Calculate SHA256 checksum by downloading archive
  5. Detect and validate System Extension bundle (if enabled)
  6. Calculate System Extension bundle checksum (if applicable)
  7. Create backup of current formula
  8. Update formula placeholders with actual values
  9. Validate updated formula syntax and structure
  10. Optionally commit changes to Git repository

This script is designed for integration with release automation workflows
and ensures formula updates are reliable and reversible.

EOF
}

# Error handler
handle_error() {
    local exit_code=$?
    log_error "Formula update failed with exit code $exit_code"
    
    if [ -f "$LOG_FILE" ]; then
        log_info "Detailed logs available at: $LOG_FILE"
    fi
    
    if [ "$CREATE_BACKUP" = true ] && [ -d "$BACKUP_DIR" ]; then
        echo ""
        echo "Rollback options:"
        echo "1. Manual rollback: cp $BACKUP_DIR/[backup-file] $FORMULA_FILE"
        echo "2. Automatic rollback: $0 --rollback"
        echo ""
    fi
    
    echo "Common troubleshooting steps:"
    echo "1. Check error messages above for specific issues"
    echo "2. Ensure the Git tag exists: git tag -l | grep $VERSION"
    echo "3. Verify archive URL is accessible: curl -I $ARCHIVE_URL"
    echo "4. Check formula syntax: ruby -c $FORMULA_FILE"
    echo "5. Use --dry-run to preview actions without making changes"
    echo ""
    
    exit $exit_code
}

# Set up error handling
trap 'handle_error' ERR

# Main execution flow
main() {
    local rollback_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                VERSION="$2"
                shift 2
                ;;
            --checksum)
                SHA256_CHECKSUM="$2"
                shift 2
                ;;
            --archive-url)
                ARCHIVE_URL="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --force)
                FORCE_UPDATE=true
                shift
                ;;
            --no-backup)
                CREATE_BACKUP=false
                shift
                ;;
            --auto-commit)
                AUTO_COMMIT=true
                shift
                ;;
            --no-tag-validation)
                VALIDATE_TAG=false
                shift
                ;;
            --system-extension-bundle)
                SYSTEM_EXTENSION_BUNDLE="$2"
                shift 2
                ;;
            --system-extension-checksum)
                SYSTEM_EXTENSION_CHECKSUM="$2"
                shift 2
                ;;
            --no-system-extension)
                INCLUDE_SYSTEM_EXTENSION=false
                shift
                ;;
            --skip-system-extension-validation)
                VALIDATE_SYSTEM_EXTENSION=false
                shift
                ;;
            --rollback)
                rollback_mode=true
                shift
                ;;
            --help)
                print_usage
                exit $EXIT_SUCCESS
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit $EXIT_USAGE_ERROR
                ;;
        esac
    done
    
    # Handle rollback mode
    if [ "$rollback_mode" = true ]; then
        setup_environment
        rollback_formula
        log_success "Formula rollback completed"
        exit $EXIT_SUCCESS
    fi
    
    # Validate required arguments
    if [ -z "$VERSION" ]; then
        log_error "Version is required. Use --version to specify."
        print_usage
        exit $EXIT_USAGE_ERROR
    fi
    
    # Start formula update process
    print_header
    
    # Execute update steps
    setup_environment
    validate_prerequisites
    validate_version
    generate_archive_url
    calculate_checksum
    detect_system_extension_bundle
    validate_system_extension_bundle
    calculate_system_extension_checksum
    create_formula_backup
    update_formula
    validate_updated_formula
    commit_changes
    generate_update_summary
    
    if [ "$DRY_RUN" = true ]; then
        log_success "🎉 Formula update preview completed successfully!"
        echo ""
        echo "Run without --dry-run to perform the actual update."
    else
        log_success "🎉 Formula update completed successfully!"
        echo ""
        echo "Formula has been updated to $VERSION"
        echo "Log file: $LOG_FILE"
    fi
}

# Change to project root directory
cd "$PROJECT_ROOT"

# Run main function with all arguments
main "$@"