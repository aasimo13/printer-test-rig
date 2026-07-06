#! /bin/sh
# Continuously reprint the test image to a queue until it is stopped.
#
# Launched (detached) by onAddingPrinter.sh via systemd-run, and stopped by
# onRemovingPrinter.sh via `systemctl stop` when the printer is unplugged.
#
# Usage: printLoop.sh <queueName>
#
# It paces itself: it submits one job, waits for that queue to drain, then
# submits the next. That keeps the printer busy back-to-back without piling
# thousands of jobs into CUPS. The loop ends when the CUPS queue disappears
# (onRemovingPrinter deletes it on unplug) or when the unit is stopped.

QUEUE="$1"
IMAGE="/home/pi/testImage.jpg"

if [ -z "$QUEUE" ]; then
	echo "printLoop.sh: no queue name given" >&2
	exit 1
fi

while lpstat -p "$QUEUE" >/dev/null 2>&1; do
	lp -d "$QUEUE" "$IMAGE"

	# Wait for this queue to finish printing before submitting the next sheet.
	# Bail out promptly if the queue is removed (printer unplugged).
	while lpstat -o "$QUEUE" 2>/dev/null | grep -q .; do
		lpstat -p "$QUEUE" >/dev/null 2>&1 || break
		sleep 2
	done

	sleep 1
done
