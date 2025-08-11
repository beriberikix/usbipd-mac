#!/bin/bash

# extension-status.sh
# System Extension status reporting script for usbipd-mac
# Provides comprehensive System Extension information with formatted output

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUNDLE_ID="com.example.usbipd-mac.SystemExtension"

# Default options
VERBOSE=false
JSON_OUTPUT=false
WATCH_MODE=false
SHOW_LOGS=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    if [[ $JSON_OUTPUT == false ]]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

log_success() {
    if [[ $JSON_OUTPUT == false ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    fi
}

log_warning() {
    if [[ $JSON_OUTPUT == false ]]; then
        echo -e "${YELLOW}[WARNING]${NC} $1"
    fi
}

log_error() {
    if [[ $JSON_OUTPUT == false ]]; then
        echo -e "${RED}[ERROR]${NC} $1"
    fi
}

# Check if running on macOS
check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is designed for macOS only."
        exit 1
    fi
}

# Get System Extension status
get_extension_status() {
    local extension_info
    extension_info=$(systemextensionsctl list | grep "$BUNDLE_ID" 2>/dev/null || true)
    
    if [[ -n "$extension_info" ]]; then
        echo "$extension_info"
        return 0
    else
        return 1
    fi
}

# Parse extension status into components
parse_extension_status() {
    local status_line="$1"
    
    # Extract components from systemextensionsctl output
    # Format: [state] bundle-id (version) team-id
    local state=$(echo "$status_line" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')
    local bundle_id=$(echo "$status_line" | awk '{print $2}')
    local version=$(echo "$status_line" | sed -n 's/.* (\([^)]*\)) .*/\1/p')
    local team_id=$(echo "$status_line" | awk '{print $NF}')
    
    echo "STATE=$state"
    echo "BUNDLE_ID=$bundle_id"  
    echo "VERSION=$version"
    echo "TEAM_ID=$team_id"
}

# Display detailed status information
show_detailed_status() {
    if [[ $JSON_OUTPUT == false ]]; then
        echo -e "${BOLD}System Extension Status Report${NC}"
        echo "=============================="
        echo
    fi
    
    local extension_status
    if extension_status=$(get_extension_status); then
        if [[ $JSON_OUTPUT == true ]]; then
            # Parse status for JSON output
            local parsed_status
            parsed_status=$(parse_extension_status "$extension_status")
            
            local state version team_id
            eval "$parsed_status"
            
            cat << EOF
{
  "bundle_id": "$BUNDLE_ID",
  "status": "found",
  "state": "$state",
  "version": "$version",
  "team_id": "$team_id",
  "raw_output": "$extension_status"
}
EOF
        else
            echo -e "${GREEN}✓ System Extension Found${NC}"
            echo "Bundle ID: $BUNDLE_ID"
            echo "Status: $extension_status"
            echo
            
            # Analyze status
            if echo "$extension_status" | grep -q "\[activated enabled\]"; then
                echo -e "${GREEN}✓ Status: ACTIVE AND ENABLED${NC}"
                echo "The System Extension is running and operational."
            elif echo "$extension_status" | grep -q "\[awaiting user approval\]"; then
                echo -e "${YELLOW}⚠ Status: AWAITING USER APPROVAL${NC}"
                echo "Action required: Go to System Preferences > Privacy & Security"
                echo "Look for a security notification and click 'Allow' to enable the extension."
            elif echo "$extension_status" | grep -q "\[terminated\]"; then
                echo -e "${RED}✗ Status: TERMINATED${NC}"
                echo "The System Extension was terminated. This may indicate an error."
            else
                echo -e "${YELLOW}⚠ Status: UNKNOWN STATE${NC}"
                echo "The extension is in an unrecognized state."
            fi
        fi
    else
        if [[ $JSON_OUTPUT == true ]]; then
            cat << EOF
{
  "bundle_id": "$BUNDLE_ID",
  "status": "not_found",
  "message": "System Extension not installed or not found"
}
EOF
        else
            echo -e "${RED}✗ System Extension Not Found${NC}"
            echo "Bundle ID: $BUNDLE_ID"
            echo "The System Extension is not installed or not found in system registry."
            echo
            echo "To install:"
            echo "  ./Scripts/install-extension.sh"
        fi
    fi
}

# List all System Extensions
list_all_extensions() {
    if [[ $JSON_OUTPUT == false ]]; then
        echo -e "${BOLD}All System Extensions${NC}"
        echo "===================="
        echo
    fi
    
    local all_extensions
    all_extensions=$(systemextensionsctl list 2>/dev/null)
    
    if [[ $JSON_OUTPUT == true ]]; then
        echo '{"all_extensions":'
        echo '"'$(echo "$all_extensions" | sed 's/"/\\"/g' | tr '\n' '\\' | sed 's/\\/\\n/g')'"'
        echo '}'
    else
        echo "$all_extensions"
    fi
}

# Show system information
show_system_info() {
    if [[ $JSON_OUTPUT == false ]]; then
        echo -e "${BOLD}System Information${NC}"
        echo "=================="
        echo
    fi
    
    local macos_version
    macos_version=$(sw_vers -productVersion)
    
    local sip_status
    sip_status=$(csrutil status 2>/dev/null || echo "Unknown")
    
    local dev_mode_status="Unknown"
    if spctl --status 2>/dev/null | grep -q "assessments disabled"; then
        dev_mode_status="Enabled (assessments disabled)"
    elif spctl --status 2>/dev/null | grep -q "assessments enabled"; then
        dev_mode_status="Disabled (assessments enabled)"
    fi
    
    if [[ $JSON_OUTPUT == true ]]; then
        cat << EOF
{
  "system_info": {
    "macos_version": "$macos_version",
    "sip_status": "$sip_status",
    "developer_mode": "$dev_mode_status"
  }
}
EOF
    else
        echo "macOS Version: $macos_version"
        echo "SIP Status: $sip_status"
        echo "Developer Mode: $dev_mode_status"
        echo
        
        # Recommendations
        if echo "$sip_status" | grep -q "enabled"; then
            log_warning "SIP is enabled - this may prevent System Extension development"
        fi
        
        if [[ "$dev_mode_status" != *"disabled"* ]]; then
            log_info "Developer mode appears to be enabled"
        fi
    fi
}

# Show recent System Extension logs
show_extension_logs() {
    if [[ $JSON_OUTPUT == false ]]; then
        echo -e "${BOLD}Recent System Extension Logs${NC}"
        echo "============================"
        echo
    fi
    
    # Show logs from the last hour related to System Extensions
    local logs
    logs=$(log show --last 1h --predicate 'category == "systemextensions" OR subsystem == "com.apple.systemextensions"' --style compact 2>/dev/null | tail -20 || true)
    
    if [[ $JSON_OUTPUT == true ]]; then
        echo '{"recent_logs":'
        echo '"'$(echo "$logs" | sed 's/"/\\"/g' | tr '\n' '\\' | sed 's/\\/\\n/g')'"'
        echo '}'
    else
        if [[ -n "$logs" ]]; then
            echo "$logs"
        else
            echo "No recent System Extension logs found."
        fi
        echo
    fi
}

# Watch extension status
watch_status() {
    if [[ $JSON_OUTPUT == true ]]; then
        log_error "Watch mode not compatible with JSON output"
        exit 1
    fi
    
    log_info "Watching System Extension status (press Ctrl+C to stop)..."
    echo
    
    local previous_status=""
    
    while true; do
        clear
        echo -e "${CYAN}$(date)${NC}"
        echo
        
        local current_status
        current_status=$(get_extension_status 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "$current_status" != "$previous_status" ]]; then
            if [[ "$current_status" != "NOT_FOUND" ]]; then
                log_success "Status changed: $current_status"
            else
                log_warning "Extension not found"
            fi
            previous_status="$current_status"
        fi
        
        show_detailed_status
        
        sleep 5
    done
}

# Health check
perform_health_check() {
    if [[ $JSON_OUTPUT == false ]]; then
        echo -e "${BOLD}System Extension Health Check${NC}"
        echo "============================="
        echo
    fi
    
    local health_status="healthy"
    local issues=()
    
    # Check if extension is installed
    if ! get_extension_status >/dev/null 2>&1; then
        health_status="unhealthy"
        issues+=("Extension not installed")
    fi
    
    # Check SIP status
    local sip_status
    sip_status=$(csrutil status 2>/dev/null || echo "unknown")
    if echo "$sip_status" | grep -q "enabled"; then
        issues+=("SIP enabled (may prevent development)")
    fi
    
    # Check for bundle existence
    local bundle_path="$PROJECT_ROOT/.build/USBIPDSystemExtension.systemextension"
    if [[ ! -d "$bundle_path" ]]; then
        issues+=("Bundle not found at $bundle_path")
    fi
    
    if [[ $JSON_OUTPUT == true ]]; then
        local issues_json
        issues_json=$(printf '%s\n' "${issues[@]}" | jq -R . | jq -s .)
        cat << EOF
{
  "health_check": {
    "status": "$health_status",
    "issues": $issues_json,
    "recommendations": []
  }
}
EOF
    else
        if [[ $health_status == "healthy" ]]; then
            log_success "System Extension appears healthy"
        else
            log_warning "Found ${#issues[@]} potential issues:"
            for issue in "${issues[@]}"; do
                echo "  - $issue"
            done
        fi
    fi
}

# Show help
show_help() {
    cat << EOF
Usage: $0 [options]

Options:
    -h, --help          Show this help message
    -v, --verbose       Verbose output with additional details
    -j, --json          Output in JSON format
    -w, --watch         Watch mode (monitor status changes)
    -l, --logs          Show recent System Extension logs
    -a, --all           Show all System Extensions (not just usbipd-mac)
    -s, --system        Show system information
    -c, --health        Perform health check
    -b, --bundle-id ID  Specify bundle identifier to check

This script provides comprehensive System Extension status information and monitoring.

Examples:
    $0                  Show basic extension status
    $0 --verbose        Show detailed status information
    $0 --watch          Monitor status changes in real-time
    $0 --json           Output status in JSON format
    $0 --health         Perform comprehensive health check
EOF
}

# Main function
main() {
    local show_all=false
    local show_system=false
    local health_check=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -j|--json)
                JSON_OUTPUT=true
                shift
                ;;
            -w|--watch)
                WATCH_MODE=true
                shift
                ;;
            -l|--logs)
                SHOW_LOGS=true
                shift
                ;;
            -a|--all)
                show_all=true
                shift
                ;;
            -s|--system)
                show_system=true
                shift
                ;;
            -c|--health)
                health_check=true
                shift
                ;;
            -b|--bundle-id)
                BUNDLE_ID="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    check_macos
    
    if [[ $WATCH_MODE == true ]]; then
        watch_status
        exit 0
    fi
    
    if [[ $JSON_OUTPUT == true ]]; then
        echo "{"
    fi
    
    # Show different views based on options
    if [[ $show_all == true ]]; then
        list_all_extensions
    elif [[ $show_system == true ]]; then
        show_system_info
    elif [[ $health_check == true ]]; then
        perform_health_check
    else
        show_detailed_status
        
        if [[ $VERBOSE == true && $JSON_OUTPUT == false ]]; then
            echo
            show_system_info
        fi
    fi
    
    if [[ $SHOW_LOGS == true ]]; then
        if [[ $JSON_OUTPUT == false ]]; then
            echo
        fi
        show_extension_logs
    fi
    
    if [[ $JSON_OUTPUT == true ]]; then
        echo "}"
    fi
}

# Run main function with all arguments
main "$@"