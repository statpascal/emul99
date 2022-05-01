unit timer;

interface

type
    TNanoTimestamp = int64;
    
function getCurrentTime: TNanoTimestamp;
procedure nanoSleep (duration: TNanoTimestamp);
procedure sleepUntil (time: TNanoTimestamp);


implementation

uses cfuncs;

const
    second = 1000 * 1000 * 1000;
    
function getCurrentTime: TNanoTimestamp;
    var
        t: timespec;
    begin
        clock_gettime (Clock_Monotonic, t);
        getCurrentTime := t.tv_sec * second + t.tv_nsec
    end;
    
procedure nanoSleep (duration: TNanoTimestamp);
    var
        request, remain: timespec;
        result: integer;
    begin
        if duration > 0 then
            begin
                request.tv_sec := duration div second;
                request.tv_nsec := duration mod second;
                repeat
                    result := clock_nanosleep (Clock_Monotonic, 0, request, remain);
                    request := remain
                until result <> EINTR
            end;
    end;
    
procedure sleepUntil (time: TNanoTimestamp);
    begin
        nanoSleep (time - getCurrentTime)
    end;
    
end.
