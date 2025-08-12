#!/bin/bash

# Environment-Specific Test Report Generator
# Unified test reporting with environment-specific metrics and analysis
# Consolidates reporting functionality from existing scripts

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/.build"
readonly LOG_DIR="${BUILD_DIR}/logs"
readonly REPORTS_DIR="${BUILD_DIR}/reports"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
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

log_header() {
    echo -e "${PURPLE}[REPORT:${TEST_ENVIRONMENT}]${NC} $1"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Create reports directory if it doesn't exist
ensure_reports_directory() {
    if [[ ! -d "$REPORTS_DIR" ]]; then
        mkdir -p "$REPORTS_DIR"
        log_info "Created reports directory: $REPORTS_DIR"
    fi
}

# Get timestamp for report generation
get_report_timestamp() {
    date "+%Y-%m-%d_%H-%M-%S"
}

# Get ISO timestamp for report content
get_iso_timestamp() {
    date -u "+%Y-%m-%dT%H:%M:%S.%3NZ"
}

# Format duration in human-readable format
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
        local remaining_seconds=$((seconds % 60))
        echo "${hours}h ${remaining_minutes}m ${remaining_seconds}s"
    fi
}

# Calculate percentage
calculate_percentage() {
    local numerator="$1"
    local denominator="$2"
    
    if [[ $denominator -eq 0 ]]; then
        echo "0"
    else
        echo "$(( (numerator * 100) / denominator ))"
    fi
}

# ============================================================================
# SWIFT TEST OUTPUT PARSING
# ============================================================================

# Parse Swift test output (internal function)
parse_swift_test_output_internal() {
    local test_output_file="$1"
    
    if [[ ! -f "$test_output_file" ]]; then
        return 1
    fi
    
    # Extract test results
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local skipped_tests=0
    local execution_time=0
    
    # Parse test summary from Swift output
    if grep -q "Test Suite.*started" "$test_output_file" 2>/dev/null; then
        total_tests=$(grep -c "Test Case.*started" "$test_output_file" 2>/dev/null)
        passed_tests=$(grep -c "Test Case.*passed" "$test_output_file" 2>/dev/null) 
        failed_tests=$(grep -c "Test Case.*failed" "$test_output_file" 2>/dev/null) 
        skipped_tests=$(grep -c "Test Case.*skipped" "$test_output_file" 2>/dev/null)
        
        # Extract execution time from final summary line
        local time_line
        time_line=$(grep "Executed.*tests.*in.*seconds" "$test_output_file" | tail -n1 2>/dev/null || echo "")
        if [[ -n "$time_line" ]]; then
            execution_time=$(echo "$time_line" | sed -n 's/.*in \([0-9.]*\) (\([0-9.]*\)) seconds/\2/p' | head -n1)
            if [[ -z "$execution_time" ]]; then
                execution_time=$(echo "$time_line" | sed -n 's/.*in \([0-9.]*\) seconds.*/\1/p' | head -n1)
            fi
        fi
        
        # If execution_time is still empty, set to 0
        if [[ -z "$execution_time" ]]; then
            execution_time="0"
        fi
    fi
    
    # Output results in structured format
    echo "total_tests=$total_tests"
    echo "passed_tests=$passed_tests"
    echo "failed_tests=$failed_tests"
    echo "skipped_tests=$skipped_tests"
    echo "execution_time=$execution_time"
}

# Public parse function with logging
parse_swift_test_output() {
    local test_output_file="$1"
    log_info "Parsing test output: $test_output_file"
    parse_swift_test_output_internal "$test_output_file"
}

# Parse build output (internal function)
parse_build_output_internal() {
    local build_output_file="$1"
    
    if [[ ! -f "$build_output_file" ]]; then
        return 1
    fi
    
    local build_success=false
    local build_time=0
    local warning_count=0
    local error_count=0
    
    # Check if build succeeded
    if grep -q "BUILD SUCCEEDED" "$build_output_file" || grep -q "Build complete!" "$build_output_file"; then
        build_success=true
    fi
    
    # Count warnings and errors
    warning_count=$(grep -c "warning:" "$build_output_file" 2>/dev/null)
    error_count=$(grep -c "error:" "$build_output_file" 2>/dev/null)
    
    # Extract build time from "Build complete! (2.5s)" format
    local time_line
    time_line=$(grep "Build complete!" "$build_output_file" | tail -n1 2>/dev/null || echo "")
    if [[ -n "$time_line" ]]; then
        build_time=$(echo "$time_line" | sed -n 's/.*(\([0-9.]*\)s).*/\1/p' | head -n1)
    fi
    
    # If build_time is still empty, set to 0
    if [[ -z "$build_time" ]]; then
        build_time="0"
    fi
    
    echo "build_success=$build_success"
    echo "build_time=$build_time"
    echo "warning_count=$warning_count"
    echo "error_count=$error_count"
}

