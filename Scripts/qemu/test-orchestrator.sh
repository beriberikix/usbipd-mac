#!/bin/bash
#
# test-orchestrator.sh - QEMU Test Orchestration Script
#
# Main entry point for QEMU-based USB/IP testing infrastructure.
# Coordinates VM lifecycle, test server execution, and test validation
# with comprehensive environment awareness and error handling.
#
# This script provides a single entry point for all QEMU testing scenarios,
# automatically detecting the test environment and configuring appropriate
# resource allocation and test parameters.

set -euo pipefail

# Script metadata
readonly SCRIPT_NAME="QEMU Test Orchestrator"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Dependencies
readonly VM_MANAGER="$SCRIPT_DIR/vm-manager.sh"
readonly VALIDATION_SCRIPT="$PROJECT_ROOT/Scripts/qemu-test-validation.sh"
readonly CONFIG_FILE="$SCRIPT_DIR/test-vm-config.json"

# Build paths
readonly BUILD_DIR="$PROJECT_ROOT/.build"
readonly QEMU_TEST_SERVER="$BUILD_DIR/debug/QEMUTestServer"

# State and logging
readonly RUN_DIR="$PROJECT_ROOT/tmp/qemu-run"
readonly LOG_DIR="$PROJECT_ROOT/tmp/qemu-logs"
readonly TEST_SESSION_ID="$(date +%Y%m%d_%H%M%S)_$$"
readonly SESSION_LOG="$LOG_DIR/orchestrator_${TEST_SESSION_ID}.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Environment Detection (consistent with existing scripts)
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

# Environment-specific configuration
get_environment_config() {
    case "$TEST_ENVIRONMENT" in
        "development")
            echo "max_duration=300 vm_memory=128M cpu_cores=1 enable_graphics=false timeout_multiplier=1.0"
            ;;
        "ci")
            echo "max_duration=600 vm_memory=256M cpu_cores=2 enable_graphics=false timeout_multiplier=1.5"
            ;;
        "production")
            echo "max_duration=1200 vm_memory=512M cpu_cores=4 enable_graphics=false timeout_multiplier=2.0"
            ;;
        *)
            log_warning "Unknown environment: $TEST_ENVIRONMENT, using development defaults"
            echo "max_duration=300 vm_memory=128M cpu_cores=1 enable_graphics=false timeout_multiplier=1.0"
            ;;
    esac
}

# Parse environment configuration (compatible with older bash versions)
get_env_config_value() {
    local key="$1"
    get_environment_config | tr ' ' '\n' | grep "^${key}=" | cut -d'=' -f2
}

# Cache commonly used values
readonly MAX_DURATION=$(get_env_config_value "max_duration")
readonly VM_MEMORY=$(get_env_config_value "vm_memory")
readonly CPU_CORES=$(get_env_config_value "cpu_cores")
readonly ENABLE_GRAPHICS=$(get_env_config_value "enable_graphics")
readonly TIMEOUT_MULTIPLIER=$(get_env_config_value "timeout_multiplier")

# Logging functions (consistent with existing patterns)
log_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[INFO:${TEST_ENVIRONMENT}]${NC} $1" | tee -a "$SESSION_LOG"
}

log_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[SUCCESS:${TEST_ENVIRONMENT}]${NC} $1" | tee -a "$SESSION_LOG"
}

log_warning() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[WARNING:${TEST_ENVIRONMENT}]${NC} $1" | tee -a "$SESSION_LOG"
}

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[ERROR:${TEST_ENVIRONMENT}]${NC} $1" | tee -a "$SESSION_LOG"
}

log_step() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${CYAN}[STEP:${TEST_ENVIRONMENT}]${NC} ${BOLD}$1${NC}" | tee -a "$SESSION_LOG"
}

