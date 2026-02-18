package memo

import "core:fmt"
import "core:testing"
import "core:mem/virtual"

Interval :: struct {
	low:   int,
	high:  int,
	value: Entry,
}

interval_length :: proc(i: ^Interval) -> int {
	return i.high - i.low
}

// returns true if i1 overlaps with the interval [low:high)
interval_overlaps :: proc(i1: Interval, low, high: int) -> bool {
	return i1.low <= high && i1.high >= low
}

LazyInterval :: struct {
	ins: [dynamic]^Interval,
	n:   ^Node,
}

lazy_interval_pos :: proc(i: ^LazyInterval) -> int {
	node_apply_shifts(i.n)
	return i.n.key.pos
}

lazy_interval_high :: proc(i: ^LazyInterval) -> int {
	high := 0
	for interval in i.ins {
		if interval.high > high {
			high = interval.high
		}
	}
	return high
}

lazy_interval_shift :: proc(i: ^LazyInterval, amt: int) {
	for j in i.ins {
		j.low += amt
		j.high += amt
	}
}

@(test)
test_interval_overlaps :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Overlapping intervals: [0, 10) and [5, 15)
	i1 := Interval{low = 0, high = 10}
	testing.expect(t, interval_overlaps(i1, 5, 15), "intervals [0,10) and [5,15) should overlap")

	// Adjacent intervals: [0, 5) and [5, 10) — overlaps returns true because low <= high
	testing.expect(t, interval_overlaps(i1, 10, 15), "intervals [0,10) and [10,15) should overlap (adjacent)")

	// Disjoint intervals: [0, 5) and [20, 30)
	i2 := Interval{low = 0, high = 5}
	testing.expect(t, !interval_overlaps(i2, 20, 30), "intervals [0,5) and [20,30) should not overlap")

	// Contained interval: [0, 20) contains [5, 10)
	i3 := Interval{low = 0, high = 20}
	testing.expect(t, interval_overlaps(i3, 5, 10), "interval [0,20) should overlap with [5,10)")

	// Same interval
	testing.expect(t, interval_overlaps(i1, 0, 10), "interval should overlap with itself")
}

@(test)
test_interval_length :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Normal interval
	i1 := Interval{low = 3, high = 10}
	testing.expect(t, interval_length(&i1) == 7, fmt.tprintf("expected length 7, got %d", interval_length(&i1)))

	// Zero-length interval
	i2 := Interval{low = 5, high = 5}
	testing.expect(t, interval_length(&i2) == 0, fmt.tprintf("expected length 0, got %d", interval_length(&i2)))

	// Single-unit interval
	i3 := Interval{low = 0, high = 1}
	testing.expect(t, interval_length(&i3) == 1, fmt.tprintf("expected length 1, got %d", interval_length(&i3)))
}

@(test)
test_lazy_interval_shift :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Create intervals and a lazy interval
	i1 := new(Interval)
	i1.low = 5
	i1.high = 10

	i2 := new(Interval)
	i2.low = 15
	i2.high = 20

	ins := make([dynamic]^Interval)
	append(&ins, i1, i2)

	// We need a node for the lazy interval; create a minimal tree
	tree := new(Tree)
	n := new(Node)
	n.key = Key{5, 0}
	n.height = 1
	n.tree = tree

	li := new(LazyInterval)
	li.ins = ins
	li.n = n

	// Shift by +3
	lazy_interval_shift(li, 3)
	testing.expect(t, i1.low == 8, fmt.tprintf("expected i1.low=8 after shift, got %d", i1.low))
	testing.expect(t, i1.high == 13, fmt.tprintf("expected i1.high=13 after shift, got %d", i1.high))
	testing.expect(t, i2.low == 18, fmt.tprintf("expected i2.low=18 after shift, got %d", i2.low))
	testing.expect(t, i2.high == 23, fmt.tprintf("expected i2.high=23 after shift, got %d", i2.high))

	// Cumulative shift by -2
	lazy_interval_shift(li, -2)
	testing.expect(t, i1.low == 6, fmt.tprintf("expected i1.low=6 after second shift, got %d", i1.low))
	testing.expect(t, i1.high == 11, fmt.tprintf("expected i1.high=11 after second shift, got %d", i1.high))
}
