// lazylog provides an interval tree backed by an AVL tree. In addition,
// the interval tree supports shifting intervals in amortized constant time
// using lazy shifts.
package memo

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
	t.root, loc = node_add(
		t.root,
		t,
		Key{low, id},
		&Interval{low, high, Entry{}},
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
	vals: []^Entry
	return node_allvals(t.root, vals)
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
