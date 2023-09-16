package pegasus

import "charset"
import "core:fmt"
import "core:strings"
import "memo"

match :: proc(
	p: Pattern,
	subject: string,
) -> (
	bool,
	int,
	^memo.Capture,
	[]ParseError,
) {
	program := must_compile(p)

	code := encode(program)

	reader := new(strings.Reader)
	defer free(reader)
	strings.reader_init(reader, subject)

	memtbl := memo.new_table(512)

	return exec(&code, reader, memtbl)
}

main :: proc() {
	subject := "23 + 23"
	space := star(set(charset.new_charset([]byte{' ', '\t', '\n'})))
	number := plus(set(charset.range('0', '9')))
	numeral := concat(number, space)

	term := or(
		non_term("number"),
		concat(concat(literal("("), non_term("expr")), literal(")")),
	)

	addition := concat(literal("+"), space)
	op_add := concat(addition, non_term("term"))
	expr := concat(non_term("term"), star(op_add))

	p := grammar(
		"expr",
		map[string]Pattern{"expr" = expr, "term" = term, "number" = numeral},
	)


	ok, pos, captures, errs := match(p, subject)

	fmt.println(subject[:pos])
}
