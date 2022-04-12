unit memory;

interface

uses types;

(* CRU is handled together with memory because of DSR ROM switching *)

function readCru (addr:  TCruAddress): TCruBit;
procedure writeCru (addr: TCruAddress; value: TCruBit);

procedure writeMemory (addr, w: uint16);
function readMemory (addr: uint16): uint16;
function getMemoryPtr (s: uint16): TMemoryPtr;

function getWaitStates: uint8;

procedure configure32KExtension;
procedure configureMiniMemory;

procedure loadConsoleRom (filename: string);
procedure loadConsoleGroms (filename: string);
procedure loadCartROM (bank: uint8; filename: string);
procedure setCartROMInverted (f: boolean);
procedure loadCartGROM (filename: string);


implementation

uses tms9901, vdp, sound, grom, fdccard, disksim, pcodecard, pcodedisk, tools, cfuncs;

const
    MaxCardBanks = 64;

type
    TMemoryReader = function (addr: uint16): uint16;
    TMemoryWriter = procedure (addr, w: uint16);
    TMemoryMapItem = record
        reader: TMemoryReader;
        writer: TMemoryWriter;
        readWaitStates, writeWaitStates: uint8;
    end;

var
    mem: array [0..MaxAddress] of uint8;
    memW: array [0..MaxAddress div 2] of uint16 absolute mem;
	
    cart: array [0..MaxCardBanks - 1, $6000..$7FFF] of uint8;
    cartW: array [0..MaxCardBanks - 1, $3000..$3FFF] of uint16 absolute cart;
    cartBanks: 1..MaxCardBanks;
    activeCartBank: 0..MaxCardBanks - 1;
    cartROMInverted: boolean;
    
    memoryMap: array [0..MaxAddress div 2] of TMemoryMapItem;

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
    
procedure writeConsoleROM (addr,  w: uint16);
    begin
    end;
    
function readConsoleROM (addr: uint16): uint16;
    begin
        readConsoleROM := ntohs (memW [addr shr 1])
    end;

procedure writeRAM (addr, w: uint16);
    begin
	memW [addr shr 1] := htons (w)
    end;

function readRAM (addr: uint16): uint16;
    begin
	readRAM := ntohs (memW [addr shr 1])
    end;

procedure writePAD (addr, w: uint16);
    begin
	writeRAM (addr or $8300, w)
    end;

function readPAD (addr: uint16): uint16;
    begin
	readPAD := readRAM (addr or $8300)
    end;

procedure writeSound (addr, w: uint16);
    begin
        soundWriteData (w shr 8)
    end;

procedure writeVDP (addr, w: uint16);
    begin
        if odd (addr shr 1) then
	    vdpWriteCommand (w shr 8)
        else
	    vdpWriteData (w shr 8)
    end;

function readVDP (addr: uint16): uint16;
    begin
        if odd (addr shr 1) then
	    readVDP := vdpReadStatus shl 8
        else
	    readVDP := vdpReadData shl 8
    end;

procedure writeCart (addr, w: uint16);
    begin
        activeCartBank := (addr shr 1) and (cartBanks - 1);
        if cartROMInverted then
            activeCartBank := cartBanks - 1 - activeCartBank
    end;
    
function readCart (addr: uint16): uint16;
    begin
	readCart := ntohs (cartW [activeCartBank, addr shr 1])
    end;
    
procedure writeDsrROM (addr, val: uint16);
    begin
        case activeDsrBase of
            FdcCardCruAddress:
                writeFdcCard (addr, val);
            PcodeCardCruAddress:
                writePcodeCard (addr, val)
	end
    end;
    
function readDsrROM (addr: uint16): uint16;
    begin
        case activeDsrBase of
            FdcCardCruAddress:
                readDsrROM := readFdcCard (addr);
	    DiskSimCruAddress:
	        readDsrRom := readDiskSim (addr);
            PcodeDiskCruAddress:
                readDsrRom := readPcodeDisk (addr);
	    PcodeCardCruAddress:
	        readDsrRom := readPcodeCard (addr)
	    else
	        readDsrRom := 0
	end
    end;

procedure writeGROM (addr, w: uint16);
    begin
	if odd (addr shr 1) then
	    writeGromAddress (groms, w shr 8)
    end;

function readGROM (addr: uint16): uint16;
    begin
	if odd (addr shr 1) then
	    readGROM := readGromAddress (groms) shl 8
        else
	    readGROM := readGromData (groms) shl 8
    end;

procedure setMemoryMap (startAddr, endAddr: uint16; writeFunc: TMemoryWriter; writeWs: uint8; readFunc: TMemoryReader; readWs: uint8);
    var
        i: 0..MaxAddress div 2;
    begin
        for i := startAddr div 2 to endAddr div 2 do
            with memoryMap [i] do
                begin
                    reader := readFunc;
                    writer := writeFunc;
                    readWaitStates := readWs;
                    writeWaitStates := writeWs
                end
    end;

procedure configure32KExtension;
    begin
        setMemoryMap ($2000, $3ffe, writeRAM, 4, readRAM, 4);
        setMemoryMap ($a000, $fffe, writeRAM, 4, readRAM, 4)
    end;

procedure configureMiniMemory;
    begin    
        writeln ('Enabling RAM at >7000');
  	setMemoryMap ($7000, $7ffe, writeRAM, 4, readRAM, 4)
    end;

procedure configureBaseMemory;
    begin
	setMemoryMap ($0000, $1ffe, writeConsoleROM, 0, readConsoleROM, 0);
        setMemoryMap ($2000, $3ffe, writeNull, 4, readNull, 4);
	setMemoryMap ($4000, $5ffe, writeDsrROM, 4, readDsrROM, 4);
	setMemoryMap ($6000, $7ffe, writeCart, 4, readCart, 4);
	setMemoryMap ($8000, $83fe, writePAD, 0, readPAD, 0);
	setMemoryMap ($8400, $85fe, writeSound, 4, readNull, 4);
	setMemoryMap ($8600, $87fe, writeNull, 4, readNull, 4);
	setMemoryMap ($8800, $8bfe, writeNull, 4, readVDP, 4);
	setMemoryMap ($8c00, $8ffe, writeVDP, 4, readNull, 4);
	setMemoryMap ($9000, $97fe, writeNull, 4, readNull, 4);	(* Speech *)
	setMemoryMap ($9800, $9bfe, writeNull, 4, readGROM, 4);
	setMemoryMap ($9c00, $9ffe, writeGROM, 23, readNull, 4);
        setMemoryMap ($a000, $fffe, writeNull, 4, readNull, 4);
	    
        fillChar (mem, sizeof (mem), 0);
        fillChar (groms, sizeof (groms), 0);
        fillChar (cart, sizeof (cart), 0);
        activeDsrBase := 0;
        cartBanks := 1;
        activeCartBank := 0;
        waitStates := 0
    end;

procedure writeMemory (addr, w: uint16);
    begin
        with memoryMap [addr shr 1] do
            begin
                writer (addr and $fffe, w);
                inc (waitStates, writeWaitStates)
            end
    end;

function readMemory (addr: uint16): uint16;
    begin
        with memoryMap [addr shr 1] do
            begin
               readMemory := reader (addr and $fffe);
               inc (waitStates, readWaitstates)
           end 
    end;
    
function getMemoryPtr (s: uint16): TMemoryPtr;
    begin
        getMemoryPtr := addr (mem [s])
    end;
    
function getWaitStates: uint8;
    begin
        getWaitStates := waitStates;
        waitStates := 0
    end;
    
(* ROM loader *)

procedure loadConsoleRom (filename: string);
    begin
        load (mem [0], MaxAddress, filename)
    end;
    
procedure loadConsoleGroms (filename: string);
    begin
        load (groms.data [0], MaxAddress, filename)
    end;

procedure loadCartROM (bank: uint8; filename: string);
    var
        size: int64;
    begin
        size := getfilesize (filename);
        if (bank = 0) and (size > sizeof (cart [0])) then
            begin
                load (cart [0], size, filename);
                bank := (size - 1) div sizeof (cart [9])
            end
        else
            load (cart [bank], sizeof (cart [bank]), filename);
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
        load (groms.data [$6000], succ (MaxAddress - $6000), filename)
    end;

function readCru (addr: TCruAddress): TCruBit;
    begin
	if addr < Tms9901MaxCruAddress then 
	    readCru := tms9901ReadBit (addr)
        else	    
	    case activeDsrBase of
                FdcCardCruAddress:
                     readCru := readFdcCardCru (addr shl 1);
	        PcodeCardCruAddress:
	            readCru := readPcodeCardCru (addr shl 1)
	        else
  		    readCru := 0
	    end
    end;

procedure writeCru (addr: TCruAddress; value: TCruBit);
    var
       addr12: TCruR12Address;
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
                    PcodeCardCruAddress:
                        writePcodeCardCru (addr12, value)
		end
	    end
    end;

begin
    configureBaseMemory
end.
