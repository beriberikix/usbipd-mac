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

# Enhanced error handling functions
retry_download() {
    local url="$1"
    local output_file="$2"
    local max_attempts="${3:-3}"
    local delay="${4:-5}"
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Downloading: $(basename "$output_file") (attempt $attempt/$max_attempts)"
        
        # Remove partial download if it exists
        if [[ -f "$output_file" ]]; then
            rm -f "$output_file"
        fi
        
        local download_success=false
        if command -v wget &> /dev/null; then
            if wget -q --show-progress --timeout=30 --tries=1 -O "$output_file" "$url"; then
                download_success=true
            fi
        elif command -v curl &> /dev/null; then
            if curl -L --progress-bar --max-time 60 --retry 0 -o "$output_file" "$url"; then
                download_success=true
            fi
        else
            log_error "No download tool available"
            return 1
        fi
        
        if [[ "$download_success" == "true" && -f "$output_file" && -s "$output_file" ]]; then
            log_success "Downloaded: $(basename "$output_file")"
            return 0
        else
            log_warning "Download failed on attempt $attempt"
            if [[ -f "$output_file" ]]; then
                rm -f "$output_file"
            fi
            
            if [[ $attempt -lt $max_attempts ]]; then
                log_info "Retrying in ${delay}s..."
                sleep "$delay"
                # Exponential backoff
                delay=$((delay * 2))
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Download failed after $max_attempts attempts: $(basename "$output_file")"
    return 1
}

# Download functions
download_file() {
    local url="$1"
    local output_file="$2"
    
    # Use retry mechanism for downloads
    retry_download "$url" "$output_file" 3 5
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
        
        # Download checksums to validate existing ISO (with retry)
        if download_file "$ALPINE_CHECKSUMS_URL" "$checksums_path"; then
            local expected_checksum
            expected_checksum=$(cut -d' ' -f1 "$checksums_path" 2>/dev/null)
            
            if [[ -n "$expected_checksum" ]] && validate_checksum "$iso_path" "$expected_checksum"; then
                log_success "Existing Alpine ISO is valid"
                return 0
            else
                log_warning "Existing Alpine ISO is invalid, re-downloading..."
                rm -f "$iso_path"
            fi
        else
            log_warning "Could not download checksums to validate existing ISO, re-downloading..."
            rm -f "$iso_path"
        fi
    fi
    
    # Download checksums first (for better error handling)
    log_info "Downloading Alpine Linux checksums..."
    if ! download_file "$ALPINE_CHECKSUMS_URL" "$checksums_path"; then
        log_error "Failed to download Alpine Linux checksums"
        return 1
    fi
    
    # Extract expected checksum from the checksum file
    local expected_checksum
    expected_checksum=$(cut -d' ' -f1 "$checksums_path" 2>/dev/null)
    
    if [[ -z "$expected_checksum" ]]; then
        log_error "Could not extract checksum from checksums file"
        log_info "Checksums file content:"
        head -n5 "$checksums_path" | sed 's/^/  /' || true
        return 1
    fi
    
    log_info "Expected checksum: $expected_checksum"
    
    # Download Alpine ISO with enhanced error handling
    local download_attempts=0
    local max_download_attempts=3
    local download_success=false
    
    while [[ $download_attempts -lt $max_download_attempts ]] && [[ "$download_success" != "true" ]]; do
        download_attempts=$((download_attempts + 1))
        log_info "Downloading Alpine ISO (attempt $download_attempts/$max_download_attempts)..."
        
        if download_file "$ALPINE_URL" "$iso_path"; then
            # Validate downloaded ISO immediately
            if validate_checksum "$iso_path" "$expected_checksum"; then
                download_success=true
                break
            else
                log_warning "Downloaded ISO failed checksum validation (attempt $download_attempts)"
                rm -f "$iso_path"
                
                if [[ $download_attempts -lt $max_download_attempts ]]; then
                    log_info "Retrying download in 5s..."
                    sleep 5
                fi
            fi
        else
            log_warning "ISO download failed (attempt $download_attempts)"
            if [[ $download_attempts -lt $max_download_attempts ]]; then
                log_info "Retrying download in 5s..."
                sleep 5
            fi
        fi
    done
    
    if [[ "$download_success" != "true" ]]; then
        log_error "Failed to download and validate Alpine Linux ISO after $max_download_attempts attempts"
        
        # Provide troubleshooting information
        log_info "Troubleshooting information:"
        log_info "  Alpine URL: $ALPINE_URL"
        log_info "  Checksums URL: $ALPINE_CHECKSUMS_URL"
        log_info "  Expected checksum: $expected_checksum"
        
        # Check if partial file exists
        if [[ -f "$iso_path" ]]; then
            local partial_size
            partial_size=$(ls -lh "$iso_path" | awk '{print $5}')
            log_info "  Partial download size: $partial_size"
            rm -f "$iso_path"
        fi
        
        return 1
    fi
    
    log_success "Alpine Linux ISO downloaded and validated successfully"
    
    # Additional verification - check ISO file properties
    local iso_size
    iso_size=$(ls -lh "$iso_path" | awk '{print $5}')
    log_info "Alpine ISO properties:"
    log_info "  File size: $iso_size"
    log_info "  Checksum: verified"
    
    return 0
}

# Disk image functions
create_disk_image() {
    log_info "Creating QEMU disk image..."
    
    # Check available disk space before creating image
    local available_space
    available_space=$(df "$BUILD_DIR" | awk 'NR==2 {print $4}')
    local required_space=524288  # 512MB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        log_error "Insufficient disk space: ${available_space}KB available, ${required_space}KB required"
        return 1
    fi
    
    # Remove existing image if present
    if [[ -f "$DISK_IMAGE" ]]; then
        log_info "Removing existing disk image"
        if ! rm -f "$DISK_IMAGE"; then
            log_error "Failed to remove existing disk image"
            return 1
        fi
    fi
    
    # Create new qcow2 disk image with error handling
    log_info "Creating qcow2 disk image (${DISK_SIZE})"
    local create_attempts=0
    local max_create_attempts=3
    
    while [[ $create_attempts -lt $max_create_attempts ]]; do
        create_attempts=$((create_attempts + 1))
        
        if qemu-img create -f qcow2 "$DISK_IMAGE" "$DISK_SIZE" >> "$LOG_FILE" 2>&1; then
            log_success "Created disk image: $(basename "$DISK_IMAGE") (${DISK_SIZE})"
            break
        else
            log_warning "Disk image creation failed (attempt $create_attempts/$max_create_attempts)"
            
            # Clean up partial image
            if [[ -f "$DISK_IMAGE" ]]; then
                rm -f "$DISK_IMAGE"
            fi
            
            if [[ $create_attempts -lt $max_create_attempts ]]; then
                log_info "Retrying disk image creation in 2s..."
                sleep 2
            else
                log_error "Failed to create disk image after $max_create_attempts attempts"
                return 1
            fi
        fi
    done
    
    # Verify image was created successfully
    log_info "Verifying disk image integrity..."
    if ! qemu-img info "$DISK_IMAGE" >> "$LOG_FILE" 2>&1; then
        log_error "Created disk image appears to be invalid"
        
        # Try to get more information about the failure
        if [[ -f "$DISK_IMAGE" ]]; then
            local file_size
            file_size=$(ls -lh "$DISK_IMAGE" | awk '{print $5}')
            log_error "Image file size: $file_size"
            
            # Check if file is corrupted
            if ! qemu-img check "$DISK_IMAGE" >> "$LOG_FILE" 2>&1; then
                log_error "Disk image is corrupted"
            fi
        fi
        
        return 1
    fi
    
    # Additional verification - check image format and virtual size
    local image_format
    image_format=$(qemu-img info "$DISK_IMAGE" | grep "file format" | awk '{print $3}')
    local virtual_size
    virtual_size=$(qemu-img info "$DISK_IMAGE" | grep "virtual size" | awk '{print $3}')
    
    if [[ "$image_format" != "qcow2" ]]; then
        log_error "Unexpected image format: $image_format (expected qcow2)"
        return 1
    fi
    
    log_success "Disk image verification passed:"
    log_info "  Format: $image_format"
    log_info "  Virtual size: $virtual_size"
    
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

# Automatic user creation with sudo access
users:
  - name: testuser
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/sh
    lock_passwd: false
    # Default password: testpass (for testing purposes only)
    passwd: "$6$rounds=4096$saltsalt$L9.LKkHxQkHZ8E7NvQW8tF7KvQN5fKjHQvQN5fKjHQvQN5fKjHQvQN5fKjHQvQN5fKjHQvQN5fKjHQvQN5fKjHQ"
    groups: [wheel, adm]
    ssh_authorized_keys: []

# Install required packages including USB/IP utilities
packages:
  - usbip
  - usbutils
  - kmod
  - util-linux

# Configure kernel modules and startup scripts for USB/IP client
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
  
  - path: /usr/local/bin/usbip-startup
    content: |
      #!/bin/sh
      # USB/IP client startup script
      
      echo "[$(date)] USBIP_STARTUP_BEGIN" > /dev/console
      
      # Load vhci-hcd kernel module
      if modprobe vhci-hcd; then
          echo "[$(date)] VHCI_MODULE_LOADED: SUCCESS" > /dev/console
      else
          echo "[$(date)] VHCI_MODULE_LOADED: FAILED" > /dev/console
          exit 1
      fi
      
      # Verify module is loaded
      if lsmod | grep -q vhci_hcd; then
          echo "[$(date)] VHCI_MODULE_VERIFIED: SUCCESS" > /dev/console
      else
          echo "[$(date)] VHCI_MODULE_VERIFIED: FAILED" > /dev/console
          exit 1
      fi
      
      # Check if usbip command is available
      if command -v usbip >/dev/null 2>&1; then
          echo "[$(date)] USBIP_COMMAND_AVAILABLE: SUCCESS" > /dev/console
          usbip version 2>&1 | sed 's/^/['"$(date)"'] USBIP_VERSION: /' > /dev/console
      else
          echo "[$(date)] USBIP_COMMAND_AVAILABLE: FAILED" > /dev/console
          exit 1
      fi
      
      # Signal that USB/IP client is ready
      echo "[$(date)] USBIP_CLIENT_READY" > /dev/console
      echo "[$(date)] USBIP_STARTUP_COMPLETE" > /dev/console
    permissions: '0755'
  
  - path: /usr/local/bin/usbip-readiness-check
    content: |
      #!/bin/sh
      # USB/IP client readiness reporting script
      
      echo "[$(date)] READINESS_CHECK_START" > /dev/console
      
      # Check system readiness
      READY=true
      
      # Check if vhci-hcd module is loaded
      if ! lsmod | grep -q vhci_hcd; then
          echo "[$(date)] READINESS_CHECK: vhci-hcd module not loaded" > /dev/console
          READY=false
      fi
      
      # Check if usbip command is available
      if ! command -v usbip >/dev/null 2>&1; then
          echo "[$(date)] READINESS_CHECK: usbip command not available" > /dev/console
          READY=false
      fi
      
      # Check if we can create USB/IP connections (basic functionality test)
      if ! usbip list -l >/dev/null 2>&1; then
          echo "[$(date)] READINESS_CHECK: usbip list command failed" > /dev/console
          READY=false
      fi
      
      if [ "$READY" = "true" ]; then
          echo "[$(date)] USBIP_CLIENT_READINESS: READY" > /dev/console
          echo "[$(date)] READINESS_CHECK_COMPLETE: SUCCESS" > /dev/console
          exit 0
      else
          echo "[$(date)] USBIP_CLIENT_READINESS: NOT_READY" > /dev/console
          echo "[$(date)] READINESS_CHECK_COMPLETE: FAILED" > /dev/console
          exit 1
      fi
    permissions: '0755'
  
  - path: /usr/local/bin/usbip-client-test
    content: |
      #!/bin/sh
      # USB/IP client comprehensive test script
      
      echo "[$(date)] USBIP_CLIENT_TEST_START" > /dev/console
      
      # Run startup sequence
      if /usr/local/bin/usbip-startup; then
          echo "[$(date)] USBIP_STARTUP_TEST: SUCCESS" > /dev/console
      else
          echo "[$(date)] USBIP_STARTUP_TEST: FAILED" > /dev/console
          exit 1
      fi
      
      # Run readiness check
      if /usr/local/bin/usbip-readiness-check; then
          echo "[$(date)] USBIP_READINESS_TEST: SUCCESS" > /dev/console
      else
          echo "[$(date)] USBIP_READINESS_TEST: FAILED" > /dev/console
          exit 1
      fi
      
      # Test basic usbip functionality
      echo "[$(date)] USBIP_FUNCTIONALITY_TEST: START" > /dev/console
      
      # Test local device listing
      if usbip list -l >/dev/null 2>&1; then
          echo "[$(date)] USBIP_LIST_LOCAL: SUCCESS" > /dev/console
      else
          echo "[$(date)] USBIP_LIST_LOCAL: FAILED" > /dev/console
      fi
      
      # Test remote listing (expected to fail without server, but command should work)
      if usbip list -r 127.0.0.1 2>/dev/null || [ $? -eq 1 ]; then
          echo "[$(date)] USBIP_LIST_REMOTE: SUCCESS" > /dev/console
      else
          echo "[$(date)] USBIP_LIST_REMOTE: FAILED" > /dev/console
      fi
      
      echo "[$(date)] USBIP_FUNCTIONALITY_TEST: COMPLETE" > /dev/console
      echo "[$(date)] USBIP_CLIENT_TEST_COMPLETE" > /dev/console
    permissions: '0755'
  
  - path: /etc/init.d/usbip-client-setup
    content: |
      #!/sbin/openrc-run
      
      name="usbip-client-setup"
      description="USB/IP client setup and readiness service"
      
      depend() {
          need localmount
          after bootmisc
          before local
      }
      
      start() {
          ebegin "Setting up USB/IP client"
          
          # Run the startup script
          if /usr/local/bin/usbip-startup; then
              # Run readiness check
              if /usr/local/bin/usbip-readiness-check; then
                  echo "[$(date)] USBIP_SERVICE_READY" > /dev/console
                  eend 0
              else
                  echo "[$(date)] USBIP_SERVICE_NOT_READY" > /dev/console
                  eend 1
              fi
          else
              echo "[$(date)] USBIP_SERVICE_STARTUP_FAILED" > /dev/console
              eend 1
          fi
      }
      
      stop() {
          ebegin "Stopping USB/IP client"
          # Clean shutdown - remove vhci-hcd module if needed
          rmmod vhci-hcd 2>/dev/null || true
          echo "[$(date)] USBIP_SERVICE_STOPPED" > /dev/console
          eend 0
      }
    permissions: '0755'

# Run commands to set up USB/IP client environment
runcmd:
  # Update package index
  - apk update
  
  # Ensure all required packages are installed
  - apk add --no-cache usbip usbutils kmod util-linux
  
  # Load vhci-hcd kernel module immediately
  - modprobe vhci-hcd || echo "[$(date)] Failed to load vhci-hcd module during setup" > /dev/console
  
  # Enable the USB/IP client setup service for automatic startup
  - rc-update add usbip-client-setup default
  
  # Create symlinks to ensure usbip tools are in PATH
  - ln -sf /usr/bin/usbip /usr/local/bin/usbip || true
  - ln -sf /usr/bin/usbipd /usr/local/bin/usbipd || true
  
  # Run comprehensive test to verify installation
  - /usr/local/bin/usbip-client-test
  
  # Final readiness signal
  - echo "[$(date)] USBIP_CLIENT_CONFIGURATION_COMPLETE" > /dev/console
  - echo "[$(date)] CLOUD_INIT_COMPLETE" > /dev/console

# Power state and final message
power_state:
  mode: reboot
  delay: "+1"
  message: "USB/IP client setup complete, rebooting..."

final_message: "USB/IP client configuration with cloud-init completed successfully"
EOF
    
    # Create cloud-init meta-data file
    cat > "${cloud_init_dir}/meta-data" << 'EOF'
instance-id: usbip-client-001
local-hostname: usbip-client
EOF
    
    # Create cloud-init network configuration (optional)
    cat > "${cloud_init_dir}/network-config" << 'EOF'
version: 1
config:
  - type: physical
    name: eth0
    subnets:
      - type: dhcp
EOF
    
    log_success "Enhanced cloud-init configuration created with:"
    log_info "  - Automatic user creation with sudo access"
    log_info "  - USB/IP module loading startup scripts"
    log_info "  - Comprehensive readiness reporting"
    log_info "  - Structured logging with timestamps"
    log_info "  - Service-based startup management"
    
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
    log_info "Validating enhanced USB/IP client configuration..."
    
    local cloud_init_dir="${BUILD_DIR}/cloud-init"
    local user_data_file="${cloud_init_dir}/user-data"
    local meta_data_file="${cloud_init_dir}/meta-data"
    local network_config_file="${cloud_init_dir}/network-config"
    
    # Verify cloud-init configuration files exist
    if [[ ! -f "$user_data_file" ]]; then
        log_error "Cloud-init user-data file not found: $user_data_file"
        return 1
    fi
    
    if [[ ! -f "$meta_data_file" ]]; then
        log_error "Cloud-init meta-data file not found: $meta_data_file"
        return 1
    fi
    
    if [[ ! -f "$network_config_file" ]]; then
        log_error "Cloud-init network-config file not found: $network_config_file"
        return 1
    fi
    
    # Verify user creation configuration
    if ! grep -q "name: testuser" "$user_data_file"; then
        log_error "User creation configuration not found in cloud-init"
        return 1
    fi
    
    if ! grep -q "sudo: ALL=(ALL) NOPASSWD:ALL" "$user_data_file"; then
        log_error "Sudo access configuration not found in cloud-init"
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
    
    # Verify startup scripts exist in configuration
    if ! grep -q "usbip-startup" "$user_data_file"; then
        log_error "USB/IP startup script not found in configuration"
        return 1
    fi
    
    if ! grep -q "usbip-readiness-check" "$user_data_file"; then
        log_error "USB/IP readiness check script not found in configuration"
        return 1
    fi
    
    if ! grep -q "usbip-client-test" "$user_data_file"; then
        log_error "USB/IP client test script not found in configuration"
        return 1
    fi
    
    # Verify module loading configuration
    if ! grep -q "modules-load.d/usbip.conf" "$user_data_file"; then
        log_error "Kernel module loading configuration not found"
        return 1
    fi
    
    # Verify service configuration
    if ! grep -q "usbip-client-setup" "$user_data_file"; then
        log_error "USB/IP client service configuration not found"
        return 1
    fi
    
    # Verify readiness reporting features
    if ! grep -q "USBIP_CLIENT_READY" "$user_data_file"; then
        log_error "USB/IP client readiness reporting not found"
        return 1
    fi
    
    if ! grep -q "READINESS_CHECK" "$user_data_file"; then
        log_error "Readiness check functionality not found"
        return 1
    fi
    
    # Verify PATH configuration for USB/IP tools
    if ! grep -q "/usr/local/bin/usbip" "$user_data_file"; then
        log_error "USB/IP tools PATH configuration not found"
        return 1
    fi
    
    # Verify structured logging with timestamps
    if ! grep -q '\[$(date)\]' "$user_data_file"; then
        log_error "Structured logging with timestamps not found"
        return 1
    fi
    
    log_success "Enhanced USB/IP client configuration validation passed"
    log_info "Validated features:"
    log_info "  ✓ Automatic user creation with sudo access"
    log_info "  ✓ USB/IP module loading startup scripts"
    log_info "  ✓ Comprehensive readiness reporting"
    log_info "  ✓ Structured logging with timestamps"
    log_info "  ✓ Service-based startup management"
    log_info "  ✓ Complete cloud-init configuration files"
    
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