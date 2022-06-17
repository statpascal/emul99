unit vdp;

interface

uses types;

const
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

function getVdpRamPtr (a: uint16): pointer;
procedure handleVDP (cycles: int64);
procedure setVdpCallback (p: TVdpCallback);


implementation

uses tools, tms9901, config, timer, math;

const
    VdpRAMSize = 16384;
    VdpRegisterCount = 8;
    Invalid = -1;
    
    FramesPerSecond = 50;	// 60/262 for 9918A
    TotalLines = 313;		
    ScanlineTime = 1000 * 1000 * 1000 div (FramesPerSecond * TotalLines);
    
type
    TScreenBitmapPtr = ^TPalette;
    TSpriteAttribute = record
        vpos, hpos, pattern, color: uint8
    end;

var
    commandByteBuffer: int16;
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
    
function getVdpRamPtr (a: uint16): pointer;
    begin
        getVdpRamPtr := addr (vdpRAM [a mod VdpRAMSize])
    end;

procedure setVdpCallback (p: TVdpCallback);
    begin
        vdpCallback := p
    end;    
    
procedure readVdpRegisters;
    var 
        colorTableAddr, patternTableAddr: uint16;
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
        colorTableAddr := vdpRegister [3] shl 6;
        patternTableAddr := (vdpRegister [4] and $07) shl 11;
        colorTableMask := ifthen (bitmapMode, colorTableAddr and $1fc0 or $003f, pred (VdpRamSize));
        patternTableMask := ifthen (bitmapMode, patternTableAddr and $1800 or (colorTableMask or $07ff * ord (textMode or multiColorMode)) and $07ff, pred (VdpRamSize));
        patternTable := getVdpRamPtr (ifthen (bitmapMode, patternTableAddr and $2000, patternTableAddr));
        colorTable := getVdpRamPtr (ifthen (bitmapMode, colorTableAddr and $2000, colorTableAddr))
    end;

(*$POINTERMATH ON*)
procedure drawSpritesScanline (displayLine: uint8; bitmapPtr: TScreenBitmapPtr);
    const
        NrSprites = 32;
        LastSpriteIndicator = $d0;
    var 
        spritePixel: array [0..ActiveDisplayWidth - 1] of boolean;
        coincidence: boolean;
        fifthSpriteIndex, spriteIndex, spriteCount: 0..NrSprites; 
        
    procedure drawSpritePattern (xpos: int16; pattern: uint16; color: TPalette);
        var
            i: 0..15;
            j: boolean;
        begin
            if pattern <> 0 then
                for i := 15 downto 8 * ord (not spriteSize4) do
                    for j := false to spriteMagnification do
                        begin
                            if (uint16 (xpos) < ActiveDisplayWidth) and odd (pattern shr i) then
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
            patternOffset: uint16;
            yoffset: 0..15;
        begin
            ypos := succ (spriteAttribute.vpos - 256 * ord (spriteAttribute.vpos > LastSpriteIndicator));    
            if (displayLine >= ypos) and (displayLine < ypos + 8 shl (ord (spriteSize4) + ord (spriteMagnification))) then
                begin
                    inc (spriteCount);
                    if spriteCount = 5 then
                        fifthSpriteIndex := spriteIndex
                    else 
                        begin
                            patternOffset := (spriteAttribute.pattern and not (3 * ord (spriteSize4))) shl 3;
                            yoffset := (displayLine - ypos) shr ord (spriteMagnification);
                            drawSpritePattern (spriteAttribute.hpos - (spriteAttribute.color and $80) shr 2, spritePatternTable [patternOffset + yOffset] shl 8 or ifthen (spriteSize4, spritePatternTable [patternOffset + yOffset + 16], 0), spriteAttribute.color and $0f)
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
        i: 0..7;
        col: 0..39;
        offset: uint16;
        pattern, colors: uint8;
    begin
        for col := 0 to 31 + 8 * ord (textMode) do 
            begin
                offset := 8 * imageTable [(4 + ord (textMode)) * (displayLine and $f8) + col]  +  displayLine shr (2 * ord (multiColorMode)) and $07  +  32 * (displayLine and $c0) * ord (bitmapMode);
                pattern := patternTable [offset and patternTableMask];	// masks set to $3fff for non-bitmap modes
                colors := ifthen (textMode, vdpRegister [7], ifthen (multiColorMode, pattern, colorTable [offset shr (6 * ord (not bitmapMode)) and colorTableMask]));
                pattern := ifthen (multiColorMode, $f0, pattern);
                colors := colors or bgColor * (ord (colors and $0f = 0) + ord (colors and $f0 = 0) shl 4);
                for i := 7 downto 2 * ord (textMode) do
                    bitmapPtr [7 - i] := (colors shr (4 * ((pattern shr i) and 1))) and $0f;
                inc (bitmapPtr, 8 - 2 * ord (textMode))
            end
    end;
    
procedure drawScanline (scanline: uint16; bitmapPtr: TScreenBitmapPtr);
    begin
        if scanline = renderHeight then 
            begin
                vdpStatus := vdpStatus or $80;
                if odd (vdpRegister [1] shr 5) then
                    tms9901setVdpInterrupt (true);
                vdpCallback (image)
            end
        else if scanline < renderHeight then
            begin
                readVdpRegisters;
                fillChar (bitmapPtr^, RenderWidth, bgColor);
                if odd (vdpRegister [1] shr 6) and (scanline in [TopBorder..TopBorder + ActiveDisplayHeight - 1]) then
                    begin
                        drawImageScanline (scanline - TopBorder, bitmapPtr + ifthen (textMode, LeftBorderText, LeftBorder));
                        if not textMode then
                            drawSpritesScanline (scanline - TopBorder, bitmapPtr + LeftBorder)
                    end;
            end;
    end;

procedure handleVDP (cycles: int64);
    const
        scanline: 0..TotalLines = 0;
        cyclesHandled: int64 = 0;
    begin
        while cyclesHandled < cycles do
            begin
                drawScanline (scanline, addr (image [scanline]));
                inc (cyclesHandled, ScanlineTime div getCycleTime);
                scanline := succ (scanline) mod TotalLines
            end
    end;
    
begin
    commandByteBuffer := Invalid;
    vdpStatus := 0;
    fillChar (vdpRegister, sizeof (vdpRegister), 0);
    fillChar (vdpRAM, sizeof (vdpRAM), 0)
end.