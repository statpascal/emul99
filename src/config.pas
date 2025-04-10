unit config;

interface

procedure loadConfig (fn: string);

function usePcode80: boolean;
function getWindowScaleHeight: uint8;
function getWindowScaleWidth: uint8;

function getCpuFrequency: int64;
function getCycleTime: int64;
function getDefaultCpuFrequency: int64;
procedure setCpuFrequency (freq: int64);

implementation

uses memory, tms9900, fdccard, rs232card, disksim, tape, pcodecard, pcodedisk, tipi, tools, sysutils;

var 
    pcode80: boolean;
    scaleWidth, scaleHeight: uint8;
    cartBank, pcodeGromCount: uint8;
    diskDsr: string;
    pcodeRomFilenames: TPcodeRomFilenames;
    cpuFrequency, defaultCpuFrequency, cycleTime: int64;

procedure loadConfigFile (fn: string; level: uint8);
    type
        TKeyType = (CpuFreq, Mem32KExt, MemExt, ConsoleRom, ConsoleGroms, CartRom, CartGroms, DiskSimDsr, DiskSimDir, FdcDsr, FdcDisk1, FdcDisk2, FdcDisk3, PcodeDsrLow, PCodeDsrHigh, PCodeGrom, PCodeScreen80, PcodeDiskDsr, PcodeDisk1, PcodeDisk2, PcodeDisk3, CartMiniMem, CartInverted, CassIn, CassOut, WindowScaleWidth, WindowScaleHeight, 
                    SerialDsr, RS232Dsr, SerialPort1In, SerialPort2In, ParallelPort1In, SerialPort1Out, SerialPort2Out, ParallelPort1Out, TipiDsr, TipiAddr, Invalid);
    const
         keyTypeMap: array [TKeyType] of string = 
             ('cpu_freq', 'mem_32k_ext', 'mem_ext', 'console_rom', 'console_groms', 'cart_rom', 'cart_groms', 'disksim_dsr', 'disksim_dir', 'fdc_dsr', 'fdc_dsk1', 'fdc_dsk2', 'fdc_dsk3', 'pcode_dsrlow', 'pcode_dsrhigh', 'pcode_grom', 'pcode_screen80', 'pcodedisk_dsr', 'pcodedisk_dsk1', 'pcodedisk_dsk2', 'pcodedisk_dsk3', 'cart_minimem', 'cart_inverted', 'cass_in', 'cass_out', 'window_scale_width', 'window_scale_height', 
              'serial_dsr', 'rs232_dsr', 'RS232/1_in', 'RS232/2_in', 'PIO/1_in', 'RS232/1_out', 'RS232/2_out', 'PIO/1_out', 'tipi_dsr', 'tipi_addr', '');
        MaxConfigLevel = 10;
        
    procedure evaluateKey (key, value, path: string);
        var
            n: int64;
            code: uint16;
            keyType: TKeyType;
            
        function findKey (s: string): TKeyType;
            var
                kt: TKeyType;
            begin
                kt := CpuFreq;
                while (kt <> Invalid) and (s <> upcase (keyTypeMap [kt])) do
                    inc (kt);
                findKey := kt
            end;

        begin
  	    val (value, n, code);
	    keyType := findKey (upcase (key));
            case keyType of
                CpuFreq:
                    begin
                        defaultCpuFrequency := n;
                        setCpuFrequency (defaultCpuFrequency)
                    end;
                Mem32KExt, MemExt:
                    if n in [1, 2] then
                        configureMemoryKExtension (n = 1);
                ConsoleRom: 
                    loadConsoleRom (path);
                ConsoleGroms:
                    loadConsoleGroms (path);
                CartRom:
                    begin
                        loadCartROM (cartBank, path);
                        inc (cartBank)
                    end;
                CartGroms:
                    loadCartGROM (path);
                DiskSimDsr:
                     diskDsr := path;
                DiskSimDir:
                     if diskDsr <> '' then
                         initDiskSim (diskDsr, path)
                     else
                         writeln ('disksim_dir specified without valid disksim_dsr value');
                FdcDsr:
                    fdcInitCard (path);
                FdcDisk1..FdcDisk3:
                    fdcSetDiskImage (succ (ord (keyType) - ord (FdcDisk1)), path);
                PcodeDsrLow: 
                    pcodeRomFilenames.dsrLow := path;
                PcodeDsrHigh:
                    pcodeRomFilenames.dsrHigh := path;
                PcodeGrom:
                    begin
                        if pcodeGromCount < 8 then
                            pcodeRomFilenames.groms [pcodeGromCount] := path;
                        inc (pcodeGromCount)
                    end;
                PcodeScreen80:
                    pcode80 := n = 1;
                PcodeDiskDsr:
                    initPcodeDisk (path);
                PcodeDisk1..PcodeDisk3:
                    pcodeDiskSetDiskImage (succ (ord (keyType) - ord (PcodeDisk1)), path);
                CartMiniMem:
                    if n = 1 then
                        configureMiniMemory;
                CartInverted:
                    setCartROMInverted (n = 1);
                CassIn:
                    setCassetteInput (path);
                CassOut:
                    setCassetteOutput (path);
                WindowScaleWidth:
                    scaleWidth := n;
                WindowScaleHeight:
                    scaleHeight := n;
                SerialDsr:
                    writeln ('Error: Simulated RS232 card is no longer supported - please switch to rs232_dsr');
                RS232Dsr:
                    initRs232Card (path);
                SerialPort1In..ParallelPort1In:
                    setSerialFileName (TIoPort (ord (keyType) - ord (SerialPort1In)), PortIn, path);
                SerialPort1Out..ParallelPort1Out:
                        setSerialFileName (TIoPort (ord (keyType) - ord (SerialPort1Out)), PortOut, path);
                TipiDsr:
                    loadTipiDsr (path);
                TipiAddr:
                    initTipi (value);
                Invalid:
                    writeln ('Invalid config entry: ', key, ' = ', value)
            end;
        end;
        
        procedure evaluateLine (dir, s: string);
            var 
                p: int64;
                key, value, path: string;
            begin
                p := pos ('=', s);
                if p <> 0 then
                    begin
                        key := trim (copy (s, 1, pred (p)));
                        value := trim (copy (s, succ (p), length (s) - p));
                        if (key <> '') and (value <> '') then 
                            begin
                                if value [1] <> '/' then
                                    path := dir + value
                                else
                                    path := value;
                                if upcase (key) = 'INCLUDE' then
                                    loadConfigFile (path, succ (level))
                                else
                                    evaluateKey (key, value, path)
                            end
                    end
            end;
        
    var
        f: text;
        s, dir: string;
        i: integer;
        
    begin
        if not fileExists (fn) then
            errorExit ('config file ' + fn + ' not found');
        if level > maxConfigLevel then
            errorExit ('Configuration files nested too deep - recursive inclusion?');
        dir := extractFilePath (fn);
        
        assign (f, fn);
        reset (f);
        while not eof (f) do
            begin
                readln (f, s);
                if (s <> '') and (s [1] <> ';') then
                    evaluateLine (dir, s)
            end;
        close (f);
        
        if level = 1 then
            for i := 2 to ParamCount do
                evaluateLine (dir, ParamStr (i));
        
        if (pcodeGromCount = 8) and (pcodeRomFilenames.dsrLow <> '') and (pcodeRomFilenames.dsrHigh <> '') then
            initPCodeCard (pcodeRomFilenames)
    end;    

procedure loadConfig (fn: string);    
    begin
        pcode80 := false;
        scaleWidth := 3;
        scaleHeight := 3;
        cartBank := 0;
        pcodeGromCount := 0;
        diskDsr := '';
        pcodeRomFilenames.dsrLow := '';
        pcodeRomFilenames.dsrHigh := '';
        loadConfigFile (fn, 1)
    end;
    
function usePcode80: boolean;
    begin
        usePcode80 := pcode80
    end;
    
function getWindowScaleHeight: uint8;
    begin
        getWindowScaleHeight := scaleHeight
    end;
    
function getWindowScaleWidth: uint8;
    begin
        getWindowScaleWidth := scaleWidth
    end;
    
function getCpuFrequency: int64;
    begin
        getCpuFrequency := cpuFrequency
    end;
    
function getCycleTime: int64;
    begin
        getCycleTime := cycleTime
    end;
    
function getDefaultCpuFrequency: int64;
    begin
        getDefaultCpuFrequency := defaultCpuFrequency
    end;
    
procedure setCpuFrequency (freq: int64);
    begin
        cpuFrequency := freq;
        cycleTime := (1000 * 1000 * 1000) div cpuFrequency;
        writeln ('CPU frequency set to ', cpuFrequency, ' Hz')
    end;
    

end.
