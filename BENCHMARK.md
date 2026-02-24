# Benchmarks

Pegasus compared against four popular JavaScript parsers, measured on three real-world files of increasing size. All benchmarks run on Apple M2 with `hyperfine --warmup 3 --runs 10`.

## Parsers

| Parser | Language | Approach | Notes |
|--------|----------|----------|-------|
| **Pegasus** | Odin | PEG packrat VM | Grammar-driven, 304-rule ES2025 grammar |
| **Tree-sitter** | C | GLR (grammar-driven) | Incremental, editor-focused, C runtime |
| **OXC** | Rust | Hand-written recursive descent | Fastest known JS parser, NAPI bindings |
| **Acorn** | Pure JS | Hand-written recursive descent | De facto standard pure-JS parser |
| **Babel** | Pure JS | Hand-written recursive descent | Most feature-complete, plugin ecosystem |

## Results

### End-to-end (process launch → exit)

This is what a user actually experiences when invoking each tool. Node.js parsers carry ~35–45 ms of runtime startup overhead; Pegasus and Tree-sitter launch in ~3 ms and ~5 ms respectively.

#### chalk.js — 6 KB

| Parser | Time | vs fastest |
|--------|------|------------|
| Tree-sitter | 8.4 ms | — |
| **Pegasus** | **31.4 ms** | **3.7×** |
| OXC | 41.4 ms | 4.9× |
| Acorn | 47.9 ms | 5.7× |
| Babel | 86.5 ms | 10.3× |

#### three-webgl.js — 106 KB (Three.js WebGLRenderer)

| Parser | Time | vs fastest |
|--------|------|------------|
| Tree-sitter | 13.5 ms | — |
| OXC | 39.1 ms | 2.9× |
| Acorn | 59.3 ms | 4.4× |
| **Pegasus** | **63.9 ms** | **4.7×** |
| Babel | 104.8 ms | 7.8× |

#### lodash.js — 545 KB

| Parser | Time | vs fastest |
|--------|------|------------|
| Tree-sitter | 37.6 ms | — |
| OXC | 49.4 ms | 1.3× |
| Acorn | 76.5 ms | 2.0× |
| Babel | 125.2 ms | 3.3× |
| **Pegasus** | **2,251 ms** | **59.9×** |

### Pure parse time (no process/runtime startup)

Isolates the parser itself. Node.js numbers measured in-process with `performance.now()` over 20 iterations (median). Pegasus numbers derived by subtracting the ~18 ms grammar compilation + binary startup baseline.

#### chalk.js — 6 KB

| Parser | Parse time | Throughput |
|--------|-----------|------------|
| OXC | 0.1 ms | 50,931 KB/s |
| Acorn | 0.4 ms | 12,979 KB/s |
| Babel | 0.6 ms | 10,427 KB/s |
| Tree-sitter | ~2 ms | ~3,000 KB/s |
| **Pegasus** | **~13 ms** | **~460 KB/s** |

#### three-webgl.js — 106 KB

| Parser | Parse time | Throughput |
|--------|-----------|------------|
| OXC | 1.2 ms | 85,382 KB/s |
| Acorn | 2.5 ms | 40,576 KB/s |
| Babel | 3.2 ms | 32,518 KB/s |
| Tree-sitter | ~6 ms | ~17,000 KB/s |
| **Pegasus** | **~46 ms** | **~2,300 KB/s** |

#### lodash.js — 545 KB

| Parser | Parse time | Throughput |
|--------|-----------|------------|
| OXC | 5.3 ms | 100,484 KB/s |
| Acorn | 8.9 ms | 59,838 KB/s |
| Babel | 10.8 ms | 49,217 KB/s |
| Tree-sitter | ~30 ms | ~18,000 KB/s |
| **Pegasus** | **~2,233 ms** | **~240 KB/s** |

## Analysis

### Where Pegasus wins

**Small files, end-to-end.** On chalk.js (6 KB), Pegasus beats Acorn, OXC, and Babel in wall-clock time because their Node.js runtime takes 35–45 ms just to start. Pegasus launches in 3 ms. For CLI tools, scripts, and pipelines that parse many small files, this matters.

**Grammar flexibility.** The other parsers are hand-written for JavaScript specifically — thousands of lines of carefully tuned code. Pegasus parses JavaScript from a ~800-line `.peg` grammar file. Changing the language means writing a new grammar, not a new parser.

### Where Pegasus loses

**Large files, pure parse time.** On lodash.js (545 KB), Pegasus is ~250× slower than OXC and ~250× slower than Acorn in pure parse time. The gap grows super-linearly with file size — three-webgl.js (106 KB) is only ~18× slower than OXC, but lodash.js (5× larger) is ~420× slower.

**Scaling.** The other parsers are all O(n) — doubling the file roughly doubles the time. Pegasus scales worse than linear on large files due to memoization table pressure and the overhead of a 304-rule PEG grammar executing on a bytecode VM. The selective memoization (threshold = 512) helps, but the constant factor is high.

### Why the gap exists

PEG parsing is fundamentally different from hand-written recursive descent:

- **Backtracking.** PEG ordered choice (`/`) tries alternatives sequentially. A rule like `A / B / C` may parse the same input region multiple times before finding the match. Hand-written parsers use lookahead to pick the right branch immediately.
- **Memoization overhead.** Packrat parsing trades memory for time by caching results. But the cache lookup, storage, and eviction have real cost — especially with 304 rules and a 545 KB input.
- **Bytecode interpretation.** Pegasus compiles grammars to bytecode and runs them on a VM. OXC and Acorn execute native/JIT-compiled code with no interpretation layer.
- **Grammar generality.** The PEG grammar handles JavaScript as a general pattern-matching problem. Hand-written parsers exploit language-specific structure (e.g., knowing that `{` after `=>` starts a block, not an object literal) to avoid expensive speculation.

### The right comparison

Pegasus is a **parser generator** — it competes with tools like Tree-sitter, ANTLR, and PEG.js, not with hand-tuned production parsers. Among grammar-driven parsers, Tree-sitter's C runtime is the gold standard; Pegasus is ~4–60× slower depending on file size, which is reasonable for an Odin bytecode VM vs optimized C.

The value proposition is: **write an 800-line grammar file, get a working parser for a full programming language, with acceptable performance for files under ~100 KB.**


