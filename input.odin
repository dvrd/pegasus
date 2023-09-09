package pegasus

import "core:fmt"
import "core:io"
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
new_input :: proc(r: strings.Reader) -> Input {
	i := Input {
		r = r,
	}
	input_refill(&i, i.base)
	return i
}

input_refill :: proc(i: ^Input, pos: int) {
	i.base = pos
	i.coff = 0
	i.nchunk, _ = strings.reader_read_at(&i.r, i.chunk[:], i64(i.base))
}

// Peek returns the next byte in the stream or 'false' if there are no more
// bytes. Successive calls to Peek will return the same value unless there is a
// call to SeekTo or Advance in between.
input_peek :: proc(i: ^Input) -> (byte, bool) {
	pos := i.base + i.coff
	if pos > i.furthest {
		i.furthest = pos
	}

	return i.chunk[i.coff], i.nchunk != 0
}

input_peek_before :: proc(i: ^Input) -> (byte, bool) {
	if i.base + i.coff - 1 < 0 {
		return 0, false
	}
	if i.coff >= 1 {
		return i.chunk[i.coff - 1], i.nchunk != 0
	}
	n, _ := strings.reader_read_at(&i.r, i.b[:], i64(input_pos(i) - 1))
	return i.b[0], n == 1
}

// SeekTo moves the current read position to the desired read position. Returns
// true if the seek went to a valid location within the reader, and false
// otherwise. In other words, if seek returns true the next call to Peek will
// return a valid byte.
input_seek_to :: proc(i: ^Input, pos: int) -> bool {
	// check if the seek position in within the current chunk and if so just
	// update the internal offset.
	chunkEnd := i.base + i.nchunk
	if pos < chunkEnd && pos >= i.base {
		i.coff = pos - i.base
		return true
	}

	// refill the cache (moves the base)
	input_refill(i, pos)
	return i.nchunk != 0
}

// Advance moves the offset forward by 'n' bytes. Returns true if the advance
// was successful (n chars were successfully skipped) and false otherwise. Note
// that even if Advance returns true the next call to Peek may return false if
// the advance went to the exact end of the data.
input_advance :: proc(i: ^Input, n: int) -> bool {
	if i.nchunk == 0 {
		return false
	}

	i.coff += n
	if i.coff > i.nchunk {
		input_refill(i, i.base + i.coff)
		return false
	} else if i.coff == i.nchunk {
		input_refill(i, i.base + i.coff)
	}
	return true
}

input_pos :: proc(i: ^Input) -> int {
	return i.base + i.coff
}

@(test)
test_input :: proc(t: ^testing.T) {
	using testing
	r := strings.Reader{}
	ok: bool

	strings.reader_init(&r, "foo bar baz")
	i := new_input(r)

	b, _ := input_peek(&i)
	msg := fmt.sbprintf(&strings.Builder{}, "incorrect peek got %c", b)
	expect(t, b == 'f', msg)

	input_advance(&i, 1)
	b, _ = input_peek(&i)
	msg = fmt.sbprintf(&strings.Builder{}, "incorrect peek got %c", b)
	expect(t, b == 'o', msg)

	input_advance(&i, 1)
	b, _ = input_peek(&i)
	msg = fmt.sbprintf(&strings.Builder{}, "incorrect peek got %c", b)
	expect(t, b == 'o', msg)

	slice: []byte = {0, 0, 0}
	strings.reader_read_at(&i.r, slice, 4)
	msg = fmt.sbprintf(&strings.Builder{}, "incorrect slice, got %s", string(slice))
	expect(t, string(slice) == "bar", msg)

	success := input_advance(&i, 9)
	expect(t, success, "incorrect: couldn't advance by 9")

	b, ok = input_peek(&i)
	msg = fmt.sbprintf(
		&strings.Builder{},
		"peek past end of buffer should return false, got %c",
		b,
	)
	expect(t, !ok, msg)

}
