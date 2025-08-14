#!/bin/bash
#
# create-test-image.sh - Create minimal Alpine Linux VM image for QEMU testing
#
# This script creates a lightweight Alpine Linux VM image with USB/IP client tools
# for testing the usbipd-mac implementation. The image is optimized for fast boot
# times and minimal resource usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
ALPINE_VERSION="3.19"
IMAGE_SIZE="1G"
VM_NAME="usbip-test"
IMAGE_DIR="${PROJECT_ROOT}/tmp/qemu-images"
ISO_DIR="${PROJECT_ROOT}/tmp/qemu-iso"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}" >&2
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" >&2
    exit 1
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Create minimal Alpine Linux VM image for QEMU testing.

OPTIONS:
    -n, --name NAME     VM name (default: $VM_NAME)
    -s, --size SIZE     Image size (default: $IMAGE_SIZE)
    -v, --version VER   Alpine version (default: $ALPINE_VERSION)
    -h, --help         Show this help message

EXAMPLES:
    $0                          # Create default VM image
    $0 --name test-vm --size 1G # Create custom VM image
    $0 --version 3.18           # Use specific Alpine version

The created VM image will include:
- Alpine Linux base system
- USB/IP client tools (usbip package)
- SSH server with key-based authentication
- Cloud-init for automatic configuration
- Minimal footprint for fast boot times

EOF
}

check_dependencies() {
    local missing_deps=()
    
    if ! command -v qemu-img >/dev/null 2>&1; then
        missing_deps+=("qemu-img")
    fi
    
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("wget or curl")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing_deps[*]}"
    fi
}

download_alpine_iso() {
    local iso_url="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/x86_64/alpine-virt-${ALPINE_VERSION}.0-x86_64.iso"
    local iso_file="${ISO_DIR}/alpine-virt-${ALPINE_VERSION}.0-x86_64.iso"
    
    mkdir -p "$ISO_DIR"
    
    if [[ -f "$iso_file" ]]; then
        log "Alpine ISO already exists: $iso_file"
        return 0
    fi
    
    log "Downloading Alpine Linux ISO..."
    if command -v wget >/dev/null 2>&1; then
        wget -O "$iso_file" "$iso_url"
    elif command -v curl >/dev/null 2>&1; then
        curl -L -o "$iso_file" "$iso_url"
    else
        error "No download tool available (wget or curl required)"
    fi
    
    log "Downloaded: $iso_file"
}

create_cloud_init_config() {
    local config_dir="${IMAGE_DIR}/${VM_NAME}-config"
    mkdir -p "$config_dir"
    
    # Create user-data for cloud-init
    cat > "$config_dir/user-data" << 'EOF'
#cloud-config
hostname: usbip-test
users:
  - name: alpine
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/ash
    ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7... # placeholder key

package_update: true
packages:
  - usbip
  - openssh
  - bash

runcmd:
  - rc-update add sshd default
  - rc-service sshd start
  - echo "PermitRootLogin no" >> /etc/ssh/sshd_config
  - echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
  - rc-service sshd restart

power_state:
  mode: poweroff
  timeout: 30
EOF

    # Create meta-data for cloud-init
    cat > "$config_dir/meta-data" << EOF
instance-id: ${VM_NAME}-001
local-hostname: ${VM_NAME}
EOF

    log "Created cloud-init configuration in $config_dir"
}

create_vm_image() {
    local image_file="${IMAGE_DIR}/${VM_NAME}.qcow2"
    
    mkdir -p "$IMAGE_DIR"
    
    if [[ -f "$image_file" ]]; then
        warn "VM image already exists: $image_file"
        read -p "Overwrite existing image? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Keeping existing image"
            return 0
        fi
        rm -f "$image_file"
    fi
    
    log "Creating VM disk image ($IMAGE_SIZE)..."
    qemu-img create -f qcow2 "$image_file" "$IMAGE_SIZE"
    
    log "Created VM image: $image_file"
}

generate_installation_notes() {
    local notes_file="${IMAGE_DIR}/${VM_NAME}-installation.md"
    
    cat > "$notes_file" << EOF
# ${VM_NAME} Installation Notes

## Created: $(date)

### Image Details
- VM Name: $VM_NAME
- Image Size: $IMAGE_SIZE
- Alpine Version: $ALPINE_VERSION
- Image Path: ${IMAGE_DIR}/${VM_NAME}.qcow2

### Manual Setup Required

This script creates the base VM image, but manual setup is required to complete the installation:

1. **Boot from ISO and install Alpine:**
   \`\`\`bash
   qemu-system-x86_64 \\
     -cdrom ${ISO_DIR}/alpine-virt-${ALPINE_VERSION}.0-x86_64.iso \\
     -hda ${IMAGE_DIR}/${VM_NAME}.qcow2 \\
     -m 256M -enable-kvm -nographic
   \`\`\`

2. **Alpine installation process:**
   - Login as root (no password)
   - Run: \`setup-alpine\`
   - Choose keyboard layout, hostname, network, etc.
   - When prompted for disk, select the virtual disk
   - Use 'sys' installation mode for full install
   - Set root password and create user account

3. **Install USB/IP tools:**
   \`\`\`bash
   apk add usbip openssh bash
   rc-update add sshd default
   \`\`\`

4. **Configure SSH access:**
   - Edit /etc/ssh/sshd_config
   - Add your public key to ~/.ssh/authorized_keys
   - Disable password authentication

5. **Test the installation:**
   \`\`\`bash
   # Boot the installed system
   qemu-system-x86_64 \\
     -hda ${IMAGE_DIR}/${VM_NAME}.qcow2 \\
     -m 256M -enable-kvm -nographic \\
     -netdev user,id=net0,hostfwd=tcp::2222-:22 \\
     -device e1000,netdev=net0
   
   # Connect via SSH
   ssh -p 2222 alpine@localhost
   \`\`\`

### Next Steps

After manual installation, the VM image will be ready for automated testing.
Use the vm-manager.sh script to control the VM lifecycle during tests.

EOF

    log "Generated installation notes: $notes_file"
}

main() {
    local vm_name="$VM_NAME"
    local image_size="$IMAGE_SIZE"
    local alpine_version="$ALPINE_VERSION"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                vm_name="$2"
                shift 2
                ;;
            -s|--size)
                image_size="$2"
                shift 2
                ;;
            -v|--version)
                alpine_version="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    # Update configuration with parsed values
    VM_NAME="$vm_name"
    IMAGE_SIZE="$image_size"
    ALPINE_VERSION="$alpine_version"
    
    log "Creating QEMU test image: $VM_NAME"
    log "Configuration:"
    log "  - VM Name: $VM_NAME"
    log "  - Image Size: $IMAGE_SIZE"
    log "  - Alpine Version: $ALPINE_VERSION"
    
    check_dependencies
    download_alpine_iso
    create_cloud_init_config
    create_vm_image
    generate_installation_notes
    
    log "VM image creation completed!"
    log "Next steps:"
    log "  1. Review: ${IMAGE_DIR}/${VM_NAME}-installation.md"
    log "  2. Complete manual Alpine installation"
    log "  3. Use vm-manager.sh for automated testing"
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi