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
# (Executes on live system, only to detect drivers in use)
# It will run the following tasks:
#   - Detect the graphics drivers used during the live session
#   - Bind resolv.conf so chroot has network connectivity if needed
#   - Start the next script, chrooted_post_install.sh in the chrooted environment

###### => variables ############################################################
# Setup file logging for debug purposes
debug=true

calamares=$(pidof calamares)
# Get mount points of target system according to installer being used (calamares)
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

###### => functions ############################################################
# Use chroot not arch-chroot
function arch_chroot() {
    chroot "$chroot_path" /bin/bash -c ${1}
}

# Detect drivers in use in live session
gpu_file="$chroot_path"/var/log/gpu-card-info.bash

function detect_vga_drivers() {
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

###### => main #################################################################

echo "+---------------------->>"
echo "[*] Detecting GPU card & drivers used in live session..."

# Detect AMD
detect_vga_drivers 'amd' 'AMD' 'amdgpu'

# Detect Intel
detect_vga_drivers 'intel' 'Intel Corporation' 'i915'

# Detect Nvidia
detect_vga_drivers 'nvidia' 'NVIDIA' 'nvidia'

# For logs
echo "+---------------------->>"
echo "[*] Content of $gpu_file :"
cat ${gpu_file}

# Run the final script inside calamares chroot (target system)
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
	arch_chroot "/usr/bin/chrooted_post_install.sh"
fi
exit 0
