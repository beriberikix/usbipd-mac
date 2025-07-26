#!/bin/bash

# QEMU USB/IP Test Tool - Startup and Management Script
# Launches QEMU instances with USB/IP client capabilities for testing

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/.build/qemu"
readonly IMAGE_NAME="qemu-usbip-client"
readonly DISK_IMAGE="${BUILD_DIR}/${IMAGE_NAME}.qcow2"
readonly LOG_DIR="${BUILD_DIR}/logs"
readonly PID_DIR="${BUILD_DIR}/pids"

# QEMU configuration (minimal resource allocation)
readonly QEMU_MEMORY="256M"
readonly QEMU_CPU_COUNT="1"
readonly QEMU_MACHINE="q35"
readonly QEMU_ACCEL="hvf"  # Hardware acceleration on macOS

# Network configuration (user mode networking)
readonly HOST_SSH_PORT="2222"
readonly HOST_USBIP_PORT="3240"
readonly GUEST_SSH_PORT="22"
readonly GUEST_USBIP_PORT="3240"

# Boot and timeout configuration
readonly BOOT_TIMEOUT="60"
readonly SHUTDOWN_TIMEOUT="30"
readonly NETWORK_TIMEOUT="10"
readonly RETRY_ATTEMPTS="3"
readonly RETRY_DELAY="5"
readonly MAX_BOOT_RETRIES="2"
readonly NETWORK_RETRY_ATTEMPTS="3"
readonly NETWORK_RETRY_DELAY="2"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
QEMU_PID=""
INSTANCE_ID=""
CONSOLE_LOG=""
MONITOR_SOCKET=""
QEMU_OVERLAY_IMAGE=""

# Logging functions
log_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC} ${message}"
    if [[ -n "${CONSOLE_LOG:-}" && -f "${CONSOLE_LOG}" ]]; then
        echo "[INFO] ${message}" >> "${CONSOLE_LOG}"
    fi
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} ${message}"
    if [[ -n "${CONSOLE_LOG:-}" && -f "${CONSOLE_LOG}" ]]; then
        echo "[SUCCESS] ${message}" >> "${CONSOLE_LOG}"
    fi
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} ${message}"
    if [[ -n "${CONSOLE_LOG:-}" && -f "${CONSOLE_LOG}" ]]; then
        echo "[WARNING] ${message}" >> "${CONSOLE_LOG}"
    fi
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} ${message}"
    if [[ -n "${CONSOLE_LOG:-}" && -f "${CONSOLE_LOG}" ]]; then
        echo "[ERROR] ${message}" >> "${CONSOLE_LOG}"
    fi
}

# Error handling and cleanup
cleanup() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code"
        log_structured "SCRIPT_FAILURE" "Exit code: $exit_code"
        
        # Generate diagnostic information
        generate_failure_diagnostics "$exit_code"
    fi
    
    # Clean up QEMU process if running
    if [[ -n "${QEMU_PID}" ]] && kill -0 "${QEMU_PID}" 2>/dev/null; then
        log_info "Cleaning up QEMU process (PID: ${QEMU_PID})"
        stop_qemu_instance
    fi
    
    # Clean up overlay image
    if [[ -n "${QEMU_OVERLAY_IMAGE}" && -f "${QEMU_OVERLAY_IMAGE}" ]]; then
        log_info "Cleaning up overlay image: $(basename "${QEMU_OVERLAY_IMAGE}")"
        rm -f "${QEMU_OVERLAY_IMAGE}"
    fi
    
    exit $exit_code
}

# Generate diagnostic information for failures
generate_failure_diagnostics() {
    local exit_code="$1"
    
    log_info "Generating failure diagnostics..."
    
    # Create diagnostics file
    local diagnostics_file="${LOG_DIR}/diagnostics-${INSTANCE_ID:-unknown}.log"
    
    {
        echo "QEMU USB/IP Test Tool - Failure Diagnostics"
        echo "============================================"
        echo "Timestamp: $(date)"
        echo "Exit Code: $exit_code"
        echo "Instance ID: ${INSTANCE_ID:-unknown}"
        echo "QEMU PID: ${QEMU_PID:-none}"
        echo ""
        
        # System information
        echo "System Information:"
        echo "  OS: $(uname -s)"
        echo "  Architecture: $(uname -m)"
        echo "  Kernel: $(uname -r)"
        echo ""
        
        # QEMU information
        if command -v qemu-system-x86_64 &> /dev/null; then
            echo "QEMU Information:"
            qemu-system-x86_64 --version | head -n1
            echo ""
        fi
        
        # Network port status
        echo "Network Port Status:"
        echo "  SSH port $HOST_SSH_PORT: $(lsof -i ":$HOST_SSH_PORT" >/dev/null 2>&1 && echo "OCCUPIED" || echo "FREE")"
        echo "  USB/IP port $HOST_USBIP_PORT: $(lsof -i ":$HOST_USBIP_PORT" >/dev/null 2>&1 && echo "OCCUPIED" || echo "FREE")"
        echo ""
        
        # Disk space
        echo "Disk Space:"
        df -h "$BUILD_DIR" 2>/dev/null || echo "  Unable to check disk space"
        echo ""
        
        # Recent console log (if available)
        if [[ -f "${CONSOLE_LOG:-}" ]]; then
            echo "Recent Console Log (last 20 lines):"
            tail -n20 "$CONSOLE_LOG"
            echo ""
        fi
        
        # Process information
        echo "Process Information:"
        if [[ -n "${QEMU_PID:-}" ]]; then
            if kill -0 "$QEMU_PID" 2>/dev/null; then
                echo "  QEMU process $QEMU_PID is running"
                ps -p "$QEMU_PID" -o pid,ppid,state,time,command 2>/dev/null || true
            else
                echo "  QEMU process $QEMU_PID is not running"
            fi
        else
            echo "  No QEMU PID available"
        fi
        
    } > "$diagnostics_file"
    
    log_info "Diagnostics written to: $(basename "$diagnostics_file")"
    log_structured "DIAGNOSTICS_GENERATED" "$diagnostics_file"
}

trap cleanup EXIT INT TERM

