unit config;

interface

procedure loadConfigFile (fn: string);

function usePcode80: boolean;

implementation

uses memory, tms9900, fdccard, disksim, tape, pcodecard, pcodedisk, tools, sysutils;

var 
    pcode80: boolean;

procedure loadConfigFile (fn: string);
    type
        TConfigKey = record
	    key, value: string
	end;
        TKeyType = (CpuFreq, Mem32KExt, ConsoleRom, ConsoleGroms, CartRom, CartGroms, DiskSimDsr, DiskSimDir, FdcDsr, FdcDisk1, FdcDisk2, FdcDisk3, PcodeDsrLow, PCodeDsrHigh, PCodeGrom, PCodeScreen80, PcodeDiskDsr, PcodeDisk1, PcodeDisk2, PcodeDisk3, CartMiniMem, CartInverted, CassIn, CassOut, Invalid);
    const
         keyTypeMap: array [TKeyType] of string = 
             ('cpu_freq', 'mem_32k_ext', 'console_rom', 'console_groms', 'cart_rom', 'cart_groms', 'disksim_dsr', 'disksim_dir', 'fdc_dsr', 'fdc_dsk1', 'fdc_dsk2', 'fdc_dsk3', 'pcode_dsrlow', 'pcode_dsrhigh', 'pcode_grom', 'pcode_screen80', 'pcodedisk_dsr', 'pcodedisk_dsk1', 'pcodedisk_dsk2', 'pcodedisk_dsk3', 'cart_minimem', 'cart_inverted', 'cass_in', 'cass_out', '');
    	MaxKeys = 30;
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
   	                case evalKey (key) of
 	                    CpuFreq:
 	                        setCpuFrequency (n);
			    Mem32KExt:
			        if n = 1 then 
 			    	    configure32KExtension;
		            ConsoleRom: 
		    	        loadConsoleRom (value);
  		            ConsoleGroms:
		                loadConsoleGroms (value);
			    CartRom:
			        begin
				    loadCartROM (cartBank, value);
				    inc (cartBank)
				end;
			    CartGroms:
			        loadCartGROM (value);
		            DiskSimDsr:
			         diskDsr := value;
		            DiskSimDir:
		                 if diskDsr <> '' then
		                     initDiskSim (diskDsr, value)
		                 else
		                     writeln ('disksim_dir specified without valid disksim_dsr value');
			    FdcDsr:
			        fdcInitCard (value);
			    FdcDisk1:
			    	fdcSetDiskImage (1, value);
			    FdcDisk2:
			    	fdcSetDiskImage (2, value);
			    FdcDisk3:
			    	fdcSetDiskImage (3, value);
			    PcodeDsrLow: 
			        pcodeRomFilenames.dsrLow := value;
			    PcodeDsrHigh:
			        pcodeRomFilenames.dsrHigh := value;
			    PcodeGrom:
			        begin
			            if pcodeGromCount < 8 then
  			    	        pcodeRomFilenames.groms [pcodeGromCount] := value;
 			    	    inc (pcodeGromCount)
 			    	end;
			    PcodeScreen80:
			    	pcode80 := true;
			    PcodeDiskDsr:
			        initPcodeDisk (value);
			    PcodeDisk1: 
			        pcodeDiskSetDiskImage (1, value);
			    PcodeDisk2: 
			        pcodeDiskSetDiskImage (2, value);
			    PcodeDisk3:
			        pcodeDiskSetDiskImage (3, value);
			    CartMiniMem:
			    	if n = 1 then
				    configureMiniMemory;
			    CartInverted:
 			        setCartROMInverted (n = 1);
			    CassIn:
			        setCassetteInput (value);
			    CassOut:
			        setCassetteOutput (value);
			    Invalid:
			        writeln ('Invalid config entry: ', key, ' = ', value)
			end
		    end;
	    if (pcodeGromCount = 8) and (pcodeRomFilenames.dsrLow <> '') and (pcodeRomFilenames.dsrHigh <> '') then
	        initPCodeCard (pcodeRomFilenames)
	end;
	
    procedure loadConfigKeys;
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
		                inc (keyCount)
		        end
	    end;
	
        begin
       	    assign (f, fn);
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
        if not fileExists (fn) then
	    errorExit ('config file ' + fn + ' not found');
        keyCount := 0;
        loadConfigKeys;
        evaluateKeys
    end;
    
function usePcode80: boolean;
    begin
    	usePcode80 := pcode80
    end;

end.
