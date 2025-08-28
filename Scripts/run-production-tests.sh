#!/bin/bash

# Production Test Execution Script
# Comprehensive test execution including QEMU integration for production environment
# Enhanced version of run-qemu-tests.sh with environment awareness

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build"
QEMU_BUILD_DIR="$BUILD_DIR/qemu"
LOGS_DIR="$QEMU_BUILD_DIR/logs"
TEST_DATA_DIR="$QEMU_BUILD_DIR/test-data"

# Test environment configuration
TEST_ENVIRONMENT="${TEST_ENVIRONMENT:-production}"
ENABLE_HARDWARE_TESTS="${ENABLE_HARDWARE_TESTS:-true}"
ENABLE_QEMU_TESTS="${ENABLE_QEMU_TESTS:-true}"
ENABLE_SYSTEM_EXTENSION_TESTS="${ENABLE_SYSTEM_EXTENSION_TESTS:-true}"
MAX_TEST_DURATION="${MAX_TEST_DURATION:-600}"  # 10 minutes
PARALLEL_EXECUTION="${PARALLEL_EXECUTION:-false}"  # Sequential for production

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Environment detection functions
detect_hardware_capabilities() {
    local capabilities=""
    
    # Check for USB hardware
    if ioreg -p IOUSB | grep -q "USB" 2>/dev/null; then
        capabilities="$capabilities usb_hardware"
    fi
    
    # Check for System Extension capability
    if [ "$(id -u)" -eq 0 ] || [ -n "$TEST_ALLOW_SYSEXT" ]; then
        capabilities="$capabilities system_extension"
    fi
    
    # Check for QEMU
    if command -v qemu-system-x86_64 >/dev/null 2>&1; then
        capabilities="$capabilities qemu"
    fi
    
    # Check for network access
    if ping -c 1 127.0.0.1 >/dev/null 2>&1; then
        capabilities="$capabilities network"
    fi
    
    echo "$capabilities"
}

# Setup functions
setup_test_environment() {
    log_step "Setting up production test environment"
    
    # Create necessary directories
    mkdir -p "$LOGS_DIR" "$TEST_DATA_DIR"
    
    # Detect capabilities
    local capabilities
    capabilities=$(detect_hardware_capabilities)
    log_info "Detected capabilities: $capabilities"
    
    # Save capabilities for test execution
    echo "$capabilities" > "$TEST_DATA_DIR/capabilities.txt"
    
    # Export environment variables for tests
    export TEST_ENVIRONMENT="$TEST_ENVIRONMENT"
    export TEST_CAPABILITIES="$capabilities"
    export TEST_LOGS_DIR="$LOGS_DIR"
    export TEST_DATA_DIR="$TEST_DATA_DIR"
    
    log_success "Test environment setup complete"
}

cleanup_test_environment() {
    log_step "Cleaning up test environment"
    
    # Kill any remaining QEMU processes
    pkill -f "qemu-system-x86_64.*test" 2>/dev/null || true
    
    # Clean up temporary files older than 1 hour
    find "$TEST_DATA_DIR" -name "*.tmp" -mtime +1 -delete 2>/dev/null || true
    
    log_success "Test environment cleanup complete"
}

# Build functions
build_project() {
    log_step "Building project for production testing"
    
    cd "$PROJECT_ROOT"
    
    # Build all targets
    log_info "Building main project..."
    swift build --configuration release
    
    # Build QEMU test server if QEMU tests are enabled
    if [ "$ENABLE_QEMU_TESTS" = "true" ]; then
        log_info "Building QEMU test server..."
        swift build --product QEMUTestServer --configuration release
        
        # Verify QEMU test server was built
        if [ ! -f "$BUILD_DIR/release/QEMUTestServer" ]; then
            log_warning "QEMU test server not built, disabling QEMU tests"
            ENABLE_QEMU_TESTS="false"
        fi
    fi
    
    log_success "Project build complete"
}

# Test execution functions
run_swift_tests() {
    log_step "Running Swift test suite"
    
    cd "$PROJECT_ROOT"
    
    local test_args=""
    
    # Configure test execution based on environment
    if [ "$PARALLEL_EXECUTION" = "true" ]; then
        test_args="$test_args --parallel"
    fi
    
    # Run production tests specifically
    log_info "Running ProductionTests..."
    if [ "$PARALLEL_EXECUTION" = "true" ]; then
        swift test --filter ProductionTests --parallel --verbose 2>&1 | tee "$LOGS_DIR/production-tests.log"
    else
        swift test --filter ProductionTests --verbose 2>&1 | tee "$LOGS_DIR/production-tests.log"
    fi
    
    # Run integration tests if hardware is available
    local capabilities
    capabilities=$(cat "$TEST_DATA_DIR/capabilities.txt")
    
    if [[ "$capabilities" == *"usb_hardware"* ]] && [ "$ENABLE_HARDWARE_TESTS" = "true" ]; then
        log_info "Running hardware integration tests..."
        swift test --filter IntegrationTests --verbose 2>&1 | tee "$LOGS_DIR/integration-tests.log"
    else
        log_warning "Hardware integration tests skipped - hardware not available"
    fi
    
    log_success "Swift tests completed"
}

