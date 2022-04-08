unit gtk3;

interface

const 
    libgtk = 'libgtk-3.so';
    libgobject = 'libgobject-2.0.so';

type 
    PChar = ^char;
    argvector = ^PChar;
    
    GtkWidget = record end;
    GtkWindow = record end;
    CairoT = record end;
    CairoSurface = record end;
    
    gpointer = pointer;
    gint = integer;
    guint = uint32;
    gfloat = double;

    PGtkWidget = ^GtkWidget;
    PGtkWindow = ^GtkWindow;
    PCairoT = ^CairoT;
    PCairoSurface = ^CairoSurface;
    GtkWindowType = (GTK_WINDOW_TOPLEVEL, GTK_WINDOW_POPUP);
    TCallback = pointer;
    
    TGdkEventKey = record
        eventtype: int32;
        window: PGtkWindow;
        send_event: boolean;
        time, state, keyval: uint32;
        length: int32;
        keystring: PChar;
        hardware_keycode: int16;
        group: uint8;
        is_modifier: boolean
    end;
    PTGdkEventKey = ^TGdkEventKey;

procedure gdk_threads_add_idle (p: TCallback; user_data: gpointer); external libgtk;
procedure g_idle_add (p: TCallback; user_data: gpointer); external libgtk;

procedure gtk_init (var argc: integer; var argv: argvector); external libgtk;
function gtk_window_new (t: GtkWindowType): PGtkWidget; external libgtk;
function gtk_button_new_with_label (title: PChar): PGtkWidget; external libgtk;
function gtk_grid_new: PGtkWidget; external libgtk;
procedure gtk_widget_show_all (w: PGtkWidget); external libgtk;
procedure gtk_window_set_title (w: PGtkWidget; title: PChar); external libgtk;
procedure gtk_widget_queue_draw (w: PGtkWidget); external libgtk;

const
    GDK_KEY_PRESS_MASK = 1024;
    GDK_KEY_PRESS = 8;
    GDK_KEY_RELEASE = 9;

procedure gtk_widget_add_events (w: PGtkWidget; events: gint); external libgtk;
procedure gtk_main; external libgtk;
procedure gtk_main_quit; external libgtk;
function g_timeout_add (interval: guint; p: TCallback; user_data: gpointer): guint; external libgtk;

function gtk_drawing_area_new: PGtkWidget; external libgtk;
procedure gtk_widget_set_size_request (widget: PGtkWidget; width, height: gint); external libgtk;

procedure gtk_container_add (container, widget: PGtkWidget); external libgtk;
procedure gtk_grid_attach (container, widget: PGtkWidget; left, top, width, height: gint); external libgtk;

procedure cairo_set_source_rgb (cr: PCairoT; r, g, b: gfloat); external libgtk;
procedure cairo_set_line_width (cr: PCairoT; width: gfloat); external libgtk;
procedure cairo_move_to (cr: PCairoT; x, y: gfloat); external libgtk;
procedure cairo_rectangle (cr: PCairoT; x, y, width, height: gfloat); external libgtk;
procedure cairo_select_font_face (cr: PCairoT; family: PChar; font_slant, font_weight: gint); external libgtk;
procedure cairo_set_font_size (cr: PCairoT; size: gfloat); external libgtk;
procedure cairo_show_text (cr: PCairoT; s: PChar); external libgtk;
procedure cairo_stroke (cr: PCairoT); external libgtk;
procedure cairo_fill (cr: PCairoT); external libgtk;
procedure cairo_paint (cr: PCairoT); external libgtk;
procedure cairo_scale (cr: PCairoT; sx, sy: double); external libgtk;
function cairo_image_surface_create (format, width, height: int32): PCairoSurface; external libgtk;
function cairo_image_surface_get_data (surface: PCairoSurface): PChar; external libgtk;
function cairo_image_surface_get_stride (surface: PCairoSurface): int32; external libgtk;
procedure cairo_set_source_surface (cr: PCairoT; surface: PCairoSurface; x, y: double); external libgtk;

procedure g_signal_connect_data (instance: PGtkWidget; detailed: PChar; handler: TCallback; user_data: gpointer; closurenotify: PChar; flags: byte); external libgobject;
procedure g_signal_connect (instance: PGtkWidget; detailed: PChar; handler: TCallback; user_data: gpointer);


const
    GDK_KEY_BackSpace = $ff08;
    GDK_KEY_Tab = $ff09;
    GDK_KEY_Return = $ff0d;
    GDK_KEY_Pause = $ff13;
    GDK_KEY_Scroll_Lock = $ff14;
    GDK_KEY_Sys_Req = $ff15;
    GDK_KEY_Escape = $ff1b;
    GDK_KEY_Delete = $ffff;
    GDK_KEY_Home = $ff50;
    GDK_KEY_Left = $ff51;
    GDK_KEY_Up = $ff52;
    GDK_KEY_Right = $ff53;
    GDK_KEY_Down = $ff54;
    GDK_KEY_Page_Up = $ff55;
    GDK_KEY_Page_Down = $ff56;
    GDK_KEY_End = $ff57;
    GDK_KEY_Begin = $ff58;
    GDK_KEY_Print = $ff61;
    GDK_KEY_Num_Lock = $ff7f;
    GDK_KEY_Dead_CircumFlex = $fe50;
    GDK_KEY_Dead_Macron = $fe52;
    GDK_KEY_F1 = $ffbe;
    GDK_KEY_F2 = $ffbf;
    GDK_KEY_F3 = $ffc0;
    GDK_KEY_F4 = $ffc1;
    GDK_KEY_F5 = $ffc2;
    GDK_KEY_F6 = $ffc3;
    GDK_KEY_F7 = $ffc4;
    GDK_KEY_F8 = $ffc5;
    GDK_KEY_F9 = $ffc6;
    GDK_KEY_F10 = $ffc7;
    GDK_KEY_F11 = $ffc8;
    GDK_KEY_F12 = $ffc9;
    GDK_KEY_KP_0 = $ffb0;
    GDK_KEY_KP_1 = $ffb1;
    GDK_KEY_KP_2 = $ffb2;
    GDK_KEY_KP_3 = $ffb3;
    GDK_KEY_KP_4 = $ffb4;
    GDK_KEY_KP_5 = $ffb5;
    GDK_KEY_KP_6 = $ffb6;
    GDK_KEY_KP_7 = $ffb7;
    GDK_KEY_KP_8 = $ffb8;
    GDK_KEY_KP_9 = $ffb9;
    GDK_KEY_Shift_L = $ffe1;
    GDK_KEY_Shift_R = $ffe2;
    GDK_KEY_Control_L = $ffe3;
    GDK_KEY_Control_R = $ffe4;
    GDK_KEY_Caps_Lock = $ffe5;
    GDK_KEY_Shift_Lock = $ffe6;
    GDK_KEY_Meta_L = $ffe7;
    GDK_KEY_Meta_R = $ffe8;
    GDK_KEY_Alt_L = $ffe9;
    GDK_KEY_Alt_R = $ffea;
    GDK_KEY_MENU = $ff67;

implementation

uses math;

procedure g_signal_connect (instance: PGtkWidget; detailed: PChar; handler: TCallback; user_data: gpointer);
    begin
	g_signal_connect_data (instance, detailed, handler, user_data, nil, 0);
    end;

begin
    setExceptionMask ([exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision, exInvalidOp])
end.
