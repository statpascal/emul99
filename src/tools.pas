unit tools;

interface

function hexstr (u: uint16): string;
function hexstr2 (u: uint8): string;
function decimalstr (v: int64): string;

function trim (s: string): string;

function loadBlock (var dest; size, offset: int64; fileName: string): int64;
function saveBlock (var src; size: int64; fileName: string): int64;
function getFileSize (fileName: string): int64;

function crc16 (var data; size: int64): uint16;
function oddParity (val: uint8): boolean;

function getHighLow (val: uint16; highByte: boolean): uint8;
procedure setHighLow (var val: uint16; highByte: boolean; b: uint8);

procedure errorExit (s: string);


implementation

uses fileop;

const 
    hex: array [0..15] of string = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F');
    
function hexstr2 (u: uint8): string;    
    begin
        hexstr2 := hex [(u shr 4) and $0f] + hex [u and $0f]
    end;
    
function hexstr (u: uint16): string;
    begin
        hexstr := hexstr2 (u shr 8) + hexstr2 (u and $ff)
    end;

function decimalstr (v: int64): string;
    var 
        s: string;
    begin
        str (v, s);
        decimalstr := s
    end;
    
function trim (s: string): string;
    var 
        b, e: int64;
    begin
        b := 1;
        e := length (s);
	while (b <= e) and (s [b] = ' ') do
	    inc (b);
	while (e >= b) and (s [e] = ' ') do
	    dec (e);
        trim := copy (s, b, succ (e - b))
    end; 
    
function loadBlock (var dest; size, offset: int64; fileName: string): int64;
    var
        handle: TFileHandle;
        bytesRead: int64;
    begin
        bytesRead := 0;
        handle := fileOpen (fileName, false, false, false, false);
        if handle = InvalidFileHandle then
            writeln ('File ', fileName, ': cannot open')
        else
            begin
                fileSeek (handle, offset);
                bytesRead := fileRead (handle, addr (dest), size);
                fileClose (handle)
            end;
        loadBlock := bytesRead
    end;
    
function saveBlock (var src; size: int64; fileName: string): int64;
    var 
        handle: TFileHandle;
        bytesWritten: int64;
    begin
        bytesWritten := 0;
        handle := fileOpen (fileName, true, true, false, false);
        if handle = InvalidFileHandle then
            writeln ('File ', fileName, ': cannot open')
        else
            begin
                bytesWritten := fileWrite (handle, addr (src), size);
                if bytesWritten <> size then
                    writeln  ('Problem saving ', fileName, ': only ', bytesWritten, ' of ', size, ' bytes written');
                fileClose (handle)
            end;
        saveBlock := bytesWritten
    end;

function getFileSize (fileName: string): int64;
    var
        handle: TFileHandle;
    begin
        handle := fileOpen (fileName, false, false, false, false);
        getFileSize := fileSize (handle);
        fileClose (handle)
    end;
                
(*$POINTERMATH ON*)
function crc16 (var data; size: int64): uint16;
    var
        crc: uint16;
        p: ^uint8;
        i: 1..8;
        j: int64;
    begin
        p := addr (data);
        crc := 0;
        for j := 0 to pred (size) do
            begin
                crc := crc xor (p [j] shl 8);
                for i := 1 to 8 do
                    crc := ((crc shl 1) xor ($1021 * (crc shr 15))) and $ffff
            end;        
        crc16 := crc
    end;
    
function oddParity (val: uint8): boolean;
    begin
        oddParity := odd ($6996 shr ((val xor (val shr 4)) and $0f))
    end;

function getHighLow (val: uint16; highByte: boolean): uint8;
    begin
        getHighLow := (val shr (ord (highByte) * 8)) and $ff
    end;
    
procedure setHighLow (var val: uint16; highByte: boolean; b: uint8);
    begin
        val := val and ($ff00 shr (8 * ord (highByte))) or (b shl (8 * ord (highByte)))
    end;
    
procedure errorExit (s: string);
    begin
        writeln ('Fatal error: ', s);
        halt (1)
    end;
    
end.
