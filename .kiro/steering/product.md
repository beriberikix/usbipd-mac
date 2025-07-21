# usbipd-mac

## Product Overview
usbipd-mac is a macOS implementation of the USB/IP protocol that allows sharing USB devices over IP networks. This server implementation enables macOS users to share USB devices with any compatible USB/IP client, with a focus on compatibility with the Linux Kernel virtual HCI driver (vhci-hcd.ko). Docker support on macOS is also a goal.

## Key Features
- USB device sharing from macOS to other systems over network
- Full compatibility with the USB/IP protocol specification
- System Extensions integration for reliable device access and claiming
- Lightweight QEMU test server for validation
- Docker enablement for USB device access from containers

## Target Users
- Developers working with USB devices across macOS and Linux environments
- System administrators managing cross-platform hardware access
- Users needing to share macOS-connected USB devices with Linux systems
- Docker users requiring access to USB devices from containers

## Product Goals
- Provide reliable USB device sharing from macOS hosts
- Ensure full compatibility with the USB/IP protocol standard (https://www.kernel.org/doc/html/latest/usb/usbip_protocol.html)
- Maintain compatibility with Linux vhci-hcd.ko driver
- Take inspiration from design patterns established by usbipd-win (https://github.com/dorssel/usbipd-win)
- Include testing capabilities through the QEMU test server
- Enable seamless USB device access for Docker containers running on macOS