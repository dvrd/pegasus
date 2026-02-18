package pegasus

import "charset"
import "core:fmt"
import "core:strings"
import "input"
import "memo"

ParseError :: struct {
	message: string,
	pos:     int,
}

Interval :: struct {
	low:  int,
	high: int,
}

error_to_string :: proc(e: ParseError) -> string {
	return fmt.tprintf("%v: %s", e.pos, e.message)
}

// Exec executes the parsing program this virtual machine was created with. It
// returns whether the parse was a match, the last position in the subject
// string that was matched, and any captures that were created.
exec :: proc(
	vm: ^Code,
	r: ^strings.Reader,
	memtbl: ^memo.Table,
) -> (
	bool,
	int,
	^memo.Capture,
	[]ParseError,
) {
	ip := 0
	st := stack_new()
	src := input.new_input(r)

	// parse in parallel?
	// if memtbl.Size() == 0 {
	// 	srccopy := input.NewInput(r)
	// 	srccopy.SeekTo(1000000)
	// 	thread? exec(vm, ,0, stack_new(), srccopy, memtbl)
	// }

	return exec_code(vm, &ip, st, &src, memtbl, nil)
}

exec_interval :: proc(
	vm: ^Code,
	r: ^strings.Reader,
	memtbl: ^memo.Table,
	intrvl: ^Interval,
) -> (
	bool,
	int,
	^memo.Capture,
	[]ParseError,
) {
	ip := 0
	st := stack_new()
	src := input.new_input(r)

	return exec_code(vm, &ip, st, &src, memtbl, intrvl)
}

