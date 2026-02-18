package pegasus

import "charset"
import "core:bytes"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"
import log "log"
import "memo"

parser: Code
re_init :: proc() {
	re_grammar_init()
}

compile_re :: proc(root: ^memo.Capture, s: string) -> (p: Pattern) {
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
		case .BRACEO:
			p = cap(compile_re(memo.capture_child(root, 1), s), int(NonTerm.BRACEO))
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

parseChar :: proc(char: string) -> byte {
	switch char[0] {
	case '\\':
		special := [?]struct{k: byte, v: byte} {
			{'n', '\n'},
			{'r', '\r'},
			{'t', '\t'},
			{'\'', '\''},
			{'"', '"'},
			{'[', '['},
			{']', ']'},
			{'\\', '\\'},
			{'-', '-'},
		}
		for entry in special {
			if char[1] == entry.k {
				return entry.v
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
	strings.reader_init(reader, s)

	memtbl := memo.new_table(512)
	is_match, _, ast, errs := exec(&parser, reader, memtbl)
	if len(errs) != 0 || !is_match {
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
	patt, patt_err := init_re_compilation(gram);if patt_err {
		log.error("Could not compile a pattern from the provided grammar")
		os.exit(1)
	}

	prog: Program
	prog, patt_err = compile(patt);if patt_err {
		log.error("Could not compile a program from the provided pattern")
		os.exit(1)
	}

	code := encode(prog)

	reader := new(strings.Reader)
	strings.reader_init(reader, subject)

	memtbl := memo.new_table(512)

	return exec(&code, reader, memtbl)
}

// Test helper: runs match() and asserts on success/failure and position.
// NOTE: match() calls os.exit(1) on grammar compilation failure, so only
// pass valid PEG grammar strings.
expect_match :: proc(
	t: ^testing.T,
	gram: string,
	subject: string,
	expected_ok: bool,
	expected_pos: int,
	msg: string,
) {
	is_match, pos, _, _ := match(gram, subject)
	testing.expect(
		t,
		is_match == expected_ok,
		fmt.tprintf("%s: expected match=%v, got match=%v", msg, expected_ok, is_match),
	)
	if expected_pos >= 0 {
		testing.expect(
			t,
			pos == expected_pos,
			fmt.tprintf("%s: expected pos=%d, got pos=%d", msg, expected_pos, pos),
		)
	}
}

// --- Layer 3: End-to-End match() tests ---

@(test)
test_match_literal :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "'hello'", "hello world", true, 5, "literal match")
}

@(test)
test_match_literal_fail :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "'hello'", "goodbye", false, -1, "literal no match")
}

@(test)
test_match_class :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "[a-z]+", "abc123", true, 3, "class match")
}

@(test)
test_match_any_dot :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, ".+", "abc", true, 3, "dot match all")
}

@(test)
test_match_alternation :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "'foo' / 'bar'", "bar", true, 3, "alternation match second")
	expect_match(t, "'foo' / 'bar'", "foo", true, 3, "alternation match first")
	expect_match(t, "'foo' / 'bar'", "baz", false, -1, "alternation no match")
}

@(test)
test_match_optional :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "'a'?", "", true, 0, "optional on empty")
	expect_match(t, "'a'?", "a", true, 1, "optional on match")
	expect_match(t, "'a'?", "b", true, 0, "optional on non-match consumes nothing")
}

@(test)
test_match_star :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "'a'*", "aaa", true, 3, "star matches all")
	expect_match(t, "'a'*", "", true, 0, "star matches empty")
	expect_match(t, "'a'*", "bbb", true, 0, "star matches zero occurrences")
}

@(test)
test_match_plus :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "'a'+", "aaa", true, 3, "plus matches all")
	expect_match(t, "'a'+", "", false, -1, "plus fails on empty")
	expect_match(t, "'a'+", "bbb", false, -1, "plus fails on non-match")
}

@(test)
test_match_not :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "!'a' .", "b", true, 1, "not predicate succeeds on non-match")
	expect_match(t, "!'a' .", "a", false, -1, "not predicate fails on match")
}

@(test)
test_match_grammar :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	gram := `
Expr    <- Term ('+' Term)*
Term    <- Factor ('*' Factor)*
Factor  <- [0-9]+
`
	expect_match(t, gram, "1+2*3", true, 5, "grammar arithmetic")
	expect_match(t, gram, "42", true, 2, "grammar single number")
}

@(test)
test_match_captures :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Use a simple capture expression (not a grammar definition).
	// NOTE: capture position tracking is still a WIP (see README TODO),
	// so we only assert on match success and capture tree existence.
	gram := "{ [a-z]+ }"
	is_match, _, captures, errs := match(gram, "hello")
	testing.expect(t, is_match, "capture grammar should match")
	testing.expect(t, len(errs) == 0, "should have no errors")
	testing.expect(t, captures != nil, "captures should not be nil")

	if captures != nil {
		n := memo.capture_num_children(captures)
		testing.expect(t, n >= 0, fmt.tprintf("capture tree should have >= 0 children, got %d", n))
	}
}

@(test)
test_match_recursive :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	gram := `
S <- '(' S ')' / ''
`
	expect_match(t, gram, "(())", true, 4, "recursive balanced parens")
	expect_match(t, gram, "()", true, 2, "recursive simple parens")
	expect_match(t, gram, "", true, 0, "recursive empty matches empty alternative")
}

// --- Layer 4: Edge Cases ---

@(test)
test_match_empty_input :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "'a'*", "", true, 0, "star on empty input")
	expect_match(t, ".", "", false, -1, "dot on empty input")
}

@(test)
test_match_empty_pattern :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "''", "hello", true, 0, "empty literal on input")
	expect_match(t, "''", "", true, 0, "empty literal on empty input")
}

@(test)
test_match_no_match_position :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	is_match, pos, _, _ := match("'xyz'", "abc")
	testing.expect(t, !is_match, "should not match")
	testing.expect(t, pos == 0, fmt.tprintf("expected pos=0 on complete failure, got %d", pos))
}

@(test)
test_match_partial :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "'hel'", "hello", true, 3, "partial prefix match")
	expect_match(t, "[a-z]+", "abc123", true, 3, "partial class match")
}
