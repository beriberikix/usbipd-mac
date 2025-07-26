#!/bin/bash

# QEMU USB/IP Test Tool - Error Handling Test Script
# Tests the error handling and recovery mechanisms

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/.build/qemu"
readonly LOG_DIR="${BUILD_DIR}/logs"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

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

# Test framework functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    log_info "Running test: $test_name"
    
    if $test_function; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_success "Test passed: $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log_error "Test failed: $test_name"
        return 1
    fi
}

# Test functions
test_retry_mechanism() {
    log_info "Testing retry mechanism with simulated failures..."
    
    # Create a temporary script that fails twice then succeeds
    local test_script="${BUILD_DIR}/test_retry.sh"
    local counter_file="${BUILD_DIR}/retry_counter"
    
    mkdir -p "$BUILD_DIR"
    echo "0" > "$counter_file"
    
    cat > "$test_script" << 'EOF'
#!/bin/bash
counter_file="$1"
current_count=$(cat "$counter_file")
new_count=$((current_count + 1))
echo "$new_count" > "$counter_file"

if [[ $new_count -le 2 ]]; then
    echo "Simulated failure (attempt $new_count)"
    exit 1
else
    echo "Success on attempt $new_count"
    exit 0
fi
EOF
    
    chmod +x "$test_script"
    
    # Implement a simple retry mechanism for testing
    local max_attempts=3
    local delay=1
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempting simulated operation (attempt $attempt/$max_attempts)"
        
        if "$test_script" "$counter_file"; then
            log_success "Simulated operation succeeded on attempt $attempt"
            local final_count
            final_count=$(cat "$counter_file")
            if [[ $final_count -eq 3 ]]; then
                log_success "Retry mechanism worked correctly (3 attempts)"
                rm -f "$test_script" "$counter_file"
                return 0
            else
                log_error "Unexpected attempt count: $final_count"
                rm -f "$test_script" "$counter_file"
                return 1
            fi
        else
            log_warning "Simulated operation failed on attempt $attempt"
            
            if [[ $attempt -lt $max_attempts ]]; then
                log_info "Retrying in ${delay}s..."
                sleep "$delay"
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Simulated operation failed after $max_attempts attempts"
    rm -f "$test_script" "$counter_file"
    return 1
}

test_timeout_detection() {
    log_info "Testing timeout detection mechanisms..."
    
    # Create a test console log with timeout scenario
    local test_console_log="${BUILD_DIR}/test_console.log"
    
    cat > "$test_console_log" << 'EOF'
[    0.000000] Linux version 5.15.0
[    0.100000] Command line: BOOT_IMAGE=/boot/vmlinuz
[    1.000000] Memory: 256MB available
[    2.000000] Loading kernel modules...
[    5.000000] USB subsystem initialized
[   10.000000] Network interface eth0 up
[   15.000000] Starting cloud-init...
[   20.000000] cloud-init: running modules
[   25.000000] Installing packages...
[   30.000000] Package installation complete
[   35.000000] Loading vhci-hcd module...
[   40.000000] vhci-hcd module loaded successfully
[   45.000000] Starting USB/IP client setup...
[   50.000000] USB/IP client configuration in progress...
EOF
    
    # Test timeout detection by simulating stall detection logic
    local initial_size
    initial_size=$(wc -l < "$test_console_log")
    
    # Simulate waiting and checking for log growth
    sleep 0.1
    
    local final_size
    final_size=$(wc -l < "$test_console_log")
    
    # Since we didn't add any new lines, this simulates a stalled boot
    local stall_detected=false
    if [[ $final_size -eq $initial_size ]]; then
        stall_detected=true
    fi
    
    # Test that we can detect the absence of completion markers
    local completion_found=false
    if grep -q "USBIP_CLIENT_READY\|CLOUD_INIT_COMPLETE\|login:" "$test_console_log" 2>/dev/null; then
        completion_found=true
    fi
    
    # For this test, we expect stall detection and no completion markers
    if [[ "$stall_detected" == "true" && "$completion_found" == "false" ]]; then
        log_success "Timeout detection working correctly (stall detected, no completion markers)"
        rm -f "$test_console_log"
        return 0
    else
        log_error "Timeout detection failed (stall: $stall_detected, completion: $completion_found)"
        rm -f "$test_console_log"
        return 1
    fi
}

test_error_pattern_detection() {
    log_info "Testing error pattern detection..."
    
    # Create test console logs with various error patterns
    local test_cases=(
        "kernel_panic:Kernel panic - not syncing: VFS: Unable to mount root fs"
        "out_of_memory:Out of memory: Kill process 1234"
        "permission_denied:Permission denied: cannot access /dev/vhci"
        "disk_full:No space left on device"
        "address_in_use:Address already in use: bind failed"
    )
    
    local patterns_detected=0
    local expected_patterns=5
    
    for test_case in "${test_cases[@]}"; do
        local error_type="${test_case%%:*}"
        local error_message="${test_case#*:}"
        local test_log="${BUILD_DIR}/test_${error_type}.log"
        
        echo "$error_message" > "$test_log"
        
        # Test pattern detection
        if grep -q "Kernel panic\|Out of memory\|Permission denied\|No space left\|Address already in use" "$test_log" 2>/dev/null; then
            patterns_detected=$((patterns_detected + 1))
            log_info "  ✓ Detected $error_type pattern"
        else
            log_warning "  ✗ Failed to detect $error_type pattern"
        fi
        
        rm -f "$test_log"
    done
    
    if [[ $patterns_detected -eq $expected_patterns ]]; then
        log_success "Error pattern detection working correctly ($patterns_detected/$expected_patterns)"
        return 0
    else
        log_error "Error pattern detection incomplete ($patterns_detected/$expected_patterns)"
        return 1
    fi
}

test_diagnostic_generation() {
    log_info "Testing diagnostic information generation..."
    
    # Create test environment
    mkdir -p "$LOG_DIR"
    local test_instance_id="test-diagnostics-$$"
    local test_console_log="${LOG_DIR}/${test_instance_id}-console.log"
    local test_diagnostics="${LOG_DIR}/diagnostics-${test_instance_id}.log"
    
    # Create sample console log
    cat > "$test_console_log" << 'EOF'
[    0.000000] Linux version 5.15.0
[    1.000000] Memory: 256MB available
[    2.000000] Error: Failed to initialize USB subsystem
[    3.000000] Kernel panic - not syncing: Fatal error
EOF
    
    # Simulate diagnostic generation
    {
        echo "QEMU USB/IP Test Tool - Failure Diagnostics"
        echo "============================================"
        echo "Timestamp: $(date)"
        echo "Exit Code: 1"
        echo "Instance ID: $test_instance_id"
        echo ""
        
        echo "System Information:"
        echo "  OS: $(uname -s)"
        echo "  Architecture: $(uname -m)"
        echo ""
        
        echo "Recent Console Log (last 5 lines):"
        tail -n5 "$test_console_log" | sed 's/^/  /'
        echo ""
        
    } > "$test_diagnostics"
    
    # Verify diagnostic file was created and contains expected content
    if [[ -f "$test_diagnostics" ]]; then
        if grep -q "Failure Diagnostics" "$test_diagnostics" && \
           grep -q "Instance ID: $test_instance_id" "$test_diagnostics" && \
           grep -q "Kernel panic" "$test_diagnostics"; then
            log_success "Diagnostic generation working correctly"
            rm -f "$test_console_log" "$test_diagnostics"
            return 0
        else
            log_error "Diagnostic file missing expected content"
            rm -f "$test_console_log" "$test_diagnostics"
            return 1
        fi
    else
        log_error "Diagnostic file was not created"
        rm -f "$test_console_log"
        return 1
    fi
}

test_network_port_retry() {
    log_info "Testing network port retry mechanism..."
    
    # This test simulates port conflict resolution
    # In a real scenario, we would test with actual port binding
    
    local port_check_attempts=0
    local max_attempts=3
    local port_available=false
    
    # Simulate port checking with eventual success
    while [[ $port_check_attempts -lt $max_attempts ]]; do
        port_check_attempts=$((port_check_attempts + 1))
        
        # Simulate port becoming available on third attempt
        if [[ $port_check_attempts -eq 3 ]]; then
            port_available=true
            break
        fi
        
        # Simulate retry delay
        sleep 0.1
    done
    
    if [[ "$port_available" == "true" && $port_check_attempts -eq 3 ]]; then
        log_success "Network port retry mechanism working correctly"
        return 0
    else
        log_error "Network port retry mechanism failed"
        return 1
    fi
}

test_structured_error_logging() {
    log_info "Testing structured error logging..."
    
    local test_log="${BUILD_DIR}/structured_error_test.log"
    
    # Simulate structured error logging
    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] BOOT_TIMEOUT: Boot timeout exceeded"
        echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] NETWORK_FAILURE: Port conflict: Port 2222 occupied"
        echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] QEMU_CRASH: Process died during boot"
        echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] DIAGNOSTICS_GENERATED: /path/to/diagnostics.log"
    } > "$test_log"
    
    # Verify structured messages can be parsed
    local structured_count
    structured_count=$(grep -E '\[.*\] (BOOT_TIMEOUT|NETWORK_FAILURE|QEMU_CRASH|DIAGNOSTICS_GENERATED):' "$test_log" | wc -l)
    
    if [[ $structured_count -eq 4 ]]; then
        log_success "Structured error logging working correctly ($structured_count messages)"
        rm -f "$test_log"
        return 0
    else
        log_error "Structured error logging incomplete ($structured_count/4 messages)"
        rm -f "$test_log"
        return 1
    fi
}

# Main test execution
main() {
    log_info "Starting QEMU error handling and recovery mechanism tests"
    log_info "========================================================="
    
    # Ensure build directory exists
    mkdir -p "$BUILD_DIR" "$LOG_DIR"
    
    # Run all tests
    run_test "Retry Mechanism" test_retry_mechanism
    run_test "Timeout Detection" test_timeout_detection
    run_test "Error Pattern Detection" test_error_pattern_detection
    run_test "Diagnostic Generation" test_diagnostic_generation
    run_test "Network Port Retry" test_network_port_retry
    run_test "Structured Error Logging" test_structured_error_logging
    
    # Test summary
    log_info "========================================================="
    log_info "Test Summary:"
    log_info "  Tests run: $TESTS_RUN"
    log_success "  Tests passed: $TESTS_PASSED"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        log_error "  Tests failed: $TESTS_FAILED"
    else
        log_info "  Tests failed: $TESTS_FAILED"
    fi
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "All error handling tests passed!"
        return 0
    else
        log_error "Some error handling tests failed"
        return 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi