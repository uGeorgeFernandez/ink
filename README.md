# INK — The Programming Language

> **Write the Future** 🖋️🇮🇳

INK is a small, safe, compiled programming language created by
**IndianBrand Technology, Hyderabad**. It is written entirely in
x86-64 Assembly and compiles your programs to real native binaries.

INK is designed around one idea: **code should read the way a person
naturally thinks.** It takes the ease and safety of Python and the
speed of compiled native code — while avoiding C's danger and
Python's slowness.

```ink
show "Jai Hind!"

fn greet(name: text) -> text {
    return "Namaste " + name
}
show greet("George")
```

```
Jai Hind!
Namaste George
```

---

## Why INK?

- **Reads clearly** — `show` instead of `print`, `let` instead of `var`, `text` instead of `str`. Words a beginner can guess.
- **Memory-safe by default** — reading past the end of a list stops with a clear error instead of corrupting memory (the mistake behind ~70% of the world's security bugs in C).
- **Type-checked** — mistakes like adding text to a number are caught *before* the program runs, with a plain-English message.
- **Compiled** — INK programs run as fast native binaries, not slow interpreted scripts.
- **Small** — the entire language fits on one page. A small language is one you can hold in your head.

---

## What INK can do today

| Feature | Example |
|---|---|
| Variables | `let name = "George"` |
| Output | `show name` |
| Maths & text | `show "Age: " + 30` |
| Decisions | `if age > 18 { ... } else { ... }` |
| Loops | `for i in 0..5 { }`, `while x < 10 { }` |
| Functions | `fn add(a: int, b: int) -> int { return a + b }` |
| Recursion | a function calling itself |
| Lists | `let nums = [10, 20, 30]`, `nums[0]`, `len(nums)` |
| Text lists | `let cities = ["Delhi", "Mumbai"]` |
| Maps | `let age = {"George": 30}`, `age["George"]` |
| Text maps | `let city = {"George": "Hyderabad"}` |
| Input | `let n = input()`, `let s = input_text()` |
| Files | `write_file("data.txt", text)`, `read_file("data.txt")` |
| Built-ins | `len`, `sum`, `min`, `max`, `abs` |
| Safety | out-of-range list access is caught at runtime |
| Type checking | wrong types caught at compile time |

---

## Getting started

### Requirements
- Linux (x86-64)
- `nasm` (assembler)
- `clang` / LLVM

Install on Ubuntu/Debian:
```bash
sudo apt-get install nasm llvm clang
```

### Build the compiler
```bash
./build.sh
```

### Run an INK program
```bash
./ink.sh tests/hello.in
```

---

## Your first program

Create a file `first.in`:
```ink
show "Hello from INK!"

let age = 25
if age > 18 {
    show "You are an adult"
}
```

Run it:
```bash
./ink.sh first.in
```

---

## How it works

INK compiles in four stages, each written in x86-64 Assembly:

```
your_program.in
      │
      ▼
  [ Lexer ]      breaks code into tokens (words)
      │
      ▼
  [ Parser ]     builds a structure (syntax tree) from the tokens
      │
      ▼
  [ Codegen ]    turns the tree into LLVM intermediate code
      │
      ▼
  output.ll  →  clang  →  native executable
```

- `lexer/` — the lexer
- `parser/` — the parser
- `codegen/` — the code generator
- `main.asm` — ties them together
- `tests/` — example INK programs

---

## Documentation

- **INK Language Guide** — the full how-to-use manual
- **INK Words Reference** — every keyword, by category
- **INK Phases & Changes** — how INK was built, phase by phase

(See the `docs/` folder.)

---

## Project status

INK is a **working prototype of an introductory language.** It
compiles and runs real programs. It is honestly **not** yet able to
build operating systems, games, or large applications — that is a
long-term goal requiring years of work and a team.

**What works:** everything in the feature table above, tested across
37+ example programs.

**Known limitations:** memory is not yet freed (programs leak over
long runs), `read_file` caps at 64KB, error messages don't yet show
line numbers, and there is no module/import system yet.

Contributions, bug reports, and — most of all — **real programs
written in INK** are welcome.

---

## Roadmap

- [x] Lexer, parser, code generator
- [x] Variables, functions, recursion
- [x] Strings, lists, maps
- [x] Type checking + memory safety
- [x] Input & file I/O
- [ ] Comments & line numbers in errors
- [ ] Modules (`import`, multiple files)
- [ ] Expanded standard library (text tools)
- [ ] A large test suite
- [ ] Script Mode vs System Mode

---

## License

See [LICENSE](LICENSE).

---

<p align="center">
<b>INK — Write the Future</b><br>
IndianBrand Technology · Hyderabad, India · Jai Hind! 🇮🇳
</p>
