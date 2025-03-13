unit serial;

// Work in progress
// - Read should not block because the CPU cycle count/real time are completely out of sync and interrupts are not served
// - Load/Save not yet implemented
// - Reading incomplete

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

    
implementation

uses vdp, memory, tms9901, pab, tools, fileop, cfuncs;

type
    TSerialModifiers = record
        ba: (_110, _300, _600, _1200, _2400, _4800, _9600);
        da: (_7, _8);
        pa: (_N, _E, _O);
        tw, ch, cr, lf, ec, nu: boolean
    end;

var
    dsrRom: TDsrRom;
    serialFiles: array [TSerialPort, TSerialPortDirection] of TFileHandle;
    
procedure serialSimPowerup;
    begin
    end;
    
procedure parseSerialModifiers (var pab: TPab; var modifiers: TSerialModifiers; var serialPort: TSerialPort);
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
    
procedure openSerialPort (var pab: TPab);
    begin
        if getRecordLength (pab) = 0 then
            setRecordLength (pab, 80);
        if getAccessType (pab) = E_Relative then
            setErrorCode (pab, E_BadAttribute);
        setRecordNumber (pab, 0);
    end;
    
procedure writeSerialPort (var pab: TPab; modifiers: TSerialModifiers; handle: TFileHandle);
    const
        displayBytes: array [1..8] of uint8 = ($0d, $0a, 0, 0, 0, 0, 0, 0);
    var
        buf: array [0..255] of uint8;
    begin
        if handle = InvalidFileHandle then
            setErrorCode (pab, E_DeviceError)
        else
            begin
                if getDataType (pab) = E_Internal then
                    fileWrite (handle, addr (pab.numChars), 1);
                vdpTransferBlock (getBufferAddress (pab), getNumChars (pab), buf, VdpRead);
                fileWrite (handle, addr (buf), getNumChars (pab));
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
        checkClearKey := readKeyboard (7, 0) and  readKeyboard (7, 3)	// FCTN + 4
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
        
procedure readSerialPort (var pab: TPab; modifiers: TSerialModifiers; handle: TFileHandle);
    var
        count, numChars, ch: uint8;
        done: boolean;
        buf: array [0..255] of uint8;
    begin
        if handle = InvalidFileHandle then
            setErrorCode (pab, E_DeviceError)
        else
            begin
                if getDataType (pab) = E_Internal then
                    readPort (handle, ch)	// TODO: numchars?
                else
                    numChars := getRecordLength (pab);
                done := false; 
                count := 0;
                while (count < numChars) and not done do
                    if readPort (handle, ch) = DataRead then
                        begin
                            buf [count] := ch;
                            inc (count)
                        end
                    else
                        begin
                            setErrorCode (pab, E_DeviceError);
                            pab.status := pab.status or PabStatusEOFReached;
                            done := true
                        end;
                vdpTransferBlock (getBufferAddress (pab), count, buf, VdpWrite);
                setNumChars (pab, count)
            end
    end;
    
(*$POINTERMATH ON*)    
procedure serialSimDSR;
    var
        pab: TPab;
        pabaddr: uint16;
        modifiers: TSerialModifiers;
        serialPort: TSerialPort;
    begin
        pabAddr := uint16 (readMemory ($8356) - (readMemory ($8354) and $ff) - 10);
        vdpTransferBlock (pabAddr, 10, pab, VdpRead);
        vdpTransferBlock (pabAddr + 10, getNameSize (pab), pab.name, VdpRead);

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
                begin
                    if serialFiles [serialPort, PortOut] = -1 then
                        writeln ('ERROR: No output file assigned to device ', getDeviceName (pab));
                    writeSerialPort (pab, modifiers, serialFiles [serialPort, PortOut])
                end;
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
        end;
        vdpTransferBlock (pabAddr, 10, pab, VdpWrite)        // write back changes 
    end;
    
function readSerial (addr: uint16): uint16;
    begin
        readSerial := ntohs (dsrRom.w [addr shr 1])
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
        serialFiles [serialPort, direction] := fileOpen (fileName, true, direction = PortOut);
        if serialFiles [serialPort, direction] = -1 then
            writeln ('ERROR: Cannot open ', filename, ' for serial/parallel output')
    end;
    
end.
