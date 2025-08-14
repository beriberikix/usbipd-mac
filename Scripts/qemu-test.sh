#!/bin/bash
#
# qemu-test.sh - QEMU Testing Infrastructure Main Entry Point
#
# Simple wrapper script that provides a consistent entry point to the
# QEMU testing infrastructure while maintaining organized script structure.
# All actual functionality is implemented in Scripts/qemu/test-orchestrator.sh.
#
# This script maintains backward compatibility with existing patterns and
# provides a clean interface for QEMU testing operations.

set -euo pipefail

# Script metadata
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# QEMU orchestration script path
readonly ORCHESTRATOR="$SCRIPT_DIR/qemu/test-orchestrator.sh"

# Check if orchestrator exists
if [[ ! -f "$ORCHESTRATOR" ]]; then
    echo "Error: QEMU test orchestrator not found at: $ORCHESTRATOR" >&2
    echo "Please ensure the QEMU testing infrastructure is properly installed." >&2
    exit 1
fi

# Check if orchestrator is executable
if [[ ! -x "$ORCHESTRATOR" ]]; then
    echo "Error: QEMU test orchestrator is not executable: $ORCHESTRATOR" >&2
    echo "Run: chmod +x $ORCHESTRATOR" >&2
    exit 1
fi

# Pass all arguments directly to the orchestrator
exec "$ORCHESTRATOR" "$@"