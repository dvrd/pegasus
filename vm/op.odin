package vm

import inst "pegasus:instructions"

Opcode :: enum {
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
	CaptureBegin,
	CaptureLate,
	CaptureEnd,
	CaptureFull,
	CheckBegin,
	CheckEnd,
	MemoOpen,
	MemoClose,
	MemoTreeOpen,
	MemoTreeInsert,
	MemoTree,
	MemoTreeClose,
	Error,
}

// instruction sizes
szChar :: 2
szReturn :: 2
szFail :: 2
szSet :: 2
szAny :: 2
szSpan :: 2
szFailTwice :: 2
szEnd :: 2
szNop :: 0
szEmpty :: 2
szCaptureBegin :: 4
szCaptureLate :: 4
szCaptureEnd :: 2
szCaptureFull :: 4
szMemoClose :: 2
szMemoTreeInsert :: 2
szMemoTree :: 2
szMemoTreeClose :: 4
szCheckBegin :: 6
szCheckEnd :: 4
szError :: 4

// jumps
szJump :: 4
szChoice :: 4
szCall :: 4
szCommit :: 4
szPartialCommit :: 4
szBackCommit :: 4
szTestChar :: 6
szTestCharNoChoice :: 6
szTestSet :: 6
szTestSetNoChoice :: 6
szTestAny :: 6
szMemoOpen :: 6
szMemoTreeOpen :: 6

// returns the size in bytes of the encoded version of this instruction
instruction_size :: proc(i: inst.Instruction) -> uint {
	sz: uint
	#partial switch t in i {
	case inst.Label, inst.Nop:
		return 0
	case inst.JumpType, inst.CheckBegin:
		sz += 4
	case:
		sz += 2
	}

	// handle instructions with extra args
	#partial switch t in i {
	case inst.MemoOpen, inst.MemoTreeOpen, inst.MemoTreeClose, inst.CaptureBegin, inst.CaptureLate, inst.CaptureFull, inst.TestChar, inst.TestCharNoChoice, inst.TestSet, inst.TestSetNoChoice, inst.TestAny, inst.Error, inst.CheckBegin, inst.CheckEnd:
		sz += 2
	}

	return sz
}
