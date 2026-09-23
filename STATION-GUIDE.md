# Printer Station Guide

How to set up a check/clean station Pi, get into it, update it, run commands, and reset it when it stops printing.

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

## 2. Install on a new Pi

Skip this if the station already prints. You need a Raspberry Pi, a microSD card (16 GB or bigger), and a computer with Raspberry Pi Imager (free from raspberrypi.com/software).

1. Put the SD card in your computer and open Raspberry Pi Imager.
2. Pick your Pi model, then Raspberry Pi OS (64-bit), then the SD card.
3. When it asks about OS customisation, fill it in:
    - Hostname: the station name, for example `pr-test-rig-3`. Use a name no other station has.
    - Username: `pi`. It has to be exactly `pi`, the scripts only work from `/home/pi`.
    - Password: the station password.
    - Wi-Fi: the shop network name and password, and set the country to US. Skip this if the Pi is on an ethernet cable.
    - Services: turn on SSH and pick password authentication.
4. Write the card, put it in the Pi, and power it on. The first boot takes a few minutes.
5. Log in like in step 1, using the hostname you picked.

Once you're logged in, install git and download the program:

```bash
sudo apt-get update && sudo apt-get install -y git
```

```bash
git clone https://github.com/aasimo13/printer-test-rig.git ~/printer-test-rig
```

Run the installer. It builds the printer driver from source, so it takes around 20 minutes. Don't close the window or let your computer sleep until it's done.

```bash
cd ~/printer-test-rig && sudo bash setup.sh
```

It should end with `=== Setup complete! ===`. Reboot:

```bash
sudo reboot
```

Wait a minute, then plug in a Canon CP1300, CP1500, or DNP QW410. It should print the test page by itself. If it doesn't, go to step 5.

## 3. Update the station

Run this once you're logged in. It pulls the latest scripts from GitHub and installs them. It takes a few seconds and doesn't reboot anything.

```bash
cd ~/printer-test-rig && git pull && sudo bash update.sh
```

It should end with `=== Update complete! ===`.

If you see `No such file or directory`, the program isn't on that Pi yet. Do step 2 instead.

If `update.sh` says to run `setup.sh`, that Pi was never fully installed. Run the installer from step 2.

## 4. Run a command

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

## 5. Reset when it stops printing

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

`resetRig.sh: command not found` means the station hasn't been updated yet. Do step 3 first.

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
