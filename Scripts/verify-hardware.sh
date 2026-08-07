#!/bin/bash
# verify-hardware.sh
#
# Run the hardware checks against a chosen build configuration, defaulting to release.
#
# This exists because of a bug that shipped. performControlTransfer returned a pointer
# out of a withUnsafeBytes closure, so every field of the USB setup packet was read from
# freed memory. Debug builds happened to leave the bytes intact and passed every check;
# optimised builds did not, and the device stalled the malformed request. v0.5.0 went out
# with control transfers broken, which means a client could not enumerate a device at all.
#
# Nothing caught it because the verification scripts speak to a daemon over TCP and have
# no idea which binary is behind the socket — and every session had started
# ./.build/debug/usbipd by hand. The test suite is a debug build too, so it cannot see
# this class of bug either.
#
# Default to release so the thing being validated is the thing that ships.

set -euo pipefail

CONFIGURATION="release"
BUSID=""
PORT=3240
KEEP_RUNNING=false

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --configuration <release|debug>   Which build to test (default: release)
  --busid <busid>                   Device to bind, e.g. 1-17. Defaults to the first
                                    device that binds successfully.
  --port <port>                     Daemon port (default: 3240)
  --keep-running                    Leave the daemon running afterwards
  -h, --help                        Show this help

Runs a control transfer and, when the device is a J-Link, a bulk protocol exchange.
Both must pass: they exercise different IOKit paths, and one has shipped broken while
the other worked.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration) CONFIGURATION="$2"; shift 2 ;;
        --busid) BUSID="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --keep-running) KEEP_RUNNING=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
    echo "--configuration must be release or debug" >&2
    exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BINARY=".build/$CONFIGURATION/usbipd"
DAEMON_PID=""
BOUND_BUSID=""

cleanup() {
    if [[ -n "$DAEMON_PID" ]] && [[ "$KEEP_RUNNING" != true ]]; then
        kill "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
    fi
    if [[ -n "$BOUND_BUSID" ]] && [[ "$KEEP_RUNNING" != true ]]; then
        "$BINARY" unbind "$BOUND_BUSID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

echo "=== Building $CONFIGURATION ==="
swift build --configuration "$CONFIGURATION" >/dev/null
echo "  $BINARY"
"$BINARY" --version 2>/dev/null | grep -v '^[0-9]' | head -2 | sed 's/^/  /'

echo
echo "=== Selecting a device ==="
if [[ -z "$BUSID" ]]; then
    # Pick the first bindable device that is not a hub. A device macOS owns is refused,
    # which is the correct outcome and not a candidate for transfer testing; a hub binds
    # but is not a meaningful transfer target, and picking one made this script report a
    # failure that said nothing about the build.
    while read -r candidate; do
        if "$BINARY" bind "$candidate" >/dev/null 2>&1; then
            BUSID="$candidate"
            break
        fi
    done < <("$BINARY" list 2>/dev/null | grep -viE "hub" | awk '/^[0-9]+-[0-9]+/ {print $1}')

    if [[ -z "$BUSID" ]]; then
        echo "  No device could be bound. Every attached device is owned by a driver," >&2
        echo "  or none is attached. Plug in a debug probe or a device in DFU mode." >&2
        exit 1
    fi
else
    "$BINARY" bind "$BUSID" >/dev/null 2>&1 || {
        echo "  $BUSID could not be bound:" >&2
        "$BINARY" bind "$BUSID" 2>&1 | grep -E '^Cannot share|^Error' >&2 || true
        exit 1
    }
fi
BOUND_BUSID="$BUSID"

DEVICE_LINE=$("$BINARY" list 2>/dev/null | grep "^$BUSID" || true)
echo "  $DEVICE_LINE"

echo
echo "=== Starting the daemon ==="
"$BINARY" daemon > /tmp/verify-hardware-daemon.log 2>&1 &
DAEMON_PID=$!

# The daemon spends about thirty seconds failing to activate a System Extension before
# it listens, so poll rather than guess at a sleep.
for _ in $(seq 1 90); do
    if nc -z 127.0.0.1 "$PORT" 2>/dev/null; then break; fi
    sleep 1
done
if ! nc -z 127.0.0.1 "$PORT" 2>/dev/null; then
    echo "  Daemon never listened on port $PORT. Log:" >&2
    tail -5 /tmp/verify-hardware-daemon.log >&2
    exit 1
fi
echo "  listening on $PORT (pid $DAEMON_PID)"

VENDOR=$(echo "$DEVICE_LINE" | grep -oE '[0-9a-f]{4}:[0-9a-f]{4}' | cut -d: -f1)
PRODUCT=$(echo "$DEVICE_LINE" | grep -oE '[0-9a-f]{4}:[0-9a-f]{4}' | cut -d: -f2)

FAILED=0

echo
echo "=== Control transfer ==="
# Run once and keep both the output and the status. Running twice to get each
# separately would leave the device in a different state for the second attempt.
if OUTPUT=$(python3 Scripts/verify-usb-transfer.py 127.0.0.1 "$PORT" "$BUSID" "$VENDOR" "$PRODUCT" 2>&1); then
    echo "$OUTPUT" | tail -2 | sed 's/^/  /'
else
    echo "$OUTPUT" | tail -3 | sed 's/^/  /'
    FAILED=1
fi

if [[ "$VENDOR" == "1366" ]]; then
    echo
    echo "=== Bulk transfer (J-Link protocol) ==="
    if OUTPUT=$(python3 Scripts/verify-jlink-bulk.py 127.0.0.1 "$PORT" "$BUSID" 2>&1); then
        echo "$OUTPUT" | tail -2 | sed 's/^/  /'
    else
        echo "$OUTPUT" | tail -3 | sed 's/^/  /'
        FAILED=1
    fi
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "PASS — $CONFIGURATION build verified against $DEVICE_LINE"
else
    echo "FAIL — a transfer failed against the $CONFIGURATION build" >&2
    echo "Daemon log: /tmp/verify-hardware-daemon.log" >&2
fi
exit "$FAILED"
