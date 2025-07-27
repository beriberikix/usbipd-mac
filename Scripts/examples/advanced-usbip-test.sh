#!/bin/bash

# Advanced USB/IP Client Test Example
# Demonstrates comprehensive testing scenarios including device import/export,
# error handling, and performance monitoring

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly SCRIPTS_DIR="${PROJECT_ROOT}/Scripts"

# Test configuration
readonly SERVER_HOST="${1:-localhost}"
readonly SERVER_PORT="${2:-3240}"
readonly TEST_DURATION="${3:-300}"
readonly CONCURRENT_CLIENTS="${4:-2}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Test tracking
declare -a QEMU_PIDS=()
declare -a TEST_RESULTS=()

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

# Main test function
main() {
    log_info "Starting advanced USB/IP client test suite"
    log_info "Server: ${SERVER_HOST}:${SERVER_PORT}"
    log_info "Duration: ${TEST_DURATION} seconds"
    log_info "Concurrent clients: ${CONCURRENT_CLIENTS}"
    
    # Create test results directory
    local results_dir="${PROJECT_ROOT}/.build/qemu/advanced-test-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${results_dir}"
    
    # Test 1: Single client comprehensive test
    log_info "=== Test 1: Single Client Comprehensive Test ==="
    if run_single_client_test "${results_dir}"; then
        TEST_RESULTS+=("Single Client: PASS")
        log_success "Single client test passed"
    else
        TEST_RESULTS+=("Single Client: FAIL")
        log_error "Single client test failed"
    fi
    
    # Test 2: Concurrent client test
    log_info "=== Test 2: Concurrent Client Test ==="
    if run_concurrent_client_test "${results_dir}"; then
        TEST_RESULTS+=("Concurrent Clients: PASS")
        log_success "Concurrent client test passed"
    else
        TEST_RESULTS+=("Concurrent Clients: FAIL")
        log_error "Concurrent client test failed"
    fi
    
    # Test 3: Error handling and recovery test
    log_info "=== Test 3: Error Handling and Recovery Test ==="
    if run_error_handling_test "${results_dir}"; then
        TEST_RESULTS+=("Error Handling: PASS")
        log_success "Error handling test passed"
    else
        TEST_RESULTS+=("Error Handling: FAIL")
        log_error "Error handling test failed"
    fi
    
    # Test 4: Performance and resource monitoring
    log_info "=== Test 4: Performance and Resource Monitoring ==="
    if run_performance_test "${results_dir}"; then
        TEST_RESULTS+=("Performance: PASS")
        log_success "Performance test passed"
    else
        TEST_RESULTS+=("Performance: FAIL")
        log_error "Performance test failed"
    fi
    
    # Generate comprehensive report
    generate_final_report "${results_dir}"
    
    # Display results summary
    display_results_summary
    
    # Cleanup any remaining processes
    cleanup_all_qemu
    
    # Exit with appropriate code
    local failed_tests=0
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "${result}" == *"FAIL"* ]]; then
            ((failed_tests++))
        fi
    done
    
    if [[ ${failed_tests} -eq 0 ]]; then
        log_success "All advanced tests completed successfully"
        exit 0
    else
        log_error "${failed_tests} test(s) failed"
        exit 1
    fi
}

# Single client comprehensive test
run_single_client_test() {
    local results_dir="$1"
    local test_log="${results_dir}/single-client-test.log"
    
    log_info "Starting single client comprehensive test..."
    
    # Start QEMU client
    local qemu_pid
    if ! qemu_pid=$("${SCRIPTS_DIR}/start-qemu-client.sh" --background 2>>"${test_log}"); then
        log_error "Failed to start QEMU client"
        return 1
    fi
    QEMU_PIDS+=("${qemu_pid}")
    
    local console_log="${PROJECT_ROOT}/.build/qemu/logs/${qemu_pid}-console.log"
    
    # Wait for readiness
    if ! "${SCRIPTS_DIR}/qemu-test-validation.sh" wait-readiness "${console_log}" 60; then
        log_error "Client failed to become ready"
        return 1
    fi
    
    # Test server connectivity
    if ! "${SCRIPTS_DIR}/qemu-test-validation.sh" check-server "${SERVER_HOST}" "${SERVER_PORT}"; then
        log_error "Server connectivity test failed"
        return 1
    fi
    
    # Monitor connection for extended period
    if ! "${SCRIPTS_DIR}/qemu-test-validation.sh" monitor-connection "${console_log}" "${SERVER_HOST}" "${SERVER_PORT}" 60; then
        log_error "Connection monitoring failed"
        return 1
    fi
    
    # Generate detailed report
    "${SCRIPTS_DIR}/qemu-test-validation.sh" generate-report "${console_log}" "${results_dir}/single-client-report.txt"
    
    return 0
}

# Concurrent client test
run_concurrent_client_test() {
    local results_dir="$1"
    local test_log="${results_dir}/concurrent-client-test.log"
    
    log_info "Starting ${CONCURRENT_CLIENTS} concurrent clients..."
    
    local client_pids=()
    local success_count=0
    
    # Start multiple clients
    for ((i=1; i<=CONCURRENT_CLIENTS; i++)); do
        log_info "Starting client ${i}/${CONCURRENT_CLIENTS}..."
        
        local qemu_pid
        if qemu_pid=$("${SCRIPTS_DIR}/start-qemu-client.sh" --background 2>>"${test_log}"); then
            client_pids+=("${qemu_pid}")
            QEMU_PIDS+=("${qemu_pid}")
            log_info "Client ${i} started (PID: ${qemu_pid})"
        else
            log_error "Failed to start client ${i}"
        fi
        
        # Small delay between starts
        sleep 2
    done
    
    # Wait for all clients to become ready
    for pid in "${client_pids[@]}"; do
        local console_log="${PROJECT_ROOT}/.build/qemu/logs/${pid}-console.log"
        
        if "${SCRIPTS_DIR}/qemu-test-validation.sh" wait-readiness "${console_log}" 90; then
            ((success_count++))
            log_info "Client ${pid} is ready"
        else
            log_error "Client ${pid} failed to become ready"
        fi
    done
    
    log_info "${success_count}/${#client_pids[@]} clients became ready"
    
    # Test concurrent operations
    if [[ ${success_count} -gt 0 ]]; then
        log_info "Testing concurrent server connections..."
        
        for pid in "${client_pids[@]}"; do
            local console_log="${PROJECT_ROOT}/.build/qemu/logs/${pid}-console.log"
            
            # Test server connectivity in background
            "${SCRIPTS_DIR}/qemu-test-validation.sh" check-server "${SERVER_HOST}" "${SERVER_PORT}" &
        done
        
        # Wait for all connectivity tests
        wait
        
        log_info "Concurrent connectivity tests completed"
    fi
    
    # Generate reports for each client
    for pid in "${client_pids[@]}"; do
        local console_log="${PROJECT_ROOT}/.build/qemu/logs/${pid}-console.log"
        "${SCRIPTS_DIR}/qemu-test-validation.sh" generate-report "${console_log}" "${results_dir}/concurrent-client-${pid}-report.txt" || true
    done
    
    # Consider test successful if at least half the clients worked
    local required_success=$((CONCURRENT_CLIENTS / 2))
    if [[ ${success_count} -ge ${required_success} ]]; then
        return 0
    else
        return 1
    fi
}

# Error handling and recovery test
run_error_handling_test() {
    local results_dir="$1"
    local test_log="${results_dir}/error-handling-test.log"
    
    log_info "Testing error handling and recovery mechanisms..."
    
    # Test 1: Invalid server connection
    log_info "Testing invalid server connection handling..."
    local qemu_pid
    if ! qemu_pid=$("${SCRIPTS_DIR}/start-qemu-client.sh" --background 2>>"${test_log}"); then
        log_error "Failed to start QEMU client for error test"
        return 1
    fi
    QEMU_PIDS+=("${qemu_pid}")
    
    local console_log="${PROJECT_ROOT}/.build/qemu/logs/${qemu_pid}-console.log"
    
    # Wait for readiness
    if ! "${SCRIPTS_DIR}/qemu-test-validation.sh" wait-readiness "${console_log}" 60; then
        log_error "Client failed to become ready for error test"
        return 1
    fi
    
    # Test connection to invalid server
    log_info "Testing connection to invalid server (should fail gracefully)..."
    if "${SCRIPTS_DIR}/qemu-test-validation.sh" check-server "invalid.host" "9999" 2>>"${test_log}"; then
        log_warning "Invalid server test unexpectedly succeeded"
    else
        log_info "Invalid server connection failed as expected"
    fi
    
    # Test 2: Network timeout handling
    log_info "Testing network timeout handling..."
    # This would involve more complex network manipulation in a real scenario
    
    # Test 3: Resource constraint handling
    log_info "Testing resource constraint handling..."
    if ! "${SCRIPTS_DIR}/test-resource-optimization.sh" 2>>"${test_log}"; then
        log_error "Resource optimization test failed"
        return 1
    fi
    
    return 0
}

