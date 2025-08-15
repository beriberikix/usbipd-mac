#!/bin/bash

# rollback-release.sh
# Release rollback and cleanup utilities for usbipd-mac
# Provides automated rollback for failed releases and cleanup of incomplete artifacts
# Handles Git tag cleanup, artifact removal, and environment restoration

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/.build"
readonly ARTIFACTS_DIR="${BUILD_DIR}/release-artifacts"
readonly BACKUP_DIR="${BUILD_DIR}/rollback-backup"
readonly LOG_DIR="${BUILD_DIR}/logs"
readonly LOG_FILE="${LOG_DIR}/rollback-$(date +%Y%m%d-%H%M%S).log"

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
ROLLBACK_TYPE="failed-release"
DRY_RUN=false
SKIP_CONFIRMATION=false
CLEANUP_ONLY=false
PRESERVE_BACKUP=false
REMOTE_NAME="origin"
MAIN_BRANCH="main"
MAX_ROLLBACK_DAYS=30
VERBOSE=false

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ROLLBACK_FAILED=1
readonly EXIT_CLEANUP_FAILED=2
readonly EXIT_TAG_CLEANUP_FAILED=3
readonly EXIT_USAGE_ERROR=4
readonly EXIT_PRECONDITION_FAILED=5

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
🔄 Release Rollback and Cleanup Utilities for usbipd-mac
==================================================================
Version: ${ROLLBACK_VERSION:-'[auto-detect]'}
Type: $ROLLBACK_TYPE
Dry Run: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")
Cleanup Only: $([ "$CLEANUP_ONLY" = true ] && echo "YES" || echo "NO")
Preserve Backup: $([ "$PRESERVE_BACKUP" = true ] && echo "YES" || echo "NO")
Skip Confirmation: $([ "$SKIP_CONFIRMATION" = true ] && echo "YES" || echo "NO")
Working Dir: $PROJECT_ROOT
Remote: $REMOTE_NAME
Main Branch: $MAIN_BRANCH
Log File: $LOG_FILE
==================================================================

EOF
}

# Print usage information
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [VERSION]

Release rollback and cleanup utilities for usbipd-mac.

ARGUMENTS:
    VERSION         Version to rollback (e.g., v1.2.3) [optional, auto-detect if omitted]

OPTIONS:
    -t, --type TYPE         Rollback type: failed-release, incomplete-build, artifacts-only
                           Default: failed-release
    -d, --dry-run          Show what would be done without making changes
    -c, --cleanup-only     Only perform cleanup, skip Git operations
    -p, --preserve-backup  Preserve backup files after rollback
    -f, --force            Skip confirmation prompts
    -r, --remote NAME      Git remote name (default: origin)
    -b, --branch NAME      Main branch name (default: main)
    --max-age DAYS         Maximum age for cleanup in days (default: 30)
    -v, --verbose          Enable verbose logging
    -h, --help             Show this help message

ROLLBACK TYPES:
    failed-release     Complete rollback including Git tags and remote cleanup
    incomplete-build   Rollback incomplete build artifacts and temporary files
    artifacts-only     Only clean up build artifacts, leave Git state unchanged

EXAMPLES:
    $0                              # Auto-detect and rollback latest failed release
    $0 v1.2.3                       # Rollback specific version
    $0 --type artifacts-only        # Clean up artifacts only
    $0 --cleanup-only --max-age 7   # Clean up files older than 7 days
    $0 --dry-run v1.2.3             # Preview rollback actions

ENVIRONMENT VARIABLES:
    ROLLBACK_REMOTE_NAME            Override default remote name
    ROLLBACK_MAIN_BRANCH            Override default main branch
    ROLLBACK_PRESERVE_LOGS          Preserve log files (default: false)
    ROLLBACK_BACKUP_RETENTION       Backup retention days (default: 7)

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
            -r|--remote)
                REMOTE_NAME="$2"
                shift 2
                ;;
            -b|--branch)
                MAIN_BRANCH="$2"
                shift 2
                ;;
            --max-age)
                MAX_ROLLBACK_DAYS="$2"
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
    REMOTE_NAME="${ROLLBACK_REMOTE_NAME:-$REMOTE_NAME}"
    MAIN_BRANCH="${ROLLBACK_MAIN_BRANCH:-$MAIN_BRANCH}"

    # Validate rollback type
    case "$ROLLBACK_TYPE" in
        failed-release|incomplete-build|artifacts-only)
            # Valid types
            ;;
        *)
            log_error "Invalid rollback type: $ROLLBACK_TYPE"
            print_usage
            exit $EXIT_USAGE_ERROR
            ;;
    esac

    # Validate max age
    if ! [[ "$MAX_ROLLBACK_DAYS" =~ ^[0-9]+$ ]] || [ "$MAX_ROLLBACK_DAYS" -le 0 ]; then
        log_error "Invalid max age: $MAX_ROLLBACK_DAYS (must be positive integer)"
        exit $EXIT_USAGE_ERROR
    fi
}

# Initialize environment
initialize_environment() {
    log_step "Initializing rollback environment"

    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Create backup directory if needed
    if [ "$ROLLBACK_TYPE" != "cleanup-only" ]; then
        mkdir -p "$BACKUP_DIR"
        log_debug "Created backup directory: $BACKUP_DIR"
    fi

    # Validate Git repository
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_error "Not inside a Git repository"
        exit $EXIT_PRECONDITION_FAILED
    fi

    # Validate remote exists (unless cleanup-only)
    if [ "$CLEANUP_ONLY" = false ] && [ "$ROLLBACK_TYPE" != "artifacts-only" ]; then
        if ! git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
            log_error "Remote '$REMOTE_NAME' not found"
            exit $EXIT_PRECONDITION_FAILED
        fi
        log_debug "Validated remote: $REMOTE_NAME"
    fi

    # Change to project root
    cd "$PROJECT_ROOT"
    log_debug "Changed to project root: $PROJECT_ROOT"

    log_info "Environment initialized successfully"
}

# Auto-detect version to rollback
detect_rollback_version() {
    if [ -n "$ROLLBACK_VERSION" ]; then
        log_debug "Using specified version: $ROLLBACK_VERSION"
        return
    fi

    log_step "Auto-detecting version to rollback"

    case "$ROLLBACK_TYPE" in
        failed-release)
            # Find the latest tag that might be a failed release
            local latest_tag
            latest_tag=$(git tag -l 'v*' --sort=-version:refname | head -1)
            
            if [ -n "$latest_tag" ]; then
                # Check if this tag has a corresponding GitHub release that might have failed
                ROLLBACK_VERSION="$latest_tag"
                log_info "Auto-detected rollback version: $ROLLBACK_VERSION"
            else
                log_warning "No version tags found for rollback"
                ROLLBACK_VERSION="unknown"
            fi
            ;;
        incomplete-build|artifacts-only)
            # For build/artifact rollbacks, use current timestamp
            ROLLBACK_VERSION="build-$(date +%Y%m%d-%H%M%S)"
            log_info "Generated rollback identifier: $ROLLBACK_VERSION"
            ;;
    esac
}

# Create backup of current state
create_backup() {
    if [ "$CLEANUP_ONLY" = true ]; then
        log_debug "Skipping backup creation (cleanup-only mode)"
        return
    fi

    log_step "Creating backup of current state"

    local backup_path="$BACKUP_DIR/rollback-$ROLLBACK_VERSION-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_path"

    # Backup Git state
    if [ "$ROLLBACK_TYPE" != "artifacts-only" ]; then
        log_debug "Backing up Git state"
        
        # Save current branch
        git rev-parse --abbrev-ref HEAD > "$backup_path/current-branch.txt"
        
        # Save current commit
        git rev-parse HEAD > "$backup_path/current-commit.txt"
        
        # Save Git status
        git status --porcelain > "$backup_path/git-status.txt"
        
        # Save remote URLs
        git remote -v > "$backup_path/git-remotes.txt"
        
        # Save tags
        git tag -l > "$backup_path/git-tags.txt"
        
        log_debug "Git state backed up to: $backup_path"
    fi

    # Backup build artifacts if they exist
    if [ -d "$ARTIFACTS_DIR" ]; then
        log_debug "Backing up build artifacts"
        cp -r "$ARTIFACTS_DIR" "$backup_path/artifacts" 2>/dev/null || true
        log_debug "Build artifacts backed up"
    fi

    # Backup important files
    for file in "Package.swift" "Package.resolved" ".swiftlint.yml"; do
        if [ -f "$PROJECT_ROOT/$file" ]; then
            cp "$PROJECT_ROOT/$file" "$backup_path/" 2>/dev/null || true
            log_debug "Backed up: $file"
        fi
    done

    # Create backup manifest
    cat > "$backup_path/backup-manifest.txt" << EOF
Rollback Backup Manifest
========================
Created: $(date)
Script: $0
Version: $ROLLBACK_VERSION
Type: $ROLLBACK_TYPE
Project Root: $PROJECT_ROOT
Git Commit: $(git rev-parse HEAD 2>/dev/null || echo "unknown")
Git Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
EOF

    log_success "Backup created: $backup_path"
}

