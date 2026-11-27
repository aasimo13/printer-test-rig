# Printer Test Rig

Raspberry Pi station that auto prints a test page when a Canon SELPHY CP1300, CP1500, or DNP QW410 is plugged in over USB.

Fresh Pi: `sudo bash setup.sh`, then reboot.
After a `git pull`: `sudo bash update.sh`.

## Self installing SD card

Skips the SSH install on a fresh Pi. Write the card with Raspberry Pi Imager (username `pi`, Wi-Fi and SSH set in the OS customisation), pull the card out, put it back in, then on a Mac with this repo:

```bash
./prep-sd-card.sh
```

It copies the program to the card's boot partition and hooks the card's first boot. Put the card in the Pi and power it. The Pi needs internet. It runs `setup.sh` by itself, takes about 25 minutes, and reboots when done.

Progress, from an SSH session on the Pi:

```bash
cat /boot/firmware/rig-install-status.txt
```

The same file is readable on any computer if you pull the card. A failed install retries on the next boot. Full log is `/var/log/rig-install.log`.

Tests for the card script: `bash tests/prep-sd-card.test.sh`.

## Copy an installed station to more cards

Skips the 25 minute install. Needs a Mac with this repo and `brew install e2fsprogs`. Shut the working station down with `sudo poweroff`, put its card in the Mac, then:

```bash
./clone-sd-card.sh save
```

That reads the card into `~/.printer-test-rig/station.img`, shrunk to what is in use plus 2 GB, so it fits any card that size or bigger. Swap in a blank card and give the new station its name:

```bash
./clone-sd-card.sh write pr-test-rig-6
```

It shows the card it is about to erase and asks before writing. The copy gets the new hostname, a fresh machine ID, and its own SSH host keys, and loses the first boot install hook. Run `write` again with another name for each extra card. The saved image is reused until you `save` with `--replace`.

Both steps ask for your Mac password, raw card access needs root. Don't edit the script while it is running. The image holds the station's Wi-Fi password and login hash, so it is kept out of the repo and readable only by you. Delete it with `./clone-sd-card.sh forget`.

Copies keep a small Linux partition (about 2 GB free) however big the card is. Only the built in card reader is picked automatically. For a USB reader pass `--disk diskN`.

Tests: `bash tests/clone-sd-card.test.sh`. They build a fake card from disk images, so they cover everything except the raw write to a real card.

## Station stopped printing? Reset it

Step by step for SSH, updating, and resetting: [STATION-GUIDE.md](STATION-GUIDE.md).

This clears stuck jobs, deletes every printer queue, restarts CUPS, and re detects whatever printer is plugged in. Each connected printer gets a fresh queue and one test print. No reboot needed.

From a Mac with this repo:

```bash
./reset-station.sh pr-test-rig-2.local
```

From any computer (station must have had `update.sh` run once):

```bash
ssh pi@pr-test-rig-2.local sudo /home/pi/resetRig.sh
```

Add `--no-print` to either one to reset without firing a test print.

If it still won't print after a reset, unplug the printer, wait 5 seconds, plug it back in. If that fails, check `/var/log/cups/error_log` on the Pi.
