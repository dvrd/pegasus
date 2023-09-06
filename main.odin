package pegasus

import "core:fmt"
import "core:os"
import "core:strings"
import "core:unicode/utf8"
import "shared:data/stack"

byte_to_str :: proc(b: byte) -> string {
	s := make([]byte, 1)
	s[0] = b
	return string(s)
}

set :: proc(sub: string) -> (p: ^Pattern) {
	p = make_pattern()
	charset := make([dynamic]u8)

	for _, idx in sub {
		append(&charset, sub[idx])
	}

	append(&p.code, Instruction{.Set, charset})

	return
}

range :: proc(sub: string) -> (p: ^Pattern) {
	p = make_pattern()
	charset := make([dynamic]u8)

	for char in sub[0] ..= sub[1] {
		append(&charset, char)
	}

	append(&p.code, Instruction{.Set, charset})
	return
}

pattern_string :: proc(sub: string) -> (p: ^Pattern) {
	p = make_pattern()
	for _, idx in sub {
		append(&p.code, Instruction{.Char, sub[idx]})
	}
	return
}

pattern_number :: proc(n: int) -> (p: ^Pattern) {
	p = make_pattern()
	append(&p.code, Instruction{.Any, n})
	return
}

pattern :: proc {
	pattern_string,
	pattern_number,
}

repeat :: proc(p: ^Pattern, rule: rune) -> ^Pattern {
	if rule == '*' {
		inject_at(&p.code, 0, Instruction{.Choice, len(p.code) + 2})
		append(&p.code, Instruction{.Commit, -len(p.code)})
	} else if rule == '+' {
		fmt.println("not done yet")
	}
	return p
}

concat :: proc(patterns: ..^Pattern) -> (p: ^Pattern) {
	p = make_pattern()
	for join in patterns {
		append(&p.code, ..join.code[:])
	}
	return
}

main :: proc() {
	space := repeat(set(" \t\n"), '*')
	defer delete(space.code)

	digit := repeat(range("09"), '*')
	defer delete(digit.code)

	add := concat(pattern("+"), space)
	defer delete(add.code)

	number := concat(digit, space)
	defer delete(number.code)

	expr := concat(number, repeat(concat(add, number), '*'))
	defer delete(expr.code)

	subject := "120 + 23"
	result := match(expr, subject)
	fmt.println(result, subject[:result])
}
