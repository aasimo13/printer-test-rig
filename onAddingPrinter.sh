#! /bin/sh

if [ "${ID_MODEL}" = "SELPHY_CP1300" ]; then
	tempDevName="Canon_SELPHY_CP1300${DEVNAME}"
	tempDevName=$(echo $tempDevName|sed 's/\//_/g')

	lpadmin -p "$tempDevName" -E -v "gutenprint53+usb://canon-cp1300/${ID_SERIAL_SHORT}" -P "/home/pi/Canon_SELPHY_CP1300.ppd"

	lpoptions -p "$tempDevName" -o StpiShrinkOutput=Expand
	lpoptions -p "$tempDevName" -o StpBorderless=True

	lp -d "$tempDevName" "/home/pi/testImage.jpg"
fi

if [ "${ID_MODEL}" = "SELPHY_CP1500" ]; then
	tempDevName="Canon_SELPHY_CP1500${DEVNAME}"
	tempDevName=$(echo $tempDevName|sed 's/\//_/g')

	lpadmin -p "$tempDevName" -E -v "gutenprint53+usb://canon-cp1500/${ID_SERIAL_SHORT}" -P "/home/pi/Canon_SELPHY_CP1500.ppd"

	lpoptions -p "$tempDevName" -o StpiShrinkOutput=Expand
	lpoptions -p "$tempDevName" -o StpBorderless=True

	lp -d "$tempDevName" "/home/pi/testImage.jpg"
fi

if [ "${PRODUCT}" = "1452/9201/100" ]; then
	tempDevName="DNP_QW410${DEVNAME}"
	tempDevName=$(echo $tempDevName|sed 's/\//_/g')

	lpadmin -p "$tempDevName" -E -v "gutenprint53+usb://dnp-qw410/${ID_SERIAL_SHORT}" -P "/home/pi/Dai_Nippon_Printing_DP-QW410.ppd"

	lpoptions -p "$tempDevName" -o StpiShrinkOutput=Expand
	lpoptions -p "$tempDevName" -o StpBorderless=True

	# The DNP reprints continuously until it is unplugged. udev kills any
	# long-running process spawned directly from a RUN+= rule, so launch the
	# loop as a detached transient systemd unit that outlives this script.
	# onRemovingPrinter.sh stops the same unit on unplug.
	unitName="print-loop-${tempDevName}"
	systemd-run --no-block --collect --unit="$unitName" \
		/home/pi/printLoop.sh "$tempDevName"
fi
