package pegasus

import "charset"

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
// 			/ '\\' [0-2][0-7][0-7]
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

re_grammar := map[string]Pattern{
	"Pattern"    = cap(
		concat(
			non_term("Spacing"),
			or(non_term("Grammar"), non_term("Expression")),
			non_term("EndOfFile"),
		),
		int(NonTerm.Pattern)
	),
	"Grammar"    = cap(plus(non_term("Definition")), int(NonTerm.Grammar)),
	"Definition" = cap(
		concat(
			non_term("Identifier"),
			non_term("LEFTARROW"),
			non_term("Expression"),
		),
		int(NonTerm.Definition)
	),
	"Expression" = cap(
		concat(
			non_term("Sequence"),
			star(concat(non_term("SLASH"), non_term("Sequence"))),
		),
		int(NonTerm.Expression)
	),
	"Sequence"   = cap(star(non_term("Prefix")), int(NonTerm.Sequence)),
	"Prefix"     = cap(
		concat(
			optional(or(non_term("AND"), non_term("NOT"))),
			non_term("Suffix"),
		),
		int(NonTerm.Prefix)
	),
	"Suffix"     = cap(
		concat(
			non_term("Primary"),
			optional(
				or(non_term("QUESTION"), non_term("STAR"), non_term("PLUS")),
			),
		),
		int(NonTerm.Suffix)
	),
	"Primary"    = cap(
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
		int(NonTerm.Primary)
	),
	"Identifier" = cap(
		concat(
			non_term("IdentStart"),
			star(non_term("IdentCont")),
			non_term("Spacing"),
		),
		int(NonTerm.Identifier)
	),
	"IdentStart" = cap(
		set(
			charset.add(
				charset.add(charset.range('a', 'z'), charset.range('A', 'Z')),
				charset.new_charset([]byte{'_'}),
			),
		),
		int(NonTerm.IdentStart)
	),
	"IdentCont"  = cap(
		or(non_term("IdentStart"), set(charset.range('0', '9'))),
		int(NonTerm.IdentCont)
	),
	"Literal"    = cap(
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
		int(NonTerm.Literal)
	),
	"Class"      = cap(
		concat(
			literal("["),
			optional(non_term("CARAT")),
			star(concat(not(literal("]")), non_term("Range"))),
			literal("]"),
			non_term("Spacing"),
		),
		int(NonTerm.Class)
	),
	"Range"      = cap(
		or(
			concat(non_term("Char"), literal("-"), non_term("Char")),
			non_term("Char"),
		),
		int(NonTerm.Range)
	),
	"Char"       = cap(
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
				set(charset.range('0', '2')),
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
		int(NonTerm.Char)
	),
	"AND"        = cap(concat(literal("&"), non_term("Spacing")), int(NonTerm.AND)),
	"NOT"        = cap(concat(literal("!"), non_term("Spacing")), int(NonTerm.NOT)),
	"QUESTION"   = cap(concat(literal("?"), non_term("Spacing")), int(NonTerm.QUESTION)),
	"STAR"       = cap(concat(literal("*"), non_term("Spacing")), int(NonTerm.STAR)),
	"PLUS"       = cap(concat(literal("+"), non_term("Spacing")), int(NonTerm.PLUS)),
	"DOT"        = cap(concat(literal("."), non_term("Spacing")), int(NonTerm.DOT)),
	"CARAT"      = cap(concat(literal("^"), non_term("Spacing")), int(NonTerm.CARAT)),
	"OPEN"       = cap(concat(literal("("), non_term("Spacing")), int(NonTerm.OPEN)),
	"CLOSE"      = concat(literal(")"), non_term("Spacing")),
	"BRACEO"     = cap(concat(literal("{"), non_term("Spacing")), int(NonTerm.BRACEO)),
	"BRACEC"     = concat(literal("}"), non_term("Spacing")),
	"BRACEPO"    = cap(concat(literal("{{"), non_term("Spacing")), int(NonTerm.BRACEPO)),
	"BRACEPC"    = concat(literal("}}"), non_term("Spacing")),
	"SLASH"      = concat(literal("/"), non_term("Spacing")),
	"LEFTARROW"  = concat(literal("<-"), non_term("Spacing")),
	"Spacing"    = star(or(non_term("Space"), non_term("Comment"))),
	"Comment"    = concat(
		literal("#"),
		star(concat(not(non_term("EndOfLine")), any(1))),
		non_term("EndOfLine"),
	),
	"Space"      = or(
		set(charset.new_charset([]byte{' ', '\t'})),
		non_term("EndOfLine"),
	),
	"EndOfLine"  = or(literal("\r\n"), literal("\n"), literal("\r")),
	"EndOfFile"  = not(any(1)),
}
