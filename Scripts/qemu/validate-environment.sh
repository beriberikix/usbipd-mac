#!/bin/bash

# QEMU Environment Validation Script
# Validates QEMU testing environment prerequisites and capabilities
# Ensures environment readiness for QEMU testing with comprehensive checks

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/.build"
readonly QEMU_BUILD_DIR="${BUILD_DIR}/qemu"
readonly QEMU_LOG_DIR="${QEMU_BUILD_DIR}/logs"
readonly QEMU_IMAGE_DIR="${QEMU_BUILD_DIR}/images"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Environment Detection
detect_qemu_test_environment() {
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

readonly TEST_ENVIRONMENT="${TEST_ENVIRONMENT:-$(detect_qemu_test_environment)}"

# Logging functions
log_info() {
    echo -e "${BLUE}[QEMU:INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[QEMU:SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[QEMU:WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[QEMU:ERROR]${NC} $1"
}

log_check() {
    echo -e "${BLUE}[QEMU:CHECK]${NC} $1"
}

# ============================================================================
# QEMU CAPABILITY DETECTION
# ============================================================================

# Check if QEMU commands are available
check_qemu_commands() {
    log_check "Checking QEMU command availability..."
    
    local qemu_commands=("qemu-system-x86_64" "qemu-img" "qemu-nbd")
    local commands_available=true
    local available_commands=()
    local missing_commands=()
    
    for cmd in "${qemu_commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            available_commands+=("$cmd")
            log_success "Command available: $cmd"
        else
            missing_commands+=("$cmd")
            commands_available=false
            log_warning "Command missing: $cmd"
        fi
    done
    
    if [[ "$commands_available" == "true" ]]; then
        log_success "All QEMU commands available"
        return 0
    else
        log_warning "Missing QEMU commands: ${missing_commands[*]}"
        log_info "Available commands: ${available_commands[*]}"
        return 1
    fi
}

# Check QEMU version compatibility
check_qemu_version() {
    log_check "Checking QEMU version compatibility..."
    
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        log_error "qemu-system-x86_64 not available"
        return 1
    fi
    
    local qemu_version_output
    qemu_version_output=$(qemu-system-x86_64 --version 2>/dev/null | head -n1 || echo "Unknown")
    log_info "QEMU version: $qemu_version_output"
    
    # Extract version number (format: QEMU emulator version X.Y.Z)
    local version_number
    if [[ "$qemu_version_output" =~ version\ ([0-9]+\.[0-9]+) ]]; then
        version_number="${BASH_REMATCH[1]}"
        log_info "Extracted version number: $version_number"
        
        # Check if version is >= 5.0 (reasonable minimum for our testing)
        local major_version="${version_number%%.*}"
        if [[ "$major_version" -ge 5 ]]; then
            log_success "QEMU version is compatible (>= 5.0)"
            return 0
        else
            log_warning "QEMU version may be too old (< 5.0), testing might be limited"
            return 1
        fi
    else
        log_warning "Could not extract QEMU version number"
        return 1
    fi
}

# Check QEMU acceleration support
check_qemu_acceleration() {
    log_check "Checking QEMU acceleration support..."
    
    local platform
    platform=$(uname -s)
    
    case "$platform" in
        "Darwin")
            # Check for Hypervisor.framework support on macOS
            if qemu-system-x86_64 -accel help 2>/dev/null | grep -q "hvf"; then
                log_success "Hypervisor.framework acceleration available"
                return 0
            else
                log_warning "Hypervisor.framework acceleration not available"
                return 1
            fi
            ;;
        "Linux")
            # Check for KVM support on Linux
            if qemu-system-x86_64 -accel help 2>/dev/null | grep -q "kvm"; then
                if [[ -c /dev/kvm ]]; then
                    log_success "KVM acceleration available"
                    return 0
                else
                    log_warning "KVM module loaded but /dev/kvm not accessible"
                    return 1
                fi
            else
                log_warning "KVM acceleration not available"
                return 1
            fi
            ;;
        *)
            log_warning "Unknown platform for acceleration check: $platform"
            return 1
            ;;
    esac
}

