unit decoder;

interface

type 
    TOpcode = (Op_IVLD, Op_LI, Op_AI, Op_ANDI, Op_ORI, Op_CI, Op_STWP, Op_STST, Op_LWPI, Op_LIMI, Op_IDLE, Op_RSET, Op_RTWP, Op_CKON, Op_CKOF, Op_LREX, 
               Op_BLWP, Op_B, Op_X, Op_CLR, Op_NEG, Op_INV, Op_INC, Op_INCT, Op_DEC, Op_DECT, Op_BL, Op_SWPB, Op_SETO, Op_ABS, Op_SRA, Op_SRL, Op_SLA, Op_SRC,
               Op_JMP, Op_JLT, Op_JLE, Op_JEQ, Op_JHE, Op_JGT, Op_JNE, Op_JNC, Op_JOC, Op_JNO, Op_JL, Op_JH, Op_JOP, Op_SBO, Op_SBZ, Op_TB, Op_COC, Op_CZC,
               Op_XOR, Op_XOP, Op_LDCR, Op_STCR, Op_MPY, Op_DIV, Op_SZC, Op_SZCB, Op_S, Op_SB, Op_C, Op_CB, Op_A, Op_AB, Op_MOV, Op_MOVB, Op_SOC, Op_SOCB);
               
    TInstructionFormat = (Format1, Format2, Format2_1, Format3, Format4, Format5, Format6, Format7, Format8, Format8_1, Format8_2, Format9);

    TInstruction = record
	opcode: TOpCode;
	instructionFormat: TInstructionFormat;
        B: boolean;        
	Td, Ts: 0..3;
        D, S, W, count: 0..15;
	disp: 0..255;
	cycles: uint8;
	instr, source, dest, imm: uint16
    end;
    
procedure decodeInstruction (instr: uint16; var result: TInstruction);
function disassembleInstruction (var instruction: TInstruction; addr: uint16): string;


implementation

uses tools;

const
    MaxInstruction = 65535;

type
    TInstructionData = record
	instructionFormat: TInstructionFormat;
	cycles: uint8;
	instructionString: string
    end;

var
    opcodeTable: array [0..MaxInstruction] of TOpcode;
    instructionData: array [TOpcode] of TInstructionData;
    decodedInstruction: array [0..MaxInstruction] of TInstruction;

procedure decodeInstruction (instr: uint16; var result: TInstruction);
    begin
        result := decodedInstruction [instr]
    end;

procedure prepareInstruction (instr: uint16; var result: TInstruction);
    const 
        ExtraCycles: array [0..3] of uint8 = (0, 4, 8, 6);

    procedure decodeGeneralSource;
        begin
            result.B := odd (instr shr 12) and (result.instructionFormat = Format1);
            result.Ts := (instr and $0030) shr 4;
            result.S := instr and $0f;
            inc (result.cycles, ExtraCycles [result.Ts] + 2 * ord (not result.B and (result.Ts = 3)))
        end;
        
    procedure decodeGeneralDestination;
        begin
            result.Td := (instr and $0C00) shr 10;
            result.D := (instr and $03C0) shr 6;
            inc (result.cycles, ExtraCycles [result.Td] + 2 * ord (not result.B and (result.Td = 3)))
        end;

    begin
	fillchar (result, sizeof (result), 0);
	result.instr := instr;
	result.opcode := opcodeTable [instr];
	result.instructionFormat := instructionData [result.opcode].instructionFormat;
	result.cycles := instructionData [result.opcode].cycles;
	
	case result.instructionFormat of
	    Format1:
	        begin
	            decodeGeneralSource;
	            decodeGeneralDestination
                end;
            Format2, Format2_1:
		result.disp := instr and $ff;
	    Format3, Format9:
	        begin
                    decodeGeneralSource;	        	
                    result.D := (instr and $03C0) shr 6
                end;
            Format4:
                begin
                    decodeGeneralSource;
                    result.count := (instr and $03C0) shr 6
                end;
            Format5:
                begin
                    result.count := (instr and $00F0) shr 4;
                    result.W := instr and $0f
                end;
            Format6:
                decodeGeneralSource;
            Format8, Format8_2:
                result.W := instr and $0f
        end;
        
        case result.opcode of
            Op_STCR:
                case result.count of
		    8:
		        inc (result.cycles, 2);
		    9..15:
		        inc (result.cycles, 16);
		    0:
		        inc (result.cycles, 18)
                end;
            Op_LDCR:
                if result.count = 0 then
                    inc (result.cycles, 32)
                else
                    inc (result.cycles, 2 * result.count)
        end 
    end;
    
function disassembleInstruction (var instruction: TInstruction; addr: uint16): string;

    function disassembleGeneralAddress (tx, x: uint8; addr: uint16): string;
        begin
            case tx of
                0:
                    disassembleGeneralAddress := 'R' + decimalstr (x);
                1:
                    disassembleGeneralAddress := '*R' + decimalstr (x);
                2:
                    if x <> 0 then
                        disassembleGeneralAddress := '@>' + hexstr (addr) + '(R' + decimalstr (x) + ')'
                    else
                        disassembleGeneralAddress := '@>' + hexstr (addr);
                3:
                    disassembleGeneralAddress := '*R' + decimalstr (x) + '+'
            end
        end;
        
    var
        res: string;
        
    begin
        res := hexstr (addr) + '  ' + hexstr (instruction.instr) + ' ';
        if (instruction.instructionFormat = Format8) or (instruction.instructionFormat = Format8_1) then
            res := res + hexstr (instruction.imm);
        if instruction.Ts = 2 then
            res := res + hexstr (instruction.source) + ' ';
        if instruction.Td = 2 then
            res := res + hexstr (instruction.dest);
        while length (res) < 22 do
            res := res + ' ';
        
        res := res + instructionData [instruction.opcode].instructionString;
        while length (res) < 27 do
            res := res + ' ';
        case instruction.instructionFormat of
            Format1:
                res := res + disassembleGeneralAddress (instruction.Ts, instruction.S, instruction.source) + ',' + disassembleGeneralAddress (instruction.Td, instruction.D, instruction.dest);
            Format2:
                res := res + '>' + hexstr (addr + 2 + 2 * int8 (instruction.disp));
            Format3, Format9:
                res := res + disassembleGeneralAddress (instruction.Ts, instruction.S, instruction.source) + ',R' + decimalstr (instruction.D);
            Format4:
                res := res + disassembleGeneralAddress (instruction.Ts, instruction.S, instruction.source) + ',' + decimalstr (instruction.count);
            Format5:
                res := res + 'R' + decimalstr (instruction.W) + ',' + decimalstr (instruction.count);
            Format6:
                res := res + disassembleGeneralAddress (instruction.Ts, instruction.S, instruction.source);
            Format8:
                res := res + 'R' + decimalstr (instruction.W) + ',>' + hexstr (instruction.imm);
            Format8_1:
                res := res + '>' + hexstr (instruction.imm);
            Format8_2:
                res := res + 'R' + decimalstr (instruction.W);
            Format2_1:
                res := res + decimalstr (instruction.disp)
        end;
        disassembleInstruction := res
    end;        


procedure createDecoderData;

    procedure enterData (opcode: TOpcode; base: uint16; instructionString: string; instructionFormat: TInstructionFormat; cycles: uint8);
        const
            opcodeBits: array [TInstructionFormat] of uint8 = (4, 8, 8, 6, 6, 8, 10, 16, 12, 12, 12, 6);
        var
            i: uint16;
        begin
            instructionData [opcode].instructionFormat := instructionFormat;
            instructionData [opcode].instructionString := instructionString;
            instructionData [opcode].cycles := cycles;
            for i := 0 to pred (1 shl (16 - opcodeBits [instructionFormat])) do
                opcodeTable [base + i] := opcode
        end;

    var
        instr: 0..MaxInstruction;
        
    begin
        fillChar (opcodeTable, sizeof (opcodeTable), ord (Op_IVLD));
        enterData (Op_IVLD, $0000, 'IVLD', Format7, 6);
        enterData (Op_LI, $0200, 'LI', Format8, 12);
        enterData (Op_AI, $0220, 'AI', Format8, 14);
        enterData (Op_ANDI, $0240, 'ANDI', Format8, 14);
        enterData (Op_ORI, $0260, 'ORI', Format8, 14);
        enterData (Op_CI, $0280, 'CI', Format8, 14);
        enterData (Op_STWP, $02a0, 'STWP', Format8_2, 8);
        enterData (Op_STST, $02c0, 'STST', Format8_2, 8);
        enterData (Op_LWPI, $02e0, 'LWPI', Format8_1, 10);
        enterData (Op_LIMI, $0300, 'LIMI', Format8_1, 16);
        enterData (Op_IDLE, $0340, 'IDLE', Format7, 12);
        enterData (Op_RSET, $0360, 'RSET', Format7, 12);
        enterData (Op_RTWP, $0380, 'RTWP', Format7, 14);
        enterData (Op_CKON, $03a0, 'CKON', Format7, 12);
        enterData (Op_CKOF, $03c0, 'CKOF', Format7, 12);
        enterData (Op_LREX, $03e0, 'LREX', Format7, 12);
        enterData (Op_BLWP, $0400, 'BLWP', Format6, 26);
        enterData (Op_B, $0440, 'B', Format6, 8);
        enterData (Op_X, $0480, 'X', Format6, 8);
        enterData (Op_CLR, $04c0, 'CLR', Format6, 10);
        enterData (Op_NEG, $0500, 'NEG', Format6, 12);
        enterData (Op_INV, $0540, 'INV', Format6, 10);
        enterData (Op_INC, $0580, 'INC', Format6, 10);
        enterData (Op_INCT, $05c0, 'INCT', Format6, 10);
        enterData (Op_DEC, $0600, 'DEC', Format6, 10);
        enterData (Op_DECT, $0640, 'DECT', Format6, 10);
        enterData (Op_BL, $0680, 'BL', Format6, 12);
        enterData (Op_SWPB, $06c0, 'SWPB', Format6, 10);
        enterData (Op_SETO, $0700, 'SETO', Format6, 10);
        enterData (Op_ABS, $0740, 'ABS', Format6, 14);
        enterData (Op_SRA, $0800, 'SRA', Format5, 12);
        enterData (Op_SRL, $0900, 'SRL', Format5, 12);
        enterData (Op_SLA, $0a00, 'SLA', Format5, 12);
        enterData (Op_SRC, $0b00, 'SRC', Format5, 12);
        enterData (Op_JMP, $1000, 'JMP', Format2, 8);
        enterData (Op_JLT, $1100, 'JLT', Format2, 8);
        enterData (Op_JLE, $1200, 'JLE', Format2, 8);
        enterData (Op_JEQ, $1300, 'JEQ', Format2, 8);
        enterData (Op_JHE, $1400, 'JHE', Format2, 8);
        enterData (Op_JGT, $1500, 'JGT', Format2, 8);
        enterData (Op_JNE, $1600, 'JNE', Format2, 8);
        enterData (Op_JNC, $1700, 'JNC', Format2, 8);
        enterData (Op_JOC, $1800, 'JOC', Format2, 8);
        enterData (Op_JNO, $1900, 'JNO', Format2, 8);
        enterData (Op_JL, $1a00, 'JL', Format2, 8);
        enterData (Op_JH, $1b00, 'JH', Format2, 8);
        enterData (Op_JOP, $1c00, 'JOP', Format2, 8);
        enterData (Op_SBO, $1d00, 'SBO', Format2_1, 12);
        enterData (Op_SBZ, $1e00, 'SBZ', Format2_1, 12);
        enterData (Op_TB, $1f00, 'TB', Format2_1, 12);
        enterData (Op_COC, $2000, 'COC', Format3, 14);
        enterData (Op_CZC, $2400, 'CZC', Format3, 14);
        enterData (Op_XOR, $2800, 'XOR', Format3, 14);
        enterData (Op_XOP, $2c00, 'XOP', Format9, 36);
        enterData (Op_LDCR, $3000, 'LDCR', Format4, 20);
        enterData (Op_STCR, $3400, 'STCR', Format4, 42);
        enterData (Op_MPY, $3800, 'MPY', Format9, 52);
        enterData (Op_DIV, $3c00, 'DIV', Format9, 108);
        enterData (Op_SZC, $4000, 'SZC', Format1, 14);
        enterData (Op_SZCB, $5000, 'SZCB', Format1, 14);
        enterData (Op_S, $6000, 'S', Format1, 14);
        enterData (Op_SB, $7000, 'SB', Format1, 14);
        enterData (Op_C, $8000, 'C', Format1, 14);
        enterData (Op_CB, $9000, 'CB', Format1, 14);
        enterData (Op_A, $a000, 'A', Format1, 14);
        enterData (Op_AB, $b000, 'AB', Format1, 14);
        enterData (Op_MOV, $c000, 'MOV', Format1, 14);
        enterData (Op_MOVB, $d000, 'MOVB', Format1, 14);
        enterData (Op_SOC, $e000, 'SOC', Format1, 14);
        enterData (Op_SOCB, $f000, 'SOCB', Format1, 14);
        
        for instr := 0 to MaxInstruction do
            prepareInstruction (instr, decodedInstruction [instr])
    end;

begin
    createDecoderData
end.
