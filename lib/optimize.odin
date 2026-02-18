#+feature dynamic-literals
package pegasus

import "charset"
import "core:fmt"
import "core:mem/virtual"
import "core:testing"

// Nodes with trees larger than this size will not be inlined.
InlineThreshold :: 100

// Inline performs inlining passes until the inliner reaches a steady-state.
inline_grammar :: proc(p: ^GrammarNode) {
	for grammar_node_inline(p) {}
}

// Get returns a possibly optimized version of this pattern. Always use this
// function to read a pattern, especially if you will be using the types of the
// underlying nodes. This function performs optimizations like collapsing an
// alternation of two class nodes into one class node.
get_pattern :: proc(p: Pattern) -> Pattern {
	#partial switch t in p {
	case ^NonTermNode:
		// Return the inlined pattern for a non-terminal that has been inlined.
		if t.inlined != nil {
			return t.inlined
		}
	case ^AltNode:
		l, r := get_pattern(t.left), get_pattern(t.right)
		_, emptyL := l.(^EmptyNode);if emptyL {
			return l
		}
		_, emptyR := r.(^EmptyNode);if emptyR {
			return get_pattern(optional(l))
		}

		// Combine the left and right sides of an alternation into a class node
		// if possible.
		set, ok := combine(l, r);if ok {
			np := new(ClassNode)
			np.chars = set
			return p
		}
	case ^OptionalNode:
		// Optional of a Kleene star is unnecessary and we can remove the
		// optional.
		np := get_pattern(t.patt)
		_, ok := np.(^StarNode);if ok {
			return np
		}
	case ^SeqNode:
		// optimize use of empty: `a ""` and `"" a` are just `a`.
		l := get_pattern(t.left)
		r := get_pattern(t.right)
		if _, emptyR := r.(^EmptyNode); emptyR {
			return l
		}
		if _, emptyL := l.(^EmptyNode); emptyL {
			return r
		}

		// This optimizes patterns like `![a-z] .`. Instead of using a not
		// predicate in this case, we can just complement the set and use a
		// class node.
		nn, okl := l.(^NotNode);if !okl {
			break
		}

		set: ^charset.Set
		#partial switch lt in get_pattern(nn.patt) {
		case ^LiteralNode:
			if len(lt.str) != 1 {
				return p
			}
			set = charset.new_charset([]byte{lt.str[0]})
		case ^ClassNode:
			set = lt.chars
		case:
			return p
		}

		#partial switch rt in r {
		case ^DotNode:
			if rt.n == 1 {
				np := new(ClassNode)
				np.chars = charset.complement(set)
				return np
			}
		case ^ClassNode:
			np := new(ClassNode)
			np.chars = charset.sub(rt.chars, set)
			return np
		case ^LiteralNode:
			if len(rt.str) == 1 {
				np := new(ClassNode)
				np.chars = charset.sub(
					charset.new_charset([]byte{rt.str[0]}),
					set,
				)
				return np
			}
		}
	}
	return p
}

// Performs inlining on a grammar node.
grammar_node_inline :: proc(p: ^GrammarNode) -> bool {
	sizes := make(map[string]int)
	leaves := make(map[string]bool)

	fn: proc(s: Pattern)
	for sub in p.defs {
		size := 0
		leaf := true
		context_map: struct {
			size: ^int,
			leaf: ^bool,
		} = {&size, &leaf}
		context.user_ptr = &context_map
		fn = proc(s: Pattern) {
			context_map := cast(^struct {
				size: ^int,
				leaf: ^bool,
			})context.user_ptr
			#partial switch t in s {
			case ^NonTermNode:
				if t.inlined == nil {
					context_map.leaf^ = false
				}
			}
			context_map.size^ += 1
		}
		walk_pattern(p.defs[sub], true, fn)
		sizes[sub] = size
		leaves[sub] = leaf
	}

	did_inline := false

	context_map: struct {
		sizes:      ^map[string]int,
		leaves:     ^map[string]bool,
		did_inline: ^bool,
		p:          ^GrammarNode,
	} = {&sizes, &leaves, &did_inline, p}
	context.user_ptr = &context_map

	fn = proc(s: Pattern) {
		context_map := cast(^struct {
			sizes:      ^map[string]int,
			leaves:     ^map[string]bool,
			did_inline: ^bool,
			p:          ^GrammarNode,
		})context.user_ptr

		#partial switch t in s {
		case ^NonTermNode:
			sz := context_map.sizes[t.name];if t.inlined == nil {
				// We only inline nodes if they are small enough and don't use
				// any non-terminals themselves.
				if sz < InlineThreshold && context_map.leaves[t.name] {
					context_map.did_inline^ = true
					t.inlined = context_map.p.defs[t.name]
				}
			}
		}
	}
	walk_pattern(p, true, fn)
	return did_inline
}

// If the bytes matched by p1 and p2 can be matched by a single charset, then
// that single combined charset is returned.
combine :: proc(p1: Pattern, p2: Pattern) -> (^charset.Set, bool) {
	set: ^charset.Set
	#partial switch t1 in p1 {
	case ^LiteralNode:
		if len(t1.str) != 1 {
			return set, false
		}
		#partial switch t2 in p2 {
		case ^ClassNode:
			return charset.add(
					t2.chars,
					charset.new_charset([]byte{t1.str[0]}),
				),
				true
		case ^LiteralNode:
			if len(t2.str) != 1 {
				return set, false
			}
			return charset.new_charset([]byte{t1.str[0], t2.str[0]}), true
		}
	case ^ClassNode:
		#partial switch t2 in p2 {
		case ^ClassNode:
			return charset.add(t2.chars, t1.chars), true
		case ^LiteralNode:
			if len(t2.str) != 1 {
				return set, false
			}
			return charset.add(
					t1.chars,
					charset.new_charset([]byte{t2.str[0]}),
				),
				true
		}
	}
	return set, false
}

// Returns the next uction in p, skipping labels and nops.
// If false is returned, there is no next uction.
next_insn :: proc(p: ProgramSlice) -> (Instruction, bool) {
	for i := 0; i < len(p); i += 1 {
		#partial switch t in p[i] {
		case Label, Nop:
			continue
		case:
			return p[i], true
		}
	}

	return Nop{}, false
}

// Returns the index of the next uction and if there was a label before
// it.
next_insn_label :: proc(p: ProgramSlice) -> (int, bool) {
	had_label := false
	for i := 0; i < len(p); i += 1 {
		#partial switch t in p[i] {
		case Nop:
			continue
		case Label:
			had_label = true
		case:
			return i, had_label
		}
	}

	return -1, had_label
}

// Optimize performs some optimization passes on the code in p. In particular
// it performs head-fail optimization and jump replacement.
optimize :: proc(p: ^Program) {
	// map from label to index in code
	labels := make(map[Label]int)
	i := 0
	for insn in p {
		#partial switch l in insn {
		case Label:
			labels[l] = i
		}
		i += 1
	}

	i = 0
	for insn in p {
		// head-fail optimization: if we find a choice uction immediately
		// followed (no label) by Char/Set/Any, we can replace with the
		// dedicated uction TestChar/TestSet/TestAny.
		ch, ok := insn.(Choice);if ok && i < len(p) - 1 {
			next := p[i + 1]
			#partial switch t in next {
			case Char:
				p[i] = TestChar{rune(t.byte), ch.lbl}
				p[i + 1] = Nop{}
			case Set:
				p[i] = TestSet{t.chars^, ch.lbl}
				p[i + 1] = Nop{}
			case Any:
				p[i] = TestAny{t.n, ch.lbl}
				p[i + 1] = Nop{}
			}
		}

		// jump optimization: if we find a jump to another control flow
		// uction, we can replace the current jump directly with the
		// target uction.
		j: Jump
		j, ok = insn.(Jump);if ok {
			next: Instruction
			next, ok = next_insn(p[labels[j.lbl]:]);if ok {
				#partial switch t in next {
				case PartialCommit, BackCommit, Commit, Jump, Return, Fail, FailTwice, End:
					p[i] = next
				}
			}
		}
		i += 1
	}
}

// --- Tests ---

@(test)
test_combine_two_single_literals :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	p1 := literal("a")
	p2 := literal("b")
	s, ok := combine(p1, p2)
	testing.expect(t, ok, "combine two single-char literals should succeed")
	testing.expect(t, charset.has(s, 'a'), "combined set should contain 'a'")
	testing.expect(t, charset.has(s, 'b'), "combined set should contain 'b'")
	testing.expect(t, !charset.has(s, 'c'), "combined set should not contain 'c'")
}

@(test)
test_combine_literal_and_class :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	p1 := literal("x")
	p2 := set(charset.range('a', 'c'))
	s, ok := combine(p1, p2)
	testing.expect(t, ok, "combine literal + class should succeed")
	testing.expect(t, charset.has(s, 'x'), "combined set should contain 'x'")
	testing.expect(t, charset.has(s, 'a'), "combined set should contain 'a'")
	testing.expect(t, charset.has(s, 'c'), "combined set should contain 'c'")
}

@(test)
test_combine_class_and_literal :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	p1 := set(charset.range('0', '9'))
	p2 := literal("z")
	s, ok := combine(p1, p2)
	testing.expect(t, ok, "combine class + literal should succeed")
	testing.expect(t, charset.has(s, '0'), "combined set should contain '0'")
	testing.expect(t, charset.has(s, 'z'), "combined set should contain 'z'")
}

@(test)
test_combine_two_classes :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	p1 := set(charset.range('a', 'c'))
	p2 := set(charset.range('x', 'z'))
	s, ok := combine(p1, p2)
	testing.expect(t, ok, "combine two classes should succeed")
	testing.expect(t, charset.has(s, 'a'), "combined set should contain 'a'")
	testing.expect(t, charset.has(s, 'z'), "combined set should contain 'z'")
	testing.expect(t, !charset.has(s, 'm'), "combined set should not contain 'm'")
}

@(test)
test_combine_multi_char_literal_fails :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	p1 := literal("ab")
	p2 := literal("c")
	_, ok := combine(p1, p2)
	testing.expect(t, !ok, "combine multi-char literal should fail")
}

@(test)
test_combine_incompatible_types_fails :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	p1 := any(1)
	p2 := literal("a")
	_, ok := combine(p1, p2)
	testing.expect(t, !ok, "combine DotNode + literal should fail")
}

@(test)
test_get_pattern_optional_of_star_collapses :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// optional(star(x)) should collapse to star(x)
	inner := star(literal("a"))
	p := optional(inner)
	result := get_pattern(p)
	_, is_star := result.(^StarNode)
	testing.expect(t, is_star, "optional(star(x)) should collapse to StarNode")
}

@(test)
test_get_pattern_seq_with_empty_right :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// seq(literal("a"), empty) should return literal("a")
	empty_node: Pattern = new(EmptyNode)
	p := concat(literal("a"), empty_node)
	result := get_pattern(p)
	lit, is_lit := result.(^LiteralNode)
	testing.expect(t, is_lit, "seq(x, empty) should return x")
	if is_lit {
		testing.expect(t, lit.str == "a", fmt.tprintf("expected 'a', got '%s'", lit.str))
	}
}

@(test)
test_get_pattern_seq_with_empty_left :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// seq(empty, literal("b")) should return literal("b")
	empty_node: Pattern = new(EmptyNode)
	p := concat(empty_node, literal("b"))
	result := get_pattern(p)
	lit, is_lit := result.(^LiteralNode)
	testing.expect(t, is_lit, "seq(empty, x) should return x")
	if is_lit {
		testing.expect(t, lit.str == "b", fmt.tprintf("expected 'b', got '%s'", lit.str))
	}
}

@(test)
test_get_pattern_alt_with_empty_right_becomes_optional :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// alt(literal("a"), empty) — the empty right triggers optional(left)
	empty_node: Pattern = new(EmptyNode)
	alt_node := new(AltNode)
	alt_node.left = literal("a")
	alt_node.right = empty_node
	p: Pattern = alt_node
	result := get_pattern(p)
	_, is_opt := result.(^OptionalNode)
	testing.expect(t, is_opt, "alt(x, empty) should become optional(x)")
}

@(test)
test_get_pattern_nonterm_inlined :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// NonTermNode with inlined pattern should return the inlined pattern.
	nt := new(NonTermNode)
	nt.name = "Foo"
	nt.inlined = literal("bar")
	p: Pattern = nt
	result := get_pattern(p)
	lit, is_lit := result.(^LiteralNode)
	testing.expect(t, is_lit, "inlined NonTermNode should return inlined pattern")
	if is_lit {
		testing.expect(t, lit.str == "bar", fmt.tprintf("expected 'bar', got '%s'", lit.str))
	}
}

@(test)
test_get_pattern_passthrough :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Patterns that don't match any optimization case return unchanged.
	p := literal("hello")
	result := get_pattern(p)
	_, is_lit := result.(^LiteralNode)
	testing.expect(t, is_lit, "literal should pass through get_pattern unchanged")
}

