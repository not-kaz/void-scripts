#!/bin/bash

# TODO : Add missing checks for already enabled services. 

# Xbps-install wrapper to allow for error handling
install_packages() {
	local packages=("$@")
	sudo xbps-install -Sy "${packages[@]}" || { echo "Error installing packages: ${packages[@]}"; exit 1; }
}

# Update system
sudo xbps-install -Syu

# Install non-free and multilib repos
repo_packages=("void-repo-nonfree" "void-repo-multilib" "void-repo-multilib-nonfree")
install_packages "${repo_packages[@]}"

# Install system time and timer packages
time_packages=("dcron" "ntp")
install_packages "${time_packages[@]}"
sudo ln -s /etc/sv/dcron /var/service/
sudo ln -s /etc/sv/ntpd /var/service/

# Enable periodic sdd trimming w/ cron
if [ ! -d "/etc/cron.weekly" ]; then
	sudo mkdir /etc/cron.weekly
fi
if [ ! -f "/etc/cron.weeky/fstrim" ]; then
	sudo touch /etc/cron.weekly/fstrim
	sudo bash -c 'echo -e "#!/bin/sh\nfstrim /" > /etc/cron.weekly/fstrim'
	sudo chmod u+x /etc/cron.weekly/fstrim
fi

# Install and enable seat management packages
seat_mgmt_packages=("dbus" "elogind")
install_packages "${seat_mgmt_packages[@]}"
sudo ln -s /etc/sv/dbus /var/service/

# Install a minimal subset of Xorg
install_packages "xorg-minimal" "xorg-fonts" "xdg-user-dirs" "xdg-utils"

# Install minimal subset of vendor gpu packages
gpu_packages=("mesa-dri" "vulkan-loader")
read -p "If using a discrete GPU, which vendor? (amd/nvidia/none): " gpu_vendor
case "$gpu_vendor" in
	amd)
		gpu_packages+=("mesa_vulkan_radeon" "xf86-video-amdgpu")
		;;
	nvidia)
		gpu_packages+=("nvidia" "xf86-video-nouveau")
		;;
	none)
		;;
	*)
		;;
esac
install_packages "${gpu_packages[@]}"

# Gnome DE installation
read -p "Do you want to install 'Gnome' as your DE? (y/n): " gnome_confirm
if [[ "$gnome_confirm" =~ ^[Yy]$ ]]; then
	install_packages "gnome"
fi

# Pipewire installation
read -p "Do you want to install 'pipewire' for audio? (y/n): " pw_install_confirm
if [[ "$pw_install_confirm" =~ ^[Yy]$ ]]; then
	install_package "pipewire"
fi

# Pipewire autostart
read -p "Do you want to autostart Pipewire with XDG? (y/n): " pw_auto_confirm
if [[ "$pw_auto_confirm" =~ ^[Yy]$ ]]; then
	if [ -d "/etc/xdg/autostart" ]; then
		if [ -f "/usr/share/applications/pipewire-pulse.desktop" ] && [ -f "/usr/share/applications/pipewire.desktop" ]; then 
			sudo cp /usr/share/applications/pipewire-pulse.desktop /etc/xdg/autostart/
			sudo cp /usr/share/applications/pipewire.desktop /etc/xdg/autostart/
		else
			echo "Pipewire desktop files not found. Unable to setup autostart."
		fi
	else 
		echo "Directory '/etc/xdg/autostart' not found."
	fi
fi

# Install base daily use packages
base_packages=("base-devel" "ffmpeg" "firefox")
install_packages "${base_packages[@]}"

# Enable GDM
if [[ "$gnome_confirm" =~ ^[Yy]$ ]]; then
	sudo ln -s /etc/sv/gdm /var/service/
fi

