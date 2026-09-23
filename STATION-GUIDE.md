# Printer Station Guide

For the check/clean station Pis that auto print a test page when a Canon CP1300, CP1500, or DNP QW410 is plugged in.

Find what you need to do, go to that section, and follow the steps in order.

| I want to | Go to |
|---|---|
| Get into a station | 1. Log in |
| Get out of a station | 2. Log out |
| Make a new station from a blank SD card | 3. Prepare the SD card, then 4. Install the program |
| Get the latest version on a station | 5. Update a station |
| A station stopped printing | 6. Reset a station |
| Reset without logging in first | 7. Reset from your computer |
| See what a station is doing | 8. Check a station |
| Reset didn't fix it | 9. Still not printing |
| Can't connect | 10. Connection errors |

Everywhere you see `<station>`, type the station's hostname instead (for example `pr-test-rig-2`). Ask Aaron for the password.

## 1. Log in

1. On a Mac open Terminal. On Windows open PowerShell.
2. Make sure your computer is on the same network as the station.
3. Type this and hit Enter:

    ```bash
    ssh pi@<station>.local
    ```

4. First time only: if it asks `Are you sure you want to continue connecting?`, type `yes` and hit Enter.
5. Type the password and hit Enter. Nothing shows up while you type, that's normal.
6. You're in when the prompt looks like `pi@<station>:~ $`. Everything you type now runs on the Pi.

## 2. Log out

1. Type this and hit Enter:

    ```bash
    exit
    ```

2. The prompt goes back to your own computer.

## 3. Prepare the SD card

Only for a brand new station. You need a Raspberry Pi, a microSD card (16 GB or bigger), and Raspberry Pi Imager on your computer (free from raspberrypi.com/software).

1. Put the SD card in your computer.
2. Open Raspberry Pi Imager.
3. Pick your Pi model.
4. Pick Raspberry Pi OS (64-bit).
5. Pick the SD card.
6. When it asks about OS customisation, choose to edit the settings.
7. Hostname: type the new station name, for example `pr-test-rig-3`. No two stations can have the same name.
8. Username: type `pi`. It has to be exactly `pi` or the program won't work.
9. Password: type the station password.
10. Wi-Fi: type the shop network name and password and set the country to US. Skip this if the Pi uses an ethernet cable.
11. Services: turn on SSH and pick password authentication.
12. Save the settings and write the card.
13. Put the card in the Pi and plug in the power.
14. Wait about 5 minutes for the first boot.
15. Go to section 4.

## 4. Install the program

Only for a brand new station, after section 3.

1. Log in (section 1) with the hostname you picked.
2. Install git:

    ```bash
    sudo apt-get update && sudo apt-get install -y git
    ```

3. Download the program:

    ```bash
    git clone https://github.com/aasimo13/printer-test-rig.git ~/printer-test-rig
    ```

4. Run the installer. It takes about 20 minutes. Don't close the window or let your computer sleep.

    ```bash
    cd ~/printer-test-rig && sudo bash setup.sh
    ```

5. Wait until you see `=== Setup complete! ===`.
6. Reboot the Pi. This logs you out.

    ```bash
    sudo reboot
    ```

7. Wait 1 minute.
8. Plug in a printer with paper and ribbon loaded.
9. It should print the test page by itself. If it doesn't, go to section 6.

## 5. Update a station

Do this when Aaron says there's a new version. Takes a few seconds, nothing reboots.

1. Log in (section 1).
2. Run the update:

    ```bash
    cd ~/printer-test-rig && git pull && sudo bash update.sh
    ```

3. Wait until you see `=== Update complete! ===`.
4. Log out (section 2).

If you see `No such file or directory`, the program was never installed on that Pi. Do section 4 instead.

If it tells you to run `setup.sh`, the install never finished. Do section 4 from step 4.

## 6. Reset a station

Do this when a station stops printing. It clears stuck jobs, wipes the printer list, and sets up whatever printer is plugged in again. Each plugged in printer prints one test page. No reboot.

1. Leave the printer plugged in and turned on.
2. Log in (section 1).
3. Run the reset:

    ```bash
    sudo /home/pi/resetRig.sh
    ```

4. Wait until you see `Reset done.`
5. The printer should start printing within a minute.
6. Log out (section 2).

To reset without printing a page, use this in step 3 instead:

```bash
sudo /home/pi/resetRig.sh --no-print
```

If you see `resetRig.sh: command not found`, update the station first (section 5), then try again.

## 7. Reset from your computer

Same as section 6 but in one command, without logging in first.

1. Open Terminal (Mac) or PowerShell (Windows).
2. Run this:

    ```bash
    ssh pi@<station>.local sudo /home/pi/resetRig.sh
    ```

3. Type the password when it asks and hit Enter.
4. Wait until you see `Reset done.`

## 8. Check a station

Log in first (section 1). Type the command and hit Enter.

| To see | Run |
|---|---|
| Printers the station has set up | `lpstat -a` |
| Jobs waiting to print | `lpstat -o` |
| If the printer shows up on USB (look for Canon or DNP) | `lsusb` |
| The last print errors | `sudo tail -n 50 /var/log/cups/error_log` |

To print the test page again by hand, get the queue name from `lpstat -a` and run:

```bash
lp -d <queue-name> /home/pi/testImage.jpg
```

To reboot the Pi (this logs you out, wait 1 minute before logging back in):

```bash
sudo reboot
```

## 9. Still not printing

Go in order and stop when it prints.

1. Wait for any sheet that's printing to come all the way out. The Canon makes four passes, so give it a minute.
2. Check the printer has paper and ribbon and shows no error on its screen.
3. Unplug the printer's USB cable, wait 5 seconds, plug it back in.
4. Reset the station (section 6).
5. Reboot the Pi (section 8), then unplug and replug the printer.
6. Still nothing: log in, run `sudo tail -n 50 /var/log/cups/error_log`, and send the output to Aaron.

## 10. Connection errors

**`Could not resolve hostname`**

1. Check the hostname spelling.
2. Check you're on the same network as the station.
3. Check the Pi has power, then wait 1 minute and try again.

**`WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED`**

The Pi was reinstalled. This is expected after section 3.

1. Clear the old key:

    ```bash
    ssh-keygen -R <station>.local
    ```

2. Log in again (section 1). Answer `yes` to the question.

**`Permission denied`**

1. The password is wrong. Passwords are case sensitive.
2. Try again. Ask Aaron if it still fails.