# Public parse function with logging
parse_build_output() {
    local build_output_file="$1"
    log_info "Parsing build output: $build_output_file"
    parse_build_output_internal "$build_output_file"
}

# ============================================================================
# ENVIRONMENT-SPECIFIC REPORT SECTIONS
# ============================================================================

# Generate environment information section
generate_environment_section() {
    cat << EOF

# Test Environment Information

**Environment:** ${TEST_ENVIRONMENT}
**Platform:** $(uname -s) $(uname -m)
**Kernel:** $(uname -r)
**Generated:** $(get_iso_timestamp)

## Environment Configuration

EOF

    case "$TEST_ENVIRONMENT" in
        "development")
            cat << EOF
- **Purpose:** Fast feedback during development
- **Expected Duration:** < 1 minute
- **Mock Level:** Comprehensive
- **Hardware Tests:** Disabled
- **System Extension Tests:** Mocked

EOF
            ;;
        "ci")
            cat << EOF
- **Purpose:** Automated validation in CI/CD
- **Expected Duration:** < 3 minutes
- **Mock Level:** Selective
- **Hardware Tests:** Disabled
- **System Extension Tests:** Mocked
- **CI Platform:** ${CI_PLATFORM:-"Unknown"}

EOF
            ;;
        "production")
            cat << EOF
- **Purpose:** Comprehensive validation for release
- **Expected Duration:** < 10 minutes
- **Mock Level:** Minimal
- **Hardware Tests:** Enabled (if available)
- **System Extension Tests:** Real (if privileges available)
- **QEMU Tests:** Enabled (if available)

EOF
            ;;
    esac
}

# Generate test execution summary
generate_test_summary() {
    local test_results="$1"
    
    # Parse test results
    local total_tests passed_tests failed_tests skipped_tests execution_time
    eval "$test_results"
    
    local success_rate
    success_rate=$(calculate_percentage "$passed_tests" "$total_tests")
    
    cat << EOF

# Test Execution Summary

## Overall Results

| Metric | Value |
|--------|-------|
| Total Tests | $total_tests |
| Passed | $passed_tests |
| Failed | $failed_tests |
| Skipped | $skipped_tests |
| Success Rate | ${success_rate}% |
| Execution Time | $(format_duration "${execution_time%.*}") |

## Status

EOF

    if [[ $failed_tests -eq 0 ]]; then
        echo "✅ **PASSED** - All tests executed successfully"
    else
        echo "❌ **FAILED** - $failed_tests test(s) failed"
    fi
    
    echo ""
}

# Generate build summary
generate_build_summary() {
    local build_results="$1"
    
    # Parse build results
    local build_success build_time warning_count error_count
    eval "$build_results"
    
    cat << EOF

# Build Summary

## Build Results

| Metric | Value |
|--------|-------|
| Build Status | $(if [[ "$build_success" == "true" ]]; then echo "✅ SUCCESS"; else echo "❌ FAILED"; fi) |
| Build Time | $(format_duration "${build_time%.*}") |
| Warnings | $warning_count |
| Errors | $error_count |

EOF
}

# Generate environment-specific metrics
generate_environment_metrics() {
    local test_results="$1"
    local build_results="$2"
    
    # Parse results
    local total_tests passed_tests failed_tests skipped_tests execution_time
    eval "$test_results"
    local build_success build_time warning_count error_count
    eval "$build_results"
    
    cat << EOF

# Environment-Specific Metrics

EOF

    case "$TEST_ENVIRONMENT" in
        "development")
            cat << EOF
## Development Environment Metrics

- **Speed Focus:** Execution time $(format_duration "${execution_time%.*}") (target: < 1 minute)
- **Mock Effectiveness:** $(calculate_percentage "$passed_tests" "$total_tests")% test pass rate with comprehensive mocking
- **Quick Feedback:** $(if [[ "${execution_time%.*}" -lt 60 ]]; then echo "✅ Target met"; else echo "⚠️ Exceeds target"; fi)

EOF
            ;;
        "ci")
            cat << EOF
## CI Environment Metrics

- **Reliability:** $(calculate_percentage "$passed_tests" "$total_tests")% test pass rate in automated environment
- **CI Duration:** Execution time $(format_duration "${execution_time%.*}") (target: < 3 minutes)
- **Build Quality:** $warning_count warnings, $error_count errors
- **Automation Success:** $(if [[ "$build_success" == "true" && $failed_tests -eq 0 ]]; then echo "✅ Fully automated"; else echo "⚠️ Manual intervention needed"; fi)

EOF
            ;;
        "production")
            cat << EOF
## Production Environment Metrics

- **Comprehensive Coverage:** $total_tests total tests executed
- **Release Readiness:** $(if [[ $failed_tests -eq 0 && "$build_success" == "true" ]]; then echo "✅ Ready for release"; else echo "❌ Not ready for release"; fi)
- **Hardware Integration:** $(if [[ $skipped_tests -eq 0 ]]; then echo "✅ All hardware tests executed"; else echo "⚠️ Some hardware tests skipped"; fi)
- **Quality Metrics:** $warning_count warnings, $error_count errors in production build

EOF
            ;;
    esac
}

# Generate performance analysis
generate_performance_analysis() {
    local test_results="$1"
    local build_results="$2"
    
    # Parse results
    local total_tests passed_tests failed_tests skipped_tests execution_time
    eval "$test_results"
    local build_success build_time warning_count error_count
    eval "$build_results"
    
    # Calculate total time using shell arithmetic
    local build_seconds="${build_time%.*}"
    local execution_seconds="${execution_time%.*}"
    local total_time=$((build_seconds + execution_seconds))
    
    cat << EOF

# Performance Analysis

## Timing Breakdown

| Phase | Duration | Percentage |
|-------|----------|------------|
| Build | $(format_duration "$build_seconds") | $(calculate_percentage "$build_seconds" "$total_time")% |
| Test Execution | $(format_duration "$execution_seconds") | $(calculate_percentage "$execution_seconds" "$total_time")% |
| **Total** | **$(format_duration "$total_time")** | **100%** |

## Performance Assessment

EOF

    # Environment-specific performance targets
    local target_time
    case "$TEST_ENVIRONMENT" in
        "development")
            target_time=60
            ;;
        "ci")
            target_time=180
            ;;
        "production")
            target_time=600
            ;;
        *)
            target_time=180
            ;;
    esac
    
    if [[ $total_time -lt $target_time ]]; then
        echo "✅ **Performance Target Met** - Execution completed within ${target_time}s target"
    else
        echo "⚠️ **Performance Target Missed** - Execution took ${total_time}s (target: ${target_time}s)"
    fi
    
    echo ""
    echo "### Recommendations"
    echo ""
    
    if [[ $execution_seconds -gt 30 && "$TEST_ENVIRONMENT" == "development" ]]; then
        echo "- Consider reducing test scope for development environment"
    fi
    
    if [[ $warning_count -gt 10 ]]; then
        echo "- Address build warnings to improve code quality"
    fi
    
    if [[ $skipped_tests -gt 5 ]]; then
        echo "- Review skipped tests to ensure adequate coverage"
    fi
    
    echo ""
}

# ============================================================================
# REPORT GENERATION FUNCTIONS
# ============================================================================

# Generate detailed test report
generate_detailed_test_report() {
    local test_output_file="$1"
    local build_output_file="$2"
    local report_file="$3"
    local report_title="${4:-Test Execution Report}"
    
    log_info "Generating detailed test report: $(basename "$report_file")"
    
    # Parse test and build outputs
    local test_results
    test_results=$(parse_swift_test_output_internal "$test_output_file")
    
    local build_results
    build_results=$(parse_build_output_internal "$build_output_file")
    
    # Generate comprehensive report
    {
        echo "# $report_title"
        echo ""
        echo "Generated for **${TEST_ENVIRONMENT}** environment on $(date)"
        
        generate_environment_section
        generate_test_summary "$test_results"
        generate_build_summary "$build_results"
        generate_environment_metrics "$test_results" "$build_results"
        generate_performance_analysis "$test_results" "$build_results"
        
        # Add raw output sections
        echo ""
        echo "# Raw Output Files"
        echo ""
        echo "- Test Output: \`$(basename "$test_output_file")\`"
        echo "- Build Output: \`$(basename "$build_output_file")\`"
        
        # Add troubleshooting section if there are failures
        local failed_tests
        failed_tests=$(echo "$test_results" | grep "failed_tests=" | cut -d'=' -f2)
        if [[ $failed_tests -gt 0 ]]; then
            echo ""
            echo "# Troubleshooting"
            echo ""
            echo "## Failed Tests"
            echo ""
            if [[ -f "$test_output_file" ]]; then
                grep -A 2 -B 2 "failed" "$test_output_file" | head -n20 | sed 's/^/    /'
            fi
        fi
        
    } > "$report_file"
    
    log_success "Detailed test report generated: $(basename "$report_file")"
    return 0
}

# Generate summary report
generate_summary_report() {
    local test_output_file="$1"
    local build_output_file="$2"
    local report_file="$3"
    
    log_info "Generating summary test report: $(basename "$report_file")"
    
    # Parse test and build outputs
    local test_results
    test_results=$(parse_swift_test_output_internal "$test_output_file")
    
    local build_results
    build_results=$(parse_build_output_internal "$build_output_file")
    
    # Parse results for summary
    local total_tests passed_tests failed_tests execution_time
    eval "$test_results"
    local build_success
    eval "$build_results"
    
    {
        echo "# Test Execution Summary - ${TEST_ENVIRONMENT^^}"
        echo ""
        echo "**Generated:** $(date)"
        echo ""
        echo "## Quick Results"
        echo ""
        echo "| Metric | Value |"
        echo "|--------|-------|"
        echo "| Environment | $TEST_ENVIRONMENT |"
        echo "| Total Tests | $total_tests |"
        echo "| Passed | $passed_tests |"
        echo "| Failed | $failed_tests |"
        echo "| Build Status | $(if [[ "$build_success" == "true" ]]; then echo "✅ SUCCESS"; else echo "❌ FAILED"; fi) |"
        echo "| Duration | $(format_duration "${execution_time%.*}") |"
        echo ""
        
        if [[ $failed_tests -eq 0 && "$build_success" == "true" ]]; then
            echo "✅ **Overall Status: PASSED**"
        else
            echo "❌ **Overall Status: FAILED**"
        fi
        
    } > "$report_file"
    
    log_success "Summary test report generated: $(basename "$report_file")"
    return 0
}

# Generate JSON report for automation
generate_json_report() {
    local test_output_file="$1"
    local build_output_file="$2"
    local report_file="$3"
    
    log_info "Generating JSON test report: $(basename "$report_file")"
    
    # Parse test and build outputs
    local test_results
    test_results=$(parse_swift_test_output_internal "$test_output_file")
    
    local build_results
    build_results=$(parse_build_output_internal "$build_output_file")
    
    # Parse results
    local total_tests passed_tests failed_tests skipped_tests execution_time
    eval "$test_results"
    local build_success build_time warning_count error_count
    eval "$build_results"
    
    # Generate JSON report
    {
        echo "{"
        echo "  \"timestamp\": \"$(get_iso_timestamp)\","
        echo "  \"environment\": \"$TEST_ENVIRONMENT\","
        echo "  \"platform\": {"
        echo "    \"os\": \"$(uname -s)\","
        echo "    \"arch\": \"$(uname -m)\","
        echo "    \"kernel\": \"$(uname -r)\""
        echo "  },"
        echo "  \"build\": {"
        echo "    \"success\": $build_success,"
        echo "    \"time\": \"${build_time}\","
        echo "    \"warnings\": $warning_count,"
        echo "    \"errors\": $error_count"
        echo "  },"
        echo "  \"tests\": {"
        echo "    \"total\": $total_tests,"
        echo "    \"passed\": $passed_tests,"
        echo "    \"failed\": $failed_tests,"
        echo "    \"skipped\": $skipped_tests,"
        echo "    \"execution_time\": \"${execution_time}\","
        echo "    \"success_rate\": $(calculate_percentage "$passed_tests" "$total_tests")"
        echo "  },"
        echo "  \"status\": {"
        echo "    \"overall\": \"$(if [[ $failed_tests -eq 0 && "$build_success" == "true" ]]; then echo "PASSED"; else echo "FAILED"; fi)\","
        echo "    \"build\": \"$(if [[ "$build_success" == "true" ]]; then echo "PASSED"; else echo "FAILED"; fi)\","
        echo "    \"tests\": \"$(if [[ $failed_tests -eq 0 ]]; then echo "PASSED"; else echo "FAILED"; fi)\""
        echo "  }"
        echo "}"
    } > "$report_file"
    
    log_success "JSON test report generated: $(basename "$report_file")"
    return 0
}

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Environment-Specific Test Report Generator

COMMANDS:
    detailed <test_output> <build_output> [report_file]     Generate detailed markdown report
    summary <test_output> <build_output> [report_file]      Generate summary markdown report
    json <test_output> <build_output> [report_file]         Generate JSON report for automation
    auto <test_output> <build_output> [base_name]           Generate all report formats
    parse-test <test_output>                                Parse and display test results
    parse-build <build_output>                              Parse and display build results

OPTIONS:
    -h, --help                                              Show this help message

ENVIRONMENT VARIABLES:
    TEST_ENVIRONMENT=development|ci|production              Override environment detection

EXAMPLES:
    $0 detailed test_output.log build_output.log            Generate detailed report
    $0 summary test_output.log build_output.log summary.md  Generate summary with custom name
    $0 json test_output.log build_output.log results.json   Generate JSON report
    $0 auto test_output.log build_output.log test_run       Generate all formats with base name
    TEST_ENVIRONMENT=ci $0 detailed tests.log build.log     Generate CI-specific report

EOF
}

# Main function for command line execution
main() {
    local command="${1:-}"
    
    # Ensure reports directory exists
    ensure_reports_directory
    
    case "$command" in
        "detailed")
            if [[ $# -lt 3 ]]; then
                log_error "Usage: $0 detailed <test_output> <build_output> [report_file]"
                exit 1
            fi
            
            local test_output="$2"
            local build_output="$3"
            local report_file="${4:-$REPORTS_DIR/detailed-report-$(get_report_timestamp).md}"
            
            generate_detailed_test_report "$test_output" "$build_output" "$report_file"
            echo "Report generated: $report_file"
            ;;
            
        "summary")
            if [[ $# -lt 3 ]]; then
                log_error "Usage: $0 summary <test_output> <build_output> [report_file]"
                exit 1
            fi
            
            local test_output="$2"
            local build_output="$3"
            local report_file="${4:-$REPORTS_DIR/summary-report-$(get_report_timestamp).md}"
            
            generate_summary_report "$test_output" "$build_output" "$report_file"
            echo "Report generated: $report_file"
            ;;
            
        "json")
            if [[ $# -lt 3 ]]; then
                log_error "Usage: $0 json <test_output> <build_output> [report_file]"
                exit 1
            fi
            
            local test_output="$2"
            local build_output="$3"
            local report_file="${4:-$REPORTS_DIR/report-$(get_report_timestamp).json}"
            
            generate_json_report "$test_output" "$build_output" "$report_file"
            echo "Report generated: $report_file"
            ;;
            
        "auto")
            if [[ $# -lt 3 ]]; then
                log_error "Usage: $0 auto <test_output> <build_output> [base_name]"
                exit 1
            fi
            
            local test_output="$2"
            local build_output="$3"
            local base_name="${4:-test-report-$(get_report_timestamp)}"
            
            log_info "Generating all report formats with base name: $base_name"
            
            generate_detailed_test_report "$test_output" "$build_output" "$REPORTS_DIR/${base_name}-detailed.md" "${base_name^} - Detailed Report"
            generate_summary_report "$test_output" "$build_output" "$REPORTS_DIR/${base_name}-summary.md"
            generate_json_report "$test_output" "$build_output" "$REPORTS_DIR/${base_name}.json"
            
            echo "Reports generated:"
            echo "  Detailed: $REPORTS_DIR/${base_name}-detailed.md"
            echo "  Summary: $REPORTS_DIR/${base_name}-summary.md"
            echo "  JSON: $REPORTS_DIR/${base_name}.json"
            ;;
            
        "parse-test")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 parse-test <test_output>"
                exit 1
            fi
            
            log_info "Parsing test output: $2"
            parse_swift_test_output "$2"
            ;;
            
        "parse-build")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 parse-build <build_output>"
                exit 1
            fi
            
            log_info "Parsing build output: $2"
            parse_build_output "$2"
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