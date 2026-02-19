// JSON Parser Example — Pegasus PEG Parser
//
// Demonstrates a complete JSON grammar following RFC 8259.
// Handles all JSON value types: objects, arrays, strings, numbers,
// booleans (true/false), and null.
//
// This is a recognizer — it validates whether input is well-formed JSON.
// Add { ... } capture groups around rules to extract a parse tree.
//
// Usage:
//   odin run examples/json -collection:shared=lib

package json

import pegasus "shared:pegasus"
import log "shared:pegasus/log"

main :: proc() {
	// ---------------------------------------------------------------
	// Grammar: JSON (RFC 8259)
	// ---------------------------------------------------------------
	//
	// PEG is well-suited for JSON because:
	//   - JSON is unambiguous (no need for backtracking heuristics)
	//   - Ordered choice (/) naturally handles value alternatives
	//   - Character classes handle string escapes cleanly
	//
	// Key PEG features used:
	//   [...]   character class
	//   [^...]  negated character class
	//   !.      end of file (not-any = nothing left)
	//   *       zero or more
	//   +       one or more
	//   ?       optional

	grammar := `
# ── Start rule ──────────────────────────────────────────────────
# A JSON document is a single value surrounded by optional whitespace.
JSON          <- Spacing Value Spacing EndOfFile

# ── Values ──────────────────────────────────────────────────────
# A JSON value is one of: object, array, string, number, true, false, null.
# PEG ordered choice tries each alternative left-to-right.
Value         <- Object
              / Array
              / String
              / Number
              / True
              / False
              / Null

# ── Objects ─────────────────────────────────────────────────────
# { "key": value, "key": value, ... }
# An object is an opening brace, zero or more key-value pairs
# separated by commas, and a closing brace.
Object        <- '{' Spacing Members? '}' Spacing
Members       <- Pair (',' Spacing Pair)*
Pair          <- String ':' Spacing Value

# ── Arrays ──────────────────────────────────────────────────────
# [ value, value, ... ]
# An array is an opening bracket, zero or more values separated
# by commas, and a closing bracket.
Array         <- '[' Spacing Elements? ']' Spacing
Elements      <- Value (',' Spacing Value)*

# ── Strings ─────────────────────────────────────────────────────
# "..." with escape sequences: \", \\, \/, \b, \f, \n, \r, \t, \uXXXX
# Each StringChar is either an escape sequence or any character that
# is NOT a double-quote and NOT a backslash.
String        <- '"' StringChar* '"' Spacing
StringChar    <- '\\' EscapeChar
              / '\\' 'u' HexDigit HexDigit HexDigit HexDigit
              / !'"' !'\\' .
EscapeChar    <- '"' / '\\' / '/' / 'b' / 'f' / 'n' / 'r' / 't'
HexDigit      <- [0-9a-fA-F]

# ── Numbers ─────────────────────────────────────────────────────
# JSON numbers: optional minus, integer part, optional fraction,
# optional exponent. No leading zeros (except "0" itself).
Number        <- '-'? IntPart FracPart? ExpPart? Spacing
IntPart       <- '0' / [1-9] [0-9]*
FracPart      <- '.' [0-9]+
ExpPart       <- [eE] [+\-]? [0-9]+

# ── Keywords ────────────────────────────────────────────────────
True          <- 'true'  Spacing
False         <- 'false' Spacing
Null          <- 'null'  Spacing

# ── Whitespace ──────────────────────────────────────────────────
# JSON allows spaces, tabs, newlines, and carriage returns.
Spacing       <- [ \t\r\n]*
EndOfFile     <- !.
	`

	// ---------------------------------------------------------------
	// Test subjects — various JSON documents
	// ---------------------------------------------------------------
	subjects := []struct {
		label:   string,
		input:   string,
	}{
		{
			"null value",
			`null`,
		},
		{
			"boolean true",
			`true`,
		},
		{
			"integer",
			`42`,
		},
		{
			"negative decimal",
			`-3.14`,
		},
		{
			"simple string",
			`"hello world"`,
		},
		{
			"string with escapes",
			`"line1\nline2\ttab"`,
		},
		{
			"empty array",
			`[]`,
		},
		{
			"array of numbers",
			`[1, 2, 3]`,
		},
		{
			"empty object",
			`{}`,
		},
		{
			"simple object",
			`{"name": "pegasus", "version": 1}`,
		},
		{
			"nested structure",
			`{"users": [{"name": "Alice", "age": 30}, {"name": "Bob", "age": 25}], "count": 2}`,
		},
		{
			"scientific notation",
			`1.5e10`,
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
			log.success("[", s.label, "] valid JSON")
			if captures != nil {
				log.info("  captures:", captures)
			}
		} else if is_match {
			log.warning("[", s.label, "] partial match — consumed", pos, "of", len(s.input), "bytes")
		} else {
			log.error("[", s.label, "] invalid JSON — failed at position", pos)
		}
	}
}
