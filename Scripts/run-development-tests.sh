#!/bin/bash

# run-development-tests.sh
# Fast test execution script for development environment
# Targets sub-1-minute execution time for rapid feedback during feature development

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build"
TIMEOUT_SECONDS=60
TEST_ENVIRONMENT="development"

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
    echo "🚀 Development Test Environment Runner"
    echo "=================================================="
    echo "Environment: $TEST_ENVIRONMENT"
    echo "Target Time: <$TIMEOUT_SECONDS seconds"
    echo "Working Dir: $PROJECT_ROOT"
    echo "Build Dir: $BUILD_DIR"
    echo "=================================================="
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
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
    
    # Check for SwiftLint (optional but recommended)
    if ! command -v swiftlint >/dev/null 2>&1; then
        log_warning "SwiftLint not found. Code quality checks will be skipped."
    fi
    
    log_success "Prerequisites check completed"
}

# Set up test environment
setup_test_environment() {
    log_info "Setting up development test environment..."
    
    # Set environment variables for development testing
    export TEST_ENVIRONMENT="development"
    export SWIFT_TEST_PARALLEL="true"
    export SWIFT_TEST_TIMEOUT="$TIMEOUT_SECONDS"
    
    # Configure test environment for mocking
    export USBIPD_TEST_MODE="development"
    export USBIPD_ENABLE_MOCKING="true"
    export USBIPD_MOCK_HARDWARE="true"
    
    # QEMU testing configuration (optional in development)
    export ENABLE_QEMU_TESTS="${ENABLE_QEMU_TESTS:-false}"
    export QEMU_TEST_MODE="${QEMU_TEST_MODE:-mock}"
    export QEMU_TIMEOUT="${QEMU_TIMEOUT:-30}"
    
    # Disable verbose logging for faster execution
    export USBIPD_LOG_LEVEL="error"
    
    log_success "Test environment configured"
}

# Clean build artifacts if needed
clean_build_artifacts() {
    if [ "$1" = "--clean" ]; then
        log_info "Cleaning build artifacts..."
        rm -rf "$BUILD_DIR"
        log_success "Build artifacts cleaned"
    fi
}

# Build the project for testing
build_project() {
    log_info "Building project for development testing..."
    
    local start_time=$(date +%s)
    
    # Build only what's needed for testing
    swift build --build-tests \
        --configuration debug \
        --enable-test-discovery \
        --jobs $(sysctl -n hw.activecpu) \
        --build-path "$BUILD_DIR" || {
        log_error "Build failed"
        exit 1
    }
    
    local end_time=$(date +%s)
    local build_time=$((end_time - start_time))
    
    log_success "Build completed in ${build_time}s"
}

# Run SwiftLint for code quality (optional)
run_linting() {
    if command -v swiftlint >/dev/null 2>&1; then
        log_info "Running SwiftLint for development files..."
        
        # Only lint files likely to be modified during development
        swiftlint lint \
            --path Sources/ \
            --path Tests/DevelopmentTests.swift \
            --path Tests/TestMocks/Development/ \
            --reporter compact \
            --quiet || {
            log_warning "SwiftLint found issues (not blocking development tests)"
        }
        
        log_success "Linting completed"
    fi
}

# Run the development test suite
run_development_tests() {
    log_info "Running development test suite..."
    
    local start_time=$(date +%s)
    
    # Use gtimeout on macOS (from coreutils) or timeout on Linux
    local timeout_cmd=""
    if command -v gtimeout >/dev/null 2>&1; then
        timeout_cmd="gtimeout ${TIMEOUT_SECONDS}s"
    elif command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout ${TIMEOUT_SECONDS}s"
    else
        log_warning "No timeout command available, running without timeout"
        timeout_cmd=""
    fi
    
    # Run specific development tests with filtering
    local test_filter="DevelopmentTests"
    local test_command="swift test"
    
    # Add test filtering
    test_command="$test_command --filter $test_filter"
    
    # Add parallel execution
    test_command="$test_command --parallel"
    
    # Add build path
    test_command="$test_command --build-path $BUILD_DIR"
    
    # Add timeout if available
    if [ -n "$timeout_cmd" ]; then
        test_command="$timeout_cmd $test_command"
    fi
    
    # Execute the test command
    log_info "Executing: $test_command"
    
    if eval "$test_command"; then
        local end_time=$(date +%s)
        local test_time=$((end_time - start_time))
        
        log_success "Development tests passed in ${test_time}s"
        
        # Check if we met the performance target
        if [ $test_time -le $TIMEOUT_SECONDS ]; then
            log_success "✅ Performance target met: ${test_time}s ≤ ${TIMEOUT_SECONDS}s"
        else
            log_warning "⚠️ Performance target missed: ${test_time}s > ${TIMEOUT_SECONDS}s"
        fi
        
        return 0
    else
        local exit_code=$?
        local end_time=$(date +%s)
        local test_time=$((end_time - start_time))
        
        if [ $exit_code -eq 124 ]; then
            log_error "Tests timed out after ${TIMEOUT_SECONDS}s"
        else
            log_error "Tests failed in ${test_time}s (exit code: $exit_code)"
        fi
        
        return $exit_code
    fi
}

# Run QEMU tests (optional in development environment)
run_qemu_tests() {
    if [ "$ENABLE_QEMU_TESTS" != "true" ]; then
        log_info "QEMU tests disabled (set ENABLE_QEMU_TESTS=true to enable)"
        return 0
    fi
    
    log_info "Running QEMU tests (development mode)..."
    
    # Check if QEMU test orchestrator is available
    local qemu_script="$SCRIPT_DIR/qemu/test-orchestrator.sh"
    if [ ! -f "$qemu_script" ]; then
        log_warning "QEMU test orchestrator not found at $qemu_script"
        log_info "Skipping QEMU tests in development environment"
        return 0
    fi
    
    # Run QEMU tests with development-specific configuration
    local start_time=$(date +%s)
    
    # Development QEMU testing uses mock mode for speed
    export TEST_ENVIRONMENT="development"
    export QEMU_TEST_MODE="mock"
    export QEMU_TIMEOUT="$QEMU_TIMEOUT"
    
    log_info "Running QEMU orchestrator in development mode..."
    if "$qemu_script" --mode development --timeout "$QEMU_TIMEOUT"; then
        local end_time=$(date +%s)
        local qemu_time=$((end_time - start_time))
        log_success "QEMU tests completed in ${qemu_time}s"
        return 0
    else
        local exit_code=$?
        local end_time=$(date +%s)
        local qemu_time=$((end_time - start_time))
        log_warning "QEMU tests failed in ${qemu_time}s (exit code: $exit_code) - continuing development tests"
        return 0  # Don't fail development tests due to QEMU issues
    fi
}

# Run completion tests (development environment)
run_completion_tests() {
    log_info "Running shell completion tests..."
    
    # Check if completion test script exists
    local completion_test_script="$SCRIPT_DIR/test-completion-environment.sh"
    if [ ! -f "$completion_test_script" ]; then
        log_warning "Completion test script not found - skipping completion tests"
        return 0
    fi
    
    local start_time=$(date +%s)
    
    # Run completion tests in development mode with reduced scope
    if "$completion_test_script" \
        --shell bash \
        --test basic \
        --output "$BUILD_DIR/completion-test-results" \
        --verbose 2>/dev/null; then
        
        local end_time=$(date +%s)
        local completion_time=$((end_time - start_time))
        log_success "Completion tests passed in ${completion_time}s"
        return 0
    else
        local exit_code=$?
        local end_time=$(date +%s)
        local completion_time=$((end_time - start_time))
        log_warning "Completion tests failed in ${completion_time}s (exit code: $exit_code) - continuing development tests"
        return 0  # Don't fail development tests due to completion issues
    fi
}

# Run specific test categories for development
run_quick_validation() {
    log_info "Running quick validation tests..."
    
    # Run only the fastest, most critical tests
    local quick_tests=(
        "testLogLevelComparison"
        "testServerConfigDefaultInitialization" 
        "testUSBIPHeaderEncoding"
        "testEndiannessHandling"
    )
    
    for test in "${quick_tests[@]}"; do
        log_info "Running quick test: $test"
        
        swift test \
            --filter "DevelopmentTests.$test" \
            --build-path "$BUILD_DIR" \
            --parallel || {
            log_warning "Quick test $test failed (continuing...)"
        }
    done
    
    log_success "Quick validation completed"
}

# Generate development test report
generate_test_report() {
    log_info "Generating development test report..."
    
    local report_file="$BUILD_DIR/development-test-report.txt"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$report_file" << EOF
Development Test Report
Generated: $timestamp
Environment: $TEST_ENVIRONMENT
Target Time: <$TIMEOUT_SECONDS seconds

Test Summary:
- Test Filter: DevelopmentTests
- Parallel Execution: Enabled
- Mocking: Enabled
- Hardware Dependencies: Disabled
- QEMU Tests: $([ "$ENABLE_QEMU_TESTS" = "true" ] && echo "Enabled" || echo "Disabled")

Configuration:
- USBIPD_TEST_MODE=$USBIPD_TEST_MODE
- USBIPD_ENABLE_MOCKING=$USBIPD_ENABLE_MOCKING
- USBIPD_MOCK_HARDWARE=$USBIPD_MOCK_HARDWARE
- USBIPD_LOG_LEVEL=$USBIPD_LOG_LEVEL
- ENABLE_QEMU_TESTS=$ENABLE_QEMU_TESTS
- QEMU_TEST_MODE=$QEMU_TEST_MODE
- QEMU_TIMEOUT=$QEMU_TIMEOUT

Build Path: $BUILD_DIR
EOF
    
    log_success "Test report generated: $report_file"
}

# Print usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --clean          Clean build artifacts before testing"
    echo "  --quick          Run only quick validation tests"
    echo "  --no-lint        Skip SwiftLint code quality checks"
    echo "  --timeout SECS   Set custom timeout (default: $TIMEOUT_SECONDS)"
    echo "  --qemu           Enable QEMU testing (development mode)"
    echo "  --help           Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  ENABLE_QEMU_TESTS    Enable/disable QEMU tests (true/false, default: false)"
    echo "  QEMU_TEST_MODE       QEMU test mode (mock/vm, default: mock)"
    echo "  QEMU_TIMEOUT         QEMU test timeout in seconds (default: 30)"
    echo ""
    echo "Examples:"
    echo "  $0                     # Run full development test suite"
    echo "  $0 --clean             # Clean build and run tests"
    echo "  $0 --quick             # Run only quick validation"
    echo "  $0 --timeout 30        # Use 30-second timeout"
    echo "  $0 --qemu              # Enable QEMU testing"
    echo "  ENABLE_QEMU_TESTS=true $0  # Enable QEMU via environment"
}

# Main execution flow
main() {
    local clean_build=false
    local quick_mode=false
    local skip_lint=false
    local enable_qemu=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                clean_build=true
                shift
                ;;
            --quick)
                quick_mode=true
                shift
                ;;
            --no-lint)
                skip_lint=true
                shift
                ;;
            --timeout)
                TIMEOUT_SECONDS="$2"
                shift 2
                ;;
            --qemu)
                enable_qemu=true
                shift
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
    
    # Set QEMU environment variable if --qemu flag is used
    if [ "$enable_qemu" = true ]; then
        export ENABLE_QEMU_TESTS="true"
    fi
    
    # Start execution
    print_header
    
    # Check prerequisites
    check_prerequisites
    
    # Set up test environment
    setup_test_environment
    
    # Clean build artifacts if requested
    if [ "$clean_build" = true ]; then
        clean_build_artifacts --clean
    fi
    
    # Build the project
    build_project
    
    # Run linting unless skipped
    if [ "$skip_lint" = false ]; then
        run_linting
    fi
    
    # Run tests based on mode
    if [ "$quick_mode" = true ]; then
        run_quick_validation
    else
        run_development_tests
    fi
    
    # Run QEMU tests if enabled
    run_qemu_tests
    
    # Run completion tests
    run_completion_tests
    
    # Generate test report
    generate_test_report
    
    log_success "🎉 Development test execution completed successfully!"
}

# Change to project root directory
cd "$PROJECT_ROOT"

# Run main function with all arguments
main "$@"