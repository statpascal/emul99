unit grom;

interface

uses types;

type
    TGrom = record
        gromAddress: uint16;
        gromSecondRead, gromSecondWrite: boolean;
        data: array [0..MaxAddress] of uint8
    end;

procedure writeGromAddress (var grom: TGrom; b: uint8);
function readGromAddress (var grom: TGrom): uint8;
function readGromData (var grom: TGrom): uint8;


implementation

uses tools;

procedure writeGromAddress (var grom: TGrom; b: uint8);
    begin
        with grom do
            begin
                gromSecondRead := false;
                gromSecondWrite := not gromSecondWrite;
                setHighLow (gromAddress, gromSecondWrite, b)
            end
    end;
    
function readGromAddress (var grom: TGrom): uint8;
    begin
        with grom do
            begin
                gromSecondWrite := false;
                gromSecondRead := not gromSecondRead;
                readGromAddress := getHighLow (succ (gromAddress), gromSecondRead)
            end
    end;
    
function readGromData (var grom: TGrom): uint8;
    begin
        with grom do
            begin
                gromSecondWrite := false;
                gromSecondRead := false;
                readGromData := data [gromAddress];
		inc (gromAddress);
		if gromAddress and $1fff = $1800
		    then gromAddress := gromAddress and $e000;
            end
    end;
    
end.
