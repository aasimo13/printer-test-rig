#!/bin/bash
# Printer Test Rig Setup for Raspberry Pi
# Supports: Canon Selphy CP1300, CP1500, DNP QW-410
# Run as root on a fresh Raspberry Pi OS install

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script as root: sudo bash setup.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PI_HOME="/home/pi"

echo "=== Installing dependencies ==="
apt-get update
apt-get install -y cups libcups2-dev libusb-1.0-0-dev build-essential wget xsltproc xz-utils

# Add pi user to lpadmin group so CUPS commands work
usermod -aG lpadmin pi

# NOTE: Gutenprint 5.3.5 is the first RELEASE with the Canon SELPHY CP1500 driver
# (added 2025-03-12). The older 5.3.4 release stops at the CP1300, so CP1500 prints
# fail with "Unable to find Gutenprint driver named Canon SELPHY CP1500". Do not
# downgrade below 5.3.5 unless you also stop using a CP1500.
# Skip the (slow, ~10-20 min) source build if Gutenprint already provides the
# canon-cp1500 driver — makes re-running setup.sh on an updated Pi fast. Force a
# rebuild with: FORCE_GUTENPRINT_BUILD=1 sudo bash setup.sh
if [ "${FORCE_GUTENPRINT_BUILD:-0}" != "1" ] && cups-genppd.5.3 -M 2>/dev/null | grep -qx canon-cp1500; then
    echo "=== Gutenprint 5.3.5 (canon-cp1500) already installed — skipping build ==="
else
    echo "=== Building Gutenprint 5.3.5 from source ==="
    cd /tmp
    if [ ! -f gutenprint-5.3.5.tar.xz ]; then
        wget https://sourceforge.net/projects/gimp-print/files/gutenprint-5.3/5.3.5/gutenprint-5.3.5.tar.xz/download -O gutenprint-5.3.5.tar.xz
    fi
    tar xf gutenprint-5.3.5.tar.xz
    cd gutenprint-5.3.5
    ./configure --without-gimp
    make -j$(nproc)
    make install
    ldconfig
fi

# Sanity check: the CP1500 driver must be present or the rig cannot print to a CP1500
if ! cups-genppd.5.3 -M 2>/dev/null | grep -qx canon-cp1500; then
    echo "ERROR: Gutenprint build is missing the canon-cp1500 driver. Aborting." >&2
    exit 1
fi

echo "=== Copying files to $PI_HOME ==="
cp "$SCRIPT_DIR/onAddingPrinter.sh" "$PI_HOME/"
cp "$SCRIPT_DIR/onRemovingPrinter.sh" "$PI_HOME/"
cp "$SCRIPT_DIR/printLoop.sh" "$PI_HOME/"
cp "$SCRIPT_DIR/removeAnyPrinterQueue.sh" "$PI_HOME/"
cp "$SCRIPT_DIR/Canon_SELPHY_CP1300.ppd" "$PI_HOME/"
cp "$SCRIPT_DIR/Canon_SELPHY_CP1500.ppd" "$PI_HOME/"
cp "$SCRIPT_DIR/Dai_Nippon_Printing_DP-QW410.ppd" "$PI_HOME/"
cp "$SCRIPT_DIR/testImage.jpg" "$PI_HOME/"

chmod +x "$PI_HOME/onAddingPrinter.sh"
chmod +x "$PI_HOME/onRemovingPrinter.sh"
chmod +x "$PI_HOME/printLoop.sh"
chmod +x "$PI_HOME/removeAnyPrinterQueue.sh"
chown pi:pi "$PI_HOME"/*.sh "$PI_HOME"/*.ppd "$PI_HOME"/testImage.jpg

echo "=== Installing udev rules ==="
cp "$SCRIPT_DIR/test.rules" /etc/udev/rules.d/test.rules
udevadm control --reload-rules
udevadm trigger

echo "=== Enabling CUPS ==="
systemctl enable cups
systemctl start cups

# Mask ipp-usb: it is a udev-activated daemon that pounces on any IPP-over-USB
# printer (the Canon SELPHY and DNP both advertise it), claims the USB interface
# and issues a USB device RESET a few seconds after plug-in. That reset lands
# mid-print and aborts the Canon's dye-sub job after only the yellow pass
# ("prints only yellow and stops"). This rig prints exclusively through
# Gutenprint USB queues and never uses IPP-over-USB, so ipp-usb is pure
# interference. It is a `static` unit, so it must be masked (not disabled).
echo "=== Masking ipp-usb (prevents it resetting the printer mid-print) ==="
systemctl stop ipp-usb.service 2>/dev/null || true
systemctl mask ipp-usb.service

echo "=== Installing boot-time queue cleanup service ==="
cp "$SCRIPT_DIR/clear-printer-queues.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable clear-printer-queues.service

echo ""
echo "=== Setup complete! ==="
echo "Reboot the Pi, then plug in a printer to test."
echo "Supported printers:"
echo "  - Canon Selphy CP1300"
echo "  - Canon Selphy CP1500"
echo "  - DNP QW-410"
