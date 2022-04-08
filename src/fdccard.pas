unit fdccard;

interface

uses types;

procedure writeFdcCard (addr, val: uint16);
function readFdcCard (addr: uint16): uint16;

procedure writeFdcCardCru (addr: TCruR12Address; value: TCruBit);
function readFdcCardCru (addr: TCruR12Address): TCruBit;

procedure fdcInitCard (dsrFilename: string);
procedure fdcSetDiskImage (diskDrive: TDiskDrive; filename: string);

const 
    FdcCardCruAddress = $1100;


implementation

uses tools, memmap,  cfuncs;

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
    
    TActiveCommand = (CmdNone, CmdReadSector, CmdWriteSector, CmdReadId, CmdReadTrack, CmdWriteTrack);
    
    TRegisters = record
        track, sector, status, data: uint8
    end;
    
    TReadIdBuffer = record
        track, side, sector, sizecode: uint8;
        crc: uint16
    end;

var
    dsrRom: array [$4000..$5fff] of uint8;
    dsrRomW: array [$2000..$2fff] of uint16 absolute dsrRom;

    disks: array [TDiskDrive] of ^TDisk;
    diskReady: array [TDiskDrive] of boolean;
    diskDoubleSided: array [TDiskDrive] of boolean;
    readIdBuffer: TReadIdBuffer;

    regs: TRegisters;
    selectedSide: 0..1;
    activeTrack: 0..DiskTracks;
    stepDirection: -1..1;
    bytesLeft: uint16;
    
    idBlockBytesLeft, dataBlockBytesLeft: uint16;
    trackWriteIdData: array [0..4] of uint8;
    trackWriteSector: 0..DiskSectors - 1;
    
    readWritePtr: ^uint8;
    activeCommand: TActiveCommand;
    activeDisk: 0..NumberDrives;
    diskImageName: array [TDiskDrive] of string;

procedure writeByte (b: uint8; var counter: uint16);
    begin
         readWritePtr^ := b;
         inc (readWritePtr);
         dec (counter)
    end;
    
procedure terminateActiveCommand;
    begin
        regs.status := regs.status and not StatusBusy;
        if (activeCommand = CmdWriteSector) and (bytesLeft <> 0) then
            begin
                regs.status := regs.status or StatusLostData;
                while bytesLeft mod SectorSize <> 0 do
                    writeByte (0, bytesLeft)
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
    
procedure handleStep (cmd: uint8);
    begin
        moveActiveTrack (stepDirection);
        if cmd and $10 <> 0 then
            regs.track := activeTrack
    end;
    
procedure handleStepIn (cmd: uint8);
    begin 
        stepDirection := 1;
        handleStep (cmd);
    end;
    
procedure handleStepOut (cmd: uint8);
    begin
        stepDirection := -1;
        handleStep (cmd)
    end;
    
function findReadWritePosition (cmd: uint16): pointer;
    begin
        findReadWritePosition := nil;
(*
        writeln ('Active Disk: ', activeDisk);
        writeln ('Regs.sector = ', regs.Sector);
        writeln ('Regs.track = ', regs.track);
        writeln ('Active Track = ', activeTrack);
*)
        if (activeDisk <> 0) and (regs.sector < DiskSectors) and (activeTrack = regs.track) and (selectedSide <= ord (diskDoubleSided [activeDisk])) then
            begin
                findReadWritePosition := addr (disks [activeDisk]^[selectedSide][activeTrack][regs.sector]);
                if cmd and $10 <> 0 then
                    bytesLeft := SectorSize * (DiskSectors - regs.sector)
                else
                    bytesLeft := SectorSize;
                regs.status := (regs.status or StatusBusy) and not (StatusCrcError or StatusLostData)
            end
        else
            regs.status := regs.status or StatusRecordNotFound
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
        bytesLeft := sizeof (readIdBuffer);
        readWritePtr := addr (readIdBuffer);
        readIdBuffer.track := activeTrack;
        readIdBuffer.side := selectedSide * ord ((activeDisk <> 0) and diskDoubleSided [activeDisk]);
        readIdBuffer.sector := regs.sector;
(*        readIdBuffer.sector := (readIdBuffer.sector + 1) mod DiskSectors; *)
        readIdBuffer.sizecode := 1;
        readIdBuffer.crc := htons (crc16 (readIdBuffer, 4));
        regs.status := (regs.status or StatusBusy) and not (StatusCrcError or StatusLostData)
    end;
    
procedure handleForceInterrupt (cmd: uint8);
    begin
        regs.status := regs.status and not StatusBusy;
