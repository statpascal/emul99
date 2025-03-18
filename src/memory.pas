unit memory;

interface

uses types;

function readCru (addr:  TCruAddress): TCruBit;
procedure writeCru (addr: TCruAddress; value: TCruBit);

procedure writeMemory (addr, val: uint16);
function readMemory (addr: uint16): uint16;

function getMemoryPtr (s: uint16): TUint8Ptr;
function getPcodeScreenBuffer: TUint8Ptr;

function getWaitStates: uint8;

procedure configure32KExtension;
procedure configureMiniMemory;

procedure loadConsoleRom (filename: string);
procedure loadConsoleGroms (filename: string);
procedure loadCartROM (bank: uint8; filename: string);
procedure setCartROMInverted (f: boolean);
procedure loadCartGROM (filename: string);


implementation

uses tms9901, vdp, sound, grom, fdccard, rs232card, disksim, pcodecard, pcodedisk, tools, cfuncs, serial, tipi;

const
    MaxCardBanks = 64;
    SAMSPageSize = 4096;
    SAMSPageCount = 256;

type
    TMemoryHandler = record
        r: function (addr: uint16): uint16;
        w: procedure (addr, w: uint16);
        rws, wws: uint8;
    end;

    
const
    mapSAMS: array [boolean, 0..15] of 0..4095 = 
        ((0, 0, 2, 3, 0, 0, 0, 0, 0, 0, 10, 11, 12, 13, 14, 15),
         (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0));
	
var
    samsMem: array [0..SAMSPageCount - 1, 0..SAMSPageSize div 2 - 1] of uint16;
    mem: array [0..MaxAddress div 2] of uint16;	  (* only used for scratch pad/Mini Memory *)
    cart: array [0..MaxCardBanks - 1, $3000..$3FFF] of uint16;
    cartBanks: 1..MaxCardBanks;
    activeCartBank: 0..MaxCardBanks - 1;
    cartROMInverted: boolean;
    samsMappingMode: boolean;
    
    memoryMap: array [0..MaxAddress div 2] of TMemoryHandler;

    groms: TGrom;
    activeDsrBase: $0000..$1f00;		(* 0: none selected *)
    waitStates: uint8;

procedure writeNull (addr, w: uint16);
    begin
    end;

function readNull (addr: uint16): uint16;
    begin
	readNull := 0
    end;
    
function getMemoryPtr16 (address: uint16): TUint16Ptr;
    begin
        if mapSAMS [false, address div SAMSPageSize] <> 0  then
            getMemoryPtr16 := addr (samsMem [mapSAMS [samsMappingMode, address div SAMSPageSize and pred (SAMSPageCount)] and $ff, address and $0ffe div 2])
        else
  	    getMemoryPtr16 := addr (mem [address shr 1])
    end;

function getPcodeScreenBuffer: TUint8Ptr;
    begin
        getPcodeScreenBuffer := addr (samsMem [mapSAMS [false, 2], 0])
//        getPcodeScreenBuffer := getMemoryPtr ($2000)
    end;
    
procedure writeMem (addr, w: uint16);
    begin
        getMemoryPtr16 (addr)^ := htons (w);
    end;

function readMem (addr: uint16): uint16;
    begin
	readMem := ntohs (getMemoryPtr16 (addr)^)
    end;

procedure writePAD (addr, w: uint16);
    begin
	writeMem (addr or $8300, w)
    end;

function readPAD (addr: uint16): uint16;
    begin
	readPAD := readMem (addr or $8300)
    end;

procedure writeSound (addr, w: uint16);
    begin
        soundWriteData (w shr 8)
    end;

procedure writeDataVdp (addr, w: uint16);
    begin
        vdpWriteData (w shr 8)
    end;
    
procedure writeCmdVdp (addr, w: uint16);
    begin
        vdpWriteCommand (w shr 8)
    end;

function readDataVdp (addr: uint16): uint16;
    begin
        readDataVdp := vdpReadData shl 8
    end;
    
function readStatusVdp (addr: uint16): uint16;
    begin
        readStatusVdp := vdpReadStatus shl 8
    end;        

procedure writeCart (addr, w: uint16);
    begin
        activeCartBank := (addr shr 1) and (cartBanks - 1);
        if cartROMInverted then
            activeCartBank := cartBanks - 1 - activeCartBank
    end;
    
function readCart (addr: uint16): uint16;
    begin
	readCart := ntohs (cart [activeCartBank, addr shr 1])
    end;
    
procedure writeSAMSRegister (addr, w: uint16);
    begin
        writeln ('SAMS: reg #', addr and $1e shr 1, ' <- ', ntohs (w) and $0fff); 
        mapSAMS [true, addr and $1e shr 1] := ntohs (w) and $0fff
    end;
    
function readSAMSRegister (addr: uint16): uint16;
    begin
        readSamsRegister := htons (mapSAMS [true, addr and $1e shr 1])
    end;
    
procedure writeDsr (addr, val: uint16);
    begin
        case activeDsrBase of
            FdcCardCruAddress:
                writeFdcCard (addr, val);
            TipiCruAddress:
                writeTipi (addr, val);
            SAMSCruAddress:
                writeSAMSRegister (addr, val);
            PcodeCardCruAddress:
                writePcodeCard (addr, val)
	end
    end;
    
function readDsr (addr: uint16): uint16;
    begin
        case activeDsrBase of
            FdcCardCruAddress:
                readDsr := readFdcCard (addr);
	    DiskSimCruAddress:
	        readDsr := readDiskSim (addr);
            RS232CruAddress:
               readDsr := readRs232Card (addr);
            TipiCruAddress:
                readDsr := readTipi (addr);
            SAMSCruAddress:
                readDsr := readSAMSRegister (addr);
            PcodeDiskCruAddress:
                readDsr := readPcodeDisk (addr);
	    PcodeCardCruAddress:
	        readDsr := readPcodeCard (addr);
            SerialSimCruAddress:
                readDsr := readSerial (addr)
	    else
	        readDsr := 0
	end
    end;

procedure writeAddrGROM (addr, w: uint16);
    begin
        writeGromAddress (groms, w shr 8)
    end;

function readDataGrom (addr: uint16): uint16;
    begin
        readDataGrom := readGromData (groms) shl 8
    end;
    
function readAddrGrom (addr: uint16): uint16;
    begin
        readAddrGrom := readGromAddress (groms) shl 8
    end;
    
procedure writeMemory (addr, val: uint16);
    begin
        memoryMap [addr shr 1].w (addr and $fffe, val);
        inc (waitStates, memoryMap [addr shr 1].wws)
    end;

function readMemory (addr: uint16): uint16;
    begin
       readMemory := memoryMap [addr shr 1].r (addr and $fffe);
       inc (waitStates, memoryMap [addr shr 1].rws)
    end;
    
function getMemoryPtr (s: uint16): TUint8Ptr;
    begin
        getMemoryPtr := TUint8Ptr (getMemoryPtr16 (s))
    end;
    
function getWaitStates: uint8;
    begin
        getWaitStates := waitStates;
        waitStates := 0
    end;
    
procedure loadConsoleRom (filename: string);
    begin
        loadBlock (mem, MaxAddress, 0, filename)
    end;
    
procedure loadConsoleGroms (filename: string);
    begin
        loadBlock (groms.data, MaxAddress, 0, filename)
    end;

procedure loadCartROM (bank: uint8; filename: string);
    var
        size: int64;
    begin
        size := getFileSize (filename);
        if (bank = 0) and (size > sizeof (cart [0])) then
            begin
                if size > sizeof (cart) then
                    errorExit ('Cannot load cartridge: please enlarge MaxCardBanks in file memory.pas');
                loadBlock (cart, size, 0, filename);
                bank := (size - 1) div sizeof (cart [9])
            end
        else
            loadBlock (cart [bank], sizeof (cart [bank]), 0, filename);
        if bank >= cartBanks then
    	    begin
	        cartBanks := 1;
	        while cartBanks <= bank do
	    	    cartBanks := cartBanks shl 1
	    end
    end;
    
procedure setCartROMInverted (f: boolean);
    begin
        cartROMInverted := f
    end;

procedure loadCartGROM (filename: string);
    begin
        loadBlock (groms.data [$6000], succ (MaxAddress - $6000), 0, filename)
    end;

function readCru (addr: TCruAddress): TCruBit;
    begin
	if addr < Tms9901MaxCruAddress then 
	    readCru := tms9901ReadBit (addr)
        else	    
	    case activeDsrBase of
                FdcCardCruAddress:
                     readCru := readFdcCardCru (addr shl 1);
                RS232CruAddress:
                    readCru := readRs232CardCru (addr shl 1);
	        PcodeCardCruAddress:
	            readCru := readPcodeCardCru (addr shl 1)
	        else
  		    readCru := 0
	    end
    end;

