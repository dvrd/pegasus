package pegasus

import "charset"

// Cap marks a pattern to be captured.
cap :: proc(
	p: Pattern,
	id: int,
	allocator := context.allocator,
) -> (
	np: Pattern,
) {
	np = new(CapNode)
	np.(^CapNode).patt = p
	np.(^CapNode).id = id
	return
}

// Check marks a pattern to be checked with the given checker.
check_pattern :: proc(p: Pattern, c: Checker) -> (np: Pattern) {
	np = new(CheckNode)
	np.(^CheckNode).patt = p
	np.(^CheckNode).checker = c
	return
}

check_pattern_with_flags :: proc(
	p: Pattern,
	c: Checker,
	id, flag: int,
) -> (
	np: Pattern,
) {
	np = new(CheckNode)
	np.(^CheckNode).patt = p
	np.(^CheckNode).checker = c
	np.(^CheckNode).id = id
	np.(^CheckNode).flag = flag
	return
}

MEMO_ID := 0

// MemoId marks a pattern as memoizable with a particular ID.
memo_id :: proc(p: Pattern, id: int) -> (m: Pattern) {
	m = new(MemoNode)
	m.(^MemoNode).patt = p
	m.(^MemoNode).id = id
	MEMO_ID = max(MEMO_ID, id) + 1
	return
}

// Memo marks a pattern as memoizable.
memo_pattern :: proc(p: Pattern) -> (m: Pattern) {
	m = new(MemoNode)
	m.(^MemoNode).patt = p
	m.(^MemoNode).id = MEMO_ID
	MEMO_ID += 1
	return
}

// Literal matches a given string literal.
literal :: proc(s: string) -> (p: Pattern) {
	p = new(LiteralNode)
	p.(^LiteralNode).str = s
	return
}

// Set matches any character in the given set.
set :: proc(chars: ^charset.Set) -> (p: Pattern) {
	p = new(ClassNode)
	c := new(charset.Set)
	c.bits = chars.bits
	p.(^ClassNode).chars = c
	return
}

// Any consumes n characters, and only fails if there
// aren't enough input characters left.
any :: proc(n: u8) -> (p: Pattern) {
	p = new(DotNode)
	p.(^DotNode).n = n
	return
}

// Repeat matches p exactly n times
repeat :: proc(p: Pattern, n: int) -> (np: Pattern) {
	if n <= 0 {
		np = new(EmptyNode)
		return
	}

	acc := p
	for i := 1; i < n; i += 1 {
		np = new(SeqNode)
		np.(^SeqNode).left = acc
		np.(^SeqNode).right = p
		acc = np
	}

	return acc
}

// Concat concatenates n patterns: `p1 p2 p3...`.
concat :: proc(
	patts: ..Pattern,
	allocator := context.allocator,
) -> (
	np: Pattern,
) {
	if len(patts) <= 0 {
		np = new(EmptyNode, allocator)
		return
	}

	acc := patts[0]
	for p in patts[1:] {
		np = new(SeqNode, allocator)
		np.(^SeqNode).left = acc
		np.(^SeqNode).right = p
		acc = np
	}
	np = acc

	return
}

// Or returns the ordered choice between n patterns: `p1 / p2 / p3...`.
or :: proc(patts: ..Pattern, allocator := context.allocator) -> (np: Pattern) {
	if len(patts) <= 0 {
		np = new(EmptyNode, allocator)
		return
	}

	// optimization: make or right associative
	acc := patts[len(patts) - 1]
	for i := len(patts) - 2; i >= 0; i -= 1 {
		np = new(AltNode, allocator)
		np.(^AltNode).left = patts[i]
		np.(^AltNode).right = acc
		acc = np
	}
	np = acc

	return
}

// Star returns the Kleene star repetition of a pattern: `p*`.
// This matches zero or more occurrences of p.
star :: proc(p: Pattern, allocator := context.allocator) -> (np: Pattern) {
	np = new(StarNode, allocator)
	np.(^StarNode).patt = p
	return
}

// Plus returns the Kleene plus repetition of a pattern: `p+`.
// This matches one or more occurrences of p.
plus :: proc(p: Pattern, allocator := context.allocator) -> (np: Pattern) {
	np = new(PlusNode, allocator)
	np.(^PlusNode).patt = p
	return
}

// Optional matches at most 1 occurrence of p: `p?`.
optional :: proc(p: Pattern, allocator := context.allocator) -> (np: Pattern) {
	np = new(OptionalNode, allocator)
	np.(^OptionalNode).patt = p
	return
}

// Not returns the not predicate applied to a pattern: `!p`.
// The not predicate succeeds if matching `p` at the current position
// fails, and does not consume any input.
not :: proc(p: Pattern, allocator := context.allocator) -> (np: Pattern) {
	np = new(NotNode, allocator)
	np.(^NotNode).patt = p
	return
}

// And returns the and predicate applied to a pattern: `&p`.
// The and predicate succeeds if matching `p` at the current position
// succeeds and does not consume any input.
// This is equivalent to `!!p`.
and :: proc(p: Pattern, allocator := context.allocator) -> (np: Pattern) {
	np = new(AndNode, allocator)
	np.(^AndNode).patt = p
	return
}

// Search is a dedicated operator for creating searches. It will match
// the first occurrence of the given pattern. Use Star(Search(p)) to match
// the last occurrence (for a non-overlapping pattern).
search :: proc(p: Pattern, allocator := context.allocator) -> (np: Pattern) {
	np = new(SearchNode, allocator)
	np.(^SearchNode).patt = p
	return
}

// (op: syntax.EmptyOp)?
emptyOp :: proc(allocator := context.allocator) -> (np: Pattern) {
	np = new(EmptyOpNode, allocator) // Op: op
	return

}

// NonTerm builds an unresolved non-terminal with a given name.
// NonTerms should be used together with `Grammar` to build a recursive
// grammar.
non_term :: proc(
	name: string,
	allocator := context.allocator,
) -> (
	np: Pattern,
) {
	np = new(NonTermNode, allocator) // Op: op
	np.(^NonTermNode).name = name
	return
}

// Grammar builds a grammar from a map of non-terminal patterns.
// Any unresolved non-terminals are resolved with their definitions
// in the map.
grammar :: proc(
	start: string,
	nonterms: map[string]Pattern,
	allocator := context.allocator,
) -> (
	np: Pattern,
) {
	np = new(GrammarNode, allocator)
	np.(^GrammarNode).defs = nonterms
	np.(^GrammarNode).start = start
	return
}

cap_grammar :: proc(start: string, nonterms: map[string]Pattern) -> Pattern {
	m := make(map[string]Pattern)
	id := 0
	for k, v in nonterms {
		m[k] = cap(v, id)
		id += 1
	}
	return grammar(start, m)
}

// Error is a pattern that throws an error with the given message.
error :: proc(
	msg: string,
	recovery: Pattern,
	allocator := context.allocator,
) -> (
	np: Pattern,
) {
	np = new(ErrorNode, allocator)
	np.(^ErrorNode).message = msg
	np.(^ErrorNode).recover = recovery
	return
}
