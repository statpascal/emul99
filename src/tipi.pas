unit tipi;

interface

uses types;

procedure writeTipi (addr, val: uint16);
function readTipi (addr: uint16): uint16;

procedure loadTipiDsr (filename: string);
procedure initTipi (value: string);


implementation

uses tools, cfuncs, math;

const
    TipiRC = $5ff8;
    TipiRD = $5ffa;
    TipiTC = $5ffc;
    TipiTD = $5ffe;
    
    WebSock_FinBinary = $82;
    WebSock_ExPayload = 126;
    WebSock_OpText = $01;
    
    MaxTransferSize = 65535;	// actual maximum should be much lower
    
var
    dsrRom: TDsrRom;
    regTd, regRd, regRc: uint8;
    transferIndex, receiveIndex: -2..MaxTransferSize;
    transferLength, receiveLength: 0..MaxTransferSize;
    transferBuffer, receiveBuffer: array [-2..MaxTransferSize] of uint8;
    tipiIp: string;
    tipiPort: uint16;
    s: int32;
    
    
procedure transferSocket (s: int32; data: pchar; length: uint32; doRead: boolean);
    var
        count: uint32;
    begin
        count := 0;
        repeat
            if doRead then
                inc (count, max (0, fdread (s, data + count, length - count)))
            else
                inc (count, max (0, fdwrite (s, data + count, length - count)))
        until count = length
    end;

procedure readSocket (s: int32; data: pchar; length: uint32);
    begin
        transferSocket (s, data, length, true)
    end;

procedure writeSocket (s: int32; data: pchar; length: uint32);
    begin
        transferSocket (s, data, length, false);
    end;

procedure initWebsocket;
    procedure connectTipi;
        var
            saddr: sockaddr_in;
        begin
            s := socket (AF_INET, SOCK_STREAM, 0);
            saddr.sin_family := AF_INET;
            saddr.sin_addr.s_addr := inet_addr (addr (tipiIp [1]));
            saddr.sin_port := htons (tipiPort);
            if connect (s, sockaddr (saddr), sizeof (saddr)) <> 0 then
                writeln ('Connection to ', tipiIp, ':', tipiPort, ' failed')
        end;

    procedure writeString (msg: string);
        begin
            msg := msg + chr (13) + chr (10);
            fdwrite (s, addr (msg [1]), length (msg))
        end;
        
    var
        ch: char;
        count: uint8;
        
    begin
        connectTipi;
        writeString ('GET /tipi HTTP/1.1');
        writeString ('Host: ' + tipiIp + ':' + decimalstr (tipiPort));
        writeString ('Sec-WebSocket-Key: psHIKsHVb/gYER0zwBk9NA==');
        writeString ('Connection: keep-alive, Upgrade');
        writeString ('Upgrade: websocket');
        writeString ('');
        // read server reply until end of HTTP upgrade
        count := 0;
        repeat
            if fdread (s, addr (ch), 1) = 1 then
                if (ch = chr (13)) or (ch = chr (10)) then
                    inc (count)
                else
                    count := 0
        until count = 4;
        
        transferIndex := -2;
        receiveLength := 0
    end;                
    
procedure receiveMessage;
    var
        opcode, payloadLen: uint8;
        exPayloadLen, bytesRead: uint16;
    begin
        repeat
            fdread (s, addr (opcode), 1);
            fdread (s, addr (payloadLen), 1);
            if payloadLen = WebSock_ExPayload then
                begin
                    fdread (s, addr (exPayloadLen), 2);
                    receiveLength := ntohs (exPayloadLen)
                end
            else
                receiveLength := payloadLen;
            bytesRead := 0;
            repeat
                inc (bytesRead, max (0, fdread (s, addr (receiveBuffer [bytesRead]), receiveLength - bytesRead)))
            until bytesRead = receiveLength
        until opcode and $7 <> WebSock_OpText;	// skip text frame
        receiveBuffer [-2] := receiveLength div 256;
        receiveBuffer [-1] := receiveLength mod 256;
        receiveIndex := -2
    end;
    
procedure transferMessage;
    var
        header: record
            msg, payloadLen: uint8;
            exPayloadLen: uint16
        end;
        mask: uint32;
    begin
        header.msg := WebSock_finBinary;
        header.exPayloadLen := htons (transferLength);
        header.payloadLen := $80 or min (WebSock_ExPayload, transferLength);
        mask := 0;
        fdwrite (s, addr (header), 2 + 2 * ord (transferLength >= WebSock_ExPayload));
        fdwrite (s, addr (mask), sizeof (mask));
        fdwrite (s, addr (transferBuffer [0]), transferLength);
        transferIndex := -2
    end;
    
function readReceiveBuffer: uint8;
    begin
        if receiveLength = 0 then
            receiveMessage;
        readReceiveBuffer := receiveBuffer [receiveIndex];
        inc (receiveIndex);
        if receiveIndex = receiveLength then
            receiveLength := 0
    end;
    
procedure appendTransferBuffer (val: uint8);
    begin
        transferBuffer [transferIndex] := val;
        inc (transferindex);
        if transferIndex = 0 then
            transferLength := 256 * transferBuffer [-2] + transferBuffer [-1];
        if transferIndex = transferLength then
            transferMessage
    end;
    
procedure processByte (tc: uint8);
    begin
        if tc = $f1 then    // reset
            transferIndex := -2
        else if tc and $fe = $02 then
            appendTransferBuffer (regTd)
        else if tc and $fe = $06 then
            regRd := readReceiveBuffer;
        regRc := tc
    end;
    
procedure writeTipi (addr, val: uint16);
    begin
        if addr = TipiTD then
            regTd := val
        else if (addr = TipiTC) and (val <> regRc) then
            processByte (val)
    end;
    
function readTipi (addr: uint16): uint16;
    begin
        if addr = TipiRD then
            readTipi := regRd
        else if addr = TipiRC then
            readTipi := regRc
        else
            readTipi := ntohs (dsrRom.w [addr shr 1])
    end;

procedure loadTipiDsr (filename: string);
    begin
        loadBlock (dsrRom, $2000, 0, filename)
    end;

procedure initTipi (value: string);
    var
        p, code: uint16;
    begin
        p := pos (':', value);
        tipiIp := copy (value, 1, pred (p));
        val (copy (value, p + 1, 5), tipiPort, code);
        initWebsocket
    end;
    
end.
