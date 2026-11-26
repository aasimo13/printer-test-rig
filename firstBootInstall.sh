#!/bin/bash
# First boot installer for the Printer Test Rig. Lives on the SD card's boot
# partition, put there by prep-sd-card.sh on a Mac.
#
#   arm   cloud-init calls this once on first boot. Installs a systemd unit
#         that runs the install, so a power cut mid install retries on the
#         next boot instead of leaving a half built station.
#   run   the unit calls this. Installs git, clones the repo from the bundle
#         on the card, runs setup.sh, then reboots.
#
# Progress:  cat /boot/firmware/rig-install-status.txt
# Full log:  /var/log/rig-install.log

set -u

BOOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$BOOT_DIR/$(basename "$0")"
STATUS="$(dirname "$BOOT_DIR")/rig-install-status.txt"
LOG="/var/log/rig-install.log"
STATE_DIR="/var/lib/printer-test-rig"
DONE="$STATE_DIR/installed"
UNIT="/etc/systemd/system/rig-install.service"
REPO="/home/pi/printer-test-rig"
ORIGIN="https://github.com/aasimo13/printer-test-rig.git"
ATTEMPTS=3

status() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$STATUS"
}

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script as root: sudo bash $0 ${1:-run}" >&2
    exit 1
fi

arm() {
    cat > "$UNIT" <<EOF
[Unit]
Description=Printer Test Rig first boot install
Wants=network-online.target
After=network-online.target
RequiresMountsFor=$BOOT_DIR
ConditionPathExists=!$DONE
ConditionPathExists=$SELF

[Service]
Type=oneshot
ExecStart=/bin/bash $SELF run
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable rig-install.service
    status "Armed. Install starts now and takes about 25 minutes."
    systemctl start --no-block rig-install.service
}

wait_for_network() {
    local _
    for _ in $(seq 1 120); do
        getent hosts deb.debian.org >/dev/null 2>&1 && return 0
        sleep 5
    done
    return 1
}

# A Pi has no clock battery. Until NTP syncs, the clock sits at the image build
# date and the HTTPS download in setup.sh can fail on a "not yet valid" cert.
wait_for_clock() {
    local _
    for _ in $(seq 1 24); do
        [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ] && return 0
        sleep 5
    done
    return 1
}

# Builds in a temp folder and renames at the end, so a power cut never leaves
# a half written repo that the next boot would mistake for a finished one.
fetch_repo() {
    local tmp="$REPO.partial"
    if [ -f "$REPO/setup.sh" ]; then
        return 0
    fi
    rm -rf "$REPO" "$tmp"
    if git clone -b main "$BOOT_DIR/printer-test-rig.bundle" "$tmp"; then
        git -C "$tmp" remote set-url origin "$ORIGIN"
    else
        # No git history means "git pull" updates won't work on this station,
        # but it still prints. Fix later by deleting the folder and cloning
        # from GitHub.
        status "WARNING: clone from the card failed, copying plain files instead."
        rm -rf "$tmp"
        mkdir -p "$tmp" || return 1
        cp -r "$BOOT_DIR"/. "$tmp"/ || return 1
        rm -f "$tmp/printer-test-rig.bundle"
    fi
    chown -R pi:pi "$tmp"
    mv "$tmp" "$REPO"
}

install_once() {
    # First boot also runs apt's own daily jobs. This makes installs wait for
    # the dpkg lock instead of failing on it, in setup.sh too. It does not
    # cover the package list lock, so "apt-get update" gets its own retries.
    echo 'DPkg::Lock::Timeout "600";' > /etc/apt/apt.conf.d/90rig-lock-timeout

    local _
    for _ in $(seq 1 6); do
        apt-get update && break
        sleep 20
    done
    apt-get install -y git || return 1
    fetch_repo || return 1
    bash "$REPO/setup.sh" || return 1
}

run() {
    mkdir -p "$STATE_DIR"
    exec >>"$LOG" 2>&1
    export DEBIAN_FRONTEND=noninteractive

    if ! id pi >/dev/null 2>&1; then
        status "FAILED: no user named pi. Re-image the card with username pi."
        exit 1
    fi

    status "Install started on $(hostname). Waiting for network."
    if ! wait_for_network; then
        status "FAILED: no network after 10 minutes. Check Wi-Fi or ethernet, then reboot to retry."
        exit 1
    fi
    wait_for_clock || status "Clock not synced after 2 minutes, carrying on."

    local n
    for n in $(seq 1 "$ATTEMPTS"); do
        status "Attempt $n of $ATTEMPTS: installing (about 20 minutes)."
        if install_once; then
            touch "$DONE"
            systemctl disable rig-install.service
            status "DONE. Rebooting. Plug in a printer after one minute."
            sync
            systemctl reboot
            exit 0
        fi
        status "Attempt $n failed. Last lines of $LOG:"
        tail -n 25 "$LOG" >> "$STATUS"
        sleep 60
    done

    status "FAILED after $ATTEMPTS attempts. Reboot the Pi to retry, or run: sudo bash $SELF run"
    exit 1
}

case "${1:-run}" in
    arm) arm ;;
    run) run ;;
    *)
        echo "Usage: sudo bash $0 [arm|run]" >&2
        exit 1
        ;;
esac
