unit pcodecard;

interface

uses types;

procedure writePcodeCard (addr, val: uint16);
function readPcodeCard (addr: uint16): uint16;

procedure writePcodeCardCru (addr: TCruR12Address; value: TCruBit);
function readPcodeCardCru (addr: TCruR12Address): TCruBit;

type
    TPcodeRomFilenames = record
        dsrLow, dsrHigh: string;
        groms: array [0..7] of string
    end;

procedure initPcodeCard (filenames: TPcodeRomFilenames);


implementation

uses grom, tools, cfuncs;

var
    dsrRom: array [0..1] of TDsrRom;  
    dsrBank: 0..1;
    pcodeGrom: TGrom;

procedure writePcodeCard (addr, val: uint16);
    begin
        if addr = $5FFE then
            writeGromAddress (pcodeGrom, val shr 8)
    end;
    
function readPcodeCard (addr: uint16): uint16;
    begin
        if addr = $5BFC then 
            readPcodeCard := readGromData (pcodeGrom) shl 8
        else if addr = $5BFE then
            readPcodeCard := readGromAddress (pcodeGrom) shl 8
        else
            readPcodeCard := ntohs (dsrRom [dsrBank].w [addr shr 1])
    end;
    
procedure writePcodeCardCru (addr: TCruR12Address; value: TCruBit);
    begin
        if addr = $1F80 then
            dsrBank := value
    end;
    
function readPcodeCardCru (addr: TCruR12Address): TCruBit;
    begin
        if addr = $1F80 then
            readPcodeCardCru := dsrBank
        else
            readPcodeCardCru := 0
    end;
    
procedure initPcodeCard (filenames: TPcodeRomFilenames);
    var
        i: 0..7;
    begin
        with filenames do
            begin
                loadBlock (dsrRom [0], $1000, 0, dsrLow);
                move (dsrRom [0], dsrRom [1], $1000);
                loadBlock (dsrRom [0].b [$5000], $1000, 0, dsrHigh);
                loadBlock (dsrRom [1].b [$5000], $1000, $1000, dsrHigh);
                for i := 0 to 7 do
                    loadBlock (pcodeGrom.data [i * $2000], $2000, 0, groms [i])
            end
    end;

end.
