unit pcode80;

interface

uses gtk3;

procedure renderPcodeScreen (cr: PCairoT);
function getPcodeScreenWidth: uint32;
function getPcodeScreenHeight: uint32;


implementation

uses memory, types;

const FontSize = 20;
      hMargin = 20;
      vMargin = 20;
      hSpacing = 12;
      vSpacing = 26;
      Width = 80;
      Height = 24;
      
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
        screenPtr: TMemoryPtr;
        y: 0..Height - 1;
        x: 0..Width - 1;
        buf: array [0..1] of char;
    begin
        screenPtr := getMemoryPtr ($2000);
        buf [1] := chr (0);
        cairo_select_font_face (cr, 'monospace', 0, 0);
        cairo_set_font_size (cr, FontSize);
        cairo_set_source_rgb (cr, 0, 0, 0);
        cairo_paint (cr);
        cairo_set_source_rgb (cr, 0, 1, 0);
        for y := 0 to Height - 1 do
            for x := 0 to Width - 1 do
                begin
                    case screenPtr^ of
                        0:
                            begin
                                cairo_rectangle (cr, hMargin + hSpacing * x, vMargin + FontSize + 9 + vSpacing * pred (y), hSpacing, vSpacing - 4);
                                cairo_fill (cr)
                            end;
                        32..127:
                            begin
                                buf [0] := chr (screenPtr^);
                                cairo_move_to (cr, hMargin + hSpacing * x, vMargin + FontSize + vSpacing * y);
                                cairo_show_text (cr, addr (buf [0]));
                                cairo_stroke (cr)
                            end
                    end;
                    inc (screenPtr)
                end
    end;
    
end.
