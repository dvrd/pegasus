package pegasus

import "core:fmt"
import "core:os"
import "core:strings"
import "memo"

match :: proc(
	grammar: string,
	subject: string,
) -> (
	bool,
	int,
	^memo.Capture,
	[]ParseError,
) {
	patt, err := re_Compile(grammar);if err {
		print_err("Could not compile a pattern from the provided grammar")
		os.exit(1)
	}

	fmt.println(patt.(^GrammarNode).defs)
	prog: Program
	prog, err = compile(patt);if err {
		print_err("Could not compile a program from the provided pattern")
		os.exit(1)
	}

	fmt.println(len(prog))
	code := encode(prog)

	reader := new(strings.Reader)
	defer free(reader)
	strings.reader_init(reader, subject)

	memtbl := memo.new_table(512)

	return exec(&code, reader, memtbl)
}

print_err :: proc(s: string) {
	os.write_string(os.stderr, "\e[1;31m")
	os.write_string(os.stderr, "ERROR: ")
	os.write_string(os.stderr, "\e[0m")
	os.write_string(os.stderr, s)
	os.write_string(os.stderr, "\n")
}

main :: proc() {
	grammar := `
Expr   <- Factor ([+\-] Factor)*
Factor <- Term ([*/] Term)*
Term   <- Number / '(' Expr ')'
Number <- [0-9]+
	`
	subject := "23"
	is_match, pos, capture, errs := match(grammar, subject)
	fmt.println(pos, subject[:pos])
}