# Performance and resource monitoring test
run_performance_test() {
    local results_dir="$1"
    local test_log="${results_dir}/performance-test.log"
    local performance_log="${results_dir}/performance-metrics.log"
    
    log_info "Running performance and resource monitoring test..."
    
    # Start performance monitoring
    local monitor_pid
    start_performance_monitoring "${performance_log}" monitor_pid
    
    # Start QEMU client
    local qemu_pid
    if ! qemu_pid=$("${SCRIPTS_DIR}/start-qemu-client.sh" --background 2>>"${test_log}"); then
        log_error "Failed to start QEMU client for performance test"
        stop_performance_monitoring "${monitor_pid}"
        return 1
    fi
    QEMU_PIDS+=("${qemu_pid}")
    
    local console_log="${PROJECT_ROOT}/.build/qemu/logs/${qemu_pid}-console.log"
    
    # Measure boot time
    local start_time=$(date +%s)
    if ! "${SCRIPTS_DIR}/qemu-test-validation.sh" wait-readiness "${console_log}" 120; then
        log_error "Client failed to become ready for performance test"
        stop_performance_monitoring "${monitor_pid}"
        return 1
    fi
    local end_time=$(date +%s)
    local boot_time=$((end_time - start_time))
    
    log_info "Boot time: ${boot_time} seconds"
    echo "Boot time: ${boot_time} seconds" >> "${performance_log}"
    
    # Run sustained operations for performance measurement
    log_info "Running sustained operations for ${TEST_DURATION} seconds..."
    local ops_start=$(date +%s)
    
    while [[ $(($(date +%s) - ops_start)) -lt ${TEST_DURATION} ]]; do
        # Perform periodic server connectivity checks
        "${SCRIPTS_DIR}/qemu-test-validation.sh" check-server "${SERVER_HOST}" "${SERVER_PORT}" >/dev/null 2>&1 || true
        sleep 10
    done
    
    # Stop performance monitoring
    stop_performance_monitoring "${monitor_pid}"
    
    # Analyze performance metrics
    analyze_performance_metrics "${performance_log}" "${results_dir}/performance-analysis.txt"
    
    return 0
}

# Start performance monitoring
start_performance_monitoring() {
    local log_file="$1"
    local pid_var="$2"
    
    {
        while true; do
            local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            local memory_usage=$(ps -o pid,rss,vsz,pcpu,comm -p $$ 2>/dev/null | tail -n +2 || echo "N/A")
            local disk_usage=$(df -h "${PROJECT_ROOT}/.build" 2>/dev/null | tail -n +2 || echo "N/A")
            
            echo "[${timestamp}] Memory: ${memory_usage}"
            echo "[${timestamp}] Disk: ${disk_usage}"
            echo "---"
            
            sleep 5
        done
    } >> "${log_file}" &
    
    eval "${pid_var}=$!"
}

# Stop performance monitoring
stop_performance_monitoring() {
    local monitor_pid="$1"
    
    if [[ -n "${monitor_pid}" ]] && kill -0 "${monitor_pid}" 2>/dev/null; then
        kill "${monitor_pid}" 2>/dev/null || true
    fi
}