# Check QEMU network capabilities
check_qemu_network() {
    log_check "Checking QEMU network capabilities..."
    
    # Test if we can create TAP interfaces (requires privileges)
    local network_capable=false
    
    # Check if we're running with privileges
    if [[ $EUID -eq 0 ]]; then
        log_info "Running with root privileges - network setup should work"
        network_capable=true
    elif command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
        log_info "Passwordless sudo available - network setup should work"
        network_capable=true
    else
        log_info "Limited privileges - will use user-mode networking"
    fi
    
    # Check if we can use user-mode networking (slirp)
    if qemu-system-x86_64 -netdev help 2>/dev/null | grep -q "user"; then
        log_success "User-mode networking (slirp) available"
        network_capable=true
    else
        log_warning "User-mode networking not available"
    fi
    
    if [[ "$network_capable" == "true" ]]; then
        log_success "QEMU network capabilities validated"
        return 0
    else
        log_error "No usable QEMU network configuration found"
        return 1
    fi
}

# Check system resources
check_system_resources() {
    log_check "Checking system resources for QEMU testing..."
    
    local resources_adequate=true
    
    # Check available memory (need at least 1GB free)
    local available_memory_kb
    case "$(uname -s)" in
        "Darwin")
            available_memory_kb=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//' | awk '{print $1 * 4}')
            ;;
        "Linux")
            available_memory_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
            ;;
        *)
            available_memory_kb=0
            ;;
    esac
    
    if [[ "$available_memory_kb" -gt 1048576 ]]; then  # 1GB in KB
        local available_memory_mb=$((available_memory_kb / 1024))
        log_success "Adequate memory available: ${available_memory_mb}MB"
    else
        log_warning "Low available memory: ${available_memory_kb}KB (may affect VM performance)"
        resources_adequate=false
    fi
    
    # Check available disk space (need at least 2GB free)
    local available_space_kb
    available_space_kb=$(df "$PROJECT_ROOT" | tail -1 | awk '{print $4}')
    
    if [[ "$available_space_kb" -gt 2097152 ]]; then  # 2GB in KB
        local available_space_mb=$((available_space_kb / 1024))
        log_success "Adequate disk space available: ${available_space_mb}MB"
    else
        log_warning "Low disk space available: ${available_space_kb}KB (may affect VM image creation)"
        resources_adequate=false
    fi
    
    if [[ "$resources_adequate" == "true" ]]; then
        log_success "System resources validation passed"
        return 0
    else
        log_warning "System resources may be insufficient for optimal QEMU testing"
        return 1
    fi
}

# Check QEMU test infrastructure
check_qemu_test_infrastructure() {
    log_check "Checking QEMU test infrastructure..."
    
    local infrastructure_ready=true
    
    # Check if QEMU directories can be created
    local qemu_dirs=("$QEMU_BUILD_DIR" "$QEMU_LOG_DIR" "$QEMU_IMAGE_DIR")
    
    for dir in "${qemu_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            if mkdir -p "$dir" 2>/dev/null; then
                log_success "Created QEMU directory: $dir"
            else
                log_error "Cannot create QEMU directory: $dir"
                infrastructure_ready=false
            fi
        else
            log_info "QEMU directory exists: $dir"
        fi
        
        # Check write permissions
        local test_file="${dir}/test-write-$$"
        if echo "test" > "$test_file" 2>/dev/null; then
            rm -f "$test_file"
            log_success "Write access confirmed: $dir"
        else
            log_error "Cannot write to QEMU directory: $dir"
            infrastructure_ready=false
        fi
    done
    
    # Check if QEMUTestServer binary exists or can be built
    local qemu_test_server="$BUILD_DIR/release/QEMUTestServer"
    if [[ -f "$qemu_test_server" ]]; then
        log_success "QEMUTestServer binary found: $qemu_test_server"
    else
        log_info "QEMUTestServer binary not found, checking if it can be built..."
        if cd "$PROJECT_ROOT" && swift build --product QEMUTestServer --configuration release &>/dev/null; then
            log_success "QEMUTestServer built successfully"
        else
            log_warning "QEMUTestServer cannot be built (may affect QEMU testing)"
            infrastructure_ready=false
        fi
    fi
    
    # Check for QEMU test orchestrator
    local qemu_orchestrator="$SCRIPT_DIR/test-orchestrator.sh"
    if [[ -f "$qemu_orchestrator" ]]; then
        log_success "QEMU test orchestrator found: $qemu_orchestrator"
    else
        log_warning "QEMU test orchestrator not found: $qemu_orchestrator"
        infrastructure_ready=false
    fi
    
    if [[ "$infrastructure_ready" == "true" ]]; then
        log_success "QEMU test infrastructure validation passed"
        return 0
    else
        log_error "QEMU test infrastructure validation failed"
        return 1
    fi
}

