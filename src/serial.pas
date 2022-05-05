unit serial;

// Work in progress
// - Read should not block because the CPU cycle count/real time are completely out of sync and interrupts are not served
// - Load/Save not yet implemented

interface

uses types;

type
    TSerialPort = (RS232_1, RS232_2, RS232_3, RS232_4, PIO_1, PIO_2);
    TSerialPortDirection = (PortIn, PortOut);
    
procedure serialSimPowerup;
procedure serialSimDSR;

function readSerial (addr: uint16): uint16;

procedure initSerial (dsrFilename: string);
procedure setSerialFileName (serialPort: TSerialPort; direction: TSerialPortDirection;  filename: string);

const
    SerialSimCruAddress = $1500;
    
    
implementation

uses vdp, memory, keyboard, pab, tools, fileop, cfuncs;

type
    TSerialModifiers = record
        ba: (_110, _300, _600, _1200, _2400, _4800, _9600);
        da: (_7, _8);
        pa: (_N, _E, _O);
        tw, ch, cr, lf, ec, nu: boolean
    end;

var
    dsrRom: array [$4000..$5fff] of uint8;
    dsrRomW: array [$2000..$2fff] of uint16 absolute dsrRom;
    
    serialFiles: array [TSerialPort, TSerialPortDirection] of TFileHandle;
    
procedure serialSimPowerup;
    begin
    end;
    
procedure parseSerialModifiers (pab: TPabPtr; var modifiers: TSerialModifiers; var serialPort: TSerialPort);
    const
        NumDevices = 8;
        DeviceNames: array [1..NumDevices] of record name: string; out: TSerialPort end = (
            (name: 'RS232/1'; out: RS232_1), (name: 'RS232/2'; out: RS232_2), (name: 'RS232/3'; out: RS232_3), (name: 'RS232/4'; out: RS232_4),
            (name: 'RS232';   out: RS232_1), (name: 'PIO/1';   out: PIO_1),   (name: 'PIO/2';   out: PIO_2),   (name: 'PIO';     out: PIO_1)
        );
    var
        i: 1..NumDevices;
        devName, fileName: string;
    begin
        decodeNames (pab, devName, fileName);
        fileName := upcase (fileName);
        with modifiers do begin
            ba := _300;
            da := _7;
            pa := _O;
            tw := pos ('.TW', fileName) <> 0;
            ch := pos ('.CH', fileName) <> 0;
            cr := pos ('.CR', fileName) <> 0;
            lf := pos ('.LF', fileName) <> 0;
            nu := pos ('.NU', fileName) <> 0
        end;
        for i := 1 to NumDevices do
            if devName = DeviceNames [i].name then
                serialPort := DeviceNames [i].out
    end;
    
procedure openSerialPort (pab: TPabPtr);
    begin
        if getRecordLength (pab) = 0 then
            setRecordLength (pab, 80);
        if getAccessType (pab) = E_Relative then
            setErrorCode (pab, E_BadAttribute);
        setRecordNumber (pab, 0);
    end;
    
procedure writeSerialPort (pab: TPabPtr; modifiers: TSerialModifiers; handle: TFileHandle);
    const
        displayBytes: array [1..8] of uint8 = ($0d, $0a, 0, 0, 0, 0, 0, 0);
    begin
        if handle = InvalidFileHandle then
            setErrorCode (pab, E_DeviceError)
        else
            begin
                if getDataType (pab) = E_Internal then
                    fileWrite (handle, addr (pab^.numChars), 1);
                fileWrite (handle, getVdpRamPtr (getBufferAddress (pab)), getNumChars (pab));
                if (getDataType (pab) = E_Display) and (getRecordType (pab) = E_Variable) then 
                    begin
                        if not modifiers.cr then
                            fileWrite (handle, addr (displayBytes [1]), 1);
                        if modifiers.nu then
                            fileWrite (handle, addr (displayBytes [3]), 6);
                        if not modifiers.lf then
                            fileWrite (handle, addr (displayBytes [2]), 1)
                    end
            end
    end;
    
function checkClearKey: boolean;
    begin
        checkClearKey := not readKeyBoard (7, 0) and not readKeyBoard (7, 3)	// FCTN + 4
    end;
    
type
    TPortStatus = (DataRead, EndOfFile, ClearPressed);
    
function readPort (handle: TFileHandle; var ch: uint8): TPortStatus;
    var
        done: boolean;
    begin
        repeat
            done := true;
            if filePollIn (handle, 100) then
                if fileRead (handle, addr (ch), 1) = 1 then
                    readPort := DataRead
                else
                    readPort := EndOfFile
            else if checkClearKey then
                readPort := ClearPressed
            else
                done := false;
        until done
    end;
        
procedure readSerialPort (pab: TPabPtr; modifiers: TSerialModifiers; handle: TFileHandle);
    var
        count, numChars, ch: uint8;
        done: boolean;
        vdpBuffer: TMemoryPtr;
    begin
        if handle = InvalidFileHandle then
            setErrorCode (pab, E_DeviceError)
        else
            begin
                if getDataType (pab) = E_Internal then
                    readPort (handle, ch)
                else
                    numChars := getRecordLength (pab);
                vdpBuffer := getVdpRamPtr (getBufferAddress (pab));
                done := false; 
                count := 0;
                while (count < numChars) and not done do
                    if readPort (handle, ch) = DataRead then
                        begin
                            vdpBuffer^ := ch;
                            inc (vdpBuffer);
                            inc (count)
                        end
                    else
                        begin
                            setErrorCode (pab, E_DeviceError);
                            pab^.status := pab^.status or PabStatusEOFReached;
                            done := true
                        end;
                setNumChars (pab, count)
            end
    end;
    
(*$POINTERMATH ON*)    
procedure serialSimDSR;
    var
        pab: TPabPtr;
        modifiers: TSerialModifiers;
        serialPort: TSerialPort;
    begin
        pab := TPabPtr (getVdpRamPtr (readMemory ($8356) - readMemory ($8354) - 10));
        setErrorCode (pab, E_NoError);
        setStatus (pab, 0);
        parseSerialModifiers (pab, modifiers, serialPort);

        case getOperation (pab) of
            E_OpenInterrupt:
                begin
                    writeln ('Device ', getDeviceName (pab), ' interrupt generation not yet implemented. Input will probably fail.');
                    openSerialPort (pab)
                end;
            E_Open:
                openSerialPort (pab);
            E_Write:
                writeSerialPort (pab, modifiers, serialFiles [serialPort, PortOut]);
            E_Read:
                readSerialPort (pab, modifiers, serialFiles [serialPort, PortIn]);
            E_Close:
                ;
            e_Load:
                ;
            E_Save:
                ;
            else
                setErrorCode (pab, E_IllegalOpcode)
        end                
    end;
    
function readSerial (addr: uint16): uint16;
    begin
        readSerial := htons (dsrRomW [addr shr 1])
    end;

procedure initSerial (dsrFilename: string);
    var 
        i: TSerialPort;
        j: TSerialPortDirection;
    begin
        loadBlock (dsrRom, sizeof (dsrRom), 0, dsrFilename);
        for i := RS232_1 to PIO_2 do
            for j := PortIn to PortOut do
                serialFiles [i, j] := -1
    end;
    
procedure setSerialFileName (serialPort: TSerialPort; direction: TSerialPortDirection; fileName: string);
    begin
        serialFiles [serialPort, direction] := fileOpen (fileName, true, direction = PortOut)
    end;
    
end.
