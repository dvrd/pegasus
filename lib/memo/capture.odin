package memo

import "core:strings"

CaptureKind :: enum {
	Node,
	Dummy,
}

Capture :: struct {
	id:       i32,
	typ:      CaptureKind,
	off:      int,
	length:   int,
	ment:     ^Entry,
	children: []^Capture,
}

capture_new :: proc(
	id, start, length: int,
	children: []^Capture,
) -> (
	c: ^Capture,
) {
	c = new(Capture)
	c.id = i32(id)
	c.typ = .Node
	c.off = start
	c.length = length
	c.children = children
	return
}

capture_new_dummy :: proc(
	start, length: int,
	children: []^Capture,
) -> (
	c: ^Capture,
) {
	c = new(Capture)
	c.id = 0
	c.typ = .Dummy
	c.off = start
	c.length = length
	c.children = children
	return
}

IteratorState :: struct {
	i:     int,
	c:     ^Capture,
	subit: proc(
		state: ^IteratorState,
	) -> (
		ch: ^Capture,
		idx: int,
		keep_going: bool,
	),
	ret:   proc(
		state: ^IteratorState,
	) -> (
		ch: ^Capture,
		idx: int,
		keep_going: bool,
	),
}

capture_child_iterator :: proc(
	c: ^Capture,
	start: int = 0,
) -> (
	proc(state: ^IteratorState) -> (ch: ^Capture, idx: int, keep_going: bool),
	^IteratorState,
) {
	i := start

	subit, ret: proc(
		state: ^IteratorState,
	) -> (
		ch: ^Capture,
		idx: int,
		keep_going: bool,
	)
	state := new(IteratorState)
	state.i = i
	state.c = c
	state.subit = subit
	state.ret = ret

	ret =
	proc(state: ^IteratorState) -> (ch: ^Capture, idx: int, keep_going: bool) {
		idx = state.i
		keep_going = true
		if idx >= len(state.c.children) {
			return nil, idx, false
		}
		ch = state.c.children[idx]
		child_state: ^IteratorState
		if ch.typ == .Dummy && state.subit == nil {
			state.subit, child_state = capture_child_iterator(ch, ch.off)
		}
		if state.subit != nil {
			ch, idx, keep_going = state.subit(child_state)
		} else {
			state.i += 1
		}
		if ch == nil {
			state.subit = nil
			state.i += 1
			ch, idx, keep_going = state.ret(state)
			return
		}
		return ch, idx, keep_going
	}
	return ret, state
}

capture_child :: proc(c: ^Capture, n: int) -> ^Capture {
	it, state := capture_child_iterator(c)
	for ch, i in it(state) {
		if i == n {
			return ch
		}
	}
	return nil
}

capture_num_children :: proc(c: ^Capture) -> int {
	nchild := 0
	for ch in c.children {
		if ch.typ == .Dummy {
			nchild += capture_num_children(ch)
		} else {
			nchild += 1
		}
	}
	return nchild
}

capture_start :: proc(c: ^Capture) -> int {
	if c.ment != nil {
		return lazy_interval_pos(c.ment.pos) + c.off
	}
	return c.off
}

capture_end :: proc(c: ^Capture) -> int {
	return capture_start(c) + c.length
}

capture_setMEnt :: proc(c: ^Capture, e: ^Entry) {
	if c.ment != nil {
		return
	}

	c.ment = e
	c.off = c.off - lazy_interval_pos(e.pos)

	for child in c.children {
		capture_setMEnt(child, e)
	}
}

// String returns a readable string representation of this node, showing the ID
// of this node and its children.
capture_to_string :: proc(c: ^Capture) -> string {
	buf := strings.builder_make()
	strings.write_int(&buf, int(c.id))
	strings.write_string(&buf, ", ")
	for child, i in c.children {
		strings.write_string(&buf, capture_to_string(child))
		if i != len(child.children) - 1 {
			strings.write_string(&buf, ", ")
		}
	}
	return strings.to_string(buf)
}
