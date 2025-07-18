#!/bin/sh

set -eu

# Color codes
RED="$(printf '\033[0;31m')"
GREEN="$(printf '\033[0;32m')"
YELLOW="$(printf '\033[1;33m')"
BLUE="$(printf '\033[0;34m')"
NC="$(printf '\033[0m')"

DISPLAY_MANAGER=""

log() {
	printf "%s[LOG] %s%s\n" "$GREEN" "$1" "$NC"
}

warn() {
	printf "%s[WARNING] %s%s\n" "$YELLOW" "$1" "$NC" >&2
}

handle_error() {
	printf "%s[ERROR] %s%s\n" "$RED" "$1" "$NC" >&2
	exit 1
}

prompt_user() {
	prompt="$1"
	while true; do
		printf "%s[PROMPT] %s (Yy/Nn/ENTER to skip): %s" "$BLUE" "$prompt" "$NC" 
		read -r response
		case "$response" in
			[Yy]|[Yy][Ee][Ss]) return 0;;
			[Nn]|[Nn][Oo]|"") return 1;;
			*) printf "Answer with Yes/Y/y, No/N/n, or press ENTER to skip.\n";;
		esac
	done
}

install_pkgs() {
	requested_pkgs="$1"
	pkg_group="${2:-}"
	pkgs_to_install=""

	[ -n "$pkg_group" ] && log "Installing package group $pkg_group..."

	if [ -z "$requested_pkgs" ]; then
		warn "No packages specified"
		return 1
	fi

	for pkg in $requested_pkgs; do
		if is_pkg_installed "$pkg"; then
			log "Package '$pkg' already installed, skipping..."
		else
			pkgs_to_install="$pkgs_to_install $pkg"
		fi
	done	

	# Trim leading/trailing spaces
	# shellcheck disable=SC2086
	set -- $pkgs_to_install
	pkgs_to_install="$*"

	if [ -n "$pkgs_to_install" ]; then
		log "Installing packages: $pkgs_to_install"
		xbps-install -y "$pkgs_to_install" || handle_error "Failed to install packages."
	fi
}

is_pkg_installed() {
	xbps-query -p pkgver "$1" >/dev/null 2>&1
}

enable_service() {
	service="$1"
	if [ -d "/etc/sv/$service" ] && [ ! -L "/var/service/$service" ]; then
		ln -s "/etc/sv/$service" /var/service/ || handle_error "Failed to enable $service"
		log "Enabled service: $service"
	else 	
		warn "Service $service not found or already enabled."
	fi
}

disable_service() {
	service="$1"
	if [ -L "/var/service/$service" ]; then
		rm /var/service/$service
		log "Disabled service '$service'."
	else
		warn "Service '$service' not found or already disabled." 
	fi
}

is_service_enabled() {
	[ -L "/var/service/$1" ] && log "Service $1 is already enabled."
}

install_sub_repos() {
	want="$1"  # one of: nonfree, multilib, all
	repo_pkgs=""

	case "$want" in
		nonfree)
			repo_pkgs="void-repo-nonfree"
			;;
		multilib)
			repo_pkgs="void-repo-multilib void-repo-multilib-nonfree"
			;;
		all|"")
			repo_pkgs="void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree"
			;;
		*)
			echo "Invalid option to install_sub_repos: '$want'"
			return 1
			;;
	esac

	if prompt_user "Install '$want' repositories? (Recommended)"; then
		log "Installing $want sub-repositories..."
		install_pkgs "$repo_pkgs" "$want sub-repositories"
	fi
}

install_firmware_pkgs() {
	while true; do
		printf "%s[PROMPT] Which firmware package? (amd/intel or ENTER to skip): %s" "$BLUE" "$NC"
		read -r choice
    	if [ -z "$choice" ]; then
			warn "Skipping firmware installation..."
   			return 0
		fi
		choice=$(printf '%s\n' "$choice" | tr '[:upper:]' '[:lower:]')
		case "$choice" in
			amd) 
				install_pkgs "linux-firmware-amd"
				return 0
				;;
			intel) 
				install_pkgs "intel-ucode"
				return 0
				;;
			"") 
				return 0
				;;
			*) log "Please answer amd, intel or press ENTER to skip."
   				continue
				;;
		esac
	done
}

install_cron_pkg() {
	while true; do
		printf "%s[PROMPT] Which cron daemon? (cronie/dcron/fcron or ENTER to skip): %s" "$BLUE" "$NC"
		read -r choice
  		if [ -z "$choice" ]; then
			warn "Skipping cron daemon installation..."
   			return 0
		fi
		choice=$(printf '%s\n' "$choice" | tr '[:upper:]' '[:lower:]')
  		case "$choice" in
		    cronie|dcron|fcron)
				install_pkgs "$choice"
				log "Enabling '$choice' service..."
				enable_service "$choice"
				break
				;;
		    *)
				log "Invalid choice, try again."
				continue
				;;
		esac
	done
  	if prompt_user "Do you wish to enable a weekly SSD trim cron job with '$choice'? (Recommended)"; then
		if [ -n "$choice" ]; then
  			CRON_JOB_PATH="/etc/cron.weekly/fstrim"
	 
		    mkdir -p "$(dirname "$CRON_JOB_PATH")"
			printf "#!/bin/sh\nfstrim /\n" > "$CRON_JOB_PATH"
		    chmod +x "$CRON_JOB_PATH"
		fi
  	fi
}

install_ntp_pkg() {
	while true; do
		# Prompt user for input
		printf "%s[PROMPT] Choose an NTP package to install (ntp, chrony, openntpd, ntpd-rs or ENTER to skip): %s" "$BLUE" "$NC"
		read -r choice
		if [ -z "$choice" ]; then
		    log "Skipping NTP package installation."
		    return 0
		fi
		# Convert choice to lowercase manually (POSIX-compliant)
		choice=$(printf '%s\n' "$choice" | tr '[:upper:]' '[:lower:]')
		# Validate the choice and break if valid
		case "$choice" in
		    ntp)
	  			service="isc-ntpd"
      				break
	  			;;
	  		chrony)
	 			service="chronyd"
           			break
	 			;;
	 		openntpd)
				service="openntpd"
           			break
	 			;;
			ntpd-rs)
   	 			service="ntpd-rs"
	      			break
				;;
		    *)
				log "Invalid choice, try again."
				# TODO: Check if 'continue' is POSIX compliant
				continue
				;;
		esac
	done
 	log "Installing '$choice' and enabling '$service' daemon..."
 	install_pkgs "$choice"
  	enable_service "$service"
}

install_session_mgmt_pkgs() {
	session_mngr_pkgs="dbus elogind"

	log "Installing 'dbus' message bus system and 'elogind' session manager..."
	install_pkgs "$session_mngr_pkgs"
	log "Disabling 'acpid' service (can conflict with 'elogind')."
	disable_service "acpid"
	log "Enabling 'dbus' service. If experiencing issues with 'elogind', enable it explicitly."
	enable_service "dbus"
}

install_gpu_drivers() {
	# TODO: If possible, move these variables closer to execution point.
	gpu_info=$(lspci | grep -i 'vga\|3d\|display')
	gpu_pkgs="xorg"

	while true; do
		printf "%s[PROMPT] Which GPU vendor drivers? (amd/nvidia or ENTER to skip): %s" "$BLUE" "$NC"
		read -r choice
		case "$choice" in
			amd|AMD) 
				# Check if AMD adapter is detected
				if echo "$gpu_info" | grep -iq 'amd'; then
					if prompt_user "AMD drivers require 'multilib' repository. Install it?"; then
						install_sub_repos multilib
					else
						log "Returning to GPU vendor select. Press ENTER to skip GPU driver installation."
						return 0
					fi
				else 
					if ! prompt_user "AMD GPU not detected. Continue anyway?"; then
						log "Install aborted. Returning to vendor select."
						continue
					fi
				fi
				gpu_pkgs="$gpu_pkgs linux-firmware-amd mesa-dri mesa-vulkan-radeon vulkan-loader"
				install_pkgs "$gpu_pkgs"
				return 0
				;;
			nvidia|NVIDIA) 
				# Check if Nvidia adapter is detected
				if echo "$gpu_info" | grep -iq 'nvidia'; then
					if ! is_pkg_installed "void-repo-nonfree" && ! is_pkg_installed "void-repo-multilib-nonfree"; then
						if prompt_user "NVIDIA drivers require 'non-free' repositories. Install them?"; then
							install_sub_repos
						else
							log "Returning to GPU vendor select. Press ENTER to skip GPU driver installation."
							continue
						fi
					fi
				else
					if prompt_user "NVIDIA GPU not detected. Continue anyway?"; then
						log "Continuing despite no NVIDIA GPU..."
					else
						log "Installation aborted. Returning to vendor select."
						continue
					fi
				fi
				gpu_pkgs="$gpu_pkgs nvidia xf86-video-nouveau mesa-dri mesa-dri-32bit nvidia-libs-32bit"
				install_pkgs "$gpu_pkgs"
				mkdir -p /etc/modprobe.d/
	 			# TODO: This can be tidied up a bit, too much repetition.
				printf "blacklist nouveau\noptions nouveau modeset=0" > /etc/modprobe.d/disable-nouveau.conf
				printf "options nvidia NVreg_InitializeSystemMemoryAllocations=0 NVreg_EnableResizableBar=1 NVreg_RegistryDwords=\"RMIntrLockingMode=1\"\n" > /etc/modprobe.d/nvidia-options.conf
				printf "options nvidia NVreg_PreserveVideoMemoryAllocations=1\n" >> /etc/modprobe.d/nvidia-options.conf
				printf "options nvidia NVreg_UsePageAttributeTable=1\n" >> /etc/modprobe.d/nvidia-options.conf
				printf "options nvidia-drm modeset=1\n" >> /etc/modprobe.d/nvidia-options.conf
				xbps-reconfigure -fa
				return 0
				;;
			"") 
				return 0
				;;
			*) log "Please answer amd/nvidia or press ENTER to skip."
				;;
		esac
	done
}

install_fonts() {
	# Currently only 'Noto-fonts' family is supported, as it's 'CJK' and 'emoji' coverage provides a consistent look.
	fonts="noto-fonts-ttf noto-fonts-cjk noto-fonts-emoji"

  	install_pkgs "$fonts"
}

install_desktop_env() {
	while true; do
		printf "%s[PROMPT] Choose an desktop environment to install (gnome/kde/xfce or ENTER to skip): %s" "$BLUE" "$NC"
		read -r choice
		if [ -z "$choice" ]; then
			log "Skipping DE installation."
			break
		fi
		choice=$(printf '%s\n' "$choice" | tr '[:upper:]' '[:lower:]')
  		# TODO: Add and test other DE choices.
		case "$choice" in
		    gnome)
      			if ! is_service_enabled "dbus"; then
		 		log "'dbus' service not found, reinstalling package and attemping to enable it.\
	    				Required for GNOME to function properly."
		 		install_pkgs "dbus"
				enable_service "dbus"
		 		fi
				install_pkgs "$choice"
				log "Installed 'GNOME' desktop environment package. Display manager assigned, it will be enabled at the end of the script."
				if prompt_user "Do you wish to install and enable 'NetworkManager' service with GNOME? (Recommended)"; then
	   			install_pkgs "NetworkManager"
	       			# Disable any other network services that could conflict with NetworkManager
	   			disable_service "dhcpd"
	       		disable_service "wpa_supplicant"
		  		disable_service "wicd"
				enable_service "NetworkManager"
	   			fi
	   			# Allow GDM to run under Wayland with Nvidia.
	   			ln -s /dev/null /etc/udev/rules.d/61-gdm.rules
	   			log "GNOME display manager will be enabled at the end of script."
	   			DISPLAY_MANAGER="gdm"
				break
				;;
		    *)
			echo "Invalid choice, please choose again."
				continue
				;;
		esac
	done
}

