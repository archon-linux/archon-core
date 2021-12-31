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
## Post installation script for Archon Linux (Executes on live system, only to detect drivers in use)
## It will run the following tasks:
##   - Detect the graphics drivers used during the live session
##   - Bind resolv.conf so chroot has network connectivity if needed
##   - Start the next script, /usr/local/bin/chrooted_post_install.sh in the chrooted environment
##################################################################################################

# ################################################################################################
# # Variables
# ################################################################################################

# Setup file logging for debug purposes
debug=true

calamares=$(pidof calamares)
## Get mount points of target system according to installer being used (calamares)
if [[ $calamares ]]; then
	chroot_path="/tmp/$(lsblk | grep 'calamares-root' | awk '{ print $NF }' | sed -e 's/\/tmp\///' -e 's/\/.*$//' | tail -n1)"
else
	chroot_path='/mnt'
fi

if [[ "$chroot_path" == '/tmp/' ]] ; then
	echo "+---------------------->>"
    echo "[!] Fatal error: $(basename "$0"): chroot_path is empty!"
fi

# Bind console output to a file
if $debug
then
	log_file=${chroot_path}/var/log/post_install.log
	# Close standard output file descriptor
	exec 1<&-
	# Close standard error file descriptor
	exec 2<&-
	# Open standard output as $log_file file for read and write.
	exec 1<>$log_file
	# Redirect standard error to standard output
	exec 2>&1
fi

## Use chroot not arch-chroot
_arch_chroot() {
    chroot "$chroot_path" /bin/bash -c ${1}
}

## Detect drivers in use in live session
gpu_file="$chroot_path"/var/log/gpu-card-info.bash

_detect_vga_drivers() {
    local card=no
    local driver=no

    if [[ -n "$(lspci -k | grep -P 'VGA|3D|Display' | grep -w "${2}")" ]]; then
        card=yes
        if [[ -n "$(lsmod | grep -w ${3})" ]]; then
			driver=yes
		fi
        if [[ -n "$(lspci -k | grep -wA2 "${2}" | grep "Kernel driver in use: ${3}")" ]]; then
			driver=yes
		fi
    fi
    echo "${1}_card=$card"     >> ${gpu_file}
    echo "${1}_driver=$driver" >> ${gpu_file}
}

# ################################################################################################
# # Main script
# ################################################################################################
echo "+---------------------->>"
echo "[*] Detecting GPU card & drivers used in live session..."

# Detect AMD
_detect_vga_drivers 'amd' 'AMD' 'amdgpu'

# Detect Intel
_detect_vga_drivers 'intel' 'Intel Corporation' 'i915'

# Detect Nvidia
_detect_vga_drivers 'nvidia' 'NVIDIA' 'nvidia'

# For logs
echo "+---------------------->>"
echo "[*] Content of $gpu_file :"
cat ${gpu_file}

##--------------------------------------------------------------------------------

## Run the final script inside calamares chroot (target system)
if [[ $calamares ]]; then
    echo "+---------------------->>"
    echo "[*] Create needed directories"
    mkdir -p "$chroot_path"/run/systemd/resolve
    echo "[*] Copy stub-resolv.conf"
    cp -f /run/systemd/resolve/stub-resolv.conf "$chroot_path"/run/systemd/resolve/stub-resolv.conf
    echo "Check skel"
    ls -la /etc/skel
	echo "+---------------------->>"
	echo "[*] Running chroot post installation script in target system..."
	_arch_chroot "/usr/bin/chrooted_post_install.sh"
fi
exit 0
