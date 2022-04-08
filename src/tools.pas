unit tools;

interface

function swap16 (u: uint16): uint16;

function hexstr (u: uint16): string;
function hexstr2 (u: uint8): string;
function decimalstr (v: int64): string;

function trim (s: string): string;

function getFilesize (filename: string): int64;

procedure load (var dest; size: int64; filename: string);

procedure loadBlock (var dest; size, offset: int64; filename: string; var bytesRead: int64);
procedure saveBlock (var src; size: int64; filename: string; var bytesWritten: int64);

function crc16 (var data; size: int64): uint16;

function getHighLow (val: uint16; highByte: boolean): uint8;
procedure setHighLow (var val: uint16; highByte: boolean; b: uint8);

procedure errorExit (s: string);


implementation

uses sysutils;

function swap16 (u: uint16): uint16;
    begin
        swap16 := (u shr 8) or ((u and $ff) shl 8)
    end;
    
const 
    hex: array [0..15] of string = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F');
    
function hexstr (u: uint16): string;
    begin
        hexstr := hex [u shr 12] + hex [(u shr 8) and $0f] + hex [(u shr 4) and $0f] + hex [u and $0f]
    end;

function hexstr2 (u: uint8): string;    
    begin
        hexstr2 := hex [(u shr 4) and $0f] + hex [u and $0f]
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
	while (b <= length (s)) and (s [b] = ' ') do
	    inc (b);
	while (e >= b) and (s [e] = ' ') do
	    dec (e);
        if e >= b then
	    trim := copy (s, b, succ (e - b))
        else
	    trim := ''
    end; 
    
function getFilesize (filename: string): int64;
    var
        f: file;
    begin
        (*$I-*)
        assign (f, filename);
        reset (f, 1);
        getFilesize := filesize (f);
        close (f);
        (*$I+*)
        if IOResult <> 0 then
            getFilesize := -1;
    end;
    
procedure load (var dest; size: int64; filename: string);
    var
        f: file;
        fsize, read: int64;
    begin
        if fileexists (filename) then
            begin
                read := 0; 
                fsize := 0;
                (*$I-*)
                assign (f, filename);
                reset (f, 1);
                fsize := filesize (f);
                if fsize > size then
                    writeln ('Problem loadiing ', filename, ': has ', fsize, ' bytes but only ', size, ' bytes expected')
                else 
                    size := fsize;
                blockread (f, dest, size, read);
                close (f);
                (*$I+*)
                if (read <> size) or (IOResult <> 0) then
                    writeln ('Problem loading ', filename, ': got only ', read, ' of ', size, ' bytes')
            end
        else
            writeln ('File ', filename, ' not found')
    end;
    
procedure loadBlock (var dest; size, offset: int64; filename: string; var bytesRead: int64);
    var
        f: file;
    begin
        bytesRead := 0;
        assign (f, filename);
        (*$I-*)
        reset (f, 1);
        seek (f, offset);
        blockRead (f, dest, size, bytesRead);
        close (f);
        (*$I+*)
        IOResult
    end;
    
procedure saveBlock (var src; size: int64; filename: string; var bytesWritten: int64);
    var 
        f: file;
    begin
        bytesWritten := 0;
        assign (f, filename);
        (*$I-*)
        rewrite (f, 1);
        blockWrite (f, src, size, bytesWritten);
        close (f);
        (*$I+*)
        IOResult    
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
                    crc := ((crc shl 1) xor ($1021 * (crc shr 15))) and $ffff;
            end;        
        crc16 := crc
    end;
    
function getHighLow (val: uint16; highByte: boolean): uint8;
    begin
        getHighLow := (val shr (ord (highByte) * 8)) and $ff;
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