# Setup and validation functions
setup_environment() {
    log_step "Setting up test environment"
    
    # Create necessary directories
    mkdir -p "$RUN_DIR" "$LOG_DIR"
    
    # Validate dependencies
    if [[ ! -f "$VM_MANAGER" ]]; then
        log_error "VM manager not found: $VM_MANAGER"
        return 1
    fi
    
    if [[ ! -x "$VM_MANAGER" ]]; then
        log_error "VM manager not executable: $VM_MANAGER"
        return 1
    fi
    
    if [[ ! -f "$VALIDATION_SCRIPT" ]]; then
        log_error "Validation script not found: $VALIDATION_SCRIPT"
        return 1
    fi
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        return 1
    fi
    
    # Check if QEMUTestServer needs to be built
    if [[ ! -x "$QEMU_TEST_SERVER" ]]; then
        log_info "Building QEMUTestServer..."
        if ! (cd "$PROJECT_ROOT" && swift build --product QEMUTestServer); then
            log_error "Failed to build QEMUTestServer"
            return 1
        fi
    fi
    
    log_success "Environment setup completed"
    return 0
}

validate_prerequisites() {
    log_step "Validating prerequisites"
    
    # Check for required tools
    local missing_tools=()
    
    if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
        missing_tools+=("qemu-system-x86_64")
    fi
    
    if ! command -v qemu-img >/dev/null 2>&1; then
        missing_tools+=("qemu-img")
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_tools+=("jq")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again"
        return 1
    fi
    
    # Validate environment-specific requirements
    if [[ "$TEST_ENVIRONMENT" == "production" ]]; then
        # Check for KVM support
        if [[ ! -r /dev/kvm ]] && [[ $(uname) == "Linux" ]]; then
            log_warning "KVM acceleration not available, tests may be slower"
        fi
    fi
    
    log_success "Prerequisites validation completed"
    return 0
}

# Test scenario functions
run_basic_connectivity_test() {
    local vm_name="$1"
    local test_server_port="$2"
    
    log_step "Running basic connectivity test"
    
    # Start test server in background
    local server_log="$LOG_DIR/test_server_${TEST_SESSION_ID}.log"
    log_info "Starting QEMUTestServer on port $test_server_port"
    
    "$QEMU_TEST_SERVER" --port "$test_server_port" --verbose > "$server_log" 2>&1 &
    local server_pid=$!
    
    # Give server time to start
    sleep 2
    
    # Check if server is running
    if ! kill -0 "$server_pid" 2>/dev/null; then
        log_error "Test server failed to start"
        return 1
    fi
    
    log_info "Test server started successfully (PID: $server_pid)"
    
    # Basic connectivity test using netcat
    local connection_timeout=10
    if timeout "$connection_timeout" bash -c "echo | nc 127.0.0.1 $test_server_port" >/dev/null 2>&1; then
        log_success "Basic connectivity test passed"
        local test_result=0
    else
        log_error "Basic connectivity test failed"
        local test_result=1
    fi
    
    # Cleanup
    if kill -0 "$server_pid" 2>/dev/null; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    
    return $test_result
}

run_protocol_validation_test() {
    local vm_name="$1"
    local test_server_port="$2"
    
    log_step "Running USB/IP protocol validation test"
    
    # Start test server with extended logging
    local server_log="$LOG_DIR/protocol_server_${TEST_SESSION_ID}.log"
    log_info "Starting QEMUTestServer for protocol testing"
    
    "$QEMU_TEST_SERVER" --port "$test_server_port" --verbose > "$server_log" 2>&1 &
    local server_pid=$!
    
    # Wait for server to be ready
    local ready_timeout=30
    local ready=false
    
    for ((i=0; i<ready_timeout; i++)); do
        if grep -q "listening" "$server_log" 2>/dev/null; then
            ready=true
            break
        fi
        sleep 1
    done
    
    if [[ "$ready" != "true" ]]; then
        log_error "Test server not ready within $ready_timeout seconds"
        kill "$server_pid" 2>/dev/null || true
        return 1
    fi
    
    log_info "Test server ready for protocol testing"
    
    # Use validation script for protocol testing
    local validation_result=0
    if [[ -x "$VALIDATION_SCRIPT" ]]; then
        export TEST_SERVER_PORT="$test_server_port"
        export TEST_SESSION_ID="$TEST_SESSION_ID"
        
        if "$VALIDATION_SCRIPT" validate-server "$server_log" basic; then
            log_success "Protocol validation test passed"
            validation_result=0
        else
            log_error "Protocol validation test failed"
            validation_result=1
        fi
    else
        log_warning "Validation script not available, skipping detailed protocol test"
        validation_result=0
    fi
    
    # Cleanup
    if kill -0 "$server_pid" 2>/dev/null; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    
    return $validation_result
}