procedure writeCru (addr: TCruAddress; value: TCruBit);
    const
        offon: array [0..1] of string = ('off', 'on');
        passmap: array [0..1] of string = ('pass', 'map');
    var
        addr12: TCruR12Address;
        samsBit : 0..7;
    begin
        addr12 := addr shl 1;
  	if addr < Tms9901MaxCruAddress then
	    tms9901WriteBit (addr, value)
	else if addr12 >= $1000 then
	    begin
  	        if addr12 and $00ff = 0 then
                    activeDsrBase := (addr12 and $ff00) * value;
                case activeDsrBase of
                    FdcCardCruAddress:
                        writeFdcCardCru (addr12, value);
                    RS232CruAddress:
                        writeRs232CardCru (addr12, value);
                    PcodeCardCruAddress:
                        writePcodeCardCru (addr12, value)
		end;
		if (addr12 >= SAMSCruAddress) and (addr12 <= SAMSCruAddress + $ff) then
		    begin
		        samsBit := addr12 and $0f shr 1;
		        case samsBit of
		            0:
		                writeln ('SAMS: ', offon [value]);
                            1:
                                begin
                                    samsMappingMode := value = 1;
                                    writeln ('SAMS: ', passmap [value]);
                                end
                        end    
                    end;
		    
	    end
    end;
    
const
    RomHandler:  	     TMemoryHandler = (r: readMem;       w: writeNull;     rws:  0; wws:  0);
    NullHandler: 	     TMemoryHandler = (r: readNull;      w: writeNull;     rws:  4; wws:  4);
    RamHandler:		     TMemoryHandler = (r: readMem;       w: writeMem;      rws:  4; wws:  4);
    ScratchPadHandler:	     TMemoryHandler = (r: readMem;       w: writeMem;      rws:  0; wws:  0);
    DsrHandler:	             TMemoryHandler = (r: readDsr;       w: writeDsr;      rws:  4; wws:  4);
    CartHandler:	     TMemoryHandler = (r: readCart;      w: writeCart;     rws:  4; wws:  4);
    SoundWriteHandler:	     TMemoryHandler = (r: readNull;      w: writeSound;    rws:  4; wws: 32);
    VdpWriteDataHandler:     TMemoryHandler = (r: readNull;      w: writeDataVdp;  rws:  4; wws:  4);
    VdpWriteCommandHandler:  TMemoryHandler = (r: readNull;      w: writeCmdVdp;   rws:  4; wws:  4);
    VdpReadDataHandler:	     TMemoryHandler = (r: readDataVdp;   w: writeNull;     rws:  4; wws:  4);
    VdpReadStatusHandler:    TMemoryHandler = (r: readStatusVdp; w: writeNull;     rws:  4; wws:  4);
    GromWriteAddressHandler: TMemoryHandler = (r: readNull;      w: writeAddrGrom; rws:  4; wws: 22);
    GromReadDataHandler:     TMemoryHandler = (r: readDataGrom;  w: writeNull;     rws: 22; wws:  4);
    GromReadAddressHandler:  TMemoryHandler = (r: readAddrGrom;  w: writeNull;     rws: 17; wws:  4);
    
procedure setMemoryMap (startAddr, endAddr: uint16; handlerEven, handlerOdd: TMemoryHandler); overload;
    var
        i: 0..MaxAddress div 2;
    begin
        for i := startAddr div 2 to endAddr div 2 do
            if odd (i) then
                memoryMap [i] := handlerOdd
            else
                memoryMap [i] := handlerEven
    end;

procedure setMemoryMap (startAddr, endAddr: uint16; handler: TMemoryHandler); overload;
    begin
        setMemoryMap (startAddr, endAddr, handler, handler)
    end;

procedure configure32KExtension;
    begin
        setMemoryMap ($2000, $3ffe, RamHandler);
        setMemoryMap ($a000, $fffe, RamHandler)
    end;

procedure configureMiniMemory;
    begin    
  	setMemoryMap ($7000, $7ffe, RamHandler)
    end;

begin
    setMemoryMap ($0000, $1ffe, RomHandler);
    setMemoryMap ($2000, $fffe, NullHandler);
    setMemoryMap ($4000, $5ffe, DsrHandler);
    setMemoryMap ($6000, $7ffe, CartHandler);
    setMemoryMap ($8000, $83fe, ScratchPadHandler);
    setMemoryMap ($8400, $85fe, SoundWriteHandler);
    setMemoryMap ($8800, $8bfe, VdpReadDataHandler, VdpReadStatusHandler);
    setMemoryMap ($8c00, $8ffe, VdpWriteDataHandler, VdpWriteCommandHandler);
    setMemoryMap ($9800, $9bfe, GromReadDataHandler, GromReadAddressHandler);
    setMemoryMap ($9c00, $9ffe, NullHandler, GromWriteAddressHandler);
        
    fillChar (mem, sizeof (mem), 0);
    fillChar (groms, sizeof (groms), 0);
    fillChar (cart, sizeof (cart), 0);
    activeDsrBase := 0;
    cartBanks := 1;
    activeCartBank := 0;
    waitStates := 0;
    samsMappingMode := false;
end.
