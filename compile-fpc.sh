rm -f bin/ti99 bin/ucsddskman
fpc -B -O2 -FEbin -Mdelphi -Fusrc/fpcunits src/ti99.pas -k-lgtk-3 -k-lcairo -k-lglib-2.0
fpc -B -O2 -FEbin -Mdelphi -Fusrc/fpcunits src/ucsddskman.pas -k-lc
rm bin/*.o bin/*.ppu
