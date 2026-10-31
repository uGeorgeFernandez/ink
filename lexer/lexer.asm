; ============================================================
; INK Programming Language — Lexer
; File: lexer/lexer.asm
; Architecture: x86-64 Assembly (NASM)
;
; The Lexer is the FIRST component of the INK compiler.
; It reads your .in source file character by character
; and groups characters into meaningful TOKENS.
;
; Example:
;   Source code:   show "Jai Hind!"
;   Tokens:        [SHOW] [STRING:"Jai Hind!"] [EOF]
;
;   Source code:   let age = 25
;   Tokens:        [LET] [IDENT:"age"] [EQUALS] [INT:25] [EOF]
;
; INK — Write the Future
; Created by: IndianBrand Technology, Hyderabad, India
; Language: 100% x86-64 Assembly — no C, no Python, no credit to anyone
; Jai Hind! 🇮🇳
; ============================================================

; ── SYSTEM CALL NUMBERS (Linux x86-64) ──────────────────────
; These are Linux kernel system calls
; We call the OS directly — no standard library needed
SYS_READ    equ 0       ; read from file
SYS_WRITE   equ 1       ; write to file
SYS_OPEN    equ 2       ; open a file
SYS_CLOSE   equ 3       ; close a file
SYS_EXIT    equ 60      ; exit program

; ── FILE FLAGS ───────────────────────────────────────────────
O_RDONLY    equ 0       ; open file read-only

; ── FILE DESCRIPTORS ─────────────────────────────────────────
STDOUT      equ 1       ; standard output (screen)
STDERR      equ 2       ; standard error (screen)

; ── TOKEN TYPES ──────────────────────────────────────────────
; Every piece of INK source code is one of these token types
TOKEN_EOF       equ 0   ; end of file — no more tokens
TOKEN_SHOW      equ 1   ; keyword: show
TOKEN_LET       equ 2   ; keyword: let
TOKEN_CONST     equ 3   ; keyword: const
TOKEN_FN        equ 4   ; keyword: fn
TOKEN_RETURN    equ 5   ; keyword: return
TOKEN_IF        equ 6   ; keyword: if
TOKEN_ELSE      equ 7   ; keyword: else
TOKEN_FOR       equ 8   ; keyword: for
TOKEN_WHILE     equ 9   ; keyword: while
TOKEN_LOOP      equ 10  ; keyword: loop
TOKEN_BREAK     equ 11  ; keyword: break
TOKEN_CONTINUE  equ 12  ; keyword: continue
TOKEN_MATCH     equ 13  ; keyword: match
TOKEN_TYPE      equ 14  ; keyword: type
TOKEN_PUB       equ 15  ; keyword: pub
TOKEN_USE       equ 16  ; keyword: use
TOKEN_IN        equ 17  ; keyword: in
TOKEN_OR        equ 18  ; keyword: or
TOKEN_AND       equ 19  ; keyword: and
TOKEN_NOT       equ 20  ; keyword: not
TOKEN_TRUE      equ 21  ; keyword: true
TOKEN_FALSE     equ 22  ; keyword: false
TOKEN_NONE      equ 23  ; keyword: none
TOKEN_EXISTS    equ 24  ; keyword: exists
TOKEN_IDENT     equ 25  ; identifier: variable/function name
TOKEN_INT       equ 26  ; integer number: 42, 100, 0
TOKEN_FLOAT     equ 27  ; float number: 3.14, 99.99
TOKEN_STRING    equ 28  ; string literal: "Hello India"
TOKEN_CHAR      equ 29  ; char literal: 'A'
TOKEN_PLUS      equ 30  ; operator: +
TOKEN_MINUS     equ 31  ; operator: -
TOKEN_STAR      equ 32  ; operator: *
TOKEN_SLASH     equ 33  ; operator: /
TOKEN_PERCENT   equ 34  ; operator: %
TOKEN_EQUALS    equ 35  ; operator: =
TOKEN_EQ_EQ     equ 36  ; operator: ==
TOKEN_BANG_EQ   equ 37  ; operator: !=
TOKEN_LT        equ 38  ; operator: <
TOKEN_GT        equ 39  ; operator: >
TOKEN_LT_EQ     equ 40  ; operator: <=
TOKEN_GT_EQ     equ 41  ; operator: >=
TOKEN_ARROW     equ 42  ; operator: ->
TOKEN_FAT_ARROW equ 43  ; operator: =>
TOKEN_LPAREN    equ 44  ; symbol: (
TOKEN_RPAREN    equ 45  ; symbol: )
TOKEN_LBRACE    equ 46  ; symbol: {
TOKEN_RBRACE    equ 47  ; symbol: }
TOKEN_LBRACKET  equ 48  ; symbol: [
TOKEN_RBRACKET  equ 49  ; symbol: ]
TOKEN_COLON     equ 50  ; symbol: :
TOKEN_SEMICOLON equ 51  ; symbol: ;
TOKEN_COMMA     equ 52  ; symbol: ,
TOKEN_DOT       equ 53  ; symbol: .
TOKEN_DOT_DOT   equ 54  ; symbol: ..
TOKEN_QUESTION  equ 55  ; symbol: ?
TOKEN_BANG      equ 56  ; symbol: !
TOKEN_PIPE      equ 57  ; symbol: |
TOKEN_AT        equ 58  ; symbol: @
TOKEN_HASH      equ 59  ; symbol: #
TOKEN_NEWLINE   equ 60  ; newline character
TOKEN_ERROR     equ 99  ; lexer error — unknown character

