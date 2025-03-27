unit rs232card;

interface

uses types;

type
    TIoPort = (RS232_1, RS232_2, PIO_1);
    TIoPortDirection = (PortIn, PortOut);

procedure writeRs232Card (addr, val: uint16);
function readRs232Card (addr: uint16): uint16;

procedure writeRs232CardCru (addr: TCruR12Address; value: TCruBit);
function readRs232CardCru (addr: TCruR12Address): TCruBit;

procedure initRs232Card (dsrFilename: string);
procedure setSerialFileName (serialPort: TIoPort; direction: TIoPortDirection;  filename: string);


implementation

uses cfuncs, tools, cthreads, fileop;

const
    PioMemAddr = $5000;

type 
    TTMS9902 = record
        cruInput: array [0..31] of TCruBit;
        ldctrl, ldir, lrdr, lxdr: boolean;
        dscenb, timenb, xbienb, rienb: boolean;
        brkon, rts, xbre, rbrl: boolean;

        ctrlReg: uint16;        
        intervalReg: uint16;
        rdrReg, xdrReg: uint16;
        transmitBuf, receiveBuf: uint16;
    end;
    TPio = record
        cruData: array [3..7] of TCruBit;
        transmitBuf, receiveBuf: uint8;
        isInput, handshakeIn, handShakeOut: boolean;
    end;
    TIoFile = record
        handle: TFileHandle;
        nozero: boolean
    end;
    
    TTMS9902Devices = RS232_1..RS232_2;
    TTMS9902BitNumber = 0..31;
    TPioBitNumber = 0..7;
        
var
    dsrRom: TDsrRom;
    tms9902: array [TTMS9902Devices] of TTMS9902;
    pio: TPio;
    ioFiles: array [TIoPort, TIoPortDirection] of TIoFile;
    
    serialReadThreadId: TThreadId;
    fds: array [TIoPort] of pollfd;
    rs232Stopped: boolean;
    
procedure outputByte (port: TIoPort; val: uint8);
    begin
        with ioFiles [port, PortOut] do
            if (handle <> InvalidFileHandle) and ((val <> 0) or not nozero)
                then fileWrite (handle, addr (val), 1);
    end;
    
procedure reset (var rs232Device: TTMS9902);
    begin
        with rs232Device do 
            begin
                brkon := false;
                rts := false;
                dscenb := false;
                timenb := false;
                xbienb := false;
                rienb := false;
                ldctrl := true;
                ldir := true;
                lrdr := true;
                lxdr := true;
                xbre := true;
                rbrl := false
            end
    end;
    
procedure writeRegisterBit (var dev: TTMS9902; bit: TTMS9902BitNumber; val: TCruBit);

    procedure setBit (var reg: uint16; var flg: boolean; maxBit: uint8);
        begin
            if bit <= maxBit then
                begin
                    if val = 1 then 
                        reg := reg or (1 shl bit)
                    else
                        reg := reg and not (1 shl bit);
                    if bit = maxBit then
                        flg := false
                end
        end;
            
    var 
        dummy: boolean;

    begin
        with dev do
            begin
                if ldctrl then
                    setBit (ctrlReg, ldctrl, 7)
                else if ldir then
                    setBit (intervalReg, ldir, 7)
                else
                    begin
                        if lrdr then
                            setBit (rdrReg, lrdr, 10);
                        if lxdr then
                            setBit (xdrReg, lxdr, 10)
                    end;
                if not (ldctrl or ldir or lrdr or lxdr) then
                    begin
                        setBit (transmitBuf, dummy, 7);
                        if bit = 7 then
                            xbre := false
                    end
            end
    end;
    
procedure writeRtson (devNr: TTMS9902Devices; var dev: TTMS9902; val: TCruBit);
    begin
        if val = 0 then
            begin
                outputByte (devNr, dev.transmitBuf);
                dev.xbre := true
            end
    end;
    
procedure handleTMS9902Write (devNr: TTMS9902Devices; var dev: TTMS9902; bit: TTMS9902BitNumber; val: TCruBit);
    begin
//        writeln ('RS232 ', devNr, ' bit ', bit, ' <- ', val);
        case bit of
            31:
                reset (dev);
            18:
                begin
                    dev.rienb := val <> 0;
                    dev.rbrl := false
                end;
            16:
                writeRtson (devNr, dev, val);
            14:
                dev.ldctrl := val = 1;
            13:
                dev.ldir := val = 1;
            12:
                dev.lrdr := val = 1;
            11:
                dev.lxdr := val = 1;
            0..10:
                writeRegisterBit (dev, bit, val)
        end
    end;

function handleTMS9902Read (var dev: TTMS9902; bit: TTMS9902BitNumber): TCruBit;
    var
        res: TCruBit;
    begin
        res := 0;
//        write ('RS232 ', (addr (dev) - addr (tms9902)) div sizeof (TTMS9902), ' read bit ', bit, ' returns ');
        case bit of
            27:
                res := 1;	// DSR alway ready
            22:
                res := ord (dev.xbre);
            21:
                res := ord (dev.rbrl);
            0..7:
                res := dev.receiveBuf shr bit and $01
        end;
//        writeln (res);
        handleTMS9902Read := res
    end;

function handlePioRead (bit: TPioBitNumber): TCruBit;
    var
        res: TCruBit;
    begin
//        write ('PIO: read bit ', bit);
        case bit of
            1:
                res := ord (pio.isInput);
            2:
                res := ord (pio.handshakeIn);
            3..7:
                res := pio.cruData [bit]
        end;
//        writeln (' return: ', res);
        handlePioRead := res
    end;

procedure handlePioWrite (bit: TPioBitNumber; val: TCruBit);
    begin
//        writeln ('PIO: bit ', bit, ' <- ', val);
        case bit of
            1:
                pio.isInput := val <> 0;
            2:  
               begin
                   pio.handshakeOut := val <> 0;
                   if not pio.isInput then  
                       begin
                            if val = 0 then
                                outputByte (PIO_1, pio.transmitBuf);
                             pio.handshakeIn := not pio.handshakeOut 	// simulate reply of receiver
                        end;
                end;
             3..7:
                pio.cruData [bit] := val
        end;
    end;
    
function readRs232CardCru (addr: TCruR12Address): TCruBit;
    var
        sel: int32;
    begin
        sel :=  (addr - RS232CruAddress) div 2;
        case sel of
            1..7:
                readRs232CardCru := handlePioRead (sel);
            32..95:
                readRs232CardCru := handleTMS9902Read (tms9902 [TTMS9902Devices ((sel - 32) div 32)], sel mod 32)
            else
                readRs232CardCru := 0
        end
    end;

procedure writeRs232CardCru (addr: TCruR12Address; value: TCruBit);
    var 
        sel: int32;
    begin
        sel := (addr - RS232CruAddress) div 2;
        case sel of
            1..7:
                handlePioWrite (sel, value);
            32..95:
                handleTMS9902Write (TTMS9902Devices ((sel - 32) div 32), tms9902 [TTMS9902Devices ((sel - 32) div 32)], sel mod 32, value)
        end
    end;

procedure writeRs232Card (addr, val: uint16);
    begin
        if addr = PioMemAddr then
            pio.transmitBuf := val shr 8
    end;
        
function readRs232Card (addr: uint16): uint16;
    begin
        if addr = PioMemAddr then
            readRs232Card := pio.receiveBuf shl 8
        else
            readRs232Card := ntohs (dsrRom.w [addr shr 1])
    end;
    
function serialReadThread (data: pointer): ptrint;
    var
        ch: char;
        dev: TIoPort;
        count: integer;
    begin
        writeln ('Started monitoring RS232 inputs');
        repeat
            if poll (addr (fds), succ (ord (PIO_1)), 0) <> 0 then
                for dev := RS232_1 to PIO_1 do
                    if fds [dev].revents and POLLIN <> 0 then
                        case dev of
                            RS232_1..RS232_2:
                                if not tms9902 [dev].rbrl then
                                    begin
                                        fileRead (fds [dev].fd, addr (ch), 1);
                                        tms9902 [dev].receiveBuf := ord (ch);
    //                                    writeln ('Receive buf: ', ch);
                                        tms9902 [dev].rbrl := true
                                   end;
                            PIO_1:
                                begin
                                    pio.handShakeIn := true;
                                    if not pio.handshakeOut then
                                        begin
                                            fileRead (fds [dev].fd, addr (ch), 1);
                                            pio.receiveBuf := ord (ch);
                                            pio.handShakeIn := false;
                                            count := 0;
                                            while not pio.handShakeOut and (count < 10000) do
                                                begin
                                                    inc (count);
                                                    usleep (100)
                                                end
                                        end
                                end
                        end;
            usleep (1000)
        until rs232Stopped;
        writeln ('Stopped monitoring RS232 inputs');
        serialReadThread := 0
    end;
    
procedure initRs232Card (dsrFilename: string);
    begin
        loadBlock (dsrRom, sizeof (dsrRom), 0, dsrFilename);
        beginThread (serialReadThread, nil, serialReadThreadId)
    end;
    
procedure setSerialFileName (serialPort: TIoPort; direction: TIoPortDirection; fileName: string);
    var 
        p: integer;
        options: string;
        optAppend, optNozero: boolean;
    begin
        optAppend := false;
        optNozero := false;
        p := pos (',', fileName);
        if p <> 0 then
            begin
                options := upcase (copy (filename, succ (p), length (filename) - p));
                filename := trim (copy (filename, 1, pred (p)));
                optAppend := pos ('APPEND', options) <> 0;
                optNozero := pos ('NOZERO', options) <> 0
            end;
        with ioFiles [serialPort, direction] do 
            begin
                handle := fileOpen (fileName, true, direction = PortOut, (direction = PortOut) and optAppend, (direction = PortOut) and not optAppend);
                nozero := optNozero;
                if handle = -1 then
                    writeln ('ERROR: Cannot open ', filename, ' for serial/parallel output');
                writeln ('Filename: ', filename, ', port: ', ord (serialPort), ', dir: ', ord (direction));
                if direction = PortIn then
                    begin
                        fds [serialPort].fd := handle;
                        writeln ('Monitoring ', filename, ' as handle ', handle)
                    end
            end
    end;
    
procedure initUnit;
    var 
        i: TIoPort;
    begin
        for i := RS232_1 to PIO_1 do
            begin
                ioFiles [i, PortIn].handle := InvalidFileHandle;
                ioFiles [i, PortOut].handle := InvalidFileHandle;
                fds [i].fd := InvalidFileHandle;
                fds [i].events := POLLIN;
            end;
        rs232Stopped := false
    end;

initialization
    initUnit
    
finalization
    if serialReadThreadId <> 0 then
        begin
            rs232Stopped := true;
            waitForThreadTerminate (serialReadThreadId, 0)
        end

end.
