# Architecture

## Overview

Pegasus is a PEG (Parsing Expression Grammar) parser library written in Odin. It compiles PEG grammars into bytecode and executes them on a virtual machine with memoization (packrat parsing) for efficient parsing of DSLs and language prototyping.

## Tech Stack

| Category | Technology |
|----------|-----------|
| Language | [Odin](https://odin-lang.org/) |
| Task Runner | [Taskfile](https://taskfile.dev/) (`Taskfile.yml`) |
| Formatter | `odinfmt` (`odinfmt.json`) |
| Language Server | OLS (`ols.json`) |
| External Dependencies | None (Odin standard library only) |

## Directory Structure

```
pegasus/
├── lib/                    # All source code (package pegasus)
│   ├── main.odin           # Entry point - demo/example usage
│   ├── grammar.odin        # PEG grammar definition (bootstrap grammar)
│   ├── re.odin             # Regex-based parser for .peg grammar strings
│   ├── nodes.odin          # AST node type definitions (Pattern union)
│   ├── pattern.odin        # Pattern construction helpers (cap, literal, star, etc.)
│   ├── checker.odin        # Runtime content validation (back-references, keyword maps)
│   ├── compile.odin        # Compiler: AST -> bytecode instructions
│   ├── optimize.odin       # Bytecode optimization pass
│   ├── instructions.odin   # Instruction type definitions (Label, Char, Jump, etc.)
│   ├── op.odin             # Opcode enum and instruction size constants
│   ├── code.odin           # Code container, encoding/decoding, serialization
│   ├── vm.odin             # Virtual machine - executes bytecode against input
│   ├── stack.odin          # VM execution stack (backtracking, memoization)
│   ├── empty.odin          # Zero-width assertion (EmptyOp) definitions
│   ├── charset/            # Character set abstraction for [a-z] style classes
│   │   └── charset.odin
│   ├── input/              # Input stream abstraction (position-tracked reader)
│   │   └── input.odin
│   ├── log/                # Custom colored logging (success, info, error)
│   │   └── log.odin
│   └── memo/               # Memoization table (packrat parsing cache)
│       ├── table.odin      # Memo table: get/put/apply_edit
│       ├── tree.odin       # Tree-structured memo entries
│       ├── node.odin       # Tree node definitions
│       ├── capture.odin    # Capture tracking
│       ├── entry.odin      # Memo entry type
│       └── interval.odin   # Interval operations for incremental parsing
├── grammars/               # Example PEG grammar files
│   ├── arith.peg           # Arithmetic expression grammar (4 rules)
│   └── peg.peg             # Self-describing PEG meta-grammar (42 lines)
├── Taskfile.yml            # Build/run/test/clean tasks
├── ols.json                # Odin Language Server config
├── odinfmt.json            # Odin formatter config (80 chars, tabs)
└── README.md               # Usage example and TODO checklist
```

## Core Components

### 1. Grammar Parser (`grammar.odin`, `re.odin`)

- `grammar.odin` defines the PEG meta-grammar as Odin data structures using pattern combinators (`cap`, `concat`, `or`, `star`, `literal`, `non_term`, etc.)
- `re.odin` provides compilation of `.peg` grammar strings into `Pattern` AST nodes
- **Self-hosting**: The PEG meta-grammar (defined in `grammar.odin`) is itself compiled to bytecode and executed through the VM to parse user grammar strings. The resulting `memo.Capture` tree is then walked by `compile_re` to reconstruct a `Pattern` tree.

### 2. AST Nodes (`nodes.odin`)

- `Pattern` is a tagged union of 20 node types (e.g., `AltNode`, `SeqNode`, `StarNode`, `LiteralNode`, `GrammarNode`)
- All nodes are heap-allocated (`^XxxNode` pointers in the union)
- `walk_pattern` provides tree traversal over the AST

### 3. Pattern Constructors (`pattern.odin`)

- Helper functions to build AST nodes: `cap()`, `literal()`, `non_term()`, `star()`, `plus()`, `optional()`, `or()`, `concat()`, `set()`, `any()`, `not()`, `and()`
- These are the public API for programmatic grammar construction

### 4. Compiler (`compile.odin`)

- Transforms `Pattern` AST into `Program` (an intermediate representation as `[dynamic]Instruction` with symbolic `Label` references)
- One `compile_xxx_node` procedure per node type, dispatched via `#partial switch`
- Includes optimizations: charset union, head-fail optimization, tail call optimization, disjoint branch detection

### 5. Optimizer (`optimize.odin`)

- Post-compilation optimization pass on the `Program` IR
- Head-fail optimization and jump replacement

### 6. Encoder (`code.odin`)

- Transforms `Program` (symbolic IR with `Label` references) into `Code` (flat byte array with resolved offsets)
- Resolves labels to byte offsets; serializes instructions into `[dynamic]byte` with opcode + args encoding
- `Code` struct bundles: `insns` (bytecode), `sets` (character sets), `errors` (error messages), `checkers` (validation callbacks)

### 7. Instruction Set (`instructions.odin`, `op.odin`)

- ~30 opcodes: `Char`, `Jump`, `Choice`, `Call`, `Commit`, `Return`, `Fail`, `Set`, `Any`, `Span`, `MemoOpen`, `MemoClose`, `MemoTree*`, `Capture*`, `Check*`, `Error`, `End`, etc.
- Instructions are defined as an Odin union (`Instruction`)
- Opcodes have fixed sizes defined as constants (`szChar :: 2`, `szJump :: 4`, etc.)

### 8. Virtual Machine (`vm.odin`, `stack.odin`)

- Stack-based bytecode interpreter
- Main loop in `exec_code` dispatches on opcodes via `#partial switch`
- `Stack` manages backtracking points, return addresses, memoization entries, and captures
- `failure_handler` unwinds the stack on parse failures

### 9. Memoization (`memo/`)

- Packrat parsing optimization: caches parse results to avoid redundant re-parsing
- `table.odin`: hash-based memo table with `get`/`put`/`apply_edit`
- `tree.odin`: tree-structured memoization for left-recursive rules
- `capture.odin`: tracks captured substrings with parent-child relationships
- Supports incremental parsing via `apply_edit`

### 10. Supporting Packages

- **`charset/`**: Bitset-based character class matching (union, complement, range operations)
- **`input/`**: Buffered input reader with position tracking, peek, advance, seek
- **`log/`**: ANSI-colored console output (red/green/yellow)

## Data Flow

```
PEG grammar string (e.g., "Expr <- Term ('+' Term)*")
    │
    ▼
┌─────────────────────────────┐
│  Grammar Parser (self-hosted)│
│  grammar.odin + re.odin     │
│  Meta-grammar VM parses PEG │
│  text → Capture tree →      │
│  Pattern tree (AST)         │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│  AST (Pattern union)        │
│  nodes.odin                 │
│  Tree of *Node structs      │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│  Compiler                   │
│  compile.odin               │
│  AST → Program (IR)         │
│  Symbolic Label references  │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│  Optimizer                  │
│  optimize.odin              │
│  Head-fail opt, jump replace│
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│  Encoder                    │
│  code.odin                  │
│  Program → Code (bytecode)  │
│  Resolves labels to offsets │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│  VM Execution               │
│  vm.odin + stack.odin       │
│  Code + input → result      │
│  Uses: charset/, input/,    │
│        memo/, checker.odin  │
└─────────────┬───────────────┘
              │
              ▼
    (is_match, position, captures, errors)
```

## Public API

The main entry point for users is the `match` procedure (defined in `re.odin`):

```odin
import "shared:pegasus"

is_match, pos, captures, errors := pegasus.match(grammar_string, subject_string)
```

For programmatic grammar construction:

```odin
p := pegasus.grammar("Start", {
    "Start" = pegasus.star(pegasus.literal("hello")),
})
program := pegasus.must_compile(p)
```

## Configuration

| File | Purpose |
|------|---------|
| `Taskfile.yml` | Build tasks: `task run`, `task build`, `task test`, `task clean` |
| `ols.json` | OLS config: collection paths, strict style checking (`-strict-style -vet`) |
| `odinfmt.json` | Formatter: 80-char width, tabs, 4-space tab width |

## Build & Run

```bash
# Run (compile + execute)
task run          # or: task r

# Build optimized binary
task build        # or: task b

# Run tests
task test         # or: task t

# Clean build artifacts
task clean        # or: task c
```

Output binary: `bin/pegasus`

## Project Status

Per README.md TODO list:
- **Complete**: Pattern logic, memoization tree, input/charset abstractions, VM, encoding, regex syntax, grammar API
- **In Progress**: Captures, CLI interface, examples, charset improvement using Odin `bit_set`
