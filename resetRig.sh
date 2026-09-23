#!/bin/bash
# Reset the Printer Test Rig without rebooting.
#
# Clears every stuck job, deletes every CUPS queue, restarts CUPS, then replays
# the udev "add" event for any printer that is still plugged in. The replay runs
# onAddingPrinter.sh exactly like a fresh plug-in, so each connected printer
# gets a new queue and ONE test print. Nothing plugged in = clean slate, the
# next plug-in prints as normal.
#
# On the Pi:        sudo /home/pi/resetRig.sh
# From a Mac:       ./reset-station.sh <pi-hostname>
# Skip the prints:  sudo /home/pi/resetRig.sh --no-print

set -u

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script as root: sudo $0" >&2
    exit 1
fi

REPRINT=1
[ "${1:-}" = "--no-print" ] && REPRINT=0

# Vendor IDs from test.rules: 04a9 Canon SELPHY, 1452 DNP
VENDORS="04a9 1452"

echo "=== Cancelling all print jobs ==="
cancel -a -x 2>/dev/null || true

echo "=== Removing all printer queues ==="
lpstat -a 2>/dev/null | cut -d" " -f1 | while read -r queue; do
    [ -n "$queue" ] && lpadmin -x "$queue" && echo "  removed $queue"
done

echo "=== Restarting CUPS ==="
systemctl restart cups
# lpadmin in the add script fails if CUPS isn't answering yet
for _ in $(seq 1 15); do
    lpstat -r 2>/dev/null | grep -q "is running" && break
    sleep 1
done

# A package update can un-mask ipp-usb, and then it resets the printer mid-print
# (Canon prints only the yellow pass). Keep it masked.
systemctl stop ipp-usb.service 2>/dev/null || true
systemctl mask ipp-usb.service >/dev/null 2>&1 || true

udevadm control --reload-rules

if [ "$REPRINT" = "1" ]; then
    echo "=== Re-detecting connected printers ==="
    for vendor in $VENDORS; do
        # usb_device only: that is the event that carries DEVNAME, which the
        # add script uses to name the queue
        udevadm trigger --action=add --subsystem-match=usb \
            --property-match=DEVTYPE=usb_device --attr-match=idVendor="$vendor"
    done
    udevadm settle --timeout=30
    sleep 2
fi

echo ""
echo "=== Queues now ==="
queues="$(lpstat -a 2>/dev/null)"
if [ -n "$queues" ]; then
    echo "$queues"
else
    echo "  (none, plug in a printer to print)"
fi
echo ""
echo "=== Jobs now ==="
lpstat -o 2>/dev/null || true
echo ""
echo "Reset done."
