package charset

import "core:fmt"
import "core:math/bits"
import "core:mem/virtual"
import "core:strings"
import "core:testing"

log_2_word_size :: 6
word_size :: 64

// A Set represents a set of chars.
Set :: struct {
	// Bits is the bit array for indicating which chars are in the set.
	// We have 256 bits because a char can have 256 different values.
	bits: [4]u64,
}

// A SmallSet is the same as a Set but can only represent 128 possible chars.
// This is an optimization, since in the common case, only ASCII bytes are
// used which are <128. The full Set is only necessary when unicode control
// characters must be matched.
SmallSet :: struct {
	bits: [2]u64,
}

// small_set_size returns the number of chars matched by this Set.
small_set_size :: proc(c: SmallSet) -> int {
	return int(bits.count_ones(c.bits[0]) + bits.count_ones(c.bits[1]))
}

// small_set_has checks if a charset accepts a character.
// Pointer receiver is for performance.
small_set_has :: proc(c: ^SmallSet, r: byte) -> bool {
	return(
		c.bits[r >> log_2_word_size] & (u64(1) << (r & (word_size - 1))) !=
		0 \
	)
}

// is_small returns true if this set can be converted to a small set. In other
// words, if this set only matches bytes <128.
is_small :: proc(c: ^Set) -> bool {
	return c.bits[2] == 0 && c.bits[3] == 0
}

// to_small_set converts this Set to a SmallSet.
to_small_set :: proc(c: Set) -> SmallSet {
	return SmallSet{[2]u64{c.bits[0], c.bits[1]}}
}

// new_charset returns a Set which accepts all chars in 'chars'. Note
// that all chars must be valid ASCII characters (<128).
new_charset :: proc(chars: []byte) -> (set: ^Set) {
	set = new(Set)
	set.bits = [4]u64{0, 0, 0, 0}
	for c in chars {
		switch {
		case c < 64:
			bit := u64(1) << c
			set.bits[0] |= bit
		case c < 128:
			bit := u64(1) << (c - 64)
			set.bits[1] |= bit
		case c < 192:
			bit := u64(1) << (c - 128)
			set.bits[2] |= bit
		case:
			bit := u64(1) << (c - 192)
			set.bits[3] |= bit
		}
	}

	return
}

// range returns a charset matching all characters between `low` and
// `high` inclusive.
range :: proc(low, high: byte) -> (set: ^Set) {
	set = new(Set)
	set.bits = [4]u64{0, 0, 0, 0}
	for c := u64(low); c <= u64(high); c += 1 {
		switch {
		case c < 64:
			bit := u64(1) << c
			set.bits[0] |= bit
		case c < 128:
			bit := u64(1) << (c - 64)
			set.bits[1] |= bit
		case c < 192:
			bit := u64(1) << (c - 128)
			set.bits[2] |= bit
		case:
			bit := u64(1) << (c - 192)
			set.bits[3] |= bit
		}
	}

	return
}

// complement returns a charset that matches all characters except for those
// matched by `c`.
complement :: proc(c: ^Set) -> (s: ^Set) {
	s = new(Set)
	s.bits = [4]u64{~c.bits[0], ~c.bits[1], ~c.bits[2], ~c.bits[3]}
	return
}

// add combines the characters two charsets match together.
add :: proc(c: ^Set, c1: ^Set) -> (s: ^Set) {
	s = new(Set)
	s.bits = [4]u64{
		c1.bits[0] | c.bits[0],
		c1.bits[1] | c.bits[1],
		c1.bits[2] | c.bits[2],
		c1.bits[3] | c.bits[3],
	}

	return
}

// sub removes from 'c' any characters in 'c1'.
sub :: proc(c: ^Set, c1: ^Set) -> (s: ^Set) {
	s = new(Set)
	s.bits = [4]u64{
		~c1.bits[0] & c.bits[0],
		~c1.bits[1] & c.bits[1],
		~c1.bits[2] & c.bits[2],
		~c1.bits[3] & c.bits[3],
	}

	return
}

// size returns the number of chars matched by this Set.
size :: proc(c: ^Set) -> int {
	return int(
		bits.count_ones(c.bits[0]) +
		bits.count_ones(c.bits[1]) +
		bits.count_ones(c.bits[2]) +
		bits.count_ones(c.bits[3]),
	)
}

// Has checks if a charset accepts a character.
// Pointer receiver is for performance.
has :: proc(c: ^Set, r: byte) -> bool {
	return(
		c.bits[r >> log_2_word_size] & (u64(1) << (r & (word_size - 1))) !=
		0 \
	)
}

