package memo

import "core:sync"
import "core:testing"
import "core:mem/virtual"
import "core:fmt"

// An Edit represents a modification to the subject string where the interval
// [Start, End) is modified to be Len bytes. If Len = 0, this is equivalent
// to deleting the interval, and if Start = End this is an insertion.
Edit :: struct {
	start: int,
	end:   int,
	len:   int,
}

// MAX_ENTRIES caps the number of entries in the memo table to prevent
// unbounded memory growth on large files. When the cap is reached, new
// entries are silently dropped. Parsing remains correct (just slower for
// the portion beyond the cap). A value of 100K entries covers ~200KB of
// typical JavaScript source with a ~300-rule grammar.
MAX_ENTRIES :: 100_000

// Table implements a memoization table using an interval tree (augmented
// to support efficient shifting).
Table :: struct {
	interval_map: ^Tree,
	threshold:    int,
	lock:         sync.Mutex,
	count:        int, // number of entries currently stored
}

new_table :: proc(threshold: int) -> (t: ^Table) {
	t = new(Table)
	t.threshold = threshold
	llt := new(Tree)
	t.interval_map = llt
	return
}

table_get :: proc(t: ^Table, id, pos: int) -> (e: ^Entry) {
	sync.mutex_lock(&t.lock)
	e = tree_find_largest(t.interval_map, id, pos)
	sync.mutex_unlock(&t.lock)
	return
}

table_put :: proc(
	t: ^Table,
	id, start, length, last_examined, count: int,
	captures: []^Capture,
) {
	if last_examined < t.threshold || length == 0 {
		return
	}

	examined := max(last_examined, length)

	e := new(Entry)
	e.length = length
	e.examined = examined
	e.count = count
	e.captures = captures

	sync.mutex_lock(&t.lock)

	// Cap entries to prevent unbounded memory growth on large files
	if t.count >= MAX_ENTRIES {
		sync.mutex_unlock(&t.lock)
		return
	}

	li := tree_add(t.interval_map, id, start, start + examined, e^)
	entry_set_pos(e, li)
	t.count += 1

	sync.mutex_unlock(&t.lock)
}

table_apply_edit :: proc(t: ^Table, e: Edit) {
	low := e.start
	high := e.end
	if low == high {
		high = low + 1
	}
	amt := e.len - (e.end - e.start)

	sync.mutex_lock(&t.lock)
	tree_remove_and_shift(t.interval_map, low, high, amt)
	sync.mutex_unlock(&t.lock)
}


table_all_values :: proc(t: ^Table) -> []^Entry {
	vals := tree_all_values(t.interval_map)
	entries := make([]^Entry, len(vals))
	for v, i in vals {
		entries[i] = v
	}
	return entries
}

@(test)
test_table_put_get :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tbl := new_table(0) // threshold=0 so everything gets memoized

	// Put an entry: id=1, start=0, length=5, last_examined=10, count=1, no captures
	table_put(tbl, 1, 0, 5, 10, 1, nil)

	// Get it back
	e := table_get(tbl, 1, 0)
	testing.expect(t, e != nil, "should find memoized entry at (id=1, pos=0)")
	testing.expect(t, e.length == 5, fmt.tprintf("expected length 5, got %d", e.length))
	testing.expect(t, e.count == 1, fmt.tprintf("expected count 1, got %d", e.count))
	// examined should be max(last_examined, length) = max(10, 5) = 10
	testing.expect(t, e.examined == 10, fmt.tprintf("expected examined 10, got %d", e.examined))
}

@(test)
test_table_miss :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tbl := new_table(0)

	// Get nonexistent key
	e := table_get(tbl, 99, 0)
	testing.expect(t, e == nil, "should return nil for nonexistent key")

	// Put something, then query wrong id
	table_put(tbl, 1, 0, 5, 10, 1, nil)
	e2 := table_get(tbl, 2, 0)
	testing.expect(t, e2 == nil, "should return nil for wrong id")

	// Query wrong position
	e3 := table_get(tbl, 1, 100)
	testing.expect(t, e3 == nil, "should return nil for wrong position")
}

@(test)
test_table_apply_edit :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tbl := new_table(0)

	// Put entries at different positions
	table_put(tbl, 1, 0, 5, 10, 1, nil)
	table_put(tbl, 2, 20, 3, 8, 1, nil)

	// Apply an edit that overlaps with the first entry: delete [0, 5)
	table_apply_edit(tbl, Edit{start = 0, end = 5, len = 0})

	// First entry should be removed (overlapping with edit)
	e1 := table_get(tbl, 1, 0)
	testing.expect(t, e1 == nil, "entry at pos 0 should be removed after overlapping edit")

	// Second entry should still exist (may have shifted)
	vals := table_all_values(tbl)
	testing.expect(t, len(vals) >= 1, "at least one entry should remain after edit")
}
