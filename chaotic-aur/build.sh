#!/usr/bin/env bash
# chaotic-aur
# https://github.com/archon-linux/archon-core
# @nekwebdev
# LICENSE: GPLv3
# original: Copyright (C) 2020-2021 Aditya Shakya <adi1090x@gmail.com>

cd "$(dirname "$0")" || exit 1
DIR="$(pwd)"
PKGDIR="$DIR/packages_caur"

## Script Termination
exit_on_signal_SIGINT () {
    { printf "\n\n%s\n" "Script interrupted." 2>&1; echo; }
    exit 0
}

exit_on_signal_SIGTERM () {
    { printf "\n\n%s\n" "Script terminated." 2>&1; echo; }
    exit 0
}

trap exit_on_signal_SIGINT SIGINT
trap exit_on_signal_SIGTERM SIGTERM

# Build packages
get_pkgs () {

	if [[ ! -d "$PKGDIR" ]]; then
		mkdir -p "$PKGDIR"
	fi

	echo -e "\nFetching Packages - \n"
	cd "$PKGDIR" && wget 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
	
	RRDIR='../../../archon-repo/x86_64'
	if [[ -d "$RRDIR" ]]; then
		mv -f ./*.pkg.tar.zst "$RRDIR" && rm -r "$PKGDIR"
		echo -e "\nPackage moved to Repository.\n[!] Don't forget to update the database.\n"
	fi
}

# Execute
get_pkgs