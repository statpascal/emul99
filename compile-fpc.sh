rm -f bin/ti99 bin/emul99 bin/ucsddskman
fpc -B -O2 -FEbin -Mdelphi -Fusrc/fpcunits src/ti99.pas -obin/emul99 -k-lgtk-3 -k-lcairo -k-lglib-2.0 -k-lgobject-2.0 -k-lSDL2
fpc -B -O2 -FEbin -Mdelphi -Fusrc/fpcunits src/ucsddskman.pas -k-lc
rm bin/*.o bin/*.ppu

AS99="xas99.py -R -b"
$AS99 src/dummyrom.a99 -o roms/dummyrom.bin
$AS99 src/disksim.a99 -o roms/disksim.bin
$AS99 src/pcodedisk.a99 -o roms/pcodedisk.bin
