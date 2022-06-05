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

uses tools, tms9901, timer;

const
    VdpRAMSize = 16384;
    VdpRegisterCount = 8;
    GraphicsWidth = 256;
    DrawHeight = 192;
    Invalid = -1;
    
type
    TVideoMode = (StandardMode, MultiColorMode, TextMode, IllegalMode1, BitmapMode, BitmapMultiColorMode, BitmapTextMode, IllegalMode2);
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
    videoMode: TVideoMode;
    screenActive, spriteSize4, spriteMagnification: boolean;
    
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
//        if odd (vdpRegister [1] shr 5) then
            tms9901setVdpInterrupt (false)
    end;
    
function getVdpRamPtr (a: uint16): TUint8Ptr;
    begin
        getVdpRamPtr := addr (vdpRAM [a])
    end;
    
procedure resetVdp;
    begin
        commandByteBuffer := Invalid;
        vdpStatus := 0;
        fillChar (vdpRegister, sizeof (vdpRegister), 0);
        fillChar (vdpRAM, sizeof (vdpRAM), 0)
    end;

procedure setVdpCallback (p: TVdpCallback);
    begin
        vdpCallback := p
    end;    
    
procedure readVdpRegisters;
    begin
        videoMode := TVideoMode ((vdpRegister [0] and $02) shl 1 or (vdpRegister [1] and $18) shr 3);
        screenActive := odd (vdpRegister [1] shr 6);
        spriteMagnification := odd (vdpRegister [1]);
        spriteSize4 := odd (vdpRegister [1] shr 1);
        
        imageTable := (vdpRegister [2] and $0f) shl 10;
        spriteAttributeTable := (vdpRegister [5] and $7f) shl 7;
        spritePatternTable := (vdpRegister [6] and $07) shl 11;
        bgColor := vdpRegister [7] and $0f;

        if videoMode = BitmapMode then
            begin
                colorTableMask := (vdpRegister [3] and $7f) shl 6 or $003f;
                patternTableMask := (vdpRegister [4] and $03) shl 11 or colorTableMask and $07ff;
                colorTable := (vdpRegister [3] and $80) shl 6;
                patternTable := (vdpRegister [4] and $04) shl 11
            end
        else
            begin
                colorTable := vdpRegister [3] shl 6;
                patternTable := (vdpRegister [4] and $07) shl 11;
            end
    end;

(*$POINTERMATH ON*)
procedure drawSpritesScanline (scanline: uint8; bitmapPtr: TScreenBitmapPtr);
    const
        NrSprites = 32;
        LastSpriteIndicator = $D0;
    type
        TSpriteAttribute = record
            vpos, hpos, pattern, color: uint8
        end;
    var 
        spritePixel: array [0..GraphicsWidth - 1] of boolean;
        spriteCount: uint8;
        coincidence: boolean;
        fifthSpriteIndex: 0..NrSprites - 1;  (* must be at least 4 to be valid *)
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
            xpos, ypos: int16;
            patternAddr: uint16;
            yoffset: 0..15;
        begin
            ypos := succ (spriteAttribute.vpos - 256 * ord (spriteAttribute.vpos > LastSpriteIndicator));    
            if (scanline >= ypos) and (scanline < ypos + 8 shl (ord (spriteSize4) + ord (spriteMagnification))) then
                begin
                    inc (spriteCount);
                    if spriteCount = 5 then
                        fifthSpriteIndex := spriteIndex
                    else if spriteCount < 5 then
                        begin
                            xpos := spriteAttribute.hpos - (spriteAttribute.color and $80) shr 2;
                            patternAddr := spritePatternTable + (spriteAttribute.pattern and not (3 * ord (spriteSize4))) shl 3;
                            yoffset := (scanline - ypos) shr ord (spriteMagnification);
                            drawSpritePattern (xpos, vdpRAM [patternAddr + yOffset] shl 8 or vdpRAM [patternAddr + yOffset + 16], spriteAttribute.color and $0f)
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
        while (spriteIndex < NrSprites) and (spriteAttributePtr [spriteIndex].vpos <> LastSpriteIndicator) do
            begin
                if spriteCount < 5 then
                    handleSprite (spriteIndex, spriteAttributePtr [spriteIndex]);
                inc (spriteIndex);
            end;
            
        if coincidence then
            vdpStatus := vdpStatus or $20;
        if not odd (vdpStatus shr 6) then
            if fifthSpriteIndex <> 0 then
                vdpStatus := vdpStatus and not $1f or fifthSpriteIndex or $40
            else
                //  TODO: Check: should this be the last drawn on the scanline?
                vdpStatus := vdpStatus or (spriteIndex - 1) and $1f
    end;

