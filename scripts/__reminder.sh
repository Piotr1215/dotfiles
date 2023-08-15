#!/bin/bash

# Ensure we have access to the X server
xhost +

message="$1"
time_string="$2"

# Define delay based on the given time string
case $time_string in
"tomorrow")
	delay="8:00 AM tomorrow"
	echo $delay
	;;
"eow")
	delay="12:00 PM next Fri"
	echo $delay
	;;
"eod")
	delay="8:00 PM"
	echo $delay
	;;
*m)
	delay="now + ${time_string%m} minutes"
	echo $delay
	;;
*h)
	delay="now + ${time_string%h} hours"
	echo $delay
	;;
*d)
	delay="now + ${time_string%d} days"
	echo $delay
	;;
*w)
	delay="now + ${time_string%w} weeks"
	echo $delay
	;;
*y)
	delay="now + ${time_string%y} years"
	echo $delay
	;;
*)
	echo "Invalid time format"
	exit 1
	;;
esac

echo "DISPLAY=:1 zenity --info --text='$message'" | at $delay

# Log the task to Taskwarrior after showing the zenity dialog
task log "$message" +reminder
