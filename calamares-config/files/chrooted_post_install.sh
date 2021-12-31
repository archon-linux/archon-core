#!/bin/bash
##################################################################################################
## ██████╗  ██████╗ ███████╗████████╗    ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗      ##
## ██╔══██╗██╔═══██╗██╔════╝╚══██╔══╝    ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║      ##
## ██████╔╝██║   ██║███████╗   ██║       ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║      ##
## ██╔═══╝ ██║   ██║╚════██║   ██║       ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║      ##
## ██║     ╚██████╔╝███████║   ██║       ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗ ##
## ╚═╝      ╚═════╝ ╚══════╝   ╚═╝       ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝ ##
##################################################################################################
## Copyright (C) 2020-2021 Aditya Shakya <adi1090x@gmail.com>
## Everyone is permitted to copy and distribute copies of this file under GNU-GPL3
## Modified from https://github.com/archcraft-os
##################################################################################################
## Post installation script for Archon Linux
## (Executes on target system to perform various operations)
## It will run the following tasks:
##   - Setup snapshots btrfs volumes with a snapper config
##   - Start systemd services and timers
##   - Remove unused ucode and VM/graphics drivers
##   - Disable autologin in the display manager and enables the correct one
##   - Remove all files related to the installation including this script and post_install
##   - Create .shh directories in user's home and /etc/skel
##   - Copy /etc/skel to /root and enable all cores for pacman compilation
##   - Move archon.desktop to autostart and delete pre/post install scripts
##################################################################################################

# ################################################################################################
# # Variables
# ################################################################################################
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

# ################################################################################################
# # Main functions
# ################################################################################################

# edits a config file of this format key="value"
_set_config() {
    sudo sed -i "s/^\($2\s*=\s*\).*\$/\1$3/" "$1"
}

# Check if package installed (0) or not (1)
_is_pkg_installed() {
    local pkgname="$1"
    pacman -Q "$pkgname" >& /dev/null
}

# Remove a package
_remove_a_pkg() {
    local pkgname="$1"
    pacman -Rsn --noconfirm "$pkgname"
}

# Remove package(s) if installed
_remove_pkgs_if_installed() {
    local pkgname
    for pkgname in "$@" ; do
        _is_pkg_installed "$pkgname" && _remove_a_pkg "$pkgname"
    done
}

## -------- Enable/Disable services/targets ------
_manage_systemd_services() {
	local _enable_services=('NetworkManager.service'
							'bluetooth.service'
							'systemd-timesyncd.service'
							'lightdm.service'
							'paccache.timer'
							'grub-btrfs.path'
							'logrotate.timer'
							"betterlockscreen@$new_user")
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
		systemctl enable -f ${srv}
	done

	# Manage targets on target system
	systemctl disable -f multi-user.target
}

## -------- Remove VM Drivers --------------------

# Remove virtualbox pkgs if not running in vbox
_remove_vbox_pkgs() {
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
_remove_vmware_pkgs() {
    local vmware_pkgs=('open-vm-tools' 'xf86-input-vmmouse' 'xf86-video-vmware')
    local _vw_pkg

    lspci | grep -i "VMware" >/dev/null
    if [[ "$?" != 0 ]] ; then
		for _vw_pkg in "${vmware_pkgs[@]}" ; do
			echo "+---------------------->>"
			echo "[*] Removing ${_vw_pkg} from target system..."
			test -n "$(pacman -Q "${_vw_pkg}" 2>/dev/null)" && pacman -Rnsdd "${_vw_pkg}" --noconfirm
		done
    fi
}

# Remove qemu guest pkg if not running in Qemu
_remove_qemu_pkgs() {
	local qemu_pkg='qemu-guest-agent'
	local qsrvfile='/etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service'

    lspci -k | grep -i "qemu" >/dev/null
    if [[ "$?" != 0 ]] ; then
		echo "+---------------------->>"
		echo "[*] Removing $qemu_pkg from target system..."
		test -n "$(pacman -Q $qemu_pkg 2>/dev/null)" && pacman -Rnsdd ${qemu_pkg} --noconfirm
		if [[ -L "$qsrvfile" ]] ; then
			rm -f "$qsrvfile"
		fi
    fi
}

## -------- Remove Un-wanted Drivers -------------
_remove_unwanted_graphics_drivers() {
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
        _remove_pkgs_if_installed xf86-video-amdgpu xf86-video-ati
	fi

	# Remove intel drivers
	echo "+---------------------->>"
    echo "Intel Card : $intel_card"
	if [[ "$intel_card" == 'no' ]] ; then
		echo "+---------------------->>"
		echo "[*] Removing Intel drivers from target system..."
        _remove_pkgs_if_installed xf86-video-intel
	fi

	# Remove All nvidia drivers
	echo "+---------------------->>"
    echo "[*] Nvidia Card : $nvidia_card"
	if [[ "$nvidia_card" == 'no' ]] ; then
		echo "[*] Removing All Nvidia drivers from target system..."
        _remove_pkgs_if_installed xf86-video-nouveau nvidia nvidia-settings nvidia-utils
	fi

	# Remove nvidia drivers
	echo "+---------------------->>"
    echo "[*] Nvidia Drivers : $nvidia_driver"
	if [[ "$nvidia_driver" == 'no' ]] ; then
		echo "[*] Removing Nvidia drivers from target system..."
        _remove_pkgs_if_installed nvidia nvidia-settings nvidia-utils
	fi

	# Remove nouveau drivers
	echo "+---------------------->>"
    echo "[*] Free Nvidia Drivers : $nvidia_driver"
	if [[ "$nvidia_driver" == 'yes' ]] ; then
		echo "[*] Removing open-source Nvidia drivers from target system..."
        _remove_pkgs_if_installed xf86-video-nouveau
	fi
}

## -------- Remove Un-wanted Ucode ---------------

# Remove un-wanted ucode package
_remove_unwanted_ucode() {
	cpu="$(grep -w "^vendor_id" /proc/cpuinfo | head -n 1 | awk '{print $3}')"
	
	case "$cpu" in
		GenuineIntel)	echo "+---------------------->>"
						echo "[*] Removing amd-ucode from target system..."
						_remove_pkgs_if_installed amd-ucode
						
						;;
		*)            	echo "+---------------------->>"
						echo "[*] Removing intel-ucode from target system..."
						_remove_pkgs_if_installed intel-ucode
						
						;;
	esac
}

