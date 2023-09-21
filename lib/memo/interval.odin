package memo

import "core:fmt"
import "core:strings"

Interval :: struct {
	low:   int,
	high:  int,
	value: Entry,
}

interval_length :: proc(i: ^Interval) -> int {
	return i.high - i.low
}

interval_to_string :: proc(i: ^Interval) -> string {
	return fmt.sbprintf(&strings.Builder{}, "[%d, %d)", i.low, i.high)
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