// String returns the string representation of the charset.
string_from_charset :: proc(c: ^Set) -> string {
	builder := strings.builder_make()
	in_range := false
	for b := int(0); b <= 255; b += 1 {
		if has(c, byte(b)) && b == 255 {
			strings.write_rune(&builder, rune(b))
		} else if has(c, byte(b)) && !in_range {
			in_range = true
			if has(c, byte(b + 1)) {
				strings.write_rune(&builder, rune(b))
				strings.write_string(&builder, "..")
			}
		} else if !has(c, byte(b)) && in_range {
			in_range = false
			strings.write_rune(&builder, rune(b - 1))
			strings.write_string(&builder, ",")
		}
	}
	s := strings.to_string(builder)
	if s != "" && s[len(s) - 1] == ',' {
		s = s[:len(s) - 1]
	}
	strings.builder_reset(&builder)
	strings.write_string(&builder, "{")
	strings.write_string(&builder, s)
	strings.write_string(&builder, "}")
	s = strings.to_string(builder)
	return s
}

in_set :: proc(set: ^Set, included, not_included: []byte, t: ^testing.T) {
	msg: string
	for r in included {
		msg = fmt.sbprintf(
			&strings.Builder{},
			"Error: %c returned 'not in set'",
			r,
		)
		testing.expect(t, has(set, r), msg)
	}

	for r in not_included {
		msg = fmt.sbprintf(
			&strings.Builder{},
			"Error: %c returned 'in set'",
			r,
		)
		testing.expect(t, !has(set, r), msg)
	}
}

@(test)
test_set :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	included: [6]byte = {'a', 'b', 'c', 'd', '{', '}'}
	not_included: [5]byte = {'x', 'y', 'z', '[', ']'}

	set := new_charset(included[:])

	in_set(set, included[:], not_included[:], t)
}

@(test)
test_range_union :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	set := range('a', 'z')
	set = add(set, range('A', 'Z'))

	included: []byte = {'a', 'b', 'c', 'd', 'z', 'y', 'A', 'Z', 'B'}
	not_included: []byte = {'0', '1', '2', 0}

	in_set(set, included, not_included, t)
}

@(test)
test_complement :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	included := []byte{'a', 'b', 'c', 'd', '{', '}'}
	not_included := []byte{'x', 'y', 'z', '[', ']'}

	set := complement(new_charset(included))

	in_set(set, not_included, included, t)
}

@(test)
test_big_set :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	included := []byte{200, 201, 203}
	not_included := []byte{0, 1, 2}

	r: rune = '\xff'
	set := range(128, u8(r))

	in_set(set, included, not_included, t)
}

@(test)
test_charset_sub :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Create set {a, b, c, d, e} and subtract {b, d}
	s1 := new_charset([]byte{'a', 'b', 'c', 'd', 'e'})
	s2 := new_charset([]byte{'b', 'd'})
	result := sub(s1, s2)

	// Should have {a, c, e}
	testing.expect(t, has(result, 'a'), "result should contain 'a'")
	testing.expect(t, !has(result, 'b'), "result should not contain 'b'")
	testing.expect(t, has(result, 'c'), "result should contain 'c'")
	testing.expect(t, !has(result, 'd'), "result should not contain 'd'")
	testing.expect(t, has(result, 'e'), "result should contain 'e'")
}

@(test)
test_charset_size :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Empty set
	empty := new_charset([]byte{})
	testing.expect(t, size(empty) == 0, fmt.tprintf("expected size 0, got %d", size(empty)))

	// Single char
	single := new_charset([]byte{'x'})
	testing.expect(t, size(single) == 1, fmt.tprintf("expected size 1, got %d", size(single)))

	// Range a-z = 26 chars
	az := range('a', 'z')
	testing.expect(t, size(az) == 26, fmt.tprintf("expected size 26, got %d", size(az)))

	// Union of two ranges
	both := add(range('a', 'z'), range('A', 'Z'))
	testing.expect(t, size(both) == 52, fmt.tprintf("expected size 52, got %d", size(both)))
}

@(test)
test_charset_string :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// A simple range should produce a readable string
	s := range('a', 'c')
	str := string_from_charset(s)
	testing.expect(t, len(str) > 0, "string_from_charset should produce non-empty string")
	// Should contain braces
	testing.expect(t, str[0] == '{', fmt.tprintf("expected string to start with '{', got '%s'", str))
	testing.expect(t, str[len(str) - 1] == '}', fmt.tprintf("expected string to end with '}', got '%s'", str))
}
