package pegasus

import "core:fmt"
import "core:slice"
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
	// need to complete remake the slice so that the underlying captures can be
	// released to the garbage collector if the user has no references to them
	// (unused stack entries shouldn't keep references to those captures).
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
