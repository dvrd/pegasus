package pegasus

import "charset"
import "core:fmt"
import "core:strings"

ErrorKind :: enum {
	// A NotFoundError means a a non-terminal was not found during grammar
	// compilation.
	NotFoundError,
}

CompileError :: struct {
	kind: ErrorKind,
	msg:  string,
}

// Error returns the error message.
not_found_error_error :: proc(e: ^CompileError) -> string {
	return fmt.sbprintf(
		&strings.Builder{},
		"non-terminal %s: not found",
		e.msg,
	)
}

// Compile takes an input pattern and returns the result of compiling it into a
// parsing program, and optimizing the program.
compile :: proc(p: Pattern) -> (c: Program, err: bool) {
	c, err = compile_pattern(p);if err {
		return
	}
	fmt.println(len(c))
	optimize(&c)
	return
}

// MustCompile is the same as Compile but panics if there is an error during
// compilation.
must_compile :: proc(p: Pattern) -> Program {
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
compile_alt_node :: proc(p: ^AltNode) -> (Program, bool) {
	// optimization: if Left and Right are charsets/single chars, return the union
	set, ok := combine(get_pattern(p.left), get_pattern(p.right));if ok {
		return Program{Set{set}}, false
	}

	fmt.println("COMPILE ALT NODE")


	l, err1 := compile_pattern(get_pattern(p.left));if err1 {
		return nil, err1
	}

	r, err2 := compile_pattern(get_pattern(p.right));if err2 {
		return nil, err2
	}

	L1 := new_label()

	// optimization: if the right and left nodes are disjoint, we can use
	// NoChoice variants of the head-fail optimization in:: structions.
	disjoint: bool
	testinsn: Instruction
	linsn, okl := next_insn(l[:])
	rinsn, okr := next_insn(r[:])
	if okl && okr {
		#partial switch lt in linsn {
		case Set:
			#partial switch rt in rinsn {
			case Char:
				disjoint = !charset.has(lt.chars, u8(rt.byte))
			}
			testinsn = TestSetNoChoice{lt.chars^, L1}
		case Char:
			#partial switch rt in rinsn {
			case Char:
				disjoint = lt.byte != rt.byte
			case Set:
				disjoint = !charset.has(rt.chars, u8(lt.byte))
			}
			testinsn = TestCharNoChoice{lt.byte, L1}
		}
	}

	L2 := new_label()
	code := make([dynamic]Instruction, 0, len(l) + len(r) + 5)
	if disjoint {
		append(&code, testinsn)
		append(&code, ..l[1:])
		append(&code, Jump{L2})
	} else {
		append(&code, Choice{L1})
		append(&code, ..l[:])
		append(&code, Commit{L2})
	}
	append(&code, L1)
	append(&code, ..r[:])
	append(&code, L2)
	return code, false
}

// Compile this node.
compile_seq_node :: proc(p: ^SeqNode) -> (Program, bool) {
	l, err1 := compile_pattern(get_pattern(p.left));if err1 {
		return nil, err1
	}
	r, err2 := compile_pattern(get_pattern(p.right));if err2 {
		return nil, err2
	}

	append(&l, ..r[:])

	return l, false
}

// Compile this node.
compile_star_node :: proc(p: ^StarNode) -> (Program, bool) {

	#partial switch t in get_pattern(p.patt) {
	case ^ClassNode:
		// optimization: repeating a charset uses the dedicated uction 'span'
		code := make(Program)

		append(&code, Span{t.chars})
		return code, false
	case ^MemoNode:
		// optimization: if the pattern we are repeating is a memoization
		// entry, we should use special in:: structions to memoize it as a tree to
		// get logarithmic saving when reparsing.
		sub, err := compile_pattern(get_pattern(t.patt))
		code := make(Program, 0, len(sub) + 7)
		L1 := new_label()
		L2 := new_label()
		L3 := new_label()
		NoJump := new_label()
		MEMO_ID += 1

		append(&code, L1)
		append(&code, MemoTreeOpen{lbl = L3, id = MEMO_ID})
		append(&code, Choice{L2})
		append(&code, ..sub[:])
		append(&code, Commit{NoJump})
		append(&code, NoJump)
		append(&code, MemoTreeInsert{})
		append(&code, L3)
		append(&code, MemoTree{})
		append(&code, Jump{L1})
		append(&code, L2)
		append(&code, MemoTreeClose{MEMO_ID})
		return code, err
	}

	sub, err := compile_pattern(get_pattern(p.patt))
	code := make(Program, 0, len(sub) + 4)

	L1 := new_label()
	L2 := new_label()
	append(&code, Choice{L2})
	append(&code, L1)
	append(&code, ..sub[:])
	append(&code, PartialCommit{L1})
	append(&code, L2)
	return code, err
}

