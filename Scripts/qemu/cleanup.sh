#!/bin/bash
#
# cleanup.sh - QEMU Test Environment Cleanup and Maintenance Utilities
#
# Provides comprehensive cleanup and maintenance utilities for QEMU test infrastructure.
# Handles orphaned VM detection, disk space management, and test environment maintenance.
#
# This script helps maintain a clean test environment by removing leftover processes,
# temporary files, and managing disk space used by VM images and test artifacts.

set -euo pipefail

# Script metadata
readonly SCRIPT_NAME="QEMU Cleanup Utilities"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Paths and directories
readonly RUN_DIR="$PROJECT_ROOT/tmp/qemu-run"
readonly LOG_DIR="$PROJECT_ROOT/tmp/qemu-logs"
readonly IMAGE_DIR="$PROJECT_ROOT/tmp/qemu-images"
readonly LOCK_DIR="$PROJECT_ROOT/tmp/qemu-locks"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Configuration
readonly DEFAULT_MAX_AGE_DAYS=7
readonly DEFAULT_MAX_DISK_USAGE_GB=5
readonly CLEANUP_SESSION_ID="cleanup_$(date +%Y%m%d_%H%M%S)_$$"

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

log_step() {
    echo -e "${CYAN}[STEP]${NC} ${BOLD}$1${NC}"
}

# Utility functions
human_readable_size() {
    local size="$1"
    if [[ $size -lt 1024 ]]; then
        echo "${size}B"
    elif [[ $size -lt $((1024 * 1024)) ]]; then
        echo "$((size / 1024))KB"
    elif [[ $size -lt $((1024 * 1024 * 1024)) ]]; then
        echo "$((size / 1024 / 1024))MB"
    else
        echo "$((size / 1024 / 1024 / 1024))GB"
    fi
}

get_disk_usage_gb() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        du -s "$dir" 2>/dev/null | awk '{print int($1/1024/1024)}'
    else
        echo "0"
    fi
}

# Process cleanup functions
cleanup_orphaned_qemu_processes() {
    log_step "Cleaning up orphaned QEMU processes"
    
    local killed_count=0
    local processes=()
    
    # Find QEMU processes related to our test infrastructure
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            processes+=("$line")
        fi
    done < <(ps aux | grep -E "(qemu-system-x86_64|QEMUTestServer)" | grep -v grep | awk '{print $2 " " $11}' || true)
    
    if [[ ${#processes[@]} -eq 0 ]]; then
        log_info "No orphaned QEMU processes found"
        return 0
    fi
    
    log_info "Found ${#processes[@]} potential QEMU processes"
    
    for process_info in "${processes[@]}"; do
        local pid=$(echo "$process_info" | awk '{print $1}')
        local cmd=$(echo "$process_info" | awk '{print $2}')
        
        # Check if process is actually related to our testing
        if ps -p "$pid" -o args= | grep -qE "(usbip-test|QEMUTestServer)" 2>/dev/null; then
            log_info "Terminating orphaned process: PID $pid ($cmd)"
            
            # Try graceful termination first
            if kill -TERM "$pid" 2>/dev/null; then
                sleep 2
                # Check if process still exists
                if kill -0 "$pid" 2>/dev/null; then
                    # Force kill if still running
                    kill -KILL "$pid" 2>/dev/null || true
                fi
                killed_count=$((killed_count + 1))
            fi
        fi
    done
    
    if [[ $killed_count -gt 0 ]]; then
        log_success "Terminated $killed_count orphaned processes"
    else
        log_info "No orphaned processes needed termination"
    fi
}

cleanup_orphaned_network_connections() {
    log_step "Cleaning up orphaned network connections"
    
    # Find processes listening on QEMU test ports
    local qemu_ports=(3240 3241 3242)
    local killed_count=0
    
    for port in "${qemu_ports[@]}"; do
        local pid=$(lsof -ti :$port 2>/dev/null || true)
        if [[ -n "$pid" ]]; then
            local process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            log_info "Found process on port $port: PID $pid ($process_name)"
            
            # Only kill if it's our test process
            if [[ "$process_name" == *"QEMUTestServer"* ]] || [[ "$process_name" == *"qemu"* ]]; then
                if kill -TERM "$pid" 2>/dev/null; then
                    sleep 1
                    kill -KILL "$pid" 2>/dev/null || true
                    killed_count=$((killed_count + 1))
                    log_success "Terminated process on port $port"
                fi
            fi
        fi
    done
    
    if [[ $killed_count -eq 0 ]]; then
        log_info "No orphaned network connections found"
    fi
}

# File system cleanup functions
cleanup_temporary_files() {
    local max_age_days="${1:-$DEFAULT_MAX_AGE_DAYS}"
    
    log_step "Cleaning up temporary files older than $max_age_days days"
    
    local cleaned_size=0
    local cleaned_count=0
    
    # Cleanup log files
    if [[ -d "$LOG_DIR" ]]; then
        log_info "Cleaning old log files in $LOG_DIR"
        while IFS= read -r -d '' file; do
            local size=$(stat -c%s "$file" 2>/dev/null || echo "0")
            cleaned_size=$((cleaned_size + size))
            cleaned_count=$((cleaned_count + 1))
            rm -f "$file"
        done < <(find "$LOG_DIR" -type f -mtime +$max_age_days -print0 2>/dev/null || true)
    fi
    
    # Cleanup run directory
    if [[ -d "$RUN_DIR" ]]; then
        log_info "Cleaning old run files in $RUN_DIR"
        while IFS= read -r -d '' file; do
            local size=$(stat -c%s "$file" 2>/dev/null || echo "0")
            cleaned_size=$((cleaned_size + size))
            cleaned_count=$((cleaned_count + 1))
            rm -f "$file"
        done < <(find "$RUN_DIR" -type f -mtime +$max_age_days -print0 2>/dev/null || true)
    fi
    
    # Cleanup lock files
    if [[ -d "$LOCK_DIR" ]]; then
        log_info "Cleaning old lock files in $LOCK_DIR"
        while IFS= read -r -d '' file; do
            # Check if lock is still active
            local lock_pid=$(cat "$file" 2>/dev/null || echo "")
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                local size=$(stat -c%s "$file" 2>/dev/null || echo "0")
                cleaned_size=$((cleaned_size + size))
                cleaned_count=$((cleaned_count + 1))
                rm -f "$file"
            fi
        done < <(find "$LOCK_DIR" -type f -name "*.lock" -print0 2>/dev/null || true)
    fi
    
    if [[ $cleaned_count -gt 0 ]]; then
        local readable_size=$(human_readable_size $cleaned_size)
        log_success "Cleaned $cleaned_count files (freed $readable_size)"
    else
        log_info "No temporary files needed cleanup"
    fi
}

cleanup_vm_images() {
    local max_disk_usage_gb="${1:-$DEFAULT_MAX_DISK_USAGE_GB}"
    
    log_step "Managing VM image disk usage (max: ${max_disk_usage_gb}GB)"
    
    if [[ ! -d "$IMAGE_DIR" ]]; then
        log_info "VM image directory does not exist: $IMAGE_DIR"
        return 0
    fi
    
    local current_usage=$(get_disk_usage_gb "$IMAGE_DIR")
    log_info "Current disk usage: ${current_usage}GB"
    
    if [[ $current_usage -le $max_disk_usage_gb ]]; then
        log_info "Disk usage within limits"
        return 0
    fi
    
    log_warning "Disk usage exceeds limit (${current_usage}GB > ${max_disk_usage_gb}GB)"
    
    # List images by age and size
    local images=()
    while IFS= read -r -d '' file; do
        images+=("$file")
    done < <(find "$IMAGE_DIR" -type f \( -name "*.qcow2" -o -name "*.img" \) -printf "%T@ %s %p\0" 2>/dev/null | sort -z -n || true)
    
    local freed_space=0
    local removed_count=0
    
    for image_info in "${images[@]}"; do
        local size=$(echo "$image_info" | awk '{print $2}')
        local path=$(echo "$image_info" | awk '{print $3}')
        
        # Skip if it's currently being used (has lock file)
        local lock_file="${path}.lock"
        if [[ -f "$lock_file" ]]; then
            local lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")
            if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
                continue
            fi
        fi
        
        log_info "Removing old VM image: $(basename "$path") ($(human_readable_size $size))"
        rm -f "$path" "$lock_file" 2>/dev/null || true
        
        freed_space=$((freed_space + size))
        removed_count=$((removed_count + 1))
        
        # Check if we're now within limits
        local new_usage=$(get_disk_usage_gb "$IMAGE_DIR")
        if [[ $new_usage -le $max_disk_usage_gb ]]; then
            log_success "Disk usage now within limits: ${new_usage}GB"
            break
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        local readable_freed=$(human_readable_size $freed_space)
        log_success "Removed $removed_count images (freed $readable_freed)"
    else
        log_warning "No images could be removed (all may be in use)"
    fi
}

# Directory cleanup functions
cleanup_empty_directories() {
    log_step "Removing empty directories"
    
    local dirs=("$RUN_DIR" "$LOG_DIR" "$LOCK_DIR" "$IMAGE_DIR")
    local removed_count=0
    
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            # Remove empty subdirectories
            while IFS= read -r -d '' subdir; do
                if rmdir "$subdir" 2>/dev/null; then
                    removed_count=$((removed_count + 1))
                    log_info "Removed empty directory: $subdir"
                fi
            done < <(find "$dir" -type d -empty -print0 2>/dev/null | head -20 || true)
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        log_success "Removed $removed_count empty directories"
    else
        log_info "No empty directories found"
    fi
}

# Main cleanup functions
full_cleanup() {
    local max_age_days="${1:-$DEFAULT_MAX_AGE_DAYS}"
    local max_disk_usage_gb="${2:-$DEFAULT_MAX_DISK_USAGE_GB}"
    
    log_step "Starting full QEMU test environment cleanup"
    log_info "Session ID: $CLEANUP_SESSION_ID"
    log_info "Max file age: $max_age_days days"
    log_info "Max disk usage: ${max_disk_usage_gb}GB"
    
    # Process cleanup
    cleanup_orphaned_qemu_processes
    cleanup_orphaned_network_connections
    
    # File system cleanup
    cleanup_temporary_files "$max_age_days"
    cleanup_vm_images "$max_disk_usage_gb"
    cleanup_empty_directories
    
    log_success "Full cleanup completed"
}

emergency_cleanup() {
    log_step "Starting emergency cleanup (forceful termination)"
    
    # Force kill all QEMU processes
    local qemu_pids=$(pgrep -f "qemu-system-x86_64" || true)
    if [[ -n "$qemu_pids" ]]; then
        echo "$qemu_pids" | xargs -r kill -KILL 2>/dev/null || true
        log_info "Force terminated all QEMU processes"
    fi
    
    # Force kill QEMUTestServer processes
    local server_pids=$(pgrep -f "QEMUTestServer" || true)
    if [[ -n "$server_pids" ]]; then
        echo "$server_pids" | xargs -r kill -KILL 2>/dev/null || true
        log_info "Force terminated all QEMUTestServer processes"
    fi
    
    # Remove all temporary files regardless of age
    for dir in "$RUN_DIR" "$LOG_DIR" "$LOCK_DIR"; do
        if [[ -d "$dir" ]]; then
            find "$dir" -type f -delete 2>/dev/null || true
            log_info "Cleaned all files from $dir"
        fi
    done
    
    log_success "Emergency cleanup completed"
}

# Status and reporting functions
show_cleanup_status() {
    log_step "QEMU Test Environment Status"
    
    # Process information
    local qemu_processes=$(pgrep -f "qemu-system-x86_64" | wc -l || echo "0")
    local server_processes=$(pgrep -f "QEMUTestServer" | wc -l || echo "0")
    
    echo "Active Processes:"
    echo "  QEMU VMs: $qemu_processes"
    echo "  Test Servers: $server_processes"
    
    # Disk usage information
    echo
    echo "Disk Usage:"
    for dir in "$RUN_DIR" "$LOG_DIR" "$IMAGE_DIR"; do
        if [[ -d "$dir" ]]; then
            local usage=$(get_disk_usage_gb "$dir")
            local file_count=$(find "$dir" -type f | wc -l)
            echo "  $(basename "$dir"): ${usage}GB ($file_count files)"
        else
            echo "  $(basename "$dir"): Directory does not exist"
        fi
    done
    
    # Network ports
    echo
    echo "Network Ports:"
    local qemu_ports=(3240 3241 3242)
    for port in "${qemu_ports[@]}"; do
        local pid=$(lsof -ti :$port 2>/dev/null || echo "")
        if [[ -n "$pid" ]]; then
            local process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            echo "  Port $port: In use by PID $pid ($process_name)"
        else
            echo "  Port $port: Available"
        fi
    done
    
    # Recent activity
    echo
    echo "Recent Activity:"
    if [[ -d "$LOG_DIR" ]]; then
        local recent_logs=$(find "$LOG_DIR" -type f -mtime -1 | wc -l)
        echo "  Log files created today: $recent_logs"
        
        local latest_log=$(find "$LOG_DIR" -type f -name "orchestrator_*.log" | head -1)
        if [[ -n "$latest_log" ]]; then
            local latest_time=$(stat -c %Y "$latest_log" 2>/dev/null || echo "0")
            local current_time=$(date +%s)
            local age_hours=$(( (current_time - latest_time) / 3600 ))
            echo "  Last orchestrator run: ${age_hours} hours ago"
        fi
    fi
}

# Help and usage
show_usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}
${CYAN}Comprehensive cleanup and maintenance utilities for QEMU test infrastructure${NC}

${BOLD}USAGE:${NC}
    $0 [COMMAND] [OPTIONS]

${BOLD}COMMANDS:${NC}
    ${GREEN}full${NC}        Complete cleanup (processes, files, images)
                  Default: Remove files >7 days, maintain <5GB disk usage
    
    ${GREEN}processes${NC}   Clean up orphaned QEMU and test server processes
                  - Gracefully terminate orphaned VMs and servers
                  - Clean up network port bindings
    
    ${GREEN}files${NC}       Clean up temporary files and logs
                  - Remove old log files, run files, and lock files
                  - Respect configurable age limits
    
    ${GREEN}images${NC}      Manage VM image disk usage
                  - Remove old VM images when disk usage is high
                  - Respect active VM locks
    
    ${GREEN}emergency${NC}   Emergency cleanup (force terminate everything)
                  - Force kill all QEMU processes
                  - Remove all temporary files regardless of age
                  - Use only when normal cleanup fails
    
    ${GREEN}status${NC}      Show current environment status
                  - Display active processes and disk usage
                  - Show network port status and recent activity
    
    ${GREEN}help${NC}        Show this help message

${BOLD}OPTIONS:${NC}
    --max-age DAYS        Maximum age for temporary files (default: $DEFAULT_MAX_AGE_DAYS)
    --max-disk-gb SIZE    Maximum disk usage in GB (default: $DEFAULT_MAX_DISK_USAGE_GB)
    --verbose            Enable verbose output
    --dry-run            Show what would be cleaned without doing it

${BOLD}EXAMPLES:${NC}
    ${YELLOW}Basic Usage:${NC}
    $0 full                           # Complete cleanup with defaults
    $0 status                         # Check current status
    $0 processes                      # Clean up orphaned processes only
    
    ${YELLOW}Customized Cleanup:${NC}
    $0 full --max-age 3               # Keep files newer than 3 days
    $0 images --max-disk-gb 2         # Limit disk usage to 2GB
    $0 files --verbose                # Detailed file cleanup
    
    ${YELLOW}Maintenance:${NC}
    $0 --dry-run full                 # Preview cleanup actions
    $0 emergency                      # Force cleanup everything
    
    ${YELLOW}Integration with Test Scripts:${NC}
    Scripts/run-development-tests.sh --cleanup  # Cleanup after tests
    Scripts/run-production-tests.sh --cleanup   # Cleanup after tests

${BOLD}DIRECTORIES MANAGED:${NC}
    ${CYAN}Log Directory:${NC} $LOG_DIR
    - Test execution logs, orchestrator logs, server logs
    
    ${CYAN}Run Directory:${NC} $RUN_DIR
    - Temporary runtime files, PID files, state files
    
    ${CYAN}Image Directory:${NC} $IMAGE_DIR
    - VM disk images, snapshots, templates
    
    ${CYAN}Lock Directory:${NC} $LOCK_DIR
    - Process locks, resource locks, coordination files

${BOLD}SAFETY FEATURES:${NC}
    - Process validation before termination
    - Active lock checking before file removal
    - Graceful termination with fallback to force
    - Dry-run mode for safe preview

${BOLD}INTEGRATION:${NC}
    This cleanup utility integrates with:
    - Scripts/qemu/test-orchestrator.sh (--cleanup flag)
    - Scripts/qemu/vm-manager.sh (cleanup functions)
    - All test execution scripts (post-test cleanup)

EOF
}

# Main function
main() {
    local command=""
    local max_age_days="$DEFAULT_MAX_AGE_DAYS"
    local max_disk_usage_gb="$DEFAULT_MAX_DISK_USAGE_GB"
    local verbose=false
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            full|processes|files|images|emergency|status)
                command="$1"
                shift
                ;;
            --max-age)
                max_age_days="$2"
                shift 2
                ;;
            --max-disk-gb)
                max_disk_usage_gb="$2"
                shift 2
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help|help)
                show_usage
                return 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                return 1
                ;;
            *)
                log_error "Unknown command: $1"
                show_usage
                return 1
                ;;
        esac
    done
    
    # Default to status if no command specified
    if [[ -z "$command" ]]; then
        command="status"
    fi
    
    # Dry run mode
    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN MODE - No actual cleanup will be performed"
    fi
    
    # Execute command
    case "$command" in
        "full")
            if [[ "$dry_run" == "true" ]]; then
                log_info "Would perform full cleanup with max_age=$max_age_days days, max_disk=${max_disk_usage_gb}GB"
            else
                full_cleanup "$max_age_days" "$max_disk_usage_gb"
            fi
            ;;
        "processes")
            if [[ "$dry_run" == "true" ]]; then
                log_info "Would clean up orphaned processes"
            else
                cleanup_orphaned_qemu_processes
                cleanup_orphaned_network_connections
            fi
            ;;
        "files")
            if [[ "$dry_run" == "true" ]]; then
                log_info "Would clean up temporary files older than $max_age_days days"
            else
                cleanup_temporary_files "$max_age_days"
            fi
            ;;
        "images")
            if [[ "$dry_run" == "true" ]]; then
                log_info "Would manage VM images to stay under ${max_disk_usage_gb}GB"
            else
                cleanup_vm_images "$max_disk_usage_gb"
            fi
            ;;
        "emergency")
            if [[ "$dry_run" == "true" ]]; then
                log_info "Would perform emergency cleanup (force terminate all)"
            else
                log_warning "Performing emergency cleanup - this will forcefully terminate all QEMU processes"
                read -p "Continue? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    emergency_cleanup
                else
                    log_info "Emergency cleanup cancelled"
                fi
            fi
            ;;
        "status")
            show_cleanup_status
            ;;
        *)
            log_error "Unknown command: $command"
            return 1
            ;;
    esac
    
    return 0
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi