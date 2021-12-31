#!/usr/bin/env bash
DIR="$(pwd)"
PKGDIR="../packages"
RRDIR='../../archon-repo/x86_64'
if [[ ! -d "$PKGDIR" ]]; then
    mkdir -p "$PKGDIR"
fi
echo -e "Building Package..."
updpkgsums && makepkg -s && mv ./*.pkg.tar.zst "$PKGDIR"

rm -rf src pkg

cd "$DIR" || exit 1

if [[ -d "$RRDIR" ]]; then
    mv -f "$PKGDIR"/*.pkg.tar.zst "$RRDIR" && rm -r "$PKGDIR"
    echo -e "Package moved to Repository.\n[!] Don't forget to update the database.\n"
fi