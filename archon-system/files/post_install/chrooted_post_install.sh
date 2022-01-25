#!/usr/bin/env bash
# calamares-config
# https://github.com/archon-linux/archon-core
# Modified: @nekwebdev
# LICENSE: GPLv3
# Original:
# https://github.com/archcraft-os
# Author : Aditya Shakya <adi1090x@gmail.com>

###### => about ################################################################
# Post installation script for Archon Linux
# (Executes on target system to perform various operations)
# Nothing should be user specific
# Anything done in the user home should be done in the skel
# It will run the following tasks:
#   - Setup snapshots btrfs volumes with a snapper config
#   - Start systemd services and timers
#   - Remove unused ucode and VM/graphics drivers
#   - Disable autologin in the display manager and enables the correct one
#   - Remove all files and packages related to the installation
#	- Create custom xdg user dirs for user and skel
#	- Fix the bashrc for user and skel
#	- Create log folders for user and skel
#   - Move archon.desktop to autostart for user and skel
#   - Create .shh directories for user and skel
#	- Copy /etc/skel to /root
# 	- Apply new grub, pamac and pacman configs
#   - Enable all cores for pacman compilation
#	- Fix journal configs
#	- Set zram defaults
#	- Set default cursor

###### => variables ############################################################

# shellcheck source=/dev/null
# Get new user's username
new_user=$(< /etc/passwd grep "/home" | cut -d: -f1 | head -1)

# Setup file logging for debug purposes
debug=true

files_to_remove=(
	/etc/sudoers.d/02_g_wheel
	/etc/sudoers.d/g_wheel
	/etc/systemd/system/{etc-pacman.d-gnupg.mount,getty@tty1.service.d}
	/etc/initcpio
	/etc/mkinitcpio-archiso.conf
	/etc/polkit-1/rules.d/49-nopasswd-calamares.rules
	/etc/polkit-1/rules.d/49-nopasswd_global.rules
	/etc/{group-,gshadow-,passwd-,shadow-}
	/etc/udev/rules.d/81-dhcpcd.rules
	/etc/skel/{.bash_profile,.bash_logout,.xinitrc,.xsession,.xsession-errors,.xsession-errors.old}
	/home/"$new_user"/{.bash_profile,.bash_logout,.xinitrc,.xsession,.xsession-errors,.xsession-errors.old,.wget-hsts,.screenrc,.ICEauthority}
	/root/{.automated_script.sh,.zlogin}
	/root/{.xinitrc,.xsession}
	/usr/local/bin/{Installation_guide,livecd-sound,choose-mirror}
	/usr/share/calamares
	/{gpg.conf,gpg-agent.conf,pubring.gpg,secring.gpg}
	/var/lib/NetworkManager/NetworkManager.state
)

# Bind console output to a file
if $debug
then
	log_file=/var/log/chrooted_post_install.log
	# Close standard output file descriptor
	exec 1<&-
	# Close standard error file descriptor
	exec 2<&-
	# Open standard output as $log_file file for read and write.
	exec 1<>$log_file
	# Redirect standard error to standard output
	exec 2>&1
fi

###### => functions ############################################################

# edits a config file of this format key="value"
function set_config() {
    sudo sed -i "s/^\($2\s*=\s*\).*\$/\1$3/" "$1"
}

# Check if package installed (0) or not (1)
function is_pkg_installed() {
    local pkgname="$1"
    pacman -Q "$pkgname" >& /dev/null
}

# Remove a package
function remove_a_pkg() {
    local pkgname="$1"
    pacman -Rsn --noconfirm "$pkgname"
}

# Remove package(s) if installed
function remove_pkgs_if_installed() {
    local pkgname
    for pkgname in "$@" ; do
        is_pkg_installed "$pkgname" && remove_a_pkg "$pkgname"
    done
}

## -------- Enable/Disable services/targets ------
function manage_systemd_services() {
	local _enable_services=('NetworkManager.service'
							'systemd-timesyncd.service'
							'lightdm.service'
							'paccache.timer'
							'grub-btrfs.path'
							'logrotate.service'
							'snapper-timeline.timer'
							'snapper-cleanup.timer'
							'zramd.service')
    local srv

	# Replace paccache.service
	mv -f /usr/lib/systemd/system/paccache.service.archon /usr/lib/systemd/system/paccache.service 

	# Enable hypervisors services if installed on it
	[[ $(lspci | grep -i virtualbox) ]] && echo "+---------------------->>" && echo "[*] Enabling vbox service..." && systemctl enable -f vboxservice.service 
	[[ $(lspci -k | grep -i qemu) ]] && echo "+---------------------->>" && echo "[*] Enabling qemu service..." && systemctl enable -f qemu-guest-agent.service 

	# Manage services on target system
	for srv in "${_enable_services[@]}"; do
		echo "+---------------------->>"
		echo "[*] Enabling $srv for target system..."
		systemctl enable -f "$srv"
	done

	# Enable/Disable betterlockscreen, it required to be toggled
	systemctl enable betterlockscreen@"$new_user"
	systemctl disable betterlockscreen@"$new_user"

	# Manage targets on target system
	systemctl disable -f multi-user.target

	# Remove the before_login.service
	systemctl disable before_login.service
	rm -f /etc/systemd/system/before_login.service
	rm -f /usr/bin/before_login.sh
}

## -------- Remove VM Drivers --------------------

# Remove virtualbox pkgs if not running in vbox
function remove_vbox_pkgs() {
	local vbox_pkg='virtualbox-guest-utils'
	local vsrvfile='/etc/systemd/system/multi-user.target.wants/vboxservice.service'

    lspci | grep -i "virtualbox" >/dev/null
    if [[ "$?" != 0 ]] ; then
		echo "+---------------------->>"
		echo "[*] Removing $vbox_pkg from target system..."
		test -n "$(pacman -Q $vbox_pkg 2>/dev/null)" && pacman -Rnsdd ${vbox_pkg} --noconfirm
		if [[ -L "$vsrvfile" ]] ; then
			rm -f "$vsrvfile"
		fi
    fi
}

# Remove vmware pkgs if not running in vmware
function remove_vmware_pkgs() {
    local vmware_pkgs=('open-vm-tools' 'xf86-input-vmmouse' 'xf86-video-vmware')
    local _vw_pkg

    lspci | grep -i "VMware" >/dev/null
    if [[ "$?" != 0 ]] ; then
		for _vw_pkg in "${vmware_pkgs[@]}" ; do
			echo "+---------------------->>"
			echo "[*] Removing ${_vw_pkg} from target system..."
			test -n "$(pacman -Q "$_vw_pkg" 2>/dev/null)" && pacman -Rnsdd "$_vw_pkg" --noconfirm
		done
    fi
}

# Remove qemu guest pkg if not running in Qemu
function remove_qemu_pkgs() {
	local qemu_pkgs=('qemu-guest-agent' 'spice-vdagent')
	local qsrvfile='/etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service'

    lspci -k | grep -i "qemu" >/dev/null
    if [[ "$?" != 0 ]] ; then
		for _qemu_pkg in "${qemu_pkgs[@]}" ; do
			echo "+---------------------->>"
			echo "[*] Removing ${_qemu_pkg} from target system..."
			test -n "$(pacman -Q "$_qemu_pkg" 2>/dev/null)" && pacman -Rnsdd "$_qemu_pkg" --noconfirm
			if [[ -L "$qsrvfile" ]] ; then
				rm -f "$qsrvfile"
			fi
		done
    fi
}

## -------- Remove Un-wanted Drivers -------------
function remove_unwanted_graphics_drivers() {
	local gpu_file='/var/log/gpu-card-info.bash'

	local amd_card=''
	local intel_card=''
	local nvidia_card=''
	local nvidia_driver=''

	if [[ -r "$gpu_file" ]] ; then
		echo "+---------------------->>"
		echo "[*] Getting drivers info from $gpu_file file..."
		source ${gpu_file}
	else
		echo "+---------------------->>"
		echo "[!] Warning: file $gpu_file does not exist [!]"
	fi

	# Remove AMD drivers
    if [[ -n "$(lspci -k | grep 'Advanced Micro Devices')" ]] ; then
        amd_card=yes
    elif [[ -n "$(lspci -k | grep 'AMD/ATI')" ]] ; then
        amd_card=yes
    elif [[ -n "$(lspci -k | grep 'Radeon')" ]] ; then
        amd_card=yes
    fi
	echo "+---------------------->>"
    echo "[*] AMD Card : $amd_card"
	if [[ "$amd_card" == 'no' ]] ; then
		echo "[*] Removing AMD drivers from target system..."
        remove_pkgs_if_installed xf86-video-amdgpu xf86-video-ati
	fi

	# Remove intel drivers
	echo "+---------------------->>"
    echo "Intel Card : $intel_card"
	if [[ "$intel_card" == 'no' ]] ; then
		echo "+---------------------->>"
		echo "[*] Removing Intel drivers from target system..."
        remove_pkgs_if_installed xf86-video-intel
	fi

	# Remove All nvidia drivers
	echo "+---------------------->>"
    echo "[*] Nvidia Card : $nvidia_card"
	if [[ "$nvidia_card" == 'no' ]] ; then
		echo "[*] Removing All Nvidia drivers from target system..."
        remove_pkgs_if_installed xf86-video-nouveau nvidia nvidia-settings nvidia-utils
	fi

	# Remove nvidia drivers
	echo "+---------------------->>"
    echo "[*] Nvidia Drivers : $nvidia_driver"
	if [[ "$nvidia_driver" == 'no' ]] ; then
		echo "[*] Removing Nvidia drivers from target system..."
        remove_pkgs_if_installed nvidia nvidia-settings nvidia-utils
	fi

	# Remove nouveau drivers
	echo "+---------------------->>"
    echo "[*] Free Nvidia Drivers : $nvidia_driver"
	if [[ "$nvidia_driver" == 'yes' ]] ; then
		echo "[*] Removing open-source Nvidia drivers from target system..."
        remove_pkgs_if_installed xf86-video-nouveau
	fi
}

## -------- Remove Un-wanted Ucode ---------------

# Remove un-wanted ucode package
function remove_unwanted_ucode() {
	cpu="$(grep -w "^vendor_id" /proc/cpuinfo | head -n 1 | awk '{print $3}')"
	
	case "$cpu" in
		GenuineIntel)	echo "+---------------------->>"
						echo "[*] Removing amd-ucode from target system..."
						remove_pkgs_if_installed amd-ucode
						
						;;
		*)            	echo "+---------------------->>"
						echo "[*] Removing intel-ucode from target system..."
						remove_pkgs_if_installed intel-ucode
						
						;;
	esac
}

## -------- Remove Packages/Installer ------------

# Remove unnecessary packages
function remove_unwanted_packages() {
    local _packages_to_remove=('calamares-config'
							   'calamares'
							   'archinstall'
							   'arch-install-scripts'
							   'mkinitcpio-archiso'
							   'darkhttpd'
							   'irssi'
							   'lftp'
							   'kitty-terminfo'
							   'lynx'
							   'mc'
							   'ddrescue'
							   'testdisk'
							   'syslinux')
    local rpkg

	echo "+---------------------->>"
	echo "[*] Removing unnecessary packages..."
    for rpkg in "${_packages_to_remove[@]}"; do
		pacman -Rnsc "$rpkg" --noconfirm
	done
}

## -------- Delete Unnecessary Files -------------

# Clean live ISO stuff from target system
function clean_target_system() {
    local dfile
	echo "+---------------------->>"
	echo "[*] Deleting live ISO files..."
    for dfile in "${files_to_remove[@]}"; do 
		rm -rf "${dfile}"
	done
    find /usr/lib/initcpio -name 'archiso*' -type f -exec rm '{}' \;
}

## -------- Perform Misc Operations --------------

function disable_autologin() {
	# disabling autologin for lightdm (if exist)
	lightdm_config='/etc/lightdm/lightdm.conf'
	if [[ -e "$lightdm_config" ]]; then
		echo "+---------------------->>"
		echo "[*] Disabling autologin for lightdm..."
		sed -i -e 's|autologin-user=.*|#autologin-user=username|g' "$lightdm_config"
		sed -i -e 's|autologin-session=.*|#autologin-session=xfce|g' "$lightdm_config"
	fi

	# disabling autologin for lxdm (if exist)
	lxdm_config='/etc/lxdm/lxdm.conf'
	if [[ -e "$lxdm_config" ]]; then
		echo "+---------------------->>"
		echo "[*] Disabling autologin for lxdm..."
		sed -i -e 's/autologin=.*/#autologin=username/g' "$lxdm_config"
	fi

	# disabling autologin for sddm (if exist)
	sddm_config='/etc/sddm.conf.d/autologin.conf'
	if [[ -e "$sddm_config" ]]; then
		echo "+---------------------->>"
		echo "[*] Disabling autologin for sddm..."
		rm -rf "$sddm_config"
	fi
}

function setup_snapper() {
	echo "+---------------------->>"
	echo "[*] Creating snapper config..."
	umount /.snapshots
	rm -rf /.snapshots
	snapper -v --no-dbus -c root create-config /
	btrfs subvolume delete /.snapshots
	mkdir /.snapshots
	chmod 750 /.snapshots
	chmod a+rx /.snapshots
	chown :"${new_user}" /.snapshots
	mount -a
	
	echo "[*] Editing snapper config..."
	set_config "/etc/snapper/configs/root" ALLOW_USERS "\"""${new_user}""\""
	set_config "/etc/snapper/configs/root" TIMELINE_LIMIT_HOURLY 2
	set_config "/etc/snapper/configs/root" TIMELINE_LIMIT_DAILY 5
	set_config "/etc/snapper/configs/root" TIMELINE_LIMIT_WEEKLY 0
	set_config "/etc/snapper/configs/root" TIMELINE_LIMIT_MONTHLY 0
	set_config "/etc/snapper/configs/root" TIMELINE_LIMIT_YEARLY 0
}