## -------- Remove Packages/Installer ------------

# Remove unnecessary packages
_remove_unwanted_packages() {
    local _packages_to_remove=('calamares-config'
							   'calamares'
							   'archinstall'
							   'arch-install-scripts'
							   'ckbcomp'
							   'boost'
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
_clean_target_system() {
    local dfile
	echo "+---------------------->>"
	echo "[*] Deleting live ISO files..."
    for dfile in "${files_to_remove[@]}"; do 
		rm -rf "${dfile}"
	done
    find /usr/lib/initcpio -name 'archiso*' -type f -exec rm '{}' \;
}

## -------- Perform Misc Operations --------------

_disable_autologin() {
	# disabling autologin for lightdm (if exist)
	lightdm_config='/etc/lightdm/lightdm.conf'
	if [[ -e "$lightdm_config" ]]; then
		echo "+---------------------->>"
		echo "[*] Disabling autologin for lightdm..."
		sed -i -e 's|autologin-user=.*|#autologin-user=username|g' "$lightdm_config"
		sed -i -e 's|autologin-session=.*|#autologin-session=xfce|g' "$lightdm_config"

		# Replacing lightdm cursor theme
		IND_THEME="/usr/share/icons/default/index.theme"
		echo "[Icon Theme]" > "$IND_THEME"
		echo "Inherits=Nordzy-cursors" >> "$IND_THEME"
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

_setup_snapper() {
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
	_set_config "/etc/snapper/configs/root" ALLOW_USERS "\"""${new_user}""\""
	_set_config "/etc/snapper/configs/root" TIMELINE_LIMIT_HOURLY 2
	_set_config "/etc/snapper/configs/root" TIMELINE_LIMIT_DAILY 5
	_set_config "/etc/snapper/configs/root" TIMELINE_LIMIT_WEEKLY 0
	_set_config "/etc/snapper/configs/root" TIMELINE_LIMIT_MONTHLY 0
	_set_config "/etc/snapper/configs/root" TIMELINE_LIMIT_YEARLY 0
}

_misc_actions() {
	# create ssh dir
	mkdir /etc/skel/.ssh
	chmod 700 /etc/skel/.ssh
	cp -r /etc/skel/.ssh /home/"$new_user"/.ssh
	chown "$new_user":"$new_user" /home/"$new_user"/.ssh
	# Copy /etc/skel to /root
	echo "+---------------------->>"
	echo "[*] Copying /etc/skel to /root"
	cp -aT /etc/skel /root
	
	echo "+---------------------->>"
	echo "[*] Using all cores when compressing packages with pacman..."
	_set_config "/etc/makepkg.conf" COMPRESSXZ "(xz -c -z - --threads=0)"
}

# ################################################################################################
# # Main script
# ################################################################################################
echo "+------------------------------------------------------->>"
echo "Configure snapper"
_setup_snapper

echo "+------------------------------------------------------->>"
echo "System services"
_manage_systemd_services

echo "+------------------------------------------------------->>"
echo "Remove VM drivers"
_remove_vbox_pkgs
_remove_vmware_pkgs
_remove_qemu_pkgs

echo "+------------------------------------------------------->>"
echo "Remove unwanted graphic drivers, ucode and packages"
_remove_unwanted_graphics_drivers
_remove_unwanted_ucode
_remove_unwanted_packages

echo "+------------------------------------------------------->>"
echo "Disable autologin"
_disable_autologin

echo "+------------------------------------------------------->>"
echo "Cleanup system"
_clean_target_system

echo "+------------------------------------------------------->>"
echo "Miscelaneous commands"
_misc_actions

echo "+------------------------------------------------------->>"
echo "Enable autostart of archon ansible"
# Enable autostart of archon ansible
archon_script=/usr/local/share/applications/archon.desktop
[[ -f "$archon_script" ]] && mv "$archon_script" /etc/xdg/autostart/archon.desktop

## End
exit 0