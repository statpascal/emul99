rm -f bin/ti99 bin/ucsddskman
fpc -B -O2 -FEbin -Mdelphi -Fusrc/fpcunits src/ti99.pas -k-lgtk-3 -k-lcairo -k-lglib-2.0
fpc -B -O2 -FEbin -Mdelphi -Fusrc/fpcunits src/ucsddskman.pas -k-lc
rm bin/*.o bin/*.ppu

AS99="xas99.py -R -b"
$AS99 src/dummyrom.a99 -o roms/dummyrom.bin
$AS99 src/disksim.a99 -o roms/disksim.bin
$AS99 src/pcodedisk.a99 -o roms/pcodedisk.bin
$AS99 src/serial.a99 -o roms/serial.bin
