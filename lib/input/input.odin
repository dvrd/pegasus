package input

import "core:fmt"
import "core:mem/virtual"
import "core:strings"
import "core:testing"

bufsz :: 4096

Input :: struct {
	r:        strings.Reader,
	chunk:    [bufsz]byte, // cached data.
	b:        [1]byte,
	nchunk:   int, // size of the cache.
	base:     int, // the position within the reader that the chunk starts at.
	coff:     int, // the offset within the chunk we are reading at.
	furthest: int, // the furthest position we have read.
}

// NewInput creates a new Input wrapper for the io.Reader_At.
new_input :: proc(r: ^strings.Reader) -> Input {
	i := Input {
		r = r^,
	}
	refill(&i, i.base)
	return i
}

refill :: proc(i: ^Input, pos: int) {
	i.base = pos
	i.coff = 0
	i.nchunk, _ = strings.reader_read_at(&i.r, i.chunk[:], i64(i.base))
}

// Peek returns the next byte in the stream or 'false' if there are no more
// bytes. Successive calls to Peek will return the same value unless there is a
// call to SeekTo or Advance in between.
peek :: proc(i: ^Input) -> (byte, bool) {
	pos := i.base + i.coff
	if pos > i.furthest {
		i.furthest = pos
	}

	return i.chunk[i.coff], i.nchunk != 0
}

peek_before :: proc(i: ^Input) -> (byte, bool) {
	if i.base + i.coff - 1 < 0 {
		return 0, false
	}
	if i.coff >= 1 {
		return i.chunk[i.coff - 1], i.nchunk != 0
	}
	n, _ := strings.reader_read_at(&i.r, i.b[:], i64(pos(i) - 1))
	return i.b[0], n == 1
}

// SeekTo moves the current read position to the desired read position. Returns
// true if the seek went to a valid location within the reader, and false
// otherwise. In other words, if seek returns true the next call to Peek will
// return a valid byte.
seek_to :: proc(i: ^Input, pos: int) -> bool {
	// check if the seek position in within the current chunk and if so just
	// update the internal offset.
	chunkEnd := i.base + i.nchunk
	if pos < chunkEnd && pos >= i.base {
		i.coff = pos - i.base
		return true
	}

	// refill the cache (moves the base)
	refill(i, pos)
	return i.nchunk != 0
}

// Advance moves the offset forward by 'n' bytes. Returns true if the advance
// was successful (n chars were successfully skipped) and false otherwise. Note
// that even if Advance returns true the next call to Peek may return false if
// the advance went to the exact end of the data.
advance :: proc(i: ^Input, n: int) -> bool {
	if i.nchunk == 0 {
		return false
	}

	i.coff += n
	if i.coff > i.nchunk {
		refill(i, i.base + i.coff)
		return false
	} else if i.coff == i.nchunk {
		refill(i, i.base + i.coff)
	}
	return true
}

slice :: proc(i: ^Input, low, high: int) -> []byte {
	b := make([]byte, high)
	strings.reader_read_at(&i.r, b, i64(low))
	return b
}

pos :: proc(i: ^Input) -> int {
	return i.base + i.coff
}

@(test)
test_input :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	r := new(strings.Reader)
	ok: bool

	strings.reader_init(r, "foo bar baz")
	i := new_input(r)

	b, _ := peek(&i)
	msg := fmt.tprintf("incorrect peek got %c", b)
	testing.expect(t, b == 'f', msg)

	advance(&i, 1)
	b, _ = peek(&i)
	msg = fmt.tprintf("incorrect peek got %c", b)
	testing.expect(t, b == 'o', msg)

	advance(&i, 1)
	b, _ = peek(&i)
	msg = fmt.tprintf("incorrect peek got %c", b)
	testing.expect(t, b == 'o', msg)

	slice: []byte = {0, 0, 0}
	strings.reader_read_at(&i.r, slice, 4)
	msg = fmt.tprintf("incorrect slice, got %s", string(slice))
	testing.expect(t, string(slice) == "bar", msg)

	success := advance(&i, 9)
	testing.expect(t, success, "incorrect: couldn't advance by 9")

	b, ok = peek(&i)
	msg = fmt.tprintf("peek past end of buffer should return false, got %c", b)
	testing.expect(t, !ok, msg)

}

@(test)
test_input_peek_before :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	r := new(strings.Reader)
	strings.reader_init(r, "abcdef")
	i := new_input(r)

	// At position 0, peek_before should return false (no previous byte)
	_, ok := peek_before(&i)
	testing.expect(t, !ok, "peek_before at position 0 should return false")

	// Advance to position 1, peek_before should return 'a'
	advance(&i, 1)
	b, ok2 := peek_before(&i)
	testing.expect(t, ok2, "peek_before at position 1 should succeed")
	testing.expect(t, b == 'a', fmt.tprintf("expected peek_before='a', got '%c'", b))

	// Advance to position 3, peek_before should return 'c'
	advance(&i, 2)
	b, ok2 = peek_before(&i)
	testing.expect(t, ok2, "peek_before at position 3 should succeed")
	testing.expect(t, b == 'c', fmt.tprintf("expected peek_before='c', got '%c'", b))
}

@(test)
test_input_seek_to :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	r := new(strings.Reader)
	strings.reader_init(r, "hello world")
	i := new_input(r)

	// Seek to position 6 ('w')
	ok := seek_to(&i, 6)
	testing.expect(t, ok, "seek_to(6) should succeed")
	b, ok2 := peek(&i)
	testing.expect(t, ok2, "peek after seek should succeed")
	testing.expect(t, b == 'w', fmt.tprintf("expected 'w' at position 6, got '%c'", b))

	// Seek back to position 0
	ok = seek_to(&i, 0)
	testing.expect(t, ok, "seek_to(0) should succeed")
	b, ok2 = peek(&i)
	testing.expect(t, ok2, "peek after seek to 0 should succeed")
	testing.expect(t, b == 'h', fmt.tprintf("expected 'h' at position 0, got '%c'", b))

	// Seek past end
	ok = seek_to(&i, 100)
	testing.expect(t, !ok, "seek_to past end should return false")
}

@(test)
test_input_slice :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	r := new(strings.Reader)
	strings.reader_init(r, "hello world")
	i := new_input(r)

	// Read slice [0, 5) = "hello"
	s := slice(&i, 0, 5)
	testing.expect(t, string(s) == "hello", fmt.tprintf("expected 'hello', got '%s'", string(s)))

	// Read slice [6, 11) = "world"
	s2 := slice(&i, 6, 11)
	testing.expect(t, string(s2[:5]) == "world", fmt.tprintf("expected 'world', got '%s'", string(s2[:5])))
}
