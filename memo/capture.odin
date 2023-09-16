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

IteratorInnerContext :: struct {
	i:     ^int,
	c:     ^Capture,
	subit: proc() -> ^Capture,
	ret:   proc() -> ^Capture,
}

capture_child_iterator :: proc(c: ^Capture, start: int) -> proc() -> ^Capture {
	i := 0
	subit, ret: proc() -> ^Capture
	context_map: IteratorInnerContext = {&i, c, subit, ret}
	context.user_ptr = &context_map
	ret = proc() -> ^Capture {
		context_map := cast(^IteratorInnerContext)context.user_ptr
		i := context_map.i
		c := context_map.c
		subit := context_map.subit
		ret := context_map.ret
		if i^ >= len(c.children) {
			return nil
		}
		ch := c.children[i^]
		if ch.typ == .Dummy && subit == nil {
			subit = capture_child_iterator(ch, ch.off)
		}
		if subit != nil {
			ch = subit()
		} else {
			i^ += 1
		}
		if ch == nil {
			subit = nil
			i^ += 1
			return ret()
		}
		return ch
	}
	return ret
}

capture_child :: proc(c: ^Capture, n: int) -> ^Capture {
	it := capture_child_iterator(c, 0)
	i := 0
	for ch := it(); ch != nil; ch = it() {
		if i == n {
			return ch
		}
		i += 1
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
