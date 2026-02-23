package pegasus

import "charset"
import "core:testing"
import "core:mem/virtual"
import "core:fmt"

// A Pattern is an object that can be compiled into a parsing program.
Pattern :: union {
	^AltNode,
	^SeqNode,
	^StarNode,
	^PlusNode,
	^OptionalNode,
	^NotNode,
	^AndNode,
	^CapNode,
	^MemoNode,
	^CheckNode,
	^GrammarNode,
	^SearchNode,
	^RepeatNode,
	^ClassNode,
	^LiteralNode,
	^NonTermNode,
	^DotNode,
	^ErrorNode,
	^EmptyOpNode,
	^EmptyNode,
}


// AltNode is the binary operator for alternation.
AltNode :: struct {
	left:  Pattern,
	right: Pattern,
}

// SeqNode is the binary operator for sequences.
SeqNode :: struct {
	left:  Pattern,
	right: Pattern,
}

// StarNode is the operator for the Kleene star.
StarNode :: struct {
	patt: Pattern,
}

// PlusNode is the operator for the Kleene plus.
PlusNode :: struct {
	patt: Pattern,
}

// OptionalNode is the operator for making a pattern optional.
OptionalNode :: struct {
	patt: Pattern,
}

// NotNode is the not predicate.
NotNode :: struct {
	patt: Pattern,
}

// AndNode is the and predicate.
AndNode :: struct {
	patt: Pattern,
}

// CapNode marks a pattern to be captured with a certain ID.
CapNode :: struct {
	patt: Pattern,
	id:   int,
}

// MemoNode marks a pattern to be memoized with a certain ID.
MemoNode :: struct {
	patt: Pattern,
	id:   int,
}

// CheckNode marks a pattern to be checker by a certain checker.
CheckNode :: struct {
	patt:    Pattern,
	checker: Checker,
	id:      int,
	flag:    int,
}

// GrammarNode represents a grammar of non-terminals and their associated
// patterns. The Grammar must also have an entry non-terminal.
GrammarNode :: struct {
	defs:  map[string]Pattern,
	start: string,
}

// SearchNode represents a search for a certain pattern.
SearchNode :: struct {
	patt: Pattern,
}

// RepeatNode represents the repetition of a pattern a constant number of
// times.
RepeatNode :: struct {
	patt: Pattern,
	n:    int,
}

// ClassNode represents a character set.
ClassNode :: struct {
	chars: ^charset.Set,
}

// LiteralNode represents a literal string.
LiteralNode :: struct {
	str: string,
}

// NonTermNode represents the use of a non-terminal. If this non-terminal is
// inlined during compilation, the `inlined` field will point to the pattern
// that is inlined.
NonTermNode :: struct {
	name:    string,
	inlined: Pattern,
}

// DotNode represents the pattern to match any byte.
DotNode :: struct {
	n: u8,
}

// ErrorNode represents a pattern that fails with a certain error message.
ErrorNode :: struct {
	message: string,
	recover: Pattern,
}

// EmptyOpNode is a node that performs a zero-width assertion.
EmptyOpNode :: struct {
	op: EmptyOp,
}


// EmtpyNode represents the empty pattern.
EmptyNode :: struct {}

// WalkFunc is a function that takes a pattern.
WalkFunc :: proc(sub: Pattern)

// CountSubPatterns returns the number of subpatterns that exist in the given
// pattern.
count_sub_patterns :: proc(p: Pattern) -> int {
	count := 0
	context.user_ptr = &count
	fn := proc(sub: Pattern) {
		count := cast(^int)context.user_ptr
		count^ += 1
	}
	walk_pattern(p, true, fn)
	return count
}

// WalkPattern calls fn for every subpattern contained in p. If followInline
// is true, WalkPattern will walk over inlined patterns as well.
walk_pattern :: proc(p: Pattern, followInline: bool, fn: WalkFunc) {
	fn(p)
	#partial switch t in p {
	case ^AltNode:
		walk_pattern(t.left, followInline, fn)
		walk_pattern(t.right, followInline, fn)
	case ^SeqNode:
		walk_pattern(t.left, followInline, fn)
		walk_pattern(t.right, followInline, fn)
	case ^StarNode:
		walk_pattern(t.patt, followInline, fn)
	case ^PlusNode:
		walk_pattern(t.patt, followInline, fn)
	case ^OptionalNode:
		walk_pattern(t.patt, followInline, fn)
	case ^NotNode:
		walk_pattern(t.patt, followInline, fn)
	case ^AndNode:
		walk_pattern(t.patt, followInline, fn)
	case ^CapNode:
		walk_pattern(t.patt, followInline, fn)
	case ^MemoNode:
		walk_pattern(t.patt, followInline, fn)
	case ^SearchNode:
		walk_pattern(t.patt, followInline, fn)
	case ^CheckNode:
		walk_pattern(t.patt, followInline, fn)
	case ^ErrorNode:
		walk_pattern(t.recover, followInline, fn)
	case ^GrammarNode:
		for k in t.defs {
			walk_pattern(t.defs[k], followInline, fn)
		}
	case ^NonTermNode:
		if t.inlined != nil && followInline {
			walk_pattern(t.inlined, followInline, fn)
		}
	}
}

// -- Test helpers --

// walk_count counts how many times fn is called during walk_pattern.
walk_count :: proc(p: Pattern, followInline: bool) -> int {
	count := 0
	context.user_ptr = &count
	fn := proc(sub: Pattern) {
		c := cast(^int)context.user_ptr
		c^ += 1
	}
	walk_pattern(p, followInline, fn)
	return count
}

// -- Tests --

@(test)
test_walk_pattern_leaf_literal :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	lit := new(LiteralNode)
	lit.str = "hello"
	p: Pattern = lit

	c := walk_count(p, false)
	testing.expect(t, c == 1, fmt.tprintf("leaf literal should visit 1 node, got %d", c))
}

@(test)
test_walk_pattern_leaf_dot :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	dot := new(DotNode)
	dot.n = 1
	p: Pattern = dot

	c := walk_count(p, false)
	testing.expect(t, c == 1, fmt.tprintf("leaf dot should visit 1 node, got %d", c))
}

@(test)
test_walk_pattern_leaf_empty :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	e := new(EmptyNode)
	p: Pattern = e

	c := walk_count(p, false)
	testing.expect(t, c == 1, fmt.tprintf("leaf empty should visit 1 node, got %d", c))
}

@(test)
test_walk_pattern_unary_star :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	lit := new(LiteralNode)
	lit.str = "a"
	star := new(StarNode)
	star.patt = lit
	p: Pattern = star

	// Star + Literal = 2 visits
	c := walk_count(p, false)
	testing.expect(t, c == 2, fmt.tprintf("star(literal) should visit 2, got %d", c))
}

@(test)
test_walk_pattern_unary_plus :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	lit := new(LiteralNode)
	lit.str = "b"
	plus := new(PlusNode)
	plus.patt = lit
	p: Pattern = plus

	c := walk_count(p, false)
	testing.expect(t, c == 2, fmt.tprintf("plus(literal) should visit 2, got %d", c))
}

@(test)
test_walk_pattern_unary_optional :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	lit := new(LiteralNode)
	lit.str = "c"
	opt := new(OptionalNode)
	opt.patt = lit
	p: Pattern = opt

	c := walk_count(p, false)
	testing.expect(t, c == 2, fmt.tprintf("optional(literal) should visit 2, got %d", c))
}

@(test)
test_walk_pattern_unary_not :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	dot := new(DotNode)
	dot.n = 1
	not := new(NotNode)
	not.patt = dot
	p: Pattern = not

	c := walk_count(p, false)
	testing.expect(t, c == 2, fmt.tprintf("not(dot) should visit 2, got %d", c))
}

@(test)
test_walk_pattern_unary_and :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	lit := new(LiteralNode)
	lit.str = "x"
	and := new(AndNode)
	and.patt = lit
	p: Pattern = and

	c := walk_count(p, false)
	testing.expect(t, c == 2, fmt.tprintf("and(literal) should visit 2, got %d", c))
}

@(test)
test_walk_pattern_binary_alt :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	l := new(LiteralNode)
	l.str = "a"
	r := new(LiteralNode)
	r.str = "b"
	alt := new(AltNode)
	alt.left = l
	alt.right = r
	p: Pattern = alt

	// Alt + left + right = 3
	c := walk_count(p, false)
	testing.expect(t, c == 3, fmt.tprintf("alt(lit, lit) should visit 3, got %d", c))
}

@(test)
test_walk_pattern_binary_seq :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	l := new(LiteralNode)
	l.str = "a"
	r := new(LiteralNode)
	r.str = "b"
	seq := new(SeqNode)
	seq.left = l
	seq.right = r
	p: Pattern = seq

	c := walk_count(p, false)
	testing.expect(t, c == 3, fmt.tprintf("seq(lit, lit) should visit 3, got %d", c))
}

@(test)
test_walk_pattern_nested_tree :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Build: Star(Seq(Literal("a"), Literal("b")))
	a := new(LiteralNode)
	a.str = "a"
	b := new(LiteralNode)
	b.str = "b"
	seq := new(SeqNode)
	seq.left = a
	seq.right = b
	star := new(StarNode)
	star.patt = seq
	p: Pattern = star

	// Star + Seq + Literal + Literal = 4
	c := walk_count(p, false)
	testing.expect(t, c == 4, fmt.tprintf("star(seq(lit,lit)) should visit 4, got %d", c))
}

