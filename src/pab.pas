unit pab;

interface

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
    TPabPtr = ^TPab;
    
procedure dumpPabOperation (pab: TPabPtr);

procedure decodeNames (pab: TPabPtr; var devName, fileName: string);

function getDeviceName (pab: TPabPtr): string;
function getFileName (pab: TPabPtr): string;
function getOperation (pab: TPabPtr): TOperation;
function getRecordType (pab: TPabPtr): TRecordType;
function getDataType (pab: TPabPtr): TDataType;
function getOperationMode (pab: TPabPtr): TOperationMode;
function getAccessType (pab: TPabPtr): TAccessType;
function getErrorCode (pab: TPabPtr): TErrorCode;
function getBufferAddress (pab: TPabPtr): uint16;
function getRecordLength (pab: TPabPtr): uint8;
function getNumChars (pab: TPabPtr): uint8;
function getRecordNumber (pab: TPabPtr): uint16;
function getFileSize (pab: TPabPtr): uint16; 	// same as record number
function getStatus (pab: TPabPtr): uint8;

procedure setRecordLength (pab: TPabPtr; len: uint8);
procedure setNumChars (pab: TPabPtr; n: uint8);
procedure setErrorCode (pab: TPabPtr; errorCode: TErrorCode);
procedure setRecordNumber (pab: TPabPtr; n: uint16);
procedure setStatus (pab: TPabPtr; status: uint8);

    
implementation

uses cfuncs;

procedure dumpPabOperation (pab: TPabPtr);    
    const
        operationString: array [TOperation] of string = ('Open', 'Close', 'Read', 'Write', 'Rewind', 'Load', 'Save', 'Delete', 'Scratch', 'Status', 'Open (Interrupt)', 'Unknow Operation');
        recordTypeString: array [TRecordType] of string = ('Fixed', 'Variable');
        dataTypeString: array [TDataType] of string = ('Display', 'Internal');
        operationModeString: array [TOperationMode] of string = ('Update', 'Output', 'Input', 'Append');
        accessTypeString: array [TAccessType] of string = ('Sequential', 'Relative');
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
        writeln ('Error code:        ', getErrorCode (pab));
        writeln
    end;
    
procedure decodeNames (pab: TPabPtr; var devName, fileName: string);
    var
        i: uint8;
        pointFound: boolean;
    begin
        devName := '';
        fileName := '';
        pointFound := false;
        for i := 0 to pred (pab^.nameSize) do
            if pointFound then
                fileName := fileName + pab^.name [i]
            else if pab^.name [i] <> '.' then
                devName := devName + pab^.name [i]
            else
                pointFound := true
    end;
  
function getDeviceName (pab: TPabPtr): string;
    var
        devName, fileName: string;
    begin
        decodeNames (pab, devName, fileName);
        getDeviceName := devName
    end;
    
function getFileName (pab: TPabPtr): string;
    var
        devName, fileName: string;
    begin
        decodeNames (pab, devName, fileName);
        getFileName := fileName;
    end;

function getOperation (pab: TPabPtr): TOperation;
    begin
        if pab^.operation = $80 then
            getOperation := E_OpenInterrupt	// Special open for original RS232 DSR
        else if pab^.operation <= ord (E_Status) then
            getOperation := TOperation (pab^.operation)
        else
            getOperation := E_UnknowOperation
    end;
    
function getRecordType (pab: TPabPtr): TRecordType;
    begin
        getRecordType := TRecordType (ord (pab^.errType and $10 <> 0))
    end;
    
function getDataType (pab: TPabPtr): TDataType;
    begin
        getDataType := TDataType (ord (pab^.errType and $08 <> 0))
    end;

function getOperationMode (pab: TPabPtr): TOperationMode;
    begin
        getOperationMode := TOperationMode ((pab^.errType shr 1) and $03)
    end;
        
function getAccessType (pab: TPabPtr): TAccessType;
    begin
        getAccessType := TAccessType (odd (pab^.errType))
    end;
    
function getErrorCode (pab: TPabPtr): TErrorCode;
    begin
        getErrorCode := TErrorCode (pab^.errType shr 5)
    end;
    
function getBufferAddress (pab: TPabPtr): uint16;
    begin
        getBufferAddress := ntohs (pab^.vdpBuffer)
    end;
    
function getRecordLength (pab: TPabPtr): uint8;
    begin
        getRecordLength := pab^.recLength
    end;
    
function getNumChars (pab: TPabPtr): uint8;
    begin
        getNumChars := pab^.numChars
    end;
    
function getRecordNumber (pab: TPabPtr): uint16;
    begin
        getRecordNumber := ntohs (pab^.recSize)
    end;
    
function getFileSize (pab: TPabPtr): uint16;
    begin
        getFileSize := getRecordNumber (pab)
    end;
    
function getStatus (pab: TPabPtr): uint8;
    begin
        getStatus := pab^.status
    end;
    
procedure setRecordLength (pab: TPabPtr; len: uint8);
    begin
        pab^.recLength := len
    end;

procedure setNumChars (pab: TPabPtr; n: uint8);
    begin
        pab^.numChars := n
    end;

procedure setErrorCode (pab: TPabPtr; errorCode: TErrorCode);
    begin
        pab^.errType := (pab^.errType and $1F) or (ord (errorCode) shl 5)
    end;
    
procedure setRecordNumber (pab: TPabPtr; n: uint16);
    begin
        pab^.recSize := htons (n)
    end;    
    
procedure setStatus (pab: TPabPtr; status: uint8);
    begin
        pab^.status := status
    end;
    
end.
