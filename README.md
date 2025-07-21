# usbipd-mac

A macOS implementation of the USB/IP protocol that allows sharing USB devices over IP networks.

## Overview

usbipd-mac is a macOS implementation of the USB/IP protocol that allows sharing USB devices over IP networks. This server implementation enables macOS users to share USB devices with any compatible USB/IP client, with a focus on compatibility with the Linux Kernel virtual HCI driver (vhci-hcd.ko). Docker support on macOS is also a goal.

## Features

- USB device sharing from macOS to other systems over network
- Full compatibility with the USB/IP protocol specification
- System Extensions integration for reliable device access and claiming
- Lightweight QEMU test server for validation
- Docker enablement for USB device access from containers

## Project Status

This project is currently in early development. The core server functionality is being implemented as an MVP.

## Building the Project

```bash
# Build using Swift Package Manager
swift build

# Build using Xcode
xcodebuild -scheme usbipd-mac build
```

## Running Tests

```bash
# Run tests using Swift Package Manager
swift test

# Run tests using Xcode
xcodebuild -scheme usbipd-mac test

# Run QEMU test server validation
./Scripts/run-qemu-tests.sh
```

## License

[MIT License](LICENSE)