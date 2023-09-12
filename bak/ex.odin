package pegasus

arithmetic_parser :: proc() -> ^Pattern {
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

	return expr
}