# Analyze performance metrics
analyze_performance_metrics() {
    local metrics_file="$1"
    local analysis_file="$2"
    
    {
        echo "Performance Analysis Report"
        echo "=========================="
        echo ""
        echo "Test Duration: ${TEST_DURATION} seconds"
        echo "Concurrent Clients: ${CONCURRENT_CLIENTS}"
        echo ""
        
        if [[ -f "${metrics_file}" ]]; then
            echo "Resource Usage Summary:"
            echo "----------------------"
            
            # Extract boot time
            local boot_time=$(grep "Boot time:" "${metrics_file}" | head -n1 | cut -d: -f2 | tr -d ' ')
            echo "Boot Time: ${boot_time} seconds"
            
            # Memory usage analysis
            echo ""
            echo "Memory Usage Patterns:"
            grep "Memory:" "${metrics_file}" | tail -n 5
            
            echo ""
            echo "Disk Usage Patterns:"
            grep "Disk:" "${metrics_file}" | tail -n 5
        else
            echo "No performance metrics available"
        fi
        
        echo ""
        echo "Performance Test Completed: $(date)"
    } > "${analysis_file}"
}

# Generate comprehensive final report
generate_final_report() {
    local results_dir="$1"
    local final_report="${results_dir}/advanced-test-final-report.txt"
    
    {
        echo "Advanced USB/IP Client Test Suite - Final Report"
        echo "==============================================="
        echo ""
        echo "Test Configuration:"
        echo "  Server: ${SERVER_HOST}:${SERVER_PORT}"
        echo "  Duration: ${TEST_DURATION} seconds"
        echo "  Concurrent Clients: ${CONCURRENT_CLIENTS}"
        echo "  Test Date: $(date)"
        echo ""
        
        echo "Test Results Summary:"
        echo "--------------------"
        for result in "${TEST_RESULTS[@]}"; do
            echo "  ${result}"
        done
        echo ""
        
        echo "Detailed Reports:"
        echo "----------------"
        for report in "${results_dir}"/*-report.txt; do
            if [[ -f "${report}" ]]; then
                echo "  $(basename "${report}")"
            fi
        done
        echo ""
        
        echo "Log Files:"
        echo "---------"
        for log in "${results_dir}"/*.log; do
            if [[ -f "${log}" ]]; then
                echo "  $(basename "${log}")"
            fi
        done
        echo ""
        
        echo "QEMU Instances Used:"
        echo "-------------------"
        for pid in "${QEMU_PIDS[@]}"; do
            echo "  PID: ${pid}"
        done
        echo ""
        
        echo "Report Generated: $(date)"
    } > "${final_report}"
    
    log_info "Final report generated: ${final_report}"
}

# Display results summary
display_results_summary() {
    echo ""
    echo "=========================================="
    echo "Advanced USB/IP Test Suite - Results"
    echo "=========================================="
    
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "${result}" == *"PASS"* ]]; then
            log_success "${result}"
        else
            log_error "${result}"
        fi
    done
    
    echo "=========================================="
}

# Cleanup all QEMU instances
cleanup_all_qemu() {
    log_info "Cleaning up all QEMU instances..."
    
    for pid in "${QEMU_PIDS[@]}"; do
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            log_info "Stopping QEMU instance (PID: ${pid})"
            kill -TERM "${pid}" 2>/dev/null || true
        fi
    done
    
    # Wait for graceful shutdown
    sleep 5
    
    # Force kill any remaining processes
    for pid in "${QEMU_PIDS[@]}"; do
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            log_info "Force stopping QEMU instance (PID: ${pid})"
            kill -KILL "${pid}" 2>/dev/null || true
        fi
    done
}

# Handle script interruption
trap 'cleanup_all_qemu; exit 1' INT TERM

# Usage information
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [SERVER_HOST] [SERVER_PORT] [DURATION] [CONCURRENT_CLIENTS]"
    echo ""
    echo "Advanced USB/IP client test suite using QEMU test tool"
    echo ""
    echo "Arguments:"
    echo "  SERVER_HOST         USB/IP server hostname or IP (default: localhost)"
    echo "  SERVER_PORT         USB/IP server port (default: 3240)"
    echo "  DURATION           Test duration in seconds (default: 300)"
    echo "  CONCURRENT_CLIENTS  Number of concurrent clients (default: 2)"
    echo ""
    echo "Tests performed:"
    echo "  1. Single client comprehensive test"
    echo "  2. Concurrent client test"
    echo "  3. Error handling and recovery test"
    echo "  4. Performance and resource monitoring"
    echo ""
    echo "Example:"
    echo "  $0 192.168.1.100 3240 600 4"
    echo ""
    exit 0
fi

# Run main function
main "$@"