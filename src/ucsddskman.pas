program ucsddskman;

(*$POINTERMATH ON*)
(*$linklib c*)

uses sysutils, memmap, cfuncs, tools;

const
    BlockSize = 512;
    PageSize = 1024;
    DirEntrySize = 26;
    DirBlock = 2;
    DirOffset = DirBlock * BlockSize;
    MaxFiles = 77;
    MaxVolName = 7;
    MaxFileName = 15;
    
    KindCode = 2;
    KindText = 3;
    KindData = 5;

type
    TDir = record
        firstblock, lastblock: uint16;
        filler, kind, length: uint8;
        name: array [1..MaxVolName] of char;
        eovblock, numfiles, loadtime, lastboot: uint16
    end;
    TFile = record
        firstblock, lastblock: uint16;
        status, kind, length: uint8;
        name: array [1..MaxFileName] of char;
        lastbyte, access: uint16
    end;
    TDirPtr = ^TDir;
    TFilePtr = ^TFile;
    TDiskImagePtr = ^uint8;
    
procedure errorExit (s: string);
    begin
        writeln (s);
        halt (1)
    end;
    
procedure warning (s: string);
    begin
        writeln (s)
    end;
    
function getName (p: TDiskImagePtr; len: uint8): string;
    var 
        res: string;
        i: 0..14;
    begin
        res := '';
        for i := 0 to pred (len) do
            res := res + chr (p [i]);
        getName := res
    end;
    
function dateString (val: uint16): string;
    var
        res: string;
        day, month, year: uint16;
        
    procedure appendVal (val: uint16; sep: boolean);
        begin
            if val < 10 then
                res := res + '0';
            res := res + decimalstr (val);
            if sep then
                res := res + '-'
        end;
        
    begin
        day := (val shr 4) and 31;
        month := val and 15;
        year := val shr 9;
        if year >= 70 then
            res := '19'
        else 
            res := '20';
        appendVal (year, true);
        appendVal (month, true);
        appendVal (day, false);
        dateString := res
    end;
    
function nameCompare (filePtr: TFilePtr; fn: string): boolean;
    var
        i: uint8;
    begin
        if length (fn) = filePtr^.length then
            begin
                nameCompare := true;
                for i := 1 to length (fn) do
                    if upcase (fn [i]) <> upcase (filePtr^.name [i]) then
                        nameCompare := false
            end
        else
            nameCompare := false
    end;

function getFilePtr (dsk: TDiskImagePtr; fn: string): TFilePtr;
    var
        dirPtr: TDirPtr;
        filePtr: TFilePtr;
        i: 1..MaxFiles;
    begin
        dirPtr := TDirPtr (dsk + DirOffset);
        getFilePtr := nil;
        for i := 1 to ntohs (dirPtr^.numFiles) do
            begin
                filePtr := TFilePtr (dsk + DirOffset + DirEntrySize * i);
                if nameCompare (filePtr, fn) then
                    getFilePtr := filePtr
            end
    end;
    
procedure listFile (filePtr: TFilePtr);

    function kindStr (kind: uint8): string;
        begin
            case kind of 
                KindCode:
                    kindStr := 'code';
                KindText:
                    kindStr := 'text';
                KindData:
                    kindStr := 'data'
                else
                    kindStr := '????'
            end
        end;
        
    begin
        write (ntohs (filePtr^.firstBlock):5, ' - ', pred (ntohs (filePtr^.lastBlock)):5, ' ', kindStr (filePtr^.kind), ' ');
        writeln (ntohs (filePtr^.lastbyte):5, ' ', dateString (ntohs (filePtr^.access)), ' ', getName (addr (filePtr^.name), filePtr^.length))
    end;

procedure listDir (dsk: TDiskImagePtr);
    var
        dirPtr: TDirPtr;
        i: 1..MaxFiles;
    begin
        dirPtr := TDirPtr (dsk + DirOffset);
        writeln ('Volume name: ', getName (addr (dirPtr^.name), dirPtr^.length));
        writeln ('First block: ', ntohs (dirPtr^.firstBlock));
        writeln ('Last block: ', ntohs (dirPtr^.eovblock));
        writeln ('Files: ', ntohs (dirPtr^.numFiles));
        writeln ('Last boot: ', dateString (ntohs (dirPtr^.lastboot)));
        writeln;
        for i := 1 to ntohs (dirPtr^.numFiles) do
            listFile (TFilePtr (dsk + DirOffset + DirEntrySize * i))
    end;
    
procedure dumpTextFile (dsk: TDiskImagePtr; filePtr: TFilePtr; fnout: string);
    var
        f: text;
        block: uint16;
        
    procedure dumpPage (p: TDiskImagePtr; var f: text);
        var
            q: TDiskImagePtr;
            i: uint8;
        begin
            q := p + 2 * BlockSize;
            while p < q do
                begin
                    if p^ = $10 then
                        begin
                            inc (p);
                            for i := 1 to p^ - 32 do
                                write (f, ' ')
                        end
                    else if p^ = $0d then
                        writeln (f)
                    else if p^ <> 0 then
                        write (f, chr (p^));
                    inc (p)
                end
        end;
        
    begin
        assign (f, fnout);
        rewrite (f);
        block := ntohs (filePtr^.firstBlock) + 2;
        while block < ntohs (filePtr^.lastBlock) do
            begin
                dumpPage (dsk + BlockSize * block, f);
                inc (block, 2)
            end;
        close (f)
    end;
    
procedure extractFile (dsk: TDiskImagePtr; fn, fnout: string);
    var
        filePtr: TFilePtr;
    begin
        filePtr := getFilePtr (dsk, fn);
        if filePtr <> nil then
            if filePtr^.kind <> 3 then
                writeln (fn, ' is not a text file')
            else
                dumpTextFile (dsk, filePtr, fnout)
        else
            writeln ('No file ', fn, ' found in image.')
    end;
    
function compressString (s: string): string;
    var 
        i, n: integer;
    begin
        n := 0;
        while (succ (n) < length (s)) and (s [succ (n)] = ' ') do
            inc (n);
        for i := succ (n) to length (s) do
            if not (s [i] in [#9, #32..#127])  then
                warning ('Invalid character #' + decimalstr (ord (s [i])) + ' in file');
        if n > 2 then 
            s := chr ($10) + chr (n + 32) + copy (s, succ (n), length (s) - n) + chr ($0d)
        else
            s := s + chr ($0d);
        compressString := s
    end;
    
procedure appendTextFile (dsk: TDiskImagePtr; fn, fnin: string);
    var 
        f: text;
        fileCount, firstBlock, block, lastBlock: uint16;
        dirPtr: TDirPtr;
        filePtr: TFilePtr;
        s: string;
        pageCount: 0..PageSize;
        dstPtr: TDiskImagePtr;
        currentTime: time_t;
        tm: ptr_tm;
        ucsdTimestamp: uint16;
    begin
        firstBlock := 6;
        dirPtr := TDirPtr (dsk + DirOffset);
        lastBlock := ntohs (TDirPtr (dsk + DirOffset)^.eovblock);
        if dirPtr^.numFiles <> 0 then
            firstBlock := ntohs (TFilePtr (dsk + DirOffset + DirEntrySize * ntohs (dirPtr^.numFiles))^.lastblock);
        if firstBlock + 4 > lastBlock then
            errorExit ('Disk image is full');
            
        currentTime := time (addr (currentTime));
        tm := localtime (addr (currentTime));
        ucsdTimestamp := htons ((tm^.tm_year mod 100) shl 9 + tm^.tm_mday shl 4 + succ (tm^.tm_mon));
        
        writeln ('Inserting at block: ', firstBlock, ', hightest block is: ', lastBlock);
        
        assign (f, fnin);
        reset (f);
        pageCount := 0;
        block := firstBlock;
        dstPtr := dsk + block * BlockSize;
        fillChar (dstPtr^, PageSize, 0);
        inc (dstPtr, PageSize);
        inc (block, 2);
        while not eof (f) do
            begin
                readln (f, s);
                s := compressString (s);
                if pageCount + length (s) > PageSize then
                    begin
                        fillChar (dstPtr^, PageSize - pageCount, 0);
                        inc (block, 2);
                        if block > lastBlock then
                            errorExit ('Disk image full - aborting');
                        pageCount := 0;
                        dstPtr := dsk + block * BlockSize
                    end;
                move (s [1], dstPtr^, length (s));
                inc (dstPtr, length (s));
                inc (pageCount, length (s))
            end;
        close (f);
        
        if pageCount > 0 then
            begin
                fillChar (dstPtr^, PageSize - pageCount, 0);
                inc (block, 2)
            end;
            
        fileCount := succ (ntohs (dirPtr^.numFiles));
        if fileCount <= MaxFiles then
            begin
                dirPtr^.numFiles := htons (fileCount);
                filePtr := TFilePtr (dsk + DirOffset + fileCount * DirEntrySize);
                filePtr^.firstBlock := htons (firstBlock);
                filePtr^.lastBlock := htons (block);
                filePtr^.lastByte := htons (BlockSize);
                filePtr^.kind := KindText;
                filePtr^.status := 0;
                filePtr^.access := ucsdTimestamp;
                filePtr^.length := length (fn);
                move (fn [1], filePtr^.name, length (fn));
                writeln ('Added local file ', fnin, ' as ', fn, ' from block ', firstBlock, ' to ', pred (block))
            end
        else
            writeln ('Directory full - cannot add file')
                        
    end;
        
    
procedure addFile (dsk: TDiskImagePtr; fn, fnin: string);
    var
        i: 1..MaxFileName;
    begin
        if not fileExists (fnin) then
            errorExit ('Local file ' + fnin + ' not found');
        if length (fn) = 0 then
            errorExit ('Cannot add empty file name');
        if getFilePtr (dsk, fn) <> nil then
            errorExit (fn + ' is already used in image');
        if length (fn) > MaxFileName then
            errorExit ('Filename ' + fn + ' too long');
        fn := upcase (fn);
        for i := 1 to length (fn) do
            if not (fn [i] in ['A'..'Z', '0'..'9', '-', '/', '\', '_', '.']) then
                errorExit ('Invalid character in filename');
        
        appendTextFile (dsk, fn, fnin)
    end;
    
procedure help;
    begin
        writeln ('Usage is:');
        writeln;
        writeln ('ucsddsk image-name list');
        writeln ('ucsddsk image-name extract ucsd-file local-file');
        writeln ('ucsddsk image-name add ucsd-file local-file')
    end;
    
procedure main;
    var
        p: TDiskImagePtr;
    begin
        p := createMapping (ParamStr (1)); 
        if p <> nil then
            begin
                if ParamStr (2) = 'list' then
                    listDir (p)
                else if ParamStr (2) = 'extract' then
                    extractFile (p, ParamStr (3), ParamStr (4))
                else if ParamStr (2) = 'add' then
                    addFile (p, ParamStr (3), ParamStr (4))
                else
                    help;
                closeAllMappings
            end
        else
            help
    end;

begin
    main
end.
