package memo

import "core:sync"

// An Edit represents a modification to the subject string where the interval
// [Start, End) is modified to be Len bytes. If Len = 0, this is equivalent
// to deleting the interval, and if Start = End this is an insertion.
Edit :: struct {
	start: int,
	end:   int,
	len:   int,
}

// Table implements a memoization table using an interval tree (augmented
// to support efficient shifting).
Table :: struct {
	interval_map: ^Tree,
	threshold:    int,
	lock:         sync.Mutex,
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
	li := tree_add(t.interval_map, id, start, start + examined, e^)
	entry_set_pos(e, li)
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
