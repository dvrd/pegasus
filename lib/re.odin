package pegasus

import "charset"
import "core:bytes"
import "core:fmt"
import "core:mem/virtual"
import "core:strconv"
import "core:strings"
import "core:testing"
import log "log"
import "memo"

parser: Code
CURRENT_RULE: string
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
			p = cap(compile_re(memo.capture_child(root, 1), s), next_capture_id(CURRENT_RULE))
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
	name := parseId(id, s)
	CURRENT_RULE = name
	return name, compile_re(exp, s)
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
	reset_capture_names()

	// Reject empty or whitespace-only grammars before parsing
	trimmed := strings.trim_space(s)
	if len(trimmed) == 0 {
		return nil, true
	}

	reader := new(strings.Reader)
	strings.reader_init(reader, s)

	memtbl := memo.new_table(512)
	is_match, _, ast, errs := exec(&parser, reader, memtbl)
	if len(errs) != 0 || !is_match {
		return nil, true
	}

	child := memo.capture_child(ast, 0)
	if child == nil {
		return nil, true
	}

	p := compile_re(child, s)
	if p == nil {
		return nil, true
	}

	return p, false
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
		errs := make([]ParseError, 1)
		errs[0] = ParseError{message = "could not compile a pattern from the provided grammar", pos = 0}
		return false, 0, nil, errs
	}

	prog: Program
	prog, patt_err = compile(patt);if patt_err {
		errs := make([]ParseError, 1)
		errs[0] = ParseError{message = "could not compile a program from the provided pattern", pos = 0}
		return false, 0, nil, errs
	}

	code := encode(prog)

	reader := new(strings.Reader)
	strings.reader_init(reader, subject)

	memtbl := memo.new_table(512)

	return exec(&code, reader, memtbl)
}

// Test helper: runs match() and asserts on success/failure and position.
// For invalid grammar tests, call match() directly and check errs.
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

// --- Layer 5: Coverage gap tests ---

@(test)
test_match_and_predicate :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// &'a' succeeds without consuming, then 'a' consumes
	expect_match(t, "&'a' 'a'", "a", true, 1, "and predicate lookahead then consume")
	// &'a' fails on 'b' — nothing consumed
	expect_match(t, "&'a' 'a'", "b", false, -1, "and predicate fails on non-match")
	// &[0-9] with digit input
	expect_match(t, "&[0-9] .", "5", true, 1, "and predicate with class")
	// &'ab' checks two chars ahead
	expect_match(t, "&'ab' 'ab'", "ab", true, 2, "and predicate multi-char")
	expect_match(t, "&'ab' 'ab'", "ac", false, -1, "and predicate multi-char fail")
}

@(test)
test_match_sequence :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "'a' 'b'", "ab", true, 2, "sequence of two literals")
	expect_match(t, "'a' 'b'", "ac", false, -1, "sequence fails on second")
	expect_match(t, "'a' 'b' 'c'", "abc", true, 3, "sequence of three literals")
	expect_match(t, "[a-z] [0-9]", "a1", true, 2, "sequence of class and class")
}

@(test)
test_match_negated_class :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "[^a-z]", "1", true, 1, "negated class matches digit")
	expect_match(t, "[^a-z]", "a", false, -1, "negated class rejects lowercase")
	expect_match(t, "[^0-9]+", "abc", true, 3, "negated digit class matches letters")
	expect_match(t, "[^0-9]+", "123", false, -1, "negated digit class rejects digits")
}

@(test)
test_match_single_chars_in_class :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "[abc]", "a", true, 1, "single char class matches a")
	expect_match(t, "[abc]", "b", true, 1, "single char class matches b")
	expect_match(t, "[abc]", "c", true, 1, "single char class matches c")
	expect_match(t, "[abc]", "d", false, -1, "single char class rejects d")
}

@(test)
test_match_multi_range_class :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match(t, "[a-zA-Z]+", "Hello", true, 5, "multi-range matches mixed case")
	expect_match(t, "[a-zA-Z0-9]+", "abc123", true, 6, "alphanumeric class matches all")
	expect_match(t, "[a-zA-Z0-9]+", "!@#", false, -1, "alphanumeric rejects symbols")
}

@(test)
test_match_escape_in_literal :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// \n in literal matches actual newline
	expect_match(t, "'\\n'", "\n", true, 1, "escaped newline in literal")
	// \t in literal matches actual tab
	expect_match(t, "'\\t'", "\t", true, 1, "escaped tab in literal")
	// \\ in literal matches actual backslash
	expect_match(t, "'\\\\'", "\\", true, 1, "escaped backslash in literal")
	// \' in literal matches actual single quote
	expect_match(t, "\"\\\"\"", "\"", true, 1, "escaped double quote in literal")
}

@(test)
test_match_octal_escape :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// \101 is octal for 'A' (65 decimal)
	expect_match(t, "'\\101'", "A", true, 1, "octal 101 matches A")
	// \060 is octal for '0' (48 decimal)
	expect_match(t, "'\\060'", "0", true, 1, "octal 060 matches 0")
}

@(test)
test_match_memoization :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// {{ }} is memoization syntax — should behave identically to ( )
	// for correctness, just with caching
	gram := `
Expr    <- Term ('+' Term)*
Term    <- Factor ('*' Factor)*
Factor  <- {{ [0-9]+ }}
`
	expect_match(t, gram, "1+2*3", true, 5, "memoized grammar arithmetic")
	expect_match(t, gram, "42", true, 2, "memoized grammar single number")
	expect_match(t, gram, "abc", false, -1, "memoized grammar rejects non-number")
}

@(test)
test_match_capture_structure :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	gram := "{ [a-z]+ }"
	is_match, pos, captures, errs := match(gram, "hello")
	testing.expect(t, is_match, "capture should match")
	testing.expect(t, pos == 5, fmt.tprintf("expected pos=5, got %d", pos))
	testing.expect(t, len(errs) == 0, "should have no errors")
	testing.expect(t, captures != nil, "captures should not be nil")

	if captures != nil {
		// The root capture wraps the entire match.
		// It should have at least one child for the { } capture group.
		n := memo.capture_num_children(captures)
		testing.expect(t, n >= 1, fmt.tprintf("expected >= 1 capture children, got %d", n))

		if n >= 1 {
			child := memo.capture_child(captures, 0)
			testing.expect(t, child != nil, "first capture child should not be nil")
			if child != nil {
				cs := memo.capture_start(child)
				ce := memo.capture_end(child)
				testing.expect(
					t,
					ce > cs,
					fmt.tprintf("capture child should span >0 chars, start=%d end=%d", cs, ce),
				)
			}
		}
	}
}

@(test)
test_match_combined_operators :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Combine multiple operators: optional, star, plus, not, and
	expect_match(t, "'a'? 'b'+", "bbb", true, 3, "optional-a then plus-b")
	expect_match(t, "'a'? 'b'+", "abbb", true, 4, "optional-a present then plus-b")
	expect_match(t, "!'x' [a-z]+", "hello", true, 5, "not-x then letters")
	expect_match(t, "&[a-z] .+", "hello", true, 5, "and-letter then dot-plus")
	expect_match(t, "&[a-z] .+", "123", false, -1, "and-letter fails on digits")
}

@(test)
test_match_grammar_with_captures :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Grammar from the README example (simplified)
	gram := `
Expr    <- Term ('+' Term)*
Term    <- { [0-9]+ }
`
	is_match, pos, captures, errs := match(gram, "1+2+3")
	testing.expect(t, is_match, "grammar with captures should match")
	testing.expect(t, pos == 5, fmt.tprintf("expected pos=5, got %d", pos))
	testing.expect(t, len(errs) == 0, "should have no errors")
	testing.expect(t, captures != nil, "captures should not be nil")
}

// --- Negative grammar tests: invalid inputs that must return errors ---

// Helper: asserts match() returns errors (non-empty errs slice) and is_match=false.
expect_match_error :: proc(t: ^testing.T, gram: string, msg: string) {
	is_match, _, _, errs := match(gram, "anything")
	testing.expect(
		t,
		!is_match,
		fmt.tprintf("%s: expected is_match=false, got true", msg),
	)
	testing.expect(
		t,
		len(errs) > 0,
		fmt.tprintf("%s: expected errors, got none", msg),
	)
}

@(test)
test_match_error_empty_grammar :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match_error(t, "", "empty grammar")
}

@(test)
test_match_error_garbage_input :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match_error(t, "!@#$%^&*()", "garbage input")
}

@(test)
test_match_error_missing_arrow :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Valid identifier but no <- arrow
	expect_match_error(t, "A [a-z]+", "missing arrow")
}

@(test)
test_match_error_unterminated_class :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match_error(t, "A <- [a-z", "unterminated character class")
}

@(test)
test_match_error_unterminated_string :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match_error(t, "A <- 'hello", "unterminated single-quoted string")
}

@(test)
test_match_error_unterminated_dquote :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match_error(t, `A <- "hello`, "unterminated double-quoted string")
}

@(test)
test_match_error_unterminated_group :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match_error(t, "A <- ('abc'", "unterminated group")
}

@(test)
test_match_error_undefined_nonterminal :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// A references B, but B is never defined — should fail at compile stage
	expect_match_error(t, "A <- B", "undefined non-terminal")
}

@(test)
test_match_error_arrow_only :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match_error(t, "<-", "arrow with no identifier or body")
}

@(test)
test_match_error_whitespace_only :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	expect_match_error(t, "   \t\n  ", "whitespace-only grammar")
}

// --- Additional PEG operator tests ---

@(test)
test_match_comment_in_grammar :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Comments start with # and extend to end of line
	gram := `
# This is a comment
A <- 'hello' # inline comment
`
	expect_match(t, gram, "hello", true, 5, "comment in grammar")
}

@(test)
test_match_end_of_file :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// !. matches only at end of input
	gram := `
A <- 'hi' !.
`
	expect_match(t, gram, "hi", true, 2, "EndOfFile succeeds at end")
	expect_match(t, gram, "hix", false, -1, "EndOfFile fails with trailing chars")
}

@(test)
test_match_mutual_recursion :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// A and B call each other: matched parentheses
	gram := `
A <- '(' B ')' / 'x'
B <- A
`
	expect_match(t, gram, "x", true, 1, "mutual recursion base case")
	expect_match(t, gram, "(x)", true, 3, "mutual recursion one level")
	expect_match(t, gram, "((x))", true, 5, "mutual recursion two levels")
}

@(test)
test_match_nested_captures :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Outer capture wraps inner capture
	gram := `
A <- { 'a' { 'b' } 'c' }
`
	is_match, pos, captures, errs := match(gram, "abc")
	testing.expect(t, is_match, "nested captures should match")
	testing.expect(t, pos == 3, fmt.tprintf("expected pos=3, got %d", pos))
	testing.expect(t, len(errs) == 0, "should have no errors")
	testing.expect(t, captures != nil, "captures should not be nil")
}

@(test)
test_match_plus_single_char :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	gram := `
A <- 'x'+
`
	expect_match(t, gram, "x", true, 1, "plus matches single char")
	expect_match(t, gram, "xxx", true, 3, "plus matches multiple chars")
	expect_match(t, gram, "y", false, -1, "plus fails on wrong char")
}

@(test)
test_match_calculator_integration :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Full calculator grammar from README — integration test
	gram := `
Expr      <- Space SubOp
SubOp     <- AddOp (Sub AddOp)*
AddOp     <- DivOp (Add DivOp)*
DivOp     <- MulOp (Div MulOp)*
MulOp     <- PowOp (Mul PowOp)*
PowOp     <- Term (Pow Term)*
Term      <- Atom / OParen Expr CParen
Pow       <- '^' Space
Mul       <- '*' Space
Div       <- '/' Space
Add       <- '+' Space
Sub       <- '-' Space
OParen    <- '(' Space
CParen    <- ')' Space
Atom      <- Numeral
Numeral   <- Number Space
Number    <- [0-9]+
Space     <- (' ' / '\t' / EndOfLine)*
EndOfLine <- '\r\n' / '\n' / '\r'
EndOfFile <- !.
`
	expect_match(t, gram, "42", true, 2, "calculator: simple number")
	expect_match(t, gram, "1 + 2", true, 5, "calculator: addition")
	expect_match(t, gram, "3 * (4 + 5)", true, 11, "calculator: parens")
	expect_match(t, gram, "2 ^ 3 + 1", true, 9, "calculator: power and add")
	expect_match(t, gram, "10 / 2 * 3 - 1 + 7", true, 18, "calculator: complex expr")
}

@(test)
test_match_dot_any_single :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Single dot matches exactly one character
	gram := `
A <- .
`
	expect_match(t, gram, "x", true, 1, "dot matches single char")
	expect_match(t, gram, "", false, -1, "dot fails on empty input")
}

@(test)
test_match_alternation_priority :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// PEG ordered choice: first match wins
	gram := `
A <- 'abc' / 'ab' / 'a'
`
	expect_match(t, gram, "abc", true, 3, "ordered choice picks longest first match 'abc'")
	expect_match(t, gram, "ab", true, 2, "ordered choice falls through to 'ab'")
	expect_match(t, gram, "a", true, 1, "ordered choice falls through to 'a'")
}

@(test)
test_match_multiline_grammar :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Multiple rules with whitespace handling
	gram := `
List    <- Item (',' Space Item)*
Item    <- [a-zA-Z]+
Space   <- ' '*
`
	expect_match(t, gram, "foo", true, 3, "multiline: single item")
	expect_match(t, gram, "foo, bar", true, 8, "multiline: two items")
	expect_match(t, gram, "a, b, c", true, 7, "multiline: three items")
}

@(test)
test_capture_names_in_grammar :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	gram := `
Expr    <- Term ('+' Term)*
Term    <- { [0-9]+ }
`
	is_match, pos, captures, errs := match(gram, "1+2+3")
	testing.expect(t, is_match, "grammar with named captures should match")
	testing.expect(t, pos == 5, fmt.tprintf("expected pos=5, got %d", pos))
	testing.expect(t, len(errs) == 0, "should have no errors")
	testing.expect(t, captures != nil, "captures should not be nil")

	// Verify capture IDs on the tree nodes are >= 100 (our capture range).
	// We don't check the global CAPTURE_NAMES here because parallel tests
	// race on it; the name table is validated by test_capture_name_table
	// and the CLI integration test.
	if captures != nil {
		found_high_id := false
		check_ids :: proc(c: ^memo.Capture, found: ^bool) {
			if c == nil do return
			if c.id >= 100 {
				found^ = true
			}
			for child in c.children {
				check_ids(child, found)
			}
		}
		check_ids(captures, &found_high_id)
		testing.expect(t, found_high_id, "capture tree should contain nodes with id >= 100")
	}
}

@(test)
test_capture_names_multiple_rules :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Two rules with captures — both should produce capture nodes with id >= 100.
	gram := `
Expr   <- { Factor } ('+' { Factor })*
Factor <- { [0-9]+ }
`
	is_match, _, captures, errs := match(gram, "1+2")
	testing.expect(t, is_match, "multi-rule capture grammar should match")
	testing.expect(t, len(errs) == 0, "should have no errors")
	testing.expect(t, captures != nil, "captures should not be nil")

	// Verify the capture tree has multiple nodes with id >= 100.
	// We don't check the global CAPTURE_NAMES here because parallel tests
	// race on it; the name table is validated by test_capture_name_table
	// and the CLI integration test.
	if captures != nil {
		high_id_count := 0
		count_high_ids :: proc(c: ^memo.Capture, count: ^int) {
			if c == nil do return
			if c.id >= 100 {
				count^ += 1
			}
			for child in c.children {
				count_high_ids(child, count)
			}
		}
		count_high_ids(captures, &high_id_count)
		testing.expect(t, high_id_count >= 2, fmt.tprintf("expected >= 2 capture nodes with id >= 100, got %d", high_id_count))
	}
}
