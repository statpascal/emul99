unit fileop;

// Thin layer encapsulating file operations

interface

const
    InvalidFileHandle = -1;

type
    TFileHandle = int32;
   
function fileOpen (fileName: string; writable, create, append, trunc: boolean): TFileHandle;
function fileWrite (handle: TFileHandle; buf: pointer; size: int64): int64;
function fileRead (handle: TFileHandle; buf: pointer; size: int64): int64;
function filePos (handle: TFileHandle): int64;
function fileSize (handle: TFileHandle): int64;
function fileEof (handle: TFileHandle): boolean;
function fileSeek (handle: TFileHandle; pos: int64): boolean;
function filePollIn (handle: TFileHandle; waitMilliSecs: int32): boolean;
function fileClose (handle: TFileHandle): boolean;
function fileLock (handle: TFileHandle): boolean;

function fileMap (handle: TFileHandle; start, length: int64): pointer;
function fileUnmap (p: pointer; length: int64): boolean;

procedure printError (msg: string);


implementation

uses cfuncs;

function fileOpen (fileName: string; writable, create, append, trunc: boolean): TFileHandle;
    begin
        fileOpen := fdopen (addr (fileName [1]), O_RDWR * ord (writable) + O_CREAT * ord (create) +
                                                 O_APPEND * ord (append) + O_TRUNC * ord (trunc), &644)
    end;
    
function fileWrite (handle: TFileHandle; buf: pointer; size: int64): int64;
    begin
        fileWrite := fdwrite (handle, buf, size)
    end;
    
function fileRead (handle: TFileHandle; buf: pointer; size: int64): int64;
    begin
        fileRead := fdread (handle, buf, size)
    end;
    
function filePos (handle: TFileHandle): int64;
    begin
        filePos := lseek (handle, 0, SEEK_CUR)
    end;
        
function fileSize (handle: TFileHandle): int64;
    var
        currentPos: int64;
    begin
        currentPos := lseek (handle, 0, SEEK_CUR);
        fileSize := lseek (handle, 0, SEEK_END);
        lseek (handle, currentPos, SEEK_SET)
    end;
    
function fileEof (handle: TFileHandle): boolean;
    begin
        fileEof := filePos (handle) = fileSize (handle)
    end;
    
function fileSeek (handle: TFileHandle; pos: int64): boolean;
    begin
        fileSeek := lseek (handle, pos, SEEK_SET) = pos
    end;
    
function filePollIn (handle: TFileHandle; waitMilliSecs: int32): boolean;
    var
        fds: pollfd;
    begin
        fds.fd := handle;
        fds.events := POLLIN;
        filePollin := (poll (addr (fds), 1, waitMilliSecs) = 1) and (fds.revents and POLLIN <> 0)
    end;
    
function fileClose (handle: TFileHandle): boolean;
    begin
        fileClose := fdclose (handle) = 0
    end;
    
function fileLock (handle: TFileHandle): boolean;
    begin
        fileLock := flock (handle, LOCK_EX) = 0
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
