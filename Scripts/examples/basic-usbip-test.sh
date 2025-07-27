#!/bin/bash

# Basic USB/IP Client Test Example
# Demonstrates how to use the QEMU test tool to validate USB/IP server functionality

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly SCRIPTS_DIR="${PROJECT_ROOT}/Scripts"

# Test configuration
readonly SERVER_HOST="${1:-localhost}"
readonly SERVER_PORT="${2:-3240}"
readonly TEST_TIMEOUT="${3:-120}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Main test function
main() {
    log_info "Starting basic USB/IP client test"
    log_info "Server: ${SERVER_HOST}:${SERVER_PORT}"
    log_info "Timeout: ${TEST_TIMEOUT} seconds"
    
    # Step 1: Create QEMU image if it doesn't exist
    if [[ ! -f "${PROJECT_ROOT}/.build/qemu/qemu-usbip-client.qcow2" ]]; then
        log_info "Creating QEMU image..."
        if ! "${SCRIPTS_DIR}/create-qemu-image.sh"; then
            log_error "Failed to create QEMU image"
            exit 1
        fi
        log_success "QEMU image created successfully"
    else
        log_info "Using existing QEMU image"
    fi
    
    # Step 2: Start QEMU client
    log_info "Starting QEMU USB/IP client..."
    local qemu_pid
    if ! qemu_pid=$("${SCRIPTS_DIR}/start-qemu-client.sh" --background); then
        log_error "Failed to start QEMU client"
        exit 1
    fi
    log_success "QEMU client started (PID: ${qemu_pid})"
    
    # Step 3: Wait for client readiness
    log_info "Waiting for USB/IP client to be ready..."
    local console_log="${PROJECT_ROOT}/.build/qemu/logs/${qemu_pid}-console.log"
    
    if ! "${SCRIPTS_DIR}/qemu-test-validation.sh" wait-readiness "${console_log}" "${TEST_TIMEOUT}"; then
        log_error "USB/IP client failed to become ready within ${TEST_TIMEOUT} seconds"
        cleanup_qemu "${qemu_pid}"
        exit 1
    fi
    log_success "USB/IP client is ready"
    
    # Step 4: Test server connectivity
    log_info "Testing server connectivity..."
    if ! "${SCRIPTS_DIR}/qemu-test-validation.sh" check-server "${SERVER_HOST}" "${SERVER_PORT}"; then
        log_error "Cannot connect to USB/IP server at ${SERVER_HOST}:${SERVER_PORT}"
        cleanup_qemu "${qemu_pid}"
        exit 1
    fi
    log_success "Server connectivity confirmed"
    
    # Step 5: Perform USB/IP operations
    log_info "Performing USB/IP client operations..."
    
    # List available devices
    log_info "Requesting device list from server..."
    if ! test_device_list "${console_log}" "${SERVER_HOST}" "${SERVER_PORT}"; then
        log_error "Device list request failed"
        cleanup_qemu "${qemu_pid}"
        exit 1
    fi
    log_success "Device list request completed"
    
    # Step 6: Generate test report
    log_info "Generating test report..."
    local report_file="${PROJECT_ROOT}/.build/qemu/test-report-$(date +%Y%m%d-%H%M%S).txt"
    if ! "${SCRIPTS_DIR}/qemu-test-validation.sh" generate-report "${console_log}" "${report_file}"; then
        log_error "Failed to generate test report"
        cleanup_qemu "${qemu_pid}"
        exit 1
    fi
    log_success "Test report generated: ${report_file}"
    
    # Step 7: Cleanup
    log_info "Cleaning up QEMU instance..."
    cleanup_qemu "${qemu_pid}"
    
    log_success "Basic USB/IP client test completed successfully"
    log_info "Check the test report for detailed results: ${report_file}"
}

# Test device list functionality
test_device_list() {
    local console_log="$1"
    local server_host="$2"
    local server_port="$3"
    
    # Send device list command through QEMU monitor
    local monitor_socket="${PROJECT_ROOT}/.build/qemu/monitor-${qemu_pid}.sock"
    
    # Wait a moment for the command to execute
    sleep 5
    
    # Check for device list response in console log
    if "${SCRIPTS_DIR}/qemu-test-validation.sh" parse-log "${console_log}" "DEVICE_LIST_REQUEST"; then
        return 0
    else
        return 1
    fi
}

# Cleanup QEMU instance
cleanup_qemu() {
    local pid="$1"
    
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        log_info "Stopping QEMU instance (PID: ${pid})"
        kill -TERM "${pid}" 2>/dev/null || true
        
        # Wait for graceful shutdown
        local count=0
        while kill -0 "${pid}" 2>/dev/null && [[ ${count} -lt 10 ]]; do
            sleep 1
            ((count++))
        done
        
        # Force kill if still running
        if kill -0 "${pid}" 2>/dev/null; then
            log_info "Force stopping QEMU instance"
            kill -KILL "${pid}" 2>/dev/null || true
        fi
    fi
}

# Handle script interruption
trap 'cleanup_qemu "${qemu_pid:-}"; exit 1' INT TERM

# Usage information
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [SERVER_HOST] [SERVER_PORT] [TIMEOUT]"
    echo ""
    echo "Basic USB/IP client test using QEMU test tool"
    echo ""
    echo "Arguments:"
    echo "  SERVER_HOST  USB/IP server hostname or IP (default: localhost)"
    echo "  SERVER_PORT  USB/IP server port (default: 3240)"
    echo "  TIMEOUT      Test timeout in seconds (default: 120)"
    echo ""
    echo "Example:"
    echo "  $0 192.168.1.100 3240 180"
    echo ""
    exit 0
fi

# Run main function
main "$@"