#! /bin/sh

if [ "${PRODUCT}" = "4a9/32db/1" ]; then
	tempDevName="Canon_SELPHY_CP1300${DEVNAME}"
	tempDevName=$(echo $tempDevName|sed 's/\//_/g')
	lpadmin -x "$tempDevName"
fi

if [ "${PRODUCT}" = "4a9/3302/1" ]; then
	tempDevName="Canon_SELPHY_CP1500${DEVNAME}"
	tempDevName=$(echo $tempDevName|sed 's/\//_/g')
	lpadmin -x "$tempDevName"
fi

if [ "${PRODUCT}" = "1452/9201/100" ]; then
	tempDevName="DNP_QW410${DEVNAME}"
	tempDevName=$(echo $tempDevName|sed 's/\//_/g')
	# Stop the continuous reprint loop started in onAddingPrinter.sh, then
	# remove the queue. Stopping first prevents new jobs racing the removal.
	systemctl stop "print-loop-${tempDevName}" 2>/dev/null
	lpadmin -x "$tempDevName"
fi
