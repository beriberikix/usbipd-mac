"""Prove a blocked IN transfer does not hold up an OUT transfer.

usbipd serialized every transfer on an interface onto one queue, and the IOKit
transfer calls block their thread until completion or timeout. A read waiting on a
bulk IN endpoint therefore stopped every other transfer — including the write that
would have made the device answer the read. Anything that reads and writes at once
deadlocked until the read timed out.

This submits both without waiting for either, then times the replies. The IN read is
posted first against an endpoint with nothing to say, so it will sit until it times
out; the OUT write is posted immediately after. If the write's reply comes back
promptly the two endpoints are independent. If it arrives only when the read gives
up, they are not.

Usage: verify-concurrent-transfers.py <host> <port> <busid> <in-ep>

The endpoint argument is a bare USB/IP endpoint number, not an address: a CP2102N
reads on 0x82, so pass 2.

The second transfer is a control request rather than a bulk write, for two reasons.
Endpoint zero exists on every device, so this works against anything that enumerates.
More importantly a control request always completes quickly, whereas a bulk write can
block for reasons of its own — a CP2102N with nothing draining its UART stalls its OUT
endpoint for the full timeout, which looks exactly like the bug under test.
"""
import socket, struct, sys, time

if len(sys.argv) != 5:
    print(__doc__)
    sys.exit(2)

host, port, busid = sys.argv[1], int(sys.argv[2]), sys.argv[3]
in_ep = int(sys.argv[4])

# GET_DESCRIPTOR(device): the least surprising thing that can be asked of any device.
GET_DEVICE_DESCRIPTOR = struct.pack("<BBHHH", 0x80, 0x06, 0x0100, 0x0000, 18)

# Longer than the server's own transfer timeout, so a deadlocked write still has a
# chance to arrive and be reported as slow rather than as a hang of this script.
DEADLINE = 90.0

# The write is only meaningful if it beats the blocked read by a wide margin. A real
# bulk write to an idle endpoint returns in single-digit milliseconds.
PROMPT = 5.0


def rx(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise RuntimeError("connection closed")
        buf += chunk
    return buf


s = socket.create_connection((host, port), timeout=DEADLINE)
s.settimeout(DEADLINE)

s.sendall(struct.pack("!HHI", 0x0111, 0x8003, 0) + busid.encode().ljust(32, b"\0"))
_, _, status = struct.unpack("!HHI", rx(s, 8))
if status != 0:
    print(f"import refused: {status}")
    sys.exit(1)
reply = rx(s, 312)
bus, dev, _ = struct.unpack("!III", reply[288:300])
devid = (bus << 16) | dev
print(f"imported {busid}")


def submit(seq, ep, direction, payload=None, length=0, setup=b"\0" * 8):
    """Send a CMD_SUBMIT without waiting for its reply."""
    hdr = struct.pack("!IIIII", 1, seq, devid, direction, ep)
    body = struct.pack("!IiiiI", 0, length if direction else len(payload or b""), 0, 0, 0) + setup
    s.sendall(hdr + body + (payload or b""))


def control(seq):
    """A device-descriptor read on endpoint zero."""
    submit(seq, 0, 1, length=18, setup=GET_DEVICE_DESCRIPTOR)


WARMUP_SEQ, READ_SEQ, CONTROL_SEQ = 1, 2, 3

# Open the interface before timing anything. The two transfers below must share one
# interface object to be a fair test, and the object is created on first use: if both
# arrive while it is still closed they race, each ends up with its own, and they cannot
# contend no matter how the queues are arranged. A real client has always enumerated
# over the control endpoint by this point, so warming up is the honest setup — without
# it this script reported success against code that still had the bug.
control(WARMUP_SEQ)
header = rx(s, 48)
warm_status, warm_len = struct.unpack("!ii", header[20:28])
if warm_len > 0:
    rx(s, warm_len)
print(f"  warm-up control transfer: status={warm_status} read={warm_len} (interface now open)")
if warm_status != 0:
    print("FAIL: the device did not answer a device-descriptor request")
    sys.exit(1)

start = time.monotonic()
# Post the read first, so that under the old behaviour it owns the queue before the
# control request is ever offered.
submit(READ_SEQ, in_ep, 1, length=512)
control(CONTROL_SEQ)
print(f"  submitted: blocking IN read on ep {in_ep}, then a control transfer on ep 0")

# Replies may return in either order — the protocol carries a seqnum for exactly that
# reason — so match on it rather than assuming.
arrivals = {}
while len(arrivals) < 2:
    if time.monotonic() - start > DEADLINE:
        break
    header = rx(s, 48)
    seq = struct.unpack("!I", header[4:8])[0]
    st, alen = struct.unpack("!ii", header[20:28])
    # Both of these are IN transfers, so either may carry a payload to drain.
    if alen > 0:
        rx(s, alen)
    arrivals[seq] = (time.monotonic() - start, st, alen)

s.close()

if CONTROL_SEQ not in arrivals:
    print(f"FAIL: the control transfer never completed within {DEADLINE:.0f}s")
    sys.exit(1)

control_at, control_status, control_len = arrivals[CONTROL_SEQ]
print(f"  control:  replied at {control_at:6.3f}s  status={control_status} read={control_len}")

if READ_SEQ in arrivals:
    read_at, read_status, read_len = arrivals[READ_SEQ]
    print(f"  IN read:  replied at {read_at:6.3f}s  status={read_status} actual={read_len}")
else:
    print(f"  IN read:  still pending after {DEADLINE:.0f}s")

# The read must actually have been blocking, or this proves nothing: a device that
# answered straight away leaves no window for the control transfer to be stuck in.
if READ_SEQ in arrivals and arrivals[READ_SEQ][0] < PROMPT:
    print(f"INCONCLUSIVE: the read returned after {arrivals[READ_SEQ][0]:.3f}s, so it never blocked.")
    print("Pick an IN endpoint with no traffic pending.")
    sys.exit(2)

if control_status != 0:
    print(f"FAIL: the control transfer itself failed with status {control_status}")
    sys.exit(1)

if control_at > PROMPT:
    print(f"FAIL: the control transfer waited {control_at:.1f}s — queued behind the blocked read")
    sys.exit(1)

print(f"PASS: a control transfer completed in {control_at:.3f}s while a read was blocked")
