#!/bin/bash

# QEMU USB/IP Test Tool - Test Validation Utilities with Environment Awareness
# Helper functions for parsing QEMU console output and validating test results
# Enhanced with environment-specific validation and test environment integration

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/.build/qemu"
readonly LOG_DIR="${BUILD_DIR}/logs"

# Test Environment Detection (initialized after function definition)

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Environment Detection Function
detect_test_environment() {
    # Check for CI environment variables
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

# Initialize test environment after function definition
readonly TEST_ENVIRONMENT="${TEST_ENVIRONMENT:-$(detect_test_environment)}"

# Environment-specific timeout configurations
get_readiness_timeout() {
    case "$TEST_ENVIRONMENT" in
        "development")
            echo 30
            ;;
        "ci")
            echo 60
            ;;
        "production")
            echo 120
            ;;
        *)
            echo 60
            ;;
    esac
}

get_connection_timeout() {
    case "$TEST_ENVIRONMENT" in
        "development")
            echo 5
            ;;
        "ci")
            echo 10
            ;;
        "production")
            echo 30
            ;;
        *)
            echo 10
            ;;
    esac
}

get_command_timeout() {
    case "$TEST_ENVIRONMENT" in
        "development")
            echo 15
            ;;
        "ci")
            echo 30
            ;;
        "production")
            echo 60
            ;;
        *)
            echo 30
            ;;
    esac
}

# Dynamic timeout configurations based on environment
readonly DEFAULT_READINESS_TIMEOUT=$(get_readiness_timeout)
readonly DEFAULT_CONNECTION_TIMEOUT=$(get_connection_timeout)
readonly DEFAULT_COMMAND_TIMEOUT=$(get_command_timeout)

# Environment-aware logging functions
log_info() {
    echo -e "${BLUE}[INFO:${TEST_ENVIRONMENT}]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS:${TEST_ENVIRONMENT}]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING:${TEST_ENVIRONMENT}]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR:${TEST_ENVIRONMENT}]${NC} $1"
}

log_environment() {
    echo -e "${BLUE}[ENVIRONMENT]${NC} Running in ${TEST_ENVIRONMENT} mode"
    echo -e "${BLUE}[ENVIRONMENT]${NC} Readiness timeout: ${DEFAULT_READINESS_TIMEOUT}s"
    echo -e "${BLUE}[ENVIRONMENT]${NC} Connection timeout: ${DEFAULT_CONNECTION_TIMEOUT}s"
    echo -e "${BLUE}[ENVIRONMENT]${NC} Command timeout: ${DEFAULT_COMMAND_TIMEOUT}s"
}

# ============================================================================
# CONSOLE OUTPUT PARSING FUNCTIONS
# ============================================================================

# Parse structured messages from QEMU console output
parse_console_log() {
    local log_file="$1"
    local message_type="${2:-}"
    local count="${3:-all}"
    
    if [[ ! -f "$log_file" ]]; then
        log_error "Console log file not found: $log_file"
        return 1
    fi
    
    if [[ -z "$message_type" ]]; then
        # Return all structured messages
        grep -E '\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9]\] [A-Z_]+' "$log_file" 2>/dev/null || true
    else
        # Return specific message type
        if [[ "$count" == "all" ]]; then
            grep -E "\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9]\] ${message_type}" "$log_file" 2>/dev/null || true
        else
            grep -E "\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9]\] ${message_type}" "$log_file" 2>/dev/null | tail -n"$count" || true
        fi
    fi
}

# Extract timestamp from structured log message
extract_timestamp() {
    local log_message="$1"
    
    echo "$log_message" | sed -n 's/^\[\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\.[0-9][0-9][0-9]\)\].*/\1/p'
}

# Extract message content from structured log message
extract_message_content() {
    local log_message="$1"
    
    echo "$log_message" | sed -n 's/^\[[^]]*\] [A-Z_]*: \(.*\)/\1/p'
}

# Parse USB/IP version information
parse_usbip_version() {
    local log_file="$1"
    
    local version_line
    version_line=$(parse_console_log "$log_file" "USBIP_VERSION")
    
    if [[ -n "$version_line" ]]; then
        extract_message_content "$version_line"
    else
        return 1
    fi
}

# Parse device list from console output
parse_device_list() {
    local log_file="$1"
    
    local device_messages
    device_messages=$(parse_console_log "$log_file" "DEVICE_LIST_RESPONSE")
    
    if [[ -n "$device_messages" ]]; then
        echo "$device_messages" | while IFS= read -r line; do
            extract_message_content "$line"
        done
    else
        return 1
    fi
}

# Parse connection status
parse_connection_status() {
    local log_file="$1"
    local server_address="${2:-}"
    
    if [[ -n "$server_address" ]]; then
        # Look for specific server connection
        parse_console_log "$log_file" "CONNECTING_TO_SERVER" | grep "$server_address" | tail -n1
    else
        # Return latest connection attempt
        parse_console_log "$log_file" "CONNECTING_TO_SERVER" | tail -n1
    fi
}

# ============================================================================
# USB/IP CLIENT READINESS DETECTION
# ============================================================================

# Check if USB/IP client is ready
is_usbip_client_ready() {
    local log_file="$1"
    
    if parse_console_log "$log_file" "USBIP_CLIENT_READY" | grep -q "USBIP_CLIENT_READY"; then
        return 0
    else
        return 1
    fi
}

# Check if vhci-hcd module is loaded
is_vhci_module_loaded() {
    local log_file="$1"
    
    if parse_console_log "$log_file" "VHCI_MODULE_LOADED" | grep -q "SUCCESS"; then
        return 0
    else
        return 1
    fi
}

# Check if cloud-init completed
is_cloud_init_complete() {
    local log_file="$1"
    
    if parse_console_log "$log_file" "CLOUD_INIT_COMPLETE" | grep -q "CLOUD_INIT_COMPLETE"; then
        return 0
    elif grep -q "Cloud-init.*finished" "$log_file" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Wait for USB/IP client readiness with timeout
wait_for_usbip_readiness() {
    local log_file="$1"
    local timeout="${2:-$DEFAULT_READINESS_TIMEOUT}"
    local check_interval="${3:-2}"
    
    log_info "Waiting for USB/IP client readiness (timeout: ${timeout}s)..."
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if is_usbip_client_ready "$log_file"; then
            log_success "USB/IP client ready after ${elapsed}s"
            return 0
        fi
        
        # Check for error conditions
        if grep -q "USBIP_CLIENT_FAILED\|VHCI_MODULE_FAILED\|BOOT_FAILED" "$log_file" 2>/dev/null; then
            log_error "USB/IP client initialization failed"
            return 1
        fi
        
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
        
        # Progress indicator
        if [[ $((elapsed % 10)) -eq 0 ]]; then
            log_info "Still waiting for readiness... (${elapsed}/${timeout}s)"
        fi
    done
    
    log_error "USB/IP client readiness timeout after ${timeout}s"
    return 1
}

# Get comprehensive readiness status
get_readiness_status() {
    local log_file="$1"
    
    local status_report=""
    
    # Check individual components
    if is_usbip_client_ready "$log_file"; then
        status_report="${status_report}✓ USB/IP client ready\n"
    else
        status_report="${status_report}✗ USB/IP client not ready\n"
    fi
    
    if is_vhci_module_loaded "$log_file"; then
        status_report="${status_report}✓ vhci-hcd module loaded\n"
    else
        status_report="${status_report}✗ vhci-hcd module not loaded\n"
    fi
    
    if is_cloud_init_complete "$log_file"; then
        status_report="${status_report}✓ Cloud-init completed\n"
    else
        status_report="${status_report}✗ Cloud-init not completed\n"
    fi
    
    # Check for version information
    local version
    if version=$(parse_usbip_version "$log_file"); then
        status_report="${status_report}✓ USB/IP version: $version\n"
    else
        status_report="${status_report}✗ USB/IP version not available\n"
    fi
    
    echo -e "$status_report"
}

# ============================================================================
# TEST RESULT VALIDATION AND REPORTING
# ============================================================================

# Validate test completion status
validate_test_completion() {
    local log_file="$1"
    local expected_status="${2:-SUCCESS}"
    
    local completion_message
    completion_message=$(parse_console_log "$log_file" "TEST_COMPLETE" | tail -n1)
    
    if [[ -z "$completion_message" ]]; then
        log_error "No test completion message found"
        return 1
    fi
    
    local actual_status
    actual_status=$(extract_message_content "$completion_message")
    
    if [[ "$actual_status" == "$expected_status" ]]; then
        log_success "Test completed with expected status: $actual_status"
        return 0
    else
        log_error "Test completed with unexpected status: $actual_status (expected: $expected_status)"
        return 1
    fi
}

# Validate device operations
validate_device_operations() {
    local log_file="$1"
    
    local validation_passed=true
    
    # Check device list operation
    local device_list_status
    device_list_status=$(parse_console_log "$log_file" "DEVICE_LIST_REQUEST" | tail -n1)
    
    if [[ -n "$device_list_status" ]]; then
        if echo "$device_list_status" | grep -q "SUCCESS"; then
            log_success "Device list operation: SUCCESS"
        else
            log_error "Device list operation failed"
            validation_passed=false
        fi
    else
        log_warning "No device list operation found"
    fi
    
    # Check device import operations
    local import_operations
    import_operations=$(parse_console_log "$log_file" "DEVICE_IMPORT_REQUEST")
    
    if [[ -n "$import_operations" ]]; then
        local import_count=0
        local import_success=0
        
        while IFS= read -r import_line; do
            import_count=$((import_count + 1))
            if echo "$import_line" | grep -q "SUCCESS"; then
                import_success=$((import_success + 1))
            fi
        done <<< "$import_operations"
        
        log_info "Device import operations: $import_success/$import_count successful"
        
        if [[ $import_success -eq $import_count ]]; then
            log_success "All device import operations successful"
        else
            log_error "Some device import operations failed"
            validation_passed=false
        fi
    else
        log_info "No device import operations found"
    fi
    
    if [[ "$validation_passed" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Generate test report
generate_test_report() {
    local log_file="$1"
    local report_file="${2:-${log_file%.log}-report.txt}"
    
    log_info "Generating test report: $(basename "$report_file")"
    
    {
        echo "QEMU USB/IP Test Tool - Test Report"
        echo "=================================="
        echo "Generated: $(date)"
        echo "Console Log: $(basename "$log_file")"
        echo ""
        
        # Basic information
        echo "Test Environment:"
        echo "  OS: $(uname -s)"
        echo "  Architecture: $(uname -m)"
        echo "  Kernel: $(uname -r)"
        echo ""
        
        # Readiness status
        echo "Readiness Status:"
        get_readiness_status "$log_file" | sed 's/^/  /'
        echo ""
        
        # Test timeline
        echo "Test Timeline:"
        local structured_messages
        structured_messages=$(parse_console_log "$log_file")
        
        if [[ -n "$structured_messages" ]]; then
            echo "$structured_messages" | head -n20 | sed 's/^/  /'
            
            local total_messages
            total_messages=$(echo "$structured_messages" | wc -l)
            if [[ $total_messages -gt 20 ]]; then
                echo "  ... (${total_messages} total messages, showing first 20)"
            fi
        else
            echo "  No structured messages found"
        fi
        echo ""
        
        # Error analysis
        echo "Error Analysis:"
        local error_patterns=("ERROR" "FAILED" "TIMEOUT" "CRASH" "PANIC")
        local errors_found=false
        
        for pattern in "${error_patterns[@]}"; do
            local error_count
            error_count=$(grep -c "$pattern" "$log_file" 2>/dev/null || echo "0")
            if [[ $error_count -gt 0 ]]; then
                echo "  $pattern: $error_count occurrences"
                errors_found=true
            fi
        done
        
        if [[ "$errors_found" == "false" ]]; then
            echo "  No error patterns detected"
        fi
        echo ""
        
        # Test summary
        echo "Test Summary:"
        if validate_test_completion "$log_file" >/dev/null 2>&1; then
            echo "  Overall Status: PASSED"
        else
            echo "  Overall Status: FAILED"
        fi
        
        if validate_device_operations "$log_file" >/dev/null 2>&1; then
            echo "  Device Operations: PASSED"
        else
            echo "  Device Operations: FAILED"
        fi
        
        local log_size
        log_size=$(wc -l < "$log_file" 2>/dev/null || echo "0")
        echo "  Console Messages: $log_size lines"
        
        local structured_count
        structured_count=$(parse_console_log "$log_file" | wc -l)
        echo "  Structured Messages: $structured_count"
        
    } > "$report_file"
    
    log_success "Test report generated: $(basename "$report_file")"
    return 0
}

# ============================================================================
# USB/IP SERVER CONNECTIVITY UTILITIES
# ============================================================================

# Check if USB/IP server is reachable
check_usbip_server_connectivity() {
    local server_host="$1"
    local server_port="${2:-3240}"
    local timeout="${3:-$DEFAULT_CONNECTION_TIMEOUT}"
    
    log_info "Checking USB/IP server connectivity: ${server_host}:${server_port}"
    
    # Use netcat or telnet to check port connectivity
    if command -v nc &> /dev/null; then
        if timeout "$timeout" nc -z "$server_host" "$server_port" 2>/dev/null; then
            log_success "USB/IP server is reachable at ${server_host}:${server_port}"
            return 0
        else
            log_error "USB/IP server is not reachable at ${server_host}:${server_port}"
            return 1
        fi
    elif command -v telnet &> /dev/null; then
        if timeout "$timeout" bash -c "echo '' | telnet $server_host $server_port" &>/dev/null; then
            log_success "USB/IP server is reachable at ${server_host}:${server_port}"
            return 0
        else
            log_error "USB/IP server is not reachable at ${server_host}:${server_port}"
            return 1
        fi
    else
        log_warning "Neither nc nor telnet available, cannot check server connectivity"
        return 1
    fi
}

# Test USB/IP server response
test_usbip_server_response() {
    local server_host="$1"
    local server_port="${2:-3240}"
    local timeout="${3:-$DEFAULT_COMMAND_TIMEOUT}"
    
    log_info "Testing USB/IP server response: ${server_host}:${server_port}"
    
    # Check basic connectivity first
    if ! check_usbip_server_connectivity "$server_host" "$server_port" "$timeout"; then
        return 1
    fi
    
    # Try to get device list (this would require usbip client tools)
    if command -v usbip &> /dev/null; then
        log_info "Attempting to list devices from server..."
        
        # Set timeout for usbip command
        if timeout "$timeout" usbip list -r "${server_host}:${server_port}" >/dev/null 2>&1; then
            log_success "USB/IP server responded to device list request"
            return 0
        else
            log_warning "USB/IP server did not respond properly to device list request"
            return 1
        fi
    else
        log_info "usbip command not available, basic connectivity check passed"
        return 0
    fi
}

# Monitor USB/IP connection status
monitor_usbip_connection() {
    local log_file="$1"
    local server_host="$2"
    local server_port="${3:-3240}"
    local duration="${4:-60}"
    local check_interval="${5:-5}"
    
    log_info "Monitoring USB/IP connection for ${duration}s (checking every ${check_interval}s)"
    
    local elapsed=0
    local connection_checks=0
    local successful_checks=0
    
    while [[ $elapsed -lt $duration ]]; do
        connection_checks=$((connection_checks + 1))
        
        if check_usbip_server_connectivity "$server_host" "$server_port" 2 >/dev/null 2>&1; then
            successful_checks=$((successful_checks + 1))
            log_info "Connection check $connection_checks: OK"
        else
            log_warning "Connection check $connection_checks: FAILED"
        fi
        
        # Check for new connection events in log
        local recent_connections
        recent_connections=$(parse_console_log "$log_file" "CONNECTING_TO_SERVER" | tail -n1)
        if [[ -n "$recent_connections" ]]; then
            log_info "Recent connection event: $recent_connections"
        fi
        
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
    done
    
    local success_rate
    success_rate=$((successful_checks * 100 / connection_checks))
    
    log_info "Connection monitoring complete:"
    log_info "  Total checks: $connection_checks"
    log_info "  Successful: $successful_checks"
    log_info "  Success rate: ${success_rate}%"
    
    if [[ $success_rate -ge 80 ]]; then
        log_success "Connection monitoring passed (${success_rate}% success rate)"
        return 0
    else
        log_error "Connection monitoring failed (${success_rate}% success rate)"
        return 1
    fi
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Validate log file format
validate_log_format() {
    local log_file="$1"
    
    if [[ ! -f "$log_file" ]]; then
        log_error "Log file not found: $log_file"
        return 1
    fi
    
    # Check for structured message format
    local structured_messages
    structured_messages=$(parse_console_log "$log_file")
    
    if [[ -z "$structured_messages" ]]; then
        log_warning "No structured messages found in log file"
        return 1
    fi
    
    # Validate timestamp format
    local invalid_timestamps=0
    while IFS= read -r message; do
        local timestamp
        timestamp=$(extract_timestamp "$message")
        if [[ -z "$timestamp" ]]; then
            invalid_timestamps=$((invalid_timestamps + 1))
        fi
    done <<< "$structured_messages"
    
    local total_messages
    total_messages=$(echo "$structured_messages" | wc -l)
    
    if [[ $invalid_timestamps -eq 0 ]]; then
        log_success "Log format validation passed ($total_messages structured messages)"
        return 0
    else
        log_error "Log format validation failed ($invalid_timestamps/$total_messages invalid timestamps)"
        return 1
    fi
}

# Get test statistics
get_test_statistics() {
    local log_file="$1"
    
    local stats=""
    
    # Count different message types
    local message_types=("USBIP_CLIENT_READY" "VHCI_MODULE_LOADED" "CONNECTING_TO_SERVER" "DEVICE_LIST_REQUEST" "DEVICE_IMPORT_REQUEST" "TEST_COMPLETE")
    
    for msg_type in "${message_types[@]}"; do
        local count
        count=$(parse_console_log "$log_file" "$msg_type" | wc -l)
        stats="${stats}${msg_type}: ${count}\n"
    done
    
    # Calculate test duration
    local first_message
    first_message=$(parse_console_log "$log_file" | head -n1)
    local last_message
    last_message=$(parse_console_log "$log_file" | tail -n1)
    
    if [[ -n "$first_message" && -n "$last_message" ]]; then
        local start_time
        start_time=$(extract_timestamp "$first_message")
        local end_time
        end_time=$(extract_timestamp "$last_message")
        
        if [[ -n "$start_time" && -n "$end_time" ]]; then
            # Convert to seconds (simplified calculation)
            local start_seconds
            start_seconds=$(date -j -f "%Y-%m-%d %H:%M:%S.%3N" "$start_time" "+%s" 2>/dev/null || echo "0")
            local end_seconds
            end_seconds=$(date -j -f "%Y-%m-%d %H:%M:%S.%3N" "$end_time" "+%s" 2>/dev/null || echo "0")
            
            if [[ $start_seconds -gt 0 && $end_seconds -gt 0 ]]; then
                local duration
                duration=$((end_seconds - start_seconds))
                stats="${stats}Test Duration: ${duration}s\n"
            fi
        fi
    fi
    
    echo -e "$stats"
}

# ============================================================================
# ENVIRONMENT-SPECIFIC VALIDATION FUNCTIONS
# ============================================================================

# Validate test environment configuration
validate_test_environment() {
    log_environment
    
    case "$TEST_ENVIRONMENT" in
        "development")
            validate_development_environment
            ;;
        "ci")
            validate_ci_environment
            ;;
        "production")
            validate_production_environment
            ;;
        *)
            log_warning "Unknown test environment: $TEST_ENVIRONMENT, using default validation"
            validate_development_environment
            ;;
    esac
}

# Validate development environment
validate_development_environment() {
    log_info "Validating development environment configuration"
    
    # Development environment focuses on speed and mocking
    if [[ $DEFAULT_READINESS_TIMEOUT -gt 60 ]]; then
        log_warning "Development environment timeout too high (${DEFAULT_READINESS_TIMEOUT}s > 60s)"
    fi
    
    # Check for development-specific directories
    if [[ ! -d "$BUILD_DIR" ]]; then
        log_info "Creating development build directory: $BUILD_DIR"
        mkdir -p "$BUILD_DIR"
    fi
    
    if [[ ! -d "$LOG_DIR" ]]; then
        log_info "Creating development log directory: $LOG_DIR"
        mkdir -p "$LOG_DIR"
    fi
    
    log_success "Development environment validation passed"
    return 0
}

# Validate CI environment
validate_ci_environment() {
    log_info "Validating CI environment configuration"
    
    # CI environment should have reliable networking and filesystem access
    if [[ -z "${CI:-}" && -z "${GITHUB_ACTIONS:-}" ]]; then
        log_warning "CI environment markers not detected"
    fi
    
    # Ensure reasonable timeouts for CI
    if [[ $DEFAULT_READINESS_TIMEOUT -lt 30 ]]; then
        log_warning "CI environment timeout may be too low (${DEFAULT_READINESS_TIMEOUT}s < 30s)"
    fi
    
    # Check for CI-specific requirements
    if ! command -v timeout &> /dev/null; then
        log_error "timeout command not available in CI environment"
        return 1
    fi
    
    log_success "CI environment validation passed"
    return 0
}

# Validate production environment
validate_production_environment() {
    log_info "Validating production environment configuration"
    
    # Production environment should have comprehensive capabilities
    if [[ $DEFAULT_READINESS_TIMEOUT -lt 60 ]]; then
        log_warning "Production environment timeout may be too low (${DEFAULT_READINESS_TIMEOUT}s < 60s)"
    fi
    
    # Check for QEMU availability
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        log_warning "QEMU not available in production environment"
    fi
    
    # Check for hardware detection capabilities
    if [[ "$(uname)" == "Darwin" ]]; then
        if ! command -v system_profiler &> /dev/null; then
            log_warning "system_profiler not available for hardware detection"
        fi
    fi
    
    log_success "Production environment validation passed"
    return 0
}

# Environment-aware test execution
run_environment_aware_validation() {
    local log_file="$1"
    local validation_type="${2:-full}"
    
    log_info "Running environment-aware validation: $validation_type"
    
    # Validate environment first
    if ! validate_test_environment; then
        log_error "Environment validation failed"
        return 1
    fi
    
    # Run validation based on environment and type
    case "$TEST_ENVIRONMENT" in
        "development")
            run_development_validation "$log_file" "$validation_type"
            ;;
        "ci")
            run_ci_validation "$log_file" "$validation_type"
            ;;
        "production")
            run_production_validation "$log_file" "$validation_type"
            ;;
        *)
            log_warning "Unknown environment, using development validation"
            run_development_validation "$log_file" "$validation_type"
            ;;
    esac
}

# Development environment validation - fast and focused
run_development_validation() {
    local log_file="$1"
    local validation_type="$2"
    
    log_info "Running development validation"
    
    # Basic validation for development
    if ! validate_log_format "$log_file"; then
        return 1
    fi
    
    # Quick readiness check
    if [[ "$validation_type" == "full" ]]; then
        if ! is_usbip_client_ready "$log_file"; then
            log_warning "USB/IP client not ready (development mode allows partial validation)"
        fi
    fi
    
    log_success "Development validation completed"
    return 0
}

# CI environment validation - reliable and comprehensive
run_ci_validation() {
    local log_file="$1"
    local validation_type="$2"
    
    log_info "Running CI validation"
    
    # Standard validation for CI
    if ! validate_log_format "$log_file"; then
        return 1
    fi
    
    # Comprehensive readiness validation
    if ! wait_for_usbip_readiness "$log_file" "$DEFAULT_READINESS_TIMEOUT"; then
        log_error "USB/IP readiness failed in CI environment"
        return 1
    fi
    
    # Device operations validation
    if [[ "$validation_type" == "full" ]]; then
        if ! validate_device_operations "$log_file"; then
            log_error "Device operations validation failed in CI environment"
            return 1
        fi
    fi
    
    log_success "CI validation completed"
    return 0
}

