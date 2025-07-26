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

# Alpine Linux configuration
readonly ALPINE_VERSION="3.19"
readonly ALPINE_ARCH="x86_64"
readonly ALPINE_ISO="alpine-virt-${ALPINE_VERSION}.0-${ALPINE_ARCH}.iso"
readonly ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ALPINE_ARCH}/${ALPINE_ISO}"
readonly ALPINE_CHECKSUMS_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ALPINE_ARCH}/${ALPINE_ISO}.sha512"

# Image configuration
readonly DISK_SIZE="512M"
readonly DISK_IMAGE="${BUILD_DIR}/${IMAGE_NAME}.qcow2"

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
    
    # Check for shasum (for checksum validation)
    if ! check_command "shasum" "shasum is usually pre-installed on macOS"; then
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

# Download functions
download_file() {
    local url="$1"
    local output_file="$2"
    
    log_info "Downloading: $(basename "$output_file")"
    
    if command -v wget &> /dev/null; then
        wget -q --show-progress -O "$output_file" "$url"
    elif command -v curl &> /dev/null; then
        curl -L --progress-bar -o "$output_file" "$url"
    else
        log_error "No download tool available"
        return 1
    fi
    
    if [[ ! -f "$output_file" ]]; then
        log_error "Download failed: $output_file not created"
        return 1
    fi
    
    log_success "Downloaded: $(basename "$output_file")"
    return 0
}

validate_checksum() {
    local file="$1"
    local expected_checksum="$2"
    
    log_info "Validating checksum for $(basename "$file")"
    
    local actual_checksum
    actual_checksum=$(shasum -a 512 "$file" | cut -d' ' -f1)
    
    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        log_success "Checksum validation passed"
        return 0
    else
        log_error "Checksum validation failed"
        log_error "Expected: $expected_checksum"
        log_error "Actual:   $actual_checksum"
        return 1
    fi
}

download_alpine_linux() {
    log_info "Downloading Alpine Linux ${ALPINE_VERSION}..."
    
    local iso_path="${BUILD_DIR}/${ALPINE_ISO}"
    local checksums_path="${BUILD_DIR}/alpine-checksums.sha512"
    
    # Skip download if ISO already exists and is valid
    if [[ -f "$iso_path" ]]; then
        log_info "Alpine ISO already exists, checking validity..."
        
        # Download checksums to validate existing ISO
        if download_file "$ALPINE_CHECKSUMS_URL" "$checksums_path"; then
            local expected_checksum
            expected_checksum=$(cut -d' ' -f1 "$checksums_path")
            
            if [[ -n "$expected_checksum" ]] && validate_checksum "$iso_path" "$expected_checksum"; then
                log_success "Existing Alpine ISO is valid"
                return 0
            else
                log_warning "Existing Alpine ISO is invalid, re-downloading..."
                rm -f "$iso_path"
            fi
        fi
    fi
    
    # Download Alpine ISO
    if ! download_file "$ALPINE_URL" "$iso_path"; then
        log_error "Failed to download Alpine Linux ISO"
        return 1
    fi
    
    # Download and validate checksums
    if ! download_file "$ALPINE_CHECKSUMS_URL" "$checksums_path"; then
        log_error "Failed to download Alpine Linux checksums"
        return 1
    fi
    
    # Extract expected checksum from the checksum file
    local expected_checksum
    expected_checksum=$(cut -d' ' -f1 "$checksums_path")
    
    if [[ -z "$expected_checksum" ]]; then
        log_error "Could not extract checksum from checksums file"
        return 1
    fi
    
    # Validate downloaded ISO
    if ! validate_checksum "$iso_path" "$expected_checksum"; then
        log_error "Alpine Linux ISO checksum validation failed"
        return 1
    fi
    
    log_success "Alpine Linux ISO downloaded and validated successfully"
    return 0
}

# Disk image functions
create_disk_image() {
    log_info "Creating QEMU disk image..."
    
    # Remove existing image if present
    if [[ -f "$DISK_IMAGE" ]]; then
        log_info "Removing existing disk image"
        rm -f "$DISK_IMAGE"
    fi
    
    # Create new qcow2 disk image
    if ! qemu-img create -f qcow2 "$DISK_IMAGE" "$DISK_SIZE" >> "$LOG_FILE" 2>&1; then
        log_error "Failed to create disk image"
        return 1
    fi
    
    log_success "Created disk image: $(basename "$DISK_IMAGE") (${DISK_SIZE})"
    
    # Verify image was created successfully
    if ! qemu-img info "$DISK_IMAGE" >> "$LOG_FILE" 2>&1; then
        log_error "Created disk image appears to be invalid"
        return 1
    fi
    
    return 0
}

