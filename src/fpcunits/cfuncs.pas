unit cfuncs;

interface

(* Calls to C runtime *)

const
    Clock_Realtime  = 0;
    Clock_Monotonic = 1;
    Timer_Abstime   = 1;
    
    EPERM           = 1;
    ENOENT          = 2;
    ESRCH           = 3;
    EINTR           = 4;
    EIO             = 5;
    ENXIO           = 6;
    E2BIG           = 7;
    ENOEXEC         = 8;
    EBADF           = 9;
    ECHILD          = 10;
    EAGAIN          = 11;
    ENOMEM          = 12;
    EACCES          = 13;
    EFAULT          = 14;
    ENOTBLK         = 15;
    EBUSY           = 16;
    EEXIST          = 17;
    EXDEV           = 18;
    ENODEV          = 19;
    ENOTDIR         = 20;
    EISDIR          = 21;
    EINVAL          = 22;
    ENFILE          = 23;
    EMFILE          = 24;
    ENOTTY          = 25;
    ETXTBSY         = 26;
    EFBIG           = 27;
    ENOSPC          = 28;
    ESPIPE          = 29;
    EROFS           = 30;
    EMLINK          = 31;
    EPIPE           = 32;
    EDOM            = 33;
    ERANGE          = 34;

    O_RDONLY = 0;
    O_WRONLY = 1;
    O_RDWR = 2;
    O_CREAT = 64;
    SEEK_SET = 0;
    SEEK_CUR = 1;
    SEEK_END = 2;
    PROT_READ = 1;
    PROT_WRITE = 2;
    PROT_EXEC = 4;
    MAP_SHARED = 1;
    MAP_PRIVATE = 2;
    MAP_SHARED_VALIDATE = 3;
    
    POLLIN = 1;
    POLLOUT = 4;

type
    cfile = record end;
    fileptr = ^cfile;
    pid_t = integer;
    clockid_t = int32;
    pchar = ^char;
    
    time_t = int64;
    ptr_time_t = ^time_t;
    tm = record
        tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst: int32
    end;
    ptr_tm = ^tm;
    timespec = record
        tv_sec: time_t;
        tv_nsec: int64
    end;
    
    pollfd = record
        fd: int32;
        events, revents: int16
    end;
    ptr_pollfd = ^pollfd;

function clock_gettime (clockid: clockid_t; var res: timespec): int32; cdecl; external;
function clock_nanosleep (clockid: clockid_t; flags: int32; var request, remain: timespec): int32; cdecl; external;
function usleep (usec: uint32): int32; cdecl; external;
function time (tloc: ptr_time_t): time_t; cdecl; external;
function localtime (timep: ptr_time_t): ptr_tm; cdecl; external;

function system (command: pchar): int64; cdecl; external;

function fopen (pathname, mode: pchar): fileptr; cdecl; external;
function fclose (stream: fileptr): int64; cdecl; external;
function fread (ptr: pointer; size, nmemb: int64; stream: fileptr): int64; cdecl; external;
function fwrite (ptr: pointer; size, nmemb: int64; stream: fileptr): int64; cdecl; external;

function fork: pid_t; cdecl; external;
function waitpid (pid: pid_t; var wstatus: integer; options: integer): pid_t; cdecl; external;

function htons (n: uint16): uint16; cdecl; external;
function ntohs (n: uint16): uint16; cdecl; external;

function fdopen (pathname: pchar; flags, mode: int32): int32; cdecl; external; external 'libc' name 'open';
function fdread (fd: int32; buf: pointer; count: int64): int64; cdecl; external 'libc' name 'read';
function fdwrite (fd: int32; buf: pointer; count: int64): int64; cdecl; external 'libc' name 'write';
function lseek (fd: int32; offset: int64; whence: int32): int64; cdecl; external;
function fdclose (fd: int32): int32; cdecl; external 'libc' name 'close';
function poll (fds: ptr_pollfd; nfds: int64; timeout: int32): int32; cdecl; external;
function mmap (addr: pointer; length: int64; prot, flags, fd: int32; off_t: int64): pointer; cdecl; external;
function munmap (addr: pointer; length: int64): int32; cdecl; external;
procedure perror (s: pchar); cdecl; external;

implementation

end.