# Production environment validation - exhaustive and hardware-aware
run_production_validation() {
    local log_file="$1"
    local validation_type="$2"
    
    log_info "Running production validation"
    
    # Comprehensive validation for production
    if ! validate_log_format "$log_file"; then
        return 1
    fi
    
    # Full readiness validation
    if ! wait_for_usbip_readiness "$log_file" "$DEFAULT_READINESS_TIMEOUT"; then
        log_error "USB/IP readiness failed in production environment"
        return 1
    fi
    
    # Complete test validation
    if ! validate_test_completion "$log_file"; then
        log_error "Test completion validation failed in production environment"
        return 1
    fi
    
    # Device operations validation
    if ! validate_device_operations "$log_file"; then
        log_error "Device operations validation failed in production environment"
        return 1
    fi
    
    # Generate comprehensive report for production
    local report_file="${log_file%.log}-${TEST_ENVIRONMENT}-report.txt"
    if ! generate_test_report "$log_file" "$report_file"; then
        log_warning "Failed to generate production test report"
    fi
    
    log_success "Production validation completed"
    return 0
}

# Environment-aware test monitoring
monitor_test_execution() {
    local log_file="$1"
    local server_host="${2:-localhost}"
    local server_port="${3:-3240}"
    
    # Adjust monitoring duration based on environment
    local monitoring_duration
    case "$TEST_ENVIRONMENT" in
        "development")
            monitoring_duration=30
            ;;
        "ci")
            monitoring_duration=60
            ;;
        "production")
            monitoring_duration=120
            ;;
        *)
            monitoring_duration=60
            ;;
    esac
    
    log_info "Starting environment-aware test monitoring (${monitoring_duration}s)"
    monitor_usbip_connection "$log_file" "$server_host" "$server_port" "$monitoring_duration"
}

