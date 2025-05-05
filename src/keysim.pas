unit keysim;

interface

procedure consoleSimulateKeypress;

function keyboardWaiting: boolean;
function keyboardAccepted: boolean;

implementation

uses tms9900, memory;

var 
    waiting, accepted: boolean;
    mutex: TRtlCriticalSection;
    
function keyboardWaiting: boolean;
    begin
        EnterCriticalSection (mutex);
        keyboardWaiting := waiting;
        waiting := false;
        LeaveCriticalSection (mutex)
    end;
    
function keyboardAccepted: boolean;
    begin
        EnterCriticalSection (mutex);
        keyboardAccepted := accepted;
        accepted := false;
        LeaveCriticalSection (mutex);
    end;

procedure consoleSimulateKeypress;
    var 
        R0, R6, val: uint16;
    begin
        R0 := readRegister (0);
        R6 := readRegister (6);
        val := readMemory ($8374); 
        writeMemory ($8374, val and $ff00 or r0 shr 8);
        if val shr 8 in [0,5] then 
            if R6 shr 8 = $20 then 
                begin
                    write (', ROM got: ', r0 shr 8);
                    EnterCriticalSection (mutex);
                    accepted := true;
                    LeaveCriticalSection (mutex)
                end
            else 
                begin
                    EnterCriticalSection (mutex);
                    waiting := true;
                    LeaveCriticalSection (mutex)
                end
    end;

begin
    InitCriticalSection (mutex);
end.
