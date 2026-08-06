"""Speak the ADB wire protocol directly over USB/IP.

adb itself waits for the phone to announce itself with CNXN, which the phone sends
once per USB connection — and on macOS that already happened, to macOS. This sends the
host's CNXN ourselves, which the phone answers regardless, so it tests the transport
rather than adb's connection state machine.
"""
import socket, struct, sys, zlib

host, port, busid = sys.argv[1], int(sys.argv[2]), sys.argv[3]
EP_OUT, EP_IN = 1, 1     # bEndpointAddress 0x01 and 0x81

def rx(s, n):
    b = b""
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c: raise RuntimeError("closed")
        b += c
    return b

s = socket.create_connection((host, port), timeout=40); s.settimeout(40)
s.sendall(struct.pack("!HHI", 0x0111, 0x8003, 0) + busid.encode().ljust(32, b"\0"))
_, _, st = struct.unpack("!HHI", rx(s, 8))
if st: print(f"import refused: {st}"); sys.exit(1)
u = rx(s, 312)
bus, dev, _ = struct.unpack("!III", u[288:300])
devid = (bus << 16) | dev
print(f"imported {busid}")

seq = [0]
def submit(ep, direction, payload=None, length=0):
    seq[0] += 1
    hdr = struct.pack("!IIIII", 1, seq[0], devid, direction, ep)
    body = struct.pack("!IiiiI", 0, length if direction else len(payload or b""), 0, 0, 0) + b"\0" * 8
    s.sendall(hdr + body + (payload or b""))
    rep = rx(s, 48)
    status, alen = struct.unpack("!ii", rep[20:28])
    data = rx(s, alen) if direction == 1 and alen > 0 else b""
    return status, alen, data

def adb_msg(cmd, arg0, arg1, payload=b""):
    command = struct.unpack("<I", cmd)[0]
    return struct.pack("<IIIIII", command, arg0, arg1, len(payload),
                       zlib.crc32(payload) & 0xFFFFFFFF, command ^ 0xFFFFFFFF) + payload

banner = b"host::features=cmd,shell_v2\x00"
msg = adb_msg(b"CNXN", 0x01000000, 256 * 1024, banner)
st, alen, _ = submit(EP_OUT, 0, payload=msg)
print(f"  bulk OUT (CNXN, {len(msg)} bytes): status={st} written={alen}")
if st != 0:
    print("FAIL: could not write to the phone"); sys.exit(1)

st, alen, data = submit(EP_IN, 1, length=512)
print(f"  bulk IN  (reply):                 status={st} actual={alen}")
if st != 0 or alen < 24:
    print(f"FAIL: no reply from the phone (status={st})"); sys.exit(1)

cmd = data[0:4]
names = {b"CNXN": "CNXN (connect)", b"AUTH": "AUTH (authenticate)", b"OKAY": "OKAY"}
arg0, arg1, dlen = struct.unpack("<III", data[4:16])
print(f"  -> {names.get(cmd, cmd)}  arg0=0x{arg0:x} payload={dlen} bytes")
if dlen and len(data) >= 24 + dlen:
    print(f"  -> payload: {data[24:24+dlen][:80]!r}")
print("PASS: the phone answered over USB/IP")
s.close()
