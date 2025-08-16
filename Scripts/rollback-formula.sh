#!/bin/bash

# rollback-formula.sh
# Homebrew formula rollback and recovery utilities for usbipd-mac
# Provides automated rollback for failed formula updates and recovery of corrupted formula state
# Handles formula backup, restoration, validation checkpoints, and notification systems

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly FORMULA_DIR="${PROJECT_ROOT}/Formula"
readonly FORMULA_FILE="${FORMULA_DIR}/usbipd-mac.rb"
readonly BACKUP_DIR="${PROJECT_ROOT}/.build/formula-backup"
readonly LOG_DIR="${PROJECT_ROOT}/.build/logs"
readonly LOG_FILE="${LOG_DIR}/formula-rollback-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Configuration variables
ROLLBACK_VERSION=""
ROLLBACK_TYPE="failed-update"
DRY_RUN=false
SKIP_CONFIRMATION=false
CLEANUP_ONLY=false
PRESERVE_BACKUP=false
CREATE_CHECKPOINT=false
VALIDATE_FORMULA=true
SEND_NOTIFICATIONS=false
HOMEBREW_PREFIX=""
MAX_BACKUP_DAYS=30
VERBOSE=false

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ROLLBACK_FAILED=1
readonly EXIT_VALIDATION_FAILED=2
readonly EXIT_BACKUP_FAILED=3
readonly EXIT_USAGE_ERROR=4
readonly EXIT_PRECONDITION_FAILED=5
readonly EXIT_NOTIFICATION_FAILED=6

# Logging functions
log_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
}

log_step() {
    local message="$1"
    echo -e "${BOLD}${CYAN}==>${NC}${BOLD} $message${NC}" | tee -a "$LOG_FILE"
}

log_debug() {
    local message="$1"
    if [ "$VERBOSE" = true ]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
    fi
}

# Print script header
print_header() {
    cat << EOF
==================================================================
🔄 Homebrew Formula Rollback and Recovery Utilities for usbipd-mac
==================================================================
Version: ${ROLLBACK_VERSION:-'[auto-detect]'}
Type: $ROLLBACK_TYPE
Formula: $FORMULA_FILE
Dry Run: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")
Cleanup Only: $([ "$CLEANUP_ONLY" = true ] && echo "YES" || echo "NO")
Create Checkpoint: $([ "$CREATE_CHECKPOINT" = true ] && echo "YES" || echo "NO")
Validate Formula: $([ "$VALIDATE_FORMULA" = true ] && echo "YES" || echo "NO")
Send Notifications: $([ "$SEND_NOTIFICATIONS" = true ] && echo "YES" || echo "NO")
Preserve Backup: $([ "$PRESERVE_BACKUP" = true ] && echo "YES" || echo "NO")
Skip Confirmation: $([ "$SKIP_CONFIRMATION" = true ] && echo "YES" || echo "NO")
Working Dir: $PROJECT_ROOT
Homebrew Prefix: ${HOMEBREW_PREFIX:-'[auto-detect]'}
Log File: $LOG_FILE
==================================================================

EOF
}

# Print usage information
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [VERSION]

Homebrew formula rollback and recovery utilities for usbipd-mac.

ARGUMENTS:
    VERSION         Version to rollback to (e.g., v1.2.3) [optional, auto-detect if omitted]

OPTIONS:
    -t, --type TYPE         Rollback type: failed-update, corrupted-state, validation-failure, manual-restore
                           Default: failed-update
    -d, --dry-run          Show what would be done without making changes
    -c, --cleanup-only     Only perform cleanup, skip formula operations
    -p, --preserve-backup  Preserve backup files after rollback
    -f, --force            Skip confirmation prompts
    --create-checkpoint    Create validation checkpoint before rollback
    --skip-validation      Skip formula validation after rollback
    --enable-notifications Enable notification system for failures
    --homebrew-prefix PATH Homebrew installation prefix (auto-detected if not specified)
    --max-backup-days DAYS Maximum age for backup cleanup in days (default: 30)
    -v, --verbose          Enable verbose logging
    -h, --help             Show this help message

ROLLBACK TYPES:
    failed-update       Rollback failed formula update with version/checksum restoration
    corrupted-state     Restore formula from backup due to corruption
    validation-failure  Rollback due to failed formula validation
    manual-restore      Manual restoration to specific backup

EXAMPLES:
    $0                                    # Auto-detect and rollback latest failed update
    $0 v1.2.3                             # Rollback to specific version
    $0 --type corrupted-state             # Restore from backup due to corruption
    $0 --create-checkpoint --dry-run      # Create checkpoint and preview rollback
    $0 --cleanup-only --max-backup-days 7 # Clean up backups older than 7 days
    $0 --enable-notifications v1.2.3      # Rollback with notification system

ENVIRONMENT VARIABLES:
    FORMULA_ROLLBACK_HOMEBREW_PREFIX     Override Homebrew prefix detection
    FORMULA_ROLLBACK_BACKUP_RETENTION    Backup retention days (default: 14)
    FORMULA_ROLLBACK_NOTIFICATION_URL    Webhook URL for notifications
    FORMULA_ROLLBACK_VALIDATE_STRICT     Enable strict validation mode
    FORMULA_ROLLBACK_AUTO_CONFIRM        Auto-confirm rollback (use with caution)

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                ROLLBACK_TYPE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -c|--cleanup-only)
                CLEANUP_ONLY=true
                shift
                ;;
            -p|--preserve-backup)
                PRESERVE_BACKUP=true
                shift
                ;;
            -f|--force)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --create-checkpoint)
                CREATE_CHECKPOINT=true
                shift
                ;;
            --skip-validation)
                VALIDATE_FORMULA=false
                shift
                ;;
            --enable-notifications)
                SEND_NOTIFICATIONS=true
                shift
                ;;
            --homebrew-prefix)
                HOMEBREW_PREFIX="$2"
                shift 2
                ;;
            --max-backup-days)
                MAX_BACKUP_DAYS="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                print_usage
                exit $EXIT_SUCCESS
                ;;
            -*)
                log_error "Unknown option: $1"
                print_usage
                exit $EXIT_USAGE_ERROR
                ;;
            *)
                if [ -z "$ROLLBACK_VERSION" ]; then
                    ROLLBACK_VERSION="$1"
                else
                    log_error "Multiple versions specified: $ROLLBACK_VERSION and $1"
                    exit $EXIT_USAGE_ERROR
                fi
                shift
                ;;
        esac
    done

    # Apply environment variable overrides
    HOMEBREW_PREFIX="${FORMULA_ROLLBACK_HOMEBREW_PREFIX:-$HOMEBREW_PREFIX}"
    SEND_NOTIFICATIONS="${FORMULA_ROLLBACK_NOTIFICATION_URL:+true}"
    
    if [ "${FORMULA_ROLLBACK_AUTO_CONFIRM:-false}" = "true" ]; then
        SKIP_CONFIRMATION=true
    fi
    
    if [ "${FORMULA_ROLLBACK_VALIDATE_STRICT:-false}" = "true" ]; then
        VALIDATE_FORMULA=true
    fi

    # Validate rollback type
    case "$ROLLBACK_TYPE" in
        failed-update|corrupted-state|validation-failure|manual-restore)
            # Valid types
            ;;
        *)
            log_error "Invalid rollback type: $ROLLBACK_TYPE"
            print_usage
            exit $EXIT_USAGE_ERROR
            ;;
    esac

    # Validate max backup days
    if ! [[ "$MAX_BACKUP_DAYS" =~ ^[0-9]+$ ]] || [ "$MAX_BACKUP_DAYS" -le 0 ]; then
        log_error "Invalid max backup days: $MAX_BACKUP_DAYS (must be positive integer)"
        exit $EXIT_USAGE_ERROR
    fi
}

# Initialize environment
initialize_environment() {
    log_step "Initializing formula rollback environment"

    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Create backup directory if needed
    if [ "$CLEANUP_ONLY" = false ]; then
        mkdir -p "$BACKUP_DIR"
        log_debug "Created backup directory: $BACKUP_DIR"
    fi

    # Validate project structure
    if [ ! -f "$FORMULA_FILE" ]; then
        log_error "Formula file not found: $FORMULA_FILE"
        exit $EXIT_PRECONDITION_FAILED
    fi

    # Detect Homebrew prefix if not specified
    if [ -z "$HOMEBREW_PREFIX" ]; then
        HOMEBREW_PREFIX=$(detect_homebrew_prefix)
        log_debug "Auto-detected Homebrew prefix: $HOMEBREW_PREFIX"
    fi

    # Validate Homebrew installation
    if [ ! -x "$HOMEBREW_PREFIX/bin/brew" ]; then
        log_warning "Homebrew not found at: $HOMEBREW_PREFIX/bin/brew"
        log_info "Formula operations will be limited to local validation"
    else
        log_debug "Validated Homebrew installation: $HOMEBREW_PREFIX"
    fi

    # Change to project root
    cd "$PROJECT_ROOT"
    log_debug "Changed to project root: $PROJECT_ROOT"

    log_info "Environment initialized successfully"
}

