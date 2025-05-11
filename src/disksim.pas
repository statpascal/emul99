unit disksim;

interface

function readDiskSim (addr: uint16): uint16;

procedure initDiskSim (dsrFileName, directory: string; diskSimHostFiles: boolean);

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

uses memory, vdp, pab, types, tools, cfuncs, math, sysutils, fileop;

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
        open, plaintext: boolean;
        plainTextFile: TFileHandle;

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
    useHostFiles: boolean;

function makeHostFileName (var pab: TPab; var isHost: boolean): string;
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
        isHost := upcase (copy (filename, 1, 3)) = '?W.';
        if isHost then
            filename := copy (filename, 4, length (filename));
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
    
procedure diskSimPowerUpRoutine;
    begin
    (* Do we really need to reserve these buffers? The UCSD editor crashes when no buffer is present but it cannot use this DSR anyway. *)
        if readMemory ($8370) = $3fff then
            reserveVdpFileBuffers (3, DiskSimCruAddress)
    end;        
    
function findFile (var pab: TPab; isOpen, setError: boolean): uint8;
    var 
        i, res: 0..MaxFiles;
        deviceName, fileName: string;
    begin
        decodeNames (pab, deviceName, fileName);
        res := 0;
        for i := 1 to MaxFiles do
            if files [i].open and (deviceName = files [i].deviceName) and (fileName = files [i].fileName) then
                res := i;
        if isOpen and (res = 0) then
            for i := MaxFiles downto 1 do
                if not files [i].open then
                    res := i;
        if setError and (res = 0) then
            setErrorCode (pab, E_FileError);
        findFile := res
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
                fileBuffer.header.eofOffset := ((fileBuffer.maxRecord mod fileBuffer.header.recordsPerSector) * fileBuffer.recordLength) and $ff
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
        loadTiFilesHeader := (loadBlock (header, sizeof (header), 0, simulatorFileName, false) = sizeof (header)) and checkTiFilesHeader (header)
    end;

procedure loadTiFilesContent (var fileBuffer: TFileBuffer);
    begin
        loadBlock (fileBuffer.sectors, sizeof (fileBuffer.sectors), sizeof (TTiFilesHeader), fileBuffer.simulatorFileName, false)
    end;
    
procedure loadTiFiles (var fileBuffer: TFileBuffer; var errorCode: TErrorCode);
    var
        header: TTiFilesHeader;
    begin
        if not loadTiFilesHeader (header, fileBuffer.simulatorFileName) then
            if fileExists (fileBuffer.simulatorFileName) and (fileBuffer.datatype = E_Display) and (fileBuffer.recordType = E_Variable) then
                begin
                    fileBuffer.plainText := true;
                    errorCode := E_NoError;
                    writeln ('Reading ', fileBuffer.simulatorFileName, ' as plain text file')
                end
            else
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
        var
            forcePlain: boolean;
        begin
            with fileBuffer do
                begin
                    decodeNames (pab, deviceName, fileName);
                    simulatorFileName := makeHostFileName (pab, forcePlain);
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
                    fillChar (sectors, sizeof (sectors), $e5 * ord (recordType = E_Fixed));
                    plainText :=  forcePlain or (operationMode = E_Output) and useHostFiles and (datatype = E_Display) and (recordType = E_Variable)
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
            if fileBuffer.plainText then
                begin
                    fileBuffer.plainTextFile := fileOpen (fileBuffer.simulatorFileName, false, false, false, false);
                    if fileBuffer.plainTextFile = InvalidFileHandle then
                        setErrorCode (pab, E_FileError)
                    else if getRecordLength (pab) = 0 then
                        setRecordLength (pab, 80)
                end
            else
                setRecordLength (pab, fileBuffer.recordLength)
        end;
        
    procedure openUpdate (var fileBuffer: TFileBuffer);
        begin
            if fileExists (fileBuffer.simulatorFileName) then
                openInput (fileBuffer)
            else
                createFile (fileBuffer, false)
        end;
        
    procedure openOutput (var fileBuffer: TFileBuffer);
        begin
            createFile (fileBuffer, true);
            if fileBuffer.plainText then
                fileBuffer.plainTextFile := fileOpen (fileBuffer.simulatorFileName, true, true, false, true)
            else
                loadTiFilesContent (fileBuffer)    (* Load and overwrite whatever is in the file *)
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
        filenr := findFile (pab, true, true);
        if filenr <> 0 then
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
        filenr := findFile (pab, false, true);
        if filenr <> 0 then
            with files [filenr] do
                if plaintext then
                    fileClose (plainTextFile)
                else
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
                    vdpTransferBlock (getBufferAddress (pab), fileBuffer.recordLength, fileBuffer.sectors [sectorNumber][sectorOffset], VdpWrite);
                    setNumChars (pab, fileBuffer.recordLength)
                end
        end;
        
    procedure readVariableRecord (var fileBuffer: TFileBuffer);
        var
            length: uint8;
            buf: array [uint8] of char;
            ch: char;
            count: uint8;
        begin
            with fileBuffer do 
                if plainText then
                    begin
                        count := 0;
                        write ('Reading: ');
                        if fileRead (plainTextFile, addr (ch), 1) = 0 then
                            setErrorCode (pab, E_PastEOF)
                        else
                            repeat
                                if (ch <> chr (10)) and (ch <> chr (13)) and (count < getRecordLength (pab)) then
                                    begin
                                        buf [count] := ch;
                                        inc (count);
                                        write (ch)
                                    end
                            until (ch = chr (10)) or (fileRead (plainTextFile, addr (ch), 1) = 0);
                        writeln;
                        vdpTransferBlock (getBufferAddress (pab), count, buf, VdpWrite);
                        setNumChars (pab, count)
                    end
                else
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
                                vdpTransferBlock (getBufferAddress (pab), length, sectors [currentSector, sectorPosition + 1], VdpWrite);
                                inc (sectorPosition, length + 1);
                                setNumChars (pab, length)
                            end
                    end
        end;
            
    var
        filenr: 0..MaxFiles;
        
    begin
        filenr := findFile (pab, false, true);
        if filenr <> 0 then
            begin
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
                    vdpTransferBlock (getBufferAddress (pab), f.recordLength, f.sectors [sectorNumber][sectorOffset], VdpRead);
                    f.activeRecord := getRecordNumber (pab);
                    if f.activeRecord > f.maxRecord then
                        f.maxRecord := f.activeRecord;
                    if sectorNumber > f.maxSector then
                        f.maxSector := sectorNumber
                end
                
        end;
                
    procedure writeVariableRecord (var f: TFileBuffer);
        var
            buf: array [uint8] of char;
        begin
            if f.plainText then
                begin
                    vdpTransferBlock (getBufferAddress (pab), getNumChars (pab), buf, VdpRead);
                    buf [getNumChars (pab)] := chr (10);
                    fileWrite (f.plainTextFile, addr (buf), getNumChars (pab) + 1)
                end
            else 
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
                    vdpTransferBlock (getBufferAddress (pab), getNumChars (pab), f.sectors [f.maxSector][f.sectorPosition + 1], VdpRead);
                    inc (f.sectorPosition, succ (getNumChars (pab)))
            end
        end;

    var
        filenr: 0..MaxFiles;
    begin
        filenr := findFile (pab, false, true);
        if filenr <> 0 then
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
        filenr := findFile (pab, false, true);
        if filenr <> 0 then
            if files [filenr].operationMode = E_Append then
                setErrorCode (pab, E_FileError)
            else
                with files [filenr] do
                    begin
                        if plainText then
                            fileSeek (plainTextFile, 0);
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
        dummy: boolean;
    begin
        fn := makeHostFileName (pab, dummy);
        setErrorCode (pab, E_NoError);
        fillChar (header, sizeof (header), 0);
        loadBlock (header, sizeof (header), 0, fn, false);
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
                loaded := loadBlock (buf, size, sizeof (header) * ord (hasHeader), fn, false);
                if hasHeader and (loaded < size) then
                    writeln ('Got only ', loaded, ' bytes of ', size, ' set as file size in header');
                if loaded = 0  then
                    setErrorCode (pab, E_FileError)
                else
                    vdpTransferBlock (getBufferAddress (pab), size, buf, VdpWrite)
            end
    end;