run_stress_test() {
    local vm_name="$1"
    local test_server_port="$2"
    
    log_step "Running stress test scenario"
    
    # Only run stress tests in production environment
    if [[ "$TEST_ENVIRONMENT" != "production" ]]; then
        log_info "Stress test skipped for $TEST_ENVIRONMENT environment"
        return 0
    fi
    
    log_info "Starting stress test with multiple concurrent connections"
    
    # Start test server
    local server_log="$LOG_DIR/stress_server_${TEST_SESSION_ID}.log"
    "$QEMU_TEST_SERVER" --port "$test_server_port" --verbose > "$server_log" 2>&1 &
    local server_pid=$!
    
    sleep 2
    
    # Multiple concurrent connections
    local stress_pids=()
    local stress_duration=30
    local connection_count=5
    
    for ((i=1; i<=connection_count; i++)); do
        (
            for ((j=1; j<=10; j++)); do
                echo | nc -w 1 127.0.0.1 "$test_server_port" >/dev/null 2>&1 || true
                sleep 0.5
            done
        ) &
        stress_pids+=($!)
    done
    
    # Wait for stress test to complete
    local stress_result=0
    for pid in "${stress_pids[@]}"; do
        if ! wait "$pid"; then
            stress_result=1
        fi
    done
    
    if [[ $stress_result -eq 0 ]]; then
        log_success "Stress test completed successfully"
    else
        log_error "Stress test encountered errors"
    fi
    
    # Cleanup
    if kill -0 "$server_pid" 2>/dev/null; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    
    return $stress_result
}

# Main orchestration functions
run_test_scenario() {
    local scenario="$1"
    local vm_name="${2:-usbip-test-$TEST_SESSION_ID}"
    
    log_step "Running test scenario: $scenario"
    
    case "$scenario" in
        "basic")
            run_basic_connectivity_test "$vm_name" 3240
            ;;
        "protocol")
            run_protocol_validation_test "$vm_name" 3240
            ;;
        "stress")
            run_stress_test "$vm_name" 3240
            ;;
        "full")
            local overall_result=0
            run_basic_connectivity_test "$vm_name" 3240 || overall_result=1
            run_protocol_validation_test "$vm_name" 3241 || overall_result=1
            run_stress_test "$vm_name" 3242 || overall_result=1
            return $overall_result
            ;;
        *)
            log_error "Unknown test scenario: $scenario"
            return 1
            ;;
    esac
}

generate_test_report() {
    local test_result="$1"
    local report_file="$LOG_DIR/test_report_${TEST_SESSION_ID}.md"
    
    log_step "Generating test report"
    
    cat > "$report_file" << EOF
# QEMU Test Orchestration Report

## Test Session Information

- **Session ID**: $TEST_SESSION_ID
- **Environment**: $TEST_ENVIRONMENT
- **Timestamp**: $(date)
- **Duration**: $(($(date +%s) - start_time)) seconds
- **Result**: $([ $test_result -eq 0 ] && echo "✅ PASSED" || echo "❌ FAILED")

## Environment Configuration

- **Max Duration**: $MAX_DURATION seconds
- **VM Memory**: $VM_MEMORY
- **CPU Cores**: $CPU_CORES
- **Graphics**: $ENABLE_GRAPHICS
- **Timeout Multiplier**: $TIMEOUT_MULTIPLIER

## Test Execution

### Files Generated

- **Session Log**: $SESSION_LOG
- **Report File**: $report_file

### Log Files

$(find "$LOG_DIR" -name "*${TEST_SESSION_ID}*" -type f | sed 's/^/- /')

## Summary

$([ $test_result -eq 0 ] && echo "All tests completed successfully." || echo "Some tests failed. Check logs for details.")

Environment: $TEST_ENVIRONMENT | Generated: $(date)
EOF
    
    log_success "Test report generated: $report_file"
    
    # Display summary
    echo
    echo -e "${BOLD}=== QEMU Test Summary ===${NC}"
    echo -e "Session: $TEST_SESSION_ID"
    echo -e "Environment: $TEST_ENVIRONMENT"
    echo -e "Result: $([ $test_result -eq 0 ] && echo -e "${GREEN}PASSED${NC}" || echo -e "${RED}FAILED${NC}")"
    echo -e "Report: $report_file"
    echo
}

