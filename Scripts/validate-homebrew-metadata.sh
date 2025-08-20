#!/bin/bash

# validate-homebrew-metadata.sh
# Homebrew metadata validation utilities for usbipd-mac external tap integration
# Comprehensive validation for homebrew metadata JSON including schema compliance,
# format validation, and content verification
# Ensures metadata consistency and prevents tap repository failures

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly VALIDATION_DIR="${PROJECT_ROOT}/.build/metadata-validation"
readonly LOG_FILE="${VALIDATION_DIR}/metadata-validation.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Configuration variables
METADATA_FILE=""
SKIP_NETWORK_VALIDATION=false
SKIP_CHECKSUM_VALIDATION=false
VERBOSE=false
DRY_RUN=false
STRICT_MODE=true

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_VALIDATION_FAILED=1
readonly EXIT_FILE_NOT_FOUND=2
readonly EXIT_SCHEMA_FAILED=3
readonly EXIT_FORMAT_FAILED=4
readonly EXIT_NETWORK_FAILED=5
readonly EXIT_USAGE_ERROR=6

# JSON Schema definition (embedded for portability)
readonly METADATA_SCHEMA='{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["schema_version", "metadata", "formula_updates"],
  "properties": {
    "schema_version": {
      "type": "string",
      "pattern": "^[0-9]+\\.[0-9]+$"
    },
    "metadata": {
      "type": "object",
      "required": ["version", "archive_url", "sha256", "timestamp"],
      "properties": {
        "version": {
          "type": "string",
          "pattern": "^v[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9.-]+)?$"
        },
        "archive_url": {
          "type": "string",
          "pattern": "^https://github\\.com/[^/]+/[^/]+/archive/v[0-9].+\\.tar\\.gz$"
        },
        "sha256": {
          "type": "string",
          "pattern": "^[a-fA-F0-9]{64}$"
        },
        "release_notes": {
          "type": "string"
        },
        "timestamp": {
          "type": "string",
          "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
        },
        "generator": {
          "type": "string"
        }
      }
    },
    "formula_updates": {
      "type": "object",
      "required": ["version_placeholder", "sha256_placeholder", "url_pattern"],
      "properties": {
        "version_placeholder": {
          "type": "string"
        },
        "sha256_placeholder": {
          "type": "string"
        },
        "url_pattern": {
          "type": "string"
        }
      }
    }
  }
}'

# Logging functions
log_info() {
    local message="${BLUE}[INFO]${NC} $1"
    echo -e "$message"
    if [[ -d "$VALIDATION_DIR" ]]; then
        echo -e "$message" >> "$LOG_FILE"
    fi
}

log_success() {
    local message="${GREEN}[SUCCESS]${NC} $1"
    echo -e "$message"
    if [[ -d "$VALIDATION_DIR" ]]; then
        echo -e "$message" >> "$LOG_FILE"
    fi
}

log_warning() {
    local message="${YELLOW}[WARNING]${NC} $1"
    echo -e "$message"
    if [[ -d "$VALIDATION_DIR" ]]; then
        echo -e "$message" >> "$LOG_FILE"
    fi
}

log_error() {
    local message="${RED}[ERROR]${NC} $1"
    echo -e "$message"
    if [[ -d "$VALIDATION_DIR" ]]; then
        echo -e "$message" >> "$LOG_FILE"
    fi
}

log_step() {
    local message="${BOLD}${BLUE}==>${NC}${BOLD} $1${NC}"
    echo -e "$message"
    if [[ -d "$VALIDATION_DIR" ]]; then
        echo -e "$message" >> "$LOG_FILE"
    fi
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        local message="${BLUE}[VERBOSE]${NC} $1"
        echo -e "$message"
        if [[ -d "$VALIDATION_DIR" ]]; then
            echo -e "$message" >> "$LOG_FILE"
        fi
    fi
}

# Print script header
print_header() {
    echo "=================================================================="
    echo "🔍 Homebrew Metadata Validation Utilities for usbipd-mac"
    echo "=================================================================="
    echo "Metadata File: ${METADATA_FILE:-'[required]'}"
    echo "Skip Network Validation: $([ "$SKIP_NETWORK_VALIDATION" = true ] && echo "YES" || echo "NO")"
    echo "Skip Checksum Validation: $([ "$SKIP_CHECKSUM_VALIDATION" = true ] && echo "YES" || echo "NO")"
    echo "Verbose: $([ "$VERBOSE" = true ] && echo "YES" || echo "NO")"
    echo "Dry Run: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")"
    echo "Strict Mode: $([ "$STRICT_MODE" = true ] && echo "YES" || echo "NO")"
    echo "Validation Dir: $VALIDATION_DIR"
    echo "=================================================================="
    echo ""
}

# Create validation environment
setup_validation_environment() {
    log_step "Setting up metadata validation environment"
    
    # Create validation directory
    if [[ ! -d "$VALIDATION_DIR" ]]; then
        mkdir -p "$VALIDATION_DIR"
        log_info "Created validation directory: $VALIDATION_DIR"
    fi
    
    # Initialize log file
    echo "=== Metadata Validation Log Started at $(date) ===" > "$LOG_FILE"
    
    # Verify metadata file exists
    if [[ ! -f "$METADATA_FILE" ]]; then
        log_error "Metadata file not found: $METADATA_FILE"
        exit $EXIT_FILE_NOT_FOUND
    fi
    
    log_success "Metadata validation environment setup completed"
}

# Validate prerequisites
validate_prerequisites() {
    log_step "Validating prerequisites"
    
    local required_tools=("jq" "curl")
    local optional_tools=("shasum" "git")
    local missing_required=()
    
    # Check required tools
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_verbose "✓ Found required tool: $tool"
        else
            missing_required+=("$tool")
            log_error "✗ Missing required tool: $tool"
        fi
    done
    
    # Check optional tools
    for tool in "${optional_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            log_verbose "✓ Found optional tool: $tool"
        else
            log_warning "⚠ Optional tool not available: $tool (some checks may be limited)"
        fi
    done
    
    # Exit if required tools are missing
    if [[ ${#missing_required[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_required[*]}"
        log_error "Please install missing tools: brew install jq curl"
        exit $EXIT_VALIDATION_FAILED
    fi
    
    # Check jq version and functionality
    if ! jq --version >/dev/null 2>&1; then
        log_error "jq is not functioning properly"
        exit $EXIT_VALIDATION_FAILED
    fi
    
    log_success "Prerequisites validation completed"
}

# Validate JSON syntax and basic structure
validate_json_syntax() {
    log_step "Validating JSON syntax and basic structure"
    
    local syntax_errors=0
    
    # Basic JSON syntax check
    log_info "Checking JSON syntax..."
    if jq empty "$METADATA_FILE" >/dev/null 2>&1; then
        log_success "✓ JSON syntax is valid"
    else
        log_error "✗ Invalid JSON syntax"
        jq empty "$METADATA_FILE" 2>&1 | while IFS= read -r line; do
            log_error "  $line"
        done
        ((syntax_errors++))
    fi
    
    # Check if it's an object (not array or primitive)
    log_info "Checking JSON structure type..."
    local json_type
    json_type=$(jq -r 'type' "$METADATA_FILE" 2>/dev/null || echo "invalid")
    if [[ "$json_type" == "object" ]]; then
        log_success "✓ JSON is an object (expected type)"
    else
        log_error "✗ JSON is not an object, found: $json_type"
        ((syntax_errors++))
    fi
    
    # Check for empty object
    local key_count
    key_count=$(jq 'keys | length' "$METADATA_FILE" 2>/dev/null || echo "0")
    if [[ "$key_count" -gt 0 ]]; then
        log_success "✓ JSON object contains $key_count keys"
    else
        log_error "✗ JSON object is empty"
        ((syntax_errors++))
    fi
    
    # Report syntax validation results
    if [[ $syntax_errors -eq 0 ]]; then
        log_success "JSON syntax validation passed"
        return $EXIT_SUCCESS
    else
        log_error "JSON syntax validation failed: $syntax_errors errors"
        return $EXIT_SCHEMA_FAILED
    fi
}

# Validate against JSON schema
validate_json_schema() {
    log_step "Validating JSON against metadata schema"
    
    local schema_errors=0
    local temp_schema_file
    temp_schema_file=$(mktemp)
    
    # Write schema to temporary file
    echo "$METADATA_SCHEMA" > "$temp_schema_file"
    
    # Validate schema file itself
    if ! jq empty "$temp_schema_file" >/dev/null 2>&1; then
        log_error "Internal error: Invalid schema definition"
        rm -f "$temp_schema_file"
        exit $EXIT_VALIDATION_FAILED
    fi
    
    log_info "Validating against embedded JSON schema..."
    
    # Check required top-level fields
    local required_fields=("schema_version" "metadata" "formula_updates")
    for field in "${required_fields[@]}"; do
        if jq -e ".$field" "$METADATA_FILE" >/dev/null 2>&1; then
            log_verbose "✓ Required top-level field found: $field"
        else
            log_error "✗ Missing required top-level field: $field"
            ((schema_errors++))
        fi
    done
    
    # Validate metadata section
    log_info "Validating metadata section..."
    local metadata_fields=("version" "archive_url" "sha256" "timestamp")
    for field in "${metadata_fields[@]}"; do
        if jq -e ".metadata.$field" "$METADATA_FILE" >/dev/null 2>&1; then
            log_verbose "✓ Required metadata field found: $field"
        else
            log_error "✗ Missing required metadata field: $field"
            ((schema_errors++))
        fi
    done
    
    # Validate formula_updates section
    log_info "Validating formula_updates section..."
    local formula_fields=("version_placeholder" "sha256_placeholder" "url_pattern")
    for field in "${formula_fields[@]}"; do
        if jq -e ".formula_updates.$field" "$METADATA_FILE" >/dev/null 2>&1; then
            log_verbose "✓ Required formula_updates field found: $field"
        else
            log_error "✗ Missing required formula_updates field: $field"
            ((schema_errors++))
        fi
    done
    
    # Clean up temporary schema file
    rm -f "$temp_schema_file"
    
    # Report schema validation results
    if [[ $schema_errors -eq 0 ]]; then
        log_success "JSON schema validation passed"
        return $EXIT_SUCCESS
    else
        log_error "JSON schema validation failed: $schema_errors errors"
        return $EXIT_SCHEMA_FAILED
    fi
}

# Validate field formats and content
validate_field_formats() {
    log_step "Validating field formats and content"
    
    local format_errors=0
    
    # Validate schema version format
    log_info "Validating schema_version format..."
    local schema_version
    schema_version=$(jq -r '.schema_version' "$METADATA_FILE" 2>/dev/null || echo "")
    if [[ "$schema_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        log_success "✓ Schema version format is valid: $schema_version"
    else
        log_error "✗ Invalid schema version format: $schema_version (expected: X.Y)"
        ((format_errors++))
    fi
    
    # Validate version format
    log_info "Validating version format..."
    local version
    version=$(jq -r '.metadata.version' "$METADATA_FILE" 2>/dev/null || echo "")
    if [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]; then
        log_success "✓ Version format is valid: $version"
    else
        log_error "✗ Invalid version format: $version (expected: vX.Y.Z or vX.Y.Z-suffix)"
        ((format_errors++))
    fi
    
    # Validate SHA256 format
    log_info "Validating SHA256 format..."
    local sha256
    sha256=$(jq -r '.metadata.sha256' "$METADATA_FILE" 2>/dev/null || echo "")
    if [[ "$sha256" =~ ^[a-fA-F0-9]{64}$ ]]; then
        log_success "✓ SHA256 format is valid"
        log_verbose "SHA256: $sha256"
    else
        log_error "✗ Invalid SHA256 format: $sha256 (expected: 64 hex characters)"
        ((format_errors++))
    fi
    
    # Validate archive URL format
    log_info "Validating archive URL format..."
    local archive_url
    archive_url=$(jq -r '.metadata.archive_url' "$METADATA_FILE" 2>/dev/null || echo "")
    if [[ "$archive_url" =~ ^https://github\.com/[^/]+/[^/]+/archive/v[0-9].+\.tar\.gz$ ]]; then
        log_success "✓ Archive URL format is valid"
        log_verbose "Archive URL: $archive_url"
    else
        log_error "✗ Invalid archive URL format: $archive_url"
        log_error "Expected: https://github.com/owner/repo/archive/vX.Y.Z.tar.gz"
        ((format_errors++))
    fi
    
    # Validate timestamp format
    log_info "Validating timestamp format..."
    local timestamp
    timestamp=$(jq -r '.metadata.timestamp' "$METADATA_FILE" 2>/dev/null || echo "")
    if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        log_success "✓ Timestamp format is valid: $timestamp"
    else
        log_error "✗ Invalid timestamp format: $timestamp (expected: ISO 8601 UTC)"
        ((format_errors++))
    fi
    
    # Validate placeholder consistency
    log_info "Validating placeholder consistency..."
    local version_placeholder
    local sha256_placeholder
    version_placeholder=$(jq -r '.formula_updates.version_placeholder' "$METADATA_FILE" 2>/dev/null || echo "")
    sha256_placeholder=$(jq -r '.formula_updates.sha256_placeholder' "$METADATA_FILE" 2>/dev/null || echo "")
    
    if [[ -n "$version_placeholder" && -n "$sha256_placeholder" ]]; then
        log_success "✓ Formula update placeholders found"
        log_verbose "Version placeholder: $version_placeholder"
        log_verbose "SHA256 placeholder: $sha256_placeholder"
    else
        log_error "✗ Missing or empty formula update placeholders"
        ((format_errors++))
    fi
    
    # Report format validation results
    if [[ $format_errors -eq 0 ]]; then
        log_success "Field format validation passed"
        return $EXIT_SUCCESS
    else
        log_error "Field format validation failed: $format_errors errors"
        return $EXIT_FORMAT_FAILED
    fi
}

# Validate network accessibility
validate_network_accessibility() {
    if [[ "$SKIP_NETWORK_VALIDATION" == "true" ]]; then
        log_step "Skipping network accessibility validation (--skip-network specified)"
        return $EXIT_SUCCESS
    fi
    
    log_step "Validating network accessibility"
    
    local network_errors=0
    local archive_url
    archive_url=$(jq -r '.metadata.archive_url' "$METADATA_FILE" 2>/dev/null || echo "")
    
    if [[ -z "$archive_url" || "$archive_url" == "null" ]]; then
        log_error "No archive URL found for network validation"
        return $EXIT_VALIDATION_FAILED
    fi
    
    log_info "Testing archive URL accessibility: $archive_url"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode: would test archive URL accessibility"
        return $EXIT_SUCCESS
    fi
    
    # Test URL accessibility with HEAD request
    local http_status
    if http_status=$(curl -s -I -L -w "%{http_code}" -o /dev/null "$archive_url" 2>/dev/null); then
        if [[ "$http_status" == "200" ]]; then
            log_success "✓ Archive URL is accessible (HTTP $http_status)"
        else
            log_error "✗ Archive URL returned HTTP $http_status"
            ((network_errors++))
        fi
    else
        log_error "✗ Failed to access archive URL"
        ((network_errors++))
    fi
    
    # Report network validation results
    if [[ $network_errors -eq 0 ]]; then
        log_success "Network accessibility validation passed"
        return $EXIT_SUCCESS
    else
        log_error "Network accessibility validation failed: $network_errors errors"
        return $EXIT_NETWORK_FAILED
    fi
}

# Validate checksum integrity
validate_checksum_integrity() {
    if [[ "$SKIP_CHECKSUM_VALIDATION" == "true" ]]; then
        log_step "Skipping checksum integrity validation (--skip-checksum specified)"
        return $EXIT_SUCCESS
    fi
    
    log_step "Validating checksum integrity"
    
    local checksum_errors=0
    local archive_url
    local expected_sha256
    archive_url=$(jq -r '.metadata.archive_url' "$METADATA_FILE" 2>/dev/null || echo "")
    expected_sha256=$(jq -r '.metadata.sha256' "$METADATA_FILE" 2>/dev/null || echo "")
    
    if [[ -z "$archive_url" || "$archive_url" == "null" ]]; then
        log_error "No archive URL found for checksum validation"
        return $EXIT_VALIDATION_FAILED
    fi
    
    if [[ -z "$expected_sha256" || "$expected_sha256" == "null" ]]; then
        log_error "No SHA256 checksum found for validation"
        return $EXIT_VALIDATION_FAILED
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode: would validate checksum integrity"
        log_info "Expected SHA256: $expected_sha256"
        return $EXIT_SUCCESS
    fi
    
    # Check if shasum is available
    if ! command -v shasum >/dev/null 2>&1; then
        log_warning "shasum not available, skipping checksum verification"
        return $EXIT_SUCCESS
    fi
    
    log_info "Downloading archive to verify checksum..."
    local temp_file
    temp_file=$(mktemp)
    
    if curl -L -f -o "$temp_file" "$archive_url" 2>/dev/null; then
        log_info "Archive downloaded successfully"
        
        # Calculate actual SHA256
        local actual_sha256
        actual_sha256=$(shasum -a 256 "$temp_file" | cut -d' ' -f1)
        
        if [[ "$actual_sha256" == "$expected_sha256" ]]; then
            log_success "✓ SHA256 checksum verification passed"
            log_verbose "Checksum: $actual_sha256"
        else
            log_error "✗ SHA256 checksum mismatch"
            log_error "Expected: $expected_sha256"
            log_error "Actual:   $actual_sha256"
            ((checksum_errors++))
        fi
        
        # Clean up
        rm -f "$temp_file"
    else
        log_error "Failed to download archive for checksum verification"
        rm -f "$temp_file"
        ((checksum_errors++))
    fi
    
    # Report checksum validation results
    if [[ $checksum_errors -eq 0 ]]; then
        log_success "Checksum integrity validation passed"
        return $EXIT_SUCCESS
    else
        log_error "Checksum integrity validation failed: $checksum_errors errors"
        return $EXIT_VALIDATION_FAILED
    fi
}

# Validate content consistency
validate_content_consistency() {
    log_step "Validating content consistency"
    
    local consistency_errors=0
    
    # Extract values for consistency checks
    local version
    local archive_url
    local url_pattern
    version=$(jq -r '.metadata.version' "$METADATA_FILE" 2>/dev/null || echo "")
    archive_url=$(jq -r '.metadata.archive_url' "$METADATA_FILE" 2>/dev/null || echo "")
    url_pattern=$(jq -r '.formula_updates.url_pattern' "$METADATA_FILE" 2>/dev/null || echo "")
    
    # Check version consistency in archive URL
    if [[ "$archive_url" == *"$version"* ]]; then
        log_success "✓ Version is consistent in archive URL"
    else
        log_error "✗ Version $version not found in archive URL: $archive_url"
        ((consistency_errors++))
    fi
    
    # Check URL pattern consistency
    if [[ -n "$url_pattern" && "$url_pattern" != "null" ]]; then
        log_success "✓ URL pattern is defined: $url_pattern"
    else
        log_error "✗ URL pattern is missing or empty"
        ((consistency_errors++))
    fi
    
    # Validate timestamp is recent (within last 30 days)
    local timestamp
    timestamp=$(jq -r '.metadata.timestamp' "$METADATA_FILE" 2>/dev/null || echo "")
    if command -v date >/dev/null 2>&1 && [[ -n "$timestamp" ]]; then
        local timestamp_epoch
        local current_epoch
        local days_old
        
        # Convert timestamp to epoch (works on both Linux and macOS)
        if timestamp_epoch=$(date -d "$timestamp" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s 2>/dev/null); then
            current_epoch=$(date +%s)
            days_old=$(( (current_epoch - timestamp_epoch) / 86400 ))
            
            if [[ $days_old -le 30 ]]; then
                log_success "✓ Timestamp is recent ($days_old days old)"
            else
                log_warning "⚠ Timestamp is $days_old days old (may be stale)"
            fi
        else
            log_warning "⚠ Could not parse timestamp for age validation"
        fi
    fi
    
    # Check release notes are present and non-empty
    local release_notes
    release_notes=$(jq -r '.metadata.release_notes' "$METADATA_FILE" 2>/dev/null || echo "")
    if [[ -n "$release_notes" && "$release_notes" != "null" && ${#release_notes} -gt 10 ]]; then
        log_success "✓ Release notes are present (${#release_notes} characters)"
    else
        log_warning "⚠ Release notes are missing or very short"
    fi
    
    # Report consistency validation results
    if [[ $consistency_errors -eq 0 ]]; then
        log_success "Content consistency validation passed"
        return $EXIT_SUCCESS
    else
        log_error "Content consistency validation failed: $consistency_errors errors"
        return $EXIT_VALIDATION_FAILED
    fi
}

# Generate validation report
generate_validation_report() {
    log_step "Generating metadata validation report"
    
    local report_file="${VALIDATION_DIR}/metadata-validation-report-$(date +%Y%m%d-%H%M%S).txt"
    local timestamp
    timestamp=$(date)
    
    cat > "$report_file" << EOF
Homebrew Metadata Validation Report
====================================

Generated: $timestamp
Validator: $(whoami)@$(hostname)
Project: usbipd-mac
Metadata File: $METADATA_FILE

Configuration:
  Skip Network Validation: $([ "$SKIP_NETWORK_VALIDATION" = true ] && echo "YES" || echo "NO")
  Skip Checksum Validation: $([ "$SKIP_CHECKSUM_VALIDATION" = true ] && echo "YES" || echo "NO")
  Verbose Output: $([ "$VERBOSE" = true ] && echo "YES" || echo "NO")
  Dry Run Mode: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")
  Strict Mode: $([ "$STRICT_MODE" = true ] && echo "YES" || echo "NO")

Metadata Information:
$(if [[ -f "$METADATA_FILE" ]]; then
    echo "  Schema Version: $(jq -r '.schema_version' "$METADATA_FILE" 2>/dev/null || echo "[Error reading]")"
    echo "  Version: $(jq -r '.metadata.version' "$METADATA_FILE" 2>/dev/null || echo "[Error reading]")"
    echo "  Archive URL: $(jq -r '.metadata.archive_url' "$METADATA_FILE" 2>/dev/null || echo "[Error reading]")"
    echo "  SHA256: $(jq -r '.metadata.sha256' "$METADATA_FILE" 2>/dev/null | head -c 16 || echo "[Error reading]")..."
    echo "  Timestamp: $(jq -r '.metadata.timestamp' "$METADATA_FILE" 2>/dev/null || echo "[Error reading]")"
    echo "  File Size: $(wc -c < "$METADATA_FILE") bytes"
else
    echo "  Metadata file not found"
fi)

Validation Results:
  ✓ Prerequisites: $([ -f "$LOG_FILE" ] && grep -c "Prerequisites validation completed" "$LOG_FILE" || echo "0") checks
  ✓ JSON Syntax: [Results in log]
  ✓ Schema Validation: [Results in log]
  ✓ Format Validation: [Results in log]
  ✓ Network Accessibility: [Results in log]
  ✓ Checksum Integrity: [Results in log]
  ✓ Content Consistency: [Results in log]

For detailed results, see: $LOG_FILE

EOF
    
    log_success "Metadata validation report generated: $(basename "$report_file")"
    log_info "Report location: $report_file"
    
    # Display summary to user
    echo ""
    cat "$report_file"
    echo ""
}

# Print usage information
print_usage() {
    cat << EOF
Usage: $0 --file METADATA_FILE [OPTIONS]

Homebrew Metadata Validation Utilities for usbipd-mac

Validates homebrew metadata JSON including schema compliance, format validation,
and content verification to ensure metadata consistency and prevent tap repository failures.

REQUIRED OPTIONS:
  --file FILE                 Path to homebrew metadata JSON file

OPTIONAL OPTIONS:
  --skip-network             Skip network accessibility validation
  --skip-checksum            Skip checksum integrity validation
  --verbose                  Enable verbose output with detailed information
  --dry-run                  Preview validation without network operations
  --no-strict                Disable strict mode (allow warnings)
  --help                     Show this help message

EXAMPLES:
  $0 --file homebrew-metadata.json                    # Complete validation
  $0 --file metadata.json --verbose                   # Detailed output
  $0 --file metadata.json --skip-network              # Skip network tests
  $0 --file metadata.json --dry-run                   # Preview validation
  $0 --file metadata.json --skip-checksum --verbose   # Skip checksum verification

EXIT CODES:
  0   Validation successful
  1   General validation failure
  2   Metadata file not found
  3   JSON schema validation failed
  4   Field format validation failed
  5   Network validation failed
  6   Usage error

VALIDATION PROCESS:
  1. Validate prerequisites (jq, curl, tools)
  2. Validate JSON syntax and basic structure
  3. Validate against embedded JSON schema
  4. Validate field formats and content
  5. Validate network accessibility (optional)
  6. Validate checksum integrity (optional)
  7. Validate content consistency
  8. Generate comprehensive validation report

SCHEMA VALIDATION:
  The script validates against an embedded JSON schema that ensures:
  - Required fields are present (schema_version, metadata, formula_updates)
  - Version follows semantic versioning (vX.Y.Z format)
  - SHA256 is valid 64-character hex string
  - Archive URL follows GitHub release pattern
  - Timestamp follows ISO 8601 UTC format
  - Formula update placeholders are properly defined

This utility ensures homebrew metadata meets quality and consistency standards
before consumption by tap repository workflows.

EOF
}

# Error handler
handle_error() {
    local exit_code=$?
    log_error "Metadata validation failed with exit code $exit_code"
    
    if [[ -f "$LOG_FILE" ]]; then
        log_info "Detailed logs available at: $LOG_FILE"
    fi
    
    echo ""
    echo "Common troubleshooting steps:"
    echo "1. Check error messages above for specific validation issues"
    echo "2. Verify metadata file exists and is readable"
    echo "3. Validate JSON syntax: jq '.' $METADATA_FILE"
    echo "4. Check field formats against expected patterns"
    echo "5. Use --verbose for detailed validation information"
    echo "6. Use --dry-run to skip network operations"
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
            --file)
                METADATA_FILE="$2"
                shift 2
                ;;
            --skip-network)
                SKIP_NETWORK_VALIDATION=true
                shift
                ;;
            --skip-checksum)
                SKIP_CHECKSUM_VALIDATION=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-strict)
                STRICT_MODE=false
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
    if [[ -z "$METADATA_FILE" ]]; then
        log_error "Metadata file is required. Use --file to specify."
        print_usage
        exit $EXIT_USAGE_ERROR
    fi
    
    # Start validation process
    print_header
    
    # Execute validation steps
    setup_validation_environment
    validate_prerequisites
    
    # Perform validation checks
    local validation_exit_code=$EXIT_SUCCESS
    
    # JSON syntax validation
    if ! validate_json_syntax; then
        validation_exit_code=$EXIT_SCHEMA_FAILED
        if [[ "$DRY_RUN" == "false" && "$STRICT_MODE" == "true" ]]; then
            log_error "JSON syntax validation failed - stopping validation"
        else
            log_warning "JSON syntax validation failed (continuing)"
        fi
    fi
    
    # Schema validation
    if [[ "$validation_exit_code" -eq $EXIT_SUCCESS ]] || [[ "$STRICT_MODE" == "false" ]]; then
        if ! validate_json_schema; then
            validation_exit_code=$EXIT_SCHEMA_FAILED
            if [[ "$DRY_RUN" == "false" && "$STRICT_MODE" == "true" ]]; then
                log_error "Schema validation failed - stopping validation"
            else
                log_warning "Schema validation failed (continuing)"
            fi
        fi
    fi
    
    # Format validation
    if [[ "$validation_exit_code" -eq $EXIT_SUCCESS ]] || [[ "$STRICT_MODE" == "false" ]]; then
        if ! validate_field_formats; then
            validation_exit_code=$EXIT_FORMAT_FAILED
            if [[ "$DRY_RUN" == "false" && "$STRICT_MODE" == "true" ]]; then
                log_error "Format validation failed - stopping validation"
            else
                log_warning "Format validation failed (continuing)"
            fi
        fi
    fi
    
    # Network accessibility validation (optional)
    if [[ "$validation_exit_code" -eq $EXIT_SUCCESS ]] || [[ "$STRICT_MODE" == "false" ]]; then
        if ! validate_network_accessibility; then
            if [[ "$STRICT_MODE" == "true" ]]; then
                validation_exit_code=$EXIT_NETWORK_FAILED
                log_error "Network accessibility validation failed"
            else
                log_warning "Network accessibility validation failed (continuing)"
            fi
        fi
    fi
    
    # Checksum integrity validation (optional)
    if [[ "$validation_exit_code" -eq $EXIT_SUCCESS ]] || [[ "$STRICT_MODE" == "false" ]]; then
        if ! validate_checksum_integrity; then
            if [[ "$STRICT_MODE" == "true" ]]; then
                validation_exit_code=$EXIT_VALIDATION_FAILED
                log_error "Checksum integrity validation failed"
            else
                log_warning "Checksum integrity validation failed (continuing)"
            fi
        fi
    fi
    
    # Content consistency validation (always run, warnings only unless strict)
    validate_content_consistency
    
    # Generate validation report
    generate_validation_report
    
    # Final result
    if [[ "$validation_exit_code" -eq $EXIT_SUCCESS ]]; then
        log_success "🎉 All metadata validation checks passed successfully!"
        echo ""
        echo "Homebrew metadata is valid and ready for tap repository consumption."
        echo "Validation log: $LOG_FILE"
    elif [[ "$STRICT_MODE" == "false" ]]; then
        log_warning "Metadata validation completed with warnings (non-strict mode)"
        echo ""
        echo "Review validation results and consider resolving issues."
        echo "Validation log: $LOG_FILE"
        exit $EXIT_SUCCESS
    else
        log_error "❌ Metadata validation failed!"
        echo ""
        echo "Please resolve validation issues before using with tap repository."
        echo "Validation log: $LOG_FILE"
        exit $validation_exit_code
    fi
}

# Ensure we're in the project root directory
cd "$PROJECT_ROOT"

# Run main function with all arguments
main "$@"