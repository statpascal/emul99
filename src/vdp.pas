unit vdp;

interface

uses types;

const
    MaxColor = 15;
    RenderWidth = 304;
    RenderHeight = 240;

type
    TPalette = 0..MaxColor;
    TScreenBitmap = array [0..RenderHeight - 1, 0..RenderWidth - 1] of TPalette;
    TRgbValue = record
        r, g, b: uint8
    end;
    TVdpCallback = procedure (var bitmap: TScreenBitmap);
    
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

function getVdpRamPtr (a: uint16): TUint8Ptr;

procedure runVdp;
procedure stopVdp;

procedure setVdpCallback (p: TVdpCallback);


implementation

uses tools, tms9901, timer, math;

const
    VdpRAMSize = 16384;
    VdpRegisterCount = 8;
    GraphicsWidth = 256;
    DrawHeight = 192;
    Invalid = -1;
    
type
    TScreenBitmapPtr = ^TPalette;

var
    commandByteBuffer: int16;
    prefetchedRead: uint8;
    readWriteAddress: uint16;

    vdpRAM: array [0..VdpRAMSize - 1] of uint8;
    vdpRegister: array [0..VdpRegisterCount - 1] of uint8;
    vdpStatus: uint8;
    
    bgColor: TPalette;
    imageTable, colorTable, colorTableMask, patternTable, patternTableMask, spriteAttributeTable, spritePatternTable: 0..VdpRAMSize - 1;
    spriteSize4, spriteMagnification, textMode, bitmapMode, multiColorMode: boolean;
    
    vdpStopped: boolean;
    vdpCallback: TVdpCallback;

procedure advanceReadWriteAddress;
    begin
        readWriteAddress := succ (readWriteAddress) mod VdpRAMSize;
        commandByteBuffer := Invalid
    end;
    
procedure prefetchReadData;
    begin
        prefetchedRead := vdpRAM [readWriteAddress];
        advanceReadWriteAddress
    end;

procedure executeCommand (command, commandByte1, commandByte2: uint8);
    begin
        if command = 2 then
            vdpRegister [commandByte2 mod VdpRegisterCount] := commandByte1
        else if command <= 1 then
            readWriteAddress := commandByte1 + 256 * commandByte2;
        if command = 0 then
            prefetchReadData;
        commandByteBuffer := Invalid
    end;

procedure vdpWriteData (b: uint8);
    begin
        vdpRAM [readWriteAddress] := b;
        advanceReadWriteAddress
    end;

procedure vdpWriteCommand (b: uint8);
    begin
        if commandByteBuffer <> Invalid then
            executeCommand (b shr 6, commandByteBuffer, b and $3f)
        else
            commandByteBuffer := b
    end;

function vdpReadData: uint8;
    begin
        vdpReadData := prefetchedRead;
        prefetchReadData
    end;

function vdpReadStatus: uint8;
    begin
        commandByteBuffer := Invalid;
        vdpReadStatus := vdpStatus;
        vdpStatus := vdpStatus and $1f;
        tms9901setVdpInterrupt (false)
    end;
    
function getVdpRamPtr (a: uint16): TUint8Ptr;
    begin
        getVdpRamPtr := addr (vdpRAM [a mod VdpRAMSize])
    end;
    

procedure setVdpCallback (p: TVdpCallback);
    begin
        vdpCallback := p
    end;    
    
procedure readVdpRegisters;
    begin
        textMode := odd (vdpRegister [1] shr 4);
        bitmapMode := odd (vdpRegister [0] shr 1);
        multiColorMode := odd (vdpRegister [1] shr 3);
        spriteMagnification := odd (vdpRegister [1]);
        spriteSize4 := odd (vdpRegister [1] shr 1);
        bgColor := vdpRegister [7] and $0f;
        
        imageTable := (vdpRegister [2] and $0f) shl 10;
        spriteAttributeTable := (vdpRegister [5] and $7f) shl 7;
        spritePatternTable := (vdpRegister [6] and $07) shl 11;
        colorTable := vdpRegister [3] shl 6;
        patternTable := (vdpRegister [4] and $07) shl 11;
        patternTableMask := pred (VdpRAMSize);
        colorTableMask := patternTableMask;
        
        if bitmapMode then
            begin
                colorTableMask := colorTable and $1fc0 or $003f;
                patternTableMask := patternTable and $1800 or (colorTableMask or $07ff * ord (textMode or multiColorMode)) and $07ff;
                colorTable := colorTable and $2000;
                patternTable := patternTable and $2000
            end
    end;

(*$POINTERMATH ON*)
procedure drawSpritesScanline (scanline: uint8; bitmapPtr: TScreenBitmapPtr);
    const
        NrSprites = 32;
        LastSpriteIndicator = $d0;
    type
        TSpriteAttribute = record
            vpos, hpos, pattern, color: uint8
        end;
    var 
        spritePixel: array [0..GraphicsWidth - 1] of boolean;
        spriteCount: uint8;
        coincidence: boolean;
        fifthSpriteIndex: 0..NrSprites - 1; 
        spriteIndex: 0..NrSprites; 
        spriteAttributePtr: ^TSpriteAttribute;
        
    procedure drawSpritePattern (xpos: int16; pattern: uint16; color: TPalette);
        var
            i: 0..15;
            j: boolean;
        begin
            if pattern <> 0 then
                for i := 15 downto 8 * ord (not spriteSize4) do
                    for j := false to spriteMagnification do
                        begin
                            if (uint16 (xpos) < GraphicsWidth) and odd (pattern shr i) then
                                if spritePixel [xpos] then
                                    coincidence := true
                                else
                                    begin
                                        if color <> 0 then
                                            bitmapPtr [xpos] := color;
                                        spritePixel [xpos] := true
                                    end;
                            inc (xpos)
                        end
        end;            
        
    procedure handleSprite (spriteIndex: uint8; var spriteAttribute: TSpriteAttribute);
        var
            ypos: int16;
            patternAddr: uint16;
            yoffset: 0..15;
        begin
            ypos := succ (spriteAttribute.vpos - 256 * ord (spriteAttribute.vpos > LastSpriteIndicator));    
            if (scanline >= ypos) and (scanline < ypos + 8 shl (ord (spriteSize4) + ord (spriteMagnification))) then
                begin
                    inc (spriteCount);
                    if spriteCount = 5 then
                        fifthSpriteIndex := spriteIndex
                    else 
                        begin
                            patternAddr := spritePatternTable + (spriteAttribute.pattern and not (3 * ord (spriteSize4))) shl 3;
                            yoffset := (scanline - ypos) shr ord (spriteMagnification);
                            drawSpritePattern (spriteAttribute.hpos - (spriteAttribute.color and $80) shr 2, vdpRAM [patternAddr + yOffset] shl 8 or vdpRAM [patternAddr + yOffset + 16], spriteAttribute.color and $0f)
                        end
                end
        end;

    begin
        fillChar (spritePixel, sizeof (spritePixel), 0);
        spriteCount := 0;
        coincidence := false;
        fifthSpriteIndex := 0;
        
        spriteIndex := 0;
        spriteAttributePtr := addr (vdpRAM [spriteAttributeTable]);
        while (spriteIndex < NrSprites) and (spriteCount < 5) and (spriteAttributePtr [spriteIndex].vpos <> LastSpriteIndicator) do
            begin
                handleSprite (spriteIndex, spriteAttributePtr [spriteIndex]);
                inc (spriteIndex)
            end;
            
        if coincidence then
            vdpStatus := vdpStatus or $20;
        if not odd (vdpStatus shr 6) then
            vdpStatus := vdpStatus and not $1f or ifthen (fifthSpriteIndex <> 0, fifthSpriteIndex or $40, min ($1f, spriteIndex))
    end;

procedure drawImageScanline (scanline: uint8; bitmapPtr: TScreenBitmapPtr);
    var
        i: 0..7;
        col: 0..39;
        offset: uint16;
        pattern, colors: uint8;
    begin
        for col := 0 to 31 + 8 * ord (textMode) do 
            begin
                offset := 8 * vdpRAM [imageTable + (4 + ord (textMode)) * (scanline and $f8) + col]  +  scanline shr (2 * ord (multiColorMode)) and $07  +  32 * (scanline and $c0) * ord (bitmapMode);
                pattern := vdpRAM [patternTable + offset and patternTableMask];	// masks set to $3fff for non-bitmap modes
                colors := ifthen (textMode, vdpRegister [7], ifthen (multiColorMode, pattern, vdpRam [colorTable + (offset shr (6 * ord (not bitmapMode))) and colorTableMask]));
                for i := 7 downto 2 * ord (textMode) do
                    bitmapPtr [7 - i] := colors shr (4 * ((ifthen (multiColorMode, $f0, pattern) shr i) and 1)) and $0f;
                inc (bitmapPtr, 8 - 2 * ord (textMode))
            end
    end;
    
procedure vdpRenderScreen;
    const
        ScanlineTime = 63898;       (* nanoseconds *)
    var
        drawWidth, vBorder, hBorder: uint16;
        image: TScreenBitmap;
        scanline: uint8;
        time: TNanoTimestamp;
    begin
        fillChar (image, sizeof (image), bgColor);
        if odd (vdpRegister [1] shr 6) then
            begin
                drawWidth := 256 - 16 * ord (textMode);
                hBorder := (RenderWidth - drawWidth) div 2;
                vBorder := (RenderHeight - DrawHeight) div 2;
                time := getCurrentTime;
                for scanline := 0 to pred (DrawHeight) do 
                    begin
                        readVdpRegisters;
                        drawImageScanline (scanline, addr (image [vBorder + scanline, hBorder]));
                        if not textMode then
                            drawSpritesScanline (scanline, addr (image [vBorder + scanline, hBorder]));
                        sleepUntil (time + scanline * ScanlineTime)
                    end
            end;
            
        vdpStatus := vdpStatus or $80;
        if odd (vdpRegister [1] shr 5) then
            tms9901setVdpInterrupt (true);
        palette [0] := palette [bgColor];
        vdpCallback (image)
    end;
    
procedure runVdp;
    const
        VdpInterval = 20 * 1000 * 1000;         (* 20 msecs for 50 fps *)
    var
        time: TNanoTimestamp;
    begin
        time := getCurrentTime;
        repeat
            vdpRenderScreen;
            inc (time, VdpInterval);
            sleepUntil (time)
        until vdpStopped
    end;
                
procedure stopVdp;
    begin
        vdpStopped := true
    end;

begin
    vdpStopped := false;
    commandByteBuffer := Invalid;
    vdpStatus := 0;
    fillChar (vdpRegister, sizeof (vdpRegister), 0);
    fillChar (vdpRAM, sizeof (vdpRAM), 0)
end.
