unit fileop;

// Thin layer encapsulating file operations

interface

const
    InvalidFileHandle = -1;

type
    TFileHandle = int32;
   
function fileOpen (fileName: string; writable, alwaysCreate: boolean): TFileHandle;
function fileWrite (handle: TFileHandle; buf: pointer; size: int64): int64;
function fileRead (handle: TFileHandle; buf: pointer; size: int64): int64;
function fileSize (handle: TFileHandle): int64;
function fileSeek (handle: TFileHandle; pos: int64): boolean;
function fileClose (handle: TFileHandle): boolean;

function fileMap (handle: TFileHandle; start, length: int64): pointer;
function fileUnmap (p: pointer; length: int64): boolean;

procedure printError (msg: string);


implementation

uses cfuncs;

function fileOpen (fileName: string; writable, alwaysCreate: boolean): TFileHandle;
    begin
        fileOpen := fdopen (addr (fileName [1]), O_RDWR * ord (writable) + O_CREAT * ord (alwaysCreate), &644)
    end;
    
function fileWrite (handle: TFileHandle; buf: pointer; size: int64): int64;
    begin
        fileWrite := fdwrite (handle, buf, size)
    end;
    
function fileRead (handle: TFileHandle; buf: pointer; size: int64): int64;
    begin
        fileRead := fdread (handle, buf, size)
    end;
    
function fileSize (handle: TFileHandle): int64;
    var
        currentPos: int64;
    begin
        currentPos := lseek (handle, 0, SEEK_CUR);
        fileSize := lseek (handle, 0, SEEK_END);
        lseek (handle, currentPos, SEEK_SET)
    end;
    
function fileSeek (handle: TFileHandle; pos: int64): boolean;
    begin
        fileSeek := lseek (handle, pos, SEEK_SET) = pos
    end;
    
function fileClose (handle: TFileHandle): boolean;
    begin
        fileClose := fdclose (handle) = 0
    end;
    
function fileMap (handle: TFileHandle; start, length: int64): pointer;
    begin
        fileMap := mmap (nil, length, PROT_READ or PROT_WRITE, MAP_SHARED, handle, start)
    end;
    
function fileUnmap (p: pointer; length: int64): boolean;
    begin
        fileUnmap := munmap (p, length) = 0
    end;
    
procedure printError (msg: string);
    begin
        perror (addr (msg [1]))
    end;
    
end.