exec_code :: proc(
	vm: ^Code,
	ip: ^int,
	st: ^Stack,
	src: ^input.Input,
	memtbl: ^memo.Table,
	intrvl: ^Interval,
) -> (
	bool,
	int,
	^memo.Capture,
	[]ParseError,
) {
	idata := vm.insns

	if ip^ < 0 || ip^ >= len(idata) {
		return true, 0, memo.capture_new_dummy(0, 0, nil), nil
	}

	caprange: Interval

	if intrvl != nil {
		caprange = intrvl^
		// Apply an edit that clears all memoized entries in the interval
		// we are capturing. This ensures that we find all captures in the
		// requested interval.
		memo.table_apply_edit(
			memtbl,
			memo.Edit{
				start = intrvl.low,
				end = intrvl.high,
				len = intrvl.high - intrvl.low,
			},
		)
	}

	context_map: struct {
		intrvl: ^Interval,
		src:    ^input.Input,
		memtbl: ^memo.Table,
	} = {intrvl, src, memtbl}
	context.user_ptr = &context_map // HAVENT TESTED THIS FUNCTION WITH THE CONTEXT - PROBABLY BROKEN
	memoize := proc(id, pos, mlen, count: int, capt: []^memo.Capture) {
		context_map := cast(^struct {
			intrvl: ^Interval,
			src:    ^input.Input,
			memtbl: ^memo.Table,
		})context.user_ptr
		intrvl := context_map.intrvl
		src := context_map.src
		memtbl := context_map.memtbl
		if intrvl != nil {
			delete(capt)
		}
		mexam := max(src.furthest, input.pos(src)) - pos + 1
		memo.table_put(memtbl, id, pos, mlen, mexam, count, capt)
	}

	success := true
	errs := make([dynamic]ParseError)

	loop: for {
		op := idata[ip^]
		#partial switch Opcode(op) {
		case .Char:
			b := decodeU8(idata[ip^ + 1:])
			instruction, ok := input.peek(src);if ok && b == instruction {
				input.advance(src, 1)
				ip^ += szChar
			} else {
				ok := failure_handler(ip, st, src, memoize);if !ok {
					return ok, input.pos(src), nil, errs[:]
				}
			}
			continue loop
		case .Jump:
			lbl := decodeU24(idata[ip^ + 1:])
			ip^ = int(lbl)
		case .Choice:
			lbl := decodeU24(idata[ip^ + 1:])
			stack_pushBacktrack(st, StackBacktrack{int(lbl), input.pos(src)})
			ip^ += szChoice
		case .Call:
			lbl := decodeU24(idata[ip^ + 1:])
			stack_pushRet(st, ip^ + szCall)
			ip^ = int(lbl)
		case .Commit:
			lbl := decodeU24(idata[ip^ + 1:])
			stack_pop(st, true)
			ip^ = int(lbl)
		case .Return:
			ent := stack_pop(st, true)
			if ent != nil && ent.stype == StackKind.Ret {
				ip^ = int(ent.ret)
			} else {
				panic("Return failed")
			}
		case .Fail:
			ok := failure_handler(ip, st, src, memoize);if !ok {
				return ok, input.pos(src), nil, errs[:]
			}
			continue loop
		case .Set:
			set := decodeSet(idata[ip^ + 1:], vm.sets[:])
			instruction, ok := input.peek(src)
			if ok && charset.has(&set, instruction) {
				input.advance(src, 1)
				ip^ += szSet
			} else {
				ok := failure_handler(ip, st, src, memoize);if !ok {
					return ok, input.pos(src), nil, errs[:]
				}
				continue loop
			}
		case .Any:
			n := decodeU8(idata[ip^ + 1:])
			ok := input.advance(src, int(n))
			if ok {
				ip^ += szAny
			} else {
				ok := failure_handler(ip, st, src, memoize);if !ok {
					return ok, input.pos(src), nil, errs[:]
				}
				continue loop
			}
		case .PartialCommit:
			lbl := decodeU24(idata[ip^ + 1:])
			ent := stack_peek(st)
			if ent != nil && ent.stype == StackKind.Btrack {
				ent.btrack.off = input.pos(src)
				stack_prop_capt(st)
				ent.capt = nil
				ip^ = int(lbl)
			} else {
				panic("PartialCommit failed")
			}
		case .Span:
			set := decodeSet(idata[ip^ + 1:], vm.sets[:])
			instruction, ok := input.peek(src)
			for ok && charset.has(&set, instruction) {
				input.advance(src, 1)
				instruction, ok = input.peek(src)
			}
			ip^ += szSpan
		case .BackCommit:
			lbl := decodeU24(idata[ip^ + 1:])
			ent := stack_pop(st, true)
			if ent != nil && ent.stype == StackKind.Btrack {
				input.seek_to(src, ent.btrack.off)
				ip^ = int(lbl)
			} else {
				panic("BackCommit failed")
			}
		case .FailTwice:
			stack_pop(st, false)
			ok := failure_handler(ip, st, src, memoize);if !ok {
				return ok, input.pos(src), nil, errs[:]
			}
			continue loop
		case .Empty:
			op: EmptyOp = EmptyOp(decodeU8(idata[ip^ + 1:]))
			r1 := rune(-1)
			r2 := rune(-1)
			// TODO: PeekBefore may cause problems with incremental parsing
			b1, ok1 := input.peek_before(src);if ok1 {
				r1 = rune(b1)
			}
			b2, ok2 := input.peek(src);if ok2 {
				r2 = rune(b2)
			}
			sat := empty_op_context(r1, r2)
			if int(sat & op) != 0 {
				ip^ += szEmpty
			} else {
				ok := failure_handler(ip, st, src, memoize);if !ok {
					return ok, input.pos(src), nil, errs[:]
				}
				continue loop
			}
		case .TestChar:
			b := decodeU8(idata[ip^ + 2:])
			lbl := decodeU24(idata[ip^ + 3:])
			instruction, ok := input.peek(src)
			if ok && instruction == b {
				stack_pushBacktrack(
					st,
					StackBacktrack{int(lbl), input.pos(src)},
				)
				input.advance(src, 1)
				ip^ += szTestChar
			} else {
				ip^ = int(lbl)
			}
		case .TestCharNoChoice:
			b := decodeU8(idata[ip^ + 2:])
			instruction, ok := input.peek(src);if ok && instruction == b {
				input.advance(src, 1)
				ip^ += szTestCharNoChoice
			} else {
				lbl := decodeU24(idata[ip^ + 3:])
				ip^ = int(lbl)
			}
		case .TestSet:
			lbl := decodeU24(idata[ip^ + 3:])
			set := decodeSet(idata[ip^ + 2:], vm.sets[:])
			instruction, ok := input.peek(src)
			if ok && charset.has(&set, instruction) {
				stack_pushBacktrack(
					st,
					StackBacktrack{int(lbl), input.pos(src)},
				)
				input.advance(src, 1)
				ip^ += szTestSet
			} else {
				ip^ = int(lbl)
			}
		case .TestSetNoChoice:
			set := decodeSet(idata[ip^ + 2:], vm.sets[:])
			instruction, ok := input.peek(src)
			if ok && charset.has(&set, instruction) {
				input.advance(src, 1)
				ip^ += szTestSetNoChoice
			} else {
				lbl := decodeU24(idata[ip^ + 3:])
				ip^ = int(lbl)
			}
		case .TestAny:
			n := decodeU8(idata[ip^ + 2:])
			lbl := decodeU24(idata[ip^ + 3:])
			ent := StackBacktrack{int(lbl), input.pos(src)}
			ok := input.advance(src, int(n))
			if ok {
				stack_pushBacktrack(st, ent)
				ip^ += szTestAny
			} else {
				ip^ = int(lbl)
			}
		case .CaptureBegin:
			id := decodeI16(idata[ip^ + 2:])
			stack_pushCapt(st, StackMemo{id = id, pos = input.pos(src)})
			ip^ += szCaptureBegin
		case .CaptureLate:
			back := decodeU8(idata[ip^ + 1:])
			id := decodeI16(idata[ip^ + 2:])
			stack_pushCapt(
				st,
				StackMemo{id = id, pos = input.pos(src) - int(back)},
			)
			ip^ += szCaptureLate
		case .CaptureFull:
			back := int(decodeU8(idata[ip^ + 1:]))
			id := decodeI16(idata[ip^ + 2:])
			pos := input.pos(src)

			if overlaps(intrvl, pos - back, pos) {
				caprange.low = min(caprange.low, pos - back)
				caprange.high = max(caprange.high, pos)
				capt := memo.capture_new(int(id), pos - back, back, nil)
				stack_add_capt(st, capt)
			}

			ip^ += szCaptureFull
		case .CaptureEnd:
			ent := stack_pop(st, false)

			if ent == nil || ent.stype != StackKind.Capt {
				panic("CaptureEnd did not find capture entry")
			}

			end := input.pos(src)
			if overlaps(intrvl, ent.memoized.pos, end) {
				caprange.low = min(caprange.low, ent.memoized.pos)
				caprange.high = max(caprange.high, end)
				capt := memo.capture_new(
					int(ent.memoized.id),
					ent.memoized.pos,
					end - ent.memoized.pos,
					ent.capt[:],
				)
				stack_add_capt(st, capt)
			}
			ip^ += szCaptureEnd
		case .End:
			fail := decodeU8(idata[ip^ + 1:])
			success = fail != 1
			break loop
		case .MemoOpen:
			lbl := decodeU24(idata[ip^ + 1:])
			id := decodeI16(idata[ip^ + 4:])

			ment := memo.table_get(
				memtbl,
				int(id),
				input.pos(src),
			);if ment != nil {
				if ment.length == -1 {
					ok := failure_handler(ip, st, src, memoize);if !ok {
						return ok, input.pos(src), nil, errs[:]
					}
					continue loop
				}
				capt := ment.captures
				if capt != nil {
					stack_add_capt(st, ..capt)
				}
				input.advance(src, ment.length)
				ip^ = int(lbl)
			} else {
				stack_pushMemo(st, StackMemo{id = id, pos = input.pos(src)})
				ip^ += szMemoOpen
			}
		case .MemoClose:
			ent := stack_pop(st, true)
			if ent != nil && ent.stype == StackKind.Memo {
				mlen := input.pos(src) - ent.memoized.pos
				memoize(
					int(ent.memoized.id),
					ent.memoized.pos,
					mlen,
					1,
					ent.capt[:],
				)
			} else {
				panic("memo close failed")
			}
			ip^ += szMemoClose
		case .MemoTreeOpen:
			lbl := decodeU24(idata[ip^ + 1:])
			id := decodeI16(idata[ip^ + 4:])

			ment := memo.table_get(memtbl, int(id), input.pos(src))
			if ment != nil {
				if ment.length == -1 {
					ok := failure_handler(ip, st, src, memoize);if !ok {
						return ok, input.pos(src), nil, errs[:]
					}
					continue loop
				}
				stack_pushMemoTree(
					st,
					StackMemo{
						id = id,
						pos = input.pos(src),
						count = ment.count,
					},
				)
				capt := ment.captures;if capt != nil {
					stack_add_capt(st, ..capt)
				}
				input.advance(src, ment.length)
				input.peek(src)
				ip^ = int(lbl)
			} else {
				stack_pushMemoTree(
					st,
					StackMemo{id = id, pos = input.pos(src)},
				)
				ip^ += szMemoTreeOpen
			}
		case .MemoTreeClose:
			id := decodeI16(idata[ip^ + 2:])
			for p := stack_peek(st);
			    p != nil &&
			    p.stype == StackKind.MemoTree &&
			    p.memoized.id == id;
			    p = stack_peek(st) {
				stack_pop(st, true)
			}
			ip^ += szMemoTreeClose
		case .MemoTreeInsert:
			ent := stack_peek(st)
			if ent == nil || ent.stype != StackKind.MemoTree {
				panic("no memo entry on stack")
			}
			mlen := input.pos(src) - ent.memoized.pos
			ent.memoized.count += 1
			memoize(
				int(ent.memoized.id),
				ent.memoized.pos,
				mlen,
				ent.memoized.count,
				ent.capt[:],
			)
			ip^ += szMemoTreeInsert
		case .MemoTree:
			seen := 0
			accum := 0
			for {
				top := stack_peekn(st, seen)
				next := stack_peekn(st, seen + 1)

				if top == nil ||
				   next == nil ||
				   top.stype != StackKind.MemoTree ||
				   next.stype != StackKind.MemoTree {
					break
				}

				seen += 1
				accum += top.memoized.count

				if accum < next.memoized.count {
					continue
				}

				for i := 0; i < seen - 1; i += 1 {
					stack_pop(st, true)
				}
				ent := stack_pop(st, false) // next is now top of stack

				if len(ent.capt) > 0 && intrvl == nil {
					dummy := memo.capture_new_dummy(
						ent.memoized.pos,
						input.pos(src) - ent.memoized.pos,
						ent.capt[:],
					)
					stack_add_capt(st, dummy)
				} else if len(ent.capt) > 0 {
					stack_add_capt(st, ..ent.capt[:])
				}

				next.memoized.count = accum + next.memoized.count
				mlen := input.pos(src) - next.memoized.pos
				memoize(
					int(next.memoized.id),
					next.memoized.pos,
					mlen,
					next.memoized.count,
					next.capt[:],
				)

				accum = 0
				seen = 0
			}

			ip^ += szMemoTree
		case .CheckBegin:
			id := decodeI16(idata[ip^ + 2:])
			flag := decodeI16(idata[ip^ + 4:])
			stack_pushCheck(
				st,
				StackMemo{id = id, count = int(flag), pos = input.pos(src)},
			)
			ip^ += szCheckBegin
		case .CheckEnd:
			ent := stack_pop(st, true)
			if ent == nil || ent.stype != StackKind.Check {
				panic("check end needs check stack entry")
			}
			checkid := decodeU24(idata[ip^ + 1:])
			checker := vm.checkers[checkid]

			id := int(ent.memoized.id)
			flag := ent.memoized.count

			n := check(
				checker,
				input.slice(src, int(ent.memoized.pos), input.pos(src)),
				src,
				id,
				RefKind(flag),
			)
			if n == -1 {
				ok := failure_handler(ip, st, src, memoize);if !ok {
					return ok, input.pos(src), nil, errs[:]
				}
				continue loop
			} else {
				input.advance(src, n)
			}

			ip^ += szCheckEnd
		case .Error:
			errid := decodeU24(idata[ip^ + 1:])
			msg := vm.errors[errid]
			append(&errs, ParseError{msg, input.pos(src)})
			ip^ += szError
		case:
			panic("Invalid opcode")
		}
	}


	if intrvl != nil {
		return success,
			input.pos(src),
			memo.capture_new_dummy(
				caprange.low,
				caprange.high - caprange.low,
				st.capt[:],
			),
			errs[:]
	}
	return success,
		input.pos(src),
		memo.capture_new_dummy(0, input.pos(src), st.capt[:]),
		errs[:]
}

MemoizedFn :: proc(id, pos, mlen, count: int, capt: []^memo.Capture)

failure_handler :: proc(
	ip: ^int,
	st: ^Stack,
	src: ^input.Input,
	memoize: MemoizedFn,
) -> bool {
	ent := stack_pop(st, false)
	if ent == nil {
		// match failed
		return false
	}

	#partial switch ent.stype {
	case .Btrack:
		ip^ = ent.btrack.ip
		input.seek_to(src, ent.btrack.off)
		ent.capt = nil
		return true
	case .Memo:
		// Mark this position in the memoTable as a failed match
		memoize(int(ent.memoized.id), ent.memoized.pos, -1, 0, nil)
		ent.capt = nil
		failure_handler(ip, st, src, memoize)
	case .Ret, .Capt, .Check:
		ent.capt = nil
		failure_handler(ip, st, src, memoize)
	}
	return true
}

decodeU8 :: proc(b: []byte) -> byte {
	return b[0]
}

decodeI8 :: proc(b: []byte) -> i8 {
	return i8(b[0])
}

decodeU16 :: proc(b: []byte) -> u16 {
	return u16(b[0]) | u16(b[1]) << 8
}

decodeI16 :: proc(b: []byte) -> i16 {
	return i16(u16(b[0]) | u16(b[1]) << 8)
}

decodeU24 :: proc(b: []byte) -> u32 {
	i1 := u32(decodeU8(b))
	i2 := u32(decodeU16(b[1:]))
	i := (i1 << 16) | i2
	return i
}

decodeSet :: proc(b: []byte, sets: []charset.Set) -> charset.Set {
	i := decodeU8(b)
	return sets[i]
}

overlaps :: proc(i: ^Interval, low2, high2: int) -> bool {
	if i == nil {
		return true
	}
	return i.low < high2 && i.high > low2
}

min :: proc(a, b: int) -> int {
	if a < b {
		return a
	}
	return b
}

max :: proc(a, b: int) -> int {
	if a > b {
		return a
	}
	return b
}
