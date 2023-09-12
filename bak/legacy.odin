package bak

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
		append(&p.code, Instruction{.Choice, len(p.code) + 2})
		append(&p.code, ..p.code[:])
		append(&p.code, Instruction{.Commit, -len(p.code)})
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

not :: proc(p: ^Pattern) {
	inject_at(&p.code, 0, Instruction{.Choice, len(p.code) + 3})
	append(&p.code, Instruction{.Commit, Offset(1)})
	append(&p.code, failure)
}

print_instructions :: proc(p: ^Pattern) {
	count := 1
	for i in p.code {
		fmt.print(count, "| ")
		fmt.println(i.kind, i.data)
		count += 1
	}
}
