#!/bin/bash

# update-changelog.sh
# Automated changelog generation and version management for usbipd-mac
# Generates CHANGELOG.md from Git commit history using conventional commits
# Validates semantic versioning and generates release notes

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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
VERSION=""
RELEASE_DATE=""
OUTPUT_FILE=""
FROM_TAG=""
TO_TAG="HEAD"
INCLUDE_UNRELEASED=true
VALIDATE_VERSION=true

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

log_header() {
    echo -e "${BOLD}${BLUE}=== $1 ===${NC}"
}

# Help function
show_help() {
    cat << EOF
usage: $0 [options] [version]

Automated changelog generation and version management for usbipd-mac.

Arguments:
  version                Version to generate changelog for (e.g., v1.2.3)

Options:
  -h, --help            Show this help message
  -n, --dry-run         Preview changes without modifying files
  -o, --output FILE     Output changelog to specific file
  -f, --from TAG        Start changelog from specific tag (default: latest tag)
  -t, --to TAG          End changelog at specific tag (default: HEAD)
  --no-unreleased       Exclude unreleased changes section
  --skip-validation     Skip semantic version validation
  --release-date DATE   Use specific release date (default: today)

Examples:
  $0 v1.2.3             Generate changelog for version 1.2.3
  $0 --dry-run          Preview changelog generation
  $0 --from v1.1.0      Generate changelog from v1.1.0 to HEAD
  $0 --output notes.md  Output to custom file

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -f|--from)
            FROM_TAG="$2"
            shift 2
            ;;
        -t|--to)
            TO_TAG="$2"
            shift 2
            ;;
        --no-unreleased)
            INCLUDE_UNRELEASED=false
            shift
            ;;
        --skip-validation)
            VALIDATE_VERSION=false
            shift
            ;;
        --release-date)
            RELEASE_DATE="$2"
            shift 2
            ;;
        -*)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            if [[ -z "$VERSION" ]]; then
                VERSION="$1"
            else
                log_error "Multiple versions specified: $VERSION and $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Set default values
if [[ -z "$OUTPUT_FILE" ]]; then
    OUTPUT_FILE="$CHANGELOG_FILE"
fi

if [[ -z "$RELEASE_DATE" ]]; then
    RELEASE_DATE=$(date +"%Y-%m-%d")
fi

# Validate semantic version format
validate_semantic_version() {
    local version=$1
    
    # Remove 'v' prefix if present
    version=${version#v}
    
    # Semantic version regex: MAJOR.MINOR.PATCH with optional pre-release and build metadata
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]; then
        log_error "Invalid semantic version: $version"
        log_error "Expected format: MAJOR.MINOR.PATCH (e.g., 1.2.3, 1.0.0-beta.1, 2.1.0+build.123)"
        return 1
    fi
    
    return 0
}

# Get latest Git tag
get_latest_tag() {
    git describe --tags --abbrev=0 2>/dev/null || echo ""
}

# Parse conventional commit message
parse_commit() {
    local commit_msg="$1"
    local commit_hash="$2"
    
    # Extract type and scope from conventional commit
    local type=""
    local scope=""
    local breaking=""
    local description="$commit_msg"
    
    # Parse conventional commit using pattern matching
    if [[ "$commit_msg" == *": "* ]]; then
        local prefix="${commit_msg%%: *}"
        description="${commit_msg#*: }"
        
        # Check for breaking change
        if [[ "$prefix" == *"!" ]]; then
            breaking="!"
            prefix="${prefix%!}"
        fi
        
        # Extract type and scope
        if [[ "$prefix" == *"("* ]]; then
            type="${prefix%%(*}"
            scope="${prefix#*(}"
            scope="${scope%)}"
        else
            type="$prefix"
        fi
        
        # Categorize commit type
        case "$type" in
            feat)
                echo "### ✨ Features"
                ;;
            fix)
                echo "### 🐛 Bug Fixes"
                ;;
            docs)
                echo "### 📚 Documentation"
                ;;
            style)
                echo "### 🎨 Code Style"
                ;;
            refactor)
                echo "### ♻️ Code Refactoring"
                ;;
            test)
                echo "### ✅ Tests"
                ;;
            chore)
                echo "### 🔧 Maintenance"
                ;;
            ci)
                echo "### 👷 CI/CD"
                ;;
            perf)
                echo "### ⚡ Performance"
                ;;
            build)
                echo "### 📦 Build System"
                ;;
            revert)
                echo "### ⏪ Reverts"
                ;;
            *)
                echo "### 🔄 Other Changes"
                ;;
        esac
        
        # Format the entry
        local entry="- "
        if [[ -n "$scope" ]]; then
            entry+="**${scope}**: "
        fi
        entry+="$description"
        if [[ -n "$breaking" ]]; then
            entry+=" ⚠️ **BREAKING CHANGE**"
        fi
        entry+=" ([${commit_hash:0:7}](https://github.com/usbipd-win/usbipd-mac/commit/$commit_hash))"
        
        echo "$entry"
    else
        # Non-conventional commit
        echo "### 🔄 Other Changes"
        echo "- $commit_msg ([${commit_hash:0:7}](https://github.com/usbipd-win/usbipd-mac/commit/$commit_hash))"
    fi
}

