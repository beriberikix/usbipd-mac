#!/bin/bash

# QEMU USB/IP Test Tool - Concurrent Execution Testing Script
# Tests the ability to run multiple QEMU instances simultaneously

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/.build/qemu"
readonly LOG_DIR="${BUILD_DIR}/logs"
readonly PID_DIR="${BUILD_DIR}/pids"

# Test configuration (defaults)
DEFAULT_MAX_CONCURRENT_INSTANCES=3
DEFAULT_INSTANCE_STARTUP_DELAY=5
DEFAULT_TEST_DURATION=30
readonly CLEANUP_TIMEOUT=10

# Test configuration (will be set by arguments)
MAX_CONCURRENT_INSTANCES=$DEFAULT_MAX_CONCURRENT_INSTANCES
INSTANCE_STARTUP_DELAY=$DEFAULT_INSTANCE_STARTUP_DELAY
TEST_DURATION=$DEFAULT_TEST_DURATION

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
STARTED_INSTANCES=()
TEST_RESULTS=()

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

# Cleanup function
cleanup() {
    local exit_code=$?
    
    log_info "Cleaning up concurrent execution test..."
    
    # Stop all started instances
    if [[ ${#STARTED_INSTANCES[@]} -gt 0 ]]; then
        for instance_info in "${STARTED_INSTANCES[@]}"; do
        local instance_pid
        instance_pid=$(echo "$instance_info" | cut -d: -f2)
        
        if kill -0 "$instance_pid" 2>/dev/null; then
            log_info "Stopping instance PID: $instance_pid"
            kill -TERM "$instance_pid" 2>/dev/null || true
            
            # Wait briefly for graceful shutdown
            local wait_count=0
            while [[ $wait_count -lt $CLEANUP_TIMEOUT ]] && kill -0 "$instance_pid" 2>/dev/null; do
                sleep 1
                wait_count=$((wait_count + 1))
            done
            
            # Force kill if still running
            if kill -0 "$instance_pid" 2>/dev/null; then
                kill -KILL "$instance_pid" 2>/dev/null || true
            fi
        fi
        done
    fi
    
    # Clean up any remaining QEMU processes
    pkill -f "qemu-system-x86_64.*qemu-usbip" 2>/dev/null || true
    
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Validation functions
validate_prerequisites() {
    log_info "Validating prerequisites for concurrent execution test..."
    
    # Check if QEMU image exists
    local disk_image="${BUILD_DIR}/qemu-usbip-client.qcow2"
    if [[ ! -f "$disk_image" ]]; then
        log_error "QEMU disk image not found: $disk_image"
        log_info "Run Scripts/create-qemu-image.sh first"
        return 1
    fi
    
    # Check if start script exists
    local start_script="${SCRIPT_DIR}/start-qemu-client.sh"
    if [[ ! -f "$start_script" ]]; then
        log_error "QEMU start script not found: $start_script"
        return 1
    fi
    
    # Check if script is executable
    if [[ ! -x "$start_script" ]]; then
        log_error "QEMU start script is not executable: $start_script"
        return 1
    fi
    
    # Create necessary directories
    mkdir -p "$LOG_DIR"
    mkdir -p "$PID_DIR"
    
    log_success "Prerequisites validation passed"
    return 0
}

# Start a single QEMU instance
start_qemu_instance() {
    local instance_number="$1"
    
    log_info "Starting QEMU instance #${instance_number}..."
    
    local start_script="${SCRIPT_DIR}/start-qemu-client.sh"
    local instance_log="${LOG_DIR}/concurrent-test-${instance_number}.log"
    
    # Start instance in background
    if "$start_script" > "$instance_log" 2>&1 &
    then
        local instance_pid=$!
        local instance_info="${instance_number}:${instance_pid}:${instance_log}"
        STARTED_INSTANCES+=("$instance_info")
        
        log_info "Instance #${instance_number} started with PID: $instance_pid"
        return 0
    else
        log_error "Failed to start instance #${instance_number}"
        return 1
    fi
}

# Monitor instance status
monitor_instance() {
    local instance_info="$1"
    local instance_number
    instance_number=$(echo "$instance_info" | cut -d: -f1)
    local instance_pid
    instance_pid=$(echo "$instance_info" | cut -d: -f2)
    local instance_log
    instance_log=$(echo "$instance_info" | cut -d: -f3)
    
    # Check if process is still running
    if ! kill -0 "$instance_pid" 2>/dev/null; then
        return 1
    fi
    
    # Check log for readiness indicators
    if [[ -f "$instance_log" ]]; then
        if grep -q "USBIP_CLIENT_READY\|QEMU instance connection information" "$instance_log" 2>/dev/null; then
            return 0
        fi
    fi
    
    return 2  # Still starting
}

# Test resource allocation conflicts
test_resource_allocation() {
    log_info "Testing resource allocation for concurrent instances..."
    
    local allocation_conflicts=0
    local port_conflicts=0
    
    # Check for port conflicts by examining logs
    for instance_info in "${STARTED_INSTANCES[@]}"; do
        local instance_log
        instance_log=$(echo "$instance_info" | cut -d: -f3)
        
        if [[ -f "$instance_log" ]]; then
            # Check for port allocation failures
            if grep -q "Port.*already in use\|Port.*occupied\|Network port.*conflict" "$instance_log" 2>/dev/null; then
                port_conflicts=$((port_conflicts + 1))
            fi
            
            # Check for resource allocation failures
            if grep -q "Resource allocation failed\|Insufficient.*memory\|CPU allocation failed" "$instance_log" 2>/dev/null; then
                allocation_conflicts=$((allocation_conflicts + 1))
            fi
        fi
    done
    
    log_info "Resource allocation test results:"
    log_info "  Port conflicts: $port_conflicts"
    log_info "  Resource allocation conflicts: $allocation_conflicts"
    
    if [[ $port_conflicts -eq 0 && $allocation_conflicts -eq 0 ]]; then
        log_success "No resource allocation conflicts detected"
        return 0
    else
        log_error "Resource allocation conflicts detected"
        return 1
    fi
}

# Test overlay image isolation
test_overlay_isolation() {
    log_info "Testing overlay image isolation..."
    
    local overlay_conflicts=0
    local unique_overlays=()
    
    # Check for unique overlay images
    for instance_info in "${STARTED_INSTANCES[@]}"; do
        local instance_log
        instance_log=$(echo "$instance_info" | cut -d: -f3)
        
        if [[ -f "$instance_log" ]]; then
            # Extract overlay image names from logs
            local overlay_name
            overlay_name=$(grep -o "overlay.*\.qcow2" "$instance_log" 2>/dev/null | head -n1 || echo "")
            
            if [[ -n "$overlay_name" ]]; then
                # Check if this overlay name is already used
                local is_duplicate=false
                for existing_overlay in "${unique_overlays[@]}"; do
                    if [[ "$overlay_name" == "$existing_overlay" ]]; then
                        is_duplicate=true
                        break
                    fi
                done
                
                if [[ "$is_duplicate" == "true" ]]; then
                    overlay_conflicts=$((overlay_conflicts + 1))
                else
                    unique_overlays+=("$overlay_name")
                fi
            fi
        fi
    done
    
    log_info "Overlay isolation test results:"
    log_info "  Unique overlay images: ${#unique_overlays[@]}"
    log_info "  Overlay conflicts: $overlay_conflicts"
    
    if [[ $overlay_conflicts -eq 0 ]]; then
        log_success "Overlay image isolation working correctly"
        return 0
    else
        log_error "Overlay image conflicts detected"
        return 1
    fi
}

# Monitor all instances
monitor_all_instances() {
    local monitoring_duration="$1"
    
    log_info "Monitoring ${#STARTED_INSTANCES[@]} instances for ${monitoring_duration}s..."
    
    local elapsed=0
    local check_interval=5
    
    while [[ $elapsed -lt $monitoring_duration ]]; do
        local running_count=0
        local ready_count=0
        local failed_count=0
        
        for instance_info in "${STARTED_INSTANCES[@]}"; do
            local status
            if monitor_instance "$instance_info"; then
                status=$?
                case $status in
                    0)
                        ready_count=$((ready_count + 1))
                        running_count=$((running_count + 1))
                        ;;
                    2)
                        running_count=$((running_count + 1))
                        ;;
                esac
            else
                failed_count=$((failed_count + 1))
            fi
        done
        
        log_info "Instance status: $ready_count ready, $((running_count - ready_count)) starting, $failed_count failed"
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    log_info "Monitoring completed"
    
    # Final status check
    local final_ready=0
    local final_running=0
    local final_failed=0
    
    for instance_info in "${STARTED_INSTANCES[@]}"; do
        local status
        if monitor_instance "$instance_info"; then
            status=$?
            case $status in
                0)
                    final_ready=$((final_ready + 1))
                    final_running=$((final_running + 1))
                    ;;
                2)
                    final_running=$((final_running + 1))
                    ;;
            esac
        else
            final_failed=$((final_failed + 1))
        fi
    done
    
    log_info "Final instance status:"
    log_info "  Ready: $final_ready"
    log_info "  Running: $final_running"
    log_info "  Failed: $final_failed"
    
    # Store results
    TEST_RESULTS+=("instances_started:${#STARTED_INSTANCES[@]}")
    TEST_RESULTS+=("instances_ready:$final_ready")
    TEST_RESULTS+=("instances_running:$final_running")
    TEST_RESULTS+=("instances_failed:$final_failed")
    
    return 0
}

