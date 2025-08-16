#!/bin/bash

# validate-homebrew-installation.sh
# Comprehensive Homebrew Installation Validation for usbipd-mac
# Post-installation verification script that validates binary functionality,
# service configuration, System Extension status, and overall installation success
# Provides detailed diagnostics and troubleshooting information

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly VALIDATION_DIR="${PROJECT_ROOT}/.build/installation-validation"
readonly LOG_FILE="${VALIDATION_DIR}/installation-validation-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Configuration variables
HOMEBREW_PREFIX=""
PACKAGE_NAME="usbipd-mac"
SKIP_SERVICE_TESTS=false
SKIP_SYSEXT_TESTS=false
SKIP_NETWORK_TESTS=false
VERBOSE=false
DRY_RUN=false
QUICK_CHECK=false
INTERACTIVE=true
GENERATE_REPORT=true

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_VALIDATION_FAILED=1
readonly EXIT_BINARY_NOT_FOUND=2
readonly EXIT_SERVICE_FAILED=3
readonly EXIT_SYSEXT_FAILED=4
readonly EXIT_NETWORK_FAILED=5
readonly EXIT_USAGE_ERROR=6

# Logging functions
log_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
}

log_step() {
    local message="$1"
    echo -e "${BOLD}${CYAN}==>${NC}${BOLD} $message${NC}" | tee -a "$LOG_FILE"
}

log_debug() {
    local message="$1"
    if [ "$VERBOSE" = true ]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
    fi
}

log_result() {
    local status="$1"
    local message="$2"
    local icon
    local color
    
    case "$status" in
        "PASS")
            icon="✅"
            color="$GREEN"
            ;;
        "FAIL")
            icon="❌"
            color="$RED"
            ;;
        "WARN")
            icon="⚠️"
            color="$YELLOW"
            ;;
        "SKIP")
            icon="⏭️"
            color="$CYAN"
            ;;
        *)
            icon="ℹ️"
            color="$BLUE"
            ;;
    esac
    
    echo -e "$icon ${color}[$status]${NC} $message" | tee -a "$LOG_FILE"
}

# Print script header
print_header() {
    cat << EOF
==================================================================
🔍 Comprehensive Homebrew Installation Validation for usbipd-mac
==================================================================
Package: $PACKAGE_NAME
Homebrew Prefix: ${HOMEBREW_PREFIX:-'[auto-detect]'}
Skip Service Tests: $([ "$SKIP_SERVICE_TESTS" = true ] && echo "YES" || echo "NO")
Skip System Extension Tests: $([ "$SKIP_SYSEXT_TESTS" = true ] && echo "YES" || echo "NO")
Skip Network Tests: $([ "$SKIP_NETWORK_TESTS" = true ] && echo "YES" || echo "NO")
Verbose: $([ "$VERBOSE" = true ] && echo "YES" || echo "NO")
Dry Run: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")
Quick Check: $([ "$QUICK_CHECK" = true ] && echo "YES" || echo "NO")
Interactive: $([ "$INTERACTIVE" = true ] && echo "YES" || echo "NO")
Generate Report: $([ "$GENERATE_REPORT" = true ] && echo "YES" || echo "NO")
Validation Dir: $VALIDATION_DIR
Log File: $LOG_FILE
==================================================================

EOF
}

# Print usage information
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Comprehensive validation script for Homebrew installation of usbipd-mac.
Validates binary functionality, service configuration, and System Extension status.

OPTIONS:
    --homebrew-prefix PATH   Homebrew installation prefix (auto-detected if not specified)
    --package-name NAME      Package name to validate (default: usbipd-mac)
    --skip-service-tests     Skip service management validation
    --skip-sysext-tests      Skip System Extension validation
    --skip-network-tests     Skip network connectivity tests
    --quick-check           Perform only essential validations
    --non-interactive       Run without user prompts
    --no-report             Skip generating validation report
    -v, --verbose           Enable verbose logging
    -d, --dry-run           Show what would be validated without running tests
    -h, --help              Show this help message

EXAMPLES:
    $0                                      # Full validation with auto-detection
    $0 --quick-check                        # Essential validations only
    $0 --skip-service-tests --verbose       # Skip service tests with verbose output
    $0 --homebrew-prefix /opt/homebrew      # Specify custom Homebrew prefix
    $0 --non-interactive --no-report        # Automated validation without report

