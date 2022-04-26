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
        
const
    mappings: TMappingNodePtr = nil;
    
function createMapping (fn: string): pointer;
    var
        newMapping: TMappingNode;
    begin
        newMapping.fn := fn;
        newMapping.fd := open (addr (fn [1]), O_RDWR);
        newMapping.p := nil;
        newMapping.next := mappings;
        
        if newMapping.fd <> -1 then
            begin
                newMapping.size := getFileSize (fn);
                newMapping.p := mmap (nil, newMapping.size, PROT_READ or PROT_WRITE, MAP_SHARED, newMapping.fd, 0);
                if newMapping.p <> nil then
                    begin
                        new (mappings);
                        mappings^ := newMapping;
                    end
            end;
        if newMapping.p = nil then
            begin
                perror (addr (fn [1]));
                if newMapping.fd <> -1 then
                    fdclose (newMapping.fd)
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
                munmap (mappings^.p, mappings^.size);
                fdclose (mappings^.fd);
                ptr := mappings;
                mappings := mappings^.next;         
                dispose (ptr)
            end
    end;

end.            