# ============================================================================
# MAIN FUNCTION FOR STANDALONE USAGE
# ============================================================================

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

QEMU USB/IP Test Tool - Test Validation Utilities with Environment Awareness

ENVIRONMENT DETECTION:
    TEST_ENVIRONMENT=development|ci|production   Set test environment explicitly
    Automatic detection: CI=1 or GITHUB_ACTIONS -> ci, otherwise development

STANDARD COMMANDS:
    parse-log <log_file> [message_type]     Parse console log messages
    check-readiness <log_file>              Check USB/IP client readiness
    wait-readiness <log_file> [timeout]     Wait for client readiness
    validate-test <log_file>                Validate test completion
    generate-report <log_file> [output]     Generate test report
    check-server <host> [port]              Check server connectivity
    test-server <host> [port]               Test server response
    monitor-connection <log_file> <host> [port] [duration]  Monitor connection
    validate-format <log_file>              Validate log format
    get-stats <log_file>                    Get test statistics

ENVIRONMENT-AWARE COMMANDS:
    validate-environment                    Validate current test environment
    environment-validation <log_file> [type]  Run environment-aware validation
    monitor-execution <log_file> [host] [port]  Environment-aware test monitoring
    environment-info                        Show current environment configuration

OPTIONS:
    -h, --help                              Show this help message
    -e, --environment                       Show environment information