# Generate test report
generate_test_report() {
    local report_file="${LOG_DIR}/concurrent-execution-test-report.txt"
    
    log_info "Generating concurrent execution test report..."
    
    {
        echo "QEMU USB/IP Test Tool - Concurrent Execution Test Report"
        echo "======================================================="
        echo "Generated: $(date)"
        echo "Test Duration: ${TEST_DURATION}s"
        echo "Max Concurrent Instances: $MAX_CONCURRENT_INSTANCES"
        echo ""
        
        # Test results
        echo "Test Results:"
        for result in "${TEST_RESULTS[@]}"; do
            local key
            key=$(echo "$result" | cut -d: -f1)
            local value
            value=$(echo "$result" | cut -d: -f2)
            echo "  $key: $value"
        done
        echo ""
        
        # Instance details
        echo "Instance Details:"
        local instance_num=1
        for instance_info in "${STARTED_INSTANCES[@]}"; do
            local instance_pid
            instance_pid=$(echo "$instance_info" | cut -d: -f2)
            local instance_log
            instance_log=$(echo "$instance_info" | cut -d: -f3)
            
            echo "  Instance #${instance_num}:"
            echo "    PID: $instance_pid"
            echo "    Log: $(basename "$instance_log")"
            
            if [[ -f "$instance_log" ]]; then
                # Extract key information from log
                local ssh_port
                ssh_port=$(grep -o "SSH: [0-9]*" "$instance_log" 2>/dev/null | head -n1 | cut -d: -f2 | tr -d ' ' || echo "N/A")
                local usbip_port
                usbip_port=$(grep -o "USB/IP: [0-9]*" "$instance_log" 2>/dev/null | head -n1 | cut -d: -f2 | tr -d ' ' || echo "N/A")
                local memory
                memory=$(grep -o "Memory: [0-9]*M" "$instance_log" 2>/dev/null | head -n1 | cut -d: -f2 | tr -d ' ' || echo "N/A")
                
                echo "    SSH Port: $ssh_port"
                echo "    USB/IP Port: $usbip_port"
                echo "    Memory: $memory"
                
                # Check for errors
                local error_count
                error_count=$(grep -c "ERROR\|FAILED" "$instance_log" 2>/dev/null || echo "0")
                echo "    Errors: $error_count"
            fi
            
            instance_num=$((instance_num + 1))
            echo ""
        done
        
        # System resource usage
        echo "System Resource Usage:"
        echo "  Memory:"
        vm_stat 2>/dev/null | head -n5 | sed 's/^/    /' || echo "    Unable to get memory stats"
        echo "  CPU:"
        top -l 1 -n 0 | grep "CPU usage" | sed 's/^/    /' || echo "    Unable to get CPU stats"
        echo ""
        
        # Test summary
        echo "Test Summary:"
        local success_rate=0
        if [[ ${#STARTED_INSTANCES[@]} -gt 0 ]]; then
            local ready_instances
            ready_instances=$(printf '%s\n' "${TEST_RESULTS[@]}" | grep "instances_ready:" | cut -d: -f2 || echo "0")
            success_rate=$((ready_instances * 100 / ${#STARTED_INSTANCES[@]}))
        fi
        
        echo "  Success Rate: ${success_rate}%"
        
        if [[ $success_rate -ge 80 ]]; then
            echo "  Overall Result: PASSED"
        else
            echo "  Overall Result: FAILED"
        fi
        
    } > "$report_file"
    
    log_success "Test report generated: $(basename "$report_file")"
    return 0
}

# Main test execution
run_concurrent_execution_test() {
    log_info "Starting concurrent execution test..."
    log_info "Max concurrent instances: $MAX_CONCURRENT_INSTANCES"
    log_info "Test duration: ${TEST_DURATION}s"
    
    # Start multiple instances with staggered startup
    for ((i=1; i<=MAX_CONCURRENT_INSTANCES; i++)); do
        if start_qemu_instance "$i"; then
            log_success "Instance #$i startup initiated"
        else
            log_error "Failed to start instance #$i"
            TEST_RESULTS+=("startup_failure:instance_$i")
        fi
        
        # Stagger startup to avoid resource conflicts
        if [[ $i -lt $MAX_CONCURRENT_INSTANCES ]]; then
            log_info "Waiting ${INSTANCE_STARTUP_DELAY}s before starting next instance..."
            sleep $INSTANCE_STARTUP_DELAY
        fi
    done
    
    log_info "All instances started, waiting for initialization..."
    sleep 10
    
    # Test resource allocation
    if test_resource_allocation; then
        TEST_RESULTS+=("resource_allocation:PASSED")
    else
        TEST_RESULTS+=("resource_allocation:FAILED")
    fi
    
    # Test overlay isolation
    if test_overlay_isolation; then
        TEST_RESULTS+=("overlay_isolation:PASSED")
    else
        TEST_RESULTS+=("overlay_isolation:FAILED")
    fi
    
    # Monitor instances
    monitor_all_instances $TEST_DURATION
    
    # Generate report
    generate_test_report
    
    log_success "Concurrent execution test completed"
    return 0
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

QEMU USB/IP Test Tool - Concurrent Execution Testing

OPTIONS:
    -n, --instances NUM     Maximum number of concurrent instances (default: $DEFAULT_MAX_CONCURRENT_INSTANCES)
    -d, --duration SEC      Test duration in seconds (default: $DEFAULT_TEST_DURATION)
    -s, --startup-delay SEC Delay between instance startups (default: $DEFAULT_INSTANCE_STARTUP_DELAY)
    -h, --help              Show this help message

EXAMPLES:
    $0                      Run test with default settings
    $0 -n 5 -d 60          Run test with 5 instances for 60 seconds
    $0 --instances 2 --duration 30 --startup-delay 10

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--instances)
                if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                    MAX_CONCURRENT_INSTANCES="$2"
                    shift 2
                else
                    log_error "Invalid number of instances: ${2:-}"
                    exit 1
                fi
                ;;
            -d|--duration)
                if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                    TEST_DURATION="$2"
                    shift 2
                else
                    log_error "Invalid test duration: ${2:-}"
                    exit 1
                fi
                ;;
            -s|--startup-delay)
                if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                    INSTANCE_STARTUP_DELAY="$2"
                    shift 2
                else
                    log_error "Invalid startup delay: ${2:-}"
                    exit 1
                fi
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    log_info "QEMU USB/IP Test Tool - Concurrent Execution Testing"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate prerequisites
    if ! validate_prerequisites; then
        log_error "Prerequisites validation failed"
        exit 1
    fi
    
    # Run the test
    if run_concurrent_execution_test; then
        log_success "Concurrent execution test completed successfully"
        exit 0
    else
        log_error "Concurrent execution test failed"
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi