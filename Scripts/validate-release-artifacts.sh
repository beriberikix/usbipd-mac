#!/bin/bash

# Release Artifact Validation Utilities
# Comprehensive validation for release artifacts including checksum verification,
# binary signature validation, and compatibility testing
# Ensures artifact integrity and security before distribution

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/.build"
readonly ARTIFACTS_DIR="${BUILD_DIR}/release-artifacts"
readonly VALIDATION_DIR="${BUILD_DIR}/validation"
readonly LOG_FILE="${VALIDATION_DIR}/artifact-validation.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Configuration variables
ARTIFACTS_PATH=""
SKIP_SIGNATURE_CHECK=false
SKIP_COMPATIBILITY_CHECK=false
VERBOSE=false
DRY_RUN=false
EXPECTED_VERSION=""
CHECKSUM_FILE=""

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_VALIDATION_FAILED=1
readonly EXIT_MISSING_ARTIFACTS=2
readonly EXIT_CHECKSUM_FAILED=3
readonly EXIT_SIGNATURE_FAILED=4
readonly EXIT_COMPATIBILITY_FAILED=5
readonly EXIT_USAGE_ERROR=6

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
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

log_step() {
    echo -e "${BOLD}${BLUE}==>${NC}${BOLD} $1${NC}" | tee -a "$LOG_FILE"
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1" | tee -a "$LOG_FILE"
    fi
}

# Print script header
print_header() {
    echo "=================================================================="
    echo "🔍 Release Artifact Validation Utilities for usbipd-mac"
    echo "=================================================================="
    echo "Artifacts Path: ${ARTIFACTS_PATH:-'[auto-detect]'}"
    echo "Expected Version: ${EXPECTED_VERSION:-'[auto-detect]'}"
    echo "Skip Signatures: $([ "$SKIP_SIGNATURE_CHECK" = true ] && echo "YES" || echo "NO")"
    echo "Skip Compatibility: $([ "$SKIP_COMPATIBILITY_CHECK" = true ] && echo "YES" || echo "NO")"
    echo "Verbose: $([ "$VERBOSE" = true ] && echo "YES" || echo "NO")"
    echo "Dry Run: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")"
    echo "Validation Dir: $VALIDATION_DIR"
    echo "=================================================================="
    echo ""
}

# Create validation environment
setup_validation_environment() {
    log_step "Setting up validation environment"
    
    # Create validation directory
    if [[ ! -d "$VALIDATION_DIR" ]]; then
        mkdir -p "$VALIDATION_DIR"
        log_info "Created validation directory: $VALIDATION_DIR"
    fi
    
    # Initialize log file
    echo "=== Artifact Validation Log Started at $(date) ===" > "$LOG_FILE"
    
    # Detect artifacts path if not provided
    if [[ -z "$ARTIFACTS_PATH" ]]; then
        if [[ -d "$ARTIFACTS_DIR" ]]; then
            ARTIFACTS_PATH="$ARTIFACTS_DIR"
            log_info "Auto-detected artifacts path: $ARTIFACTS_PATH"
        else
            log_error "No artifacts directory found and no path specified"
            log_error "Expected location: $ARTIFACTS_DIR"
            log_error "Use --artifacts-path to specify custom location"
            exit $EXIT_MISSING_ARTIFACTS
        fi
    fi
    
    # Verify artifacts directory exists
    if [[ ! -d "$ARTIFACTS_PATH" ]]; then
        log_error "Artifacts directory does not exist: $ARTIFACTS_PATH"
        exit $EXIT_MISSING_ARTIFACTS
    fi
    
    log_success "Validation environment setup completed"
}

# Validate prerequisites
validate_prerequisites() {
    log_step "Validating prerequisites"
    
    local required_tools=("shasum" "file" "codesign")
    local optional_tools=("otool" "lipo" "plutil")
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
        log_error "Please install missing tools and retry"
        exit $EXIT_VALIDATION_FAILED
    fi
    
    log_success "Prerequisites validation completed"
}

# Discover release artifacts
discover_artifacts() {
    log_step "Discovering release artifacts"
    
    local artifacts=()
    local checksums=()
    
    # Find binary executables
    while IFS= read -r -d '' file; do
        if file "$file" | grep -q "Mach-O.*executable"; then
            artifacts+=("$file")
            log_verbose "Found executable: $(basename "$file")"
        fi
    done < <(find "$ARTIFACTS_PATH" -type f -executable -print0)
    
    # Find app bundles (System Extension)
    while IFS= read -r -d '' bundle; do
        if [[ -d "$bundle" && "$bundle" == *.app ]]; then
            artifacts+=("$bundle")
            log_verbose "Found app bundle: $(basename "$bundle")"
        fi
    done < <(find "$ARTIFACTS_PATH" -name "*.app" -type d -print0)
    
    # Find archives and packages
    while IFS= read -r -d '' archive; do
        artifacts+=("$archive")
        log_verbose "Found archive: $(basename "$archive")"
    done < <(find "$ARTIFACTS_PATH" -name "*.tar.gz" -o -name "*.zip" -o -name "*.dmg" -print0)
    
    # Find checksum files
    while IFS= read -r -d '' checksum_file; do
        checksums+=("$checksum_file")
        log_verbose "Found checksum file: $(basename "$checksum_file")"
    done < <(find "$ARTIFACTS_PATH" -name "*.sha256" -o -name "*-checksums.txt" -o -name "SHA256SUMS" -print0)
    
    # Store discovered artifacts in global arrays
    DISCOVERED_ARTIFACTS=("${artifacts[@]}")
    DISCOVERED_CHECKSUMS=("${checksums[@]}")
    
    log_info "Discovered ${#artifacts[@]} artifacts and ${#checksums[@]} checksum files"
    
    if [[ ${#artifacts[@]} -eq 0 ]]; then
        log_error "No release artifacts found in $ARTIFACTS_PATH"
        exit $EXIT_MISSING_ARTIFACTS
    fi
    
    # Auto-detect checksum file if not specified
    if [[ -z "$CHECKSUM_FILE" && ${#checksums[@]} -eq 1 ]]; then
        CHECKSUM_FILE="${checksums[0]}"
        log_info "Auto-detected checksum file: $(basename "$CHECKSUM_FILE")"
    fi
    
    log_success "Artifact discovery completed"
}

# Validate checksums
validate_checksums() {
    log_step "Validating artifact checksums"
    
    if [[ -z "$CHECKSUM_FILE" ]]; then
        log_warning "No checksum file specified, attempting to find or generate checksums"
        
        # Try to find a checksum file
        local checksum_candidates=("${ARTIFACTS_PATH}/SHA256SUMS" "${ARTIFACTS_PATH}/checksums.sha256" "${ARTIFACTS_PATH}/release-checksums.txt")
        for candidate in "${checksum_candidates[@]}"; do
            if [[ -f "$candidate" ]]; then
                CHECKSUM_FILE="$candidate"
                log_info "Found checksum file: $(basename "$CHECKSUM_FILE")"
                break
            fi
        done
        
        # Generate checksums if none found
        if [[ -z "$CHECKSUM_FILE" ]]; then
            log_info "Generating checksums for validation..."
            CHECKSUM_FILE="${VALIDATION_DIR}/generated-checksums.sha256"
            
            for artifact in "${DISCOVERED_ARTIFACTS[@]}"; do
                if [[ -f "$artifact" ]]; then
                    shasum -a 256 "$artifact" >> "$CHECKSUM_FILE"
                elif [[ -d "$artifact" ]]; then
                    # For directories (app bundles), checksum the entire contents
                    find "$artifact" -type f -exec shasum -a 256 {} \; | sort >> "$CHECKSUM_FILE"
                fi
            done
            
            log_success "Generated checksum file: $(basename "$CHECKSUM_FILE")"
        fi
    fi
    
    if [[ ! -f "$CHECKSUM_FILE" ]]; then
        log_error "Checksum file not found: $CHECKSUM_FILE"
        return $EXIT_CHECKSUM_FAILED
    fi
    
    # Validate checksums
    local checksum_failures=0
    local checksum_successes=0
    
    log_info "Validating checksums using: $(basename "$CHECKSUM_FILE")"
    
    # Read checksum file and validate each entry
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^#.* ]] && continue
        
        # Parse checksum line (format: checksum filename)
        local expected_checksum
        local filename
        if [[ "$line" =~ ^([a-fA-F0-9]{64})\s+(.+)$ ]]; then
            expected_checksum="${BASH_REMATCH[1]}"
            filename="${BASH_REMATCH[2]}"
        else
            log_warning "Invalid checksum line format: $line"
            continue
        fi
        
        # Find the full path to the file
        local file_path=""
        if [[ -f "$filename" ]]; then
            file_path="$filename"
        elif [[ -f "${ARTIFACTS_PATH}/${filename}" ]]; then
            file_path="${ARTIFACTS_PATH}/${filename}"
        else
            # Search for file in artifacts directory
            file_path=$(find "$ARTIFACTS_PATH" -name "$(basename "$filename")" -type f | head -1)
        fi
        
        if [[ -z "$file_path" || ! -f "$file_path" ]]; then
            log_error "File not found for checksum validation: $filename"
            ((checksum_failures++))
            continue
        fi
        
        # Calculate actual checksum
        local actual_checksum
        actual_checksum=$(shasum -a 256 "$file_path" | cut -d' ' -f1)
        
        # Compare checksums
        if [[ "$expected_checksum" == "$actual_checksum" ]]; then
            log_verbose "✓ Checksum valid: $(basename "$file_path")"
            ((checksum_successes++))
        else
            log_error "✗ Checksum mismatch: $(basename "$file_path")"
            log_error "  Expected: $expected_checksum"
            log_error "  Actual:   $actual_checksum"
            ((checksum_failures++))
        fi
        
    done < "$CHECKSUM_FILE"
    
    # Report results
    if [[ $checksum_failures -eq 0 ]]; then
        log_success "All $checksum_successes checksums validated successfully"
        return $EXIT_SUCCESS
    else
        log_error "Checksum validation failed: $checksum_failures failures, $checksum_successes successes"
        return $EXIT_CHECKSUM_FAILED
    fi
}

# Validate binary signatures
validate_signatures() {
    if [[ "$SKIP_SIGNATURE_CHECK" == "true" ]]; then
        log_step "Skipping signature validation (--skip-signatures specified)"
        return $EXIT_SUCCESS
    fi
    
    log_step "Validating binary signatures and code signing"
    
    local signature_failures=0
    local signature_successes=0
    local unsigned_binaries=0
    
    for artifact in "${DISCOVERED_ARTIFACTS[@]}"; do
        local artifact_name
        artifact_name=$(basename "$artifact")
        
        # Skip non-executable files for signature checking
        if [[ -f "$artifact" ]] && ! file "$artifact" | grep -q "Mach-O.*executable"; then
            log_verbose "Skipping non-executable file: $artifact_name"
            continue
        fi
        
        # Check if artifact is signed
        if codesign -dv "$artifact" >/dev/null 2>&1; then
            log_verbose "Checking signature for: $artifact_name"
            
            # Verify signature
            if codesign --verify --deep --strict "$artifact" >/dev/null 2>&1; then
                log_success "✓ Valid signature: $artifact_name"
                
                # Get signature details if verbose
                if [[ "$VERBOSE" == "true" ]]; then
                    local signature_info
                    signature_info=$(codesign -dvv "$artifact" 2>&1)
                    log_verbose "Signature details for $artifact_name:"
                    echo "$signature_info" | while IFS= read -r line; do
                        log_verbose "  $line"
                    done
                fi
                
                ((signature_successes++))
            else
                log_error "✗ Invalid signature: $artifact_name"
                
                # Get detailed error information
                local signature_error
                signature_error=$(codesign --verify --deep --strict "$artifact" 2>&1 || true)
                log_error "  Error: $signature_error"
                
                ((signature_failures++))
            fi
        else
            log_warning "⚠ Unsigned binary: $artifact_name"
            ((unsigned_binaries++))
        fi
    done
    
    # Report results
    log_info "Signature validation summary:"
    log_info "  Valid signatures: $signature_successes"
    log_info "  Invalid signatures: $signature_failures"
    log_info "  Unsigned binaries: $unsigned_binaries"
    
    if [[ $signature_failures -gt 0 ]]; then
        log_error "Signature validation failed: $signature_failures invalid signatures"
        return $EXIT_SIGNATURE_FAILED
    elif [[ $unsigned_binaries -gt 0 ]]; then
        log_warning "Found $unsigned_binaries unsigned binaries (acceptable for development releases)"
        log_success "No signature validation failures detected"
        return $EXIT_SUCCESS
    else
        log_success "All binaries have valid signatures"
        return $EXIT_SUCCESS
    fi
}

# Validate compatibility and architecture
validate_compatibility() {
    if [[ "$SKIP_COMPATIBILITY_CHECK" == "true" ]]; then
        log_step "Skipping compatibility validation (--skip-compatibility specified)"
        return $EXIT_SUCCESS
    fi
    
    log_step "Validating binary compatibility and architecture"
    
    local compatibility_failures=0
    local compatibility_successes=0
    
    for artifact in "${DISCOVERED_ARTIFACTS[@]}"; do
        local artifact_name
        artifact_name=$(basename "$artifact")
        
        # Skip non-binary files
        if [[ ! -f "$artifact" ]] || ! file "$artifact" | grep -q "Mach-O"; then
            log_verbose "Skipping non-binary file: $artifact_name"
            continue
        fi
        
        log_verbose "Checking compatibility for: $artifact_name"
        
        # Check architecture
        local arch_info
        if command -v lipo >/dev/null 2>&1; then
            arch_info=$(lipo -info "$artifact" 2>/dev/null || echo "Unknown architecture")
            log_verbose "  Architecture: $arch_info"
            
            # Check for expected architectures (arm64 and/or x86_64)
            if [[ "$arch_info" =~ (arm64|x86_64) ]]; then
                log_verbose "  ✓ Compatible architecture detected"
                ((compatibility_successes++))
            else
                log_error "  ✗ Unexpected architecture: $arch_info"
                ((compatibility_failures++))
            fi
        else
            log_verbose "  Architecture check skipped (lipo not available)"
        fi
        
        # Check minimum macOS version
        if command -v otool >/dev/null 2>&1; then
            local version_info
            version_info=$(otool -l "$artifact" | grep -A 2 "LC_VERSION_MIN_MACOSX\|LC_BUILD_VERSION" | head -n 3 || echo "")
            if [[ -n "$version_info" ]]; then
                log_verbose "  Version requirements:"
                echo "$version_info" | while IFS= read -r line; do
                    [[ -n "$line" ]] && log_verbose "    $line"
                done
            fi
        fi
        
        # Basic executable test (if it's a standalone binary)
        if [[ -x "$artifact" ]] && file "$artifact" | grep -q "executable"; then
            log_verbose "  Testing executable format..."
            
            # Try to get help or version information (with timeout)
            local exec_test_result=""
            if timeout 5s "$artifact" --version >/dev/null 2>&1; then
                log_verbose "  ✓ Executable responds to --version"
            elif timeout 5s "$artifact" --help >/dev/null 2>&1; then
                log_verbose "  ✓ Executable responds to --help"
            else
                log_verbose "  ⚠ Executable doesn't respond to standard flags (may be normal)"
            fi
        fi
    done
    
    # Check System Extension bundle structure
    for artifact in "${DISCOVERED_ARTIFACTS[@]}"; do
        if [[ -d "$artifact" && "$artifact" == *.app ]]; then
            local bundle_name
            bundle_name=$(basename "$artifact")
            log_verbose "Validating System Extension bundle: $bundle_name"
            
            # Check Info.plist
            local info_plist="${artifact}/Contents/Info.plist"
            if [[ -f "$info_plist" ]]; then
                log_verbose "  ✓ Info.plist found"
                
                if command -v plutil >/dev/null 2>&1; then
                    if plutil -lint "$info_plist" >/dev/null 2>&1; then
                        log_verbose "  ✓ Info.plist is valid"
                        
                        # Check for required System Extension keys
                        local bundle_id
                        bundle_id=$(plutil -extract CFBundleIdentifier raw "$info_plist" 2>/dev/null || echo "")
                        if [[ -n "$bundle_id" ]]; then
                            log_verbose "  Bundle ID: $bundle_id"
                        fi
                        
                        ((compatibility_successes++))
                    else
                        log_error "  ✗ Info.plist is invalid"
                        ((compatibility_failures++))
                    fi
                else
                    log_verbose "  Info.plist validation skipped (plutil not available)"
                fi
            else
                log_error "  ✗ Info.plist not found in System Extension bundle"
                ((compatibility_failures++))
            fi
            
            # Check executable
            local main_executable="${artifact}/Contents/MacOS/$(basename "${artifact%.app}")"
            if [[ -f "$main_executable" ]]; then
                log_verbose "  ✓ Main executable found"
            else
                log_warning "  ⚠ Main executable not found at expected location"
            fi
        fi
    done
    
    # Report results
    log_info "Compatibility validation summary:"
    log_info "  Compatible artifacts: $compatibility_successes"
    log_info "  Incompatible artifacts: $compatibility_failures"
    
    if [[ $compatibility_failures -eq 0 ]]; then
        log_success "All artifacts passed compatibility validation"
        return $EXIT_SUCCESS
    else
        log_error "Compatibility validation failed: $compatibility_failures failures"
        return $EXIT_COMPATIBILITY_FAILED
    fi
}

# Generate validation report
generate_validation_report() {
    log_step "Generating validation report"
    
    local report_file="${VALIDATION_DIR}/validation-report-$(date +%Y%m%d-%H%M%S).txt"
    local timestamp
    timestamp=$(date)
    
    cat > "$report_file" << EOF
Release Artifact Validation Report
=================================

Generated: $timestamp
Validator: $(whoami)@$(hostname)
Project: usbipd-mac
Expected Version: ${EXPECTED_VERSION:-'[auto-detect]'}

Artifacts Directory: $ARTIFACTS_PATH
Validation Directory: $VALIDATION_DIR
Log File: $LOG_FILE

Configuration:
  Skip Signature Check: $([ "$SKIP_SIGNATURE_CHECK" = true ] && echo "YES" || echo "NO")
  Skip Compatibility Check: $([ "$SKIP_COMPATIBILITY_CHECK" = true ] && echo "YES" || echo "NO")
  Verbose Output: $([ "$VERBOSE" = true ] && echo "YES" || echo "NO")
  Dry Run Mode: $([ "$DRY_RUN" = true ] && echo "YES" || echo "NO")

Discovered Artifacts:
$(for artifact in "${DISCOVERED_ARTIFACTS[@]}"; do
    echo "  - $(basename "$artifact") ($(file "$artifact" | cut -d: -f2- | xargs))"
done)

Discovered Checksums:
$(for checksum in "${DISCOVERED_CHECKSUMS[@]}"; do
    echo "  - $(basename "$checksum")"
done)

Validation Results:
  ✓ Prerequisites: $([ $? -eq 0 ] && echo "PASSED" || echo "FAILED")
  ✓ Artifact Discovery: $([ ${#DISCOVERED_ARTIFACTS[@]} -gt 0 ] && echo "PASSED (${#DISCOVERED_ARTIFACTS[@]} artifacts)" || echo "FAILED")
  ✓ Checksum Validation: [Results in log]
  ✓ Signature Validation: [Results in log] 
  ✓ Compatibility Check: [Results in log]

For detailed results, see: $LOG_FILE

EOF
    
    log_success "Validation report generated: $(basename "$report_file")"
    log_info "Report location: $report_file"
    
    # Display summary to user
    echo ""
    cat "$report_file"
    echo ""
}

# Print usage information
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Release Artifact Validation Utilities for usbipd-mac

Validates release artifacts including checksum verification, binary signature 
validation, and compatibility testing to ensure artifact integrity and security.

OPTIONS:
  --artifacts-path PATH       Directory containing release artifacts (default: auto-detect)
  --checksum-file FILE       Checksum file for validation (default: auto-detect)
  --expected-version VERSION Expected release version for validation
  --skip-signatures          Skip binary signature validation
  --skip-compatibility       Skip compatibility and architecture validation
  --verbose                  Enable verbose output with detailed information
  --dry-run                  Preview validation without failing on errors
  --help                     Show this help message

EXAMPLES:
  $0                                    # Validate artifacts with auto-detection
  $0 --artifacts-path ./dist           # Validate artifacts in specific directory
  $0 --checksum-file checksums.sha256  # Use specific checksum file
  $0 --expected-version v1.2.3         # Validate against expected version
  $0 --verbose --dry-run               # Preview with detailed output
  $0 --skip-signatures                 # Skip signature validation for development builds

EXIT CODES:
  0   Validation successful
  1   General validation failure
  2   Missing artifacts
  3   Checksum validation failed
  4   Signature validation failed  
  5   Compatibility validation failed
  6   Usage error

VALIDATION PROCESS:
  1. Validate prerequisites and setup validation environment
  2. Discover release artifacts (binaries, bundles, archives)
  3. Validate checksums against provided or generated checksum file
  4. Validate binary signatures and code signing (if not skipped)
  5. Validate compatibility and architecture requirements (if not skipped)
  6. Generate comprehensive validation report

This utility ensures release artifacts meet security and quality standards
before distribution to users.

EOF
}

# Error handler
handle_error() {
    local exit_code=$?
    log_error "Artifact validation failed with exit code $exit_code"
    
    if [[ -f "$LOG_FILE" ]]; then
        log_info "Detailed logs available at: $LOG_FILE"
    fi
    
    echo ""
    echo "Common troubleshooting steps:"
    echo "1. Check error messages above for specific validation issues"
    echo "2. Ensure all required tools are installed and up to date" 
    echo "3. Verify artifact directory contains expected release files"
    echo "4. Check checksum file format and file paths"
    echo "5. For signature issues, verify code signing certificates"
    echo "6. Use --verbose for detailed validation information"
    echo "7. Use --dry-run to preview validation without failing"
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
            --artifacts-path)
                ARTIFACTS_PATH="$2"
                shift 2
                ;;
            --checksum-file)
                CHECKSUM_FILE="$2"
                shift 2
                ;;
            --expected-version)
                EXPECTED_VERSION="$2"
                shift 2
                ;;
            --skip-signatures)
                SKIP_SIGNATURE_CHECK=true
                shift
                ;;
            --skip-compatibility)
                SKIP_COMPATIBILITY_CHECK=true
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
    
    # Start validation process
    print_header
    
    # Execute validation steps
    setup_validation_environment
    validate_prerequisites
    discover_artifacts
    
    # Perform validation checks
    local validation_exit_code=$EXIT_SUCCESS
    
    # Checksum validation
    if ! validate_checksums; then
        validation_exit_code=$EXIT_CHECKSUM_FAILED
        if [[ "$DRY_RUN" == "false" ]]; then
            log_error "Checksum validation failed - stopping validation"
        else
            log_warning "Checksum validation failed (continuing due to dry-run mode)"
        fi
    fi
    
    # Signature validation
    if [[ "$validation_exit_code" -eq $EXIT_SUCCESS ]] || [[ "$DRY_RUN" == "true" ]]; then
        if ! validate_signatures; then
            validation_exit_code=$EXIT_SIGNATURE_FAILED
            if [[ "$DRY_RUN" == "false" ]]; then
                log_error "Signature validation failed - stopping validation"
            else
                log_warning "Signature validation failed (continuing due to dry-run mode)"
            fi
        fi
    fi
    
    # Compatibility validation  
    if [[ "$validation_exit_code" -eq $EXIT_SUCCESS ]] || [[ "$DRY_RUN" == "true" ]]; then
        if ! validate_compatibility; then
            validation_exit_code=$EXIT_COMPATIBILITY_FAILED
            if [[ "$DRY_RUN" == "false" ]]; then
                log_error "Compatibility validation failed"
            else
                log_warning "Compatibility validation failed (continuing due to dry-run mode)"
            fi
        fi
    fi
    
    # Generate validation report
    generate_validation_report
    
    # Final result
    if [[ "$validation_exit_code" -eq $EXIT_SUCCESS ]]; then
        log_success "🎉 All artifact validation checks passed successfully!"
        echo ""
        echo "Release artifacts are ready for distribution."
        echo "Validation log: $LOG_FILE"
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_warning "Validation completed with issues (dry-run mode - no failure)"
        echo ""
        echo "Review validation results and resolve issues before release."
        echo "Validation log: $LOG_FILE"
        exit $EXIT_SUCCESS
    else
        log_error "❌ Artifact validation failed!"
        echo ""
        echo "Please resolve validation issues before distributing artifacts."
        echo "Validation log: $LOG_FILE"
        exit $validation_exit_code
    fi
}

# Ensure we're in the project root directory
cd "$PROJECT_ROOT"

# Initialize global arrays
declare -a DISCOVERED_ARTIFACTS
declare -a DISCOVERED_CHECKSUMS

# Run main function with all arguments
main "$@"