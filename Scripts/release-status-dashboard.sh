#!/bin/bash

# release-status-dashboard.sh
# Release workflow status dashboard for usbipd-mac
# Provides status reporting and progress tracking for release workflows
# Integrates with GitHub API for real-time monitoring and troubleshooting assistance

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly BUILD_DIR="$PROJECT_ROOT/.build"
readonly DASHBOARD_DIR="$BUILD_DIR/dashboard"

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Dashboard configuration
DASHBOARD_MODE="status"
REFRESH_INTERVAL=30
AUTO_REFRESH=false
OUTPUT_FORMAT="terminal"
GITHUB_REPO=""
GITHUB_OWNER=""
VERBOSE=false
SHOW_LOGS=false
FILTER_WORKFLOW=""
MAX_RUNS=10

# GitHub API configuration
GITHUB_API_BASE="https://api.github.com"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Status tracking
declare -A WORKFLOW_STATUS
declare -A WORKFLOW_TIMES
declare -A WORKFLOW_ARTIFACTS

# ============================================================================
# LOGGING AND OUTPUT FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1" >&2
    fi
}

log_header() {
    echo -e "${BOLD}${CYAN}$1${NC}" >&2
}

print_separator() {
    echo -e "${CYAN}$(printf '=%.0s' {1..80})${NC}" >&2
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Get current timestamp
get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Get ISO timestamp
get_iso_timestamp() {
    date -u "+%Y-%m-%dT%H:%M:%S.%3NZ"
}

# Format duration
format_duration() {
    local seconds="$1"
    
    if [[ $seconds -lt 60 ]]; then
        echo "${seconds}s"
    elif [[ $seconds -lt 3600 ]]; then
        local minutes=$((seconds / 60))
        local remaining_seconds=$((seconds % 60))
        echo "${minutes}m ${remaining_seconds}s"
    else
        local hours=$((seconds / 3600))
        local remaining_minutes=$(((seconds % 3600) / 60))
        echo "${hours}h ${remaining_minutes}m"
    fi
}

# Ensure dashboard directory exists
ensure_dashboard_directory() {
    if [[ ! -d "$DASHBOARD_DIR" ]]; then
        mkdir -p "$DASHBOARD_DIR"
        log_debug "Created dashboard directory: $DASHBOARD_DIR"
    fi
}

# Detect GitHub repository information
detect_github_repo() {
    if [[ -n "$GITHUB_REPO" && -n "$GITHUB_OWNER" ]]; then
        return 0
    fi
    
    # Try to get from git remote
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    
    if [[ -n "$remote_url" ]]; then
        if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/\.]+) ]]; then
            GITHUB_OWNER="${BASH_REMATCH[1]}"
            GITHUB_REPO="${BASH_REMATCH[2]}"
            log_debug "Detected GitHub repo: $GITHUB_OWNER/$GITHUB_REPO"
        fi
    fi
    
    # Fallback to environment or config
    GITHUB_OWNER="${GITHUB_OWNER:-${GITHUB_REPOSITORY_OWNER:-}}"
    GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-}}"
    
    if [[ -z "$GITHUB_OWNER" || -z "$GITHUB_REPO" ]]; then
        log_error "Could not detect GitHub repository. Please set GITHUB_OWNER and GITHUB_REPO."
        return 1
    fi
}

# ============================================================================
# GITHUB API FUNCTIONS
# ============================================================================

# Make GitHub API request
github_api_request() {
    local endpoint="$1"
    local method="${2:-GET}"
    local data="${3:-}"
    
    local curl_args=(-s -X "$method")
    
    if [[ -n "$GITHUB_TOKEN" ]]; then
        curl_args+=(-H "Authorization: token $GITHUB_TOKEN")
    fi
    
    curl_args+=(-H "Accept: application/vnd.github.v3+json")
    
    if [[ -n "$data" ]]; then
        curl_args+=(-H "Content-Type: application/json" -d "$data")
    fi
    
    curl_args+=("$GITHUB_API_BASE/$endpoint")
    
    log_debug "GitHub API request: $method $endpoint"
    curl "${curl_args[@]}"
}

# Get workflow runs
get_workflow_runs() {
    local workflow_filter="${1:-}"
    local per_page="${2:-$MAX_RUNS}"
    
    local endpoint="repos/$GITHUB_OWNER/$GITHUB_REPO/actions/runs?per_page=$per_page"
    
    if [[ -n "$workflow_filter" ]]; then
        endpoint="$endpoint&workflow=$workflow_filter"
    fi
    
    github_api_request "$endpoint"
}

# Get specific workflow run
get_workflow_run() {
    local run_id="$1"
    github_api_request "repos/$GITHUB_OWNER/$GITHUB_REPO/actions/runs/$run_id"
}

# Get workflow run jobs
get_workflow_run_jobs() {
    local run_id="$1"
    github_api_request "repos/$GITHUB_OWNER/$GITHUB_REPO/actions/runs/$run_id/jobs"
}

# Get workflow run artifacts
get_workflow_run_artifacts() {
    local run_id="$1"
    github_api_request "repos/$GITHUB_OWNER/$GITHUB_REPO/actions/runs/$run_id/artifacts"
}

# Get workflow run logs
get_workflow_run_logs() {
    local run_id="$1"
    local job_id="${2:-}"
    
    if [[ -n "$job_id" ]]; then
        github_api_request "repos/$GITHUB_OWNER/$GITHUB_REPO/actions/jobs/$job_id/logs"
    else
        github_api_request "repos/$GITHUB_OWNER/$GITHUB_REPO/actions/runs/$run_id/logs"
    fi
}

# Cancel workflow run
cancel_workflow_run() {
    local run_id="$1"
    github_api_request "repos/$GITHUB_OWNER/$GITHUB_REPO/actions/runs/$run_id/cancel" "POST"
}

# ============================================================================
# DATA PARSING FUNCTIONS
# ============================================================================

# Parse workflow run data
parse_workflow_run() {
    local json_data="$1"
    
    # Extract key fields using basic JSON parsing
    local id name status conclusion created_at updated_at
    id=$(echo "$json_data" | grep -o '"id":[0-9]*' | cut -d: -f2 | head -n1)
    name=$(echo "$json_data" | grep -o '"name":"[^"]*"' | cut -d: -f2 | tr -d '"' | head -n1)
    status=$(echo "$json_data" | grep -o '"status":"[^"]*"' | cut -d: -f2 | tr -d '"' | head -n1)
    conclusion=$(echo "$json_data" | grep -o '"conclusion":"[^"]*"' | cut -d: -f2 | tr -d '"' | head -n1)
    created_at=$(echo "$json_data" | grep -o '"created_at":"[^"]*"' | cut -d: -f2- | tr -d '"' | head -n1)
    updated_at=$(echo "$json_data" | grep -o '"updated_at":"[^"]*"' | cut -d: -f2- | tr -d '"' | head -n1)
    
    echo "id=$id"
    echo "name=$name"
    echo "status=$status"
    echo "conclusion=$conclusion"
    echo "created_at=$created_at"
    echo "updated_at=$updated_at"
}

# Parse workflow runs list
parse_workflow_runs() {
    local json_data="$1"
    
    # Extract workflow runs from JSON array
    # This is a simplified parser - in production you might want to use jq
    echo "$json_data" | grep -o '"workflow_runs":\[.*\]' | sed 's/"workflow_runs":\[//' | sed 's/\]$//' | 
    while IFS= read -r run_data; do
        if [[ -n "$run_data" ]]; then
            parse_workflow_run "$run_data"
            echo "---"
        fi
    done
}

# Get status icon for workflow status
get_status_icon() {
    local status="$1"
    local conclusion="${2:-}"
    
    case "$status" in
        "completed")
            case "$conclusion" in
                "success") echo "✅" ;;
                "failure") echo "❌" ;;
                "cancelled") echo "🚫" ;;
                "skipped") echo "⏭️" ;;
                *) echo "❓" ;;
            esac
            ;;
        "in_progress") echo "🔄" ;;
        "queued") echo "⏳" ;;
        "requested") echo "📋" ;;
        *) echo "❓" ;;
    esac
}

# Get status color for terminal output
get_status_color() {
    local status="$1"
    local conclusion="${2:-}"
    
    case "$status" in
        "completed")
            case "$conclusion" in
                "success") echo "$GREEN" ;;
                "failure") echo "$RED" ;;
                "cancelled") echo "$YELLOW" ;;
                *) echo "$NC" ;;
            esac
            ;;
        "in_progress") echo "$BLUE" ;;
        "queued") echo "$CYAN" ;;
        *) echo "$NC" ;;
    esac
}

# ============================================================================
# DASHBOARD DISPLAY FUNCTIONS
# ============================================================================

# Display dashboard header
display_dashboard_header() {
    print_separator
    log_header "🚀 Release Workflow Status Dashboard"
    print_separator
    echo -e "Repository: ${BOLD}$GITHUB_OWNER/$GITHUB_REPO${NC}"
    echo -e "Mode: ${BOLD}$DASHBOARD_MODE${NC}"
    echo -e "Updated: ${BOLD}$(get_timestamp)${NC}"
    if [[ "$AUTO_REFRESH" == "true" ]]; then
        echo -e "Auto-refresh: ${BOLD}${REFRESH_INTERVAL}s${NC}"
    fi
    print_separator
    echo
}

# Display workflow run summary
display_workflow_summary() {
    local run_data="$1"
    
    # Parse run data
    local id name status conclusion created_at updated_at
    eval "$(parse_workflow_run "$run_data")"
    
    local icon color
    icon=$(get_status_icon "$status" "$conclusion")
    color=$(get_status_color "$status" "$conclusion")
    
    # Calculate duration
    local start_time end_time duration
    start_time=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${created_at%.*}Z" "+%s" 2>/dev/null || echo "0")
    end_time=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${updated_at%.*}Z" "+%s" 2>/dev/null || echo "$start_time")
    duration=$((end_time - start_time))
    
    echo -e "${icon} ${color}${BOLD}${name}${NC} ${color}(#${id})${NC}"
    echo -e "   Status: ${color}${status}${NC}"
    if [[ -n "$conclusion" && "$conclusion" != "null" ]]; then
        echo -e "   Result: ${color}${conclusion}${NC}"
    fi
    echo -e "   Duration: $(format_duration "$duration")"
    echo -e "   Started: ${created_at}"
    echo
}

# Display workflow jobs
display_workflow_jobs() {
    local run_id="$1"
    
    log_info "Fetching jobs for workflow run #$run_id..."
    local jobs_data
    jobs_data=$(get_workflow_run_jobs "$run_id")
    
    if [[ -n "$jobs_data" ]]; then
        echo -e "${BOLD}Jobs:${NC}"
        # Simplified job parsing - you might want to enhance this
        echo "$jobs_data" | grep -o '"name":"[^"]*"' | cut -d: -f2 | tr -d '"' | while read -r job_name; do
            echo -e "  • $job_name"
        done
        echo
    fi
}

# Display workflow artifacts
display_workflow_artifacts() {
    local run_id="$1"
    
    log_info "Fetching artifacts for workflow run #$run_id..."
    local artifacts_data
    artifacts_data=$(get_workflow_run_artifacts "$run_id")
    
    if [[ -n "$artifacts_data" ]]; then
        echo -e "${BOLD}Artifacts:${NC}"
        # Simplified artifact parsing
        local artifact_count
        artifact_count=$(echo "$artifacts_data" | grep -o '"name":"[^"]*"' | wc -l)
        if [[ $artifact_count -gt 0 ]]; then
            echo "$artifacts_data" | grep -o '"name":"[^"]*"' | cut -d: -f2 | tr -d '"' | while read -r artifact_name; do
                echo -e "  📦 $artifact_name"
            done
        else
            echo -e "  ${YELLOW}No artifacts found${NC}"
        fi
        echo
    fi
}

# Display release workflows status
display_release_workflows() {
    log_info "Fetching release workflow runs..."
    
    local runs_data
    runs_data=$(get_workflow_runs "$FILTER_WORKFLOW")
    
    if [[ -z "$runs_data" ]]; then
        log_error "Failed to fetch workflow runs"
        return 1
    fi
    
    echo -e "${BOLD}Recent Workflow Runs:${NC}"
    echo
    
    # Parse and display workflow runs
    local run_count=0
    echo "$runs_data" | grep -o '{[^{}]*"id":[0-9]*[^{}]*}' | head -n "$MAX_RUNS" | while read -r run_json; do
        if [[ -n "$run_json" ]]; then
            display_workflow_summary "$run_json"
            run_count=$((run_count + 1))
        fi
    done
    
    if [[ $run_count -eq 0 ]]; then
        echo -e "${YELLOW}No workflow runs found${NC}"
    fi
}

# Display detailed workflow information
display_workflow_details() {
    local run_id="$1"
    
    log_info "Fetching detailed information for workflow run #$run_id..."
    
    local run_data
    run_data=$(get_workflow_run "$run_id")
    
    if [[ -z "$run_data" ]]; then
        log_error "Failed to fetch workflow run details"
        return 1
    fi
    
    echo -e "${BOLD}Workflow Run Details:${NC}"
    echo
    
    display_workflow_summary "$run_data"
    display_workflow_jobs "$run_id"
    display_workflow_artifacts "$run_id"
    
    if [[ "$SHOW_LOGS" == "true" ]]; then
        echo -e "${BOLD}Recent Logs:${NC}"
        local logs_data
        logs_data=$(get_workflow_run_logs "$run_id" | head -n 20)
        if [[ -n "$logs_data" ]]; then
            echo "$logs_data" | sed 's/^/  /'
        else
            echo -e "  ${YELLOW}Logs not available${NC}"
        fi
        echo
    fi
}

# Display dashboard statistics
display_dashboard_stats() {
    log_info "Generating workflow statistics..."
    
    local runs_data
    runs_data=$(get_workflow_runs "" 50) # Get more runs for stats
    
    if [[ -z "$runs_data" ]]; then
        log_error "Failed to fetch workflow data for statistics"
        return 1
    fi
    
    # Count workflow statuses
    local total_runs success_runs failed_runs in_progress_runs
    total_runs=$(echo "$runs_data" | grep -c '"id":[0-9]*' || echo "0")
    success_runs=$(echo "$runs_data" | grep -c '"conclusion":"success"' || echo "0")
    failed_runs=$(echo "$runs_data" | grep -c '"conclusion":"failure"' || echo "0")
    in_progress_runs=$(echo "$runs_data" | grep -c '"status":"in_progress"' || echo "0")
    
    echo -e "${BOLD}Workflow Statistics (Last $total_runs runs):${NC}"
    echo
    echo -e "  ✅ Successful: $success_runs"
    echo -e "  ❌ Failed: $failed_runs"
    echo -e "  🔄 In Progress: $in_progress_runs"
    echo -e "  📊 Success Rate: $(( total_runs > 0 ? (success_runs * 100) / total_runs : 0 ))%"
    echo
}

# ============================================================================
# MONITORING AND ALERTS
# ============================================================================

# Check for failed workflows
check_for_failures() {
    log_info "Checking for workflow failures..."
    
    local runs_data
    runs_data=$(get_workflow_runs "" 10)
    
    local failed_count
    failed_count=$(echo "$runs_data" | grep -c '"conclusion":"failure"' || echo "0")
    
    if [[ $failed_count -gt 0 ]]; then
        log_warning "Found $failed_count failed workflow(s) in recent runs"
        
        # Extract failed workflow IDs and names
        echo "$runs_data" | grep -B 5 -A 5 '"conclusion":"failure"' | grep -o '"id":[0-9]*\|"name":"[^"]*"' | while read -r line; do
            if [[ "$line" =~ ^\"id\": ]]; then
                local failed_id
                failed_id=$(echo "$line" | cut -d: -f2)
                echo -e "  ❌ Failed workflow ID: $failed_id"
            fi
        done
        
        return 1
    else
        log_success "No recent workflow failures detected"
        return 0
    fi
}

# Monitor workflow progress
monitor_workflow_progress() {
    local run_id="${1:-}"
    
    if [[ -z "$run_id" ]]; then
        log_info "Monitoring all in-progress workflows..."
        
        # Get in-progress workflows
        local runs_data
        runs_data=$(get_workflow_runs)
        
        local in_progress_ids
        in_progress_ids=$(echo "$runs_data" | grep -B 5 '"status":"in_progress"' | grep -o '"id":[0-9]*' | cut -d: -f2)
        
        if [[ -z "$in_progress_ids" ]]; then
            log_info "No workflows currently in progress"
            return 0
        fi
        
        for workflow_id in $in_progress_ids; do
            log_info "Monitoring workflow #$workflow_id"
            display_workflow_details "$workflow_id"
        done
    else
        log_info "Monitoring specific workflow #$run_id"
        display_workflow_details "$run_id"
    fi
}

# Generate status report
generate_status_report() {
    local report_file="$DASHBOARD_DIR/status-report-$(date +%Y%m%d-%H%M%S).md"
    
    log_info "Generating status report: $(basename "$report_file")"
    
    {
        echo "# Release Workflow Status Report"
        echo ""
        echo "**Repository:** $GITHUB_OWNER/$GITHUB_REPO"
        echo "**Generated:** $(get_iso_timestamp)"
        echo ""
        
        # Get workflow data for report
        local runs_data
        runs_data=$(get_workflow_runs "" 20)
        
        echo "## Recent Workflow Runs"
        echo ""
        
        if [[ -n "$runs_data" ]]; then
            echo "| ID | Name | Status | Conclusion | Duration |"
            echo "|----|------|--------|------------|----------|"
            
            echo "$runs_data" | grep -o '{[^{}]*"id":[0-9]*[^{}]*}' | head -n 10 | while read -r run_json; do
                local id name status conclusion created_at updated_at
                eval "$(parse_workflow_run "$run_json")"
                
                local start_time end_time duration
                start_time=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${created_at%.*}Z" "+%s" 2>/dev/null || echo "0")
                end_time=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${updated_at%.*}Z" "+%s" 2>/dev/null || echo "$start_time")
                duration=$((end_time - start_time))
                
                local icon
                icon=$(get_status_icon "$status" "$conclusion")
                
                echo "| $id | $name | $icon $status | $conclusion | $(format_duration "$duration") |"
            done
        fi
        
        echo ""
        echo "## Troubleshooting"
        echo ""
        echo "### Common Issues"
        echo ""
        echo "- **Build failures**: Check SwiftLint compliance and dependency resolution"
        echo "- **Test failures**: Verify environment setup and test dependencies"
        echo "- **Artifact issues**: Validate build configuration and permissions"
        echo ""
        echo "### Useful Commands"
        echo ""
        echo "```bash"
        echo "# View workflow details"
        echo "$0 --mode details --run-id <ID>"
        echo ""
        echo "# Monitor in-progress workflows"
        echo "$0 --mode monitor"
        echo ""
        echo "# Check for failures"
        echo "$0 --mode check-failures"
        echo "```"
        
    } > "$report_file"
    
    log_success "Status report generated: $report_file"
    echo "$report_file"
}

# ============================================================================
# MAIN DASHBOARD FUNCTIONS
# ============================================================================

# Run dashboard in different modes
run_dashboard() {
    case "$DASHBOARD_MODE" in
        "status")
            display_dashboard_header
            display_release_workflows
            display_dashboard_stats
            ;;
        "monitor")
            display_dashboard_header
            monitor_workflow_progress
            ;;
        "details")
            if [[ -n "${RUN_ID:-}" ]]; then
                display_dashboard_header
                display_workflow_details "$RUN_ID"
            else
                log_error "Run ID required for details mode. Use --run-id option."
                exit 1
            fi
            ;;
        "stats")
            display_dashboard_header
            display_dashboard_stats
            ;;
        "check-failures")
            display_dashboard_header
            check_for_failures
            ;;
        "report")
            report_file=$(generate_status_report)
            log_success "Report generated: $report_file"
            ;;
        *)
            log_error "Unknown dashboard mode: $DASHBOARD_MODE"
            exit 1
            ;;
    esac
}

# Auto-refresh dashboard
run_auto_refresh() {
    while true; do
        clear
        run_dashboard
        
        echo -e "${CYAN}Press Ctrl+C to stop auto-refresh...${NC}"
        sleep "$REFRESH_INTERVAL"
    done
}

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Release Workflow Status Dashboard for usbipd-mac

Provides real-time monitoring and status reporting for GitHub Actions release workflows.

OPTIONS:
    --mode MODE                 Dashboard mode: status, monitor, details, stats, check-failures, report
    --run-id ID                Specific workflow run ID (required for details mode)
    --filter WORKFLOW          Filter workflows by name
    --refresh SECONDS          Auto-refresh interval in seconds
    --auto-refresh             Enable auto-refresh mode
    --max-runs COUNT           Maximum number of runs to display (default: 10)
    --show-logs                Show workflow logs (details mode only)
    --format FORMAT            Output format: terminal, json, markdown
    --verbose                  Enable verbose logging
    --help                     Show this help message

ENVIRONMENT VARIABLES:
    GITHUB_TOKEN               GitHub personal access token for API access
    GITHUB_OWNER               GitHub repository owner (auto-detected)
    GITHUB_REPO                GitHub repository name (auto-detected)

EXAMPLES:
    $0                                    # Show status dashboard
    $0 --mode monitor                     # Monitor in-progress workflows
    $0 --mode details --run-id 123456    # Show details for specific run
    $0 --mode stats                       # Show workflow statistics
    $0 --auto-refresh --refresh 10        # Auto-refresh every 10 seconds
    $0 --mode check-failures              # Check for recent failures
    $0 --mode report                      # Generate status report

MODES:
    status          Show recent workflow runs and overall status
    monitor         Monitor in-progress workflows with real-time updates
    details         Show detailed information for a specific workflow run
    stats           Display workflow statistics and success rates
    check-failures  Check for and report workflow failures
    report          Generate comprehensive status report

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode)
                DASHBOARD_MODE="$2"
                shift 2
                ;;
            --run-id)
                RUN_ID="$2"
                shift 2
                ;;
            --filter)
                FILTER_WORKFLOW="$2"
                shift 2
                ;;
            --refresh)
                REFRESH_INTERVAL="$2"
                shift 2
                ;;
            --auto-refresh)
                AUTO_REFRESH=true
                shift
                ;;
            --max-runs)
                MAX_RUNS="$2"
                shift 2
                ;;
            --show-logs)
                SHOW_LOGS=true
                shift
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
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
}

# Main function
main() {
    parse_arguments "$@"
    
    # Setup
    ensure_dashboard_directory
    
    # Detect GitHub repository
    if ! detect_github_repo; then
        exit 1
    fi
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Validate GitHub API access
    if [[ -z "$GITHUB_TOKEN" ]]; then
        log_warning "GITHUB_TOKEN not set. API rate limiting may apply."
    fi
    
    # Run dashboard
    if [[ "$AUTO_REFRESH" == "true" ]]; then
        trap 'log_info "Auto-refresh stopped"; exit 0' INT
        run_auto_refresh
    else
        run_dashboard
    fi
}

# Error handler
handle_error() {
    local exit_code=$?
    log_error "Dashboard failed with exit code $exit_code"
    exit $exit_code
}

trap 'handle_error' ERR

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi