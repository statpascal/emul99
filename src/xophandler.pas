unit xophandler;

interface

uses types;

procedure handleXop (op: uint16; var cpu: TTMS9900);


implementation

uses disksim, pcodedisk, serial;

const
    DiskSimPowerUp = 0;
    DiskSimDSR = 1;
    DiskSimSubFiles = 2;
    DiskSimSub10 = 3;
    DiskSimSub11 = 4;
    DiskSimSub12 = 5;
    DiskSimSub13 = 6;
    DiskSimSub14 = 7;
    DiskSimSub15 = 8;
    DiskSimSub16 = 9;
    PCodeDiskSub10 = 10;
    SerialPowerUp = 11;
    SerialDSR = 12;
    
procedure handleXop (op: uint16; var cpu: TTMS9900);
    begin
        case op of
            DiskSimPowerUp:
                diskSimPowerUpRoutine;
            DiskSimDSR:
                diskSimDSRRoutine;
            DiskSimSubFiles:
                diskSimSubFilesBasic;
            DiskSimSub10:
               diskSimSubSectorIO;
            DiskSimSub11:
               diskSimSubFormatDisk;
            DiskSimSub12:
               diskSimSubProtectFile;
            DiskSimSub13:
               diskSimSubRenameFile;
            DiskSimSub14:
               diskSimSubFileInput;
            DiskSimSub15:
               diskSimSubFileOutput;
            DiskSimSub16:
               diskSimSubNumberOfFiles;
            PCodeDiskSub10:
               pcodeDiskSubSectorIO;
            SerialPowerUp:
                serialSimPowerup;
            SerialDSR:
                serialSimDSR;
            else
                writeln ('XOP handler: unknown op ', op)
        end
    end;
    
end.
