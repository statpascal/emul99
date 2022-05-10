unit tms9900;

interface

procedure setCpuFrequency (freq: uint32);
function getCycles: int64;

procedure runCpu;
procedure stopCpu;


implementation

uses memory, tms9901, types, xophandler, tools, timer;

const 
    Status_LGT = $8000;
    Status_AGT = $4000;
    Status_EQ  = $2000;
    Status_C   = $1000;
    Status_OV  = $0800;
    Status_OP  = $0400;
    Status_X   = $0200;
    Status_None = 0;
    
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
	instr, source, dest, imm, statusBits: uint16
    end;
    
var
    pc, wp, st: uint16;
    cpuStopped: boolean;
    cycles: int64;
    cpuFreq: uint32;
    instructionString: array [TOpcode] of string;
    decodedInstruction: array [uint16] of TInstruction;

procedure prepareInstruction (instr: uint16; opcode: TOpcode; instructionFormat: TInstructionFormat; cycles: uint8; statusBits: uint16; var result: TInstruction);
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
	result.opcode := opcode;
	result.instructionFormat := instructionFormat;
	result.cycles := cycles;
	result.statusBits := statusBits;
	
	if instructionFormat in [Format1, Format2, Format3, Format4, Format6, Format9] then
	    decodeGeneralSource;
	case instructionFormat of
	    Format1:
                decodeGeneralDestination;
            Format2, Format2_1:
		result.disp := instr and $ff;
	    Format3, Format9:
                result.D := (instr and $03C0) shr 6;
            Format4:
                result.count := (instr and $03C0) shr 6;
            Format5:
                result.count := (instr and $00F0) shr 4
        end;
        if instructionFormat in [Format5, Format8, Format8_2] then
            result.W := instr and $0f;
        
        if result.opcode in [Op_STCR, Op_LDCR] then
            begin
                if result.opcode = Op_STCR then
                    inc (result.cycles, 16 * ord ((result.count >= 9) or (result.count = 0)) + 2 * ord (result.count and 7 = 0))
                else
                    inc (result.cycles, 2 * result.count or 32 * ord (result.count = 0));
                result.statusBits := statusBits or Status_OP * ord (result.count in [1..8])
            end 
        else if (result.opcode in [Op_SLA, Op_SRA, Op_SRC, Op_SRL]) and (result.count = 0) then
            inc (result.cycles, 8)
    end;
    
function disassembleInstruction (var instruction: TInstruction; addr: uint16): string;
    var
        codestr, textstr: string;

    function reg (r: uint8): string;
        begin
            reg := 'R' + decimalStr (r)
        end;
        
    function hex (w: uint16): string;
        var
            s: string;
        begin
            s := hexstr (w);
            codestr := codestr + ' ' + s;
            hex := '>' + s
        end;
        
    function makeLength (s: string; n: uint8): string;
        begin
            while length (s) < n do
                s := s + ' ';
            makeLength := s
        end;
        
    function genAddr (tx, x: uint8; addr: uint16): string;
        begin
            case tx of
                0:
                    genAddr := reg (x);
                1:
                    genAddr := '*' + reg (x);
                2:
                    if x <> 0 then
                        genAddr := '@' + hex (addr) + '(' + reg (x) + ')'
                    else
                        genAddr := '@' + hex (addr);
                3:
                    genAddr := '*' + reg (x) + '+'
            end
        end;
        
    begin
        codestr := hexstr (addr) + '  ' + hexstr (instruction.instr);
        textstr := makeLength (instructionString [instruction.opcode], 5);
        if instruction.instructionFormat in [Format1, Format3, Format4, Format6, Format9] then
            textstr := textstr + genAddr (instruction.Ts, instruction.S, instruction.source)
        else if instruction.instructionFormat in [Format5, Format8, Format8_2] then
            textstr := textstr + reg (instruction.W);
        case instruction.instructionFormat of
            Format1:
                textstr := textstr + ',' + genAddr (instruction.Td, instruction.D, instruction.dest);
            Format2:
                textstr := textstr + '>' + hexstr (addr + 2 + 2 * int8 (instruction.disp));
            Format3, Format9:
                textstr := textstr + ',' + reg (instruction.D);
            Format4, Format5:
                textstr := textstr + ',' + decimalstr (instruction.count);
            Format8:
                textstr := textstr + ',' + hex (instruction.imm);
            Format8_1:
                textstr := textstr + hex (instruction.imm);
            Format2_1:
                textstr := textstr + decimalstr (instruction.disp)
        end;
        disassembleInstruction := makeLength (codestr, 22) + textstr
    end;        

procedure enterData (opcode: TOpcode; base: uint16; instString: string; instructionFormat: TInstructionFormat; cycles: uint8; statusBits: uint16);
    const
        opcodeBits: array [TInstructionFormat] of uint8 = (4, 8, 8, 6, 6, 8, 10, 16, 12, 12, 12, 6);
    var
        i: uint16;
    begin
        instructionString [opcode] := instString;
        for i := 0 to pred (1 shl (16 - opcodeBits [instructionFormat])) do
            prepareInstruction (base + i, opcode, instructionFormat, cycles, statusBits, decodedInstruction [base + i])
    end;

procedure updateStatusBits (var instruction: TInstruction; val: uint16);
    begin
	st := (st and not instruction.statusBits) or (val and instruction.statusBits)
    end;

function getWordStatus (w: uint16): uint16;
    begin
        case w of
	    $0000:
	        getWordStatus := Status_EQ or Status_C;
   	    $0001..$7fff:
	        getWordStatus := Status_AGT or Status_LGT;
	    $8000:
	        getWordStatus := Status_LGT or Status_OV;
	    $8001..$ffff:
	        getWordStatus := Status_LGT
        end
    end;
    
function getByteStatus (b: uint8): uint16;
    begin
	getByteStatus := getWordStatus (b shl 8) or Status_OP * ord (oddParity (b))
    end;
    
function compare (u1, u2: uint16; s1, s2: int16): uint16;
    begin
        compare := Status_EQ * ord (u1 = u2) or Status_LGT * ord (u1 > u2) or Status_AGT * ord (s1 > s2)
    end;

function compare16 (a, b: uint16): uint16;
    begin
        compare16 := compare (a, b, int16 (a), int16 (b))
    end;

function compare8 (a, b: uint8): uint16;
    begin
        compare8 := compare (a, b, int8 (a), int8 (b)) or Status_OP * ord (oddParity (a))
    end;
    
function addStatus (a, b, res, signMask: uint16; isSub: boolean): uint16;
    begin
        addStatus := Status_C * ord ((res < b) or (isSub and (a = 0))) or Status_OV * ord ((res xor a) and (res xor b) and signMask <> 0);
    end;

procedure add16 (var status: uint16; a, b: uint16; var result: uint16; isSub: boolean);
    begin
        result := uint16 (a + b);
        status := getWordStatus (result) and (Status_LGT or Status_AGT or Status_EQ) or addStatus (a, b, result, $8000, isSub)
    end;
    
procedure add8 (var status: uint16; a, b: uint8; var result: uint8; isSub: boolean);
    begin
        result := uint8 (a + b);
        status := getByteStatus (result) and (Status_LGT or Status_AGT or Status_EQ or Status_OP) or addStatus (a, b, result, $80, isSub)
    end;
    
function readRegister (reg: uint8): uint16;
    begin
	readRegister := readMemory (uint16 (wp + 2 * reg))
    end;

procedure writeRegister (reg: uint8; val: uint16);
    begin
	writeMemory (uint16 (wp + 2 * reg), val)
    end;

function fetchInstruction: uint16;
    begin
    	fetchInstruction := readMemory (pc);
    	pc := uint16 (pc + 2)
    end;

function getGeneralAddress (T: uint8; reg: uint8; var addr: uint16; byteOp: boolean): uint16;
    var
	tmp: uint16;
    begin
	case T of
	    0:
		getGeneralAddress := uint16 (wp + 2 * reg);
	    1:
		getGeneralAddress := readRegister (reg);
	    2:
	        begin
	            addr := fetchInstruction;	// fill in address for tracing
 		    if reg = 0 then
	 	        getGeneralAddress := addr
		    else
		        getGeneralAddress := uint16 (addr + readRegister (reg))
		end;
	    3:  
		begin
		    tmp := readRegister (reg);
		    writeRegister (reg, uint16 (tmp + 2 - ord (byteOp)));
		    getGeneralAddress := tmp
		end
	end
    end;

function getSourceAddress (var instruction: TInstruction): uint16;
    begin
	getSourceAddress := getGeneralAddress (instruction.Ts, instruction.S, instruction.source, instruction.B)
    end;

function getDestAddress (var instruction: TInstruction): uint16;
    begin
	getDestAddress := getGeneralAddress (instruction.Td, instruction.D, instruction.dest, instruction.B)
    end;

procedure performContextSwitch (newWP, newPC: uint16);
    begin
	writeMemory (uint16 (newWP + 26), wp);
	writeMemory (uint16 (newWP + 28), pc);
	writeMemory (uint16 (newWP + 30), st);
	wp := newWP;
	pc := newPC and $fffe
    end;

procedure executeInstruction (var instruction: TInstruction); forward;

procedure executeFormat1 (var instruction: TInstruction);
    var
	srcaddr, dstaddr, srcval, dstval, result, status: uint16;
	srcval8, dstval8, result8: uint8;
    begin
	srcaddr := getSourceAddress (instruction);
	srcval := readMemory (srcaddr);
	dstaddr := getDestAddress (instruction);
	dstval := readMemory (dstaddr);
	if instruction.B then
	    begin
  	        srcval8 := getHighLow (srcval, not odd (srcaddr));
  	        dstval8 := getHighLow (dstval, not odd (dstaddr));
  	        result := dstval;
	    end;
        case instruction.opcode of
	    Op_A:
	        add16 (status, srcval, dstval, result, false);
	    Op_S:
	        add16 (status, uint16 (-srcval), dstval, result, true);
	    Op_AB:
	    	add8 (status, srcval8, dstval8, result8, false);
	    Op_SB:
	    	add8 (status, uint8 (-srcval8), dstval8, result8, true);
	    Op_C:
	        status := compare16 (srcval, dstval);
	    Op_CB:
	        status := compare8 (srcval8, dstval8);
	    Op_MOV:
   	        result := srcval;
	    Op_MOVB:
	        result8 := srcval8;
	    Op_SOC:
	        result := srcval or dstval;
	    Op_SOCB:
	        result8 := srcval8 or dstval8;
	    Op_SZC:
 	        result := dstval and not srcval;
	    Op_SZCB:
 	        result8 := dstval8 and not srcval8
	end;
	if instruction.opcode in [Op_MOVB, Op_SOCB, Op_SZCB] then
 	    status := getByteStatus (result8)
	else if instruction.opcode in [Op_MOV, Op_SOC, Op_SZC] then
  	    status := getWordStatus (result);
	if not (instruction.opcode in [Op_C, Op_CB]) then
	    begin
  	        if instruction.B then
	            setHighLow (result, not odd (dstaddr), result8);
  	        writeMemory (dstaddr, result);
	    end;
	updateStatusBits (instruction, status)
    end;

procedure executeFormat2 (var instruction: TInstruction);
    const
        JumpCondition: array [Op_JMP..Op_JOP] of record flags: uint16; val: boolean end = (
            (flags: 0;                      val: false),	(* JMP *)
            (flags: Status_AGT + Status_EQ; val: false),	(* JLT *)
            (flags: Status_LGT;             val: false),	(* JLE *)
            (flags: Status_EQ;              val: true),		(* JEQ *)
            (flags: Status_LGT + Status_EQ; val: true),		(* JHE *)
            (flags: Status_AGT;             val: true),		(* JGT *)
            (flags: Status_EQ;              val: false),	(* JNE *)
            (flags: Status_C;               val: false),	(* JNC *)
            (flags: Status_C;               val: true),		(* JOC *)
            (flags: Status_OV;              val: false),	(* JNO *)
            (flags: Status_LGT + Status_EQ; val: false),	(* JL  *)
            (flags: Status_LGT;             val: true),		(* JH  *)
            (flags: Status_OP;              val: true)		(* JOP *)
        );
    begin
        with JumpCondition [instruction.opcode] do
	    if (st and flags <> 0) = val then
		begin
  		    inc (cycles, 2);
		    pc := uint16 (pc + 2 * int8 (instruction.disp))
 	        end
    end;

procedure executeFormat2_1 (var instruction: TInstruction);
    var 
	addr: uint16;
    begin
        addr := (readRegister (12) div 2 + int8 (instruction.disp)) and $0fff;
	case instruction.opcode of
	    Op_SBO:
	        writeCru (addr, 1);
	    Op_SBZ:
	        writeCru (addr, 0);
	    Op_TB:
	        updateStatusBits (instruction, Status_EQ * readCru (addr))
	end
    end;

procedure executeFormat3 (var instruction: TInstruction);
    var
	srcval, dstval, status: uint16;
    begin
	srcval := readMemory (getSourceAddress (instruction));
	dstval := readRegister (instruction.D);
	case instruction.opcode of
	    Op_XOR:
	        begin
		    writeRegister(instruction.D, srcval xor dstval);
		    status := getWordStatus (srcval xor dstval)
		end;
	    Op_COC:
	        status := Status_EQ * ord (srcval and dstval = srcval);
	    Op_CZC:
	        status := Status_EQ * ord (srcval and dstval = 0)
	end;
	updateStatusBits (instruction, status)
    end;

procedure executeFormat4 (var instruction: TInstruction);
    var
	srcaddr, srcval, bits: uint16;
        cruBase: TCRUAddress;
	i, count: 0..16;
    begin
	srcaddr := getSourceAddress (instruction);
	srcval := readMemory (srcaddr);
	cruBase := (readRegister (12) shr 1) and $0fff;
	count := instruction.count or 16 * ord (instruction.count = 0);

	if instruction.opcode = Op_LDCR then
	    begin
		if count <= 8 then
	            bits := getHighLow (srcval, not odd (srcaddr))
	        else
	            bits := srcval;
   	        for i := 0 to pred (count) do
		    writeCru (cruBase + i, ord (odd (bits shr i)))
	    end
	else (* STCR *)
	    begin
		bits := 0;
		for i := 0 to pred (count) do
 		    bits := bits or readCru (cruBase + i) shl i;
		if count <= 8 then
		    setHighLow (srcval, not odd (srcaddr), bits)
		else
		    srcval := bits;
		writeMemory (srcaddr, srcval)
	    end;
	    
	if count <= 8 then
  	    updateStatusBits (instruction, getByteStatus (bits))
	else
	    updateStatusBits (instruction, getWordStatus (bits))
    end;

procedure executeFormat5 (var instruction: TInstruction);
    var 
	count: uint8;
	val: uint16;
	overflow, carry: boolean;
    begin
	count := instruction.count;
	if count = 0 then
            count := readRegister (0) and $000f;
	if count = 0 then
	    count := 16;
        inc (cycles, 2 * count);
	
	val := readRegister (instruction.w);
	overflow := false;
	carry := odd (val shr (pred (count) + (17 - 2 * count) * ord (instruction.opcode = Op_SLA)));
	
	case instruction.opcode of
	    Op_SLA:
	        begin
    	            if count = 16 then
	                overflow := val <> 0
	            else
	                overflow := (val shr (15 - count) <> 0) and (succ (val shr (15 - count)) <> 1 shl succ (count));
		    val := uint16 (val shl count)
		end;
	    Op_SRA:
	        val := uint16 (int16 (val) shr count);
	    Op_SRC:
	        val := uint16 ((val shl 16 or val) shr count);
	    Op_SRL:
	        val := val shr count
	end;
	
	writeRegister (instruction.w, val);
	updateStatusBits (instruction, getWordStatus (val) and (Status_LGT or Status_AGT or Status_EQ) 
	    or Status_OV * ord (overflow) or Status_C * ord (carry))
    end;

procedure executeFormat6 (var instruction: TInstruction);
    var
	srcaddr, srcval, result, status: uint16;
    begin
	srcaddr := getSourceAddress (instruction);
	srcval := readMemory (srcaddr);
	status := 0;
        case instruction.opcode of
            Op_ABS:
                begin
                    status := getWordStatus (srcval);
                    if int16 (srcval) < 0 then
                        writeMemory (srcaddr, uint16 (-srcval))
		    else
                        dec (cycles, 2)
                end;
            Op_B:
                pc := srcaddr and $fffe;
            Op_BL:
                begin
                    writeRegister (11, pc);
                    pc := srcaddr and $fffe
                end;
            Op_BLWP:
                performContextSwitch (srcval, readMemory (srcaddr + 2));
            Op_CLR:
                result := 0;
            Op_DEC:
                add16 (status, uint16 (-1), srcval, result, true);
            Op_DECT:
                add16 (status, uint16 (-2), srcval, result, true);
            Op_INC:
                add16 (status, 1, srcval, result, false);
            Op_INCT:
                add16 (status, 2, srcval, result, false);
            Op_INV:
                result := uint16 (not srcval);
            Op_NEG:
                result := uint16 (-srcval);
            Op_SETO:
                result := $ffff;
            Op_SWPB:
                result := swap16 (srcval);
            Op_X:
                executeInstruction (decodedInstruction [srcval])
        end;
	if instruction.opcode in [Op_CLR, Op_DEC, Op_DECT, Op_INC, Op_INCT, Op_INV, Op_NEG, Op_SETO, Op_SWPB] then
	    writeMemory (srcaddr, result);
	if instruction.opcode in [Op_INV, Op_NEG] then
	    status := getWordStatus (result);
	updateStatusBits (instruction, status)
    end;

procedure executeFormat7 (var instruction: TInstruction);
    begin
        case instruction.opcode of
   	    Op_RTWP:
	        begin
		    st := readRegister (15);
		    pc := readRegister (14) and $fffe;
		    wp := readRegister (13) and $fffe;
   	        end;
 	    Op_RSET:
	        st := st and $ff0
	end
    end;

procedure executeFormat8 (var instruction: TInstruction);
    var
	result, status: uint16;
    begin
        instruction.imm := fetchInstruction;
        case instruction.opcode of
  	    Op_AI:
	        add16 (status, readRegister (instruction.w), instruction.imm, result, false);
	    Op_ANDI:
	        result := readRegister (instruction.w) and instruction.imm;
	    Op_CI:
	        status := compare16 (readRegister (instruction.w), instruction.imm);
	    Op_LI:
	        result := instruction.imm;
	    Op_ORI:
	        result := readRegister (instruction.w) or instruction.imm
	end;
        if instruction.opcode <> Op_CI then
            writeRegister (instruction.w, result);
        if instruction.opcode in [Op_ANDI, Op_LI, Op_ORI] then
            status := getWordStatus (result);
	updateStatusBits (instruction, status)
    end;

procedure executeFormat8_1 (var instruction: TInstruction);
    begin
        instruction.imm := fetchInstruction;
        case instruction.opcode of
	    Op_LIMI:
	        st := st and $fff0 or instruction.imm and $000f;
	    Op_LWPI:
	        wp := instruction.imm
        end
    end;

procedure executeFormat8_2 (var instruction: TInstruction);
    begin
        case instruction.opcode of
            Op_STST:
	        writeRegister (instruction.w, st);
   	    Op_STWP:
	        writeRegister (instruction.w, wp)
        end
    end;

procedure executeFormat9 (var instruction: TInstruction);	
    var
	srcaddr, srcval: uint16;
        product, dividend: uint32;
    begin
	srcaddr := getSourceAddress (instruction);
	(* Simulator hook for XOP 0 *)
	if (instruction.opcode = Op_XOP) and (instruction.D = 0) then
   	    handleXop (srcaddr)
	else
	    begin	
		srcval := readMemory (srcaddr);
		case instruction.opcode of
		    Op_XOP:
		        begin
		            performContextSwitch (readMemory ($0040 + 2 * instruction.D), readMemory ($0042 + 2 * instruction.D));
                            writeRegister (11, srcaddr);
                            st := st or Status_X
                        end;
                    Op_MPY:
                        begin
                            product := srcval * readRegister (instruction.D);
                            writeRegister (instruction.D, product shr 16);
                            writeRegister (instruction.D + 1, uint16 (product))
                        end;
                    Op_DIV:
                        begin
                            dividend := readRegister (instruction.D);
                            if srcval > dividend then 
                                begin
                                    dividend := dividend shl 16 + readRegister (instruction.D + 1);
                                    writeRegister (instruction.D, dividend div srcval);
                                    writeRegister (instruction.D + 1, dividend mod srcval);
                                    st := st and not Status_OV
                                end
                            else
                                begin
                                    st := st or Status_OV;
                                    dec (cycles, instruction.cycles - 16)
                                end
                        end
                end
	    end
    end;

procedure executeInstruction (var instruction: TInstruction);
    const
	dispatch: array [TInstructionFormat] of procedure (var instruction: TInstruction) = (
	    executeFormat1, executeFormat2, executeFormat2_1, executeFormat3, executeFormat4, executeFormat5, executeFormat6, executeFormat7, executeFormat8, executeFormat8_1, executeFormat8_2, executeFormat9);
    var
	prevPC: uint16;
	prevCycles: int64;
    begin
        prevPC := uint16 (pc - 2);
        prevCycles := cycles;
	dispatch [instruction.instructionFormat] (instruction);
	inc (cycles, instruction.cycles + getWaitStates);
//        writeln (cycles - prevCycles:3, '  ', disassembleInstruction (instruction, prevPC))
    end;	

procedure handleInterrupt (level: uint8);
    begin
	performContextSwitch (readMemory (4 * level), readMemory (4 * level + 2));
	inc (cycles, 22);
	if st and $000f > 0 then
	    dec (st)
    end;

procedure setCpuFrequency (freq: uint32);
    begin
        cpuFreq := freq
    end;
    
function getCycles: int64;
    begin
        getCycles := cycles
    end;
    
procedure runCpu;
    var
	time: TNanoTimestamp;
	cycleTime: int64;
    begin
        cpuStopped := false;
    	cycles := 0;
    	cycleTime := (1000 * 1000 * 1000) div cpuFreq;
        st := 0;
    	performContextSwitch (readMemory (0), readMemory (2));
    	
    	time := getCurrentTime;
    	repeat
            executeInstruction (decodedInstruction [fetchInstruction]);
	    sleepUntil (time + cycles * cycleTime);
  	    handleTimer (cycles);
	    if (st and $000f >= 1) and tms9901IsInterrupt then 
  	        handleInterrupt (1)
        until cpuStopped
    end;

procedure stopCpu;
    begin
	cpuStopped := true
    end;

begin
    fillChar (decodedInstruction, sizeof (decodedInstruction), 0);
    enterData (Op_IVLD, $0000, 'IVLD', Format7,    6, Status_None);
    enterData (Op_LI,   $0200, 'LI',   Format8,   12, Status_LGT + Status_AGT + Status_EQ);
    enterData (Op_AI,   $0220, 'AI',   Format8,   14, Status_LGT + Status_AGT + Status_EQ + Status_C + Status_OV);
    enterData (Op_ANDI, $0240, 'ANDI', Format8,   14, Status_LGT + Status_AGT + Status_EQ);
    enterData (Op_ORI,  $0260, 'ORI',  Format8,   14, Status_LGT + Status_AGT + Status_EQ);
    enterData (Op_CI,   $0280, 'CI',   Format8,   14, Status_LGT + Status_AGT + Status_EQ);
    enterData (Op_STWP, $02a0, 'STWP', Format8_2,  8, Status_None);
    enterData (Op_STST, $02c0, 'STST', Format8_2,  8, Status_None);
    enterData (Op_LWPI, $02e0, 'LWPI', Format8_1, 10, Status_None);
    enterData (Op_LIMI, $0300, 'LIMI', Format8_1, 16, Status_None);
    enterData (Op_IDLE, $0340, 'IDLE', Format7,   12, Status_None);
    enterData (Op_RSET, $0360, 'RSET', Format7,   12, Status_None);
    enterData (Op_RTWP, $0380, 'RTWP', Format7,   14, Status_None);
    enterData (Op_CKON, $03a0, 'CKON', Format7,   12, Status_None);
    enterData (Op_CKOF, $03c0, 'CKOF', Format7,   12, Status_None);
    enterData (Op_LREX, $03e0, 'LREX', Format7,   12, Status_None);
    enterData (Op_BLWP, $0400, 'BLWP', Format6,   26, Status_None);
    enterData (Op_B,    $0440, 'B',    Format6,    8, Status_None);
    enterData (Op_X,    $0480, 'X',    Format6,    8, Status_None);
    enterData (Op_CLR,  $04c0, 'CLR',  Format6,   10, Status_None);
    enterData (Op_NEG,  $0500, 'NEG',  Format6,   12, Status_LGT + Status_AGT + Status_EQ + Status_C + Status_OV);
    enterData (Op_INV,  $0540, 'INV',  Format6,   10, Status_LGT + Status_AGT + Status_EQ);
    enterData (Op_INC,  $0580, 'INC',  Format6,   10, Status_LGT + Status_AGT + Status_EQ + Status_C + Status_OV);
    enterData (Op_INCT, $05c0, 'INCT', Format6,   10, Status_LGT + Status_AGT + Status_EQ + Status_C + Status_OV);
    enterData (Op_DEC,  $0600, 'DEC',  Format6,   10, Status_LGT + Status_AGT + Status_EQ + Status_C + Status_OV);
    enterData (Op_DECT, $0640, 'DECT', Format6,   10, Status_LGT + Status_AGT + Status_EQ + Status_C + Status_OV);
    enterData (Op_BL,   $0680, 'BL',   Format6,   12, Status_None);
    enterData (Op_SWPB, $06c0, 'SWPB', Format6,   10, Status_None);
    enterData (Op_SETO, $0700, 'SETO', Format6,   10, Status_None);
    enterData (Op_ABS,  $0740, 'ABS',  Format6,   14, Status_LGT + Status_AGT + Status_EQ + Status_OV);
    enterData (Op_SRA,  $0800, 'SRA',  Format5,   12, Status_LGT + Status_AGT + Status_EQ + Status_C);
    enterData (Op_SRL,  $0900, 'SRL',  Format5,   12, Status_LGT + Status_AGT + Status_EQ + Status_C);
    enterData (Op_SLA,  $0a00, 'SLA',  Format5,   12, Status_LGT + Status_AGT + Status_EQ + Status_C + Status_OV);
    enterData (Op_SRC,  $0b00, 'SRC',  Format5,   12, Status_LGT + Status_AGT + Status_EQ + Status_C);
    enterData (Op_JMP,  $1000, 'JMP',  Format2,    8, Status_None);
    enterData (Op_JLT,  $1100, 'JLT',  Format2,    8, Status_None);
    enterData (Op_JLE,  $1200, 'JLE',  Format2,    8, Status_None);
    enterData (Op_JEQ,  $1300, 'JEQ',  Format2,    8, Status_None);
    enterData (Op_JHE,  $1400, 'JHE',  Format2,    8, Status_None);
    enterData (Op_JGT,  $1500, 'JGT',  Format2,    8, Status_None);
    enterData (Op_JNE,  $1600, 'JNE',  Format2,    8, Status_None);
    enterData (Op_JNC,  $1700, 'JNC',  Format2,    8, Status_None);
    enterData (Op_JOC,  $1800, 'JOC',  Format2,    8, Status_None);
    enterData (Op_JNO,  $1900, 'JNO',  Format2,    8, Status_None);
    enterData (Op_JL,   $1a00, 'JL',   Format2,    8, Status_None);
    enterData (Op_JH,   $1b00, 'JH',   Format2,    8, Status_None);
    enterData (Op_JOP,  $1c00, 'JOP',  Format2,    8, Status_None);
    enterData (Op_SBO,  $1d00, 'SBO',  Format2_1, 12, Status_None);
    enterData (Op_SBZ,  $1e00, 'SBZ',  Format2_1, 12, Status_None);
    enterData (Op_TB,   $1f00, 'TB',   Format2_1, 12, Status_EQ);
    enterData (Op_COC,  $2000, 'COC',  Format3,   14, Status_EQ);
    enterData (Op_CZC,  $2400, 'CZC',  Format3,   14, Status_EQ);
    enterData (Op_XOR,  $2800, 'XOR',  Format3,   14, Status_LGT + Status_AGT + Status_EQ);
    enterData (Op_XOP,  $2c00, 'XOP',  Format9,   36, Status_X);
    enterData (Op_LDCR, $3000, 'LDCR', Format4,   20, Status_LGT + Status_AGT + Status_EQ + Status_C);
    enterData (Op_STCR, $3400, 'STCR', Format4,   42, Status_LGT + Status_AGT + Status_EQ);
    enterData (Op_MPY,  $3800, 'MPY',  Format9,   52, Status_None);
    enterData (Op_DIV,  $3c00, 'DIV',  Format9,  108, Status_OV);
    enterData (Op_SZC,  $4000, 'SZC',  Format1,   14, Status_LGT + Status_AGT + Status_EQ);
    enterData (Op_SZCB, $5000, 'SZCB', Format1,   14, Status_LGT + Status_AGT + Status_EQ + Status_OP);
    enterData (Op_S,    $6000, 'S',    Format1,   14, Status_LGT + Status_AGT + Status_EQ + Status_C + Status_OV);
    enterData (Op_SB,   $7000, 'SB',   Format1,   14, Status_LGT + Status_AGT + Status_EQ + Status_C + Status_OV + Status_OP);
    enterData (Op_C,    $8000, 'C',    Format1,   14, Status_LGT + Status_AGT + Status_EQ);
    enterData (Op_CB,   $9000, 'CB',   Format1,   14, Status_LGT + Status_AGT + Status_EQ + Status_OP);
    enterData (Op_A,    $a000, 'A',    Format1,   14, Status_LGT + Status_AGT + Status_EQ + Status_C + Status_OV);
    enterData (Op_AB,   $b000, 'AB',   Format1,   14, Status_LGT + Status_AGT + Status_EQ + Status_C + Status_OV + Status_OP);
    enterData (Op_MOV,  $c000, 'MOV',  Format1,   14, Status_LGT + Status_AGT + Status_EQ);
    enterData (Op_MOVB, $d000, 'MOVB', Format1,   14, Status_LGT + Status_AGT + Status_EQ + Status_OP);
    enterData (Op_SOC,  $e000, 'SOC',  Format1,   14, Status_LGT + Status_AGT + Status_EQ);
    enterData (Op_SOCB, $f000, 'SOCB', Format1,   14, Status_LGT + Status_AGT + Status_EQ + Status_OP)
end.