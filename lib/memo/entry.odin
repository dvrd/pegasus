package memo

import "core:fmt"
import "core:mem/virtual"
import "core:testing"

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

// --- Tests ---

@(test)
test_entry_set_pos :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Create a tree and add a node so we have a valid LazyInterval
	tree := new(Tree)
	iv := new(Interval)
	iv.low = 5
	iv.high = 15
	iv.value = Entry{length = 10, examined = 10, count = 1}
	root, li := node_add(nil, tree, Key{5, 1}, iv)
	tree.root = root

	// Create an entry and set its pos
	e := new(Entry)
	e.length = 10
	e.examined = 10
	e.count = 1

	entry_set_pos(e, li)
	testing.expect(t, e.pos == li, "entry pos should be set to the lazy interval")
	testing.expect(t, e.pos != nil, "entry pos should not be nil after set_pos")
}

@(test)
test_entry_set_pos_propagates_to_captures :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Create tree + node for LazyInterval
	tree := new(Tree)
	iv := new(Interval)
	iv.low = 10
	iv.high = 20
	iv.value = Entry{length = 10, examined = 10, count = 1}
	root, li := node_add(nil, tree, Key{10, 1}, iv)
	tree.root = root

	// Create captures
	c1 := capture_new(1, 12, 3, nil)
	c2 := capture_new(2, 15, 2, nil)
	caps := make([]^Capture, 2)
	caps[0] = c1
	caps[1] = c2

	// Create entry with captures
	e := new(Entry)
	e.length = 10
	e.examined = 10
	e.count = 1
	e.captures = caps

	entry_set_pos(e, li)

	// After set_pos, captures should have their ment set to e
	testing.expect(t, c1.ment == e, "capture 1 ment should point to entry")
	testing.expect(t, c2.ment == e, "capture 2 ment should point to entry")
}

@(test)
test_entry_set_pos_nil_captures :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Create tree + node for LazyInterval
	tree := new(Tree)
	iv := new(Interval)
	iv.low = 0
	iv.high = 5
	iv.value = Entry{length = 5}
	root, li := node_add(nil, tree, Key{0, 1}, iv)
	tree.root = root

	// Entry with nil captures — should not panic
	e := new(Entry)
	e.length = 5
	entry_set_pos(e, li)
	testing.expect(t, e.pos == li, "entry pos should be set even with nil captures")
}

@(test)
test_entry_fields :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Test entry with length=-1 (failed match)
	e := new(Entry)
	e.length = -1
	e.examined = 5
	e.count = 0
	testing.expect(t, e.length == -1, "failed match entry should have length -1")
	testing.expect(t, e.examined == 5, fmt.tprintf("expected examined=5, got %d", e.examined))
	testing.expect(t, e.count == 0, "failed match should have count 0")
	testing.expect(t, e.pos == nil, "unset pos should be nil")
}
