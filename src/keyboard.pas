unit keyboard;

interface

type
    TKeys = (KeyEqual, KeyPoint, KeyComma, KeyM, KeyN, KeySlash, KeyFire1, KeyFire2,
             KeySpace, KeyL, KeyK, KeyJ, KeyH, KeySemicolon, KeyLeft1, KeyLeft2,
             KeyEnter, KeyO, KeyI, KeyU, KeyY, KeyP, KeyRight1, KeyRigh2,
             KeyInvalid1, Key9, Key8, Key7, Key6, Key0, KeyDown1, KeyDown2, 
             KeyFctn, Key2, Key3, Key4, Key5, Key1, KeyUp1, KeyUp2,
             KeyShift, KeyS, KeyD, keyF, KeyG, KeyA, KeyInvalid2, KeyInvalid3,
             KeyCtrl, KeyW, KeyE, KeyR, KeyT, KeyQ, KeyInvalid4, KeyInvalid5,
             KeyInvalid6, KeyX, KeyC, KeyV, KeyB, KeyZ, KeyInvalid7, KeyInvalid8);

procedure setKeyPressed (key: TKeys; pressed: boolean);
function readKeyboard (addr, col: uint8): boolean;


implementation

var
    keyboardMatrix: array [3..10, 0..7] of boolean;

function readKeyboard (addr, col: uint8): boolean;
    begin
        readKeyboard := keyboardMatrix [addr, col]
    end;
    
procedure setKeyPressed (key: TKeys; pressed: boolean);
    begin
        keyboardMatrix [3 + ord (key) div 8, ord (key) mod 8] := not pressed
    end;
    
begin
    fillChar (keyboardMatrix, sizeof (keyboardMatrix), true)    
end.
