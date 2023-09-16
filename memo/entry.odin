package memo

// An Entry represents a memoized parse result. It stores the non-terminal
// memoized, the start position of the parse result, the length, and the number
// of characters examined to make the parse determination. If the length is -1,
// the non-terminal failed to match at this location (but still may have
// examined a non-zero number of characters).
Entry :: struct {
	length:   int,
	examined: int,
	count:    int,
	captures: []^Capture,
	pos:      ^LazyInterval,
}

entry_set_pos :: proc(e: ^Entry, pos: ^LazyInterval) {
	e.pos = pos
	for capture in e.captures {
		capture_setMEnt(capture, e)
	}
}
