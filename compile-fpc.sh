#!/bin/bash
rm -f bin/ti99 bin/emul99 bin/ucsddskman

if [[ "$(uname)" == "Darwin" ]]; then
BREW_BASE=/usr/local/opt
LIB_PATH="-Fl${BREW_BASE}/sdl2/lib -Fl${BREW_BASE}/glib/lib -Fl${BREW_BASE}/cairo/lib -Fl${BREW_BASE}/gtk+3/lib"
fi

echo $LIB_PATH
fpc -B -O2 -FEbin -Mdelphi -Fusrc/fpcunits ${LIB_PATH} src/ti99.pas -k-lgtk-3 -k-lcairo -k-lglib-2.0 -k-lgobject-2.0 -k-lSDL2 -obin/emul99
fpc -B -O2 -FEbin -Mdelphi -Fusrc/fpcunits src/ucsddskman.pas -k-lc
rm bin/*.o bin/*.ppu

AS99="xas99.py -R -b"
$AS99 src/dummyrom.a99 -o roms/dummyrom.bin
$AS99 src/disksim.a99 -o roms/disksim.bin
$AS99 src/pcodedisk.a99 -o roms/pcodedisk.bin
