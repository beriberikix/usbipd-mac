# USB/IP Protocol Reference

## Overview

This document provides a reference for the USB/IP protocol implementation in usbipd-mac.

## Protocol Version

The USB/IP protocol version implemented is 1.1.1 (0x0111).

## Message Types

### Device List Request/Response

Used to request and receive a list of available USB devices.

### Device Import Request/Response

Used to request and confirm the import of a specific USB device.

## References

- [USB/IP Protocol Specification](https://www.kernel.org/doc/html/latest/usb/usbip_protocol.html)
- [usbipd-win Project](https://github.com/dorssel/usbipd-win)