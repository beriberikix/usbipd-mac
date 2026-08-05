#!/bin/bash

# validate-usb-entitlements.sh
#
# Empirically determines which entitlement, if any, gates usbipd-mac's ability to
# take a USB device away from its in-kernel driver.
#
# Background: Apple's response to FB22897007 stated that com.apple.security.device.usb
# "does not require entitlement request to use" and can be added directly to an
# entitlements file. That is correct — but it is an App Sandbox entitlement, and this
# script measures whether it changes anything for a non-sandboxed daemon like usbipd.
#
# It compiles one standalone probe (Scripts/entitlement-validation/USBClaimProbe.swift),
# signs it several times with different entitlement sets, runs each build against the
# USB devices currently attached, and diffs the results.
#
# Everything is non-destructive by default: devices are opened and immediately closed.
# Pass --seize to additionally attempt taking a device away from its current owner.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly SOURCE_DIR="${SCRIPT_DIR}/entitlement-validation"
readonly PROBE_SOURCE="${SOURCE_DIR}/USBClaimProbe.swift"
readonly ENTITLEMENTS_DIR="${SOURCE_DIR}/entitlements"
readonly BUILD_DIR="${PROJECT_ROOT}/.build/entitlement-validation"
readonly BUNDLE_ID="com.usbipd.entitlement-probe"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Ordered so the control groups run before the variants they are compared against.
# Not declared readonly: macOS ships bash 3.2, which does not accept `readonly arr=()`.
VARIANTS=(
    "baseline"
    "usb-only"
    "sandboxed-only"
    "sandboxed-usb"
    "driverkit"
)

SEIZE=false
INCLUDE_APPLE=false
INCLUDE_HUBS=false
LIST_ONLY=false

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()      { echo -e "${GREEN}[ OK ]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $*" >&2; }
log_section() { echo; echo -e "${BLUE}=== $* ===${NC}"; }

usage() {
    cat <<'EOF'
Usage: ./Scripts/validate-usb-entitlements.sh [options]

Options:
  --seize           Also attempt USBDeviceOpenSeize/USBInterfaceOpenSeize when a
                    plain open is refused. This can disconnect a device from its
                    current driver — do not use on a device you are relying on.
  --include-apple   Include Apple-vendor (0x05ac) devices, skipped by default
  --include-hubs    Include USB hubs, skipped by default
  --list-only       Enumerate devices and driver ownership without opening anything
  -h, --help        Show this help

Output:
  .build/entitlement-validation/<variant>.json      per-variant machine-readable results
  .build/entitlement-validation/<variant>.log       per-variant console output
  .build/entitlement-validation/report.md           cross-variant comparison, ready to
                                                    attach to a Feedback Assistant report

Recommended run: attach the USB device you actually care about sharing (a serial
adapter, a debug probe, a board in DFU mode), then run this twice — once as your
user and once under sudo — since root changes some IOKit outcomes.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --seize) SEIZE=true; shift ;;
        --include-apple) INCLUDE_APPLE=true; shift ;;
        --include-hubs) INCLUDE_HUBS=true; shift ;;
        --list-only) LIST_ONLY=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown option: $1"; usage; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

