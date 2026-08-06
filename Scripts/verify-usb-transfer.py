#!/usr/bin/env python3
"""Prove that a real USB transfer completes end to end.

Everything else in this project's interop testing has relied on the Linux kernel's
vhci driver to drive traffic, which leaves a gap: devices with no kernel driver bound
are the ones usbipd can actually open, and those are exactly the devices nothing in a
Linux guest probes unaided. So the transfer path stayed unverified — requests were
seen to route, but no bytes ever came back.

This client removes the kernel from the loop. It speaks USB/IP directly over TCP and
issues one specific control transfer: GET_DESCRIPTOR for the 18-byte device
descriptor. If the reply carries a descriptor whose idVendor and idProduct match the
device we asked for, then data moved from real hardware, through IOKit, through the
USB/IP encoders, and back over the wire.

Usage: verify-usb-transfer.py <host> <port> <busid> <expect_vid> <expect_pid>
"""

import socket
import struct
import sys

USBIP_VERSION = 0x0111
OP_REQ_IMPORT = 0x8003
OP_REP_IMPORT = 0x0003
USBIP_CMD_SUBMIT = 0x00000001
USBIP_RET_SUBMIT = 0x00000003


def recv_exactly(sock, count):
    """Read exactly count bytes or raise."""
    buf = b""
    while len(buf) < count:
        chunk = sock.recv(count - len(buf))
        if not chunk:
            raise RuntimeError(f"connection closed after {len(buf)} of {count} bytes")
        buf += chunk
    return buf


def import_device(sock, busid):
    """OP_REQ_IMPORT, returning (busnum, devnum) from the reply's device record."""
    # op_common: version(2) code(2) status(4), then busid[32]
    request = struct.pack("!HHI", USBIP_VERSION, OP_REQ_IMPORT, 0)
    request += busid.encode().ljust(32, b"\0")
    sock.sendall(request)

    version, code, status = struct.unpack("!HHI", recv_exactly(sock, 8))
    if code != OP_REP_IMPORT:
        raise RuntimeError(f"expected OP_REP_IMPORT (0x{OP_REP_IMPORT:04x}), got 0x{code:04x}")
    if status != 0:
        raise RuntimeError(f"server refused the import, status={status}")

    # op_import_reply is exactly one struct usbip_usb_device (312 bytes).
    udev = recv_exactly(sock, 312)
    path = udev[0:256].split(b"\0", 1)[0].decode(errors="replace")
    reported_busid = udev[256:288].split(b"\0", 1)[0].decode(errors="replace")
    busnum, devnum, speed = struct.unpack("!III", udev[288:300])
    id_vendor, id_product, bcd_device = struct.unpack("!HHH", udev[300:306])

    print(f"  imported: busid={reported_busid} path={path}")
    print(f"            {id_vendor:04x}:{id_product:04x} busnum={busnum} devnum={devnum} speed={speed}")
    return busnum, devnum


def get_device_descriptor(sock, busnum, devnum, seqnum=1):
    """Issue GET_DESCRIPTOR(device) as a control transfer and return the payload."""
    devid = (busnum << 16) | devnum

    # usbip_header_basic: command seqnum devid direction ep. Direction 1 is IN.
    header = struct.pack("!IIIII", USBIP_CMD_SUBMIT, seqnum, devid, 1, 0)

    # bmRequestType=0x80 (device-to-host), bRequest=0x06 GET_DESCRIPTOR,
    # wValue=0x0100 (DEVICE descriptor, index 0), wIndex=0, wLength=18.
    # The setup packet is raw USB bytes and stays little-endian.
    setup = struct.pack("<BBHHH", 0x80, 0x06, 0x0100, 0x0000, 18)

    # usbip_header_cmd_submit: flags, buffer_length, start_frame, packets, interval,
    # then the 8-byte setup packet.
    body = struct.pack("!IiiiI", 0, 18, 0, 0, 0) + setup
    sock.sendall(header + body)

    reply = recv_exactly(sock, 48)
    command, ret_seqnum, _, _, _ = struct.unpack("!IIIII", reply[0:20])
    status, actual_length = struct.unpack("!ii", reply[20:28])

    if command != USBIP_RET_SUBMIT:
        raise RuntimeError(f"expected RET_SUBMIT (0x{USBIP_RET_SUBMIT:x}), got 0x{command:x}")
    if ret_seqnum != seqnum:
        raise RuntimeError(f"sequence mismatch: sent {seqnum}, got {ret_seqnum}")

    print(f"  RET_SUBMIT: status={status} actual_length={actual_length}")
    if status != 0:
        raise RuntimeError(f"transfer failed with status {status}")
    if actual_length <= 0:
        raise RuntimeError("transfer reported success but returned no data")

    return recv_exactly(sock, actual_length)


def main():
    if len(sys.argv) != 6:
        print(__doc__)
        return 2

    host, port, busid = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    expect_vid, expect_pid = int(sys.argv[4], 16), int(sys.argv[5], 16)

    with socket.create_connection((host, port), timeout=15) as sock:
        sock.settimeout(15)
        print(f"connected to {host}:{port}")
        busnum, devnum = import_device(sock, busid)
        print("requesting device descriptor...")
        data = get_device_descriptor(sock, busnum, devnum)

    print(f"  payload ({len(data)} bytes): {data.hex()}")

    if len(data) < 18:
        print(f"FAIL: descriptor is {len(data)} bytes, expected 18")
        return 1

    length, desc_type = data[0], data[1]
    vid, pid = struct.unpack("<HH", data[8:12])
    print(f"  bLength={length} bDescriptorType=0x{desc_type:02x} idVendor={vid:04x} idProduct={pid:04x}")

    if length != 18 or desc_type != 0x01:
        print("FAIL: not a USB device descriptor")
        return 1
    if (vid, pid) != (expect_vid, expect_pid):
        print(f"FAIL: descriptor reports {vid:04x}:{pid:04x}, expected {expect_vid:04x}:{expect_pid:04x}")
        return 1

    print(f"PASS: real descriptor from {vid:04x}:{pid:04x} returned over USB/IP")
    return 0


if __name__ == "__main__":
    sys.exit(main())
