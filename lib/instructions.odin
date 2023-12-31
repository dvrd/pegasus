package pegasus

import "charset"
import "core:fmt"
import "core:strings"

uniqId: int

Instruction :: union {
	Label,
	Char,
	Jump,
	Choice,
	Call,
	Commit,
	Return,
	Fail,
	Set,
	Any,
	PartialCommit,
	Span,
	BackCommit,
	FailTwice,
	Empty,
	TestChar,
	TestCharNoChoice,
	TestSet,
	TestSetNoChoice,
	TestAny,
	End,
	Nop,
	MemoOpen,
	MemoClose,
	MemoTreeOpen,
	MemoTreeInsert,
	MemoTree,
	MemoTreeClose,
	CaptureBegin,
	CaptureLate,
	CaptureEnd,
	CaptureFull,
	CheckBegin,
	CheckEnd,
	Error,
	OpenCall,
}

Program :: [dynamic]Instruction
ProgramSlice :: []Instruction

is_jmp_type :: proc(i: Instruction) -> bool {
	#partial switch t in i {
	case Jump, Choice, Call, Commit, PartialCommit, BackCommit, TestChar, TestCharNoChoice, TestSet, TestSetNoChoice, TestAny, MemoOpen, MemoTreeOpen:
		return true
	}
	return false
}

// Label is used for marking a location in the instruction code with
// a unique ID
Label :: struct {
	id: int,
}

// NewLabel returns a new label with a unique ID
new_label :: proc() -> Label {
	uniqId += 1
	return Label{uniqId}
}

// Char consumes the next byte of the subject if it matches Byte and
// fails otherwise.
Char :: struct {
	byte: rune,
}

// Jump jumps to Lbl.
Jump :: struct {
	lbl: Label,
}

// Choice pushes Lbl to the stack and if there is a failure the label will
// be popped from the stack and jumped to.
Choice :: struct {
	lbl: Label,
}

// Call pushes the next instruction to the stack as a return address and jumps
// to Lbl.
Call :: struct {
	lbl: Label,
}

// Commit jumps to Lbl and removes the top entry from the stack
Commit :: struct {
	lbl: Label,
}

// Return pops a return address off the stack and jumps to it.
Return :: struct {}

// Fail causes the instruction pointer to go to the fail state.
Fail :: struct {}

// Set consumes the next byte of input if it is in the set of chars defined
// by bits.
Set :: struct {
	chars: ^charset.Set,
}

// Any consumes the next N bytes and fails if that is not possible.
Any :: struct {
	n: int,
}

// PartialCommit modifies the backtrack entry on the top of the stack to
// point to the current subject offset, and jumps to Lbl.
PartialCommit :: struct {
	lbl: Label,
}

// Span consumes zero or more bytes in the set bits. This instruction
// never fails.
Span :: struct {
	chars: ^charset.Set,
}

// BackCommit pops a backtrack entry off the stack, goes to the subject
// position in the entry, and jumps to Lbl.
BackCommit :: struct {
	lbl: Label,
}

// FailTwice pops an entry off the stack and sets the instruction pointer to
// the fail state.
FailTwice :: struct {}

// Empty makes a zero-width assertion according to the Op option. We use the
// same zero-width assertions that are supported by Go's regexp package.
Empty :: struct {
	op: EmptyOp,
}

// TestChar consumes the next byte if it matches Byte and jumps to Lbl
// otherwise. If the consumption is possible, a backtrack entry referring
// to Lbl and the subject position from before consumption is pushed to the
// stack.
TestChar :: struct {
	byte: rune,
	lbl:  Label,
}

// TestCharNoChoice consumes the next byte if it matches Byte and jumps to Lbl
// otherwise. No backtrack entry is pushed to the stack.
TestCharNoChoice :: struct {
	byte: rune,
	lbl:  Label,
}

// TestSet consumes the next byte if it is in the set Chars and jumps to
// Lbl otherwise. If the consumption is possible, a backtrack entry referring
// to Lbl and the subject position from before consumption is pushed to the
// stack.
TestSet :: struct {
	chars: charset.Set,
	lbl:   Label,
}

// TestSetNoChoice is the same as TestSet but no backtrack entry is pushed to
// the stack.
TestSetNoChoice :: struct {
	chars: charset.Set,
	lbl:   Label,
}

// TestAny consumes the next N bytes and jumps to Lbl if that is not possible.
// If the consumption is possible, a backtrack entry referring to Lbl and
// the subject position from before consumption is pushed to the stack.
TestAny :: struct {
	n:   int,
	lbl: Label,
}

// End immediately completes the pattern as a match.
End :: struct {
	fail: bool,
}

// Nop does nothing.
Nop :: struct {}

