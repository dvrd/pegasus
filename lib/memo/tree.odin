// lazylog provides an interval tree backed by an AVL tree. In addition,
// the interval tree supports shifting intervals in amortized constant time
// using lazy shifts.
package memo

import "core:testing"
import "core:mem/virtual"
import "core:fmt"

// ShiftThreshold is the number of shifts to accumulate before applying all
// shifts.
ShiftThreshold :: -1

// A Key stores the start position of an interval, and a unique ID if you would
// like to store multiple intervals starting from the same position. The key is
// used for uniquely identifying a particular interval when searching or
// removing from the tree.
Key :: struct {
	pos: int,
	id:  int,
}

// compare orders keys by pos and then id.
key_compare :: proc(k, other: Key) -> int {
	if k.pos < other.pos {
		return -1
	} else if k.pos > other.pos {
		return 1
	} else if k.id < other.id {
		return -1
	} else if k.id > other.id {
		return 1
	}
	return 0
}

// A Shift of intervals in the tree. The shift starts at idx and moves
// intervals after idx by amt. Shifts are lazily applied in the tree to avoid
// linear time costs.
Shift :: struct {
	idx:    int,
	amt:    int,
	tstamp: u64,
}

Tree :: struct {
	root:   ^Node,
	shifts: [dynamic]Shift, // list of non-applied shifts
	tstamp: u64, // most recent timestamp
}

// Adds the given interval to the tree. An id should also be given to the
// interval to uniquely identify it if any other intervals begin at the same
// location.
tree_add :: proc(t: ^Tree, id, low, high: int, value: Entry) -> ^LazyInterval {
	loc: ^LazyInterval
	interval := new(Interval)
	interval.low = low
	interval.high = high
	interval.value = value
	t.root, loc = node_add(
		t.root,
		t,
		Key{low, id},
		interval,
	)
	return loc
}

// Search for the interval starting at pos with the given id. Returns nil if no
// such interval exists.
tree_find_largest :: proc(t: ^Tree, id, pos: int) -> ^Entry {
	n := node_search(t.root, Key{pos, id})
	if n != nil {
		if len(n.interval.ins) == 0 {
			return nil
		}

		max := 0
		i := 0
		for inter in n.interval.ins[1:] {
			if interval_length(inter) > interval_length(n.interval.ins[max]) {
				max = i + 1
			}
		}

		return &n.interval.ins[max].value
	}
	return nil
}

tree_remove_and_shift :: proc(t: ^Tree, low, high, amt: int) {
	t.root = node_remove_overlaps(t.root, low, high)
	if amt != 0 {
		tree_shift(t, low, amt)
	}
}

tree_all_values :: proc(t: ^Tree) -> []^Entry {
	vals := make([dynamic]^Entry)
	node_allvals(t.root, &vals)
	return vals[:]
}

// Shift all intervals in the tree after idx by amt. The shift idx should not
// lie inside an interval. This could conceivably be implemented, but is not
// currently. If a negative shift is performed, ensure that there is space for
// all intervals to be shifted left without overlapping with another interval.
tree_shift :: proc(t: ^Tree, idx, amt: int) {
	if amt == 0 {
		return
	}

	t.tstamp += 1
	append(&t.shifts, Shift{idx, amt, t.tstamp})
	if ShiftThreshold != -1 && len(t.shifts) >= ShiftThreshold {
		node_apply_all_shifts(t.root)
	}
}

tree_apply_all_shifts :: proc(t: ^Tree) {
	node_apply_all_shifts(t.root)
	t.shifts = nil
}

// Size returns the total number of intervals stored in the tree.
tree_size :: proc(t: ^Tree) -> int {
	return node_size(t.root)
}


// Returns max number
max :: proc(a, b: int) -> int {
	if a > b {
		return a
	}
	return b
}

@(test)
test_tree_add_and_find :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Use new_table to create a properly initialized tree
	tbl := new_table(0)
	tree := tbl.interval_map

	// Add entries at different positions
	tree_add(tree, 1, 0, 10, Entry{length = 5, examined = 10, count = 1})
	tree_add(tree, 2, 5, 13, Entry{length = 3, examined = 8, count = 1})

	// Verify tree size
	testing.expect(t, tree_size(tree) == 2, fmt.tprintf("expected tree size 2, got %d", tree_size(tree)))

	// Find entry at position 0 with id 1
	found := tree_find_largest(tree, 1, 0)
	testing.expect(t, found != nil, "should find entry at (id=1, pos=0)")
	testing.expect(t, found.length == 5, fmt.tprintf("expected length 5, got %d", found.length))

	// Find entry at position 5 with id 2
	found2 := tree_find_largest(tree, 2, 5)
	testing.expect(t, found2 != nil, "should find entry at (id=2, pos=5)")
	testing.expect(t, found2.length == 3, fmt.tprintf("expected length 3, got %d", found2.length))

	// Miss: wrong id
	miss := tree_find_largest(tree, 99, 0)
	testing.expect(t, miss == nil, "should not find entry with non-existent id")

	// Miss: wrong position
	miss2 := tree_find_largest(tree, 1, 100)
	testing.expect(t, miss2 == nil, "should not find entry at non-existent position")
}

@(test)
test_tree_remove_and_shift :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tbl := new_table(0)
	tree := tbl.interval_map

	tree_add(tree, 1, 0, 10, Entry{length = 5})
	tree_add(tree, 2, 20, 28, Entry{length = 3})
	tree_add(tree, 3, 40, 55, Entry{length = 7})

	// Remove overlapping with [0, 10) — should remove entry at pos 0
	tree_remove_and_shift(tree, 0, 10, 0)
	removed := tree_find_largest(tree, 1, 0)
	testing.expect(t, removed == nil, "entry at pos 0 should be removed after overlap removal")

	// Entry at pos 20 should still exist
	still_there := tree_find_largest(tree, 2, 20)
	testing.expect(t, still_there != nil, "entry at pos 20 should still exist")
}

@(test)
test_tree_all_values :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tbl := new_table(0)
	tree := tbl.interval_map

	tree_add(tree, 1, 0, 10, Entry{length = 5})
	tree_add(tree, 2, 20, 28, Entry{length = 3})

	vals := tree_all_values(tree)
	testing.expect(t, len(vals) == 2, fmt.tprintf("expected 2 values, got %d", len(vals)))
}

@(test)
test_tree_avl_balance :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tbl := new_table(0)
	tree := tbl.interval_map

	// Insert in sorted order (worst case for unbalanced BST)
	for i := 0; i < 20; i += 1 {
		tree_add(tree, i, i * 10, i * 10 + 5, Entry{length = i})
	}

	// Verify tree size
	sz := tree_size(tree)
	testing.expect(t, sz == 20, fmt.tprintf("expected tree size 20, got %d", sz))

	// For an AVL tree with 20 nodes, height should be at most ceil(1.44 * log2(21)) ≈ 7
	h := node_get_height(tree.root)
	testing.expect(t, h <= 7, fmt.tprintf("AVL tree height %d exceeds expected max 7 for 20 nodes", h))

	// Verify all entries are findable
	for i := 0; i < 20; i += 1 {
		found := tree_find_largest(tree, i, i * 10)
		testing.expect(t, found != nil, fmt.tprintf("should find entry at id=%d, pos=%d", i, i * 10))
	}
}
