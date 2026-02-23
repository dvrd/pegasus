# Pegasus

A fast **PEG (Parsing Expression Grammar)** parser and packrat virtual machine for [Odin](https://odin-lang.org/). Compiles grammars into bytecode, optimizes them, and executes them with selective memoization — fast enough to parse real-world JavaScript files up to 545 KB.

Ships with a **full ES2025 JavaScript grammar** (~304 rules) validated against 76 production files (~2.5 MB total) from Node.js, Express, Three.js, Lodash, Underscore, Prettier, D3, and more.


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

# Parse a real JavaScript file
./bin/pegasus grammars/javascript.peg --file node_modules/express/lib/router/index.js

# Batch-validate a directory
for f in node_modules/express/lib/*.js; do
  ./bin/pegasus grammars/javascript.peg --file "$f" --quiet || echo "FAIL: $f"
done
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


## JavaScript Grammar

The flagship grammar at `grammars/javascript.peg` is a **complete ES2025 PEG grammar** — ~800 lines, ~304 rules covering the full language:

- **Modules** — `import` / `export` with all specifier forms, ES2022 string literal module export names, `import()` with options arg, `with` and `assert` attribute clauses
- **Declarations** — `let`, `const`, `var`, `using`, `await using`, classes with fields/static blocks/auto-accessors, generators, async generators
- **Expressions** — optional chaining (`?.`), nullish coalescing (`??`), private field `in` checks (`#x in obj`), tagged templates, destructuring assignment
- **Statements** — `for-of`, `for-in`, `for-await-of`, labeled statements (including labeled function declarations), `switch`, `try`/`catch`/`finally`
- **Functions** — arrow functions, async arrows, default parameters, rest parameters, computed property names
- **Literals** — template literals with nesting, regex literals, BigInt, numeric separators, legacy octal literals
- **Classes** — decorators, static blocks, auto-accessors (`accessor x = 1`), private fields/methods, computed names
- **Unicode** — non-ASCII identifiers via UTF-8 byte ranges (`café`, `π`, `日本語`), `\uXXXX` and `\u{XXXXX}` escapes

### Validated against real-world code

The grammar has been tested against **76 production JavaScript files** (~2.5 MB total, 1.6 KB – 545 KB) from:

- **Node.js internals** — `path`, `fs`, `net`, `http2`, `streams`, `crypto`, `child_process`, `repl`, `readline`, `url`, CJS/ESM loaders, `buffer`, `events`, `errors`, `zlib`, `dgram`, `worker`, `cluster`, `console`, `timers`
- **Express.js** — router, app, response
- **Lodash** (545 KB), **Three.js** — `WebGLRenderer` (106 KB)
- **Underscore.js** (68 KB), **Prettier**, **Moment.js**, **D3**, npm utilities

### ASI via `%begin_line`

JavaScript's Automatic Semicolon Insertion (ASI) requires knowing whether a newline occurred between two tokens. Pegasus supports this through the built-in `%begin_line` assertion, which succeeds at the start of input or immediately after a newline character.

The grammar uses `!%begin_line` in the 9 restricted productions where ASI matters:

```peg
ReturnStatement   <- RETURN (!%begin_line Expression)? EOS
ThrowStatement    <- THROW !%begin_line Expression EOS
PostfixExpression <- LeftHandSideExpression (!%begin_line ('++' / '--') S)?
ArrowFunction     <- ArrowParameters !%begin_line ARROW ConciseBody
YieldExpression   <- YIELD (!%begin_line STAR? AssignmentExpression)?
# ... and continue, break, async arrow, async method
```

This means `return\n42` correctly parses as `return;` followed by `42;`, while `return 42` parses as `return 42;`.

### Performance

Three key optimizations keep parsing tractable for large files:

- **Arrow parameter lookahead** — a balanced-paren scan before `=>` avoids expensive speculative `FormalParameters` parses on every `(expr)`. ~38% faster.
- **Unified `LeftHandSideExpression`** — merges `CallExpression` / `OptionalExpression` / `NewExpression` into a single rule with a suffix loop, eliminating exponential double-parse. ~42% faster.
- **Arena allocator** — `match()` allocates into a virtual arena, avoiding per-node allocation overhead. Combined with in-place stack operations and a memo table cap (100K entries), this reduced memory from OOM to 67 MB on Lodash (545 KB) and improved Three.js (106 KB) from 3.4s to 0.06s (57x).

Selective memoization (threshold = 512) keeps memory usage reasonable.

### Known limitations

| # | Gap | Severity | Notes |
|---|-----|----------|-------|
| 1 | **ASI over-permissive** | Low | `EOS` fallback accepts code that should be a syntax error. Restricted productions (`return`, `throw`, `++/--`) are handled correctly via `%begin_line`, but the general case is an approximation. Accepts invalid code but never rejects valid code. |
| 2 | **`import.source()`** | Low | Source Phase Imports (Stage 3). Not yet in the spec. |


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

### Built-in assertions

Zero-width assertions that test position without consuming input:

| Syntax | Description |
|--------|-------------|
| `%begin_line` | Matches at start of input or immediately after `\n` |
| `%end_line` | Matches at end of input or immediately before `\n` |
| `%begin_text` | Matches only at the very start of input |
| `%end_text` | Matches only at the very end of input |
| `%word_boundary` | Matches at a word/non-word boundary |
| `%no_word_boundary` | Matches where there is no word boundary |

These are useful for line-sensitive grammars. For example, the JavaScript grammar uses `!%begin_line` to detect newlines between tokens for ASI (Automatic Semicolon Insertion).

### Comments

Lines starting with `#` are comments.


## Grammars

| File | Description |
|------|-------------|
| `grammars/javascript.peg` | **Full ES2025 JavaScript** — ~304 rules, validated against 76 production files |
| `grammars/peg.peg` | PEG meta-grammar — Pegasus can parse its own grammar format |
| `grammars/arith.peg` | Arithmetic expressions with operator precedence |

## Examples

The `examples/` directory contains standalone Odin packages that embed grammars and parse input programmatically:

- **`examples/calculator/`** — Arithmetic expressions with operator precedence
- **`examples/json/`** — Full JSON parser (objects, arrays, strings, numbers, booleans, null)
- **`examples/javascript/`** — JavaScript subset (variables, functions, control flow, expressions)


## Testing

Run the full test suite (188 tests across all packages):

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

Pegasus works in four stages:

1. **Parse** — The PEG grammar string is parsed into an AST of grammar rules
2. **Check** — The checker validates rule references, detects left recursion, and annotates the AST
3. **Compile** — The AST is compiled into a bytecode `Program` (a sequence of `Instruction` values), then optimized (dead code elimination, jump threading)
4. **Execute** — The VM runs the program against the subject string using a packrat memoization table with selective caching (only entries where the parser examined ≥512 characters are memoized)

Key packages:
- `lib/` — Core: grammar parsing (`grammar.odin`), checker (`checker.odin`), compiler (`compile.odin`), optimizer (`optimize.odin`), VM (`vm.odin`), pattern matching (`re.odin`)
- `lib/charset/` — Character set operations using Odin `bit_set`
- `lib/input/` — Input abstraction over the subject string
- `lib/memo/` — Memoization table (tree-based), capture tree, parse tree nodes
- `lib/log/` — Logging utilities


## License

MIT
