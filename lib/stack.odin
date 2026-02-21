package pegasus

import "base:runtime"
import "core:slice"
import "core:testing"
import "core:mem/virtual"
import "core:fmt"
import "memo"

Stack :: struct {
	entries:  [dynamic]StackEntry,
	capt:     [dynamic]^memo.Capture,
	_pop_buf: StackEntry, // scratch space so stack_pop can return a stable pointer
}

stack_add_capt :: proc(s: ^Stack, capt: ..^memo.Capture) {
	if len(s.entries) == 0 {
		append(&s.capt, ..capt)
	} else {
		stack_entry_add_capt(&s.entries[len(s.entries) - 1], capt)
	}
}

stack_prop_capt :: proc(s: ^Stack) {
	if len(s.entries) == 0 {
		return
	}

	top := s.entries[len(s.entries) - 1]
	if top.capt != nil && len(top.capt) > 0 {
		if len(s.entries) == 1 {
			append(&s.capt, ..top.capt[:])
		} else {
			stack_entry_add_capt(&s.entries[len(s.entries) - 2], top.capt[:])
		}
	}
}

StackKind :: enum {
	Ret,
	Btrack,
	Memo,
	MemoTree,
	Capt,
	Check,
}

StackEntry :: struct {
	stype:    StackKind,
	// we could use a union to avoid the space cost but I have found this
	// doesn't impact performance and the space cost itself is quite small
	// because the stack is usually small.
	ret:      StackRet, // stackRet is reused for stCheck
	btrack:   StackBacktrack,
	memoized: StackMemo, // stackMemo is reused for stCapt
	capt:     [dynamic]^memo.Capture,
}

stack_entry_add_capt :: proc(se: ^StackEntry, capt: []^memo.Capture) {
	if len(capt) == 0 {
		return
	}
	if se.capt == nil {
		se.capt = make([dynamic]^memo.Capture, 0, len(capt))
	}
	append(&se.capt, ..capt[:])
}

StackRet :: int

StackBacktrack :: struct {
	ip:  int,
	off: int,
}

StackMemo :: struct {
	id:    i16,
	pos:   int,
	count: int,
}

stack_new :: proc() -> (s: ^Stack) {
	s = new(Stack)
	s.entries = make([dynamic]StackEntry, 0, 4)
	s.capt = make([dynamic]^memo.Capture, 0)
	return
}

stack_reset :: proc(s: ^Stack) {
	s.capt = nil
	// Free the old entries backing array before reallocating.
	// Under arena allocation this is a no-op, but it's correct code regardless.
	delete(s.entries)
	s.entries = make([dynamic]StackEntry, 0, 4)
}

stack_push :: proc(s: ^Stack, ent: StackEntry) {
	append(&s.entries, ent)
}

// propagate marks whether captures should be propagated up the stack.
stack_pop :: proc(s: ^Stack, propagate: bool) -> ^StackEntry {
	if len(s.entries) == 0 {
		return nil
	}

	// Copy the top entry before shrinking so the caller gets a stable value.
	// We shrink the dynamic array in-place (no allocation) instead of
	// creating a new slice via slice.to_dynamic which leaked under arena.
	top_idx := len(s.entries) - 1
	s._pop_buf = s.entries[top_idx]
	ret := &s._pop_buf
	(^runtime.Raw_Dynamic_Array)(&s.entries).len = top_idx
	// For non-capture entries, propagate the captures upward.
	// For capture entries, we create a new node with the corresponding
	// children, and this is manually handled by the caller.
	if propagate && ret.capt != nil {
		stack_add_capt(s, ..ret.capt[:])
	}
	return ret
}

stack_peek :: proc(s: ^Stack) -> ^StackEntry {
	return stack_peekn(s, 0)
}

stack_peekn :: proc(s: ^Stack, n: int) -> ^StackEntry {
	if len(s.entries) <= n {
		return nil
	}
	return &s.entries[len(s.entries) - n - 1]
}

stack_pushRet :: proc(s: ^Stack, r: StackRet) {
	stack_push(s, StackEntry{stype = .Ret, ret = r})
}

stack_pushBacktrack :: proc(s: ^Stack, b: StackBacktrack) {
	stack_push(s, StackEntry{stype = .Btrack, btrack = b})
}

stack_pushMemo :: proc(s: ^Stack, m: StackMemo) {
	stack_push(s, StackEntry{stype = .Memo, memoized = m})
}

stack_pushMemoTree :: proc(s: ^Stack, m: StackMemo) {
	stack_push(s, StackEntry{stype = .MemoTree, memoized = m})
}

stack_pushCapt :: proc(s: ^Stack, m: StackMemo) {
	stack_push(s, StackEntry{stype = .Capt, memoized = m})
}

stack_pushCheck :: proc(s: ^Stack, m: StackMemo) {
	stack_push(s, StackEntry{stype = .Check, memoized = m})
}

// -- Test helpers --

make_test_capture :: proc(id: int, off: int, length: int) -> ^memo.Capture {
	return memo.capture_new(id, off, length, nil)
}

// -- Tests --

@(test)
test_stack_add_capt_empty_stack :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	s := stack_new()
	c1 := make_test_capture(1, 0, 5)
	c2 := make_test_capture(2, 5, 3)

	// With no entries, captures should go to s.capt
	stack_add_capt(s, c1, c2)
	testing.expect(t, len(s.capt) == 2, fmt.tprintf("expected 2 captures on stack, got %d", len(s.capt)))
	testing.expect(t, s.capt[0].id == 1, fmt.tprintf("expected id=1, got %d", s.capt[0].id))
	testing.expect(t, s.capt[1].id == 2, fmt.tprintf("expected id=2, got %d", s.capt[1].id))
}

@(test)
test_stack_add_capt_with_entries :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	s := stack_new()
	stack_pushRet(s, 42)

	c1 := make_test_capture(1, 0, 5)
	stack_add_capt(s, c1)

	// Capture should be on the top entry, not on s.capt
	testing.expect(t, len(s.capt) == 0, "stack capt should be empty when entries exist")
	top := stack_peek(s)
	testing.expect(t, len(top.capt) == 1, fmt.tprintf("expected 1 capture on top entry, got %d", len(top.capt)))
	testing.expect(t, top.capt[0].id == 1, fmt.tprintf("expected capture id=1, got %d", top.capt[0].id))
}

@(test)
test_stack_prop_capt_single_entry :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	s := stack_new()
	stack_pushRet(s, 10)

	// Add capture to top entry directly
	c1 := make_test_capture(1, 0, 3)
	stack_add_capt(s, c1)

	// With only 1 entry, prop_capt should move captures to s.capt
	stack_prop_capt(s)
	testing.expect(t, len(s.capt) == 1, fmt.tprintf("expected 1 capture on stack after prop, got %d", len(s.capt)))
	testing.expect(t, s.capt[0].id == 1, fmt.tprintf("expected id=1, got %d", s.capt[0].id))
}

@(test)
test_stack_prop_capt_multiple_entries :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	s := stack_new()
	stack_pushRet(s, 10) // bottom entry
	stack_pushRet(s, 20) // top entry

	// Add captures to top entry
	c1 := make_test_capture(1, 0, 3)
	c2 := make_test_capture(2, 3, 4)
	stack_add_capt(s, c1, c2)

	// prop_capt should move top's captures to second-from-top
	stack_prop_capt(s)

	bottom := stack_peekn(s, 1)
	testing.expect(t, bottom != nil, "bottom entry should exist")
	testing.expect(t, len(bottom.capt) == 2, fmt.tprintf("expected 2 captures on bottom, got %d", len(bottom.capt)))
	testing.expect(t, bottom.capt[0].id == 1, fmt.tprintf("expected id=1, got %d", bottom.capt[0].id))
	testing.expect(t, bottom.capt[1].id == 2, fmt.tprintf("expected id=2, got %d", bottom.capt[1].id))

	// s.capt should remain empty
	testing.expect(t, len(s.capt) == 0, "stack capt should be empty when propagated to entry")
}

@(test)
test_stack_prop_capt_empty_stack :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	s := stack_new()

	// Should be a no-op, no crash
	stack_prop_capt(s)
	testing.expect(t, len(s.capt) == 0, "prop_capt on empty stack should be no-op")
}

@(test)
test_stack_prop_capt_no_captures :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	s := stack_new()
	stack_pushRet(s, 10)
	stack_pushRet(s, 20)

	// Top has no captures — prop_capt should be a no-op
	stack_prop_capt(s)
	bottom := stack_peekn(s, 1)
	testing.expect(t, len(bottom.capt) == 0, "bottom should have no captures when top had none")
	testing.expect(t, len(s.capt) == 0, "stack capt should remain empty")
}

@(test)
test_stack_pop_propagate_true :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	s := stack_new()
	stack_pushRet(s, 10) // bottom
	stack_pushRet(s, 20) // top

	// Add capture to top entry
	c1 := make_test_capture(1, 0, 5)
	stack_add_capt(s, c1)

	// Pop with propagate=true — capture should bubble to bottom entry
	popped := stack_pop(s, true)
	testing.expect(t, popped != nil, "pop should return entry")
	testing.expect(t, popped.ret == 20, fmt.tprintf("expected ret=20, got %d", popped.ret))

	bottom := stack_peek(s)
	testing.expect(t, bottom != nil, "bottom entry should exist")
	testing.expect(t, len(bottom.capt) == 1, fmt.tprintf("expected 1 capture on bottom after propagate, got %d", len(bottom.capt)))
	testing.expect(t, bottom.capt[0].id == 1, fmt.tprintf("expected id=1, got %d", bottom.capt[0].id))
}

@(test)
test_stack_pop_propagate_false :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	s := stack_new()
	stack_pushRet(s, 10) // bottom
	stack_pushRet(s, 20) // top

	// Add capture to top entry
	c1 := make_test_capture(1, 0, 5)
	stack_add_capt(s, c1)

	// Pop with propagate=false — capture should NOT bubble
	popped := stack_pop(s, false)
	testing.expect(t, popped != nil, "pop should return entry")

	bottom := stack_peek(s)
	testing.expect(t, bottom != nil, "bottom entry should exist")
	testing.expect(t, len(bottom.capt) == 0, "bottom should have no captures when propagate=false")
	testing.expect(t, len(s.capt) == 0, "stack capt should be empty when propagate=false")
}

@(test)
test_stack_pop_propagate_to_stack_capt :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	s := stack_new()
	stack_pushRet(s, 10) // only entry

	c1 := make_test_capture(1, 0, 5)
	stack_add_capt(s, c1)

	// Pop the only entry with propagate=true — capture goes to s.capt
	popped := stack_pop(s, true)
	testing.expect(t, popped != nil, "pop should return entry")
	testing.expect(t, len(s.entries) == 0, "stack should be empty after pop")
	testing.expect(t, len(s.capt) == 1, fmt.tprintf("expected 1 capture on stack capt, got %d", len(s.capt)))
	testing.expect(t, s.capt[0].id == 1, fmt.tprintf("expected id=1, got %d", s.capt[0].id))
}

@(test)
test_stack_peekn :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	s := stack_new()
	stack_pushRet(s, 100)
	stack_pushRet(s, 200)
	stack_pushRet(s, 300)

	// peekn(0) = top
	p0 := stack_peekn(s, 0)
	testing.expect(t, p0 != nil && p0.ret == 300, fmt.tprintf("peekn(0) expected 300, got %v", p0 != nil ? p0.ret : -1))

	// peekn(1) = second from top
	p1 := stack_peekn(s, 1)
	testing.expect(t, p1 != nil && p1.ret == 200, fmt.tprintf("peekn(1) expected 200, got %v", p1 != nil ? p1.ret : -1))

	// peekn(2) = bottom
	p2 := stack_peekn(s, 2)
	testing.expect(t, p2 != nil && p2.ret == 100, fmt.tprintf("peekn(2) expected 100, got %v", p2 != nil ? p2.ret : -1))

	// peekn(3) = out of bounds
	p3 := stack_peekn(s, 3)
	testing.expect(t, p3 == nil, "peekn(3) should return nil for 3-element stack")
}

@(test)
test_stack_reset :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	s := stack_new()
	stack_pushRet(s, 10)
	stack_pushRet(s, 20)

	c1 := make_test_capture(1, 0, 5)
	stack_add_capt(s, c1) // goes to top entry

	// Also add directly to s.capt by popping with propagate, then adding more
	stack_pop(s, true) // propagates c1 to bottom entry
	stack_pop(s, true) // propagates c1 to s.capt (stack now empty)
	testing.expect(t, len(s.capt) > 0, "s.capt should have captures before reset")

	stack_reset(s)
	testing.expect(t, len(s.entries) == 0, "entries should be empty after reset")
	testing.expect(t, s.capt == nil, "capt should be nil after reset")

	// Stack should be usable after reset
	stack_pushRet(s, 99)
	p := stack_peek(s)
	testing.expect(t, p != nil && p.ret == 99, "stack should work after reset")
}

@(test)
test_stack_entry_add_capt_initializes :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	se := StackEntry{stype = .Ret, ret = 1}
	c1 := make_test_capture(1, 0, 3)
	c2 := make_test_capture(2, 3, 2)

	// First call initializes capt from slice
	stack_entry_add_capt(&se, {c1, c2})
	testing.expect(t, len(se.capt) == 2, fmt.tprintf("expected 2 captures, got %d", len(se.capt)))

	// Second call appends
	c3 := make_test_capture(3, 5, 1)
	stack_entry_add_capt(&se, {c3})
	testing.expect(t, len(se.capt) == 3, fmt.tprintf("expected 3 captures after append, got %d", len(se.capt)))
	testing.expect(t, se.capt[2].id == 3, fmt.tprintf("expected id=3, got %d", se.capt[2].id))
}

@(test)
test_stack_entry_add_capt_empty_slice :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	se := StackEntry{stype = .Ret, ret = 1}

	// Adding empty slice should be a no-op
	stack_entry_add_capt(&se, {})
	testing.expect(t, len(se.capt) == 0, "adding empty slice should not create capt")
}

@(test)
test_stack_push_pop :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	s := stack_new()

	// Push three entries
	stack_pushRet(s, 100)
	stack_pushRet(s, 200)
	stack_pushRet(s, 300)

	// Pop in LIFO order
	e3 := stack_pop(s, true)
	testing.expect(t, e3 != nil, "pop should return entry")
	testing.expect(t, e3.stype == .Ret, "expected Ret entry")
	testing.expect(t, e3.ret == 300, fmt.tprintf("expected ret=300, got %d", e3.ret))

	e2 := stack_pop(s, true)
	testing.expect(t, e2 != nil, "pop should return entry")
	testing.expect(t, e2.ret == 200, fmt.tprintf("expected ret=200, got %d", e2.ret))

	e1 := stack_pop(s, true)
	testing.expect(t, e1 != nil, "pop should return entry")
	testing.expect(t, e1.ret == 100, fmt.tprintf("expected ret=100, got %d", e1.ret))

	// Pop from empty stack
	empty := stack_pop(s, true)
	testing.expect(t, empty == nil, "pop from empty stack should return nil")
}

@(test)
test_stack_peek :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	s := stack_new()

	// Peek empty stack
	p := stack_peek(s)
	testing.expect(t, p == nil, "peek on empty stack should return nil")

	// Push and peek
	stack_pushRet(s, 42)
	p = stack_peek(s)
	testing.expect(t, p != nil, "peek should return entry")
	testing.expect(t, p.ret == 42, fmt.tprintf("expected peek ret=42, got %d", p.ret))

	// Peek doesn't remove
	p2 := stack_peek(s)
	testing.expect(t, p2 != nil, "second peek should still return entry")
	testing.expect(t, p2.ret == 42, "peek should not remove the entry")

	// Push another, peek returns new top
	stack_pushBacktrack(s, StackBacktrack{ip = 10, off = 20})
	p3 := stack_peek(s)
	testing.expect(t, p3 != nil, "peek should return new top")
	testing.expect(t, p3.stype == .Btrack, "expected Btrack entry on top")
}

@(test)
test_stack_entry_types :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	s := stack_new()

	// Push each entry type
	stack_pushRet(s, 1)
	stack_pushBacktrack(s, StackBacktrack{ip = 10, off = 20})
	stack_pushMemo(s, StackMemo{id = 5, pos = 30, count = 1})
	stack_pushCapt(s, StackMemo{id = 7, pos = 40, count = 0})
	stack_pushCheck(s, StackMemo{id = 9, pos = 50, count = 2})

	// Pop and verify types in reverse order
	e5 := stack_pop(s, false)
	testing.expect(t, e5.stype == .Check, fmt.tprintf("expected Check, got %v", e5.stype))

	e4 := stack_pop(s, false)
	testing.expect(t, e4.stype == .Capt, fmt.tprintf("expected Capt, got %v", e4.stype))

	e3 := stack_pop(s, false)
	testing.expect(t, e3.stype == .Memo, fmt.tprintf("expected Memo, got %v", e3.stype))
	testing.expect(t, e3.memoized.id == 5, fmt.tprintf("expected memo id=5, got %d", e3.memoized.id))

	e2 := stack_pop(s, false)
	testing.expect(t, e2.stype == .Btrack, fmt.tprintf("expected Btrack, got %v", e2.stype))
	testing.expect(t, e2.btrack.ip == 10, fmt.tprintf("expected btrack ip=10, got %d", e2.btrack.ip))
	testing.expect(t, e2.btrack.off == 20, fmt.tprintf("expected btrack off=20, got %d", e2.btrack.off))

	e1 := stack_pop(s, false)
	testing.expect(t, e1.stype == .Ret, fmt.tprintf("expected Ret, got %v", e1.stype))
}
