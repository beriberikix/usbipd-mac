#!/bin/bash

# QEMU USB/IP Test Tool - Image Creation Script
# Creates a minimal Linux image with USB/IP client capabilities for testing

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/.build/qemu"
readonly IMAGE_NAME="qemu-usbip-client"
readonly LOG_FILE="${BUILD_DIR}/image-creation.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC} ${message}"
    if [[ -f "${LOG_FILE}" ]]; then
        echo "[INFO] ${message}" >> "${LOG_FILE}"
    fi
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} ${message}"
    if [[ -f "${LOG_FILE}" ]]; then
        echo "[SUCCESS] ${message}" >> "${LOG_FILE}"
    fi
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} ${message}"
    if [[ -f "${LOG_FILE}" ]]; then
        echo "[WARNING] ${message}" >> "${LOG_FILE}"
    fi
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} ${message}"
    if [[ -f "${LOG_FILE}" ]]; then
        echo "[ERROR] ${message}" >> "${LOG_FILE}"
    fi
}

# Error handling
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code"
        log_info "Check log file: ${LOG_FILE}"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Dependency validation functions
check_command() {
    local cmd="$1"
    local package_hint="${2:-}"
    
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command '$cmd' not found"
        if [[ -n "$package_hint" ]]; then
            log_info "Install with: $package_hint"
        fi
        return 1
    fi
    return 0
}

validate_qemu() {
    log_info "Validating QEMU installation..."
    
    if ! check_command "qemu-system-x86_64" "brew install qemu"; then
        return 1
    fi
    
    if ! check_command "qemu-img" "brew install qemu"; then
        return 1
    fi
    
    # Check QEMU version
    local qemu_version
    qemu_version=$(qemu-system-x86_64 --version | head -n1)
    log_info "Found QEMU: $qemu_version"
    
    return 0
}

validate_download_tools() {
    log_info "Validating download tools..."
    
    # Check for wget or curl
    if ! check_command "wget" "brew install wget" && ! check_command "curl" "curl is usually pre-installed"; then
        log_error "Neither wget nor curl found - need at least one for downloads"
        return 1
    fi
    
    return 0
}

validate_disk_utilities() {
    log_info "Validating disk utilities..."
    
    # Check for basic disk utilities (should be available on macOS)
    if ! check_command "dd" "dd is a system utility"; then
        return 1
    fi
    
    if ! check_command "mount" "mount is a system utility"; then
        return 1
    fi
    
    return 0
}

validate_dependencies() {
    log_info "Validating required dependencies..."
    
    local validation_failed=false
    
    if ! validate_qemu; then
        validation_failed=true
    fi
    
    if ! validate_download_tools; then
        validation_failed=true
    fi
    
    if ! validate_disk_utilities; then
        validation_failed=true
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        log_error "Dependency validation failed"
        return 1
    fi
    
    log_success "All dependencies validated successfully"
    return 0
}

# Setup functions
setup_build_environment() {
    log_info "Setting up build environment..."
    
    # Create build directory
    mkdir -p "${BUILD_DIR}"
    
    # Initialize log file
    echo "QEMU Image Creation Log - $(date)" > "${LOG_FILE}"
    
    log_success "Build environment ready at: ${BUILD_DIR}"
}

# Main execution
main() {
    log_info "Starting QEMU image creation script"
    log_info "Project root: ${PROJECT_ROOT}"
    log_info "Build directory: ${BUILD_DIR}"
    
    # Setup build environment
    setup_build_environment
    
    # Validate all dependencies
    if ! validate_dependencies; then
        log_error "Cannot proceed without required dependencies"
        exit 1
    fi
    
    log_success "QEMU image creation script foundation ready"
    log_info "Next steps will implement image download and preparation"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi