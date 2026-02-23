package pegasus

import "core:fmt"
import "core:testing"

// An EmptyOp specifies a kind or mixture of zero-width assertions.
// EmptyOp values are bit flags — each must be a distinct power of 2
// so they can be combined with |= and tested with & in the VM.
EmptyOp :: enum {
	BeginLine      = 1,
	EndLine        = 2,
	BeginText      = 4,
	EndText        = 8,
	WordBoundary   = 16,
	NoWordBoundary = 32,
}

// EmptyOpContext returns the zero-width assertions
// satisfied at the position between the runes r1 and r2.
// Passing r1 == -1 indicates that the position is
// at the beginning of the text.
// Passing r2 == -1 indicates that the position is
// at the end of the text.
empty_op_context :: proc(r1, r2: rune) -> EmptyOp {
	op := EmptyOp.NoWordBoundary
	boundary: byte
	switch {
	case is_word_char(r1):
		boundary = 1
	case r1 == '\n':
		op |= .BeginLine
	case r1 < 0:
		op |= .BeginText | .BeginLine
	}
	switch {
	case is_word_char(r2):
		boundary ~= 1
	case r2 == '\n':
		op |= .EndLine
	case r2 < 0:
		op |= .EndText | .EndLine
	}
	if boundary != 0 { 	// IsWordChar(r1) != IsWordChar(r2)
		op ~= (.WordBoundary | .NoWordBoundary)
	}
	return op
}

// IsWordChar reports whether r is considered a "word character"
// during the evaluation of the \b and \B zero-width assertions.
// These assertions are ASCII-only: the word characters are [A-Za-z0-9_].
is_word_char :: proc(r: rune) -> bool {
	// Test for lowercase letters first, as these occur more
	// frequently than uppercase letters in common cases.
	return(
		'a' <= r && r <= 'z' ||
		'A' <= r && r <= 'Z' ||
		'0' <= r && r <= '9' ||
		r == '_' \
	)
}

// --- Tests ---

// The VM checks assertions via: int(sat & op) != 0
// So a "satisfied" check means the bitwise AND of the result with
// the desired flag is non-zero.
satisfied :: proc(op: EmptyOp, flag: EmptyOp) -> bool {
	return int(op & flag) != 0
}

@(test)
test_is_word_char_lowercase :: proc(t: ^testing.T) {
	testing.expect(t, is_word_char('a'), "'a' should be word char")
	testing.expect(t, is_word_char('m'), "'m' should be word char")
	testing.expect(t, is_word_char('z'), "'z' should be word char")
}

@(test)
test_is_word_char_uppercase :: proc(t: ^testing.T) {
	testing.expect(t, is_word_char('A'), "'A' should be word char")
	testing.expect(t, is_word_char('M'), "'M' should be word char")
	testing.expect(t, is_word_char('Z'), "'Z' should be word char")
}

@(test)
test_is_word_char_digits :: proc(t: ^testing.T) {
	testing.expect(t, is_word_char('0'), "'0' should be word char")
	testing.expect(t, is_word_char('5'), "'5' should be word char")
	testing.expect(t, is_word_char('9'), "'9' should be word char")
}

@(test)
test_is_word_char_underscore :: proc(t: ^testing.T) {
	testing.expect(t, is_word_char('_'), "'_' should be word char")
}

@(test)
test_is_word_char_non_word :: proc(t: ^testing.T) {
	testing.expect(t, !is_word_char(' '), "space should not be word char")
	testing.expect(t, !is_word_char('.'), "'.' should not be word char")
	testing.expect(t, !is_word_char('-'), "'-' should not be word char")
	testing.expect(t, !is_word_char('\n'), "newline should not be word char")
	testing.expect(t, !is_word_char(0), "null should not be word char")
}

@(test)
test_is_word_char_negative_rune :: proc(t: ^testing.T) {
	// -1 is used as sentinel for beginning/end of text.
	testing.expect(t, !is_word_char(-1), "-1 sentinel should not be word char")
}

@(test)
test_empty_op_begin_text :: proc(t: ^testing.T) {
	// At beginning of text (r1=-1), before a word char 'a'.
	// op starts as NoWordBoundary(32).
	// r1 < 0 → op |= BeginText(4) | BeginLine(1) → 37.
	// r2='a' is word → boundary ^= 1 → 1.
	// boundary != 0 → op ^= (WordBoundary(16) | NoWordBoundary(32)) → 37 ^ 48 = 21.
	// Result: BeginLine(1) | BeginText(4) | WordBoundary(16) = 21.
	op := empty_op_context(-1, 'a')
	testing.expect(t, int(op) == 21, fmt.tprintf("expected 21, got %d", int(op)))
	testing.expect(t, satisfied(op, .BeginText), "BeginText should be satisfied")
	testing.expect(t, satisfied(op, .BeginLine), "BeginLine should be satisfied")
	testing.expect(t, satisfied(op, .WordBoundary), "WordBoundary should be satisfied")
}

@(test)
test_empty_op_end_text :: proc(t: ^testing.T) {
	// At end of text (r2=-1), after a word char 'a'.
	// op starts as NoWordBoundary(32).
	// r1='a' is word → boundary = 1.
	// r2 < 0 → op |= EndText(8) | EndLine(2) → 42.
	// boundary == 1 → op ^= (WordBoundary(16) | NoWordBoundary(32)) → 42 ^ 48 = 26.
	// Result: EndLine(2) | EndText(8) | WordBoundary(16) = 26.
	op := empty_op_context('a', -1)
	testing.expect(t, int(op) == 26, fmt.tprintf("expected 26, got %d", int(op)))
	testing.expect(t, satisfied(op, .EndText), "EndText should be satisfied")
	testing.expect(t, satisfied(op, .EndLine), "EndLine should be satisfied")
	testing.expect(t, satisfied(op, .WordBoundary), "WordBoundary should be satisfied")
}

@(test)
test_empty_op_both_sentinels :: proc(t: ^testing.T) {
	// Empty text: both r1=-1 and r2=-1.
	// op starts as NoWordBoundary(32).
	// r1 < 0 → op |= BeginText(4) | BeginLine(1) → 37.
	// r2 < 0 → op |= EndText(8) | EndLine(2) → 47.
	// boundary == 0 → no XOR.
	// Result: BeginLine(1) | EndLine(2) | BeginText(4) | EndText(8) | NoWordBoundary(32) = 47.
	op := empty_op_context(-1, -1)
	testing.expect(t, int(op) == 47, fmt.tprintf("expected 47, got %d", int(op)))
	testing.expect(t, satisfied(op, .BeginText), "BeginText should be satisfied")
	testing.expect(t, satisfied(op, .EndText), "EndText should be satisfied")
	testing.expect(t, satisfied(op, .EndLine), "EndLine should be satisfied")
	testing.expect(t, satisfied(op, .BeginLine), "BeginLine should be satisfied")
	testing.expect(t, satisfied(op, .NoWordBoundary), "NoWordBoundary should be satisfied")
	testing.expect(t, !satisfied(op, .WordBoundary), "WordBoundary should NOT be satisfied")
}

@(test)
test_empty_op_word_boundary :: proc(t: ^testing.T) {
	// Transition from non-word ' ' to word char 'a'.
	// op starts as NoWordBoundary(32).
	// r1=' ' → no case matches.
	// r2='a' is word → boundary ^= 1 → 1.
	// boundary != 0 → op ^= (WordBoundary(16) | NoWordBoundary(32)) → 32 ^ 48 = 16.
	// Result: WordBoundary(16) = 16.
	op := empty_op_context(' ', 'a')
	testing.expect(t, int(op) == 16, fmt.tprintf("expected 16, got %d", int(op)))
	testing.expect(t, satisfied(op, .WordBoundary), "WordBoundary should be satisfied")
	testing.expect(t, !satisfied(op, .NoWordBoundary), "NoWordBoundary should NOT be satisfied")
}

@(test)
test_empty_op_no_word_boundary :: proc(t: ^testing.T) {
	// Both word chars 'a' and 'b' = no word boundary.
	// op starts as NoWordBoundary(32).
	// r1='a' is word → boundary = 1.
	// r2='b' is word → boundary ^= 1 → 0.
	// boundary == 0 → no XOR.
	// Result: NoWordBoundary(32) = 32.
	op := empty_op_context('a', 'b')
	testing.expect(t, op == .NoWordBoundary, fmt.tprintf("expected NoWordBoundary(32), got %d", int(op)))
	testing.expect(t, satisfied(op, .NoWordBoundary), "NoWordBoundary should be satisfied")
	testing.expect(t, !satisfied(op, .WordBoundary), "WordBoundary should NOT be satisfied")
}

