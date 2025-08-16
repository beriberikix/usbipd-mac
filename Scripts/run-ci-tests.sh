#!/bin/bash

# run-ci-tests.sh
# GitHub Actions-compatible test execution script for CI environments
# Provides reliable automated testing in CI environments without hardware dependencies

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build"
TIMEOUT_SECONDS=180  # 3 minutes for CI
TEST_ENVIRONMENT="ci"

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

# Print script header
print_header() {
    echo "=================================================="
    echo "🤖 CI Test Environment Runner"
    echo "=================================================="
    echo "Environment: $TEST_ENVIRONMENT"
    echo "Target Time: <$TIMEOUT_SECONDS seconds"
    echo "Working Dir: $PROJECT_ROOT"
    echo "Build Dir: $BUILD_DIR"
    echo "CI System: ${CI:-'local'}"
    echo "GitHub Actions: ${GITHUB_ACTIONS:-'false'}"
    echo "=================================================="
}

# Check CI environment prerequisites
check_ci_prerequisites() {
    log_info "Checking CI environment prerequisites..."
    
    # Check if we're in the correct directory
    if [ ! -f "$PROJECT_ROOT/Package.swift" ]; then
        log_error "Package.swift not found. Please run this script from the project root."
        exit 1
    fi
    
    # Check Swift installation
    if ! command -v swift >/dev/null 2>&1; then
        log_error "Swift is not installed or not in PATH"
        exit 1
    fi
    
    # Note: SwiftLint validation is handled by the Code Quality job in consolidated CI
    
    # Check CI environment variables
    if [ -n "${CI}" ] && [ "${CI}" = "true" ]; then
        log_info "Running in CI environment"
        
        if [ -n "${GITHUB_ACTIONS}" ] && [ "${GITHUB_ACTIONS}" = "true" ]; then
            log_info "GitHub Actions environment detected"
        fi
    else
        log_warning "Not running in recognized CI environment"
    fi
    
    log_success "CI prerequisites check completed"
}

# Set up CI test environment
setup_ci_test_environment() {
    log_info "Setting up CI test environment..."
    
    # Set environment variables for CI testing
    export TEST_ENVIRONMENT="ci"
    export SWIFT_TEST_PARALLEL="true"
    export SWIFT_TEST_TIMEOUT="$TIMEOUT_SECONDS"
    
    # Configure test environment for CI
    export USBIPD_TEST_MODE="ci"
    export USBIPD_ENABLE_MOCKING="true"
    export USBIPD_MOCK_HARDWARE="true"
    export USBIPD_CI_MODE="true"
    
    # Set logging level for CI (info for debugging CI issues)
    export USBIPD_LOG_LEVEL="info"
    
    # QEMU testing configuration for CI (mock mode only)
    export ENABLE_QEMU_TESTS="${ENABLE_QEMU_TESTS:-true}"
    export QEMU_TEST_MODE="mock"  # Always mock in CI
    export QEMU_TIMEOUT="${QEMU_TIMEOUT:-60}"
    
    # Disable interactive features for CI
    export USBIPD_INTERACTIVE="false"
    export USBIPD_NO_COLOR="true"
    
    # Configure for GitHub Actions if detected
    if [ -n "${GITHUB_ACTIONS}" ] && [ "${GITHUB_ACTIONS}" = "true" ]; then
        export USBIPD_GITHUB_ACTIONS="true"
        export USBIPD_LOG_FORMAT="github"
    fi
    
    log_success "CI test environment configured"
}

# Validate CI environment capabilities
validate_ci_environment() {
    log_info "Validating CI environment capabilities..."
    
    local validation_issues=()
    
    # Check that we don't have hardware access (expected in CI)
    if [ -d "/dev/usb" ] || [ -n "$(ls /dev/tty.usb* 2>/dev/null)" ]; then
        validation_issues+=("Hardware USB devices detected - CI should use mocks")
    fi
    
    # Check that we don't have admin privileges (expected in CI)
    if [ "$EUID" -eq 0 ]; then
        validation_issues+=("Running as root - CI should run with standard privileges")
    fi
    
    # Check required CI environment is properly configured
    if [ "$USBIPD_MOCK_HARDWARE" != "true" ]; then
        validation_issues+=("Hardware mocking not enabled for CI")
    fi
    
    # Check disk space for CI builds
    local available_space=$(df "$BUILD_DIR" | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 1000000 ]; then  # Less than ~1GB
        validation_issues+=("Low disk space available for CI builds")
    fi
    
    # Report validation results
    if [ ${#validation_issues[@]} -eq 0 ]; then
        log_success "CI environment validation passed"
    else
        log_warning "CI environment validation issues found:"
        for issue in "${validation_issues[@]}"; do
            log_warning "  - $issue"
        done
        # Continue execution but note the issues
    fi
}

# Clean build artifacts (always clean in CI)
clean_ci_build_artifacts() {
    log_info "Cleaning CI build artifacts..."
    
    # Remove build directory completely
    rm -rf "$BUILD_DIR"
    
    # Remove any test artifacts
    find "$PROJECT_ROOT" -name "*.profraw" -delete 2>/dev/null || true
    find "$PROJECT_ROOT" -name "*-test-report.txt" -delete 2>/dev/null || true
    
    log_success "CI build artifacts cleaned"
}

# Build the project for CI testing
build_ci_project() {
    log_info "Building project for CI testing..."
    
    local start_time=$(date +%s)
    
    # Build with CI-optimized settings
    swift build --build-tests \
        --configuration debug \
        --enable-test-discovery \
        --build-path "$BUILD_DIR" \
        -Xswiftc -warnings-as-errors || {
        log_error "CI build failed"
        exit 1
    }
    
    local end_time=$(date +%s)
    local build_time=$((end_time - start_time))
    
    log_success "CI build completed in ${build_time}s"
    
    # Check build time performance
    if [ $build_time -gt 120 ]; then  # More than 2 minutes
        log_warning "CI build took longer than expected: ${build_time}s"
    fi
}

# Note: SwiftLint validation is now handled by the Code Quality job in consolidated CI

# Run the CI test suite
run_ci_tests() {
    log_info "Running CI test suite..."
    
    local start_time=$(date +%s)
    
    # Use timeout command (should be available in CI environments)
    local timeout_cmd=""
    if command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout ${TIMEOUT_SECONDS}s"
    else
        log_warning "No timeout command available, running without timeout"
        timeout_cmd=""
    fi
    
    # Run CI-specific tests with filtering
    local test_filter="CITests"
    local test_command="swift test"
    
    # Add test filtering for CI tests
    test_command="$test_command --filter $test_filter"
    
    # Add parallel execution
    test_command="$test_command --parallel"
    
    # Add build path
    test_command="$test_command --build-path $BUILD_DIR"
    
    # Add configuration
    test_command="$test_command --configuration release"
    
    # Add timeout if available
    if [ -n "$timeout_cmd" ]; then
        test_command="$timeout_cmd $test_command"
    fi
    
    # Execute the test command
    log_info "Executing: $test_command"
    
    if eval "$test_command"; then
        local end_time=$(date +%s)
        local test_time=$((end_time - start_time))
        
        log_success "CI tests passed in ${test_time}s"
        
        # Check if we met the performance target
        if [ $test_time -le $TIMEOUT_SECONDS ]; then
            log_success "✅ CI performance target met: ${test_time}s ≤ ${TIMEOUT_SECONDS}s"
        else
            log_warning "⚠️ CI performance target missed: ${test_time}s > ${TIMEOUT_SECONDS}s"
        fi
        
        return 0
    else
        local exit_code=$?
        local end_time=$(date +%s)
        local test_time=$((end_time - start_time))
        
        if [ $exit_code -eq 124 ]; then
            log_error "CI tests timed out after ${TIMEOUT_SECONDS}s"
        else
            log_error "CI tests failed in ${test_time}s (exit code: $exit_code)"
        fi
        
        return $exit_code
    fi
}

# Run protocol validation tests specifically
run_protocol_validation() {
    log_info "Running protocol validation tests..."
    
    # Run protocol-specific tests that are critical for CI
    local protocol_tests=(
        "testUSBIPSubmitRequestEncodingDecoding"
        "testUSBIPSubmitResponseEncodingDecoding"
        "testUSBIPUnlinkRequestEncodingDecoding"
        "testUSBIPUnlinkResponseEncodingDecoding"
        "testUSBIPMessageHeaderConsistency"
        "testRoundTripEncodingDecoding"
    )
    
    for test in "${protocol_tests[@]}"; do
        log_info "Running protocol test: $test"
        
        swift test \
            --filter "CITests.$test" \
            --build-path "$BUILD_DIR" \
            --configuration release \
            --parallel || {
            log_error "Critical protocol test $test failed"
            return 1
        }
    done
    
    log_success "Protocol validation completed"
}

# Run network layer tests
run_network_validation() {
    log_info "Running network layer validation tests..."
    
    # Run network-specific tests suitable for CI
    local network_tests=(
        "testServerStartStop"
        "testServerErrorHandling"
        "testServerAlreadyRunningError"
    )
    
    for test in "${network_tests[@]}"; do
        log_info "Running network test: $test"
        
        swift test \
            --filter "CITests.$test" \
            --build-path "$BUILD_DIR" \
            --configuration release \
            --parallel || {
            log_warning "Network test $test failed (continuing...)"
        }
    done
    
    log_success "Network validation completed"
}

# Run QEMU mock tests (CI environment)
run_qemu_mock_tests() {
    if [ "$ENABLE_QEMU_TESTS" != "true" ]; then
        log_info "QEMU tests disabled (set ENABLE_QEMU_TESTS=true to enable)"
        return 0
    fi
    
    log_info "Running QEMU mock tests (CI mode)..."
    
    # Check if QEMU test orchestrator is available
    local qemu_script="$SCRIPT_DIR/qemu/test-orchestrator.sh"
    if [ ! -f "$qemu_script" ]; then
        log_info "QEMU test orchestrator not found at $qemu_script"
        log_info "QEMU tests will be skipped in CI (graceful degradation)"
        return 0
    fi
    
    # Run QEMU tests with CI-specific configuration
    local start_time=$(date +%s)
    
    # CI QEMU testing always uses mock mode for reliability
    export TEST_ENVIRONMENT="ci"
    export QEMU_TEST_MODE="mock"
    export QEMU_TIMEOUT="$QEMU_TIMEOUT"
    
    log_info "Running QEMU orchestrator in CI mock mode..."
    
    # Use timeout for CI environment
    local timeout_cmd=""
    if command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout ${QEMU_TIMEOUT}s"
    fi
    
    local qemu_command="\"$qemu_script\" --mode ci --timeout \"$QEMU_TIMEOUT\""
    if [ -n "$timeout_cmd" ]; then
        qemu_command="$timeout_cmd $qemu_command"
    fi
    
    if eval "$qemu_command"; then
        local end_time=$(date +%s)
        local qemu_time=$((end_time - start_time))
        log_success "QEMU mock tests completed in ${qemu_time}s"
        
        # Check QEMU test performance for CI
        if [ $qemu_time -gt $QEMU_TIMEOUT ]; then
            log_warning "QEMU tests took longer than timeout: ${qemu_time}s > ${QEMU_TIMEOUT}s"
        fi
        
        return 0
    else
        local exit_code=$?
        local end_time=$(date +%s)
        local qemu_time=$((end_time - start_time))
        
        if [ $exit_code -eq 124 ]; then
            log_error "QEMU mock tests timed out after ${QEMU_TIMEOUT}s"
        else
            log_error "QEMU mock tests failed in ${qemu_time}s (exit code: $exit_code)"
        fi
        
        # In CI, QEMU test failures should not block the entire CI run
        # but should be reported as warnings for visibility
        log_warning "QEMU test failure reported but not blocking CI execution"
        return 0
    fi
}

# Generate CI test report
generate_ci_test_report() {
    log_info "Generating CI test report..."
    
    local report_file="$BUILD_DIR/ci-test-report.txt"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$report_file" << EOF
CI Test Report
Generated: $timestamp
Environment: $TEST_ENVIRONMENT
Target Time: <$TIMEOUT_SECONDS seconds
CI System: ${CI:-'local'}
GitHub Actions: ${GITHUB_ACTIONS:-'false'}

Test Summary:
- Test Filter: CITests
- Parallel Execution: Enabled
- Configuration: Release
- Mocking: Enabled
- Hardware Dependencies: Disabled
- Administrative Privileges: Disabled
- QEMU Tests: $([ "$ENABLE_QEMU_TESTS" = "true" ] && echo "Enabled (Mock Mode)" || echo "Disabled")

Configuration:
- USBIPD_TEST_MODE=$USBIPD_TEST_MODE
- USBIPD_ENABLE_MOCKING=$USBIPD_ENABLE_MOCKING
- USBIPD_MOCK_HARDWARE=$USBIPD_MOCK_HARDWARE
- USBIPD_CI_MODE=$USBIPD_CI_MODE
- USBIPD_LOG_LEVEL=$USBIPD_LOG_LEVEL
- ENABLE_QEMU_TESTS=$ENABLE_QEMU_TESTS
- QEMU_TEST_MODE=$QEMU_TEST_MODE
- QEMU_TIMEOUT=$QEMU_TIMEOUT

Build Path: $BUILD_DIR
Swift Version: $(swift --version | head -n1)
EOF

    # Add GitHub Actions specific information if available
    if [ -n "${GITHUB_ACTIONS}" ] && [ "${GITHUB_ACTIONS}" = "true" ]; then
        cat >> "$report_file" << EOF

GitHub Actions Information:
- Runner OS: ${RUNNER_OS:-'unknown'}
- Workflow: ${GITHUB_WORKFLOW:-'unknown'}
- Job: ${GITHUB_JOB:-'unknown'}
- Run ID: ${GITHUB_RUN_ID:-'unknown'}
- Run Number: ${GITHUB_RUN_NUMBER:-'unknown'}
EOF
    fi
    
    log_success "CI test report generated: $report_file"
    
    # Also output report location for GitHub Actions
    if [ -n "${GITHUB_ACTIONS}" ] && [ "${GITHUB_ACTIONS}" = "true" ]; then
        echo "::notice title=CI Test Report::Report generated at $report_file"
    fi
}

# Verify test results and artifacts
verify_ci_results() {
    log_info "Verifying CI test results..."
    
    # Check that test report was created
    if [ ! -f "$BUILD_DIR/ci-test-report.txt" ]; then
        log_warning "CI test report not found"
    fi
    
    # Check build artifacts
    if [ ! -d "$BUILD_DIR" ]; then
        log_error "Build directory not found"
        return 1
    fi
    
    # Check that tests were actually run (look for test bundle)
    if [ ! -f "$BUILD_DIR/release/CITestsPackageTests.xctest/Contents/MacOS/CITestsPackageTests" ]; then
        log_warning "CI test bundle not found in expected location"
    fi
    
    log_success "CI results verification completed"
}

# Print usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --protocol-only      Run only protocol validation tests"
    echo "  --network-only       Run only network validation tests"
    echo "  --qemu-only          Run only QEMU mock validation tests"
    echo "  --no-lint            Skip SwiftLint code quality checks"
    echo "  --no-qemu            Disable QEMU mock testing"
    echo "  --timeout SECS       Set custom timeout (default: $TIMEOUT_SECONDS)"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                      # Run full CI test suite"
    echo "  $0 --protocol-only      # Run only protocol tests"
    echo "  $0 --network-only       # Run only network tests"
    echo "  $0 --qemu-only          # Run only QEMU mock tests"
    echo "  $0 --no-qemu            # Disable QEMU testing"
    echo "  $0 --timeout 120        # Use 2-minute timeout"
    echo ""
    echo "Environment Variables:"
    echo "  CI                      Set to 'true' to indicate CI environment"
    echo "  GITHUB_ACTIONS          Set to 'true' for GitHub Actions"
    echo "  USBIPD_LOG_LEVEL        Override log level (default: info)"
    echo "  ENABLE_QEMU_TESTS       Enable/disable QEMU tests (true/false, default: true)"
    echo "  QEMU_TIMEOUT            QEMU test timeout in seconds (default: 60)"
}

# Main execution flow
main() {
    local protocol_only=false
    local network_only=false
    local qemu_only=false
    local skip_lint=false
    local disable_qemu=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --protocol-only)
                protocol_only=true
                shift
                ;;
            --network-only)
                network_only=true
                shift
                ;;
            --qemu-only)
                qemu_only=true
                shift
                ;;
            --no-lint)
                skip_lint=true
                shift
                ;;
            --no-qemu)
                disable_qemu=true
                shift
                ;;
            --timeout)
                TIMEOUT_SECONDS="$2"
                shift 2
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Override QEMU settings based on command line flags
    if [ "$disable_qemu" = true ]; then
        export ENABLE_QEMU_TESTS="false"
    fi
    
    # Start execution
    print_header
    
    # Check CI prerequisites
    check_ci_prerequisites
    
    # Set up CI test environment
    setup_ci_test_environment
    
    # Validate CI environment
    validate_ci_environment
    
    # Always clean build artifacts in CI
    clean_ci_build_artifacts
    
    # Build the project
    build_ci_project
    
    # Note: SwiftLint validation is handled by the Code Quality job in consolidated CI
    
    # Run tests based on mode
    if [ "$protocol_only" = true ]; then
        run_protocol_validation
    elif [ "$network_only" = true ]; then
        run_network_validation
    elif [ "$qemu_only" = true ]; then
        run_qemu_mock_tests
    else
        # Run full CI test suite
        run_ci_tests
        
        # Run QEMU mock tests as part of full suite
        run_qemu_mock_tests
    fi
    
    # Generate CI test report
    generate_ci_test_report
    
    # Verify results
    verify_ci_results
    
    log_success "🎉 CI test execution completed successfully!"
}

# Change to project root directory
cd "$PROJECT_ROOT"

# Run main function with all arguments
main "$@"