ENVIRONMENT VARIABLES:
    HOMEBREW_PREFIX                         Override Homebrew prefix detection
    USBIPD_VALIDATION_SKIP_SERVICES        Skip service validation (true/false)
    USBIPD_VALIDATION_SKIP_SYSEXT          Skip System Extension validation (true/false)
    USBIPD_VALIDATION_TIMEOUT              Validation timeout in seconds (default: 30)

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --homebrew-prefix)
                HOMEBREW_PREFIX="$2"
                shift 2
                ;;
            --package-name)
                PACKAGE_NAME="$2"
                shift 2
                ;;
            --skip-service-tests)
                SKIP_SERVICE_TESTS=true
                shift
                ;;
            --skip-sysext-tests)
                SKIP_SYSEXT_TESTS=true
                shift
                ;;
            --skip-network-tests)
                SKIP_NETWORK_TESTS=true
                shift
                ;;
            --quick-check)
                QUICK_CHECK=true
                shift
                ;;
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            --no-report)
                GENERATE_REPORT=false
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                print_usage
                exit $EXIT_SUCCESS
                ;;
            -*)
                log_error "Unknown option: $1"
                print_usage
                exit $EXIT_USAGE_ERROR
                ;;
            *)
                log_error "Unexpected argument: $1"
                print_usage
                exit $EXIT_USAGE_ERROR
                ;;
        esac
    done

    # Apply environment variable overrides
    HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-$HOMEBREW_PREFIX}"
    
    if [ "${USBIPD_VALIDATION_SKIP_SERVICES:-false}" = "true" ]; then
        SKIP_SERVICE_TESTS=true
    fi
    
    if [ "${USBIPD_VALIDATION_SKIP_SYSEXT:-false}" = "true" ]; then
        SKIP_SYSEXT_TESTS=true
    fi
}

# Initialize validation environment
initialize_environment() {
    log_step "Initializing validation environment"

    # Create validation directory
    mkdir -p "$VALIDATION_DIR"
    log_debug "Created validation directory: $VALIDATION_DIR"

    # Initialize log file
    echo "=== Installation Validation Log Started at $(date) ===" > "$LOG_FILE"

    # Detect Homebrew prefix if not specified
    if [ -z "$HOMEBREW_PREFIX" ]; then
        HOMEBREW_PREFIX=$(detect_homebrew_prefix)
        log_debug "Auto-detected Homebrew prefix: $HOMEBREW_PREFIX"
    fi

    # Validate Homebrew installation
    if [ ! -x "$HOMEBREW_PREFIX/bin/brew" ]; then
        log_error "Homebrew not found at: $HOMEBREW_PREFIX/bin/brew"
        exit $EXIT_VALIDATION_FAILED
    fi

    log_info "Environment initialized successfully"
}

# Detect Homebrew prefix
detect_homebrew_prefix() {
    # Try common Homebrew prefixes
    local common_prefixes=(
        "/opt/homebrew"      # Apple Silicon default
        "/usr/local"         # Intel Mac default
        "/home/linuxbrew/.linuxbrew"  # Linux
    )
    
    for prefix in "${common_prefixes[@]}"; do
        if [ -x "$prefix/bin/brew" ]; then
            echo "$prefix"
            return
        fi
    done
    
    # Try to detect from PATH
    local brew_path
    if command -v brew >/dev/null 2>&1; then
        brew_path=$(command -v brew)
        # Extract prefix (e.g., /opt/homebrew/bin/brew -> /opt/homebrew)
        echo "${brew_path%/bin/brew}"
        return
    fi
    
    # Default fallback
    echo "/opt/homebrew"
}

# Validate Homebrew package installation
validate_package_installation() {
    log_step "Validating Homebrew package installation"

    # Check if package is installed
    if [ "$DRY_RUN" = false ]; then
        if "$HOMEBREW_PREFIX/bin/brew" list "$PACKAGE_NAME" >/dev/null 2>&1; then
            log_result "PASS" "Package $PACKAGE_NAME is installed via Homebrew"
            
            # Get package information
            local package_info
            package_info=$("$HOMEBREW_PREFIX/bin/brew" info "$PACKAGE_NAME" --json)
            local installed_version
            installed_version=$(echo "$package_info" | grep -o '"versions":{"stable":"[^"]*"' | cut -d'"' -f6)
            log_info "Installed version: ${installed_version:-'unknown'}"
        else
            log_result "FAIL" "Package $PACKAGE_NAME is not installed via Homebrew"
            return $EXIT_VALIDATION_FAILED
        fi
    else
        log_result "SKIP" "[DRY RUN] Would check package installation"
    fi

    return $EXIT_SUCCESS
}

# Validate binary installation and functionality
validate_binary_functionality() {
    log_step "Validating binary installation and functionality"

    local binary_path="$HOMEBREW_PREFIX/bin/usbipd"
    local validation_failed=false

    # Test 1: Check binary exists
    if [ -f "$binary_path" ]; then
        log_result "PASS" "Binary exists at $binary_path"
    else
        log_result "FAIL" "Binary not found at $binary_path"
        return $EXIT_BINARY_NOT_FOUND
    fi

    # Test 2: Check binary permissions
    if [ -x "$binary_path" ]; then
        log_result "PASS" "Binary has execute permissions"
    else
        log_result "FAIL" "Binary is not executable"
        validation_failed=true
    fi

    # Test 3: Check binary size (sanity check)
    local binary_size
    binary_size=$(wc -c < "$binary_path")
    if [ "$binary_size" -gt 100000 ]; then  # At least 100KB
        log_result "PASS" "Binary size is reasonable ($binary_size bytes)"
    else
        log_result "WARN" "Binary size seems unusually small ($binary_size bytes)"
    fi

    # Test 4: Test binary functionality
    if [ "$DRY_RUN" = false ]; then
        # Test --version flag
        if "$binary_path" --version >/dev/null 2>&1; then
            log_result "PASS" "Binary responds to --version"
        else
            log_result "FAIL" "Binary does not respond to --version"
            validation_failed=true
        fi

        # Test --help flag
        if "$binary_path" --help >/dev/null 2>&1; then
            log_result "PASS" "Binary responds to --help"
        else
            log_result "WARN" "Binary does not respond to --help (may be expected)"
        fi

        # Test basic command parsing
        if "$binary_path" --invalid-flag 2>&1 | grep -q "error\|invalid\|unknown"; then
            log_result "PASS" "Binary properly handles invalid arguments"
        else
            log_result "WARN" "Binary argument handling unclear"
        fi
    else
        log_result "SKIP" "[DRY RUN] Would test binary functionality"
    fi

    # Test 5: Check code signing (macOS)
    if command -v codesign >/dev/null 2>&1; then
        if [ "$DRY_RUN" = false ]; then
            if codesign --verify --verbose "$binary_path" >/dev/null 2>&1; then
                log_result "PASS" "Binary is properly code signed"
            else
                log_result "WARN" "Binary is not code signed (may be expected for local builds)"
            fi
        else
            log_result "SKIP" "[DRY RUN] Would check code signing"
        fi
    fi

    if [ "$validation_failed" = true ]; then
        return $EXIT_BINARY_NOT_FOUND
    fi

    return $EXIT_SUCCESS
}

# Validate service configuration
validate_service_configuration() {
    if [ "$SKIP_SERVICE_TESTS" = true ]; then
        log_result "SKIP" "Service validation skipped (--skip-service-tests)"
        return $EXIT_SUCCESS
    fi

    log_step "Validating service configuration"

    local validation_failed=false

    # Test 1: Check if service is available
    if [ "$DRY_RUN" = false ]; then
        if "$HOMEBREW_PREFIX/bin/brew" services list | grep -q "$PACKAGE_NAME"; then
            log_result "PASS" "Service is available in Homebrew services"
            
            # Get service status
            local service_status
            service_status=$("$HOMEBREW_PREFIX/bin/brew" services list | grep "$PACKAGE_NAME" | awk '{print $2}')
            log_info "Service status: ${service_status:-'unknown'}"
        else
            log_result "FAIL" "Service not found in Homebrew services"
            validation_failed=true
        fi
    else
        log_result "SKIP" "[DRY RUN] Would check service availability"
    fi

    # Test 2: Check launchd plist file
    local plist_path="$HOMEBREW_PREFIX/Library/LaunchDaemons/homebrew.mxcl.$PACKAGE_NAME.plist"
    if [ -f "$plist_path" ]; then
        log_result "PASS" "LaunchDaemon plist exists"
        
        # Validate plist content
        if [ "$DRY_RUN" = false ]; then
            if plutil -lint "$plist_path" >/dev/null 2>&1; then
                log_result "PASS" "LaunchDaemon plist is valid XML"
            else
                log_result "FAIL" "LaunchDaemon plist is invalid"
                validation_failed=true
            fi
        fi
    else
        log_result "WARN" "LaunchDaemon plist not found (service may not be installed)"
    fi

    # Test 3: Test service management commands (if interactive)
    if [ "$INTERACTIVE" = true ] && [ "$DRY_RUN" = false ] && [ "$QUICK_CHECK" = false ]; then
        echo ""
        read -p "Test service start/stop functionality? (y/N): " -n 1 -r
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Testing service management functionality"
            
            # Try to start service
            if "$HOMEBREW_PREFIX/bin/brew" services start "$PACKAGE_NAME" >/dev/null 2>&1; then
                log_result "PASS" "Service can be started"
                
                # Wait a moment for service to initialize
                sleep 2
                
                # Check if service is running
                if "$HOMEBREW_PREFIX/bin/brew" services list | grep "$PACKAGE_NAME" | grep -q "started"; then
                    log_result "PASS" "Service is running after start"
                else
                    log_result "WARN" "Service may not be running properly"
                fi
                
                # Stop service
                if "$HOMEBREW_PREFIX/bin/brew" services stop "$PACKAGE_NAME" >/dev/null 2>&1; then
                    log_result "PASS" "Service can be stopped"
                else
                    log_result "WARN" "Service stop may have failed"
                fi
            else
                log_result "FAIL" "Service cannot be started"
                validation_failed=true
            fi
        else
            log_result "SKIP" "Service functionality test skipped by user"
        fi
    else
        log_result "SKIP" "Service functionality test skipped (non-interactive or dry-run)"
    fi

    if [ "$validation_failed" = true ]; then
        return $EXIT_SERVICE_FAILED
    fi

    return $EXIT_SUCCESS
}

