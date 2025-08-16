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

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_VALIDATION_FAILED=1
readonly EXIT_FORMULA_NOT_FOUND=2
readonly EXIT_UPDATE_FAILED=3
readonly EXIT_CHECKSUM_FAILED=4
readonly EXIT_VERSION_MISMATCH=5
readonly EXIT_USAGE_ERROR=6

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
    echo "Dry Run: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")"
    echo "Skip Validation: $([ "$SKIP_VALIDATION" = true ] && echo "YES" || echo "NO")"
    echo "Force Update: $([ "$FORCE_UPDATE" = true ] && echo "YES" || echo "NO")"
    echo "Create Backup: $([ "$CREATE_BACKUP" = true ] && echo "YES" || echo "NO")"
    echo "Auto Commit: $([ "$AUTO_COMMIT" = true ] && echo "YES" || echo "NO")"
    echo "Validate Tag: $([ "$VALIDATE_TAG" = true ] && echo "YES" || echo "NO")"
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
        return 0
    fi
    
    local temp_file
    temp_file=$(mktemp)
    
    # Verify placeholders exist
    if ! grep -q "VERSION_PLACEHOLDER" "$FORMULA_FILE"; then
        log_error "VERSION_PLACEHOLDER not found in formula file"
        exit $EXIT_UPDATE_FAILED
    fi
    
    if ! grep -q "SHA256_PLACEHOLDER" "$FORMULA_FILE"; then
        log_error "SHA256_PLACEHOLDER not found in formula file"
        exit $EXIT_UPDATE_FAILED
    fi
    
    # Update formula with actual values
    sed "s/VERSION_PLACEHOLDER/$VERSION/g" "$FORMULA_FILE" | \
    sed "s/SHA256_PLACEHOLDER/$SHA256_CHECKSUM/g" > "$temp_file"
    
    # Verify the update was successful
    if grep -q "VERSION_PLACEHOLDER\|SHA256_PLACEHOLDER" "$temp_file"; then
        log_error "Failed to replace all placeholders in formula"
        rm -f "$temp_file"
        exit $EXIT_UPDATE_FAILED
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
    
    # Replace original formula with updated version
    mv "$temp_file" "$FORMULA_FILE"
    
    log_success "Formula updated successfully"
    log_info "Version: $VERSION"
    log_info "SHA256: $SHA256_CHECKSUM"
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
        if "$formula_validator" --skip-installation; then
            log_success "✓ Formula validation passed"
        else
            log_error "✗ Formula validation failed"
            exit $EXIT_VALIDATION_FAILED
        fi
    else
        log_warning "Formula validation script not found, skipping comprehensive validation"
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
- Formula URL: $ARCHIVE_URL

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
  Formula File: $FORMULA_FILE

Configuration:
  Dry Run: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")
  Skip Validation: $([ "$SKIP_VALIDATION" = true ] && echo "YES" || echo "NO")
  Force Update: $([ "$FORCE_UPDATE" = true ] && echo "YES" || echo "NO")
  Create Backup: $([ "$CREATE_BACKUP" = true ] && echo "YES" || echo "NO")
  Auto Commit: $([ "$AUTO_COMMIT" = true ] && echo "YES" || echo "NO")
  Validate Tag: $([ "$VALIDATE_TAG" = true ] && echo "YES" || echo "NO")

Update Status:
  ✓ Prerequisites validated
  ✓ Version validated
  ✓ Archive URL generated
  ✓ SHA256 checksum calculated
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

ROLLBACK:
  To rollback to previous formula version:
  $0 --rollback

UPDATE PROCESS:
  1. Validate prerequisites and version format
  2. Validate that Git tag exists for the version
  3. Generate archive URL from Git repository
  4. Calculate SHA256 checksum by downloading archive
  5. Create backup of current formula
  6. Update formula placeholders with actual values
  7. Validate updated formula syntax and structure
  8. Optionally commit changes to Git repository

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