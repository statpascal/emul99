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

const
    PcodeCardCruAddress = $1f00;


implementation

uses grom, tools, cfuncs;

var
    pcodeDsrLow: array [$4000..$4fff] of uint8;
    pcodeDsrLowW: array [$2000..$27ff] of uint16 absolute pcodeDsrLow;
    
    pcodeDsrHigh: array [0..1, $5000..$5FFF] of uint8;
    pcodeDsrHighW: array [0..1, $2800..$2FFF] of uint16 absolute pcodeDsrHigh;
    
    pcodeHighBank: 0..1;
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
        else if addr >= $5000 then
            readPcodeCard := ntohs (pcodeDsrHighW [pcodeHighBank, addr shr 1])
        else
            readPcodeCard := ntohs (pcodeDsrLowW [addr shr 1])
    end;
    
procedure writePcodeCardCru (addr: TCruR12Address; value: TCruBit);
    begin
        if addr = $1F80 then
            pcodeHighBank := value
    end;
    
function readPcodeCardCru (addr: TCruR12Address): TCruBit;
    begin
        if addr = $1F80 then
            readPcodeCardCru := pcodeHighBank
        else
            readPcodeCardCru := 0
    end;
    
procedure initPcodeCard (filenames: TPcodeRomFilenames);
    var
        i: 0..7;
    begin
        with filenames do
            begin
                loadBlock (pcodeDsrLow, sizeof (pcodeDsrLow), 0, dsrLow);
                loadBlock (pcodeDsrHigh, sizeof (pcodeDsrHigh), 0, dsrHigh);
                for i := 0 to 7 do
                    loadBlock (pcodeGrom.data [i * $2000], $2000, 0, groms [i])
            end
    end;

end.
