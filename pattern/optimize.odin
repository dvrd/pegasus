package pattern

import "pegasus:charset"
import inst "pegasus:instructions"

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
			np.chars = &set
			return p
		}
	case ^OptionalNode:
		// Optional of a Kleene star is unnecessary and we can remove the
		// optional.
		np := get_pattern(t.patt)
		star, ok := np.(^StarNode);if ok {
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
			chars := charset.new([]byte{lt.str[0]})
			set = &chars
		case ^ClassNode:
			set = lt.chars
		case:
			return p
		}

		#partial switch rt in r {
		case ^DotNode:
			if rt.n == 1 {
				np := new(ClassNode)
				chars := charset.complement(set^)
				np.chars = &chars
				return np
			}
		case ^ClassNode:
			np := new(ClassNode)
			chars := charset.sub(rt.chars^, set^)
			np.chars = &chars
			return np
		case ^LiteralNode:
			if len(rt.str) == 1 {
				np := new(ClassNode)
				chars := charset.sub(charset.new([]byte{rt.str[0]}), set^)
				np.chars = &chars
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
combine :: proc(p1: Pattern, p2: Pattern) -> (charset.Set, bool) {
	set: charset.Set
	#partial switch t1 in p1 {
	case ^LiteralNode:
		if len(t1.str) != 1 {
			return set, false
		}
		#partial switch t2 in p2 {
		case ^ClassNode:
			return charset.add(t2.chars^, charset.new([]byte{t1.str[0]})), true
		case ^LiteralNode:
			if len(t2.str) != 1 {
				return set, false
			}
			return charset.new([]byte{t1.str[0], t2.str[0]}), true
		}
	case ^ClassNode:
		#partial switch t2 in p2 {
		case ^ClassNode:
			return charset.add(t2.chars^, t1.chars^), true
		case ^LiteralNode:
			if len(t2.str) != 1 {
				return set, false
			}
			return charset.add(t1.chars^, charset.new([]byte{t2.str[0]})), true
		}
	}
	return set, false
}

// Returns the next instruction in p, skipping labels and nops.
// If false is returned, there is no next instruction.
next_insn :: proc(p: inst.ProgramSlice) -> (inst.Instruction, bool) {
	for i := 0; i < len(p); i += 1 {
		#partial switch t in p[i] {
		case inst.Label, inst.Nop:
			continue
		case:
			return p[i], true
		}
	}

	return inst.Nop{}, false
}

// Returns the index of the next instruction and if there was a label before
// it.
next_insn_label :: proc(p: inst.ProgramSlice) -> (int, bool) {
	had_label := false
	for i := 0; i < len(p); i += 1 {
		#partial switch t in p[i] {
		case inst.Nop:
			continue
		case inst.Label:
			had_label = true
		case:
			return i, had_label
		}
	}

	return -1, had_label
}

// Optimize performs some optimization passes on the code in p. In particular
// it performs head-fail optimization and jump replacement.
optimize :: proc(p: inst.Program) {
	// map from label to index in code
	labels := make(map[inst.Label]int)
	i := 0
	for insn in p {
		#partial switch l in insn {
		case inst.Label:
			labels[l] = i
		}
		i += 1
	}

	i = 0
	for insn in p {
		// head-fail optimization: if we find a choice instruction immediately
		// followed (no label) by Char/Set/Any, we can replace with the
		// dedicated instruction TestChar/TestSet/TestAny.
		ch, ok := insn.(inst.Choice);if ok && i < len(p) - 1 {
			next := p[i + 1]
			#partial switch t in next {
			case inst.Char:
				p[i] = inst.TestChar{inst.Char{rune(t.byte)}, ch.lbl}
				p[i + 1] = inst.Nop{}
			case inst.Set:
				p[i] = inst.TestSet{t.chars^, ch.lbl}
				p[i + 1] = inst.Nop{}
			case inst.Any:
				p[i] = inst.TestAny{inst.Any{t.n}, ch.lbl}
				p[i + 1] = inst.Nop{}
			}
		}

		// jump optimization: if we find a jump to another control flow
		// instruction, we can replace the current jump directly with the
		// target instruction.
		if j, ok := insn.(inst.Jump); ok {
			next, ok := next_insn(p[labels[j.lbl]:])
			if ok {
				#partial switch t in next {
				case inst.PartialCommit, inst.BackCommit, inst.Commit, inst.Jump, inst.Return, inst.Fail, inst.FailTwice, inst.End:
					p[i] = next
				}
			}
		}
		i += 1
	}
}
