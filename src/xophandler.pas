unit xophandler;

interface

procedure handleXop (op: uint16);


implementation

uses disksim, pcodedisk, serial;

const
    LastXop = 12;
    
procedure handleXop (op: uint16);
    const XopHandlerProc: array [0..LastXop] of procedure =
        (diskSimPowerUpRoutine, diskSimDSRRoutine, diskSimSubFilesBasic, diskSimSubSectorIO, diskSimSubFormatDisk, diskSimSubProtectFile,
         diskSimSubRenameFile, diskSimSubFileInput, diskSimSubFileOutput, diskSimSubNumberOfFiles, pcodeDiskSubSectorIO, 
         serialSimPowerup, serialSimDSR);
    begin
        if op <= LastXop then
            XopHandlerProc [op]
        else
            writeln ('XOP handler: unknown op ', op)
    end;
    
end.
