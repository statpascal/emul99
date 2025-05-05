unit tms9901;

interface

uses types;

const
    Tms9901MaxCruAddress = 31;
    
type
    TTms9901CruAddress = 0..Tms9901MaxCruAddress;
    TKeys = (KeyEqual, KeyPoint, KeyComma, KeyM, KeyN, KeySlash, KeyFire1, KeyFire2,
             KeySpace, KeyL, KeyK, KeyJ, KeyH, KeySemicolon, KeyLeft1, KeyLeft2,
             KeyEnter, KeyO, KeyI, KeyU, KeyY, KeyP, KeyRight1, KeyRigh2,
             KeyInvalid1, Key9, Key8, Key7, Key6, Key0, KeyDown1, KeyDown2, 
             KeyFctn, Key2, Key3, Key4, Key5, Key1, KeyUp1, KeyUp2,
             KeyShift, KeyS, KeyD, keyF, KeyG, KeyA, KeyInvalid2, KeyInvalid3,
             KeyCtrl, KeyW, KeyE, KeyR, KeyT, KeyQ, KeyInvalid4, KeyInvalid5,
             KeyInvalid6, KeyX, KeyC, KeyV, KeyB, KeyZ, KeyInvalid7, KeyInvalid8);


function tms9901ReadBit (addr: TTms9901CRUAddress): TCRUBit;
procedure tms9901WriteBit (addr: TTms9901CRUAddress; value: TCRUBit);

function tms9901IsInterrupt: boolean;
procedure tms9901setVDPInterrupt (f: boolean);
procedure tms9901setPeripheralInterrupt (f: boolean);

procedure setKeyPressed (key: TKeys; pressed: boolean);
function readKeyboard (addr, col: uint8): boolean;
function keyboardScanned: boolean;

procedure handleTimer (cycles: int64);


implementation

uses tape, timer, tools;

var
    cruBit: array [TTms9901CruAddress] of TCRUBit;
    peripheralInterrupt, vdpInterrupt, timerInterrupt, timerMode: boolean;
    clockReg, readReg, decrementer: int16;
    keyboardMatrix: array [3..10, 0..7] of boolean;
    keyScanDone: boolean;

function readKeyboard (addr, col: uint8): boolean;
    begin
        readKeyboard := keyboardMatrix [addr, col]
    end;
    
procedure setKeyPressed (key: TKeys; pressed: boolean);
    begin
        keyboardMatrix [3 + ord (key) div 8, ord (key) mod 8] := pressed
    end;
    
function keyboardScanned: boolean;
    begin
        keyboardScanned := keyScanDone;
        keyScanDone := false
    end;
    
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
        tms9901ReadBit := cruBit [addr];
        if timerMode then
            case addr of
                1..14:
                    tms9901ReadBit := (readReg shr pred (addr)) and 1;
                15:
                    tms9901ReadBit := ord (timerInterrupt)	 (* TODO: invert bit? *)
            end
        else
            case addr of
                1:
                    tms9901ReadBit := ord (not peripheralInterrupt);
                2: 
                    tms9901ReadBit := ord (not vdpInterrupt);
                3..10:
                    begin
                        tms9901ReadBit := ord (not keyboardMatrix [addr, 4 * cruBit [20] + 2 * cruBit [19] + cruBit [18]]);
                        if addr = 10 then
                            keyScanDone := true
                    end
            end;
        if addr = 27 then
            tms9901ReadBit := cruTapeInput
    end;
    
procedure tms9901WriteBit (addr: TTms9901CRUAddress; value: TCRUBit);
    begin
        if not (timerMode and (addr in [1..15])) then
            cruBit [addr] := value;
        
        if timerMode then
            case addr of 
                0:
                    if value = 0 then
                        timerMode := false;
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
                    timerMode := false
            end
        else
            case addr of
                0:
                    if value = 1 then
                        enterTimerMode;
                1:
                    peripheralInterrupt := false;
                2:
                    vdpInterrupt := false;
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
    tms9901Reset;
    fillChar (keyboardMatrix, sizeof (keyboardMatrix), false)
end.