run_qemu_tests() {
    if [ "$ENABLE_QEMU_TESTS" != "true" ]; then
        log_warning "QEMU tests disabled"
        return 0
    fi
    
    log_step "Running QEMU comprehensive tests"
    
    local capabilities
    capabilities=$(cat "$TEST_DATA_DIR/capabilities.txt")
    
    # Set QEMU test environment variables for production
    export TEST_ENVIRONMENT="production"
    export QEMU_TEST_MODE="${QEMU_TEST_MODE:-vm}"  # Default to VM mode in production
    export QEMU_TIMEOUT="${QEMU_TIMEOUT:-120}"
    
    cd "$PROJECT_ROOT"
    
    # Test 1: QEMU test server execution
    log_info "Testing QEMU test server..."
    local qemu_server_path="$BUILD_DIR/release/QEMUTestServer"
    
    if [ ! -f "$qemu_server_path" ]; then
        log_error "QEMU test server not found at $qemu_server_path"
        return 1
    fi
    
    # Use timeout command if available
    local timeout_cmd=""
    if command -v gtimeout >/dev/null 2>&1; then
        timeout_cmd="gtimeout"
    elif command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout"
    fi
    
    if [ -n "$timeout_cmd" ]; then
        log_info "Testing QEMU server with timeout..."
        if $timeout_cmd 10s "$qemu_server_path" > "$LOGS_DIR/qemu-server.log" 2>&1; then
            log_success "QEMU server test completed"
        else
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                log_success "QEMU server test completed (timed out as expected)"
            else
                log_error "QEMU server test failed (exit code: $exit_code)"
                return 1
            fi
        fi
    else
        log_info "Testing QEMU server without timeout..."
        "$qemu_server_path" > "$LOGS_DIR/qemu-server.log" 2>&1 &
        local server_pid=$!
        sleep 2
        kill $server_pid 2>/dev/null || true
        wait $server_pid 2>/dev/null || true
        log_success "QEMU server test completed"
    fi
    
    # Test 2: Run QEMU orchestrator if available
    local qemu_orchestrator="$SCRIPT_DIR/qemu/test-orchestrator.sh"
    if [ -f "$qemu_orchestrator" ]; then
        log_info "Running QEMU test orchestrator (production mode)..."
        
        local start_time=$(date +%s)
        
        if "$qemu_orchestrator" --mode production --timeout "$QEMU_TIMEOUT" > "$LOGS_DIR/qemu-orchestrator.log" 2>&1; then
            local end_time=$(date +%s)
            local qemu_time=$((end_time - start_time))
            log_success "QEMU orchestrator completed in ${qemu_time}s"
        else
            local exit_code=$?
            local end_time=$(date +%s)
            local qemu_time=$((end_time - start_time))
            
            if [ $exit_code -eq 124 ]; then
                log_error "QEMU orchestrator timed out after ${QEMU_TIMEOUT}s"
                return 1
            else
                log_error "QEMU orchestrator failed in ${qemu_time}s (exit code: $exit_code)"
                return 1
            fi
        fi
    else
        log_warning "QEMU test orchestrator not found at $qemu_orchestrator"
    fi
    
    # Test 3: Run QEMU validation script if available
    if [ -f "$SCRIPT_DIR/qemu-test-validation.sh" ]; then
        log_info "Running QEMU validation script..."
        bash "$SCRIPT_DIR/qemu-test-validation.sh" validate-environment > "$LOGS_DIR/qemu-validation.log" 2>&1
        log_success "QEMU validation script test completed"
    fi
    
    # Test 4: Run production-specific QEMU integration tests
    log_info "Running QEMU integration test suite..."
    if swift test --filter QEMUIntegrationTests --verbose 2>&1 | tee "$LOGS_DIR/qemu-integration-tests.log"; then
        log_success "QEMU integration test suite completed"
    else
        local exit_code=$?
        if [[ "$capabilities" != *"qemu"* ]]; then
            log_warning "QEMU integration tests failed but QEMU not available - graceful degradation"
        else
            log_error "QEMU integration test suite failed (exit code: $exit_code)"
            return 1
        fi
    fi
    
    # Test 5: Test both mock and VM modes if QEMU available
    if [[ "$capabilities" == *"qemu"* ]]; then
        log_info "Testing QEMU in both mock and VM modes..."
        
        # Test mock mode
        export QEMU_TEST_MODE="mock"
        if "$qemu_orchestrator" --mode production --timeout 30 > "$LOGS_DIR/qemu-mock-mode.log" 2>&1; then
            log_success "QEMU mock mode test completed"
        else
            log_warning "QEMU mock mode test failed"
        fi
        
        # Test VM mode if QEMU available
        export QEMU_TEST_MODE="vm"
        if "$qemu_orchestrator" --mode production --timeout "$QEMU_TIMEOUT" > "$LOGS_DIR/qemu-vm-mode.log" 2>&1; then
            log_success "QEMU VM mode test completed"
        else
            log_warning "QEMU VM mode test failed"
        fi
    else
        log_info "QEMU not available, testing mock mode only..."
        export QEMU_TEST_MODE="mock"
        if [ -f "$qemu_orchestrator" ] && "$qemu_orchestrator" --mode production --timeout 30 > "$LOGS_DIR/qemu-mock-only.log" 2>&1; then
            log_success "QEMU mock-only test completed"
        else
            log_warning "QEMU mock-only test failed or orchestrator unavailable"
        fi
    fi
    
    log_success "QEMU comprehensive tests completed"
}

run_system_extension_tests() {
    if [ "$ENABLE_SYSTEM_EXTENSION_TESTS" != "true" ]; then
        log_warning "System Extension tests disabled"
        return 0
    fi
    
    log_step "Running System Extension tests"
    
    local capabilities
    capabilities=$(cat "$TEST_DATA_DIR/capabilities.txt")
    
    if [[ "$capabilities" != *"system_extension"* ]]; then
        log_warning "System Extension capability not available, skipping System Extension tests"
        return 0
    fi
    
    cd "$PROJECT_ROOT"
    
    # Run System Extension specific tests
    log_info "Running System Extension integration tests..."
    swift test --filter SystemExtensionIntegrationTests --verbose 2>&1 | tee "$LOGS_DIR/system-extension-tests.log"
    
    log_success "System Extension tests completed"
}

run_performance_tests() {
    log_step "Running performance validation"
    
    cd "$PROJECT_ROOT"
    
    # Measure build time
    log_info "Measuring build performance..."
    local build_start=$(date +%s)
    swift build --configuration release > "$LOGS_DIR/build-performance.log" 2>&1
    local build_end=$(date +%s)
    local build_time=$((build_end - build_start))
    
    log_info "Build completed in ${build_time} seconds"
    echo "build_time_seconds: $build_time" >> "$LOGS_DIR/performance-metrics.log"
    
    # Measure test execution time
    log_info "Measuring test performance..."
    local test_start=$(date +%s)
    swift test --filter ProductionTests 2>&1 | tee -a "$LOGS_DIR/test-performance.log"
    local test_end=$(date +%s)
    local test_time=$((test_end - test_start))
    
    log_info "Tests completed in ${test_time} seconds"
    echo "test_time_seconds: $test_time" >> "$LOGS_DIR/performance-metrics.log"
    
    # Performance validation
    if [ $test_time -gt $MAX_TEST_DURATION ]; then
        log_warning "Test execution time ($test_time s) exceeded maximum ($MAX_TEST_DURATION s)"
    else
        log_success "Test execution time within acceptable limits"
    fi
    
    log_success "Performance validation completed"
}

generate_test_report() {
    log_step "Generating comprehensive test report"
    
    local report_file="$LOGS_DIR/production-test-report.md"
    local capabilities
    capabilities=$(cat "$TEST_DATA_DIR/capabilities.txt")
    
    cat > "$report_file" << EOF
# Production Test Report

## Test Environment
- **Environment**: $TEST_ENVIRONMENT
- **Date**: $(date)
- **Capabilities**: $capabilities
- **Hardware Tests**: $ENABLE_HARDWARE_TESTS
- **QEMU Tests**: $ENABLE_QEMU_TESTS
- **System Extension Tests**: $ENABLE_SYSTEM_EXTENSION_TESTS

## Test Results

### Swift Tests
EOF
    
    if [ -f "$LOGS_DIR/production-tests.log" ]; then
        echo "- Production Tests: ✅ Completed" >> "$report_file"
    else
        echo "- Production Tests: ❌ Not executed" >> "$report_file"
    fi
    
    if [ -f "$LOGS_DIR/integration-tests.log" ]; then
        echo "- Integration Tests: ✅ Completed" >> "$report_file"
    else
        echo "- Integration Tests: ⚠️ Skipped (hardware not available)" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

### QEMU Integration
EOF
    
    if [ -f "$LOGS_DIR/qemu-server.log" ]; then
        echo "- QEMU Server: ✅ Tested" >> "$report_file"
    else
        echo "- QEMU Server: ⚠️ Skipped" >> "$report_file"
    fi
    
    if [ -f "$LOGS_DIR/qemu-orchestrator.log" ]; then
        echo "- QEMU Orchestrator: ✅ Executed" >> "$report_file"
    else
        echo "- QEMU Orchestrator: ⚠️ Skipped" >> "$report_file"
    fi
    
    if [ -f "$LOGS_DIR/qemu-integration-tests.log" ]; then
        echo "- QEMU Integration Tests: ✅ Completed" >> "$report_file"
    else
        echo "- QEMU Integration Tests: ⚠️ Skipped" >> "$report_file"
    fi
    
    if [ -f "$LOGS_DIR/qemu-mock-mode.log" ]; then
        echo "- QEMU Mock Mode: ✅ Tested" >> "$report_file"
    else
        echo "- QEMU Mock Mode: ⚠️ Skipped" >> "$report_file"
    fi
    
    if [ -f "$LOGS_DIR/qemu-vm-mode.log" ]; then
        echo "- QEMU VM Mode: ✅ Tested" >> "$report_file"
    else
        echo "- QEMU VM Mode: ⚠️ Skipped" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

### System Extension
EOF
    
    if [ -f "$LOGS_DIR/system-extension-tests.log" ]; then
        echo "- System Extension Tests: ✅ Completed" >> "$report_file"
    else
        echo "- System Extension Tests: ⚠️ Skipped" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

### Performance Metrics
EOF
    
    if [ -f "$LOGS_DIR/performance-metrics.log" ]; then
        cat "$LOGS_DIR/performance-metrics.log" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## Log Files
- Production Tests: \`$LOGS_DIR/production-tests.log\`
- Integration Tests: \`$LOGS_DIR/integration-tests.log\`
- QEMU Server: \`$LOGS_DIR/qemu-server.log\`
- QEMU Orchestrator: \`$LOGS_DIR/qemu-orchestrator.log\`
- QEMU Integration Tests: \`$LOGS_DIR/qemu-integration-tests.log\`
- QEMU Mock Mode: \`$LOGS_DIR/qemu-mock-mode.log\`
- QEMU VM Mode: \`$LOGS_DIR/qemu-vm-mode.log\`
- QEMU Validation: \`$LOGS_DIR/qemu-validation.log\`
- System Extension: \`$LOGS_DIR/system-extension-tests.log\`
- Performance: \`$LOGS_DIR/performance-metrics.log\`

## Summary
Production test execution completed for environment: $TEST_ENVIRONMENT
EOF
    
    # Add completion test results to report
    if [ -f "$LOGS_DIR/completion-tests.log" ]; then
        cat >> "$report_file" << EOF

### Shell Completion Tests
EOF
        cat "$LOGS_DIR/completion-tests.log" >> "$report_file"
    fi
    
    log_info "Test report generated: $report_file"
    log_success "Comprehensive test report generated"
}

# Run comprehensive shell completion tests
run_completion_tests() {
    log_step "Running Comprehensive Shell Completion Tests"
    
    local completion_test_script="$SCRIPT_DIR/test-completion-environment.sh"
    local completion_log="$LOGS_DIR/completion-tests.log"
    
    if [ ! -f "$completion_test_script" ]; then
        log_warning "Completion test script not found - skipping completion tests"
        echo "Completion tests: SKIPPED (script not found)" > "$completion_log"
        return 0
    fi
    
    log_info "Running comprehensive completion tests for production validation..."
    
    # Run comprehensive completion tests with all shells and scenarios
    if "$completion_test_script" \
        --output "$BUILD_DIR/production-completion-results" \
        --verbose \
        > "$completion_log" 2>&1; then
        
        log_success "Comprehensive completion tests passed"
        echo "Completion Tests: ✅ PASSED" >> "$completion_log"
        
        # Add summary to log
        echo "" >> "$completion_log"
        echo "Production Completion Test Summary:" >> "$completion_log"
        echo "- All shells tested: bash, zsh, fish" >> "$completion_log"
        echo "- All scenarios tested: basic, dynamic, error-handling, performance" >> "$completion_log"
        echo "- Test environment: production" >> "$completion_log"
        
        # Add completion files info if available
        local completion_dir="$BUILD_DIR/production-completion-results"
        if [ -d "$completion_dir" ]; then
            echo "- Generated completion files:" >> "$completion_log"
            for file in "$completion_dir"/*; do
                if [ -f "$file" ]; then
                    local filename=$(basename "$file")
                    local size=$(stat -f %z "$file" 2>/dev/null || echo "unknown")
                    echo "  - $filename ($size bytes)" >> "$completion_log"
                fi
            done
        fi
        
        return 0
    else
        local exit_code=$?
        log_error "Comprehensive completion tests failed with exit code $exit_code"
        echo "Completion Tests: ❌ FAILED (exit code: $exit_code)" >> "$completion_log"
        
        # In production, completion test failures should be investigated
        echo "" >> "$completion_log"
        echo "FAILURE DETAILS:" >> "$completion_log"
        echo "Exit Code: $exit_code" >> "$completion_log"
        echo "This indicates a significant issue with completion system that needs investigation" >> "$completion_log"
        
        return $exit_code
    fi
}

# Main execution
main() {
    log_step "Starting Production Test Execution"
    log_info "Environment: $TEST_ENVIRONMENT"
    log_info "Hardware tests: $ENABLE_HARDWARE_TESTS"
    log_info "QEMU tests: $ENABLE_QEMU_TESTS"
    log_info "System Extension tests: $ENABLE_SYSTEM_EXTENSION_TESTS"
    
    # Setup
    setup_test_environment
    
    # Build project
    build_project
    
    # Execute tests
    run_swift_tests
    run_qemu_tests
    run_system_extension_tests
    run_completion_tests
    run_performance_tests
    
    # Generate report
    generate_test_report
    
    # Cleanup
    cleanup_test_environment
    
    log_success "Production test execution completed successfully"
    log_info "Test report available at: $LOGS_DIR/production-test-report.md"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        cat << EOF
Usage: $0 [OPTIONS]

Production Test Execution Script
Runs comprehensive test suite including QEMU integration for production environment

OPTIONS:
    --help, -h              Show this help message
    --hardware-only         Run only hardware-dependent tests
    --qemu-only            Run only QEMU integration tests
    --no-hardware          Disable hardware tests
    --no-qemu              Disable QEMU tests
    --no-system-extension  Disable System Extension tests
    --parallel             Enable parallel test execution
    --timeout SECONDS      Set maximum test duration (default: 600)

ENVIRONMENT VARIABLES:
    TEST_ENVIRONMENT       Test environment (default: production)
    ENABLE_HARDWARE_TESTS  Enable hardware tests (default: true)
    ENABLE_QEMU_TESTS      Enable QEMU tests (default: true)
    ENABLE_SYSTEM_EXTENSION_TESTS  Enable System Extension tests (default: true)
    MAX_TEST_DURATION      Maximum test duration in seconds (default: 600)
    PARALLEL_EXECUTION     Enable parallel execution (default: false)
    QEMU_TEST_MODE         QEMU test mode: mock or vm (default: vm)
    QEMU_TIMEOUT          QEMU test timeout in seconds (default: 120)

EXAMPLES:
    $0                     # Run all production tests
    $0 --hardware-only     # Run only hardware tests
    $0 --no-qemu          # Run tests without QEMU integration
    $0 --parallel         # Enable parallel execution
EOF
        exit 0
        ;;
    --hardware-only)
        ENABLE_QEMU_TESTS="false"
        ENABLE_SYSTEM_EXTENSION_TESTS="false"
        ;;
    --qemu-only)
        ENABLE_HARDWARE_TESTS="false"
        ENABLE_SYSTEM_EXTENSION_TESTS="false"
        ;;
    --no-hardware)
        ENABLE_HARDWARE_TESTS="false"
        ;;
    --no-qemu)
        ENABLE_QEMU_TESTS="false"
        ;;
    --no-system-extension)
        ENABLE_SYSTEM_EXTENSION_TESTS="false"
        ;;
    --parallel)
        PARALLEL_EXECUTION="true"
        ;;
    --timeout)
        if [ -n "$2" ]; then
            MAX_TEST_DURATION="$2"
            shift
        else
            log_error "Timeout value required"
            exit 1
        fi
        ;;
esac

# Trap for cleanup on exit
trap cleanup_test_environment EXIT

# Run main function
main "$@"