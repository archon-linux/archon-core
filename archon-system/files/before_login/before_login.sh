#!/usr/bin/env bash
# archon-system
# https://github.com/archon-linux/archon-core
# @nekwebdev
# LICENSE: GPLv3

# shellcheck source=/dev/null
# exit if any command errors & if a variable is unknown
set -e -u

# copying the new pacman.conf and pamac.conf
mv -f /etc/pacman.conf.archon /etc/pacman.conf
mv -f /etc/pamac.conf.archon /etc/pamac.conf

# copying the new lightdm.conf
mv -f /etc/lightdm/lightdm.conf.archon /etc/lightdm/lightdm.conf

# set default cursor theme to Nordzy-cursors and copy that default to user's .icons
sed -i -e 's/Inherits=.*/Inherits=Nordzy-cursors/g' /usr/share/icons/default/index.theme

# create custom xdg-user-dirs
# need a dummy home as $HOME is not set yet and the source would fail.
HOME="/my/dummy"
source /etc/skel/.config/user-dirs.dirs
xdg_folders=("$XDG_DESKTOP_DIR" "$XDG_DOCUMENTS_DIR" "$XDG_DOWNLOAD_DIR" "$XDG_MUSIC_DIR" "$XDG_PICTURES_DIR" "$XDG_PUBLICSHARE_DIR" "$XDG_TEMPLATES_DIR" "$XDG_VIDEOS_DIR")
for xdg_folder in "${xdg_folders[@]}"; do
    mkdir -p "/home/liveuser/$( echo "$xdg_folder" | cut -d'/' -f4- )"
    chown liveuser:liveuser "/home/liveuser/$( echo "$xdg_folder" | cut -d'/' -f4- )"
done
# create liveuser .ssh
mkdir /home/liveuser/.ssh
chmod 700 /home/liveuser/.ssh
chown liveuser:liveuser /home/liveuser/.ssh

# fix liveuser bashrc
# mv -f /home/liveuser/.bashrc.archon /home/liveuser/.bashrc

# create liveuser log folder
mkdir -p /home/liveuser/.local/log
chown liveuser:liveuser /home/liveuser/.local/log

# set dash as symlink to /bin/sh
ln -sfT dash /usr/bin/sh

# fix missing theme xsettings entry
theme=$( gsettings get org.gnome.desktop.interface gtk-theme | sed "s/'//g" )
[[ -z "$theme" ]] && gsettings set org.gnome.desktop.interface gtk-theme 'FlatColor'

# fix gsettings defaults
gsettings set org.cinnamon.desktop.default-applications.terminal exec alacritty
gsettings set org.gnome.desktop.default-applications.terminal exec alacritty

exit 0
