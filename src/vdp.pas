unit vdp;

interface

uses types;

const
    VdpRAMSize = 16384;
    MaxColor = 15;
    
    ActiveDisplayWidth = 256;
    ActiveDisplayHeight = 192;
    TopBorder = 27;
    BottomBorder = 24;
    LeftBorder = 13; 	
    LeftBorderText = 19;
    RightBorder = 15;
    
    RenderWidth = ActiveDisplayWidth + LeftBorder + RightBorder;
    RenderHeight = ActiveDisplayHeight + TopBorder + BottomBorder;

type
    TPalette = 0..MaxColor;
    TScreenBitmap = array [0..RenderHeight - 1, 0..RenderWidth - 1] of TPalette;
    TRgbValue = record
        r, g, b: uint8
    end;
    TVdpCallback = procedure (var bitmap: TScreenBitmap);
    TVdpDirection = (VdpRead, VdpWrite);
    
const
    palette: array [TPalette] of TRgbValue = (
        (r: 0; g: 0; b: 0),        (r: 0; g: 0; b: 0),        (r: 33; g: 200; b: 66),        (r: 94; g: 220; b: 120),
        (r: 84; g: 85; b: 237),    (r: 125; g: 118; b: 252),  (r: 212; g: 82; b: 77),        (r: 66; g: 235; b: 245),
        (r: 252; g: 85; b: 84),    (r: 255; g: 121; b: 120),  (r: 212; g: 193; b: 84),       (r: 230; g: 206; b: 128),
        (r: 33; g: 176; b: 59),    (r: 201; g: 91; b: 186),   (r: 204; g: 204; b: 204),      (r: 255; g: 255; b: 255));

procedure vdpWriteData (b: uint8);
procedure vdpWriteCommand (b: uint8);
function vdpReadData: uint8;
function vdpReadStatus: uint8;

procedure vdpTransferBlock (address, size: uint16; var buf; direction: TVdpDirection);

procedure handleVDP (cycles: int64);
procedure setVdpCallback (p: TVdpCallback);


implementation

uses tools, tms9901, config, timer, math;
(*$POINTERMATH ON*)

const
    VdpRegisterCount = 8;
    Invalid = -1;
    
    FramesPerSecond = 50;	// 9929
    TotalLines = 313;		
//    FramesPerSecond = 60;	// 9918A
//    TotalLines = 262;	
    ScanlineTime = 1000 * 1000 * 1000 div (FramesPerSecond * TotalLines);
    
type
    TScreenBitmapPtr = ^TPalette;
    TSpriteAttribute = record
        vpos, hpos, pattern, color: uint8
    end;

var
    commandByte1: Invalid..$ff;
    prefetchedRead: uint8;
    readWriteAddress: uint16;

    vdpRAM: array [0..VdpRAMSize - 1] of uint8;
    vdpRegister: array [0..VdpRegisterCount - 1] of uint8;
    vdpStatus: uint8;
    
    bgColor: TPalette;
    imageTable, patternTable, colorTable, spritePatternTable: TUint8Ptr;
    spriteAttributeTable: ^TSpriteAttribute;
    colorTableMask, patternTableMask: 0..VdpRAMSize - 1;
    spriteSize4, spriteMagnification, textMode, bitmapMode, multiColorMode: boolean;
    
    vdpCallback: TVdpCallback;
    image: TScreenBitmap;

procedure advanceReadWriteAddress;
    begin
        readWriteAddress := succ (readWriteAddress) mod VdpRAMSize;
        commandByte1 := Invalid
    end;
    
procedure prefetchReadData;
    begin
        prefetchedRead := vdpRAM [readWriteAddress];
        advanceReadWriteAddress
    end;

procedure vdpWriteData (b: uint8);
    begin
        vdpRAM [readWriteAddress] := b;
        advanceReadWriteAddress
    end;

procedure vdpWriteCommand (b: uint8);
    begin
        if commandByte1 <> Invalid then
            begin
                if b shr 6 <= 1 then
                    readWriteAddress := commandByte1 + 256 * (b and $3f)
                else if b shr 6 = 2 then 
                    vdpRegister [b mod VdpRegisterCount] := commandByte1;
                if b shr 6 = 0 then
                    prefetchReadData;
                commandByte1 := Invalid
            end
        else
            commandByte1 := b
    end;

function vdpReadData: uint8;
    begin
        vdpReadData := prefetchedRead;
        prefetchReadData
    end;

