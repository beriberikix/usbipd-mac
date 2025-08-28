#!/bin/bash

# prepare-release.sh
# Release preparation script for usbipd-mac
# Validates environment and prerequisites, checks code quality and tests, creates release tags
# Provides safe local release preparation before triggering automated workflows

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build"
CHANGELOG_FILE="$PROJECT_ROOT/CHANGELOG.md"
PACKAGE_SWIFT="$PROJECT_ROOT/Package.swift"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
DRY_RUN=false
SKIP_TESTS=false
SKIP_LINT=false
FORCE_RELEASE=false
VERSION=""
REMOTE_NAME="origin"
MAIN_BRANCH="main"

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

log_step() {
    echo -e "${BOLD}${BLUE}==>${NC}${BOLD} $1${NC}"
}

# Print script header
print_header() {
    echo "=================================================================="
    echo "🚀 Release Preparation Tool for usbipd-mac"
    echo "=================================================================="
    echo "Version: ${VERSION:-'[auto-detect]'}"
    echo "Dry Run: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")"
    echo "Skip Tests: $([ "$SKIP_TESTS" = true ] && echo "YES" || echo "NO")"
    echo "Skip Lint: $([ "$SKIP_LINT" = true ] && echo "YES" || echo "NO")"
    echo "Force Release: $([ "$FORCE_RELEASE" = true ] && echo "YES" || echo "NO")"
    echo "Working Dir: $PROJECT_ROOT"
    echo "Remote: $REMOTE_NAME"
    echo "Main Branch: $MAIN_BRANCH"
    echo "=================================================================="
    echo ""
}

# Validate prerequisites
validate_prerequisites() {
    log_step "Validating prerequisites"
    
    # Check if we're in the correct directory
    if [ ! -f "$PACKAGE_SWIFT" ]; then
        log_error "Package.swift not found. Please run this script from the project root."
        exit 1
    fi
    
    # Check required tools
    local required_tools=("swift" "git" "swiftlint")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
        log_info "✓ Found: $tool"
    done
    
    # Check Git repository status
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_error "Not inside a Git repository"
        exit 1
    fi
    
    # Check if remote exists
    if ! git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
        log_error "Remote '$REMOTE_NAME' not found"
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Check Git repository status
check_git_status() {
    log_step "Checking Git repository status"
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        if [ "$FORCE_RELEASE" = false ]; then
            log_error "Repository has uncommitted changes. Please commit or stash them first."
            log_info "Use --force to override this check."
            exit 1
        else
            log_warning "Repository has uncommitted changes (continuing due to --force)"
        fi
    fi
    
    # Check current branch
    local current_branch
    current_branch=$(git branch --show-current)
    log_info "Current branch: $current_branch"
    
    # Check if we're on main branch
    if [ "$current_branch" != "$MAIN_BRANCH" ]; then
        if [ "$FORCE_RELEASE" = false ]; then
            log_error "Not on $MAIN_BRANCH branch. Switch to $MAIN_BRANCH before creating a release."
            log_info "Use --force to override this check."
            exit 1
        else
            log_warning "Not on $MAIN_BRANCH branch (continuing due to --force)"
        fi
    fi
    
    # Fetch latest changes from remote
    log_info "Fetching latest changes from $REMOTE_NAME..."
    git fetch "$REMOTE_NAME"
    
    # Check if local branch is up to date with remote
    local local_commit remote_commit
    local_commit=$(git rev-parse HEAD)
    remote_commit=$(git rev-parse "$REMOTE_NAME/$MAIN_BRANCH" 2>/dev/null || echo "")
    
    if [ -n "$remote_commit" ] && [ "$local_commit" != "$remote_commit" ]; then
        if [ "$FORCE_RELEASE" = false ]; then
            log_error "Local branch is not up to date with $REMOTE_NAME/$MAIN_BRANCH"
            log_info "Please pull latest changes or use --force to override."
            exit 1
        else
            log_warning "Local branch not up to date with remote (continuing due to --force)"
        fi
    fi
    
    log_success "Git repository status check completed"
}

# Detect or validate version
detect_version() {
    log_step "Detecting version information"
    
    if [ -n "$VERSION" ]; then
        # Validate provided version format
        if ! [[ "$VERSION" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]; then
            log_error "Invalid version format: $VERSION"
            log_info "Expected format: vX.Y.Z or X.Y.Z (with optional pre-release suffix)"
            exit 1
        fi
        
        # Normalize version (ensure it starts with 'v')
        if [[ ! "$VERSION" =~ ^v ]]; then
            VERSION="v$VERSION"
        fi
        
        log_info "Using provided version: $VERSION"
    else
        # Auto-detect next version based on git tags
        local latest_tag
        latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
        
        log_info "Latest tag: $latest_tag"
        
        # Extract version numbers
        local version_number
        version_number=$(echo "$latest_tag" | sed 's/^v//' | sed 's/-.*$//')
        
        if [[ ! "$version_number" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_warning "Cannot parse latest tag version, defaulting to v0.1.0"
            VERSION="v0.1.0"
        else
            # Increment patch version by default
            local major minor patch
            IFS='.' read -r major minor patch <<< "$version_number"
            patch=$((patch + 1))
            VERSION="v$major.$minor.$patch"
        fi
        
        log_info "Auto-detected next version: $VERSION"
    fi
    
    # Check if tag already exists
    if git rev-parse "$VERSION" >/dev/null 2>&1; then
        if [ "$FORCE_RELEASE" = false ]; then
            log_error "Tag $VERSION already exists"
            log_info "Use --force to override or specify a different version."
            exit 1
        else
            log_warning "Tag $VERSION already exists (continuing due to --force)"
        fi
    fi
    
    log_success "Version detection completed: $VERSION"
}

# Run code quality checks
run_code_quality_checks() {
    if [ "$SKIP_LINT" = true ]; then
        log_step "Skipping code quality checks (--skip-lint specified)"
        return 0
    fi
    
    log_step "Running code quality checks"
    
    # Run SwiftLint
    log_info "Running SwiftLint..."
    if swiftlint lint --strict --config "$PROJECT_ROOT/.swiftlint.yml"; then
        log_success "SwiftLint passed"
    else
        log_error "SwiftLint failed"
        log_info "Fix linting issues before releasing, or use --skip-lint to override."
        exit 1
    fi
    
    log_success "Code quality checks completed"
}

# Build project
build_project() {
    log_step "Building project"
    
    # Clean build directory
    log_info "Cleaning build artifacts..."
    rm -rf "$BUILD_DIR"
    
    # Build in release configuration
    log_info "Building project in release configuration..."
    local start_time
    start_time=$(date +%s)
    
    if swift build --configuration release --build-path "$BUILD_DIR"; then
        local end_time build_time
        end_time=$(date +%s)
        build_time=$((end_time - start_time))
        log_success "Build completed in ${build_time}s"
    else
        log_error "Build failed"
        exit 1
    fi
}

# Run tests
run_tests() {
    if [ "$SKIP_TESTS" = true ]; then
        log_step "Skipping tests (--skip-tests specified)"
        return 0
    fi
    
    log_step "Running test suite"
    
    # Run CI tests (comprehensive but not requiring hardware)
    log_info "Running CI test suite..."
    local start_time
    start_time=$(date +%s)
    
    if "$SCRIPT_DIR/run-ci-tests.sh"; then
        local end_time test_time
        end_time=$(date +%s)
        test_time=$((end_time - start_time))
        log_success "Tests completed in ${test_time}s"
    else
        log_error "Tests failed"
        log_info "Fix test failures before releasing, or use --skip-tests to override."
        exit 1
    fi
}

# Generate or update changelog
update_changelog() {
    log_step "Updating changelog"
    
    # Create changelog if it doesn't exist
    if [ ! -f "$CHANGELOG_FILE" ]; then
        log_info "Creating new CHANGELOG.md..."
        cat > "$CHANGELOG_FILE" << EOF
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [$VERSION] - $(date +%Y-%m-%d)

### Added
- Initial release

EOF
        log_success "Created CHANGELOG.md"
    else
        # Check if version already exists in changelog
        if grep -q "## \[$VERSION\]" "$CHANGELOG_FILE"; then
            log_warning "Version $VERSION already exists in CHANGELOG.md"
        else
            # Add new version entry
            log_info "Adding $VERSION entry to CHANGELOG.md..."
            
            # Create temporary file with new entry
            local temp_file
            temp_file=$(mktemp)
            
            # Add new version entry after [Unreleased]
            awk -v version="$VERSION" -v date="$(date +%Y-%m-%d)" '
                /^## \[Unreleased\]/ {
                    print $0
                    print ""
                    print "## [" version "] - " date
                    print ""
                    print "### Added"
                    print "- New features and improvements"
                    print ""
                    print "### Fixed"
                    print "- Bug fixes and stability improvements"
                    print ""
                    next
                }
                { print }
            ' "$CHANGELOG_FILE" > "$temp_file"
            
            mv "$temp_file" "$CHANGELOG_FILE"
            log_success "Updated CHANGELOG.md"
        fi
    fi
    
    log_info "Please review and edit CHANGELOG.md for $VERSION before continuing."
    
    if [ "$DRY_RUN" = false ] && [ "$FORCE_RELEASE" = false ]; then
        echo -n "Press Enter to continue after reviewing the changelog..."
        read -r
    fi
}

# Create Git tag
create_git_tag() {
    log_step "Creating Git tag"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would create tag $VERSION"
        return 0
    fi
    
    # Add changelog changes if any
    if git diff --quiet "$CHANGELOG_FILE"; then
        log_info "No changelog changes to commit"
    else
        log_info "Committing changelog updates..."
        git add "$CHANGELOG_FILE"
        git commit -m "docs: update CHANGELOG.md for $VERSION"
    fi
    
    # Create annotated tag
    local tag_message="Release $VERSION

$(git log --oneline "$(git describe --tags --abbrev=0 2>/dev/null || echo 'HEAD~10')..HEAD" | head -10)

Generated with release preparation script."
    
    log_info "Creating annotated tag $VERSION..."
    git tag -a "$VERSION" -m "$tag_message"
    
    log_success "Created Git tag: $VERSION"
}

# Validate release readiness
validate_release_readiness() {
    log_step "Validating release readiness"
    
    local validation_issues=()
    
    # Check that version is properly formatted
    if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]; then
        validation_issues+=("Invalid version format: $VERSION")
    fi
    
    # Check that build was successful
    if [ ! -d "$BUILD_DIR" ]; then
        validation_issues+=("Build directory not found - build may have failed")
    fi
    
    # Check that we're on the right branch (unless forced)
    if [ "$FORCE_RELEASE" = false ]; then
        local current_branch
        current_branch=$(git branch --show-current)
        if [ "$current_branch" != "$MAIN_BRANCH" ]; then
            validation_issues+=("Not on $MAIN_BRANCH branch")
        fi
    fi
    
    # Check for uncommitted changes (unless forced)
    if [ "$FORCE_RELEASE" = false ]; then
        if ! git diff-index --quiet HEAD --; then
            validation_issues+=("Repository has uncommitted changes")
        fi
    fi
    
    # Report validation results
    if [ ${#validation_issues[@]} -eq 0 ]; then
        log_success "Release readiness validation passed"
        return 0
    else
        log_error "Release readiness validation failed:"
        for issue in "${validation_issues[@]}"; do
            log_error "  - $issue"
        done
        return 1
    fi
}

# Generate shell completion scripts
generate_completion_scripts() {
    log_step "Generating shell completion scripts"
    
    local completion_script="$SCRIPT_DIR/generate-completions.sh"
    local completions_dir="$PROJECT_ROOT/completions"
    
    # Check if completion generation script exists
    if [ ! -f "$completion_script" ]; then
        log_warning "Completion generation script not found at: $completion_script"
        log_info "Skipping completion generation"
        return 0
    fi
    
    # Remove existing completions directory to ensure fresh generation
    if [ -d "$completions_dir" ]; then
        log_info "Cleaning existing completions directory..."
        rm -rf "$completions_dir"
    fi
    
    # Generate completion scripts
    log_info "Running completion generation..."
    if [ "$DRY_RUN" = true ]; then
        log_info "Dry run: Would generate completion scripts to $completions_dir"
    else
        # Execute completion generation script
        if "$completion_script" --output "$completions_dir" --clean --verbose 2>&1; then
            log_success "Shell completion scripts generated successfully"
            
            # Verify generated files
            local generated_files=()
            if [ -f "$completions_dir/usbipd" ]; then
                generated_files+=("bash: usbipd")
            fi
            if [ -f "$completions_dir/_usbipd" ]; then
                generated_files+=("zsh: _usbipd")
            fi
            if [ -f "$completions_dir/usbipd.fish" ]; then
                generated_files+=("fish: usbipd.fish")
            fi
            
            if [ ${#generated_files[@]} -gt 0 ]; then
                log_info "Generated completion files:"
                for file in "${generated_files[@]}"; do
                    log_info "  ✓ $file"
                done
            else
                log_warning "No completion files found after generation"
            fi
        else
            log_error "Failed to generate shell completion scripts"
            if [ "$FORCE_RELEASE" = false ]; then
                log_error "Use --force to continue without completion scripts"
                exit 1
            else
                log_warning "Continuing without completion scripts due to --force flag"
            fi
        fi
    fi
}

# Generate release summary
generate_release_summary() {
    log_step "Generating release summary"
    
    local summary_file="$BUILD_DIR/release-summary-$VERSION.txt"
    mkdir -p "$(dirname "$summary_file")"
    
    cat > "$summary_file" << EOF
Release Summary for $VERSION
============================
Generated: $(date)
Prepared by: $(git config user.name) <$(git config user.email)>

Project Information:
  Project: usbipd-mac
  Version: $VERSION
  Commit: $(git rev-parse HEAD)
  Branch: $(git branch --show-current)

Release Preparation Status:
  Prerequisites: ✓ Validated
  Git Status: ✓ Checked
  Code Quality: $([ "$SKIP_LINT" = true ] && echo "⚠ Skipped" || echo "✓ Passed")
  Build: ✓ Successful
  Completions: $([ -d "$PROJECT_ROOT/completions" ] && [ "$(ls -A "$PROJECT_ROOT/completions" 2>/dev/null)" ] && echo "✓ Generated" || echo "⚠ Skipped")
  Tests: $([ "$SKIP_TESTS" = true ] && echo "⚠ Skipped" || echo "✓ Passed")
  Changelog: ✓ Updated
  Git Tag: $([ "$DRY_RUN" = true ] && echo "⚠ Dry Run" || echo "✓ Created")

Next Steps:
  1. Push the tag to trigger automated release workflow:
     git push $REMOTE_NAME $VERSION
  
  2. Monitor the GitHub Actions workflow:
     https://github.com/[owner]/usbipd-mac/actions
  
  3. Verify release artifacts and update documentation as needed

Configuration:
  Dry Run: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")
  Skip Tests: $([ "$SKIP_TESTS" = true ] && echo "YES" || echo "NO")
  Skip Lint: $([ "$SKIP_LINT" = true ] && echo "YES" || echo "NO")
  Force Release: $([ "$FORCE_RELEASE" = true ] && echo "YES" || echo "NO")

EOF
    
    log_success "Release summary generated: $(basename "$summary_file")"
    log_info "Summary location: $summary_file"
    
    # Display summary to user
    echo ""
    cat "$summary_file"
    echo ""
}

# Print next steps
print_next_steps() {
    log_step "Next Steps"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}This was a dry run. No changes were made.${NC}"
        echo "To perform the actual release preparation, run without --dry-run:"
        echo "  $0 --version $VERSION"
        echo ""
        return 0
    fi
    
    echo -e "${GREEN}✅ Release preparation completed successfully!${NC}"
    echo ""
    echo "To trigger the automated release workflow:"
    echo -e "  ${BOLD}git push $REMOTE_NAME $VERSION${NC}"
    echo ""
    echo "To monitor the release process:"
    echo "  - GitHub Actions: https://github.com/[owner]/usbipd-mac/actions"
    echo "  - Releases: https://github.com/[owner]/usbipd-mac/releases"
    echo ""
    echo "Additional commands:"
    echo "  - View tag details: git show $VERSION"
    echo "  - List recent tags: git tag -l --sort=-version:refname | head -5"
    echo ""
}

# Print usage information
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Release Preparation Tool for usbipd-mac

Validates environment, runs quality checks, and prepares release tags for automated workflows.

OPTIONS:
  --version VERSION        Specific version to release (e.g., v1.2.3 or 1.2.3)
  --dry-run               Preview actions without making changes
  --skip-tests            Skip test execution (not recommended)
  --skip-lint             Skip code quality checks (not recommended)
  --force                 Override safety checks (use with caution)
  --remote REMOTE         Git remote name (default: origin)
  --main-branch BRANCH    Main branch name (default: main)
  --help                  Show this help message

EXAMPLES:
  $0                           # Auto-detect next version and prepare release
  $0 --version v1.2.3         # Prepare specific version
  $0 --dry-run                # Preview without making changes
  $0 --version v1.3.0 --force # Force release preparation
  $0 --skip-tests --skip-lint # Skip validation steps (not recommended)

ENVIRONMENT VARIABLES:
  VERSION                     Override version detection
  REMOTE_NAME                Override git remote name (default: origin)
  MAIN_BRANCH                Override main branch name (default: main)

This script will:
  1. Validate prerequisites and environment
  2. Check Git repository status and fetch latest changes
  3. Detect or validate version information
  4. Run code quality checks with SwiftLint
  5. Build project in release configuration
  6. Execute comprehensive test suite
  7. Update CHANGELOG.md with new version entry
  8. Create annotated Git tag for the release
  9. Generate release summary and next steps

After successful preparation, push the tag to trigger automated release workflows.

EOF
}

# Error handler
handle_error() {
    local exit_code=$?
    log_error "Release preparation failed with exit code $exit_code"
    
    if [ -f "$BUILD_DIR/release-summary-$VERSION.txt" ]; then
        log_info "Partial release summary available at: $BUILD_DIR/release-summary-$VERSION.txt"
    fi
    
    echo ""
    echo "Common troubleshooting steps:"
    echo "1. Check error messages above for specific issues"
    echo "2. Ensure all prerequisites are installed and up to date"
    echo "3. Verify Git repository is clean and up to date"
    echo "4. Run individual commands manually to isolate the problem"
    echo "5. Use --dry-run to preview actions without making changes"
    echo ""
    
    exit $exit_code
}

# Set up error handling
trap 'handle_error' ERR

# Main execution flow
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                VERSION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --skip-lint)
                SKIP_LINT=true
                shift
                ;;
            --force)
                FORCE_RELEASE=true
                shift
                ;;
            --remote)
                REMOTE_NAME="$2"
                shift 2
                ;;
            --main-branch)
                MAIN_BRANCH="$2"
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
    
    # Override from environment variables if set
    VERSION="${VERSION:-}"
    REMOTE_NAME="${REMOTE_NAME:-$REMOTE_NAME}"
    MAIN_BRANCH="${MAIN_BRANCH:-$MAIN_BRANCH}"
    
    # Start release preparation
    print_header
    
    # Execute release preparation steps
    validate_prerequisites
    check_git_status
    detect_version
    run_code_quality_checks
    build_project
    generate_completion_scripts
    run_tests
    update_changelog
    validate_release_readiness
    create_git_tag
    generate_release_summary
    print_next_steps
    
    log_success "🎉 Release preparation completed!"
}

# Change to project root directory
cd "$PROJECT_ROOT"

# Run main function with all arguments
main "$@"