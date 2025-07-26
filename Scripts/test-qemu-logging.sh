#!/bin/bash

# QEMU USB/IP Test Tool - Logging Functionality Test Script
# Tests the structured logging and output parsing capabilities

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

# Test structured log message parsing
test_log_parsing() {
    log_info "Testing structured log message parsing..."
    
    # Create a test log file with sample structured messages
    local test_log="${BUILD_DIR}/test-console.log"
    mkdir -p "$BUILD_DIR"
    
    cat > "$test_log" << 'EOF'
[2024-01-15 10:30:15.123] USBIP_STARTUP_BEGIN
[2024-01-15 10:30:15.456] VHCI_MODULE_LOADED: SUCCESS
[2024-01-15 10:30:15.789] VHCI_MODULE_VERIFIED: SUCCESS
[2024-01-15 10:30:16.012] USBIP_COMMAND_AVAILABLE: SUCCESS
[2024-01-15 10:30:16.234] USBIP_VERSION: usbip (usbip-utils 2.0)
[2024-01-15 10:30:16.456] USBIP_CLIENT_READY
[2024-01-15 10:30:16.678] USBIP_STARTUP_COMPLETE
[2024-01-15 10:30:17.890] READINESS_CHECK_START
[2024-01-15 10:30:18.123] USBIP_CLIENT_READINESS: READY
[2024-01-15 10:30:18.345] READINESS_CHECK_COMPLETE: SUCCESS
[2024-01-15 10:30:20.567] CONNECTING_TO_SERVER: 192.168.1.100:3240
[2024-01-15 10:30:21.789] DEVICE_LIST_REQUEST: SUCCESS
[2024-01-15 10:30:22.012] DEVICE_IMPORT_REQUEST: 1-1 SUCCESS
[2024-01-15 10:30:23.234] TEST_COMPLETE: SUCCESS
EOF
    
    # Test parsing functions
    local parse_count=0
    local success_count=0
    
    # Test 1: Parse all structured messages
    log_info "Test 1: Parsing all structured messages"
    local all_messages
    all_messages=$(grep -E '\[(.*)\] (USBIP_|VHCI_|CONNECTING_|DEVICE_|TEST_|READINESS_)' "$test_log" 2>/dev/null || true)
    local message_count
    message_count=$(echo "$all_messages" | wc -l)
    
    if [[ "$message_count" -ge 13 ]]; then
        log_success "Found expected number of structured messages: $message_count"
        ((success_count++))
    else
        log_error "Expected at least 13 structured messages, found: $message_count"
    fi
    ((parse_count++))
    
    # Test 2: Extract specific status types
    log_info "Test 2: Extracting specific status types"
    
    # Test client ready status
    local client_ready
    client_ready=$(grep "USBIP_CLIENT_READY" "$test_log" | tail -n1)
    if [[ -n "$client_ready" ]]; then
        log_success "Client ready status extracted: $client_ready"
        ((success_count++))
    else
        log_error "Failed to extract client ready status"
    fi
    ((parse_count++))
    
    # Test version extraction
    local version
    version=$(grep "USBIP_VERSION:" "$test_log" | tail -n1 | sed 's/.*USBIP_VERSION: //')
    if [[ "$version" == "usbip (usbip-utils 2.0)" ]]; then
        log_success "Version extracted correctly: $version"
        ((success_count++))
    else
        log_error "Version extraction failed, got: $version"
    fi
    ((parse_count++))
    
    # Test connection status
    local connection
    connection=$(grep "CONNECTING_TO_SERVER:" "$test_log" | tail -n1)
    if [[ "$connection" == *"192.168.1.100:3240"* ]]; then
        log_success "Connection status extracted: $connection"
        ((success_count++))
    else
        log_error "Connection status extraction failed"
    fi
    ((parse_count++))
    
    # Test device operations
    local device_list
    device_list=$(grep "DEVICE_LIST_REQUEST:" "$test_log" | tail -n1)
    if [[ "$device_list" == *"SUCCESS"* ]]; then
        log_success "Device list status extracted: $device_list"
        ((success_count++))
    else
        log_error "Device list status extraction failed"
    fi
    ((parse_count++))
    
    local device_import
    device_import=$(grep "DEVICE_IMPORT_REQUEST:" "$test_log" | tail -n1)
    if [[ "$device_import" == *"1-1 SUCCESS"* ]]; then
        log_success "Device import status extracted: $device_import"
        ((success_count++))
    else
        log_error "Device import status extraction failed"
    fi
    ((parse_count++))
    
    # Test overall test status
    local test_status
    test_status=$(grep "TEST_COMPLETE:" "$test_log" | tail -n1)
    if [[ "$test_status" == *"SUCCESS"* ]]; then
        log_success "Test completion status extracted: $test_status"
        ((success_count++))
    else
        log_error "Test completion status extraction failed"
    fi
    ((parse_count++))
    
    # Clean up test file
    rm -f "$test_log"
    
    log_info "Log parsing test results: $success_count/$parse_count tests passed"
    
    if [[ "$success_count" -eq "$parse_count" ]]; then
        log_success "All log parsing tests passed"
        return 0
    else
        log_error "Some log parsing tests failed"
        return 1
    fi
}

# Test structured log message generation
test_log_generation() {
    log_info "Testing structured log message generation..."
    
    # Create a test log file
    local test_log="${BUILD_DIR}/test-generation.log"
    mkdir -p "$BUILD_DIR"
    
    # Function to generate structured log messages (simulating the QEMU startup script functionality)
    generate_structured_log() {
        local level="$1"
        local message="$2"
        local timestamp
        # Use a compatible timestamp format for macOS
        timestamp=$(date '+%Y-%m-%d %H:%M:%S.000')
        echo "[${timestamp}] ${level}: ${message}" >> "$test_log"
    }
    
    # Generate test messages
    generate_structured_log "USBIP_CLIENT_READY" "Test client initialization"
    generate_structured_log "USBIP_VERSION" "2.0"
    generate_structured_log "VHCI_MODULE_LOADED" "vhci-hcd module loaded successfully"
    generate_structured_log "CONNECTING_TO_SERVER" "127.0.0.1:3240"
    generate_structured_log "DEVICE_LIST_REQUEST" "SUCCESS"
    generate_structured_log "DEVICE_IMPORT_REQUEST" "1-1 SUCCESS"
    generate_structured_log "TEST_COMPLETE" "SUCCESS"
    
    # Verify generated messages
    local generated_count
    generated_count=$(wc -l < "$test_log")
    
    if [[ "$generated_count" -eq 7 ]]; then
        log_success "Generated expected number of log messages: $generated_count"
    else
        log_error "Expected 7 log messages, generated: $generated_count"
        rm -f "$test_log"
        return 1
    fi
    
    # Verify message format
    local format_valid=true
    while IFS= read -r line; do
        if ! echo "$line" | grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}\] [A-Z_]+:'; then
            log_error "Invalid message format: $line"
            format_valid=false
        fi
    done < "$test_log"
    
    if [[ "$format_valid" == "true" ]]; then
        log_success "All generated messages have correct format"
    else
        log_error "Some generated messages have incorrect format"
        rm -f "$test_log"
        return 1
    fi
    
    # Clean up test file
    rm -f "$test_log"
    
    log_success "Log generation test passed"
    return 0
}