@(test)
test_walk_pattern_cap_memo_search :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	lit := new(LiteralNode)
	lit.str = "x"

	cap := new(CapNode)
	cap.patt = lit
	cap.id = 1

	mem := new(MemoNode)
	mem.patt = cap
	mem.id = 2

	srch := new(SearchNode)
	srch.patt = mem
	p: Pattern = srch

	// Search + Memo + Cap + Literal = 4
	c := walk_count(p, false)
	testing.expect(t, c == 4, fmt.tprintf("search(memo(cap(lit))) should visit 4, got %d", c))
}

@(test)
test_walk_pattern_error_node :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	lit := new(LiteralNode)
	lit.str = "recovery"
	err := new(ErrorNode)
	err.message = "expected something"
	err.recover = lit
	p: Pattern = err

	// Error + Literal(recover) = 2
	c := walk_count(p, false)
	testing.expect(t, c == 2, fmt.tprintf("error(literal) should visit 2, got %d", c))
}

@(test)
test_walk_pattern_nonterm_no_inline :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	lit := new(LiteralNode)
	lit.str = "inlined"
	nt := new(NonTermNode)
	nt.name = "Foo"
	nt.inlined = lit
	p: Pattern = nt

	// followInline=false: only visits NonTerm itself
	c := walk_count(p, false)
	testing.expect(t, c == 1, fmt.tprintf("nonterm with followInline=false should visit 1, got %d", c))
}

@(test)
test_walk_pattern_nonterm_with_inline :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	lit := new(LiteralNode)
	lit.str = "inlined"
	nt := new(NonTermNode)
	nt.name = "Foo"
	nt.inlined = lit
	p: Pattern = nt

	// followInline=true: visits NonTerm + inlined Literal
	c := walk_count(p, true)
	testing.expect(t, c == 2, fmt.tprintf("nonterm with followInline=true should visit 2, got %d", c))
}

@(test)
test_walk_pattern_nonterm_nil_inlined :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	nt := new(NonTermNode)
	nt.name = "Bar"
	// inlined is nil
	p: Pattern = nt

	// Even with followInline=true, nil inlined means just 1 visit
	c := walk_count(p, true)
	testing.expect(t, c == 1, fmt.tprintf("nonterm with nil inlined should visit 1, got %d", c))
}

@(test)
test_walk_pattern_grammar_node :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	a := new(LiteralNode)
	a.str = "a"
	b := new(LiteralNode)
	b.str = "b"

	g := new(GrammarNode)
	g.start = "A"
	g.defs = make(map[string]Pattern)
	g.defs["A"] = a
	g.defs["B"] = b
	p: Pattern = g

	// Grammar + Literal("a") + Literal("b") = 3
	c := walk_count(p, false)
	testing.expect(t, c == 3, fmt.tprintf("grammar with 2 defs should visit 3, got %d", c))
}

@(test)
test_walk_pattern_check_node :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	lit := new(LiteralNode)
	lit.str = "checked"
	chk := new(CheckNode)
	chk.patt = lit
	chk.id = 1
	p: Pattern = chk

	// Check + Literal = 2
	c := walk_count(p, false)
	testing.expect(t, c == 2, fmt.tprintf("check(literal) should visit 2, got %d", c))
}

@(test)
test_count_sub_patterns_leaf :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	lit := new(LiteralNode)
	lit.str = "hello"
	p: Pattern = lit

	c := count_sub_patterns(p)
	testing.expect(t, c == 1, fmt.tprintf("count_sub_patterns leaf should be 1, got %d", c))
}

@(test)
test_count_sub_patterns_nested :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Alt(Star(Literal("a")), Plus(Literal("b")))
	a := new(LiteralNode)
	a.str = "a"
	b := new(LiteralNode)
	b.str = "b"
	star := new(StarNode)
	star.patt = a
	plus := new(PlusNode)
	plus.patt = b
	alt := new(AltNode)
	alt.left = star
	alt.right = plus
	p: Pattern = alt

	// Alt + Star + Literal + Plus + Literal = 5
	c := count_sub_patterns(p)
	testing.expect(t, c == 5, fmt.tprintf("count_sub_patterns nested should be 5, got %d", c))
}

@(test)
test_walk_pattern_repeat_node :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	lit := new(LiteralNode)
	lit.str = "r"
	rep := new(RepeatNode)
	rep.patt = lit
	rep.n = 3
	p: Pattern = rep

	// RepeatNode is not in the walk_pattern switch (uses #partial switch)
	// so only the RepeatNode itself is visited, not its child
	c := walk_count(p, false)
	testing.expect(t, c == 1, fmt.tprintf("repeat(literal) should visit 1 (not walked), got %d", c))
}
