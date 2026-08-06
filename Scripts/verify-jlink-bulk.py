"""Speak the J-Link protocol directly over USB/IP, bypassing probe-rs.

EMU_CMD_VERSION (0x01) is written to the bulk OUT endpoint; the probe replies on the
bulk IN endpoint with a 2-byte length followed by a version string. If that string
comes back, real bidirectional bulk traffic completed through usbipd.
"""
import socket, struct, sys

host, port, busid = sys.argv[1], int(sys.argv[2]), sys.argv[3]

def rx(s, n):
    b = b""
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c: raise RuntimeError("closed")
        b += c
    return b

s = socket.create_connection((host, port), timeout=30); s.settimeout(30)
s.sendall(struct.pack("!HHI", 0x0111, 0x8003, 0) + busid.encode().ljust(32, b"\0"))
_, _, st = struct.unpack("!HHI", rx(s, 8))
if st != 0:
    print(f"import refused: {st}"); sys.exit(1)
u = rx(s, 312)
bus, dev, _ = struct.unpack("!III", u[288:300])
devid = (bus << 16) | dev
print(f"imported {busid}")

def submit(seq, ep, direction, payload=None, length=0):
    hdr = struct.pack("!IIIII", 1, seq, devid, direction, ep)
    body = struct.pack("!IiiiI", 0, length if direction else len(payload or b""), 0, 0, 0) + b"\0" * 8
    s.sendall(hdr + body + (payload or b""))
    rep = rx(s, 48)
    status, alen = struct.unpack("!ii", rep[20:28])
    data = rx(s, alen) if direction == 1 and alen > 0 else b""
    return status, alen, data

# EMU_CMD_VERSION
st, alen, _ = submit(1, 2, 0, payload=bytes([0x01]))
print(f"  bulk OUT (EMU_CMD_VERSION): status={st} written={alen}")

st, alen, data = submit(2, 1, 1, length=64)
print(f"  bulk IN  (64-byte read):    status={st} actual={alen} data={data.hex()[:64]}")
if st != 0:
    print("FAIL: no response from the probe"); sys.exit(1)

n = struct.unpack("<H", data[:2])[0]
print(f"  probe says the version string is {n} bytes")

st, alen, data = submit(3, 1, 1, length=n)
print(f"  bulk IN  (version string):  status={st} actual={alen}")
text = data.split(b"\0", 1)[0].decode(errors="replace")
print(f"  -> {text!r}")
print("PASS: bidirectional bulk traffic over USB/IP" if text else "FAIL: empty version")
s.close()
