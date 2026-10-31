#!/bin/bash
# INK compiler build script
# Builds the INK compiler from x86-64 Assembly source.
set -e

echo "Building INK compiler..."
mkdir -p build/output

nasm -f elf64 lexer/lexer.asm   -o build/output/lexer.o
nasm -f elf64 parser/parser.asm -o build/output/parser.o
nasm -f elf64 codegen/codegen.asm -o build/output/codegen.o
nasm -f elf64 main.asm          -o build/output/main.o

ld -o build/output/ink \
   build/output/main.o \
   build/output/lexer.o \
   build/output/parser.o \
   build/output/codegen.o

echo "Done. The compiler is at build/output/ink"
echo "Run a program with:  ./ink.sh tests/hello.in"
