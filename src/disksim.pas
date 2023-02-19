unit disksim;

interface

function readDiskSim (addr: uint16): uint16;

procedure initDiskSim (dsrFileName, directory: string);

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


implementation

uses memory, vdp, pab, types, tools, cfuncs, math, sysutils;

const
    SectorSize = 256;
    MaxSectors = 4 * 360;       (* DS/DD floppy *)
    MaxFiles = 16;
    EofMarker = $ff;
    TiFilesVariable = $80;
    TiFilesProtected = $08;
    TiFilesInternal = $02;
    TiFilesProgram = $01;
    TiFilesMagic: array [0..7] of char = (#07, 'T', 'I', 'F', 'I', 'L', 'E', 'S');

type 
    TTiFilesHeader = record
        magic: array [0..7] of uint8;
        totalNumberOfSectors: uint16;
        flags, recordsPerSector, eofOffset, recordLength: uint8;
        level3Records: uint16;
        fileName: array [0..9] of uint8;
        mxt: uint8;
        padding: array [27..127] of uint8
    end;
    
    TFileBuffer = record
        deviceName, fileName, simulatorFileName: string;
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

        header: TTiFilesHeader;
        sectors: array [0..MaxSectors - 1, 0..255] of uint8;
    end;
    
var
    dsrRom: TDsrRom;
    files: array [1..MaxFiles] of TFileBuffer;
    fileDirectory: string;

function makeHostFileName (var pab: TPab): string;
    const
        n = 2;
        s1: array [1..n] of char = ('/', '\');
        s2: array [1..n] of string = ('\s', '\b');
    var
        i: int64;
        j: 1..n + 1;
        res: string;
        fileName: string;
    begin
        fileName := getFileName (pab);
        res := fileDirectory + '/';
        i := 1;
        for i := 1 to length (fileName) do
            begin
                j := 1;
                while (j <= n) and (fileName [i] <> s1 [j]) do
                    inc (j);
                if j <= n then
                    res := res + s2 [j]
                else
                    res := res + fileName [i]
            end;
        makeHostFileName := res
    end;    
    
procedure diskSimSubFiles (numberOfFiles: uint8);
    const
        fileBufferAreaHeader: array [1..5] of uint8 = ($aa, $3f, $ff, DiskSimCruAddress div 256, 0);
    var
        fileBufferBegin: uint16;
    begin
//        writeln ('CALL FILES (', numberOfFiles, ')');
        if numberOfFiles in [1..16] then
            begin
                fileBufferBegin := $3DEF - numberOfFiles * 518 - 5;
                writeMemory ($8370, fileBufferBegin - 1);
                fileBufferAreaHeader [5] := numberOfFiles;
                vdpWriteBlock (fileBufferBegin, sizeof (fileBufferAreaHeader), fileBufferAreaHeader);
                writeMemory ($8350, readMemory ($8350) and $00ff)
            end
        else
            writeMemory ($8350, readMemory ($8350) and $00ff or $0200) // TODO: Bad attribute - check if correct error code
    end;

procedure diskSimPowerUpRoutine;
    begin
    (* Do we really need to reserve these buffers? The UCSD editor crashes when no buffer is present but it cannot use this DSR anyway. *)
        if readMemory ($8370) = $3fff then
            diskSimSubFiles (3)
    end;        
    
function findFile (var pab: TPab): uint8;
    var 
        i: 1..MaxFiles;
        deviceName, fileName: string;
    begin
        decodeNames (pab, deviceName, fileName);
        findFile := 0;
        for i := 1 to MaxFiles do
            if files [i].open and (deviceName = files [i].deviceName) and (fileName = files [i].fileName) then
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

procedure initTiFilesHeader (var header: TTiFilesHeader; fileName: string);
    begin
        fillChar (header, sizeof (header), 0);
        move (TiFilesMagic, header.magic, sizeof (TiFilesMagic));
        fillchar (header.fileName, sizeof (header.fileName), ' ');
        if length (fileName) > 0 then
            move (fileName [1], header.fileName, min (sizeof (header.fileName), length (fileName)));
    end;
    
function checkTiFilesHeader (var header: TTiFilesHeader): boolean;
    begin
        checkTiFilesHeader := compareByte (TiFilesMagic, header.magic, sizeof (TiFilesMagic)) = 0
    end;

(*$POINTERMATH ON*)    
function saveTiFiles (var fileBuffer: TFileBuffer): boolean;
    var
        contentBytes: int64;
    begin
        initTiFilesHeader (fileBuffer.header, fileBuffer.fileName);
        fileBuffer.header.totalNumberOfSectors := htons (fileBuffer.maxSector + 1);
        fileBuffer.header.recordLength := fileBuffer.recordLength;
        if fileBuffer.recordType = E_Fixed then 
            begin
                fileBuffer.header.recordsPerSector := SectorSize div fileBuffer.recordLength;
                fileBuffer.header.level3Records := fileBuffer.maxRecord;
                fileBuffer.header.eofOffset := ((fileBuffer.maxRecord mod fileBuffer.header.recordsPerSector) * fileBuffer.recordLength) and $ff;
            end
        else 
            begin
                fileBuffer.header.eofOffset := fileBuffer.eofPosition;
                fileBuffer.header.level3Records := ntohs (fileBuffer.header.totalNumberOfSectors);
                fileBuffer.header.recordsPerSector := (SectorSize - 1) div fileBuffer.recordLength;
                fileBuffer.header.flags := $80
            end;
        if fileBuffer.dataType = E_Internal then
            fileBuffer.header.flags := fileBuffer.header.flags or $02;
        contentBytes := sizeof (TTiFilesHeader) + ntohs (fileBuffer.header.totalNumberOfSectors) * SectorSize;
        saveTiFiles := saveBlock (fileBuffer.header, contentBytes, fileBuffer.simulatorFileName) = contentBytes
    end;
    
function loadTiFilesHeader (var header: TTiFilesHeader; simulatorFileName: string): boolean;
    begin
        loadTiFilesHeader := (loadBlock (header, sizeof (header), 0, simulatorFileName) = sizeof (header)) and checkTiFilesHeader (header)
    end;

procedure loadTiFilesContent (var fileBuffer: TFileBuffer);
    begin
        loadBlock (fileBuffer.sectors, sizeof (fileBuffer.sectors), sizeof (TTiFilesHeader), fileBuffer.simulatorFileName)
    end;
    
procedure loadTiFiles (var fileBuffer: TFileBuffer; var errorCode: TErrorCode);
    var
        header: TTiFilesHeader;
    begin
        if not loadTiFilesHeader (header, fileBuffer.simulatorFileName) then
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

procedure diskSimDsrOpen (var pab: TPab);

    procedure initFileBuffer (var fileBuffer: TFileBuffer);
        begin
            with fileBuffer do
                begin
                    decodeNames (pab, deviceName, fileName);
                    simulatorFileName := makeHostFileName (pab);
                    open := true;
                    recordType := getRecordType (pab);
                    dataType := getDataType (pab);
                    operationMode := getOperationmode (pab);
                    accessType := getAccessType (pab);
                    maxSector := 0;
                    recordLength := getRecordLength (pab);
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
            if getRecordLength (pab) = 0 then
                setRecordLength (pab, 80);
            f.recordLength := getRecordLength (pab)
        end;
        
    procedure openInput (var fileBuffer: TFileBuffer);
        var 
            errorCode: TErrorCode;
        begin
            loadTiFiles (fileBuffer, errorCode);
            setErrorCode (pab, errorCode);
            setRecordLength (pab, fileBuffer.recordLength)
        end;
        
    procedure openUpdate (var fileBuffer: TFileBuffer);
        begin
            if fileExists (fileBuffer.simulatorFileName) then
                openInput (fileBuffer)
            else
                createFile (fileBuffer, false);
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
        filenr := findFile (pab);
        if filenr = 0 then
            filenr := findFreeFile;
        if filenr = 0 then
            setErrorCode (pab, E_FileError)
        else
            begin
                initFileBuffer (files [filenr]);
                case getOperationMode (pab) of
                    E_Output:
                        openOutput (files [filenr]);
                    E_Update:
                        openUpdate (files [filenr]);
                    E_Input:
                        openInput (files [filenr]);
                    E_Append:
                        openAppend (files [filenr])
                end;
                if getErrorCode (pab) <> E_NoError then
                    files [filenr].open := false
            end
    end;
    
procedure diskSimDsrClose (var pab: TPab);
    var
        filenr: 0..MaxFiles;
    begin
        filenr := findFile (pab);
        if filenr = 0 then
            setErrorCode (pab,  E_FileError)
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
                                setErrorCode (pab,  E_FileError)
                        end;
                    open := false
                end
    end;
    
procedure diskSimDsrRead (var pab: TPab);

    procedure readFixedRecord (var fileBuffer: TFileBuffer);
        var
            recsSector: uint8;
            sectorNumber: uint16;
            sectorOffset: uint8;
        begin
            if getRecordNumber (pab) > fileBuffer.maxRecord then
                setErrorCode (pab, E_PastEOF)
            else
                begin
                    recsSector := SectorSize div fileBuffer.recordLength;
                    sectorNumber := getRecordNumber (pab) div recsSector;
                    sectorOffset := (getRecordNumber (pab)  mod recsSector) * fileBuffer.recordLength;
                    vdpWriteBlock (getBufferAddress (pab), fileBuffer.recordLength, fileBuffer.sectors [sectorNumber][sectorOffset]);
                    setNumChars (pab, fileBuffer.recordLength)
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
                            setErrorCode (pab, E_PastEOF)
                        else
                            begin
                                inc (currentSector);
                                sectorPosition := 0
                            end;
                    if getErrorCode (pab) = E_NoError then
                        begin
                            length := sectors [currentSector, sectorPosition];
                            vdpWriteBlock (getBufferAddress (pab), length, sectors [currentSector, sectorPosition + 1]);
                            inc (sectorPosition, length + 1);
                            setNumChars (pab, length)
                        end
                end
        end;
            
    var
        filenr: 0..MaxFiles;
        
    begin
        filenr := findFile (pab);
        if filenr = 0 then
            setErrorCode (pab, E_FileError)
        else begin
            files [filenr].activeRecord := getRecordNumber (pab);
            if files [filenr].recordType = E_Fixed then
                readFixedRecord (files [filenr])
            else
                readVariableRecord (files [filenr]);
            setRecordNumber (pab, files [filenr].activeRecord + 1)
        end
    end;
    
procedure diskSimDsrWrite (var pab: TPab);
    
    procedure writeFixedRecord (var f: TFileBuffer);
        var
            recsSector: uint8;
            sectorNumber: uint16;
            sectorOffset: uint8;
        begin
            recsSector := SectorSize div f.recordLength;
            sectorNumber := getRecordNumber (pab) div recsSector;
            sectorOffset := (getRecordNumber (pab) mod recsSector) * f.recordLength;
            if sectorNumber >= MaxSectors then
                setErrorCode (pab, E_MemoryFull)
            else
                begin
                    vdpReadBlock (getBufferAddress (pab), f.recordLength, f.sectors [sectorNumber][sectorOffset]);
                    f.activeRecord := getRecordNumber (pab);
                    if f.activeRecord > f.maxRecord then
                        f.maxRecord := f.activeRecord;
                    if sectorNumber > f.maxSector then
                        f.maxSector := sectorNumber
                end
                
        end;
                
    procedure writeVariableRecord (var f: TFileBuffer);
        begin
            if getNumChars (pab) + 1 >= SectorSize - f.sectorPosition then
                if f.maxSector + 1 >= MaxSectors then
                    begin
                        setErrorCode (pab, E_MemoryFull);
                        exit
                    end
                else 
                    begin
                        f.sectors [f.maxSector, f.sectorPosition] := EofMarker;
                        inc (f.maxSector);
                        f.sectorPosition := 0
                    end;
            f.sectors [f.maxSector][f.sectorPosition] := getNumChars (pab);
            vdpReadBlock (getBufferAddress (pab), getNumChars (pab), f.sectors [f.maxSector][f.sectorPosition + 1]);
            inc (f.sectorPosition, succ (getNumChars (pab)))
        end;

    var
        filenr: 0..MaxFiles;
    begin
        filenr := findFile (pab);
        if filenr = 0 then
            setErrorCode (pab, E_FileError)
        else 
            begin
                if getRecordType (pab) = E_Fixed then
                    writeFixedRecord (files [filenr])
                else
                    writeVariableRecord (files [filenr]);
                setRecordNumber (pab, succ (files [filenr].activeRecord))
            end
    end;
    
procedure diskSimDsrRewind (var pab: TPab);
    var
        filenr: 0..MaxFiles;
    begin
        filenr := findFile (pab);
        if filenr = 0 then
            setErrorCode (pab, E_FileError)
        else 
            with files [filenr] do
                if files [filenr].operationMode = E_Append then
                    setErrorCode (pab, E_FileError)
                else
                    begin
                        activeRecord := 0;
                        currentSector := 0;
                        sectorPosition := 0
                    end
    end;
    
procedure diskSimDsrLoad (var pab: TPab);
    var 
        buf: array [0..VdpRAMSize] of uint8;
        fn: string;
        header: TTiFilesHeader;
        hasHeader: boolean;
        size, loaded: uint16;
    begin
        fn := makeHostFileName (pab);
        setErrorCode (pab, E_NoError);
        fillChar (header, sizeof (header), 0);
        loadBlock (header, sizeof (header), 0, fn);
        hasHeader := checkTiFilesHeader (header);
        if hasHeader then
            begin
                size := SectorSize * pred (ntohs (header.totalNumberOfSectors)) + header.eofOffset;
                if header.eofOffset = 0 then
                    inc (size, Sectorsize);
                writeln ('Program size: ', size);
                writeln ('VDP buffer size: ', getRecordNumber (pab));
                writeln ('Header flags: ', header.flags);
                if (header.flags <> TiFilesProgram) or (header.totalNumberOfSectors = 0) or (size > getRecordNumber (pab)) or (size > VdpRAMSize) then
                    begin
                        writeln ('Header check failed');
                        setErrorCode (pab, E_FileError)
                    end
            end
        else
            begin
                writeln ('No TIFILES header in ', fn, ' - trying to load as program');
                size := getRecordNumber (pab);
                writeln ('VDP buffer size: ', size);
                if size > VdpRAMSize then
                    setErrorCode (pab, E_FileError)
            end;
        if getErrorCode (pab) = E_NoError then
            begin
                loaded := loadBlock (buf, size, sizeof (header) * ord (hasHeader), fn);
                if (loaded = 0) or hasHeader and (loaded < size) then
                    setErrorCode (pab, E_FileError)
                else
                    vdpWriteBlock (getBufferAddress (pab), size, buf)
            end
    end;

procedure diskSimDsrSave (var pab: TPab);
    var
        buf: array [0..16384 + sizeof (TTiFilesHeader)] of uint8;
        header: TTiFilesHeader absolute buf;
        sectors: uint16;
    begin
        initTiFilesHeader (header, getFileName (pab));
        sectors := getRecordNumber (pab) div SectorSize;
        header.flags := TiFilesProgram;
        header.eofOffset := getRecordNumber (pab) mod SectorSize;
        if header.eofOffset <> 0 then
            inc (sectors);
        header.totalNumberOfSectors := htons (sectors);
        if getRecordNumber (pab) >= 15384 then
            setErrorCode (pab, E_MemoryFull)
        else
            begin
                vdpReadBlock (getBufferAddress (pab), getRecordNumber (pab), buf [sizeof (TTiFilesHeader)]);
                if saveBlock (buf, sizeof (TTiFilesHeader) + getRecordNumber (pab), makeHostFileName (pab))  <> sizeof (TTiFilesHeader) + getRecordNumber (pab) then
                    setErrorCode (pab, E_FileError)
            end
    end;
    
procedure diskSimDsrDelete (var pab: TPab);
    var
        filenr: 0..MaxFiles;
    begin
        filenr := findFile (pab);
        if filenr <> 0 then
            files [filenr].open := false;
        deleteFile (makeHostFileName (pab))
    end;
    
procedure diskSimDsrUnsupported (var pab: TPab);
    begin
        setErrorCode (pab, E_IllegalOpcode);
        writeln ('Disksim: Unsupported operation ', pab.operation, ' requested')
    end;
    
procedure diskSimDsrStatus (var pab: TPab);
    var 
        filenr: 0..MaxFiles;
        header: TTiFilesHeader;
        status: uint8;
        
    function checkFlag (tiFilesFlag: uint8): uint8;
        begin
            checkFlag := ord (header.flags and tiFilesFlag <> 0)
        end;
        
    begin
        filenr := findFile (pab);
        if filenr = 0 then
            if loadTiFilesHeader (header, makeHostFileName (pab)) then
                status := PabStatusFileProgram * checkFlag (TiFilesProgram) + PabStatusWriteProtected * checkFlag (TiFilesProtected) +
                          PabStatusFileInternal * checkFlag (TiFilesInternal) + PabStatusFileVariable * checkFlag (TiFilesVariable)
            else 
                status := PabStatusFileNotFound
        else
            with files [filenr] do
                begin
                    status := PabStatusFileInternal * ord (dataType);
                    if recordType = E_Variable then
                        begin
                            status := status or PabStatusFileVariable;
                            if (currentSector > maxSector) or (sectors [currentSector, sectorPosition] = EofMarker) then
                                status := status or PabStatusEofReached
                        end
                    else
                        if getRecordNumber (pab) > maxRecord then
                            status := status or PabStatusEofReached
                end;
        setStatus (pab, status)
    end;
    
procedure diskSimDsrRoutine;
    const dsrOperation: array [TOperation] of procedure (var pab: TPab) = (
        diskSimDsrOpen, diskSimDsrClose, diskSimDsrRead, diskSimDsrWrite, diskSimDsrRewind, diskSimDsrLoad, diskSimDsrSave, diskSimDsrDelete, diskSimDsrUnsupported, diskSimDsrStatus, diskSimDsrUnsupported, diskSimDsrUnsupported);
    var
        pab: TPab;
        pabAddr: uint16;
    begin
        pabAddr := uint16 (readMemory ($8356) - (readMemory ($8354) and $ff) - 10);
        vdpReadBlock (pabAddr, 10, pab);
        vdpReadBlock (pabAddr + 10, getNameSize (pab), pab.name);
        dsrOperation [getOperation (pab)] (pab);
        vdpWriteBlock (pabAddr, 10, pab)		// write back changes        
    end;

procedure diskSimSubFilesBasic;
    begin
        writeln ('Files: Not implemented yet')
    end;

procedure diskSimSubSectorIO;
    begin
        writeln ('>10 Sector IO: not implemented yet')
    end;    

procedure diskSimSubFormatDisk;
    begin
        writeln ('>11 Format Disk: not implemented yet')
    end;
    
procedure diskSimSubProtectFile;
    begin
        writeln ('>12 File Protection: not implemented yet')
    end;
    
procedure diskSimSubRenameFile;
    begin
        writeln ('>13 Rename File: not implemented yet')
    end;
    
procedure diskSimSubFileInput;
    begin
        writeln ('>14 File Sector Input: not implemented yet')
    end;
    
procedure diskSimSubFileOutput;
    begin
        writeln ('>15 File Sector Output: not implemented yet')
    end;
    
procedure diskSimSubNumberOfFiles;
    begin
        diskSimSubFiles (readMemory ($834c) shr 8)
    end;

procedure initFileBuffers;
    var
        i: 1..MaxFiles;
    begin
        for i := 1 to MaxFiles do
            with files [i] do
                begin
                    fileName := '';
                    deviceName := '';
                    open := false
                end
    end;

function readDiskSim (addr: uint16): uint16;
    begin
        readDiskSim := ntohs (dsrRom.w [addr shr 1])
    end;

procedure initDiskSim (dsrFileName, directory: string);
    begin
        loadBlock (dsrRom, sizeof (dsrRom), 0, dsrFileName);
        initFileBuffers;
        fileDirectory := directory;
    end;

end.
