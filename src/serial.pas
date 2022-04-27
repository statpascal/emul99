unit serial;

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

uses vdp, memory, pab, tools, cfuncs, sysutils;

type
    TSerialModifiers = record
        ba: (_110, _300, _600, _1200, _2400, _4800, _9600);
        da: (_7, _8);
        pa: (_N, _E, _O);
        tw, ch, cr, lf, ec, nu: boolean
    end;
    TSerialFile = record
        fd: int32;
        fn: string
    end;

var
    dsrRom: array [$4000..$5fff] of uint8;
    dsrRomW: array [$2000..$2fff] of uint16 absolute dsrRom;
    
    serialFiles: array [TSerialPort, TSerialPortDirection] of TSerialFile;
    
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
    
procedure writeSerialPort (pab: TPabPtr; modifiers: TSerialModifiers; serialPort: TSerialPort);
    const
        displayBytes: array [1..8] of uint8 = ($0d, $0a, 0, 0, 0, 0, 0, 0);
    begin
        with serialFiles [serialPort, PortOut] do
            if fd = -1 then
                setErrorCode (pab, E_DeviceError)
            else
                begin
                    if getDataType (pab) = E_Internal then
                        fdwrite (fd, addr (pab^.numChars), 1);
                    fdwrite (fd, getVdpRamPtr (getBufferAddress (pab)), getNumChars (pab));
                    if (getDataType (pab) = E_Display) and (getRecordType (pab) = E_Variable) then 
                         begin
                            if not modifiers.cr then
                                fdwrite (fd, addr (displayBytes [1]), 1);
                            if modifiers.nu then
                                fdwrite (fd, addr (displayBytes [3]), 6);
                            if not modifiers.lf then
                                fdwrite (fd, addr (displayBytes [2]), 1)
                        end
                end
    end;
    
procedure readSerialPort (pab: TPabPtr; modifiers: TSerialModifiers; serialPort: TSerialPort);
    var
        count, numChars, ch: uint8;
        done: boolean;
        vdpBuffer: TMemoryPtr;
    begin
        with serialFiles [serialPort, PortIn] do
            if fd = -1 then
                setErrorCode (pab, E_DeviceError)
            else
                begin
                    if getDataType (pab) = E_Internal then
                        fdread (fd, addr (numChars), 1)
                    else
                        numChars := getRecordLength (pab);
                    vdpBuffer := getVdpRamPtr (getBufferAddress (pab));
                    done := false; 
                    count := 0;
                    while (count < numChars) and not done do
                        if fdread (fd, addr (ch), 1) > 0 then
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
                    setNumChars (pab, count);
//                    setRecordNumber (pab, succ (getRecordNumber (pab)))
                end;
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
                writeSerialPort (pab, modifiers, serialPort);
            E_Read:
                readSerialPort (pab, modifiers, serialPort);
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
        load (dsrRom, sizeof (dsrRom), dsrFilename);
        for i := RS232_1 to PIO_2 do
            for j := PortIn to PortOut do
                serialFiles [i, j].fd := -1
    end;
    
procedure setSerialFileName (serialPort: TSerialPort; direction: TSerialPortDirection; filename: string);
    begin
        with serialFiles [serialPort, direction] do
            begin
                fn := filename;
                fd := open (addr (fn [1]), O_RDWR or O_CREAT)
            end
    end;
    
end.