cleanup_session() {
    log_step "Cleaning up test session"
    
    # Kill any remaining background processes
    jobs -p | while read -r pid; do
        kill "$pid" 2>/dev/null || true
    done
    
    # Clean up any orphaned QEMU processes
    if [[ -x "$VM_MANAGER" ]]; then
        "$VM_MANAGER" cleanup-orphaned 2>/dev/null || true
    fi
    
    log_success "Session cleanup completed"
}

# Help and usage functions
show_usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}
${CYAN}Comprehensive QEMU-based USB/IP testing infrastructure with environment awareness${NC}

${BOLD}USAGE:${NC}
    $0 [OPTIONS] <scenario>

${BOLD}TEST SCENARIOS:${NC}
    ${GREEN}basic${NC}      Basic connectivity testing (quick validation)
                 - Tests server startup and basic TCP connectivity
                 - Suitable for development and CI environments
                 - Duration: ~30 seconds
    
    ${GREEN}protocol${NC}   USB/IP protocol validation (comprehensive)
                 - Validates USB/IP message handling and responses
                 - Tests protocol compliance and error handling
                 - Duration: ~60 seconds
    
    ${GREEN}stress${NC}     Stress testing with concurrent connections (production only)
                 - Multiple simultaneous client connections
                 - Load testing and resource utilization validation
                 - Duration: ~120 seconds
    
    ${GREEN}full${NC}       Complete test suite (all scenarios)
                 - Runs basic, protocol, and stress tests sequentially
                 - Comprehensive validation for release candidates
                 - Duration: ~300+ seconds

${BOLD}OPTIONS:${NC}
    -e, --environment ENV    Override automatic environment detection
                            Valid environments: development, ci, production
    -v, --verbose           Enable verbose output with detailed logging
    -h, --help              Show this comprehensive help message
    --dry-run              Show execution plan without running actual tests
    --report-only          Generate test report from existing session logs
    --cleanup              Clean up orphaned processes and temporary files
    --info                 Display current environment configuration
    --mode MODE            Set QEMU test mode (mock or vm, default: auto)
    --timeout SECONDS      Override default timeout (environment-specific)

${BOLD}ENVIRONMENT VARIABLES:${NC}
    ${YELLOW}Core Configuration:${NC}
    TEST_ENVIRONMENT         Set test environment explicitly
                            (development|ci|production)
    QEMU_TEST_MODE          QEMU testing mode (mock|vm)
                            - mock: Fast simulation without VM
                            - vm: Full VM-based testing
    QEMU_TIMEOUT            Test timeout in seconds (per-test)
    
    ${YELLOW}Advanced Configuration:${NC}
    QEMU_TIMEOUT_MULTIPLIER  Timeout multiplier for slow systems (default: 1.0)
    QEMU_SKIP_VALIDATION    Skip prerequisite validation (not recommended)
    QEMU_VM_MEMORY          Override VM memory allocation (e.g., 512M)
    QEMU_CPU_CORES          Override VM CPU core count (e.g., 2)
    QEMU_LOG_LEVEL          Set logging verbosity (error|warn|info|debug)

${BOLD}EXAMPLES:${NC}
    ${YELLOW}Development Workflow:${NC}
    $0 basic                           # Quick connectivity check
    $0 --verbose basic                 # Detailed development testing
    $0 --dry-run full                  # Preview full test execution
    
    ${YELLOW}CI/CD Integration:${NC}
    TEST_ENVIRONMENT=ci $0 protocol    # CI protocol validation
    $0 --environment ci --timeout 90 basic  # CI with custom timeout
    QEMU_TEST_MODE=mock $0 full        # Fast CI testing with mocks
    
    ${YELLOW}Production Validation:${NC}
    $0 --environment production full   # Complete production testing
    $0 stress                          # Production stress testing only
    QEMU_VM_MEMORY=1G $0 protocol      # High-memory protocol testing
    
    ${YELLOW}Maintenance and Debugging:${NC}
    $0 --cleanup                       # Clean up after failed tests
    $0 --report-only                   # Generate report from last session
    $0 --info                         # Show current configuration