// MemoOpen begins a memo entry at this position. It marks the pattern that is
// being memoized with a unique ID for that pattern, and stores a label to
// jump to if the pattern is found in the memoization table.
MemoOpen :: struct {
	lbl: Label,
	id:  int,
}

// MemoClose completes a memoization entry and adds the entry into the memo
// table if it meets certain conditions (size, or other heuristics).
MemoClose :: struct {}

// MemoTreeOpen starts a memoization tree repetition routine.
MemoTreeOpen :: struct {
	lbl: Label,
	id:  int,
}

// MemoTreeInsert performs insertion into the memoization table for the tree
// memoization strategy.
MemoTreeInsert :: struct {}

// MemoTree "tree-ifies" the current memoization entries on the stack.
MemoTree :: struct {}

// MemoTreeClose completes the tree memoization routine.
MemoTreeClose :: struct {
	id: int,
}

// CaptureBegin begins capturing the given ID.
CaptureBegin :: struct {
	id: int,
}

// CaptureLate begins capturing the given ID at the current subject position
// minus Back.
CaptureLate :: struct {
	back: rune,
	id:   int,
}

// CaptureEnd completes an active capture.
CaptureEnd :: struct {
	id: int,
}

// CaptureFull begins a capture for the given ID at the current subject
// position minus Back, and immediately completes the capture. This is
// equivalent to CaptureLate Back ID; CaptureEnd.
CaptureFull :: struct {
	back: rune,
	id:   int,
}

// CheckBegin marks the beginning position for a checker.
CheckBegin :: struct {
	id:   int,
	flag: int,
}

// CheckEnd records the end position of a checker and applies the checker to
// determine if the match should fail.
CheckEnd :: struct {
	checker: Checker,
}


// Error logs an error message at the current position.
Error :: struct {
	message: string,
}

// OpenCall is a dummy instruction for resolving recursive function calls in
// grammars.
OpenCall :: struct {
	// Nop
	name: string,
}

string_from_label :: proc(i: Label) -> string {
	return fmt.sbprintf(&strings.Builder{}, "L%v", i.id)
}

string_from_char :: proc(i: Char) -> string {
	return fmt.sbprintf(&strings.Builder{}, "Char %v", i.byte)
}

string_from_jump :: proc(i: Jump) -> string {
	return fmt.sbprintf(&strings.Builder{}, "Jump %v", i.lbl)
}

string_from_choice :: proc(i: Choice) -> string {
	return fmt.sbprintf(&strings.Builder{}, "Choice %v", i.lbl)
}

string_from_call :: proc(i: Call) -> string {
	return fmt.sbprintf(&strings.Builder{}, "Call %v", i.lbl)
}

string_from_commit :: proc(i: Commit) -> string {
	return fmt.sbprintf(&strings.Builder{}, "Commit %v", i.lbl)
}

string_from_return :: proc(i: Return) -> string {
	return "Return"
}

string_from_fail :: proc(i: Fail) -> string {
	return "Fail"
}

string_from_set :: proc(i: Set) -> string {
	return fmt.sbprintf(&strings.Builder{}, "Set %v", i.chars)
}

string_from_any :: proc(i: Any) -> string {
	return fmt.sbprintf(&strings.Builder{}, "Any %v", i.n)
}

string_from_partial_commit :: proc(i: PartialCommit) -> string {
	return fmt.sbprintf(&strings.Builder{}, "PartialCommit %v", i.lbl)
}

string_from_span :: proc(i: Span) -> string {
	return fmt.sbprintf(&strings.Builder{}, "Span %v", i.chars)
}

string_from_back_commit :: proc(i: BackCommit) -> string {
	return fmt.sbprintf(&strings.Builder{}, "BackCommit %v", i)
}

string_from_fail_twice :: proc(i: FailTwice) -> string {
	return "FailTwice"
}

string_from_test_char :: proc(i: TestChar) -> string {
	return fmt.sbprintf(&strings.Builder{}, "TestChar %v %v", i.byte, i.lbl)
}

string_from_test_char_no_choice :: proc(i: TestCharNoChoice) -> string {
	return fmt.sbprintf(
		&strings.Builder{},
		"TestCharNoChoice %v %v",
		i.byte,
		i.lbl,
	)
}

string_from_test_set :: proc(i: TestSet) -> string {
	return fmt.sbprintf(&strings.Builder{}, "TestSet %v %v", i.chars, i.lbl)
}

string_from_test_set_no_choice :: proc(i: TestSetNoChoice) -> string {
	return fmt.sbprintf(
		&strings.Builder{},
		"TestSetNoChoice %v %v",
		i.chars,
		i.lbl,
	)
}

string_from_test_any :: proc(i: TestAny) -> string {
	return fmt.sbprintf(&strings.Builder{}, "TestAny %v %v", i.n, i.lbl)
}

string_from_end :: proc(i: End) -> string {
	if i.fail {
		return "End Fail"
	}
	return "End Success"
}

string_from_nop :: proc(i: Nop) -> string {
	return "Nop"
}

string_from_check_begin :: proc(i: CheckBegin) -> string {
	return "CheckBegin"
}

string_from_check_end :: proc(i: CheckEnd) -> string {
	return fmt.sbprintf(&strings.Builder{}, "CheckEnd %v", i)
}

string_from_memo_open :: proc(i: MemoOpen) -> string {
	return fmt.sbprintf(&strings.Builder{}, "MemoOpen %v %v", i.lbl, i.id)
}

string_from_memo_close :: proc(i: MemoClose) -> string {
	return "MemoClose"
}

string_from_memo_tree_open :: proc(i: MemoTreeOpen) -> string {
	return fmt.sbprintf(&strings.Builder{}, "MemoTreeOpen %v %v", i.lbl, i.id)
}

string_from_memo_tree_insert :: proc(i: MemoTreeInsert) -> string {
	return "MemoTreeInsert"
}

string_from_memo_tree :: proc(i: MemoTree) -> string {
	return "MemoTree"
}

string_from_memo_tree_close :: proc(i: MemoTreeClose) -> string {
	return fmt.sbprintf(&strings.Builder{}, "MemoTreeClose %v", i.id)
}

string_from_capture_begin :: proc(i: CaptureBegin) -> string {
	return fmt.sbprintf(&strings.Builder{}, "CaptureBegin %v", i.id)
}

string_from_capture_late :: proc(i: CaptureLate) -> string {
	return fmt.sbprintf(&strings.Builder{}, "CaptureLate %v %v", i.back, i.id)
}

string_from_capture_end :: proc(i: CaptureEnd) -> string {
	return "Capture end"
}

string_from_capture_full :: proc(i: CaptureFull) -> string {
	return fmt.sbprintf(&strings.Builder{}, "CaptureFull %v %v", i.back, i.id)
}

string_from_error :: proc(i: Error) -> string {
	return fmt.sbprintf(&strings.Builder{}, "CaptureFull %s", i.message)
}

string_from_empty :: proc(i: Empty) -> string {
	return "Empty"
}

string_from_open_call :: proc(i: OpenCall) -> string {
	return fmt.sbprintf(&strings.Builder{}, "OpenCall %v", i.name)
}

// String returns the string representation of the program.
string_from_program :: proc(p: []Instruction) -> string {
	s: string
	last: Instruction
	for inst in p {
		#partial switch t in inst {
		case Nop:
			continue
		case Label:
			_, ok := last.(Label);if ok {
				s = strings.concatenate(
					{
						s,
						fmt.sbprintf(
							&strings.Builder{},
							"\n%v:",
							to_string(t),
						),
					},
				)
			} else {
				s = strings.concatenate(
					{s, fmt.sbprintf(&strings.Builder{}, "%v:", to_string(t))},
				)
			}
		case Char:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case Jump:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case Choice:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case Call:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case Commit:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case Return:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case Fail:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case Set:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case Any:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case PartialCommit:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case Span:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case BackCommit:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case FailTwice:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case TestChar:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case TestCharNoChoice:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case TestSet:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case TestSetNoChoice:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case TestAny:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case End:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case CheckBegin:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case CheckEnd:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case MemoOpen:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case MemoClose:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case MemoTreeOpen:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case MemoTreeInsert:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case MemoTree:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case MemoTreeClose:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case CaptureBegin:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case CaptureLate:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case CaptureEnd:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case CaptureFull:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case Error:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		case Empty:
			s = strings.concatenate(
				{s, fmt.sbprintf(&strings.Builder{}, "\t%v\n", to_string(t))},
			)
		}
		last = inst
	}
	s = strings.concatenate({s, "\n"})
	return s
}

to_string :: proc {
	string_from_label,
	string_from_char,
	string_from_jump,
	string_from_choice,
	string_from_call,
	string_from_commit,
	string_from_return,
	string_from_fail,
	string_from_set,
	string_from_any,
	string_from_partial_commit,
	string_from_span,
	string_from_back_commit,
	string_from_fail_twice,
	string_from_test_char,
	string_from_test_char_no_choice,
	string_from_test_set,
	string_from_test_set_no_choice,
	string_from_test_any,
	string_from_end,
	string_from_nop,
	string_from_check_begin,
	string_from_check_end,
	string_from_memo_open,
	string_from_memo_close,
	string_from_memo_tree_open,
	string_from_memo_tree_insert,
	string_from_memo_tree,
	string_from_memo_tree_close,
	string_from_capture_begin,
	string_from_capture_late,
	string_from_capture_end,
	string_from_capture_full,
	string_from_error,
	string_from_empty,
	string_from_program,
}
