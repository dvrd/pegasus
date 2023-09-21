package pegasus

import "charset"
import "core:fmt"
import "core:os"
import "core:strings"
import "memo"
import log "shared:logging"

match :: proc(
	gram: string,
	subject: string,
) -> (
	bool,
	int,
	^memo.Capture,
	[]ParseError,
) {
	patt, err := re_Compile(gram);if err {
		log.error("Could not compile a pattern from the provided grammar")
		os.exit(1)
	}

	prog: Program
	prog, err = compile(patt);if err {
		log.error("Could not compile a program from the provided pattern")
		os.exit(1)
	}

	code := encode(prog)

	reader := new(strings.Reader)
	defer free(reader)
	strings.reader_init(reader, subject)

	memtbl := memo.new_table(512)

	return exec(&code, reader, memtbl)
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
	log.success("matched til position", pos, "|", subject[:pos])
}