# ============================================================================
# ENVIRONMENT-SPECIFIC VALIDATION
# ============================================================================

# Validate development environment for QEMU testing
validate_development_qemu() {
    log_info "Validating QEMU capabilities for development environment..."
    
    local validation_passed=true
    
    # Essential checks for development
    if ! check_qemu_commands; then
        log_info "QEMU commands not available - QEMU tests will be skipped in development"
        return 0  # Not blocking for development
    fi
    
    if ! check_qemu_version; then
        log_warning "QEMU version issues detected"
    fi
    
    # Infrastructure should be available
    if ! check_qemu_test_infrastructure; then
        validation_passed=false
    fi
    
    # Optional checks for development
    check_qemu_acceleration || log_info "QEMU acceleration not available (tests will be slower)"
    check_qemu_network || log_info "Limited QEMU network capabilities"
    check_system_resources || log_info "System resources may limit QEMU testing"
    
    if [[ "$validation_passed" == "true" ]]; then
        log_success "QEMU development environment validation passed"
        return 0
    else
        log_error "QEMU development environment validation failed"
        return 1
    fi
}

# Validate CI environment for QEMU testing
validate_ci_qemu() {
    log_info "Validating QEMU capabilities for CI environment..."
    
    local validation_passed=true
    
    # In CI, QEMU tests should gracefully degrade if not available
    if ! check_qemu_commands; then
        log_info "QEMU commands not available in CI - tests will run in mock mode"
        return 0  # Graceful degradation in CI
    fi
    
    if ! check_qemu_version; then
        log_warning "QEMU version issues in CI environment"
    fi
    
    # Infrastructure must be available in CI
    if ! check_qemu_test_infrastructure; then
        validation_passed=false
    fi
    
    # CI-specific checks
    check_system_resources || log_warning "Limited system resources in CI"
    
    # Network and acceleration are less critical in CI
    check_qemu_network || log_info "Using simplified networking in CI"
    check_qemu_acceleration || log_info "No acceleration in CI (expected)"
    
    if [[ "$validation_passed" == "true" ]]; then
        log_success "QEMU CI environment validation passed"
        return 0
    else
        log_warning "QEMU CI environment has limitations but will proceed"
        return 0  # Don't fail CI due to QEMU issues
    fi
}

# Validate production environment for QEMU testing
validate_production_qemu() {
    log_info "Validating QEMU capabilities for production environment..."
    
    local validation_passed=true
    local warnings_count=0
    
    # Production requires comprehensive QEMU support
    if ! check_qemu_commands; then
        log_error "QEMU commands required for production testing"
        validation_passed=false
    fi
    
    if ! check_qemu_version; then
        log_warning "QEMU version issues may affect production testing"
        warnings_count=$((warnings_count + 1))
    fi
    
    if ! check_qemu_test_infrastructure; then
        log_error "QEMU test infrastructure required for production"
        validation_passed=false
    fi
    
    if ! check_system_resources; then
        log_warning "System resources may be insufficient for production testing"
        warnings_count=$((warnings_count + 1))
    fi
    
    if ! check_qemu_network; then
        log_warning "QEMU network limitations may affect production testing"
        warnings_count=$((warnings_count + 1))
    fi
    
    if ! check_qemu_acceleration; then
        log_warning "No QEMU acceleration available (testing will be slower)"
        warnings_count=$((warnings_count + 1))
    fi
    
    if [[ "$validation_passed" == "true" ]]; then
        if [[ "$warnings_count" -eq 0 ]]; then
            log_success "QEMU production environment validation passed with no warnings"
        else
            log_success "QEMU production environment validation passed with $warnings_count warnings"
        fi
        return 0
    else
        log_error "QEMU production environment validation failed"
        return 1
    fi
}

# ============================================================================
# INSTALLATION HELPERS
# ============================================================================

