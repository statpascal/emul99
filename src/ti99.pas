program ti99;

uses cthreads, gtk3, cfuncs, sdl2, timer, memmap, sysutils, fileop,
     tms9900, tms9901, vdp, memory, sound, fdccard, tape, config, tools, pcode80, keysim;

const
    KeyMapSize = 256;
    VersionString = '0.2 Beta 5';
    WindowTitle = 'Emul99';

type
    TKeyMapEntry = record
        keyval: uint16;
        isShift, isFunction: boolean;
        key: TKeys
    end;

var
    keyMap: array [1..KeyMapSize] of TKeyMapEntry;
    hardwareKeyIndex: array [uint8] of 0..KeyMapSize;
    keyMapCount: uint16;
    pressCount: array [TKeys] of int64;
    cpuThreadId: TThreadId;
    gtkColor: array [0..MaxColor] of uint32;
    currentScreenBitmap: TRenderedBitmap;
    vdpWindow, vdpWindowDrawingArea, pcodeWindow, pcodeWindowDrawingArea: PGtkWidget;
    
procedure sdlCallback (userdata, stream: pointer; len: int32); export;
    begin
        getSamples (TSampleDataPtr (stream), len)
    end;

procedure startSound;
    const
        BufferSize = 512;
    var 
        desired, obtained: SDL_AudioSpec;
    begin
        with desired do
            begin
                freq := SampleRate;
                format := AUDIO_S16;
                channels := 1;
                samples := BufferSize;
                callback := addr (sdlCallback);
                userdata := nil
            end;
        SDL_Init (SDL_INIT_AUDIO);
        SDL_OpenAudio (desired, obtained);
        SDL_PauseAudio (0)
    end;
    
function cpuThreadProc (data: pointer): ptrint;
    begin
        runCPU;
        cpuThreadProc := 0
    end;

procedure setTitleBar;
    var
        msg: string;
    begin
        str (getCpuFrequency / 1000000:1:1, msg);
        msg := 'Emul99 (' + msg + ' MHz)';
        if vdpWindow <> nil then
            gtk_window_set_title (vdpWindow, addr (msg [1]));
        if pcodeWindow <> nil then
            gtk_window_set_title (pcodeWindow, addr (msg [1]))
    end;

procedure fillKeyMap;
    const
        NumKeys: array ['0'..'9'] of TKeys = (Key0, Key1, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9);
        AlphaKeys: array ['A'..'Z'] of TKeys = (KeyA, KeyB, KeyC, KeyD, KeyE, KeyF, KeyG, KeyH, KeyI, KeyJ, KeyK, KeyL, KeyM, KeyN, KeyO, KeyP, KeyQ, KeyR, KeyS, KeyT, KeyU, KeyV, KeyW, KeyX, KeyY, KeyZ);
        ShiftNum: string = ')!@#$%^&*(';
        NrFuncChar = 12;
        FuncChars: string = '~[]_?''"|{}\`';
        FuncKeys: array [1..NrFuncChar] of TKeys = (KeyW, KeyR, KeyT, KeyU, KeyI, KeyO, KeyP, KeyA, KeyF, KeyG, KeyZ, KeyC);
    var
        ch: char;
        i: 1..NrFuncChar;
        
    procedure addKeyMap (val: uint16; shift, func: boolean; k: TKeys); 
        begin
            if keyMapCount < KeyMapSize then
                begin
                    inc (keyMapCount);
                    with keyMap [keyMapCount] do 
                        begin
                            keyval := val;
                            isShift := shift;
                            isFunction := func;
                            key := k
                        end
                end
        end;

    begin
        keyMapCount := 0;

        for ch := '0' to '9' do
            addKeyMap (ord (ch), false, false, NumKeys [ch]);
        for ch := '0' to '9' do
            addKeyMap (ord (ShiftNum [succ (ord (ch) - ord ('0'))]), true, false, NumKeys [ch]);                        
        for ch := 'A' to 'Z' do
            addKeyMap (ord (ch), true, false, AlphaKeys [ch]);
        for ch := 'a' to 'z' do
            addKeyMap (ord (ch), false, false, AlphaKeys [upcase (ch)]);
        for i := 1 to NrFuncChar do
            addKeyMap (ord (FuncChars [i]), false, true, FuncKeys [i]);
            
        addKeyMap (ord ('='), false, false, KeyEqual);
        addKeyMap (ord ('+'), true, false, KeyEqual);
        addKeyMap (ord (' '), false, false, KeySpace);

        addKeyMap (ord ('.'), false, false, KeyPoint);
        addKeyMap (ord (','), false, false, KeyComma);
        addKeyMap (ord (';'), false, false, KeySemicolon);
        addKeyMap (ord ('/'), false, false, KeySlash);

        addKeyMap (ord ('>'), true, false, KeyPoint);
        addKeyMap (ord ('<'), true, false, KeyComma);
        addKeyMap (ord (':'), true, false, KeySemicolon);
        addKeyMap (ord ('-'), true, false, KeySlash);

        addKeyMap (GDK_KEY_Left, false, true, KeyS);
        addKeyMap (GDK_KEY_Right, false, true, KeyD);
        addKeyMap (GDK_KEY_Up, false, true, KeyE);
        addKeyMap (GDK_KEY_Down, false, true, KeyX);
        addKeyMap (GDK_KEY_BackSpace, false, true, KeyS);
        addKeyMap (GDK_KEY_Return, false, false, KeyEnter);
        addKeyMap (GDK_KEY_Dead_Macron, true, false, Key6);
        addKeyMap (GDK_KEY_Dead_CircumFlex, false, true, KeyC);
        
        addKeyMap (GDK_KEY_Control_L, false, false, KeyCtrl);
        addKeyMap (GDK_KEY_Control_R, false, false, KeyCtrl);
        addKeyMap (GDK_KEY_Menu, false, false, KeyFctn);
        addKeyMap (GDK_KEY_Meta_R, false, false, KeyFctn);
        addKeyMap (GDK_KEY_ALT_L, false, false, KeyFctn);

        (* Joystick 1 *)
        addKeyMap (GDK_KEY_KP_4, false, false, KeyLeft1);
        addKeyMap (GDK_KEY_KP_6, false, false, KeyRight1);
        addKeyMap (GDK_KEY_KP_8, false, false, KeyUp1);
        addKeyMap (GDK_KEY_KP_2, false, false, KeyDown1);
        addKeyMap (GDK_KEY_KP_0, false, false, KeyFire1);
        
        fillChar (pressCount, sizeof (pressCount), 0)
    end;    
    
procedure pressKey (key: TKeys);
    begin
        inc (pressCount [key]);
        if pressCount [key] = 1 then
            setKeyPressed (key, true)
    end;
    
procedure releaseKey (key: TKeys);    
    begin
        dec (pressCount [key]);
        if pressCount [key] = 0 then
            setKeyPressed (key, false)
    end;

procedure keyDown (evKeyval: uint16; hardwareKey: uint8);
    var
        j: 1..KeyMapSize;
    begin
        for j := 1 to KeyMapCount do
            with keyMap [j] do 
                if evKeyVal = keyval then
                    begin
                        if isShift then
                            pressKey (KeyShift);
                        if isFunction then
                            pressKey (KeyFctn);
                        pressKey (key);
                        hardwareKeyIndex [hardwareKey] := j;
                        exit
                    end
    end;
        
procedure keyUp (hardwareKey: uint8);
    begin
        with keyMap [hardwareKeyIndex [hardwareKey]] do
            begin
                releaseKey (key);
                if isShift then
                    releaseKey (KeyShift);
                if isFunction then
                    releaseKey (KeyFctn);
                hardwareKeyIndex [hardwareKey] := 0
            end
    end;
        
function windowKeyEvent (window: PGtkWidget; event: PTGdkEventKey; data: gpointer): boolean; export;
    begin
//        writeln ('Key event: type = ', event^.eventtype, ' key code = ', event^.keyval, ' hardware val = ', hexstr (event^.hardware_keycode));
        if event^.eventtype = GDK_KEY_PRESS then
            begin
                case event^.keyval of
                    GDK_KEY_F5:
                        setCpuFrequency (getDefaultCpuFrequency);
                    GDK_KEY_F6:
                        setCpuFrequency (1000 * 1000 * 1000);	
                    GDK_KEY_F7:
                        if getCpuFrequency > 1000 * 1000 then
                            setCpuFrequency (getCpuFrequency - 1000 * 1000);
                    GDK_KEY_F8:
                        setCpuFrequency (getCpuFrequency + 1000 * 1000);
                end;
                if (getResetKey <> -1) and (getResetKey = event^.keyval)
                    then resetCpu;
                setTitleBar
            end;
        with event^ do
            if (eventtype = GDK_KEY_RELEASE) and (hardwareKeyIndex [hardware_keycode] <> 0) then
                keyUp (uint8 (hardware_keycode))
            else if (eventtype = GDK_KEY_PRESS) and (hardwareKeyIndex [uint8 (hardware_keycode)] = 0) then
                keyDown (keyval, uint8 (hardware_keycode));
        windowKeyEvent := false
    end;
    
