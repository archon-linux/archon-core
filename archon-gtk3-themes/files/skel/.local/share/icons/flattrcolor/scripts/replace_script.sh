#!/usr/bin/env bash

if [ -n "${XDG_DATA_HOME}" ]; then
  LOCAL="${XDG_DATA_HOME}"
else
  LOCAL="${HOME}/.local/share"
fi

function replaceall {
	cd "$LOCAL/icons/flattrcolor/scripts" || exit 0
	sh ./change_all_folders.sh
}

replaceall

# set old to new
cd "$LOCAL/icons/flattrcolor/scripts" || exit 0

# Start flavours
# Base16 Gruvbox dark, medium - gtk icons flattcolor color config
# Dawid Kurek (dawikur@gmail.com), morhetz (https://github.com/morhetz/gruvbox)
newglyph=#282828
newfront=#665c54
newback=#504945
# End flavours

# Glyph default color: 282828
#	Front default color: 665c54
#	Back default color: 504945
oldglyph=#282828
oldfront=#665c54
oldback=#504945

sed -i "s/$oldglyph/$newglyph/g" replace_folder_file.sh
sed -i "s/$oldfront/$newfront/g" replace_folder_file.sh
sed -i "s/$oldback/$newback/g" replace_folder_file.sh

sed -i "s/$oldglyph/$newglyph/g" "$0"
sed -i "s/$oldfront/$newfront/g" "$0"
sed -i "s/$oldback/$newback/g" "$0"
