package pegasus

import "core:builtin"
import "core:bytes"
import "core:fmt"

Opcode :: enum {
	Any, /* if no char, fail */
	Char, /* if char != aux, fail */
	Set, /* if char not in buff, fail */
	Ret, /* return from a rule */
	End, /* end of pattern */
	EndFail, /* end match in failure */
	Choice, /* stack a choice; next fail will jump to 'offset' */
	Jmp, /* jump to 'offset' */
	Call, /* call rule at 'offset' */
	Commit, /* pop choice and jump to 'offset' */
	Fail, /* go back to saved state on choice and jump to saved offset */
}

Offset :: int
N :: int
Buffer :: [dynamic]rune

Instruction :: struct {
	kind: Opcode,
	data: union {
		rune,
		int,
		Buffer,
		^Instruction,
	},
}

Instructions :: [dynamic]Instruction

Backtrack :: struct {
	ip: int,
	sp: int,
}

Return :: int

Entry :: union {
	Backtrack,
	Return,
}

Pattern :: struct {
	code: [dynamic]Instruction,
}

make_pattern :: proc() -> (p: ^Pattern) {
	p = new(Pattern)
	p.code = make(Instructions)
	return
}

anger: rune : '😡'
sadness: rune : '😔'
happiness: rune : '😬'
failure := Instruction{.Fail, sadness}
end_failure := Instruction{.EndFail, anger}
end := Instruction{.End, happiness}

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