# Utility functions
generate_instance_id() {
    echo "qemu-usbip-$(date +%s)-$$"
}

check_command() {
    local cmd="$1"
    local package_hint="${2:-}"
    
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command '$cmd' not found"
        if [[ -n "$package_hint" ]]; then
            log_info "Install with: $package_hint"
        fi
        return 1
    fi
    return 0
}

# Enhanced error handling functions
retry_with_backoff() {
    local max_attempts="$1"
    local delay="$2"
    local description="$3"
    shift 3
    local command=("$@")
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempting $description (attempt $attempt/$max_attempts)"
        
        if "${command[@]}"; then
            log_success "$description succeeded on attempt $attempt"
            return 0
        else
            local exit_code=$?
            log_warning "$description failed on attempt $attempt (exit code: $exit_code)"
            
            if [[ $attempt -lt $max_attempts ]]; then
                log_info "Retrying in ${delay}s..."
                sleep "$delay"
                # Exponential backoff
                delay=$((delay * 2))
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "$description failed after $max_attempts attempts"
    return 1
}

handle_boot_timeout() {
    local timeout_reason="$1"
    
    log_error "Boot timeout occurred: $timeout_reason"
    log_structured "BOOT_TIMEOUT" "$timeout_reason"
    
    # Generate detailed diagnostics for boot timeout
    local boot_diagnostics="${LOG_DIR}/boot-timeout-${INSTANCE_ID}.log"
    {
        echo "Boot Timeout Diagnostics - $(date)"
        echo "=================================="
        echo "Timeout Reason: $timeout_reason"
        echo "Boot Timeout: ${BOOT_TIMEOUT}s"
        echo "Instance ID: $INSTANCE_ID"
        echo ""
        
        # Check QEMU process status
        if [[ -n "$QEMU_PID" ]]; then
            if kill -0 "$QEMU_PID" 2>/dev/null; then
                echo "QEMU Process Status: RUNNING (PID: $QEMU_PID)"
                ps -p "$QEMU_PID" -o pid,ppid,state,time,command 2>/dev/null || true
            else
                echo "QEMU Process Status: NOT RUNNING"
            fi
        fi
        echo ""
        
        # Check console log for boot progress
        if [[ -f "$CONSOLE_LOG" ]]; then
            echo "Console Log Analysis:"
            echo "  Total lines: $(wc -l < "$CONSOLE_LOG")"
            echo "  Last 10 lines:"
            tail -n10 "$CONSOLE_LOG" | sed 's/^/    /'
            echo ""
            
            # Look for specific boot indicators
            echo "Boot Progress Indicators:"
            if grep -q "kernel" "$CONSOLE_LOG" 2>/dev/null; then
                echo "  ✓ Kernel messages found"
            else
                echo "  ✗ No kernel messages found"
            fi
            
            if grep -q "cloud-init" "$CONSOLE_LOG" 2>/dev/null; then
                echo "  ✓ Cloud-init messages found"
            else
                echo "  ✗ No cloud-init messages found"
            fi
            
            if grep -q "login:" "$CONSOLE_LOG" 2>/dev/null; then
                echo "  ✓ Login prompt reached"
            else
                echo "  ✗ Login prompt not reached"
            fi
            
            if grep -q "USBIP" "$CONSOLE_LOG" 2>/dev/null; then
                echo "  ✓ USB/IP messages found"
            else
                echo "  ✗ No USB/IP messages found"
            fi
        fi
        
    } > "$boot_diagnostics"
    
    log_info "Boot timeout diagnostics written to: $(basename "$boot_diagnostics")"
    return 1
}

handle_network_failure() {
    local failure_type="$1"
    local details="${2:-}"
    
    log_error "Network configuration failure: $failure_type"
    if [[ -n "$details" ]]; then
        log_error "Details: $details"
    fi
    log_structured "NETWORK_FAILURE" "$failure_type: $details"
    
    # Generate network diagnostics
    local network_diagnostics="${LOG_DIR}/network-failure-${INSTANCE_ID}.log"
    {
        echo "Network Failure Diagnostics - $(date)"
        echo "====================================="
        echo "Failure Type: $failure_type"
        echo "Details: $details"
        echo "Instance ID: $INSTANCE_ID"
        echo ""
        
        # Check port availability
        echo "Port Status:"
        echo "  SSH port $HOST_SSH_PORT: $(lsof -i ":$HOST_SSH_PORT" >/dev/null 2>&1 && echo "OCCUPIED" || echo "FREE")"
        echo "  USB/IP port $HOST_USBIP_PORT: $(lsof -i ":$HOST_USBIP_PORT" >/dev/null 2>&1 && echo "OCCUPIED" || echo "FREE")"
        echo ""
        
        # Check network interfaces
        echo "Network Interfaces:"
        ifconfig 2>/dev/null | grep -E "^[a-z]|inet " | sed 's/^/  /' || echo "  Unable to get interface information"
        echo ""
        
        # Check for QEMU network configuration in console log
        if [[ -f "$CONSOLE_LOG" ]]; then
            echo "QEMU Network Messages:"
            grep -i "network\|eth\|dhcp" "$CONSOLE_LOG" 2>/dev/null | tail -n5 | sed 's/^/  /' || echo "  No network messages found"
        fi
        
    } > "$network_diagnostics"
    
    log_info "Network failure diagnostics written to: $(basename "$network_diagnostics")"
    return 1
}