# Provide QEMU installation instructions
show_qemu_installation_instructions() {
    log_info "QEMU Installation Instructions:"
    
    local platform
    platform=$(uname -s)
    
    case "$platform" in
        "Darwin")
            cat << EOF

For macOS, you can install QEMU using:

1. Homebrew (recommended):
   brew install qemu

2. MacPorts:
   sudo port install qemu

3. Building from source:
   Visit https://www.qemu.org/download/#source

After installation, verify with:
   qemu-system-x86_64 --version

EOF
            ;;
        "Linux")
            cat << EOF

For Linux, you can install QEMU using your package manager:

Ubuntu/Debian:
   sudo apt-get update
   sudo apt-get install qemu-system-x86 qemu-utils

RHEL/CentOS/Fedora:
   sudo yum install qemu-system-x86 qemu-img
   # or
   sudo dnf install qemu-system-x86 qemu-img

Arch Linux:
   sudo pacman -S qemu

After installation, verify with:
   qemu-system-x86_64 --version

EOF
            ;;
        *)
            cat << EOF

For your platform ($platform), please visit:
https://www.qemu.org/download/

Follow the installation instructions for your specific OS.

EOF
            ;;
    esac
}

# ============================================================================
# REPORTING
# ============================================================================

# Generate QEMU environment report
generate_qemu_report() {
    local report_file="${1:-${PROJECT_ROOT}/qemu-environment-report.txt}"
    
    log_info "Generating QEMU environment report: $(basename "$report_file")"
    
    {
        echo "QEMU Environment Validation Report"
        echo "=================================="
        echo "Generated: $(date)"
        echo "Test Environment: $TEST_ENVIRONMENT"
        echo "Platform: $(uname -s) $(uname -m)"
        echo "Kernel: $(uname -r)"
        echo ""
        
        echo "QEMU Installation:"
        if command -v qemu-system-x86_64 &> /dev/null; then
            qemu-system-x86_64 --version | head -n1 | sed 's/^/  /'
            echo "  Installation Path: $(command -v qemu-system-x86_64)"
        else
            echo "  QEMU not installed"
        fi
        echo ""
        
        echo "QEMU Commands:"
        local qemu_commands=("qemu-system-x86_64" "qemu-img" "qemu-nbd")
        for cmd in "${qemu_commands[@]}"; do
            if command -v "$cmd" &> /dev/null; then
                echo "  $cmd: Available ($(command -v "$cmd"))"
            else
                echo "  $cmd: Not Available"
            fi
        done
        echo ""
        
        echo "Acceleration Support:"
        case "$(uname -s)" in
            "Darwin")
                if qemu-system-x86_64 -accel help 2>/dev/null | grep -q "hvf"; then
                    echo "  Hypervisor.framework: Available"
                else
                    echo "  Hypervisor.framework: Not Available"
                fi
                ;;
            "Linux")
                if qemu-system-x86_64 -accel help 2>/dev/null | grep -q "kvm"; then
                    echo "  KVM: Available"
                else
                    echo "  KVM: Not Available"
                fi
                ;;
        esac
        echo ""
        
        echo "System Resources:"
        case "$(uname -s)" in
            "Darwin")
                echo "  Available Memory: $(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//' | awk '{print ($1 * 4) / 1024}')MB"
                ;;
            "Linux")
                echo "  Available Memory: $(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)MB"
                ;;
        esac
        echo "  Available Disk Space: $(df "$PROJECT_ROOT" | tail -1 | awk '{print int($4/1024)}')MB"
        echo ""
        
        echo "QEMU Test Infrastructure:"
        echo "  Project Root: $PROJECT_ROOT"
        echo "  QEMU Build Directory: $QEMU_BUILD_DIR"
        echo "  QEMU Log Directory: $QEMU_LOG_DIR"
        echo "  QEMU Image Directory: $QEMU_IMAGE_DIR"
        echo ""
        
        local qemu_test_server="$BUILD_DIR/release/QEMUTestServer"
        if [[ -f "$qemu_test_server" ]]; then
            echo "  QEMUTestServer: Available ($qemu_test_server)"
        else
            echo "  QEMUTestServer: Not Built"
        fi
        
        local qemu_orchestrator="$SCRIPT_DIR/test-orchestrator.sh"
        if [[ -f "$qemu_orchestrator" ]]; then
            echo "  Test Orchestrator: Available ($qemu_orchestrator)"
        else
            echo "  Test Orchestrator: Not Available"
        fi
        echo ""
        
        echo "Validation Results:"
        echo "  Development: $(validate_development_qemu &>/dev/null && echo "PASS" || echo "FAIL")"
        echo "  CI: $(validate_ci_qemu &>/dev/null && echo "PASS" || echo "FAIL")"
        echo "  Production: $(validate_production_qemu &>/dev/null && echo "PASS" || echo "FAIL")"
        
    } > "$report_file"
    
    log_success "QEMU environment report generated: $(basename "$report_file")"
    return 0
}

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

QEMU Environment Validation Script

COMMANDS:
    validate [environment]                  Validate QEMU environment (development|ci|production)
    check-commands                          Check QEMU command availability
    check-version                          Check QEMU version compatibility
    check-acceleration                     Check QEMU acceleration support
    check-network                          Check QEMU network capabilities
    check-resources                        Check system resources
    check-infrastructure                   Check QEMU test infrastructure
    check-all                              Run all capability checks
    install-help                           Show QEMU installation instructions
    generate-report [output_file]          Generate QEMU environment report
    info                                   Show QEMU environment information

OPTIONS:
    -h, --help                             Show this help message

ENVIRONMENT VARIABLES:
    TEST_ENVIRONMENT=development|ci|production  Override environment detection

EXAMPLES:
    $0 validate development                Validate development environment
    $0 check-all                          Check all QEMU capabilities
    $0 install-help                       Show installation instructions
    $0 generate-report qemu-report.txt    Generate detailed report
    TEST_ENVIRONMENT=production $0 validate  Validate production environment

EOF
}

# Main function for command line execution
main() {
    local command="${1:-validate}"
    
    case "$command" in
        "validate")
            local environment="${2:-$TEST_ENVIRONMENT}"
            case "$environment" in
                "development")
                    validate_development_qemu
                    exit_code=$?
                    ;;
                "ci")
                    validate_ci_qemu
                    exit_code=$?
                    ;;
                "production")
                    validate_production_qemu
                    exit_code=$?
                    ;;
                *)
                    log_error "Unknown environment: $environment"
                    exit 1
                    ;;
            esac
            exit $exit_code
            ;;
        "check-commands")
            check_qemu_commands
            exit $?
            ;;
        "check-version")
            check_qemu_version
            exit $?
            ;;
        "check-acceleration")
            check_qemu_acceleration
            exit $?
            ;;
        "check-network")
            check_qemu_network
            exit $?
            ;;
        "check-resources")
            check_system_resources
            exit $?
            ;;
        "check-infrastructure")
            check_qemu_test_infrastructure
            exit $?
            ;;
        "check-all")
            log_info "Running all QEMU capability checks..."
            local overall_result=0
            
            check_qemu_commands || overall_result=1
            check_qemu_version || overall_result=1
            check_qemu_acceleration || overall_result=1
            check_qemu_network || overall_result=1
            check_system_resources || overall_result=1
            check_qemu_test_infrastructure || overall_result=1
            
            if [[ $overall_result -eq 0 ]]; then
                log_success "All QEMU capability checks passed"
            else
                log_warning "Some QEMU capability checks failed or had warnings"
            fi
            exit $overall_result
            ;;
        "install-help")
            show_qemu_installation_instructions
            exit 0
            ;;
        "generate-report")
            generate_qemu_report "${2:-}"
            exit $?
            ;;
        "info")
            echo "QEMU Environment Information:"
            echo "  Test Environment: $TEST_ENVIRONMENT"
            echo "  Project Root: $PROJECT_ROOT"
            echo "  QEMU Build Directory: $QEMU_BUILD_DIR"
            echo "  QEMU Log Directory: $QEMU_LOG_DIR"
            echo "  QEMU Image Directory: $QEMU_IMAGE_DIR"
            if command -v qemu-system-x86_64 &> /dev/null; then
                echo "  QEMU Version: $(qemu-system-x86_64 --version | head -n1)"
            else
                echo "  QEMU: Not Available"
            fi
            exit 0
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