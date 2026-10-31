; ============================================================
; INK Programming Language — Code Generator
; File: codegen/codegen.asm
; Architecture: x86-64 Assembly (NASM)
;
; Phase 3 — Code Generator
;
; Takes the AST built by the Parser and converts it
; to LLVM IR (Intermediate Representation).
;
; LLVM IR looks like this:
;
;   define i64 @main() {
;   entry:
;     %result = add i64 5, 3
;     ret i64 0
;   }
;
; LLVM then takes this IR and compiles it to real
; machine code for ARM64 (phones) or x86-64 (desktops).
;
; Pipeline:
;   INK source (.in)
;       → Lexer  → Tokens
;       → Parser → AST
;       → Codegen → LLVM IR (.ll file)
;       → llc    → Object file (.o)
;       → clang  → Executable binary
;
; INK — Write the Future
; IndianBrand Technology, Hyderabad, India
; Jai Hind! 🇮🇳
; ============================================================

; ── SYSTEM CALLS ─────────────────────────────────────────────
SYS_WRITE   equ 1
SYS_OPEN    equ 2
SYS_CLOSE   equ 3
SYS_EXIT    equ 60
O_WRONLY    equ 1
O_CREAT     equ 64
O_TRUNC     equ 512
STDOUT      equ 1
STDERR      equ 2

; ── AST NODE TYPES (same as parser) ──────────────────────────
NODE_PROGRAM        equ 1
NODE_LET            equ 2
NODE_CONST          equ 3
NODE_ASSIGN         equ 4
NODE_FN_DEF         equ 5
NODE_FN_CALL        equ 6
NODE_RETURN         equ 7
NODE_IF             equ 8
NODE_WHILE          equ 9
NODE_FOR            equ 10
NODE_LOOP           equ 11
NODE_BREAK          equ 12
NODE_CONTINUE       equ 13
NODE_MATCH          equ 14
NODE_BLOCK          equ 15
NODE_SHOW           equ 16
NODE_USE            equ 17
NODE_TYPE_DEF       equ 18
NODE_BINARY         equ 19
NODE_UNARY          equ 20
NODE_INT_LIT        equ 21
NODE_FLOAT_LIT      equ 22
NODE_STRING_LIT     equ 23
NODE_CHAR_LIT       equ 24
NODE_BOOL_LIT       equ 25
NODE_NONE_LIT       equ 26
NODE_IDENT          equ 27
NODE_FIELD_ACCESS   equ 28
NODE_INDEX          equ 29
NODE_ARRAY_LIT      equ 30
NODE_MAP_LIT        equ 31
NODE_OPTIONAL_CHECK equ 32
NODE_ERROR_HANDLE   equ 33
NODE_TYPE_ANNOT     equ 34
NODE_PARAM          equ 35
NODE_MATCH_ARM      equ 36

; ── BINARY OPERATORS ─────────────────────────────────────────
BINOP_ADD   equ 1
BINOP_SUB   equ 2
BINOP_MUL   equ 3
BINOP_DIV   equ 4
BINOP_MOD   equ 5
BINOP_EQ    equ 6
BINOP_NEQ   equ 7
BINOP_LT    equ 8
BINOP_GT    equ 9
BINOP_LTE   equ 10
BINOP_GTE   equ 11
BINOP_AND   equ 12
BINOP_OR    equ 13
BINOP_RANGE equ 14

; ── NODE STRUCTURE OFFSETS ───────────────────────────────────
NODE_SIZE   equ 64
NODE_TYPE   equ 0
NODE_LEFT   equ 8
NODE_RIGHT  equ 16
NODE_EXTRA  equ 24
NODE_TSTART equ 32
NODE_TLEN   equ 40
NODE_TLINE  equ 48
NODE_NEXT   equ 56

; ── OUTPUT BUFFER ────────────────────────────────────────────
; We write LLVM IR into a memory buffer first
; then write to the .ll output file
MAX_IR      equ 4194304     ; 4MB output buffer

; ── REGISTER COUNTER ─────────────────────────────────────────
; LLVM IR uses SSA form — every value has a unique register
; We count up: %0, %1, %2, %3...
MAX_VARS    equ 10000       ; max variables/registers

; ── VARIABLE TABLE ───────────────────────────────────────────
; Maps variable names to their LLVM register numbers
; Each entry: name_start(8) + name_len(8) + reg_num(8) = 24 bytes
VAR_ENTRY_SIZE  equ 32   ; name_start, name_len, reg, type
MAX_VAR_TABLE   equ 1000    ; max variables in scope

; ── LABEL COUNTER ────────────────────────────────────────────
; For generating unique labels: if.then.0, if.else.0, loop.0 etc

; ── DATA SECTION ─────────────────────────────────────────────
section .data

    ; Status messages
    msg_codegen     db  "[INK] Generating LLVM IR...", 10, 0
    msg_codegen_ok  db  "[INK] LLVM IR generated successfully!", 10, 0
    msg_codegen_err db  "[INK ERROR] Code generation failed.", 10, 0
    msg_writing     db  "[INK] Writing IR to output file...", 10, 0
    msg_write_ok    db  "[INK] Written to output.ll", 10, 0
    msg_compiling   db  "[INK] Compiling with LLVM...", 10, 0
    msg_done        db  "[INK] Compilation complete! Binary ready.", 10, 0

    ; LLVM IR boilerplate — start of every .ll file
    ir_header       db  "; INK Language — Generated LLVM IR", 10
                    db  "; IndianBrand Technology, Hyderabad, India", 10
                    db  "; Write the Future | Jai Hind!", 10
                    db  10, 0
    ir_header_len   equ $ - ir_header

    ; Target triple for x86-64 Linux
    ir_target       db  'target triple = "x86_64-pc-linux-gnu"', 10
                    db  10, 0
    ir_target_len   equ $ - ir_target

    ; Standard type declarations
    ir_types        db  "; Standard types", 10
                    db  "; int = i64, float = double, bool = i1, text = i8*", 10
                    db  10, 0

    ; Printf declaration for show statement
    ir_printf_decl  db  'declare i32 @printf(i8* nocapture, ...)', 10
                    db  10, 0
    ir_printf_len   equ $ - ir_printf_decl

    ; String format constants
    ir_fmt_int      db  '@.fmt.int = private constant [4 x i8] c"%ld\00"', 10, 0
    ir_fmt_str      db  '@.fmt.str = private constant [3 x i8] c"%s\00"', 10, 0
    ir_fmt_nl       db  '@.fmt.newline = private constant [2 x i8] c"\0A\00"', 10, 0

    ; Main function start
    ir_main_start   db  "define i64 @main() {", 10
                    db  "entry:", 10, 0
    ir_main_end     db  "  ret i64 0", 10
                    db  "}", 10, 0

    ; LLVM IR instruction templates
    ; Add instruction
    ir_add          db  "  %", 0
    ir_add_mid      db  " = add i64 %", 0
    ir_add_comma    db  ", %", 0

    ; Sub instruction
    ir_sub_op       db  " = sub i64 %", 0

    ; Mul instruction
    ir_mul_op       db  " = mul i64 %", 0

    ; Div instruction
    ir_div_op       db  " = sdiv i64 %", 0

    ; Alloca — allocate variable on stack
    ir_alloca       db  "  %", 0
    ir_alloca_type  db  " = alloca i64", 10, 0

    ; Store — write value to variable
    ir_store        db  "  store i64 %", 0
    ir_store_to     db  ", i64* %", 0
    ir_newline      db  10, 0

    ; Load — read value from variable
    ir_load         db  "  %", 0
    ir_load_from    db  " = load i64, i64* %", 0

    ; Call printf for show
    ir_call_printf  db  "  call i32 (i8*, ...) @printf(i8* getelementptr inbounds ", 0
    ir_call_arg     db  ", i64 %", 0
    ir_call_end     db  ")", 10, 0

    ; Branch instructions
    ir_br           db  "  br label %", 0
    ir_br_cond      db  "  br i1 %", 0
    ir_br_then      db  ", label %", 0
    ir_br_else      db  ", label %", 0
    ir_label        db  10, 0  ; newline before label

    ; Compare instructions
    ir_icmp_eq      db  " = icmp eq i64 %", 0
    ir_icmp_ne      db  " = icmp ne i64 %", 0
    ir_icmp_lt      db  " = icmp slt i64 %", 0
    ir_icmp_gt      db  " = icmp sgt i64 %", 0
    ir_icmp_le      db  " = icmp sle i64 %", 0
    ir_icmp_ge      db  " = icmp sge i64 %", 0

    ; Function definition
    ir_fn_start     db  "define i64 @", 0
    ir_fn_args      db  "() {", 10
                    db  "entry:", 10, 0
    ir_fn_end       db  "  ret i64 0", 10
                    db  "}", 10, 10, 0

    ; Return instruction
    ir_ret          db  "  ret i64 %", 0

    ; Output filename
    out_filename    db  "output.ll", 0
    out_mode        equ O_WRONLY | O_CREAT | O_TRUNC
    out_perms       equ 0o644

    ; Numbers as strings for register names
    digits          db  "0123456789"

; ── BSS SECTION ──────────────────────────────────────────────

    ; Inline IR strings
    cstr_0 db "  br label %break.target", 10, 0
    cstr_1 db "  %", 0
    cstr_2 db " = alloca i64", 10, 0
    cstr_3 db "  store i64 %", 0
    cstr_4 db ", i64* %", 0
    cstr_5 db 10, 0
    cstr_6 db "  store i64 %", 0
    cstr_7 db ", i64* %", 0
    cstr_8 db 10, 0
    cstr_9 db "call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([4 x i8], [4 x i8]* @.fmt.int, i32 0, i32 0), i64 %", 0
    cstr_10 db ")", 10, 0
    cstr_11 db "call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([2 x i8], [2 x i8]* @.fmt.newline, i32 0, i32 0))", 10, 0
    cstr_12 db "call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([3 x i8], [3 x i8]* @.fmt.str, i32 0, i32 0), i8* %", 0
    cstr_13 db ")", 10, 0
    cstr_14 db "call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([2 x i8], [2 x i8]* @.fmt.newline, i32 0, i32 0))", 10, 0
    cstr_15 db "  %", 0
    cstr_16 db " = add i64 0, ", 0
    cstr_17 db 10, 0
    cstr_18 db "  %", 0
    cstr_19 db " = fadd double 0.0, ", 0
    cstr_20 db 10, 0
    cstr_21 db "  %", 0
    cstr_22 db " = getelementptr inbounds [", 0
    cstr_23 db " x i8], [", 0
    cstr_24 db " x i8]* @.str.", 0
    cstr_25 db ", i32 0, i32 0", 10, 0
    cstr_26 db "  %", 0
    cstr_27 db " = add i64 0, ", 0
    cstr_28 db 10, 0
    cstr_29 db "  %", 0
    cstr_30 db " = load i64, i64* %", 0
    cstr_31 db 10, 0
    cstr_32 db "  %", 0
    cstr_33 db " = add i64 %", 0
    cstr_34 db " = sub i64 %", 0
    cstr_35 db " = mul i64 %", 0
    cstr_36 db " = sdiv i64 %", 0
    cstr_37 db " = srem i64 %", 0
    cstr_38 db " = icmp eq i64 %", 0
    cstr_39 db " = icmp ne i64 %", 0
    cstr_40 db " = icmp slt i64 %", 0
    cstr_41 db " = icmp sgt i64 %", 0
    cstr_42 db " = icmp sle i64 %", 0
    cstr_43 db " = icmp sge i64 %", 0
    cstr_44 db ", %", 0
    cstr_eq db " = ", 0
    cstr_45 db 10, 0
    cstr_46 db "  %", 0
    cstr_47 db " = sub i64 0, %", 0
    cstr_48 db " = xor i1 %", 0
    cstr_49 db ", true", 0
    cstr_50 db 10, 0
    cstr_51 db "  br i1 %", 0
    cstr_52 db ", label %if.then.", 0
    cstr_53 db ", label %if.else.", 0
    cstr_54 db 10, 0
    cstr_55 db 10, 0
    cstr_56 db "if.then.", 0
    cstr_57 db ":", 10, 0
    cstr_58 db "  br label %if.end.", 0
    cstr_59 db 10, 0
    cstr_60 db 10, 0
    cstr_61 db "if.else.", 0
    cstr_62 db ":", 10, 0
    cstr_63 db "  br label %if.end.", 0
    cstr_64 db 10, 0
    cstr_65 db 10, 0
    cstr_66 db "if.end.", 0
    cstr_67 db ":", 10, 0
    cstr_68 db "  br label %while.cond.", 0
    cstr_69 db 10, 0
    cstr_70 db 10, 0
    cstr_71 db "while.cond.", 0
    cstr_72 db ":", 10, 0
    cstr_73 db "  br i1 %", 0
    cstr_74 db ", label %while.body.", 0
    cstr_75 db ", label %while.end.", 0
    cstr_76 db 10, 0
    cstr_77 db 10, 0
    cstr_78 db "while.body.", 0
    cstr_79 db ":", 10, 0
    cstr_80 db "  br label %while.cond.", 0
    cstr_81 db 10, 0
    cstr_82 db 10, 0
    cstr_83 db "while.end.", 0
    cstr_84 db ":", 10, 0
    cstr_85 db "  %", 0
    cstr_86 db " = alloca i64", 10, 0
    cstr_87 db "  store i64 %", 0
    cstr_88 db ", i64* %", 0
    cstr_89 db 10, 0
    cstr_90 db "  br label %for.cond.", 0
    cstr_91 db 10, 0
    cstr_92 db 10, 0
    cstr_93 db "for.cond.", 0
    cstr_94 db ":", 10, 0
    cstr_95 db "  %", 0
    cstr_96 db " = load i64, i64* %", 0
    cstr_97 db 10, 0
    cstr_98 db "  %", 0
    cstr_99 db " = icmp slt i64 %", 0
    cstr_100 db ", %", 0
    cstr_101 db 10, 0
    cstr_102 db "  br i1 %", 0
    cstr_103 db ", label %for.body.", 0
    cstr_104 db ", label %for.end.", 0
    cstr_105 db 10, 0
    cstr_106 db 10, 0
    cstr_107 db "for.body.", 0
    cstr_108 db ":", 10, 0
    cstr_109 db "  %", 0
    cstr_110 db " = add i64 %", 0
    cstr_111 db "  %", 0
    cstr_112 db " = load i64, i64* %", 0
    cstr_113 db 10, 0
    cstr_114 db "  %", 0
    cstr_115 db " = add i64 %", 0
    cstr_116 db ", 1", 10, 0
    cstr_117 db "  store i64 %", 0
    cstr_118 db ", i64* %", 0
    cstr_119 db 10, 0
    cstr_120 db "  br label %for.cond.", 0
    cstr_121 db 10, 0
    cstr_122 db 10, 0
    cstr_123 db "for.end.", 0
    cstr_124 db ":", 10, 0
    cstr_125 db "  br label %loop.start.", 0
    cstr_126 db 10, 0
    cstr_127 db 10, 0
    cstr_128 db "loop.start.", 0
    cstr_129 db ":", 10, 0
    cstr_130 db "  br label %loop.start.", 0
    cstr_131 db 10, 0
    cstr_132 db 10, 0
    cstr_133 db "loop.end.", 0
    cstr_134 db ":", 10, 0
    cstr_135 db "  br label %fn.skip.", 0
    cstr_136 db 10, 0
    cstr_137 db 10, 0
    cstr_138 db "define i64 @", 0
    cstr_139 db "() {", 10
    cstr_140 db "  ret i64 0", 10
    cstr_141 db "fn.skip.", 0
    cstr_142 db ":", 10, 0
    cstr_143 db "  %", 0
    cstr_144 db " = call i64 @", 0
    cstr_145 db "()", 10, 0
    cstr_146 db "  ret i64 %", 0
    cstr_147 db 10, 0
    cstr_148 db "  ret i64 0", 10, 0
    cstr_149 db 10, "; String literal constants", 10, 0
    cstr_150 db "@.str.", 0
    cstr_151 db " = private constant [", 0
    cstr_152 db " x i8] c", 0x22, 0
    cstr_153 db "\00", 0x22, 10, 0


    ; Phase 3: -> text return types
    cstr_fn_def_str    db "define i8* @", 0
    cstr_fn_close_str  db "  ret i8* null", 10, "}", 10, 10, 0
    cstr_ret_str_pfx   db "  ret i8* %", 0
    cstr_ret_null      db "  ret i8* null", 10, 0
    cstr_call_pre_str  db " = call i8* @", 0

    cstr_alloca_plist  db " = alloca i64*", 10, 0
    cstr_store_plist   db "  store i64* %", 0
    cstr_storemid_plist db ", i64** %", 0
    cstr_load_plist    db " = load i64*, i64** %", 0
    cstr_len_gep       db " = getelementptr i64, i64* %", 0
    ; Phase 5: user input
    ir_fmt_scan   db '@.fmt.scan = private constant [4 x i8] c"%ld\00"', 10, 0
    ir_fmt_wmode  db '@.mode.w = private constant [2 x i8] c"w\00"', 10, 0
    ir_fmt_rmode  db '@.mode.r = private constant [2 x i8] c"r\00"', 10, 0
    cstr_scan_pre db " = call i32 (i8*, ...) @scanf(i8* getelementptr inbounds ([4 x i8], [4 x i8]* @.fmt.scan, i32 0, i32 0), i64* %", 0
    cstr_inbuf_malloc db " = call i8* @malloc(i64 256)", 10, 0
    cstr_stdin_load db " = load i8*, i8** @stdin", 10, 0
    cstr_fgets_pre db " = call i8* @fgets(i8* %", 0
    cstr_fgets_mid db ", i32 256, i8* %", 0
    cstr_strip_nl_gep db " = call i8* @strchr(i8* %", 0
    cstr_comma_10 db ", i32 10)", 10, 0
    cstr_store_nlterm db "  store i8 0, i8* %", 0
    ; Phase 5: stdlib (min/max/abs/sum)
    cstr_icmp_slt_r  db " = icmp slt i64 %", 0
    cstr_icmp_sgt_r  db " = icmp sgt i64 %", 0
    cstr_select_pre  db " = select i1 %", 0
    cstr_sel_i64     db ", i64 %", 0
    cstr_sub0        db " = sub i64 0, %", 0
    cstr_bcheck_pre  db "  call void @__ink_bounds_check(i64 %", 0
    cstr_bcheck_mid  db ", i64* %", 0
    cstr_p2i_pre  db " = ptrtoint i8* %", 0
    cstr_p2i_suf  db " to i64", 10, 0
    cstr_i2p_pre  db " = inttoptr i64 %", 0
    cstr_i2p_suf  db " to i8*", 10, 0
    cstr_mapget_pre db " = call i64 @__ink_map_get(i64* %", 0
    cstr_mapget_mid db ", i8* %", 0
    ; file I/O
    bi_write db "write_file"
    bi_read  db "read_file"
    cstr_fopen_w  db " = call i8* @fopen(i8* %", 0
    cstr_fopen_wm db ", i8* getelementptr inbounds ([2 x i8], [2 x i8]* @.mode.w, i32 0, i32 0))", 10, 0
    cstr_fopen_rm db ", i8* getelementptr inbounds ([2 x i8], [2 x i8]* @.mode.r, i32 0, i32 0))", 10, 0
    cstr_fputs    db " = call i32 @fputs(i8* %", 0
    cstr_fputs_f  db ", i8* %", 0
    cstr_fclose   db " = call i32 @fclose(i8* %", 0
    cstr_malloc64k db " = call i8* @malloc(i64 65536)", 10, 0
    cstr_fread    db " = call i64 @fread(i8* %", 0
    cstr_fread_a  db ", i64 1, i64 65535, i8* %", 0
    cstr_gep_i8   db " = getelementptr i8, i8* %", 0
    cstr_gep_i8_r db ", i64 %", 0
    cstr_store_z8 db "  store i8 0, i8* %", 0

    ; Phase 4: lists (heap i64 arrays; slot 0 = length)
    cstr_arr_malloc  db " = call i8* @malloc(i64 ", 0
    cstr_arr_bcast   db " = bitcast i8* %", 0
    cstr_to_i64p     db " to i64*", 10, 0
    cstr_arr_gep     db " = getelementptr i64, i64* %", 0
    cstr_gep_idx     db ", i64 ", 0
    cstr_gep_reg     db ", i64 %", 0
    cstr_store_arr   db "  store i64 ", 0
    cstr_store_areg  db "  store i64 %", 0
    cstr_to_slot     db ", i64* %", 0
    cstr_load_slot   db " = load i64, i64* %", 0
    cstr_idx_add1    db " = add i64 %", 0

    ; Phase 3: int-to-text conversion
    cstr_malloc24    db " = call i8* @malloc(i64 24)", 10, 0
    cstr_sprintf_pre db " = call i32 (i8*, i8*, ...) @sprintf(i8* %", 0
    cstr_sprintf_mid db ", i8* getelementptr inbounds ([4 x i8], [4 x i8]* @.fmt.int, i32 0, i32 0), i64 %", 0

    ; Phase 3: libc + string concat
    ir_exit_decl db 'declare void @exit(i32)', 10, 10, 0
    ir_strcmp_decl db 'declare i32 @strcmp(i8*, i8*)', 10, 10, 0
    ir_mapget_fn db 'define i64 @__ink_map_get(i64* %m, i8* %key) {', 10
                 db 'entry:', 10
                 db '  %n = load i64, i64* %m', 10
                 db '  br label %loop', 10
                 db 'loop:', 10
                 db '  %i = phi i64 [0, %entry], [%ni, %cont]', 10
                 db '  %done = icmp sge i64 %i, %n', 10
                 db '  br i1 %done, label %notfound, label %body', 10
                 db 'body:', 10
                 db '  %koff = mul i64 %i, 2', 10
                 db '  %koff1 = add i64 %koff, 1', 10
                 db '  %kslot = getelementptr i64, i64* %m, i64 %koff1', 10
                 db '  %kint = load i64, i64* %kslot', 10
                 db '  %kptr = inttoptr i64 %kint to i8*', 10
                 db '  %cmp = call i32 @strcmp(i8* %kptr, i8* %key)', 10
                 db '  %eq = icmp eq i32 %cmp, 0', 10
                 db '  br i1 %eq, label %found, label %cont', 10
                 db 'found:', 10
                 db '  %voff = add i64 %koff, 2', 10
                 db '  %vslot = getelementptr i64, i64* %m, i64 %voff', 10
                 db '  %val = load i64, i64* %vslot', 10
                 db '  ret i64 %val', 10
                 db 'cont:', 10
                 db '  %ni = add i64 %i, 1', 10
                 db '  br label %loop', 10
                 db 'notfound:', 10
                 db '  ret i64 0', 10
                 db '}', 10, 10, 0
    ir_bounds_msg db '@.ink.oob = private constant [45 x i8] c"[INK RUNTIME ERROR] List index out of range\0A\00"', 10, 10, 0
    ir_bounds_fn db 'define void @__ink_bounds_check(i64 %idx, i64* %arr) {', 10
                 db 'entry:', 10
                 db '  %len = load i64, i64* %arr', 10
                 db '  %neg = icmp slt i64 %idx, 0', 10
                 db '  %oob = icmp sge i64 %idx, %len', 10
                 db '  %bad = or i1 %neg, %oob', 10
                 db '  br i1 %bad, label %fail, label %ok', 10
                 db 'fail:', 10
                 db '  call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([45 x i8], [45 x i8]* @.ink.oob, i32 0, i32 0))', 10
                 db '  call void @exit(i32 1)', 10
                 db '  unreachable', 10
                 db 'ok:', 10
                 db '  ret void', 10
                 db '}', 10, 10, 0
    ir_libc_decl db 'declare i64 @strlen(i8* nocapture)', 10
                 db 'declare i8* @malloc(i64)', 10
                 db 'declare i8* @strcpy(i8*, i8* nocapture)', 10
                 db 'declare i8* @strcat(i8*, i8* nocapture)', 10
                 db 'declare i32 @sprintf(i8*, i8* nocapture, ...)', 10
                 db 'declare i32 @scanf(i8* nocapture, ...)', 10
                 db 'declare i8* @fgets(i8*, i32, i8*)', 10
                 db '@stdin = external global i8*', 10
                 db 'declare i8* @strchr(i8*, i32)', 10
                 db 'declare i8* @fopen(i8*, i8*)', 10
                 db 'declare i32 @fputs(i8*, i8*)', 10
                 db 'declare i32 @fclose(i8*)', 10
                 db 'declare i64 @fread(i8*, i64, i64, i8*)', 10
                 db 'declare i64 @fseek(i8*, i64, i32)', 10
                 db 'declare i64 @ftell(i8*)', 10, 10, 0
    cstr_strlen_pre db " = call i64 @strlen(i8* %", 0
    cstr_malloc_pre db " = call i8* @malloc(i64 %", 0
    cstr_strcpy_pre db " = call i8* @strcpy(i8* %", 0
    cstr_strcat_pre db " = call i8* @strcat(i8* %", 0
    cstr_comma_i8p  db ", i8* %", 0
    cstr_close_nl   db ")", 10, 0
    cstr_fn_par_str db "i8* %", 0
    cstr_fn_par_list db "i64* %", 0

    ; Phase 2 strings
    cstr_while_end_lbl db "while.end.", 0
    cstr_while_cond_lbl db "while.cond.", 0
    cstr_loop_end_lbl2 db "loop.end.", 0
    cstr_loop_start_lbl2 db "loop.start.", 0
    cstr_brk_dead    db "brk.dead.", 0
    err_undef_var    db "[INK ERROR] Undefined variable: ", 0
    err_unknown_fn   db "[INK ERROR] Unknown function: ", 0
    err_arg_count    db "[INK ERROR] Wrong number of arguments in call to: ", 0
    err_arg_type     db "[INK ERROR] Argument type mismatch (int vs text) in call to: ", 0
    err_op_on_text   db "[INK ERROR] Arithmetic/comparison operator used on text value", 10, 0
    err_assign_type  db "[INK ERROR] Type mismatch in assignment to: ", 0
    err_break_outside db "[INK ERROR] break/continue outside a loop", 10, 0
    cstr_alloca_pstr   db " = alloca i8*", 10, 0
    cstr_store_pstr    db "  store i8* %", 0
    cstr_storemid_pstr db ", i8** %", 0
    cstr_load_pstr     db " = load i8*, i8** %", 0
    cstr_fn_def1     db "define i64 @", 0
    cstr_fn_par_i64  db "i64 %", 0
    cstr_fn_par_sep  db ", ", 0
    cstr_fn_body_open db ") {", 10, "entry:", 10, 0
    cstr_fn_close    db "  ret i64 0", 10, "}", 10, 10, 0
    cstr_lparen_only db "(", 0
    cstr_call_pre    db " = call i64 @", 0
    cstr_call_close  db ")", 10, 0
    cstr_icmp_ne0    db " = icmp ne i64 %", 0
    cstr_comma0_nl   db ", 0", 10, 0
    cstr_ret_pfx     db "  ret i64 %", 0
    cstr_ret0        db "  ret i64 0", 10, 0
    cstr_ret_dead    db "ret.dead.", 0

    ; For loop string constants
    cstr_alloca_pfx db "  %", 0
    cstr_alloca_sfx db " = alloca i64", 10, 0
    cstr_store_pfx db "  store i64 %", 0
    cstr_store_mid db ", i64* %", 0
    cstr_nl db 10, 0
    cstr_br_label db "  br label %", 0
    cstr_for_cond db "for.cond.", 0
    cstr_colon_nl db ":", 10, 0
    cstr_pct db "  %", 0
    cstr_load_i64 db " = load i64, i64* %", 0
    cstr_icmp_slt db " = icmp slt i64 %", 0
    cstr_comma_pct db ", %", 0
    cstr_lbl_comma db ", label %", 0
    cstr_for_body_lbl db "for.body.", 0
    cstr_for_end_lbl db "for.end.", 0
    cstr_add_i64_pct db " = add i64 %", 0
    cstr_comma_1_nl db ", 1", 10, 0

    ; Phase 4 additional strings
    cstr_load db " = load i64, i64* %", 0
    cstr_icmp_lt db " = icmp slt i64 %", 0
    cstr_br_i1 db "  br i1 %", 0
    cstr_lbl_then db ", label %for.body.", 0
    cstr_lbl_else db ", label %for.end.", 0
    cstr_for_body db "for.body.", 0
    cstr_for_end db "for.end.", 0
    cstr_add_i64 db " = add i64 %", 0
    cstr_comma1 db ", 1", 10, 0

section .bss
    ; Phase 2: two-buffer function emission
    emit_buf_base resq 1    ; pointer to active output buffer
    emit_pos_addr resq 1    ; pointer to active position variable
    fn_buf        resb 1048576  ; function definitions buffer (1MB)
    fn_pos        resq 1
    saved_reg_counter resq 1
    saved_var_count   resq 1
    var_scope_base    resq 1    ; lookups search from here (function scoping)
    cg_error_flag     resq 1    ; set on undefined variable etc.
    cur_loop_end_lbl  resq 1    ; label number of innermost loop end
    cur_loop_cond_lbl resq 1    ; label number of innermost loop cond/start
    cur_loop_kind     resq 1    ; 0=none 1=while 2=for 3=loop
    fn_arg_regs   resq 16   ; arg registers for a call
    fn_arg_isstr  resq 16   ; per-arg: 1 if string typed
    fn_arg_islist resq 16   ; per-arg: 1 if list typed
    fnp_is_text   resq 1    ; current param is text flag
    fnp_is_list   resq 1    ; current param is list flag
    fn_table      resb 64*40 ; name_start, name_len, rettype, param_count, type_mask
    chk_fn_entry  resq 1     ; entry ptr during call checking
    arr_raw   resq 1
    arr_ptr   resq 1
    arr_n     resq 1
    arr_slot  resq 1
    arr_elem_is_str resq 1   ; last array literal: 1 if elements are text
    idx_elem_is_str resq 1   ; last index/list var: 1 if elements are text
    map_ptr resq 1
    map_keys resq 256
    map_vals resq 256
    map_n resq 1
    map_val_is_str resq 1
    fio_a resq 1
    fio_b resq 1
    fio_c resq 1
    mm_is_max resq 1         ; min/max builtin: 1 if max
    arr_elems resq 256    ; element value registers (build time)
    fn_table_count resq 1
    cur_fn_rettype resq 1   ; return type of fn being generated (0 in main)
    cc_l_reg resq 1
    cc_r_reg resq 1
    cc_len1  resq 1
    cc_len2  resq 1
    cc_sum   resq 1
    cc_tot   resq 1
    cc_buf   resq 1
    fn_arg_count  resq 1
    for_end_reg   resq 1   ; end register number
    for_ctr_reg   resq 1   ; counter alloca register
    for_loaded_reg resq 1  ; loaded value register (temp)
    for_inc_reg   resq 1   ; incremented value register (temp)
    for_ctr_alloca resq 1  ; the actual counter alloca register (permanent)
    for_cur_reg    resq 1  ; current value register
    for_cmp_reg    resq 1  ; compare result register

    ; LLVM IR output buffer
    ir_buf          resb    MAX_IR

    ; Current position in IR buffer
    ir_pos          resq    1

    ; Register counter — current SSA register number
    reg_counter     resq    1

    ; Label counter — for unique branch labels
    label_counter   resq    1

    ; Variable table
    var_table       resb    MAX_VAR_TABLE * VAR_ENTRY_SIZE

    ; Number of variables in table
    var_count       resq    1

    ; Pointer to source buffer (for reading token text)
    cg_src_buf      resq    1

    ; Current function name buffer
    cur_fn_name     resb    256
    cur_fn_len      resq    1

    ; Temporary number buffer for converting ints to strings
    num_buf         resb    32

    ; Output file descriptor
    out_fd          resq    1

    ; String literal counter for unique global names
    str_lit_count   resq    1

    ; String literal storage — global string constants in IR
    ; Each string literal becomes a global in LLVM IR
    str_lit_buf     resb    65536   ; 64KB for string literals section

    ; Position in string literal buffer
    str_lit_pos     resq    1

; ── TEXT SECTION ─────────────────────────────────────────────
section .text
    global codegen_init
    global ink_codegen
    global codegen_write_output

; ============================================================
; CODEGEN_INIT
; Initialises code generator state
; Input: rdi = pointer to source buffer
; ============================================================
codegen_init:
    push    rbp
    mov     rbp, rsp

    mov     [cg_src_buf], rdi   ; save source buffer pointer

    ; Reset all counters
    mov     qword [ir_pos],        0
    mov     qword [fn_pos],        0
    mov     qword [var_scope_base], 0
    mov     qword [cg_error_flag],  0
    mov     qword [cur_loop_kind],  0
    mov     qword [fn_table_count], 0
    mov     qword [cur_fn_rettype], 0
    lea     rax, [ir_buf]
    mov     [emit_buf_base], rax
    lea     rax, [ir_pos]
    mov     [emit_pos_addr], rax
    mov     qword [reg_counter],   0
    mov     qword [label_counter], 0
    mov     qword [var_count],     0
    mov     qword [str_lit_count], 0
    mov     qword [str_lit_pos],   0

    pop     rbp
    ret

; ============================================================
; INK_CODEGEN — main code generation entry point
; Input: rdi = pointer to root AST node (PROGRAM node)
; Returns: rax = 1 if success, 0 if error
; ============================================================
ink_codegen:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12

    mov     r12, rdi            ; save root node

    ; Print status message
    mov     rdi, msg_codegen
    call    cg_print_str

    ; Write LLVM IR header
    call    emit_header

    ; Pre-pass: register all function signatures
    mov     rdi, r12
    call    codegen_register_fns

    ; Generate code for entire program
    mov     rdi, r12
    call    codegen_program

    ; Write main function end
    call    emit_main_end

    ; Write all string literals (global constants)
    call    emit_string_globals

    ; Check for semantic errors
    cmp     qword [cg_error_flag], 0
    jne     .had_errors

    ; Success
    mov     rdi, msg_codegen_ok
    call    cg_print_str

    mov     rax, 1

    pop     r12
    pop     rbx
    pop     rbp
    ret

.had_errors:
    mov     rdi, msg_codegen_err
    call    cg_print_str
    xor     rax, rax
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; CODEGEN_REGISTER_FNS — pre-pass
; Registers every top-level function's signature BEFORE any
; code generation, so functions can be called before defined.
; Input: rdi = PROGRAM node
; ============================================================
codegen_register_fns:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13

    mov     r12, [rdi + NODE_LEFT]      ; first statement
.loop:
    test    r12, r12
    jz      .done
    mov     rax, [r12 + NODE_TYPE]
    cmp     rax, NODE_FN_DEF
    jne     .next

    ; return type
    mov     rdi, [r12 + NODE_TSTART]    ; return-type node
    call    type_node_is_text
    mov     r13, rax

    ; param count + type mask
    xor     rdx, rdx
    xor     rcx, rcx
    mov     rbx, [r12 + NODE_EXTRA]
.sig:
    test    rbx, rbx
    jz      .sig_done
    push    rcx
    push    rdx
    mov     rdi, rbx
    call    param_is_text
    pop     rdx
    pop     rcx
    test    rax, rax
    jz      .sig_int
    bts     rcx, rdx
.sig_int:
    inc     rdx
    mov     rbx, [rbx + NODE_NEXT]
    jmp     .sig
.sig_done:
    mov     rdi, [r12 + NODE_LEFT]
    mov     rsi, r13
    call    fn_table_add

.next:
    mov     r12, [r12 + NODE_NEXT]
    jmp     .loop

.done:
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; EMIT_HEADER
; Writes the LLVM IR file header
; ============================================================
emit_header:
    push    rbp
    mov     rbp, rsp

    ; Write comment header
    mov     rdi, ir_header
    call    emit_str

    ; Write target triple
    mov     rdi, ir_target
    call    emit_str

    ; Write printf declaration
    mov     rdi, ir_printf_decl
    call    emit_str

    ; Write libc string declarations
    mov     rdi, ir_libc_decl
    call    emit_str

    ; Write map runtime helper
    mov     rdi, ir_strcmp_decl
    call    emit_str
    mov     rdi, ir_mapget_fn
    call    emit_str

    ; Write bounds-check error message + helper
    mov     rdi, ir_bounds_msg
    call    emit_str
    mov     rdi, ir_exit_decl
    call    emit_str
    mov     rdi, ir_bounds_fn
    call    emit_str

    ; Write format string declarations
    mov     rdi, ir_fmt_int
    call    emit_str
    mov     rdi, ir_fmt_scan
    call    emit_str
    mov     rdi, ir_fmt_wmode
    call    emit_str
    mov     rdi, ir_fmt_rmode
    call    emit_str
    mov     rdi, ir_fmt_str
    call    emit_str
    mov     rdi, ir_fmt_nl
    call    emit_str

    ; Write newline separator
    mov     rdi, ir_newline
    call    emit_str

    ; Write main function start
    mov     rdi, ir_main_start
    call    emit_str

    pop     rbp
    ret

; ============================================================
; EMIT_MAIN_END
; Writes closing of main function
; ============================================================
emit_main_end:
    push    rbp
    mov     rbp, rsp

    mov     rdi, ir_main_end
    call    emit_str

    pop     rbp
    ret

; ============================================================
; CODEGEN_PROGRAM
; Generates code for PROGRAM node
; Input: rdi = PROGRAM node pointer
; ============================================================
codegen_program:
    push    rbp
    mov     rbp, rsp
    push    r12

    mov     r12, rdi

    ; Get first statement (left child)
    mov     r12, [r12 + NODE_LEFT]

.stmt_loop:
    test    r12, r12
    jz      .done               ; no more statements

    ; Generate code for this statement
    mov     rdi, r12
    call    codegen_node

    ; Move to next sibling
    mov     r12, [r12 + NODE_NEXT]
    jmp     .stmt_loop

.done:
    pop     r12
    pop     rbp
    ret

; ============================================================
; CODEGEN_NODE
; Dispatches to correct codegen function based on node type
; Input: rdi = AST node pointer
; Returns: rax = LLVM register number holding the result
; ============================================================
codegen_node:
    push    rbp
    mov     rbp, rsp
    push    rbx

    test    rdi, rdi
    jz      .null_node

    mov     rbx, rdi            ; save node pointer
    mov     rax, [rdi + NODE_TYPE]  ; get node type

    cmp     rax, NODE_LET
    je      .do_let

    cmp     rax, NODE_CONST
    je      .do_const

    cmp     rax, NODE_FN_DEF
    je      .do_fn_def

    cmp     rax, NODE_FN_CALL
    je      .do_fn_call

    cmp     rax, NODE_RETURN
    je      .do_return

    cmp     rax, NODE_IF
    je      .do_if

    cmp     rax, NODE_WHILE
    je      .do_while

    cmp     rax, NODE_FOR
    je      .do_for

    cmp     rax, NODE_LOOP
    je      .do_loop

    cmp     rax, NODE_BREAK
    je      .do_break

    cmp     rax, NODE_CONTINUE
    je      .do_continue

    cmp     rax, NODE_SHOW
    je      .do_show

    cmp     rax, NODE_BINARY
    je      .do_binary

    cmp     rax, NODE_UNARY
    je      .do_unary

    cmp     rax, NODE_INT_LIT
    je      .do_int_lit

    cmp     rax, NODE_FLOAT_LIT
    je      .do_float_lit

    cmp     rax, NODE_STRING_LIT
    je      .do_string_lit

    cmp     rax, NODE_BOOL_LIT
    je      .do_bool_lit

    cmp     rax, NODE_IDENT
    je      .do_ident

    cmp     rax, NODE_BLOCK
    je      .do_block

    cmp     rax, NODE_ASSIGN
    je      .do_assign

    cmp     rax, NODE_MAP_LIT
    je      .do_map

    cmp     rax, NODE_ARRAY_LIT
    je      .do_array

    cmp     rax, NODE_INDEX
    je      .do_index

    ; Unknown node — skip
    xor     rax, rax
    jmp     .done

.do_let:
    mov     rdi, rbx
    call    codegen_let
    jmp     .done

.do_const:
    mov     rdi, rbx
    call    codegen_let         ; const is same as let for now
    jmp     .done

.do_fn_def:
    mov     rdi, rbx
    call    codegen_fn_def
    jmp     .done

.do_fn_call:
    mov     rdi, rbx
    call    codegen_fn_call
    jmp     .done

.do_return:
    mov     rdi, rbx
    call    codegen_return
    jmp     .done

.do_if:
    mov     rdi, rbx
    call    codegen_if
    jmp     .done

.do_while:
    mov     rdi, rbx
    call    codegen_while
    jmp     .done

.do_for:
    mov     rdi, rbx
    call    codegen_for
    jmp     .done

.do_loop:
    mov     rdi, rbx
    call    codegen_loop
    jmp     .done

.do_break:
    mov     rdi, rbx
    call    codegen_break
    jmp     .done

.do_continue:
    mov     rdi, rbx
    call    codegen_continue
    jmp     .done

.do_show:
    mov     rdi, rbx
    call    codegen_show
    jmp     .done

.do_binary:
    mov     rdi, rbx
    call    codegen_binary
    jmp     .done

.do_unary:
    mov     rdi, rbx
    call    codegen_unary
    jmp     .done

.do_int_lit:
    mov     rdi, rbx
    call    codegen_int_lit
    jmp     .done

.do_float_lit:
    mov     rdi, rbx
    call    codegen_float_lit
    jmp     .done

.do_string_lit:
    mov     rdi, rbx
    call    codegen_string_lit
    jmp     .done

.do_bool_lit:
    mov     rdi, rbx
    call    codegen_bool_lit
    jmp     .done

.do_ident:
    mov     rdi, rbx
    call    codegen_ident
    jmp     .done

.do_block:
    mov     rdi, rbx
    call    codegen_block
    jmp     .done

.do_assign:
    mov     rdi, rbx
    call    codegen_assign
    jmp     .done

.do_map:
    mov     rdi, rbx
    call    codegen_map_lit
    jmp     .done

.do_array:
    mov     rdi, rbx
    call    codegen_array_lit
    jmp     .done

.do_index:
    mov     rdi, rbx
    call    codegen_index
    jmp     .done

.null_node:
    xor     rax, rax

.done:
    pop     rbx
    pop     rbp
    ret

; ============================================================
; CODEGEN_LET
; Generates: let name = expr
;
; LLVM IR output:
;   %name = alloca i64          ; allocate on stack
;   %val = ... (expr result)    ; evaluate expression
;   store i64 %val, i64* %name  ; store value
; ============================================================
codegen_let:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi            ; r12 = LET node
    mov     r13, [r12 + NODE_LEFT]  ; r13 = IDENT node

    ; ── Determine type from RHS (0=int 1=text 2=list) ────
    mov     rdi, [r12 + NODE_RIGHT]
    call    expr_type
    mov     rcx, rax
.type_done:
    push    rcx                 ; [rsp] = type

    ; ── Alloca register + var table ──────────────────────
    call    new_reg
    mov     rbx, rax
    mov     rdi, r13
    mov     rsi, rbx
    mov     rdx, [rsp]          ; type
    call    var_table_add

    ; ── Emit alloca (i64 or i8*) ─────────────────────────
    mov     rdi, cstr_1         ; "  %"
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    cmp     qword [rsp], 2
    jge     .alloca_list
    cmp     qword [rsp], 1
    je      .alloca_str
    mov     rdi, cstr_2         ; " = alloca i64\n"
    call    emit_str
    jmp     .alloca_done
.alloca_str:
    mov     rdi, cstr_alloca_pstr   ; " = alloca i8*\n"
    call    emit_str
    jmp     .alloca_done
.alloca_list:
    mov     rdi, cstr_alloca_plist  ; " = alloca i64*\n"
    call    emit_str
.alloca_done:

    ; ── Evaluate RHS ─────────────────────────────────────
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    push    rax                 ; [rsp]=value reg, [rsp+8]=type

    ; ── Emit store (typed) ───────────────────────────────
    cmp     qword [rsp + 8], 2
    jge     .st_list
    cmp     qword [rsp + 8], 1
    je      .st_str
    mov     rdi, cstr_3         ; "  store i64 %"
    call    emit_str
    jmp     .st_val
.st_str:
    mov     rdi, cstr_store_pstr    ; "  store i8* %"
    call    emit_str
    jmp     .st_val
.st_list:
    mov     rdi, cstr_store_plist   ; "  store i64* %"
    call    emit_str
.st_val:
    pop     rdi                 ; value register
    call    emit_num
    cmp     qword [rsp], 2
    jge     .st_mid_list
    cmp     qword [rsp], 1
    je      .st_mid_str
    mov     rdi, cstr_4         ; ", i64* %"
    call    emit_str
    jmp     .st_mid_done
.st_mid_str:
    mov     rdi, cstr_storemid_pstr ; ", i8** %"
    call    emit_str
    jmp     .st_mid_done
.st_mid_list:
    mov     rdi, cstr_storemid_plist ; ", i64** %"
    call    emit_str
.st_mid_done:
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_5         ; newline
    call    emit_str

    pop     rcx                 ; discard type
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; CODEGEN_ASSIGN
; Generates: name = expr
; ============================================================
codegen_assign:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi

    ; ── Indexed assignment? arr[i] = value ───────────────
    mov     rax, [r12 + NODE_LEFT]
    mov     rax, [rax + NODE_TYPE]
    cmp     rax, NODE_INDEX
    jne     .simple_assign

    ; Is the target list text-typed? (need ptrtoint on store)
    mov     rax, [r12 + NODE_LEFT]
    mov     rdi, [rax + NODE_LEFT]
    call    expr_type
    mov     qword [idx_elem_is_str], 0
    cmp     rax, 3
    jne     .ia_not_text
    mov     qword [idx_elem_is_str], 1
.ia_not_text:

    ; evaluate RHS value
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    mov     r13, rax                ; value

    ; if text list, ptrtoint value to i64 for storage
    cmp     qword [idx_elem_is_str], 1
    jne     .ia_val_ready
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_p2i_pre
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_p2i_suf
    call    emit_str
    pop     r13
.ia_val_ready:

    ; evaluate array pointer (INDEX node's LEFT)
    mov     rax, [r12 + NODE_LEFT]
    mov     rdi, [rax + NODE_LEFT]
    call    codegen_node
    mov     [arr_ptr], rax

    ; evaluate index (INDEX node's RIGHT)
    mov     rax, [r12 + NODE_LEFT]
    mov     rdi, [rax + NODE_RIGHT]
    call    codegen_node
    push    rax                     ; raw index

    ; ── bounds check ─────────────────────────────────────
    mov     rdi, cstr_bcheck_pre
    call    emit_str
    mov     rdi, [rsp]              ; raw index
    call    emit_num
    mov     rdi, cstr_bcheck_mid
    call    emit_str
    mov     rdi, [arr_ptr]
    call    emit_num
    mov     rdi, cstr_call_close
    call    emit_str

    ; realidx = index + 1
    call    new_reg
    mov     rbx, rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_idx_add1      ; " = add i64 %"
    call    emit_str
    pop     rdi                     ; raw index reg
    call    emit_num
    mov     rdi, cstr_comma_1_nl    ; ", 1\n"
    call    emit_str

    ; slot = gep ptr, %realidx
    call    new_reg
    mov     [arr_slot], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_arr_gep       ; " = getelementptr i64, i64* %"
    call    emit_str
    mov     rdi, [arr_ptr]
    call    emit_num
    mov     rdi, cstr_gep_reg       ; ", i64 %"
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    ; store i64 %value, i64* %slot
    mov     rdi, cstr_store_areg    ; "  store i64 %"
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_to_slot       ; ", i64* %"
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

.simple_assign:
    ; Evaluate RHS
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    mov     r13, rax                ; value register

    ; Look up variable
    mov     rdi, [r12 + NODE_LEFT]
    call    var_table_get
    cmp     rax, -1
    jne     .var_ok
    mov     qword [cg_error_flag], 1
    mov     rdi, err_undef_var
    call    cg_print_str
    mov     rax, [r12 + NODE_LEFT]
    mov     rdi, [rax + NODE_TSTART]
    mov     rsi, [rax + NODE_TLEN]
    call    cg_print_src
    xor     rax, rax
.var_ok:
    mov     rbx, rax                ; var alloca register

    ; Variable's declared type
    mov     rdi, [r12 + NODE_LEFT]
    call    var_table_get_type
    cmp     rax, -1
    jne     .t_ok
    xor     rax, rax
.t_ok:
    push    rax                     ; [rsp] = var type

    ; RHS type must match
    mov     rdi, [r12 + NODE_RIGHT]
    call    expr_is_string
    cmp     rax, [rsp]
    je      .types_match
    mov     qword [cg_error_flag], 1
    mov     rdi, err_assign_type
    call    cg_print_str
    mov     rax, [r12 + NODE_LEFT]
    mov     rdi, [rax + NODE_TSTART]
    mov     rsi, [rax + NODE_TLEN]
    call    cg_print_src
.types_match:

    ; Typed store
    cmp     qword [rsp], 1
    je      .s_str
    mov     rdi, cstr_3             ; "  store i64 %"
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_4             ; ", i64* %"
    call    emit_str
    jmp     .s_var
.s_str:
    mov     rdi, cstr_store_pstr    ; "  store i8* %"
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_storemid_pstr ; ", i8** %"
    call    emit_str
.s_var:
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_5             ; newline
    call    emit_str

    pop     rcx                     ; discard type
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; CODEGEN_SHOW
; Generates: show expr
;
; LLVM IR output:
;   %val = ... (expression)
;   call i32 @printf("%ld\n", %val)
; ============================================================
codegen_show:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi            ; r12 = SHOW node

    ; Get left child node and check its type BEFORE codegen
    mov     rax, [r12 + NODE_LEFT]
    test    rax, rax
    jz      .done

    ; Save node type for later
    mov     rbx, [rax + NODE_TYPE]  ; rbx = child node type

    ; Full string-type inference (vars, concat chains)
    push    rax
    mov     rdi, rax
    call    expr_is_string
    cmp     rax, 1
    pop     rax
    jne     .type_known
    mov     rbx, NODE_STRING_LIT    ; treat as string
.type_known:

    ; Generate the expression to show
    mov     rdi, rax
    call    codegen_node
    mov     r13, rax            ; r13 = result register

    cmp     rbx, NODE_STRING_LIT
    je      .show_string

    ; Show as integer — %N = call i32 @printf(fmt, val)
    mov     rdi, cstr_32        ; "  %"
    call    emit_str
    call    new_reg
    push    rax
    mov     rdi, rax
    call    emit_num
    mov     rdi, cstr_eq
    call    emit_str
    mov     rdi, cstr_9
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_10
    call    emit_str
    pop     rax

    ; Print newline — %N = call i32 @printf(newline)
    mov     rdi, cstr_32        ; "  %"
    call    emit_str
    call    new_reg
    push    rax
    mov     rdi, rax
    call    emit_num
    mov     rdi, cstr_eq
    call    emit_str
    mov     rdi, cstr_11
    call    emit_str
    pop     rax
    jmp     .done

.show_string:
    ; Show as string — %N = call i32 @printf(fmt, ptr)
    mov     rdi, cstr_32
    call    emit_str
    call    new_reg
    push    rax
    mov     rdi, rax
    call    emit_num
    mov     rdi, cstr_eq
    call    emit_str
    mov     rdi, cstr_12
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_13
    call    emit_str
    pop     rax

    ; Print newline
    mov     rdi, cstr_32
    call    emit_str
    call    new_reg
    push    rax
    mov     rdi, rax
    call    emit_num
    mov     rdi, cstr_eq
    call    emit_str
    mov     rdi, cstr_14
    call    emit_str
    pop     rax

.done:
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; CODEGEN_INT_LIT
; Generates code for integer literal: 42
;
; LLVM IR output:
;   %reg = add i64 0, 42    ; load constant into register
; ============================================================
codegen_int_lit:
    push    rbp
    mov     rbp, rsp
    push    r12

    mov     r12, rdi            ; r12 = INT_LIT node

    ; Allocate new register
    call    new_reg
    push    rax                 ; save register number

    ; Emit: %reg = add i64 0, <value>
    mov     rdi, cstr_15
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_16
    call    emit_str

    ; Get the actual integer value from source
    mov     rdi, [r12 + NODE_TSTART]   ; start position
    mov     rsi, [r12 + NODE_TLEN]     ; length
    call    emit_source_text

    mov     rdi, cstr_17
    call    emit_str

    pop     rax                 ; return register number

    pop     r12
    pop     rbp
    ret

; ============================================================
; CODEGEN_FLOAT_LIT
; Generates code for float literal: 3.14
; ============================================================
codegen_float_lit:
    push    rbp
    mov     rbp, rsp
    push    r12

    mov     r12, rdi

    call    new_reg
    push    rax

    ; For floats — use double type in LLVM
    mov     rdi, cstr_18
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_19
    call    emit_str

    mov     rdi, [r12 + NODE_TSTART]
    mov     rsi, [r12 + NODE_TLEN]
    call    emit_source_text

    mov     rdi, cstr_20
    call    emit_str

    pop     rax
    pop     r12
    pop     rbp
    ret

; ============================================================
; CODEGEN_STRING_LIT
; Generates code for string literal: "Jai Hind!"
;
; LLVM IR output (global):
;   @.str.0 = private constant [10 x i8] c"Jai Hind!\00"
;
; Usage:
;   %reg = getelementptr [10 x i8], [10 x i8]* @.str.0, i32 0, i32 0
; ============================================================
codegen_string_lit:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13

    mov     r12, rdi            ; r12 = STRING_LIT node

    ; Get string literal index
    mov     r13, [str_lit_count]
    inc     qword [str_lit_count]

    ; Save this string literal for later global emission
    ; Store: str_start, str_len, str_index in str_lit_buf
    mov     rax, [str_lit_pos]
    mov     rbx, [r12 + NODE_TSTART]
    mov     [str_lit_buf + rax], rbx
    add     rax, 8
    mov     rbx, [r12 + NODE_TLEN]
    mov     [str_lit_buf + rax], rbx
    add     rax, 8
    mov     [str_lit_buf + rax], r13
    add     rax, 8
    mov     [str_lit_pos], rax

    ; Allocate register for the pointer
    call    new_reg
    push    rax

    ; Emit: %reg = getelementptr...
    mov     rdi, cstr_21
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_22
    call    emit_str

    ; String length + 1 for null terminator
    mov     rdi, [r12 + NODE_TLEN]
    inc     rdi
    call    emit_num

    mov     rdi, cstr_23
    call    emit_str

    mov     rdi, [r12 + NODE_TLEN]
    inc     rdi
    call    emit_num

    mov     rdi, cstr_24
    call    emit_str
    mov     rdi, r13
    call    emit_num

    mov     rdi, cstr_25
    call    emit_str

    pop     rax
    pop     r13
    pop     r12
    pop     rbp
    ret

; ============================================================
; CODEGEN_BOOL_LIT
; Generates code for bool literal: true / false
; ============================================================
codegen_bool_lit:
    push    rbp
    mov     rbp, rsp
    push    r12

    mov     r12, rdi

    call    new_reg
    push    rax

    mov     rdi, cstr_26
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_27
    call    emit_str

    ; extra = 1 for true, 0 for false
    mov     rdi, [r12 + NODE_EXTRA]
    call    emit_num

    mov     rdi, cstr_28
    call    emit_str

    pop     rax
    pop     r12
    pop     rbp
    ret

; ============================================================
; CODEGEN_IDENT
; Generates code to load a variable: name
;
; LLVM IR output:
;   %reg = load i64, i64* %var_reg
; ============================================================
codegen_ident:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13

    mov     r12, rdi            ; IDENT node

    mov     rdi, r12
    call    var_table_get
    cmp     rax, -1
    jne     .found
    ; ── Undefined variable: report and flag error ────────
    mov     qword [cg_error_flag], 1
    mov     rdi, err_undef_var
    call    cg_print_str
    mov     rdi, [r12 + NODE_TSTART]
    mov     rsi, [r12 + NODE_TLEN]
    call    cg_print_src
    xor     rax, rax            ; dummy register 0
.found:
    mov     r13, rax            ; alloca register

    mov     rdi, r12
    call    var_table_get_type
    cmp     rax, -1
    jne     .type_ok
    xor     rax, rax            ; default int
.type_ok:
    push    rax                 ; [rsp] = type

    call    new_reg
    push    rax                 ; [rsp]=new reg, [rsp+8]=type

    mov     rdi, cstr_pct       ; "  %"
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    cmp     qword [rsp + 8], 2
    jge     .ld_list
    cmp     qword [rsp + 8], 1
    je      .ld_str
    mov     rdi, cstr_load_i64  ; " = load i64, i64* %"
    call    emit_str
    jmp     .ld_done
.ld_str:
    mov     rdi, cstr_load_pstr ; " = load i8*, i8** %"
    call    emit_str
    jmp     .ld_done
.ld_list:
    mov     rdi, cstr_load_plist ; " = load i64*, i64** %"
    call    emit_str
.ld_done:
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    pop     rax                 ; new register
    pop     rcx                 ; discard type
    pop     r13
    pop     r12
    pop     rbp
    ret

; ============================================================
; CODEGEN_BINARY
; Generates code for binary expression: a + b, a == b etc
;
; LLVM IR output:
;   %left  = ... (left expression)
;   %right = ... (right expression)
;   %result = add i64 %left, %right
; ============================================================
codegen_binary:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi            ; r12 = BINARY node

    ; ── String concatenation? (BINOP_ADD on string operands) ─
    mov     rax, [r12 + NODE_EXTRA]
    cmp     rax, BINOP_ADD
    jne     .numeric
    mov     rdi, r12
    call    expr_is_string
    test    rax, rax
    jz      .numeric

    ; ---- evaluate operands, auto-convert ints to text ----
    mov     rdi, [r12 + NODE_LEFT]
    call    codegen_node
    mov     rsi, [r12 + NODE_LEFT]
    call    to_text_if_int
    push    rax
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    mov     rsi, [r12 + NODE_RIGHT]
    call    to_text_if_int
    mov     [cc_r_reg], rax
    pop     rax
    mov     [cc_l_reg], rax

    ; %len1 = strlen(left)
    call    new_reg
    mov     [cc_len1], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [cc_len1]
    call    emit_num
    mov     rdi, cstr_strlen_pre
    call    emit_str
    mov     rdi, [cc_l_reg]
    call    emit_num
    mov     rdi, cstr_close_nl
    call    emit_str

    ; %len2 = strlen(right)
    call    new_reg
    mov     [cc_len2], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [cc_len2]
    call    emit_num
    mov     rdi, cstr_strlen_pre
    call    emit_str
    mov     rdi, [cc_r_reg]
    call    emit_num
    mov     rdi, cstr_close_nl
    call    emit_str

    ; %sum = add i64 %len1, %len2
    call    new_reg
    mov     [cc_sum], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [cc_sum]
    call    emit_num
    mov     rdi, cstr_add_i64_pct
    call    emit_str
    mov     rdi, [cc_len1]
    call    emit_num
    mov     rdi, cstr_comma_pct
    call    emit_str
    mov     rdi, [cc_len2]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    ; %tot = add i64 %sum, 1
    call    new_reg
    mov     [cc_tot], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [cc_tot]
    call    emit_num
    mov     rdi, cstr_add_i64_pct
    call    emit_str
    mov     rdi, [cc_sum]
    call    emit_num
    mov     rdi, cstr_comma_1_nl
    call    emit_str

    ; %buf = malloc(%tot)
    call    new_reg
    mov     [cc_buf], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [cc_buf]
    call    emit_num
    mov     rdi, cstr_malloc_pre
    call    emit_str
    mov     rdi, [cc_tot]
    call    emit_num
    mov     rdi, cstr_close_nl
    call    emit_str

    ; %_ = strcpy(%buf, %left)
    call    new_reg
    mov     [cc_len1], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [cc_len1]
    call    emit_num
    mov     rdi, cstr_strcpy_pre
    call    emit_str
    mov     rdi, [cc_buf]
    call    emit_num
    mov     rdi, cstr_comma_i8p
    call    emit_str
    mov     rdi, [cc_l_reg]
    call    emit_num
    mov     rdi, cstr_close_nl
    call    emit_str

    ; %_ = strcat(%buf, %right)
    call    new_reg
    mov     [cc_len1], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [cc_len1]
    call    emit_num
    mov     rdi, cstr_strcat_pre
    call    emit_str
    mov     rdi, [cc_buf]
    call    emit_num
    mov     rdi, cstr_comma_i8p
    call    emit_str
    mov     rdi, [cc_r_reg]
    call    emit_num
    mov     rdi, cstr_close_nl
    call    emit_str

    ; result = %buf
    mov     rax, [cc_buf]
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

.numeric:
    ; ── Reject text in arithmetic/comparison ─────────────
    mov     rdi, [r12 + NODE_LEFT]
    call    expr_is_string
    test    rax, rax
    jnz     .text_op_err
    mov     rdi, [r12 + NODE_RIGHT]
    call    expr_is_string
    test    rax, rax
    jz      .types_ok
.text_op_err:
    mov     qword [cg_error_flag], 1
    mov     rdi, err_op_on_text
    call    cg_print_str
    xor     rax, rax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
.types_ok:
    ; Generate left side
    mov     rdi, [r12 + NODE_LEFT]
    call    codegen_node
    mov     r13, rax            ; r13 = left register

    ; Generate right side
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    mov     r14, rax            ; r14 = right register

    ; Get operator
    mov     rbx, [r12 + NODE_EXTRA]

    ; Allocate result register
    call    new_reg
    push    rax                 ; save result register

    ; Emit the operation
    mov     rdi, cstr_32
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num

    ; Choose LLVM instruction based on operator
    cmp     rbx, BINOP_ADD
    je      .op_add
    cmp     rbx, BINOP_SUB
    je      .op_sub
    cmp     rbx, BINOP_MUL
    je      .op_mul
    cmp     rbx, BINOP_DIV
    je      .op_div
    cmp     rbx, BINOP_MOD
    je      .op_mod
    cmp     rbx, BINOP_EQ
    je      .op_eq
    cmp     rbx, BINOP_NEQ
    je      .op_neq
    cmp     rbx, BINOP_LT
    je      .op_lt
    cmp     rbx, BINOP_GT
    je      .op_gt
    cmp     rbx, BINOP_LTE
    je      .op_lte
    cmp     rbx, BINOP_GTE
    je      .op_gte
    jmp     .op_add             ; default to add

.op_add:
    mov     rdi, cstr_33
    call    emit_str
    jmp     .emit_operands

.op_sub:
    mov     rdi, cstr_34
    call    emit_str
    jmp     .emit_operands

.op_mul:
    mov     rdi, cstr_35
    call    emit_str
    jmp     .emit_operands

.op_div:
    mov     rdi, cstr_36
    call    emit_str
    jmp     .emit_operands

.op_mod:
    mov     rdi, cstr_37
    call    emit_str
    jmp     .emit_operands

.op_eq:
    mov     rdi, cstr_38
    call    emit_str
    jmp     .emit_operands

.op_neq:
    mov     rdi, cstr_39
    call    emit_str
    jmp     .emit_operands

.op_lt:
    mov     rdi, cstr_40
    call    emit_str
    jmp     .emit_operands

.op_gt:
    mov     rdi, cstr_41
    call    emit_str
    jmp     .emit_operands

.op_lte:
    mov     rdi, cstr_42
    call    emit_str
    jmp     .emit_operands

.op_gte:
    mov     rdi, cstr_43
    call    emit_str

.emit_operands:
    ; Emit: %left_reg, %right_reg
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_44
    call    emit_str
    mov     rdi, r14
    call    emit_num
    mov     rdi, cstr_45
    call    emit_str

    pop     rax                 ; result register

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; CODEGEN_UNARY
; Generates code for unary expression: -x, not x
; ============================================================
codegen_unary:
    push    rbp
    mov     rbp, rsp
    push    r12

    mov     r12, rdi

    ; Generate operand
    mov     rdi, [r12 + NODE_LEFT]
    call    codegen_node
    push    rax                 ; operand register

    call    new_reg
    push    rax                 ; result register

    mov     rdi, cstr_46
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num

    mov     rax, [r12 + NODE_EXTRA]
    cmp     rax, 20             ; TOKEN_NOT
    je      .do_not

    ; Negate: sub 0, operand
    mov     rdi, cstr_47
    call    emit_str
    mov     rdi, [rsp + 8]
    call    emit_num
    jmp     .done_op

.do_not:
    mov     rdi, cstr_48
    call    emit_str
    mov     rdi, [rsp + 8]
    call    emit_num
    mov     rdi, cstr_49
    call    emit_str

.done_op:
    mov     rdi, cstr_50
    call    emit_str

    pop     rax
    add     rsp, 8              ; pop operand reg

    pop     r12
    pop     rbp
    ret

; ============================================================
; CODEGEN_IF
; Generates code for if/else statement
;
; LLVM IR output:
;   %cond = ... (condition)
;   br i1 %cond, label %if.then.N, label %if.else.N
;
;   if.then.N:
;     ... (then block)
;     br label %if.end.N
;
;   if.else.N:
;     ... (else block)
;     br label %if.end.N
;
;   if.end.N:
; ============================================================
codegen_if:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13

    mov     r12, rdi            ; r12 = IF node

    ; Get unique label number
    mov     r13, [label_counter]
    inc     qword [label_counter]

    ; Generate condition (convert to i1 if needed)
    mov     rdi, [r12 + NODE_LEFT]
    call    codegen_node
    mov     rsi, [r12 + NODE_LEFT]
    call    cond_to_i1
    push    rax                 ; save condition register

    ; Emit conditional branch
    mov     rdi, cstr_51
    call    emit_str
    pop     rdi
    call    emit_num
    mov     rdi, cstr_52
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_53
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_54
    call    emit_str

    ; Emit then block label
    mov     rdi, cstr_55
    call    emit_str
    mov     rdi, cstr_56
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_57
    call    emit_str

    ; Generate then block
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node

    ; Branch to end
    mov     rdi, cstr_58
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_59
    call    emit_str

    ; Emit else block label
    mov     rdi, cstr_60
    call    emit_str
    mov     rdi, cstr_61
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_62
    call    emit_str

    ; Generate else block (if exists)
    mov     rdi, [r12 + NODE_EXTRA]
    test    rdi, rdi
    jz      .no_else
    call    codegen_node

.no_else:
    ; Branch to end
    mov     rdi, cstr_63
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_64
    call    emit_str

    ; Emit end label
    mov     rdi, cstr_65
    call    emit_str
    mov     rdi, cstr_66
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_67
    call    emit_str

    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbp
    ret

; ============================================================
; CODEGEN_WHILE
; Generates code for while loop
;
; LLVM IR output:
;   br label %while.cond.N
;
;   while.cond.N:
;     %cond = ... (condition)
;     br i1 %cond, label %while.body.N, label %while.end.N
;
;   while.body.N:
;     ... (body)
;     br label %while.cond.N
;
;   while.end.N:
; ============================================================
codegen_while:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13

    mov     r12, rdi

    mov     r13, [label_counter]
    inc     qword [label_counter]

    ; Jump to condition check
    mov     rdi, cstr_68
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_69
    call    emit_str

    ; Condition label
    mov     rdi, cstr_70
    call    emit_str
    mov     rdi, cstr_71
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_72
    call    emit_str

    ; Generate condition (convert to i1 if needed)
    mov     rdi, [r12 + NODE_LEFT]
    call    codegen_node
    mov     rsi, [r12 + NODE_LEFT]
    call    cond_to_i1
    push    rax

    ; Conditional branch
    mov     rdi, cstr_73
    call    emit_str
    pop     rdi
    call    emit_num
    mov     rdi, cstr_74
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_75
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_76
    call    emit_str

    ; Body label
    mov     rdi, cstr_77
    call    emit_str
    mov     rdi, cstr_78
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_79
    call    emit_str

    ; ── enter loop scope (save outer, set current) ───────
    mov     rax, [cur_loop_kind]
    push    rax
    mov     rax, [cur_loop_end_lbl]
    push    rax
    mov     rax, [cur_loop_cond_lbl]
    push    rax
    mov     qword [cur_loop_kind], 1
    mov     [cur_loop_end_lbl], r13
    mov     [cur_loop_cond_lbl], r13

    ; Generate body
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    ; ── exit loop scope (restore outer) ──────────────────
    pop     rax
    mov     [cur_loop_cond_lbl], rax
    pop     rax
    mov     [cur_loop_end_lbl], rax
    pop     rax
    mov     [cur_loop_kind], rax


    ; Loop back to condition
    mov     rdi, cstr_80
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_81
    call    emit_str

    ; End label
    mov     rdi, cstr_82
    call    emit_str
    mov     rdi, cstr_83
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_84
    call    emit_str

    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbp
    ret

; ============================================================
; CODEGEN_FOR
; Generates: for i in start..end { body }
;
; Clean implementation using dedicated BSS storage
; ============================================================
codegen_for:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi            ; r12 = FOR node

    ; Get label number
    mov     r13, [label_counter]
    inc     qword [label_counter]

    ; Get range node
    mov     r14, [r12 + NODE_EXTRA]
    test    r14, r14
    jz      .done

    ; Save start and end node pointers BEFORE any codegen
    mov     rbx, [r14 + NODE_LEFT]    ; rbx = start node
    mov     r14, [r14 + NODE_RIGHT]   ; r14 = end node

    ; Generate start value
    mov     rdi, rbx
    call    codegen_node
    mov     [for_end_reg], rax        ; temporarily store start reg

    ; Generate end value
    mov     rdi, r14
    call    codegen_node
    ; rax = end register — save permanently
    push    rax                        ; [rsp] = end_reg

    ; Allocate counter on stack: %N = alloca i64
    call    new_reg
    mov     rbx, rax                   ; rbx = counter alloca reg
    mov     [for_ctr_alloca], rbx     ; save permanently

    ; emit: %counter = alloca i64
    mov     rdi, cstr_alloca_pfx      ; "  %"
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_alloca_sfx
    call    emit_str

    ; Store start into counter: store i64 %start, i64* %counter
    mov     rdi, cstr_store_pfx       ; "  store i64 %"
    call    emit_str
    mov     rdi, [for_end_reg]        ; start register
    call    emit_num
    mov     rdi, cstr_store_mid       ; ", i64* %"
    call    emit_str
    mov     rdi, rbx                   ; counter alloca
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    ; Register loop variable in var table
    mov     rdi, [r12 + NODE_LEFT]    ; IDENT node
    mov     rsi, rbx                   ; alloca register
    xor     rdx, rdx                   ; type = int
    call    var_table_add

    ; Save end register permanently
    pop     rax                        ; restore end_reg
    mov     [for_end_reg], rax        ; save end register

    ; Jump to condition
    mov     rdi, cstr_br_label        ; "  br label %"
    call    emit_str
    mov     rdi, cstr_for_cond        ; "for.cond."
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    ; ── CONDITION LABEL ──────────────────────────────────
    mov     rdi, cstr_nl
    call    emit_str
    mov     rdi, cstr_for_cond        ; "for.cond."
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_colon_nl
    call    emit_str

    ; Load counter: %cur = load i64, i64* %counter
    call    new_reg
    mov     [for_cur_reg], rax        ; save cur_reg in BSS

    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [for_cur_reg]
    call    emit_num
    mov     rdi, cstr_load_i64
    call    emit_str
    mov     rdi, [for_ctr_alloca]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    ; Compare: %cmp = icmp slt i64 %cur, %end
    call    new_reg
    mov     [for_cmp_reg], rax        ; save cmp_reg in BSS

    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [for_cmp_reg]
    call    emit_num
    mov     rdi, cstr_icmp_slt
    call    emit_str
    mov     rdi, [for_cur_reg]        ; cur_reg
    call    emit_num
    mov     rdi, cstr_comma_pct
    call    emit_str
    mov     rdi, [for_end_reg]        ; end register
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    ; Branch: br i1 %cmp, label %for.body.N, label %for.end.N
    ; Use BSS vars — no stack confusion

    mov     rdi, cstr_br_i1
    call    emit_str
    mov     rdi, [for_cmp_reg]        ; cmp register from BSS
    call    emit_num
    mov     rdi, cstr_lbl_comma       ; ", label %"
    call    emit_str
    mov     rdi, cstr_for_body_lbl    ; "for.body."
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_lbl_comma       ; ", label %"
    call    emit_str
    mov     rdi, cstr_for_end_lbl     ; "for.end."
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    ; ── BODY LABEL ───────────────────────────────────────
    mov     rdi, cstr_nl
    call    emit_str
    mov     rdi, cstr_for_body_lbl
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_colon_nl
    call    emit_str

    ; ── enter loop scope (save outer, set current) ───────
    mov     rax, [cur_loop_kind]
    push    rax
    mov     rax, [cur_loop_end_lbl]
    push    rax
    mov     rax, [cur_loop_cond_lbl]
    push    rax
    mov     qword [cur_loop_kind], 2
    mov     [cur_loop_end_lbl], r13
    mov     [cur_loop_cond_lbl], r13

    ; Generate body
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    ; ── exit loop scope (restore outer) ──────────────────
    pop     rax
    mov     [cur_loop_cond_lbl], rax
    pop     rax
    mov     [cur_loop_end_lbl], rax
    pop     rax
    mov     [cur_loop_kind], rax


    ; ── INCREMENT ────────────────────────────────────────
    ; Load counter: %ld = load i64, i64* %counter
    call    new_reg
    mov     [for_loaded_reg], rax

    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [for_loaded_reg]
    call    emit_num
    mov     rdi, cstr_load_i64
    call    emit_str
    mov     rdi, [for_ctr_alloca]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    ; Add 1: %inc = add i64 %ld, 1
    call    new_reg
    mov     [for_inc_reg], rax

    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [for_inc_reg]
    call    emit_num
    mov     rdi, cstr_add_i64_pct
    call    emit_str
    mov     rdi, [for_loaded_reg]
    call    emit_num
    mov     rdi, cstr_comma_1_nl
    call    emit_str

    ; Store: store i64 %inc, i64* %counter
    mov     rdi, cstr_store_pfx
    call    emit_str
    mov     rdi, [for_inc_reg]
    call    emit_num
    mov     rdi, cstr_store_mid
    call    emit_str
    mov     rdi, [for_ctr_alloca]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

; Loop back: br label %for.cond.N
    mov     rdi, cstr_br_label
    call    emit_str
    mov     rdi, cstr_for_cond
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    ; ── END LABEL ────────────────────────────────────────
    mov     rdi, cstr_nl
    call    emit_str
    mov     rdi, cstr_for_end_lbl
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_colon_nl
    call    emit_str

.done:
    xor     rax, rax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; CODEGEN_LOOP
; Generates code for infinite loop
; ============================================================
codegen_loop:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13

    mov     r12, rdi

    mov     r13, [label_counter]
    inc     qword [label_counter]

    ; Jump to loop
    mov     rdi, cstr_125
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_126
    call    emit_str

    ; Loop label
    mov     rdi, cstr_127
    call    emit_str
    mov     rdi, cstr_128
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_129
    call    emit_str

    ; ── enter loop scope ─────────────────────────────────
    mov     rax, [cur_loop_kind]
    push    rax
    mov     rax, [cur_loop_end_lbl]
    push    rax
    mov     rax, [cur_loop_cond_lbl]
    push    rax
    mov     qword [cur_loop_kind], 3
    mov     [cur_loop_end_lbl], r13
    mov     [cur_loop_cond_lbl], r13

    ; Generate body
    mov     rdi, [r12 + NODE_LEFT]
    call    codegen_node
    ; ── exit loop scope ──────────────────────────────────
    pop     rax
    mov     [cur_loop_cond_lbl], rax
    pop     rax
    mov     [cur_loop_end_lbl], rax
    pop     rax
    mov     [cur_loop_kind], rax


    ; Loop back unconditionally
    mov     rdi, cstr_130
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_131
    call    emit_str

    ; End label (reached by break)
    mov     rdi, cstr_132
    call    emit_str
    mov     rdi, cstr_133
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_134
    call    emit_str

    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbp
    ret

; ============================================================
; CODEGEN_FN_DEF
; Generates code for function definition
;
; LLVM IR output:
;   define i64 @name() {
;   entry:
;     ... body ...
;     ret i64 0
;   }
; ============================================================
codegen_fn_def:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi            ; r12 = FN_DEF node

    ; ── Determine return type & register function ────────
    mov     rdi, [r12 + NODE_TSTART]    ; return-type node (0 if none)
    call    type_node_is_text
    mov     [cur_fn_rettype], rax
    ; (signature already registered by pre-pass)

    ; ── Switch output to fn_buf ──────────────────────────
    lea     rax, [fn_buf]
    mov     [emit_buf_base], rax
    lea     rax, [fn_pos]
    mov     [emit_pos_addr], rax

    ; ── Save + reset register counter (per-function SSA) ─
    mov     rax, [reg_counter]
    mov     [saved_reg_counter], rax
    mov     qword [reg_counter], 0

    ; ── Save var table scope ─────────────────────────────
    mov     rax, [var_count]
    mov     [saved_var_count], rax
    mov     [var_scope_base], rax   ; hide outer variables

    ; ── define i64/i8* @name( ────────────────────────────
    cmp     qword [cur_fn_rettype], 1
    je      .def_str
    mov     rdi, cstr_fn_def1
    jmp     .def_emit
.def_str:
    mov     rdi, cstr_fn_def_str
.def_emit:
    call    emit_str
    mov     rbx, [r12 + NODE_LEFT]  ; IDENT node (fn name)
    mov     rdi, [rbx + NODE_TSTART]
    mov     rsi, [rbx + NODE_TLEN]
    call    emit_source_text
    mov     rdi, cstr_lparen_only
    call    emit_str

    ; ── Parameter list: i64 %a, i64 %b ───────────────────
    mov     rbx, [r12 + NODE_EXTRA]
    test    rbx, rbx
    jz      .params_done
.param_loop:
    mov     rdi, rbx
    call    param_is_list
    test    rax, rax
    jz      .p_chk_text
    mov     rdi, cstr_fn_par_list
    call    emit_str
    jmp     .p_name
.p_chk_text:
    mov     rdi, rbx
    call    param_is_text
    test    rax, rax
    jz      .p_int
    mov     rdi, cstr_fn_par_str
    call    emit_str
    jmp     .p_name
.p_int:
    mov     rdi, cstr_fn_par_i64
    call    emit_str
.p_name:
    mov     rax, [rbx + NODE_LEFT]  ; param IDENT
    mov     rdi, [rax + NODE_TSTART]
    mov     rsi, [rax + NODE_TLEN]
    call    emit_source_text
    mov     rbx, [rbx + NODE_NEXT]
    test    rbx, rbx
    jz      .params_done
    mov     rdi, cstr_fn_par_sep
    call    emit_str
    jmp     .param_loop
.params_done:
    mov     rdi, cstr_fn_body_open  ; ") {\nentry:\n"
    call    emit_str

    ; ── Param allocas: %N = alloca; store %name → %N ─────
    mov     rbx, [r12 + NODE_EXTRA]
.alloca_loop:
    test    rbx, rbx
    jz      .body
    mov     rdi, rbx
    call    param_is_list
    mov     [fnp_is_list], rax
    mov     rdi, rbx
    call    param_is_text
    mov     [fnp_is_text], rax

    call    new_reg
    mov     r13, rax

    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, r13
    call    emit_num
    cmp     qword [fnp_is_list], 1
    je      .pa_list
    cmp     qword [fnp_is_text], 1
    je      .pa_str
    mov     rdi, cstr_alloca_sfx
    call    emit_str
    mov     rdi, cstr_store_pfx
    call    emit_str
    jmp     .pa_name
.pa_str:
    mov     rdi, cstr_alloca_pstr
    call    emit_str
    mov     rdi, cstr_store_pstr
    call    emit_str
    jmp     .pa_name
.pa_list:
    mov     rdi, cstr_alloca_plist
    call    emit_str
    mov     rdi, cstr_store_plist
    call    emit_str
.pa_name:
    mov     rax, [rbx + NODE_LEFT]
    mov     rdi, [rax + NODE_TSTART]
    mov     rsi, [rax + NODE_TLEN]
    call    emit_source_text
    cmp     qword [fnp_is_list], 1
    je      .pa_mid_list
    cmp     qword [fnp_is_text], 1
    je      .pa_mid_str
    mov     rdi, cstr_store_mid
    call    emit_str
    jmp     .pa_mid_done
.pa_mid_str:
    mov     rdi, cstr_storemid_pstr
    call    emit_str
    jmp     .pa_mid_done
.pa_mid_list:
    mov     rdi, cstr_storemid_plist
    call    emit_str
.pa_mid_done:
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    ; register param in var table (0=int 1=text 2=list)
    mov     rcx, [fnp_is_text]
    cmp     qword [fnp_is_list], 1
    jne     .pa_type_ok
    mov     rcx, 2
.pa_type_ok:
    mov     rdi, [rbx + NODE_LEFT]
    mov     rsi, r13
    mov     rdx, rcx
    call    var_table_add

    mov     rbx, [rbx + NODE_NEXT]
    jmp     .alloca_loop

.body:
    ; ── Function body ────────────────────────────────────
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node

    ; ── Close function (typed default return) ────────────
    cmp     qword [cur_fn_rettype], 1
    je      .close_str
    mov     rdi, cstr_fn_close      ; ret i64 0
    jmp     .close_emit
.close_str:
    mov     rdi, cstr_fn_close_str  ; ret i8* null
.close_emit:
    call    emit_str

    ; ── Restore main buffer, counter, scope ──────────────
    lea     rax, [ir_buf]
    mov     [emit_buf_base], rax
    lea     rax, [ir_pos]
    mov     [emit_pos_addr], rax

    mov     rax, [saved_reg_counter]
    mov     [reg_counter], rax
    mov     rax, [saved_var_count]
    mov     [var_count], rax
    mov     qword [var_scope_base], 0   ; back to main scope
    mov     qword [cur_fn_rettype], 0   ; back in main (int)

    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; CODEGEN_FN_CALL
; Generates code for function call: name(args)
; ============================================================
codegen_fn_call:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi
    xor     r14, r14                    ; arg count (survives recursion)

    ; ── Builtin: len(list) ───────────────────────────────
    mov     rax, [r12 + NODE_LEFT]
    cmp     qword [rax + NODE_TLEN], 3
    jne     .not_len
    mov     rcx, [cg_src_buf]
    add     rcx, [rax + NODE_TSTART]
    cmp     byte [rcx], 'l'
    jne     .not_len
    cmp     byte [rcx+1], 'e'
    jne     .not_len
    cmp     byte [rcx+2], 'n'
    jne     .not_len
    ; evaluate the single argument (the list → i64* register)
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    mov     [arr_ptr], rax
    ; slot0 = gep ptr, 0 ; %v = load slot0
    xor     rdi, rdi
    call    emit_gep_const_idx
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_load_slot
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    pop     rax
    jmp     .fn_ret
.not_len:

    ; ── Builtin: input() → reads an integer ──────────────
    mov     rax, [r12 + NODE_LEFT]
    cmp     qword [rax + NODE_TLEN], 5
    jne     .not_input
    mov     rcx, [cg_src_buf]
    add     rcx, [rax + NODE_TSTART]
    cmp     byte [rcx], 'i'
    jne     .not_input
    cmp     byte [rcx+1], 'n'
    jne     .not_input
    cmp     byte [rcx+2], 'p'
    jne     .not_input
    cmp     byte [rcx+3], 'u'
    jne     .not_input
    cmp     byte [rcx+4], 't'
    jne     .not_input
    ; %slot = alloca i64 ; scanf("%ld", %slot) ; %v = load %slot
    call    new_reg
    mov     [arr_slot], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_2             ; " = alloca i64\n"
    call    emit_str
    call    new_reg
    push    rax                     ; scanf result reg (unused)
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_scan_pre
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_close_nl      ; ")\n"
    call    emit_str
    pop     rax
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_load_i64      ; " = load i64, i64* %"
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    pop     rax
    jmp     .fn_ret
.not_input:

    ; ── Builtin: input_text() → reads a line ─────────────
    mov     rax, [r12 + NODE_LEFT]
    cmp     qword [rax + NODE_TLEN], 10
    jne     .not_input_text
    mov     rcx, [cg_src_buf]
    add     rcx, [rax + NODE_TSTART]
    cmp     byte [rcx], 'i'
    jne     .not_input_text
    cmp     byte [rcx+5], '_'
    jne     .not_input_text
    cmp     byte [rcx+6], 't'
    jne     .not_input_text
    ; %buf = malloc(256)
    call    new_reg
    mov     [arr_ptr], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [arr_ptr]
    call    emit_num
    mov     rdi, cstr_inbuf_malloc  ; " = call i8* @malloc(i64 256)\n"
    call    emit_str
    ; %in = load i8*, i8** @stdin
    call    new_reg
    mov     [arr_raw], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [arr_raw]
    call    emit_num
    mov     rdi, cstr_stdin_load    ; " = load i8*, i8** @stdin\n"
    call    emit_str
    ; %r = fgets(%buf, 256, %in)
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_fgets_pre     ; " = call i8* @fgets(i8* %"
    call    emit_str
    mov     rdi, [arr_ptr]
    call    emit_num
    mov     rdi, cstr_fgets_mid     ; ", i32 256, i8* %"
    call    emit_str
    mov     rdi, [arr_raw]
    call    emit_num
    mov     rdi, cstr_close_nl      ; ")\n"
    call    emit_str
    pop     rax
    ; strip trailing newline: %p = strchr(%buf, 10)
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_strip_nl_gep  ; " = call i8* @strchr(i8* %"
    call    emit_str
    mov     rdi, [arr_ptr]
    call    emit_num
    mov     rdi, cstr_comma_10      ; ", i32 10)\n"
    call    emit_str
    pop     r13                     ; r13 = newline ptr register
    ; store i8 0, i8* %p  (null-terminate at the newline)
    mov     rdi, cstr_store_nlterm  ; "  store i8 0, i8* %"
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; result = the buffer pointer (text)
    mov     rax, [arr_ptr]
    jmp     .fn_ret
.not_input_text:

    ; ── Builtin: write_file(name, content) → 0 ───────────
    mov     rdi, r12
    mov     rsi, bi_write
    mov     rdx, 10
    call    name_matches
    test    rax, rax
    jz      .not_write
    ; eval name (text)
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    mov     [fio_a], rax                ; name ptr
    ; eval content (text) = second arg
    mov     rax, [r12 + NODE_RIGHT]
    mov     rdi, [rax + NODE_NEXT]
    call    codegen_node
    mov     [fio_b], rax                ; content ptr
    ; %f = fopen(name, "w")
    call    new_reg
    mov     [fio_c], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [fio_c]
    call    emit_num
    mov     rdi, cstr_fopen_w
    call    emit_str
    mov     rdi, [fio_a]
    call    emit_num
    mov     rdi, cstr_fopen_wm
    call    emit_str
    ; fputs(content, f)
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_fputs
    call    emit_str
    mov     rdi, [fio_b]
    call    emit_num
    mov     rdi, cstr_fputs_f
    call    emit_str
    mov     rdi, [fio_c]
    call    emit_num
    mov     rdi, cstr_close_nl
    call    emit_str
    pop     rax
    ; fclose(f)
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_fclose
    call    emit_str
    mov     rdi, [fio_c]
    call    emit_num
    mov     rdi, cstr_close_nl
    call    emit_str
    pop     rax
    ; result = 0
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_16                ; " = add i64 0, "
    call    emit_str
    xor     rdi, rdi
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    pop     rax
    jmp     .fn_ret
.not_write:

    ; ── Builtin: read_file(name) → text ──────────────────
    mov     rdi, r12
    mov     rsi, bi_read
    mov     rdx, 9
    call    name_matches
    test    rax, rax
    jz      .not_read
    ; eval name
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    mov     [fio_a], rax                ; name
    ; %f = fopen(name, "r")
    call    new_reg
    mov     [fio_c], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [fio_c]
    call    emit_num
    mov     rdi, cstr_fopen_w           ; " = call i8* @fopen(i8* %"
    call    emit_str
    mov     rdi, [fio_a]
    call    emit_num
    mov     rdi, cstr_fopen_rm          ; ", @.mode.r)\n"
    call    emit_str
    ; %buf = malloc(65536)
    call    new_reg
    mov     [fio_b], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [fio_b]
    call    emit_num
    mov     rdi, cstr_malloc64k
    call    emit_str
    ; %nread = fread(buf, 1, 65535, f)
    call    new_reg
    mov     [arr_n], rax                ; nread reg
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [arr_n]
    call    emit_num
    mov     rdi, cstr_fread
    call    emit_str
    mov     rdi, [fio_b]
    call    emit_num
    mov     rdi, cstr_fread_a
    call    emit_str
    mov     rdi, [fio_c]
    call    emit_num
    mov     rdi, cstr_close_nl
    call    emit_str
    ; null-terminate: %p = getelementptr i8, i8* %buf, i64 %nread ; store i8 0
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_gep_i8            ; " = getelementptr i8, i8* %"
    call    emit_str
    mov     rdi, [fio_b]
    call    emit_num
    mov     rdi, cstr_gep_i8_r          ; ", i64 %"
    call    emit_str
    mov     rdi, [arr_n]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    mov     rdi, cstr_store_z8          ; "  store i8 0, i8* %"
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    pop     rax
    ; fclose(f)
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_fclose
    call    emit_str
    mov     rdi, [fio_c]
    call    emit_num
    mov     rdi, cstr_close_nl
    call    emit_str
    pop     rax
    ; result = buf (text pointer)
    mov     rax, [fio_b]
    jmp     .fn_ret
.not_read:

    ; ── Builtin: abs(x) ──────────────────────────────────
    mov     rdi, r12
    mov     rsi, bi_abs
    mov     rdx, 3
    call    name_matches
    test    rax, rax
    jz      .not_abs
    ; eval arg
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    mov     r13, rax                ; x
    ; %neg = sub i64 0, %x
    call    new_reg
    mov     rbx, rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_sub0          ; " = sub i64 0, %"
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; %cmp = icmp slt i64 %x, 0  → but we need select; compare x<0
    call    new_reg
    push    rax                     ; cmp reg
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_icmp_slt_r    ; " = icmp slt i64 %"
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_comma0_nl     ; ", 0\n"
    call    emit_str
    ; %r = select i1 %cmp, i64 %neg, i64 %x
    call    new_reg
    push    rax                     ; result reg
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_select_pre    ; " = select i1 %"
    call    emit_str
    mov     rdi, [rsp+8]            ; cmp
    call    emit_num
    mov     rdi, cstr_sel_i64       ; ", i64 %"
    call    emit_str
    mov     rdi, rbx                ; neg
    call    emit_num
    mov     rdi, cstr_sel_i64
    call    emit_str
    mov     rdi, r13                ; x
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    pop     rax                     ; result
    add     rsp, 8                  ; drop cmp
    jmp     .fn_ret
.not_abs:

    ; ── Builtin: min(a,b) / max(a,b) ─────────────────────
    mov     rdi, r12
    mov     rsi, bi_min
    mov     rdx, 3
    call    name_matches
    mov     [arr_n], rax            ; 1 if min
    mov     rdi, r12
    mov     rsi, bi_max
    mov     rdx, 3
    call    name_matches
    mov     rcx, [arr_n]
    or      rcx, rax
    test    rcx, rcx
    jz      .not_minmax
    mov     [mm_is_max], rax        ; 1 if max (clobber-safe)
    ; eval a, b
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    mov     r13, rax                ; a
    mov     rax, [r12 + NODE_RIGHT]
    mov     rdi, [rax + NODE_NEXT]
    call    codegen_node
    mov     rbx, rax                ; b
    ; %cmp = icmp (slt for min / sgt for max) i64 %a, %b
    call    new_reg
    push    rax                     ; cmp reg
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    cmp     qword [mm_is_max], 1
    je      .mm_max
    mov     rdi, cstr_icmp_slt_r
    jmp     .mm_emit
.mm_max:
    mov     rdi, cstr_icmp_sgt_r
.mm_emit:
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_comma_pct     ; ", %"
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; %r = select i1 %cmp, i64 %a, i64 %b
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_select_pre
    call    emit_str
    mov     rdi, [rsp+8]
    call    emit_num
    mov     rdi, cstr_sel_i64
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_sel_i64
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    pop     rax
    add     rsp, 8
    jmp     .fn_ret
.not_minmax:

    ; ── Builtin: sum(list) ───────────────────────────────
    mov     rdi, r12
    mov     rsi, bi_sum
    mov     rdx, 3
    call    name_matches
    test    rax, rax
    jz      .not_sum
    ; eval list → i64* in arr_ptr
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    mov     [arr_ptr], rax
    ; %lenslot = gep ptr,0 ; %len = load
    xor     rdi, rdi
    call    emit_gep_const_idx
    call    new_reg
    mov     [arr_n], rax            ; len reg
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [arr_n]
    call    emit_num
    mov     rdi, cstr_load_slot
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; %acc = alloca i64 ; store 0
    call    new_reg
    mov     [cc_sum], rax           ; acc alloca
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [cc_sum]
    call    emit_num
    mov     rdi, cstr_2             ; " = alloca i64\n"
    call    emit_str
    mov     rdi, cstr_store_arr     ; "  store i64 "
    call    emit_str
    xor     rdi, rdi
    call    emit_num
    mov     rdi, cstr_to_slot       ; ", i64* %"
    call    emit_str
    mov     rdi, [cc_sum]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; %ix = alloca i64 ; store 0
    call    new_reg
    mov     [cc_tot], rax           ; index alloca
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [cc_tot]
    call    emit_num
    mov     rdi, cstr_2
    call    emit_str
    mov     rdi, cstr_store_arr
    call    emit_str
    xor     rdi, rdi
    call    emit_num
    mov     rdi, cstr_to_slot
    call    emit_str
    mov     rdi, [cc_tot]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; label numbers
    mov     r13, [label_counter]
    inc     qword [label_counter]
    ; br cond
    mov     rdi, cstr_br_label
    call    emit_str
    mov     rdi, cstr_for_cond
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; cond label
    mov     rdi, cstr_nl
    call    emit_str
    mov     rdi, cstr_for_cond
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_colon_nl
    call    emit_str
    ; %ci = load ix
    call    new_reg
    mov     [cc_l_reg], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [cc_l_reg]
    call    emit_num
    mov     rdi, cstr_load_i64
    call    emit_str
    mov     rdi, [cc_tot]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; %cmp = icmp slt %ci, %len
    call    new_reg
    mov     [cc_r_reg], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [cc_r_reg]
    call    emit_num
    mov     rdi, cstr_icmp_slt_r
    call    emit_str
    mov     rdi, [cc_l_reg]
    call    emit_num
    mov     rdi, cstr_comma_pct
    call    emit_str
    mov     rdi, [arr_n]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; br cmp, body, end
    mov     rdi, cstr_br_i1
    call    emit_str
    mov     rdi, [cc_r_reg]
    call    emit_num
    mov     rdi, cstr_lbl_comma
    call    emit_str
    mov     rdi, cstr_for_body_lbl
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_lbl_comma
    call    emit_str
    mov     rdi, cstr_for_end_lbl
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; body label
    mov     rdi, cstr_nl
    call    emit_str
    mov     rdi, cstr_for_body_lbl
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_colon_nl
    call    emit_str
    ; realidx = ci + 1
    call    new_reg
    mov     [cc_len1], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [cc_len1]
    call    emit_num
    mov     rdi, cstr_idx_add1
    call    emit_str
    mov     rdi, [cc_l_reg]
    call    emit_num
    mov     rdi, cstr_comma_1_nl
    call    emit_str
    ; slot = gep ptr, realidx
    call    new_reg
    mov     [arr_slot], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_arr_gep
    call    emit_str
    mov     rdi, [arr_ptr]
    call    emit_num
    mov     rdi, cstr_gep_reg
    call    emit_str
    mov     rdi, [cc_len1]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; %el = load slot
    call    new_reg
    mov     [cc_len2], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [cc_len2]
    call    emit_num
    mov     rdi, cstr_load_slot
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; %oldacc = load acc
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_load_i64
    call    emit_str
    mov     rdi, [cc_sum]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; %newacc = add oldacc, el
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_idx_add1      ; " = add i64 %"
    call    emit_str
    mov     rdi, [rsp+8]           ; oldacc
    call    emit_num
    mov     rdi, cstr_comma_pct
    call    emit_str
    mov     rdi, [cc_len2]         ; el
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; store newacc → acc
    mov     rdi, cstr_store_areg
    call    emit_str
    mov     rdi, [rsp]             ; newacc
    call    emit_num
    mov     rdi, cstr_to_slot
    call    emit_str
    mov     rdi, [cc_sum]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    add     rsp, 16                ; drop oldacc,newacc regs
    ; i++ : %ni = add ci,1 ; store
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_idx_add1
    call    emit_str
    mov     rdi, [cc_l_reg]
    call    emit_num
    mov     rdi, cstr_comma_1_nl
    call    emit_str
    mov     rdi, cstr_store_areg
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_to_slot
    call    emit_str
    mov     rdi, [cc_tot]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    pop     rax
    ; br cond
    mov     rdi, cstr_br_label
    call    emit_str
    mov     rdi, cstr_for_cond
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; end label
    mov     rdi, cstr_nl
    call    emit_str
    mov     rdi, cstr_for_end_lbl
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_colon_nl
    call    emit_str
    ; result = load acc
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_load_i64
    call    emit_str
    mov     rdi, [cc_sum]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    pop     rax
    jmp     .fn_ret
.not_sum:

    ; ── Evaluate args, keep (reg,isstr) pairs on stack ───
    mov     rbx, [r12 + NODE_RIGHT]
.arg_loop:
    test    rbx, rbx
    jz      .eval_done
    push    rbx
    mov     rdi, rbx
    call    expr_type                   ; 0/1/2/3
    mov     r13, rax                    ; save type
    mov     rdi, rbx
    call    codegen_node                ; rax = arg register
    pop     rbx
    ; compute isstr / islist from r13
    xor     rcx, rcx
    cmp     r13, 1
    sete    cl                          ; isstr = (type==1)
    xor     rdx, rdx
    cmp     r13, 2
    setge   dl                          ; islist = (type>=2)
    push    rax                         ; reg
    push    rcx                         ; isstr
    push    rdx                         ; islist
    inc     r14
    mov     rbx, [rbx + NODE_NEXT]
    jmp     .arg_loop
.eval_done:

    ; ── Unload stack into arrays (reverse order) ─────────
    mov     rcx, r14
.unload:
    test    rcx, rcx
    jz      .unload_done
    dec     rcx
    pop     rax                         ; islist
    mov     [fn_arg_islist + rcx*8], rax
    pop     rax                         ; isstr
    mov     [fn_arg_isstr + rcx*8], rax
    pop     rax                         ; reg
    mov     [fn_arg_regs + rcx*8], rax
    jmp     .unload
.unload_done:

    ; ── Type check the call against the signature ────────
    mov     rdi, [r12 + NODE_LEFT]
    call    fn_table_lookup_entry
    mov     [chk_fn_entry], rax
    cmp     rax, -1
    jne     .fn_known
    ; (len handled earlier; other unknowns are errors)
    ; unknown function
    mov     qword [cg_error_flag], 1
    mov     rdi, err_unknown_fn
    call    cg_print_str
    mov     rax, [r12 + NODE_LEFT]
    mov     rdi, [rax + NODE_TSTART]
    mov     rsi, [rax + NODE_TLEN]
    call    cg_print_src
    jmp     .checks_done
.fn_known:
    ; argument count
    mov     rcx, [rax + 24]
    cmp     rcx, r14
    je      .count_ok
    mov     qword [cg_error_flag], 1
    mov     rdi, err_arg_count
    call    cg_print_str
    mov     rax, [r12 + NODE_LEFT]
    mov     rdi, [rax + NODE_TSTART]
    mov     rsi, [rax + NODE_TLEN]
    call    cg_print_src
    jmp     .checks_done
.count_ok:
    ; argument types vs mask
    xor     rbx, rbx
.chk_loop:
    cmp     rbx, r14
    jge     .checks_done
    mov     rax, [chk_fn_entry]
    mov     rcx, [rax + 32]             ; type mask
    xor     rdx, rdx
    bt      rcx, rbx
    setc    dl                          ; expected: 1 if text
    cmp     rdx, [fn_arg_isstr + rbx*8]
    je      .chk_next
    mov     qword [cg_error_flag], 1
    mov     rdi, err_arg_type
    call    cg_print_str
    mov     rax, [r12 + NODE_LEFT]
    mov     rdi, [rax + NODE_TSTART]
    mov     rsi, [rax + NODE_TLEN]
    call    cg_print_src
    jmp     .checks_done
.chk_next:
    inc     rbx
    jmp     .chk_loop
.checks_done:

    ; ── %N = call i64 @name( ─────────────────────────────
    call    new_reg
    mov     r13, rax

    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, [r12 + NODE_LEFT]      ; fn name → return type?
    call    fn_table_lookup
    cmp     rax, 1
    je      .call_str
    mov     rdi, cstr_call_pre          ; " = call i64 @"
    jmp     .call_emit
.call_str:
    mov     rdi, cstr_call_pre_str      ; " = call i8* @"
.call_emit:
    call    emit_str

    mov     rax, [r12 + NODE_LEFT]
    mov     rdi, [rax + NODE_TSTART]
    mov     rsi, [rax + NODE_TLEN]
    call    emit_source_text

    mov     rdi, cstr_lparen_only
    call    emit_str

    ; ── Emit typed args ──────────────────────────────────
    xor     rbx, rbx
.emit_arg_loop:
    cmp     rbx, r14
    jge     .emit_args_done
    test    rbx, rbx
    jz      .no_sep
    mov     rdi, cstr_fn_par_sep        ; ", "
    call    emit_str
.no_sep:
    cmp     qword [fn_arg_islist + rbx*8], 1
    je      .a_list
    cmp     qword [fn_arg_isstr + rbx*8], 1
    je      .a_str
    mov     rdi, cstr_fn_par_i64
    jmp     .a_emit
.a_str:
    mov     rdi, cstr_fn_par_str
    jmp     .a_emit
.a_list:
    mov     rdi, cstr_fn_par_list
.a_emit:
    call    emit_str
    mov     rdi, [fn_arg_regs + rbx*8]
    call    emit_num
    inc     rbx
    jmp     .emit_arg_loop
.emit_args_done:
    mov     rdi, cstr_call_close        ; ")\n"
    call    emit_str

    mov     rax, r13

.fn_ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; CODEGEN_RETURN
; Generates code for return statement
; ============================================================
codegen_return:
    push    rbp
    mov     rbp, rsp
    push    r12

    mov     r12, rdi

    mov     rdi, [r12 + NODE_LEFT]
    test    rdi, rdi
    jz      .no_value

    call    codegen_node
    push    rax
    cmp     qword [cur_fn_rettype], 1
    je      .ret_str
    mov     rdi, cstr_ret_pfx       ; "  ret i64 %"
    jmp     .ret_emit
.ret_str:
    mov     rdi, cstr_ret_str_pfx   ; "  ret i8* %"
.ret_emit:
    call    emit_str
    pop     rdi
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    jmp     .dead_block

.no_value:
    cmp     qword [cur_fn_rettype], 1
    je      .ret_null
    mov     rdi, cstr_ret0          ; "  ret i64 0\n"
    call    emit_str
    jmp     .dead_block
.ret_null:
    mov     rdi, cstr_ret_null      ; "  ret i8* null\n"
    call    emit_str

.dead_block:
    ; Open a dead block so any following instructions stay valid
    mov     rdi, cstr_nl
    call    emit_str
    mov     rdi, cstr_ret_dead      ; "ret.dead."
    call    emit_str
    mov     rax, [label_counter]
    inc     qword [label_counter]
    mov     rdi, rax
    call    emit_num
    mov     rdi, cstr_colon_nl      ; ":\n"
    call    emit_str

    xor     rax, rax
    pop     r12
    pop     rbp
    ret

; ============================================================
; CODEGEN_BLOCK
; Generates code for a block: { statements }
; ============================================================
codegen_block:
    push    rbp
    mov     rbp, rsp
    push    r12

    mov     r12, [rdi + NODE_LEFT]  ; first statement

.stmt_loop:
    test    r12, r12
    jz      .done

    mov     rdi, r12
    call    codegen_node

    mov     r12, [r12 + NODE_NEXT]
    jmp     .stmt_loop

.done:
    xor     rax, rax
    pop     r12
    pop     rbp
    ret

; ============================================================
; EMIT_STRING_GLOBALS
; Emits all string literal global constants before main
; Must be called after main body is emitted but we insert
; them at the top using the pre-header buffer technique
; For simplicity we emit them inline at end of file
; ============================================================
emit_string_globals:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13

    ; Check if any string literals
    mov     r13, [str_lit_count]
    test    r13, r13
    jz      .done

    ; Emit comment
    mov     rdi, cstr_149
    call    emit_str

    ; Loop through each string literal
    xor     r12, r12            ; index into str_lit_buf

.lit_loop:
    cmp     r12, r13
    jge     .done

    ; Get string info: start, len, index
    mov     rax, r12
    mov     rcx, 24             ; 3 * 8 bytes per entry
    mul     rcx

    mov     rbx, [str_lit_buf + rax]        ; source start
    mov     rcx, [str_lit_buf + rax + 8]    ; source length
    push    rcx                              ; save length

    ; Emit: @.str.N = private constant [LEN+1 x i8] c"TEXT\00"
    mov     rdi, cstr_150
    call    emit_str
    mov     rdi, r12
    call    emit_num

    mov     rdi, cstr_151
    call    emit_str

    ; length + 1 for null
    pop     rdi
    push    rdi
    inc     rdi
    call    emit_num

    mov     rdi, cstr_152
    call    emit_str

    ; Emit the actual string text from source
    pop     rsi                 ; length
    mov     rdi, rbx            ; start position
    call    emit_source_text

    ; Null terminator
    mov     rdi, cstr_153
    call    emit_str

    inc     r12
    jmp     .lit_loop

.done:
    pop     r13
    pop     r12
    pop     rbp
    ret

; ============================================================
; CODEGEN_WRITE_OUTPUT
; Writes the generated IR buffer to output.ll file
; ============================================================
codegen_write_output:
    push    rbp
    mov     rbp, rsp

    mov     rdi, msg_writing
    call    cg_print_str

    ; Open output file
    mov     rax, SYS_OPEN
    mov     rdi, out_filename
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, 0o644
    syscall
    cmp     rax, 0
    jl      .error
    mov     [out_fd], rax

    ; Write IR buffer to file
    mov     rax, SYS_WRITE
    mov     rdi, [out_fd]
    mov     rsi, ir_buf
    mov     rdx, [ir_pos]
    syscall

    ; Write function definitions buffer
    mov     rax, SYS_WRITE
    mov     rdi, [out_fd]
    lea     rsi, [fn_buf]
    mov     rdx, [fn_pos]
    syscall

    ; Close file
    mov     rax, SYS_CLOSE
    mov     rdi, [out_fd]
    syscall

    mov     rdi, msg_write_ok
    call    cg_print_str

    mov     rax, 1
    pop     rbp
    ret

.error:
    xor     rax, rax
    pop     rbp
    ret

; ============================================================
; VARIABLE TABLE FUNCTIONS
; ============================================================

; Add variable to table
; Input: rdi = IDENT node pointer
;        rsi = alloca register number
var_table_add:
    push    rbp
    mov     rbp, rsp
    push    rbx

    mov     r8, rdx             ; save type (mul clobbers rdx!)

    ; Get current count
    mov     rax, [var_count]
    cmp     rax, MAX_VAR_TABLE - 1
    jge     .overflow

    ; Calculate entry offset
    mov     rcx, VAR_ENTRY_SIZE
    mul     rcx
    lea     rbx, [var_table + rax]

    ; Store name start, name len, register
    mov     rax, [rdi + NODE_TSTART]
    mov     [rbx], rax
    mov     rax, [rdi + NODE_TLEN]
    mov     [rbx + 8], rax
    mov     [rbx + 16], rsi
    mov     [rbx + 24], r8      ; type: 0=int, 1=string

    ; Increment count
    inc     qword [var_count]

.overflow:
    pop     rbx
    pop     rbp
    ret

; Look up variable in table
; Input: rdi = IDENT node pointer
; Returns: rax = alloca register number (0 if not found)
var_table_get:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14

    ; Get identifier info
    mov     r12, [rdi + NODE_TSTART]    ; name start in source
    mov     r13, [rdi + NODE_TLEN]      ; name length

    ; Search table
    mov     r14, [var_scope_base]       ; index (scoped)

.search_loop:
    cmp     r14, [var_count]
    jge     .not_found

    ; Get entry
    mov     rax, r14
    mov     rcx, VAR_ENTRY_SIZE
    mul     rcx
    lea     rbx, [var_table + rax]

    ; Compare lengths
    cmp     r13, [rbx + 8]
    jne     .next_entry

    ; Compare names
    mov     rdi, r12                    ; ident name in source
    mov     rsi, [rbx]                  ; stored name in source
    mov     rcx, r13                    ; length

    ; Both point into source buffer — compare
    mov     r8, [cg_src_buf]
    add     rdi, r8                     ; absolute pointer to ident
    add     rsi, r8                     ; absolute pointer to stored

    ; Compare character by character
    push    rcx
.char_loop:
    test    rcx, rcx
    jz      .match
    mov     al, [rdi]
    mov     ah, [rsi]
    cmp     al, ah
    jne     .char_no_match
    inc     rdi
    inc     rsi
    dec     rcx
    jmp     .char_loop

.match:
    pop     rcx
    ; Found — return register number
    mov     rax, [rbx + 16]
    jmp     .done

.char_no_match:
    pop     rcx

.next_entry:
    inc     r14
    jmp     .search_loop

.not_found:
    mov     rax, -1                     ; -1 = not found

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

var_table_get_type:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14

    ; Get identifier info
    mov     r12, [rdi + NODE_TSTART]    ; name start in source
    mov     r13, [rdi + NODE_TLEN]      ; name length

    ; Search table
    mov     r14, [var_scope_base]       ; index (scoped)

.search_loop:
    cmp     r14, [var_count]
    jge     .not_found

    ; Get entry
    mov     rax, r14
    mov     rcx, VAR_ENTRY_SIZE
    mul     rcx
    lea     rbx, [var_table + rax]

    ; Compare lengths
    cmp     r13, [rbx + 8]
    jne     .next_entry

    ; Compare names
    mov     rdi, r12                    ; ident name in source
    mov     rsi, [rbx]                  ; stored name in source
    mov     rcx, r13                    ; length

    ; Both point into source buffer — compare
    mov     r8, [cg_src_buf]
    add     rdi, r8                     ; absolute pointer to ident
    add     rsi, r8                     ; absolute pointer to stored

    ; Compare character by character
    push    rcx
.char_loop:
    test    rcx, rcx
    jz      .match
    mov     al, [rdi]
    mov     ah, [rsi]
    cmp     al, ah
    jne     .char_no_match
    inc     rdi
    inc     rsi
    dec     rcx
    jmp     .char_loop

.match:
    pop     rcx
    ; Found — return TYPE
    mov     rax, [rbx + 24]
    jmp     .done

.char_no_match:
    pop     rcx

.next_entry:
    inc     r14
    jmp     .search_loop

.not_found:
    mov     rax, -1                     ; -1 = not found

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; REGISTER ALLOCATION
; ============================================================

; Allocate a new SSA register — returns next number
new_reg:
    mov     rax, [reg_counter]
    inc     qword [reg_counter]
    ret

; ============================================================
; CODEGEN_BREAK / CODEGEN_CONTINUE
; br to innermost loop's end/cond label, then open dead block
; ============================================================
codegen_break:
    push    rbp
    mov     rbp, rsp
    cmp     qword [cur_loop_kind], 0
    je      .outside
    mov     rdi, cstr_br_label      ; "  br label %"
    call    emit_str
    call    emit_loop_end_name
    mov     rdi, [cur_loop_end_lbl]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    call    emit_dead_block
    xor     rax, rax
    pop     rbp
    ret
.outside:
    mov     qword [cg_error_flag], 1
    mov     rdi, err_break_outside
    call    cg_print_str
    xor     rax, rax
    pop     rbp
    ret

codegen_continue:
    push    rbp
    mov     rbp, rsp
    cmp     qword [cur_loop_kind], 0
    je      codegen_break.outside
    mov     rdi, cstr_br_label
    call    emit_str
    call    emit_loop_cond_name
    mov     rdi, [cur_loop_cond_lbl]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    call    emit_dead_block
    xor     rax, rax
    pop     rbp
    ret

; emit "while.end." / "for.end." / "loop.end." by kind
emit_loop_end_name:
    mov     rax, [cur_loop_kind]
    cmp     rax, 1
    je      .w
    cmp     rax, 2
    je      .f
    mov     rdi, cstr_loop_end_lbl2
    jmp     emit_str
.w: mov     rdi, cstr_while_end_lbl
    jmp     emit_str
.f: mov     rdi, cstr_for_end_lbl
    jmp     emit_str

; emit "while.cond." / "for.cond." / "loop.start." by kind
emit_loop_cond_name:
    mov     rax, [cur_loop_kind]
    cmp     rax, 1
    je      .w
    cmp     rax, 2
    je      .f
    mov     rdi, cstr_loop_start_lbl2
    jmp     emit_str
.w: mov     rdi, cstr_while_cond_lbl
    jmp     emit_str
.f: mov     rdi, cstr_for_cond
    jmp     emit_str

; open an unreachable block after a terminator
emit_dead_block:
    push    rbp
    mov     rbp, rsp
    mov     rdi, cstr_nl
    call    emit_str
    mov     rdi, cstr_brk_dead
    call    emit_str
    mov     rax, [label_counter]
    inc     qword [label_counter]
    mov     rdi, rax
    call    emit_num
    mov     rdi, cstr_colon_nl
    call    emit_str
    pop     rbp
    ret

; ============================================================
; NAME_MATCHES — rdi=FN_CALL node, rsi=cstr literal, rdx=len → rax=1 if match
; ============================================================
name_matches:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    mov     rbx, [rdi + NODE_LEFT]
    cmp     [rbx + NODE_TLEN], rdx
    jne     .no
    mov     r12, [cg_src_buf]
    add     r12, [rbx + NODE_TSTART]    ; source name
    mov     r13, rsi                    ; literal
.loop:
    test    rdx, rdx
    jz      .yes
    mov     al, [r12]
    cmp     al, [r13]
    jne     .no
    inc     r12
    inc     r13
    dec     rdx
    jmp     .loop
.yes:
    mov     rax, 1
    jmp     .out
.no:
    xor     rax, rax
.out:
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; literals for builtin names
section .data
    bi_min db "min"
    bi_max db "max"
    bi_abs db "abs"
    bi_sum db "sum"
section .text

; ============================================================
; FNCALL_IS_TEXT_BUILTIN — rdi = FN_CALL node → rax=1 if input_text
; ============================================================
fncall_is_text_builtin:
    push    rbp
    mov     rbp, rsp
    push    rbx
    mov     rbx, [rdi + NODE_LEFT]      ; name IDENT
    ; read_file → text (9 chars)
    cmp     qword [rbx + NODE_TLEN], 9
    jne     .chk_input_text
    mov     rax, [cg_src_buf]
    add     rax, [rbx + NODE_TSTART]
    cmp     byte [rax], 'r'
    jne     .chk_input_text
    cmp     byte [rax+1], 'e'
    jne     .chk_input_text
    cmp     byte [rax+2], 'a'
    jne     .chk_input_text
    cmp     byte [rax+3], 'd'
    jne     .chk_input_text
    mov     rax, 1
    pop     rbx
    pop     rbp
    ret
.chk_input_text:
    cmp     qword [rbx + NODE_TLEN], 10
    jne     .no
    mov     rax, [cg_src_buf]
    add     rax, [rbx + NODE_TSTART]
    cmp     byte [rax], 'i'
    jne     .no
    cmp     byte [rax+6], 't'
    jne     .no
    mov     rax, 1
    pop     rbx
    pop     rbp
    ret
.no:
    xor     rax, rax
    pop     rbx
    pop     rbp
    ret

; ============================================================
; EXPR_TYPE — rdi=node → rax: 0=int, 1=text, 2=list
; ============================================================
expr_type:
    push    rbp
    mov     rbp, rsp
    push    rbx
    test    rdi, rdi
    jz      .int
    mov     rbx, rdi
    mov     rax, [rbx + NODE_TYPE]
    cmp     rax, NODE_MAP_LIT
    je      .map
    cmp     rax, NODE_ARRAY_LIT
    je      .list
    cmp     rax, NODE_STRING_LIT
    je      .text
    cmp     rax, NODE_IDENT
    je      .var
    cmp     rax, NODE_FN_CALL
    je      .fncall
    cmp     rax, NODE_INDEX
    je      .index_type
    cmp     rax, NODE_BINARY
    je      .binary
    jmp     .int
.var:
    mov     rdi, rbx
    call    var_table_get_type
    cmp     rax, -1
    je      .int
    jmp     .ret
.fncall:
    mov     rdi, rbx
    call    fncall_is_text_builtin
    test    rax, rax
    jnz     .text
    mov     rdi, [rbx + NODE_LEFT]
    call    fn_table_lookup
    jmp     .ret
.binary:
    ; string concat → text, else int
    mov     rdi, rbx
    call    expr_is_string
    test    rax, rax
    jnz     .text
    jmp     .int
.index_type:
    ; element type = list's element type
    mov     rdi, [rbx + NODE_LEFT]      ; the list expr
    call    expr_type
    cmp     rax, 3
    je      .text
    jmp     .int

.map:
    ; check first entry's value type
    mov     rax, [rbx + NODE_LEFT]      ; first entry
    test    rax, rax
    jz      .map_int
    push    rbx
    mov     rdi, [rax + NODE_RIGHT]     ; first value
    call    expr_is_string
    pop     rbx
    cmp     rax, 1
    je      .map_text
.map_int:
    mov     rax, 4
    jmp     .ret
.map_text:
    mov     rax, 5
    jmp     .ret

.list:
    ; check first element type
    push    rbx
    mov     rax, [rbx + NODE_LEFT]      ; first element
    test    rax, rax
    jz      .list_int
    mov     rdi, rax
    call    expr_is_string
    pop     rbx
    cmp     rax, 1
    je      .list_text
    mov     rax, 2
    jmp     .ret
.list_int:
    pop     rbx
    mov     rax, 2
    jmp     .ret
.list_text:
    mov     rax, 3
    jmp     .ret
.text:
    mov     rax, 1
    jmp     .ret
.int:
    xor     rax, rax
.ret:
    pop     rbx
    pop     rbp
    ret

; ============================================================
; EXPR_IS_STRING — recursive type inference
; rdi = node ptr → rax = 1 if expression is string-typed
; ============================================================
expr_is_string:
    push    rbp
    mov     rbp, rsp
    push    rbx
    test    rdi, rdi
    jz      .no
    mov     rbx, rdi
    mov     rax, [rbx + NODE_TYPE]
    cmp     rax, NODE_STRING_LIT
    je      .yes
    cmp     rax, NODE_IDENT
    je      .check_var
    cmp     rax, NODE_FN_CALL
    je      .check_fn
    cmp     rax, NODE_INDEX
    je      .check_index
    cmp     rax, NODE_BINARY
    jne     .no
    mov     rax, [rbx + NODE_EXTRA]
    cmp     rax, BINOP_ADD
    jne     .no
    mov     rdi, [rbx + NODE_LEFT]
    call    expr_is_string
    test    rax, rax
    jnz     .yes
    mov     rdi, [rbx + NODE_RIGHT]
    call    expr_is_string
    test    rax, rax
    jnz     .yes
    jmp     .no
.check_var:
    mov     rdi, rbx
    call    var_table_get_type
    cmp     rax, 1
    je      .yes
    jmp     .no
.check_fn:
    mov     rdi, rbx
    call    fncall_is_text_builtin
    test    rax, rax
    jnz     .yes
    mov     rdi, [rbx + NODE_LEFT]
    call    fn_table_lookup
    cmp     rax, 1
    je      .yes
    jmp     .no
.check_index:
    mov     rdi, [rbx + NODE_LEFT]      ; the list/map
    call    expr_type
    cmp     rax, 3
    je      .yes
    cmp     rax, 5
    je      .yes
.no:
    xor     rax, rax
    jmp     .out
.yes:
    mov     rax, 1
.out:
    pop     rbx
    pop     rbp
    ret

; ============================================================
; TYPE_NODE_IS_TEXT — rdi = type IDENT node (or 0) → rax=1 if "text"
; ============================================================
type_node_is_text:
    push    rbp
    mov     rbp, rsp
    test    rdi, rdi
    jz      .no
    cmp     qword [rdi + NODE_TLEN], 4
    jne     .no
    mov     rax, [cg_src_buf]
    add     rax, [rdi + NODE_TSTART]
    cmp     byte [rax], 't'
    jne     .no
    cmp     byte [rax+1], 'e'
    jne     .no
    cmp     byte [rax+2], 'x'
    jne     .no
    cmp     byte [rax+3], 't'
    jne     .no
    mov     rax, 1
    pop     rbp
    ret
.no:
    xor     rax, rax
    pop     rbp
    ret

; ============================================================
; FN_TABLE_ADD — rdi = fn name IDENT node, rsi = rettype
; ============================================================
fn_table_add:
    push    rbp
    mov     rbp, rsp
    push    rbx
    mov     rax, [fn_table_count]
    cmp     rax, 63
    jge     .full
    imul    rax, rax, 40
    lea     rbx, [fn_table + rax]
    mov     rax, [rdi + NODE_TSTART]
    mov     [rbx], rax
    mov     rax, [rdi + NODE_TLEN]
    mov     [rbx + 8], rax
    mov     [rbx + 16], rsi     ; rettype
    mov     [rbx + 24], rdx     ; param count
    mov     [rbx + 32], rcx     ; param type mask
    inc     qword [fn_table_count]
.full:
    pop     rbx
    pop     rbp
    ret

; ============================================================
; FN_TABLE_LOOKUP — rdi = fn name IDENT node → rax = rettype (0 if unknown)
; ============================================================
fn_table_lookup:
    ; rdi = fn name IDENT → rax = rettype (0 if unknown)
    push    rbp
    mov     rbp, rsp
    call    fn_table_lookup_entry
    cmp     rax, -1
    je      .unknown
    mov     rax, [rax + 16]
    pop     rbp
    ret
.unknown:
    xor     rax, rax
    pop     rbp
    ret

; rdi = fn name IDENT node → rax = entry ptr, or -1 if not found
fn_table_lookup_entry:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, [rdi + NODE_TSTART]
    mov     r13, [rdi + NODE_TLEN]
    xor     r14, r14
.loop:
    cmp     r14, [fn_table_count]
    jge     .not_found
    mov     rax, r14
    imul    rax, rax, 40
    lea     rbx, [fn_table + rax]
    mov     rax, [rbx + 8]
    cmp     rax, r13
    jne     .next
    mov     rdi, r12
    mov     rsi, [rbx]
    mov     rax, [cg_src_buf]
    add     rdi, rax
    add     rsi, rax
    mov     rcx, r13
.cmp_loop:
    test    rcx, rcx
    jz      .match
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .next
    inc     rdi
    inc     rsi
    dec     rcx
    jmp     .cmp_loop
.match:
    mov     rax, rbx
    jmp     .done
.next:
    inc     r14
    jmp     .loop
.not_found:
    mov     rax, -1
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret


; ============================================================
; TO_TEXT_IF_INT — auto-convert int values to text for concat
; Input:  rax = value register, rsi = expression node ptr
; Output: rax = text (i8*) register
; ============================================================
to_text_if_int:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12

    mov     r12, rax            ; value register
    mov     rdi, rsi
    call    expr_is_string
    test    rax, rax
    jz      .convert
    mov     rax, r12            ; already text
    jmp     .done

.convert:
    ; %m = malloc(24)
    call    new_reg
    mov     rbx, rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_malloc24
    call    emit_str

    ; %_ = sprintf(%m, "%ld", %val)
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_sprintf_pre
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_sprintf_mid
    call    emit_str
    mov     rdi, r12
    call    emit_num
    mov     rdi, cstr_close_nl
    call    emit_str
    pop     rax

    mov     rax, rbx

.done:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; PARAM_IS_LIST — rdi = PARAM node → rax=1 if ": list"
; ============================================================
param_is_list:
    push    rbp
    mov     rbp, rsp
    push    rbx
    mov     rbx, [rdi + NODE_RIGHT]
    test    rbx, rbx
    jz      .no
    cmp     qword [rbx + NODE_TLEN], 4
    jne     .no
    mov     rax, [cg_src_buf]
    add     rax, [rbx + NODE_TSTART]
    cmp     byte [rax], 'l'
    jne     .no
    cmp     byte [rax+1], 'i'
    jne     .no
    cmp     byte [rax+2], 's'
    jne     .no
    cmp     byte [rax+3], 't'
    jne     .no
    mov     rax, 1
    pop     rbx
    pop     rbp
    ret
.no:
    xor     rax, rax
    pop     rbx
    pop     rbp
    ret

; ============================================================
; PARAM_IS_TEXT — rdi = PARAM node → rax=1 if ": text"
; ============================================================
param_is_text:
    push    rbp
    mov     rbp, rsp
    push    rbx
    mov     rbx, [rdi + NODE_RIGHT]     ; type annotation IDENT
    test    rbx, rbx
    jz      .no
    cmp     qword [rbx + NODE_TLEN], 4
    jne     .no
    mov     rax, [cg_src_buf]
    add     rax, [rbx + NODE_TSTART]
    cmp     byte [rax], 't'
    jne     .no
    cmp     byte [rax+1], 'e'
    jne     .no
    cmp     byte [rax+2], 'x'
    jne     .no
    cmp     byte [rax+3], 't'
    jne     .no
    mov     rax, 1
    jmp     .out
.no:
    xor     rax, rax
.out:
    pop     rbx
    pop     rbp
    ret

; ============================================================
; CODEGEN_ARRAY_LIT — [a, b, c]
; Layout: heap i64 array, slot 0 = count, slots 1..n = elements.
; Returns rax = i64* register (the array pointer).
; ============================================================
; ============================================================
; CODEGEN_MAP_LIT — {"k": v, ...}
; Heap i64 array: slot0=count, then (keyptr_as_i64, value) pairs.
; Keys are string literals (ptrtoint); values are int expressions.
; Returns rax = i64* pointer.
; ============================================================
codegen_map_lit:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi                    ; MAP_LIT node

    ; Evaluate entries: each entry has key span (TSTART/TLEN) + value RIGHT
    xor     r13, r13                    ; count
    mov     rbx, [r12 + NODE_LEFT]      ; first entry
.map_eval:
    test    rbx, rbx
    jz      .map_eval_done
    ; --- key: emit a string global, get its i8* then ptrtoint ---
    ; reuse codegen_string_lit machinery by faking a STRING_LIT node:
    ; simpler — emit key via emit_key_string helper
    push    rbx
    mov     rdi, rbx
    call    emit_map_key                ; returns rax = i64 (ptrtoint of key)
    pop     rbx
    mov     [map_keys + r13*8], rax
    ; --- value (ptrtoint if text) ---
    push    rbx
    mov     rdi, [rbx + NODE_RIGHT]
    call    expr_is_string
    mov     [map_val_is_str], rax
    mov     rdi, [rbx + NODE_RIGHT]
    call    codegen_node
    pop     rbx
    cmp     qword [map_val_is_str], 1
    jne     .mv_store
    ; ptrtoint the text value
    push    rbx
    push    rax
    call    new_reg
    mov     rbx, rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_p2i_pre
    call    emit_str
    pop     rax
    mov     rdi, rax
    call    emit_num
    mov     rdi, cstr_p2i_suf
    call    emit_str
    mov     rax, rbx
    pop     rbx
.mv_store:
    mov     [map_vals + r13*8], rax
    inc     r13
    mov     rbx, [rbx + NODE_NEXT]
    jmp     .map_eval
.map_eval_done:
    mov     [map_n], r13

    ; bytes = (count*2 + 1) * 8
    mov     rax, r13
    imul    rax, rax, 2
    inc     rax
    imul    rax, rax, 8
    push    rax

    ; %raw = malloc(bytes)
    call    new_reg
    mov     [arr_raw], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [arr_raw]
    call    emit_num
    mov     rdi, cstr_arr_malloc
    call    emit_str
    pop     rdi
    call    emit_num
    mov     rdi, cstr_close_nl
    call    emit_str

    ; %ptr = bitcast to i64*
    call    new_reg
    mov     [arr_ptr], rax
    mov     [map_ptr], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [arr_ptr]
    call    emit_num
    mov     rdi, cstr_arr_bcast
    call    emit_str
    mov     rdi, [arr_raw]
    call    emit_num
    mov     rdi, cstr_to_i64p
    call    emit_str

    ; store count at slot 0
    xor     rdi, rdi
    call    emit_gep_const_idx
    mov     rdi, cstr_store_arr
    call    emit_str
    mov     rdi, [map_n]
    call    emit_num
    mov     rdi, cstr_to_slot
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    ; store each (key,val) pair
    xor     rbx, rbx
.map_store:
    cmp     rbx, [map_n]
    jge     .map_store_done
    ; key slot = i*2 + 1
    mov     rax, rbx
    imul    rax, rax, 2
    inc     rax
    push    rbx
    mov     rdi, rax
    call    emit_gep_const_idx
    pop     rbx
    mov     rdi, cstr_store_areg        ; "  store i64 %"
    call    emit_str
    mov     rdi, [map_keys + rbx*8]
    call    emit_num
    mov     rdi, cstr_to_slot
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    ; val slot = i*2 + 2
    mov     rax, rbx
    imul    rax, rax, 2
    add     rax, 2
    push    rbx
    mov     rdi, rax
    call    emit_gep_const_idx
    pop     rbx
    mov     rdi, cstr_store_areg
    call    emit_str
    mov     rdi, [map_vals + rbx*8]
    call    emit_num
    mov     rdi, cstr_to_slot
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    inc     rbx
    jmp     .map_store
.map_store_done:

    mov     rax, [map_ptr]
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; emit a key string global from entry node (TSTART/TLEN), return rax = i64 ptrtoint
emit_map_key:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi                    ; entry node

    ; register string literal for later global emission
    mov     r13, [str_lit_count]
    inc     qword [str_lit_count]
    mov     rax, [str_lit_pos]
    mov     rbx, [r12 + NODE_TSTART]
    mov     [str_lit_buf + rax], rbx
    add     rax, 8
    mov     rbx, [r12 + NODE_TLEN]
    mov     [str_lit_buf + rax], rbx
    add     rax, 8
    mov     [str_lit_buf + rax], r13
    add     rax, 8
    mov     [str_lit_pos], rax

    ; %p = getelementptr [(len+1) x i8], ...* @.str.N, i32 0, i32 0
    call    new_reg
    push    rax                         ; ptr reg
    mov     rdi, cstr_21          ; "  %"
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_22          ; " = getelementptr inbounds ["
    call    emit_str
    mov     rdi, [r12 + NODE_TLEN]
    inc     rdi
    call    emit_num
    mov     rdi, cstr_23          ; " x i8], ["
    call    emit_str
    mov     rdi, [r12 + NODE_TLEN]
    inc     rdi
    call    emit_num
    mov     rdi, cstr_24          ; " x i8]* @.str."
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_25          ; ", i32 0, i32 0\n"
    call    emit_str

    ; %int = ptrtoint i8* %p to i64
    call    new_reg
    mov     rbx, rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_p2i_pre
    call    emit_str
    pop     rdi                         ; ptr reg
    call    emit_num
    mov     rdi, cstr_p2i_suf
    call    emit_str
    mov     rax, rbx                    ; return i64

    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

codegen_array_lit:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi                    ; ARRAY_LIT node

    ; Detect element type from first element (int vs text)
    mov     qword [arr_elem_is_str], 0
    mov     rax, [r12 + NODE_LEFT]
    test    rax, rax
    jz      .no_first
    mov     rdi, rax
    call    expr_is_string
    mov     [arr_elem_is_str], rax
.no_first:

    ; Evaluate elements, count them
    xor     r13, r13                    ; count
    mov     rbx, [r12 + NODE_LEFT]      ; first element
.eval:
    test    rbx, rbx
    jz      .eval_done
    push    rbx
    mov     rdi, rbx
    call    codegen_node
    pop     rbx
    ; if elements are strings, ptrtoint to store in i64 array
    cmp     qword [arr_elem_is_str], 1
    jne     .store_elem
    push    rbx
    push    rax
    call    new_reg
    mov     rbx, rax                    ; int reg
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_p2i_pre           ; " = ptrtoint i8* %"
    call    emit_str
    pop     rax                         ; original ptr reg
    mov     rdi, rax
    call    emit_num
    mov     rdi, cstr_p2i_suf           ; " to i64\n"
    call    emit_str
    mov     rax, rbx                    ; now use int reg
    pop     rbx
.store_elem:
    mov     [arr_elems + r13*8], rax
    inc     r13
    mov     rbx, [rbx + NODE_NEXT]
    jmp     .eval
.eval_done:
    mov     [arr_n], r13

    ; bytes = (count + 1) * 8
    mov     rax, r13
    inc     rax
    imul    rax, rax, 8
    push    rax                         ; byte size

    ; %raw = call i8* @malloc(i64 BYTES)
    call    new_reg
    mov     [arr_raw], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [arr_raw]
    call    emit_num
    mov     rdi, cstr_arr_malloc        ; " = call i8* @malloc(i64 "
    call    emit_str
    pop     rdi                         ; byte size
    call    emit_num
    mov     rdi, cstr_close_nl
    call    emit_str

    ; %ptr = bitcast i8* %raw to i64*
    call    new_reg
    mov     [arr_ptr], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [arr_ptr]
    call    emit_num
    mov     rdi, cstr_arr_bcast         ; " = bitcast i8* %"
    call    emit_str
    mov     rdi, [arr_raw]
    call    emit_num
    mov     rdi, cstr_to_i64p           ; " to i64*\n"
    call    emit_str

    ; slot0 = count : %s = gep ptr, 0 ; store count, %s
    call    emit_gep_const              ; rdi consumed inside; uses arr_ptr + arg
    ; store count into slot 0
    mov     rdi, cstr_store_arr         ; "  store i64 "
    call    emit_str
    mov     rdi, [arr_n]
    call    emit_num
    mov     rdi, cstr_to_slot           ; ", i64* %"
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    ; store each element at slot i+1
    xor     rbx, rbx
.store_loop:
    cmp     rbx, [arr_n]
    jge     .store_done
    ; slot = gep ptr, (i+1)
    mov     rax, rbx
    inc     rax
    push    rbx
    mov     rdi, rax
    call    emit_gep_const_idx          ; rdi = constant index → sets arr_slot
    pop     rbx
    ; store element value
    mov     rdi, cstr_store_areg        ; "  store i64 %"
    call    emit_str
    mov     rdi, [arr_elems + rbx*8]
    call    emit_num
    mov     rdi, cstr_to_slot           ; ", i64* %"
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    inc     rbx
    jmp     .store_loop
.store_done:

    mov     rax, [arr_ptr]              ; result = array pointer
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; helper: emit "%slot = getelementptr i64, i64* %arr_ptr, i64 0"  (slot0)
emit_gep_const:
    push    rbp
    mov     rbp, rsp
    call    new_reg
    mov     [arr_slot], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_arr_gep           ; " = getelementptr i64, i64* %"
    call    emit_str
    mov     rdi, [arr_ptr]
    call    emit_num
    mov     rdi, cstr_gep_idx           ; ", i64 "
    call    emit_str
    xor     rdi, rdi
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    pop     rbp
    ret

; helper: emit "%slot = getelementptr i64, i64* %arr_ptr, i64 <rdi>"
emit_gep_const_idx:
    push    rbp
    mov     rbp, rsp
    push    r12
    mov     r12, rdi                    ; constant index
    call    new_reg
    mov     [arr_slot], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_arr_gep
    call    emit_str
    mov     rdi, [arr_ptr]
    call    emit_num
    mov     rdi, cstr_gep_idx
    call    emit_str
    mov     rdi, r12
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    pop     r12
    pop     rbp
    ret

; ============================================================
; CODEGEN_INDEX — arr[i]  → loads element at slot (i+1)
; Returns rax = value register
; ============================================================
codegen_index:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13

    mov     r12, rdi                    ; INDEX node

    ; Is the base a map? (type 4) → call map_get
    mov     rdi, [r12 + NODE_LEFT]
    call    expr_type
    cmp     rax, 4
    je      .is_map_index
    cmp     rax, 5
    je      .is_map_index
    jmp     .not_map_index
.is_map_index:
    ; remember if map holds text values (type 5)
    mov     qword [map_val_is_str], 0
    cmp     rax, 5
    jne     .mi_novtext
    mov     qword [map_val_is_str], 1
.mi_novtext:
    ; evaluate map pointer
    mov     rdi, [r12 + NODE_LEFT]
    call    codegen_node
    mov     [map_ptr], rax
    ; evaluate key (text pointer)
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    mov     r13, rax                    ; key i8*
    ; %v = call i64 @__ink_map_get(i64* %map, i8* %key)
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_mapget_pre
    call    emit_str
    mov     rdi, [map_ptr]
    call    emit_num
    mov     rdi, cstr_mapget_mid
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_close_nl
    call    emit_str
    pop     rax
    ; if text-valued map, inttoptr the result
    cmp     qword [map_val_is_str], 1
    jne     .mi_done
    mov     r13, rax
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_i2p_pre
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_i2p_suf
    call    emit_str
    pop     rax
.mi_done:
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
.not_map_index:

    ; Determine if the list holds text (type 3)
    mov     qword [idx_elem_is_str], 0
    mov     rdi, [r12 + NODE_LEFT]
    call    expr_type
    cmp     rax, 3
    jne     .idx_not_text
    mov     qword [idx_elem_is_str], 1
.idx_not_text:

    ; evaluate array (gives i64* pointer register)
    mov     rdi, [r12 + NODE_LEFT]
    call    codegen_node
    mov     [arr_ptr], rax

    ; evaluate index expression
    mov     rdi, [r12 + NODE_RIGHT]
    call    codegen_node
    mov     r13, rax                    ; index register

    ; ── bounds check: call @__ink_bounds_check(idx, arr) ─
    mov     rdi, cstr_bcheck_pre        ; "  call void @__ink_bounds_check(i64 %"
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_bcheck_mid        ; ", i64* %"
    call    emit_str
    mov     rdi, [arr_ptr]
    call    emit_num
    mov     rdi, cstr_call_close        ; ")\n"
    call    emit_str

    ; realidx = index + 1  (slot 0 is length)
    call    new_reg
    mov     rbx, rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_idx_add1          ; " = add i64 %"
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_comma_1_nl        ; ", 1\n"
    call    emit_str

    ; slot = gep ptr, %realidx
    call    new_reg
    mov     [arr_slot], rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_arr_gep
    call    emit_str
    mov     rdi, [arr_ptr]
    call    emit_num
    mov     rdi, cstr_gep_reg           ; ", i64 %"
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str

    ; value = load i64, i64* %slot
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_load_slot         ; " = load i64, i64* %"
    call    emit_str
    mov     rdi, [arr_slot]
    call    emit_num
    mov     rdi, cstr_nl
    call    emit_str
    pop     rax

    ; if text list, inttoptr the loaded i64 → i8*
    cmp     qword [idx_elem_is_str], 1
    jne     .idx_done
    mov     r13, rax                    ; loaded int
    call    new_reg
    push    rax
    mov     rdi, cstr_pct
    call    emit_str
    mov     rdi, [rsp]
    call    emit_num
    mov     rdi, cstr_i2p_pre           ; " = inttoptr i64 %"
    call    emit_str
    mov     rdi, r13
    call    emit_num
    mov     rdi, cstr_i2p_suf           ; " to i8*\n"
    call    emit_str
    pop     rax
.idx_done:

    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; COND_TO_I1
; Ensures a condition value is i1 for br.
; Input:  rax = value register, rsi = expression node ptr
; Output: rax = i1 register
; If the expr was a comparison binary, result is already i1.
; Otherwise emit: %M = icmp ne i64 %N, 0
; ============================================================
cond_to_i1:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12

    mov     r12, rax            ; value register
    test    rsi, rsi
    jz      .convert
    mov     rbx, [rsi + NODE_TYPE]
    cmp     rbx, NODE_BINARY
    jne     .convert
    mov     rbx, [rsi + NODE_EXTRA]
    cmp     rbx, BINOP_EQ
    jl      .convert
    cmp     rbx, BINOP_GTE
    jg      .convert
    ; already i1
    mov     rax, r12
    jmp     .done

.convert:
    call    new_reg
    mov     rbx, rax
    mov     rdi, cstr_pct           ; "  %"
    call    emit_str
    mov     rdi, rbx
    call    emit_num
    mov     rdi, cstr_icmp_ne0      ; " = icmp ne i64 %"
    call    emit_str
    mov     rdi, r12
    call    emit_num
    mov     rdi, cstr_comma0_nl     ; ", 0\n"
    call    emit_str
    mov     rax, rbx

.done:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; IR EMISSION HELPERS
; ============================================================

; Emit null-terminated string to IR buffer
; Input: rdi = string pointer
emit_str:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12

    mov     r12, rdi
    xor     rbx, rbx

.len_loop:
    cmp     byte [r12 + rbx], 0
    je      .copy
    inc     rbx
    jmp     .len_loop

.copy:
    ; Copy to ACTIVE buffer (ir_buf or fn_buf)
    push    rsi
    push    rdi
    push    rcx
    mov     rsi, r12
    mov     rdx, [emit_pos_addr]
    mov     rax, [rdx]
    mov     rdi, [emit_buf_base]
    add     rdi, rax
    mov     rcx, rbx
    rep movsb
    mov     rdx, [emit_pos_addr]
    add     [rdx], rbx
    pop     rcx
    pop     rdi
    pop     rsi

    pop     r12
    pop     rbx
    pop     rbp
    ret

; emit_cstr is now an alias for emit_str
; Input: rdi = pointer to null-terminated string
emit_cstr:
    jmp     emit_str


; Emit a number (integer) to IR buffer
; Input: rdi = number to emit
emit_num:
    push    rbp
    mov     rbp, rsp
    push    rbx

    mov     rax, rdi
    test    rax, rax
    jnz     .not_zero

    ; Emit "0"
    mov     rdx, [emit_pos_addr]
    mov     rax, [rdx]
    mov     r8, [emit_buf_base]
    mov     byte [r8 + rax], '0'
    inc     qword [rdx]
    jmp     .done

.not_zero:
    ; Convert to decimal in temp buffer
    lea     rbx, [num_buf + 31]
    mov     byte [rbx], 0
    dec     rbx

.convert:
    test    rax, rax
    jz      .emit_digits
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx
    add     dl, '0'
    mov     [rbx], dl
    dec     rbx
    jmp     .convert

.emit_digits:
    inc     rbx
    ; Copy to IR buffer
.digit_loop:
    cmp     byte [rbx], 0
    je      .done
    mov     rdx, [emit_pos_addr]
    mov     rax, [rdx]
    mov     r8, [emit_buf_base]
    mov     cl, [rbx]
    mov     [r8 + rax], cl
    inc     qword [rdx]
    inc     rbx
    jmp     .digit_loop

.done:
    pop     rbx
    pop     rbp
    ret

; Emit text from source buffer
; Input: rdi = start offset, rsi = length
emit_source_text:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12

    mov     r12, rdi            ; start offset
    mov     rbx, rsi            ; length

    test    rbx, rbx
    jz      .done

    ; Get source buffer pointer
    mov     rax, [cg_src_buf]
    add     rax, r12            ; absolute pointer to text

    ; Copy to ACTIVE buffer
    mov     rsi, rax
    mov     rdx, [emit_pos_addr]
    mov     rax, [rdx]
    mov     rdi, [emit_buf_base]
    add     rdi, rax

    push    rcx
    mov     rcx, rbx
    rep movsb
    pop     rcx

    mov     rdx, [emit_pos_addr]
    add     [rdx], rbx

.done:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Print string to stdout
; Input: rdi = string pointer
; Print source text (rdi=start offset, rsi=len) + newline to stdout
cg_print_src:
    push    rbp
    mov     rbp, rsp
    push    rbx
    mov     rbx, rsi
    mov     rsi, [cg_src_buf]
    add     rsi, rdi
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT
    mov     rdx, rbx
    syscall
    ; newline
    push    10
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT
    mov     rsi, rsp
    mov     rdx, 1
    syscall
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

cg_print_str:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12

    mov     r12, rdi
    xor     rbx, rbx
.len_loop:
    cmp     byte [r12 + rbx], 0
    je      .write
    inc     rbx
    jmp     .len_loop
.write:
    test    rbx, rbx
    jz      .done
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT
    mov     rsi, r12
    mov     rdx, rbx
    syscall
.done:
    pop     r12
    pop     rbx
    pop     rbp
    ret