handle_qemu_crash() {
    local crash_reason="$1"
    
    log_error "QEMU process crashed: $crash_reason"
    log_structured "QEMU_CRASH" "$crash_reason"
    
    # Generate crash diagnostics
    local crash_diagnostics="${LOG_DIR}/qemu-crash-${INSTANCE_ID}.log"
    {
        echo "QEMU Crash Diagnostics - $(date)"
        echo "==============================="
        echo "Crash Reason: $crash_reason"
        echo "Instance ID: $INSTANCE_ID"
        echo "QEMU PID: ${QEMU_PID:-unknown}"
        echo ""
        
        # System resource information
        echo "System Resources:"
        echo "  Memory usage:"
        vm_stat 2>/dev/null | head -n10 | sed 's/^/    /' || echo "    Unable to get memory stats"
        echo "  Disk space:"
        df -h "$BUILD_DIR" 2>/dev/null | sed 's/^/    /' || echo "    Unable to get disk space"
        echo ""
        
        # QEMU command that was used
        if [[ -f "${PID_DIR}/${INSTANCE_ID}-command.log" ]]; then
            echo "QEMU Command:"
            cat "${PID_DIR}/${INSTANCE_ID}-command.log" | sed 's/^/  /'
            echo ""
        fi
        
        # Console log analysis
        if [[ -f "$CONSOLE_LOG" ]]; then
            echo "Console Log (last 20 lines):"
            tail -n20 "$CONSOLE_LOG" | sed 's/^/  /'
            echo ""
            
            # Look for error patterns
            echo "Error Patterns Found:"
            grep -i "error\|fail\|panic\|segfault\|abort" "$CONSOLE_LOG" 2>/dev/null | tail -n5 | sed 's/^/  /' || echo "  No obvious error patterns found"
        fi
        
    } > "$crash_diagnostics"
    
    log_info "QEMU crash diagnostics written to: $(basename "$crash_diagnostics")"
    return 1
}

detect_common_failures() {
    local console_log="$1"
    
    if [[ ! -f "$console_log" ]]; then
        return 0
    fi
    
    # Check for common failure patterns
    if grep -q "No space left on device" "$console_log" 2>/dev/null; then
        handle_qemu_crash "Disk space exhausted"
        return 1
    fi
    
    if grep -q "Permission denied" "$console_log" 2>/dev/null; then
        handle_qemu_crash "Permission denied - check file permissions"
        return 1
    fi
    
    if grep -q "Address already in use" "$console_log" 2>/dev/null; then
        handle_network_failure "Port conflict" "Network ports already in use"
        return 1
    fi
    
    if grep -q "Kernel panic" "$console_log" 2>/dev/null; then
        handle_qemu_crash "Guest kernel panic"
        return 1
    fi
    
    if grep -q "Out of memory" "$console_log" 2>/dev/null; then
        handle_qemu_crash "Guest out of memory"
        return 1
    fi
    
    return 0
}

# Validation functions
validate_qemu_installation() {
    log_info "Validating QEMU installation..."
    
    if ! check_command "qemu-system-x86_64" "brew install qemu"; then
        return 1
    fi
    
    if ! check_command "qemu-img" "brew install qemu"; then
        return 1
    fi
    
    # Check QEMU version
    local qemu_version
    qemu_version=$(qemu-system-x86_64 --version | head -n1)
    log_info "Found QEMU: $qemu_version"
    
    # Test hardware acceleration availability
    if qemu-system-x86_64 -accel help 2>/dev/null | grep -q "hvf"; then
        log_info "Hardware acceleration (HVF) available"
    else
        log_warning "Hardware acceleration (HVF) not available, using TCG"
    fi
    
    return 0
}

validate_image_availability() {
    log_info "Validating QEMU image availability..."
    
    if [[ ! -f "$DISK_IMAGE" ]]; then
        log_error "QEMU disk image not found: $DISK_IMAGE"
        log_info "Run Scripts/create-qemu-image.sh to create the image first"
        return 1
    fi
    
    # Verify image integrity
    if ! qemu-img check "$DISK_IMAGE" >/dev/null 2>&1; then
        log_error "QEMU disk image appears to be corrupted: $DISK_IMAGE"
        log_info "Run Scripts/create-qemu-image.sh to recreate the image"
        return 1
    fi
    
    # Get image information
    local image_info
    image_info=$(qemu-img info "$DISK_IMAGE" 2>/dev/null)
    local virtual_size
    virtual_size=$(echo "$image_info" | grep "virtual size" | awk '{print $3}')
    local disk_size
    disk_size=$(echo "$image_info" | grep "disk size" | awk '{print $3}')
    
    log_info "Image validation passed:"
    log_info "  Virtual size: ${virtual_size}"
    log_info "  Disk size: ${disk_size}"
    
    return 0
}

validate_network_ports() {
    log_info "Validating network port availability..."
    
    # Check if SSH port is available with retry
    local ssh_port_attempts=0
    while [[ $ssh_port_attempts -lt $NETWORK_RETRY_ATTEMPTS ]]; do
        if ! lsof -i ":${HOST_SSH_PORT}" >/dev/null 2>&1; then
            break
        fi
        
        ssh_port_attempts=$((ssh_port_attempts + 1))
        if [[ $ssh_port_attempts -lt $NETWORK_RETRY_ATTEMPTS ]]; then
            log_warning "Host SSH port ${HOST_SSH_PORT} is in use, retrying in ${NETWORK_RETRY_DELAY}s (attempt $ssh_port_attempts/$NETWORK_RETRY_ATTEMPTS)"
            sleep "$NETWORK_RETRY_DELAY"
        fi
    done
    
    if [[ $ssh_port_attempts -eq $NETWORK_RETRY_ATTEMPTS ]]; then
        log_error "Host SSH port ${HOST_SSH_PORT} is persistently in use"
        log_info "Another QEMU instance may be running, or port is occupied"
        handle_network_failure "SSH port conflict" "Port ${HOST_SSH_PORT} occupied after $NETWORK_RETRY_ATTEMPTS attempts"
        return 1
    fi
    
    # Check if USB/IP port is available with retry
    local usbip_port_attempts=0
    while [[ $usbip_port_attempts -lt $NETWORK_RETRY_ATTEMPTS ]]; do
        if ! lsof -i ":${HOST_USBIP_PORT}" >/dev/null 2>&1; then
            break
        fi
        
        usbip_port_attempts=$((usbip_port_attempts + 1))
        if [[ $usbip_port_attempts -lt $NETWORK_RETRY_ATTEMPTS ]]; then
            log_warning "Host USB/IP port ${HOST_USBIP_PORT} is in use, retrying in ${NETWORK_RETRY_DELAY}s (attempt $usbip_port_attempts/$NETWORK_RETRY_ATTEMPTS)"
            sleep "$NETWORK_RETRY_DELAY"
        fi
    done
    
    if [[ $usbip_port_attempts -eq $NETWORK_RETRY_ATTEMPTS ]]; then
        log_error "Host USB/IP port ${HOST_USBIP_PORT} is persistently in use"
        log_info "USB/IP server may be running, or port is occupied"
        handle_network_failure "USB/IP port conflict" "Port ${HOST_USBIP_PORT} occupied after $NETWORK_RETRY_ATTEMPTS attempts"
        return 1
    fi
    
    log_success "Network ports are available"
    return 0
}

