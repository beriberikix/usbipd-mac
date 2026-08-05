#!/bin/bash
# portable-timeout.sh
#
# The QEMU harness calls `timeout` in about thirty places. GNU coreutils provides it;
# macOS does not ship it, so on the platform this project targets every one of those
# calls failed with "command not found" — and because most were used as
# `if timeout ... ; then`, the failure read as the *test* failing rather than as a
# missing tool. The basic connectivity check reported a broken server while the server
# was listening and reachable.
#
# Source this near the top of any script that uses `timeout`. It prefers the real
# thing, then gtimeout from coreutils, and otherwise emulates enough of the interface
# for this harness: `timeout <duration> <command...>`, returning 124 on expiry.

if ! command -v timeout >/dev/null 2>&1; then
    if command -v gtimeout >/dev/null 2>&1; then
        timeout() { gtimeout "$@"; }
    else
        timeout() {
            local duration="$1"
            shift

            # Accept GNU-style suffixes (5s, 2m). BSD sleep takes a bare number, and
            # this harness only ever uses seconds.
            case "$duration" in
                *s) duration="${duration%s}" ;;
                *m) duration=$(( ${duration%m} * 60 )) ;;
                *h) duration=$(( ${duration%h} * 3600 )) ;;
            esac

            "$@" &
            local cmd_pid=$!

            ( sleep "$duration" 2>/dev/null && kill -TERM "$cmd_pid" 2>/dev/null ) &
            local watcher_pid=$!

            local rc=0
            wait "$cmd_pid" 2>/dev/null || rc=$?

            # If the watcher is gone the timeout already fired.
            if kill -0 "$watcher_pid" 2>/dev/null; then
                kill "$watcher_pid" 2>/dev/null
                wait "$watcher_pid" 2>/dev/null || true
            else
                rc=124
            fi

            return $rc
        }
    fi
fi
