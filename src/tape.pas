unit tape;

interface

uses types;

procedure cruTapeOutput (value: TCruBit);
function cruTapeInput: TCruBit;

procedure setCassetteMotor (cs1, on: boolean);

procedure setCassetteInput (fn: string);
procedure setCassetteOutput (fn: string);


implementation

uses timer, tms9900, tools, math;

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
    
const
    BitCpuCycles = 2176;
    PcmSampleRate = 22050;	(* yields (almost exactly) 16 samples for an encoded bit *)
    PeriodSamples: array [boolean] of uint8 = (16, 8);
    ZeroLevel = 128;
    Spike = 100;
    SpikeSamples = 3;
    ReadThreshold = 20;
    LongPeriodThreshold = 12;
    waveHeader: TWaveHeader = (magic1: ('R', 'I', 'F', 'F'); filesize: 0; magic2: ('W', 'A', 'V', 'E'); magic3: ('f', 'm', 't', ' ');
                               fmtlength: 16; formattag: 1; channels: 1; samplerate: PcmSampleRate; bytessec: PcmSampleRate;
                               blockalign: 1; bitsample: 8; magic4: ('d', 'a', 't', 'a'); datalength: 0);

var
    togglesInput: ^boolean;	(* true if short interval *)
    togglesRecorded, togglesAllocated, togglesRead: int64;
    readBeginCycles: int64;
    
    fOutput: file of uint8;
    outputOpen: boolean;
    pcmSamples: uint32;    
    
procedure outputWaveHeader;
    var
        written: int64;
    begin
        waveHeader.datalength := pcmSamples;
        waveHeader.filesize := pcmSamples + sizeof (TWaveHeader) - 8;
        seek (fOutput, 0);
        blockWrite (fOutput, waveHeader, sizeof (waveHeader), written);
        seek (fOutput, waveHeader.filesize)
    end;
    
procedure setCassetteOutput (fn: string);
    begin
        (*$I-*)
        assign (fOutput, fn);
        rewrite (fOutput, 1);
        (*$I+*)
        pcmSamples := 0;
        outputOpen := IOResult = 0;
        if outputOpen then
            outputWaveHeader
        else
            writeln ('Cannot open ', fn, ' for cassette output')
    end;
    
procedure cruTapeOutput (value: TCruBit);
    const
        lastCycles: int64 = 0;
        toggleVal: -Spike..Spike = Spike;
    var
        i, samples: uint8;
    begin
        if (lastCycles <> 0) and outputOpen then
            begin
                samples := PeriodSamples [getCycles - lastCycles < 3 * BitCpuCycles div 4];
                for i := 1 to samples do
                    write (fOutput, ZeroLevel + toggleVal * ord (i > samples - SpikeSamples));
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
        if outputOpen and not on then
            outputWaveHeader;
        if on then
            readBeginCycles := 0
    end;
    
procedure setCassetteInput (fn: string);
    type
        TToggleStatus = -1..1;
    var 
        toggleStatus: TToggleStatus;    
        startPos, count, bytesRead: int64;
        f: file of uint8;
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
        
    procedure appendToggle (isShort: boolean);
        var
            q: ^boolean;
        begin
            if togglesRecorded = togglesAllocated then
                begin
                    togglesAllocated := max (2 * togglesAllocated, 100000);
                    getMem (q, togglesAllocated);
                    if (togglesInput <> nil) then
                        begin
                            move (togglesInput^, q^, togglesRecorded);
                            freeMem (togglesInput, togglesRecorded)
                        end;
                    togglesInput := q
                end;
            togglesInput [togglesRecorded] := isShort;
            inc (togglesRecorded)
        end;
                
    procedure setStatus (status: TToggleStatus);
        begin
            if status <> toggleStatus then
                begin
                    appendToggle (count - startPos <= LongPeriodThreshold);
                    toggleStatus := status;
                    startPos := count
                end
        end;
        
    begin
        toggleStatus := 0;
        togglesInput := nil;
        togglesRecorded := 0;
        togglesAllocated := 0;
        togglesRead := 0;
        count := 0;
        {$I-*}
        assign (f, fn);
        reset (f);
        {$I+}
        if IOResult = 0 then
            begin
                blockRead (f, inputHeader, sizeof (inputHeader), bytesRead);
                if (bytesRead = sizeof (inputHeader)) and checkHeader (inputHeader) then
                    while not eof (f) do
                        begin
                            read (f, val);
                            inc (count);
                            if val < ZeroLevel - ReadThreshold then
                                setStatus (-1)
                            else if val > ZeroLevel + ReadThreshold then
                                setStatus (1)
                        end
                else
                    writeln ('Cassette input from ', fn, ' failed - WAV 22050 U8 mono required');
                close (f)
            end
        else
            writeln ('Cannot open ', fn, ' for cassette input')
    end;
    
end.