(*        writeln ('FDC: Force interrupt'); *)
    end;
    
procedure handleReadTrack (cmd: uint8);
    begin
        writeln ('FDC: Read Track not implemented')
    end;
    
procedure handleWriteTrack (cmd: uint8);
    begin
        if selectedSide <= ord (diskDoubleSided [activeDisk]) then
            begin
                readWritePtr := addr (disks [activeDisk]^[selectedSide][activeTrack][0]);
                bytesLeft := 3236;
                regs.status := (regs.status or StatusBusy) and not (StatusCrcError or StatusLostData);
                activeCommand := CmdWriteTrack
            end
        else
            begin
                readWritePtr := nil;
                regs.status := StatusRecordNotFound
            end;
(*        writeln ('FDC: Write Track S', selectedSide, ' T', activeTrack) *)
    end;
    
procedure handleCommand (cmd: uint8);
    begin
        terminateActiveCommand;
        if activeDisk <> 0 then
            if diskReady [activeDisk] then
                case cmd of
                    $00..$0f:
                        handleRestore (cmd);
                    $10..$1f:
                        handleSeek (cmd);
                    $20..$3f:
                        handleStep (cmd);
                    $40..$5f:
                        handleStepIn (cmd);
                    $60..$7f:
                        handleStepOut (cmd);
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
    const
        IdMark = $fe;
        DataMark = $fb;
    begin
        regs.data := val;
    
        if activeCommand = CmdWriteTrack then
            begin
                if val = $fe then 
                    idBlockBytesLeft := sizeof (trackWriteIdData)
                else if val = $fb then
                    begin
                        dataBlockBytesLeft := 256;
                        if (activeDisk <> 0) and (selectedSide <= ord (diskDoubleSided [activeDisk])) then
                            readWritePtr := addr (disks [activeDisk]^[selectedSide][activeTrack][trackWriteSector])
                        else
                            readWritePtr := nil;
                    end
                else if idBlockBytesLeft > 0 then 
                    begin
                        trackWriteIdData [sizeof (trackWriteIdData) - idBlockBytesLeft] := val;
                        dec (idBlockBytesLeft);
                        if idBlockBytesLeft = 0 then 
                            begin
                                if trackWriteIdData [2] < DiskSectors then
                                    trackWriteSector := trackWriteIdData [2];
                            end
                    end
                else if dataBlockBytesLeft > 0 then
                    begin
                        writeByte (val, dataBlockBytesLeft);
                    end;
                    
                dec (bytesLeft);
                if bytesLeft = 0 then 
                    terminateActiveCommand
            end
        else if activeCommand = CmdWriteSector then
            begin
                if (readWritePtr <> nil) and (bytesLeft > 0) then 
                    begin
                        writeByte (val, bytesLeft);
                        if bytesLeft = 0 then
                            regs.status := regs.status and not StatusBusy
                        else if bytesLeft mod SectorSize = 0 then
                            inc (regs.sector);
                    end
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
        if count mod 100 = 0 then
        getStatus := regs.status or StatusIndexPulse
        else
        getStatus := regs.status;
        inc (count);
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
            (* Error? *)
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
            readFdcCard := htons (dsrRomW [addr shr 1])
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
        res: TCruBit;
    begin
        bit := (addr and $ff) shr 1;
        case bit of
            1, 2, 3:
                res := ord (activeDisk = bit);
            6:
                res := 1;
            7:
                res := selectedSide
            else
                res := 0
        end;
        readFdcCardCru := res
    end;

procedure fdcInitCard (dsrFilename: string);
    begin
        load (dsrRom, sizeof (dsrRom), dsrFilename);
        activeCommand := CmdNone;
        activeDisk := 0;
        stepDirection := 1;
        handleRestore (0)
    end;
    
procedure fdcSetDiskImage (diskDrive: TDiskDrive; filename: string);
    begin
        diskImageName [diskDrive] := filename;
        diskReady [diskDrive] := filename <> '';
        if diskReady [diskDrive] then
            begin
                disks [diskDrive] := createMapping (filename);
                case getMappingSize (disks [diskDrive]) of
                    SingleSidedDisk:
                        diskDoubleSided [diskDrive] := false;
                    DoubleSidedDisk:
                        diskDoubleSided [diskDrive] := true
                    else
                        begin
                            writeln ('Illegal disk size (', getMappingSize (disks [diskDrive]), ' bytes) in file ', filename);
                            diskReady [diskDrive] := false
                        end
                end
            end
    end; 

var
    i: TDiskDrive;

begin
    for i := 1 to NumberDrives do
        diskImageName [i] := ''    
end.
