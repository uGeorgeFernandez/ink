; ============================================================
; INK Programming Language — Parser
; File: parser/parser.asm
; Architecture: x86-64 Assembly (NASM)
;
; The Parser is Phase 2 of the INK compiler.
; It reads tokens from the Lexer and builds an
; Abstract Syntax Tree (AST) — a tree structure
; that represents the meaning of your INK code.
;
; Example:
;   Tokens:  [LET] [IDENT:x] [EQUALS] [INT:5] [PLUS] [INT:3]
;   AST:
;            LET_STMT
;           /         \
;        IDENT:x     BINARY_ADD
;                   /          \
;               INT:5         INT:3
;
; The AST is then passed to the Code Generator (Phase 3)
; which converts it to LLVM IR and then machine code.
;
; INK — Write the Future
; Created by: IndianBrand Technology, Hyderabad, India
; Language: 100% x86-64 Assembly — no C, no Python
; Jai Hind! 🇮🇳
; ============================================================

; ── SYSTEM CALLS ────────────────────────────────────────────
SYS_WRITE   equ 1
SYS_EXIT    equ 60
STDOUT      equ 1
STDERR      equ 2

; ── TOKEN TYPES (same as lexer) ──────────────────────────────
TOKEN_EOF       equ 0
TOKEN_SHOW      equ 1
TOKEN_LET       equ 2
TOKEN_CONST     equ 3
TOKEN_FN        equ 4
TOKEN_RETURN    equ 5
TOKEN_IF        equ 6
TOKEN_ELSE      equ 7
TOKEN_FOR       equ 8
TOKEN_WHILE     equ 9
TOKEN_LOOP      equ 10
TOKEN_BREAK     equ 11
TOKEN_CONTINUE  equ 12
TOKEN_MATCH     equ 13
TOKEN_TYPE      equ 14
TOKEN_PUB       equ 15
TOKEN_USE       equ 16
TOKEN_IN        equ 17
TOKEN_OR        equ 18
TOKEN_AND       equ 19
TOKEN_NOT       equ 20
TOKEN_TRUE      equ 21
TOKEN_FALSE     equ 22
TOKEN_NONE      equ 23
TOKEN_EXISTS    equ 24
TOKEN_IDENT     equ 25
TOKEN_INT       equ 26
TOKEN_FLOAT     equ 27
TOKEN_STRING    equ 28
TOKEN_CHAR      equ 29
TOKEN_PLUS      equ 30
TOKEN_MINUS     equ 31
TOKEN_STAR      equ 32
TOKEN_SLASH     equ 33
TOKEN_PERCENT   equ 34
TOKEN_EQUALS    equ 35
TOKEN_EQ_EQ     equ 36
TOKEN_BANG_EQ   equ 37
TOKEN_LT        equ 38
TOKEN_GT        equ 39
TOKEN_LT_EQ     equ 40
TOKEN_GT_EQ     equ 41
TOKEN_ARROW     equ 42
TOKEN_FAT_ARROW equ 43
TOKEN_LPAREN    equ 44
TOKEN_RPAREN    equ 45
TOKEN_LBRACE    equ 46
TOKEN_RBRACE    equ 47
TOKEN_LBRACKET  equ 48
TOKEN_RBRACKET  equ 49
TOKEN_COLON     equ 50
TOKEN_SEMICOLON equ 51
TOKEN_COMMA     equ 52
TOKEN_DOT       equ 53
TOKEN_DOT_DOT   equ 54
TOKEN_QUESTION  equ 55
TOKEN_BANG      equ 56
TOKEN_PIPE      equ 57
TOKEN_AT        equ 58

; ── TOKEN STRUCTURE SIZE ─────────────────────────────────────
TOKEN_SIZE      equ 40
; Offsets within token structure:
TOK_TYPE        equ 0   ; token type (8 bytes)
TOK_START       equ 8   ; start position in source (8 bytes)
TOK_LEN         equ 16  ; length of token text (8 bytes)
TOK_LINE        equ 24  ; line number (8 bytes)
TOK_COL         equ 32  ; column number (8 bytes)

; ── AST NODE TYPES ───────────────────────────────────────────
; Every piece of INK code becomes one of these node types
NODE_PROGRAM        equ 1   ; root node — entire program
NODE_LET            equ 2   ; let x = expr
NODE_CONST          equ 3   ; const X = expr
NODE_ASSIGN         equ 4   ; x = expr
NODE_FN_DEF         equ 5   ; fn name(params) -> type { body }
NODE_FN_CALL        equ 6   ; name(args)
NODE_RETURN         equ 7   ; return expr
NODE_IF             equ 8   ; if cond { then } else { else }
NODE_WHILE          equ 9   ; while cond { body }
NODE_FOR            equ 10  ; for i in range { body }
NODE_LOOP           equ 11  ; loop { body }
NODE_BREAK          equ 12  ; break
NODE_CONTINUE       equ 13  ; continue
NODE_MATCH          equ 14  ; match expr { arms }
NODE_BLOCK          equ 15  ; { statements }
NODE_SHOW           equ 16  ; show expr
NODE_USE            equ 17  ; use module
NODE_TYPE_DEF       equ 18  ; type Name { fields }
NODE_BINARY         equ 19  ; expr OP expr
NODE_UNARY          equ 20  ; OP expr
NODE_INT_LIT        equ 21  ; integer literal: 42
NODE_FLOAT_LIT      equ 22  ; float literal: 3.14
NODE_STRING_LIT     equ 23  ; string literal: "hello"
NODE_CHAR_LIT       equ 24  ; char literal: 'A'
NODE_BOOL_LIT       equ 25  ; true or false
NODE_NONE_LIT       equ 26  ; none
NODE_IDENT          equ 27  ; identifier: name, age
NODE_FIELD_ACCESS   equ 28  ; obj.field
NODE_INDEX          equ 29  ; arr[i]
NODE_ARRAY_LIT      equ 30  ; [1, 2, 3]
NODE_MAP_LIT        equ 31  ; {"key": value}
NODE_OPTIONAL_CHECK equ 32  ; expr exists
NODE_ERROR_HANDLE   equ 33  ; expr or { ... }
NODE_TYPE_ANNOT     equ 34  ; expr: Type
NODE_PARAM          equ 35  ; function parameter
NODE_MATCH_ARM      equ 36  ; pattern => expr

; ── BINARY OPERATORS ─────────────────────────────────────────
BINOP_ADD   equ 1   ; +
BINOP_SUB   equ 2   ; -
BINOP_MUL   equ 3   ; *
BINOP_DIV   equ 4   ; /
BINOP_MOD   equ 5   ; %
BINOP_EQ    equ 6   ; ==
BINOP_NEQ   equ 7   ; !=
BINOP_LT    equ 8   ; <
BINOP_GT    equ 9   ; >
BINOP_LTE   equ 10  ; <=
BINOP_GTE   equ 11  ; >=
BINOP_AND   equ 12  ; and
BINOP_OR    equ 13  ; or
BINOP_RANGE equ 14  ; ..

; ── AST NODE STRUCTURE ───────────────────────────────────────
; Every AST node is stored as a fixed-size structure
; Offset 0:  type      (8 bytes) — what type of node
; Offset 8:  left      (8 bytes) — pointer to left child
; Offset 16: right     (8 bytes) — pointer to right child
; Offset 24: extra     (8 bytes) — extra data (operator, etc.)
; Offset 32: tok_start (8 bytes) — source position
; Offset 40: tok_len   (8 bytes) — source length
; Offset 48: tok_line  (8 bytes) — line number
; Offset 56: sibling   (8 bytes) — next node in list
; Total: 64 bytes per node
NODE_SIZE   equ 64

; Node field offsets
NODE_TYPE   equ 0
NODE_LEFT   equ 8
NODE_RIGHT  equ 16
NODE_EXTRA  equ 24
NODE_TSTART equ 32
NODE_TLEN   equ 40
NODE_TLINE  equ 48
NODE_NEXT   equ 56  ; next sibling in a list

; ── MAX SIZES ────────────────────────────────────────────────
MAX_NODES   equ 50000   ; maximum AST nodes
MAX_ERRORS  equ 100     ; maximum parse errors before giving up

; ── DATA SECTION ─────────────────────────────────────────────
section .data

    ; Parser messages
    msg_parsing     db  "[INK] Parsing tokens...", 10, 0
    msg_parse_ok    db  "[INK] Parse complete — AST built successfully!", 10, 0
    msg_parse_fail  db  "[INK] Parse failed — errors found.", 10, 0

    ; Error message prefixes
    err_prefix      db  "[INK ERROR] Line ", 0
    err_col_sep     db  ", Col ", 0
    err_col_end     db  ": ", 0
    err_newline     db  10, 0

    ; Specific error messages
    err_expect_expr     db  "Expected expression", 0
    err_expect_ident    db  "Expected identifier", 0
    err_expect_colon    db  "Expected ':'", 0
    err_expect_equals   db  "Expected '='", 0
    err_expect_lparen   db  "Expected '('", 0
    err_expect_rparen   db  "Expected ')'", 0
    err_expect_lbrace   db  "Expected '{'", 0
    err_expect_rbrace   db  "Expected '}'", 0
    err_expect_rbracket db  "Expected ']'", 0
    err_expect_arrow    db  "Expected '->'", 0
    err_expect_in       db  "Expected 'in'", 0
    err_unexpected_tok  db  "Unexpected token", 0

    ; Debug messages
    msg_node_program    db  "AST: PROGRAM", 10, 0
    msg_node_let        db  "AST: LET statement", 10, 0
    msg_node_fn         db  "AST: FUNCTION definition", 10, 0
    msg_node_if         db  "AST: IF statement", 10, 0
    msg_node_show       db  "AST: SHOW statement", 10, 0
    msg_node_for        db  "AST: FOR loop", 10, 0
    msg_node_while      db  "AST: WHILE loop", 10, 0
    msg_node_loop       db  "AST: LOOP", 10, 0
    msg_node_return     db  "AST: RETURN", 10, 0
    msg_node_binary     db  "AST: BINARY expression", 10, 0
    msg_node_call       db  "AST: FUNCTION CALL", 10, 0
    msg_node_ident      db  "AST: IDENTIFIER", 10, 0
    msg_node_int        db  "AST: INTEGER literal", 10, 0
    msg_node_string     db  "AST: STRING literal", 10, 0
    msg_node_bool       db  "AST: BOOLEAN literal", 10, 0

; ── BSS SECTION ──────────────────────────────────────────────
section .bss

    ; AST node pool — all nodes allocated from here
    node_pool   resb    MAX_NODES * NODE_SIZE

    ; Node allocator pointer
    node_next   resq    1   ; index of next free node

    ; Parser state
    tok_pos     resq    1   ; current position in token array
    tok_total   resq    1   ; total number of tokens
    error_count resq    1   ; number of parse errors

    ; Pointer to token array (set by caller)
    tok_array   resq    1   ; pointer to token array from lexer

    ; Pointer to source buffer (set by caller)
    src_buffer  resq    1   ; pointer to source buffer from lexer

    ; Root of AST
    ast_root    resq    1   ; pointer to root program node

; ── TEXT SECTION ─────────────────────────────────────────────
section .text
    global ink_parse
    global parser_init

; ============================================================
; PARSER_INIT
; Initialises parser state before parsing
; Input: rdi = pointer to token array
;        rsi = total token count
;        rdx = pointer to source buffer
; ============================================================
parser_init:
    push    rbp
    mov     rbp, rsp

    mov     [tok_array],  rdi   ; save token array pointer
    mov     [tok_total],  rsi   ; save token count
    mov     [src_buffer], rdx   ; save source buffer pointer

    ; Reset state
    mov     qword [tok_pos],     0   ; start at first token
    mov     qword [node_next],   0   ; start at first node slot
    mov     qword [error_count], 0   ; no errors yet
    mov     qword [ast_root],    0   ; no AST yet

    pop     rbp
    ret

; ============================================================
; INK_PARSE — main parser entry point
; Parses all tokens and builds the AST
; Returns: rax = pointer to root AST node (0 if error)
; ============================================================
ink_parse:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12

    ; Print parsing message
    mov     rdi, msg_parsing
    call    print_str

    ; Parse the entire program
    call    parse_program
    mov     r12, rax            ; save root node

    ; Check for errors
    cmp     qword [error_count], 0
    jne     .parse_failed

    ; Save root to global
    mov     [ast_root], r12

    ; Print success
    mov     rdi, msg_parse_ok
    call    print_str

    mov     rax, r12            ; return root node

    pop     r12
    pop     rbx
    pop     rbp
    ret

.parse_failed:
    mov     rdi, msg_parse_fail
    call    print_str
    xor     rax, rax            ; return null on failure

    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; PARSE_PROGRAM
; Parses entire INK program — top level
; Returns: rax = pointer to PROGRAM node
;
; Grammar:
;   program = statement*
; ============================================================
parse_program:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13

    ; Allocate PROGRAM node
    mov     rdi, NODE_PROGRAM
    call    alloc_node
    mov     r12, rax            ; r12 = program node
    mov     r13, 0              ; r13 = last statement node

.stmt_loop:
    ; Check if we are at end of file
    call    current_token_type
    cmp     rax, TOKEN_EOF
    je      .done

    ; Parse one statement
    call    parse_statement
    test    rax, rax
    jz      .stmt_loop          ; null = empty/error, keep going

    ; Link statement into program's child list
    cmp     r13, 0
    jne     .link_sibling
    ; First statement — set as left child of program
    mov     [r12 + NODE_LEFT], rax
    mov     r13, rax
    jmp     .stmt_loop

.link_sibling:
    ; Add as next sibling of last statement
    mov     [r13 + NODE_NEXT], rax
    mov     r13, rax
    jmp     .stmt_loop

.done:
    mov     rax, r12

    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; PARSE_STATEMENT
; Parses one INK statement
; Returns: rax = AST node pointer (0 if error/empty)
;
; Grammar:
;   statement = let_stmt
;             | const_stmt
;             | fn_stmt
;             | return_stmt
;             | if_stmt
;             | while_stmt
;             | for_stmt
;             | loop_stmt
;             | show_stmt
;             | use_stmt
;             | type_stmt
;             | expr_stmt
; ============================================================
parse_statement:
    push    rbp
    mov     rbp, rsp
    push    rbx

    ; Look at current token type
    call    current_token_type
    mov     rbx, rax

    cmp     rbx, TOKEN_LET
    je      .parse_let

    cmp     rbx, TOKEN_CONST
    je      .parse_const

    cmp     rbx, TOKEN_FN
    je      .parse_fn

    cmp     rbx, TOKEN_RETURN
    je      .parse_return

    cmp     rbx, TOKEN_IF
    je      .parse_if

    cmp     rbx, TOKEN_WHILE
    je      .parse_while

    cmp     rbx, TOKEN_FOR
    je      .parse_for

    cmp     rbx, TOKEN_LOOP
    je      .parse_loop

    cmp     rbx, TOKEN_BREAK
    je      .parse_break

    cmp     rbx, TOKEN_CONTINUE
    je      .parse_continue

    cmp     rbx, TOKEN_SHOW
    je      .parse_show

    cmp     rbx, TOKEN_USE
    je      .parse_use

    cmp     rbx, TOKEN_TYPE
    je      .parse_type_def

    cmp     rbx, TOKEN_AT
    je      .parse_annotation

    cmp     rbx, TOKEN_EOF
    je      .parse_eof

    ; Default — expression statement (assignment, fn call)
    jmp     .parse_expr_stmt

.parse_let:
    call    parse_let_stmt
    jmp     .done

.parse_const:
    call    parse_const_stmt
    jmp     .done

.parse_fn:
    call    parse_fn_def
    jmp     .done

.parse_return:
    call    parse_return_stmt
    jmp     .done

.parse_if:
    call    parse_if_stmt
    jmp     .done

.parse_while:
    call    parse_while_stmt
    jmp     .done

.parse_for:
    call    parse_for_stmt
    jmp     .done

.parse_loop:
    call    parse_loop_stmt
    jmp     .done

.parse_break:
    call    advance_token       ; consume 'break'
    mov     rdi, NODE_BREAK
    call    alloc_node
    jmp     .done

.parse_continue:
    call    advance_token       ; consume 'continue'
    mov     rdi, NODE_CONTINUE
    call    alloc_node
    jmp     .done

.parse_show:
    call    parse_show_stmt
    jmp     .done

.parse_use:
    call    parse_use_stmt
    jmp     .done

.parse_type_def:
    call    parse_type_def
    jmp     .done

.parse_annotation:
    ; @system, @entry etc — consume and continue
    call    advance_token       ; consume @
    call    advance_token       ; consume annotation name
    call    parse_statement     ; parse what follows
    jmp     .done

.parse_eof:
    xor     rax, rax
    jmp     .done

.parse_expr_stmt:
    call    parse_expression
    jmp     .done

.done:
    pop     rbx
    pop     rbp
    ret

; ============================================================
; PARSE_LET_STMT
; Parses: let name [: type] = expr
; Returns: rax = NODE_LET pointer
; ============================================================
parse_let_stmt:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13

    ; Consume 'let'
    call    advance_token

    ; Allocate LET node
    mov     rdi, NODE_LET
    call    alloc_node
    mov     r12, rax

    ; Save line info
    call    current_token_line
    mov     [r12 + NODE_TLINE], rax

    ; Expect identifier
    call    current_token_type
    cmp     rax, TOKEN_IDENT
    jne     .error_ident

    ; Save identifier token info
    call    current_token_start
    mov     [r12 + NODE_TSTART], rax
    call    current_token_len
    mov     [r12 + NODE_TLEN], rax

    ; Allocate IDENT node for variable name
    mov     rdi, NODE_IDENT
    call    alloc_node
    mov     r13, rax
    ; Get start position and save to ident node
    call    current_token_start
    mov     [r13 + NODE_TSTART], rax
    ; Get length and save to ident node
    call    current_token_len
    mov     [r13 + NODE_TLEN], rax

    ; Set name as left child
    mov     [r12 + NODE_LEFT], r13

    call    advance_token       ; consume identifier

    ; Check for optional type annotation: : type
    call    current_token_type
    cmp     rax, TOKEN_COLON
    jne     .check_equals
    call    advance_token       ; consume ':'
    call    parse_type_expr     ; parse the type
    mov     [r12 + NODE_EXTRA], rax  ; store type in extra
    jmp     .check_equals

.check_equals:
    ; Expect '='
    call    current_token_type
    cmp     rax, TOKEN_EQUALS
    jne     .error_equals
    call    advance_token       ; consume '='

    ; Parse the value expression
    call    parse_expression
    mov     [r12 + NODE_RIGHT], rax  ; value as right child

    mov     rax, r12

    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

.error_ident:
    mov     rdi, err_expect_ident
    call    parse_error
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

.error_equals:
    mov     rdi, err_expect_equals
    call    parse_error
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; PARSE_CONST_STMT
; Parses: const NAME = expr
; ============================================================
parse_const_stmt:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13

    call    advance_token       ; consume 'const'

    mov     rdi, NODE_CONST
    call    alloc_node
    mov     r12, rax

    ; Expect identifier
    call    current_token_type
    cmp     rax, TOKEN_IDENT
    jne     .error

    ; Allocate IDENT node
    mov     rdi, NODE_IDENT
    call    alloc_node
    mov     r13, rax
    call    current_token_start
    mov     [r13 + NODE_TSTART], rax
    call    current_token_len
    mov     [r13 + NODE_TLEN], rax
    mov     [r12 + NODE_LEFT], r13

    call    advance_token       ; consume name

    ; Expect '='
    call    current_token_type
    cmp     rax, TOKEN_EQUALS
    jne     .error

    call    advance_token       ; consume '='

    ; Parse value
    call    parse_expression
    mov     [r12 + NODE_RIGHT], rax

    mov     rax, r12
    pop     r13
    pop     r12
    pop     rbp
    ret

.error:
    call    parse_error_unexpected
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbp
    ret

; ============================================================
; PARSE_FN_DEF
; Parses: fn name(params) [-> type] { body }
; ============================================================
parse_fn_def:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14

    call    advance_token       ; consume 'fn'

    ; Allocate FN_DEF node
    mov     rdi, NODE_FN_DEF
    call    alloc_node
    mov     r12, rax

    ; Expect function name
    call    current_token_type
    cmp     rax, TOKEN_IDENT
    jne     .error_name

    ; Save name
    mov     rdi, NODE_IDENT
    call    alloc_node
    mov     r13, rax
    call    current_token_start
    mov     [r13 + NODE_TSTART], rax
    call    current_token_len
    mov     [r13 + NODE_TLEN], rax
    mov     [r12 + NODE_LEFT], r13  ; name = left child

    call    advance_token       ; consume name

    ; Expect '('
    call    current_token_type
    cmp     rax, TOKEN_LPAREN
    jne     .error_lparen
    call    advance_token       ; consume '('

    ; Parse parameter list
    call    parse_param_list
    mov     [r12 + NODE_EXTRA], rax  ; params = extra

    ; Expect ')'
    call    current_token_type
    cmp     rax, TOKEN_RPAREN
    jne     .error_rparen
    call    advance_token       ; consume ')'

    ; Check for return type: -> type
    call    current_token_type
    cmp     rax, TOKEN_ARROW
    jne     .parse_body
    call    advance_token       ; consume '->'
    call    parse_type_expr     ; parse return type
    mov     [r12 + NODE_TSTART], rax    ; store return-type node on FN_DEF

.parse_body:
    ; Parse function body { ... }
    call    parse_block
    mov     [r12 + NODE_RIGHT], rax  ; body = right child

    mov     rax, r12

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

.error_name:
    mov     rdi, err_expect_ident
    call    parse_error
    xor     rax, rax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

.error_lparen:
    mov     rdi, err_expect_lparen
    call    parse_error
    xor     rax, rax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

.error_rparen:
    mov     rdi, err_expect_rparen
    call    parse_error
    xor     rax, rax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; PARSE_PARAM_LIST
; Parses: param, param, ... (inside parentheses)
; Returns: rax = first PARAM node (linked list)
; ============================================================
parse_param_list:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13

    mov     r12, 0              ; first param
    mov     r13, 0              ; last param

.param_loop:
    ; Check if no more params
    call    current_token_type
    cmp     rax, TOKEN_RPAREN
    je      .done
    cmp     rax, TOKEN_EOF
    je      .done

    ; Parse one parameter: name: type
    call    current_token_type
    cmp     rax, TOKEN_IDENT
    jne     .done

    ; Allocate PARAM node
    mov     rdi, NODE_PARAM
    call    alloc_node
    mov     r14, rax            ; r14 = param node

    ; Save param name via IDENT node
    mov     rdi, NODE_IDENT
    call    alloc_node
    mov     r15, rax            ; r15 = ident node
    call    current_token_start
    mov     [r15 + NODE_TSTART], rax
    call    current_token_len
    mov     [r15 + NODE_TLEN], rax
    mov     [r14 + NODE_LEFT], r15   ; name as left child of param

    call    advance_token       ; consume param name

    ; Check for : type
    call    current_token_type
    cmp     rax, TOKEN_COLON
    jne     .no_type
    call    advance_token       ; consume ':'
    call    parse_type_expr
    mov     [r14 + NODE_RIGHT], rax  ; type as right child

.no_type:
    mov     rax, r14            ; param node

    ; Link into list
    cmp     r12, 0
    jne     .add_to_list
    mov     r12, rax
    mov     r13, rax
    jmp     .check_comma

.add_to_list:
    mov     [r13 + NODE_NEXT], rax
    mov     r13, rax

.check_comma:
    ; Check for comma separator
    call    current_token_type
    cmp     rax, TOKEN_COMMA
    jne     .done
    call    advance_token       ; consume ','
    jmp     .param_loop

.done:
    mov     rax, r12

    pop     r13
    pop     r12
    pop     rbp
    ret

; ============================================================
; PARSE_RETURN_STMT
; Parses: return [expr]
; ============================================================
parse_return_stmt:
    push    rbp
    mov     rbp, rsp
    push    r12

    call    advance_token       ; consume 'return'

    mov     rdi, NODE_RETURN
    call    alloc_node
    mov     r12, rax

    ; Check if there is a return value
    call    current_token_type
    cmp     rax, TOKEN_RBRACE   ; end of block = no value
    je      .no_value
    cmp     rax, TOKEN_EOF
    je      .no_value

    ; Parse return value
    call    parse_expression
    mov     [r12 + NODE_LEFT], rax

.no_value:
    mov     rax, r12

    pop     r12
    pop     rbp
    ret

; ============================================================
; PARSE_IF_STMT
; Parses: if condition { then_block } [else { else_block }]
; ============================================================
parse_if_stmt:
    push    rbp
    mov     rbp, rsp
    push    r12

    call    advance_token       ; consume 'if'

    ; Allocate IF node
    mov     rdi, NODE_IF
    call    alloc_node
    mov     r12, rax

    ; Parse condition
    call    parse_expression
    mov     [r12 + NODE_LEFT], rax   ; condition = left

    ; Parse then block
    call    parse_block
    mov     [r12 + NODE_RIGHT], rax  ; then block = right

    ; Check for else
    call    current_token_type
    cmp     rax, TOKEN_ELSE
    jne     .done
    call    advance_token       ; consume 'else'

    ; Check for else if
    call    current_token_type
    cmp     rax, TOKEN_IF
    je      .else_if

    ; else { block }
    call    parse_block
    mov     [r12 + NODE_EXTRA], rax  ; else block = extra
    jmp     .done

.else_if:
    ; else if — recurse
    call    parse_if_stmt
    mov     [r12 + NODE_EXTRA], rax

.done:
    mov     rax, r12
    pop     r12
    pop     rbp
    ret

; ============================================================
; PARSE_WHILE_STMT
; Parses: while condition { body }
; ============================================================
parse_while_stmt:
    push    rbp
    mov     rbp, rsp
    push    r12

    call    advance_token       ; consume 'while'

    mov     rdi, NODE_WHILE
    call    alloc_node
    mov     r12, rax

    call    parse_expression    ; condition
    mov     [r12 + NODE_LEFT], rax

    call    parse_block         ; body
    mov     [r12 + NODE_RIGHT], rax

    mov     rax, r12
    pop     r12
    pop     rbp
    ret

; ============================================================
; PARSE_FOR_STMT
; Parses: for i in expr { body }
;      or for i in start..end { body }
; ============================================================
parse_for_stmt:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13
    push    r14

    call    advance_token       ; consume 'for'

    mov     rdi, NODE_FOR
    call    alloc_node
    mov     r12, rax

    ; Parse loop variable name
    call    current_token_type
    cmp     rax, TOKEN_IDENT
    jne     .error

    mov     rdi, NODE_IDENT
    call    alloc_node
    mov     r13, rax            ; r13 = ident node
    call    current_token_start
    mov     [r13 + NODE_TSTART], rax
    call    current_token_len
    mov     [r13 + NODE_TLEN], rax
    mov     [r12 + NODE_LEFT], r13   ; variable = left

    call    advance_token       ; consume variable name

    ; Check for comma (for i, j in ...)
    call    current_token_type
    cmp     rax, TOKEN_COMMA
    jne     .expect_in
    call    advance_token       ; consume ','
    ; Parse second variable (simplified — just consume it)
    call    current_token_type
    cmp     rax, TOKEN_IDENT
    jne     .expect_in
    call    advance_token       ; consume second variable name

.expect_in:
    ; Expect 'in'
    call    current_token_type
    cmp     rax, TOKEN_IN
    jne     .error
    call    advance_token       ; consume 'in'

    ; Parse start of range — just a primary/unary expr
    ; We handle .. manually here to avoid consuming {
    call    parse_unary_expr
    mov     r14, rax            ; r14 = start expr

    ; Check for .. range operator
    call    current_token_type
    cmp     rax, TOKEN_DOT_DOT
    jne     .no_range

    call    advance_token       ; consume '..'

    ; Parse end of range
    call    parse_unary_expr
    mov     rbx, rax            ; rbx = end expr

    ; Build range binary node
    mov     rdi, NODE_BINARY
    call    alloc_node
    mov     [rax + NODE_LEFT],  r14
    mov     [rax + NODE_RIGHT], rbx
    mov     qword [rax + NODE_EXTRA], BINOP_RANGE
    mov     [r12 + NODE_EXTRA], rax   ; range = extra
    jmp     .parse_body

.no_range:
    ; No range — just a collection
    mov     [r12 + NODE_EXTRA], r14   ; iterable = extra

.parse_body:
    ; Parse body { ... }
    call    parse_block
    mov     [r12 + NODE_RIGHT], rax   ; body = right

    mov     rax, r12
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    ret

.error:
    call    parse_error_unexpected
    xor     rax, rax
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    ret

; ============================================================
; PARSE_LOOP_STMT
; Parses: loop { body }
; ============================================================
parse_loop_stmt:
    push    rbp
    mov     rbp, rsp
    push    r12

    call    advance_token       ; consume 'loop'

    mov     rdi, NODE_LOOP
    call    alloc_node
    mov     r12, rax

    call    parse_block
    mov     [r12 + NODE_LEFT], rax

    mov     rax, r12
    pop     r12
    pop     rbp
    ret

; ============================================================
; PARSE_SHOW_STMT
; Parses: show expr
; ============================================================
parse_show_stmt:
    push    rbp
    mov     rbp, rsp
    push    r12

    call    advance_token       ; consume 'show'

    mov     rdi, NODE_SHOW
    call    alloc_node
    mov     r12, rax

    call    parse_expression
    mov     [r12 + NODE_LEFT], rax

    mov     rax, r12
    pop     r12
    pop     rbp
    ret

; ============================================================
; PARSE_USE_STMT
; Parses: use module
; ============================================================
parse_use_stmt:
    push    rbp
    mov     rbp, rsp
    push    r12

    call    advance_token       ; consume 'use'

    mov     rdi, NODE_USE
    call    alloc_node
    mov     r12, rax

    ; Save module name
    call    current_token_start
    mov     [r12 + NODE_TSTART], rax
    call    current_token_len
    mov     [r12 + NODE_TLEN], rax

    call    advance_token       ; consume module name

    ; Handle dotted paths: use web.http
.dot_loop:
    call    current_token_type
    cmp     rax, TOKEN_DOT
    jne     .done
    call    advance_token       ; consume '.'
    call    advance_token       ; consume next part
    jmp     .dot_loop

.done:
    mov     rax, r12
    pop     r12
    pop     rbp
    ret

; ============================================================
; PARSE_TYPE_DEF
; Parses: type Name { field: Type, ... }
; ============================================================
parse_type_def:
    push    rbp
    mov     rbp, rsp
    push    r12

    call    advance_token       ; consume 'type'

    mov     rdi, NODE_TYPE_DEF
    call    alloc_node
    mov     r12, rax

    ; Type name
    call    current_token_start
    mov     [r12 + NODE_TSTART], rax
    call    current_token_len
    mov     [r12 + NODE_TLEN], rax
    call    advance_token       ; consume type name

    ; Parse body { fields }
    call    parse_block
    mov     [r12 + NODE_LEFT], rax

    mov     rax, r12
    pop     r12
    pop     rbp
    ret

; ============================================================
; PARSE_BLOCK
; Parses: { statement* }
; Returns: rax = NODE_BLOCK pointer
; ============================================================
parse_block:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13

    ; Expect '{'
    call    current_token_type
    cmp     rax, TOKEN_LBRACE
    jne     .error
    call    advance_token       ; consume '{'

    ; Allocate BLOCK node
    mov     rdi, NODE_BLOCK
    call    alloc_node
    mov     r12, rax
    mov     r13, 0              ; last statement

.block_loop:
    ; Check for closing '}'
    call    current_token_type
    cmp     rax, TOKEN_RBRACE
    je      .block_done
    cmp     rax, TOKEN_EOF
    je      .block_done

    ; Parse statement inside block
    call    parse_statement
    test    rax, rax
    jz      .block_loop

    ; Link statement
    cmp     r13, 0
    jne     .link_stmt
    mov     [r12 + NODE_LEFT], rax  ; first stmt = left child
    mov     r13, rax
    jmp     .block_loop

.link_stmt:
    mov     [r13 + NODE_NEXT], rax
    mov     r13, rax
    jmp     .block_loop

.block_done:
    ; Expect '}'
    call    current_token_type
    cmp     rax, TOKEN_RBRACE
    jne     .error
    call    advance_token       ; consume '}'

    mov     rax, r12

    pop     r13
    pop     r12
    pop     rbp
    ret

.error:
    mov     rdi, err_expect_lbrace
    call    parse_error
    xor     rax, rax
    pop     r13
    pop     r12
    pop     rbp
    ret

; ============================================================
; PARSE_EXPRESSION
; Parses an expression with operator precedence
; Also handles assignment: ident = expr
; ============================================================
parse_expression:
    push    rbp
    mov     rbp, rsp
    push    r12

    call    parse_or_expr
    mov     r12, rax            ; r12 = left side

    ; Check for assignment: if next token is = and left is IDENT
    call    current_token_type
    cmp     rax, TOKEN_EQUALS
    jne     .no_assign

    ; Check left side is an identifier OR an index (arr[i])
    test    r12, r12
    jz      .no_assign
    mov     rax, [r12 + NODE_TYPE]
    cmp     rax, NODE_IDENT
    je      .is_target
    cmp     rax, NODE_INDEX
    je      .is_target
    jmp     .no_assign
.is_target:

    ; It is an assignment!
    call    advance_token       ; consume '='

    ; Parse right side
    call    parse_expression    ; right side (recursive)
    mov     rbx, rax

    ; Build ASSIGN node
    mov     rdi, NODE_ASSIGN
    call    alloc_node
    mov     [rax + NODE_LEFT],  r12   ; variable
    mov     [rax + NODE_RIGHT], rbx   ; value
    mov     r12, rax

.no_assign:
    mov     rax, r12
    pop     r12
    pop     rbp
    ret

; ── Level 1: OR ──────────────────────────────────────────────
parse_or_expr:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13

    call    parse_and_expr
    mov     r12, rax            ; r12 = left side

.or_loop:
    call    current_token_type
    cmp     rax, TOKEN_OR
    jne     .done

    call    advance_token       ; consume 'or'

    ; Check for error handler: expr or { ... }
    call    current_token_type
    cmp     rax, TOKEN_LBRACE
    jne     .or_binary

    ; Error handler: expr or { block }
    mov     rdi, NODE_ERROR_HANDLE
    call    alloc_node
    mov     r13, rax            ; r13 = error handle node
    mov     [r13 + NODE_LEFT], r12   ; left = original expr
    call    parse_block
    mov     [r13 + NODE_RIGHT], rax  ; right = error block
    mov     r12, r13
    jmp     .done

.or_binary:
    ; Regular binary or
    call    parse_and_expr
    mov     rbx, rax            ; rbx = right side

    mov     rdi, NODE_BINARY
    call    alloc_node
    mov     [rax + NODE_LEFT],  r12
    mov     [rax + NODE_RIGHT], rbx
    mov     qword [rax + NODE_EXTRA], BINOP_OR
    mov     r12, rax
    jmp     .or_loop

.done:
    mov     rax, r12
    pop     r13
    pop     r12
    pop     rbp
    ret

; ── Level 2: AND ─────────────────────────────────────────────
parse_and_expr:
    push    rbp
    mov     rbp, rsp
    push    r12

    call    parse_compare_expr
    mov     r12, rax

.and_loop:
    call    current_token_type
    cmp     rax, TOKEN_AND
    jne     .done

    call    advance_token

    push    r12
    call    parse_compare_expr
    mov     rbx, rax
    pop     r12

    mov     rdi, NODE_BINARY
    call    alloc_node
    mov     [rax + NODE_LEFT],  r12
    mov     [rax + NODE_RIGHT], rbx
    mov     qword [rax + NODE_EXTRA], BINOP_AND
    mov     r12, rax
    jmp     .and_loop

.done:
    mov     rax, r12
    pop     r12
    pop     rbp
    ret

; ── Level 3: Comparison ──────────────────────────────────────
parse_compare_expr:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13
    push    r14

    call    parse_add_expr
    mov     r12, rax            ; r12 = left side

.cmp_loop:
    call    current_token_type
    mov     r13, rax            ; r13 = operator token type

    cmp     r13, TOKEN_EQ_EQ    ; ==
    je      .do_compare
    cmp     r13, TOKEN_BANG_EQ  ; !=
    je      .do_compare
    cmp     r13, TOKEN_LT       ; <
    je      .do_compare
    cmp     r13, TOKEN_GT       ; >
    je      .do_compare
    cmp     r13, TOKEN_LT_EQ    ; <=
    je      .do_compare
    cmp     r13, TOKEN_GT_EQ    ; >=
    je      .do_compare
    jmp     .done

.do_compare:
    ; Convert token type to binop constant BEFORE advancing
    mov     rax, r13
    call    token_to_binop
    mov     r14, rax            ; r14 = binop constant

    call    advance_token       ; consume operator

    ; Parse right side
    call    parse_add_expr
    mov     rbx, rax            ; rbx = right side node

    ; Build binary node
    mov     rdi, NODE_BINARY
    call    alloc_node
    mov     [rax + NODE_LEFT],  r12   ; left expression
    mov     [rax + NODE_RIGHT], rbx   ; right expression
    mov     [rax + NODE_EXTRA], r14   ; operator
    mov     r12, rax
    jmp     .cmp_loop

.done:
    mov     rax, r12
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    ret

; ── Level 4: Addition/Subtraction ────────────────────────────
parse_add_expr:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13

    call    parse_mul_expr
    mov     r12, rax

.add_loop:
    call    current_token_type

    cmp     rax, TOKEN_PLUS
    je      .do_add
    cmp     rax, TOKEN_MINUS
    je      .do_sub
    jmp     .done

.do_add:
    call    advance_token
    push    r12
    call    parse_mul_expr
    mov     rbx, rax
    pop     r12

    mov     rdi, NODE_BINARY
    call    alloc_node
    mov     [rax + NODE_LEFT],  r12
    mov     [rax + NODE_RIGHT], rbx
    mov     qword [rax + NODE_EXTRA], BINOP_ADD
    mov     r12, rax
    jmp     .add_loop

.do_sub:
    call    advance_token
    push    r12
    call    parse_mul_expr
    mov     rbx, rax
    pop     r12

    mov     rdi, NODE_BINARY
    call    alloc_node
    mov     [rax + NODE_LEFT],  r12
    mov     [rax + NODE_RIGHT], rbx
    mov     qword [rax + NODE_EXTRA], BINOP_SUB
    mov     r12, rax
    jmp     .add_loop

.done:
    mov     rax, r12
    pop     r13
    pop     r12
    pop     rbp
    ret

; ── Level 5: Multiply/Divide/Modulo ──────────────────────────
parse_mul_expr:
    push    rbp
    mov     rbp, rsp
    push    r12

    call    parse_unary_expr
    mov     r12, rax

.mul_loop:
    call    current_token_type

    cmp     rax, TOKEN_STAR
    je      .do_mul
    cmp     rax, TOKEN_SLASH
    je      .do_div
    cmp     rax, TOKEN_PERCENT
    je      .do_mod
    jmp     .done

.do_mul:
    call    advance_token
    push    r12
    call    parse_unary_expr
    mov     rbx, rax
    pop     r12
    mov     rdi, NODE_BINARY
    call    alloc_node
    mov     [rax + NODE_LEFT],  r12
    mov     [rax + NODE_RIGHT], rbx
    mov     qword [rax + NODE_EXTRA], BINOP_MUL
    mov     r12, rax
    jmp     .mul_loop

.do_div:
    call    advance_token
    push    r12
    call    parse_unary_expr
    mov     rbx, rax
    pop     r12
    mov     rdi, NODE_BINARY
    call    alloc_node
    mov     [rax + NODE_LEFT],  r12
    mov     [rax + NODE_RIGHT], rbx
    mov     qword [rax + NODE_EXTRA], BINOP_DIV
    mov     r12, rax
    jmp     .mul_loop

.do_mod:
    call    advance_token
    push    r12
    call    parse_unary_expr
    mov     rbx, rax
    pop     r12
    mov     rdi, NODE_BINARY
    call    alloc_node
    mov     [rax + NODE_LEFT],  r12
    mov     [rax + NODE_RIGHT], rbx
    mov     qword [rax + NODE_EXTRA], BINOP_MOD
    mov     r12, rax
    jmp     .mul_loop

.done:
    mov     rax, r12
    pop     r12
    pop     rbp
    ret

; ── Level 6: Unary operators ─────────────────────────────────
parse_unary_expr:
    push    rbp
    mov     rbp, rsp
    push    r12

    call    current_token_type

    cmp     rax, TOKEN_NOT
    je      .do_not

    cmp     rax, TOKEN_MINUS
    je      .do_neg

    ; No unary op — go to primary
    call    parse_postfix_expr
    jmp     .done

.do_not:
    call    advance_token
    call    parse_unary_expr
    mov     rdi, NODE_UNARY
    push    rax
    call    alloc_node
    pop     rbx
    mov     [rax + NODE_LEFT],  rbx
    mov     qword [rax + NODE_EXTRA], TOKEN_NOT
    jmp     .done

.do_neg:
    call    advance_token
    call    parse_unary_expr
    mov     rdi, NODE_UNARY
    push    rax
    call    alloc_node
    pop     rbx
    mov     [rax + NODE_LEFT],  rbx
    mov     qword [rax + NODE_EXTRA], TOKEN_MINUS
    jmp     .done

.done:
    pop     r12
    pop     rbp
    ret

; ── Level 7: Postfix — field access, index, function call ───
parse_postfix_expr:
    push    rbp
    mov     rbp, rsp
    push    r12

    call    parse_primary_expr
    mov     r12, rax

.postfix_loop:
    call    current_token_type

    cmp     rax, TOKEN_DOT
    je      .do_field_access

    cmp     rax, TOKEN_LBRACKET
    je      .do_index

    cmp     rax, TOKEN_LPAREN
    je      .do_call

    cmp     rax, TOKEN_QUESTION
    je      .do_optional

    jmp     .done

.do_field_access:
    call    advance_token       ; consume '.'
    mov     rdi, NODE_FIELD_ACCESS
    call    alloc_node
    mov     [rax + NODE_LEFT], r12
    push    rax
    ; Parse field name
    call    current_token_start
    pop     rbx
    mov     [rbx + NODE_TSTART], rax
    call    current_token_len
    mov     [rbx + NODE_TLEN], rax
    call    advance_token       ; consume field name
    mov     r12, rbx
    jmp     .postfix_loop

.do_index:
    call    advance_token       ; consume '['
    mov     rdi, NODE_INDEX
    call    alloc_node
    mov     [rax + NODE_LEFT], r12
    push    rax
    call    parse_expression
    pop     rbx
    mov     [rbx + NODE_RIGHT], rax
    ; Consume ']'
    call    current_token_type
    cmp     rax, TOKEN_RBRACKET
    jne     .error_rbracket
    call    advance_token
    mov     r12, rbx
    jmp     .postfix_loop

.do_call:
    call    advance_token       ; consume '('
    mov     rdi, NODE_FN_CALL
    call    alloc_node
    mov     [rax + NODE_LEFT], r12   ; function = left
    push    rax
    call    parse_arg_list      ; parse arguments
    pop     rbx
    mov     [rbx + NODE_RIGHT], rax  ; args = right
    ; Consume ')'
    call    current_token_type
    cmp     rax, TOKEN_RPAREN
    jne     .error_rparen
    call    advance_token
    mov     r12, rbx
    jmp     .postfix_loop

.do_optional:
    call    advance_token       ; consume '?'
    mov     rdi, NODE_OPTIONAL_CHECK
    call    alloc_node
    mov     [rax + NODE_LEFT], r12
    mov     r12, rax
    jmp     .postfix_loop

.error_rbracket:
    mov     rdi, err_expect_rbracket
    call    parse_error
    jmp     .done

.error_rparen:
    mov     rdi, err_expect_rparen
    call    parse_error
    jmp     .done

.done:
    mov     rax, r12
    pop     r12
    pop     rbp
    ret

; ── Primary expressions ───────────────────────────────────────
parse_primary_expr:
    push    rbp
    mov     rbp, rsp
    push    rbx

    call    current_token_type
    mov     rbx, rax

    ; Integer literal
    cmp     rbx, TOKEN_INT
    je      .parse_int

    ; Float literal
    cmp     rbx, TOKEN_FLOAT
    je      .parse_float

    ; String literal
    cmp     rbx, TOKEN_STRING
    je      .parse_string

    ; Char literal
    cmp     rbx, TOKEN_CHAR
    je      .parse_char

    ; Boolean true
    cmp     rbx, TOKEN_TRUE
    je      .parse_true

    ; Boolean false
    cmp     rbx, TOKEN_FALSE
    je      .parse_false

    ; None
    cmp     rbx, TOKEN_NONE
    je      .parse_none

    ; Identifier
    cmp     rbx, TOKEN_IDENT
    je      .parse_ident

    ; Grouped expression: ( expr )
    cmp     rbx, TOKEN_LPAREN
    je      .parse_grouped

    ; Array literal: [1, 2, 3]
    cmp     rbx, TOKEN_LBRACKET
    je      .parse_array

    ; Map literal: {"k": v, ...}
    cmp     rbx, TOKEN_LBRACE
    je      .parse_map

    ; Error
    jmp     .parse_error

.parse_int:
    mov     rdi, NODE_INT_LIT
    call    alloc_node
    mov     rbx, rax            ; save node pointer
    call    current_token_start
    mov     [rbx + NODE_TSTART], rax
    call    current_token_len
    mov     [rbx + NODE_TLEN], rax
    call    advance_token
    mov     rax, rbx
    jmp     .done

.parse_float:
    mov     rdi, NODE_FLOAT_LIT
    call    alloc_node
    mov     rbx, rax
    call    current_token_start
    mov     [rbx + NODE_TSTART], rax
    call    current_token_len
    mov     [rbx + NODE_TLEN], rax
    call    advance_token
    mov     rax, rbx
    jmp     .done

.parse_string:
    mov     rdi, NODE_STRING_LIT
    call    alloc_node
    mov     rbx, rax            ; save node
    call    current_token_start
    mov     [rbx + NODE_TSTART], rax
    call    current_token_len
    mov     [rbx + NODE_TLEN], rax
    call    advance_token
    mov     rax, rbx
    jmp     .done

.parse_char:
    mov     rdi, NODE_CHAR_LIT
    call    alloc_node
    push    rax
    call    current_token_start
    pop     rbx
    mov     [rbx + NODE_TSTART], rax
    call    advance_token
    mov     rax, rbx
    jmp     .done

.parse_true:
    mov     rdi, NODE_BOOL_LIT
    call    alloc_node
    mov     qword [rax + NODE_EXTRA], 1   ; 1 = true
    call    advance_token
    jmp     .done

.parse_false:
    mov     rdi, NODE_BOOL_LIT
    call    alloc_node
    mov     qword [rax + NODE_EXTRA], 0   ; 0 = false
    call    advance_token
    jmp     .done

.parse_none:
    mov     rdi, NODE_NONE_LIT
    call    alloc_node
    call    advance_token
    jmp     .done

.parse_ident:
    mov     rdi, NODE_IDENT
    call    alloc_node
    mov     rbx, rax            ; save node
    call    current_token_start
    mov     [rbx + NODE_TSTART], rax
    call    current_token_len
    mov     [rbx + NODE_TLEN], rax
    call    current_token_line
    mov     [rbx + NODE_TLINE], rax
    call    advance_token
    mov     rax, rbx
    jmp     .done

.parse_grouped:
    call    advance_token       ; consume '('
    call    parse_expression
    push    rax
    call    current_token_type
    cmp     rax, TOKEN_RPAREN
    jne     .error_rparen2
    call    advance_token       ; consume ')'
    pop     rax
    jmp     .done

.error_rparen2:
    pop     rax
    mov     rdi, err_expect_rparen
    call    parse_error
    jmp     .done

.parse_array:
    call    advance_token       ; consume '['
    mov     rdi, NODE_ARRAY_LIT
    call    alloc_node
    push    rax
    call    parse_arg_list      ; reuse arg list parser
    pop     rbx
    mov     [rbx + NODE_LEFT], rax
    call    current_token_type
    cmp     rax, TOKEN_RBRACKET
    jne     .error_rbracket2
    call    advance_token       ; consume ']'
    mov     rax, rbx
    jmp     .done

.error_rbracket2:
    mov     rdi, err_expect_rbracket
    call    parse_error
    xor     rax, rax
    jmp     .done

.parse_map:
    call    advance_token           ; consume '{'
    mov     rdi, NODE_MAP_LIT
    call    alloc_node
    mov     r12, rax                ; r12 = map node
    xor     r13, r13                ; r13 = last entry (for chaining)

    ; empty map?
    call    current_token_type
    cmp     rax, TOKEN_RBRACE
    je      .map_close

.map_entry_loop:
    ; key must be a string literal
    call    current_token_type
    cmp     rax, TOKEN_STRING
    jne     .map_err

    ; build entry node: LEFT=key IDENT-ish, RIGHT=value
    push    r12
    push    r13
    mov     rdi, NODE_MAP_LIT       ; reuse type tag for entry (distinguished by parent)
    call    alloc_node
    mov     rbx, rax                ; rbx = entry node
    ; store key text span on entry (TSTART/TLEN)
    call    current_token_start
    mov     [rbx + NODE_TSTART], rax
    call    current_token_len
    mov     [rbx + NODE_TLEN], rax
    call    advance_token           ; consume key string

    ; expect ':'
    call    current_token_type
    cmp     rax, TOKEN_COLON
    jne     .map_err_pop
    call    advance_token           ; consume ':'

    ; parse value expression
    call    parse_expression
    mov     [rbx + NODE_RIGHT], rax ; value

    pop     r13
    pop     r12
    ; chain entry into map
    test    r13, r13
    jnz     .map_chain
    mov     [r12 + NODE_LEFT], rbx  ; first entry
    jmp     .map_chained
.map_chain:
    mov     [r13 + NODE_NEXT], rbx
.map_chained:
    mov     r13, rbx

    ; comma → more entries
    call    current_token_type
    cmp     rax, TOKEN_COMMA
    jne     .map_close
    call    advance_token           ; consume ','
    jmp     .map_entry_loop

.map_close:
    call    current_token_type
    cmp     rax, TOKEN_RBRACE
    jne     .map_err
    call    advance_token           ; consume '}'
    mov     rax, r12
    jmp     .done

.map_err_pop:
    pop     r13
    pop     r12
.map_err:
    mov     rdi, err_expect_expr
    call    parse_error
    xor     rax, rax
    jmp     .done

.parse_error:
    mov     rdi, err_expect_expr
    call    parse_error
    xor     rax, rax

.done:
    pop     rbx
    pop     rbp
    ret

; ============================================================
; PARSE_ARG_LIST
; Parses comma-separated argument list
; Returns: first arg node (linked list)
; ============================================================
parse_arg_list:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13

    mov     r12, 0
    mov     r13, 0

.arg_loop:
    call    current_token_type
    cmp     rax, TOKEN_RPAREN
    je      .done
    cmp     rax, TOKEN_RBRACKET
    je      .done
    cmp     rax, TOKEN_EOF
    je      .done

    call    parse_expression
    test    rax, rax
    jz      .done

    cmp     r12, 0
    jne     .link_arg
    mov     r12, rax
    mov     r13, rax
    jmp     .check_comma

.link_arg:
    mov     [r13 + NODE_NEXT], rax
    mov     r13, rax

.check_comma:
    call    current_token_type
    cmp     rax, TOKEN_COMMA
    jne     .done
    call    advance_token       ; consume ','
    jmp     .arg_loop

.done:
    mov     rax, r12
    pop     r13
    pop     r12
    pop     rbp
    ret

; ============================================================
; PARSE_TYPE_EXPR
; Parses a type expression: int, text, bool, User, list[T]
; Returns: rax = type node
; ============================================================
parse_type_expr:
    push    rbp
    mov     rbp, rsp
    push    r12

    ; Just consume the type name for now
    mov     rdi, NODE_IDENT
    call    alloc_node
    mov     r12, rax

    call    current_token_start
    mov     [r12 + NODE_TSTART], rax
    call    current_token_len
    mov     [r12 + NODE_TLEN], rax
    call    advance_token       ; consume type name

    ; Check for generic: list[T]
    call    current_token_type
    cmp     rax, TOKEN_LBRACKET
    jne     .done
    call    advance_token       ; consume '['
    call    advance_token       ; consume type parameter (simplified)
    call    current_token_type
    cmp     rax, TOKEN_RBRACKET
    jne     .done
    call    advance_token       ; consume ']'

.done:
    mov     rax, r12
    pop     r12
    pop     rbp
    ret

; ============================================================
; NODE ALLOCATOR
; Input: rdi = node type
; Returns: rax = pointer to new zeroed node (0 if overflow)
; ============================================================
alloc_node:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12

    mov     r12, rdi            ; save node type

    ; Bounds check — do not overflow node pool
    mov     rbx, [node_next]
    cmp     rbx, MAX_NODES - 1
    jge     .overflow

    inc     qword [node_next]   ; advance allocator

    ; Calculate pointer: node_pool + (index * NODE_SIZE)
    mov     rax, rbx
    mov     rcx, NODE_SIZE
    mul     rcx
    lea     rax, [node_pool + rax]

    ; Zero the node (64 bytes = 8 qwords)
    mov     qword [rax + 0],  0
    mov     qword [rax + 8],  0
    mov     qword [rax + 16], 0
    mov     qword [rax + 24], 0
    mov     qword [rax + 32], 0
    mov     qword [rax + 40], 0
    mov     qword [rax + 48], 0
    mov     qword [rax + 56], 0

    ; Set node type
    mov     [rax + NODE_TYPE], r12

    pop     r12
    pop     rbx
    pop     rbp
    ret

.overflow:
    xor     rax, rax            ; return null on overflow
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; TOKEN ACCESS HELPERS
; All return values in rax
; ============================================================

; Get current token type
current_token_type:
    push    rbx
    mov     rax, [tok_pos]
    mov     rcx, TOKEN_SIZE
    mul     rcx
    mov     rbx, [tok_array]
    mov     rax, [rbx + rax + TOK_TYPE]
    pop     rbx
    ret

; Get current token start position
current_token_start:
    push    rbx
    mov     rax, [tok_pos]
    mov     rcx, TOKEN_SIZE
    mul     rcx
    mov     rbx, [tok_array]
    mov     rax, [rbx + rax + TOK_START]
    pop     rbx
    ret

; Get current token length
current_token_len:
    push    rbx
    mov     rax, [tok_pos]
    mov     rcx, TOKEN_SIZE
    mul     rcx
    mov     rbx, [tok_array]
    mov     rax, [rbx + rax + TOK_LEN]
    pop     rbx
    ret

; Get current token line number
current_token_line:
    push    rbx
    mov     rax, [tok_pos]
    mov     rcx, TOKEN_SIZE
    mul     rcx                 ; rax = offset into token array
    mov     rbx, [tok_array]
    mov     rax, [rbx + rax + TOK_LINE]  ; TOK_LINE = 24
    pop     rbx
    ret

; Advance to next token
advance_token:
    inc     qword [tok_pos]
    ret

; ============================================================
; TOKEN_TO_BINOP
; Converts token type to binary operator constant
; Input: rax = token type
; Returns: rax = BINOP constant
; ============================================================
token_to_binop:
    cmp     rax, TOKEN_PLUS
    je      .add
    cmp     rax, TOKEN_MINUS
    je      .sub
    cmp     rax, TOKEN_STAR
    je      .mul
    cmp     rax, TOKEN_SLASH
    je      .div
    cmp     rax, TOKEN_PERCENT
    je      .mod
    cmp     rax, TOKEN_EQ_EQ
    je      .eq
    cmp     rax, TOKEN_BANG_EQ
    je      .neq
    cmp     rax, TOKEN_LT
    je      .lt
    cmp     rax, TOKEN_GT
    je      .gt
    cmp     rax, TOKEN_LT_EQ
    je      .lte
    cmp     rax, TOKEN_GT_EQ
    je      .gte
    cmp     rax, TOKEN_DOT_DOT
    je      .range
    xor     rax, rax
    ret
.add:   mov rax, BINOP_ADD
    ret
.sub:   mov rax, BINOP_SUB
    ret
.mul:   mov rax, BINOP_MUL
    ret
.div:   mov rax, BINOP_DIV
    ret
.mod:   mov rax, BINOP_MOD
    ret
.eq:    mov rax, BINOP_EQ
    ret
.neq:   mov rax, BINOP_NEQ
    ret
.lt:    mov rax, BINOP_LT
    ret
.gt:    mov rax, BINOP_GT
    ret
.lte:   mov rax, BINOP_LTE
    ret
.gte:   mov rax, BINOP_GTE
    ret
.range: mov rax, BINOP_RANGE
    ret

; ============================================================
; ERROR HANDLING
; ============================================================

; Print parse error with message
; Input: rdi = error message string pointer
parse_error:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    rdi                 ; save message

    ; Increment error count
    inc     qword [error_count]

    ; Print: [INK ERROR] Line X, Col Y: message
    mov     rdi, err_prefix
    call    print_str

    ; Print line number
    call    current_token_line
    mov     rdi, rax
    call    print_number

    mov     rdi, err_col_end
    call    print_str

    ; Print error message
    pop     rdi
    call    print_str

    mov     rdi, err_newline
    call    print_str

    ; Synchronise — skip tokens until safe point
    call    sync_parser

    pop     rbx
    pop     rbp
    ret

parse_error_unexpected:
    mov     rdi, err_unexpected_tok
    call    parse_error
    ret

; Skip tokens to find a safe synchronisation point
sync_parser:
    push    rbp
    mov     rbp, rsp

.sync_loop:
    call    current_token_type
    cmp     rax, TOKEN_EOF
    je      .sync_done
    cmp     rax, TOKEN_RBRACE   ; end of block
    je      .sync_done
    cmp     rax, TOKEN_LET      ; start of new statement
    je      .sync_done
    cmp     rax, TOKEN_FN
    je      .sync_done
    cmp     rax, TOKEN_IF
    je      .sync_done
    cmp     rax, TOKEN_FOR
    je      .sync_done
    cmp     rax, TOKEN_WHILE
    je      .sync_done
    cmp     rax, TOKEN_RETURN
    je      .sync_done
    call    advance_token
    jmp     .sync_loop

.sync_done:
    pop     rbp
    ret

; ============================================================
; UTILITY FUNCTIONS
; ============================================================

; Print null-terminated string
; Input: rdi = string pointer
print_str:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12

    mov     r12, rdi

    ; Calculate length
    xor     rbx, rbx
.len_loop:
    cmp     byte [r12 + rbx], 0
    je      .len_done
    inc     rbx
    jmp     .len_loop
.len_done:

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

; Print integer in decimal
; Input: rdi = integer value
print_number:
    push    rbp
    mov     rbp, rsp
    push    rbx

    mov     rax, rdi
    test    rax, rax
    jnz     .not_zero

    ; Print "0"
    push    word 0x0030
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT
    lea     rsi, [rsp]
    mov     rdx, 1
    syscall
    add     rsp, 2
    jmp     .done

.not_zero:
    ; Convert to decimal string
    sub     rsp, 24             ; buffer on stack
    lea     rbx, [rsp + 23]
    mov     byte [rbx], 0
    dec     rbx

.convert_loop:
    test    rax, rax
    jz      .print_num

    xor     rdx, rdx
    mov     rcx, 10
    div     rcx                 ; rax = quotient, rdx = remainder
    add     dl, '0'
    mov     [rbx], dl
    dec     rbx
    jmp     .convert_loop

.print_num:
    inc     rbx
    ; Calculate length
    lea     rcx, [rsp + 23]
    sub     rcx, rbx

    mov     rax, SYS_WRITE
    mov     rdi, STDOUT
    mov     rsi, rbx
    mov     rdx, rcx
    syscall

    add     rsp, 24

.done:
    pop     rbx
    pop     rbp
    ret
