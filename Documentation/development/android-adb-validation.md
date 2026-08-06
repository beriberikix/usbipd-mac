# Validating with an Android device

A second unbound device class, tested on 2026-08-06 with a Pixel 10a (`18d1:4ee7`) in
"charging + debug" mode. Until this, every claim about what works rested on a single
J-Link.

## Ownership

One interface, class 255 / subclass 0x42 / protocol 1 — the ADB interface — with no
driver matched against it, opening with `kIOReturnSuccess`. The harness reports
**USABLE TODAY**, and `usbipd bind 1-18` accepts it.

Two failure modes predicted beforehand did not apply to this device: ADB is interface 0
here (the phone exposes no MTP interface in this mode), and there is no mixed-ownership
composite to trip the ownership verdict. Both remain untested.

## The transport works

`Scripts/verify-adb-protocol.py` sends the host's `CNXN` on bulk EP1 OUT and reads the
reply on EP1 IN:

```
bulk OUT (CNXN, 52 bytes): status=0 written=52
bulk IN  (reply):          status=0 actual=24
-> AUTH (authenticate)  arg0=0x1 payload=20 bytes
```

The phone returned its authentication challenge. That is a complete bidirectional ADB
exchange over USB/IP against hardware that is not a J-Link.

## `adb` itself reports the device offline

```
List of devices attached
61141JEA316294	offline
```

The serial is real, but it comes from the USB string descriptor over a control
transfer — not from the ADB protocol. `adb` never wrote a byte.

This is a property of ADB, not of the transport. On USB the phone announces itself with
`CNXN` once per connection, and `adb` waits for that announcement before doing anything
else. macOS enumerated the phone when it was plugged in, so the announcement has already
happened — to macOS. Attaching from a USB/IP client causes no bus reset the phone can
observe, so it never repeats it.

**This generalises.** Any device whose protocol keys off connection or reset events will
behave this way, because usbipd shares a device macOS has already enumerated and does
not own the port. Request/response devices like a J-Link are unaffected: the host
initiates everything, so there is no missed announcement. Nothing here can be fixed
without the ability to reset the device, which needs the DriverKit entitlement.

## Two defects this found

**A timeout reported bytes it did not have.** `actualLength` is primed with the buffer
capacity to satisfy `ReadPipeTO`'s in/out contract, and IOKit does not reset it when
nothing is read. A timed-out bulk IN therefore answered `status=-110` with
`actualLength=512` and no payload, so a client reading that many bytes would
desynchronise the stream. Now zeroed on every non-success path, for bulk and interrupt.

**The default transfer timeout was far too short.** At 5000 ms, any IN endpoint that is
merely idle produced ETIMEDOUT, and adb gave up on the first read. Real usbip servers
leave such reads pending until data arrives or the client unlinks them. The default is
now 60000 ms.

## UNLINK does not cancel a pending read

Measured directly: submit a bulk IN that will not complete, then unlink it.

```
sent UNLINK for it
RET_UNLINK: seqnum=101 status=0 after 0.0s
(no RET_SUBMIT — the read was never completed)
```

`RET_UNLINK` returns success immediately, but the in-flight IOKit read is not aborted;
it is only reclaimed when its own timeout expires. This is why the timeout cannot simply
be removed in favour of unlimited waits — a cancelled transfer would leak permanently.

An earlier note in this project claimed UNLINK cancelled a blocked transfer cleanly.
That was a misreading: the `RET_SUBMIT` observed alongside it was the 5-second timeout
firing, not cancellation. Wiring `AbortPipe` into the unlink path is the actual fix and
has not been done.

## Also observed

`usbipd bind` writes the allow-list to configuration, but a running daemon reads that
file only at startup, so a device bound while the daemon is running is not served until
it restarts.