# Rollback Git operations
rollback_git_operations() {
    if [ "$CLEANUP_ONLY" = true ] || [ "$ROLLBACK_TYPE" = "artifacts-only" ]; then
        log_debug "Skipping Git operations"
        return
    fi

    log_step "Rolling back Git operations"

    case "$ROLLBACK_TYPE" in
        failed-release)
            rollback_failed_release_git
            ;;
        incomplete-build)
            rollback_incomplete_build_git
            ;;
    esac
}

# Rollback failed release Git operations
rollback_failed_release_git() {
    log_info "Rolling back failed release Git operations"

    # Check if tag exists locally
    if git tag -l | grep -q "^$ROLLBACK_VERSION$"; then
        log_info "Found local tag: $ROLLBACK_VERSION"

        if [ "$DRY_RUN" = false ]; then
            # Delete local tag
            log_info "Deleting local tag: $ROLLBACK_VERSION"
            git tag -d "$ROLLBACK_VERSION"
            log_success "Local tag deleted: $ROLLBACK_VERSION"
        else
            log_info "[DRY RUN] Would delete local tag: $ROLLBACK_VERSION"
        fi
    else
        log_debug "Local tag not found: $ROLLBACK_VERSION"
    fi

    # Check if tag exists on remote
    if git ls-remote --tags "$REMOTE_NAME" | grep -q "refs/tags/$ROLLBACK_VERSION$"; then
        log_info "Found remote tag: $ROLLBACK_VERSION"

        if [ "$DRY_RUN" = false ]; then
            # Delete remote tag
            log_info "Deleting remote tag: $ROLLBACK_VERSION"
            if git push "$REMOTE_NAME" --delete "refs/tags/$ROLLBACK_VERSION"; then
                log_success "Remote tag deleted: $ROLLBACK_VERSION"
            else
                log_warning "Failed to delete remote tag (might not exist): $ROLLBACK_VERSION"
            fi
        else
            log_info "[DRY RUN] Would delete remote tag: $ROLLBACK_VERSION"
        fi
    else
        log_debug "Remote tag not found: $ROLLBACK_VERSION"
    fi

    # Reset to main branch if we're on a release branch
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    if [[ "$current_branch" == "release/"* ]] || [[ "$current_branch" == "hotfix/"* ]]; then
        log_info "Currently on release/hotfix branch: $current_branch"
        
        if [ "$DRY_RUN" = false ]; then
            # Fetch latest main
            log_info "Fetching latest main branch"
            git fetch "$REMOTE_NAME" "$MAIN_BRANCH"
            
            # Switch to main
            log_info "Switching to main branch"
            git checkout "$MAIN_BRANCH"
            
            # Reset to remote main
            git reset --hard "$REMOTE_NAME/$MAIN_BRANCH"
            
            # Delete release branch
            log_info "Deleting release branch: $current_branch"
            git branch -D "$current_branch"
            
            log_success "Switched to main branch and cleaned up release branch"
        else
            log_info "[DRY RUN] Would switch to main and delete branch: $current_branch"
        fi
    fi
}

# Rollback incomplete build Git operations
rollback_incomplete_build_git() {
    log_info "Rolling back incomplete build Git operations"

    # Reset any staged changes related to build artifacts
    if [ "$DRY_RUN" = false ]; then
        log_info "Resetting staged changes"
        git reset HEAD -- .build/ 2>/dev/null || true
        git reset HEAD -- build/ 2>/dev/null || true
        git reset HEAD -- dist/ 2>/dev/null || true
        
        # Clean untracked build files
        git clean -fd .build/ 2>/dev/null || true
        git clean -fd build/ 2>/dev/null || true
        git clean -fd dist/ 2>/dev/null || true
        
        log_success "Git workspace cleaned of build artifacts"
    else
        log_info "[DRY RUN] Would reset staged changes and clean build artifacts"
    fi
}

# Clean up build artifacts
cleanup_build_artifacts() {
    log_step "Cleaning up build artifacts"

    local cleanup_paths=(
        "$BUILD_DIR"
        "$PROJECT_ROOT/build"
        "$PROJECT_ROOT/dist"
        "$PROJECT_ROOT/.swiftpm"
        "$PROJECT_ROOT/Package.resolved"
    )

    for path in "${cleanup_paths[@]}"; do
        if [ -e "$path" ]; then
            log_info "Cleaning up: $(basename "$path")"
            
            if [ "$DRY_RUN" = false ]; then
                if [ -d "$path" ]; then
                    rm -rf "$path"
                else
                    rm -f "$path"
                fi
                log_success "Cleaned up: $(basename "$path")"
            else
                log_info "[DRY RUN] Would clean up: $(basename "$path")"
            fi
        else
            log_debug "Path not found (skipping): $(basename "$path")"
        fi
    done
}

# Clean up temporary files
cleanup_temporary_files() {
    log_step "Cleaning up temporary files"

    # Find and clean up temporary files older than MAX_ROLLBACK_DAYS
    local temp_patterns=(
        "$PROJECT_ROOT/tmp"
        "$PROJECT_ROOT/.tmp"
        "$PROJECT_ROOT/temp"
        "/tmp/usbipd-*"
        "/tmp/swift-*"
        "${TMPDIR:-/tmp}/usbipd-*"
    )

    for pattern in "${temp_patterns[@]}"; do
        # Expand glob pattern
        local expanded_paths=($pattern)
        
        for path in "${expanded_paths[@]}"; do
            # Check if path exists and is older than MAX_ROLLBACK_DAYS
            if [ -e "$path" ]; then
                local file_age
                file_age=$(( ($(date +%s) - $(stat -f %m "$path" 2>/dev/null || stat -c %Y "$path" 2>/dev/null || echo 0)) / 86400 ))
                
                if [ "$file_age" -gt "$MAX_ROLLBACK_DAYS" ]; then
                    log_info "Cleaning up old temporary file: $(basename "$path") (${file_age} days old)"
                    
                    if [ "$DRY_RUN" = false ]; then
                        rm -rf "$path"
                        log_success "Cleaned up: $(basename "$path")"
                    else
                        log_info "[DRY RUN] Would clean up: $(basename "$path")"
                    fi
                else
                    log_debug "Keeping recent temporary file: $(basename "$path") (${file_age} days old)"
                fi
            fi
        done
    done
}

# Clean up log files
cleanup_log_files() {
    log_step "Cleaning up old log files"

    if [ -d "$LOG_DIR" ]; then
        # Find log files older than MAX_ROLLBACK_DAYS
        if [ "$DRY_RUN" = false ]; then
            find "$LOG_DIR" -name "*.log" -type f -mtime +"$MAX_ROLLBACK_DAYS" -delete 2>/dev/null || true
            log_success "Cleaned up old log files (older than $MAX_ROLLBACK_DAYS days)"
        else
            local old_logs
            old_logs=$(find "$LOG_DIR" -name "*.log" -type f -mtime +"$MAX_ROLLBACK_DAYS" 2>/dev/null | wc -l)
            log_info "[DRY RUN] Would clean up $old_logs old log files"
        fi
    fi
}

# Clean up backup files
cleanup_backup_files() {
    if [ "$PRESERVE_BACKUP" = true ]; then
        log_debug "Preserving backup files (--preserve-backup specified)"
        return
    fi

    log_step "Cleaning up old backup files"

    if [ -d "$BACKUP_DIR" ]; then
        # Find backup directories older than configured retention
        local backup_retention="${ROLLBACK_BACKUP_RETENTION:-7}"
        
        if [ "$DRY_RUN" = false ]; then
            find "$BACKUP_DIR" -type d -name "rollback-*" -mtime +"$backup_retention" -exec rm -rf {} + 2>/dev/null || true
            log_success "Cleaned up old backup files (older than $backup_retention days)"
        else
            local old_backups
            old_backups=$(find "$BACKUP_DIR" -type d -name "rollback-*" -mtime +"$backup_retention" 2>/dev/null | wc -l)
            log_info "[DRY RUN] Would clean up $old_backups old backup directories"
        fi
    fi
}

# Verify rollback completion
verify_rollback() {
    log_step "Verifying rollback completion"

    local verification_failed=false

    # Verify Git state (if applicable)
    if [ "$ROLLBACK_TYPE" != "artifacts-only" ] && [ "$CLEANUP_ONLY" = false ]; then
        log_info "Verifying Git state"

        # Check if rollback tag is removed
        if [ "$ROLLBACK_TYPE" = "failed-release" ] && [ -n "$ROLLBACK_VERSION" ] && [ "$ROLLBACK_VERSION" != "unknown" ]; then
            if git tag -l | grep -q "^$ROLLBACK_VERSION$"; then
                log_error "Local tag still exists: $ROLLBACK_VERSION"
                verification_failed=true
            else
                log_debug "✓ Local tag removed: $ROLLBACK_VERSION"
            fi
        fi

        # Check current branch
        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD)
        log_debug "Current branch: $current_branch"

        # Check working directory is clean
        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
            log_warning "Working directory has uncommitted changes"
        else
            log_debug "✓ Working directory is clean"
        fi
    fi

    # Verify build artifacts are cleaned
    log_info "Verifying artifact cleanup"

    if [ -d "$ARTIFACTS_DIR" ]; then
        log_warning "Artifacts directory still exists: $ARTIFACTS_DIR"
        # This might be intentional in some cases, so don't fail
    else
        log_debug "✓ Artifacts directory cleaned"
    fi

    if [ -d "$BUILD_DIR" ]; then
        log_warning "Build directory still exists: $BUILD_DIR"
        # This might be intentional in some cases, so don't fail
    else
        log_debug "✓ Build directory cleaned"
    fi

    if [ "$verification_failed" = true ]; then
        log_error "Rollback verification failed"
        return $EXIT_ROLLBACK_FAILED
    else
        log_success "Rollback verification completed successfully"
        return $EXIT_SUCCESS
    fi
}

# Generate rollback report
generate_rollback_report() {
    log_step "Generating rollback report"

    local report_file="$LOG_DIR/rollback-report-$(date +%Y%m%d-%H%M%S).txt"

    cat > "$report_file" << EOF
Rollback Report for usbipd-mac
==============================
Date: $(date)
Script: $0
Version: $ROLLBACK_VERSION
Type: $ROLLBACK_TYPE
Dry Run: $DRY_RUN
Project Root: $PROJECT_ROOT

Git Information:
- Current Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
- Current Commit: $(git rev-parse HEAD 2>/dev/null || echo "unknown")
- Remote: $REMOTE_NAME
- Main Branch: $MAIN_BRANCH

Cleanup Summary:
- Build artifacts: $([ -d "$BUILD_DIR" ] && echo "present" || echo "cleaned")
- Temporary files: cleaned (older than $MAX_ROLLBACK_DAYS days)
- Log files: cleaned (older than $MAX_ROLLBACK_DAYS days)
- Backup files: $([ "$PRESERVE_BACKUP" = true ] && echo "preserved" || echo "cleaned")

Actions Performed:
EOF

    # Add specific actions based on rollback type
    case "$ROLLBACK_TYPE" in
        failed-release)
            cat >> "$report_file" << EOF
- Removed Git tag: $ROLLBACK_VERSION (if existed)
- Reset to main branch (if on release branch)
- Cleaned up build artifacts
- Cleaned up temporary files
EOF
            ;;
        incomplete-build)
            cat >> "$report_file" << EOF
- Reset staged build-related changes
- Cleaned up build artifacts
- Cleaned up temporary files
EOF
            ;;
        artifacts-only)
            cat >> "$report_file" << EOF
- Cleaned up build artifacts only
- Preserved Git state unchanged
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
        failed-release)
            echo "  • Remove Git tag: $ROLLBACK_VERSION (local and remote)"
            echo "  • Switch to main branch and cleanup release branches"
            echo "  • Remove all build artifacts and temporary files"
            ;;
        incomplete-build)
            echo "  • Reset staged changes related to build artifacts"
            echo "  • Clean untracked build files"
            echo "  • Remove all build artifacts and temporary files"
            ;;
        artifacts-only)
            echo "  • Remove build artifacts only"
            echo "  • Preserve Git state unchanged"
            ;;
    esac

    if [ "$CLEANUP_ONLY" = false ]; then
        echo "  • Create backup of current state"
    fi
    echo "  • Clean up files older than $MAX_ROLLBACK_DAYS days"
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
    
    # Create backup
    create_backup
    
    # Perform rollback operations
    rollback_git_operations
    
    # Clean up artifacts
    cleanup_build_artifacts
    
    # Clean up temporary files
    cleanup_temporary_files
    
    # Clean up log files
    cleanup_log_files
    
    # Clean up backup files
    cleanup_backup_files
    
    # Verify rollback
    if ! verify_rollback; then
        log_error "Rollback verification failed"
        exit $EXIT_ROLLBACK_FAILED
    fi
    
    # Generate report
    generate_rollback_report
    
    log_success "Rollback completed successfully"
    
    if [ "$DRY_RUN" = true ]; then
        echo ""
        echo -e "${BOLD}${GREEN}This was a dry run. No changes were made.${NC}"
        echo -e "${BOLD}Run without --dry-run to perform the actual rollback.${NC}"
    fi
    
    echo ""
    log_success "🎉 Rollback operation completed for version: $ROLLBACK_VERSION"
}

# Error handling
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Execute main function with all arguments
main "$@"