EXAMPLES:
    # Standard usage
    $0 parse-log console.log USBIP_CLIENT_READY
    $0 check-readiness console.log
    $0 wait-readiness console.log 60
    
    # Environment-aware usage
    TEST_ENVIRONMENT=ci $0 environment-validation console.log full
    $0 environment-info
    $0 validate-environment
    $0 monitor-execution console.log localhost 3240
    
    # Traditional usage (still supported)
    $0 validate-test console.log
    $0 generate-report console.log
    $0 check-server localhost 3240

EOF
}

# Main function for standalone execution
main() {
    local command="${1:-}"
    
    case "$command" in
        "parse-log")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 parse-log <log_file> [message_type]"
                exit 1
            fi
            parse_console_log "$2" "${3:-}"
            ;;
        "check-readiness")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 check-readiness <log_file>"
                exit 1
            fi
            if is_usbip_client_ready "$2"; then
                log_success "USB/IP client is ready"
                exit 0
            else
                log_error "USB/IP client is not ready"
                exit 1
            fi
            ;;
        "wait-readiness")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 wait-readiness <log_file> [timeout]"
                exit 1
            fi
            wait_for_usbip_readiness "$2" "${3:-$DEFAULT_READINESS_TIMEOUT}"
            exit_code=$?
            exit $exit_code
            ;;
        "validate-test")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 validate-test <log_file>"
                exit 1
            fi
            validate_test_completion "$2"
            exit_code=$?
            exit $exit_code
            ;;
        "generate-report")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 generate-report <log_file> [output]"
                exit 1
            fi
            generate_test_report "$2" "${3:-}"
            exit_code=$?
            exit $exit_code
            ;;
        "check-server")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 check-server <host> [port]"
                exit 1
            fi
            check_usbip_server_connectivity "$2" "${3:-3240}"
            exit_code=$?
            exit $exit_code
            ;;
        "test-server")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 test-server <host> [port]"
                exit 1
            fi
            test_usbip_server_response "$2" "${3:-3240}"
            exit_code=$?
            exit $exit_code
            ;;
        "monitor-connection")
            if [[ $# -lt 3 ]]; then
                log_error "Usage: $0 monitor-connection <log_file> <host> [port] [duration]"
                exit 1
            fi
            monitor_usbip_connection "$2" "$3" "${4:-3240}" "${5:-60}"
            ;;
        "validate-format")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 validate-format <log_file>"
                exit 1
            fi
            validate_log_format "$2"
            ;;
        "get-stats")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 get-stats <log_file>"
                exit 1
            fi
            get_test_statistics "$2"
            ;;
        "validate-environment")
            validate_test_environment
            exit_code=$?
            exit $exit_code
            ;;
        "environment-validation")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 environment-validation <log_file> [validation_type]"
                exit 1
            fi
            run_environment_aware_validation "$2" "${3:-full}"
            exit_code=$?
            exit $exit_code
            ;;
        "monitor-execution")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 monitor-execution <log_file> [host] [port]"
                exit 1
            fi
            monitor_test_execution "$2" "${3:-localhost}" "${4:-3240}"
            exit_code=$?
            exit $exit_code
            ;;
        "environment-info")
            log_environment
            echo "Build Directory: $BUILD_DIR"
            echo "Log Directory: $LOG_DIR"
            echo "Script Directory: $SCRIPT_DIR"
            echo "Project Root: $PROJECT_ROOT"
            exit 0
            ;;
        "-e"|"--environment")
            log_environment
            exit 0
            ;;
        "-h"|"--help"|"")
            show_usage
            exit 0
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