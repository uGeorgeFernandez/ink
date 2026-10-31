; ============================================================
; INK Programming Language — Main Entry Point
; File: main.asm
;
; Connects all three phases:
;   Phase 1: Lexer   — source → tokens
;   Phase 2: Parser  — tokens → AST
;   Phase 3: Codegen — AST   → LLVM IR (.ll file)
;
; After generating output.ll, compile with:
;   llc -filetype=obj output.ll -o output.o
;   clang output.o -o myprogram
;   ./myprogram
;
; INK — Write the Future
; IndianBrand Technology, Hyderabad, India
; Jai Hind!
; ============================================================

SYS_READ    equ 0
SYS_WRITE   equ 1
SYS_OPEN    equ 2
SYS_CLOSE   equ 3
SYS_EXIT    equ 60
O_RDONLY    equ 0
STDOUT      equ 1
STDERR      equ 2

MAX_SOURCE  equ 1048576

extern lexer_init
extern ink_lex
extern parser_init
extern ink_parse
extern codegen_init
extern ink_codegen
extern codegen_write_output

extern source_buf
extern token_array
extern src_len
extern tok_count

section .data
    banner      db  "INK v0.1 — India's Programming Language", 10
                db  "Write the Future | IndianBrand Technology | Hyderabad", 10
                db  "Jai Hind!", 10, 0

    err_no_file db  "[INK ERROR] Usage: ink <filename.in>", 10, 0
    err_open    db  "[INK ERROR] Cannot open file", 10, 0
    err_read    db  "[INK ERROR] Cannot read file", 10, 0
    err_parse   db  "[INK ERROR] Parse failed", 10, 0
    err_codegen db  "[INK ERROR] Code generation failed", 10, 0

    msg_success db  "[INK] output.ll ready!", 10
               db  "[INK] Compile with: clang output.ll -o program", 10
               db  "[INK] Run with:     ./program", 10, 0

section .bss
    file_fd     resq 1

section .text
    global _start

_start:
    ; Print banner
    mov     rdi, banner
    call    print_str_main

    ; Check arguments
    mov     rax, [rsp]
    cmp     rax, 2
    jl      .no_file

    ; Open source file
    mov     rsi, [rsp + 16]     ; argv[1] = filename
    mov     rax, SYS_OPEN
    mov     rdi, rsi
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      .open_fail
    mov     [file_fd], rax

    ; Read file into source buffer
    mov     rax, SYS_READ
    mov     rdi, [file_fd]
    mov     rsi, source_buf
    mov     rdx, MAX_SOURCE
    syscall
    cmp     rax, 0
    jl      .read_fail
    mov     [src_len], rax

    ; Close file
    mov     rax, SYS_CLOSE
    mov     rdi, [file_fd]
    syscall

    ; ── PHASE 1: LEXER ──────────────────────────────────────
    call    lexer_init
    call    ink_lex
    ; rax = token count

    ; ── PHASE 2: PARSER ─────────────────────────────────────
    mov     rdi, token_array
    mov     rsi, rax            ; token count
    mov     rdx, source_buf     ; source buffer
    call    parser_init
    call    ink_parse
    ; rax = AST root node
    test    rax, rax
    jz      .parse_fail

    push    rax                 ; save AST root

    ; ── PHASE 3: CODE GENERATOR ─────────────────────────────
    mov     rdi, source_buf     ; source buffer for token text
    call    codegen_init

    pop     rdi                 ; AST root node
    call    ink_codegen
    test    rax, rax
    jz      .codegen_fail

    ; Write output.ll file
    call    codegen_write_output

    ; Print success message
    mov     rdi, msg_success
    call    print_str_main

    ; Exit success
    mov     rax, SYS_EXIT
    xor     rdi, rdi
    syscall

.no_file:
    mov     rdi, err_no_file
    call    print_str_main
    mov     rax, SYS_EXIT
    mov     rdi, 1
    syscall

.open_fail:
    mov     rdi, err_open
    call    print_str_main
    mov     rax, SYS_EXIT
    mov     rdi, 1
    syscall

.read_fail:
    mov     rdi, err_read
    call    print_str_main
    mov     rax, SYS_EXIT
    mov     rdi, 1
    syscall

.parse_fail:
    mov     rdi, err_parse
    call    print_str_main
    mov     rax, SYS_EXIT
    mov     rdi, 1
    syscall

.codegen_fail:
    mov     rdi, err_codegen
    call    print_str_main
    mov     rax, SYS_EXIT
    mov     rdi, 1
    syscall

print_str_main:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12, rdi
    xor     rbx, rbx
.len:
    cmp     byte [r12 + rbx], 0
    je      .write
    inc     rbx
    jmp     .len
.write:
    test    rbx, rbx
    jz      .exit
    mov     rax, SYS_WRITE
    mov     rdi, STDOUT
    mov     rsi, r12
    mov     rdx, rbx
    syscall
.exit:
    pop     r12
    pop     rbx
    pop     rbp
    ret
