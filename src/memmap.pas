unit memmap;

interface

function createMapping (fn: string): pointer;
function getMappingSize (p: pointer): int64;
(* procedure closeMapping (p: pointer); *)
procedure closeAllMappings;


implementation

uses tools, cfuncs;

type
    TMappingNodePtr = ^TMappingNode;
    TMappingNode = record
        fn: string;
        fd: int32;
        p: pointer;
        size: int64;
        next: TMappingNodePtr
    end;
        
var
    mappings: TMappingNodePtr;
    
function createMapping (fn: string): pointer;
    var
        newMapping: TMappingNode;
        ptr: TMappingNodePtr;
    begin
        newMapping.fn := fn;
        newMapping.fd := open (addr (fn [1]), O_RDWR);
        newMapping.p := nil;
        newMapping.next := mappings;
        
        if newMapping.fd <> -1 then
            begin
                newMapping.size := getFileSize (fn);
                newMapping.p := mmap (nil, newMapping.size, PROT_READ or PROT_WRITE, MAP_SHARED, newMapping.fd, 0);
            end;
        
        if newMapping.p <> nil then
            begin
                new (ptr);
                ptr^ := newMapping;
                mappings := ptr
            end
        else
            perror ('');
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
        dummy: int32;
    begin
        while mappings <> nil do
            begin
                dummy := munmap (mappings^.p, mappings^.size);
                ptr := mappings;
                mappings := mappings^.next;         
                dispose (ptr)
            end
    end;

begin
    mappings := nil
end.            