package memo

import "core:strings"
import "core:testing"
import "core:mem/virtual"
import "core:fmt"

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
	defer strings.builder_destroy(&buf)
	strings.write_int(&buf, int(c.id))
	strings.write_string(&buf, ", ")
	for child, i in c.children {
		strings.write_string(&buf, capture_to_string(child))
		if i != len(child.children) - 1 {
			strings.write_string(&buf, ", ")
		}
	}
	return strings.clone(strings.to_string(buf))
}

@(test)
test_capture_new :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	c := capture_new(42, 10, 5, nil)
	testing.expect(t, c.id == 42, fmt.tprintf("expected id 42, got %d", c.id))
	testing.expect(t, c.typ == .Node, "expected type Node")
	testing.expect(t, capture_start(c) == 10, fmt.tprintf("expected start 10, got %d", capture_start(c)))
	testing.expect(t, capture_end(c) == 15, fmt.tprintf("expected end 15, got %d", capture_end(c)))
	testing.expect(t, c.length == 5, fmt.tprintf("expected length 5, got %d", c.length))

	// Test dummy capture
	d := capture_new_dummy(0, 10, nil)
	testing.expect(t, d.id == 0, "dummy should have id 0")
	testing.expect(t, d.typ == .Dummy, "expected type Dummy")
}

@(test)
test_capture_children :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Create child captures
	c1 := capture_new(1, 0, 3, nil)
	c2 := capture_new(2, 3, 4, nil)
	c3 := capture_new(3, 7, 2, nil)

	// Create parent with children
	children := make([]^Capture, 3)
	children[0] = c1
	children[1] = c2
	children[2] = c3
	parent := capture_new(0, 0, 9, children)

	// Verify num_children
	n := capture_num_children(parent)
	testing.expect(t, n == 3, fmt.tprintf("expected 3 children, got %d", n))

	// Verify capture_child access
	ch0 := capture_child(parent, 0)
	testing.expect(t, ch0 != nil, "child 0 should not be nil")
	testing.expect(t, ch0.id == 1, fmt.tprintf("expected child 0 id=1, got %d", ch0.id))

	ch1 := capture_child(parent, 1)
	testing.expect(t, ch1 != nil, "child 1 should not be nil")
	testing.expect(t, ch1.id == 2, fmt.tprintf("expected child 1 id=2, got %d", ch1.id))

	ch2 := capture_child(parent, 2)
	testing.expect(t, ch2 != nil, "child 2 should not be nil")
	testing.expect(t, ch2.id == 3, fmt.tprintf("expected child 2 id=3, got %d", ch2.id))

	// Iterate with child_iterator and count
	count := 0
	iter, state := capture_child_iterator(parent, 0)
	for _ in iter(state) {
		count += 1
	}
	testing.expect(t, count == 3, fmt.tprintf("iterator should yield 3 children, got %d", count))
}

@(test)
test_capture_to_string :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Leaf capture
	c := capture_new(5, 0, 3, nil)
	s := capture_to_string(c)
	testing.expect(t, len(s) > 0, "capture_to_string should produce non-empty string")
	// The string should contain the id "5"
	has_id := false
	for ch in s {
		if ch == '5' {
			has_id = true
			break
		}
	}
	testing.expect(t, has_id, fmt.tprintf("capture string should contain id '5', got '%s'", s))
}
