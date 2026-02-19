// Simplified JavaScript Example — Pegasus PEG Parser
//
// Demonstrates a simplified JavaScript expression/statement grammar.
// This is NOT a full JS parser — it covers a useful subset to show
// how PEG handles real-world-ish syntax:
//
//   - Variable declarations: var x = 5; let y = "hello"; const z = true;
//   - Assignments: x = 10;
//   - Function calls: foo(1, 2, "bar")
//   - Expressions with operators: +, -, *, /, ==, !=, <, >
//   - String literals (single and double quoted)
//   - Number literals (integers and decimals)
//   - Boolean literals: true, false
//   - Single-line comments: // ...
//   - Semicolons as statement terminators
//   - Identifiers: [a-zA-Z_][a-zA-Z0-9_]*
//
// Usage:
//   odin run examples/javascript -collection:shared=lib

package javascript

import pegasus "shared:pegasus"
import log "shared:pegasus/log"

main :: proc() {
	// ---------------------------------------------------------------
	// Grammar: Simplified JavaScript
	// ---------------------------------------------------------------
	//
	// Design notes:
	//   - The grammar is intentionally simple. A real JS parser would
	//     need hundreds of rules for full ES2024 coverage.
	//   - PEG's ordered choice (/) is perfect for keyword vs identifier
	//     disambiguation: try the keyword first, fall back to identifier.
	//   - The !IdentCont after keywords ensures "variable" doesn't match
	//     as keyword "var" followed by "iable".
	//   - Comments are consumed as whitespace so they're invisible to
	//     the rest of the grammar.

	grammar := `
# ── Start rule ──────────────────────────────────────────────────
# A program is a sequence of statements separated by whitespace.
Program       <- Spacing Statement* EndOfFile

# ── Statements ──────────────────────────────────────────────────
# Each statement is one of: variable declaration, assignment/expression,
# or a bare semicolon (empty statement).
Statement     <- VarDecl
              / ExprStmt
              / ';' Spacing

# ── Variable declarations ───────────────────────────────────────
# var x = expr;  |  let y = expr;  |  const z = expr;
# The keyword is followed by an identifier, '=', an expression,
# and a semicolon.
VarDecl       <- VarKeyword Identifier '=' Spacing Expr ';' Spacing

# Keywords — the !IdentCont ensures we don't match a prefix of
# a longer identifier (e.g., "variable" should NOT match "var").
VarKeyword    <- ('var' / 'let' / 'const') !IdentCont Spacing

# ── Expression statements ───────────────────────────────────────
# An expression followed by a semicolon. Covers assignments like
# x = 10; and function calls like foo(1, 2);
ExprStmt      <- Expr ';' Spacing

# ── Expressions ─────────────────────────────────────────────────
# Precedence (lowest to highest):
#   1. Comparison: ==, !=, <, >
#   2. Addition/Subtraction: +, -
#   3. Multiplication/Division: *, /
#   4. Primary: literals, identifiers, function calls, parens

# Comparison operators (lowest precedence)
Expr          <- AddExpr (CompOp AddExpr)*
CompOp        <- ('==' / '!=' / '<' / '>') Spacing

# Addition and subtraction
AddExpr       <- MulExpr (AddOp MulExpr)*
AddOp         <- [+\-] Spacing

# Multiplication and division
MulExpr       <- Primary (MulOp Primary)*
MulOp         <- [*/] Spacing

# ── Primary expressions ────────────────────────────────────────
# A primary is a literal, a function call, a plain identifier,
# or a parenthesized expression.
Primary       <- BoolLiteral
              / NumberLiteral
              / StringLiteral
              / FuncCall
              / Identifier
              / '(' Spacing Expr ')' Spacing

# ── Function calls ──────────────────────────────────────────────
# foo(arg1, arg2, ...)
# We need &'(' to distinguish a function call from a plain identifier.
# The & (and-predicate) peeks ahead without consuming.
FuncCall      <- Identifier '(' Spacing ArgList? ')' Spacing
ArgList       <- Expr (',' Spacing Expr)*

# ── Literals ────────────────────────────────────────────────────

# Boolean literals — must not be followed by identifier characters
# so "trueValue" parses as an identifier, not "true" + "Value".
BoolLiteral   <- ('true' / 'false') !IdentCont Spacing

# Number literals — integers and decimals
NumberLiteral <- [0-9]+ ('.' [0-9]+)? Spacing

# String literals — single or double quoted
# The inner loop matches any character except the closing quote.
StringLiteral <- DQString / SQString
DQString      <- '"' (!'"' .)* '"' Spacing
SQString      <- ['] (!['] .)* ['] Spacing

# ── Identifiers ─────────────────────────────────────────────────
# Standard identifier: starts with letter or underscore, followed
# by letters, digits, or underscores.
Identifier    <- IdentStart IdentCont* Spacing
IdentStart    <- [a-zA-Z_]
IdentCont     <- [a-zA-Z0-9_]

# ── Whitespace and comments ─────────────────────────────────────
# Whitespace includes spaces, tabs, newlines, and single-line comments.
# Comments start with // and run to end of line.
Spacing       <- (Space / Comment)*
Comment       <- '//' (!EndOfLine .)* EndOfLine
Space         <- ' ' / '\t' / EndOfLine
EndOfLine     <- '\r\n' / '\n' / '\r'
EndOfFile     <- !.
	`

	// ---------------------------------------------------------------
	// Test subjects — various JS-like snippets
	// ---------------------------------------------------------------
	subjects := []struct {
		label: string,
		input: string,
	}{
		{
			"variable declaration (number)",
			`var x = 42;`,
		},
		{
			"let with string",
			`let name = "hello";`,
		},
		{
			"const with boolean",
			`const flag = true;`,
		},
		{
			"assignment",
			`x = 10;`,
		},
		{
			"expression with operators",
			`x = 1 + 2 * 3;`,
		},
		{
			"comparison",
			`x = a > b;`,
		},
		{
			"function call",
			`foo(1, 2);`,
		},
		{
			"function call with string arg",
			`log("hello", 42);`,
		},
		{
			"multiple statements",
			"var x = 5;\nvar y = 10;\nx = x + y;\n",
		},
		{
			"with comments",
			"// this is a comment\nvar x = 1;\n// another comment\nvar y = 2;\n",
		},
		{
			"parenthesized expression",
			`var result = (1 + 2) * 3;`,
		},
		{
			"decimal number",
			`var pi = 3.14;`,
		},
		{
			"single-quoted string",
			"let msg = 'world';\n",
		},
		{
			"equality check",
			`x = a == b;`,
		},
		{
			"inequality check",
			`x = a != b;`,
		},
	}

	for s in subjects {
		is_match, pos, captures, errs := pegasus.match(grammar, s.input)

		if len(errs) > 0 {
			log.error("[", s.label, "] grammar error:")
			for e in errs {
				log.error("  at position", e.pos, ":", e.message)
			}
			continue
		}

		if is_match && pos == len(s.input) {
			log.success("[", s.label, "] fully parsed")
			if captures != nil {
				log.info("  captures:", captures)
			}
		} else if is_match {
			log.warning("[", s.label, "] partial match — consumed", pos, "of", len(s.input), "bytes")
			log.info("  parsed:", s.input[:pos])
		} else {
			log.error("[", s.label, "] failed at position", pos)
			if pos < len(s.input) {
				log.info("  near:", s.input[pos:min(pos + 20, len(s.input))])
			}
		}
	}
}