@(test)
test_empty_op_newline_begin_line :: proc(t: ^testing.T) {
	// After newline, before word char 'a'.
	// op starts as NoWordBoundary(32).
	// r1='\n' → op |= BeginLine(1) → 33.
	// r2='a' is word → boundary ^= 1 → 1.
	// boundary != 0 → op ^= (WordBoundary(16) | NoWordBoundary(32)) → 33 ^ 48 = 17.
	// Result: BeginLine(1) | WordBoundary(16) = 17.
	op := empty_op_context('\n', 'a')
	testing.expect(t, int(op) == 17, fmt.tprintf("expected 17, got %d", int(op)))
	testing.expect(t, satisfied(op, .BeginLine), "BeginLine should be satisfied")
	testing.expect(t, satisfied(op, .WordBoundary), "WordBoundary should be satisfied")
}

@(test)
test_empty_op_before_newline :: proc(t: ^testing.T) {
	// Before newline, after word char 'a'.
	// op starts as NoWordBoundary(32).
	// r1='a' is word → boundary = 1.
	// r2='\n' → op |= EndLine(2) → 34.
	// boundary == 1 → op ^= (WordBoundary(16) | NoWordBoundary(32)) → 34 ^ 48 = 18.
	// Result: EndLine(2) | WordBoundary(16) = 18.
	op := empty_op_context('a', '\n')
	testing.expect(t, int(op) == 18, fmt.tprintf("expected 18, got %d", int(op)))
	testing.expect(t, satisfied(op, .EndLine), "EndLine should be satisfied")
	testing.expect(t, satisfied(op, .WordBoundary), "WordBoundary should be satisfied")
}

@(test)
test_empty_op_word_boundary_at_text_start :: proc(t: ^testing.T) {
	// Beginning of text before a word char = same as test_empty_op_begin_text.
	// Result: BeginLine(1) | BeginText(4) | WordBoundary(16) = 21.
	op := empty_op_context(-1, 'a')
	testing.expect(t, int(op) == 21, fmt.tprintf("expected 21, got %d", int(op)))
	testing.expect(t, satisfied(op, .BeginText), "BeginText should be satisfied")
	testing.expect(t, satisfied(op, .WordBoundary), "WordBoundary should be satisfied")
}

@(test)
test_empty_op_word_boundary_at_text_end :: proc(t: ^testing.T) {
	// After word char 'z' at end of text.
	// Same as ('a', -1): EndLine(2) | EndText(8) | WordBoundary(16) = 26.
	op := empty_op_context('z', -1)
	testing.expect(t, int(op) == 26, fmt.tprintf("expected 26, got %d", int(op)))
	testing.expect(t, satisfied(op, .EndText), "EndText should be satisfied")
	testing.expect(t, satisfied(op, .WordBoundary), "WordBoundary should be satisfied")
}

@(test)
test_empty_op_non_word_to_non_word :: proc(t: ^testing.T) {
	// Both non-word, non-special chars = NoWordBoundary.
	// op starts as NoWordBoundary(32). No cases match. boundary == 0. No XOR.
	// Result: NoWordBoundary(32) = 32.
	op := empty_op_context(' ', '.')
	testing.expect(t, op == .NoWordBoundary, fmt.tprintf("expected NoWordBoundary(32), got %d", int(op)))
}

@(test)
test_empty_op_word_to_non_word :: proc(t: ^testing.T) {
	// Word char 'a' followed by non-word ' ' = word boundary.
	// op starts as NoWordBoundary(32).
	// r1='a' is word → boundary = 1.
	// r2=' ' → no case matches. boundary stays 1.
	// boundary != 0 → op ^= (WordBoundary(16) | NoWordBoundary(32)) → 32 ^ 48 = 16.
	// Result: WordBoundary(16) = 16.
	op := empty_op_context('a', ' ')
	testing.expect(t, int(op) == 16, fmt.tprintf("expected 16, got %d", int(op)))
	testing.expect(t, satisfied(op, .WordBoundary), "WordBoundary should be satisfied")
	testing.expect(t, !satisfied(op, .NoWordBoundary), "NoWordBoundary should NOT be satisfied")
}
