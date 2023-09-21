package pegasus

import "charset"
import "core:bytes"
import "core:os"
import "core:strconv"
import "core:strings"
import "log"
import "memo"

parser: Code
re_init :: proc() {
	prog := must_compile(grammar("Pattern", re_grammar))
	parser = encode(prog)
}

count := 0
compile_re :: proc(root: ^memo.Capture, s: string) -> (p: Pattern) {
	count += 1
	#partial switch NonTerm(root.id) {
	case .Pattern:
		p = compile_re(memo.capture_child(root, 0), s)
	case .Grammar:
		nonterms := make(map[string]Pattern)
		first: string
		iter, state := memo.capture_child_iterator(root, 0)
		for c in iter(state) {
			k, v := compileDef(c, s)
			if first == "" {
				first = k
			}
			nonterms[k] = v
		}
		p = grammar(first, nonterms)
	case .Expression:
		alternations := make(
			[dynamic]Pattern,
			0,
			memo.capture_num_children(root),
		)
		iter, state := memo.capture_child_iterator(root, 0)
		for c in iter(state) {
			append(&alternations, compile_re(c, s))
		}
		p = or(..alternations[:])
	case .Sequence:
		concats := make([dynamic]Pattern, 0, memo.capture_num_children(root))
		iter, state := memo.capture_child_iterator(root, 0)
		for c in iter(state) {
			append(&concats, compile_re(c, s))
		}
		p = concat(..concats[:])
	case .Prefix:
		c := memo.capture_child(root, 0)
		#partial switch NonTerm(c.id) {
		case .AND:
			p = and(compile_re(memo.capture_child(root, 1), s))
		case .NOT:
			p = not(compile_re(memo.capture_child(root, 1), s))
		case:
			p = compile_re(memo.capture_child(root, 0), s)
		}
	case .Suffix:
		if memo.capture_num_children(root) == 2 {
			c := memo.capture_child(root, 1)
			#partial switch NonTerm(c.id) {
			case .QUESTION:
				p = optional(compile_re(memo.capture_child(root, 0), s))
			case .STAR:
				p = star(compile_re(memo.capture_child(root, 0), s))
			case .PLUS:
				p = plus(compile_re(memo.capture_child(root, 0), s))
			}
		} else {
			p = compile_re(memo.capture_child(root, 0), s)
		}
	case .Primary:
		#partial switch NonTerm(memo.capture_child(root, 0).id) {
		case .Identifier, .Literal, .Class:
			p = compile_re(memo.capture_child(root, 0), s)
		case .OPEN:
			p = compile_re(memo.capture_child(root, 1), s)
		case .BRACEPO:
			p = memo_pattern(compile_re(memo.capture_child(root, 1), s))
		case .DOT:
			p = any(1)
		}
	case .Literal:
		lit := new(bytes.Buffer)
		iter, state := memo.capture_child_iterator(root, 0)
		for c in iter(state) {
			bytes.buffer_write_byte(
				lit,
				parseChar(s[memo.capture_start(c):memo.capture_end(c)]),
			)
		}
		p = literal(bytes.buffer_to_string(lit))
	case .Class:
		chrst := new(charset.Set)
		if memo.capture_num_children(root) <= 0 {
			break
		}
		complement := false
		if memo.capture_child(root, 0).id == i32(NonTerm.CARAT) {
			complement = true
		}
		iter, state := memo.capture_child_iterator(root, 0)
		for c, i in iter(state) {
			if i == 0 && complement {
				continue
			}
			chrst = charset.add(chrst, compileSet(c, s))
		}
		if complement {
			chrst = charset.complement(chrst)
		}
		p = set(chrst)
	case .Identifier:
		p = non_term(parseId(root, s))
	}
	return p
}

special := map[byte]byte {
	'n'  = '\n',
	'r'  = '\r',
	't'  = '\t',
	'\'' = '\'',
	'"'  = '"',
	'['  = '[',
	']'  = ']',
	'\\' = '\\',
	'-'  = '-',
}

parseChar :: proc(char: string) -> byte {
	switch char[0] {
	case '\\':
		for k, v in special {
			if char[1] == k {
				return v
			}
		}

		i, _ := strconv.parse_int(char[1:], 8)
		return byte(i)
	case:
		return char[0]
	}
}

parseId :: proc(root: ^memo.Capture, s: string) -> string {
	ident := new(bytes.Buffer)
	iter, state := memo.capture_child_iterator(root, 0)
	for c in iter(state) {
		bytes.buffer_write_string(
			ident,
			s[memo.capture_start(c):memo.capture_end(c)],
		)
	}
	return bytes.buffer_to_string(ident)
}

compileDef :: proc(root: ^memo.Capture, s: string) -> (string, Pattern) {
	id := memo.capture_child(root, 0)
	exp := memo.capture_child(root, 1)
	return parseId(id, s), compile_re(exp, s)
}

compileSet :: proc(root: ^memo.Capture, s: string) -> ^charset.Set {
	switch memo.capture_num_children(root) {
	case 1:
		c := memo.capture_child(root, 0)
		chrst := make([]byte, 1)
		chrst[0] = parseChar(s[memo.capture_start(c):memo.capture_end(c)])
		return charset.new_charset(chrst)
	case 2:
		c1, c2 := memo.capture_child(root, 0), memo.capture_child(root, 1)
		return (charset.range(
					parseChar(s[memo.capture_start(c1):memo.capture_end(c1)]),
					parseChar(s[memo.capture_start(c2):memo.capture_end(c2)]),
				))
	}
	chrst := new(charset.Set)
	return chrst
}

init_re_compilation :: proc(s: string) -> (Pattern, bool) {
	re_init()

	reader := new(strings.Reader)
	defer free(reader)
	strings.reader_init(reader, s)

	memtbl := memo.new_table(512)
	match, _, ast, errs := exec(&parser, reader, memtbl)
	if len(errs) != 0 || !match {
		return nil, true
	}

	return compile_re(memo.capture_child(ast, 0), s), false
}

re_must_compile :: proc(s: string) -> Pattern {
	p, err := init_re_compilation(s);if err {
		panic("Could not compile")
	}
	return p
}

match :: proc(
	gram: string,
	subject: string,
) -> (
	bool,
	int,
	^memo.Capture,
	[]ParseError,
) {
	patt, err := init_re_compilation(gram);if err {
		log.error("Could not compile a pattern from the provided grammar")
		os.exit(1)
	}

	prog: Program
	prog, err = compile(patt);if err {
		log.error("Could not compile a program from the provided pattern")
		os.exit(1)
	}

	code := encode(prog)

	reader := new(strings.Reader)
	defer free(reader)
	strings.reader_init(reader, subject)

	memtbl := memo.new_table(512)

	return exec(&code, reader, memtbl)
}
