unit keysim;

interface

procedure consoleSimulateKeypress;

procedure waitKeyPolling;
procedure waitKeyAccepted;

implementation

uses tms9900, memory;

var 
    keyPolling, keyAccepted: PRTLEvent;
    
procedure waitKeyPolling;
    begin
        RTLEventWaitFor (keyPolling);
        RTLEventResetEvent (keyPolling);
    end;
    
procedure waitKeyAccepted;
    begin
        RTLEventWaitFor (keyAccepted);
        RTLEventResetEvent (keyAccepted);
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
            if R6 and $2000 <> 0 then 
                begin
                    write (', ROM got: ', r0 shr 8);
                    RTLEVentSetEvent (keyAccepted)
                end
            else 
                RTLEventSetEvent (keyPolling)
    end;

begin
    keyPolling := RTLEventCreate;
    keyAccepted := RTLEventCreate
end.