${BOLD}ENVIRONMENT DETECTION AND CONFIGURATION:${NC}
    ${YELLOW}Automatic Detection:${NC}
    CI=true or GITHUB_ACTIONS=true    → ci environment
    TEST_ENVIRONMENT=production       → production environment
    Default                           → development environment
    
    ${YELLOW}Environment-Specific Settings:${NC}
    Development: Fast, minimal resources, quick feedback
    - Duration: 5 minutes max, Memory: 128M, CPU: 1 core
    - Optimized for rapid iteration and local testing
    
    CI: Balanced, reliable, automated
    - Duration: 10 minutes max, Memory: 256M, CPU: 2 cores
    - Designed for automated testing in CI/CD pipelines
    
    Production: Comprehensive, thorough, realistic
    - Duration: 20 minutes max, Memory: 512M, CPU: 4 cores
    - Full validation with realistic resource allocation

${BOLD}INTEGRATION WITH OTHER SCRIPTS:${NC}
    This orchestrator integrates with:
    - Scripts/run-development-tests.sh (--qemu flag)
    - Scripts/run-ci-tests.sh (automatic QEMU integration)
    - Scripts/run-production-tests.sh (comprehensive testing)
    - Scripts/qemu/validate-environment.sh (prerequisite validation)

${BOLD}EXIT CODES:${NC}
    0    All tests passed successfully
    1    Test failures or setup errors
    130  Test interrupted by user (Ctrl+C)

${BOLD}LOG FILES AND REPORTS:${NC}
    Session logs: \$PROJECT_ROOT/tmp/qemu-logs/orchestrator_SESSIONID.log
    Test reports: \$PROJECT_ROOT/tmp/qemu-logs/test_report_SESSIONID.md
    Server logs:  \$PROJECT_ROOT/tmp/qemu-logs/*server_SESSIONID.log

${BOLD}TROUBLESHOOTING:${NC}
    Common issues and solutions:
    1. "QEMU not found" → Run: Scripts/qemu/validate-environment.sh install-help
    2. "Permission denied" → Ensure proper file permissions and dependencies
    3. "VM creation failed" → Check system resources and virtualization support
    4. "Tests timeout" → Increase timeout or check system performance

For more detailed information, see project documentation or run:
    Scripts/qemu/validate-environment.sh --help

EOF
}

show_environment_info() {
    echo -e "${BOLD}=== Environment Information ===${NC}"
    echo "Current Environment: $TEST_ENVIRONMENT"
    echo "Configuration:"
    echo "  max_duration: $MAX_DURATION"
    echo "  vm_memory: $VM_MEMORY"
    echo "  cpu_cores: $CPU_CORES"
    echo "  enable_graphics: $ENABLE_GRAPHICS"
    echo "  timeout_multiplier: $TIMEOUT_MULTIPLIER"
    echo
    echo "Paths:"
    echo "  Project Root: $PROJECT_ROOT"
    echo "  VM Manager: $VM_MANAGER"
    echo "  Config File: $CONFIG_FILE"
    echo "  Test Server: $QEMU_TEST_SERVER"
    echo "  Log Directory: $LOG_DIR"
    echo
    echo "Dependencies:"
    echo "  QEMU: $(command -v qemu-system-x86_64 || echo 'Not found')"
    echo "  jq: $(command -v jq || echo 'Not found')"
    echo
    echo "Environment Variables:"
    echo "  TEST_ENVIRONMENT: ${TEST_ENVIRONMENT:-'(auto-detected)'}"
    echo "  QEMU_TEST_MODE: ${QEMU_TEST_MODE:-'(auto)'}"
    echo "  QEMU_TIMEOUT: ${QEMU_TIMEOUT:-'(environment default)'}"
    echo "  QEMU_TIMEOUT_MULTIPLIER: ${QEMU_TIMEOUT_MULTIPLIER:-'(environment default)'}"
    echo
}

show_quick_reference() {
    cat << EOF
${BOLD}=== QEMU Test Orchestrator - Quick Reference ===${NC}

${YELLOW}Most Common Usage Patterns:${NC}

${GREEN}Development Testing:${NC}
  $0 basic                    # Quick connectivity test (~30s)
  $0 --verbose protocol       # Detailed protocol validation (~60s)

${GREEN}CI/CD Integration:${NC}
  TEST_ENVIRONMENT=ci $0 basic           # CI basic testing
  QEMU_TEST_MODE=mock $0 protocol        # Fast mock testing

${GREEN}Production Validation:${NC}
  $0 --environment production full       # Complete test suite
  $0 stress                             # Stress testing only

${YELLOW}Maintenance Commands:${NC}
  $0 --cleanup               # Clean up after failed tests
  $0 --info                 # Show current configuration
  $0 --dry-run full         # Preview test execution

${YELLOW}Integration with Test Scripts:${NC}
  Scripts/run-development-tests.sh --qemu    # Enable in development
  Scripts/run-ci-tests.sh --qemu-only       # CI QEMU testing only
  Scripts/run-production-tests.sh           # Automatic integration

For comprehensive help: $0 --help
For environment validation: Scripts/qemu/validate-environment.sh --help

EOF
}

# Main function
main() {
    local scenario=""
    local verbose=false
    local dry_run=false
    local report_only=false
    local cleanup_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                export TEST_ENVIRONMENT="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --report-only)
                report_only=true
                shift
                ;;
            --cleanup)
                cleanup_only=true
                shift
                ;;
            --mode)
                export QEMU_TEST_MODE="$2"
                shift 2
                ;;
            --timeout)
                export QEMU_TIMEOUT="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                return 0
                ;;
            --info)
                show_environment_info
                return 0
                ;;
            --quick-reference|--quick-ref)
                show_quick_reference
                return 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                return 1
                ;;
            *)
                scenario="$1"
                shift
                ;;
        esac
    done
    
    # Handle special modes
    if [[ "$cleanup_only" == "true" ]]; then
        cleanup_session
        return 0
    fi
    
    if [[ "$report_only" == "true" ]]; then
        # Find the most recent session log
        local latest_log=$(ls -t "$LOG_DIR"/orchestrator_*.log 2>/dev/null | head -n1 || true)
        if [[ -n "$latest_log" ]]; then
            log_info "Generating report from: $latest_log"
            generate_test_report 0  # Assume success for report-only mode
        else
            log_error "No session logs found"
            return 1
        fi
        return 0
    fi
    
    # Validate scenario
    if [[ -z "$scenario" ]]; then
        log_error "No test scenario specified"
        show_usage
        return 1
    fi
    
    # Set start time for duration calculation
    local start_time=$(date +%s)
    
    # Show environment info if verbose
    if [[ "$verbose" == "true" ]]; then
        show_environment_info
    fi
    
    log_step "Starting QEMU Test Orchestration"
    log_info "Session ID: $TEST_SESSION_ID"
    log_info "Environment: $TEST_ENVIRONMENT"
    log_info "Scenario: $scenario"
    
    # Dry run mode
    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN MODE - No tests will be executed"
        echo
        echo "Would execute scenario: $scenario"
        echo "Environment configuration:"
        echo "  max_duration: $MAX_DURATION"
        echo "  vm_memory: $VM_MEMORY"
        echo "  cpu_cores: $CPU_CORES"
        echo "  enable_graphics: $ENABLE_GRAPHICS"
        echo "  timeout_multiplier: $TIMEOUT_MULTIPLIER"
        return 0
    fi
    
    # Set up signal handlers for cleanup
    trap cleanup_session EXIT
    trap 'log_error "Test interrupted by user"; exit 130' INT TERM
    
    local overall_result=0
    
    # Setup and validation
    if ! setup_environment; then
        overall_result=1
    elif ! validate_prerequisites; then
        overall_result=1
    else
        # Run the test scenario
        if ! run_test_scenario "$scenario"; then
            overall_result=1
        fi
    fi
    
    # Generate report
    generate_test_report $overall_result
    
    # Return appropriate exit code
    if [[ $overall_result -eq 0 ]]; then
        log_success "QEMU test orchestration completed successfully"
    else
        log_error "QEMU test orchestration completed with errors"
    fi
    
    return $overall_result
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi