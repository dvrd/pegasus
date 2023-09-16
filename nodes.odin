package pegasus

import "charset"

// A Pattern is an object that can be compiled into a parsing program.
Pattern :: union {
	^AltNode,
	^SeqNode,
	^StarNode,
	^PlusNode,
	^OptionalNode,
	^NotNode,
	^AndNode,
	^CapNode,
	^MemoNode,
	^CheckNode,
	^GrammarNode,
	^SearchNode,
	^RepeatNode,
	^ClassNode,
	^LiteralNode,
	^NonTermNode,
	^DotNode,
	^ErrorNode,
	^EmptyOpNode,
	^EmptyNode,
}


// AltNode is the binary operator for alternation.
AltNode :: struct {
	left:  Pattern,
	right: Pattern,
}

// SeqNode is the binary operator for sequences.
SeqNode :: struct {
	left:  Pattern,
	right: Pattern,
}

// StarNode is the operator for the Kleene star.
StarNode :: struct {
	patt: Pattern,
}

// PlusNode is the operator for the Kleene plus.
PlusNode :: struct {
	patt: Pattern,
}

// OptionalNode is the operator for making a pattern optional.
OptionalNode :: struct {
	patt: Pattern,
}

// NotNode is the not predicate.
NotNode :: struct {
	patt: Pattern,
}

// AndNode is the and predicate.
AndNode :: struct {
	patt: Pattern,
}

// CapNode marks a pattern to be captured with a certain ID.
CapNode :: struct {
	patt: Pattern,
	id:   int,
}

// MemoNode marks a pattern to be memoized with a certain ID.
MemoNode :: struct {
	patt: Pattern,
	id:   int,
}

// CheckNode marks a pattern to be checker by a certain checker.
CheckNode :: struct {
	patt:    Pattern,
	checker: Checker,
	id:      int,
	flag:    int,
}

// GrammarNode represents a grammar of non-terminals and their associated
// patterns. The Grammar must also have an entry non-terminal.
GrammarNode :: struct {
	defs:  map[string]Pattern,
	start: string,
}

// SearchNode represents a search for a certain pattern.
SearchNode :: struct {
	patt: Pattern,
}

// RepeatNode represents the repetition of a pattern a constant number of
// times.
RepeatNode :: struct {
	patt: Pattern,
	n:    int,
}

// ClassNode represents a character set.
ClassNode :: struct {
	chars: ^charset.Set,
}

// LiteralNode represents a literal string.
LiteralNode :: struct {
	str: string,
}

// NonTermNode represents the use of a non-terminal. If this non-terminal is
// inlined during compilation, the `inlined` field will point to the pattern
// that is inlined.
NonTermNode :: struct {
	name:    string,
	inlined: Pattern,
}

// DotNode represents the pattern to match any byte.
DotNode :: struct {
	n: u8,
}

// ErrorNode represents a pattern that fails with a certain error message.
ErrorNode :: struct {
	message: string,
	recover: Pattern,
}

// EmptyOpNode is a node that performs a zero-width assertion.
EmptyOpNode :: struct {} //op: syntax.EmptyOp


// EmtpyNode represents the empty pattern.
EmptyNode :: struct {}

// WalkFunc is a function that takes a pattern.
WalkFunc :: proc(sub: Pattern)

// CountSubPatterns returns the number of subpatterns that exist in the given
// pattern.
count_sub_patterns :: proc(p: Pattern) -> int {
	count := 0
	context.user_ptr = &count
	fn := proc(sub: Pattern) {
		count := cast(^int)context.user_ptr
		count^ += 1
	}
	walk_pattern(p, true, fn)
	return count
}

// WalkPattern calls fn for every subpattern contained in p. If followInline
// is true, WalkPattern will walk over inlined patterns as well.
walk_pattern :: proc(p: Pattern, followInline: bool, fn: WalkFunc) {
	fn(p)
	#partial switch t in p {
	case ^AltNode:
		walk_pattern(t.left, followInline, fn)
		walk_pattern(t.right, followInline, fn)
	case ^SeqNode:
		walk_pattern(t.left, followInline, fn)
		walk_pattern(t.right, followInline, fn)
	case ^StarNode:
		walk_pattern(t.patt, followInline, fn)
	case ^PlusNode:
		walk_pattern(t.patt, followInline, fn)
	case ^OptionalNode:
		walk_pattern(t.patt, followInline, fn)
	case ^NotNode:
		walk_pattern(t.patt, followInline, fn)
	case ^AndNode:
		walk_pattern(t.patt, followInline, fn)
	case ^CapNode:
		walk_pattern(t.patt, followInline, fn)
	case ^MemoNode:
		walk_pattern(t.patt, followInline, fn)
	case ^SearchNode:
		walk_pattern(t.patt, followInline, fn)
	case ^CheckNode:
		walk_pattern(t.patt, followInline, fn)
	case ^ErrorNode:
		walk_pattern(t.recover, followInline, fn)
	case ^GrammarNode:
		for k in t.defs {
			walk_pattern(t.defs[k], followInline, fn)
		}
	case ^NonTermNode:
		if t.inlined != nil && followInline {
			walk_pattern(t.inlined, followInline, fn)
		}
	}
}
