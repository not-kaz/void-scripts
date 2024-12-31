#!/bin/bash

handle_error() {
	echo "Exiting due to error: $1"
	exit 1
}

command -v git >/dev/null 2>&1 || handle_error "Git is not installed?"
command -v sudo >/dev/null 2>&1 || handle_error "Sudo is not installed?"

git clone --depth 1 --single-branch --branch=nvidia https://github.com/fvalasiad/void-packages.git \
	|| handle_error "Git clone failed."

cd void-packages || handle_error "Cannot 'cd' into void-packages. Does it exist?"

./xbps-src binary-bootstrap || handle_error "Failed to run 'xbps-src binary-bootstrap'"

./xbps-src pkg nvidia || handle_error "Failed to run 'xbps-src pkg nvidia'"

read -p "Are you sure you want to install the nvidia package using 'sudo xi -f nvidia'? (y/n): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Installation canceled."
    exit 0
fi

sudo xi -f nvidia || handle_error "Failed to run 'xi -f nvidia'"

echo "Installation should be completed successfully."
exit 0
