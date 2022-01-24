#!/usr/bin/env bash

# Start flavours
# Base16 Gruvbox dark, medium - gtk icons flattcolor color config
# Dawid Kurek (dawikur@gmail.com), morhetz (https://github.com/morhetz/gruvbox)
newglyph=#282828
newfront=#665c54
newback=#504945
# End flavours

# Glyph default color: 282828
# Front default color: 665c54
# Back default color: 504945
oldglyph=#282828
oldfront=#665c54
oldback=#504945

sed -i "s/#524954/$oldglyph/g" $1
sed -i "s/#9b8aa0/$oldfront/g" $1
sed -i "s/#716475/$oldback/g" $1
sed -i "s/$oldglyph;/$newglyph;/g" $1
sed -i "s/$oldfront;/$newfront;/g" $1
sed -i "s/$oldback;/$newback;/g" $1

sed -i "s/newglyph=.*/newglyph=$newglyph/g" replace_script.sh
sed -i "s/newfront=.*/newfront=$newfront/g" replace_script.sh
sed -i "s/newback=.*/newback=$newback/g" replace_script.sh