preflight() {
    log_section "Preflight"

    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_error "This validation must run on macOS (found $(uname -s))."
        log_error "It measures live IOKit behaviour and has no meaningful result elsewhere."
        exit 1
    fi

    local missing=false
    for tool in swiftc codesign; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool not found: $tool"
            missing=true
        fi
    done
    if [[ "$missing" == true ]]; then
        log_error "Install the Xcode Command Line Tools: xcode-select --install"
        exit 1
    fi

    log_ok "macOS $(sw_vers -productVersion) ($(uname -m))"
    log_ok "swiftc: $(swiftc --version 2>/dev/null | head -1)"

    local sip
    sip="$(csrutil status 2>/dev/null || echo 'csrutil unavailable')"
    log_info "SIP: ${sip}"

    if [[ "$EUID" -eq 0 ]]; then
        log_info "Running as root (euid 0)."
    else
        log_info "Running as uid ${EUID}. Re-run under sudo to capture the root results too."
    fi

    if [[ "$SEIZE" == true ]]; then
        log_warn "--seize is enabled. Devices may be disconnected from their current driver."
    fi
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

build_probe() {
    log_section "Building probe"

    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    # A sandboxed executable needs an embedded Info.plist with a bundle identifier,
    # otherwise the sandbox has no container to initialise and the process dies at
    # launch. Harmless for the unsandboxed variants.
    local info_plist="${BUILD_DIR}/Info.plist"
    cat > "$info_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleName</key>
	<string>usb-claim-probe</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
</dict>
</plist>
EOF

    if ! swiftc -O \
        -o "${BUILD_DIR}/usb-claim-probe" \
        "$PROBE_SOURCE" \
        -framework IOKit \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$info_plist" \
        2> "${BUILD_DIR}/build.log"; then
        log_error "Probe failed to compile. Build log:"
        cat "${BUILD_DIR}/build.log" >&2
        exit 1
    fi

    log_ok "Built ${BUILD_DIR}/usb-claim-probe"
}

# ---------------------------------------------------------------------------
# Per-variant sign and run
# ---------------------------------------------------------------------------

probe_args() {
    local variant="$1"
    local args=(--variant "$variant" --json -)
    [[ "$SEIZE" == true ]] && args+=(--seize)
    [[ "$INCLUDE_APPLE" == true ]] && args+=(--include-apple)
    [[ "$INCLUDE_HUBS" == true ]] && args+=(--include-hubs)
    [[ "$LIST_ONLY" == true ]] && args+=(--list-only)
    printf '%s\n' "${args[@]}"
}

SUCCESSFUL_RUNS=()

run_variant() {
    local variant="$1"
    local entitlements="${ENTITLEMENTS_DIR}/${variant}.entitlements"
    local binary="${BUILD_DIR}/usb-claim-probe-${variant}"
    local json="${BUILD_DIR}/${variant}.json"
    local log="${BUILD_DIR}/${variant}.log"

    if [[ ! -f "$entitlements" ]]; then
        log_error "Missing entitlements file: $entitlements"
        return 1
    fi

    cp "${BUILD_DIR}/usb-claim-probe" "$binary"

    if ! codesign --force --sign - --entitlements "$entitlements" "$binary" \
        > "${BUILD_DIR}/${variant}.codesign.log" 2>&1; then
        log_warn "${variant}: codesign refused this entitlement set"
        sed 's/^/         /' "${BUILD_DIR}/${variant}.codesign.log" || true
        return 1
    fi

    # Record what the signature actually carries, so the report is not relying on
    # what we asked for.
    codesign -d --entitlements - --xml "$binary" \
        > "${BUILD_DIR}/${variant}.effective-entitlements.xml" 2>/dev/null || true

    local args=()
    while IFS= read -r line; do args+=("$line"); done < <(probe_args "$variant")

    set +e
    "$binary" "${args[@]}" > "$json" 2> "$log"
    local status=$?
    set -e

    if [[ $status -ne 0 ]] || [[ ! -s "$json" ]]; then
        if [[ $status -eq 137 ]] || [[ $status -eq 9 ]]; then
            log_warn "${variant}: process was killed at launch (exit ${status})."
            log_warn "         This is AMFI rejecting a restricted entitlement that has no"
            log_warn "         matching provisioning profile — the expected result for driverkit."
        else
            log_warn "${variant}: run failed (exit ${status})"
        fi
        head -20 "$log" | sed 's/^/         /' || true
        rm -f "$json"
        return 1
    fi

    log_ok "${variant}: completed, results in ${variant}.json"
    SUCCESSFUL_RUNS+=("$json")
    return 0
}

# ---------------------------------------------------------------------------
# Static audit of the entitlements the project actually ships
# ---------------------------------------------------------------------------

audit_project_entitlements() {
    log_section "Auditing shipped entitlement files"

    local files=(
        "${PROJECT_ROOT}/usbipd.entitlements"
        "${PROJECT_ROOT}/Sources/SystemExtension/SystemExtension.entitlements"
    )

    # Entitlement keys that look plausible but are not real, and so are silently
    # ignored by codesign and by the provisioning system.
    local -a bad_keys=(
        "com.apple.developer.driverkit.usb.transport"
        "com.apple.developer.driverkit.transport-usb"
    )

    local findings=0
    for file in "${files[@]}"; do
        [[ -f "$file" ]] || continue
        echo "  ${file#"${PROJECT_ROOT}"/}"

        for key in "${bad_keys[@]}"; do
            if grep -q "$key" "$file"; then
                log_warn "    misspelled key '${key}' — the real key is"
                log_warn "    'com.apple.developer.driverkit.transport.usb'; as written it is ignored"
                findings=$((findings + 1))
            fi
        done

        if grep -q "com.apple.developer.endpoint-security.client" "$file"; then
            log_warn "    requests com.apple.developer.endpoint-security.client, which is unrelated"
            log_warn "    to USB and is itself a separately-approved managed capability"
            findings=$((findings + 1))
        fi

        if grep -q "com.apple.security.device.usb" "$file" && \
           ! grep -q "com.apple.security.app-sandbox" "$file"; then
            log_info "    has com.apple.security.device.usb without com.apple.security.app-sandbox;"
            log_info "    outside the sandbox this key has nothing to relax (this run measures that)"
        fi
    done

    if [[ $findings -eq 0 ]]; then
        log_ok "No malformed or over-broad entitlement keys found"
    else
        log_warn "${findings} entitlement issue(s) found — see Documentation/development/entitlement-validation.md"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    preflight
    audit_project_entitlements
    build_probe

    log_section "Running entitlement variants"
    for variant in "${VARIANTS[@]}"; do
        run_variant "$variant" || true
    done

    log_section "Comparison"
    if [[ ${#SUCCESSFUL_RUNS[@]} -eq 0 ]]; then
        log_error "No variant produced results; nothing to compare."
        exit 1
    fi

    local report="${BUILD_DIR}/report.md"
    "${BUILD_DIR}/usb-claim-probe" --compare "${SUCCESSFUL_RUNS[@]}" --markdown "$report" \
        > /dev/null 2> "${BUILD_DIR}/compare.log" || {
            log_error "Comparison failed:"
            cat "${BUILD_DIR}/compare.log" >&2
            exit 1
        }

    cat "$report"

    log_section "Done"
    log_ok "Report: ${report}"
    log_info "Per-variant JSON and logs: ${BUILD_DIR}"
    log_info "Attach report.md to a new Feedback Assistant report — FB22897007 is closed"
    log_info "and no longer monitored."
}

main "$@"
