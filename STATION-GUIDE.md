# Printer Station Guide

How to get into a check/clean station Pi, update it, run commands, and reset it when it stops printing.

Everywhere below, swap `<station>` for the station's hostname (for example `pr-test-rig-2`). Ask Aaron for the password if you don't have it.

## 1. Log in

Open Terminal on a Mac, or PowerShell on Windows. Both have `ssh` built in. The computer has to be on the same network as the station.

```bash
ssh pi@<station>.local
```

The first time you connect to a station it asks `Are you sure you want to continue connecting?`. Type `yes` and hit Enter.

Then it asks for the password. Nothing shows up while you type it, that's normal. Hit Enter.

You're in when the prompt looks like `pi@<station>:~ $`. Everything you type now runs on the Pi, not your computer.

To log out:

```bash
exit
```

## 2. Update the station

Run this once you're logged in. It pulls the latest scripts from GitHub and installs them. It takes a few seconds and doesn't reboot anything.

```bash
cd ~/printer-test-rig && git pull && sudo bash update.sh
```

It should end with `=== Update complete! ===`.

If you see `No such file or directory`, the repo isn't on that Pi yet. Clone it first, then run the update command again:

```bash
git clone https://github.com/aasimo13/printer-test-rig.git ~/printer-test-rig
```

If `update.sh` says to run `setup.sh`, that Pi was never set up properly. Stop there and tell Aaron. `setup.sh` builds the printer driver from source and takes 20 minutes.

## 3. Run a command

Type the command and hit Enter. Anything that changes the system needs `sudo` in front. These are the useful ones.

See which printers the station has set up:

```bash
lpstat -a
```

See jobs waiting to print:

```bash
lpstat -o
```

Check the printer shows up on USB at all (look for Canon or DNP in the list):

```bash
lsusb
```

Send the test image again by hand. Replace the queue name with one from `lpstat -a`:

```bash
lp -d <queue-name> /home/pi/testImage.jpg
```

See the last print errors:

```bash
sudo tail -n 50 /var/log/cups/error_log
```

Reboot the Pi (this logs you out, wait a minute before you log back in):

```bash
sudo reboot
```

## 4. Reset when it stops printing

This clears stuck jobs, wipes the printer list, restarts the print system, and re-detects whatever printer is plugged in. Each plugged in printer gets set up again and prints one test page. No reboot needed.

Logged in on the Pi:

```bash
sudo /home/pi/resetRig.sh
```

Or from your computer without logging in first (it still asks for the password):

```bash
ssh pi@<station>.local sudo /home/pi/resetRig.sh
```

To reset without printing a page:

```bash
sudo /home/pi/resetRig.sh --no-print
```

The end of the output lists the printer queues and jobs. If a printer is plugged in you should see one queue and it should start printing.

`resetRig.sh: command not found` means the station hasn't been updated yet. Do step 2 first.

## Still not printing

1. Wait for any sheet in progress to fully come out. The Canon makes four passes per print, so give it about a minute.
2. Unplug the printer's USB cable, wait 5 seconds, plug it back in.
3. Run the reset again.
4. Still nothing, run `sudo tail -n 50 /var/log/cups/error_log` and send the output to Aaron.

## Connection problems

`Could not resolve hostname`: check the hostname spelling, check you're on the same network, and make sure the Pi is powered on. Give it a minute after power on.

`WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED`: the Pi got reinstalled. Clear the old key, then log in again:

```bash
ssh-keygen -R <station>.local
```

`Permission denied`: the password is wrong. Passwords are case sensitive.
