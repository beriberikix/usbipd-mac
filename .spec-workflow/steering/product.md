# Product Overview

## Project Repositories
**Main Repository**: https://github.com/beriberikix/usbipd-mac  
**Homebrew Tap Repository**: https://github.com/beriberikix/homebrew-usbipd-mac

## Product Purpose
usbipd-mac is a macOS implementation of the USB/IP protocol that enables sharing USB devices over IP networks. The project solves the critical problem of accessing USB devices from virtual environments, containers, and remote systems on macOS platforms, bridging the gap between physical hardware and virtualized workloads.

## Target Users
The primary users of usbipd-mac are:

1. **Developers using Docker on macOS**: Need access to USB devices (hardware keys, development boards, testing equipment) from within containers
2. **Virtual machine users**: Require USB device passthrough to Linux VMs running on macOS hosts
3. **Remote development teams**: Need to share physical USB devices across network boundaries for testing and development
4. **Hardware engineers**: Developing and testing USB devices who need flexible device sharing capabilities
5. **System administrators**: Managing development environments that require USB device access across multiple systems

Their key pain points include:
- Inability to access USB devices from Docker containers on macOS
- Complex VM setup for USB passthrough scenarios
- Lack of native macOS USB/IP protocol support
- Need for reliable, performance-optimized USB device sharing

## Key Features

1. **USB Device Sharing**: Share USB devices from macOS to any compatible USB/IP client over network
2. **Docker Integration**: Enable USB device access from Docker containers running on macOS
3. **Linux Kernel Compatibility**: Full compatibility with Linux vhci-hcd.ko virtual HCI driver
4. **System Extensions Integration**: Reliable device access and claiming through macOS System Extensions
5. **QEMU Validation**: Lightweight test server for protocol validation and testing
6. **Network Protocol Support**: Complete USB/IP protocol specification implementation

## Business Objectives

- **Developer Productivity**: Eliminate friction in development workflows requiring USB device access from containers/VMs
- **Platform Parity**: Bring macOS to feature parity with Linux USB/IP implementations
- **Open Source Leadership**: Establish the project as the canonical USB/IP solution for macOS
- **Community Growth**: Build an active contributor and user community around the project
- **Enterprise Adoption**: Enable enterprise development teams to standardize on macOS while maintaining USB hardware workflows

## Success Metrics

- **Adoption Rate**: 1000+ GitHub stars within first year
- **Docker Integration**: Seamless USB device access from Docker Desktop on macOS
- **Performance**: Sub-50ms latency for typical USB operations over local network
- **Compatibility**: 95%+ success rate with common USB device types
- **Community Health**: Active monthly contributors and regular issue resolution

## Product Principles

1. **Compatibility First**: Maintain strict compatibility with USB/IP protocol specification and Linux kernel implementations
2. **Performance Oriented**: Optimize for low-latency, high-throughput USB operations
3. **Developer Experience**: Provide clear, simple APIs and excellent documentation for integration
4. **System Integration**: Work seamlessly with macOS security and permission models
5. **Open Development**: Transparent development process with community input and contribution
6. **Production Ready**: Focus on reliability, error handling, and production deployment scenarios

## Development Workflow Requirements

All feature development and implementation work must follow a structured git workflow:

1. **Feature Branch Creation**: Always create a feature branch from main before starting any spec implementation
2. **Incremental Commits**: Commit and push changes at logical completion points during implementation
3. **Pull Request Process**: Final task must always include creating a pull request for code review
4. **CI Validation**: Ensure all GitHub Actions CI checks pass before merging
5. **Code Quality**: Maintain SwiftLint compliance and comprehensive test coverage throughout development

This workflow ensures code quality, traceability, and collaborative review for all project contributions.

## Monitoring & Visibility

- **Dashboard Type**: CLI-based status and monitoring tools
- **Real-time Updates**: Live device status, connection monitoring, and performance metrics
- **Key Metrics Displayed**: 
  - Connected USB devices and their status
  - Active client connections and throughput
  - Protocol-level statistics and error rates
  - System resource usage (memory, CPU, network)
- **Sharing Capabilities**: Configuration export/import, status reporting for troubleshooting

## Future Vision

The long-term vision is to establish usbipd-mac as the standard solution for USB device virtualization on macOS, enabling seamless integration across all major containerization and virtualization platforms.

### Potential Enhancements
- **Remote Access**: Secure tunneling features for sharing USB devices across the internet
- **Analytics**: Historical performance trends, device usage patterns, and optimization recommendations  
- **Collaboration**: Multi-tenant support for shared development environments and device pools
- **Cloud Integration**: Integration with cloud development platforms and remote workspaces
- **Device Management**: Centralized device discovery, allocation, and access control systems