procedure preparePalette;
    var
        i: 0..MaxColor;
    begin
        for i := 0 to MaxColor do
            with palette [i] do 
                gtkColor [i] := r shl 16 + g shl 8 + b
    end;

(*$POINTERMATH ON*)    
procedure renderScreen (var renderedBitmap: TRenderedBitmap; bitmap: PCairoSurface);
    var 
        y, x, stride: uint16;
        row: PChar;
        p: ^uint32 absolute row;
        q: ^TPalette;
    begin
        row := cairo_image_surface_get_data (bitmap);
        stride := cairo_image_surface_get_stride (bitmap);
        for y := 0 to pred (RenderHeight) do
            begin
                q := addr (renderedBitmap [y]);
                for x := 0 to pred (RenderWidth) do
                    p [x] := gtkColor [q [x]];
                inc (row, stride)
            end
    end;
    
function drawCallback (window: PGtkWidget; cr: PCairoT; data: gpointer): boolean; export;
    const
        bitmap: PCairoSurface = nil;
    begin
        if window = pcodeWindowDrawingArea  then
            renderPcodeScreen (cr);
        if window = vdpWindowDrawingArea then
            begin
                if bitmap = nil then
                    bitmap := cairo_image_surface_create (1, RenderWidth, RenderHeight);
                renderScreen (currentScreenBitmap, bitmap);
                cairo_scale (cr, getWindowScaleWidth, getWindowScaleHeight);
                cairo_set_source_surface (cr, bitmap, 0, 0);
                cairo_paint (cr)
            end;
        drawCallback := true
    end;
    
procedure windowClosed (sender: PGtkWidget; user_data: gpointer); export;
    begin
        if sender = vdpWindow then
            vdpWindow := nil
        else if sender = pcodeWindow then
            pcodeWindow := nil;
        if (vdpWindow = nil) and (pcodeWindow = nil) then
            gtk_main_quit
    end;

procedure queueRedraw (w: PGtkWidget); export;
    begin
        if (w = vdpWindow) or (w = pcodeWindow)	then	// Window not closed already?
            gtk_widget_queue_draw (w)
    end;    

procedure screenCallback (var renderedBitmap: TRenderedBitmap);
    begin
        if (vdpWindow <> nil) and (compareByte (currentScreenBitmap, renderedBitmap, sizeof (currentScreenBitmap)) <> 0) then
            begin
                currentScreenBitmap := renderedBitmap;
                g_idle_add (addr (queueRedraw), vdpWindow)
            end;
        if (pcodeWindow <> nil) and screenBufferChanged then 
            g_idle_add (addr (queueRedraw), pcodeWindow)
    end;
    
procedure initGui;
    var    
        argv: argvector;
        argc: integer;
        
    procedure setupWindow (var window, drawingArea: PGtkWidget; width, height: integer);
        begin
            window := gtk_window_new (GTK_WINDOW_TOPLEVEL);
            gtk_widget_add_events (window, GDK_KEY_PRESS_MASK);
            drawingArea := gtk_drawing_area_new;
            gtk_container_add (window, drawingArea);
            g_signal_connect (window, 'destroy', addr (windowClosed), nil);
            g_signal_connect (window, 'key_press_event', addr (windowKeyEvent), nil);
            g_signal_connect (window, 'key_release_event', addr (windowKeyEvent), nil);
            g_signal_connect (drawingArea, 'draw', addr (drawCallback), nil); 
            gtk_widget_set_size_request (drawingArea, width, height);
            gtk_window_set_resizable (window, false);
            gtk_widget_show_all (window);
        end;
        
    begin
        preparePalette;
        argc := 0;
        argv := nil;
        gtk_init (argc, argv);
        if usePcode80 <> PCode80_Only then
            setupWindow (vdpWindow, vdpWindowDrawingArea, RenderWidth * getWindowScaleWidth, RenderHeight * getWindowScaleHeight);
        if usePCode80 <> PCode80_None then
            setupWindow (pcodeWindow, pcodeWindowDrawingArea, getPcodeScreenWidth, getPcodeScreenHeight);
        setTitleBar
    end;

procedure startThreads;
    begin
        beginThread (cpuThreadProc, nil, cpuThreadId);
        startKeyReader;
        startSound
    end;

procedure stopThreads;
    begin
        SDL_CloseAudio;
        stopKeyReader;
        stopCPU;
        waitForThreadTerminate (cpuThreadId, 0);
    end;
    
begin
    writeln ('emul99 version ', VersionString, ' starting');
    loadConfig;
    initGui;
    fillKeyMap;
    setVDPCallback (screenCallback);    
    startThreads;
    gtk_main;
    stopThreads
end.