; ── TOKEN STRUCTURE ──────────────────────────────────────────
; Each token is stored as a structure in memory:
; Offset 0:  type    (8 bytes) — what type of token
; Offset 8:  start   (8 bytes) — position in source file
; Offset 16: length  (8 bytes) — how many characters long
; Offset 24: line    (8 bytes) — which line number
; Offset 32: column  (8 bytes) — which column number
; Total: 40 bytes per token
TOKEN_SIZE      equ 40

; ── MAX SIZES ────────────────────────────────────────────────
MAX_TOKENS      equ 100000  ; maximum tokens in one file
MAX_SOURCE      equ 1048576 ; maximum source file size (1MB)
MAX_TOKEN_TEXT  equ 256     ; maximum length of one token text

; ── DATA SECTION ─────────────────────────────────────────────
section .data

    ; INK banner — shown when lexer starts
    banner      db  "INK Lexer v0.1 — India's Programming Language", 10
                db  "Write the Future | IndianBrand Technology | Hyderabad", 10
                db  "Jai Hind!", 10, 0
    banner_len  equ $ - banner

    ; Error messages
    err_no_file     db  "[INK ERROR] No source file provided.", 10
                    db  "Usage: ink <filename.in>", 10, 0
    err_no_file_len equ $ - err_no_file

    err_open_fail   db  "[INK ERROR] Cannot open source file.", 10, 0
    err_open_len    equ $ - err_open_fail

    err_read_fail   db  "[INK ERROR] Cannot read source file.", 10, 0
    err_read_len    equ $ - err_read_fail

    err_too_large   db  "[INK ERROR] Source file too large (max 1MB).", 10, 0
    err_large_len   equ $ - err_too_large

    err_unterminated db "[INK ERROR] Unterminated string literal.", 10, 0
    err_unterm_len  equ $ - err_unterminated

    err_unknown     db  "[INK ERROR] Unknown character: ", 0
    err_unk_len     equ $ - err_unknown

    ; Debug messages
    msg_lexing      db  "[INK] Lexing source file...", 10, 0
    msg_done        db  "[INK] Lexing complete.", 10, 0

    ; INK keywords — used for keyword detection
    ; Format: length byte followed by keyword string
    kw_show     db  4, "show"
    kw_let      db  3, "let"
    kw_const    db  5, "const"
    kw_fn       db  2, "fn"
    kw_return   db  6, "return"
    kw_if       db  2, "if"
    kw_else     db  4, "else"
    kw_for      db  3, "for"
    kw_while    db  5, "while"
    kw_loop     db  4, "loop"
    kw_break    db  5, "break"
    kw_continue db  8, "continue"
    kw_match    db  5, "match"
    kw_type     db  4, "type"
    kw_pub      db  3, "pub"
    kw_use      db  3, "use"
    kw_in       db  2, "in"
    kw_or       db  2, "or"
    kw_and      db  3, "and"
    kw_not      db  3, "not"
    kw_true     db  4, "true"
    kw_false    db  5, "false"
    kw_none     db  4, "none"
    kw_exists   db  6, "exists"

    ; Keyword lookup table — pairs of (pointer, token_type)
    ; Used by keyword_check function
    kw_table:
        dq  kw_show,     TOKEN_SHOW
        dq  kw_let,      TOKEN_LET
        dq  kw_const,    TOKEN_CONST
        dq  kw_fn,       TOKEN_FN
        dq  kw_return,   TOKEN_RETURN
        dq  kw_if,       TOKEN_IF
        dq  kw_else,     TOKEN_ELSE
        dq  kw_for,      TOKEN_FOR
        dq  kw_while,    TOKEN_WHILE
        dq  kw_loop,     TOKEN_LOOP
        dq  kw_break,    TOKEN_BREAK
        dq  kw_continue, TOKEN_CONTINUE
        dq  kw_match,    TOKEN_MATCH
        dq  kw_type,     TOKEN_TYPE
        dq  kw_pub,      TOKEN_PUB
        dq  kw_use,      TOKEN_USE
        dq  kw_in,       TOKEN_IN
        dq  kw_or,       TOKEN_OR
        dq  kw_and,      TOKEN_AND
        dq  kw_not,      TOKEN_NOT
        dq  kw_true,     TOKEN_TRUE
        dq  kw_false,    TOKEN_FALSE
        dq  kw_none,     TOKEN_NONE
        dq  kw_exists,   TOKEN_EXISTS
        dq  0, 0         ; end of table

; ── BSS SECTION — uninitialised data ─────────────────────────
section .bss
    global source_buf
    global token_array
    global src_pos
    global src_len
    global tok_count
    global file_fd

    ; Source file buffer — holds entire .in file
    source_buf  resb    MAX_SOURCE

    ; Token array — holds all tokens found
    token_array resb    MAX_TOKENS * TOKEN_SIZE

    ; Lexer state variables
    src_pos     resq    1   ; current position in source buffer
    src_len     resq    1   ; total length of source
    tok_count   resq    1   ; number of tokens found so far
    cur_line    resq    1   ; current line number (starts at 1)
    cur_col     resq    1   ; current column number (starts at 1)
    file_fd     resq    1   ; file descriptor for source file

    ; Temporary token text buffer
    tok_text    resb    MAX_TOKEN_TEXT

; ── TEXT SECTION — executable code ───────────────────────────
section .text
    global ink_lex          ; main lexer function — callable externally
    global lexer_init       ; initialise lexer

; ============================================================
; LEXER_INIT — initialise all lexer state variables
; ============================================================
lexer_init:
    push    rbp
    mov     rbp, rsp

    ; Set all state to starting values
    mov     qword [src_pos],   0   ; start at beginning of file
    mov     qword [tok_count], 0   ; no tokens yet
    mov     qword [cur_line],  1   ; start at line 1
    mov     qword [cur_col],   1   ; start at column 1

    pop     rbp
    ret

; ============================================================
; INK_LEX — main lexer loop
; Reads source file and produces all tokens
;
; This is the heart of the INK lexer.
; It loops through every character in the source file
; and decides what token each character starts.
; ============================================================
ink_lex:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

.lex_loop:
    ; Skip whitespace (spaces, tabs) but NOT newlines
    call    skip_whitespace

    ; Check if we have reached end of file
    call    is_at_end
    test    rax, rax
    jnz     .emit_eof           ; if at end, emit EOF token

    ; Peek at current character
    call    peek_char           ; returns char in al

    ; ── COMMENTS ── skip // comments
    cmp     al, '/'
    jne     .not_comment
    call    peek_next_char      ; look at next char
    cmp     al, '/'
    jne     .not_comment
    call    advance_char        ; consume first /
    call    advance_char        ; consume second /
    call    skip_line_comment   ; skip to end of line
    jmp     .lex_loop

.not_comment:
    ; ── NEWLINE ──
    cmp     al, 10              ; 10 = newline character
    jne     .not_newline
    call    advance_char        ; consume the newline
    inc     qword [cur_line]    ; increment line counter
    mov     qword [cur_col], 1  ; reset column counter
    jmp     .lex_loop           ; INK ignores newlines as separators

.not_newline:
    ; ── STRING LITERAL ── starts with "
    cmp     al, '"'
    jne     .not_string
    call    lex_string
    jmp     .lex_loop

.not_string:
    ; ── CHAR LITERAL ── starts with '
    cmp     al, 39              ; 39 = single quote '
    jne     .not_char
    call    lex_char
    jmp     .lex_loop

.not_char:
    ; ── NUMBER ── starts with digit 0-9
    cmp     al, '0'
    jl      .not_number
    cmp     al, '9'
    jg      .not_number
    call    lex_number
    jmp     .lex_loop

.not_number:
    ; ── IDENTIFIER or KEYWORD ── starts with letter or _
    call    is_alpha_or_underscore
    test    rax, rax
    jz      .not_ident
    call    lex_identifier
    jmp     .lex_loop

.not_ident:
    ; ── OPERATORS AND SYMBOLS ──
    call    advance_char        ; consume the character
    movzx   rbx, al             ; save the character

    ; Check each operator/symbol
    cmp     bl, '+'
    jne     .not_plus
    mov     rdi, TOKEN_PLUS
    call    emit_simple_token
    jmp     .lex_loop

.not_plus:
    cmp     bl, '-'
    jne     .not_minus
    ; Check for -> arrow
    call    peek_char
    cmp     al, '>'
    jne     .just_minus
    call    advance_char
    mov     rdi, TOKEN_ARROW
    call    emit_simple_token
    jmp     .lex_loop
.just_minus:
    mov     rdi, TOKEN_MINUS
    call    emit_simple_token
    jmp     .lex_loop

.not_minus:
    cmp     bl, '*'
    jne     .not_star
    mov     rdi, TOKEN_STAR
    call    emit_simple_token
    jmp     .lex_loop

.not_star:
    cmp     bl, '/'
    jne     .not_slash
    mov     rdi, TOKEN_SLASH
    call    emit_simple_token
    jmp     .lex_loop

.not_slash:
    cmp     bl, '%'
    jne     .not_percent
    mov     rdi, TOKEN_PERCENT
    call    emit_simple_token
    jmp     .lex_loop

.not_percent:
    cmp     bl, '='
    jne     .not_equals
    ; Check for == or =>
    call    peek_char
    cmp     al, '='
    jne     .check_fat_arrow
    call    advance_char
    mov     rdi, TOKEN_EQ_EQ
    call    emit_simple_token
    jmp     .lex_loop
.check_fat_arrow:
    cmp     al, '>'
    jne     .just_equals
    call    advance_char
    mov     rdi, TOKEN_FAT_ARROW
    call    emit_simple_token
    jmp     .lex_loop
.just_equals:
    mov     rdi, TOKEN_EQUALS
    call    emit_simple_token
    jmp     .lex_loop

.not_equals:
    cmp     bl, '!'
    jne     .not_bang
    ; Check for !=
    call    peek_char
    cmp     al, '='
    jne     .just_bang
    call    advance_char
    mov     rdi, TOKEN_BANG_EQ
    call    emit_simple_token
    jmp     .lex_loop
.just_bang:
    mov     rdi, TOKEN_BANG
    call    emit_simple_token
    jmp     .lex_loop

.not_bang:
    cmp     bl, '<'
    jne     .not_lt
    ; Check for <=
    call    peek_char
    cmp     al, '='
    jne     .just_lt
    call    advance_char
    mov     rdi, TOKEN_LT_EQ
    call    emit_simple_token
    jmp     .lex_loop
.just_lt:
    mov     rdi, TOKEN_LT
    call    emit_simple_token
    jmp     .lex_loop

.not_lt:
    cmp     bl, '>'
    jne     .not_gt
    ; Check for >=
    call    peek_char
    cmp     al, '='
    jne     .just_gt
    call    advance_char
    mov     rdi, TOKEN_GT_EQ
    call    emit_simple_token
    jmp     .lex_loop
.just_gt:
    mov     rdi, TOKEN_GT
    call    emit_simple_token
    jmp     .lex_loop

.not_gt:
    cmp     bl, '('
    jne     .not_lparen
    mov     rdi, TOKEN_LPAREN
    call    emit_simple_token
    jmp     .lex_loop

.not_lparen:
    cmp     bl, ')'
    jne     .not_rparen
    mov     rdi, TOKEN_RPAREN
    call    emit_simple_token
    jmp     .lex_loop

.not_rparen:
    cmp     bl, '{'
    jne     .not_lbrace
    mov     rdi, TOKEN_LBRACE
    call    emit_simple_token
    jmp     .lex_loop

.not_lbrace:
    cmp     bl, '}'
    jne     .not_rbrace
    mov     rdi, TOKEN_RBRACE
    call    emit_simple_token
    jmp     .lex_loop

.not_rbrace:
    cmp     bl, '['
    jne     .not_lbracket
    mov     rdi, TOKEN_LBRACKET
    call    emit_simple_token
    jmp     .lex_loop

.not_lbracket:
    cmp     bl, ']'
    jne     .not_rbracket
    mov     rdi, TOKEN_RBRACKET
    call    emit_simple_token
    jmp     .lex_loop

.not_rbracket:
    cmp     bl, ':'
    jne     .not_colon
    mov     rdi, TOKEN_COLON
    call    emit_simple_token
    jmp     .lex_loop

.not_colon:
    cmp     bl, ','
    jne     .not_comma
    mov     rdi, TOKEN_COMMA
    call    emit_simple_token
    jmp     .lex_loop

.not_comma:
    cmp     bl, '.'
    jne     .not_dot
    ; Check for .. range operator
    call    peek_char
    cmp     al, '.'
    jne     .just_dot
    call    advance_char
    mov     rdi, TOKEN_DOT_DOT
    call    emit_simple_token
    jmp     .lex_loop
.just_dot:
    mov     rdi, TOKEN_DOT
    call    emit_simple_token
    jmp     .lex_loop

.not_dot:
    cmp     bl, '?'
    jne     .not_question
    mov     rdi, TOKEN_QUESTION
    call    emit_simple_token
    jmp     .lex_loop

.not_question:
    cmp     bl, '|'
    jne     .not_pipe
    mov     rdi, TOKEN_PIPE
    call    emit_simple_token
    jmp     .lex_loop

.not_pipe:
    cmp     bl, '@'
    jne     .not_at
    mov     rdi, TOKEN_AT
    call    emit_simple_token
    jmp     .lex_loop

.not_at:
    ; Unknown character — emit error token
    mov     rdi, TOKEN_ERROR
    call    emit_simple_token
    jmp     .lex_loop

.emit_eof:
    ; Emit final EOF token
    mov     rdi, TOKEN_EOF
    call    emit_simple_token

    ; Return total token count
    mov     rax, [tok_count]

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ============================================================
; HELPER FUNCTIONS
; ============================================================

; ── PEEK_CHAR ────────────────────────────────────────────────
; Returns current character without advancing position
; Returns: al = current character (0 if at end)
peek_char:
    mov     rax, [src_pos]
    cmp     rax, [src_len]
    jge     .at_end
    movzx   rax, byte [source_buf + rax]
    ret
.at_end:
    xor     rax, rax            ; return 0 at end of file
    ret

; ── PEEK_NEXT_CHAR ───────────────────────────────────────────
; Returns next character (one ahead) without advancing
; Returns: al = next character (0 if at end)
peek_next_char:
    mov     rax, [src_pos]
    inc     rax
    cmp     rax, [src_len]
    jge     .at_end
    movzx   rax, byte [source_buf + rax]
    ret
.at_end:
    xor     rax, rax
    ret

; ── ADVANCE_CHAR ─────────────────────────────────────────────
; Moves position forward by one character
; Returns: al = character that was consumed
advance_char:
    mov     rax, [src_pos]
    cmp     rax, [src_len]
    jge     .at_end
    movzx   rax, byte [source_buf + rax]
    inc     qword [src_pos]
    inc     qword [cur_col]
    ret
