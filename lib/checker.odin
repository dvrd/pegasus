package pegasus

import "charset"
import "core:fmt"
import "core:mem/virtual"
import "core:strings"
import "core:testing"
import "input"
import "memo"

// A Checker is used so the user can perform additional custom validation of
// parse results. For example, you might want to parse only 8-bit integers by
// matching [0-9]+ and then using a checker to ensure the matched integer is in
// the range 0-256.
Checker :: union {
	^BackReference,
	^MapChecker,
}

MapChecker :: map[string]struct {}

new_map_checker :: proc(strs: []string) -> MapChecker {
	m := make(map[string]struct {})
	for s in strs {
		m[s] = struct {}{}
	}
	return m
}

check_map_checker :: proc(
	m: ^MapChecker,
	b: []byte,
	src: ^input.Input,
	id: int,
	flag: RefKind,
) -> int {
	_, ok := m[string(b)];if ok {
		return 0
	}
	return -1
}

BackReference :: struct {
	symbols: map[int]string,
}

RefKind :: enum {
	RefDef,
	RefUse,
	RefBlock,
}

new_back_reference :: proc() -> BackReference {
	return BackReference{make(map[int]string)}
}

check_back_reference :: proc(
	r: ^BackReference,
	b: []byte,
	src: ^input.Input,
	id: int,
	flag: RefKind,
) -> int {
	#partial switch flag {
	case .RefDef:
		r.symbols[id] = string(b)
		return 0
	case .RefUse:
		back := r.symbols[id]
		buf := make([]byte, len(back))
		n, _ := strings.reader_read_at(&src.r, buf, i64(input.pos(src)))
		if n == len(buf) && string(buf) == back {
			return n
		}
	return -1
}

// --- Tests ---

// Helper: compile pattern → encode → exec against subject string.
exec_pattern :: proc(
	patt: Pattern,
	subject: string,
) -> (
	bool,
	int,
	^memo.Capture,
	[]ParseError,
) {
	prog, err := compile(patt)
	if err {return false, 0, nil, nil}
	code := encode(prog)
	reader := new(strings.Reader)
	strings.reader_init(reader, subject)
	memtbl := memo.new_table(0)
	return exec(&code, reader, memtbl)
}

@(test)
test_map_checker_keyword_accepted :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	mc := new_map_checker([]string{"if", "else", "while"})
	patt := check_pattern(plus(set(charset.range('a', 'z'))), &mc)
	ok, pos, _, _ := exec_pattern(patt, "if")
	testing.expect(t, ok, "should match keyword 'if'")
	testing.expect(t, pos == 2, fmt.tprintf("expected pos=2, got pos=%d", pos))
}

@(test)
test_map_checker_keyword_rejected :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	mc := new_map_checker([]string{"if", "else", "while"})
	patt := check_pattern(plus(set(charset.range('a', 'z'))), &mc)
	ok, _, _, _ := exec_pattern(patt, "foo")
	testing.expect(t, !ok, "should reject non-keyword 'foo'")
}

@(test)
test_map_checker_empty_map_rejects :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	mc := new_map_checker([]string{})
	patt := check_pattern(plus(set(charset.range('a', 'z'))), &mc)
	ok, _, _, _ := exec_pattern(patt, "anything")
	testing.expect(t, !ok, "empty map checker should reject everything")
}

@(test)
test_map_checker_exact_boundary :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// "while" is a keyword, but "whileloop" should match [a-z]+ as "whileloop"
	// which is NOT in the keyword set — so the checker should reject it
	mc := new_map_checker([]string{"while"})
	patt := check_pattern(plus(set(charset.range('a', 'z'))), &mc)
	ok, _, _, _ := exec_pattern(patt, "whileloop")
	testing.expect(t, !ok, "should reject 'whileloop' — not exact keyword match")
}

@(test)
test_back_reference_same_symbol :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	br := new_back_reference()
	// Pattern: define symbol 0 from [a-z]+, then literal '=', then use symbol 0
	def_part := check_pattern_with_flags(
		plus(set(charset.range('a', 'z'))), &br, 0, int(RefKind.RefDef),
	)
	eq := literal("=")
	// For RefUse, the inner pattern matches nothing — the checker reads ahead itself
	// We use any(0) which matches zero chars (the empty pattern)
	use_part := check_pattern_with_flags(
		any(0), &br, 0, int(RefKind.RefUse),
	)
	patt := concat(def_part, eq, use_part)
	ok, pos, _, _ := exec_pattern(patt, "abc=abc")
	testing.expect(t, ok, "should match 'abc=abc' — same symbol on both sides")
	testing.expect(t, pos == 7, fmt.tprintf("expected pos=7, got pos=%d", pos))
}

@(test)
test_back_reference_different_symbol :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	br := new_back_reference()
	def_part := check_pattern_with_flags(
		plus(set(charset.range('a', 'z'))), &br, 0, int(RefKind.RefDef),
	)
	eq := literal("=")
	use_part := check_pattern_with_flags(
		any(0), &br, 0, int(RefKind.RefUse),
	)
	patt := concat(def_part, eq, use_part)
	ok, _, _, _ := exec_pattern(patt, "abc=xyz")
	testing.expect(t, !ok, "should reject 'abc=xyz' — different symbols")
}

@(test)
test_nil_checker_returns_negative :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Nil Checker (zero value of union) should return -1
	c: Checker
	s := "test"
	result := check(c, transmute([]byte)s, nil, 0, .RefDef)
	testing.expect(t, result == -1, fmt.tprintf("nil checker should return -1, got %d", result))
}

@(test)
test_new_map_checker_contains_keys :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	mc := new_map_checker([]string{"alpha", "beta", "gamma"})
	_, ok1 := mc["alpha"]
	_, ok2 := mc["beta"]
	_, ok3 := mc["gamma"]
	_, ok4 := mc["delta"]
	testing.expect(t, ok1, "should contain 'alpha'")
	testing.expect(t, ok2, "should contain 'beta'")
	testing.expect(t, ok3, "should contain 'gamma'")
	testing.expect(t, !ok4, "should not contain 'delta'")
}

@(test)
test_back_reference_refblock_returns_zero :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	br := new_back_reference()
	s := "test"
	result := check_back_reference(&br, transmute([]byte)s, nil, 0, .RefBlock)
	testing.expect(t, result == 0, fmt.tprintf("RefBlock should return 0, got %d", result))
}

	return 0
}

new_checker :: proc {
	new_map_checker,
	new_back_reference,
}

check :: proc(
	checker: Checker,
	b: []byte,
	src: ^input.Input,
	id: int,
	flag: RefKind,
) -> int {
	switch c in checker {
	case ^BackReference:
		return check_back_reference(c, b, src, id, flag)
	case ^MapChecker:
		return check_map_checker(c, b, src, id, flag)
	}
	return -1
}
