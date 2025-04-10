unit pcode80;

interface

uses gtk3;

procedure renderPcodeScreen (cr: PCairoT);

function screenBufferChanged: boolean;
function getPcodeScreenWidth: uint32;
function getPcodeScreenHeight: uint32;


implementation

uses memory, types, vdp;

const 
    FontSize = 20;
    hMargin = 20;
    vMargin = 20;
    hSpacing = 12;
    vSpacing = 26;
    Width = 80;
    Height = 24;
      
var
    renderedScreen: array [0..Height - 1, 0..Width - 1] of uint8;
    
function screenBufferChanged: boolean;
    begin
        screenBufferChanged := compareByte (getPcodeScreenBuffer^, renderedScreen, Width * Height) <> 0
    end;
      
function getPcodeScreenWidth: uint32;
    begin
        getPcodeScreenWidth := 2 * hMargin + Width * hSpacing
    end;
    
function getPcodeScreenHeight: uint32;
    begin
        getPcodeScreenHeight := 2 * vMargin + Height * vSpacing
    end;

procedure renderPcodeScreen (cr: PCairoT);
    var
        x, y: integer;
        buf: array [0..1] of char;
    begin
        move (getPcodeScreenBuffer^, renderedScreen, Width * Height);
        buf [1] := chr (0);
        cairo_select_font_face (cr, 'monospace', 0, 0);
        cairo_set_font_size (cr, FontSize);
        cairo_set_source_rgb (cr, 0, 0, 0);
        cairo_paint (cr);
        cairo_set_source_rgb (cr, 1, 1, 0.4);
        for y := 0 to Height - 1 do
            for x := 0 to Width - 1 do
                case renderedScreen [y, x] of
                    0:
                        begin
                            cairo_rectangle (cr, hMargin + hSpacing * x, vMargin + FontSize + 9 + vSpacing * pred (y), hSpacing, vSpacing - 4);
                            cairo_fill (cr)
                        end;
                    32..127:
                        begin
                            buf [0] := chr (renderedScreen [y, x]);
                            cairo_move_to (cr, hMargin + hSpacing * x, vMargin + FontSize + vSpacing * y);
                            cairo_show_text (cr, addr (buf [0]));
                            cairo_stroke (cr)
                        end
                end
    end;
    
end.
