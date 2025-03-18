unit rs232card;

interface

uses types;

function readRs232Card (addr: uint16): uint16;

procedure writeRs232CardCru (addr: TCruR12Address; value: TCruBit);
function readRs232CardCru (addr: TCruR12Address): TCruBit;

procedure initRs232Card (dsrFilename: string);


implementation

uses cfuncs, tools;

type 
    TMS9902 = record
        cruInput: array [0..31] of TCruBit;
        ldctrl, ldir, lrdr, lxdr: boolean;
        dscenb, timenb, xbienb, rienb: boolean;
        brkon, rts: boolean;

        ctrlReg: uint16;        
        intervalReg: uint16;
        rdrReg, xdrReg: uint16;
        transmitBuf: uint16;
    end;
    
    TRs232DeviceNumber = 0..1;
    TRs232BitNumber = 0..31;
        
var
    dsrRom: TDsrRom;
    rs232Devices: array [0..1] of TMS9902;
    
procedure reset (var rs232Device: TMS9902);
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
                lxdr := true
            end
    end;
    
procedure writeRegisterBit (var dev: TMS9902; bit: TRs232BitNumber; val: TCruBit);

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
                    setBit (transmitBuf, dummy, 7)
            end
    end;
    
procedure writeRtson (var dev: TMS9902; val: TCruBit);
    begin
        if val = 0 then
            writeln ('Output char: ', chr (dev.transmitBuf), ' - ord ', dev.transmitBuf)
    end;
    
function readRs232Card (addr: uint16): uint16;
    begin
        readRs232Card := ntohs (dsrRom.w [addr shr 1])
    end;
    
procedure handleDevice (var dev: TMS9902; bit: TRs232BitNumber; val: TCruBit);
    begin
        writeln ('RS232 ', (addr (dev) - addr (rs232Devices)) div sizeof (TMS9902), ' bit ', bit, ' <- ', val);
        case bit of
            31:
                reset (dev);
            16:
                writeRtson (dev, val);
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

procedure writeRs232CardCru (addr: TCruR12Address; value: TCruBit);
    var 
        sel: int32;
    begin
       sel :=  (addr - RS232CruAddress - $40) div 2;
       if (sel >= 0) and (sel <= 53) then
            handleDevice (rs232Devices [sel div 32], sel mod 32, value)
    end;
    
function readRs232CardCru (addr: TCruR12Address): TCruBit;
    begin
        writeln ('RS232 ', (addr - RS232CruAddress - $40) div 2, ' read');
        case (addr - RS232CruAddress - $40) div 2 of
            27:
                readRs232CardCru := 1;	// DTR
            22:
                readRs232CardCru := 1	// Buffer empty
            else
                readRs232CardCru := 0
        end
    end;

procedure initRs232Card (dsrFilename: string);
    begin
        loadBlock (dsrRom, sizeof (dsrRom), 0, dsrFilename);
    end;
    
end.
