// Calculator Example — Pegasus PEG Parser
//
// Demonstrates a simple arithmetic expression grammar with operator precedence.
// Supports: +, -, *, /, ^ (power), parenthesized sub-expressions, integers.
//
// Operator precedence (lowest to highest):
//   1. Subtraction (-)
//   2. Addition (+)
//   3. Division (/)
//   4. Multiplication (*)
//   5. Exponentiation (^)
//   6. Atoms / Parenthesized expressions
//
// Usage:
//   odin run examples/calculator -collection:shared=lib

package calculator

import pegasus "shared:pegasus"
import log "shared:pegasus/log"

main :: proc() {
	// ---------------------------------------------------------------
	// Grammar: Arithmetic expressions with operator precedence
	// ---------------------------------------------------------------
	//
	// The first rule ("Expr") is the start rule. Pegasus always begins
	// parsing from the first rule defined in the grammar.
	//
	// Precedence is encoded by nesting: lower-precedence operators
	// appear higher in the rule chain, so they bind less tightly.
	//
	// PEG ordered choice (/) means "try left first; if it fails, try right."
	// PEG repetition (*) means "zero or more."
	// { ... } creates a capture group.

	grammar := `
# ── Start rule ──────────────────────────────────────────────────
# Skip leading whitespace, then parse a full expression.
Expr      <- Space SubOp

# ── Precedence chain ────────────────────────────────────────────
# Each level tries the next-higher-precedence operator first,
# then optionally repeats with the current operator.

SubOp     <- AddOp (Sub AddOp)*    # lowest: subtraction
AddOp     <- DivOp (Add DivOp)*    # addition
DivOp     <- MulOp (Div MulOp)*    # division
MulOp     <- PowOp (Mul PowOp)*    # multiplication
PowOp     <- Term  (Pow Term)*     # highest binary: exponentiation

# ── Terms ───────────────────────────────────────────────────────
# A term is either a plain number or a parenthesized sub-expression.
Term      <- Atom / OParen Expr CParen

# ── Operators (each consumes trailing whitespace) ───────────────
Pow       <- '^' Space
Mul       <- '*' Space
Div       <- '/' Space
Add       <- '+' Space
Sub       <- '-' Space

# ── Delimiters ──────────────────────────────────────────────────
OParen    <- '(' Space
CParen    <- ')' Space

# ── Atoms ───────────────────────────────────────────────────────
Atom      <- Numeral

# ── Numerals ────────────────────────────────────────────────────
# A numeral is one or more digits followed by optional whitespace.
# { Numeral } would create a capture around the matched number.
Numeral   <- Number Space
Number    <- [0-9]+

# ── Whitespace ──────────────────────────────────────────────────
Space     <- (' ' / '\t' / EndOfLine)*
EndOfLine <- '\r\n' / '\n' / '\r'
EndOfFile <- !.
	`

	// ---------------------------------------------------------------
	// Test subjects
	// ---------------------------------------------------------------
	subjects := []string{
		"42",                     // simple number
		"1 + 2",                  // addition
		"3 * 4 + 5",             // precedence: (3*4) + 5
		"23 + 2 +(1* 2) ^ 2",   // mixed operators with parens
		"(1 + 2) * (3 + 4)",    // fully parenthesized
		"2 ^ 3 ^ 2",            // right-associative exponentiation
	}

	for subject in subjects {
		is_match, pos, captures, errs := pegasus.match(grammar, subject)

		if len(errs) > 0 {
			log.error("parse error for:", subject)
			for e in errs {
				log.error("  at position", e.pos, ":", e.message)
			}
			continue
		}

		if is_match {
			log.success("matched:", subject[:pos])
			if captures != nil {
				log.info("  captures:", captures)
			}
		} else {
			log.warning("no match for:", subject, "— consumed til position", pos)
		}
	}
}
