package pegasus

// An EmptyOp specifies a kind or mixture of zero-width assertions.
EmptyOp :: enum {
	BeginLine,
	EndLine,
	BeginText,
	EndText,
	WordBoundary,
	NoWordBoundary,
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

// IsWordChar reports whether r is considered a “word character”
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
