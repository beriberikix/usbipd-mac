# Documentation

Welcome to the usbipd-mac documentation hub. This directory contains comprehensive documentation for developers and users.

## Quick Start

- **[Project README](../README.md)** - Main project overview, installation, and basic usage
- **[Protocol Reference](protocol-reference.md)** - USB/IP protocol implementation details
- **[QEMU Test Tool](qemu-test-tool.md)** - QEMU test utilities. Note these do not boot a VM or run a `usbip` client; interop is validated with Docker, see the probe-rs document below

## Developer Documentation

The `development/` folder contains detailed documentation for contributors:

- **[Driver-free release scope](development/driver-free-release.md)** - which devices can be shared today, measured rather than assumed
- **[Entitlement validation](development/entitlement-validation.md)** - which entitlement actually gates USB claiming, and how to measure it
- **[probe-rs validation](development/probe-rs-validation.md)** - end-to-end proof over USB/IP with a real tool, and what it exposed
- **[Unwired code sweep](development/unwired-code-sweep.md)** - finding mechanisms nothing calls, and what that found
- **[Architecture](development/architecture.md)** - System design and component overview
- **[CI/CD](development/ci-cd.md)** - Continuous integration and deployment workflows
- **[System Extension Development](development/system-extension-development.md)** - macOS System Extension integration
- **[Testing Strategy](development/testing-strategy.md)** - Testing approaches and environments

## API Reference

The `api/` folder contains technical implementation documentation:

- **[USB Implementation](api/usb-implementation.md)** - USB request/response protocol details

## Troubleshooting

The `troubleshooting/` folder contains problem resolution guides:

- **[Build Troubleshooting](troubleshooting/build-troubleshooting.md)** - Common build and setup issues
- **[QEMU Troubleshooting](troubleshooting/qemu-troubleshooting.md)** - QEMU testing issues
- **[System Extension Troubleshooting](troubleshooting/system-extension-troubleshooting.md)** - System Extension development issues

## Navigation

This documentation is organized to serve different user needs:

- **End Users**: Start with the main [README](../README.md) for installation and basic usage
- **Contributors**: Review [Architecture](development/architecture.md) and [Testing Strategy](development/testing-strategy.md)
- **Integration Developers**: Reference [API documentation](api/) and [Protocol Reference](protocol-reference.md)
- **Troubleshooting**: Check relevant guides in the [troubleshooting/](troubleshooting/) folder

For the most current information, always refer to the documentation in this folder rather than scattered documentation files throughout the codebase.