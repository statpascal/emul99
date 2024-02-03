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

var
    dsrRom: TDsrRom;
    regTd, regRd, regRc: uint8;
    transferIndex, receiveIndex: -2..65535;
    transferLength, receiveLength: uint16;
    transferBuffer, receiveBuffer: array [uint16] of uint8;
    tipiIp: string;
    tipiPort: uint16;
    s: int32;
    saddr: sockaddr_in;

procedure connectTipi;
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
    
procedure initWebsocket;
    const 
        bufSize = 65536;
    var
        buf: array [uint16] of char;
        readLen: int64;
    begin
        connectTipi;
        writeString ('GET /tipi HTTP/1.1');
        writeString ('Host: ' + tipiIp + ':' + decimalstr (tipiPort));
        writeString ('Sec-WebSocket-Key: psHIKsHVb/gYER0zwBk9NA==');
        writeString ('Connection: keep-alive, Upgrade');
        writeString ('Upgrade: websocket');
        writeString ('');
        readLen := fdread (s, addr (buf), bufSize)
    end;                
    
procedure writeWSBinary (var buffer; length: uint16);
    var
        header: record
            msg, payloadLen: uint8;
            exPayloadLen: uint16
        end;
        mask: uint32;
    begin
        header.msg := WebSock_finBinary;
        header.exPayloadLen := htons (length);
        header.payloadLen := $80 or min (WebSock_ExPayload, length);
        mask := 0;
        fdwrite (s, addr (header), 2 + 2 * ord (length >= WebSock_ExPayload));
        fdwrite (s, addr (mask), sizeof (mask));
        fdwrite (s, addr (buffer), length)
    end;
    
procedure readWSBinary (var buffer; var length: uint16; var opcode: uint8);
    var
        payloadLen: uint8;
        exPayloadLen: uint16;
    begin
        fdread (s, addr (opcode), 1);
        fdread (s, addr (payloadLen), 1);
        if payloadLen = WebSock_ExPayload then
            begin
                fdread (s, addr (exPayloadLen), 2);
                length := ntohs (exPayloadLen)
            end
        else
            length := payloadLen;
        fdread (s, addr (buffer), length);
        opcode := opcode and $7
    end;
    
procedure receiveMessage;
    var 
        opcode: uint8;
    begin
        repeat
            readWSBinary (receiveBuffer, receiveLength, opcode)
        until opcode <> $01;	// text frame
        receiveIndex := -2
    end;
    
function readReceiveBuffer: uint8;
    begin
        if receiveLength = 0 then
            receiveMessage;
        inc (receiveIndex);
        if receiveIndex = -1 then
            readReceiveBuffer := receiveLength div 256
        else if receiveIndex = 0 then
            readReceiveBuffer := receiveLength mod 256
        else 
            begin
                readReceiveBuffer := receiveBuffer [pred (receiveIndex)];
                if receiveIndex = receiveLength then 
                    receiveLength := 0;
            end
    end;
    
procedure transferMessage;
    begin
        transferIndex := -2;
        writeWSBinary (transferBuffer, transferLength)
    end;
    
procedure appendTransferBuffer (val: uint8);
    begin
        inc (transferindex);
        if transferIndex = - 1 then
            transferLength := val * 256
        else if transferIndex = 0 then
            inc (transferLength, val)
        else
            begin
                transferBuffer [pred (transferIndex)] := val;
                if transferIndex = transferLength then
                    transferMessage
            end
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
    
begin
    transferIndex := -2;
    receiveIndex := -2;
    receiveLength := 0
end.