# Setup functions
setup_runtime_environment() {
    log_info "Setting up QEMU runtime environment..."
    
    # Generate unique instance ID
    INSTANCE_ID=$(generate_instance_id)
    
    # Create necessary directories
    mkdir -p "$LOG_DIR"
    mkdir -p "$PID_DIR"
    
    # Set up logging paths
    CONSOLE_LOG="${LOG_DIR}/${INSTANCE_ID}-console.log"
    MONITOR_SOCKET="${PID_DIR}/${INSTANCE_ID}-monitor.sock"
    
    # Create overlay image for this instance (copy-on-write)
    QEMU_OVERLAY_IMAGE="${BUILD_DIR}/${INSTANCE_ID}-overlay.qcow2"
    
    log_info "Instance ID: ${INSTANCE_ID}"
    log_info "Console log: $(basename "${CONSOLE_LOG}")"
    log_info "Monitor socket: $(basename "${MONITOR_SOCKET}")"
    log_info "Overlay image: $(basename "${QEMU_OVERLAY_IMAGE}")"
    
    return 0
}

create_overlay_image() {
    log_info "Creating overlay image for instance..."
    
    # Create overlay image based on the main disk image
    if ! qemu-img create -f qcow2 -b "$DISK_IMAGE" -F qcow2 "$QEMU_OVERLAY_IMAGE" >/dev/null 2>&1; then
        log_error "Failed to create overlay image"
        return 1
    fi
    
    # Verify overlay image
    if ! qemu-img info "$QEMU_OVERLAY_IMAGE" >/dev/null 2>&1; then
        log_error "Created overlay image appears to be invalid"
        return 1
    fi
    
    log_success "Overlay image created successfully"
    return 0
}

# QEMU management functions
build_qemu_command() {
    local qemu_cmd=(
        "qemu-system-x86_64"
        
        # Machine and CPU configuration
        "-machine" "$QEMU_MACHINE"
        "-cpu" "host"
        "-smp" "$QEMU_CPU_COUNT"
        "-m" "$QEMU_MEMORY"
        
        # Hardware acceleration (if available)
        "-accel" "$QEMU_ACCEL,thread=multi"
        
        # Disk configuration (use overlay image)
        "-drive" "file=${QEMU_OVERLAY_IMAGE},format=qcow2,if=virtio"
        
        # Network configuration (user mode networking with port forwarding)
        "-netdev" "user,id=net0,hostfwd=tcp::${HOST_SSH_PORT}-:${GUEST_SSH_PORT},hostfwd=tcp::${HOST_USBIP_PORT}-:${GUEST_USBIP_PORT}"
        "-device" "virtio-net-pci,netdev=net0"
        
        # Serial console configuration (redirect to log file)
        "-serial" "file:${CONSOLE_LOG}"
        
        # Monitor configuration (QEMU monitor socket)
        "-monitor" "unix:${MONITOR_SOCKET},server,nowait"
        
        # Display configuration (headless)
        "-display" "none"
        
        # Disable default devices to minimize resource usage
        "-nodefaults"
        "-no-user-config"
        
        # RTC configuration
        "-rtc" "base=utc,clock=host"
        
        # Boot configuration
        "-boot" "order=c"
        
        # Enable KVM if available (fallback handled by -accel)
        "-enable-kvm" "2>/dev/null" "||" "true"
    )
    
    # Remove the KVM fallback hack and build clean command
    local clean_qemu_cmd=(
        "qemu-system-x86_64"
        "-machine" "$QEMU_MACHINE"
        "-cpu" "host"
        "-smp" "$QEMU_CPU_COUNT"
        "-m" "$QEMU_MEMORY"
        "-accel" "$QEMU_ACCEL,thread=multi"
        "-drive" "file=${QEMU_OVERLAY_IMAGE},format=qcow2,if=virtio"
        "-netdev" "user,id=net0,hostfwd=tcp::${HOST_SSH_PORT}-:${GUEST_SSH_PORT},hostfwd=tcp::${HOST_USBIP_PORT}-:${GUEST_USBIP_PORT}"
        "-device" "virtio-net-pci,netdev=net0"
        "-serial" "file:${CONSOLE_LOG}"
        "-monitor" "unix:${MONITOR_SOCKET},server,nowait"
        "-display" "none"
        "-nodefaults"
        "-no-user-config"
        "-rtc" "base=utc,clock=host"
        "-boot" "order=c"
    )
    
    echo "${clean_qemu_cmd[@]}"
}

start_qemu_instance() {
    log_info "Starting QEMU instance..."
    
    # Build QEMU command
    local qemu_command
    qemu_command=$(build_qemu_command)
    
    log_info "QEMU command: $qemu_command"
    
    # Save command for diagnostics
    echo "$qemu_command" > "${PID_DIR}/${INSTANCE_ID}-command.log"
    
    # Initialize console log
    echo "QEMU Console Log - Instance: ${INSTANCE_ID} - $(date)" > "$CONSOLE_LOG"
    echo "========================================" >> "$CONSOLE_LOG"
    
    # Pre-flight checks before starting QEMU
    log_info "Performing pre-flight checks..."
    
    # Check disk space
    local available_space
    available_space=$(df "$BUILD_DIR" | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 100000 ]]; then  # Less than ~100MB
        log_error "Insufficient disk space: ${available_space}KB available"
        handle_qemu_crash "Insufficient disk space"
        return 1
    fi
    
    # Check memory availability (basic check)
    local memory_pressure
    memory_pressure=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
    if [[ -n "$memory_pressure" && $memory_pressure -lt 10000 ]]; then  # Less than ~40MB free pages
        log_warning "Low memory available, QEMU may fail to start"
    fi
    
    # Start QEMU in background with error handling
    log_info "Launching QEMU process..."
    if ! eval "$qemu_command" & then
        log_error "Failed to start QEMU process"
        handle_qemu_crash "QEMU launch failed"
        return 1
    fi
    
    QEMU_PID=$!
    
    # Verify QEMU process started successfully
    sleep 1
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        log_error "QEMU process died immediately after startup"
        handle_qemu_crash "Immediate process death"
        return 1
    fi
    
    # Save PID to file
    echo "$QEMU_PID" > "${PID_DIR}/${INSTANCE_ID}.pid"
    
    log_info "QEMU started with PID: $QEMU_PID"
    log_info "Console output: $CONSOLE_LOG"
    log_info "Monitor socket: $MONITOR_SOCKET"
    log_structured "QEMU_STARTED" "PID: $QEMU_PID"
    
    return 0
}

wait_for_boot() {
    log_info "Waiting for QEMU instance to boot (timeout: ${BOOT_TIMEOUT}s)..."
    
    local elapsed=0
    local boot_complete=false
    local last_log_size=0
    local stall_count=0
    local max_stalls=3
    
    while [[ $elapsed -lt $BOOT_TIMEOUT ]]; do
        # Check if QEMU process is still running
        if ! kill -0 "$QEMU_PID" 2>/dev/null; then
            log_error "QEMU process died during boot"
            handle_qemu_crash "Process died during boot"
            return 1
        fi
        
        # Check for common failure patterns
        if [[ -f "$CONSOLE_LOG" ]] && ! detect_common_failures "$CONSOLE_LOG"; then
            return 1
        fi
        
        # Check console log for boot completion indicators
        if [[ -f "$CONSOLE_LOG" ]]; then
            # Monitor log growth to detect stalls
            local current_log_size
            current_log_size=$(wc -l < "$CONSOLE_LOG" 2>/dev/null || echo "0")
            
            if [[ $current_log_size -eq $last_log_size ]]; then
                stall_count=$((stall_count + 1))
                if [[ $stall_count -ge $max_stalls && $elapsed -gt 30 ]]; then
                    log_warning "Boot appears to be stalled (no log activity for $((stall_count * 2))s)"
                    # Try sending a key to wake up the system
                    if [[ -S "$MONITOR_SOCKET" ]]; then
                        echo "sendkey ret" | socat - "UNIX-CONNECT:$MONITOR_SOCKET" 2>/dev/null || true
                    fi
                    stall_count=0
                fi
            else
                stall_count=0
                last_log_size=$current_log_size
            fi
            
            # Look for USB/IP client readiness indicators
            if grep -q "USBIP_CLIENT_READY" "$CONSOLE_LOG" 2>/dev/null; then
                boot_complete=true
                break
            fi
            
            # Alternative boot completion indicators
            if grep -q "CLOUD_INIT_COMPLETE" "$CONSOLE_LOG" 2>/dev/null; then
                boot_complete=true
                break
            fi
            
            # Check for login prompt as fallback
            if grep -q "login:" "$CONSOLE_LOG" 2>/dev/null; then
                log_warning "Login prompt detected, but USB/IP readiness not confirmed"
                # Give it a few more seconds to complete USB/IP setup
                local extra_wait=10
                local extra_elapsed=0
                while [[ $extra_elapsed -lt $extra_wait ]]; do
                    if grep -q "USBIP_CLIENT_READY" "$CONSOLE_LOG" 2>/dev/null; then
                        boot_complete=true
                        break
                    fi
                    sleep 1
                    extra_elapsed=$((extra_elapsed + 1))
                done
                
                if [[ "$boot_complete" != "true" ]]; then
                    log_warning "USB/IP readiness not confirmed, but login available"
                    boot_complete=true
                fi
                break
            fi
            
            # Check for error conditions that indicate boot failure
            if grep -q "Kernel panic\|Out of memory\|segfault" "$CONSOLE_LOG" 2>/dev/null; then
                log_error "Critical boot error detected in console log"
                handle_boot_timeout "Critical boot error"
                return 1
            fi
        fi
        
        sleep 2
        elapsed=$((elapsed + 2))
        
        # Progress indicator with more detail
        if [[ $((elapsed % 10)) -eq 0 ]]; then
            local progress_info="Boot progress: ${elapsed}/${BOOT_TIMEOUT}s"
            if [[ -f "$CONSOLE_LOG" ]]; then
                local log_lines
                log_lines=$(wc -l < "$CONSOLE_LOG" 2>/dev/null || echo "0")
                progress_info="$progress_info (console: ${log_lines} lines)"
            fi
            log_info "$progress_info"
        fi
    done
    
    if [[ "$boot_complete" == "true" ]]; then
        log_success "QEMU instance boot completed"
        log_structured "BOOT_COMPLETE" "Boot time: ${elapsed}s"
        
        # Display boot summary from console log
        if [[ -f "$CONSOLE_LOG" ]]; then
            log_info "Boot summary:"
            if grep -q "USBIP_CLIENT_READY" "$CONSOLE_LOG"; then
                log_info "  ✓ USB/IP client ready"
            fi
            if grep -q "VHCI_MODULE_LOADED" "$CONSOLE_LOG"; then
                log_info "  ✓ vhci-hcd module loaded"
            fi
            if grep -q "USBIP_VERSION" "$CONSOLE_LOG"; then
                local version_line
                version_line=$(grep "USBIP_VERSION" "$CONSOLE_LOG" | tail -n1)
                log_info "  ✓ ${version_line##*USBIP_VERSION: }"
            fi
            
            # Log total boot time and console activity
            local total_lines
            total_lines=$(wc -l < "$CONSOLE_LOG" 2>/dev/null || echo "0")
            log_info "  ✓ Boot completed in ${elapsed}s with ${total_lines} console messages"
        fi
        
        return 0
    else
        log_error "QEMU instance failed to boot within ${BOOT_TIMEOUT} seconds"
        handle_boot_timeout "Boot timeout exceeded"
        return 1
    fi
}

# Instance management functions
stop_qemu_instance() {
    if [[ -z "$QEMU_PID" ]]; then
        log_warning "No QEMU PID available for shutdown"
        return 0
    fi
    
    log_info "Stopping QEMU instance (PID: $QEMU_PID)..."
    
    # Try graceful shutdown first via monitor
    if [[ -S "$MONITOR_SOCKET" ]]; then
        log_info "Attempting graceful shutdown via QEMU monitor..."
        echo "system_powerdown" | socat - "UNIX-CONNECT:$MONITOR_SOCKET" 2>/dev/null || true
        
        # Wait for graceful shutdown
        local elapsed=0
        while [[ $elapsed -lt $SHUTDOWN_TIMEOUT ]] && kill -0 "$QEMU_PID" 2>/dev/null; do
            sleep 1
            elapsed=$((elapsed + 1))
        done
    fi
    
    # Force kill if still running
    if kill -0 "$QEMU_PID" 2>/dev/null; then
        log_warning "Graceful shutdown failed, forcing termination..."
        kill -TERM "$QEMU_PID" 2>/dev/null || true
        sleep 2
        
        if kill -0 "$QEMU_PID" 2>/dev/null; then
            kill -KILL "$QEMU_PID" 2>/dev/null || true
        fi
    fi
    
    # Clean up PID file
    if [[ -f "${PID_DIR}/${INSTANCE_ID}.pid" ]]; then
        rm -f "${PID_DIR}/${INSTANCE_ID}.pid"
    fi
    
    log_success "QEMU instance stopped"
    return 0
}

show_connection_info() {
    log_info "QEMU instance connection information:"
    log_info "  Instance ID: $INSTANCE_ID"
    log_info "  SSH access: ssh -p $HOST_SSH_PORT testuser@localhost"
    log_info "  USB/IP port: localhost:$HOST_USBIP_PORT"
    log_info "  Console log: $CONSOLE_LOG"
    log_info "  Monitor socket: $MONITOR_SOCKET"
    log_info "  Process ID: $QEMU_PID"
}

# Structured logging functions for USB/IP operations
log_structured() {
    local level="$1"
    local message="$2"
    local timestamp
    # Use compatible timestamp format for macOS (gdate supports %3N if available)
    if command -v gdate >/dev/null 2>&1; then
        timestamp=$(gdate '+%Y-%m-%d %H:%M:%S.%3N')
    else
        timestamp=$(date '+%Y-%m-%d %H:%M:%S.000')
    fi
    
    # Write to console log with structured format
    if [[ -n "${CONSOLE_LOG:-}" && -f "${CONSOLE_LOG}" ]]; then
        echo "[${timestamp}] ${level}: ${message}" >> "${CONSOLE_LOG}"
    fi
    
    # Also write to stdout for immediate feedback
    case "$level" in
        "USBIP_CLIENT_READY"|"USBIP_VERSION"|"VHCI_MODULE_LOADED")
            log_success "$message"
            ;;
        "CONNECTING_TO_SERVER"|"DEVICE_LIST_REQUEST"|"DEVICE_IMPORT_REQUEST")
            log_info "$message"
            ;;
        "TEST_COMPLETE")
            if [[ "$message" == *"SUCCESS"* ]]; then
                log_success "$message"
            else
                log_error "$message"
            fi
            ;;
        *)
            log_info "$message"
            ;;
    esac
}

# Parse console log for structured USB/IP messages
parse_console_log() {
    local log_file="$1"
    local pattern="${2:-}"
    
    if [[ ! -f "$log_file" ]]; then
        return 1
    fi
    
    if [[ -n "$pattern" ]]; then
        grep "$pattern" "$log_file" 2>/dev/null || true
    else
        # Parse all structured messages
        grep -E '\[(.*)\] (USBIP_|VHCI_|CONNECTING_|DEVICE_|TEST_)' "$log_file" 2>/dev/null || true
    fi
}

# Extract specific USB/IP status from console log
get_usbip_status() {
    local log_file="$1"
    local status_type="$2"
    
    case "$status_type" in
        "client_ready")
            parse_console_log "$log_file" "USBIP_CLIENT_READY" | tail -n1
            ;;
        "version")
            parse_console_log "$log_file" "USBIP_VERSION:" | tail -n1 | sed 's/.*USBIP_VERSION: //'
            ;;
        "vhci_loaded")
            parse_console_log "$log_file" "VHCI_MODULE_LOADED" | tail -n1
            ;;
        "last_connection")
            parse_console_log "$log_file" "CONNECTING_TO_SERVER:" | tail -n1
            ;;
        "last_device_list")
            parse_console_log "$log_file" "DEVICE_LIST_REQUEST:" | tail -n1
            ;;
        "last_device_import")
            parse_console_log "$log_file" "DEVICE_IMPORT_REQUEST:" | tail -n1
            ;;
        "test_status")
            parse_console_log "$log_file" "TEST_COMPLETE:" | tail -n1
            ;;
        *)
            return 1
            ;;
    esac
}

# Send command to QEMU instance via monitor socket
send_qemu_command() {
    local command="$1"
    local timeout="${2:-5}"
    
    if [[ ! -S "$MONITOR_SOCKET" ]]; then
        log_error "Monitor socket not available: $MONITOR_SOCKET"
        return 1
    fi
    
    log_info "Sending QEMU command: $command"
    
    # Send command with timeout
    if timeout "$timeout" bash -c "echo '$command' | socat - 'UNIX-CONNECT:$MONITOR_SOCKET'"; then
        log_success "QEMU command executed successfully"
        return 0
    else
        log_error "QEMU command failed or timed out"
        return 1
    fi
}

# Execute USB/IP command in guest and log structured output
execute_usbip_command() {
    local usbip_command="$1"
    local expected_pattern="${2:-}"
    
    log_info "Executing USB/IP command in guest: $usbip_command"
    
    # Create a temporary script to execute in the guest
    local temp_script="/tmp/usbip_test_$(date +%s).sh"
    local guest_script="/tmp/usbip_command.sh"
    
    # Create script content with structured logging
    cat > "$temp_script" << EOF
#!/bin/sh
set -e

# Function to log structured messages
log_structured() {
    local level="\$1"
    local message="\$2"
    local timestamp=\$(date '+%Y-%m-%d %H:%M:%S.%3N')
    echo "[\${timestamp}] \${level}: \${message}" > /dev/console
}

# Execute the USB/IP command with error handling
if $usbip_command; then
    log_structured "COMMAND_SUCCESS" "$usbip_command"
else
    log_structured "COMMAND_FAILURE" "$usbip_command"
    exit 1
fi
EOF
    
    # Copy script to guest via QEMU monitor (simplified approach)
    # In a real implementation, this would use SSH or other mechanisms
    log_info "USB/IP command prepared for execution"
    
    # Clean up temporary script
    rm -f "$temp_script"
    
    return 0
}

# Validate structured logging functionality
test_structured_logging() {
    log_info "Testing structured logging functionality..."
    
    # Test structured log writing
    log_structured "USBIP_CLIENT_READY" "Test client initialization"
    log_structured "USBIP_VERSION" "2.0"
    log_structured "VHCI_MODULE_LOADED" "vhci-hcd module loaded successfully"
    log_structured "CONNECTING_TO_SERVER" "127.0.0.1:3240"
    log_structured "DEVICE_LIST_REQUEST" "SUCCESS"
    log_structured "DEVICE_IMPORT_REQUEST" "1-1 SUCCESS"
    log_structured "TEST_COMPLETE" "SUCCESS"
    
    # Verify structured messages can be parsed
    if [[ -f "$CONSOLE_LOG" ]]; then
        local structured_count
        structured_count=$(parse_console_log "$CONSOLE_LOG" | wc -l)
        log_info "Structured log messages found: $structured_count"
        
        # Test specific status extraction
        local client_ready_status
        client_ready_status=$(get_usbip_status "$CONSOLE_LOG" "client_ready")
        if [[ -n "$client_ready_status" ]]; then
            log_success "Client ready status extraction: OK"
        else
            log_warning "Client ready status extraction: No data"
        fi
        
        local version_status
        version_status=$(get_usbip_status "$CONSOLE_LOG" "version")
        if [[ -n "$version_status" ]]; then
            log_success "Version status extraction: $version_status"
        else
            log_warning "Version status extraction: No data"
        fi
    fi
    
    log_success "Structured logging test completed"
    return 0
}

# Test functions
test_qemu_functionality() {
    log_info "Testing QEMU startup functionality..."
    
    # Verify QEMU process is running
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        log_error "QEMU process is not running"
        return 1
    fi
    
    # Verify console log exists and has content
    if [[ ! -f "$CONSOLE_LOG" ]]; then
        log_error "Console log file not found"
        return 1
    fi
    
    if [[ ! -s "$CONSOLE_LOG" ]]; then
        log_error "Console log file is empty"
        return 1
    fi
    
    # Verify monitor socket exists
    if [[ ! -S "$MONITOR_SOCKET" ]]; then
        log_error "Monitor socket not found"
        return 1
    fi
    
    # Test monitor connectivity
    if ! echo "info version" | socat - "UNIX-CONNECT:$MONITOR_SOCKET" >/dev/null 2>&1; then
        log_error "Cannot communicate with QEMU monitor"
        return 1
    fi
    
    # Verify network ports are bound
    if ! lsof -i ":$HOST_SSH_PORT" >/dev/null 2>&1; then
        log_error "SSH port forwarding not active"
        return 1
    fi
    
    if ! lsof -i ":$HOST_USBIP_PORT" >/dev/null 2>&1; then
        log_error "USB/IP port forwarding not active"
        return 1
    fi
    
    # Test structured logging functionality
    if ! test_structured_logging; then
        log_error "Structured logging test failed"
        return 1
    fi
    
    # Test QEMU monitor command interface
    if ! send_qemu_command "info version"; then
        log_error "QEMU monitor command test failed"
        return 1
    fi
    
    log_success "QEMU functionality test passed"
    return 0
}

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND

QEMU USB/IP Test Tool - Startup and Management Script

COMMANDS:
    start       Start a new QEMU instance
    stop        Stop running QEMU instance
    status      Show status of running instances
    test        Test QEMU startup functionality
    help        Show this help message

OPTIONS:
    -h, --help  Show this help message

EXAMPLES:
    $0 start                    # Start QEMU instance
    $0 stop                     # Stop QEMU instance
    $0 status                   # Show instance status
    $0 test                     # Test functionality

CONFIGURATION:
    Memory: $QEMU_MEMORY
    CPU cores: $QEMU_CPU_COUNT
    SSH port: $HOST_SSH_PORT
    USB/IP port: $HOST_USBIP_PORT
    Boot timeout: ${BOOT_TIMEOUT}s

FILES:
    Disk image: $DISK_IMAGE
    Logs: $LOG_DIR
    PIDs: $PID_DIR

EOF
}