# Generate changelog section
generate_changelog_section() {
    local from_ref="$1"
    local to_ref="$2"
    local section_title="$3"
    
    log_info "Generating changelog section: $section_title"
    
    # Get commit range
    local git_range
    if [[ -n "$from_ref" ]]; then
        git_range="${from_ref}..${to_ref}"
    else
        git_range="$to_ref"
    fi
    
    # Check if there are commits in range
    if ! git rev-list --count "$git_range" >/dev/null 2>&1; then
        log_warning "No commits found in range: $git_range"
        return 0
    fi
    
    local commit_count
    commit_count=$(git rev-list --count "$git_range" 2>/dev/null || echo "0")
    
    if [[ "$commit_count" == "0" ]]; then
        log_info "No commits found for section: $section_title"
        return 0
    fi
    
    log_info "Found $commit_count commits for section: $section_title"
    
    # Generate section header
    echo ""
    echo "## $section_title"
    echo ""
    
    # Create temporary files for each category
    local temp_dir=$(mktemp -d)
    
    # Process commits and categorize them
    while IFS= read -r line; do
        local hash=$(echo "$line" | cut -d' ' -f1)
        local msg=$(echo "$line" | cut -d' ' -f2-)
        
        local parsed_output
        parsed_output=$(parse_commit "$msg" "$hash")
        
        local category=$(echo "$parsed_output" | head -n1)
        local entry=$(echo "$parsed_output" | tail -n1)
        
        # Create safe filename from category
        local category_file
        case "$category" in
            "### ✨ Features")
                category_file="features"
                ;;
            "### 🐛 Bug Fixes")
                category_file="bugfixes"
                ;;
            "### 📚 Documentation")
                category_file="documentation"
                ;;
            "### ✅ Tests")
                category_file="tests"
                ;;
            "### 🎨 Code Style")
                category_file="codestyle"
                ;;
            "### ♻️ Code Refactoring")
                category_file="coderefactoring"
                ;;
            "### 👷 CI/CD")
                category_file="cicd"
                ;;
            "### ⚡ Performance")
                category_file="performance"
                ;;
            "### 📦 Build System")
                category_file="buildsystem"
                ;;
            "### ⏪ Reverts")
                category_file="reverts"
                ;;
            "### 🔧 Maintenance")
                category_file="maintenance"
                ;;
            *)
                category_file="otherchanges"
                ;;
        esac
        echo "$entry" >> "$temp_dir/$category_file"
        
    done < <(git log --reverse --pretty=format:"%H %s" "$git_range" 2>/dev/null)
    
    # Output categories in a specific order
    local ordered_categories=(
        "breaking:### ⚠️ Breaking Changes"
        "features:### ✨ Features" 
        "bugfixes:### 🐛 Bug Fixes"
        "performance:### ⚡ Performance"
        "documentation:### 📚 Documentation"
        "tests:### ✅ Tests"
        "cicd:### 👷 CI/CD"
        "coderefactoring:### ♻️ Code Refactoring"
        "codestyle:### 🎨 Code Style"
        "buildsystem:### 📦 Build System"
        "maintenance:### 🔧 Maintenance"
        "reverts:### ⏪ Reverts"
        "otherchanges:### 🔄 Other Changes"
    )
    
    for category_spec in "${ordered_categories[@]}"; do
        local category_file="${category_spec%%:*}"
        local category_title="${category_spec#*:}"
        
        if [[ -f "$temp_dir/$category_file" ]]; then
            echo "$category_title"
            echo ""
            cat "$temp_dir/$category_file"
            echo ""
        fi
    done
    
    # Cleanup
    rm -rf "$temp_dir"
}

# Generate full changelog
generate_changelog() {
    log_header "Generating Changelog"
    
    # Create temporary file for new changelog
    local temp_changelog
    temp_changelog=$(mktemp)
    
    # Changelog header
    cat > "$temp_changelog" << EOF
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

EOF
    
    # Generate unreleased section if requested
    if [[ "$INCLUDE_UNRELEASED" == "true" ]]; then
        local latest_tag
        latest_tag=$(get_latest_tag)
        
        if [[ -n "$latest_tag" ]]; then
            generate_changelog_section "$latest_tag" "HEAD" "[Unreleased]" >> "$temp_changelog"
        else
            generate_changelog_section "" "HEAD" "[Unreleased]" >> "$temp_changelog"
        fi
    fi
    
    # Generate version section if version is specified
    if [[ -n "$VERSION" ]]; then
        local from_ref="$FROM_TAG"
        if [[ -z "$from_ref" ]]; then
            from_ref=$(get_latest_tag)
        fi
        
        generate_changelog_section "$from_ref" "$TO_TAG" "[$VERSION] - $RELEASE_DATE" >> "$temp_changelog"
    fi
    
    # Add existing changelog content if it exists
    if [[ -f "$CHANGELOG_FILE" && "$OUTPUT_FILE" == "$CHANGELOG_FILE" ]]; then
        # Extract existing versions (skip header and unreleased)
        if grep -q "^## \[" "$CHANGELOG_FILE"; then
            echo "" >> "$temp_changelog"
            sed -n '/^## \[[0-9]/,$p' "$CHANGELOG_FILE" >> "$temp_changelog"
        fi
    fi
    
    # Show preview or write file
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Changelog preview:"
        echo ""
        cat "$temp_changelog"
    else
        mv "$temp_changelog" "$OUTPUT_FILE"
        log_success "Changelog written to: $OUTPUT_FILE"
    fi
    
    rm -f "$temp_changelog"
}

# Generate release notes
generate_release_notes() {
    local version="$1"
    local notes_file="$PROJECT_ROOT/release-notes-${version#v}.md"
    
    log_info "Generating release notes for $version"
    
    local from_ref="$FROM_TAG"
    if [[ -z "$from_ref" ]]; then
        from_ref=$(get_latest_tag)
    fi
    
    cat > "$notes_file" << EOF
# Release Notes - $version

Released on $RELEASE_DATE

EOF
    
    generate_changelog_section "$from_ref" "$TO_TAG" "Changes in $version" >> "$notes_file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Release notes preview:"
        echo ""
        cat "$notes_file"
        rm -f "$notes_file"
    else
        log_success "Release notes written to: $notes_file"
    fi
}

# Validate Git repository
validate_git_repo() {
    log_info "Validating Git repository"
    
    # Check if we're in a Git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not in a Git repository"
        exit 1
    fi
    
    # Check for uncommitted changes
    if [[ -n "$(git status --porcelain)" ]]; then
        log_warning "Working directory has uncommitted changes"
        if [[ "$DRY_RUN" == "false" ]]; then
            log_error "Please commit or stash changes before updating changelog"
            exit 1
        fi
    fi
    
    log_success "Git repository validation passed"
}

# Main execution
main() {
    cd "$PROJECT_ROOT"
    
    log_header "Changelog Generation for usbipd-mac"
    log_info "Project root: $PROJECT_ROOT"
    log_info "Output file: $OUTPUT_FILE"
    
    # Validate version if provided
    if [[ -n "$VERSION" && "$VALIDATE_VERSION" == "true" ]]; then
        log_info "Validating version: $VERSION"
        validate_semantic_version "$VERSION"
        log_success "Version validation passed"
    fi
    
    # Validate Git repository
    validate_git_repo
    
    # Auto-detect FROM_TAG if not specified
    if [[ -z "$FROM_TAG" && -n "$VERSION" ]]; then
        FROM_TAG=$(get_latest_tag)
        if [[ -n "$FROM_TAG" ]]; then
            log_info "Using latest tag as base: $FROM_TAG"
        else
            log_info "No previous tags found, generating changelog from repository start"
        fi
    fi
    
    # Generate changelog
    generate_changelog
    
    # Generate release notes if version specified
    if [[ -n "$VERSION" ]]; then
        generate_release_notes "$VERSION"
    fi
    
    log_success "Changelog generation completed successfully"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "This was a dry run. No files were modified."
    fi
}

# Error handling
trap 'log_error "Script failed on line $LINENO"' ERR

# Run main function
main "$@"