# Detect Homebrew prefix
detect_homebrew_prefix() {
    # Try common Homebrew prefixes
    local common_prefixes=(
        "/opt/homebrew"      # Apple Silicon default
        "/usr/local"         # Intel Mac default
        "/home/linuxbrew/.linuxbrew"  # Linux
    )
    
    for prefix in "${common_prefixes[@]}"; do
        if [ -x "$prefix/bin/brew" ]; then
            echo "$prefix"
            return
        fi
    done
    
    # Try to detect from PATH
    local brew_path
    if command -v brew >/dev/null 2>&1; then
        brew_path=$(command -v brew)
        # Extract prefix (e.g., /opt/homebrew/bin/brew -> /opt/homebrew)
        echo "${brew_path%/bin/brew}"
        return
    fi
    
    # Default fallback
    echo "/opt/homebrew"
}

# Auto-detect version to rollback
detect_rollback_version() {
    if [ -n "$ROLLBACK_VERSION" ]; then
        log_debug "Using specified version: $ROLLBACK_VERSION"
        return
    fi

    log_step "Auto-detecting version for rollback"

    case "$ROLLBACK_TYPE" in
        failed-update|validation-failure)
            # Try to detect from Git history or backup files
            local latest_backup
            if [ -d "$BACKUP_DIR" ]; then
                latest_backup=$(find "$BACKUP_DIR" -name "formula-backup-*" -type d | sort -r | head -1)
                if [ -n "$latest_backup" ]; then
                    # Extract version from backup directory name
                    ROLLBACK_VERSION=$(basename "$latest_backup" | sed 's/formula-backup-\(.*\)-[0-9]*-[0-9]*/\1/')
                    log_info "Auto-detected rollback version from backup: $ROLLBACK_VERSION"
                else
                    log_warning "No backup directories found, using current state"
                    ROLLBACK_VERSION="current-$(date +%Y%m%d-%H%M%S)"
                fi
            else
                ROLLBACK_VERSION="unknown-$(date +%Y%m%d-%H%M%S)"
                log_info "Generated rollback identifier: $ROLLBACK_VERSION"
            fi
            ;;
        corrupted-state|manual-restore)
            # Use timestamp for state restoration
            ROLLBACK_VERSION="restore-$(date +%Y%m%d-%H%M%S)"
            log_info "Generated restoration identifier: $ROLLBACK_VERSION"
            ;;
    esac
}

# Create validation checkpoint
create_validation_checkpoint() {
    if [ "$CREATE_CHECKPOINT" = false ] && [ "$CLEANUP_ONLY" = true ]; then
        log_debug "Skipping checkpoint creation"
        return
    fi

    log_step "Creating validation checkpoint"

    local checkpoint_path="$BACKUP_DIR/checkpoint-$ROLLBACK_VERSION-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$checkpoint_path"

    # Backup current formula
    if [ -f "$FORMULA_FILE" ]; then
        cp "$FORMULA_FILE" "$checkpoint_path/usbipd-mac.rb"
        log_debug "Formula backed up to checkpoint"
    fi

    # Run pre-rollback validation
    local validation_result="$checkpoint_path/pre-rollback-validation.txt"
    
    if [ "$DRY_RUN" = false ]; then
        validate_formula_syntax "$FORMULA_FILE" > "$validation_result" 2>&1 || true
        
        # Add formula content analysis
        {
            echo "=== Formula Content Analysis ==="
            echo "File: $FORMULA_FILE"
            echo "Size: $(wc -c < "$FORMULA_FILE") bytes"
            echo "Lines: $(wc -l < "$FORMULA_FILE") lines"
            echo ""
            echo "=== Placeholder Analysis ==="
            grep -n "PLACEHOLDER" "$FORMULA_FILE" || echo "No placeholders found"
            echo ""
            echo "=== Dependencies ==="
            grep -n "depends_on" "$FORMULA_FILE" || echo "No dependencies found"
            echo ""
            echo "=== Service Configuration ==="
            grep -n -A 10 "service do" "$FORMULA_FILE" || echo "No service configuration found"
        } >> "$validation_result"
        
        log_debug "Pre-rollback validation saved to: $validation_result"
    else
        echo "[DRY RUN] Would perform pre-rollback validation" > "$validation_result"
    fi

    # Create checkpoint manifest
    cat > "$checkpoint_path/checkpoint-manifest.txt" << EOF
Formula Rollback Checkpoint Manifest
====================================
Created: $(date)
Script: $0
Rollback Version: $ROLLBACK_VERSION
Rollback Type: $ROLLBACK_TYPE
Project Root: $PROJECT_ROOT
Formula File: $FORMULA_FILE
Homebrew Prefix: $HOMEBREW_PREFIX

Pre-Rollback State:
- Formula exists: $([ -f "$FORMULA_FILE" ] && echo "yes" || echo "no")
- Formula size: $([ -f "$FORMULA_FILE" ] && wc -c < "$FORMULA_FILE" || echo "0") bytes
- Backup directory: $BACKUP_DIR
- Log file: $LOG_FILE

Validation Status:
- Syntax check: $([ "$DRY_RUN" = true ] && echo "skipped (dry run)" || echo "completed")
- Content analysis: completed
- Dependency check: completed
EOF

    log_success "Validation checkpoint created: $checkpoint_path"
}