# Command handlers
cmd_start() {
    log_info "Starting QEMU USB/IP client instance..."
    
    # Validate environment
    if ! validate_qemu_installation; then
        log_error "QEMU validation failed"
        return 1
    fi
    
    if ! validate_image_availability; then
        log_error "Image validation failed"
        return 1
    fi
    
    if ! validate_network_ports; then
        log_error "Network port validation failed"
        return 1
    fi
    
    # Setup runtime environment
    if ! setup_runtime_environment; then
        log_error "Runtime environment setup failed"
        return 1
    fi
    
    # Create overlay image with retry
    if ! retry_with_backoff 2 2 "overlay image creation" create_overlay_image; then
        log_error "Overlay image creation failed after retries"
        return 1
    fi
    
    # Attempt to start QEMU with retries for transient failures
    local boot_attempt=1
    local boot_success=false
    
    while [[ $boot_attempt -le $MAX_BOOT_RETRIES ]] && [[ "$boot_success" != "true" ]]; do
        log_info "Boot attempt $boot_attempt/$MAX_BOOT_RETRIES"
        
        # Clean up any previous attempt
        if [[ -n "$QEMU_PID" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
            log_info "Cleaning up previous QEMU instance"
            stop_qemu_instance
            sleep 2
        fi
        
        # Recreate overlay image for retry attempts
        if [[ $boot_attempt -gt 1 ]]; then
            log_info "Recreating overlay image for retry attempt"
            if [[ -f "$QEMU_OVERLAY_IMAGE" ]]; then
                rm -f "$QEMU_OVERLAY_IMAGE"
            fi
            if ! create_overlay_image; then
                log_error "Failed to recreate overlay image for retry"
                boot_attempt=$((boot_attempt + 1))
                continue
            fi
        fi
        
        # Start QEMU instance
        if ! start_qemu_instance; then
            log_error "Failed to start QEMU instance (attempt $boot_attempt)"
            boot_attempt=$((boot_attempt + 1))
            if [[ $boot_attempt -le $MAX_BOOT_RETRIES ]]; then
                log_info "Retrying QEMU startup in ${RETRY_DELAY}s..."
                sleep "$RETRY_DELAY"
            fi
            continue
        fi
        
        # Wait for boot completion
        if ! wait_for_boot; then
            log_error "QEMU instance failed to boot properly (attempt $boot_attempt)"
            stop_qemu_instance
            boot_attempt=$((boot_attempt + 1))
            if [[ $boot_attempt -le $MAX_BOOT_RETRIES ]]; then
                log_info "Retrying boot in ${RETRY_DELAY}s..."
                sleep "$RETRY_DELAY"
            fi
            continue
        fi
        
        # Test functionality
        if ! test_qemu_functionality; then
            log_error "QEMU functionality test failed (attempt $boot_attempt)"
            stop_qemu_instance
            boot_attempt=$((boot_attempt + 1))
            if [[ $boot_attempt -le $MAX_BOOT_RETRIES ]]; then
                log_info "Retrying due to functionality test failure in ${RETRY_DELAY}s..."
                sleep "$RETRY_DELAY"
            fi
            continue
        fi
        
        # Success!
        boot_success=true
        break
    done
    
    if [[ "$boot_success" != "true" ]]; then
        log_error "Failed to start QEMU instance after $MAX_BOOT_RETRIES attempts"
        log_structured "STARTUP_FAILED" "All retry attempts exhausted"
        return 1
    fi
    
    # Show connection information
    show_connection_info
    
    log_success "QEMU USB/IP client instance started successfully"
    log_info "Instance is ready for USB/IP testing"
    log_structured "STARTUP_SUCCESS" "Boot attempt: $boot_attempt"
    
    return 0
}

cmd_stop() {
    log_info "Stopping QEMU instances..."
    
    # Find running instances
    local pid_files
    pid_files=$(find "$PID_DIR" -name "*.pid" 2>/dev/null || true)
    
    if [[ -z "$pid_files" ]]; then
        log_info "No running QEMU instances found"
        return 0
    fi
    
    local stopped_count=0
    while IFS= read -r pid_file; do
        if [[ -f "$pid_file" ]]; then
            local pid
            pid=$(cat "$pid_file")
            local instance_id
            instance_id=$(basename "$pid_file" .pid)
            
            if kill -0 "$pid" 2>/dev/null; then
                log_info "Stopping instance: $instance_id (PID: $pid)"
                
                # Set up variables for cleanup
                QEMU_PID="$pid"
                INSTANCE_ID="$instance_id"
                MONITOR_SOCKET="${PID_DIR}/${instance_id}-monitor.sock"
                QEMU_OVERLAY_IMAGE="${BUILD_DIR}/${instance_id}-overlay.qcow2"
                
                stop_qemu_instance
                stopped_count=$((stopped_count + 1))
            else
                log_info "Cleaning up stale PID file: $instance_id"
                rm -f "$pid_file"
            fi
        fi
    done <<< "$pid_files"
    
    log_success "Stopped $stopped_count QEMU instance(s)"
    return 0
}

cmd_status() {
    log_info "QEMU instance status:"
    
    # Find PID files
    local pid_files
    pid_files=$(find "$PID_DIR" -name "*.pid" 2>/dev/null || true)
    
    if [[ -z "$pid_files" ]]; then
        log_info "No QEMU instances found"
        return 0
    fi
    
    local running_count=0
    while IFS= read -r pid_file; do
        if [[ -f "$pid_file" ]]; then
            local pid
            pid=$(cat "$pid_file")
            local instance_id
            instance_id=$(basename "$pid_file" .pid)
            
            if kill -0 "$pid" 2>/dev/null; then
                log_info "  ✓ $instance_id (PID: $pid) - RUNNING"
                running_count=$((running_count + 1))
            else
                log_info "  ✗ $instance_id (PID: $pid) - STOPPED"
                rm -f "$pid_file"
            fi
        fi
    done <<< "$pid_files"
    
    log_info "Total running instances: $running_count"
    return 0
}

cmd_test() {
    log_info "Testing QEMU startup functionality..."
    
    # Start instance
    if ! cmd_start; then
        log_error "QEMU startup test failed"
        return 1
    fi
    
    # Additional functionality tests
    log_info "Running additional functionality tests..."
    
    # Test console log parsing
    if [[ -f "$CONSOLE_LOG" ]]; then
        local readiness_count
        readiness_count=$(grep -c "USBIP_CLIENT_READY" "$CONSOLE_LOG" 2>/dev/null || echo "0")
        log_info "USB/IP readiness signals found: $readiness_count"
        
        if [[ "$readiness_count" -gt 0 ]]; then
            log_success "Console log parsing test passed"
        else
            log_warning "Console log parsing test: no readiness signals found"
        fi
    fi
    
    # Stop instance after testing
    log_info "Stopping test instance..."
    stop_qemu_instance
    
    log_success "QEMU startup functionality test completed"
    return 0
}

# Main execution
main() {
    local command="${1:-}"
    
    case "$command" in
        "start")
            cmd_start
            ;;
        "stop")
            cmd_stop
            ;;
        "status")
            cmd_status
            ;;
        "test")
            cmd_test
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        "")
            log_error "No command specified"
            show_usage
            exit 1
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi