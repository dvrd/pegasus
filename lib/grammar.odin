package pegasus

import "charset"
import "core:mem/virtual"
import "core:sync"

// Pattern    <- Spacing_ (Grammar / Expression) EndOfFile_
// Grammar    <- Definition+
// Definition <- Identifier LEFTARROW Expression
//
// Expression <- Sequence (SLASH Sequence)*
// Sequence   <- Prefix*
// Prefix     <- (AND / NOT)? Suffix
// Suffix     <- Primary (QUESTION / STAR / PLUS)?
// Primary    <- Identifier !LEFTARROW
// 			/ '(' Expression ')'
// 			/ Literal / Class
// 			/ BRACEPO Expression BRACEPC
// 			/ BRACEO Expression BRACEC
// 			/ DOT
//
// Identifier <- IdentStart IdentCont* Spacing_
// IdentStart <- [a-zA-Z_]
// IdentCont  <- IdentStart / [0-9]
//
// Literal    <- ['] (!['] Char)* ['] Spacing_
// 			/ ["] (!["] Char)* ["] Spacing_
// Class      <- '[' CARAT? (!']' Range)* ']' Spacing_
// Range      <- Char '-' Char / Char
// Char       <- '\\' [nrt'"\[\]\\\-]
// 			/ '\\' [0-3][0-7][0-7]
// 			/ '\\' [0-7][0-7]?
// 			/ !'\\' .
//
// AND        <- '&' Spacing_
// NOT        <- '!' Spacing_
// QUESTION   <- '?' Spacing_
// STAR       <- '*' Spacing_
// PLUS       <- '+' Spacing_
// DOT        <- '.' Spacing_
// CARAT      <- '^' Spacing_
// BRACEO     <- '{' Spacing_
// BRACEC     <- '}' Spacing_
// BRACEPO    <- '{{' Spacing_
// BRACEPC    <- '}}' Spacing_
// LEFTARROW  <- '<-' Spacing_
// OPEN       <- '(' Spacing_
// CLOSE      <- ')' Spacing_
// SLASH      <- '/' Spacing_
//
// Spacing_   <- (Space_ / Comment_)*
// Comment_   <- '#' (!EndOfLine_ .)* EndOfLine_
// Space_     <- ' ' / '\t' / EndOfLine_
// EndOfLine_ <- '\r\n' / '\n' / '\r'
// EndOfFile_ <- !.

NonTerm :: enum {
	Pattern,
	Grammar,
	Definition,
	Expression,
	Sequence,
	Prefix,
	Suffix,
	Primary,
	Literal,
	Range,
	Class,
	Identifier,
	IdentStart,
	IdentCont,
	Char,
	AND,
	NOT,
	QUESTION,
	STAR,
	PLUS,
	DOT,
	CARAT,
	OPEN,
	BRACEO,
	BRACEPO,
}

re_grammar: map[string]Pattern
re_grammar_arena: virtual.Arena
re_grammar_initialized: bool
re_grammar_mutex: sync.Mutex

re_grammar_init :: proc() {
	if re_grammar_initialized {
		return
	}

	sync.mutex_lock(&re_grammar_mutex)
	defer sync.mutex_unlock(&re_grammar_mutex)

	// Double-check after acquiring lock
	if re_grammar_initialized {
		return
	}

	arena_err := virtual.arena_init_growing(&re_grammar_arena)
	assert(arena_err == .None, "Failed to initialize re_grammar arena")
	saved_allocator := context.allocator
	context.allocator = virtual.arena_allocator(&re_grammar_arena)
	defer context.allocator = saved_allocator

	re_grammar = make(map[string]Pattern)
	re_grammar["Pattern"] = cap(
		concat(
			non_term("Spacing"),
			or(non_term("Grammar"), non_term("Expression")),
			non_term("EndOfFile"),
		),
		int(NonTerm.Pattern),
	)
	re_grammar["Grammar"] = cap(plus(non_term("Definition")), int(NonTerm.Grammar))
	re_grammar["Definition"] = cap(
		concat(
			non_term("Identifier"),
			non_term("LEFTARROW"),
			non_term("Expression"),
		),
		int(NonTerm.Definition),
	)
	re_grammar["Expression"] = cap(
		concat(
			non_term("Sequence"),
			star(concat(non_term("SLASH"), non_term("Sequence"))),
		),
		int(NonTerm.Expression),
	)
	re_grammar["Sequence"] = cap(star(non_term("Prefix")), int(NonTerm.Sequence))
	re_grammar["Prefix"] = cap(
		concat(
			optional(or(non_term("AND"), non_term("NOT"))),
			non_term("Suffix"),
		),
		int(NonTerm.Prefix),
	)
	re_grammar["Suffix"] = cap(
		concat(
			non_term("Primary"),
			optional(
				or(non_term("QUESTION"), non_term("STAR"), non_term("PLUS")),
			),
		),
		int(NonTerm.Suffix),
	)
	re_grammar["Primary"] = cap(
		or(
			concat(non_term("Identifier"), not(non_term("LEFTARROW"))),
			concat(
				non_term("OPEN"),
				non_term("Expression"),
				non_term("CLOSE"),
			),
			concat(
				non_term("BRACEPO"),
				non_term("Expression"),
				non_term("BRACEPC"),
			),
			concat(
				non_term("BRACEO"),
				non_term("Expression"),
				non_term("BRACEC"),
			),
			non_term("Literal"),
			non_term("Class"),
			non_term("DOT"),
		),
		int(NonTerm.Primary),
	)
	re_grammar["Identifier"] = cap(
		concat(
			non_term("IdentStart"),
			star(non_term("IdentCont")),
			non_term("Spacing"),
		),
		int(NonTerm.Identifier),
	)
	re_grammar["IdentStart"] = cap(
		set(
			charset.add(
				charset.add(charset.range('a', 'z'), charset.range('A', 'Z')),
				charset.new_charset([]byte{'_', '%'}), // % for built-in assertions like %begin_line
			),
		),
		int(NonTerm.IdentStart),
	)
	re_grammar["IdentCont"] = cap(
		or(non_term("IdentStart"), set(charset.range('0', '9'))),
		int(NonTerm.IdentCont),
	)
	re_grammar["Literal"] = cap(
		or(
			concat(
				literal("'"),
				star(concat(not(literal("'")), non_term("Char"))),
				literal("'"),
				non_term("Spacing"),
			),
			concat(
				literal("\""),
				star(concat(not(literal("\"")), non_term("Char"))),
				literal("\""),
				non_term("Spacing"),
			),
		),
		int(NonTerm.Literal),
	)
	re_grammar["Class"] = cap(
		concat(
			literal("["),
			optional(non_term("CARAT")),
			star(concat(not(literal("]")), non_term("Range"))),
			literal("]"),
			non_term("Spacing"),
		),
		int(NonTerm.Class),
	)
	re_grammar["Range"] = cap(
		or(
			concat(non_term("Char"), literal("-"), non_term("Char")),
			non_term("Char"),
		),
		int(NonTerm.Range),
	)
	re_grammar["Char"] = cap(
		or(
			concat(
				literal("\\"),
				set(
					charset.new_charset(
						[]byte{'n', 'r', 't', '\'', '"', '[', ']', '\\', '-'},
					),
				),
			),
		concat(
			literal("\\"),
			set(charset.range('0', '3')),
			set(charset.range('0', '7')),
			set(charset.range('0', '7')),
		),
			concat(
				literal("\\"),
				set(charset.range('0', '7')),
				optional(set(charset.range('0', '7'))),
			),
			concat(not(literal("\\")), any(1)),
		),
		int(NonTerm.Char),
	)
	re_grammar["AND"] = cap(
		concat(literal("&"), non_term("Spacing")),
		int(NonTerm.AND),
	)
	re_grammar["NOT"] = cap(
		concat(literal("!"), non_term("Spacing")),
		int(NonTerm.NOT),
	)
	re_grammar["QUESTION"] = cap(
		concat(literal("?"), non_term("Spacing")),
		int(NonTerm.QUESTION),
	)
	re_grammar["STAR"] = cap(
		concat(literal("*"), non_term("Spacing")),
		int(NonTerm.STAR),
	)
	re_grammar["PLUS"] = cap(
		concat(literal("+"), non_term("Spacing")),
		int(NonTerm.PLUS),
	)
	re_grammar["DOT"] = cap(
		concat(literal("."), non_term("Spacing")),
		int(NonTerm.DOT),
	)
	re_grammar["CARAT"] = cap(
		concat(literal("^"), non_term("Spacing")),
		int(NonTerm.CARAT),
	)
	re_grammar["OPEN"] = cap(
		concat(literal("("), non_term("Spacing")),
		int(NonTerm.OPEN),
	)
	re_grammar["CLOSE"] = concat(literal(")"), non_term("Spacing"))
	re_grammar["BRACEO"] = cap(
		concat(literal("{"), non_term("Spacing")),
		int(NonTerm.BRACEO),
	)
	re_grammar["BRACEC"] = concat(literal("}"), non_term("Spacing"))
	re_grammar["BRACEPO"] = cap(
		concat(literal("{{"), non_term("Spacing")),
		int(NonTerm.BRACEPO),
	)
	re_grammar["BRACEPC"] = concat(literal("}}"), non_term("Spacing"))
	re_grammar["SLASH"] = concat(literal("/"), non_term("Spacing"))
	re_grammar["LEFTARROW"] = concat(literal("<-"), non_term("Spacing"))
	re_grammar["Spacing"] = star(or(non_term("Space"), non_term("Comment")))
	re_grammar["Comment"] = concat(
		literal("#"),
		star(concat(not(non_term("EndOfLine")), any(1))),
		non_term("EndOfLine"),
	)
	re_grammar["Space"] = or(
		set(charset.new_charset([]byte{' ', '\t'})),
		non_term("EndOfLine"),
	)
	re_grammar["EndOfLine"] = or(literal("\r\n"), literal("\n"), literal("\r"))
	re_grammar["EndOfFile"] = not(any(1))

	// Compile the meta-grammar parser (also allocated from the grammar arena)
	prog := must_compile(grammar("Pattern", re_grammar))
	parser = encode(prog)

	re_grammar_initialized = true
}
