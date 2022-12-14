# Update system and install non-free repo
xpbs-install -Syu
xbps-install -S void-repo-nonfree

# Get and enable a cron daemon
xbps-install -S dcron
ln -s /etc/sv/dcron /var/service/

# Enable periodic sdd trimming w/ cron
touch /etc/cron.weekly/fstrim
echo "#!/bin/sh /n fstrim /" >> /etc/cron.weekly/fstrim
chmod u+x /etc/cron.weekly/fstrim

# Seat management 
xbps-install -S elogind
ln -s /etc/sv/dbus /var/service/

# Xorg
xbps-install -S xorg-minimal xorg-fonts xdg-user-dirs xdg-utils

# Graphics 
xbps-install -S mesa-dri vulkan-loader mesa-vulkan-radeon xf86-video-amdgpu

# Audio
xbps-install -S pipewire

# Development 
xbps-install -S gcc make git pkg-config

# Time
xbps-install -S ntp
ln -s /etc/sv/ntpd /var/service/

# Video codec
xbps-install -S ffmpeg

# Browser
xbps-install -S firefox