# Validate System Extension status
validate_system_extension() {
    if [ "$SKIP_SYSEXT_TESTS" = true ]; then
        log_result "SKIP" "System Extension validation skipped (--skip-sysext-tests)"
        return $EXIT_SUCCESS
    fi

    log_step "Validating System Extension status"

    # Test 1: Check if System Extensions framework is available
    if command -v systemextensionsctl >/dev/null 2>&1; then
        log_result "PASS" "systemextensionsctl is available"
    else
        log_result "WARN" "systemextensionsctl not available (older macOS version?)"
        return $EXIT_SUCCESS
    fi

    if [ "$DRY_RUN" = false ]; then
        # Test 2: List System Extensions
        local sysext_list
        if sysext_list=$(systemextensionsctl list 2>/dev/null); then
            log_result "PASS" "Can query System Extensions"
            
            # Check if usbipd-mac extension is listed
            if echo "$sysext_list" | grep -q "usbipd-mac\|com\..*\.usbipd"; then
                log_result "PASS" "usbipd-mac System Extension found"
                log_debug "System Extension details:"
                echo "$sysext_list" | grep -A 2 -B 2 "usbipd-mac\|com\..*\.usbipd" | while read -r line; do
                    log_debug "  $line"
                done
            else
                log_result "WARN" "usbipd-mac System Extension not found (may need manual activation)"
            fi
        else
            log_result "WARN" "Cannot query System Extensions (permission denied?)"
        fi

        # Test 3: Check System Integrity Protection status
        if command -v csrutil >/dev/null 2>&1; then
            local sip_status
            if sip_status=$(csrutil status 2>/dev/null); then
                if echo "$sip_status" | grep -q "enabled"; then
                    log_result "PASS" "System Integrity Protection is enabled"
                    log_info "SIP status: $sip_status"
                else
                    log_result "WARN" "System Integrity Protection status: $sip_status"
                fi
            else
                log_result "WARN" "Cannot check SIP status (permission denied?)"
            fi
        fi
    else
        log_result "SKIP" "[DRY RUN] Would check System Extension status"
    fi

    return $EXIT_SUCCESS
}

# Validate network functionality
validate_network_functionality() {
    if [ "$SKIP_NETWORK_TESTS" = true ]; then
        log_result "SKIP" "Network validation skipped (--skip-network-tests)"
        return $EXIT_SUCCESS
    fi

    log_step "Validating network functionality"

    local binary_path="$HOMEBREW_PREFIX/bin/usbipd"

    if [ "$DRY_RUN" = false ]; then
        # Test 1: Check if default port is available
        local default_port=3240
        if ! lsof -i ":$default_port" >/dev/null 2>&1; then
            log_result "PASS" "Default port $default_port is available"
        else
            log_result "WARN" "Default port $default_port is in use"
            log_info "Process using port $default_port:"
            lsof -i ":$default_port" | head -5 | while read -r line; do
                log_debug "  $line"
            done
        fi

        # Test 2: Test network interface detection
        local network_interfaces
        if network_interfaces=$(ifconfig | grep -E "^[a-z]" | cut -d: -f1); then
            log_result "PASS" "Network interfaces detected"
            log_debug "Available interfaces: $(echo "$network_interfaces" | tr '\n' ' ')"
        else
            log_result "WARN" "Cannot detect network interfaces"
        fi

        # Test 3: Basic connectivity test (if not in quick mode)
        if [ "$QUICK_CHECK" = false ]; then
            if ping -c 1 -t 5 localhost >/dev/null 2>&1; then
                log_result "PASS" "Local network connectivity works"
            else
                log_result "WARN" "Local network connectivity test failed"
            fi
        fi
    else
        log_result "SKIP" "[DRY RUN] Would test network functionality"
    fi

    return $EXIT_SUCCESS
}

# Validate permissions and security
validate_permissions_security() {
    log_step "Validating permissions and security"

    local binary_path="$HOMEBREW_PREFIX/bin/usbipd"
    local validation_failed=false

    # Test 1: Check binary ownership
    if [ -f "$binary_path" ]; then
        local binary_owner
        binary_owner=$(stat -f "%Su" "$binary_path" 2>/dev/null || stat -c "%U" "$binary_path" 2>/dev/null || echo "unknown")
        
        if [ "$binary_owner" = "root" ] || [ "$binary_owner" = "$(whoami)" ]; then
            log_result "PASS" "Binary ownership is appropriate ($binary_owner)"
        else
            log_result "WARN" "Binary owner is unusual: $binary_owner"
        fi
    fi

    # Test 2: Check if running as root is possible (for System Extension)
    if [ "$(id -u)" -eq 0 ]; then
        log_result "PASS" "Running with root privileges (required for System Extension)"
    else
        log_result "WARN" "Not running as root (System Extension functionality may be limited)"
        log_info "Note: Some usbipd-mac features require root privileges"
    fi

    # Test 3: Check Full Disk Access (if available)
    if [ "$DRY_RUN" = false ] && [ "$QUICK_CHECK" = false ]; then
        # Try to access a restricted location to test Full Disk Access
        if [ -r "/Library/Application Support" ] 2>/dev/null; then
            log_result "PASS" "Full Disk Access appears to be granted"
        else
            log_result "WARN" "Full Disk Access may not be granted (some features may not work)"
        fi
    fi

    return $EXIT_SUCCESS
}

# Generate comprehensive validation report
generate_validation_report() {
    if [ "$GENERATE_REPORT" = false ]; then
        log_debug "Report generation skipped (--no-report)"
        return
    fi

    log_step "Generating validation report"

    local report_file="$VALIDATION_DIR/validation-report-$(date +%Y%m%d-%H%M%S).html"

    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>usbipd-mac Homebrew Installation Validation Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .section { margin: 20px 0; }
        .pass { color: green; }
        .fail { color: red; }
        .warn { color: orange; }
        .skip { color: blue; }
        .log { background-color: #f9f9f9; padding: 10px; font-family: monospace; white-space: pre-wrap; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔍 usbipd-mac Homebrew Installation Validation Report</h1>
        <p><strong>Generated:</strong> $(date)</p>
        <p><strong>Package:</strong> $PACKAGE_NAME</p>
        <p><strong>Homebrew Prefix:</strong> $HOMEBREW_PREFIX</p>
        <p><strong>Validation Directory:</strong> $VALIDATION_DIR</p>
    </div>

    <div class="section">
        <h2>System Information</h2>
        <table>
            <tr><th>Property</th><th>Value</th></tr>
            <tr><td>macOS Version</td><td>$(sw_vers -productVersion 2>/dev/null || echo "Unknown")</td></tr>
            <tr><td>Hardware</td><td>$(system_profiler SPHardwareDataType | grep "Model Name" | cut -d: -f2 | xargs 2>/dev/null || echo "Unknown")</td></tr>
            <tr><td>Architecture</td><td>$(uname -m)</td></tr>
            <tr><td>Homebrew Version</td><td>$("$HOMEBREW_PREFIX/bin/brew" --version | head -1 2>/dev/null || echo "Unknown")</td></tr>
            <tr><td>User</td><td>$(whoami)</td></tr>
            <tr><td>UID</td><td>$(id -u)</td></tr>
        </table>
    </div>

    <div class="section">
        <h2>Validation Log</h2>
        <div class="log">$(cat "$LOG_FILE" | sed 's/\x1b\[[0-9;]*m//g')</div>
    </div>

    <div class="section">
        <h2>Recommendations</h2>
        <ul>
EOF

    # Add recommendations based on validation results
    if grep -q "FAIL" "$LOG_FILE"; then
        echo "            <li class=\"fail\">❌ Some validation tests failed. Review the log above for details.</li>" >> "$report_file"
    fi
    
    if grep -q "System Extension not found" "$LOG_FILE"; then
        echo "            <li class=\"warn\">⚠️ System Extension may need manual activation in System Preferences → Security & Privacy.</li>" >> "$report_file"
    fi
    
    if grep -q "Not running as root" "$LOG_FILE"; then
        echo "            <li class=\"warn\">⚠️ Some features require root privileges. Consider running with sudo for full functionality.</li>" >> "$report_file"
    fi
    
    if grep -q "Full Disk Access may not be granted" "$LOG_FILE"; then
        echo "            <li class=\"warn\">⚠️ Grant Full Disk Access to usbipd in System Preferences → Security & Privacy → Privacy for full functionality.</li>" >> "$report_file"
    fi

    cat >> "$report_file" << EOF
            <li class="pass">✅ Refer to the project documentation for troubleshooting guidance.</li>
            <li class="pass">✅ Report issues at the project's GitHub repository if problems persist.</li>
        </ul>
    </div>

    <div class="section">
        <h2>Log File Location</h2>
        <p>Full validation log: <code>$LOG_FILE</code></p>
    </div>
</body>
</html>
EOF

    log_success "Validation report generated: $report_file"
    
    if [ "$INTERACTIVE" = true ] && command -v open >/dev/null 2>&1; then
        read -p "Open validation report in browser? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            open "$report_file"
        fi
    fi
}

# Main validation orchestrator
run_validation() {
    log_step "Starting comprehensive Homebrew installation validation"

    local overall_result=$EXIT_SUCCESS

    # Core validations
    if ! validate_package_installation; then
        overall_result=$EXIT_VALIDATION_FAILED
    fi

    if ! validate_binary_functionality; then
        overall_result=$EXIT_VALIDATION_FAILED
    fi

    # Optional validations based on configuration
    if ! validate_service_configuration; then
        overall_result=$EXIT_VALIDATION_FAILED
    fi

    if ! validate_system_extension; then
        overall_result=$EXIT_VALIDATION_FAILED
    fi

    if ! validate_network_functionality; then
        overall_result=$EXIT_VALIDATION_FAILED
    fi

    if ! validate_permissions_security; then
        overall_result=$EXIT_VALIDATION_FAILED
    fi

    return $overall_result
}

# Main execution function
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Print header
    print_header
    
    # Initialize environment
    initialize_environment
    
    # Run validation
    if run_validation; then
        log_success "🎉 All validations completed successfully"
        final_result=$EXIT_SUCCESS
    else
        log_error "❌ Some validations failed"
        final_result=$EXIT_VALIDATION_FAILED
    fi
    
    # Generate report
    generate_validation_report
    
    # Final summary
    echo ""
    log_step "Validation Summary"
    
    local pass_count fail_count warn_count skip_count
    pass_count=$(grep -c "✅ \[PASS\]" "$LOG_FILE" || echo "0")
    fail_count=$(grep -c "❌ \[FAIL\]" "$LOG_FILE" || echo "0")
    warn_count=$(grep -c "⚠️ \[WARN\]" "$LOG_FILE" || echo "0")
    skip_count=$(grep -c "⏭️ \[SKIP\]" "$LOG_FILE" || echo "0")
    
    echo "  • Passed: $pass_count"
    echo "  • Failed: $fail_count"
    echo "  • Warnings: $warn_count"
    echo "  • Skipped: $skip_count"
    echo ""
    
    if [ "$final_result" -eq $EXIT_SUCCESS ]; then
        echo -e "${GREEN}${BOLD}✅ Homebrew installation validation completed successfully!${NC}"
    else
        echo -e "${RED}${BOLD}❌ Homebrew installation validation completed with issues.${NC}"
        echo -e "${YELLOW}Check the log file for details: $LOG_FILE${NC}"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        echo ""
        echo -e "${BOLD}${CYAN}This was a dry run. No actual tests were performed.${NC}"
    fi
    
    exit $final_result
}

# Error handling
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Execute main function with all arguments
main "$@"