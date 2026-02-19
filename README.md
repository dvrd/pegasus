# Pegasus

A fast **PEG (Parsing Expression Grammar)** parser for [Odin](https://odin-lang.org/). Built for parsing DSLs, config formats, or prototyping a language without pulling in heavy dependencies.

Pegasus compiles your grammar into a bytecode program and runs it on a virtual machine with memoization, so repeated parses are efficient.


## Installation

Pegasus is designed to be used as a shared collection. Symlink or copy the project into Odin's `shared` folder:

```sh
# From your Odin installation's shared directory
ln -s /path/to/pegasus pegasus
```

Then import it in your code:

```odin
import pegasus "shared:pegasus"
```


## Quick Start

Define a grammar as a string using PEG syntax, then call `match()`:

```odin
import pegasus "shared:pegasus"
import "shared:pegasus/log"

main :: proc() {
	grammar := `
Expr   		<- Space SubOp 

SubOp		<- AddOp (Sub AddOp)*
AddOp		<- DivOp (Add DivOp)*
DivOp		<- MulOp (Div MulOp)*
MulOp		<- PowOp (Mul PowOp)*
PowOp		<- Term (Pow Term)*
Term   		<- Atom / OParen Expr CParen

Pow			<- '^' Space
Mul			<- '*' Space
Div			<- '/' Space
Add			<- '+' Space
Sub			<- '-' Space

OParen 		<- '(' Space
CParen 		<- ')' Space

Atom		<- Numeral

Numeral 	<- Number Space
Number  	<- [0-9]+
Space   	<- (' ' / '\t' / EndOfLine)*
EndOfLine 	<- '\r\n' / '\n' / '\r'
EndOfFile 	<- !.
	`

	subject := "23 + 2 +(1* 2) ^ 2"
	is_match, pos, captures, errors := pegasus.match(grammar, subject)

	if is_match {
		log.success("matched til position", pos, "|", subject[:pos])
		log.info(captures)
	} else {
		log.error("matched til position", pos, "|", subject[:pos])
		for err in errors {
			log.error(err.message)
		}
	}
}
```


## CLI Usage

Build the binary, then run it against a grammar file:

```sh
task b    # build to ./bin/pegasus
```

### Basic usage

```sh
# Parse input string against a grammar
./bin/pegasus grammars/arith.peg "2+3*(4-1)"

# Parse input from a file
./bin/pegasus grammars/peg.peg --file grammars/arith.peg

# Parse input from stdin
echo "2+3" | ./bin/pegasus grammars/arith.peg
```

### Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--file` | `-f` | Read input from a file instead of an argument |
| `--quiet` | `-q` | Suppress output, only set exit code |
| `--help` | `-h` | Show usage information |

### Exit codes

| Code | Meaning |
|------|--------|
| `0` | Input matched the grammar |
| `1` | Input did not match |
| `2` | Error (bad grammar, missing file, no input) |

### Examples

```sh
# Quiet mode — useful in scripts
./bin/pegasus grammars/arith.peg "2+3" --quiet && echo "valid"

# Check exit code
./bin/pegasus grammars/arith.peg "???"; echo "exit: $?"

# Parse a grammar file with the PEG meta-grammar
./bin/pegasus grammars/peg.peg --file grammars/arith.peg
```


## API

### `match`

```
match :: proc(grammar: string, subject: string) -> (bool, int, ^memo.Capture, []ParseError)
```

**Parameters:**
- `grammar` — a PEG grammar string (see syntax reference below)
- `subject` — the input string to parse

**Returns:**
- `bool` — whether the grammar matched the subject
- `int` — how many characters were consumed
- `^memo.Capture` — the capture tree (from `{ }` expressions in the grammar)
- `[]ParseError` — any errors encountered during parsing


## PEG Syntax Reference

Grammars are defined as a set of rules. The first rule is the start rule.

### Rules

```
RuleName <- Pattern
```

### Terminals

| Syntax | Description |
|--------|-------------|
| `'abc'` | Literal string (single quotes) |
| `"abc"` | Literal string (double quotes) |
| `[a-z]` | Character class |
| `[^0-9]` | Negated character class |
| `.` | Any character |

### Operators

| Syntax | Description |
|--------|-------------|
| `A B` | Sequence — match A then B |
| `A / B` | Ordered choice — try A, if it fails try B |
| `A*` | Zero or more repetitions |
| `A+` | One or more repetitions |
| `A?` | Optional (zero or one) |
| `!A` | Not predicate — succeed if A fails, consume nothing |
| `&A` | And predicate — succeed if A succeeds, consume nothing |
| `(A)` | Grouping |
| `{ A }` | Capture — record the matched text |

### Comments

Lines starting with `#` are comments.


## Examples

The `examples/` directory contains complete, annotated grammars:

- **`examples/calculator/`** — Arithmetic expressions with operator precedence
- **`examples/json/`** — Full JSON parser (objects, arrays, strings, numbers, booleans, null)
- **`examples/javascript/`** — Subset of JavaScript (variables, functions, control flow, expressions)

Each example is a standalone Odin package that you can study or run.


## Testing

Run the full test suite (185 tests across all packages):

```sh
task ta    # runs all tests with -thread-count:1 for determinism
```

Other useful commands:

```sh
task t     # run tests for lib only
task b     # build
task r     # run
task c     # clean
```


## Architecture

Pegasus works in three stages:

1. **Compile** — The PEG grammar string is parsed and compiled into a bytecode `Program` (a sequence of `Instruction` values)
2. **Optimize** — The program is optimized (dead code elimination, jump threading)
3. **Execute** — The VM runs the program against the subject string, using a memoization table to avoid redundant work

Key packages:
- `lib/` — Core parser: grammar compilation, VM, pattern matching
- `lib/charset/` — Character set operations using Odin `bit_set`
- `lib/input/` — Input abstraction over the subject string
- `lib/memo/` — Memoization table, capture tree, parse tree nodes
- `lib/log/` — Logging utilities


## License

MIT
