unit sound;

interface

const 
    SampleRate = 223722;
type
    TSampleDataPtr = ^int16;

procedure getSamples (buffer: TSampleDataPtr; len: uint32);
procedure soundWriteData (b: uint8);


implementation

uses tools, math;

const
    ToneGenerators = 3;
    NoiseGenerator = ToneGenerators;
    MaxToneDivider = $03ff;
    MaxAttenuator = $0f;
    MaxVolume = 8000;

var
    toneDivider: array [0..ToneGenerators] of 0..MaxToneDivider;
    noiseIsWhite: boolean;
    noiseShift: uint16;
    attenuator: array [0..ToneGenerators] of 0..MaxAttenuator;
    selectedRegister: 0..ToneGenerators;
    volume: array [0..MaxAttenuator] of int16;
    silence: array [0..ToneGenerators] of 0..MaxAttenuator;
    
procedure setNoiseData (b: uint8);
    begin
        noiseShift := $8000;
        toneDivider [NoiseGenerator] := $10 shl (b and $03);
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

procedure initVolume;
    var 
        i: 0..MaxAttenuator - 1;
    begin
        for i := 0 to MaxAttenuator - 1 do
            volume [i] := round (MaxVolume * power (0.5, i / 5));
        volume [MaxAttenuator] := 0;
        fillChar (silence, sizeof (silence), MaxAttenuator)
    end;
      
(*$POINTERMATH ON*)
procedure getSamples (buffer: TSampleDataPtr; len: uint32);
    const
	generatorCounter: array [0..ToneGenerators] of int32 = (0, 0, 0, 0);
	generatorOutput: array [0..ToneGenerators] of -1..1 = (1, 1, 1, 1);
	
    procedure updateNoiseCounter;
        begin
            generatorCounter [NoiseGenerator] := toneDivider [NoiseGenerator - ord (toneDivider [NoiseGenerator] = $80)];
            if (generatorOutput [NoiseGenerator] = 1) then
                noiseShift := noiseShift shr 1 or ord (odd (noiseShift shr 1) xor (noiseIsWhite and odd (noiseShift shr 3))) shl 15
        end;
	
    procedure calculateNextSample (var v: int16);
        var
            j: 0..ToneGenerators;
        begin
            for j := 0 to ToneGenerators do 
                begin
                    dec (generatorCounter [j]);
                    if generatorCounter [j] = 0 then
                        generatorOutput [j] := -generatorOutput [j];
                    if generatorCounter [j] <= 0 then
                        if j = NoiseGenerator then
                            updateNoiseCounter
                        else
                            generatorCounter [j] := toneDivider [j]
                end;
            for j := 0 to pred (ToneGenerators) do
                inc (v, generatorOutput [j] * volume [attenuator [j]]);
            if odd (noiseShift) then
                inc (v, generatorOutput [NoiseGenerator] * volume [attenuator [NoiseGenerator]])
        end;

    var 
        i: uint32;
    begin
        fillChar (buffer^, len, 0);
        if compareByte (attenuator, silence, sizeof (attenuator)) <> 0 then
            for i := 0 to pred (len div 2) do
                calculateNextSample (buffer [i])
    end;
      
begin
    selectedRegister := 0;
    fillChar (toneDivider, sizeof (toneDivider), 0);
    fillChar (attenuator, sizeof (attenuator), MaxAttenuator);
    initVolume
end.
    