install_audio_pkgs() {
	conf="20-pipewire-pulse.conf"
	src="/usr/share/examples/pipewire/"
	dest="/etc/pipewire/pipewire.conf.d/"

	if ! is_pkg_installed "elogind"; then
		warn "'elogind' not installed. Users must be added to 'audio' and 'video' groups for PipeWire to work properly."
	fi
	# We only support Pipewire.
	install_pkgs "pipewire"
	if [ ! -d ${dest} ]; then
		log "Creating folder '$dest' for Pipewire PulseAudio config."
		mkdir -p ${dest}
	else
		log "Pipewire PulseAudio config directory already exists. Skipping..."
	fi
	# Configure Pipewire to use PulseAudio interface.
	if [ -f "${src}${conf}" ] && [ ! -e "${dest}${conf}" ]; then
		log "Creating PipeWire conf..."
		ln -s "${src}${conf}" "${dest}${conf}"
	else 
		log "Pipewire config already setup. Skipping..."
	fi
}

install_flatpak() {
	# TODO: Add more output here and maybe some error checking for 'flatpak remote-add'.
	if prompt_user "Install 'flatpak' and add the 'flathub' repository? (Recommended)"; then
 		install_pkgs "flatpak"
   		flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
 	fi
}

install_additional_pkgs() {
	printf "Install any additional packages (Press ENTER to skip): "
	read -r choice
	if [ -n "$choice" ]; then
		install_pkgs "$choice"
	fi
}

do_perf_tweaks() {
	# Esync compatibility for game performance.
	# Tweak sysctl for more game compatibility.
	if prompt_user "Modify system to be compatible with 'esync' for game performance and adjust 'sysctl' values for game stability? (Recommended) "; then
 		# TODO: Improve this prompt, it's lacking clarification. It needs to be the actual username, not display name etc."
 		printf "[PROMPT] Provide username: "
 		read -r $username
   		if [ -n "$username" ] && [ -f /etc/security/limits.conf ]; then
	 		log "Modifying 'ulimits' in '/etc/security/limits.conf' for 'esync' compatiblity..."
			printf "%s hard nofile 524288" >> /etc/security/limits.conf
   			mkdir -p /etc/sysctl.d/
	  		printf "vm.max_map_count=2147483642" > /etc/sysctl.d/80-gamecompatibility.conf
		 	if prompt_user "Install 'gamemode' package? (Recommended) "; then
		 		install_pkgs "gamemode"
	 			usermod -aG gamemode "$username"
		 	fi
   		fi
	fi
}

enable_display_manager() {
	if [ -n "$DISPLAY_MANAGER" ]; then
 		log "Enabling display manager..."
 		enable_service "$DISPLAY_MANAGER"
   	fi
}

main() {
	# Check if XBPS is present on system and update it
	if ! command -v xbps-install >/dev/null 2>&1 && ! command -v xbps-query >/dev/null 2>&1; then
		handle_error "XBPS not found. Couldn't run xbps-install or xbps-query."
	fi
	log "Updating XBPS and repository database..."
	xbps-install -Su xbps || handle_error "Failed to update XBPS."
	xbps-install -Syu || handle_error "Failed to update XBPS database."
	log "Updated XBPS and database successfully."
	install_sub_repos all
	install_firmware_pkgs
 	install_cron_pkg
	install_ntp_pkg
	install_session_mgmt_pkgs
	install_gpu_drivers
	install_fonts
	install_desktop_env
	install_audio_pkgs
	enable_display_manager
	log "Void setup script finished successfully." 
	log "Reboot for changes to take effect."
}

main "$@"
