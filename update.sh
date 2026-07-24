#!/bin/bash
# Fast update for the Printer Test Rig.
#
# Syncs the scripts, PPDs, udev rules, and services from this checkout onto the
# Pi WITHOUT rebuilding Gutenprint or reinstalling apt packages. Use this after
# a `git pull` when you only changed shell scripts / PPDs / rules. For a fresh
# Pi (or to (re)build Gutenprint and install dependencies) run setup.sh instead.
#
# Typical update flow on a Pi:
#   cd printer-test-rig && git pull && sudo bash update.sh

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script as root: sudo bash update.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PI_HOME="/home/pi"

# Guard: this only makes sense once Gutenprint (with the CP1500 driver) is
# already installed. If it isn't, this is a fresh box — send them to setup.sh.
if ! cups-genppd.5.3 -M 2>/dev/null | grep -qx canon-cp1500; then
    echo "ERROR: Gutenprint canon-cp1500 driver not found — this looks like a" >&2
    echo "       fresh install. Run 'sudo bash setup.sh' first." >&2
    exit 1
fi

echo "=== Copying files to $PI_HOME ==="
cp "$SCRIPT_DIR/onAddingPrinter.sh" "$PI_HOME/"
cp "$SCRIPT_DIR/onRemovingPrinter.sh" "$PI_HOME/"
cp "$SCRIPT_DIR/removeAnyPrinterQueue.sh" "$PI_HOME/"
cp "$SCRIPT_DIR/Canon_SELPHY_CP1300.ppd" "$PI_HOME/"
cp "$SCRIPT_DIR/Canon_SELPHY_CP1500.ppd" "$PI_HOME/"
cp "$SCRIPT_DIR/Dai_Nippon_Printing_DP-QW410.ppd" "$PI_HOME/"
cp "$SCRIPT_DIR/testImage.jpg" "$PI_HOME/"

chmod +x "$PI_HOME/onAddingPrinter.sh"
chmod +x "$PI_HOME/onRemovingPrinter.sh"
chmod +x "$PI_HOME/removeAnyPrinterQueue.sh"
chown pi:pi "$PI_HOME"/*.sh "$PI_HOME"/*.ppd "$PI_HOME"/testImage.jpg

echo "=== Installing udev rules ==="
cp "$SCRIPT_DIR/test.rules" /etc/udev/rules.d/test.rules
udevadm control --reload-rules

# Re-confirm ipp-usb stays masked (a package update can un-mask it), otherwise
# it will reset the printer mid-print and the Canon prints only the yellow pass.
echo "=== Ensuring ipp-usb is masked ==="
systemctl stop ipp-usb.service 2>/dev/null || true
systemctl mask ipp-usb.service 2>/dev/null || true

echo "=== Reinstalling boot-time queue cleanup service ==="
cp "$SCRIPT_DIR/clear-printer-queues.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable clear-printer-queues.service

echo ""
echo "=== Update complete! ==="
echo "Unplug and replug a printer to test the updated scripts."
