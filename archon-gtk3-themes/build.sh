#!/usr/bin/env bash
# archon-gtk3-themes
# https://github.com/archon-linux/archon-core
# @nekwebdev
# LICENSE: GPLv3

cd "$(dirname "$0")" || exit 1
DIR="$(pwd)"
PKGDIR="../packages"
RRDIR='../../archon-repo/x86_64'
if [[ ! -d "$PKGDIR" ]]; then
    mkdir -p "$PKGDIR"
fi
echo -e "Building Package..."
makepkg -s && mv ./*.pkg.tar.zst "$PKGDIR"

rm -rf src pkg

cd "$DIR" || exit 1

if [[ -d "$RRDIR" ]]; then
    mv -f "$PKGDIR"/*.pkg.tar.zst "$RRDIR" && rm -r "$PKGDIR"
    echo -e "Package moved to Repository.\n[!] Don't forget to update the database.\n"
fi