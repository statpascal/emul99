unit perfdata;

interface

procedure recordPerfData (address: uint16; cycles: int64);

procedure enablePerfData (fn: string);
procedure dumpPerfData;


implementation

uses types, memory, tools;

type
    TPerfData = record
        count, cycles: int64
    end;    
    
var
    perfData: array [0..MaxAddress div 2] of TPerfData;
    perfDataCart: array [0..MaxCartBanks, $3000..$3fff] of TPerfData;
    perfFilename: string;
    perfDataEnabled: boolean;
    
procedure recordPerfData (address: uint16; cycles: int64);

    procedure recordInstruction (var perfDat: TPerfData; cycles: int64);
        begin
            inc (perfDat.count);
            inc (perfDat.cycles, cycles)
        end;
    
    begin        
        if (address >= $6000) and (address < $8000) then
            recordInstruction (perfDataCart [getActiveCartBank][address div 2], cycles)
        else
            recordInstruction (perfData [address div 2], cycles)
    end;
    
procedure enablePerfData (fn: string);
    begin
        perfFilename := fn;
        perfDataEnabled := true
    end;

procedure dumpPerfData;
    var
        f: text;
        bank, address: integer;
        
    procedure printData (address: integer; perfDat: TPerfData; bank: integer);
        begin
            if perfDat.count <> 0 then
                writeln (f, hexstr (2 * address):10, bank:10, perfDat.count:10, perfDat.cycles:10)
        end;
        
    begin
        if perfDataEnabled then 
            begin
                assign (f, perfFilename);
                rewrite (f);
                writeln (f, 'Address':10, 'Bank':10, 'Count':10, 'Cycles':10);
                writeln (f);
                for address := $0000 to $2fff do
                    printData (address, perfData [address], 0);
                for bank := 0 to pred (maxCartBanks) do
                    for address := $3000 to $3fff do
                        printData (address, perfDataCart [bank, address], bank);
                for address := $4000 to $7fff do
                    printData (address, perfData [address], 0);
                close (f)
            end
    end;

end.
