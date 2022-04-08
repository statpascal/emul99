unit timer;

interface

type
    TNanoTimestamp = int64;
    
function getCurrentTime: TNanoTimestamp;
procedure nanoSleep (duration: TNanoTimestamp);
function sleepUntil (time: TNanoTimestamp): TNanoTimestamp;


implementation

uses cfuncs;

const
    second = 1000 * 1000 * 1000;
    
function getCurrentTime: TNanoTimestamp;
    var
        dummy: integer;
        t: timespec;
    begin
        dummy := clock_gettime (Clock_Monotonic, t);
        getCurrentTime := t.tv_sec * second + t.tv_nsec
    end;
    
procedure nanoSleep (duration: TNanoTimestamp);
    var
        request, remain: timespec;
        result: integer;
    begin
        request.tv_sec := duration div second;
        request.tv_nsec := duration mod second;
        repeat
            result := clock_nanosleep (Clock_Monotonic, 0, request, remain);
            request := remain
        until result <> EINTR
    end;
    
function sleepUntil (time: TNanoTimestamp): TNanoTimestamp;
    var
        timeWait: TNanoTimestamp;
    begin
        timeWait := time - getCurrentTime;
        if timeWait > 0 then
            nanoSleep (timeWait);
        sleepUntil := timeWait;
    end;
    
end.
