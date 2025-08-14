#!/bin/bash
#
# USB/IP Testing Setup Script
# Sets up VM and guides through USB/IP testing workflow
#

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

echo "🔧 USB/IP Testing Setup"
echo "======================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v qemu-system-x86_64 &> /dev/null; then
    echo "❌ QEMU not found. Please install: brew install qemu"
    exit 1
fi

if ! swift build --product QEMUTestServer &> /dev/null; then
    echo "❌ Failed to build QEMUTestServer"
    exit 1
fi

echo "✅ Prerequisites OK"
echo ""

# Check if we have a bootable VM
if [[ ! -f "tmp/qemu-images/usbip-test.qcow2" ]] || [[ $(stat -f%z "tmp/qemu-images/usbip-test.qcow2" 2>/dev/null || echo 0) -lt 1000000 ]]; then
    echo "📥 Setting up Alpine Linux VM..."
    echo ""
    echo "You have two options:"
    echo "1. Automated Alpine installation (recommended)"
    echo "2. Manual VM setup"
    echo ""
    read -p "Choose option (1 or 2): " option
    
    if [[ "$option" == "1" ]]; then
        echo ""
        echo "Starting automated Alpine installation..."
        echo "This will:"
        echo "- Create a 4GB VM disk"
        echo "- Boot Alpine Linux with VNC display"
        echo "- Guide you through installation"
        echo ""
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo ""
            echo "🚀 Starting manual Alpine Linux installation..."
            echo "This will boot the VM with Alpine Linux ISO for manual installation."
            echo ""
            echo "Follow the installation guide: tmp/qemu-images/usbip-test-installation.md"
            echo ""
            
            # Boot VM for manual installation using the exact command from installation notes
            qemu-system-x86_64 \
                -cdrom "$PROJECT_ROOT/tmp/qemu-iso/alpine-virt-3.19.0-x86_64.iso" \
                -hda "$PROJECT_ROOT/tmp/qemu-images/usbip-test.qcow2" \
                -m 256M \
                -netdev user,id=net0,hostfwd=tcp::2222-:22 \
                -device e1000,netdev=net0 \
                -nographic
                
            echo ""
            echo "✅ Installation session completed!"
            echo "Run this script again to verify the setup."
        else
            echo "Installation cancelled."
            exit 0
        fi
    else
        echo ""
        echo "Manual setup instructions:"
        echo "1. Review: $PROJECT_ROOT/tmp/qemu-images/usbip-test-installation.md"
        echo "2. Boot VM with Alpine ISO for manual installation"
        echo "3. Follow the Alpine setup process in the VM"
        echo "4. Come back and run this script again"
        exit 0
    fi
fi

echo ""
echo "🚀 Ready for USB/IP Testing!"
echo "============================"
echo ""

# Check USB devices
echo "USB devices available for testing:"
"$PROJECT_ROOT/.build/debug/usbipd" list 2>/dev/null || {
    echo "No USB devices found or usbipd not built."
    echo "Make sure you have USB devices connected and run: swift build"
}

echo ""
echo "Next steps:"
echo "1. Connect a USB serial device"
echo "2. Start the VM: $PROJECT_ROOT/Scripts/qemu/vm-manager.sh start usbip-test"
echo "3. Follow the testing guide in the README"
echo ""
echo "Quick test commands:"
echo "# Start VM"
echo "./Scripts/qemu/vm-manager.sh start usbip-test"
echo ""
echo "# List USB devices"
echo "sudo ./.build/debug/usbipd list"
echo ""
echo "# Bind device (replace 1-1 with your device)"
echo "sudo ./.build/debug/usbipd bind 1-1"
echo ""
echo "# Start USB/IP server"
echo "sudo ./.build/debug/usbipd daemon --foreground"
echo ""
echo "# In VM (via SSH to localhost:2222):"
echo "usbip list -r 10.0.2.2"
echo "usbip attach -r 10.0.2.2 -b 1-1"
echo ""

echo "✅ Setup complete! Ready for USB/IP testing."