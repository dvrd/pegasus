package pegasus

import "charset"
import "core:testing"
import "core:mem/virtual"
import "core:fmt"

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

@(test)
test_pattern_constructors :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// literal
	p_lit := literal("abc")
	lit, ok_lit := p_lit.(^LiteralNode)
	testing.expect(t, ok_lit, "literal should produce LiteralNode")
	testing.expect(t, lit.str == "abc", fmt.tprintf("expected 'abc', got '%s'", lit.str))

	// any
	p_any := any(3)
	dot, ok_dot := p_any.(^DotNode)
	testing.expect(t, ok_dot, "any should produce DotNode")
	testing.expect(t, dot.n == 3, fmt.tprintf("expected n=3, got %d", dot.n))

	// optional
	p_opt := optional(literal("x"))
	_, ok_opt := p_opt.(^OptionalNode)
	testing.expect(t, ok_opt, "optional should produce OptionalNode")

	// not
	p_not := not(literal("x"))
	_, ok_not := p_not.(^NotNode)
	testing.expect(t, ok_not, "not should produce NotNode")

	// and
	p_and := and(literal("x"))
	_, ok_and := p_and.(^AndNode)
	testing.expect(t, ok_and, "and should produce AndNode")

	// star
	p_star := star(literal("x"))
	_, ok_star := p_star.(^StarNode)
	testing.expect(t, ok_star, "star should produce StarNode")

	// plus
	p_plus := plus(literal("x"))
	_, ok_plus := p_plus.(^PlusNode)
	testing.expect(t, ok_plus, "plus should produce PlusNode")

	// search
	p_search := search(literal("x"))
	_, ok_search := p_search.(^SearchNode)
	testing.expect(t, ok_search, "search should produce SearchNode")

	// emptyOp
	p_empty := emptyOp()
	_, ok_empty := p_empty.(^EmptyOpNode)
	testing.expect(t, ok_empty, "emptyOp should produce EmptyOpNode")

	// error
	p_err := error("bad", nil)
	err_node, ok_err := p_err.(^ErrorNode)
	testing.expect(t, ok_err, "error should produce ErrorNode")
	testing.expect(t, err_node.message == "bad", fmt.tprintf("expected message 'bad', got '%s'", err_node.message))

	// or (alternation)
	p_or := or(literal("a"), literal("b"))
	_, ok_or := p_or.(^AltNode)
	testing.expect(t, ok_or, "or should produce AltNode")

	// concat (sequence)
	p_seq := concat(literal("a"), literal("b"))
	_, ok_seq := p_seq.(^SeqNode)
	testing.expect(t, ok_seq, "concat should produce SeqNode")

	// repeat
	p_rep := repeat(literal("a"), 3)
	_, ok_rep := p_rep.(^SeqNode)
	testing.expect(t, ok_rep, "repeat(3) should produce SeqNode")

	// repeat(p, 0) should produce EmptyNode
	p_rep0 := repeat(literal("a"), 0)
	_, ok_rep0 := p_rep0.(^EmptyNode)
	testing.expect(t, ok_rep0, "repeat(0) should produce EmptyNode")

	// non_term
	p_nt := non_term("Foo")
	nt, ok_nt := p_nt.(^NonTermNode)
	testing.expect(t, ok_nt, "non_term should produce NonTermNode")
	testing.expect(t, nt.name == "Foo", fmt.tprintf("expected name 'Foo', got '%s'", nt.name))
}

@(test)
test_pattern_cap_and_memo :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// cap wrapping
	inner := literal("hello")
	p_cap := cap(inner, 42)
	cn, ok_cap := p_cap.(^CapNode)
	testing.expect(t, ok_cap, "cap should produce CapNode")
	testing.expect(t, cn.id == 42, fmt.tprintf("expected cap id=42, got %d", cn.id))
	_, ok_inner := cn.patt.(^LiteralNode)
	testing.expect(t, ok_inner, "cap inner should be LiteralNode")

	// memo wrapping
	inner2 := literal("world")
	p_memo := memo_pattern(inner2)
	mn, ok_memo := p_memo.(^MemoNode)
	testing.expect(t, ok_memo, "memo_pattern should produce MemoNode")
	_, ok_inner2 := mn.patt.(^LiteralNode)
	testing.expect(t, ok_inner2, "memo inner should be LiteralNode")
	testing.expect(t, mn.id >= 0, fmt.tprintf("memo id should be >= 0, got %d", mn.id))
}