// Compile this node.
compile_plus_node :: proc(p: ^PlusNode) -> (Program, bool) {
	starp := star(get_pattern(p.patt))
	star, err1 := compile_pattern(starp);if err1 {
		return nil, err1
	}
	sub, err2 := compile_pattern(get_pattern(p.patt));if err2 {
		return nil, err2
	}

	code := make(Program, 0, len(sub) + len(star))
	append(&code, ..sub[:])
	append(&code, ..star[:])

	return code, false
}

// Compile this node.
compile_optional_node :: proc(p: ^OptionalNode) -> (Program, bool) {
	// optimization: if the pattern is a class node or single char literal, we
	// can use the Test*NoChoice in:: structions.
	#partial switch t in get_pattern(p.patt) {
	case ^LiteralNode:
		if len(t.str) == 1 {
			L1 := new_label()
			prog := make(Program)
			append(&prog, TestCharNoChoice{rune(t.str[0]), L1}, L1)
			return prog, false
		}
	case ^ClassNode:
		L1 := new_label()
		prog := make(Program)
		append(&prog, TestSetNoChoice{t.chars^, L1}, L1)
		return prog, false
	}

	empty := new(EmptyNode)
	a := new(AltNode)
	a.left = get_pattern(p.patt)
	a.right = empty
	return compile_pattern(a)

}

// Compile this node.
compile_not_node :: proc(p: ^NotNode) -> (Program, bool) {
	sub, err := compile_pattern(get_pattern(p.patt))
	L1 := new_label()
	code := make(Program, 0, len(sub) + 3)
	append(&code, Choice{L1})
	append(&code, ..sub[:])
	append(&code, FailTwice{})
	append(&code, L1)
	return code, err
}

// Compile this node.
compile_and_node :: proc(p: ^AndNode) -> (Program, bool) {
	sub, err := compile_pattern(get_pattern(p.patt))
	code := make(Program, 0, len(sub) + 5)
	L1 := new_label()
	L2 := new_label()

	append(&code, Choice{L1})
	append(&code, ..sub[:])
	append(&code, BackCommit{L2})
	append(&code, L1)
	append(&code, Fail{})
	append(&code, L2)
	return code, err
}

// Compile this node.
compile_cap_node :: proc(p: ^CapNode) -> (Program, bool) {
	sub, err := compile_pattern(get_pattern(p.patt));if err {
		return nil, err
	}
	code := make(Program, 0, len(sub) + 2)

	i := 0
	back := 0
	loop: for insn in sub {
		#partial switch t in insn {
		case Char, Set:
			back += 1
		case Any:
			back += int(t.n)
		case:
			break loop
		}
		i += 1
	}

	if i == 0 || back >= 256 {
		append(&code, CaptureBegin{p.id})
		i = 0
	} else if i == len(sub) && back < 256 {
		append(&code, ..sub[:])
		append(&code, CaptureFull{rune(back), p.id})
		return code, false
	} else {
		append(&code, ..sub[:i])
		append(&code, CaptureLate{rune(back), p.id})
	}
	append(&code, ..sub[i:])
	append(&code, CaptureEnd{})
	return code, false
}

// Compile this node.
compile_memo_node :: proc(p: ^MemoNode) -> (Program, bool) {
	L1 := new_label()
	sub, err := compile_pattern(get_pattern(p.patt))
	code := make(Program, 0, len(sub) + 3)
	append(&code, MemoOpen{L1, p.id})
	append(&code, ..sub[:])
	append(&code, MemoClose{})
	append(&code, L1)
	return code, err
}

// Compile this node.
compile_check_node :: proc(p: ^CheckNode) -> (Program, bool) {
	L1 := new_label()
	sub, err := compile_pattern(get_pattern(p.patt))
	code := make(Program, 0, len(sub) + 3)
	append(&code, CheckBegin{p.id, p.flag})
	append(&code, ..sub[:])
	append(&code, CheckEnd{p.checker})
	append(&code, L1)
	return code, err
}

// Compile this node.
compile_search_node :: proc(p: ^SearchNode) -> (Program, bool) {
	rsearch: Pattern
	cs: charset.Set
	opt := false

	sub, err := compile_pattern(get_pattern(p.patt));if err {
		return nil, err
	}

	next, ok := next_insn(sub[:]);if ok {
		#partial switch t in next {
		case Char:
			cs = charset.complement(charset.new_charset([]byte{byte(t.byte)}))^
			opt = true
		case Set:
			// Heuristic: if the set is smaller than 10 chars, it
			// is unlikely enough to match that we should consume all
			// chars from the complement before continuing the search.
			// The number 10 was arbitrarily chosen.
			if charset.size(t.chars) < 10 {
				cs = charset.complement(t.chars)^
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
	return compile_pattern(grammar("S", m))
}

// Compile this node.
compile_empty_op_node :: proc(p: ^EmptyOpNode) -> (Program, bool) {
	// Empty{p.op}
	return Program{Empty{}}, false
}

// Compile this node.
compile_grammar_node :: proc(p: ^GrammarNode) -> (Program, bool) {
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
		return compile_pattern(p.defs[p.start])
	}

	code := make(Program)
	LEnd := new_label()
	append(&code, OpenCall{p.start}, Jump{LEnd})

	labels := make(map[string]Label)
	fmt.println("GRAMMAR NODE | PRE LABELS CODE", len(code), p.defs)
	for k, v in p.defs {
		if k != p.start && !used[k] {
			continue
		}
		label := new_label()
		labels[k] = label
		fmt.println("GRAMMAR NODE | PATT", k, v)
		insns, err := compile_pattern(v);if err {
			return nil, err
		}
		fmt.println("GRAMMAR NODE | LABELS", len(insns))
		append(&code, label)
		append(&code, ..insns[:])
		append(&code, Return{})
	}

	fmt.println("GRAMMAR NODE | POST LABELS CODE", len(code))
	// resolve calls to OpenCall and do tail call optimization
	next: Instruction
	for i := 0; i < len(code); i += 1 {
		insn := code[i]
		oc, ok := insn.(OpenCall);if ok {
			lbl: Label
			lbl, ok = labels[oc.name];if !ok {
				return nil, true
			}

			// replace this placeholder uction with a normal call
			replace: Instruction = Call{lbl}
			// if a call is immediately followed by a return, optimize to
			// a jump for tail call optimization.
			next, ok = next_insn(code[i + 1:]);if ok {
				#partial switch t in next {
				case Return:
					replace = Jump{lbl}
					// remove the return in:: struction if there is no label referring to it
					retidx, hadlbl := next_insn_label(code[i + 1:])
					if !hadlbl {
						code[i + 1 + retidx] = Nop{}
					}
				}
			}

			// perform the replacement of the opencall by either a call or jump
			code[i] = replace
		}
	}

	append(&code, LEnd)

	fmt.println(len(code))
	return code, false
}

// Compile this node.
compile_class_node :: proc(p: ^ClassNode) -> (Program, bool) {
	return Program{Set{p.chars}}, false
}

// Compile this node.
compile_literal_node :: proc(p: ^LiteralNode) -> (Program, bool) {
	code := make(Program, len(p.str))
	for i := 0; i < len(p.str); i += 1 {
		code[i] = Char{rune(p.str[i])}
	}
	return code, false
}

// Compile this node.
compile_non_term_node :: proc(p: ^NonTermNode) -> (Program, bool) {
	if p.inlined != nil {
		return compile_pattern(p.inlined)
	}
	code := make(Program)
	append(&code, OpenCall{p.name})
	return code, false
}

// Compile this node.
compile_dot_node :: proc(p: ^DotNode) -> (Program, bool) {
	code := make(Program)
	append(&code, Any{int(p.n)})

	return code, false
}

// Compile this node.
compile_error_node :: proc(p: ^ErrorNode) -> (Program, bool) {
	recovery: Program
	err: bool = false

	if p.recover == nil {
		recovery = Program{End{true}}
	} else {
		recovery, err = compile_pattern(get_pattern(p.recover))
	}

	code := make(Program, 0, len(recovery) + 1)
	append(&code, Error{p.message})
	append(&code, ..recovery[:])
	return code, err
}

// Compile this node.
compile_empty_node :: proc(p: ^EmptyNode) -> (Program, bool) {
	return Program{}, false
}

compile_pattern :: proc(pattern: Pattern) -> (c: Program, err: bool) {
	#partial switch p in pattern {
	case ^AltNode:
		c, err = compile_alt_node(p)
	case ^SeqNode:
		c, err = compile_seq_node(p)
	case ^StarNode:
		c, err = compile_star_node(p)
	case ^PlusNode:
		c, err = compile_plus_node(p)
	case ^OptionalNode:
		c, err = compile_optional_node(p)
	case ^NotNode:
		c, err = compile_not_node(p)
	case ^AndNode:
		c, err = compile_and_node(p)
	case ^CapNode:
		c, err = compile_cap_node(p)
	case ^MemoNode:
		c, err = compile_memo_node(p)
	case ^CheckNode:
		c, err = compile_check_node(p)
	case ^GrammarNode:
		c, err = compile_grammar_node(p)
	case ^SearchNode:
		c, err = compile_search_node(p)
	case ^NonTermNode:
		c, err = compile_non_term_node(p)
	case ^ErrorNode:
		c, err = compile_error_node(p)
	case ^ClassNode:
		c, err = compile_class_node(p)
	case ^EmptyOpNode:
		c, err = compile_empty_op_node(p)
	case ^EmptyNode:
		c, err = compile_empty_node(p)
	case ^LiteralNode:
		c, err = compile_literal_node(p)
	case ^DotNode:
		c, err = compile_dot_node(p)
	}
	return
}
