#!/bin/sh

# This script just creates and writes some sane defaults to a brand new .xinitrc file.
# Look into polkit and make sure that these end up before the wm exec.

username="$(logname)"
filepath="/home/$username/"
filename=".xinitrc"
text="exec pipewire &
exec pipewire-pulse &\n"

if ! test -f "$filepath/$filename"; then
	touch "$filepath/$filename"
fi

echo -n "$text" | cat - "$filepath/$filename" > /tmp/$filename.tmp
mv /tmp/$filename.tmp "$filepath/$filename"
#sed -i "1s/^/dbus-run-session pipewire & \n/" $file
#sed -i "2s/^/dbus-run-session pipewire-pulse & \n/" $file
