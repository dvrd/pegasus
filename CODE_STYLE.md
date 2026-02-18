# Code Style

## Language

Odin — all source files use `.odin` extension.

## Formatter & Linter

| Tool | Config | Settings |
|------|--------|----------|
| `odinfmt` | `odinfmt.json` | 80-char width, tabs, 4-space tab width |
| OLS checker | `ols.json` | `-strict-style -vet -vet-using-param -vet-style -vet-semicolon` |

## Naming Conventions

| Element | Convention | Examples |
|---------|-----------|----------|
| Files | lowercase single word | `compile.odin`, `vm.odin`, `nodes.odin`, `grammar.odin` |
| Packages | lowercase single word | `package pegasus`, `package charset`, `package memo` |
| Directories | lowercase single word | `charset/`, `input/`, `log/`, `memo/` |
| Structs | PascalCase | `AltNode`, `ParseError`, `StackEntry`, `GrammarNode` |
| Enums | PascalCase | `Opcode`, `StackKind`, `NonTerm`, `ErrorKind` |
| Enum variants | PascalCase | `Opcode.Char`, `Opcode.Jump`, `StackKind.Btrack` |
| Union types | PascalCase | `Pattern`, `Instruction`, `Checker` |
| Type aliases | PascalCase | `Program :: [dynamic]Instruction`, `WalkFunc :: proc(...)` |
| Public functions | snake_case (preferred) | `compile_pattern`, `new_label`, `must_compile` |
| Internal helpers | camelCase (legacy) | `encodeU8`, `parseChar`, `compileDef`, `addSet` |
| Constants (sizes) | camelCase with `sz` prefix | `szChar :: 2`, `szJump :: 4`, `szMemoOpen :: 6` |
| Constants (strings) | UPPER_CASE | `RED :: "\e[1;31m%v\e[0m"` |
| Variables | very short, abbreviated | `ip` (instruction pointer), `st` (stack), `src` (source) |
| Labels | Uppercase short | `L1`, `L2`, `LEnd` |
| Named returns | short lowercase | `(c: Program, err: bool)`, `(np: Pattern)` |

**Note**: The codebase has two competing function naming styles. `snake_case` is dominant and preferred for new code. `camelCase` appears in `code.odin` and `re.odin` (likely from the original Go port).

## Node Type Naming

All AST node types use the `XxxNode` suffix:

```odin
AltNode, SeqNode, StarNode, PlusNode, OptionalNode,
NotNode, AndNode, CapNode, MemoNode, CheckNode,
GrammarNode, SearchNode, RepeatNode, ClassNode,
LiteralNode, NonTermNode, DotNode, ErrorNode,
EmptyOpNode, EmptyNode
```

## File Organization

Each `.odin` file corresponds to one stage or concept in the compiler pipeline:

```
grammar.odin    → grammar definition
re.odin         → grammar string parsing
nodes.odin      → AST type definitions
pattern.odin    → pattern constructors
checker.odin    → runtime content validation (back-refs, keywords)
compile.odin    → compilation to IR (Program)
optimize.odin   → bytecode optimization
instructions.odin → instruction types
op.odin         → opcodes and sizes
code.odin       → encoding IR → bytecode (Code)
vm.odin         → virtual machine
stack.odin      → VM stack
```

Sub-packages isolate cross-cutting concerns:
- `charset/charset.odin` — character set operations
- `input/input.odin` — input stream
- `log/log.odin` — colored logging
- `memo/*.odin` — memoization (6 files, split by concept)

## Import Style

```odin
package pegasus

import "charset"          // local subpackage (bare name)
import "core:fmt"         // core library (core: prefix)
import "core:strings"     // core library
import "input"            // local subpackage
import "memo"             // local subpackage
```

- Imports are **alphabetically sorted**
- Local and core imports are **mixed** (not grouped separately)
- No import aliases used anywhere
- No blank-line separation between import groups

## Code Patterns

### Union + Switch Dispatch (Primary Polymorphism)

No interfaces — polymorphism is achieved via tagged unions and `#partial switch`:

```odin
// Define a union type
Pattern :: union { ^AltNode, ^SeqNode, ^StarNode, ... }

// Dispatch with switch
compile_pattern :: proc(pattern: Pattern) -> (c: Program, err: bool) {
    #partial switch p in pattern {
    case ^AltNode:
        c, err = compile_alt_node(p)
    case ^SeqNode:
        c, err = compile_seq_node(p)
    // ... one case per variant
    }
    return
}
```

### One Function Per Node Type

Each node type gets its own `compile_xxx_node` procedure:

```odin
compile_alt_node :: proc(p: ^AltNode) -> (Program, bool) { ... }
compile_seq_node :: proc(p: ^SeqNode) -> (Program, bool) { ... }
compile_star_node :: proc(p: ^StarNode) -> (Program, bool) { ... }
```

### Procedure Overloading

Odin's explicit overload sets create a single name dispatching to type-specific implementations:

```odin
to_string :: proc {
    string_from_label,
    string_from_char,
    string_from_jump,
    // ... 25+ overloads
}

new_checker :: proc { new_map_checker, new_back_reference }
```

### Context User Pointer for Closures

Since Odin doesn't have closures, `context.user_ptr` is used to pass state to callback procs:

```odin
count := 0
context.user_ptr = &count
fn := proc(sub: Pattern) {
    count := cast(^int)context.user_ptr
    count^ += 1
}
walk_pattern(p, true, fn)
```

## Error Handling

- Errors returned as `bool` (true = error) alongside the result value
- Inline error checking with `;if err`:

```odin
compile :: proc(p: Pattern) -> (c: Program, err: bool) {
    c, err = compile_pattern(p);if err {
        return
    }
    optimize(&c)
    return
}
```

- `must_xxx` variants panic on error:

```odin
must_compile :: proc(p: Pattern) -> Program {
    c, err := compile(p);if err {
        panic("Error: failed to compile pattern")
    }
    return c
}
```

- Critical/impossible failures use `panic()` directly:

```odin
case .Return:
    ent := stack_pop(st, true)
    if ent != nil && ent.stype == StackKind.Ret {
        ip^ = int(ent.ret)
    } else {
        panic("Return failed")
    }
```

## Comment Style

```odin
// Doc comment goes directly above the declaration.
// Describes WHAT the thing does, not HOW.
compile :: proc(p: Pattern) -> (c: Program, err: bool) { ... }

// Multi-line doc comments use multiple // lines.
// Exec executes the parsing program this virtual machine was created with. It
// returns whether the parse was a match, the last position in the subject
// string that was matched, and any captures that were created.
exec :: proc(...) -> (...) { ... }
```

- Use `//` line comments (no `///` or `/** */`)
- Doc comments describe **what**, not **how**
- Some comments reference original Go naming (project was ported from Go)

## Testing

Tests are **co-located** in source files using Odin's `@(test)` attribute:

```odin
import "core:testing"

@(test)
test_set :: proc(t: ^testing.T) {
    included: [6]byte = {'a', 'b', 'c', 'd', '{', '}'}
    set := new_charset(included[:])
    // ...
    testing.expect(t, has(&set, b), fmt.sbprintf(&sb, ...))
}
```

- **No separate test files** — tests live in the same `.odin` file as the code
- Test function naming: `test_xxx`
- Assertions: `testing.expect(t, condition, message)`
- Run with: `task test` (invokes `odin test`)
- Helper functions for tests are regular procs in the same file

## Do's and Don'ts

### Do

- Use `snake_case` for new function names
- Use `PascalCase` for types, structs, enums, unions
- Use `XxxNode` suffix for AST node types
- Use `#partial switch` for union dispatch
- Use named return values: `proc(...) -> (result: Type, err: bool)`
- Use `;if err` for inline error checking
- Use `context.user_ptr` for callback state
- Keep variables short: `ip`, `st`, `src`, `p`, `t`
- Put tests in the same file with `@(test)` attribute
- Sort imports alphabetically

### Don't

- Don't use interfaces — use union + switch dispatch
- Don't create separate test files — use inline `@(test)` procs
- Don't use import aliases
- Don't use Odin's `Maybe` or error unions — use `bool` error returns
- Don't use long variable names — follow the terse style
- Don't add blank lines between import groups