# Create backup of current formula state
create_formula_backup() {
    if [ "$CLEANUP_ONLY" = true ]; then
        log_debug "Skipping backup creation (cleanup-only mode)"
        return
    fi

    log_step "Creating backup of current formula state"

    local backup_path="$BACKUP_DIR/formula-backup-$ROLLBACK_VERSION-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_path"

    # Backup current formula
    if [ -f "$FORMULA_FILE" ]; then
        cp "$FORMULA_FILE" "$backup_path/usbipd-mac.rb"
        log_debug "Formula backed up to: $backup_path/usbipd-mac.rb"
        
        # Create formula hash for integrity verification
        local formula_hash
        formula_hash=$(shasum -a 256 "$FORMULA_FILE" | cut -d' ' -f1)
        echo "$formula_hash" > "$backup_path/formula.sha256"
        log_debug "Formula hash: $formula_hash"
    else
        log_warning "Formula file not found for backup: $FORMULA_FILE"
        touch "$backup_path/formula-missing.txt"
    fi

    # Backup related files
    for file in "Scripts/update-formula.sh" "Scripts/validate-formula.sh"; do
        local file_path="$PROJECT_ROOT/$file"
        if [ -f "$file_path" ]; then
            local backup_file="$backup_path/$(basename "$file")"
            cp "$file_path" "$backup_file"
            log_debug "Backed up: $file"
        fi
    done

    # Create backup manifest
    cat > "$backup_path/backup-manifest.txt" << EOF
Formula Backup Manifest
=======================
Created: $(date)
Script: $0
Rollback Version: $ROLLBACK_VERSION
Rollback Type: $ROLLBACK_TYPE
Project Root: $PROJECT_ROOT
Formula File: $FORMULA_FILE

Backup Contents:
- Formula file: $([ -f "$backup_path/usbipd-mac.rb" ] && echo "yes" || echo "no")
- Formula hash: $([ -f "$backup_path/formula.sha256" ] && cat "$backup_path/formula.sha256" || echo "unavailable")
- Update script: $([ -f "$backup_path/update-formula.sh" ] && echo "yes" || echo "no")
- Validation script: $([ -f "$backup_path/validate-formula.sh" ] && echo "yes" || echo "no")

Rollback Information:
- Rollback type: $ROLLBACK_TYPE
- Target version: $ROLLBACK_VERSION
- Backup path: $backup_path
- Log file: $LOG_FILE
EOF

    log_success "Formula backup created: $backup_path"
}

# Rollback formula operations
rollback_formula_operations() {
    if [ "$CLEANUP_ONLY" = true ]; then
        log_debug "Skipping formula operations (cleanup-only mode)"
        return
    fi

    log_step "Rolling back formula operations"

    case "$ROLLBACK_TYPE" in
        failed-update)
            rollback_failed_update
            ;;
        corrupted-state)
            restore_from_backup
            ;;
        validation-failure)
            rollback_validation_failure
            ;;
        manual-restore)
            perform_manual_restore
            ;;
    esac
}

# Rollback failed formula update
rollback_failed_update() {
    log_info "Rolling back failed formula update"

    # Try to restore from the most recent backup
    local latest_backup
    latest_backup=$(find "$BACKUP_DIR" -name "formula-backup-*" -type d | sort -r | head -1)

    if [ -n "$latest_backup" ] && [ -d "$latest_backup" ]; then
        log_info "Found backup to restore from: $(basename "$latest_backup")"
        
        local backup_formula="$latest_backup/usbipd-mac.rb"
        if [ -f "$backup_formula" ]; then
            if [ "$DRY_RUN" = false ]; then
                # Verify backup integrity
                if verify_backup_integrity "$latest_backup"; then
                    # Restore formula from backup
                    cp "$backup_formula" "$FORMULA_FILE"
                    log_success "Formula restored from backup"
                    
                    # Validate restored formula
                    if [ "$VALIDATE_FORMULA" = true ]; then
                        validate_restored_formula
                    fi
                else
                    log_error "Backup integrity check failed"
                    exit $EXIT_BACKUP_FAILED
                fi
            else
                log_info "[DRY RUN] Would restore formula from: $backup_formula"
            fi
        else
            log_error "Backup formula not found: $backup_formula"
            exit $EXIT_BACKUP_FAILED
        fi
    else
        log_warning "No backup found for rollback, attempting to restore placeholders"
        restore_formula_placeholders
    fi
}

# Restore formula placeholders
restore_formula_placeholders() {
    log_info "Restoring formula placeholders for template state"

    if [ "$DRY_RUN" = false ]; then
        # Read current formula
        local formula_content
        formula_content=$(cat "$FORMULA_FILE")
        
        # Restore version and checksum placeholders
        formula_content=$(echo "$formula_content" | sed 's/version ".*"/version "VERSION_PLACEHOLDER"/')
        formula_content=$(echo "$formula_content" | sed 's/sha256 ".*"/sha256 "SHA256_PLACEHOLDER"/')
        formula_content=$(echo "$formula_content" | sed 's|url ".*"|url "https://github.com/beriberikix/usbipd-mac/archive/VERSION_PLACEHOLDER.tar.gz"|')
        
        # Write back to formula file
        echo "$formula_content" > "$FORMULA_FILE"
        
        log_success "Formula placeholders restored"
    else
        log_info "[DRY RUN] Would restore formula placeholders"
    fi
}

# Restore from backup
restore_from_backup() {
    log_info "Restoring formula from backup due to corrupted state"

    # Find the most recent valid backup
    local backups
    readarray -t backups < <(find "$BACKUP_DIR" -name "formula-backup-*" -type d | sort -r)

    local restored=false
    for backup in "${backups[@]}"; do
        log_info "Attempting restore from: $(basename "$backup")"
        
        if verify_backup_integrity "$backup"; then
            local backup_formula="$backup/usbipd-mac.rb"
            
            if [ "$DRY_RUN" = false ]; then
                cp "$backup_formula" "$FORMULA_FILE"
                log_success "Formula restored from backup: $(basename "$backup")"
                restored=true
                break
            else
                log_info "[DRY RUN] Would restore from: $backup_formula"
                restored=true
                break
            fi
        else
            log_warning "Backup integrity check failed for: $(basename "$backup")"
        fi
    done

    if [ "$restored" = false ]; then
        log_error "No valid backup found for restoration"
        exit $EXIT_BACKUP_FAILED
    fi
}

# Rollback validation failure
rollback_validation_failure() {
    log_info "Rolling back due to validation failure"

    # This is similar to failed update, but with additional validation steps
    rollback_failed_update
    
    # Run comprehensive validation
    if [ "$DRY_RUN" = false ] && [ "$VALIDATE_FORMULA" = true ]; then
        log_info "Running comprehensive validation after rollback"
        if ! validate_formula_comprehensive; then
            log_error "Validation still failing after rollback"
            exit $EXIT_VALIDATION_FAILED
        fi
    fi
}

# Perform manual restore
perform_manual_restore() {
    log_info "Performing manual formula restore"

    # List available backups for user selection
    local backups
    readarray -t backups < <(find "$BACKUP_DIR" -name "formula-backup-*" -type d | sort -r)

    if [ ${#backups[@]} -eq 0 ]; then
        log_error "No backups available for manual restore"
        exit $EXIT_BACKUP_FAILED
    fi

    log_info "Available backups:"
    local i=1
    for backup in "${backups[@]}"; do
        local backup_name=$(basename "$backup")
        local backup_date=$(stat -f %Sm -t "%Y-%m-%d %H:%M:%S" "$backup" 2>/dev/null || stat -c %y "$backup" 2>/dev/null || echo "unknown")
        echo "  $i) $backup_name ($backup_date)"
        ((i++))
    done

    if [ "$SKIP_CONFIRMATION" = false ] && [ "$DRY_RUN" = false ]; then
        echo ""
        read -p "Select backup number to restore (1-${#backups[@]}): " -r backup_choice
        
        if ! [[ "$backup_choice" =~ ^[0-9]+$ ]] || [ "$backup_choice" -lt 1 ] || [ "$backup_choice" -gt ${#backups[@]} ]; then
            log_error "Invalid backup selection: $backup_choice"
            exit $EXIT_USAGE_ERROR
        fi
        
        local selected_backup="${backups[$((backup_choice-1))]}"
        log_info "Selected backup: $(basename "$selected_backup")"
    else
        # Auto-select most recent backup for non-interactive mode
        local selected_backup="${backups[0]}"
        log_info "Auto-selected most recent backup: $(basename "$selected_backup")"
    fi

    # Restore from selected backup
    if verify_backup_integrity "$selected_backup"; then
        local backup_formula="$selected_backup/usbipd-mac.rb"
        
        if [ "$DRY_RUN" = false ]; then
            cp "$backup_formula" "$FORMULA_FILE"
            log_success "Formula manually restored from: $(basename "$selected_backup")"
        else
            log_info "[DRY RUN] Would restore from: $backup_formula"
        fi
    else
        log_error "Selected backup failed integrity check"
        exit $EXIT_BACKUP_FAILED
    fi
}

# Verify backup integrity
verify_backup_integrity() {
    local backup_path="$1"
    local backup_formula="$backup_path/usbipd-mac.rb"
    local backup_hash_file="$backup_path/formula.sha256"

    log_debug "Verifying backup integrity: $(basename "$backup_path")"

    # Check if backup formula exists
    if [ ! -f "$backup_formula" ]; then
        log_debug "Backup formula file missing: $backup_formula"
        return 1
    fi

    # Check if hash file exists and verify
    if [ -f "$backup_hash_file" ]; then
        local expected_hash
        expected_hash=$(cat "$backup_hash_file")
        local actual_hash
        actual_hash=$(shasum -a 256 "$backup_formula" | cut -d' ' -f1)
        
        if [ "$expected_hash" = "$actual_hash" ]; then
            log_debug "✓ Backup integrity verified"
            return 0
        else
            log_debug "✗ Backup hash mismatch: expected $expected_hash, got $actual_hash"
            return 1
        fi
    else
        log_debug "⚠ No hash file found, performing basic validation"
        # Basic validation - check if file is not empty and has Ruby syntax
        if [ -s "$backup_formula" ] && grep -q "class.*Formula" "$backup_formula"; then
            log_debug "✓ Basic backup validation passed"
            return 0
        else
            log_debug "✗ Basic backup validation failed"
            return 1
        fi
    fi
}

# Validate formula syntax
validate_formula_syntax() {
    local formula_file="$1"
    
    log_debug "Validating formula syntax: $formula_file"

    # Basic Ruby syntax check
    if ! ruby -c "$formula_file" >/dev/null 2>&1; then
        log_debug "✗ Ruby syntax validation failed"
        return 1
    fi

    # Homebrew formula structure check
    if ! grep -q "class.*Formula" "$formula_file"; then
        log_debug "✗ Formula class structure missing"
        return 1
    fi

    if ! grep -q "def install" "$formula_file"; then
        log_debug "✗ Install method missing"
        return 1
    fi

    log_debug "✓ Formula syntax validation passed"
    return 0
}

# Validate restored formula
validate_restored_formula() {
    log_info "Validating restored formula"

    if validate_formula_syntax "$FORMULA_FILE"; then
        log_success "Restored formula syntax validation passed"
        
        # Additional validation with brew audit if available
        if [ -x "$HOMEBREW_PREFIX/bin/brew" ]; then
            log_debug "Running brew audit on restored formula"
            if "$HOMEBREW_PREFIX/bin/brew" audit --strict "$FORMULA_FILE" >/dev/null 2>&1; then
                log_success "Brew audit validation passed"
            else
                log_warning "Brew audit validation failed (may be due to placeholders)"
            fi
        fi
    else
        log_error "Restored formula failed syntax validation"
        exit $EXIT_VALIDATION_FAILED
    fi
}

# Comprehensive formula validation
validate_formula_comprehensive() {
    log_info "Running comprehensive formula validation"

    # Syntax validation
    if ! validate_formula_syntax "$FORMULA_FILE"; then
        log_error "Comprehensive validation failed: syntax errors"
        return 1
    fi

    # Content validation
    local formula_content
    formula_content=$(cat "$FORMULA_FILE")

    # Check required fields
    local required_fields=("desc" "homepage" "url" "version" "sha256")
    for field in "${required_fields[@]}"; do
        if ! echo "$formula_content" | grep -q "$field"; then
            log_error "Comprehensive validation failed: missing field $field"
            return 1
        fi
    done

    # Check dependencies
    if ! echo "$formula_content" | grep -q "depends_on :macos"; then
        log_error "Comprehensive validation failed: missing macOS dependency"
        return 1
    fi

    # Check service configuration
    if ! echo "$formula_content" | grep -q "service do"; then
        log_warning "Service configuration missing (acceptable for some formula versions)"
    fi

    log_success "Comprehensive formula validation passed"
    return 0
}

# Clean up old backup files
cleanup_backup_files() {
    if [ "$PRESERVE_BACKUP" = true ]; then
        log_debug "Preserving backup files (--preserve-backup specified)"
        return
    fi

    log_step "Cleaning up old backup files"

    if [ -d "$BACKUP_DIR" ]; then
        # Find backup directories older than MAX_BACKUP_DAYS
        local backup_retention="${FORMULA_ROLLBACK_BACKUP_RETENTION:-14}"
        
        if [ "$DRY_RUN" = false ]; then
            find "$BACKUP_DIR" -type d -name "formula-backup-*" -mtime +"$backup_retention" -exec rm -rf {} + 2>/dev/null || true
            find "$BACKUP_DIR" -type d -name "checkpoint-*" -mtime +"$backup_retention" -exec rm -rf {} + 2>/dev/null || true
            log_success "Cleaned up old backup files (older than $backup_retention days)"
        else
            local old_backups
            old_backups=$(find "$BACKUP_DIR" -type d \( -name "formula-backup-*" -o -name "checkpoint-*" \) -mtime +"$backup_retention" 2>/dev/null | wc -l)
            log_info "[DRY RUN] Would clean up $old_backups old backup directories"
        fi
    fi
}

# Send notification about rollback
send_notification() {
    if [ "$SEND_NOTIFICATIONS" = false ]; then
        log_debug "Notifications disabled"
        return
    fi

    local notification_url="${FORMULA_ROLLBACK_NOTIFICATION_URL:-}"
    if [ -z "$notification_url" ]; then
        log_debug "No notification URL configured"
        return
    fi

    log_step "Sending rollback notification"

    local status="$1"
    local message="$2"

    local payload
    payload=$(cat << EOF
{
    "type": "formula-rollback",
    "status": "$status",
    "message": "$message",
    "version": "$ROLLBACK_VERSION",
    "rollback_type": "$ROLLBACK_TYPE",
    "project": "usbipd-mac",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "dry_run": $DRY_RUN
}
EOF
)

    if [ "$DRY_RUN" = false ]; then
        if curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$notification_url" >/dev/null 2>&1; then
            log_success "Notification sent successfully"
        else
            log_warning "Failed to send notification (exit code: $?)"
        fi
    else
        log_info "[DRY RUN] Would send notification: $message"
    fi
}

# Verify rollback completion
verify_rollback() {
    log_step "Verifying rollback completion"

    local verification_failed=false

    # Verify formula file exists and is valid
    if [ ! -f "$FORMULA_FILE" ]; then
        log_error "Formula file missing after rollback: $FORMULA_FILE"
        verification_failed=true
    elif [ "$VALIDATE_FORMULA" = true ]; then
        if validate_formula_syntax "$FORMULA_FILE"; then
            log_debug "✓ Formula syntax validation passed"
        else
            log_error "Formula syntax validation failed after rollback"
            verification_failed=true
        fi
    fi

    # Check formula content
    if [ -f "$FORMULA_FILE" ]; then
        local formula_size
        formula_size=$(wc -c < "$FORMULA_FILE")
        if [ "$formula_size" -lt 100 ]; then
            log_warning "Formula file seems unusually small: $formula_size bytes"
        else
            log_debug "✓ Formula file size acceptable: $formula_size bytes"
        fi
    fi

    if [ "$verification_failed" = true ]; then
        log_error "Rollback verification failed"
        send_notification "failed" "Formula rollback verification failed for version $ROLLBACK_VERSION"
        return $EXIT_ROLLBACK_FAILED
    else
        log_success "Rollback verification completed successfully"
        send_notification "success" "Formula rollback completed successfully for version $ROLLBACK_VERSION"
        return $EXIT_SUCCESS
    fi
}

# Generate rollback report
generate_rollback_report() {
    log_step "Generating rollback report"

    local report_file="$LOG_DIR/formula-rollback-report-$(date +%Y%m%d-%H%M%S).txt"

    cat > "$report_file" << EOF
Formula Rollback Report for usbipd-mac
======================================
Date: $(date)
Script: $0
Version: $ROLLBACK_VERSION
Type: $ROLLBACK_TYPE
Dry Run: $DRY_RUN
Project Root: $PROJECT_ROOT
Formula File: $FORMULA_FILE
Homebrew Prefix: $HOMEBREW_PREFIX

Formula Information:
- Formula exists: $([ -f "$FORMULA_FILE" ] && echo "yes" || echo "no")
- Formula size: $([ -f "$FORMULA_FILE" ] && wc -c < "$FORMULA_FILE" || echo "0") bytes
- Syntax valid: $([ -f "$FORMULA_FILE" ] && validate_formula_syntax "$FORMULA_FILE" >/dev/null 2>&1 && echo "yes" || echo "no")

Backup Information:
- Backup directory: $BACKUP_DIR
- Number of backups: $([ -d "$BACKUP_DIR" ] && find "$BACKUP_DIR" -name "formula-backup-*" -type d | wc -l || echo "0")
- Backup retention: ${FORMULA_ROLLBACK_BACKUP_RETENTION:-14} days

Rollback Summary:
- Cleanup performed: $([ "$CLEANUP_ONLY" = true ] && echo "yes (cleanup-only)" || echo "no")
- Validation enabled: $VALIDATE_FORMULA
- Notifications sent: $SEND_NOTIFICATIONS
- Backup preserved: $PRESERVE_BACKUP

Actions Performed:
EOF

    # Add specific actions based on rollback type
    case "$ROLLBACK_TYPE" in
        failed-update)
            cat >> "$report_file" << EOF
- Restored formula from backup or reset to placeholders
- Validated restored formula syntax
- Cleaned up old backup files
EOF
            ;;
        corrupted-state)
            cat >> "$report_file" << EOF
- Restored formula from most recent valid backup
- Verified backup integrity before restoration
- Cleaned up old backup files
EOF
            ;;
        validation-failure)
            cat >> "$report_file" << EOF
- Restored formula from backup
- Performed comprehensive validation after rollback
- Cleaned up old backup files
EOF
            ;;
        manual-restore)
            cat >> "$report_file" << EOF
- Manually selected and restored specific backup
- Verified backup integrity before restoration
- Cleaned up old backup files
EOF
            ;;
    esac

    cat >> "$report_file" << EOF

Log File: $LOG_FILE
Report Generated: $(date)
EOF

    log_success "Rollback report generated: $report_file"
}

