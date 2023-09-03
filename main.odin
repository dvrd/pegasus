package pegasus

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

Literal :: union {
	string,
	int,
}

Char :: struct {
	literal: rune,
}

Any :: struct {
	n: int,
}

Choice :: struct {
	pos: int,
}

Commit :: struct {
	pos: int,
}

Charset :: struct {
	set: [dynamic]Char,
}

EOF :: distinct int

Instruction :: union #no_nil {
	Char,
	Any,
	Charset,
	Choice,
	Commit,
	EOF,
}

Instructions :: [dynamic]Instruction

pattern_string :: proc(pattern: string) -> Instructions {
	data := make(Instructions)
	for literal in pattern {
		append(&data, Char{literal})
	}
	return data
}

pattern_int :: proc(n: int) -> Instructions {
	data := make(Instructions)
	append(&data, Any{n})
	return data
}

pattern :: proc {
	pattern_string,
	pattern_int,
}

range :: proc(r: string) -> Instructions {
	data := make(Instructions)
	chars := make([dynamic]Char)
	for char in r[0] ..= r[1] {
		append(&chars, Char{rune(char)})
	}
	append(&data, Charset{chars})
	return data
}

set :: proc(s: string) -> Instructions {
	data := make(Instructions)
	chars := make([dynamic]Char)
	for rune in s {
		append(&chars, Char{rune})
	}
	append(&data, Charset{chars})
	return data
}

repeat :: proc(i: ^Instructions, count: int) {
	if count == 0 {
		inject_at(i, 0, Choice{len(i) + 2})
		append(i, Commit{1})
	}
}

concat :: proc(a, b: ^Instructions) {
	append(a, ..b[:])
}

match :: proc(stack: ^Instructions, test: string) -> int {
	pc := 0
	pos := 0
	last_pos: int
	saved := -1
	ops: for pc < len(stack) {
		fmt.println("INFO: executing at", pc)
		switch i in stack[pc] {
		case Char:
			fmt.println(pc, i)
			if i.literal == rune(test[pos]) {
				pos += 1
			}
		case Charset:
			last_pos = pos
			for char in i.set {
				if pos >= len(test) {
					return pos
				}
				if char.literal == rune(test[pos]) {
					pos += 1
				}
			}
			if last_pos == pos {
				pc -= 1
				continue ops
			}
		case Choice:
			if saved == pc + i.pos {
				pc = saved
				saved = -1
				continue ops
			} else {
				saved = pc + i.pos
			}
		case Commit:
			pc = pc - i.pos
			continue ops
		case Any:
			fmt.println(pc, i)
			if i.n >= len(test) {
				return len(test)
			} else {
				pos += i.n
			}
		case EOF:
			fmt.println(i)
		case:
			fmt.println("unknown instruction")
		}
		pc += 1
	}
	return pos
}

main :: proc() {
	spaces := set(" \t\n")
	repeat(&spaces, 0)

	add := pattern("+")
	concat(&add, &spaces)

	digits := range("09")
	repeat(&digits, 0)
	concat(&digits, &spaces)

	concat(&digits, &add)
	concat(&digits, &digits)
	fmt.println(digits)

	subject := "25 + 25"
	result := match(&digits, subject)
	fmt.println(result, subject[:result])
}
