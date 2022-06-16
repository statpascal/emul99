unit sound;

interface

const 
    SampleRate = 223722;
type
    TSampleDataPtr = ^int16;

procedure getSamples (buffer: TSampleDataPtr; len: uint32);
procedure soundWriteData (b: uint8);


implementation

uses math;

const
    ToneGenerators = 3;
    NoiseGenerator = ToneGenerators;
    MaxToneDivider = $03ff;
    MaxAttenuator = $0f;
    MaxVolume = 8000;

var
    toneDivider: array [0..ToneGenerators] of 0..MaxToneDivider;
    generatorCounter: array [0..ToneGenerators] of int32;
    generatorOutput: array [0..ToneGenerators] of -1..1;
    attenuator: array [0..ToneGenerators] of 0..MaxAttenuator;
    noiseIsWhite: boolean;
    noiseShift: uint16;
    selectedRegister: 0..ToneGenerators;
    volume: array [0..MaxAttenuator] of int16;
    
procedure setNoiseData (b: uint8);
    begin
        noiseShift := $8000;
        toneDivider [NoiseGenerator] := $20 shl (b and $03);
        noiseIsWhite := odd (b shr 2)
    end;

procedure handleData (b: uint8);
    begin
        if selectedRegister = NoiseGenerator then
            setNoiseData (b)
        else
            toneDivider [selectedRegister] := (toneDivider [selectedRegister] and $f) or (b and $3f) shl 4
    end;
    
procedure handleCommand (b: uint8);
    begin
        selectedRegister := (b shr 5) and $03;
        if odd (b shr 4) then
            attenuator [selectedRegister] := b and $0f
        else if selectedRegister = NoiseGenerator then
            setNoiseData (b)
        else
            toneDivider [selectedRegister] := b and $f
    end;
    
procedure soundWriteData (b: uint8);
    begin
        if odd (b shr 7) then
            handleCommand (b)
        else
            handleData (b)
    end;

(*$POINTERMATH ON*)
procedure getSamples (buffer: TSampleDataPtr; len: uint32);
    var 
        i: uint32;
        j: 0..ToneGenerators;
    begin
        fillChar (buffer^, 2 * len, 0);
        for j := 0 to ToneGenerators do
            if attenuator [j] <> MaxAttenuator then
                for i := 0 to pred (len div 2) do
                    begin
                        dec (generatorCounter [j]);
                        if generatorCounter [j] <= 0 then
                            if j = NoiseGenerator then
                                begin
                                    generatorCounter [NoiseGenerator] := toneDivider [NoiseGenerator - ord (toneDivider [NoiseGenerator] = $100)];
                                    noiseShift := noiseShift shr 1 or ord (odd (noiseShift shr 1) xor (noiseIsWhite and odd (noiseShift shr 3))) shl 15;
                                    generatorOutput [NoiseGenerator] := noiseShift and 1
                                end
                            else
                                begin
                                    generatorCounter [j] := toneDivider [j];
                                    generatorOutput [j] := -generatorOutput [j]
                                end;
                        inc (buffer [i], generatorOutput [j] * volume [attenuator [j]])
                    end;
    end;
      
var 
    i: 0..MaxAttenuator - 1;
    
begin
    selectedRegister := 0;
    fillChar (toneDivider, sizeof (toneDivider), 0);
    fillChar (generatorCounter, sizeof (generatorCounter), 0);
    fillChar (generatorOutput, sizeof (generatorOutput), 1);
    fillChar (attenuator, sizeof (attenuator), MaxAttenuator);
    for i := 0 to MaxAttenuator - 1 do
        volume [i] := round (MaxVolume * power (0.5, i / 5));
    volume [MaxAttenuator] := 0
end.    