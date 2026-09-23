# Printer Test Rig

Raspberry Pi station that auto prints a test page when a Canon SELPHY CP1300, CP1500, or DNP QW410 is plugged in over USB.

Fresh Pi: `sudo bash setup.sh`, then reboot.
After a `git pull`: `sudo bash update.sh`.

## Station stopped printing? Reset it

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