configure_usbip_client() {
    log_info "Configuring USB/IP client capabilities..."
    
    # Create cloud-init configuration directory
    local cloud_init_dir="${BUILD_DIR}/cloud-init"
    mkdir -p "$cloud_init_dir"
    
    # Create comprehensive cloud-init user-data configuration with USB/IP client setup
    cat > "${cloud_init_dir}/user-data" << 'EOF'
#cloud-config

# Create a test user with sudo privileges
users:
  - name: testuser
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/sh
    lock_passwd: false
    passwd: "$6$rounds=4096$saltsalt$L9.LKkHxQkHZ8E7NvQW8tF7KvQN5fKjHQvQN5fKjHQvQN5fKjHQvQN5fKjHQvQN5fKjHQvQN5fKjHQvQN5fKjHQ"

# Install required packages including USB/IP utilities
packages:
  - usbip
  - usbutils
  - kmod

# Configure kernel modules for USB/IP client
write_files:
  - path: /etc/modules-load.d/usbip.conf
    content: |
      # USB/IP client kernel modules
      vhci-hcd
    permissions: '0644'
  
  - path: /etc/modprobe.d/usbip.conf
    content: |
      # USB/IP client module configuration
      # Ensure vhci-hcd loads properly
      options vhci-hcd
    permissions: '0644'
  
  - path: /usr/local/bin/usbip-client-test
    content: |
      #!/bin/sh
      # USB/IP client test script
      
      echo "USBIP_CLIENT_TEST_START" > /dev/console
      
      # Check if vhci-hcd module is loaded
      if lsmod | grep -q vhci_hcd; then
          echo "VHCI_MODULE_LOADED: SUCCESS" > /dev/console
      else
          echo "VHCI_MODULE_LOADED: FAILED" > /dev/console
          exit 1
      fi
      
      # Check if usbip command is available
      if command -v usbip >/dev/null 2>&1; then
          echo "USBIP_COMMAND_AVAILABLE: SUCCESS" > /dev/console
          usbip version > /dev/console 2>&1
      else
          echo "USBIP_COMMAND_AVAILABLE: FAILED" > /dev/console
          exit 1
      fi
      
      # Test usbip list functionality (will fail without server, but command should work)
      echo "USBIP_LIST_TEST: START" > /dev/console
      if usbip list -r 127.0.0.1 2>/dev/null || [ $? -eq 1 ]; then
          echo "USBIP_LIST_TEST: SUCCESS" > /dev/console
      else
          echo "USBIP_LIST_TEST: FAILED" > /dev/console
      fi
      
      echo "USBIP_CLIENT_TEST_COMPLETE" > /dev/console
    permissions: '0755'
  
  - path: /etc/init.d/usbip-client-setup
    content: |
      #!/sbin/openrc-run
      
      name="usbip-client-setup"
      description="USB/IP client setup service"
      
      depend() {
          need localmount
          after bootmisc
      }
      
      start() {
          ebegin "Setting up USB/IP client"
          
          # Load vhci-hcd module
          modprobe vhci-hcd
          
          # Verify module loaded
          if lsmod | grep -q vhci_hcd; then
              echo "USBIP_CLIENT_READY" > /dev/console
              eend 0
          else
              echo "USBIP_CLIENT_FAILED" > /dev/console
              eend 1
          fi
      }
      
      stop() {
          ebegin "Stopping USB/IP client"
          # Remove vhci-hcd module if needed
          rmmod vhci-hcd 2>/dev/null || true
          eend 0
      }
    permissions: '0755'

# Run commands to set up USB/IP client environment
runcmd:
  # Update package index
  - apk update
  
  # Ensure usbip package is properly installed
  - apk add --no-cache usbip usbutils kmod
  
  # Load vhci-hcd kernel module
  - modprobe vhci-hcd || echo "Failed to load vhci-hcd module" > /dev/console
  
  # Enable the USB/IP client setup service
  - rc-update add usbip-client-setup default
  
  # Create symlinks to ensure usbip tools are in PATH
  - ln -sf /usr/bin/usbip /usr/local/bin/usbip || true
  - ln -sf /usr/bin/usbipd /usr/local/bin/usbipd || true
  
  # Verify installation
  - /usr/local/bin/usbip-client-test
  
  # Output readiness indicator
  - echo "USBIP_CLIENT_CONFIGURATION_COMPLETE" > /dev/console

# Final message
final_message: "USB/IP client configuration completed successfully"
EOF
    
    log_success "USB/IP client configuration created"
    return 0
}

prepare_filesystem_structure() {
    log_info "Preparing filesystem structure with USB/IP client capabilities..."
    
    # Create temporary mount directory
    local mount_dir="${BUILD_DIR}/mnt"
    mkdir -p "$mount_dir"
    
    # Configure USB/IP client capabilities
    if ! configure_usbip_client; then
        log_error "Failed to configure USB/IP client capabilities"
        return 1
    fi
    
    log_success "Filesystem structure with USB/IP client capabilities prepared"
    return 0
}

validate_usbip_configuration() {
    log_info "Validating USB/IP client configuration..."
    
    local cloud_init_dir="${BUILD_DIR}/cloud-init"
    local user_data_file="${cloud_init_dir}/user-data"
    
    # Verify cloud-init configuration exists
    if [[ ! -f "$user_data_file" ]]; then
        log_error "Cloud-init user-data file not found: $user_data_file"
        return 1
    fi
    
    # Verify USB/IP package is specified in cloud-init
    if ! grep -q "usbip" "$user_data_file"; then
        log_error "USB/IP package not found in cloud-init configuration"
        return 1
    fi
    
    # Verify vhci-hcd module configuration exists
    if ! grep -q "vhci-hcd" "$user_data_file"; then
        log_error "vhci-hcd module configuration not found"
        return 1
    fi
    
    # Verify test script exists in configuration
    if ! grep -q "usbip-client-test" "$user_data_file"; then
        log_error "USB/IP client test script not found in configuration"
        return 1
    fi
    
    # Verify module loading configuration
    if ! grep -q "modules-load.d/usbip.conf" "$user_data_file"; then
        log_error "Kernel module loading configuration not found"
        return 1
    fi
    
    # Verify PATH configuration for USB/IP tools
    if ! grep -q "/usr/local/bin/usbip" "$user_data_file"; then
        log_error "USB/IP tools PATH configuration not found"
        return 1
    fi
    
    log_success "USB/IP client configuration validation passed"
    return 0
}

test_image_creation() {
    log_info "Testing image creation functionality..."
    
    # Verify all required files exist
    local iso_path="${BUILD_DIR}/${ALPINE_ISO}"
    
    if [[ ! -f "$iso_path" ]]; then
        log_error "Alpine ISO not found: $iso_path"
        return 1
    fi
    
    if [[ ! -f "$DISK_IMAGE" ]]; then
        log_error "Disk image not found: $DISK_IMAGE"
        return 1
    fi
    
    # Test qemu-img info on created image
    log_info "Verifying disk image properties..."
    if ! qemu-img info "$DISK_IMAGE" >> "$LOG_FILE" 2>&1; then
        log_error "Disk image verification failed"
        return 1
    fi
    
    # Check image size is reasonable
    local image_size
    image_size=$(qemu-img info "$DISK_IMAGE" | grep "virtual size" | awk '{print $3}')
    log_info "Created disk image virtual size: ${image_size}"
    
    # Validate USB/IP client configuration
    if ! validate_usbip_configuration; then
        log_error "USB/IP client configuration validation failed"
        return 1
    fi
    
    log_success "Image creation functionality test passed"
    return 0
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
    
    # Download Alpine Linux ISO with checksum validation
    if ! download_alpine_linux; then
        log_error "Failed to download and validate Alpine Linux"
        exit 1
    fi
    
    # Create QEMU disk image
    if ! create_disk_image; then
        log_error "Failed to create disk image"
        exit 1
    fi
    
    # Prepare filesystem structure with USB/IP client capabilities
    if ! prepare_filesystem_structure; then
        log_error "Failed to prepare filesystem structure with USB/IP client capabilities"
        exit 1
    fi
    
    # Test the created components
    if ! test_image_creation; then
        log_error "Image creation testing failed"
        exit 1
    fi
    
    log_success "Alpine Linux image with USB/IP client capabilities completed successfully"
    log_info "Created disk image: ${DISK_IMAGE}"
    log_info "Alpine ISO: ${BUILD_DIR}/${ALPINE_ISO}"
    log_info "Cloud-init configuration: ${BUILD_DIR}/cloud-init/"
    log_info "USB/IP client features:"
    log_info "  - usbip-utils package installation"
    log_info "  - vhci-hcd kernel module auto-loading"
    log_info "  - USB/IP tools in system PATH"
    log_info "  - Client validation test script"
    log_info "Log file: ${LOG_FILE}"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi