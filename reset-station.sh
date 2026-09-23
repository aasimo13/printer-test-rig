#!/bin/bash
# Reset a check/clean station Pi from your Mac over SSH.
#
#   ./reset-station.sh pr-test-rig-2.local
#   ./reset-station.sh pr-test-rig-2.local --no-print
#
# Streams this checkout's resetRig.sh to the Pi and runs it with sudo, so it
# works even on a station that hasn't had update.sh run yet.

set -eu

if [ $# -lt 1 ]; then
    echo "Usage: $0 <pi-hostname-or-ip> [--no-print]" >&2
    exit 1
fi

HOST="$1"
shift
case "$HOST" in
    *@*) TARGET="$HOST" ;;
    *)   TARGET="pi@$HOST" ;;
esac

case "${1:-}" in
    ""|--no-print) ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ssh -o ConnectTimeout=10 "$TARGET" "sudo bash -s -- ${1:-}" < "$SCRIPT_DIR/resetRig.sh"
