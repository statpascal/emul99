unit tms9900;

interface

procedure setCpuFrequency (freq: uint32);
function getCycles: int64;

procedure runCpu;
procedure stopCpu;


implementation

uses memory, tms9901, decoder, types, xophandler, tools, timer;

const 
    Status_LGT = $8000;
    Status_AGT = $4000;
    Status_EQ  = $2000;
    Status_C   = $1000;
    Status_OV  = $0800;
    Status_OP  = $0400;
    Status_X   = $0200;

var
    cpu: TTMS9900;
    cpuStopped: boolean;
    cycles: int64;
    cpuFreq: uint32;
    statusMask: array [TOpcode] of uint16;		(* Status bits affected by instruction *)
    
procedure initOpcodeStatus;
    type
        TOpcodeSet = set of TOpcode;
    const 
        Entries = 6;
        opcodeStatus: array [1..Entries] of record opcodes: TOpcodeSet; status: uint16 end = (
            (opcodes: [Op_A, Op_AI, Op_DEC, Op_DECT, Op_INC, Op_INCT, Op_NEG, Op_S, Op_SLA];
             status:  Status_LGT + Status_AGT + Status_EQ + Status_C + Status_OV),
            (opcodes: [Op_AB, Op_SB];
             status:  Status_LGT + Status_AGT + Status_EQ + Status_C + Status_OV + Status_OP),
            (opcodes: [Op_ANDI, Op_C, Op_CI, Op_INV, Op_LI, Op_MOV, Op_ORI, Op_SOC, Op_SZC, Op_XOR, Op_STCR];
             status:  Status_LGT + Status_AGT + Status_EQ),
            (opcodes: [Op_CB, Op_MOVB, Op_SOCB, Op_SZCB];
             status:  Status_LGT + Status_AGT + Status_EQ + Status_OP),
            (opcodes: [Op_LDCR, Op_SRA, Op_SRC, Op_SRL];
             status:  Status_LGT + Status_AGT + Status_EQ + Status_C),
            (opcodes: [Op_COC, Op_CZC, Op_TB];
             status:  Status_EQ));
    var
        i: 1..Entries;
        j: TOpcode;
    begin
        fillChar (statusMask, sizeof (statusMask), 0);
        for i := 1 to Entries do
            with opcodeStatus [i] do
                for j := Op_LI to Op_SOCB do
                    if j in opcodes then
                        statusMask [j] := status;
	statusMask [Op_ABS] := Status_LGT + Status_AGT + Status_EQ + Status_OV;
	statusMask [Op_DIV] := Status_OV
    end;
        
procedure updateStatusBits (mask, val: uint16);
    begin
	cpu.st := (cpu.st and not mask) or (val and mask)
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
	readRegister := readMemory (uint16 (cpu.wp + 2 * reg))
    end;

procedure writeRegister (reg: uint8; val: uint16);
    begin
	writeMemory (uint16 (cpu.wp + 2 * reg), val)
    end;

function readInstruction: uint16;
    begin
    	readInstruction := readMemory (cpu.pc);
    	cpu.pc := uint16 (cpu.pc + 2)
    end;

function getGeneralAddress (T: uint8; reg: uint8; var addr: uint16; byteOp: boolean): uint16;
    var
	tmp: uint16;
    begin
	case T of
	    0:
		getGeneralAddress := uint16 (cpu.wp + 2 * reg);
	    1:
		getGeneralAddress := readRegister (reg);
	    2:
	        begin
	            addr := readInstruction;	(* fill in address for disassembler *)
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
	writeMemory (newWP + 26, cpu.wp);
	writeMemory (newWP + 28, cpu.pc);
	writeMemory (newWP + 30, cpu.st);
	cpu.wp := newWP;
	cpu.pc := newPC and $fffe
    end;

procedure executeInstruction (instr: uint16); forward;

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
	if (instruction.opcode = Op_MOVB) or (instruction.opcode = Op_SOCB) or (instruction.opcode = Op_SZCB) then
 	    status := getByteStatus (result8)
	else if (instruction.opcode = Op_MOV) or (instruction.opcode = Op_SOC) or (instruction.opcode = Op_SZC) then
  	    status := getWordStatus (result);
	if (instruction.opcode <> Op_C) and (instruction.opcode <> Op_CB) then
	    begin
  	        if instruction.B then
	            setHighLow (result, not odd (dstaddr), result8);
  	        writeMemory (dstaddr, result);
	    end;
	updateStatusBits (statusMask [instruction.opcode], status)
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
        with JumpCondition [instruction.opcode], cpu do
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
	        cpu.st := (cpu.st and not Status_EQ) or (Status_EQ * readCru (addr))
	end
    end;

procedure executeFormat3 (var instruction: TInstruction);
    var
	srcval, dstval, result, status: uint16;
    begin
	srcval := readMemory (getSourceAddress (instruction));
	dstval := readRegister (instruction.D);
	case instruction.opcode of
	    Op_XOR:
	        begin
		    result := srcval xor dstval;
		    writeRegister(instruction.D, result);
		    status := getWordStatus (result)
		end;
	    Op_COC:
	        status := Status_EQ * ord (srcval and dstval = srcval);
	    Op_CZC:
	        status := Status_EQ * ord (srcval and dstval = 0)
	end;
	updateStatusBits (statusMask [instruction.opcode], status)
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
  	    updateStatusBits (statusMask [instruction.opcode] or Status_OP, getByteStatus (bits))
	else
	    updateStatusBits (statusMask [instruction.opcode], getWordStatus (bits))
    end;

procedure executeFormat5 (var instruction: TInstruction);
    var 
	count: uint8;
	val: uint16;
	overflow, carry: boolean;
    begin
	count := instruction.count;
	if count = 0 then
	    begin
	    	inc (cycles, 8);
 	        count := readRegister (0) and $000f;
		if count = 0 then
		    count := 16
	    end;
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
	updateStatusBits (statusMask [instruction.opcode], getWordStatus (val) and (Status_LGT or Status_AGT or Status_EQ) 
	    or Status_OV * ord (overflow) or Status_C * ord (carry))
    end;

procedure executeFormat6 (var instruction: TInstruction);
    const
	writeResultOpcodes: set of TOpcode = [Op_CLR, Op_DEC, Op_DECT, Op_INC, Op_INCT, Op_INV, Op_NEG, Op_SETO, Op_SWPB];
    var
	srcaddr, srcval, result, status: uint16;
    begin
	srcaddr := getSourceAddress (instruction);
	(* TODO: B, BL do not need val - really read? *)
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
                cpu.pc := srcaddr and $fffe;
            Op_BL:
                begin
                    writeRegister (11, cpu.pc);
                    cpu.pc := srcaddr and $fffe
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
                executeInstruction (srcval)
        end;
	if instruction.opcode in writeResultOpcodes then
	    writeMemory (srcaddr, result);
	if (instruction.opcode = Op_INV) or (instruction.opcode = Op_NEG) then
	    status := getWordStatus (result);
	updateStatusBits (statusMask [instruction.opcode], status)
    end;

procedure executeFormat7 (var instruction: TInstruction);
    begin
        with cpu do 
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
        instruction.imm := readInstruction;
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
        if (instruction.opcode <> Op_CI) and (instruction.opcode <> Op_AI) then
            status := getWordStatus (result);
	updateStatusBits (statusMask [instruction.opcode], status)
    end;

procedure executeFormat8_1 (var instruction: TInstruction);
    begin
        instruction.imm := readInstruction;
        case instruction.opcode of
	    Op_LIMI:
	        cpu.st := cpu.st and $fff0 or instruction.imm and $000f;
	    Op_LWPI:
	        cpu.wp := instruction.imm
        end
    end;

procedure executeFormat8_2 (var instruction: TInstruction);
    begin
        case instruction.opcode of
            Op_STST:
	        writeRegister (instruction.w, cpu.st);
   	    Op_STWP:
	        writeRegister (instruction.w, cpu.wp)
        end
    end;

procedure executeFormat9 (var instruction: TInstruction);	
    var
	srcaddr, srcval, oldWP: uint16;
        product, dividend: uint32;
    begin
	srcaddr := getSourceAddress (instruction);
	(* Simulator hook for XOP 0 *)
	if (instruction.opcode = Op_XOP) and (instruction.D = 0) then
   	    handleXop (srcaddr, cpu)
	else
	    begin	
		srcval := readMemory (srcaddr);
		with cpu do 
		    case instruction.opcode of
			Op_XOP:
			    begin
				oldWP := wp;
				wp := readMemory ($0040 + 2 * instruction.D);
				writeRegister (11, srcaddr);
				writeRegister (13, oldWP);
				writeRegister (14, pc);
				writeRegister (15, st);
				pc := readMemory ($0042 + 2 * instruction.D) and $fffe;
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

procedure executeInstruction (instr: uint16);
    type
        TExecuteProc = procedure (var instruction: TInstruction);
    const
	dispatch: array [TInstructionFormat] of TExecuteProc = (
	    executeFormat1, executeFormat2, executeFormat2_1, executeFormat3, executeFormat4, executeFormat5, executeFormat6, executeFormat7, executeFormat8, executeFormat8_1, executeFormat8_2, executeFormat9);
    var
	instruction: TInstruction;
	prevPC: uint16;
	prevCycles: int64;
    begin
        prevPC := uint16 (cpu.pc - 2);
        prevCycles := cycles;
        
        decodeInstruction (instr, instruction);
	dispatch [instruction.instructionFormat] (instruction);
	inc (cycles, instruction.cycles + getWaitStates);

//        writeln (cycles - prevCycles:3, '  ', disassembleInstruction (instruction, prevPC))
    end;	

procedure handleInterrupt (level: uint8);
    begin
	performContextSwitch (readMemory (4 * level), readMemory (4 * level + 2));
	inc (cycles, 22);
	if cpu.st and $000f > 0 then
	    dec (cpu.st)
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
        cpu.st := 0;
    	performContextSwitch (readMemory (0), readMemory (2));
    	
    	time := getCurrentTime;
	while not cpuStopped do 
            begin
  	        executeInstruction (readInstruction);
		sleepUntil (time + cycles * cycleTime);
  	        handleTimer (cycles);
		if (cpu.st and $000f >= 1) and tms9901IsInterrupt then 
  	            handleInterrupt (1)
	    end
    end;

procedure stopCpu;
    begin
	cpuStopped := true;
    end;

begin
    initOpcodeStatus
end.
