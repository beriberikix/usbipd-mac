#!/bin/bash
#
# vm-manager.sh - QEMU VM lifecycle management for USB/IP testing
#
# This script provides reliable VM lifecycle operations with state tracking,
# process management, and comprehensive error handling. It integrates with
# the existing test environment patterns and configuration system.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Enhanced error handling and cleanup
TEMP_FILES=()
CLEANUP_PIDS=()

# Signal handler for cleanup
cleanup_on_exit() {
    local exit_code=$?
    
    # Clean up temporary files
    if [[ ${#TEMP_FILES[@]} -gt 0 ]]; then
        for temp_file in "${TEMP_FILES[@]}"; do
            [[ -f "$temp_file" ]] && rm -f "$temp_file" 2>/dev/null
        done
    fi
    
    # Clean up background processes
    if [[ ${#CLEANUP_PIDS[@]} -gt 0 ]]; then
        for pid in "${CLEANUP_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid" 2>/dev/null || true
                sleep 1
                kill -KILL "$pid" 2>/dev/null || true
            fi
        done
    fi
    
    exit $exit_code
}

# Install cleanup handlers
trap cleanup_on_exit EXIT
trap 'log_warning "Operation interrupted by user"; exit 130' INT TERM

# Load configuration
CONFIG_FILE="${SCRIPT_DIR}/test-vm-config.json"
VALIDATION_SCRIPT="${PROJECT_ROOT}/Scripts/qemu-test-validation.sh"

# State management
VM_STATE_DIR="${PROJECT_ROOT}/tmp/qemu-run"
VM_LOG_DIR="${PROJECT_ROOT}/tmp/qemu-logs"
VM_IMAGE_DIR="${PROJECT_ROOT}/tmp/qemu-images"

# Default configuration
DEFAULT_VM_NAME="usbip-test"
DEFAULT_MEMORY="256M"
DEFAULT_CPU_CORES=1

# Colors for output (inherited from validation script pattern)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Environment Detection (leveraging validation script patterns)
detect_test_environment() {
    if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "ci"
    elif [[ -n "${TEST_ENVIRONMENT:-}" ]]; then
        echo "$TEST_ENVIRONMENT"
    elif [[ -n "${PRODUCTION_TEST:-}" ]]; then
        echo "production"
    else
        echo "development"
    fi
}

readonly TEST_ENVIRONMENT="${TEST_ENVIRONMENT:-$(detect_test_environment)}"

# Logging functions (consistent with validation script)
log_info() {
    echo -e "${BLUE}[VM-MANAGER:${TEST_ENVIRONMENT}]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[VM-MANAGER:${TEST_ENVIRONMENT}]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[VM-MANAGER:${TEST_ENVIRONMENT}]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[VM-MANAGER:${TEST_ENVIRONMENT}]${NC} $1" >&2
}

# Enhanced error handling functions
handle_critical_error() {
    local error_msg="$1"
    local vm_name="${2:-}"
    local exit_code="${3:-1}"
    
    log_error "CRITICAL ERROR: $error_msg"
    
    if [[ -n "$vm_name" ]]; then
        save_vm_state "$vm_name" "failed" "$error_msg"
        
        # Attempt emergency cleanup
        local vm_pid
        if vm_pid=$(get_vm_pid "$vm_name" 2>/dev/null); then
            log_info "Attempting emergency VM cleanup..."
            kill -KILL "$vm_pid" 2>/dev/null || true
        fi
    fi
    
    exit "$exit_code"
}

validate_prerequisites() {
    local required_commands=("qemu-system-x86_64" "qemu-img")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        handle_critical_error "Missing required commands: ${missing_commands[*]}"
    fi
    
    # Validate directories
    local required_dirs=("$VM_STATE_DIR" "$VM_LOG_DIR" "$VM_IMAGE_DIR")
    for dir in "${required_dirs[@]}"; do
        if ! mkdir -p "$dir" 2>/dev/null; then
            handle_critical_error "Cannot create required directory: $dir"
        fi
    done
}

# Robust timeout handler
wait_with_timeout() {
    local timeout="$1"
    local check_interval="$2"
    local check_function="$3"
    local description="$4"
    shift 4
    local check_args=("$@")
    
    local elapsed=0
    log_info "$description (timeout: ${timeout}s)"
    
    while [[ $elapsed -lt $timeout ]]; do
        if "$check_function" "${check_args[@]}"; then
            return 0
        fi
        
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
        
        # Progress indicator every 10 seconds
        if [[ $((elapsed % 10)) -eq 0 && $elapsed -lt $timeout ]]; then
            log_info "Still waiting... (${elapsed}/${timeout}s)"
        fi
    done
    
    log_error "$description failed after ${timeout}s timeout"
    return 1
}

# Enhanced resource validation
validate_system_resources() {
    local memory_mb="${1:-256}"
    local check_disk_space="${2:-true}"
    
    # Check available memory (basic check)
    if [[ "$TEST_ENVIRONMENT" == "production" ]]; then
        local memory_kb=$((memory_mb * 1024))
        local available_kb
        
        if available_kb=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null); then
            if [[ $available_kb -lt $memory_kb ]]; then
                log_warning "Low available memory: ${available_kb}KB < ${memory_kb}KB requested"
            fi
        elif available_kb=$(vm_stat 2>/dev/null | awk '/Pages free:/ {print $3}' | tr -d '.'); then
            # macOS memory check (approximate)
            available_kb=$((available_kb * 4))  # 4KB pages
            if [[ $available_kb -lt $memory_kb ]]; then
                log_warning "Low available memory: ${available_kb}KB < ${memory_kb}KB requested"
            fi
        fi
    fi
    
    # Check disk space for VM images
    if [[ "$check_disk_space" == "true" ]]; then
        local available_space
        if available_space=$(df "$VM_IMAGE_DIR" 2>/dev/null | awk 'NR==2 {print $4}'); then
            # Require at least 1GB available space
            if [[ $available_space -lt 1048576 ]]; then
                log_warning "Low disk space in VM image directory: ${available_space}KB available"
            fi
        fi
    fi
}

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

load_vm_config() {
    local vm_name="$1"
    local config_key="environments.${TEST_ENVIRONMENT}"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        return 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq not available, using default configuration"
        return 1
    fi
    
    # Extract configuration for current environment
    local config
    if ! config=$(jq -r ".${config_key}" "$CONFIG_FILE" 2>/dev/null); then
        log_warning "Failed to parse configuration for environment: $TEST_ENVIRONMENT"
        return 1
    fi
    
    if [[ "$config" == "null" ]]; then
        log_warning "No configuration found for environment: $TEST_ENVIRONMENT"
        return 1
    fi
    
    echo "$config"
}

get_config_value() {
    local config="$1"
    local key="$2"
    local default_value="$3"
    
    if command -v jq &> /dev/null; then
        local value
        if value=$(echo "$config" | jq -r ".${key}" 2>/dev/null) && [[ "$value" != "null" ]]; then
            echo "$value"
        else
            echo "$default_value"
        fi
    else
        echo "$default_value"
    fi
}

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

get_vm_state_file() {
    local vm_name="$1"
    echo "${VM_STATE_DIR}/${vm_name}.state"
}

get_vm_pid_file() {
    local vm_name="$1"
    echo "${VM_STATE_DIR}/${vm_name}.pid"
}

get_vm_log_file() {
    local vm_name="$1"
    echo "${VM_LOG_DIR}/${vm_name}-console.log"
}

get_vm_monitor_file() {
    local vm_name="$1"
    echo "${VM_STATE_DIR}/${vm_name}.monitor"
}

save_vm_state() {
    local vm_name="$1"
    local state="$2"
    local additional_info="${3:-}"
    
    # Validate inputs
    if [[ -z "$vm_name" || -z "$state" ]]; then
        log_error "Invalid parameters for save_vm_state: vm_name='$vm_name', state='$state'"
        return 1
    fi
    
    # Ensure directory exists
    if ! mkdir -p "$VM_STATE_DIR"; then
        log_error "Cannot create VM state directory: $VM_STATE_DIR"
        return 1
    fi
    
    local state_file
    state_file=$(get_vm_state_file "$vm_name")
    
    # Create temporary file for atomic write
    local temp_state_file="${state_file}.tmp"
    TEMP_FILES+=("$temp_state_file")
    
    # Write state to temporary file
    if ! cat > "$temp_state_file" << EOF
{
    "vm_name": "$vm_name",
    "state": "$state",
    "timestamp": "$(date -Iseconds)",
    "environment": "$TEST_ENVIRONMENT",
    "pid": "${VM_PID:-}",
    "additional_info": "$additional_info"
}
EOF
    then
        log_error "Failed to write VM state to temporary file: $temp_state_file"
        rm -f "$temp_state_file" 2>/dev/null
        return 1
    fi
    
    # Atomically move to final location
    if ! mv "$temp_state_file" "$state_file"; then
        log_error "Failed to update VM state file: $state_file"
        rm -f "$temp_state_file" 2>/dev/null
        return 1
    fi
    
    log_info "VM state saved: $vm_name -> $state"
    return 0
}

get_vm_state() {
    local vm_name="$1"
    local state_file
    state_file=$(get_vm_state_file "$vm_name")
    
    if [[ ! -f "$state_file" ]]; then
        echo "unknown"
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        jq -r '.state' "$state_file" 2>/dev/null || echo "unknown"
    else
        # Fallback parsing without jq
        grep -o '"state": "[^"]*"' "$state_file" 2>/dev/null | cut -d'"' -f4 || echo "unknown"
    fi
}

get_vm_pid() {
    local vm_name="$1"
    local pid_file
    pid_file=$(get_vm_pid_file "$vm_name")
    
    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        
        # Verify process is still running
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        else
            # Clean up stale PID file
            rm -f "$pid_file"
            return 1
        fi
    fi
    
    return 1
}

cleanup_vm_state() {
    local vm_name="$1"
    
    local state_file pid_file monitor_file
    state_file=$(get_vm_state_file "$vm_name")
    pid_file=$(get_vm_pid_file "$vm_name")
    monitor_file=$(get_vm_monitor_file "$vm_name")
    
    rm -f "$state_file" "$pid_file" "$monitor_file"
    
    log_info "VM state cleaned up: $vm_name"
}

# ============================================================================
# VM LIFECYCLE FUNCTIONS
# ============================================================================

create_vm() {
    local vm_name="${1:-$DEFAULT_VM_NAME}"
    local force_recreate="${2:-false}"
    
    log_info "Creating VM: $vm_name"
    
    # Validate prerequisites first
    validate_prerequisites
    
    # Check if VM already exists
    local current_state
    current_state=$(get_vm_state "$vm_name" 2>/dev/null || echo "unknown")
    
    if [[ "$current_state" != "unknown" && "$force_recreate" != "true" ]]; then
        log_warning "VM already exists with state: $current_state"
        log_info "Use 'force_recreate=true' to recreate"
        return 1
    fi
    
    # Check for VM image
    local image_file="${VM_IMAGE_DIR}/${vm_name}.qcow2"
    if [[ ! -f "$image_file" ]]; then
        log_error "VM image not found: $image_file"
        log_info "Create VM image first using: Scripts/qemu/create-test-image.sh"
        return 1
    fi
    
    # Validate VM image integrity
    if ! qemu-img info "$image_file" >/dev/null 2>&1; then
        handle_critical_error "VM image is corrupted: $image_file" "$vm_name"
    fi
    
    # Validate system resources
    local memory_mb=256
    local config
    if config=$(load_vm_config "$vm_name"); then
        log_info "Loaded configuration for environment: $TEST_ENVIRONMENT"
        memory_mb=$(echo "$config" | jq -r '.vm.memory // "256M"' | sed 's/M$//')
    else
        log_warning "Using default configuration"
        config=""
    fi
    
    validate_system_resources "$memory_mb" true
    
    # Save initial state with error handling
    if ! save_vm_state "$vm_name" "created" "VM created but not started"; then
        log_error "Failed to save VM state"
        return 1
    fi
    
    log_success "VM created: $vm_name"
    return 0
}

start_vm() {
    local vm_name="${1:-$DEFAULT_VM_NAME}"
    local background="${2:-true}"
    
    log_info "Starting VM: $vm_name"
    
    # Check current state
    local current_state
    current_state=$(get_vm_state "$vm_name" 2>/dev/null || echo "unknown")
    
    if [[ "$current_state" == "running" ]]; then
        log_warning "VM is already running: $vm_name"
        return 0
    fi
    
    # Check if VM exists
    if [[ "$current_state" == "unknown" ]]; then
        log_info "VM not found, creating: $vm_name"
        if ! create_vm "$vm_name"; then
            return 1
        fi
    fi
    
    # Load configuration
    local config
    if config=$(load_vm_config "$vm_name"); then
        local memory cpu_cores enable_kvm boot_timeout
        memory=$(get_config_value "$config" "vm.memory" "$DEFAULT_MEMORY")
        cpu_cores=$(get_config_value "$config" "vm.cpu_cores" "$DEFAULT_CPU_CORES")
        enable_kvm=$(get_config_value "$config" "vm.enable_kvm" "true")
        boot_timeout=$(get_config_value "$config" "vm.boot_timeout" "60")
        
        log_info "VM Configuration:"
        log_info "  Memory: $memory"
        log_info "  CPU Cores: $cpu_cores"
        log_info "  KVM: $enable_kvm"
        log_info "  Boot Timeout: ${boot_timeout}s"
    else
        memory="$DEFAULT_MEMORY"
        cpu_cores="$DEFAULT_CPU_CORES"
        enable_kvm="true"
        boot_timeout="60"
    fi
    
    # Prepare VM files
    local image_file log_file pid_file monitor_file
    image_file="${VM_IMAGE_DIR}/${vm_name}.qcow2"
    log_file=$(get_vm_log_file "$vm_name")
    pid_file=$(get_vm_pid_file "$vm_name")
    monitor_file=$(get_vm_monitor_file "$vm_name")
    
    # Build QEMU command
    local qemu_cmd=(
        "qemu-system-x86_64"
        "-hda" "$image_file"
        "-m" "$memory"
        "-smp" "$cpu_cores"
        "-monitor" "unix:$monitor_file,server,nowait"
        "-netdev" "user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::3240-:3240"
        "-device" "e1000,netdev=net0"
    )
    
    # Add KVM if enabled and available
    if [[ "$enable_kvm" == "true" ]] && [[ -r "/dev/kvm" ]]; then
        qemu_cmd+=("-enable-kvm")
        log_info "KVM acceleration enabled"
    elif [[ "$enable_kvm" == "true" ]]; then
        log_warning "KVM requested but not available"
    fi
    
    # Add environment-specific arguments
    if [[ -n "$config" ]] && command -v jq &> /dev/null; then
        local qemu_args
        if qemu_args=$(echo "$config" | jq -r '.qemu_args[]' 2>/dev/null); then
            while IFS= read -r arg; do
                if [[ -n "$arg" ]]; then
                    qemu_cmd+=("$arg")
                fi
            done <<< "$qemu_args"
        fi
    fi
    
    log_info "QEMU command: ${qemu_cmd[*]}"
    
    # Start VM
    if [[ "$background" == "true" ]]; then
        # Start in background
        "${qemu_cmd[@]}" > "$log_file" 2>&1 &
        local qemu_pid=$!
        
        # Save PID
        echo "$qemu_pid" > "$pid_file"
        VM_PID="$qemu_pid"
        
        log_info "VM started in background with PID: $qemu_pid"
        
        # Update state
        save_vm_state "$vm_name" "starting" "VM process started, waiting for boot"
        
        # Add PID to cleanup list
        CLEANUP_PIDS+=("$qemu_pid")
        
        # Helper function to check boot completion
        check_vm_boot() {
            local vm_pid="$1"
            local log_file="$2"
            
            # First check if process is still alive
            if ! kill -0 "$vm_pid" 2>/dev/null; then
                log_error "VM process died during boot (PID: $vm_pid)"
                save_vm_state "$vm_name" "failed" "VM process died during boot"
                return 1
            fi
            
            # Check for boot completion markers
            if grep -q "login:" "$log_file" 2>/dev/null || \
               grep -q "Welcome to Alpine" "$log_file" 2>/dev/null || \
               grep -q "USBIP_CLIENT_READY" "$log_file" 2>/dev/null; then
                return 0
            fi
            
            return 1
        }
        
        # Use the enhanced timeout handler for boot waiting
        if wait_with_timeout "$boot_timeout" 2 check_vm_boot "Waiting for VM to boot" "$qemu_pid" "$log_file"; then
            log_success "VM boot completed successfully"
            save_vm_state "$vm_name" "running" "VM successfully booted and running"
            return 0
        else
            # Boot timeout - attempt graceful cleanup
            log_warning "VM boot timeout, attempting graceful shutdown..."
            
            if kill -TERM "$qemu_pid" 2>/dev/null; then
                # Wait for graceful termination
                local cleanup_timeout=10
                local elapsed=0
                while [[ $elapsed -lt $cleanup_timeout ]] && kill -0 "$qemu_pid" 2>/dev/null; do
                    sleep 1
                    elapsed=$((elapsed + 1))
                done
                
                # Force kill if still running
                if kill -0 "$qemu_pid" 2>/dev/null; then
                    log_warning "Graceful shutdown failed, force killing VM"
                    kill -KILL "$qemu_pid" 2>/dev/null || true
                fi
            fi
            
            save_vm_state "$vm_name" "failed" "VM boot timeout after ${boot_timeout}s"
            return 1
        fi
        
    else
        # Start in foreground (for debugging)
        log_info "Starting VM in foreground..."
        save_vm_state "$vm_name" "running" "VM running in foreground"
        exec "${qemu_cmd[@]}"
    fi
}

stop_vm() {
    local vm_name="${1:-$DEFAULT_VM_NAME}"
    local force="${2:-false}"
    
    log_info "Stopping VM: $vm_name"
    
    # Check current state
    local current_state
    current_state=$(get_vm_state "$vm_name" 2>/dev/null || echo "unknown")
    
    if [[ "$current_state" == "stopped" ]]; then
        log_info "VM is already stopped: $vm_name"
        return 0
    fi
    
    # Get VM PID
    local vm_pid
    if vm_pid=$(get_vm_pid "$vm_name"); then
        log_info "Found VM process: PID $vm_pid"
        
        if [[ "$force" == "true" ]]; then
            log_info "Force stopping VM..."
            kill -KILL "$vm_pid" 2>/dev/null
        else
            log_info "Gracefully stopping VM..."
            
            # Try graceful shutdown first
            kill -TERM "$vm_pid" 2>/dev/null
            
            # Helper function to check if process has stopped
            check_process_stopped() {
                local pid="$1"
                ! kill -0 "$pid" 2>/dev/null
            }
            
            # Use enhanced timeout handler for graceful shutdown
            if ! wait_with_timeout 30 1 check_process_stopped "Waiting for graceful VM shutdown" "$vm_pid"; then
                log_warning "Graceful shutdown timeout, force killing VM"
                kill -KILL "$vm_pid" 2>/dev/null || true
                sleep 2
                
                # Final verification with timeout
                if ! wait_with_timeout 5 1 check_process_stopped "Waiting for force kill completion" "$vm_pid"; then
                    log_error "Unable to terminate VM process even with SIGKILL"
                    return 1
                fi
            fi
        fi
        
        # Verify process is stopped
        if kill -0 "$vm_pid" 2>/dev/null; then
            log_error "Failed to stop VM process: PID $vm_pid"
            return 1
        fi
        
    else
        log_info "No running VM process found for: $vm_name"
    fi
    
    # Update state
    save_vm_state "$vm_name" "stopped" "VM stopped"
    
    log_success "VM stopped: $vm_name"
    return 0
}

cleanup_vm() {
    local vm_name="${1:-$DEFAULT_VM_NAME}"
    local remove_image="${2:-false}"
    
    log_info "Cleaning up VM: $vm_name"
    
    # Stop VM if running
    local current_state
    current_state=$(get_vm_state "$vm_name" 2>/dev/null || echo "unknown")
    
    if [[ "$current_state" == "running" || "$current_state" == "starting" ]]; then
        log_info "Stopping VM before cleanup..."
        stop_vm "$vm_name" "true"  # Force stop for cleanup
    fi
    
    # Clean up state files
    cleanup_vm_state "$vm_name"
    
    # Clean up log files
    local log_file
    log_file=$(get_vm_log_file "$vm_name")
    if [[ -f "$log_file" ]]; then
        rm -f "$log_file"
        log_info "Removed log file: $(basename "$log_file")"
    fi
    
    # Clean up monitor socket
    local monitor_file
    monitor_file=$(get_vm_monitor_file "$vm_name")
    if [[ -S "$monitor_file" ]]; then
        rm -f "$monitor_file"
        log_info "Removed monitor socket: $(basename "$monitor_file")"
    fi
    
    # Remove VM image if requested
    if [[ "$remove_image" == "true" ]]; then
        local image_file="${VM_IMAGE_DIR}/${vm_name}.qcow2"
        if [[ -f "$image_file" ]]; then
            rm -f "$image_file"
            log_info "Removed VM image: $(basename "$image_file")"
        fi
    fi
    
    log_success "VM cleanup completed: $vm_name"
    return 0
}

# ============================================================================
# VM STATUS AND MONITORING
# ============================================================================

get_vm_status() {
    local vm_name="${1:-$DEFAULT_VM_NAME}"
    local verbose="${2:-false}"
    
    local current_state
    current_state=$(get_vm_state "$vm_name" 2>/dev/null || echo "unknown")
    
    if [[ "$verbose" == "true" ]]; then
        log_info "VM Status Report for: $vm_name"
        log_info "  State: $current_state"
        
        local vm_pid
        if vm_pid=$(get_vm_pid "$vm_name" 2>/dev/null); then
            log_info "  PID: $vm_pid"
            
            # Get process details
            if ps -p "$vm_pid" &>/dev/null; then
                local cpu_usage memory_usage
                cpu_usage=$(ps -p "$vm_pid" -o %cpu --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
                memory_usage=$(ps -p "$vm_pid" -o %mem --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
                log_info "  CPU Usage: ${cpu_usage}%"
                log_info "  Memory Usage: ${memory_usage}%"
            fi
        else
            log_info "  PID: Not running"
        fi
        
        # Check log file
        local log_file
        log_file=$(get_vm_log_file "$vm_name")
        if [[ -f "$log_file" ]]; then
            local log_size
            log_size=$(wc -l < "$log_file" 2>/dev/null || echo "0")
            log_info "  Log Lines: $log_size"
            log_info "  Log File: $(basename "$log_file")"
        else
            log_info "  Log File: Not found"
        fi
        
        # State file info
        local state_file
        state_file=$(get_vm_state_file "$vm_name")
        if [[ -f "$state_file" ]]; then
            if command -v jq &> /dev/null; then
                local timestamp additional_info
                timestamp=$(jq -r '.timestamp' "$state_file" 2>/dev/null || echo "N/A")
                additional_info=$(jq -r '.additional_info' "$state_file" 2>/dev/null || echo "N/A")
                log_info "  Last Update: $timestamp"
                log_info "  Info: $additional_info"
            fi
        fi
        
    else
        echo "$current_state"
    fi
}

list_vms() {
    local verbose="${1:-false}"
    
    if [[ ! -d "$VM_STATE_DIR" ]]; then
        log_info "No VMs found (state directory does not exist)"
        return 0
    fi
    
    local vm_found=false
    
    for state_file in "$VM_STATE_DIR"/*.state; do
        if [[ -f "$state_file" ]]; then
            vm_found=true
            local vm_name
            vm_name=$(basename "$state_file" .state)
            
            if [[ "$verbose" == "true" ]]; then
                get_vm_status "$vm_name" "true"
                echo ""
            else
                local state
                state=$(get_vm_state "$vm_name")
                printf "%-20s %s\n" "$vm_name" "$state"
            fi
        fi
    done
    
    if [[ "$vm_found" == "false" ]]; then
        log_info "No VMs found"
    fi
}

# ============================================================================
# ERROR HANDLING AND RECOVERY
# ============================================================================

check_vm_health() {
    local vm_name="${1:-$DEFAULT_VM_NAME}"
    
    log_info "Checking VM health: $vm_name"
    
    local current_state
    current_state=$(get_vm_state "$vm_name" 2>/dev/null || echo "unknown")
    
    case "$current_state" in
        "running")
            # Check if process is actually running
            local vm_pid
            if vm_pid=$(get_vm_pid "$vm_name"); then
                if kill -0 "$vm_pid" 2>/dev/null; then
                    log_success "VM is healthy: process running"
                    return 0
                else
                    log_error "VM state mismatch: marked as running but process not found"
                    save_vm_state "$vm_name" "failed" "Process died unexpectedly"
                    return 1
                fi
            else
                log_error "VM marked as running but no PID file found"
                save_vm_state "$vm_name" "failed" "PID file missing"
                return 1
            fi
            ;;
        "stopped"|"failed")
            log_info "VM is not running (state: $current_state)"
            return 1
            ;;
        "unknown")
            log_info "VM state unknown (not created or cleaned up)"
            return 1
            ;;
        *)
            log_warning "VM in intermediate state: $current_state"
            return 1
            ;;
    esac
}

recover_vm() {
    local vm_name="${1:-$DEFAULT_VM_NAME}"
    local recovery_action="${2:-restart}"
    
    log_info "Recovering VM: $vm_name (action: $recovery_action)"
    
    case "$recovery_action" in
        "restart")
            stop_vm "$vm_name" "true"
            sleep 2
            start_vm "$vm_name"
            ;;
        "cleanup")
            cleanup_vm "$vm_name" "false"
            create_vm "$vm_name"
            ;;
        "recreate")
            cleanup_vm "$vm_name" "true"
            create_vm "$vm_name"
            start_vm "$vm_name"
            ;;
        *)
            log_error "Unknown recovery action: $recovery_action"
            return 1
            ;;
    esac
}

cleanup_orphaned_processes() {
    log_info "Cleaning up orphaned QEMU processes..."
    
    local orphaned_count=0
    
    # Find QEMU processes that might be orphaned
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local pid process_info
            pid=$(echo "$line" | awk '{print $1}')
            process_info=$(echo "$line" | cut -d' ' -f2-)
            
            # Check if this PID corresponds to any known VM
            local found_vm=false
            if [[ -d "$VM_STATE_DIR" ]]; then
                for pid_file in "$VM_STATE_DIR"/*.pid; do
                    if [[ -f "$pid_file" ]]; then
                        local known_pid
                        known_pid=$(cat "$pid_file" 2>/dev/null || echo "")
                        if [[ "$known_pid" == "$pid" ]]; then
                            found_vm=true
                            break
                        fi
                    fi
                done
            fi
            
            if [[ "$found_vm" == "false" ]]; then
                log_warning "Found orphaned QEMU process: PID $pid"
                log_info "Process: $process_info"
                
                # Ask for confirmation in interactive mode
                if [[ -t 0 ]]; then
                    read -p "Kill orphaned process $pid? (y/N): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        kill -TERM "$pid" 2>/dev/null && orphaned_count=$((orphaned_count + 1))
                    fi
                else
                    # In non-interactive mode, kill orphaned processes
                    kill -TERM "$pid" 2>/dev/null && orphaned_count=$((orphaned_count + 1))
                fi
            fi
        fi
    done < <(pgrep -fl qemu-system 2>/dev/null || true)
    
    if [[ $orphaned_count -gt 0 ]]; then
        log_success "Cleaned up $orphaned_count orphaned processes"
    else
        log_info "No orphaned processes found"
    fi
}

# ============================================================================
# MAIN FUNCTION AND COMMAND INTERFACE
# ============================================================================

usage() {
    cat << EOF
Usage: $0 <command> [vm_name] [options]

QEMU VM lifecycle management for USB/IP testing with environment awareness.

COMMANDS:
    create [vm_name] [force_recreate]     Create VM (default: $DEFAULT_VM_NAME)
    start [vm_name] [background]          Start VM (default: background=true)
    stop [vm_name] [force]                Stop VM (default: graceful shutdown)
    cleanup [vm_name] [remove_image]      Clean up VM (default: keep image)
    status [vm_name] [verbose]            Get VM status
    list [verbose]                        List all VMs
    health [vm_name]                      Check VM health
    recover [vm_name] [action]            Recover VM (restart|cleanup|recreate)
    cleanup-orphaned                     Clean up orphaned QEMU processes

EXAMPLES:
    # Basic lifecycle
    $0 create my-vm
    $0 start my-vm
    $0 stop my-vm
    $0 cleanup my-vm

    # Status and monitoring
    $0 status my-vm verbose
    $0 list verbose
    $0 health my-vm

    # Recovery operations
    $0 recover my-vm restart
    $0 cleanup-orphaned

ENVIRONMENT:
    TEST_ENVIRONMENT=development|ci|production    Set test environment
    Current environment: $TEST_ENVIRONMENT

FILES:
    Config: $CONFIG_FILE
    State:  $VM_STATE_DIR/
    Logs:   $VM_LOG_DIR/
    Images: $VM_IMAGE_DIR/

EOF
}

main() {
    local command="${1:-}"
    
    # Validate command is provided
    if [[ -z "$command" ]]; then
        log_error "No command specified"
        usage
        exit 1
    fi
    
    # Validate VM name if provided
    local vm_name="${2:-$DEFAULT_VM_NAME}"
    if [[ ! "$vm_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        handle_critical_error "Invalid VM name: '$vm_name'. Only alphanumeric characters, underscores, and hyphens are allowed."
    fi
    
    case "$command" in
        "create")
            if ! create_vm "$vm_name" "${3:-false}"; then
                log_error "Failed to create VM: $vm_name"
                exit 1
            fi
            ;;
        "start")
            if ! start_vm "$vm_name" "${3:-true}"; then
                log_error "Failed to start VM: $vm_name"
                exit 1
            fi
            ;;
        "stop")
            if ! stop_vm "$vm_name" "${3:-false}"; then
                log_error "Failed to stop VM: $vm_name"
                exit 1
            fi
            ;;
        "cleanup")
            if ! cleanup_vm "$vm_name" "${3:-false}"; then
                log_error "Failed to cleanup VM: $vm_name"
                exit 1
            fi
            ;;
        "status")
            get_vm_status "${2:-$DEFAULT_VM_NAME}" "${3:-false}"
            ;;
        "list")
            list_vms "${2:-false}"
            ;;
        "health")
            check_vm_health "${2:-$DEFAULT_VM_NAME}"
            ;;
        "recover")
            recover_vm "${2:-$DEFAULT_VM_NAME}" "${3:-restart}"
            ;;
        "cleanup-orphaned")
            cleanup_orphaned_processes
            ;;
        "-h"|"--help"|"help"|"")
            usage
            exit 0
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi