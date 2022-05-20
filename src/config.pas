unit config;

interface

procedure loadConfigFile (fn: string);

function usePcode80: boolean;
function getWindowScaleHeight: uint8;
function getWindowScaleWidth: uint8;

implementation

uses memory, tms9900, fdccard, disksim, tape, pcodecard, pcodedisk, serial, tools, sysutils;

var 
    pcode80: boolean;
    scaleWidth, scaleHeight: uint8;

procedure loadConfigFile (fn: string);
    type
        TConfigKey = record
	    key, value, path: string
	end;
        TKeyType = (CpuFreq, Mem32KExt, ConsoleRom, ConsoleGroms, CartRom, CartGroms, DiskSimDsr, DiskSimDir, FdcDsr, FdcDisk1, FdcDisk2, FdcDisk3, PcodeDsrLow, PCodeDsrHigh, PCodeGrom, PCodeScreen80, PcodeDiskDsr, PcodeDisk1, PcodeDisk2, PcodeDisk3, CartMiniMem, CartInverted, CassIn, CassOut, WindowScaleWidth, WindowScaleHeight, 
                    SerialDsr, SerialPort1In, SerialPort2In, SerialPort3In, SerialPort4In, ParallelPort1In, ParallelPort2In, SerialPort1Out, SerialPort2Out, SerialPort3Out, SerialPort4Out, ParallelPort1Out, ParallelPort2Out, Invalid);
    const
         keyTypeMap: array [TKeyType] of string = 
             ('cpu_freq', 'mem_32k_ext', 'console_rom', 'console_groms', 'cart_rom', 'cart_groms', 'disksim_dsr', 'disksim_dir', 'fdc_dsr', 'fdc_dsk1', 'fdc_dsk2', 'fdc_dsk3', 'pcode_dsrlow', 'pcode_dsrhigh', 'pcode_grom', 'pcode_screen80', 'pcodedisk_dsr', 'pcodedisk_dsk1', 'pcodedisk_dsk2', 'pcodedisk_dsk3', 'cart_minimem', 'cart_inverted', 'cass_in', 'cass_out', 'window_scale_width', 'window_scale_height', 
              'serial_dsr', 'RS232/1_in', 'RS232/2_in', 'RS232/3_in', 'RS232/4_in', 'PIO/1_in', 'PIO/2_in', 'RS232/1_out', 'RS232/2_out', 'RS232/3_out', 'RS232/4_out', 'PIO/1_out', 'PIO/2_out', '');
    	MaxKeys = 50;
    	MaxConfigLevel = 10;
    var
        keyCount: 0..MaxKeys;
        keys: array [1..MaxKeys] of TConfigKey;
        
    procedure evaluateKeys;
        var
            i: 1..MaxKeys;
            n: int64;
            code: uint16;
            cartBank, pcodeGromCount: uint8;
            diskDsr: string;
            pcodeRomFilenames: TPcodeRomFilenames;
            keyType: TKeyType;
            
        function evalKey (s: string): TKeyType;
  	    var
	        kt: TKeyType;
	    begin
	        kt := CpuFreq;
	        while (kt <> Invalid) and (upcase (s) <> upcase (keyTypeMap [kt])) do
		    inc (kt);
	        evalKey := kt
	    end;

        begin
            cartBank := 0;
            pcodeGromCount := 0;
	    for i := 1 to keyCount do
	        with keys [i] do
	            begin
	                val (value, n, code);
	                keyType := evalKey (key);
   	                case keyType of
 	                    CpuFreq:
 	                        setCpuFrequency (n);
			    Mem32KExt:
			        if n = 1 then 
 			    	    configure32KExtension;
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
			    	pcode80 := true;
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
			        initSerial (path);
			    SerialPort1In..ParallelPort2In:
			        setSerialFileName (TSerialPort (ord (keyType) - ord (SerialPort1In)), PortIn, path);
			    SerialPort1Out..ParallelPort2Out:
			        setSerialFileName (TSerialPort (ord (keyType) - ord (SerialPort1Out)), PortOut, path);
			    Invalid:
			        writeln ('Invalid config entry: ', key, ' = ', value)
			end
		    end;
	    if (pcodeGromCount = 8) and (pcodeRomFilenames.dsrLow <> '') and (pcodeRomFilenames.dsrHigh <> '') then
	        initPCodeCard (pcodeRomFilenames)
	end;
	
    procedure loadConfigKeys (dir, fn: string; level: uint8);
        var
            f: text;
            s: string;
            
        procedure evaluateLine (s: string);
      	    var 
	        p: int64;
 	    begin
	        p := pos ('=', s);
	        if p <> 0 then
	            with keys [succ (keyCount)] do
  		        begin
		            key := trim (copy (s, 1, pred (p)));
		            value := trim (copy (s, succ (p), length (s) - p));
		            if (key <> '') and (value <> '') then 
		                if upcase (key) = 'INCLUDE' then
		                    loadConfigKeys (dir, value, succ (level))
		                else
		                    begin
		                        if value [1] <> '/' then
		                            path := dir + value
		                        else
		                            path := value;
     		                        inc (keyCount)
				    end
		        end
	    end;
	
        begin
            if not fileExists (dir + fn) then
	        errorExit ('config file ' + dir + fn + ' not found');
	    if level > maxConfigLevel then
	        errorExit ('Configuration files nested too deep - recursive inclusion?');
       	    assign (f, dir + fn);
    	    reset (f);
    	    while not eof (f) do
	        begin
	     	    readln (f, s);
	     	    if (s <> '') and (s [1] <> ';') then
	     	    	evaluateLine (s)
		end;
	    close (f)
    end;
    
    begin
        pcode80 := false;
        scaleWidth := 4;
        scaleHeight := 4;
        keyCount := 0;
        loadConfigKeys (extractFilePath (fn), extractFileName (fn), 1);
        evaluateKeys
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

end.
