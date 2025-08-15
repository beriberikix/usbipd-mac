#!/bin/bash

# Release Workflow Performance Benchmarking
# Measures and analyzes release workflow execution times, build performance,
# and artifact generation efficiency for optimization insights
# Provides detailed performance reports and optimization recommendations

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/.build"
readonly BENCHMARK_DIR="${BUILD_DIR}/benchmarks"
readonly LOG_FILE="${BENCHMARK_DIR}/performance-benchmark.log"
readonly RESULTS_DIR="${BENCHMARK_DIR}/results"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Configuration variables
GENERATE_REPORT=false
BENCHMARK_TYPE="full"
OUTPUT_FORMAT="markdown"
ITERATIONS=1
PARALLEL_BUILD=true
CACHE_ENABLED=true
VERBOSE=false

# Performance targets (in seconds)
readonly TARGET_TOTAL_WORKFLOW=900    # 15 minutes
readonly TARGET_BUILD_TIME=300        # 5 minutes
readonly TARGET_TEST_TIME=600         # 10 minutes
readonly TARGET_ARTIFACT_TIME=180     # 3 minutes

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_BENCHMARK_FAILED=1
readonly EXIT_MISSING_DEPS=2
readonly EXIT_USAGE_ERROR=3

# Logging functions
log_info() {
    echo -e "${BLUE}[BENCHMARK]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_header() {
    echo -e "${PURPLE}${BOLD}[PERFORMANCE]${NC} $1" | tee -a "$LOG_FILE"
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1" | tee -a "$LOG_FILE"
    fi
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Ensure benchmark directories exist
ensure_benchmark_directories() {
    for dir in "$BENCHMARK_DIR" "$RESULTS_DIR"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_verbose "Created directory: $dir"
        fi
    done
}

# Get high-precision timestamp
get_timestamp() {
    if command -v gdate >/dev/null 2>&1; then
        # GNU date (if available via coreutils)
        gdate '+%s.%3N'
    else
        # macOS date
        python3 -c "import time; print(f'{time.time():.3f}')"
    fi
}

# Calculate elapsed time with precision
calculate_elapsed() {
    local start_time="$1"
    local end_time="$2"
    python3 -c "print(f'{float('$end_time') - float('$start_time'):.3f}')"
}

# Format duration in human-readable format
format_duration() {
    local seconds="$1"
    python3 -c "
import math
seconds = float('$seconds')
if seconds < 60:
    print(f'{seconds:.1f}s')
elif seconds < 3600:
    minutes = int(seconds // 60)
    remaining_seconds = seconds % 60
    print(f'{minutes}m {remaining_seconds:.1f}s')
else:
    hours = int(seconds // 3600)
    remaining_minutes = int((seconds % 3600) // 60)
    remaining_seconds = seconds % 60
    print(f'{hours}h {remaining_minutes}m {remaining_seconds:.1f}s')
"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get system information
get_system_info() {
    cat << EOF
{
    "os": "$(uname -s)",
    "arch": "$(uname -m)", 
    "kernel": "$(uname -r)",
    "swift_version": "$(swift --version | head -n1 | cut -d' ' -f4 2>/dev/null || echo 'unknown')",
    "xcode_version": "$(xcodebuild -version 2>/dev/null | head -n1 | sed 's/Xcode //' || echo 'unknown')",
    "cpu_cores": "$(sysctl -n hw.ncpu)",
    "memory_gb": "$(echo "$(sysctl -n hw.memsize) / 1024 / 1024 / 1024" | bc)"
}
EOF
}

# ============================================================================
# BENCHMARKING FUNCTIONS
# ============================================================================

# Clean build environment for consistent benchmarking
clean_build_environment() {
    log_info "Cleaning build environment for consistent benchmarking"
    
    # Remove build artifacts
    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "${BUILD_DIR:?}"/*
        log_verbose "Removed build artifacts"
    fi
    
    # Clean Swift package cache if not using cache
    if [[ "$CACHE_ENABLED" == "false" ]]; then
        swift package clean 2>/dev/null || true
        log_verbose "Cleaned Swift package cache"
    fi
}

# Benchmark Swift build performance
benchmark_build_performance() {
    local iteration="$1"
    local build_log="${RESULTS_DIR}/build-${iteration}.log"
    local build_metrics="${RESULTS_DIR}/build-${iteration}.json"
    
    log_info "Benchmarking build performance (iteration $iteration)"
    
    local start_time
    start_time=$(get_timestamp)
    
    # Run build with timing
    local build_success=false
    local warning_count=0
    local error_count=0
    
    if swift build --configuration release --verbose > "$build_log" 2>&1; then
        build_success=true
        log_success "Build completed successfully"
    else
        log_error "Build failed"
    fi
    
    local end_time
    end_time=$(get_timestamp)
    local elapsed_time
    elapsed_time=$(calculate_elapsed "$start_time" "$end_time")
    
    # Count warnings and errors
    warning_count=$(grep -c "warning:" "$build_log" 2>/dev/null || echo "0")
    error_count=$(grep -c "error:" "$build_log" 2>/dev/null || echo "0")
    
    # Generate build metrics
    cat << EOF > "$build_metrics"
{
    "iteration": $iteration,
    "success": $build_success,
    "elapsed_time": $elapsed_time,
    "warnings": $warning_count,
    "errors": $error_count,
    "cache_enabled": $CACHE_ENABLED,
    "parallel_enabled": $PARALLEL_BUILD,
    "configuration": "release"
}
EOF
    
    log_verbose "Build metrics saved to: $(basename "$build_metrics")"
    echo "$elapsed_time"
}

# Benchmark test execution performance
benchmark_test_performance() {
    local iteration="$1"
    local test_log="${RESULTS_DIR}/test-${iteration}.log"
    local test_metrics="${RESULTS_DIR}/test-${iteration}.json"
    
    log_info "Benchmarking test execution performance (iteration $iteration)"
    
    local start_time
    start_time=$(get_timestamp)
    
    # Run tests with timing
    local test_success=false
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    if swift test --parallel > "$test_log" 2>&1; then
        test_success=true
        log_success "Tests completed successfully"
    else
        log_error "Tests failed"
    fi
    
    local end_time
    end_time=$(get_timestamp)
    local elapsed_time
    elapsed_time=$(calculate_elapsed "$start_time" "$end_time")
    
    # Parse test results
    total_tests=$(grep -c "Test Case.*started" "$test_log" 2>/dev/null || echo "0")
    passed_tests=$(grep -c "Test Case.*passed" "$test_log" 2>/dev/null || echo "0")
    failed_tests=$(grep -c "Test Case.*failed" "$test_log" 2>/dev/null || echo "0")
    
    # Generate test metrics
    cat << EOF > "$test_metrics"
{
    "iteration": $iteration,
    "success": $test_success,
    "elapsed_time": $elapsed_time,
    "total_tests": $total_tests,
    "passed_tests": $passed_tests,
    "failed_tests": $failed_tests,
    "parallel_enabled": true
}
EOF
    
    log_verbose "Test metrics saved to: $(basename "$test_metrics")"
    echo "$elapsed_time"
}

# Benchmark artifact generation performance
benchmark_artifact_performance() {
    local iteration="$1"
    local artifact_log="${RESULTS_DIR}/artifact-${iteration}.log"
    local artifact_metrics="${RESULTS_DIR}/artifact-${iteration}.json"
    
    log_info "Benchmarking artifact generation performance (iteration $iteration)"
    
    local start_time
    start_time=$(get_timestamp)
    
    # Simulate artifact generation process
    local artifact_success=false
    local binary_count=0
    local total_size=0
    
    # Build release binaries
    if swift build --configuration release --product usbipd > "$artifact_log" 2>&1; then
        artifact_success=true
        
        # Count and measure artifacts
        if [[ -d "${BUILD_DIR}/release" ]]; then
            binary_count=$(find "${BUILD_DIR}/release" -type f -executable | wc -l)
            total_size=$(find "${BUILD_DIR}/release" -type f -exec stat -f%z {} + | awk '{s+=$1} END {print s}' 2>/dev/null || echo "0")
        fi
        
        log_success "Artifact generation completed successfully"
    else
        log_error "Artifact generation failed"
    fi
    
    local end_time
    end_time=$(get_timestamp)
    local elapsed_time
    elapsed_time=$(calculate_elapsed "$start_time" "$end_time")
    
    # Generate artifact metrics
    cat << EOF > "$artifact_metrics"
{
    "iteration": $iteration,
    "success": $artifact_success,
    "elapsed_time": $elapsed_time,
    "binary_count": $binary_count,
    "total_size_bytes": $total_size,
    "configuration": "release"
}
EOF
    
    log_verbose "Artifact metrics saved to: $(basename "$artifact_metrics")"
    echo "$elapsed_time"
}

# Run comprehensive performance benchmark
run_comprehensive_benchmark() {
    local benchmark_id="benchmark-$(date '+%Y%m%d-%H%M%S')"
    local summary_file="${RESULTS_DIR}/${benchmark_id}-summary.json"
    
    log_header "Starting comprehensive performance benchmark"
    log_info "Benchmark ID: $benchmark_id"
    log_info "Iterations: $ITERATIONS"
    
    # Initialize summary data
    local total_build_time=0
    local total_test_time=0
    local total_artifact_time=0
    local successful_iterations=0
    
    for ((i=1; i<=ITERATIONS; i++)); do
        log_header "Iteration $i of $ITERATIONS"
        
        # Clean environment for consistent results
        clean_build_environment
        
        # Benchmark build performance
        local build_time
        build_time=$(benchmark_build_performance "$i")
        total_build_time=$(python3 -c "print($total_build_time + $build_time)")
        
        # Benchmark test performance (only if build succeeded)
        local test_time=0
        if [[ -f "${RESULTS_DIR}/build-${i}.json" ]] && grep -q '"success": true' "${RESULTS_DIR}/build-${i}.json"; then
            test_time=$(benchmark_test_performance "$i")
            total_test_time=$(python3 -c "print($total_test_time + $test_time)")
        fi
        
        # Benchmark artifact performance
        local artifact_time
        artifact_time=$(benchmark_artifact_performance "$i")
        total_artifact_time=$(python3 -c "print($total_artifact_time + $artifact_time)")
        
        # Calculate iteration total
        local iteration_total
        iteration_total=$(python3 -c "print($build_time + $test_time + $artifact_time)")
        
        log_info "Iteration $i completed in $(format_duration "$iteration_total")"
        log_info "  Build: $(format_duration "$build_time")"
        log_info "  Tests: $(format_duration "$test_time")"
        log_info "  Artifacts: $(format_duration "$artifact_time")"
        
        successful_iterations=$((successful_iterations + 1))
    done
    
    # Calculate averages
    local avg_build_time
    avg_build_time=$(python3 -c "print($total_build_time / $successful_iterations)")
    local avg_test_time
    avg_test_time=$(python3 -c "print($total_test_time / $successful_iterations)")
    local avg_artifact_time
    avg_artifact_time=$(python3 -c "print($total_artifact_time / $successful_iterations)")
    local avg_total_time
    avg_total_time=$(python3 -c "print(($total_build_time + $total_test_time + $total_artifact_time) / $successful_iterations)")
    
    # Generate summary report
    cat << EOF > "$summary_file"
{
    "benchmark_id": "$benchmark_id",
    "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')",
    "system_info": $(get_system_info),
    "configuration": {
        "iterations": $ITERATIONS,
        "benchmark_type": "$BENCHMARK_TYPE",
        "cache_enabled": $CACHE_ENABLED,
        "parallel_build": $PARALLEL_BUILD
    },
    "results": {
        "successful_iterations": $successful_iterations,
        "averages": {
            "build_time": $avg_build_time,
            "test_time": $avg_test_time,
            "artifact_time": $avg_artifact_time,
            "total_time": $avg_total_time
        },
        "totals": {
            "build_time": $total_build_time,
            "test_time": $total_test_time,
            "artifact_time": $total_artifact_time,
            "total_time": $(python3 -c "print($total_build_time + $total_test_time + $total_artifact_time)")
        },
        "performance_targets": {
            "build_target": $TARGET_BUILD_TIME,
            "test_target": $TARGET_TEST_TIME,
            "artifact_target": $TARGET_ARTIFACT_TIME,
            "total_target": $TARGET_TOTAL_WORKFLOW
        }
    }
}
EOF
    
    log_success "Benchmark completed successfully"
    log_info "Summary saved to: $(basename "$summary_file")"
    
    # Display results
    display_benchmark_results "$summary_file"
}

# Display benchmark results
display_benchmark_results() {
    local summary_file="$1"
    
    if [[ ! -f "$summary_file" ]]; then
        log_error "Summary file not found: $summary_file"
        return 1
    fi
    
    log_header "Performance Benchmark Results"
    
    # Parse results using Python for JSON handling
    python3 << EOF
import json

with open('$summary_file', 'r') as f:
    data = json.load(f)

results = data['results']
config = data['configuration']
system = data['system_info']

print("\n📊 SYSTEM CONFIGURATION")
print(f"  OS: {system['os']} {system['arch']}")
print(f"  Swift: {system['swift_version']}")
print(f"  CPU Cores: {system['cpu_cores']}")
print(f"  Memory: {system['memory_gb']}GB")
print(f"  Cache: {'Enabled' if config['cache_enabled'] else 'Disabled'}")

print("\n⏱️  AVERAGE PERFORMANCE RESULTS")
def format_time(seconds):
    if seconds < 60:
        return f"{seconds:.1f}s"
    elif seconds < 3600:
        minutes = int(seconds // 60)
        remaining_seconds = seconds % 60
        return f"{minutes}m {remaining_seconds:.1f}s"
    else:
        hours = int(seconds // 3600)
        remaining_minutes = int((seconds % 3600) // 60)
        remaining_seconds = seconds % 60
        return f"{hours}h {remaining_minutes}m {remaining_seconds:.1f}s"

avg = results['averages']
targets = results['performance_targets']

def status_icon(actual, target):
    return "✅" if actual <= target else "⚠️" 

print(f"  Build Time:    {format_time(avg['build_time']):>8} {status_icon(avg['build_time'], targets['build_target'])} (target: {format_time(targets['build_target'])})")
print(f"  Test Time:     {format_time(avg['test_time']):>8} {status_icon(avg['test_time'], targets['test_target'])} (target: {format_time(targets['test_target'])})")
print(f"  Artifact Time: {format_time(avg['artifact_time']):>8} {status_icon(avg['artifact_time'], targets['artifact_target'])} (target: {format_time(targets['artifact_target'])})")
print(f"  Total Time:    {format_time(avg['total_time']):>8} {status_icon(avg['total_time'], targets['total_target'])} (target: {format_time(targets['total_target'])})")

print("\n📈 PERFORMANCE ANALYSIS")
build_pct = (avg['build_time'] / avg['total_time']) * 100
test_pct = (avg['test_time'] / avg['total_time']) * 100
artifact_pct = (avg['artifact_time'] / avg['total_time']) * 100

print(f"  Build Phase:    {build_pct:.1f}% of total time")
print(f"  Test Phase:     {test_pct:.1f}% of total time") 
print(f"  Artifact Phase: {artifact_pct:.1f}% of total time")

print("\n🔧 OPTIMIZATION RECOMMENDATIONS")
if avg['build_time'] > targets['build_target']:
    print("  - Consider enabling distributed build caching")
    print("  - Review build dependencies for optimization opportunities")

if avg['test_time'] > targets['test_target']:
    print("  - Evaluate test parallelization settings")
    print("  - Consider test suite optimization for CI environment")

if avg['total_time'] > targets['total_target']:
    print("  - Overall workflow exceeds target - review all phases")
    print("  - Consider workflow optimization or infrastructure upgrades")

if build_pct > 50:
    print("  - Build phase dominates execution time - focus optimization here")
elif test_pct > 40:
    print("  - Test phase is significant - consider test optimization")

print()
EOF
    
    echo "Full results saved to: $summary_file"
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

# Generate detailed performance report
generate_performance_report() {
    local summary_file="$1"
    local report_file="${RESULTS_DIR}/performance-report-$(date '+%Y%m%d-%H%M%S').md"
    
    log_info "Generating detailed performance report"
    
    if [[ ! -f "$summary_file" ]]; then
        log_error "Summary file not found: $summary_file"
        return 1
    fi
    
    # Generate comprehensive markdown report
    python3 << EOF > "$report_file"
import json
from datetime import datetime

with open('$summary_file', 'r') as f:
    data = json.load(f)

def format_time(seconds):
    if seconds < 60:
        return f"{seconds:.1f}s"
    elif seconds < 3600:
        minutes = int(seconds // 60)
        remaining_seconds = seconds % 60
        return f"{minutes}m {remaining_seconds:.1f}s"
    else:
        hours = int(seconds // 3600)
        remaining_minutes = int((seconds % 3600) // 60)
        remaining_seconds = seconds % 60
        return f"{hours}h {remaining_minutes}m {remaining_seconds:.1f}s"

def status_icon(actual, target):
    return "✅ PASS" if actual <= target else "⚠️ SLOW"

results = data['results']
config = data['configuration']
system = data['system_info']
avg = results['averages']
targets = results['performance_targets']

print(f"# Release Workflow Performance Report")
print()
print(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print(f"**Benchmark ID:** {data['benchmark_id']}")
print()

print("## Executive Summary")
print()
overall_status = "PASS" if avg['total_time'] <= targets['total_target'] else "NEEDS OPTIMIZATION"
print(f"**Overall Performance:** {overall_status}")
print(f"**Total Workflow Time:** {format_time(avg['total_time'])} (target: {format_time(targets['total_target'])})")
print(f"**Iterations Completed:** {results['successful_iterations']}")
print()

print("## System Configuration")
print()
print("| Component | Value |")
print("|-----------|-------|")
print(f"| Operating System | {system['os']} {system['arch']} |")
print(f"| Kernel | {system['kernel']} |")
print(f"| Swift Version | {system['swift_version']} |")
print(f"| Xcode Version | {system['xcode_version']} |")
print(f"| CPU Cores | {system['cpu_cores']} |")
print(f"| Memory | {system['memory_gb']}GB |")
print(f"| Cache Enabled | {config['cache_enabled']} |")
print(f"| Parallel Build | {config['parallel_build']} |")
print()

print("## Performance Results")
print()
print("| Phase | Average Time | Status | Target | Performance |")
print("|-------|--------------|--------|--------|-------------|")
print(f"| Build | {format_time(avg['build_time'])} | {status_icon(avg['build_time'], targets['build_target'])} | {format_time(targets['build_target'])} | {(avg['build_time']/targets['build_target']*100):.1f}% of target |")
print(f"| Test | {format_time(avg['test_time'])} | {status_icon(avg['test_time'], targets['test_target'])} | {format_time(targets['test_target'])} | {(avg['test_time']/targets['test_target']*100):.1f}% of target |")
print(f"| Artifact | {format_time(avg['artifact_time'])} | {status_icon(avg['artifact_time'], targets['artifact_target'])} | {format_time(targets['artifact_target'])} | {(avg['artifact_time']/targets['artifact_target']*100):.1f}% of target |")
print(f"| **Total** | **{format_time(avg['total_time'])}** | **{status_icon(avg['total_time'], targets['total_target'])}** | **{format_time(targets['total_target'])}** | **{(avg['total_time']/targets['total_target']*100):.1f}% of target** |")
print()

print("## Time Distribution")
print()
build_pct = (avg['build_time'] / avg['total_time']) * 100
test_pct = (avg['test_time'] / avg['total_time']) * 100
artifact_pct = (avg['artifact_time'] / avg['total_time']) * 100

print(f"- **Build Phase:** {build_pct:.1f}% ({format_time(avg['build_time'])})")
print(f"- **Test Phase:** {test_pct:.1f}% ({format_time(avg['test_time'])})")
print(f"- **Artifact Phase:** {artifact_pct:.1f}% ({format_time(avg['artifact_time'])})")
print()

print("## Optimization Recommendations")
print()

if avg['total_time'] <= targets['total_target']:
    print("✅ **Overall Performance: EXCELLENT**")
    print("- Workflow meets all performance targets")
    print("- Continue monitoring for performance regressions")
else:
    print("⚠️ **Overall Performance: NEEDS IMPROVEMENT**")

if avg['build_time'] > targets['build_target']:
    print()
    print("### Build Performance Optimization")
    print("- Enable distributed build caching for faster compilation")
    print("- Review build dependencies for unnecessary rebuilds")
    print("- Consider upgrading to faster CI runners")
    print("- Implement incremental build optimizations")

if avg['test_time'] > targets['test_target']:
    print()
    print("### Test Performance Optimization")
    print("- Optimize test parallelization settings")
    print("- Review test suite for long-running tests")
    print("- Consider test environment optimization")
    print("- Implement test result caching where possible")

if avg['artifact_time'] > targets['artifact_target']:
    print()
    print("### Artifact Generation Optimization")
    print("- Review artifact packaging efficiency")
    print("- Optimize binary stripping and compression")
    print("- Consider parallel artifact generation")

if build_pct > 50:
    print()
    print("### Focus Area: Build Optimization")
    print("- Build phase consumes majority of workflow time")
    print("- Prioritize build system optimization efforts")
elif test_pct > 40:
    print()
    print("### Focus Area: Test Optimization")
    print("- Test phase is significant performance factor")
    print("- Focus on test execution efficiency")

print()
print("## Detailed Metrics")
print()
print("### Raw Performance Data")
print()
print("```json")
print(json.dumps(data, indent=2))
print("```")
print()
print("---")
print("*Report generated by benchmark-release-performance.sh*")
EOF
    
    log_success "Detailed performance report generated: $(basename "$report_file")"
    echo "Report saved to: $report_file"
}

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Release Workflow Performance Benchmarking Tool

COMMANDS:
    run                      Run performance benchmark (default)
    report <summary_file>    Generate detailed report from existing benchmark
    clean                    Clean benchmark artifacts and logs
    
OPTIONS:
    --iterations <N>         Number of benchmark iterations (default: 1)
    --type <TYPE>           Benchmark type: quick|full (default: full)
    --format <FORMAT>       Output format: markdown|json (default: markdown)
    --no-cache              Disable build caching for benchmarking
    --no-parallel           Disable parallel build for benchmarking
    --generate-report       Generate detailed report after benchmark
    --verbose               Enable verbose logging
    -h, --help              Show this help message

EXAMPLES:
    $0                                          Run single iteration benchmark
    $0 --iterations 3 --generate-report        Run 3 iterations with report
    $0 --type quick --no-cache                 Quick benchmark without cache
    $0 report results/benchmark-summary.json   Generate report from existing data
    $0 clean                                   Clean benchmark artifacts

ENVIRONMENT VARIABLES:
    BENCHMARK_ITERATIONS    Override default iteration count
    BENCHMARK_VERBOSE       Enable verbose output (true/false)

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            run)
                # Default command, no action needed
                shift
                ;;
            report)
                if [[ -z "${2:-}" ]]; then
                    log_error "report command requires summary file argument"
                    exit $EXIT_USAGE_ERROR
                fi
                generate_performance_report "$2"
                exit $EXIT_SUCCESS
                ;;
            clean)
                log_info "Cleaning benchmark artifacts"
                rm -rf "$BENCHMARK_DIR"
                log_success "Benchmark artifacts cleaned"
                exit $EXIT_SUCCESS
                ;;
            --iterations)
                if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "Invalid iterations value: ${2:-}"
                    exit $EXIT_USAGE_ERROR
                fi
                ITERATIONS="$2"
                shift 2
                ;;
            --type)
                if [[ -z "${2:-}" ]]; then
                    log_error "Type option requires value"
                    exit $EXIT_USAGE_ERROR
                fi
                BENCHMARK_TYPE="$2"
                shift 2
                ;;
            --format)
                if [[ -z "${2:-}" ]]; then
                    log_error "Format option requires value"
                    exit $EXIT_USAGE_ERROR
                fi
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --no-cache)
                CACHE_ENABLED=false
                shift
                ;;
            --no-parallel)
                PARALLEL_BUILD=false
                shift
                ;;
            --generate-report)
                GENERATE_REPORT=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit $EXIT_SUCCESS
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit $EXIT_USAGE_ERROR
                ;;
        esac
    done
}

# Validate dependencies
validate_dependencies() {
    local missing_deps=()
    
    # Check required commands
    for cmd in swift python3 bc; do
        if ! command_exists "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install missing dependencies and try again"
        exit $EXIT_MISSING_DEPS
    fi
    
    # Check Swift package
    if [[ ! -f "$PROJECT_ROOT/Package.swift" ]]; then
        log_error "Package.swift not found in project root: $PROJECT_ROOT"
        exit $EXIT_MISSING_DEPS
    fi
    
    log_verbose "All dependencies validated successfully"
}

# Main function
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Apply environment variable overrides
    ITERATIONS="${BENCHMARK_ITERATIONS:-$ITERATIONS}"
    VERBOSE="${BENCHMARK_VERBOSE:-$VERBOSE}"
    
    # Validate environment
    validate_dependencies
    ensure_benchmark_directories
    
    # Initialize logging
    echo "# Performance Benchmark Log - $(date)" > "$LOG_FILE"
    
    log_header "Release Workflow Performance Benchmark"
    log_info "Project: usbipd-mac"
    log_info "Benchmark Type: $BENCHMARK_TYPE"
    log_info "Iterations: $ITERATIONS"
    log_info "Cache Enabled: $CACHE_ENABLED"
    log_info "Parallel Build: $PARALLEL_BUILD"
    
    # Run benchmark
    local benchmark_start
    benchmark_start=$(get_timestamp)
    
    run_comprehensive_benchmark
    
    local benchmark_end
    benchmark_end=$(get_timestamp)
    local total_benchmark_time
    total_benchmark_time=$(calculate_elapsed "$benchmark_start" "$benchmark_end")
    
    log_success "Benchmark completed in $(format_duration "$total_benchmark_time")"
    
    # Generate report if requested
    if [[ "$GENERATE_REPORT" == "true" ]]; then
        local latest_summary
        latest_summary=$(find "$RESULTS_DIR" -name "*-summary.json" -type f -exec stat -f "%m %N" {} + | sort -nr | head -n1 | cut -d' ' -f2-)
        if [[ -n "$latest_summary" ]]; then
            generate_performance_report "$latest_summary"
        fi
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi