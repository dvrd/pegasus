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
	charset := make([dynamic]rune)

	for _, idx in sub {
		append(&charset, rune(sub[idx]))
	}

	append(&p.code, Instruction{.Set, charset})

	return
}

range :: proc(start: u8, end: u8) -> (p: ^Pattern) {
	p = make_pattern()
	charset := make([dynamic]rune)

	for char in start ..= end {
		append(&charset, rune(char))
	}

	append(&p.code, Instruction{.Set, charset})
	return
}

pattern_string :: proc(sub: string) -> (p: ^Pattern) {
	p = make_pattern()
	for _, idx in sub {
		append(&p.code, Instruction{.Char, rune(sub[idx])})
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

option :: proc(left, right: ^Pattern) -> (p: ^Pattern) {
	p = make_pattern()
	inject_at(&p.code, 0, Instruction{.Choice, len(left.code) + 2})
	append(&p.code, ..left.code[:])
	append(&p.code, Instruction{.Commit, Offset(len(right.code) + 1)})
	append(&p.code, ..right.code[:])
	return
}

print_instructions :: proc(p: ^Pattern) {
	count := 1
	for i in p.code {
		fmt.print(count, "| ")
		fmt.println(i.kind, i.data)
		count += 1
	}
}

main :: proc() {
	space := repeat(set(" \t\n"), '*')
	defer delete(space.code)

	OP := concat(pattern("("), space)
	defer delete(OP.code)

	CP := concat(pattern(")"), space)
	defer delete(CP.code)

	digit := repeat(range('0', '9'), '*')
	defer delete(digit.code)

	add := concat(pattern("+"), space)
	defer delete(add.code)

	number := concat(digit, space)
	defer delete(number.code)

	add_expr := concat(number, repeat(concat(add, number), '*'))
	defer delete(add_expr.code)

	atom := option(number, concat(OP, add, CP))
	defer delete(atom.code)

	expr := concat(atom, repeat(concat(add, atom), '*'))

	// print_instructions(expr)

	subject := "23 + 123 + 24"
	result := match(expr, subject)
	fmt.println(result, subject[:result])
}
