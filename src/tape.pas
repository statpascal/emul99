unit tape;

interface

uses types;

procedure cruTapeOutput (value: TCruBit);
function cruTapeInput: TCruBit;

procedure setCassetteMotor (cs1, on: boolean);

procedure setCassetteInput (fn: string);
procedure setCassetteOutput (fn: string);


implementation

uses timer, tms9900, tools, fileop, math;

type
    TWaveHeader = record
        magic1: array [0..3] of char;	(* 'RIFF' *)
        filesize: uint32;
        magic2, magic3: array [0..3] of char;   (* 'WAVE', 'fmt '*)
        fmtlength: uint32;
        formattag, channels: uint16;
        samplerate, bytessec: uint32;
        blockalign, bitsample: uint16;
        magic4: array [0..3] of char;	(* 'data' *)
        datalength: uint32
    end;
    TToggleStatus = -1..1;
    
const
    BitCpuCycles = 2176;
    PcmSampleRate = 22050;	(* yields (almost exactly) 16 samples for an encoded bit *)
    ZeroLevel = 128;
    Spike = 100;
    SpikeSamples = 3;
    ReadThreshold = 20;
    LongPeriodThreshold = 12;
    
    PeriodSamples: array [boolean] of uint8 = (16, 8);
    waveHeader: TWaveHeader = (magic1: ('R', 'I', 'F', 'F'); filesize: 0; magic2: ('W', 'A', 'V', 'E'); magic3: ('f', 'm', 't', ' ');
                               fmtlength: 16; formattag: 1; channels: 1; samplerate: PcmSampleRate; bytessec: PcmSampleRate;
                               blockalign: 1; bitsample: 8; magic4: ('d', 'a', 't', 'a'); datalength: 0);
    pcmSamples: uint32 = 0;
    fOutput: TFileHandle = InvalidFileHandle;
    togglesInput: ^boolean = nil;	(* true if short interval *)
    togglesRecorded: int64 = 0;
    togglesAllocated: int64 = 0;
    togglesRead: int64 = 0;
    readBeginCycles: int64 = 0;
    
procedure outputWaveHeader;
    begin
        waveHeader.datalength := pcmSamples;
        waveHeader.filesize := pcmSamples + sizeof (TWaveHeader) - 8;
        fileSeek (fOutput, 0);
        fileWrite (fOutput, addr (waveHeader), sizeof (waveHeader));
        fileSeek (fOutput, waveHeader.filesize)
    end;
    
procedure setCassetteOutput (fn: string);
    begin
        fOutput := fileOpen (fn, true, true, false, true);
        if fOutput <> InvalidFileHandle then
            outputWaveHeader
        else
            writeln ('Cannot open ', fn, ' for cassette output')
    end;
    
procedure cruTapeOutput (value: TCruBit);
    const
        lastCycles: int64 = 0;
        outputVal: array [TToggleStatus] of uint8 = (ZeroLevel - Spike, ZeroLevel, ZeroLevel + Spike);
        toggleVal: TToggleStatus = 1;
    var
        i, samples: uint8;
    begin
        if (lastCycles <> 0) and (fOutput <> InvalidFileHandle) then
            begin
                samples := PeriodSamples [getCycles - lastCycles < 3 * BitCpuCycles div 4];
                for i := 1 to samples do
                    fileWrite (fOutput, addr (outputVal [toggleVal * ord (i > samples - SpikeSamples)]), 1);
                inc (pcmSamples, samples);
                toggleVal := -toggleVal
            end;
        lastCycles := getCycles
    end;
    
(*$POINTERMATH ON*)
function cruTapeInput: TCruBit;
    const 
        value: TCruBit = 0;
        nextToggle: int64 = 0;
    begin
        if togglesRead < togglesRecorded then 
            if readBeginCycles = 0 then
                readBeginCycles := getCycles
            else if getCycles - readBeginCycles >= nextToggle then
                begin
                    value := value xor 1;
                    inc (nextToggle, BitCpuCycles div (1 + ord (togglesInput [togglesRead])));
                    inc (togglesRead)
                end;
        cruTapeInput := value
    end;

procedure setCassetteMotor (cs1, on: boolean);
    begin
        if (fOutput <> InvalidFileHandle) and not on then
            outputWaveHeader;
        if on then
            readBeginCycles := 0
    end;
    
procedure setCassetteInput (fn: string);
    var 
        toggleStatus: TToggleStatus;    
        startPos, count: int64;
        f: TFileHandle;
        val: uint8;
        inputHeader: TWaveHeader;
        
    function checkHeader (var header: TWaveHeader): boolean;
        var
            headerRequired: TWaveHeader;
        begin
            headerRequired := waveHeader;
            headerRequired.filesize := header.filesize;
            headerRequired.datalength := header.datalength;
            checkHeader := compareByte (header, headerRequired, sizeof (header)) = 0
        end;
        
    procedure setStatus (status: TToggleStatus);
        begin
            if (status <> toggleStatus) and (togglesRecorded < togglesAllocated) then
                begin
                    togglesInput [togglesRecorded] := count - startPos <= LongPeriodThreshold;
                    inc (togglesRecorded);
                    toggleStatus := status;
                    startPos := count
                end
        end;
        
    begin
        toggleStatus := 0;
        count := 0;
        startPos := 0;
        f := fileOpen (fn, false, false, false, false);
        if f <> InvalidFileHandle then
            begin
                togglesAllocated := fileSize (f);	// rough upper bound for possible toggles 
                getMem (togglesInput, togglesAllocated);
                if togglesInput = nil then
                    writeln ('Cannot allocated memory for cassette input')
                else if (fileRead (f, addr (inputHeader), sizeof (inputHeader)) = sizeof (inputHeader)) and checkHeader (inputHeader) then
                    while fileRead (f, addr (val), 1) = 1 do
                        begin
                            inc (count);
                            if val < ZeroLevel - ReadThreshold then
                                setStatus (-1)
                            else if val > ZeroLevel + ReadThreshold then
                                setStatus (1)
                        end
                else
                    writeln ('Cassette input from ', fn, ' failed - WAV 22050 U8 mono required');
                fileClose (f)
            end
        else
            writeln ('Cannot open ', fn, ' for cassette input')
    end;
    
end.
