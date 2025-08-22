#!/bin/bash

# generate-homebrew-metadata.sh
# Homebrew metadata generation script for usbipd-mac external tap integration
# Generates structured metadata JSON for tap repository consumption
# Designed for integration with release automation workflows

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly OUTPUT_DIR="$PROJECT_ROOT/.build/homebrew-metadata"
readonly OUTPUT_FILE="$OUTPUT_DIR/homebrew-metadata.json"
readonly LOG_FILE="$OUTPUT_DIR/metadata-generation.log"

# Color output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Configuration variables
VERSION=""
SHA256_CHECKSUM=""
ARCHIVE_URL=""
BINARY_URL=""
RELEASE_NOTES=""
DRY_RUN=false
FORCE_OVERWRITE=false
VALIDATE_INPUTS=true

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_VALIDATION_FAILED=1
readonly EXIT_GENERATION_FAILED=2
readonly EXIT_USAGE_ERROR=3
readonly EXIT_NETWORK_FAILED=4
readonly EXIT_JSON_FAILED=5

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    [ -d "$(dirname "$LOG_FILE")" ] && echo -e "${BLUE}[INFO]${NC} $1" >> "$LOG_FILE" || true
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    [ -d "$(dirname "$LOG_FILE")" ] && echo -e "${GREEN}[SUCCESS]${NC} $1" >> "$LOG_FILE" || true
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    [ -d "$(dirname "$LOG_FILE")" ] && echo -e "${YELLOW}[WARNING]${NC} $1" >> "$LOG_FILE" || true
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    [ -d "$(dirname "$LOG_FILE")" ] && echo -e "${RED}[ERROR]${NC} $1" >> "$LOG_FILE" || true
}

log_step() {
    echo -e "${BOLD}${BLUE}==>${NC}${BOLD} $1${NC}"
    [ -d "$(dirname "$LOG_FILE")" ] && echo -e "${BOLD}${BLUE}==>${NC}${BOLD} $1${NC}" >> "$LOG_FILE" || true
}

# Print script header
print_header() {
    echo "=================================================================="
    echo "🏺 Homebrew Metadata Generation for usbipd-mac"
    echo "=================================================================="
    echo "Version: ${VERSION:-'[required]'}"
    echo "Checksum: ${SHA256_CHECKSUM:-'[auto-calculate]'}"
    echo "Archive URL: ${ARCHIVE_URL:-'[auto-detect]'}"
    echo "Binary URL: ${BINARY_URL:-'[auto-detect]'}"
    echo "Release Notes: ${RELEASE_NOTES:-'[auto-extract]'}"
    echo "Output File: $OUTPUT_FILE"
    echo "Dry Run: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")"
    echo "Force Overwrite: $([ "$FORCE_OVERWRITE" = true ] && echo "YES" || echo "NO")"
    echo "Validate Inputs: $([ "$VALIDATE_INPUTS" = true ] && echo "YES" || echo "NO")"
    echo "=================================================================="
    echo ""
}

# Setup environment
setup_environment() {
    log_step "Setting up metadata generation environment"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    echo "=== Homebrew Metadata Generation Log Started at $(date) ===" > "$LOG_FILE"
    
    # Check if output file exists
    if [ -f "$OUTPUT_FILE" ] && [ "$FORCE_OVERWRITE" = false ]; then
        log_error "Output file already exists: $OUTPUT_FILE"
        log_error "Use --force to overwrite or remove the file manually"
        exit $EXIT_GENERATION_FAILED
    fi
    
    log_success "Environment setup completed"
}

# Validate prerequisites
validate_prerequisites() {
    log_step "Validating prerequisites"
    
    local required_tools=("git" "curl" "shasum" "jq")
    local missing_required=()
    
    # Check required tools
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_info "✓ Found required tool: $tool"
        else
            missing_required+=("$tool")
            log_error "✗ Missing required tool: $tool"
        fi
    done
    
    # Exit if required tools are missing
    if [ ${#missing_required[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_required[*]}"
        log_error "Please install: brew install jq curl git coreutils"
        exit $EXIT_VALIDATION_FAILED
    fi
    
    # Check Git repository status
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_error "Not inside a Git repository"
        exit $EXIT_VALIDATION_FAILED
    fi
    
    log_success "Prerequisites validation completed"
}

# Validate version format and Git tag
validate_version() {
    if [ "$VALIDATE_INPUTS" = false ]; then
        log_step "Skipping version validation (--skip-validation specified)"
        return 0
    fi
    
    log_step "Validating version information"
    
    if [ -z "$VERSION" ]; then
        log_error "Version is required"
        exit $EXIT_USAGE_ERROR
    fi
    
    # Normalize version format (ensure it starts with 'v')
    if [[ ! "$VERSION" =~ ^v ]]; then
        VERSION="v$VERSION"
        log_info "Normalized version to: $VERSION"
    fi
    
    # Validate version format
    if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]; then
        log_error "Invalid version format: $VERSION"
        log_error "Expected format: vX.Y.Z or vX.Y.Z-suffix"
        exit $EXIT_VALIDATION_FAILED
    fi
    
    # Validate that Git tag exists
    if git rev-parse "$VERSION" >/dev/null 2>&1; then
        log_success "✓ Git tag $VERSION exists"
        
        # Get commit hash for tag
        local tag_commit
        tag_commit=$(git rev-parse "$VERSION")
        log_info "Tag commit: $tag_commit"
    else
        log_error "Git tag $VERSION does not exist"
        log_error "Create the tag first or use --skip-validation to override"
        exit $EXIT_VALIDATION_FAILED
    fi
    
    log_success "Version validation completed: $VERSION"
}

# Generate archive and binary URLs from version
generate_urls() {
    log_step "Generating archive and binary URLs"
    
    if [ -n "$ARCHIVE_URL" ] && [ -n "$BINARY_URL" ]; then
        log_info "Using provided archive URL: $ARCHIVE_URL"
        log_info "Using provided binary URL: $BINARY_URL"
        return 0
    fi
    
    # Auto-generate GitHub archive URL
    local repo_url
    repo_url=$(git remote get-url origin 2>/dev/null || echo "")
    
    if [ -n "$repo_url" ]; then
        # Convert Git URL to GitHub archive URL
        # Handle both SSH and HTTPS URLs
        if [[ "$repo_url" =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
            local owner="${BASH_REMATCH[1]}"
            local repo="${BASH_REMATCH[2]%.git}"
            ARCHIVE_URL="https://github.com/$owner/$repo/archive/$VERSION.tar.gz"
            BINARY_URL="https://github.com/$owner/$repo/releases/download/$VERSION/usbipd-$VERSION-macos"
            log_success "Generated archive URL: $ARCHIVE_URL"
            log_success "Generated binary URL: $BINARY_URL"
        else
            log_error "Cannot determine GitHub repository from remote URL: $repo_url"
            exit $EXIT_VALIDATION_FAILED
        fi
    else
        log_error "Cannot determine Git remote URL"
        exit $EXIT_VALIDATION_FAILED
    fi
}

# Calculate SHA256 checksum for binary
calculate_checksum() {
    log_step "Calculating SHA256 checksum for binary"
    
    if [ -n "$SHA256_CHECKSUM" ]; then
        log_info "Using provided SHA256 checksum: $SHA256_CHECKSUM"
        return 0
    fi
    
    if [ -z "$BINARY_URL" ]; then
        log_error "Binary URL is required for checksum calculation"
        exit $EXIT_VALIDATION_FAILED
    fi
    
    log_info "Downloading binary for checksum calculation..."
    log_info "URL: $BINARY_URL"
    
    local temp_file
    temp_file=$(mktemp)
    
    # Download binary with progress
    if curl -L -f -o "$temp_file" "$BINARY_URL"; then
        log_success "Binary downloaded successfully"
        
        # Calculate SHA256 checksum
        SHA256_CHECKSUM=$(shasum -a 256 "$temp_file" | cut -d' ' -f1)
        log_success "SHA256 checksum calculated: $SHA256_CHECKSUM"
        
        # Verify checksum format
        if [[ ! "$SHA256_CHECKSUM" =~ ^[a-fA-F0-9]{64}$ ]]; then
            log_error "Invalid SHA256 checksum format: $SHA256_CHECKSUM"
            exit $EXIT_VALIDATION_FAILED
        fi
        
        # Clean up
        rm -f "$temp_file"
    else
        log_error "Failed to download binary from: $BINARY_URL"
        log_error "Please verify the binary URL is accessible and the release exists"
        rm -f "$temp_file"
        exit $EXIT_NETWORK_FAILED
    fi
}

# Extract release notes from Git tag or changelog
extract_release_notes() {
    log_step "Extracting release notes"
    
    if [ -n "$RELEASE_NOTES" ]; then
        log_info "Using provided release notes"
        return 0
    fi
    
    # Try to get release notes from Git tag annotation
    local tag_message
    if tag_message=$(git tag -l --format='%(contents)' "$VERSION" 2>/dev/null); then
        if [ -n "$tag_message" ]; then
            RELEASE_NOTES="$tag_message"
            log_success "Release notes extracted from Git tag annotation"
            return 0
        fi
    fi
    
    # Try to extract from CHANGELOG.md or similar files
    local changelog_files=("CHANGELOG.md" "CHANGES.md" "HISTORY.md" "NEWS.md")
    for changelog_file in "${changelog_files[@]}"; do
        if [ -f "$PROJECT_ROOT/$changelog_file" ]; then
            log_info "Searching for release notes in $changelog_file..."
            
            # Extract section for this version
            local version_clean="${VERSION#v}"
            local section
            if section=$(awk "/^## \[?$version_clean\]?|^# \[?$version_clean\]?|^$version_clean/{flag=1; next} /^## |^# /{flag=0} flag" "$PROJECT_ROOT/$changelog_file" 2>/dev/null); then
                if [ -n "$section" ]; then
                    RELEASE_NOTES="$section"
                    log_success "Release notes extracted from $changelog_file"
                    return 0
                fi
            fi
        fi
    done
    
    # Generate basic release notes from Git commits
    log_info "Generating release notes from Git commit history..."
    local previous_tag
    previous_tag=$(git tag --sort=-version:refname | grep -A 1 "^$VERSION$" | tail -1 2>/dev/null || echo "")
    
    if [ -n "$previous_tag" ] && [ "$previous_tag" != "$VERSION" ]; then
        RELEASE_NOTES=$(git log --pretty=format:"- %s" "$previous_tag..$VERSION" 2>/dev/null || echo "")
        if [ -n "$RELEASE_NOTES" ]; then
            log_success "Release notes generated from Git commits since $previous_tag"
        else
            RELEASE_NOTES="Release $VERSION"
            log_warning "No commit history available, using basic release notes"
        fi
    else
        RELEASE_NOTES="Release $VERSION"
        log_warning "No previous tag found, using basic release notes"
    fi
}

# Generate metadata JSON
generate_metadata_json() {
    log_step "Generating homebrew metadata JSON"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would generate metadata with:"
        log_info "  Version: $VERSION"
        log_info "  Archive URL: $ARCHIVE_URL"
        log_info "  SHA256: $SHA256_CHECKSUM"
        log_info "  Release Notes: $(echo "$RELEASE_NOTES" | head -c 100)..."
        return 0
    fi
    
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Create JSON using jq for proper escaping and formatting
    local metadata_json
    metadata_json=$(jq -n \
        --arg version "$VERSION" \
        --arg archive_url "$ARCHIVE_URL" \
        --arg binary_url "$BINARY_URL" \
        --arg sha256 "$SHA256_CHECKSUM" \
        --arg release_notes "$RELEASE_NOTES" \
        --arg timestamp "$timestamp" \
        --arg generator "usbipd-mac homebrew metadata generator v1.0" \
        '{
            "schema_version": "1.0",
            "metadata": {
                "version": $version,
                "archive_url": $archive_url,
                "binary_url": $binary_url,
                "sha256": $sha256,
                "release_notes": $release_notes,
                "timestamp": $timestamp,
                "generator": $generator
            },
            "formula_updates": {
                "version_placeholder": "{{VERSION}}",
                "sha256_placeholder": "{{SHA256}}",
                "url_pattern": "releases/download/{{VERSION}}/usbipd-{{VERSION}}-macos"
            }
        }')
    
    if [ $? -ne 0 ] || [ -z "$metadata_json" ]; then
        log_error "Failed to generate JSON metadata"
        exit $EXIT_JSON_FAILED
    fi
    
    # Write JSON to output file
    echo "$metadata_json" > "$OUTPUT_FILE"
    log_success "Metadata JSON generated: $OUTPUT_FILE"
    
    # Validate generated JSON
    if jq empty "$OUTPUT_FILE" >/dev/null 2>&1; then
        log_success "✓ Generated JSON is valid"
    else
        log_error "✗ Generated JSON is invalid"
        exit $EXIT_JSON_FAILED
    fi
    
    # Log file size and preview
    local file_size
    file_size=$(wc -c < "$OUTPUT_FILE")
    log_info "Metadata file size: $file_size bytes"
    
    log_info "Generated metadata preview:"
    jq '.' "$OUTPUT_FILE" | head -10 | while IFS= read -r line; do
        log_info "  $line"
    done
}

# Validate generated metadata
validate_metadata() {
    log_step "Validating generated metadata"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would validate generated metadata"
        return 0
    fi
    
    if [ ! -f "$OUTPUT_FILE" ]; then
        log_error "Output file not found: $OUTPUT_FILE"
        exit $EXIT_GENERATION_FAILED
    fi
    
    # Validate JSON structure
    local schema_errors=0
    
    # Check required fields
    local required_fields=("metadata.version" "metadata.archive_url" "metadata.binary_url" "metadata.sha256" "metadata.timestamp")
    for field in "${required_fields[@]}"; do
        if jq -e ".$field" "$OUTPUT_FILE" >/dev/null 2>&1; then
            log_info "✓ Required field found: $field"
        else
            log_error "✗ Missing required field: $field"
            ((schema_errors++))
        fi
    done
    
    # Validate version format
    local json_version
    json_version=$(jq -r '.metadata.version' "$OUTPUT_FILE")
    if [[ "$json_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]; then
        log_success "✓ Version format is valid: $json_version"
    else
        log_error "✗ Invalid version format in metadata: $json_version"
        ((schema_errors++))
    fi
    
    # Validate SHA256 format
    local json_sha256
    json_sha256=$(jq -r '.metadata.sha256' "$OUTPUT_FILE")
    if [[ "$json_sha256" =~ ^[a-fA-F0-9]{64}$ ]]; then
        log_success "✓ SHA256 format is valid"
    else
        log_error "✗ Invalid SHA256 format in metadata: $json_sha256"
        ((schema_errors++))
    fi
    
    # Validate URL formats
    local archive_url
    archive_url=$(jq -r '.metadata.archive_url' "$OUTPUT_FILE")
    if [[ "$archive_url" =~ ^https://github\.com/[^/]+/[^/]+/archive/v[0-9].+\.tar\.gz$ ]]; then
        log_success "✓ Archive URL format is valid"
    else
        log_error "✗ Invalid archive URL format in metadata: $archive_url"
        ((schema_errors++))
    fi
    
    local binary_url
    binary_url=$(jq -r '.metadata.binary_url' "$OUTPUT_FILE")
    if [[ "$binary_url" =~ ^https://github\.com/[^/]+/[^/]+/releases/download/v[0-9].+-macos$ ]]; then
        log_success "✓ Binary URL format is valid"
    else
        log_error "✗ Invalid binary URL format in metadata: $binary_url"
        ((schema_errors++))
    fi
    
    # Report validation results
    if [ $schema_errors -eq 0 ]; then
        log_success "Metadata validation completed successfully"
    else
        log_error "Metadata validation failed: $schema_errors errors"
        exit $EXIT_VALIDATION_FAILED
    fi
}

# Generate summary report
generate_summary() {
    log_step "Generating metadata generation summary"
    
    local summary_file="$OUTPUT_DIR/metadata-generation-summary-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$summary_file" << EOF
Homebrew Metadata Generation Summary
====================================

Generated: $(date)
Generated by: $(whoami)@$(hostname)
Project: usbipd-mac

Metadata Information:
  Version: $VERSION
  SHA256 Checksum: $SHA256_CHECKSUM
  Archive URL: $ARCHIVE_URL
  Binary URL: $BINARY_URL
  Output File: $OUTPUT_FILE
  File Size: $([ -f "$OUTPUT_FILE" ] && wc -c < "$OUTPUT_FILE" || echo "0") bytes

Configuration:
  Dry Run: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")
  Force Overwrite: $([ "$FORCE_OVERWRITE" = true ] && echo "YES" || echo "NO")
  Validate Inputs: $([ "$VALIDATE_INPUTS" = true ] && echo "YES" || echo "NO")

Generation Status:
  ✓ Prerequisites validated
  ✓ Version validated
  ✓ Archive URL generated
  ✓ SHA256 checksum calculated
  ✓ Release notes extracted
  ✓ Metadata JSON generated
  ✓ Generated metadata validated

Release Notes Preview:
$(echo "$RELEASE_NOTES" | head -5)
$([ "$(echo "$RELEASE_NOTES" | wc -l)" -gt 5 ] && echo "...")

Next Steps:
  1. Verify the generated metadata file:
     cat $OUTPUT_FILE
  
  2. Upload metadata as release asset in workflow:
     gh release upload $VERSION $OUTPUT_FILE
  
  3. Monitor tap repository workflow for automatic formula update

Log File: $LOG_FILE

EOF
    
    log_success "Metadata generation summary created: $(basename "$summary_file")"
    log_info "Summary location: $summary_file"
    
    # Display summary to user
    echo ""
    cat "$summary_file"
    echo ""
}

# Print usage information
print_usage() {
    cat << EOF
Usage: $0 --version VERSION [OPTIONS]

Homebrew Metadata Generation for usbipd-mac External Tap Integration

Generates structured metadata JSON for tap repository consumption,
including version, checksum, release notes, and formula update placeholders.

REQUIRED OPTIONS:
  --version VERSION           Release version (e.g., v1.2.3 or 1.2.3)

OPTIONAL OPTIONS:
  --checksum CHECKSUM         SHA256 checksum (auto-calculated if not provided)
  --archive-url URL           Archive URL (auto-generated if not provided)
  --binary-url URL            Binary URL (auto-generated if not provided)
  --release-notes TEXT        Release notes (auto-extracted if not provided)
  --dry-run                   Preview generation without creating files
  --force                     Force overwrite existing output file
  --skip-validation           Skip input validation and Git tag checks
  --help                      Show this help message

EXAMPLES:
  $0 --version v1.2.3                     # Generate metadata for version 1.2.3
  $0 --version 1.2.3 --dry-run           # Preview metadata generation
  $0 --version v1.2.3 --force            # Overwrite existing metadata file
  $0 --version v1.2.3 --checksum abc123  # Use specific checksum
  $0 --version v1.2.3 --skip-validation  # Skip Git tag validation

GENERATION PROCESS:
  1. Validate prerequisites and version format
  2. Validate that Git tag exists for the version
  3. Generate archive URL from Git repository
  4. Calculate SHA256 checksum by downloading archive
  5. Extract release notes from Git tag or changelog
  6. Generate structured JSON metadata
  7. Validate generated metadata structure
  8. Create generation summary report

OUTPUT:
  The script generates homebrew-metadata.json with the following structure:
  {
    "schema_version": "1.0",
    "metadata": {
      "version": "v1.2.3",
      "archive_url": "https://github.com/owner/repo/archive/v1.2.3.tar.gz",
      "sha256": "abc123...",
      "release_notes": "Release notes...",
      "timestamp": "2024-01-01T00:00:00Z",
      "generator": "usbipd-mac homebrew metadata generator v1.0"
    },
    "formula_updates": {
      "version_placeholder": "{{VERSION}}",
      "sha256_placeholder": "{{SHA256}}",
      "url_pattern": "archive/{{VERSION}}.tar.gz"
    }
  }

This script is designed for integration with release automation workflows
and supports the external tap repository architecture for Homebrew distribution.

EOF
}

# Error handler
handle_error() {
    local exit_code=$?
    log_error "Metadata generation failed with exit code $exit_code"
    
    if [ -f "$LOG_FILE" ]; then
        log_info "Detailed logs available at: $LOG_FILE"
    fi
    
    echo ""
    echo "Common troubleshooting steps:"
    echo "1. Check error messages above for specific issues"
    echo "2. Ensure the Git tag exists: git tag -l | grep $VERSION"
    echo "3. Verify archive URL is accessible: curl -I $ARCHIVE_URL"
    echo "4. Check JSON syntax: jq '.' $OUTPUT_FILE"
    echo "5. Use --dry-run to preview generation without creating files"
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
            --checksum)
                SHA256_CHECKSUM="$2"
                shift 2
                ;;
            --archive-url)
                ARCHIVE_URL="$2"
                shift 2
                ;;
            --binary-url)
                BINARY_URL="$2"
                shift 2
                ;;
            --release-notes)
                RELEASE_NOTES="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_OVERWRITE=true
                shift
                ;;
            --skip-validation)
                VALIDATE_INPUTS=false
                shift
                ;;
            --help)
                print_usage
                exit $EXIT_SUCCESS
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit $EXIT_USAGE_ERROR
                ;;
        esac
    done
    
    # Validate required arguments
    if [ -z "$VERSION" ]; then
        log_error "Version is required. Use --version to specify."
        print_usage
        exit $EXIT_USAGE_ERROR
    fi
    
    # Start metadata generation process
    print_header
    
    # Execute generation steps
    setup_environment
    validate_prerequisites
    validate_version
    generate_urls
    calculate_checksum
    extract_release_notes
    generate_metadata_json
    validate_metadata
    generate_summary
    
    if [ "$DRY_RUN" = true ]; then
        log_success "🎉 Metadata generation preview completed successfully!"
        echo ""
        echo "Run without --dry-run to generate the actual metadata file."
    else
        log_success "🎉 Homebrew metadata generation completed successfully!"
        echo ""
        echo "Metadata file generated: $OUTPUT_FILE"
        echo "Log file: $LOG_FILE"
    fi
}

# Change to project root directory
cd "$PROJECT_ROOT"

# Run main function with all arguments
main "$@"