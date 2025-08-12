#!/bin/bash

# Test Environment Setup Utility
# Validates test environment prerequisites and sets up environment-specific configurations
# Integrates with the environment-aware test system

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/.build"
readonly LOG_DIR="${BUILD_DIR}/logs"
readonly TEST_CONFIG_DIR="${PROJECT_ROOT}/Tests"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Environment Detection
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

readonly TEST_ENVIRONMENT="${TEST_ENVIRONMENT:-$(detect_test_environment)}"

# Logging functions
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
    echo -e "${BLUE}[ENVIRONMENT]${NC} Running test environment setup for: ${TEST_ENVIRONMENT}"
}

# ============================================================================
# CAPABILITY DETECTION
# ============================================================================

# Check if command is available
check_command_availability() {
    local command_name="$1"
    local required="${2:-false}"
    
    if command -v "$command_name" &> /dev/null; then
        log_success "Command available: $command_name"
        return 0
    else
        if [[ "$required" == "true" ]]; then
            log_error "Required command not available: $command_name"
            return 1
        else
            log_warning "Optional command not available: $command_name"
            return 0
        fi
    fi
}

# Check Swift toolchain
check_swift_toolchain() {
    log_info "Checking Swift toolchain..."
    
    if ! check_command_availability "swift" "true"; then
        return 1
    fi
    
    # Check Swift version
    local swift_version
    swift_version=$(swift --version 2>/dev/null | head -n1 || echo "Unknown")
    log_info "Swift version: $swift_version"
    
    # Check if we can build
    if ! swift build --help &> /dev/null; then
        log_error "Swift build command not functional"
        return 1
    fi
    
    log_success "Swift toolchain validation passed"
    return 0
}

# Check network connectivity
check_network_connectivity() {
    log_info "Checking network connectivity..."
    
    # Test basic connectivity
    local test_hosts=("github.com" "google.com")
    local connectivity_working=false
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 5000 "$host" &> /dev/null; then
            log_success "Network connectivity to $host: OK"
            connectivity_working=true
            break
        else
            log_warning "Network connectivity to $host: FAILED"
        fi
    done
    
    if [[ "$connectivity_working" == "true" ]]; then
        log_success "Network connectivity validation passed"
        return 0
    else
        log_warning "Network connectivity validation failed"
        return 1
    fi
}

# Check filesystem permissions
check_filesystem_permissions() {
    log_info "Checking filesystem permissions..."
    
    # Check if we can create directories
    local test_dirs=("$BUILD_DIR" "$LOG_DIR")
    
    for dir in "${test_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            if mkdir -p "$dir" 2>/dev/null; then
                log_success "Created directory: $dir"
            else
                log_error "Cannot create directory: $dir"
                return 1
            fi
        else
            log_info "Directory exists: $dir"
        fi
        
        # Check if we can write to the directory
        local test_file="${dir}/test-write-$$"
        if echo "test" > "$test_file" 2>/dev/null; then
            rm -f "$test_file"
            log_success "Write access confirmed: $dir"
        else
            log_error "Cannot write to directory: $dir"
            return 1
        fi
    done
    
    log_success "Filesystem permissions validation passed"
    return 0
}

# Check QEMU availability
check_qemu_availability() {
    log_info "Checking QEMU availability..."
    
    local qemu_commands=("qemu-system-x86_64" "qemu-img")
    local qemu_available=true
    
    for cmd in "${qemu_commands[@]}"; do
        if ! check_command_availability "$cmd" "false"; then
            qemu_available=false
        fi
    done
    
    if [[ "$qemu_available" == "true" ]]; then
        # Check QEMU version
        local qemu_version
        qemu_version=$(qemu-system-x86_64 --version 2>/dev/null | head -n1 || echo "Unknown")
        log_info "QEMU version: $qemu_version"
        log_success "QEMU availability validation passed"
        return 0
    else
        log_warning "QEMU not fully available (some integration tests may be skipped)"
        return 1
    fi
}

# Check hardware capabilities
check_hardware_capabilities() {
    log_info "Checking hardware capabilities..."
    
    # Check platform
    local platform
    platform=$(uname -s)
    log_info "Platform: $platform"
    
    case "$platform" in
        "Darwin")
            check_macos_capabilities
            ;;
        "Linux")
            check_linux_capabilities
            ;;
        *)
            log_warning "Unknown platform: $platform"
            return 1
            ;;
    esac
}

# Check macOS-specific capabilities
check_macos_capabilities() {
    log_info "Checking macOS-specific capabilities..."
    
    # Check macOS version
    if command -v sw_vers &> /dev/null; then
        local macos_version
        macos_version=$(sw_vers -productVersion)
        log_info "macOS version: $macos_version"
    fi
    
    # Check if System Extensions are supported
    if command -v systemextensionsctl &> /dev/null; then
        log_success "System Extensions support available"
    else
        log_warning "System Extensions support not available"
    fi
    
    # Check IOKit framework availability (for USB device access)
    if [[ -d "/System/Library/Frameworks/IOKit.framework" ]]; then
        log_success "IOKit framework available"
    else
        log_warning "IOKit framework not found"
    fi
    
    log_success "macOS capabilities validation completed"
    return 0
}

# Check Linux-specific capabilities
check_linux_capabilities() {
    log_info "Checking Linux-specific capabilities..."
    
    # Check if running in container/CI
    if [[ -f "/.dockerenv" ]] || [[ -n "${CONTAINER:-}" ]]; then
        log_info "Running in container environment"
    fi
    
    # Check USB/IP client tools
    if check_command_availability "usbip" "false"; then
        local usbip_version
        usbip_version=$(usbip version 2>/dev/null || echo "Unknown")
        log_info "USB/IP version: $usbip_version"
    fi
    
    log_success "Linux capabilities validation completed"
    return 0
}

# Check administrative privileges
check_administrative_privileges() {
    log_info "Checking administrative privileges..."
    
    local has_admin_privileges=false
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        log_info "Running as root"
        has_admin_privileges=true
    fi
    
    # Check if sudo is available and user can use it
    if command -v sudo &> /dev/null; then
        if sudo -n true 2>/dev/null; then
            log_info "Passwordless sudo available"
            has_admin_privileges=true
        elif [[ "$TEST_ENVIRONMENT" != "ci" ]]; then
            # Only prompt for sudo in non-CI environments
            if sudo true 2>/dev/null; then
                log_info "Sudo available with password"
                has_admin_privileges=true
            fi
        fi
    fi
    
    if [[ "$has_admin_privileges" == "true" ]]; then
        log_success "Administrative privileges available"
        return 0
    else
        log_warning "Administrative privileges not available (some tests may be skipped)"
        return 1
    fi
}

# ============================================================================
# ENVIRONMENT-SPECIFIC SETUP
# ============================================================================

# Setup development environment
setup_development_environment() {
    log_info "Setting up development environment..."
    
    # Create development-specific directories
    local dev_dirs=("$BUILD_DIR/development" "$LOG_DIR/development")
    for dir in "${dev_dirs[@]}"; do
        mkdir -p "$dir"
        log_info "Created development directory: $dir"
    done
    
    # Set development-specific environment variables
    export SWIFT_BUILD_CONFIGURATION="debug"
    export TEST_TIMEOUT="30"
    export ENABLE_FAST_MODE="true"
    export MOCK_LEVEL="comprehensive"
    
    log_success "Development environment setup completed"
    return 0
}

# Setup CI environment
setup_ci_environment() {
    log_info "Setting up CI environment..."
    
    # Create CI-specific directories
    local ci_dirs=("$BUILD_DIR/ci" "$LOG_DIR/ci")
    for dir in "${ci_dirs[@]}"; do
        mkdir -p "$dir"
        log_info "Created CI directory: $dir"
    done
    
    # Set CI-specific environment variables
    export SWIFT_BUILD_CONFIGURATION="release"
    export TEST_TIMEOUT="60"
    export ENABLE_CI_MODE="true"
    export MOCK_LEVEL="selective"
    export CI_RETRY_COUNT="1"
    
    # Disable interactive prompts
    export DEBIAN_FRONTEND=noninteractive
    export SWIFT_DISABLE_INTERACTIVE="1"
    
    log_success "CI environment setup completed"
    return 0
}

# Setup production environment
setup_production_environment() {
    log_info "Setting up production environment..."
    
    # Create production-specific directories
    local prod_dirs=("$BUILD_DIR/production" "$LOG_DIR/production")
    for dir in "${prod_dirs[@]}"; do
        mkdir -p "$dir"
        log_info "Created production directory: $dir"
    done
    
    # Set production-specific environment variables
    export SWIFT_BUILD_CONFIGURATION="release"
    export TEST_TIMEOUT="120"
    export ENABLE_COMPREHENSIVE_TESTS="true"
    export MOCK_LEVEL="minimal"
    export ENABLE_HARDWARE_TESTS="true"
    export ENABLE_QEMU_TESTS="true"
    export ENABLE_SYSTEM_EXTENSION_TESTS="true"
    
    log_success "Production environment setup completed"
    return 0
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

# Validate development environment requirements
validate_development_requirements() {
    log_info "Validating development environment requirements..."
    
    local validation_passed=true
    
    # Essential requirements for development
    if ! check_swift_toolchain; then
        validation_passed=false
    fi
    
    if ! check_filesystem_permissions; then
        validation_passed=false
    fi
    
    # Optional but recommended for development
    check_network_connectivity || true
    check_qemu_availability || true
    
    if [[ "$validation_passed" == "true" ]]; then
        log_success "Development environment validation passed"
        return 0
    else
        log_error "Development environment validation failed"
        return 1
    fi
}

# Validate CI environment requirements
validate_ci_requirements() {
    log_info "Validating CI environment requirements..."
    
    local validation_passed=true
    
    # Essential requirements for CI
    if ! check_swift_toolchain; then
        validation_passed=false
    fi
    
    if ! check_filesystem_permissions; then
        validation_passed=false
    fi
    
    if ! check_network_connectivity; then
        log_warning "Network connectivity issues may affect CI tests"
    fi
    
    # CI-specific checks
    if [[ -z "${CI:-}" && -z "${GITHUB_ACTIONS:-}" ]]; then
        log_warning "CI environment variables not detected"
    fi
    
    if [[ "$validation_passed" == "true" ]]; then
        log_success "CI environment validation passed"
        return 0
    else
        log_error "CI environment validation failed"
        return 1
    fi
}

# Validate production environment requirements
validate_production_requirements() {
    log_info "Validating production environment requirements..."
    
    local validation_passed=true
    
    # Essential requirements for production
    if ! check_swift_toolchain; then
        validation_passed=false
    fi
    
    if ! check_filesystem_permissions; then
        validation_passed=false
    fi
    
    if ! check_network_connectivity; then
        validation_passed=false
    fi
    
    # Production-specific checks
    if ! check_hardware_capabilities; then
        log_warning "Hardware capability issues detected"
    fi
    
    if ! check_qemu_availability; then
        log_warning "QEMU not available (integration tests will be limited)"
    fi
    
    if ! check_administrative_privileges; then
        log_warning "Administrative privileges not available (some tests will be skipped)"
    fi
    
    if [[ "$validation_passed" == "true" ]]; then
        log_success "Production environment validation passed"
        return 0
    else
        log_error "Production environment validation failed"
        return 1
    fi
}

# ============================================================================
# MAIN SETUP FUNCTION
# ============================================================================

# Main environment setup function
setup_test_environment() {
    local environment="${1:-$TEST_ENVIRONMENT}"
    local validate_only="${2:-false}"
    
    log_environment
    log_info "Setting up test environment: $environment"
    
    # Validate and setup based on environment
    case "$environment" in
        "development")
            if ! validate_development_requirements; then
                return 1
            fi
            if [[ "$validate_only" == "false" ]]; then
                setup_development_environment
            fi
            ;;
        "ci")
            if ! validate_ci_requirements; then
                return 1
            fi
            if [[ "$validate_only" == "false" ]]; then
                setup_ci_environment
            fi
            ;;
        "production")
            if ! validate_production_requirements; then
                return 1
            fi
            if [[ "$validate_only" == "false" ]]; then
                setup_production_environment
            fi
            ;;
        *)
            log_error "Unknown test environment: $environment"
            return 1
            ;;
    esac
    
    if [[ "$validate_only" == "true" ]]; then
        log_success "Environment validation completed for: $environment"
    else
        log_success "Environment setup completed for: $environment"
    fi
    
    return 0
}

# Generate environment report
generate_environment_report() {
    local report_file="${1:-${PROJECT_ROOT}/test-environment-report.txt}"
    
    log_info "Generating environment report: $(basename "$report_file")"
    
    {
        echo "Test Environment Setup Report"
        echo "============================"
        echo "Generated: $(date)"
        echo "Environment: $TEST_ENVIRONMENT"
        echo "Platform: $(uname -s) $(uname -m)"
        echo "Kernel: $(uname -r)"
        echo ""
        
        echo "Project Structure:"
        echo "  Project Root: $PROJECT_ROOT"
        echo "  Build Directory: $BUILD_DIR"
        echo "  Log Directory: $LOG_DIR"
        echo "  Test Config Directory: $TEST_CONFIG_DIR"
        echo ""
        
        echo "Swift Toolchain:"
        if command -v swift &> /dev/null; then
            swift --version | head -n1 | sed 's/^/  /'
        else
            echo "  Swift not available"
        fi
        echo ""
        
        echo "System Capabilities:"
        echo "  Network Connectivity: $(check_network_connectivity &>/dev/null && echo "Available" || echo "Limited")"
        echo "  QEMU Integration: $(check_qemu_availability &>/dev/null && echo "Available" || echo "Not Available")"
        echo "  Administrative Privileges: $(check_administrative_privileges &>/dev/null && echo "Available" || echo "Not Available")"
        echo ""
        
        echo "Environment Variables:"
        env | grep -E "^(TEST_|SWIFT_|CI|GITHUB)" | sort | sed 's/^/  /' || echo "  No relevant environment variables set"
        
    } > "$report_file"
    
    log_success "Environment report generated: $(basename "$report_file")"
    return 0
}

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Test Environment Setup Utility

COMMANDS:
    setup [environment]                     Setup test environment (development|ci|production)
    validate [environment]                  Validate environment without setup
    check-capabilities                      Check system capabilities
    generate-report [output_file]           Generate environment report
    info                                    Show environment information

OPTIONS:
    -h, --help                              Show this help message

ENVIRONMENT VARIABLES:
    TEST_ENVIRONMENT=development|ci|production  Override environment detection

EXAMPLES:
    $0 setup development                    Setup development environment
    $0 validate ci                          Validate CI environment
    $0 check-capabilities                   Check all system capabilities
    $0 generate-report env-report.txt       Generate detailed environment report
    TEST_ENVIRONMENT=production $0 setup    Setup production environment

EOF
}

# Main function for command line execution
main() {
    local command="${1:-setup}"
    
    case "$command" in
        "setup")
            setup_test_environment "${2:-$TEST_ENVIRONMENT}" "false"
            exit_code=$?
            exit $exit_code
            ;;
        "validate")
            setup_test_environment "${2:-$TEST_ENVIRONMENT}" "true"
            exit_code=$?
            exit $exit_code
            ;;
        "check-capabilities")
            log_info "Checking all system capabilities..."
            check_swift_toolchain
            check_network_connectivity
            check_filesystem_permissions
            check_qemu_availability
            check_hardware_capabilities
            check_administrative_privileges
            log_success "Capability check completed"
            ;;
        "generate-report")
            generate_environment_report "${2:-}"
            exit_code=$?
            exit $exit_code
            ;;
        "info")
            log_environment
            echo "Project Root: $PROJECT_ROOT"
            echo "Build Directory: $BUILD_DIR"
            echo "Log Directory: $LOG_DIR"
            echo "Test Config Directory: $TEST_CONFIG_DIR"
            ;;
        "-h"|"--help")
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