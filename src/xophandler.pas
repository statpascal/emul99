unit xophandler;

interface

procedure handleXop (op: uint16);


implementation

uses disksim, pcodedisk, serial;

procedure handleXop (op: uint16);
    begin
        case op of
            $1000: pcodeDiskPowerup;
            $1001: pcodeDiskSubSectorIO;
            
            $1200: diskSimPowerUpRoutine;
            $1201: diskSimDSRRoutine;
            $1202: diskSimSubFilesBasic;
            $1203: diskSimSubSectorIO;
            $1204: diskSimSubFormatDisk;
            $1205: diskSimSubProtectFile;
            $1206: diskSimSubRenameFile;
            $1207: diskSimSubFileInput;
            $1208: diskSimSubFileOutput;
            $1209: diskSimSubNumberOfFiles;
            
            $1500: serialSimPowerup;
            $1501: serialSimDSR
            else
                writeln ('Unhandled XOP ',  op, ' in DSR - check if DSR ROMs match simulator version')
        end
    end;
    
end.