# Confirm rollback action
confirm_rollback() {
    if [ "$SKIP_CONFIRMATION" = true ]; then
        log_debug "Skipping confirmation (--force specified)"
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        log_debug "Skipping confirmation (dry run mode)"
        return
    fi

    log_step "Rollback Confirmation"

    echo ""
    echo -e "${YELLOW}${BOLD}WARNING: This will perform the following actions:${NC}"
    echo ""

    case "$ROLLBACK_TYPE" in
        failed-update)
            echo "  • Restore formula from backup or reset to template state"
            echo "  • Validate restored formula syntax"
            echo "  • Clean up old backup files"
            ;;
        corrupted-state)
            echo "  • Restore formula from most recent valid backup"
            echo "  • Verify backup integrity before restoration"
            echo "  • Clean up old backup files"
            ;;
        validation-failure)
            echo "  • Restore formula from backup"
            echo "  • Run comprehensive validation after rollback"
            echo "  • Clean up old backup files"
            ;;
        manual-restore)
            echo "  • Present backup selection for manual restoration"
            echo "  • Restore from selected backup"
            echo "  • Clean up old backup files"
            ;;
    esac

    if [ "$CLEANUP_ONLY" = false ]; then
        echo "  • Create backup of current state before rollback"
    fi
    if [ "$CREATE_CHECKPOINT" = true ]; then
        echo "  • Create validation checkpoint"
    fi
    if [ "$SEND_NOTIFICATIONS" = true ]; then
        echo "  • Send rollback notifications"
    fi
    echo "  • Clean up files older than $MAX_BACKUP_DAYS days"
    echo ""

    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Rollback cancelled by user"
        exit $EXIT_SUCCESS
    fi

    log_info "Rollback confirmed by user"
}

# Main execution function
main() {
    # Initialize logging
    mkdir -p "$LOG_DIR"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Print header
    print_header
    
    # Initialize environment
    initialize_environment
    
    # Auto-detect version if needed
    detect_rollback_version
    
    # Confirm rollback action
    confirm_rollback
    
    # Create validation checkpoint
    create_validation_checkpoint
    
    # Create backup
    create_formula_backup
    
    # Perform rollback operations
    rollback_formula_operations
    
    # Clean up backup files
    cleanup_backup_files
    
    # Verify rollback
    if ! verify_rollback; then
        log_error "Rollback verification failed"
        exit $EXIT_ROLLBACK_FAILED
    fi
    
    # Generate report
    generate_rollback_report
    
    log_success "Formula rollback completed successfully"
    
    if [ "$DRY_RUN" = true ]; then
        echo ""
        echo -e "${BOLD}${GREEN}This was a dry run. No changes were made.${NC}"
        echo -e "${BOLD}Run without --dry-run to perform the actual rollback.${NC}"
    fi
    
    echo ""
    log_success "🎉 Formula rollback operation completed for version: $ROLLBACK_VERSION"
}

# Error handling
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Execute main function with all arguments
main "$@"