function misc_actions() {
	echo "+---------------------->>"
	echo "[*] Create custom xdg-user-dirs"
	# Need a dummy home as $HOME would lead to root and mess with the cut.
	HOME="/my/dummy"
	source /etc/skel/.config/user-dirs.dirs
	xdg_folders=("$XDG_DESKTOP_DIR" "$XDG_DOCUMENTS_DIR" "$XDG_DOWNLOAD_DIR" "$XDG_MUSIC_DIR" "$XDG_PICTURES_DIR" "$XDG_PUBLICSHARE_DIR" "$XDG_TEMPLATES_DIR" "$XDG_VIDEOS_DIR")
	for root_path in "/etc/skel" "/home/${new_user}"; do
		for xdg_folder in "${xdg_folders[@]}"; do
			mkdir -p "${root_path}/$( echo "$xdg_folder" | cut -d'/' -f4- )"
		done
	done
	for xdg_folder in "${xdg_folders[@]}"; do
		chown "${new_user}":"${new_user}" "/home/${new_user}/$( echo "$xdg_folder" | cut -d'/' -f4- )"
	done

	# echo "+---------------------->>"
	# echo "[*] Applying the new bashrc"
	# mv -f /etc/skel/.bashrc.archon /etc/skel/.bashrc
	# mv -f /home/"$new_user"/.bashrc.archon /home/"$new_user"/.bashrc

	echo "+---------------------->>"
	echo "[*] Create log folder"
	mkdir -p /etc/skel/.local/log
	mkdir -p /home/"$new_user"/.local/log
	chown "$new_user":"$new_user" /home/"$new_user"/.local/log

	echo "+---------------------->>"
	echo "[*] Create /etc/skel/.ssh"
	mkdir /etc/skel/.ssh
	chmod 700 /etc/skel/.ssh
	cp -r /etc/skel/.ssh /home/"$new_user"/.ssh
	chown "$new_user":"$new_user" /home/"$new_user"/.ssh

	echo "+------------------------------------------------------->>"
	echo "Enable autostart of archon ansible"
	# Enable autostart of archon ansible
	mkdir -p /etc/skel/.config/autostart
	cp /etc/skel/.local/share/applications/archon.desktop /etc/skel/.config/autostart/archon.desktop
	mkdir -p /home/"$new_user"/.config/autostart
	cp /home/"$new_user"/.local/share/applications/archon.desktop /home/"$new_user"/.config/autostart/archon.desktop
	chown -R "$new_user":"$new_user" /home/"$new_user"/.config/autostart

	echo "+---------------------->>"
	echo "[*] Copying /etc/skel to /root"
	cp -aT /etc/skel /root
	
	echo "+---------------------->>"
	echo "[*] Applying the new grub config"
	mv -f /etc/default/grub.archon /etc/default/grub
	grub-mkconfig -o /boot/grub/grub.cfg

	echo "+---------------------->>"
	echo "[*] Applying the new pacman.conf and pamac.conf"
	mv -f /etc/pacman.conf.archon /etc/pacman.conf
	mv -f /etc/pamac.conf.archon /etc/pamac.conf

	echo "+---------------------->>"
	echo "[*] Using all cores when compressing packages with pacman..."
	set_config "/etc/makepkg.conf" COMPRESSXZ "(xz -c -z - --threads=0)"

	echo "+---------------------->>"
	echo "[*] Removing journald volatile storage..."
	rm /etc/systemd/journald.conf.d/volatile-storage.conf

	echo "+---------------------->>"
	echo "[*] Creating persistent and 500M limit journald conf..."
	PERSIST_CONF="/etc/systemd/journald.conf.d/00-persistent-storage.conf"
	echo "[Journal]" > "$PERSIST_CONF"
	echo "Storage=persistent" >> "$PERSIST_CONF"
	SIZE_CONF="/etc/systemd/journald.conf.d/00-journal-size.conf"
	echo "[Journal]" > "$SIZE_CONF"
	echo "SystemMaxUse=500M" >> "$SIZE_CONF"

	echo "+---------------------->>"
	echo "[*] Setting zramd defaults..."
	sed -i -e 's/.*FRACTION=.*/FRACTION=0.5/g' /etc/default/zramd
	sed -i -e 's/.*PRIORITY=.*/PRIORITY=0/g' /etc/default/zramd
	sed -i -e 's/.*SKIP_VM=.*/SKIP_VM=true/g' /etc/default/zramd

	echo "+---------------------->>"
	echo "[*] Setting default cursor to Nordzy-cursors"
	default_theme="/usr/share/icons/default/index.theme"
	sed -i -e 's/Inherits=.*/Inherits=Nordzy-cursors/g' "$default_theme"
	
	echo "+---------------------->>"
	echo "[*] KillUserProcesses in logind.conf"
	sed -i -e 's/.*KillUserProcesses=.*/KillUserProcesses=yes/g' /etc/systemd/logind.conf
	
	echo "+---------------------->>"
	echo "[*] set dash as symlink for /bin/sh instead of bash"
	ln -sfT dash /usr/bin/sh
}

###### => main #################################################################

echo "+------------------------------------------------------->>"
echo "Configure snapper"
setup_snapper

echo "+------------------------------------------------------->>"
echo "System services"
manage_systemd_services

echo "+------------------------------------------------------->>"
echo "Remove VM drivers"
remove_vbox_pkgs
remove_vmware_pkgs
remove_qemu_pkgs

echo "+------------------------------------------------------->>"
echo "Remove unwanted graphic drivers, ucode and packages"
remove_unwanted_graphics_drivers
remove_unwanted_ucode
remove_unwanted_packages

echo "+------------------------------------------------------->>"
echo "Disable autologin"
disable_autologin

echo "+------------------------------------------------------->>"
echo "Cleanup system"
clean_target_system

echo "+------------------------------------------------------->>"
echo "Miscelaneous commands"
misc_actions

exit 0