procedure diskSimDsrSave (var pab: TPab);
    var
        buf: array [0..VdpRAMSize + sizeof (TTiFilesHeader)] of uint8;
        header: TTiFilesHeader absolute buf;
        sectors: uint16;
        dummy: boolean;
    begin
        initTiFilesHeader (header, getFileName (pab));
        sectors := getRecordNumber (pab) div SectorSize;
        header.flags := TiFilesProgram;
        header.eofOffset := getRecordNumber (pab) mod SectorSize;
        if header.eofOffset <> 0 then
            inc (sectors);
        header.totalNumberOfSectors := htons (sectors);
        if getRecordNumber (pab) >= 16384 then
            setErrorCode (pab, E_MemoryFull)
        else
            begin
                vdpTransferBlock (getBufferAddress (pab), getRecordNumber (pab), buf [sizeof (TTiFilesHeader)], VdpRead);
                if saveBlock (buf, sizeof (TTiFilesHeader) + getRecordNumber (pab), makeHostFileName (pab, dummy))  <> sizeof (TTiFilesHeader) + getRecordNumber (pab) then
                    setErrorCode (pab, E_FileError)
            end
    end;
    
procedure diskSimDsrDelete (var pab: TPab);
    var
        filenr: 0..MaxFiles;
        dummy: boolean;
    begin
        filenr := findFile (pab, false, false);
        if filenr <> 0 then
            files [filenr].open := false;
        deleteFile (makeHostFileName (pab, dummy))
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
        dummy: boolean;
        
    function checkFlag (tiFilesFlag: uint8): uint8;
        begin
            checkFlag := ord (header.flags and tiFilesFlag <> 0)
        end;
        
    begin
        filenr := findFile (pab, false, false);
        if filenr = 0 then
            if loadTiFilesHeader (header, makeHostFileName (pab, dummy)) then
                status := PabStatusFileProgram * checkFlag (TiFilesProgram) + PabStatusWriteProtected * checkFlag (TiFilesProtected) +
                          PabStatusFileInternal * checkFlag (TiFilesInternal) + PabStatusFileVariable * checkFlag (TiFilesVariable)
            else 
                status := PabStatusFileNotFound
        else
            with files [filenr] do
                if plainText then
                    status := PabStatusFileVariable or PabStatusEofReached * ord (fileEof (plainTextFile))
                else
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
        vdpTransferBlock (pabAddr, 10, pab, VdpRead);
        vdpTransferBlock (pabAddr + 10, getNameSize (pab), pab.name, VdpRead);
//        dumpPabOperation (pab);
        dsrOperation [getOperation (pab)] (pab);
//        if getOperation (pab) in [E_Open, E_Close] then
            dumpPabOperation (pab);
        vdpTransferBlock (pabAddr, 10, pab, VdpWrite)		// write back changes        
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
        reserveVdpFileBuffers (readMemory ($834c) shr 8, DiskSimCruAddress)
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

procedure initDiskSim (dsrFileName, directory: string; diskSimHostFiles: boolean);
    begin
        loadBlock (dsrRom, sizeof (dsrRom), 0, dsrFileName, true);
        initFileBuffers;
        fileDirectory := directory;
        useHostFiles := diskSimHostFiles
    end;

end.
