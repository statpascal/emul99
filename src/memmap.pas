unit memmap;

interface

function createMapping (fn: string): pointer;
function getMappingSize (p: pointer): int64;
(* procedure closeMapping (p: pointer); *)


implementation

uses tools, fileop;

type
    TMappingNodePtr = ^TMappingNode;
    TMappingNode = record
        fn: string;
        fd: TFileHandle;
        p: pointer;
        size: int64;
        next: TMappingNodePtr
    end;
        
const
    mappings: TMappingNodePtr = nil;
    
function createMapping (fn: string): pointer;
    var
        newMapping: TMappingNode;
    begin
        newMapping.fn := fn;
        newMapping.fd := fileOpen (fn, true, false, false, false);
        newMapping.p := nil;
        newMapping.next := mappings;
        
        if newMapping.fd <> InvalidFileHandle then
            begin
                newMapping.size := fileSize (newMapping.fd);
                newMapping.p := fileMap (newMapping.fd, 0, newMapping.size);
                if newMapping.p <> nil then
                    begin
                        new (mappings);
                        mappings^ := newMapping;
                    end
            end;
        if newMapping.p = nil then
            begin
                printError ('Memory mapping of ' + fn + ' failed');
                if newMapping.fd <> InvalidFileHandle then
                    fileClose (newMapping.fd)
            end;
        createMapping := newMapping.p
    end;
    
function getMappingSize (p: pointer): int64;
    var
        ptr: TMappingNodePtr;
    begin
        ptr := mappings;
        while (ptr <> nil) and (ptr^.p <> p) do
            ptr := ptr^.next;
        if ptr <> nil then
            getMappingSize := ptr^.size
        else
            getMappingSize := 0
   end;
   
procedure closeAllMappings;
    var
        ptr: TMappingNodePtr;
    begin
        while mappings <> nil do
            begin
                fileUnmap (mappings^.p, mappings^.size);
                fileClose (mappings^.fd);
                ptr := mappings;
                mappings := mappings^.next;         
                dispose (ptr)
            end
    end;
    
finalization
    begin
        closeAllMappings
    end;

end.