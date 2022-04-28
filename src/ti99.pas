program ti99;

(*$linklib c*)

uses cthreads, gtk3, cfuncs, sdl2, timer, memmap,
     tms9900, tms9901, vdp, memory, sound, keyboard, fdccard, tape, config, tools, pcode80;

const
    KeyMapSize = 256;

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
    cpuThreadId, vdpThreadId: TThreadId;
    gtkColor: array [0..MaxColor] of uint32;
    tiImage: TScreenImage;
    newImage: boolean;
    
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
    
procedure stopSound;
    begin
        SDL_PauseAudio (1);
        SDL_CloseAudio
    end;    

function cpuThreadProc (data: pointer): ptrint;
    begin
        runCPU;
        cpuThreadProc := 0
    end;

function vdpThreadProc (data: pointer): ptrint;
    begin
        runVDP;
        vdpThreadProc := 0
    end;
    
procedure startThreads;
    begin
        beginThread (cpuThreadProc, nil, cpuThreadId);
        beginThread (vdpThreadProc, nil, vdpThreadId);
        startSound;
    end;

procedure stopThreads;
    begin
        stopSound;
        stopCPU;
        stopVDP;
        waitForThreadTerminate (cpuThreadId, 0);
        waitForThreadTerminate (vdpThreadId, 0)
    end;

procedure addKeyMapUint (val: uint16; shift, func: boolean; k: TKeys); 
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

procedure addKeyMap (ch: char; isShift, isFunction: boolean; key: TKeys);
    begin
        addKeyMapUint (ord (ch), isShift, isFunction, key)
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
    begin
        keyMapCount := 0;

        for ch := '0' to '9' do
            addKeyMap (ch, false, false, NumKeys [ch]);
        for ch := '0' to '9' do
            addKeyMap (ShiftNum [succ (ord (ch) - ord ('0'))], true, false, NumKeys [ch]);                        
        for ch := 'A' to 'Z' do
            addKeyMap (ch, true, false, AlphaKeys [ch]);
        for ch := 'a' to 'z' do
            addKeyMap (ch, false, false, AlphaKeys [upcase (ch)]);
        for i := 1 to NrFuncChar do
            addKeyMap (FuncChars [i], false, true, FuncKeys [i]);
            
        addKeyMap ('=', false, false, KeyEqual);
        addKeyMap ('+', true, false, KeyEqual);
        addKeyMap (' ', false, false, KeySpace);

        addKeyMap ('.', false, false, KeyPoint);
        addKeyMap (',', false, false, KeyComma);
        addKeyMap (';', false, false, KeySemicolon);
        addKeyMap ('/', false, false, KeySlash);

        addKeyMap ('>', true, false, KeyPoint);
        addKeyMap ('<', true, false, KeyComma);
        addKeyMap (':', true, false, KeySemicolon);
        addKeyMap ('-', true, false, KeySlash);

        addKeyMapUint (GDK_KEY_Left, false, true, KeyS);
        addKeyMapUint (GDK_KEY_Right, false, true, KeyD);
        addKeyMapUint (GDK_KEY_Up, false, true, KeyE);
        addKeyMapUint (GDK_KEY_Down, false, true, KeyX);
        addKeyMapUint (GDK_KEY_BackSpace, false, true, KeyS);
        addKeyMapUint (GDK_KEY_Return, false, false, KeyEnter);
        addKeyMapUint (GDK_KEY_Dead_Macron, true, false, Key6);
        addKeyMapUint (GDK_KEY_Dead_CircumFlex, false, true, KeyC);
        
        addKeyMapUint (GDK_KEY_Control_L, false, false, KeyCtrl);
        addKeyMapUint (GDK_KEY_Control_R, false, false, KeyCtrl);
        addKeyMapUint (GDK_KEY_Menu, false, false, KeyFctn);

        (* Joystick 1 *)
        addKeyMapUint (GDK_KEY_KP_4, false, false, KeyLeft1);
        addKeyMapUint (GDK_KEY_KP_6, false, false, KeyRight1);
        addKeyMapUint (GDK_KEY_KP_8, false, false, KeyUp1);
        addKeyMapUint (GDK_KEY_KP_2, false, false, KeyDown1);
        addKeyMapUint (GDK_KEY_Alt_L, false, false, KeyFire1);
        
        fillChar (pressCount, sizeof (pressCount), 0)
    end;    
    
procedure callPressKey (key: TKeys);
    begin
        inc (pressCount [key]);
        if pressCount [key] = 1 then
            pressKey (key)
    end;
    
procedure callReleaseKey (key: TKeys);    
    begin
        dec (pressCount [key]);
        if pressCount [key] = 0 then
            releaseKey (key)
    end;

procedure keyDown (keymap: TKeyMapEntry);
    begin
        if keyMap.isShift then
            callPressKey (KeyShift);
        if keyMap.isFunction then
            callPressKey (KeyFctn);
        callPressKey (keyMap.key)
    end;
        
procedure keyUp (var keymap: TKeyMapEntry);
    begin
        callReleaseKey (keyMap.key);
        if keyMap.isShift then
            callReleaseKey (KeyShift);
        if keyMap.isFunction then
            callReleaseKey (KeyFctn)
    end;
        
function windowKeyEvent (window: PGtkWidget; p: pointer; data: gpointer): boolean; export;
    var
        event: PTGdkEventKey;
        keyval: uint32;
        j: integer;
    begin
        event := p;
(*
        writeln ('Key event: type = ', event^.eventtype, ' key = ', event^.keyval, ' hardware val = ', hexstr (event^.hardware_keycode));
*)
        keyval := event^.keyval;
        windowKeyEvent := false;
        for j := 1 to KeyMapCount do
           if ord (keyMap [j].keyval) = keyval then
                begin
                    if (event^.eventtype = GDK_KEY_PRESS) and (hardwareKeyIndex [uint8 (event^.hardware_keycode)] = 0) then
                        begin
                            keyDown (keyMap [j]);
                            hardwareKeyIndex [uint8 (event^.hardware_keycode)] := j
                        end
                    else if (event^.eventtype = GDK_KEY_RELEASE) and (hardwareKeyIndex [uint8 (event^.hardware_keycode)] <> 0) then
                        begin
                            keyUp (keyMap [hardwareKeyIndex [uint8 (event^.hardware_keycode)]]);
                            hardwareKeyIndex [uint8 (event^.hardware_keycode)] := 0
                        end;
                    exit
                end
    end;

procedure preparePalette;
    var
        i: 0..MaxColor;
    begin
        for i := 0 to MaxColor do
            with palette [i] do 
                gtkColor [i] := r shl 16 + g shl 8 + b
    end;

procedure screenCallback (var image: TScreenImage);
    begin
        if compareByte (tiImage, image, sizeof (tiImage)) <> 0 then
            begin
                tiImage := image;
                newImage := true
            end;
    end;

(*$POINTERMATH ON*)    
procedure renderScreen (var image: TScreenImage; bitmap: PCairoSurface);
    var 
        y, x, stride: uint16;
        row: PChar;
        p: ^uint32 absolute row;
        q: ^TPaletteEntry;
    begin
        if newImage then 
            begin
                newImage := false;
                row := cairo_image_surface_get_data (bitmap);
                stride := cairo_image_surface_get_stride (bitmap);
                for y := 0 to pred (RenderHeight) do
                    begin
                        q := addr (image [y]);
                        for x := 0 to pred (RenderWidth) do
                            p [x] := gtkColor [q [x]];
                        inc (row, stride)
                    end
            end
    end;
    
function drawCallback (window: PGtkWidget; p: pointer; data: gpointer): boolean; export;
    var
        cr: PCairoT absolute p;
        bitmap: PCairoSurface absolute data;
    begin
        if usePcode80 then
            renderPcodeScreen (cr)
        else
            begin
                renderscreen (tiImage, bitmap);
                cairo_scale (cr, getWindowScaleWidth, getWindowScaleHeight);
                cairo_set_source_surface (cr, bitmap, 0, 0);
                cairo_paint (cr)
            end;
        drawCallback := true
    end;
    
function checkScreenUpdate (user_data: gpointer): boolean; export;
    begin
        if newImage or usePcode80 then
            gtk_widget_queue_draw (PGtkWidget (user_data));
        checkScreenUpdate := true
    end;

procedure windowClosed (sender: PGtkWidget; user_data: gpointer); export;
    begin
        gtk_main_quit
    end;

procedure main;
    var
        argv: argvector;
        argc: integer;
        window, drawingArea: PGtkWidget;
        bitmap: PCairoSurface;
    begin
        if ParamCount >= 1 then
            loadConfigFile (ParamStr (1))
        else
            loadConfigFile ('ti99.cfg');
        fillChar (tiImage, sizeof (tiImage), 0);
        preparePalette;
        
        argc := 0;
        argv := nil;
        gtk_init (argc, argv);
        window := gtk_window_new (GTK_WINDOW_TOPLEVEL);
        gtk_window_set_title (window, 'TI 99/4A Simulator');
        gtk_widget_add_events (window, GDK_KEY_PRESS_MASK);
        drawingArea := gtk_drawing_area_new;
        gtk_container_add (window, drawingArea);
        if usePcode80 then
            gtk_widget_set_size_request (drawingArea, getPcodeScreenWidth, getPcodeScreenHeight)
        else
            gtk_widget_set_size_request (drawingArea, getWindowScaleWidth * RenderWidth, getWindowScaleHeight * RenderHeight);
        bitmap := cairo_image_surface_create (1, RenderWidth, RenderHeight);

        g_signal_connect (window, 'destroy', addr (windowClosed), nil);
        g_signal_connect (window, 'key_press_event', addr (windowKeyEvent), nil);
        g_signal_connect (window, 'key_release_event', addr (windowKeyEvent), nil);
        g_signal_connect (drawingArea, 'draw', addr (drawCallback), bitmap);
        gtk_widget_show_all (window);

        fillKeyMap;
        setVDPCallback (screenCallback);    
        startThreads;
        g_timeout_add (20, addr (checkScreenUpdate), window);
        
        gtk_main;

        stopThreads;
        closeAllMappings
    end;

begin
    main
end.