procedure drawImageScanline (y, yOffset: uint8; bitmapPtr: TScreenBitmapPtr);

    procedure drawBitmapPattern (destPtr: TScreenBitmapPtr; pattern, colors, textOffset: uint8);
        var
            i: 0..7;
        begin
            colors := colors or bgColor * ord (colors and $0f = 0) or (bgColor shl 4) * ord (colors and $f0 = 0);
            for i := 7 downto textOffset do
                destPtr [7 - i] := colors shr (4 * ((pattern shr i) and 1)) and $0f
        end;
        
    procedure drawTextMode (imageTablePtr: TUint8Ptr);
        var
            x: 0..39;
        begin
            for x := 0 to 39 do
                drawBitmapPattern (bitmapPtr + 6 * x, vdpRAM [patternTable + imageTablePtr [x] shl 3 + yoffset], vdpRegister [7], 2)
        end;
        
    procedure drawStandardMode (imageTablePtr: TUint8Ptr);
        var
            x: 0..31;
        begin
            for x := 0 to 31 do 
                drawBitmapPattern (bitmapPtr + 8 * x, vdpRAM [patternTable + imageTablePtr [x] shl 3 + yoffset], vdpRAM [colorTable + imageTablePtr [x] shr 3], 0);
        end;
        
    procedure drawBitmapMode (imageTablePtr: TUint8Ptr);
        var
            x: 0..31;
            offset, offsetBase: uint16;
        begin
            offsetBase := (y and $f8) shl 8 + yOffset;
            for x := 0 to 31 do
                begin
                    offset := offsetBase + imageTablePtr [x] shl 3;
                    drawBitmapPattern (bitmapPtr + 8 * x, vdpRAM [patternTable + offset and patternTableMask], vdpRAM [colorTable + offset and colorTableMask], 0);
                end
        end;
        
    procedure drawMultiColorMode (scanline: uint8);
        var
            x: 0..31;
            imageTablePtr: TUint8Ptr;
        begin
            imageTablePtr := addr (vdpRAM [imageTable + (scanline and $f8) shl 2]);
            for x := 0 to 31 do
                drawBitmapPattern (bitmapPtr + 8 * x, $f0, vdpRAM [patternTable + (scanline and $1c) shr 2 + imageTableptr [x] shl 3], 0)
        end;
        
    begin                
        case videoMode of
            StandardMode:                
                drawStandardMode (getVdpRamPtr (imageTable + y shl 5));
            BitmapMode:
                drawBitmapMode (getVdpRamPtr (imageTable + y shl 5));
            TextMode:
                drawTextMode (getVdpRamPtr (imageTable + 40 * y));
            multiColorMode:
                drawMultiColorMode (y shl 3 + yOffset)
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
        fillchar (image, sizeof (image), bgColor);
        readVdpRegisters;
                
        if screenActive then
            begin
                drawWidth := 256 - 16 * ord (videoMode = TextMode);
                hBorder := (RenderWidth - drawWidth) div 2;
                vBorder := (RenderHeight - DrawHeight) div 2;
                time := getCurrentTime;
                for scanline := 0 to pred (DrawHeight) do 
                    begin
                        readVdpRegisters;
                        drawImageScanline (scanline shr 3, scanline and $07, addr (image [vBorder + scanline, hBorder]));
                        if videoMode <> TextMode then
                            drawSpritesScanline (scanline, addr (image [vBorder + scanline, hBorder]));
                        sleepUntil (time + scanline * ScanlineTime)
                    end
            end;
            
        vdpStatus := vdpStatus or $80;
        if odd (vdpRegister [1] shr 5) then
            tms9901setVdpInterrupt (true);
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
    resetVdp
end.
