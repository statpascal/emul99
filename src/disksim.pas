unit disksim;

interface

function readDiskSim (addr: uint16): uint16;

procedure initDiskSim (dsrFilename, directory: string);

procedure diskSimPowerUpRoutine;
procedure diskSimDsrRoutine;

(* CALL FILES *)
procedure diskSimSubFilesBasic;

(* Sub programs >10 to >16 *)
procedure diskSimSubSectorIO;
procedure diskSimSubFormatDisk;
procedure diskSimSubProtectFile;
procedure diskSimSubRenameFile;
procedure diskSimSubFileInput;
procedure diskSimSubFileOutput;
procedure diskSimSubNumberOfFiles;

const 
    DiskSimCruAddress = $1200;

implementation

uses memory, vdp, tools, cfuncs, math, sysutils;

const
    SectorSize = 256;
    MaxSectors = 4 * 360;       (* DS/DD floppy *)
    MaxFiles = 16;
    EofMarker = $ff;

type 
    TOperation = (E_Open, E_Close, E_Read, E_Write, E_Rewind, E_Load, E_Save, E_Delete, E_Scratch, E_Status);
    TRecordType = (E_Fixed, E_Variable);
    TDataType = (E_Display, E_Internal);
    TOperationMode = (E_Update, E_Output, E_Input, E_Append);
    TAccessType = (E_Sequential, E_Relative);
    TErrorType = (E_NoError, E_WriteProtection, E_BadAttribute, E_IllegalOpcode, E_MemoryFull, E_PastEOF, E_DeviceError, E_FileError);

    TPab = record
        operation: TOperation;
        errType: uint8;
        vdpBuffer: uint16;
        recLength, numChars: uint8;
        recSize: uint16;
        status: uint8;
        nameSize: uint8;
        name: array [0..255] of char
    end;
    TPabPtr = ^TPab;
    
    TDecodedPab = record
        devicename, filename: string;
        operation: TOperation;
        errorCode: TErrorType;
        recordType: TRecordType;
        dataType: TDataType;
        operationMode: TOperationMode;
        accessType: TAccessType;
        vdpBuffer: uint16;
        recordLength, numChars: uint8;
        recordNumber: uint16;
        status: uint8
    end;
    
    TFileBuffer = record
        devicename, filename, simulatorFilename: string;
        open: boolean;

        recordType: TRecordType;
        dataType: TDataType;
        operationMode: TOperationMode;
        accessType: TAccessType;        
        
        maxSector: 0..MaxSectors;
        recordLength: 0..255;
        maxRecord, activeRecord: uint16;
        
        eofPosition, sectorPosition: 0..255;            (* Variable only *)
        currentSector: 0..MaxSectors;
        
        sectors: array [0..MaxSectors - 1, 0..255] of uint8;
    end;
    
    TTiFilesHeader = record
        magic: array [0..7] of uint8;
        totalNumberOfSectors: uint16;
        flags, recordsPerSector, eofOffset, recordLength: uint8;
        level3Records: uint16;
        filename: array [0..9] of uint8;
        mxt: uint8;
        padding: array [27..127] of uint8
    end;
    
const
    TiFilesVariable = $80;
    TiFilesProtected = $08;
    TiFilesInternal = $02;
    TiFilesProgram = $01;

var
    files: array [1..MaxFiles] of TFileBuffer;
    fileDirectory: string;

function makeSimulatorFilename (device, filename: string): string;
    const
        n = 3;
        s1: array [1..n] of char = ('.', '/', '\');
        s2: array [1..n] of string = ('', '\s', '\b');
    var
        i: int64;
        j: 1..n + 1;
        res: string;
    begin
        res := fileDirectory + '/';
        i := 1;
        for i := 1 to length (filename) do
            begin
                j := 1;
                while (j <= n) and (filename [i] <> s1 [j]) do
                    inc (j);
                if j <= n then
                    res := res + s2 [j]
                else
                    res := res + filename [i]
            end;
        makeSimulatorFilename := res
    end;    
    
procedure diskSimSubFiles (numberOfFiles: int8);
    const
        fileBufferAreaHeader: array [1..5] of uint8 = ($aa, $3f, $ff, DiskSimCruAddress div 256, 0);
    var
        fileBufferBegin: uint16;
    begin
        fileBufferBegin := $3DEF - numberOfFiles * 518 - 5;
        writeMemory ($8370, fileBufferBegin - 1);
        fileBufferAreaHeader [5] := numberOfFiles;
        move (fileBufferAreaHeader, getVdpRamPtr (fileBufferBegin)^, sizeof (fileBufferAreaHeader));
        writeMemory ($8350, readMemory ($8350) and $00ff)
    end;

procedure diskSimPowerUpRoutine;
    begin
        if readMemory ($8370) = $3fff then
            diskSimSubFiles (3)
    end;        
    
procedure dumpPabOperation (var decodedPab: TDecodedPab);    
    const
        operationString: array [TOperation] of string = ('Open', 'Close', 'Read', 'Write', 'Rewind', 'Load', 'Save', 'Delete', 'Scratch', 'Status');
        recordTypeString: array [TRecordType] of string = ('Fixed', 'Variable');
        dataTypeString: array [TDataType] of string = ('Display', 'Internal');
        operationModeString: array [TOperationMode] of string = ('Update', 'Output', 'Input', 'Append');
        accessTypeString: array [TAccessType] of string = ('Sequential', 'Relative');
    begin
        with decodedPab do
            begin
                writeln ('Device:            ', devicename);
                writeln ('File:              ', filename);
                writeln ('Operation:         ', operationString [operation]);
                writeln ('Record type:       ', recordTypeString [recordType]);
                writeln ('Data type::        ', dataTypeString [dataType]);
                writeln ('Operation mode:    ', operationModeString [operationMode]);
                writeln ('Access type:       ', accessTypeString [accessType]);
                writeln ('Record length      ', recordLength);
                writeln ('Number of char:    ', numChars);
                writeln ('Recod #/File size: ', recordNumber);
                writeln
            end
    end;
    
procedure decodePab (pab: TPabPtr; var decodedPab: TDecodedPab);
    var
        i: uint8;
        pointFound: boolean;
    begin
        decodedPab.devicename := '';
        decodedPab.filename := '';
        pointFound := false;
        for i := 0 to pred (pab^.nameSize) do
            if pointFound then
                decodedPab.fileName := decodedPab.fileName + pab^.name [i]
            else if pab^.name [i] <> '.' then
                decodedPab.devicename := decodedPab.devicename + pab^.name [i]
            else
                pointFound := true;
                
        decodedPab.operation := pab^.operation;
        decodedPab.errorCode := E_NoError;
        decodedPab.recordType := TRecordType (ord (pab^.errType and $10 <> 0));
        decodedPab.dataType := TDataType (ord (pab^.errType and $08 <> 0));
        decodedPab.operationMode := TOperationMode ((pab^.errType shr 1) and $03);
        decodedPab.accessType := TAccessType (odd (pab^.errType));
        decodedPab.vdpBuffer := ntohs (pab^.vdpBuffer);
        decodedPab.recordLength := pab^.recLength;
        decodedPab.numChars := pab^.numChars;
        decodedPab.recordNumber := ntohs (pab^.recSize);
        decodedPab.status := 0
        
    end;
    
function findFile (devicename, filename: string): uint8;
    var 
        i: 1..MaxFiles;
    begin
        findFile := 0;
        for i := 1 to MaxFiles do
            if files [i].open and (devicename = files [i].devicename) and (filename = files [i].filename) then
                findFile := i    
    end;
    
function findFreeFile: uint8;
    var 
        i: 1..MaxFiles;
    begin
        findFreeFile := 0;
        for i := MaxFiles downto 1 do
            if not files [i].open then
                findFreeFile := i
    end;
    

const
    TiFilesMagic: array [0..7] of char = (#07, 'T', 'I', 'F', 'I', 'L', 'E', 'S');

procedure initTiFilesHeader (var header: TTiFilesHeader; filename: string);
    begin
        fillChar (header, sizeof (header), 0);
        move (TiFilesMagic, header.magic, sizeof (TiFilesMagic));
        fillchar (header.filename, sizeof (header.filename), ' ');
        if length (filename) > 0 then
            move (filename [1], header.filename, min (sizeof (header.filename), length (filename)));
    end;
    
function checkTiFilesHeader (var header: TTiFilesHeader): boolean;
    begin
        checkTiFilesHeader := compareByte (TiFilesMagic, header.magic, sizeof (TiFilesMagic)) = 0
    end;

(*$POINTERMATH ON*)    
function saveTiFiles (var fileBuffer: TFileBuffer): boolean;
    var
        header: TTiFilesHeader;
        p: ^uint8;
        contentBytes, bytesWritten: int64;
    begin
        initTiFilesHeader (header, fileBuffer.filename);
        header.totalNumberOfSectors := htons (fileBuffer.maxSector + 1);
        header.recordLength := fileBuffer.recordLength;
        if fileBuffer.recordType = E_Fixed then 
            begin
                header.recordsPerSector := SectorSize div fileBuffer.recordLength;
                header.level3Records := fileBuffer.maxRecord;
                header.eofOffset := ((fileBuffer.maxRecord mod header.recordsPerSector) * fileBuffer.recordLength) and $ff;
            end
        else 
            begin
                header.eofOffset := fileBuffer.eofPosition;
                header.level3Records := ntohs (header.totalNumberOfSectors);
                header.recordsPerSector := (SectorSize - 1) div fileBuffer.recordLength;
                header.flags := $80
            end;
        if fileBuffer.dataType = E_Internal then
            header.flags := header.flags or $02;
        
        contentBytes := sizeof (header) + ntohs (header.totalNumberOfSectors) * SectorSize;
        getMem (p, contentBytes);
        move (header, p [0], sizeof (header));
        move (fileBuffer.sectors, p [sizeof (header)], ntohs (header.totalNumberOfSectors) * SectorSize);
        saveBlock (p^, contentBytes, fileBuffer.simulatorFilename, bytesWritten);
        freeMem (p, contentBytes);
        saveTiFiles := contentBytes = bytesWritten        
    end;
    
function loadTiFilesHeader (var header: TTiFilesHeader; simulatorFilename: string): boolean;
    var 
        bytesRead: int64;
    begin
        loadBlock (header, sizeof (header), 0, simulatorFilename, bytesRead);
        loadTiFilesHeader := (bytesRead = sizeof (header)) and checkTiFilesHeader (header)
    end;

procedure loadTiFilesContent (var fileBuffer: TFileBuffer);
    var
        bytesRead: int64;
    begin
        loadBlock (fileBuffer.sectors, sizeof (fileBuffer.sectors), sizeof (TTiFilesHeader), fileBuffer.simulatorFilename, bytesRead)
    end;
    
procedure loadTiFiles (var fileBuffer: TFileBuffer; var errorCode: TErrorType);
    var
        header: TTiFilesHeader;
    begin
        if not loadTiFilesHeader (header, fileBuffer.simulatorFilename) then
            errorCode := E_FileError
        else if ((fileBuffer.recordType = E_Variable) <> (header.flags and TiFilesVariable <> 0)) or
                ((fileBuffer.dataType = E_Internal) <> (header.flags and TiFilesInternal <> 0)) or
                ((fileBuffer.recordLength <> 0) and (fileBuffer.recordLength <> header.recordLength)) or
                (header.flags and TiFilesProgram <> 0) then
            errorCode := E_BadAttribute
        else
            begin
                fileBuffer.maxSector := ntohs (header.totalNumberOfSectors) - 1;
                fileBuffer.recordLength := header.recordLength;
                
                (* FIXED only *)
                fileBuffer.maxRecord := header.level3Records;
                (* VARIABLE only *)
                fileBuffer.eofPosition := header.eofOffset;
                loadTiFilesContent (fileBuffer);
                errorCode := E_NoError
            end
    end;

procedure diskSimDsrOpen (var decodedPab: TDecodedPab);

    procedure initFileBuffer (var fileBuffer: TFileBuffer);
        begin
            with fileBuffer do
                begin
                    devicename := decodedPab.devicename;
                    filename := decodedPab.filename;
                    simulatorFilename := makeSimulatorFilename (devicename, filename);
                    open := true;
                    recordType := decodedPab.recordType;
                    dataType := decodedPab.dataType;
                    operationMode := decodedPab.operationMode;
                    accessType := decodedPab.accessType;
                    maxSector := 0;
                    recordLength := decodedPab.recordLength;
                    maxRecord := 0;
                    activeRecord := 0;
                    eofPosition := 0;
                    sectorPosition := 0;
                    currentSector := 0;
                    if recordType = E_Fixed then
                        fillChar (sectors, sizeof (sectors), $e5)
                    else
                        fillChar (sectors, sizeof (sectors), 0)
                end
        end;
        
    procedure createFile (var f: TFileBuffer; readOldContent: boolean);
        begin
            initFileBuffer (f);
            if decodedPab.recordLength = 0 then
                 decodedPab.recordLength := 80;
            f.recordLength := decodedPab.recordLength
        end;
        
    procedure openInput (var fileBuffer: TFileBuffer);
        begin
            initFileBuffer (fileBuffer);
            (* TODO: Error status *)
            loadTiFiles (fileBuffer, decodedPab.errorCode);
            decodedPab.recordLength := fileBuffer.recordLength
        end;
        
    procedure openUpdate (var fileBuffer: TFileBuffer);
        begin
            if fileExists (fileBuffer.simulatorFilename) then
                openInput (fileBuffer)
            else
                createFile (fileBuffer, false)
        end;
        
    procedure openOutput (var fileBuffer: TFileBuffer);
        begin
            createFile (fileBuffer, true);
            loadTiFilesContent (fileBuffer);    (* Load and overwrite whatever is in the file *)
        end;
        
    procedure openAppend (var fileBuffer: TFileBuffer);
        begin
            (* TODO: Only for variable files *)
            openInput (fileBuffer);
            with fileBuffer do 
                begin
                    currentSector := maxSector;
                    sectorPosition := eofPosition
                end
        end;
        
    var
        filenr: 0..MaxFiles;
        
    begin
        filenr := findFile (decodedPab.devicename, decodedPab.filename);
        if filenr = 0 then
            filenr := findFreeFile;
        if filenr = 0 then
            decodedPab.errorCode := E_FileError
        else
            begin
                case decodedPab.operationMode of
                    E_Output:
                        openOutput (files [filenr]);
                    E_Update:
                        openUpdate (files [filenr]);
                    E_Input:
                        openInput (files [filenr]);
                    E_Append:
                        openAppend (files [filenr])
                end;
                if decodedPab.errorCode <> E_NoError then
                    files [filenr].open := false
            end
    end;
    
procedure diskSimDsrClose (var decodedPab: TDecodedPab);
    var
        filenr: 0..MaxFiles;
    begin
        filenr := findFile (decodedPab.devicename, decodedPab.filename);
        if filenr = 0 then
            decodedPab.errorCode := E_FileError
        else 
            with files [filenr] do
                begin
                    if operationMode <> E_Input then
                        begin
                            if recordType = E_Variable then
                                begin
                                    sectors [maxSector][sectorPosition] := EofMarker; 
                                    eofPosition := sectorposition
                                end;
                            if not saveTiFiles (files [filenr]) then
                                decodedPab.errorCode := E_FileError
                        end;
                    open := false
                end
    end;
    
procedure diskSimDsrRead (var decodedPab: TDecodedPab);

    procedure readFixedRecord (var fileBuffer: TFileBuffer);
        var
            recsSector: uint8;
            sectorNumber: uint16;
            sectorOffset: uint8;
        begin
            if decodedPab.recordNumber > fileBuffer.maxRecord then
                decodedPab.errorCode := E_PastEOF
            else
                begin
                    recsSector := SectorSize div fileBuffer.recordLength;
                    sectorNumber := decodedPab.recordNumber div recsSector;
                    sectorOffset := (decodedPab.recordNumber mod recsSector) * fileBuffer.recordLength;
                    move (fileBuffer.sectors [sectorNumber][sectorOffset], getVdpRamPtr (decodedPab.vdpBuffer)^, fileBuffer.recordLength);
                    decodedPab.numChars := fileBuffer.recordLength
                end
        end;
        
    procedure readVariableRecord (var fileBuffer: TFileBuffer);
        var
            length: uint8;
        begin
            with fileBuffer do 
                begin
                    if sectors [currentSector, sectorPosition] = EofMarker then
                        if currentSector >= maxSector then
                            decodedPab.errorCode := E_PastEOF
                        else
                            begin
                                inc (currentSector);
                                sectorPosition := 0
                            end;
                    if decodedPab.errorCode = E_NoError then
                        begin
                            length := sectors [currentSector, sectorPosition];
                            move (sectors [currentSector, sectorPosition + 1], getVdpRamPtr (decodedPab.vdpBuffer)^, length);
                            inc (sectorPosition, length + 1);
                            decodedPab.numChars := length
                        end
                end
        end;
            
    var
        filenr: 0..MaxFiles;
        
    begin
        filenr := findFile (decodedPab.devicename, decodedPab.filename);
        if filenr = 0 then
            decodedPab.errorCode := E_FileError
        else begin
            files [filenr].activeRecord := decodedPab.recordNumber;
            if files [filenr].recordType = E_Fixed then
                readFixedRecord (files [filenr])
            else
                readVariableRecord (files [filenr]);
            decodedPab.recordNumber := files [filenr].activeRecord + 1
        end
    end;
    
procedure diskSimDsrWrite (var decodedPab: TDecodedPab);
    
    procedure writeFixedRecord (var f: TFileBuffer);
        var
            recsSector: uint8;
            sectorNumber: uint16;
            sectorOffset: uint8;
        begin
            recsSector := SectorSize div f.recordLength;
            sectorNumber := decodedPab.recordNumber div recsSector;
            sectorOffset := (decodedPab.recordNumber mod recsSector) * f.recordLength;
            if sectorNumber >= MaxSectors then
                decodedPab.errorCode := E_MemoryFull
            else
                begin
                    move (getVdpRamPtr (decodedPab.vdpBuffer)^, f.sectors [sectorNumber][sectorOffset], f.recordLength);
                    f.activeRecord := decodedPab.recordNumber;
                    if f.activeRecord > f.maxRecord then
                        f.maxRecord := f.activeRecord;
                    if sectorNumber > f.maxSector then
                        f.maxSector := sectorNumber
                end
                
        end;
                
    procedure writeVariableRecord (var f: TFileBuffer);
        begin
            if decodedPab.numChars + 1 >= SectorSize - f.sectorPosition then
                if f.maxSector + 1 >= MaxSectors then
                    begin
                        decodedPab.errorCode := E_MemoryFull;
                        exit
                    end
                else 
                    begin
                        f.sectors [f.maxSector, f.sectorPosition] := EofMarker;
                        inc (f.maxSector);
                        f.sectorPosition := 0
                    end;
            f.sectors [f.maxSector][f.sectorPosition] := decodedPab.numChars;
            move (getVdpRamPtr (decodedPab.vdpBuffer)^, f.sectors [f.maxSector][f.sectorPosition + 1], decodedPab.numChars);
            inc (f.sectorPosition, decodedPab.numChars + 1)
        end;

    var
        filenr: 0..MaxFiles;
    begin
        filenr := findFile (decodedPab.devicename, decodedPab.filename);
        if filenr = 0 then
            decodedPab.errorCode := E_FileError
        else begin
            if decodedPab.recordType = E_Fixed then
                writeFixedRecord (files [filenr])
            else
                writeVariableRecord (files [filenr]);
            decodedPab.recordNumber := files [filenr].activeRecord + 1
        end;
    end;
    
procedure diskSimDsrRewind (var decodedPab: TDecodedPab);
    var
        filenr: 0..MaxFiles;
    begin
        filenr := findFile (decodedPab.devicename, decodedPab.filename);
        if filenr = 0 then
            decodedPab.errorCode := E_FileError
        else 
            with files [filenr] do
                if files [filenr].operationMode = E_Append then
                    decodedPab.errorCode := E_FileError
                else
                    begin
                        activeRecord := 0;
                        currentSector := 0;
                        sectorPosition := 0
                    end
    end;
    
procedure diskSimDsrLoad (var decodedPab: TDecodedPab);
    var 
        fn: string;
        bytesRead: int64;
        header: TTiFilesHeader;
    begin
        fn := makeSimulatorFilename (decodedPab.deviceName, decodedPab.filename);
        loadBlock (header, sizeof (header), 0, fn, bytesRead);
        loadBlock (getVdpRamPtr (decodedPab.vdpBuffer)^, decodedPab.recordNumber, sizeof (header) * ord (checkTiFilesHeader (header)), fn, bytesRead);
        if bytesRead = 0 then
            decodedPab.errorCode := E_FileError
    end;

procedure diskSimDsrSave (var decodedPab: TDecodedPab);
    var
        buf: array [0..16384 + sizeof (TTiFilesHeader)] of uint8;
        header: TTiFilesHeader absolute buf;
        bytesWritten: int64;
        sectors: uint16;
    begin
        initTiFilesHeader (header, decodedPab.filename);
        sectors := decodedPab.recordNumber div SectorSize;
        header.flags := TiFilesProgram;
        header.eofOffset := decodedPab.recordNumber mod SectorSize;
        if header.eofOffset <> 0 then
            inc (sectors);
        header.totalNumberOfSectors := htons (sectors);
        move (getVdpRamPtr (decodedPab.vdpBuffer)^, buf [sizeof (TTiFilesHeader)], decodedPab.recordNumber);
        saveBlock (buf, sizeof (TTiFilesHeader) + decodedPab.recordNumber, makeSimulatorFilename (decodedPab.devicename, decodedPab.filename), bytesWritten);
        if bytesWritten <> sizeof (TTiFilesHeader) + decodedPab.recordNumber then
            decodedPab.errorCode := E_FileError
    end;
    
procedure diskSimDsrDelete (var decodedPab: TDecodedPab);
    var
        filenr: 0..MaxFiles;
    begin
        filenr := findFile (decodedPab.devicename, decodedPab.filename);
        if filenr <> 0 then
            files [filenr].open := false;
        deleteFile (makeSimulatorFilename (decodedPab.devicename, decodedPab.filename))
    end;
    
procedure diskSimDsrScratch (var decodedPab: TDecodedPab);
    begin
        decodedPab.errorCode := E_BadAttribute
    end;
    
procedure diskSimDsrStatus (var decodedPab: TDecodedPab);
    const
        (* Status flags *)
        FileNotFound = $80;
        WriteProtected = $40;
        FileInternal = $10;
        FileProgram = $08;
        FileVariable = $04;
        MemoryFull = $02;
        EOFReached = $01;
    var 
        filenr: 0..MaxFiles;
        header: TTiFilesHeader;
        
    procedure transferFlag (tiFilesFlag, statusFlag: uint8);
        begin
            if header.flags and tiFilesFlag <> 0 then
                decodedPab.status := decodedPab.status or statusFlag
        end;
        
    begin
        filenr := findFile (decodedPab.devicename, decodedPab.filename);
        if filenr = 0 then
            begin
                if not loadTiFilesHeader (header, makeSimulatorFilename (decodedPab.devicename, decodedPab.filename)) then
                    decodedPab.status := FileNotFound
                else 
                    begin
                        transferFlag (TiFilesProgram, FileProgram);
                        transferFlag (TiFilesProtected, WriteProtected);
                        transferFlag (TiFilesInternal, Fileinternal);
                        transferFlag (TiFilesVariable, FileVariable)
                    end
            end
        else
            with files [filenr] do
                begin
                    decodedPab.status := FileInternal * ord (dataType);
                    if recordType = E_Variable then
                        begin
                            decodedPab.status := decodedPab.status or FileVariable;
                            if (currentSector > maxSector) or (sectors [currentSector, sectorPosition] = EofMarker) then
                                decodedPab.status := decodedPab.status or EofReached
                        end
                    else
                        if decodedPab.recordNumber > maxRecord then
                            decodedPab.status := decodedPab.status or EofReached
                end
    end;
    
procedure diskSimDsrRoutine;
    var
        pab: TPabPtr;
        decodedPab: TDecodedPab;
    begin
        pab := TPabPtr (getVdpRamPtr (readMemory ($8356) - 14));
        decodePab (pab, decodedPab);
//        dumpPabOperation (decodedPab);
        case decodedPab.operation of
            E_Open:
                diskSimDsrOpen (decodedPab);
            E_Close:
                diskSimDsrClose (decodedPab);
            E_Read:
                diskSimDsrRead (decodedPab);
            E_Write:
                diskSimDsrWrite (decodedPab);
            e_Rewind:
                diskSimDsrRewind (decodedPab);
            E_Load:
                diskSimDsrLoad (decodedPab);
            E_Save:
                diskSimDsrSave (decodedPab);
            E_Delete:
                diskSimDsrDelete (decodedPab);
            E_Scratch:
                diskSimDsrScratch (decodedPab);
            E_Status:
                begin
                    diskSimDsrStatus (decodedPab);
                    pab^.status := decodedPab.status
                end;
        end;
        pab^.recLength := decodedPab.recordLength;
        pab^.recSize := htons (decodedPab.recordNumber);
        pab^.errType := (pab^.errType and $1F) or (ord (decodedPab.errorCode) shl 5);
        pab^.numChars := decodedPab.numChars
    end;

procedure diskSimSubFilesBasic;
    begin
        writeln ('Not implemented yet')
    end;

procedure diskSimSubSectorIO;
    begin
        writeln ('Disk sector IO not supported for files in a directory')
    end;    

procedure diskSimSubFormatDisk;
    begin
        writeln ('Not implemented yet')
    end;
    
procedure diskSimSubProtectFile;
    begin
        writeln ('Not implemented yet')
    end;
    
procedure diskSimSubRenameFile;
    begin
        writeln ('Not implemented yet')
    end;
    
procedure diskSimSubFileInput;
    begin
        writeln ('Not implemented yet')
    end;
    
procedure diskSimSubFileOutput;
    begin
        writeln ('Not implemented yet')
    end;
    
procedure diskSimSubNumberOfFiles;
    begin
        writeln ('Not implemented yet')
    end;
    

procedure initFileBuffers;
    var
        i: 1..MaxFiles;
    begin
        for i := 1 to MaxFiles do
            with files [i] do
                begin
                    filename := '';
                    devicename := '';
                    open := false
                end
    end;

var    
    dsrRom: array [$4000..$5fff] of uint8;
    dsrRomW: array [$2000..$2fff] of uint16 absolute dsrRom;
    
function readDiskSim (addr: uint16): uint16;
    begin
        readDiskSim := htons (dsrRomW [addr shr 1])
    end;

procedure initDiskSim (dsrFilename, directory: string);
    begin
        load (dsrRom, sizeof (dsrRom), dsrFilename);
        initFileBuffers;
        fileDirectory := directory;
    end;

end.