function vdpReadStatus: uint8;
    begin
        commandByte1 := Invalid;
        vdpReadStatus := vdpStatus;
        vdpStatus := vdpStatus and $1f;
        tms9901setVdpInterrupt (false)
    end;
    
procedure vdpTransferBlock (address, size: uint16; var buf; direction: TVdpDirection);
    var
        p: TUint8Ptr;
        i: uint16;
    begin
        p := addr (buf);
        if size <> 0 then
            for i := 0 to pred (size) do
                if direction = VdpWrite then
                    vdpRAM [(address + i) mod VdpRAMSize] := p [i]
                else
                    p [i] := vdpRAM [(address + i) mod VdpRAMSize]
    end;

procedure setVdpCallback (p: TVdpCallback);
    begin
        vdpCallback := p
    end;    
    
procedure readVdpRegisters;
        
    function getVdpRamPtr (a: uint16): pointer;
        begin
            getVdpRamPtr := addr (vdpRAM [a mod VdpRAMSize])
        end;
        
    begin
        textMode := odd (vdpRegister [1] shr 4);
        bitmapMode := odd (vdpRegister [0] shr 1);
        multiColorMode := odd (vdpRegister [1] shr 3);
        spriteMagnification := odd (vdpRegister [1]);
        spriteSize4 := odd (vdpRegister [1] shr 1);
        bgColor := vdpRegister [7] and $0f;
        
        imageTable := getVdpRamPtr ((vdpRegister [2] and $0f) shl 10);
        spriteAttributeTable := getVdpRamPtr ((vdpRegister [5] and $7f) shl 7);
        spritePatternTable := getVdpRamPtr ((vdpRegister [6] and $07) shl 11);
        
        if bitmapMode then
            begin
                patternTable := getVdpRamPtr ((vdpRegister [4] and $04) shl 11);
                colorTable := getVdpRamPtr ((vdpRegister [3] and $80) shl 6);
                patternTableMask := (vdpRegister [4] and $03) shl 11 or ifthen (textMode or multiColorMode, $1f, vdpRegister [3] and $1f) shl 6 or $003f;
                colorTableMask := (vdpRegister [3] and $7f) shl 6 or $003f
            end
        else
            begin
                patternTable := getVdpRamPtr ((vdpRegister [4] and $07) shl 11);
                colorTable := getVdpRamPtr (vdpRegister [3] shl 6);
                patternTableMask := $3fff;
                colorTableMask := $3fff
            end
    end;

procedure drawSpritesScanline (displayLine: uint8; bitmapPtr: TScreenBitmapPtr);
    const
        NrSprites = 32;
        LastSpriteIndicator = $d0;
    var 
        spritePixel: array [0..ActiveDisplayWidth - 1] of boolean;
        coincidence: boolean;
        fifthSpriteIndex, spriteIndex, spriteCount: 0..NrSprites; 
        
    procedure drawSpritePattern (xpos: int16; p1, p2: int64; color: TPalette);
        var
            pattern: uint32;
        begin
            if spriteMagnification then
                begin // duplicate bits, see https://graphics.stanford.edu/~seander/bithacks.html
                    p1 := ((p1 * $0101010101010101) and $8040201008040201) * $0102040810204081;
                    p2 := ((p2 * $0101010101010101) and $8040201008040201) * $0102040810204081;
                    pattern := ((p1 shr 33) and $55550000 or (p1 shr 32) and $AAAA0000 or (p2 shr 49) and $5555 or (p2 shr 48) and $AAAA) shl max (0, -xpos)
                end
            else
                pattern := (p1 shl 24 or p2 shl 16) shl max (0, -xpos);
            xpos := max (0, xpos);
                            
            while (pattern <> 0) and (xpos < ActiveDisplayWidth) do
                begin
                    if odd (pattern shr 31) then
                        if spritePixel [xpos] then
                            coincidence := true
                        else
                            begin
                                if color <> 0 then
                                    bitmapPtr [xpos] := color;
                                spritePixel [xpos] := true
                            end;
                    inc (xpos);
                    pattern := uint32 (pattern shl 1)
                end
        end;     
        
    procedure handleSprite (spriteIndex: uint8; var spriteAttribute: TSpriteAttribute);
        var
            ypos: int16;
            patternAddr: TUint8Ptr;
        begin
            ypos := succ (spriteAttribute.vpos - 256 * ord (spriteAttribute.vpos > LastSpriteIndicator));    
            if (displayLine >= ypos) and (displayLine < ypos + 8 shl (ord (spriteSize4) + ord (spriteMagnification))) then
                begin
                    inc (spriteCount);
                    if spriteCount = 5 then
                        fifthSpriteIndex := spriteIndex
                    else 
                        begin
                            patternAddr := spritePatternTable + (spriteAttribute.pattern and not (3 * ord (spriteSize4))) shl 3 + (displayLine - ypos) shr ord (spriteMagnification);
                            drawSpritePattern (spriteAttribute.hpos - (spriteAttribute.color and $80) shr 2, patternAddr [0], patternAddr [16] * ord (spriteSize4), spriteAttribute.color and $0f)
                        end
                end
        end;

    begin
        fillChar (spritePixel, sizeof (spritePixel), 0);
        spriteCount := 0;
        coincidence := false;
        fifthSpriteIndex := 0;
        
        spriteIndex := 0;
        while (spriteIndex < NrSprites) and (spriteCount < 5) and (spriteAttributeTable [spriteIndex].vpos <> LastSpriteIndicator) do
            begin
                handleSprite (spriteIndex, spriteAttributeTable [spriteIndex]);
                inc (spriteIndex)
            end;
            
        if coincidence then
            vdpStatus := vdpStatus or $20;
        if not odd (vdpStatus shr 6) then
            vdpStatus := vdpStatus and not $1f or ifthen (fifthSpriteIndex <> 0, fifthSpriteIndex or $40, min ($1f, spriteIndex))
    end;

procedure drawImageScanline (displayLine: uint8; bitmapPtr: TScreenBitmapPtr);
    var
        pattern, colors: uint8;
        charEnd: TScreenBitmapPtr;
        offset: uint16;
        linePtr, lineEnd: TUint8Ptr;
    begin
        offset := (displayLine shr (2 * ord (multiColorMode))) and $07 + 32 * (displayLine and $c0) * ord (bitmapMode);
        linePtr := imageTable + (4 + ord (textMode)) * (displayLine and $f8);
        lineEnd := linePtr + 32 + 8 * ord (textMode);
        repeat
            pattern := patternTable [(8 * linePtr^ + offset) and patternTableMask];	// masks set to $3fff for non-bitmap modes
            if textMode then
                colors := vdpRegister [7]
            else if multiColorMode then
                colors := pattern
            else 
                colors := colorTable [((8 * linePtr^ + offset) shr (6 * ord (not bitmapMode))) and colorTableMask];
            if multiColorMode then 
                pattern := $f0;
            inc (linePtr);
            
            colors := colors or bgColor * (ord (colors and $0f = 0) + ord (colors and $f0 = 0) shl 4);
            charEnd := bitMapPtr + (8 - 2 * ord (textMode));
            repeat
                bitmapPtr^ := colors shr (pattern shr 5 and $04) and $0f;
                pattern := uint8 (pattern shl 1);
                inc (bitmapPtr)
            until bitmapPtr = charEnd
        until linePtr = lineEnd
    end;
    
procedure drawScanline (scanline: uint16);
    begin
        if scanline = RenderHeight then
            begin
                vdpStatus := vdpStatus or $80;
                if odd (vdpRegister [1] shr 5) then
                    tms9901setVdpInterrupt (true);
                vdpCallback (image)
            end
        else if scanline < renderHeight then
            begin
                readVdpRegisters;
                fillChar (image [scanline], RenderWidth, bgColor);
                if odd (vdpRegister [1] shr 6) and (scanline >= TopBorder) and (scanline < TopBorder + ActiveDisplayHeight) then
                    begin
                        drawImageScanline (scanline - TopBorder, addr (image [scanline, ifthen (textMode, LeftBorderText, LeftBorder)]));
                        if not textMode then
                            drawSpritesScanline (scanline - TopBorder, addr (image [scanline, LeftBorder]))
                    end
            end
    end;

procedure handleVDP (cycles: int64);
    const
        scanline: 0..TotalLines = 0;
        cyclesHandled: int64 = 0;
    begin
        while cyclesHandled < cycles do
            begin
                drawScanline (scanline);
                inc (cyclesHandled, ScanlineTime div getCycleTime);
                scanline := succ (scanline) mod TotalLines
            end
    end;
    
begin
    commandByte1 := Invalid;
    vdpStatus := 0;
    fillChar (vdpRegister, sizeof (vdpRegister), 0);
    fillChar (vdpRAM, sizeof (vdpRAM), 0)
end.