@(test)
test_next_insn_skips_labels_and_nops :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	prog := []Instruction{Nop{}, Label{1}, Nop{}, Char{'x'}}
	insn, ok := next_insn(prog)
	testing.expect(t, ok, "should find instruction after labels/nops")
	ch, is_char := insn.(Char)
	testing.expect(t, is_char, "next instruction should be Char")
	if is_char {
		testing.expect(t, ch.byte == 'x', fmt.tprintf("expected 'x', got '%c'", ch.byte))
	}
}

@(test)
test_next_insn_empty_program :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	prog := []Instruction{}
	_, ok := next_insn(prog)
	testing.expect(t, !ok, "empty program should return false")
}

@(test)
test_next_insn_only_labels_nops :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	prog := []Instruction{Nop{}, Label{1}, Nop{}}
	_, ok := next_insn(prog)
	testing.expect(t, !ok, "program with only labels/nops should return false")
}

@(test)
test_next_insn_label_reports_label :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	prog := []Instruction{Label{1}, Char{'a'}}
	idx, had_label := next_insn_label(prog)
	testing.expect(t, had_label, "should report label was seen")
	testing.expect(t, idx == 1, fmt.tprintf("expected idx=1, got %d", idx))
}

@(test)
test_next_insn_label_no_label :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	prog := []Instruction{Nop{}, Char{'a'}}
	idx, had_label := next_insn_label(prog)
	testing.expect(t, !had_label, "should report no label seen")
	testing.expect(t, idx == 1, fmt.tprintf("expected idx=1, got %d", idx))
}

@(test)
test_optimize_head_fail_char :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Choice + Char should become TestChar + Nop
	lbl := Label{99}
	prog := Program{Choice{lbl}, Char{'a'}, Commit{lbl}, lbl}
	optimize(&prog)

	_, is_test_char := prog[0].(TestChar)
	testing.expect(t, is_test_char, "Choice+Char should be optimized to TestChar")
	_, is_nop := prog[1].(Nop)
	testing.expect(t, is_nop, "Char after Choice should become Nop")
}

@(test)
test_optimize_head_fail_set :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Choice + Set should become TestSet + Nop
	lbl := Label{99}
	cs := charset.range('a', 'z')
	prog := Program{Choice{lbl}, Set{cs}, Commit{lbl}, lbl}
	optimize(&prog)

	_, is_test_set := prog[0].(TestSet)
	testing.expect(t, is_test_set, "Choice+Set should be optimized to TestSet")
	_, is_nop := prog[1].(Nop)
	testing.expect(t, is_nop, "Set after Choice should become Nop")
}

@(test)
test_optimize_head_fail_any :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Choice + Any should become TestAny + Nop
	lbl := Label{99}
	prog := Program{Choice{lbl}, Any{1}, Commit{lbl}, lbl}
	optimize(&prog)

	_, is_test_any := prog[0].(TestAny)
	testing.expect(t, is_test_any, "Choice+Any should be optimized to TestAny")
	_, is_nop := prog[1].(Nop)
	testing.expect(t, is_nop, "Any after Choice should become Nop")
}

@(test)
test_optimize_jump_to_return :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Jump to a label that points to Return should become Return
	lbl := Label{50}
	prog := Program{Jump{lbl}, lbl, Return{}}
	optimize(&prog)

	_, is_return := prog[0].(Return)
	testing.expect(t, is_return, "Jump to Return should be replaced with Return")
}

@(test)
test_optimize_jump_to_fail :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Jump to a label that points to Fail should become Fail
	lbl := Label{51}
	prog := Program{Jump{lbl}, lbl, Fail{}}
	optimize(&prog)

	_, is_fail := prog[0].(Fail)
	testing.expect(t, is_fail, "Jump to Fail should be replaced with Fail")
}

@(test)
test_optimize_end_to_end_alternation :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Compile 'a' / 'b' and verify the optimizer produces a Set instruction.
	// Two single-char literals should combine into a single Set via combine().
	p := or(literal("a"), literal("b"))
	prog, err := compile(p)
	testing.expect(t, !err, "compile alternation should not error")

	// The combined alternation should produce exactly one Set instruction.
	set_count := 0
	for insn in prog {
		if _, ok := insn.(Set); ok {
			set_count += 1
		}
	}
	testing.expect(t, set_count == 1, fmt.tprintf("expected 1 Set instruction from combined 'a'/'b', got %d", set_count))
}
