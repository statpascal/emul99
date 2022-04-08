unit pcodedisk;

interface

uses types;

procedure pcodeDiskSubSectorIO;
function readPcodeDisk (addr: uint16): uint16;

procedure initPcodeDisk (dsrFilename: string);
procedure pcodeDiskSetDiskImage (diskDrive: TDiskDrive; filename: string);

const
    PcodeDiskCruAddress = $1300;

    
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
    dsrRom: array [$4000..$5fff] of uint8;
    dsrRomW: array [$2000..$2fff] of uint16 absolute dsrRom;
    
    diskBuffers: array [TDiskDrive] of ^TDisk;
    diskSectors: array [TDiskDrive] of 0..MaxSectors;

procedure pcodeDiskSubSectorIO;
    type
        TSectorIOCmd = record
            sectorNumberOut: uint16;
            drive: uint8;
            rw: uint8;
            bufptr: uint16;
            sectorNumberIn: uint16
        end;
        TSectorIOCmdPtr = ^TSectorIOCmd;
    var
        cmd: ^TSectorIOCmd;
        sectorNumber: uint16;
    begin
        cmd := TSectorIOCmdPtr (getMemoryPtr ($834a));
        sectorNumber := ntohs (cmd^.sectorNumberIn);
        if (cmd^.drive in [1..NumberDrives]) and (sectorNumber < diskSectors [cmd^.drive]) then
            begin
                if (cmd^.rw <> 0) then
                    move (diskBuffers [cmd^.drive]^[ntohs (cmd^.sectorNumberIn)], getVdpRamPtr (ntohs (cmd^.bufptr))^, SectorSize)
                else
                    move (getVdpRamPtr (ntohs (cmd^.bufptr))^, diskBuffers [cmd^.drive]^[ntohs (cmd^.sectorNumberIn)], SectorSize);
                cmd^.sectorNumberOut := cmd^.sectorNumberin;
                cmd^.sectorNumberIn := E_NoError
            end
        else
            cmd^.sectorNumberIn := E_DeviceError
    end;    

function readPcodeDisk (addr: uint16): uint16;
    begin
        readPcodeDisk := htons (dsrRomW [addr shr 1])
    end;

procedure pcodeDiskSetDiskImage (diskDrive: TDiskDrive; filename: string);
    begin
        diskBuffers [diskDrive] := createMapping (filename);
        diskSectors [diskDrive] := getMappingSize (diskBuffers [diskDrive]) div SectorSize
    end;

procedure initPcodeDisk (dsrFilename: string);
    var 
        i: TDiskDrive;
    begin
        load (dsrRom, sizeof (dsrRom), dsrFilename);
        for i := 1 to NumberDrives do
            diskSectors [i] := 0;
    end;
    
end.
