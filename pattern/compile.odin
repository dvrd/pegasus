package pattern

import "core:fmt"
import "core:strings"
import "pegasus:charset"
import inst "pegasus:instructions"

ErrorKind :: enum {
	// A NotFoundError means a a non-terminal was not found during grammar
	// compilation.
	NotFoundError,
}

Error :: struct {
	kind: ErrorKind,
	msg:  string,
}

// Error returns the error message.
not_found_error_error :: proc(e: ^Error) -> string {
	return fmt.sbprintf(
		&strings.Builder{},
		"non-terminal %s: not found",
		e.msg,
	)
}

// Compile takes an input pattern and returns the result of compiling it into a
// parsing program, and optimizing the program.
compile :: proc(pattern: Pattern) -> (c: inst.Program, err: bool) {
	#partial switch p in pattern {
	case ^AltNode:
		c, err = compile_pattern(p)
	case ^SeqNode:
		c, err = compile_pattern(p)
	case ^StarNode:
		c, err = compile_pattern(p)
	case ^PlusNode:
		c, err = compile_pattern(p)
	case ^OptionalNode:
		c, err = compile_pattern(p)
	case ^NotNode:
		c, err = compile_pattern(p)
	case ^AndNode:
		c, err = compile_pattern(p)
	case ^CapNode:
		c, err = compile_pattern(p)
	case ^MemoNode:
		c, err = compile_pattern(p)
	case ^CheckNode:
		c, err = compile_pattern(p)
	case ^GrammarNode:
		c, err = compile_pattern(p)
	case ^SearchNode:
		c, err = compile_pattern(p)
	case ^NonTermNode:
		c, err = compile_pattern(p)
	case ^ErrorNode:
		c, err = compile_pattern(p)
	}

	if err {return}
	optimize(c)
	return
}

// MustCompile is the same as Compile but panics if there is an error during
// compilation.
must_compile :: proc(p: Pattern) -> inst.Program {
	c, err := compile(p);if err {
		panic(
			fmt.sbprintf(
				&strings.Builder{},
				"Error: failed to compile pattern %v",
				p,
			),
		)
	}
	return c
}

// Compile this node.
compile_alt_node :: proc(p: ^AltNode) -> (inst.Program, bool) {
	// optimization: if Left and Right are charsets/single chars, return the union
	set, ok := combine(get_pattern(p.left), get_pattern(p.right));if ok {
		return inst.Program{inst.Set{&set}}, false
	}


	l, err1 := compile(get_pattern(p.left));if err1 {
		return nil, err1
	}

	r, err2 := compile(get_pattern(p.right));if err2 {
		return nil, err2
	}

	L1 := inst.new_label()

	// optimization: if the right and left nodes are disjoint, we can use
	// NoChoice variants of the head-fail optimization in:: structions.
	disjoint: bool
	testinsn: inst.Instruction
	linsn, okl := next_insn(l[:])
	rinsn, okr := next_insn(r[:])
	if okl && okr {
		#partial switch lt in linsn {
		case inst.Set:
			#partial switch rt in rinsn {
			case inst.Char:
				disjoint = !charset.has(lt.chars^, u8(rt.byte))
			}
			testinsn = inst.TestSetNoChoice{lt.chars, L1}
		case inst.Char:
			#partial switch rt in rinsn {
			case inst.Char:
				disjoint = lt.byte != rt.byte
			case inst.Set:
				disjoint = !charset.has(rt.chars^, u8(lt.byte))
			}
			testinsn = inst.TestCharNoChoice{inst.Char{lt.byte}, L1}
		}
	}

	L2 := inst.new_label()
	code := make([dynamic]inst.Instruction, 0, len(l) + len(r) + 5)
	if disjoint {
		append(&code, testinsn)
		append(&code, ..l[1:])
		append(&code, inst.Jump{L2})
	} else {
		append(&code, inst.Choice{L1})
		append(&code, ..l[:])
		append(&code, inst.Commit{L2})
	}
	append(&code, L1)
	append(&code, ..r[:])
	append(&code, L2)
	return code, false
}

// Compile this node.
compile_seq_node :: proc(p: ^SeqNode) -> (inst.Program, bool) {
	l, err1 := compile(get_pattern(p.left));if err1 {
		return nil, err1
	}
	r, err2 := compile(get_pattern(p.right));if err2 {
		return nil, err2
	}

	append(&l, ..r[:])

	return l, false
}

// Compile this node.
compile_star_node :: proc(p: ^StarNode) -> (inst.Program, bool) {

	#partial switch t in get_pattern(p.patt) {
	case ^ClassNode:
		// optimization: repeating a charset uses the dedicated instruction 'span'
		code := make(inst.Program)

		append(&code, inst.Span{t.chars})
		return code, false
	case ^MemoNode:
		// optimization: if the pattern we are repeating is a memoization
		// entry, we should use special in:: structions to memoize it as a tree to
		// get logarithmic saving when reparsing.
		sub, err := compile(get_pattern(t.patt))
		code := make(inst.Program, 0, len(sub) + 7)
		L1 := inst.new_label()
		L2 := inst.new_label()
		L3 := inst.new_label()
		NoJump := inst.new_label()
		MEMO_ID += 1

		append(&code, L1)
		append(&code, inst.MemoTreeOpen{lbl = L3, id = MEMO_ID})
		append(&code, inst.Choice{L2})
		append(&code, ..sub[:])
		append(&code, inst.Commit{NoJump})
		append(&code, NoJump)
		append(&code, inst.MemoTreeInsert{})
		append(&code, L3)
		append(&code, inst.MemoTree{})
		append(&code, inst.Jump{L1})
		append(&code, L2)
		append(&code, inst.MemoTreeClose{MEMO_ID})
		return code, err
	}

	sub, err := compile(get_pattern(p.patt))
	code := make(inst.Program, 0, len(sub) + 4)

	L1 := inst.new_label()
	L2 := inst.new_label()
	append(&code, inst.Choice{L2})
	append(&code, L1)
	append(&code, ..sub[:])
	append(&code, inst.PartialCommit{L1})
	append(&code, L2)
	return code, err
}

// Compile this node.
compile_plus_node :: proc(p: ^PlusNode) -> (inst.Program, bool) {
	starp := star(get_pattern(p.patt))
	star, err1 := compile(starp);if err1 {
		return nil, err1
	}
	sub, err2 := compile(get_pattern(p.patt));if err2 {
		return nil, err2
	}

	code := make(inst.Program, 0, len(sub) + len(star))
	append(&code, ..sub[:])
	append(&code, ..star[:])

	return code, false
}

// Compile this node.
compile_optional_node :: proc(p: ^OptionalNode) -> (inst.Program, bool) {
	// optimization: if the pattern is a class node or single char literal, we
	// can use the Test*NoChoice in:: structions.
	#partial switch t in get_pattern(p.patt) {
	case ^LiteralNode:
		if len(t.str) == 1 {
			L1 := inst.new_label()
			prog := make(inst.Program)
			append(
				&prog,
				inst.TestCharNoChoice{inst.Char{rune(t.str[0])}, L1},
				L1,
			)
			return prog, false
		}
	case ^ClassNode:
		L1 := inst.new_label()
		prog := make(inst.Program)
		append(&prog, inst.TestSetNoChoice{t.chars, L1}, L1)
		return prog, false
	}

	empty := new(EmptyNode)
	a := new(AltNode)
	a.left = get_pattern(p.patt)
	a.right = empty
	return compile(a)

}

// Compile this node.
compile_not_node :: proc(p: ^NotNode) -> (inst.Program, bool) {
	sub, err := compile(get_pattern(p.patt))
	L1 := inst.new_label()
	code := make(inst.Program, 0, len(sub) + 3)
	append(&code, inst.Choice{L1})
	append(&code, ..sub[:])
	append(&code, inst.FailTwice{})
	append(&code, L1)
	return code, err
}

// Compile this node.
compile_and_node :: proc(p: ^AndNode) -> (inst.Program, bool) {
	sub, err := compile(get_pattern(p.patt))
	code := make(inst.Program, 0, len(sub) + 5)
	L1 := inst.new_label()
	L2 := inst.new_label()

	append(&code, inst.Choice{L1})
	append(&code, ..sub[:])
	append(&code, inst.BackCommit{L2})
	append(&code, L1)
	append(&code, inst.Fail{})
	append(&code, L2)
	return code, err
}

// Compile this node.
compile_cap_node :: proc(p: ^CapNode) -> (inst.Program, bool) {
	sub, err := compile(get_pattern(p.patt));if err {
		return nil, err
	}
	code := make(inst.Program, 0, len(sub) + 2)

	i := 0
	back := 0
	loop: for insn in sub {
		#partial switch t in insn {
		case inst.Char, inst.Set:
			back += 1
		case inst.Any:
			back += int(t.n)
		case:
			break loop
		}
		i += 1
	}

	if i == 0 || back >= 256 {
		append(&code, inst.CaptureBegin{p.id})
		i = 0
	} else if i == len(sub) && back < 256 {
		append(&code, ..sub[:])
		append(&code, inst.CaptureFull{rune(back), p.id})
		return code, false
	} else {
		append(&code, ..sub[:i])
		append(&code, inst.CaptureLate{rune(back), p.id})
	}
	append(&code, ..sub[i:])
	append(&code, inst.CaptureEnd{})
	return code, false
}

// Compile this node.
compile_memo_node :: proc(p: ^MemoNode) -> (inst.Program, bool) {
	L1 := inst.new_label()
	sub, err := compile(get_pattern(p.patt))
	code := make(inst.Program, 0, len(sub) + 3)
	append(&code, inst.MemoOpen{L1, p.id})
	append(&code, ..sub[:])
	append(&code, inst.MemoClose{})
	append(&code, L1)
	return code, err
}

// Compile this node.
compile_check_node :: proc(p: ^CheckNode) -> (inst.Program, bool) {
	L1 := inst.new_label()
	sub, err := compile(get_pattern(p.patt))
	code := make(inst.Program, 0, len(sub) + 3)
	append(&code, inst.CheckBegin{p.id, p.flag})
	append(&code, ..sub[:])
	append(&code, inst.CheckEnd{p.checker})
	append(&code, L1)
	return code, err
}

// Compile this node.
compile_search_node :: proc(p: ^SearchNode) -> (inst.Program, bool) {
	rsearch: Pattern
	cs: charset.Set
	opt := false

	sub, err := compile(get_pattern(p.patt));if err {
		return nil, err
	}

	next, ok := next_insn(sub[:]);if ok {
		#partial switch t in next {
		case inst.Char:
			cs = charset.complement(charset.new([]byte{byte(t.byte)}))
			opt = true
		case inst.Set:
			// Heuristic: if the set is smaller than 10 chars, it
			// is unlikely enough to match that we should consume all
			// chars from the complement before continuing the search.
			// The number 10 was arbitrarily chosen.
			if charset.size(t.chars) < 10 {
				cs = charset.complement(t.chars^)
				opt = true
			}
		}
	}

	if opt {
		rsearch = concat(star(set(&cs)), non_term("S"))
	} else {
		rsearch = non_term("S")
	}

	m: map[string]Pattern = {
		"S" = or(get_pattern(p.patt), concat(any(1), rsearch)),
	}
	return compile(grammar("S", m))
}

// Compile this node.
compile_empty_op_node :: proc(p: ^EmptyOpNode) -> (inst.Program, bool) {
	// inst.Empty{p.op}
	return inst.Program{inst.Empty{}}, false
}

// Compile this node.
compile_grammar_node :: proc(p: ^GrammarNode) -> (inst.Program, bool) {
	inline_grammar(p)

	used := make(map[string]bool)
	context.user_ptr = &used
	fn: proc(sub: Pattern)
	for v in p.defs {
		fn = proc(sub: Pattern) {
			used := cast(^map[string]bool)context.user_ptr
			#partial switch t in sub {
			case ^NonTermNode:
				if t.inlined == nil {
					used[t.name] = true
				}
			}
		}
		walk_pattern(p.defs[v], true, fn)
	}

	if len(used) == 0 {
		return compile(p.defs[p.start])
	}

	code := make(inst.Program)
	LEnd := inst.new_label()
	append(&code, inst.OpenCall{p.start}, inst.Jump{LEnd})

	labels := make(map[string]inst.Label)
	for k, v in p.defs {
		if k != p.start && !used[k] {
			continue
		}
		label := inst.new_label()
		labels[k] = label
		fn, err := compile(v)
		if err {
			return nil, err
		}
		append(&code, label)
		append(&code, ..fn[:])
		append(&code, inst.Return{})
	}

	// resolve calls to OpenCall and do tail call optimization
	next: inst.Instruction
	for i := 0; i < len(code); i += 1 {
		insn := code[i]
		oc, ok := insn.(inst.OpenCall);if ok {
			lbl, ok := labels[oc.name];if !ok {
				return nil, true
			}

			// replace this placeholder instruction with a normal call
			replace: inst.Instruction = inst.Call{lbl}
			// if a call is immediately followed by a return, optimize to
			// a jump for tail call optimization.
			next, ok = next_insn(code[i + 1:]);if ok {
				#partial switch t in next {
				case inst.Return:
					replace = inst.Jump{lbl}
					// remove the return in:: struction if there is no label referring to it
					retidx, hadlbl := next_insn_label(code[i + 1:])
					if !hadlbl {
						code[i + 1 + retidx] = inst.Nop{}
					}
				}
			}

			// perform the replacement of the opencall by either a call or jump
			code[i] = replace
		}
	}

	append(&code, LEnd)

	return code, false
}

// Compile this node.
compile_class_node :: proc(p: ^ClassNode) -> (inst.Program, bool) {
	return inst.Program{inst.Set{p.chars}}, false
}

// Compile this node.
compile_literal_node :: proc(p: ^LiteralNode) -> (inst.Program, bool) {
	code := make(inst.Program, len(p.str))
	for i := 0; i < len(p.str); i += 1 {
		code[i] = inst.Char{rune(p.str[i])}
	}
	return code, false
}

// Compile this node.
compile_non_term_node :: proc(p: ^NonTermNode) -> (inst.Program, bool) {
	if p.inlined != nil {
		return compile(p.inlined)
	}
	code := make(inst.Program)
	append(&code, inst.Nop{})
	return code, false
}

// Compile this node.
compile_dot_node :: proc(p: ^DotNode) -> (inst.Program, bool) {
	code := make(inst.Program)
	append(&code, inst.Any{int(p.n)})

	return code, false
}

// Compile this node.
compile_error_node :: proc(p: ^ErrorNode) -> (inst.Program, bool) {
	recovery: inst.Program
	err: bool = false

	if p.recover == nil {
		recovery = inst.Program{inst.End{true}}
	} else {
		recovery, err = compile(get_pattern(p.recover))
	}

	code := make(inst.Program, 0, len(recovery) + 1)
	append(&code, inst.Error{p.message})
	append(&code, ..recovery[:])
	return code, err
}

// Compile this node.
compile_empty_node :: proc(p: ^EmptyNode) -> (inst.Program, bool) {
	return inst.Program{}, false
}

compile_pattern :: proc {
	compile_alt_node,
	compile_seq_node,
	compile_star_node,
	compile_plus_node,
	compile_optional_node,
	compile_not_node,
	compile_and_node,
	compile_cap_node,
	compile_memo_node,
	compile_check_node,
	compile_search_node,
	compile_empty_op_node,
	compile_grammar_node,
	compile_class_node,
	compile_literal_node,
	compile_non_term_node,
	compile_dot_node,
	compile_error_node,
	compile_empty_node,
}
