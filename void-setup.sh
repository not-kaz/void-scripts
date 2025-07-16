#!/bin/sh

set -eu

# Message colors codes
#RED='\033[0;31m'
#GREEN='\033[0;32m'
#YELLOW='\033[1;33m'
#BLUE='\033[0;34m'
#NC='\033[0m'
RED="$(printf '\033[0;31m')"
GREEN="$(printf '\033[0;32m')"
YELLOW="$(printf '\033[1;33m')"
BLUE="$(printf '\033[0;34m')"
NC="$(printf '\033[0m')"

log() {
   printf "${GREEN}[LOG] %s${NC}\n" "$1"
}

warn() {
	printf "${YELLOW}[WARNING] %s${NC}\n" "$1" >&2
}

handle_error() {
	printf "${RED}[ERROR] %s${NC}\n" "$1" >&2
    exit 1
}

prompt_user() {
	prompt="$1"
	reponse=""

	while true; do
		printf "%s[PROMPT] %s (Yy/Nn/press ENTER to skip): %s" "$BLUE" "$prompt" "$NC" 
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

	if [ -n "$pkg_group" ]; then
		log "Installing package group $pkg_group..."
	fi

	if [ -z "$requested_pkgs" ]; then
		warn "No packages specified for installation"
		return 1
	fi

	for pkg in $requested_pkgs; do
		if is_pkg_installed "$pkg"; then
			log "Package '$pkg' is already installed, skipping..."
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
        warn "Service $service not found in /etc/sv/, or already enabled."
    fi
}

disable_service() {
	service="$1"

	if [ -f "/var/service/$service" ]; then
		rm /var/service/$service
		log "Disabled service '$service'."
	else
		warn "Attempted to disable service '$service', but it was not found." 
	fi
}

is_service_enabled() {
    [ -L "/var/service/$service" ] && log "Service $1 is already enabled."
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

    if prompt_user "Do you want to install the '$want' repositories? (Recommended)"; then
        log "Installing $want sub-repositories..."
        install_pkgs "$repo_pkgs" "$want sub-repositories"
    fi
}


install_firmware_pkgs() {
	choice=""

	while true; do
		printf "%s[PROMPT] Which firmware package to you want to install? (amd/intel or ENTER to skip): %s" "$BLUE" "$NC"
		read -r choice
		case "$choice" in
			amd|AMD) 
				install_pkgs "linux-firmware-amd"
				return 0
				;;
			intel|INTEL) 
				install_pkgs "intel-ucode"
				return 0
				;;
			"") 
				# User pressed ENTER to skip
				return 0
				;;
			*) log "Please answer amd, intel or press ENTER to skip."
				;;
		esac
	done
}

install_cron_daemon() {
	choice=""

	# TODO: Implement case-insensitive choice and use it to enable the appropriate service.
	# TODO: Implement check to see if user already has ANY cron daemon installed, to prevent bloat and misconfiguration."
	while true; do
		printf "%s[PROMPT] Which cron daemon would you like to install? (cronie/dcron/fcron or press ENTER to skip): %s" "$BLUE" "$NC"
		read -r choice
		case "$choice" in
			cronie|CRONIE|Cronie) 
				install_pkgs "cronie"
				return 0
				;;
			dcron|DCRON|Dcron) 
				install_pkgs "dcron"
				return 0
				;;
			fcron|FCRON|Fcron) 
				install_pkgs "fcron"
				return 0
				;;
			"") 
				# User pressed ENTER to skip
				return 0
				;;
			*) log "Please answer 'cronie', 'dcron', 'fcron' or press ENTER to skip: "
				;;
		esac
	done
	# TODO: Enable weekly ssd trim
}

install_ntp_pkg() {
	:
}

install_session_mgmt_pkgs() {
	session_mngr_pkgs="dbus elogind"

	log "Installing 'dbus' message bus system and 'elogind' session manager..."
	install_pkgs "$session_mngr_pkgs"
	log "Disabling 'acpid' service, as it can conflict with 'elogind'."
	disable_service "acpid"
	log "Enabling service 'dbus', if you are experiencing issues with 'elogind', enable it's service explicity."
	enable_service "dbus"
}

install_gpu_drivers() {
	# Offer to install 'xorg', say it's recommended.
	gpu_info=$(lspci | grep -i 'vga\|3d\|display')
	choice=""
	gpu_pkgs="xorg"


	while true; do
		printf "%s[PROMPT] Which gpu vendor drivers do you want to install? (amd/nvidia or press ENTER to skip): %s" "$BLUE" "$NC"
		read -r choice
		case "$choice" in
			amd|AMD) 
				# Check if AMD adapter is detected
				if echo "$gpu_info" | grep -iq 'amd'; then
					if prompt_user "It is required to install the 'multilib' repository for AMD drivers to function properly. Do you want to install them? "; then
						install_sub_repos multilib
					else
						log "Returning to GPU vendor select. Press ENTER to skip GPU driver installation."
						return 0
					fi
				else 
					if ! prompt_user "AMD GPU was not detected with 'lspci', do you still want to continue w/ installation?"; then
						log "Install aborted due to missing AMD GPU. Returning to vendor select."
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
						if prompt_user "It is required to install the 'non-free' repositories for Nvidia drivers to function properly. Do you want to install them? "; then
							install_sub_repos
						else
							log "Returning to GPU vendor select. Press ENTER to skip GPU driver installation."
							continue
						fi
					fi
				else
					if prompt_user "Nvidia GPU was not detected with 'lspci', do you still want to continue w/ installation?"; then
						log "Continuing despite no NVIDIA GPU..."
					else
						log "Installation aborted due to missing NVIDIA GPU. Returning to vendor select."
						continue
					fi
				fi
				gpu_pkgs="$gpu_pkgs nvidia xf86-video-nouveau mesa-dri mesa-dri-32bit nvidia-libs-32bit"
				install_pkgs "$gpu_pkgs"
				return 0
				;;
			"") 
				# User pressed ENTER to skip
				return 0
				;;
			*) log "Please answer amd/nvidia or press ENTER to skip."
				;;
		esac
	done
}

install_fonts() {
	:
}

install_desktop_env() {
	:
}

install_audio_pkgs() {
	conf="20-pipewire-pulse.conf"
	src="/usr/share/examples/pipewire/"
	dest="/etc/pipewire/pipewire.conf.d/"

	if ! is_pkg_installed "elogind"; then
		warn "'elogind' is not installed. \
			Without it, users must be added to the 'audio' and 'video' groups for PipeWire to work properly."
	fi

	# We only support Pipewire.
	install_pkgs "pipewire"

	if [ ! -d ${dest} ]; then
		log "Creating folder '$dest' for Pipewire PulseAudio config."
		mkdir -p ${dest}
	else
		log "Pipewire PulseAudio config directory already created. Skipping..."
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
	# Offer to add flathub repo.
	:
}

install_additional_pkgs() {
	# User requested packages to install.
	:
}

do_perf_tweaks() {
	# Esync compatiblity for game perf.
	# Tweak sysctl for more game compatiblity.
	:
}

enable_display_manager() {
	# Inform user that this might start display manager right away, if they do not want to, they should enable manually.
	# If running GDM + Wayland + Nvidia, offer to  create udev rule.
	:
}


main() {
	# Check if XBPS is present on system and update it
	if ! command -v xbps-install >/dev/null 2>&1 && ! command -v xbps-query >/dev/null 2>&1; then
		handle_error "XBPS not found. Couldn't run xbps-install or xbps-query."
	fi
	log "Updating XBPS and the XBPS repository database..."
	xbps-install -Su xbps || handle_error "Failed to update XBPS."
	xbps-install -Syu || handle_error "Failed to update XBPS database."
	log "Updated XBPS and the XBPS database successfully."

	install_sub_repos all
	install_firmware_pkgs
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
