unit pab;

interface

uses types;

const
    PabStatusFileNotFound = $80;
    PabStatusWriteProtected = $40;
    PabStatusFileInternal = $10;
    PabStatusFileProgram = $08;
    PabStatusFileVariable = $04;
    PabStatusMemoryFull = $02;
    PabStatusEOFReached = $01;

type
    TOperation = (E_Open, E_Close, E_Read, E_Write, E_Rewind, E_Load, E_Save, E_Delete, E_Scratch, E_Status, E_OpenInterrupt, E_UnknowOperation);
    TRecordType = (E_Fixed, E_Variable);
    TDataType = (E_Display, E_Internal);
    TOperationMode = (E_Update, E_Output, E_Input, E_Append);
    TAccessType = (E_Sequential, E_Relative);
    TErrorCode = (E_NoError, E_WriteProtection, E_BadAttribute, E_IllegalOpcode, E_MemoryFull, E_PastEOF, E_DeviceError, E_FileError);

    TPab = record
        operation, errType: uint8;
        vdpBuffer: uint16;
        recLength, numChars: uint8;
        recSize: uint16;
        status, nameSize: uint8;
        name: array [0..255] of char
    end;
    
procedure dumpPabOperation (var pab: TPab);

procedure decodeNames (var pab: TPab; var devName, fileName: string);

function getDeviceName (var pab: TPab): string;
function getFileName (var pab: TPab): string;
function getOperation (var pab: TPab): TOperation;
function getRecordType (var pab: TPab): TRecordType;
function getDataType (var pab: TPab): TDataType;
function getOperationMode (var pab: TPab): TOperationMode;
function getAccessType (var pab: TPab): TAccessType;
function getErrorCode (var pab: TPab): TErrorCode;
function getBufferAddress (var pab: TPab): uint16;
function getRecordLength (var pab: TPab): uint8;
function getNumChars (var pab: TPab): uint8;
function getRecordNumber (var pab: TPab): uint16;
function getFileSize (var pab: TPab): uint16; 	// same as record number
function getStatus (var pab: TPab): uint8;
function getNameSize (var pab: TPab): uint8;

procedure setRecordLength (var pab: TPab; len: uint8);
procedure setNumChars (var pab: TPab; n: uint8);
procedure setErrorCode (var pab: TPab; errorCode: TErrorCode);
procedure setRecordNumber (var pab: TPab; n: uint16);
procedure setStatus (var pab: TPab; status: uint8);

procedure reserveVdpFileBuffers (nFiles: uint8; diskCruBase: TCruR12Address);
    
implementation

uses cfuncs, vdp, memory;

procedure dumpPabOperation (var pab: TPab);    
    const
        operationString: array [TOperation] of string = ('Open', 'Close', 'Read', 'Write', 'Rewind', 'Load', 'Save', 'Delete', 'Scratch', 'Status', 'Open (Interrupt)', 'Unknow Operation');
        recordTypeString: array [TRecordType] of string = ('Fixed', 'Variable');
        dataTypeString: array [TDataType] of string = ('Display', 'Internal');
        operationModeString: array [TOperationMode] of string = ('Update', 'Output', 'Input', 'Append');
        accessTypeString: array [TAccessType] of string = ('Sequential', 'Relative');
        errorCodeString: array [TErrorCode] of string = ('NoError', 'WriteProtection', 'BadAttribute', 'IllegalOpcode', 'MemoryFull', 'PastEOF', 'DeviceError', 'FileError');
    begin
        writeln ('Device:            ', getDeviceName (pab));
        writeln ('File:              ', getFileName (pab));
        writeln ('Operation:         ', operationString [getOperation (pab)]);
        writeln ('Record type:       ', recordTypeString [getRecordType (pab)]);
        writeln ('Data type::        ', dataTypeString [getDataType (pab)]);
        writeln ('Operation mode:    ', operationModeString [getOperationMode (pab)]);
        writeln ('Access type:       ', accessTypeString [getAccessType (pab)]);
        writeln ('Record length      ', getRecordLength (pab));
        writeln ('Number of char:    ', getNumChars (pab));
        writeln ('Recod #/File size: ', getRecordNumber (pab));
        writeln ('Status:            ', getStatus (pab));
        writeln ('Error code:        ', errorCodeString [getErrorCode (pab)]);
        writeln
    end;
    
procedure decodeNames (var pab: TPab; var devName, fileName: string);
    var
        i: uint8;
        pointFound: boolean;
    begin
        devName := '';
        fileName := '';
        pointFound := false;
        for i := 0 to pred (pab.nameSize) do
            if pointFound then
                fileName := fileName + pab.name [i]
            else if pab.name [i] <> '.' then
                devName := devName + pab.name [i]
            else
                pointFound := true
    end;
  
function getDeviceName (var pab: TPab): string;
    var
        devName, fileName: string;
    begin
        decodeNames (pab, devName, fileName);
        getDeviceName := devName
    end;
    
function getFileName (var pab: TPab): string;
    var
        devName, fileName: string;
    begin
        decodeNames (pab, devName, fileName);
        getFileName := fileName;
    end;

function getOperation (var pab: TPab): TOperation;
    begin
        if pab.operation = $80 then
            getOperation := E_OpenInterrupt	// Special open for original RS232 DSR
        else if pab.operation <= ord (E_Status) then
            getOperation := TOperation (pab.operation)
        else
            getOperation := E_UnknowOperation
    end;
    
function getRecordType (var pab: TPab): TRecordType;
    begin
        getRecordType := TRecordType (ord (pab.errType and $10 <> 0))
    end;
    
function getDataType (var pab: TPab): TDataType;
    begin
        getDataType := TDataType (ord (pab.errType and $08 <> 0))
    end;

function getOperationMode (var pab: TPab): TOperationMode;
    begin
        getOperationMode := TOperationMode ((pab.errType shr 1) and $03)
    end;
        
function getAccessType (var pab: TPab): TAccessType;
    begin
        getAccessType := TAccessType (odd (pab.errType))
    end;
    
function getErrorCode (var pab: TPab): TErrorCode;
    begin
        getErrorCode := TErrorCode (pab.errType shr 5)
    end;
    
function getBufferAddress (var pab: TPab): uint16;
    begin
        getBufferAddress := ntohs (pab.vdpBuffer)
    end;
    
function getRecordLength (var pab: TPab): uint8;
    begin
        getRecordLength := pab.recLength
    end;
    
function getNumChars (var pab: TPab): uint8;
    begin
        getNumChars := pab.numChars
    end;
    
function getRecordNumber (var pab: TPab): uint16;
    begin
        getRecordNumber := ntohs (pab.recSize)
    end;
    
function getFileSize (var pab: TPab): uint16;
    begin
        getFileSize := getRecordNumber (pab)
    end;
    
function getStatus (var pab: TPab): uint8;
    begin
        getStatus := pab.status
    end;
    
function getNameSize (var pab: TPab): uint8;
    begin
        getNameSize := pab.nameSize
    end;
    
procedure setRecordLength (var pab: TPab; len: uint8);
    begin
        pab.recLength := len
    end;

procedure setNumChars (var pab: TPab; n: uint8);
    begin
        pab.numChars := n
    end;

procedure setErrorCode (var pab: TPab; errorCode: TErrorCode);
    begin
        pab.errType := (pab.errType and $1F) or (ord (errorCode) shl 5)
    end;
    
procedure setRecordNumber (var pab: TPab; n: uint16);
    begin
        pab.recSize := htons (n)
    end;    
    
procedure setStatus (var pab: TPab; status: uint8);
    begin
        pab.status := status
    end;

procedure reserveVdpFileBuffers (nFiles: uint8; diskCruBase: TCruR12Address);
    const
        fileBufferAreaHeader: array [1..5] of uint8 = ($aa, $3f, $ff, 0, 0);
    var
        fileBufferBegin: uint16;
    begin
        if nFiles in [1..16] then
            begin
                fileBufferBegin := $3DEF - nFiles * 518 - 5;
                writeMemory ($8370, fileBufferBegin - 1);
                fileBufferAreaHeader [4] := diskCruBase shr 8;
                fileBufferAreaHeader [5] := nFiles;
                vdpTransferBlock (fileBufferBegin, sizeof (fileBufferAreaHeader), fileBufferAreaHeader, VdpWrite);
                writeMemory ($8350, readMemory ($8350) and $00ff)
            end
        else
            writeMemory ($8350, readMemory ($8350) and $00ff or $0200) // TODO: Bad attribute - check if correct error code
    end;
    
end.
