#! /bin/sh

for wireless in /sys/class/net/*/wireless
do
	[ -d "$wireless" ] || continue
	iface=$(basename "$(dirname "$wireless")")
	iw dev "$iface" set power_save off
done