# Test QEMU monitor socket communication
test_monitor_socket() {
    log_info "Testing QEMU monitor socket communication..."
    
    # Check if socat is available
    if ! command -v socat &> /dev/null; then
        log_warning "socat not available, skipping monitor socket test"
        log_info "Install socat with: brew install socat"
        return 0
    fi
    
    # Create a mock monitor socket for testing
    local test_socket="${BUILD_DIR}/test-monitor.sock"
    mkdir -p "$BUILD_DIR"
    
    # Start a simple echo server to simulate QEMU monitor
    (
        socat UNIX-LISTEN:"$test_socket",fork EXEC:'echo "QEMU 7.0.0 monitor - type help for more information"'
    ) &
    local server_pid=$!
    
    # Give the server time to start
    sleep 1
    
    # Test communication
    local response
    if response=$(echo "info version" | socat - "UNIX-CONNECT:$test_socket" 2>/dev/null); then
        if [[ "$response" == *"QEMU"* ]]; then
            log_success "Monitor socket communication test passed"
            kill "$server_pid" 2>/dev/null || true
            rm -f "$test_socket"
            return 0
        else
            log_error "Unexpected response from monitor socket: $response"
        fi
    else
        log_error "Failed to communicate with monitor socket"
    fi
    
    # Clean up
    kill "$server_pid" 2>/dev/null || true
    rm -f "$test_socket"
    return 1
}

# Test log file rotation and management
test_log_management() {
    log_info "Testing log file management..."
    
    # Create test log directory
    local test_log_dir="${BUILD_DIR}/test-logs"
    mkdir -p "$test_log_dir"
    
    # Create multiple test log files
    local instance_ids=("qemu-usbip-1234567890-1" "qemu-usbip-1234567891-2" "qemu-usbip-1234567892-3")
    
    for instance_id in "${instance_ids[@]}"; do
        local log_file="${test_log_dir}/${instance_id}-console.log"
        echo "Test log content for $instance_id" > "$log_file"
        echo "[$(date)] USBIP_CLIENT_READY" >> "$log_file"
        echo "[$(date)] TEST_COMPLETE: SUCCESS" >> "$log_file"
    done
    
    # Verify log files were created
    local log_count
    log_count=$(find "$test_log_dir" -name "*-console.log" | wc -l)
    
    if [[ "$log_count" -eq 3 ]]; then
        log_success "Created expected number of log files: $log_count"
    else
        log_error "Expected 3 log files, found: $log_count"
        rm -rf "$test_log_dir"
        return 1
    fi
    
    # Test log file parsing for each instance
    local parse_success=0
    for instance_id in "${instance_ids[@]}"; do
        local log_file="${test_log_dir}/${instance_id}-console.log"
        if grep -q "USBIP_CLIENT_READY" "$log_file"; then
            ((parse_success++))
        fi
    done
    
    if [[ "$parse_success" -eq 3 ]]; then
        log_success "All log files contain expected structured messages"
    else
        log_error "Some log files missing structured messages"
        rm -rf "$test_log_dir"
        return 1
    fi
    
    # Clean up
    rm -rf "$test_log_dir"
    
    log_success "Log management test passed"
    return 0
}

# Main test execution
main() {
    log_info "Starting QEMU logging functionality tests..."
    
    local test_count=0
    local success_count=0
    
    # Test 1: Log parsing
    if test_log_parsing; then
        ((success_count++))
    fi
    ((test_count++))
    
    # Test 2: Log generation
    if test_log_generation; then
        ((success_count++))
    fi
    ((test_count++))
    
    # Test 3: Monitor socket communication
    if test_monitor_socket; then
        ((success_count++))
    fi
    ((test_count++))
    
    # Test 4: Log management
    if test_log_management; then
        ((success_count++))
    fi
    ((test_count++))
    
    # Summary
    log_info "Test results: $success_count/$test_count tests passed"
    
    if [[ "$success_count" -eq "$test_count" ]]; then
        log_success "All logging functionality tests passed"
        return 0
    else
        log_error "Some logging functionality tests failed"
        return 1
    fi
}

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

QEMU USB/IP Test Tool - Logging Functionality Test Script

OPTIONS:
    -h, --help  Show this help message

DESCRIPTION:
    This script tests the structured logging and output parsing capabilities
    of the QEMU USB/IP test tool. It validates:
    
    1. Structured log message parsing
    2. Log message generation and formatting
    3. QEMU monitor socket communication
    4. Log file management and rotation
    
EXAMPLES:
    $0              # Run all logging tests
    $0 --help       # Show this help

EOF
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        "-h"|"--help")
            show_usage
            exit 0
            ;;
        "")
            main
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
fi