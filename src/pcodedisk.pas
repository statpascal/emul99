unit pcodedisk;

interface

uses types;

procedure pcodeDiskSubSectorIO;
function readPcodeDisk (addr: uint16): uint16;

procedure initPcodeDisk (dsrFilename: string);
procedure pcodeDiskSetDiskImage (diskDrive: TDiskDrive; filename: string);

    
implementation

uses vdp, memory, memmap, cfuncs, tools;

const 
    MaxSectors = 65536;
    SectorSize = 256;
    E_NoError = 0;
    E_DeviceError = 6;
    
type
    TDisk = array [0..MaxSectors - 1, 0..SectorSize - 1] of uint8;

var
    dsrRom: TDsrRom;
    diskBuffers: array [TDiskDrive] of ^TDisk;
    diskSectors: array [TDiskDrive] of 0..MaxSectors;

procedure pcodeDiskSubSectorIO;
    type
        TSectorIOCmd = record
            sectorNumberOut: uint16;
            drive: uint8;
            rw: uint8;
            bufptr: uint16;
            case boolean of
                false: (sectorNumberIn: uint16);
                true:  (errorCode: uint8)
        end;
        TSectorIOCmdPtr = ^TSectorIOCmd;
    var
        cmd: TSectorIOCmdPtr;
        sectorNumber: uint16;
    begin
        cmd := TSectorIOCmdPtr (getMemoryPtr ($834a));
        sectorNumber := ntohs (cmd^.sectorNumberIn);
        if (cmd^.drive in [1..NumberDrives]) and (sectorNumber < diskSectors [cmd^.drive]) then
            begin
                if (cmd^.rw <> 0) then
                    vdpWriteBlock (ntohs (cmd^.bufptr), SectorSize, diskBuffers [cmd^.drive]^[sectorNumber])
                else
                    vdpReadBlock (ntohs (cmd^.bufptr), SectorSize, diskBuffers [cmd^.drive]^[sectorNumber]);
                cmd^.sectorNumberOut := cmd^.sectorNumberin;
                cmd^.errorCode := E_NoError
            end
        else
            cmd^.errorCode := E_DeviceError
    end;    

function readPcodeDisk (addr: uint16): uint16;
    begin
        readPcodeDisk := ntohs (dsrRom.w [addr shr 1])
    end;

procedure pcodeDiskSetDiskImage (diskDrive: TDiskDrive; filename: string);
    begin
        diskBuffers [diskDrive] := createMapping (filename);
        diskSectors [diskDrive] := getMappingSize (diskBuffers [diskDrive]) div SectorSize
    end;

procedure initPcodeDisk (dsrFilename: string);
    begin
        loadBlock (dsrRom, sizeof (dsrRom), 0, dsrFilename);
        fillChar (diskSectors, sizeof (diskSectors), 0)
    end;
    
end.
