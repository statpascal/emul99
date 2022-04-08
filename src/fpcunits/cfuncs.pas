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

function clock_gettime (clockid: clockid_t; var res: timespec): int32; external;
function clock_nanosleep (clockid: clockid_t; flags: int32; var request, remain: timespec): int32; external;
function usleep (usec: uint32): int32; external;
function time (tloc: ptr_time_t): time_t; external;
function localtime (timep: ptr_time_t): ptr_tm; external;

function system (command: pchar): int64; external;

function fopen (pathname, mode: pchar): fileptr; external;
function fclose (stream: fileptr): int64; external;
function fread (ptr: pointer; size, nmemb: int64; stream: fileptr): int64; external;
function fwrite (ptr: pointer; size, nmemb: int64; stream: fileptr): int64; external;

function fork: pid_t; external;
function waitpid (pid: pid_t; var wstatus: integer; options: integer): pid_t; external;

function htons (n: uint16): uint16; external;
function ntohs (n: uint16): uint16; external;

const
    O_RDONLY = 0;
    O_WRONLY = 1;
    O_RDWR = 2;
    PROT_READ = 1;
    PROT_WRITE = 2;
    PROT_EXEC = 4;
    MAP_SHARED = 1;
    MAP_PRIVATE = 2;
    MAP_SHARED_VALIDATE = 3;

function open (pathname: pchar; flags: int32): int32; external;
function mmap (addr: pointer; length: int64; prot, flags, fd: int32; off_t: int64): pointer; external;
function munmap (addr: pointer; length: int64): int32; external;
procedure  perror (s: pchar); external;

implementation

end.