#!/bin/bash
# ============================================================
# INK Language — Build & Run Script
# 
# Usage:
#   ./ink.sh hello.in          -- compile and run hello.in
#   ./ink.sh hello.in --ir     -- show generated LLVM IR
#   ./ink.sh --build           -- rebuild the INK compiler
#
# INK — Write the Future
# IndianBrand Technology, Hyderabad, India
# Jai Hind!
# ============================================================

SAFFRON='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── REBUILD COMPILER ─────────────────────────────────────────
if [ "$1" == "--build" ]; then
    echo -e "${SAFFRON}"
    echo "  ================================================"
    echo "       INK Language Compiler — Build"
    echo "       IndianBrand Technology | Hyderabad"
    echo "  ================================================"
    echo -e "${NC}"

    # Check tools
    for tool in nasm ld clang; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}[ERROR]${NC} '$tool' not found"
            echo "Install: sudo apt install nasm binutils clang"
            exit 1
        fi
    done

    mkdir -p build/output

    echo -e "${BLUE}[1/4]${NC} Assembling Lexer..."
    nasm -f elf64 lexer/lexer.asm -o build/output/lexer.o || exit 1

    echo -e "${BLUE}[2/4]${NC} Assembling Parser..."
    nasm -f elf64 parser/parser.asm -o build/output/parser.o || exit 1

    echo -e "${BLUE}[3/4]${NC} Assembling Code Generator..."
    nasm -f elf64 codegen/codegen.asm -o build/output/codegen.o || exit 1

    echo -e "${BLUE}[4/4]${NC} Assembling Main & Linking..."
    nasm -f elf64 main.asm -o build/output/main.o || exit 1
    ld -o build/output/ink \
       build/output/main.o \
       build/output/lexer.o \
       build/output/parser.o \
       build/output/codegen.o || exit 1

    echo ""
    echo -e "${GREEN}  INK compiler built successfully!${NC}"
    echo "  Run: ./ink.sh hello.in"
    echo ""
    exit 0
fi

# ── COMPILE AND RUN A .in FILE ────────────────────────────────
if [ -z "$1" ]; then
    echo ""
    echo -e "${SAFFRON}  INK Language — Write the Future${NC}"
    echo "  IndianBrand Technology | Hyderabad | inddn.in"
    echo ""
    echo "  Usage:"
    echo "    ./ink.sh <program.in>        compile and run"
    echo "    ./ink.sh <program.in> --ir   show LLVM IR"
    echo "    ./ink.sh --build             rebuild compiler"
    echo ""
    exit 0
fi

SOURCE="$1"

if [ ! -f "$SOURCE" ]; then
    echo -e "${RED}[ERROR]${NC} File not found: $SOURCE"
    exit 1
fi

if [ ! -f "build/output/ink" ]; then
    echo -e "${RED}[ERROR]${NC} INK compiler not built. Run: ./ink.sh --build"
    exit 1
fi

# Step 1: Compile .in → output.ll
./build/output/ink "$SOURCE"
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} INK compilation failed"
    exit 1
fi

# Show IR if requested
if [ "$2" == "--ir" ]; then
    echo ""
    echo -e "${SAFFRON}=== Generated LLVM IR ===${NC}"
    cat output.ll
    echo ""
    exit 0
fi

# Step 2: Compile LLVM IR → binary
BINARY="${SOURCE%.in}"
clang output.ll -o "$BINARY" 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} LLVM compilation failed"
    exit 1
fi

# Step 3: Run
echo ""
echo -e "${SAFFRON}=== Output ===${NC}"
./"$BINARY"
echo ""
