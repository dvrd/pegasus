package pegasus

import "core:builtin"
import "core:bytes"
import "core:fmt"

Opcode :: enum {
	Any, /* if no char, fail */
	Char, /* if char != aux, fail */
	Set, /* if char not in buff, fail */
	TestAny, /* in no char, jump to 'offset' */
	TestChar, /* if char != aux, jump to 'offset' */
	TestSet, /* if char not in buff, jump to 'offset' */
	Span, /* read a span of chars in buff */
	Behind, /* walk back 'aux' characters (fail if not possible) */
	Ret, /* return from a rule */
	End, /* end of pattern */
	Choice, /* stack a choice; next fail will jump to 'offset' */
	Jmp, /* jump to 'offset' */
	Call, /* call rule at 'offset' */
	OpenCall, /* call rule number 'key' (must be closed to a ICall) */
	Commit, /* pop choice and jump to 'offset' */
	PartialCommit, /* update top choice to current position and jump */
	BackCommit, /* "fails" but jump to its own 'offset' */
	FailTwice, /* pop one choice and then fail */
	Fail, /* go back to saved state on choice and jump to saved offset */
	Giveup, /* internal use */
	FullCapture, /* complete capture of last 'off' chars */
	OpenCapture, /* start a capture */
	CloseCapture,
	CloseRunTime,
}

Offset :: int
N :: int
Buffer :: [dynamic]byte

Instruction :: struct {
	kind: Opcode,
	data: union {
		byte,
		int,
		Buffer,
		^Instruction,
	},
}

Instructions :: [dynamic]Instruction

EntryKind :: enum {
	Backtrack,
	Ret,
}

Entry :: struct {
	kind:    EntryKind,
	address: int,
}

Pattern :: struct {
	code: [dynamic]Instruction,
}

make_pattern :: proc() -> (p: ^Pattern) {
	p = new(Pattern)
	p.code = make(Instructions)
	return
}

giveup := Instruction{.Giveup, nil}
failure := Instruction{.Fail, nil}

match :: proc(p: ^Pattern, sub: string) -> (pos: int, ok: bool) #optional_ok {
	ok = true
	pos = 0 // subject position
	pc := 0 // program counter
	stack := make([dynamic]Entry)
	op: Instruction // next operation

	for pos < len(sub) && pc < len(p.code) {
		op = p.code[pc]
		#partial switch op.kind {
		case .Any:
			if pos + op.data.(N) <= len(sub) {
				pos += op.data.(N)
			} else {
				p.code[pc] = failure
			}
			continue
		case .Set:
			if bytes.contains_rune(op.data.(Buffer)[:], rune(sub[pos])) > -1 {
				pos += 1
				pc += 1
			} else {
				p.code[pc] = failure
			}
		case .Char:
			if op.data.(byte) == sub[pos] {
				pos += 1
				pc += 1
			} else {
				p.code[pc] = failure
			}
			continue
		case .Choice:
			append(&stack, Entry{.Backtrack, pc + op.data.(Offset)})
			pc += 1
			continue
		case .Jmp:
			pc += op.data.(Offset)
			continue
		case .Call:
			append(&stack, Entry{.Ret, pc + 1})
			pc += op.data.(Offset)
			continue
		case .Commit:
			pop(&stack)
			pc += op.data.(Offset)
		case .Ret:
			assert(len(stack) > 0)
			pc = pop(&stack).address
		case .Fail:
			entry := pop(&stack)
			for ; len(stack) > 0 && entry.kind != .Backtrack; entry = pop(&stack) {}
			if entry.kind == .Backtrack {
				pc = entry.address
				continue
			} else {
				ok = false
				return
			}
		}
	}
	return
}

/*
match :: proc(state, o, s, e: string, op: ^Instruction, capture: ^Capture, ptop: int) -> string {
	sp := 0
	stack: [INITBACK]Stack
	capsize := INITCAPSIZE
	captop := 0 /* point to first empty slot in captures */
	ndyncap := 0 /* number of dynamic captures (in Lua stack) */
	current := op /* current instruction */
	stack[sp].next = &giveup
	stack[sp].saved = nil
	stack[sp].caplevel = 0
	sp += 1

	// lua_pushlightuserdata(L, stackbase)

	fmt.println(stack[0])

	// assert(stackidx(ptop) + ndyncap == lua_gettop(L) && ndyncap <= captop)
	    switch (cast(Opcode)current.(Inst).code) {
      case IEnd: {
        assert(stack == getstackbase(L, ptop) + 1);
        capture[captop].kind = .Cclose;
        capture[captop].s = nil;
        return s;
      }
      case IRet: {
        assert(stack > getstackbase(L, ptop) && stack[sp - 1].saved == nil);
				sp -= 1
        current = stack[sp].next;
        continue;
      }
      case ITestAny: {
        if s < e {
					p += 2
				} else {
					p += getoffset(p)
				}
        continue;
      }
      case ITestChar: {
        if cast(byte)s == current.(Int).aux && s < e {
					 current += 2
				} else {
					current += getoffset(p)
				}
        continue
      }
      case ITestSet: {
				c := cast(byte)s
        if (testchar(current.next.next.(byte), c) && s < e) {
          current += 1 + CHARSETINSTSIZE
				} else {
					current += getoffset(p)
				}
        continue;
      }
      case IBehind: {
        int n = current.(Inst).aux;
        if (n > s - o) goto fail;
        s -= n; p++;
        continue;
      }
      case ISpan: {
        for (; s < e; s++) {
          int c = (byte)*s;
          if (!testchar((p+1)->buff, c)) break;
        }
        p += CHARSETINSTSIZE;
        continue;
      }
      case IJmp: {
        p += getoffset(p);
        continue;
      }
      case IChoice: {
        if (stack == stacklimit)
          stack = doublestack(L, &stacklimit, ptop);
        stack->p = p + getoffset(p);
        stack->s = s;
        stack->caplevel = captop;
        stack++;
        p += 2;
        continue;
      }
      case ICall: {
        if (stack == stacklimit)
          stack = doublestack(L, &stacklimit, ptop);
        stack->s = NULL;
        stack->p = p + 2;  /* save return address */
        stack++;
        p += getoffset(p);
        continue;
      }
      case ICommit: {
        assert(stack > getstackbase(L, ptop) && (stack - 1)->s != NULL);
        stack--;
        p += getoffset(p);
        continue;
      }
      case IPartialCommit: {
        assert(stack > getstackbase(L, ptop) && (stack - 1)->s != NULL);
        (stack - 1)->s = s;
        (stack - 1)->caplevel = captop;
        p += getoffset(p);
        continue;
      }
      case IBackCommit: {
        assert(stack > getstackbase(L, ptop) && (stack - 1)->s != NULL);
        s = (--stack)->s;
        captop = stack->caplevel;
        p += getoffset(p);
        continue;
      }
      case IFailTwice:
        assert(stack > getstackbase(L, ptop));
        stack--;
        /* go through */
      case IFail:
      fail: { /* pattern failed: try to backtrack */
        do {  /* remove pending calls */
          assert(stack > getstackbase(L, ptop));
          s = (--stack)->s;
        } while (s == NULL);
        if (ndyncap > 0)  /* is there matchtime captures? */
          ndyncap -= removedyncap(L, capture, stack->caplevel, captop);
        captop = stack->caplevel;
        p = stack->p;
        printf("**FAIL**\n");
        continue;
      }
      case ICloseRunTime: {
        CapState cs;
        int rem, res, n;
        int fr = lua_gettop(L) + 1;  /* stack index of first result */
        cs.reclevel = 0; cs.L = L;
        cs.s = o; cs.ocap = capture; cs.ptop = ptop;
        n = runtimecap(&cs, capture + captop, s, &rem);  /* call function */
        captop -= n;  /* remove nested captures */
        ndyncap -= rem;  /* update number of dynamic captures */
        fr -= rem;  /* 'rem' items were popped from Lua stack */
        res = resdyncaptures(L, fr, s - o, e - o);  /* get result */
        if (res == -1)  /* fail? */
          goto fail;
        s = o + res;  /* else update current position */
        n = lua_gettop(L) - fr + 1;  /* number of new captures */
        ndyncap += n;  /* update number of dynamic captures */
        if (n == 0)  /* no new captures? */
          captop--;  /* remove open group */
        else {  /* new captures; keep original open group */
          if (fr + n >= SHRT_MAX)
            luaL_error(L, "too many results in match-time capture");
          /* add new captures + close group to 'capture' list */
          capture = growcap(L, capture, &capsize, captop, n + 1, ptop);
          adddyncaptures(s, capture + captop, n, fr);
          captop += n + 1;  /* new captures + close group */
        }
        p++;
        continue;
      }
      case ICloseCapture: {
        const char *s1 = s;
        assert(captop > 0);
        /* if possible, turn capture into a full capture */
        if (capture[captop - 1].siz == 0 &&
            s1 - capture[captop - 1].s < UCHAR_MAX) {
          capture[captop - 1].siz = s1 - capture[captop - 1].s + 1;
          p++;
          continue;
        }
        else {
          capture[captop].siz = 1;  /* mark entry as closed */
          capture[captop].s = s;
          goto pushcapture;
        }
      }
      case IOpenCapture:
        capture[captop].siz = 0;  /* mark entry as open */
        capture[captop].s = s;
        goto pushcapture;
      case IFullCapture:
        capture[captop].siz = getoff(p) + 1;  /* save capture size */
        capture[captop].s = s - getoff(p);
        /* goto pushcapture; */
      pushcapture: {
        capture[captop].idx = p->i.key;
        capture[captop].kind = getkind(p);
        captop++;
        capture = growcap(L, capture, &capsize, captop, 0, ptop);
        p++;
        continue;
      }
      default: assert(0); return NULL;
    }
  }
}
*/
