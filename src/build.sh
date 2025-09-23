#!/bin/bash
EXT=
if [ "$#" -eq 1 ]; then
    EXT=_$1
fi

echo "Convert misc/atarist.xml to misc/atarist_xml.hex"
cat misc/atarist.xml | gzip | xxd -p -c1 | unix2dos > misc/atarist_xml.hex


# run through grc to highlight NOTEs, WARNings and ERRORs
grc --config=gw_sh.grc gw_sh ./build${EXT}.tcl
