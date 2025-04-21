unit config;

interface

type TPCode80Screen = (PCode80_None, PCode80_Only, PCode80_Both);

procedure loadConfig;

function usePcode80: TPcode80Screen;
function getWindowScaleHeight: uint8;
function getWindowScaleWidth: uint8;
function getResetKey: integer;

function getCpuFrequency: int64;
function getCycleTime: int64;
function getDefaultCpuFrequency: int64;
procedure setCpuFrequency (freq: int64);

implementation

uses memory, tms9900, fdccard, rs232card, disksim, tape, pcodecard, pcodedisk, tipi, tools, sysutils, types;

var 
    pcode80: TPCode80Screen;
    scaleWidth, scaleHeight, memExtension: uint8;
    cartBanks, currentBank, pcodeGromCount: uint8;
    consoleRomFile, consoleGromFile: string;
    diskSimDsrPath, diskSimDirPath: string;
    fdcDsrPath, pcodeDiskDsrPath: string;
    fdcDiskImage, pcodeDiskImage: array [TDiskDrive] of string;
    rs232DsrPath: string;
    rs232FileNames: array [TIoPort, TIoPortDirection] of string;
    cartRoms: array [uint8] of string;
    cartGrom: string;
    tipiDsrPath, tipiWsUrl: string;
    cassInPath, cassOutPath: string;
    useMiniMem: boolean;
    resetKey: integer;
    
    pcodeRomFilenames: TPcodeRomFilenames;
    cpuFrequency, defaultCpuFrequency, cycleTime: int64;

procedure evaluateKey (key, value, path: string; var success: boolean);
    type
        TKeyType = (CpuFreq, Mem32KExt, MemExt, ConsoleRom, ConsoleGroms, CartRom, CartGroms, DiskSimDsr, DiskSimDir, FdcDsr, FdcDisk1, FdcDisk2, FdcDisk3, PcodeDsrLow, PCodeDsrHigh, PCodeGrom, PCodeScreen80, PcodeDiskDsr, PcodeDisk1, PcodeDisk2, PcodeDisk3, CartMiniMem, CartInverted, CassIn, CassOut, WindowScaleWidth, WindowScaleHeight, 
                    SerialDsr, RS232Dsr, SerialPort1In, SerialPort2In, ParallelPort1In, SerialPort1Out, SerialPort2Out, ParallelPort1Out, TipiDsr, TipiAddr, ResetCode, Invalid);
    const
         keyTypeMap: array [TKeyType] of string = 
             ('cpu_freq', 'mem_32k_ext', 'mem_ext', 'console_rom', 'console_groms', 'cart_rom', 'cart_groms', 'disksim_dsr', 'disksim_dir', 'fdc_dsr', 'fdc_dsk1', 'fdc_dsk2', 'fdc_dsk3', 'pcode_dsrlow', 'pcode_dsrhigh', 'pcode_grom', 'pcode_screen80', 'pcodedisk_dsr', 'pcodedisk_dsk1', 'pcodedisk_dsk2', 'pcodedisk_dsk3', 'cart_minimem', 'cart_inverted', 'cass_in', 'cass_out', 'window_scale_width', 'window_scale_height', 
              'serial_dsr', 'rs232_dsr', 'RS232/1_in', 'RS232/2_in', 'PIO/1_in', 'RS232/1_out', 'RS232/2_out', 'PIO/1_out', 'tipi_dsr', 'tipi_addr', 'reset_key', '');
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
        success := true;
        case keyType of
            CpuFreq:
                defaultCpuFrequency := n;
            Mem32KExt, MemExt:
                if n in [0..2] then
                    memExtension := n;
            ConsoleRom: 
                consoleRomFile := path;
            ConsoleGroms:
                consoleGromFile := path;
            CartRom:
                begin
                    cartRoms [currentBank] := path;
                    inc (currentBank);
                    cartBanks := currentBank;
                end;
            CartGroms:
                cartGrom := path;
            DiskSimDsr:
                 diskSimDsrPath := path;
            DiskSimDir:
                 diskSimDirPath :=  path;
            FdcDsr:
                fdcDsrPath := path;
            FdcDisk1..FdcDisk3:
                fdcDiskImage [succ (ord (keyType) - ord (FdcDisk1))] := path;
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
                if n in [0..2] then
                    pcode80 := TPCode80Screen (n);
            PcodeDiskDsr:
                pcodeDiskDsrPath := path;
            PcodeDisk1..PcodeDisk3:
                pcodeDiskImage [succ (ord (keyType) - ord (PcodeDisk1))] := path;
            CartMiniMem:
                useMiniMem := n = 1;
            CartInverted:
                setCartROMInverted (n = 1);
            CassIn:
                cassInPath := path;
            CassOut:
                cassOutPath := path;
            WindowScaleWidth:
                scaleWidth := n;
            WindowScaleHeight:
                scaleHeight := n;
            SerialDsr:
                begin
                    writeln ('Error: Simulated RS232 card (serial_dsr key) is no longer supported - please switch to rs232_dsr');
                    success := false
                end;
            RS232Dsr:
                rs232DsrPath := path;
            SerialPort1In..ParallelPort1In:
                rs232FileNames [TIoPort (ord (keyType) - ord (SerialPort1In)), PortIn] := path;
            SerialPort1Out..ParallelPort1Out:
                rs232FileNames [TIoPort (ord (keyType) - ord (SerialPort1Out)), PortOut] := path;
            TipiDsr:
                tipiDsrPath := path;
            TipiAddr:
                tipiWsUrl := value;
            ResetCode:
                resetKey := n;
            Invalid:
                success := false
        end;
    end;

procedure loadConfigFile (fn: string; level: uint8); forward;
    
procedure evaluateConfigLine (dir, s: string; level: uint8);
    var 
        p: int64;
        key, value, path: string;
        success: boolean;
    begin
        p := pos ('=', s);
        success := false;
        if p <> 0 then
            begin
                key := trim (copy (s, 1, pred (p)));
                value := trim (copy (s, succ (p), length (s) - p));
                if key <> '' then 
                    begin
                        if (value <> '') and (value [1] <> '/') then
                            path := dir + value
                        else
                            path := value;
                        success := true;
                        if upcase (key) = 'INCLUDE' then
                            loadConfigFile (path, succ (level))
                        else
                            evaluateKey (key, value, path, success)
                    end
            end;
        if not success then 
            errorExit ('Invalid config option: ' + s);
    end;
    
procedure loadConfigFile (fn: string; level: uint8);
    const
        MaxConfigLevel = 10;
        
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
        currentBank := 0; 	// clear previious cart ROMs if new cart_rom entry is read
        writeln ('Reading config file: ', fn);
        assign (f, fn);
        reset (f);
        while not eof (f) do
            begin
                readln (f, s);
                if (s <> '') and (s [1] <> ';') and (s [1] <> '#') then
                    evaluateConfigLine (dir, s, level)
            end;
        close (f);
        currentBank := 0
    end;    
    
procedure setConfigData;
    var
        i: TDiskDrive;
        j: uint8;
        port: TIoPort;
        dir: TIoPortDirection;
    begin
        setCpuFrequency (defaultCpuFrequency);
        if consoleRomFile <> '' then
            loadConsoleRom (consoleRomFile)
        else
            errorExit ('Need console ROM to start simulator');
        if consoleGromFile <> '' then
            loadConsoleGroms (consoleGromFile);
        if memExtension <> 0 then
            configureMemoryKExtension (memExtension = 1);
        if useMiniMem then
           configureMiniMemory;
        if cartBanks <> 0 then        
            for j := 0 to pred (cartBanks) do
                loadCartROM (j, cartRoms [j]);
        if cartGrom <> '' then
            loadCartGROM (cartGrom);
        if (diskSimDsrPath <> '') and (diskSimDirPath <> '') then
            initDiskSim (diskSimDsrPath, diskSimDirPath);
        if pcodeDiskDsrPath <> '' then
            begin
                initPcodeDisk (pcodeDiskDsrPath);
                for i := 1 to NumberDrives do
                    if pcodeDiskImage [i] <> ''
                        then pcodeDiskSetDiskImage (i, pcodeDiskImage [i])
            end;
        if fdcDsrPath <> '' then
            begin
                fdcInitCard (fdcDsrPath);
                for i := 1 to NumberDrives do
                    if fdcDiskImage [i] <> '' then
                        fdcSetDiskImage (i, fdcDiskImage [i])
            end;
        if (pcodeGromCount = 8) and (pcodeRomFilenames.dsrLow <> '') and (pcodeRomFilenames.dsrHigh <> '') then
            initPCodeCard (pcodeRomFilenames);
        if rs232DsrPath <> '' then
            begin
                for port := RS232_1 to PIO_1 do
                    for dir := PortIn to PortOut do
                        if rs232FileNames [port, dir] <> '' then
                            setSerialFileName (port, dir, rs232FileNames [port, dir]);
                initRs232Card (rs232DsrPath)
            end;
        if (tipiDsrPath <> '') and (tipiWsUrl <> '') then
            begin
                loadTipiDsr (tipiDsrPath);
                initTipi (tipiWsUrl)
            end;
        if cassInPath <> '' then
            setCassetteInput (cassInPath);
        if cassOutPath <> '' then
            setCassetteoutput (cassOutPath);
    end;

procedure loadConfig;
    var 
        i: integer;
        s: string;
    begin
        pcode80 := PCode80_None;
        scaleWidth := 3;
        scaleHeight := 3;
        cartBanks := 0;
        pcodeGromCount := 0;
        defaultCpuFrequency := 3000000;
        resetKey := -1;
        
        if ParamCount = 0 then
            loadConfigFile ('ti99.cfg', 0)
        else
            for i := 1 to ParamCount do
                begin
                    s := ParamStr (i);
                    if fileExists (s) then
                        loadConfigFile (s, 0)
                    else
                        evaluateConfigLine ('', s, 0)
                end;
                
        setConfigData        
    end;
    
function usePcode80: TPcode80Screen;
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
    
function getResetKey: integer;
    begin
        getResetKey := resetKey
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
        cycleTime := (1000 * 1000 * 1000) div cpuFrequency
    end;
    

end.