.at_end:
    xor     rax, rax
    ret

; ── IS_AT_END ────────────────────────────────────────────────
; Checks if we have reached end of source file
; Returns: rax = 1 if at end, 0 if not
is_at_end:
    mov     rax, [src_pos]
    cmp     rax, [src_len]
    jge     .yes
    xor     rax, rax            ; not at end
    ret
.yes:
    mov     rax, 1              ; at end
    ret

; ── IS_ALPHA_OR_UNDERSCORE ───────────────────────────────────
; Checks if current char is a-z, A-Z, or _
; Returns: rax = 1 if yes, 0 if no
is_alpha_or_underscore:
    call    peek_char
    cmp     al, '_'
    je      .yes
    cmp     al, 'a'
    jl      .check_upper
    cmp     al, 'z'
    jle     .yes
.check_upper:
    cmp     al, 'A'
    jl      .no
    cmp     al, 'Z'
    jle     .yes
.no:
    xor     rax, rax
    ret
.yes:
    mov     rax, 1
    ret

; ── IS_ALPHANUMERIC ──────────────────────────────────────────
; Checks if current char is a-z, A-Z, 0-9, or _
; Returns: rax = 1 if yes, 0 if no
is_alphanumeric:
    call    peek_char
    cmp     al, '_'
    je      .yes
    cmp     al, '0'
    jl      .check_alpha
    cmp     al, '9'
    jle     .yes
.check_alpha:
    cmp     al, 'a'
    jl      .check_upper
    cmp     al, 'z'
    jle     .yes
.check_upper:
    cmp     al, 'A'
    jl      .no
    cmp     al, 'Z'
    jle     .yes
.no:
    xor     rax, rax
    ret
.yes:
    mov     rax, 1
    ret

; ── IS_DIGIT ─────────────────────────────────────────────────
; Checks if current char is 0-9
; Returns: rax = 1 if yes, 0 if no
is_digit:
    call    peek_char
    cmp     al, '0'
    jl      .no
    cmp     al, '9'
    jg      .no
    mov     rax, 1
    ret
.no:
    xor     rax, rax
    ret

; ── SKIP_WHITESPACE ──────────────────────────────────────────
; Skips spaces and tabs (but not newlines — they are significant)
skip_whitespace:
    call    peek_char
    cmp     al, ' '
    je      .skip
    cmp     al, 9               ; tab character
    je      .skip
    ret
.skip:
    call    advance_char
    jmp     skip_whitespace

; ── SKIP_LINE_COMMENT ────────────────────────────────────────
; Skips from // to end of line
; Called when we detect // — advances past both slashes then skips to EOL
skip_line_comment:
.loop:
    call    is_at_end
    test    rax, rax
    jnz     .done
    call    peek_char
    cmp     al, 10              ; newline
    je      .done
    call    advance_char
    jmp     .loop
.done:
    ret

; ── LEX_STRING ───────────────────────────────────────────────
; Lexes a string literal: "Hello India"
; Called when current char is "
lex_string:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12

    ; Record start position (after opening quote)
    call    advance_char        ; consume opening "
    mov     r12, [src_pos]      ; r12 = start of string content

    ; Scan until closing " or end of file
.scan_loop:
    call    is_at_end
    test    rax, rax
    jnz     .unterminated       ; reached EOF without closing "

    call    peek_char
    cmp     al, '"'
    je      .found_end          ; found closing "

    cmp     al, '\'
    jne     .normal_char
    ; Handle escape sequences: \n \t \\ \"
    call    advance_char        ; consume backslash
    call    advance_char        ; consume escaped char
    jmp     .scan_loop

.normal_char:
    call    advance_char
    jmp     .scan_loop

.found_end:
    ; Calculate string length
    mov     rbx, [src_pos]
    sub     rbx, r12            ; length = current - start

    call    advance_char        ; consume closing "

    ; Emit STRING token
    mov     rdi, TOKEN_STRING
    mov     rsi, r12            ; start position
    mov     rdx, rbx            ; length
    call    emit_token

    pop     r12
    pop     rbx
    pop     rbp
    ret

.unterminated:
    ; Error — string not closed
    mov     rax, SYS_WRITE
    mov     rdi, STDERR
    mov     rsi, err_unterminated
    mov     rdx, err_unterm_len
    syscall

    pop     r12
    pop     rbx
    pop     rbp
    ret

; ── LEX_CHAR ─────────────────────────────────────────────────
; Lexes a char literal: 'A'
; Called when current char is '
lex_char:
    push    rbp
    mov     rbp, rsp

    call    advance_char        ; consume opening '
    mov     rsi, [src_pos]      ; start position

    call    peek_char
    cmp     al, '\'
    jne     .normal
    call    advance_char        ; consume backslash
.normal:
    call    advance_char        ; consume the char

    ; Emit CHAR token
    mov     rdi, TOKEN_CHAR
    mov     rdx, 1
    call    emit_token

    ; Consume closing '
    call    advance_char

    pop     rbp
    ret

; ── LEX_NUMBER ───────────────────────────────────────────────
; Lexes an integer or float: 42, 3.14
; Called when current char is 0-9
lex_number:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13

    mov     r12, [src_pos]      ; r12 = start position
    mov     r13, TOKEN_INT      ; assume integer first

    ; Consume all digits
.digit_loop:
    call    is_digit
    test    rax, rax
    jz      .check_float
    call    advance_char
    jmp     .digit_loop

.check_float:
    ; Check if this is a float (has decimal point)
    call    peek_char
    cmp     al, '.'
    jne     .emit_number
    ; Check next char is also a digit (not .. operator)
    call    peek_next_char
    cmp     al, '.'
    je      .emit_number        ; it is .., not a float
    cmp     al, '0'
    jl      .emit_number
    cmp     al, '9'
    jg      .emit_number

    ; It is a float
    mov     r13, TOKEN_FLOAT
    call    advance_char        ; consume '.'

.float_loop:
    call    is_digit
    test    rax, rax
    jz      .emit_number
    call    advance_char
    jmp     .float_loop

.emit_number:
    mov     rbx, [src_pos]
    sub     rbx, r12            ; length

    mov     rdi, r13            ; INT or FLOAT
    mov     rsi, r12            ; start
    mov     rdx, rbx            ; length
    call    emit_token

    pop     r13
    pop     r12
    pop     rbp
    ret

; ── LEX_IDENTIFIER ───────────────────────────────────────────
; Lexes an identifier or keyword: name, age, show, let, fn
; Called when current char is letter or _
lex_identifier:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13

    mov     r12, [src_pos]      ; r12 = start position

    ; Consume all alphanumeric chars and underscores
.scan_loop:
    call    is_alphanumeric
    test    rax, rax
    jz      .check_keyword
    call    advance_char
    jmp     .scan_loop

.check_keyword:
    ; Calculate identifier length
    mov     r13, [src_pos]
    sub     r13, r12            ; r13 = length

    ; Check if this identifier is a keyword
    mov     rdi, r12            ; start of identifier in source
    mov     rsi, r13            ; length of identifier
    call    keyword_check       ; returns token type in rax

    ; Emit token with correct type (keyword or IDENT)
    mov     rdi, rax            ; token type
    mov     rsi, r12            ; start position
    mov     rdx, r13            ; length
    call    emit_token

    pop     r13
    pop     r12
    pop     rbp
    ret

; ── KEYWORD_CHECK ────────────────────────────────────────────
; Checks if an identifier matches any INK keyword
; Input:  rdi = start offset in source_buf (not pointer)
;         rsi = length of identifier
; Returns: rax = token type (TOKEN_IDENT if not a keyword)
keyword_check:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; r12 = absolute pointer to identifier in source
    lea     r12, [source_buf]
    add     r12, rdi
    mov     r13, rsi            ; r13 = identifier length
    lea     r14, [kw_table]     ; r14 = keyword table pointer

.table_loop:
    mov     r15, [r14]          ; r15 = keyword entry pointer
    test    r15, r15
    jz      .not_keyword        ; end of table — not a keyword

    ; Get keyword length (first byte)
    movzx   rbx, byte [r15]

    ; Compare lengths first
    cmp     rbx, r13
    jne     .next_entry         ; lengths differ — skip

    ; Compare strings character by character
    mov     rdi, r12            ; identifier in source
    lea     rsi, [r15 + 1]      ; keyword string (skip length byte)
    mov     rcx, r13            ; length to compare
    call    str_compare
    test    rax, rax
    jnz     .next_entry         ; strings differ — skip

    ; Match found — get token type
    mov     rax, [r14 + 8]      ; token type is second entry
    jmp     .done

.next_entry:
    add     r14, 16             ; advance to next table entry (2 * 8 bytes)
    jmp     .table_loop

.not_keyword:
    mov     rax, TOKEN_IDENT    ; default — it is an identifier

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ── STR_COMPARE ──────────────────────────────────────────────
; Compares two strings of given length
; Input:  rdi = string 1 pointer
;         rsi = string 2 pointer
;         rcx = length
; Returns: rax = 0 if equal, non-zero if different
str_compare:
    push    rbp
    mov     rbp, rsp
    push    rbx

    xor     rax, rax            ; assume equal

.loop:
    test    rcx, rcx
    jz      .equal              ; all chars matched
    movzx   rax, byte [rdi]
    movzx   rbx, byte [rsi]
    cmp     rax, rbx
    jne     .not_equal          ; found difference
    inc     rdi
    inc     rsi
    dec     rcx
    jmp     .loop

.equal:
    xor     rax, rax
    pop     rbx
    pop     rbp
    ret

.not_equal:
    mov     rax, 1
    pop     rbx
    pop     rbp
    ret

; ── PRINT_STR ────────────────────────────────────────────────
; Prints a null-terminated string to stdout
; Input: rdi = pointer to string
print_str:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12

    mov     r12, rdi            ; save string pointer

    ; Calculate length
    xor     rbx, rbx
.len_loop:
    cmp     byte [r12 + rbx], 0
    je      .len_done
    inc     rbx
    jmp     .len_loop
.len_done:

    ; Write to stdout
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT
    mov     rsi, r12
    mov     rdx, rbx
    syscall

    pop     r12
    pop     rbx
    pop     rbp
    ret

; ── EMIT_SIMPLE_TOKEN ────────────────────────────────────────
; Emits a token with type only (for single-char tokens)
; Input: rdi = token type
emit_simple_token:
    push    rbp
    mov     rbp, rsp
    push    rdx

    ; Bounds check — do not overflow token array
    mov     rax, [tok_count]
    cmp     rax, MAX_TOKENS - 1
    jge     .overflow

    ; Calculate token position in token array
    mov     rcx, TOKEN_SIZE
    mul     rcx
    lea     rdx, [token_array + rax]  ; rdx = pointer to token slot

    ; Write token type
    mov     [rdx], rdi

    ; Write position
    mov     rax, [src_pos]
    mov     [rdx + 8], rax

    ; Write length (1 for simple tokens)
    mov     qword [rdx + 16], 1

    ; Write line number
    mov     rax, [cur_line]
    mov     [rdx + 24], rax

    ; Write column number
    mov     rax, [cur_col]
    mov     [rdx + 32], rax

    ; Increment token count
    inc     qword [tok_count]

.overflow:
    pop     rdx
    pop     rbp
    ret

; ── EMIT_TOKEN ───────────────────────────────────────────────
; Emits a token with type, start position, and length
; Input: rdi = token type
;        rsi = start position in source
;        rdx = length
emit_token:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13

    ; Bounds check
    mov     rax, [tok_count]
    cmp     rax, MAX_TOKENS - 1
    jge     .overflow

    mov     rbx, rdi            ; save type
    mov     r12, rsi            ; save start
    mov     r13, rdx            ; save length

    ; Calculate token position in token array
    mov     rcx, TOKEN_SIZE
    mul     rcx
    lea     rsi, [token_array + rax]

    ; Write token fields
    mov     [rsi], rbx          ; type
    mov     [rsi + 8], r12      ; start position
    mov     [rsi + 16], r13     ; length
    mov     rax, [cur_line]
    mov     [rsi + 24], rax     ; line number
    mov     rax, [cur_col]
    mov     [rsi + 32], rax     ; column number

    ; Increment token count
    inc     qword [tok_count]

.overflow:
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
