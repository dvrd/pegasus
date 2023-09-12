package vm

import "core:builtin"
import "core:bytes"
import "core:fmt"
import inst "pegasus:instructions"

failure := inst.Fail{}
end_failure := inst.End{true}
end := inst.End{false}

match :: proc(p: ^Pattern, sub: string) -> (sp: int, ok: bool) #optional_ok {
	append(&p.code, end)
	ok = true
	fail := false
	sp = 0 // subject position
	ip := 0 // instruction pointer
	stack := make([dynamic]Entry)
	op: Instruction // next operation

	base: for sp < len(sub) && ip < len(p.code) {
		op = fail ? failure : p.code[ip]
		fmt.println(ip, "|", op.kind, op.data)
		#partial switch op.kind {
		case .Any:
			if sp + op.data.(N) <= len(sub) {
				sp += op.data.(N)
			} else {
				fail = true
			}
			continue
		case .Set:
			for r in op.data.(Buffer) {
				if r == rune(sub[sp]) {
					sp += 1
					ip += 1
					continue base
				}
			}
			fail = true
		case .Char:
			if op.data.(rune) == rune(sub[sp]) {
				sp += 1
				ip += 1
			} else {
				fail = true
			}
			continue
		case .Choice:
			append(&stack, Backtrack{ip + op.data.(Offset), sp})
			ip += 1
			continue
		case .Jmp:
			ip += op.data.(Offset)
			continue
		case .Call:
			append(&stack, ip + 1)
			ip += op.data.(Offset)
			continue
		case .Commit:
			pop(&stack)
			ip += op.data.(Offset)
		case .Ret:
			assert(len(stack) > 0)
			ip = pop(&stack).(Return)
			continue
		case .End:
			return
		case .EndFail:
			ok = false
			sp = 0
			return
		case .Fail:
			fail = false
			for len(stack) > 0 {
				entry := pop(&stack)
				#partial switch e in entry {
				case Backtrack:
					ip = entry.(Backtrack).ip
					sp = entry.(Backtrack).sp
					continue base
				}
			}
			p.code[ip] = end_failure
		}
	}
	return
}
