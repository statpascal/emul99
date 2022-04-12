unit tms9901;

interface

uses types;

const
    Tms9901MaxCruAddress = 31;
    
type
    TTms9901CruAddress = 0..Tms9901MaxCruAddress;

procedure tms9901Reset;

function tms9901ReadBit (addr: TTms9901CRUAddress): TCRUBit;
procedure tms9901WriteBit (addr: TTms9901CRUAddress; value: TCRUBit);

function tms9901IsInterrupt: boolean;

procedure tms9901setVDPInterrupt (f: boolean);
procedure tms9901setPeripheralInterrupt (f: boolean);

procedure handleTimer (cycles: int64);


implementation

uses keyboard, tape, timer, tools;

var
    cruBit: array [TTms9901CruAddress] of TCRUBit;
    peripheralInterrupt, vdpInterrupt, timerInterrupt, timerMode: boolean;
    clockReg, readReg, decrementer: int16;

procedure tms9901Reset;
    begin
        fillChar (cruBit, sizeof (cruBit), 0);
        peripheralInterrupt := false;
        vdpInterrupt := false;
        timerInterrupt := false;
        timerMode := false;
        clockReg := 0;
        readReg := 0;
        decrementer := 0
    end;
    
procedure leaveTimerMode;
    begin
        timerMode := false
    end;
    
procedure enterTimerMode;
    begin
        timerMode := true;
        if clockReg <> 0 then
            readReg := decrementer
        else
            readReg := 0
    end;
    
function tms9901ReadBit (addr: TTms9901CRUAddress): TCRUBit;
    begin
        if timerMode then
            case addr of
                0:
                    tms9901ReadBit := 1;
                1..14:
                    tms9901ReadBit := ord (odd (readReg shr pred (addr)));
                15:
                    tms9901ReadBit := ord (timerInterrupt);	 (* TODO: invert bit? *)
                27:
                    tms9901ReadBit := cruTapeInput
                else
                    tms9901ReadBit := cruBit [addr]
            end
        else
            case addr of
                0:
                    tms9901ReadBit := 0;
                1:
                    tms9901ReadBit := ord (not peripheralInterrupt);
                2: 
                    tms9901ReadBit := ord (not vdpInterrupt);
                3..10:
                    tms9901ReadBit := ord (readKeyboard (addr, 4 * cruBit [20] + 2 * cruBit [19] + cruBit [18]));
                27:
                    tms9901ReadBit := cruTapeInput
                else
                    tms9901ReadBit := cruBit [addr]
            end
    end;
    
procedure tms9901WriteBit (addr: TTms9901CRUAddress; value: TCRUBit);
    begin
        if not timerMode or (addr > 14) then
            cruBit [addr] := value;
        
        if timerMode then
            case addr of 
                0:
                    if value = 0 then
                        leaveTimerMode;
                1..14:
                    begin
                        if value = 1 then
                            clockReg := clockReg or 1 shl pred (addr)
                        else
                            clockReg := clockReg and not (1 shl pred (addr));
                        decrementer := clockReg;
                    end;
                15:
                    if value = 0 then
                        tms9901Reset
                else
                    leaveTimerMode
            end;
        
        if not timerMode then
            case addr of
                0:
                    if value = 1 then
                        enterTimerMode;
                3:
                    timerInterrupt := false;
                22, 23:
                    setCassetteMotor (addr = 22, value = 1);
                25:
                    cruTapeOutput (value)
            end
    end;
    
function tms9901IsInterrupt: boolean;
    begin
        tms9901IsInterrupt := peripheralInterrupt and (cruBit [1] = 1) or 
                              vdpInterrupt and (cruBit [2] = 1) or 
                              timerInterrupt and (cruBit [3] = 1)
    end;
    
procedure tms9901setVDPInterrupt (f: boolean);
    begin
        vdpInterrupt := f
    end;

procedure tms9901setPeripheralInterrupt (f: boolean);
    begin
        (* Not used in simulator: How is it reset? *)
        peripheralInterrupt := f
    end;
    
procedure handleTimer (cycles: int64);
    const
        TickCycles = 64;
        lastCycles: int64 = 0;
    begin
        if clockReg <> 0 then
            begin
                while lastCycles + TickCycles < cycles do
                    begin
                        inc (lastCycles, TickCycles);
                        dec (decrementer);
                        if decrementer <= 0 then
                            begin
                                timerInterrupt := true;
                                decrementer := clockReg;
                            end
                    end
            end
        else
            lastCycles := cycles
    end;
    
begin
    tms9901Reset
end.
