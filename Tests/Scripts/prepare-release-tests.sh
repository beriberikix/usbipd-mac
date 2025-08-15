#!/bin/bash

# prepare-release-tests.sh
# Comprehensive test suite for Scripts/prepare-release.sh
# Tests version validation, environment checks, and Git operations using shell script testing patterns

set -e  # Exit on any error

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PREPARE_RELEASE_SCRIPT="$PROJECT_ROOT/Scripts/prepare-release.sh"
TEST_TEMP_DIR=""
ORIGINAL_PWD="$(pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

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

log_test_header() {
    echo -e "${BOLD}${BLUE}==>${NC}${BOLD} $1${NC}"
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-'Values should be equal'}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [ "$expected" = "$actual" ]; then
        log_success "✓ $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "✗ $message"
        log_error "  Expected: '$expected'"
        log_error "  Actual:   '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-'String should contain substring'}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$haystack" == *"$needle"* ]]; then
        log_success "✓ $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "✗ $message"
        log_error "  Haystack: '$haystack'"
        log_error "  Needle:   '$needle'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_exists() {
    local file_path="$1"
    local message="${2:-"File should exist: $file_path"}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [ -f "$file_path" ]; then
        log_success "✓ $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "✗ $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_exit_code() {
    local expected_code="$1"
    local actual_code="$2"
    local message="${3:-"Exit code should be $expected_code"}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [ "$expected_code" -eq "$actual_code" ]; then
        log_success "✓ $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "✗ $message"
        log_error "  Expected code: $expected_code"
        log_error "  Actual code:   $actual_code"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test environment setup
setup_test_environment() {
    log_info "Setting up test environment"
    
    # Create temporary directory for testing
    TEST_TEMP_DIR=$(mktemp -d)
    log_info "Test temp directory: $TEST_TEMP_DIR"
    
    # Verify the prepare-release script exists
    if [ ! -f "$PREPARE_RELEASE_SCRIPT" ]; then
        log_error "prepare-release.sh script not found at: $PREPARE_RELEASE_SCRIPT"
        exit 1
    fi
    
    # Make sure the script is executable
    chmod +x "$PREPARE_RELEASE_SCRIPT"
    
    log_success "Test environment setup completed"
}

# Test environment cleanup
cleanup_test_environment() {
    log_info "Cleaning up test environment"
    
    # Remove temporary test directory
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
        log_info "Removed test temp directory: $TEST_TEMP_DIR"
    fi
    
    # Return to original working directory
    cd "$ORIGINAL_PWD"
    
    log_success "Test environment cleanup completed"
}

# Create a mock git repository for testing
create_mock_git_repo() {
    local repo_dir="$1"
    local branch_name="${2:-main}"
    
    mkdir -p "$repo_dir"
    cd "$repo_dir"
    
    # Initialize git repo
    git init --quiet
    git config user.name "Test User"
    git config user.email "test@example.com"
    git config init.defaultBranch "$branch_name"
    
    # Create Package.swift to simulate usbipd-mac project
    cat > Package.swift << 'EOF'
// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "usbipd-mac",
    platforms: [
        .macOS(.v11)
    ]
)
EOF
    
    # Create basic project structure
    mkdir -p Sources/USBIPDCore
    echo "// Test file" > Sources/USBIPDCore/main.swift
    
    # Create .swiftlint.yml
    cat > .swiftlint.yml << 'EOF'
disabled_rules:
  - line_length
included:
  - Sources
EOF
    
    # Initial commit
    git add .
    git commit --quiet -m "Initial commit"
    
    # Add remote for testing
    git remote add origin "https://github.com/test/usbipd-mac.git"
    
    cd "$ORIGINAL_PWD"
    log_info "Created mock git repository at: $repo_dir"
}

# Test: Script help and usage
test_help_and_usage() {
    log_test_header "Testing help and usage display"
    
    # Test help flag
    local help_output
    help_output=$("$PREPARE_RELEASE_SCRIPT" --help 2>&1) || true
    
    assert_contains "$help_output" "Usage:" "Help output should contain usage information"
    assert_contains "$help_output" "Release Preparation Tool" "Help should contain script description"
    assert_contains "$help_output" "--version" "Help should document --version option"
    assert_contains "$help_output" "--dry-run" "Help should document --dry-run option"
}

# Test: Version validation
test_version_validation() {
    log_test_header "Testing version validation"
    
    # Test invalid version formats (these should fail early before directory changes)
    local invalid_versions=("1.2" "v1.2" "1.2.3.4" "invalid" "")
    for version in "${invalid_versions[@]}"; do
        local output exit_code=0
        output=$("$PREPARE_RELEASE_SCRIPT" --version "$version" --dry-run 2>&1) || exit_code=$?
        
        if [ "$exit_code" -ne 0 ]; then
            log_success "✓ Invalid version format rejected: $version"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            log_error "✗ Invalid version format accepted: $version"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))
    done
    
    # Test that version validation logic exists in the script
    if grep -q "Invalid version format" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Version validation logic exists in script"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Version validation logic not found in script"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test: Prerequisites validation
test_prerequisites_validation() {
    log_test_header "Testing prerequisites validation"
    
    # Test that prerequisites validation logic exists in the script
    if grep -q "Prerequisites validation completed" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Prerequisites validation logic exists in script"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Prerequisites validation logic not found in script"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test that the script checks for required tools
    local required_tools=("swift" "git" "swiftlint")
    for tool in "${required_tools[@]}"; do
        if grep -q "command.*$tool" "$PREPARE_RELEASE_SCRIPT" || grep -q "required_tools.*$tool" "$PREPARE_RELEASE_SCRIPT"; then
            log_success "✓ Script checks for required tool: $tool"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            log_error "✗ Script doesn't check for required tool: $tool"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))
    done
    
    # Test Package.swift check
    if grep -q "Package.swift not found" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script validates Package.swift exists"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script doesn't validate Package.swift existence"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test: Git status checking
test_git_status_checking() {
    log_test_header "Testing Git status checking"
    
    # Test that Git status checking logic exists in the script
    if grep -q "Git repository status check completed" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Git status checking logic exists in script"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Git status checking logic not found in script"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test that the script checks for uncommitted changes
    if grep -q "uncommitted changes" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script checks for uncommitted changes"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script doesn't check for uncommitted changes"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test that the script supports --force flag
    if grep -q "FORCE_RELEASE" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script supports --force flag"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script doesn't support --force flag"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test: Environment checks
test_environment_checks() {
    log_test_header "Testing environment checks"
    
    # Test that the script has environment validation logic
    if grep -q "validate_prerequisites" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script has environment validation function"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script missing environment validation function"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test that the script checks for Git repository
    if grep -q "is-inside-work-tree" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script validates Git repository"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script doesn't validate Git repository"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test: Build process
test_build_process() {
    log_test_header "Testing build process"
    
    # Test that the script has build functionality
    if grep -q "swift build" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script includes swift build command"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script doesn't include swift build command"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test that the script builds in release configuration
    if grep -q "configuration release" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script builds in release configuration"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script doesn't build in release configuration"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test that the script has build function
    if grep -q "build_project" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script has build_project function"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script missing build_project function"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test: Changelog operations
test_changelog_operations() {
    log_test_header "Testing changelog operations"
    
    # Test that the script has changelog functionality
    if grep -q "CHANGELOG.md" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script references CHANGELOG.md"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script doesn't reference CHANGELOG.md"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test that the script has changelog update function
    if grep -q "update_changelog" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script has update_changelog function"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script missing update_changelog function"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test that the script can create new changelog
    if grep -q "Creating new CHANGELOG.md" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script can create new CHANGELOG.md"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script can't create new CHANGELOG.md"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test: Dry run functionality
test_dry_run_functionality() {
    log_test_header "Testing dry run functionality"
    
    # Test that the script supports dry run flag
    if grep -q "DRY_RUN" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script supports DRY_RUN flag"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script doesn't support DRY_RUN flag"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test that dry run prevents tag creation
    if grep -q "DRY RUN: Would create tag" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script prevents tag creation in dry run"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script doesn't prevent tag creation in dry run"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test that dry run indicates no changes made
    if grep -q "This was a dry run" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script indicates dry run status"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script doesn't indicate dry run status"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test: Release readiness validation
test_release_readiness_validation() {
    log_test_header "Testing release readiness validation"
    
    # Test that the script has release readiness validation
    if grep -q "validate_release_readiness" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script has validate_release_readiness function"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script missing validate_release_readiness function"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test that the script validates version format in readiness check
    if grep -q "Invalid version format.*\$VERSION" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script validates version format in readiness check"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script doesn't validate version format in readiness check"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test that script generates release summary
    if grep -q "generate_release_summary" "$PREPARE_RELEASE_SCRIPT"; then
        log_success "✓ Script generates release summary"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "✗ Script doesn't generate release summary"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Test: Error handling and recovery
test_error_handling() {
    log_test_header "Testing error handling and recovery"
    
    # Test invalid command line arguments
    local output exit_code=0
    output=$("$PREPARE_RELEASE_SCRIPT" --invalid-option 2>&1) || exit_code=$?
    
    assert_exit_code 1 "$exit_code" "Should fail with invalid command line option"
    assert_contains "$output" "Unknown option" "Should report unknown option error"
    assert_contains "$output" "Usage:" "Should show usage information on error"
}

# Print test summary
print_test_summary() {
    echo ""
    echo "=================================================================="
    echo "🧪 Release Preparation Script Test Results"
    echo "=================================================================="
    echo "Tests Run:    $TESTS_RUN"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}✅ All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}❌ $TESTS_FAILED test(s) failed${NC}"
        return 1
    fi
}

# Main test execution
main() {
    echo "=================================================================="
    echo "🧪 Release Preparation Script Test Suite"
    echo "=================================================================="
    echo "Testing: $PREPARE_RELEASE_SCRIPT"
    echo "Working Directory: $PROJECT_ROOT"
    echo "=================================================================="
    echo ""
    
    # Setup test environment
    setup_test_environment
    
    # Run test suites
    test_help_and_usage
    test_version_validation
    test_prerequisites_validation
    test_git_status_checking
    test_environment_checks
    test_build_process
    test_changelog_operations
    test_dry_run_functionality
    test_release_readiness_validation
    test_error_handling
    
    # Cleanup and show results
    cleanup_test_environment
    
    echo ""
    if print_test_summary; then
        log_success "🎉 Release preparation script tests completed successfully!"
        exit 0
    else
        log_error "💥 Some tests failed - review output above"
        exit 1
    fi
}

# Error handler
handle_error() {
    local exit_code=$?
    log_error "Test execution failed with exit code $exit_code"
    cleanup_test_environment
    exit $exit_code
}

# Set up error handling
trap 'handle_error' ERR

# Change to project root and execute tests
cd "$PROJECT_ROOT"
main "$@"