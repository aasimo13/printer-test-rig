#! /bin/sh

lpstat -a | cut -d" " -f1 | while read CIAO
do
	lpadmin -x "$CIAO"
done
