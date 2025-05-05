unit fdccard;

interface

uses types;

procedure writeFdcCard (addr, val: uint16);
function readFdcCard (addr: uint16): uint16;

procedure writeFdcCardCru (addr: TCruR12Address; value: TCruBit);
function readFdcCardCru (addr: TCruR12Address): TCruBit;

procedure fdcInitCard (dsrFilename: string);
procedure fdcSetDiskImage (diskDrive: TDiskDrive; filename: string);


implementation
(*$POINTERMATH ON*)
uses tools, memmap, cfuncs, math;

const
    SectorSize = 256;
    DiskSectors = 9;
    DiskTracks = 40;
    SingleSidedDisk = DiskTracks * DiskSectors * SectorSize;
    DoubleSidedDisk = 2 * SingleSidedDisk;
    
    MemStatusRead  = $5ff0;
    MemTrackRead   = $5ff2;
    MemSectorRead  = $5ff4;
    MemDataRead    = $5ff6;
    MemCmdWrite    = $5ff8;
    MemTrackWrite  = $5ffa;
    MemSectorWrite = $5ffc;
    MemDataWrite   = $5ffe;
    
    StatusNotReady 	 = $80;
    StatusWriteProtect   = $40;
    StatusHeadLoaded 	 = $20;
    StatusSeekError 	 = $10;
    StatusRecordNotFound = StatusSeekError;
    StatusCrcError 	 = $08;
    StatusTrack0 	 = $04;
    StatusLostData 	 = StatusTrack0;
    StatusIndexPulse 	 = $02;
    StatusBusy 		 = $01;

type
    TSector = array [0..SectorSize - 1] of uint8;
    TTrack = array [0..DiskSectors - 1] of TSector;
    TDisk = array [0..1, 0..DiskTracks - 1] of TTrack;	(* two sides, single density *)
    TStepDirection = -1..1;
    TActiveCommand = (CmdNone, CmdReadSector, CmdWriteSector, CmdReadId, CmdReadTrack, CmdWriteTrack);
    
    TRegisters = record
        track, sector, status, data: uint8
    end;
    TSectorIdData = record
        track, side, sector, sizecode: uint8;
        crc: uint16
    end;

var
    dsrRom: TDsrRom;
    disks: array [TDiskDrive] of ^TDisk;
    diskDoubleSided: array [TDiskDrive] of boolean;
    sectorIdData: TSectorIdData;

    regs: TRegisters;
    selectedSide: 0..1;
    activeTrack: 0..DiskTracks;
    stepDirection: TStepDirection;
    bytesLeft, trackBytesLeft: uint16;
    trackWriteSector: 0..DiskSectors - 1;
    
    readWritePtr: TUint8Ptr;
    activeCommand: TActiveCommand;
    activeDisk: 0..NumberDrives;

procedure writeByte (var p: TUint8Ptr; b: uint8; var counter: uint16);
    begin
        if p <> nil then
            begin
                p^ := b;
                inc (p)
            end;
        dec (counter)
    end;
    
procedure terminateActiveCommand;
    begin
        regs.status := regs.status and not StatusBusy;
        if (activeCommand = CmdWriteSector) and (bytesLeft <> 0) then
            begin
                regs.status := regs.status or StatusLostData;
                while bytesLeft mod SectorSize <> 0 do
                    writeByte (readWritePtr, 0, bytesLeft)
            end;
        activeCommand := CmdNone
    end;
    
procedure handleRestore (cmd: uint8);
    begin 
        activeTrack := 0;
        regs.track := 0;
        regs.sector := 0;
        regs.status := StatusTrack0;
    end;
    
procedure moveActiveTrack (delta: int16);
    begin
        if activeTrack + delta < 0 then
            activeTrack := 0
        else if activeTrack + delta >= DiskTracks then
            activeTrack := DiskTracks - 1
        else
            inc (activeTrack, delta);
        regs.status := StatusTrack0 * ord (activeTrack = 0)
    end;
    
procedure handleSeek (cmd: uint8);
    begin
        moveActiveTrack (regs.data - regs.track);
        regs.track := regs.data;
    end;
    
procedure handleStep (cmd: uint8; direction: TStepDirection);
    begin
        stepDirection := direction;
        moveActiveTrack (stepDirection);
        if cmd and $10 <> 0 then
            regs.track := activeTrack
    end;
    
function getDiskPointer (disk, side, track, sector: uint8): TUint8Ptr;
    begin
        if (disk in [1..NumberDrives]) and (disks [disk] <> nil) and (side <= ord (diskDoubleSided [disk])) and (track < DiskTracks) and (sector < DiskSectors) then
            getDiskPointer := addr (disks [disk]^[side, ifthen (side = 0, track, DiskTracks - track - 1), sector])
        else
            getDiskPointer := nil
    end;
    
function findReadWritePosition (cmd: uint16): TUint8Ptr;
    var
        res: TUint8Ptr;
    begin
        writeln ('Disk:     ', activeDisk);
        writeln ('Side:     ', selectedSide);
        writeln ('Track:    ', activeTrack);
        writeln ('Sector:   ', regs.sector);
        if activeTrack = regs.track then
            res := getDiskPointer (activeDisk, selectedSide, activeTrack, regs.sector)
        else
            res := nil;
        writeln ('Offset:   ', system.hexStr (int64 (res) - int64 (disks [activeDisk]), 8));
        writeln;
        if res <> nil then
            begin
                bytesLeft := SectorSize * ifthen (cmd and $10 <> 0, DiskSectors - regs.sector, 1);
                regs.status := (regs.status or StatusBusy) and not (StatusCrcError or StatusLostData)
            end
        else
            regs.status := regs.status or StatusRecordNotFound;
        findReadWritePosition := res
    end;
            
    
procedure handleReadSector (cmd: uint8);
    begin
        readWritePtr := findReadWritePosition (cmd);
        if readWritePtr <> nil then
            activeCommand := CmdReadSector;
    end;
    
procedure handleWriteSector (cmd: uint8);
    begin
        readWritePtr := findReadWritePosition (cmd);
        if readWritePtr <> nil then
            activeCommand := CmdWriteSector;
    end;
    
procedure handleReadId (cmd: uint8);
    begin
        bytesLeft := sizeof (sectorIdData);
        readWritePtr := addr (sectorIdData);
        sectorIdData.track := activeTrack;
        sectorIdData.side := selectedSide * ord ((activeDisk <> 0) and diskDoubleSided [activeDisk]);
        sectorIdData.sector := regs.sector;
        sectorIdData.sizecode := 1;
        sectorIdData.crc := htons (crc16 (sectorIdData, 4));
        regs.status := (regs.status or StatusBusy) and not (StatusCrcError or StatusLostData)
    end;
    
procedure handleForceInterrupt (cmd: uint8);
    begin
        regs.status := regs.status and not StatusBusy
    end;
    
procedure handleReadTrack (cmd: uint8);
    begin
        writeln ('FDC: Read Track not implemented')
    end;
    
procedure handleWriteTrack (cmd: uint8);
    begin
        if getDiskPointer (activeDisk, selectedSide, activeTrack, 0) <> nil then
            begin
                bytesLeft := 3236;	// track length written by disk manager
                regs.status := (regs.status or StatusBusy) and not (StatusCrcError or StatusLostData);
                activeCommand := CmdWriteTrack
            end
        else
            regs.status := StatusRecordNotFound
    end;
    
procedure handleCommand (cmd: uint8);
    begin
        terminateActiveCommand;
        writeln ('FDC cmd:  ', hexstr2 (cmd));
        if activeDisk <> 0 then
            if disks [activeDisk] <> nil then
                case cmd of
                    $00..$0f:
                        handleRestore (cmd);
                    $10..$1f:
                        handleSeek (cmd);
                    $20..$3f:
                        handleStep (cmd, stepDirection);
                    $40..$5f:
                        handleStep (cmd, 1);
                    $60..$7f:
                        handleStep (cmd, -1);
                    $80..$9f:
                        handleReadSector (cmd);
                    $a0..$bf:
                        handleWriteSector (cmd);
                    $c0..$cf:
                        handleReadId (cmd);
                    $d0..$df:
                        handleForceInterrupt (cmd);
                    $e0..$ef:
                        handleReadTrack (cmd);
                    $f0..$ff:
                        handleWriteTrack (cmd)
                end
            else
                regs.status := regs.status or StatusNotReady
    end;
    
procedure handleDataWrite (val: uint8);
    begin
        regs.data := val;
        if activeCommand = CmdWriteTrack then
            begin
                if val = $fe then 
                    begin
                        trackBytesLeft := 4;
                        readWritePtr := addr (sectorIdData)
                    end
                else if val = $fb then
                    begin
                        trackBytesLeft := 256;
                        readWritePtr := getDiskPointer (activeDisk, selectedSide, activeTrack, trackWriteSector)
                    end
                else if trackBytesLeft > 0 then 
                    begin
                        writeByte (readWritePtr, val, trackBytesLeft);
                        if (trackBytesLeft = 0) and (readWritePtr = TUint8Ptr (addr (sectorIdData)) + 4) then
                            trackWriteSector := sectorIdData.sector;
                    end;
                dec (bytesLeft);
                if bytesLeft = 0 then 
                    terminateActiveCommand
            end
        else if (activeCommand = CmdWriteSector) and (readWritePtr <> nil) and (bytesLeft > 0) then 
            begin
                writeByte (readWritePtr, val, bytesLeft);
                if bytesLeft = 0 then
                    regs.status := regs.status and not StatusBusy
                else if bytesLeft mod SectorSize = 0 then
                    inc (regs.sector);
            end
    end;

procedure writeFdcCard (addr, val: uint16);
    begin
        val := (val shr 8) xor $ff;
        case addr of
            MemCmdWrite:
                handleCommand (val);
            MemTrackWrite:
                regs.track := val;
            MemSectorWrite:
                regs.sector := val;
            MemDataWrite:
                handleDataWrite (val)
        end
    end;
    
function getStatus: uint8;
    const
        count: int64 = 0;
    begin 
        getStatus := regs.status or StatusIndexPulse * ord (count mod 64 = 0);
        inc (count)
    end;
        
function handleDataRead: uint8;
    begin
        if (readWritePtr <> nil) and (bytesLeft > 0) then 
            begin
                handleDataRead := readWritePtr^;
                inc (readWritePtr);
                dec (bytesLeft);
                if bytesLeft = 0 then
                    regs.status := regs.status and not StatusBusy
                else if bytesLeft mod SectorSize = 0 then
                    inc (regs.sector)
            end
        else
            handleDataRead := 0
    end;
        
function readFdcCard (addr: uint16): uint16;
    var
        res: uint8;
    begin
        if addr >= MemStatusRead then
            begin
                case addr of
                    MemStatusRead:
                        res := getStatus;
                    MemTrackRead:
                        res := regs.track;
                    MemSectorRead:
                        res := regs.sector;
                    MemDataRead:
                        res := handleDataRead
                    else
                        res := $ff
                end;
                readFdcCard := (res xor $ff) shl 8
            end
        else
            readFdcCard := ntohs (dsrRom.w [addr shr 1])
    end;

procedure writeFdcCardCru (addr: TCruR12Address; value: TCruBit);
    var
        bit: int8;
    begin
        bit := (addr and $ff) shr 1;
        case bit of
            4..6:
                if value = 1 then
                    activeDisk := bit - 3
                else if bit - 3 = activeDisk then
                    activeDisk := 0; 
            7:
                selectedSide := value
        end
    end;
    
function readFdcCardCru (addr: TCruR12Address): TCruBit;
    var
        bit: 0..$7f;
    begin
        bit := (addr and $ff) shr 1;
        case bit of
            1, 2, 3:
                readFdcCardCru := ord (activeDisk = bit);
            6:
                readFdcCardCru := 1;
            7:
                readFdcCardCru := selectedSide
            else
                readFdcCardCru := 0
        end
    end;

procedure fdcInitCard (dsrFilename: string);
    begin
        loadBlock (dsrRom, sizeof (dsrRom), 0, dsrFilename, true);
        activeCommand := CmdNone;
        activeDisk := 0;
        stepDirection := 1;
        handleRestore (0)
    end;
    
procedure fdcSetDiskImage (diskDrive: TDiskDrive; filename: string);
    begin
        disks [diskDrive] := createMapping (filename);
        if disks [diskDrive] <> nil then
            case getMappingSize (disks [diskDrive]) of
                SingleSidedDisk:
                    diskDoubleSided [diskDrive] := false;
                DoubleSidedDisk:
                    diskDoubleSided [diskDrive] := true
                else
                    errorExit ('Disk size in ' + filename + ' is not supported (only 90/180 KBytes images)')
            end
        else
            errorExit ('Cannot open disk image ' + filename)
    end; 

begin
    fillChar (disks, sizeof (disks), 0)
end.
