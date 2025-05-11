unit keysim;

interface

procedure consoleKscanHook;

procedure startKeyReader;
procedure stopKeyReader;

implementation

uses tms9900, memory, cfuncs, config, sysutils, fileop, tools;

var 
    simKey: uint8;
    keyDone: PRTLEvent;
    keyFifoThreadStopped: boolean;
    keyFifoThreadId: TThreadId;
    
procedure simulateKey (ch: uint8; shift, ctrl, fctn: boolean);
    const
        ShiftNum: string = ')!@#$%^&*(';
        FctnKeys = 27;
        fctnKey: array [1..FctnKeys] of record ch: char; val: uint8 end = (
            (ch: 'A'; val: 124), (ch: 'C'; val:  96), (ch: 'F'; val: 123), (ch: 'G'; val: 125),
            (ch: 'I'; val:  63), (ch: 'O'; val:  39), (ch: 'P'; val:  34), (ch: 'R'; val:  91),
            (ch: 'T'; val:  93), (ch: 'U'; val:  95), (ch: 'W'; val: 126), (ch: 'Z'; val:  92),
            (ch: 'S'; val:   8), (ch: 'D'; val:   9), (ch: 'X'; val:  10), (ch: 'E'; val:  11),
            (ch: '0'; val: 188), (ch: '1'; val:   3), (ch: '2'; val:   4), (ch: '3'; val:   7),
            (ch: '4'; val:   2), (ch: '5'; val:  14), (ch: '6'; val:  12), (ch: '7'; val:   1),
            (ch: '8'; val:   6), (ch: '9'; val:  15), (ch: '='; val:   5));
    var
        i: 1..FctnKeys;
    begin
        if ch = 10 then
            simKey := 13
        else if shift then
            case chr (ch) of
                '0'..'9':
                    simKey := ord (ShiftNum [ch - 47]);
                'a'..'z':
                    simKey := ch - 32;
                '=':
                    simKey := 43;
            end
        else if ctrl then
            case chr (ch) of
                '0'..'7':
                    simKey := 177 + (ch - 49);
                '=':
                    simKey := 157;
                '8'..'9':
                    simKey := 158 + (ch - 56);
                'A'..'Z':
                    simKey := 129 + (ch - 65);
                'a'..'z':
                    simKey := 129 + (ch - 97);
            end
        else if fctn then
            begin
                for i := 1 to FctnKeys do
                    if upcase (fctnKey [i].ch) = upcase (chr (ch)) then
                        simKey := fctnKey [i].val
            end
        else
            simKey := ch;
        RTLEventWaitFor (keyDone);        
    end;

procedure consoleKscanHook;
    var 
        R0, val: uint16;
    const
        count: int64 = 0;
    begin
        inc (count);
        R0 := readRegister (0);
        
        if odd (count) and (simKey <> 0) and (readMemory ($8374) shr 8 in [0, 5]) then
            begin
                R0 := simKey shl 8;
                writeRegister (6, readRegister (6) or $2000);
                simKey := 0;
                RTLEventSetEvent (keyDone)
            end
        else if R0 shr 8 <> 255 then
            writeln ('KEY press: ', R0 shr 8);
            
        // perform overwritten movb 0, @>8375 at >0478
        val := readMemory ($8374); 
        writeMemory ($8374, val and $ff00 or r0 shr 8);
    end;
    
function keyFifoReadThread (data: pointer): ptrint;
    var
        fd: pollfd;
        ch, n: uint8;
        fn: string;
        shift, ctrl, fctn: boolean;
    begin
        fn := getKeyInFifo;
        if not fileExists (fn) then
            mkfifo (addr (fn [1]), &600);
        fd.fd := fileOpen (fn, false, false, false, false);
        if fd.fd = InvalidFileHandle then
            errorExit ('Cannot open ' + fn + ' for key input');
        fd.events := POLLIN;
        shift := false;
        ctrl := false;
        fctn := false;
        repeat
            if (poll (addr (fd), 1, 0) > 0) and (fd.revents and POLLIN <> 0) then
                begin
                    ch := 0;
                    fileRead (fd.fd, addr (ch), 1);
                    case ch of
                        10, 32..127:
                            simulateKey (ch, shift, ctrl, fctn);
                        128:
                            shift := true;
                        129: 
                            shift := false;
                        130:
                            ctrl := true;
                        131:
                            ctrl := false;
                        132:
                            fctn := true;
                        133:
                            fctn := false;
                        251:
                            begin
                                fileRead (fd.fd, addr (n), 1);
                                usleep (uint32 (n) * 100 * 1000)
                            end;
                        252:
                            setCpuFrequency (getDefaultCpuFrequency);
                        253:
                            setCpuFrequency (1000 * 1000 * 1000);
                        254:
                            resetCpu;
                        255:
                            errorExit ('Stop code received')
                    end
                end
            else
                usleep (10000)
        until keyFifoThreadStopped;
        keyFifoReadThread := 0
    end;

procedure startKeyReader;
    begin
        if getKeyInFifo <> '' then
            beginThread (keyFifoReadThread, nil, keyFifoThreadId);
    end;    

procedure stopKeyReader;
    begin
        keyFifoThreadStopped := true;
//        if getKeyInFifo <> '' then
//            waitForThreadTerminate (keyFifoThreadId, 0)
    end;

begin
    keyDone := RTLEventCreate
end.
