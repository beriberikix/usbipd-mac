#!/bin/bash

# generate-completions.sh
# Standalone script for generating shell completion scripts
# Uses the usbipd completion command to generate completion scripts for bash, zsh, and fish
# Provides error handling and output directory management for release workflow integration

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build"
DEFAULT_OUTPUT_DIR="$PROJECT_ROOT/completions"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
VERBOSE=false
OUTPUT_DIR=""
SHELLS=()
VALIDATE=true
CLEAN=false

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

log_debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BOLD}[DEBUG]${NC} $1"
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Generate shell completion scripts for usbipd using the completion command.

OPTIONS:
    -o, --output DIR        Output directory for completion scripts (default: $DEFAULT_OUTPUT_DIR)
    -s, --shell SHELL       Generate for specific shell (bash, zsh, fish) - can be repeated
    --no-validate           Skip validation of generated completion scripts
    --clean                 Clean output directory before generation
    -v, --verbose           Enable verbose output
    -h, --help              Show this help message

EXAMPLES:
    $0                                    # Generate all completions to default directory
    $0 -o ./dist/completions             # Generate to custom directory
    $0 -s bash -s zsh                    # Generate only bash and zsh completions
    $0 --clean -v                        # Clean directory and generate with verbose output

NOTES:
    - Requires usbipd binary to be built (runs 'swift build' if needed)
    - Generated scripts are suitable for distribution via Homebrew
    - Validation ensures completion scripts are syntactically correct
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -s|--shell)
                SHELLS+=("$2")
                shift 2
                ;;
            --no-validate)
                VALIDATE=false
                shift
                ;;
            --clean)
                CLEAN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set default output directory if not specified
    if [ -z "$OUTPUT_DIR" ]; then
        OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
    fi
    
    log_debug "Parsed arguments:"
    log_debug "  Output directory: $OUTPUT_DIR"
    log_debug "  Shells: ${SHELLS[*]:-all}"
    log_debug "  Validate: $VALIDATE"
    log_debug "  Clean: $CLEAN"
    log_debug "  Verbose: $VERBOSE"
}

# Validate environment and prerequisites
validate_environment() {
    log_info "Validating environment..."
    
    # Check if we're in the correct directory
    if [ ! -f "$PROJECT_ROOT/Package.swift" ]; then
        log_error "Package.swift not found. Please run this script from the project root or Scripts directory."
        exit 1
    fi
    
    # Check if swift is available
    if ! command -v swift >/dev/null 2>&1; then
        log_error "Swift is not installed or not in PATH"
        exit 1
    fi
    
    # Check if git is available (for version detection)
    if ! command -v git >/dev/null 2>&1; then
        log_warning "Git is not available - version detection may be limited"
    fi
    
    log_debug "Environment validation successful"
}

# Build usbipd if needed
ensure_usbipd_built() {
    log_info "Ensuring usbipd is built..."
    
    local usbipd_binary="$BUILD_DIR/debug/usbipd"
    
    # Check if binary exists and is newer than source files
    if [ -f "$usbipd_binary" ]; then
        local binary_time=$(stat -f %m "$usbipd_binary" 2>/dev/null || echo 0)
        local source_time=$(find "$PROJECT_ROOT/Sources" -name "*.swift" -exec stat -f %m {} \; 2>/dev/null | sort -nr | head -n1 || echo 0)
        
        if [ "$binary_time" -gt "$source_time" ]; then
            log_debug "usbipd binary is up to date"
            return 0
        fi
    fi
    
    log_info "Building usbipd..."
    cd "$PROJECT_ROOT"
    
    if [ "$VERBOSE" = true ]; then
        swift build --product usbipd
    else
        swift build --product usbipd >/dev/null 2>&1
    fi
    
    if [ $? -ne 0 ]; then
        log_error "Failed to build usbipd"
        exit 1
    fi
    
    log_success "usbipd built successfully"
}

# Prepare output directory
prepare_output_directory() {
    log_info "Preparing output directory: $OUTPUT_DIR"
    
    # Clean directory if requested
    if [ "$CLEAN" = true ] && [ -d "$OUTPUT_DIR" ]; then
        log_info "Cleaning existing output directory..."
        rm -rf "$OUTPUT_DIR"
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Verify directory is writable
    if [ ! -w "$OUTPUT_DIR" ]; then
        log_error "Output directory is not writable: $OUTPUT_DIR"
        exit 1
    fi
    
    log_debug "Output directory prepared: $OUTPUT_DIR"
}

# Generate completion scripts
generate_completions() {
    log_info "Generating shell completion scripts..."
    
    local usbipd_binary="$BUILD_DIR/debug/usbipd"
    local completion_args=("completion" "generate" "--output" "$OUTPUT_DIR")
    
    # Add shell-specific arguments
    for shell in "${SHELLS[@]}"; do
        completion_args+=("--shell" "$shell")
    done
    
    # Add verbose flag if enabled
    if [ "$VERBOSE" = true ]; then
        completion_args+=("--verbose")
    fi
    
    log_debug "Running: $usbipd_binary ${completion_args[*]}"
    
    # Change to project root for proper execution context
    cd "$PROJECT_ROOT"
    
    # Execute completion generation
    if ! "$usbipd_binary" "${completion_args[@]}"; then
        log_error "Failed to generate completion scripts"
        exit 1
    fi
    
    log_success "Completion scripts generated successfully"
}

# Validate generated completion scripts
validate_completions() {
    if [ "$VALIDATE" = false ]; then
        log_debug "Skipping completion validation (--no-validate specified)"
        return 0
    fi
    
    log_info "Validating generated completion scripts..."
    
    local usbipd_binary="$BUILD_DIR/debug/usbipd"
    local validation_args=("completion" "validate" "--output" "$OUTPUT_DIR")
    
    # Add shell-specific arguments
    for shell in "${SHELLS[@]}"; do
        validation_args+=("--shell" "$shell")
    done
    
    log_debug "Running: $usbipd_binary ${validation_args[*]}"
    
    # Execute validation
    if ! "$usbipd_binary" "${validation_args[@]}"; then
        log_warning "Completion script validation failed - scripts may have issues"
        return 1
    fi
    
    log_success "Completion scripts validated successfully"
}

# Display generation summary
display_summary() {
    log_info "Completion Generation Summary"
    echo "=============================="
    echo "Output Directory: $OUTPUT_DIR"
    echo "Generated Files:"
    
    if [ -d "$OUTPUT_DIR" ]; then
        local file_count=0
        for file in "$OUTPUT_DIR"/*; do
            if [ -f "$file" ]; then
                local filename=$(basename "$file")
                local size=$(stat -f %z "$file" 2>/dev/null || echo "unknown")
                echo "  ✓ $filename ($size bytes)"
                ((file_count++))
            fi
        done
        
        if [ $file_count -eq 0 ]; then
            echo "  (no files generated)"
        else
            echo ""
            echo "Total files generated: $file_count"
        fi
    else
        echo "  (output directory not found)"
    fi
    
    echo ""
    echo "Installation Instructions:"
    echo "  Bash:  Copy usbipd to /usr/local/etc/bash_completion.d/ or ~/.bash_completion"
    echo "  Zsh:   Copy _usbipd to a directory in \$FPATH (e.g., /usr/local/share/zsh/site-functions/)"
    echo "  Fish:  Copy usbipd.fish to ~/.config/fish/completions/"
    echo ""
    echo "Homebrew Integration:"
    echo "  These scripts will be automatically installed by the Homebrew formula"
    echo "  during 'brew install usbip' when distributed via the tap repository."
}

# Error handling
handle_error() {
    local exit_code=$?
    log_error "Script failed with exit code $exit_code"
    
    if [ -d "$OUTPUT_DIR" ] && [ "$CLEAN" = true ]; then
        log_info "Cleaning up partial generation..."
        rm -rf "$OUTPUT_DIR"
    fi
    
    exit $exit_code
}

# Set up error handling
trap handle_error ERR

# Main execution
main() {
    log_info "Shell Completion Generator for usbipd-mac"
    echo "=========================================="
    
    parse_arguments "$@"
    validate_environment
    ensure_usbipd_built
    prepare_output_directory
    generate_completions
    validate_completions
    display_summary
    
    log_success "Shell completion generation completed successfully!"
}

# Execute main function with all arguments
main "$@"