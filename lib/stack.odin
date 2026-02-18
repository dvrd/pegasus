package pegasus

import "core:slice"
import "core:testing"
import "core:mem/virtual"
import "core:fmt"
import "memo"

Stack :: struct {
	entries: [dynamic]StackEntry,
	capt:    [dynamic]^memo.Capture,
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
	if len(se.capt) == 0 {
		se.capt = slice.to_dynamic(capt)
	} else {
		append(&se.capt, ..capt[:])
	}
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

	ret := &s.entries[len(s.entries) - 1]
	s.entries = slice.to_dynamic(s.entries[:len(s.entries) - 1])
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
