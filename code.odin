package pegasus

import "charset"
import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:testing"

// Code is the representation of VM bytecode.
Code :: struct {
	// list of charsets
	sets:     [dynamic]charset.Set,
	// list of error messages
	errors:   [dynamic]string,
	// list of checker functions
	checkers: [dynamic]Checker,
	// the encoded instructions
	insns:    [dynamic]byte,
}


// Size returns the size of the encoded instructions.
code_size :: proc(c: ^Code) -> int {
	return len(c.insns)
}

/* No idea how this works have to still figure it out
func init() {
	gob.Register(MapChecker{})
	gob.Register(BackReference{})
}
*/

// Encode transforms a program into VM bytecode.
encode :: proc(insns: Program) -> Code {
	code := Code {
		sets     = make([dynamic]charset.Set),
		errors   = make([dynamic]string),
		checkers = make([dynamic]Checker),
		insns    = make([dynamic]byte),
	}

	bcount: uint
	labels := make(map[Label]uint)
	for insn in insns {
		#partial switch t in insn {
		case Nop:
			continue
		case Label:
			labels[t] = bcount
			continue
		case:
			bcount += instruction_size(insn)
		}
	}

	for insn in insns {
		op: Opcode
		args: []byte
		#partial switch t in insn {
		case Label, Nop:
			continue
		case Char:
			op = .Char
			args = []byte{byte(t.byte)}
		case Jump:
			op = .Jump
			args = encodeLabel(labels[t.lbl])
		case Choice:
			op = .Choice
			args = encodeLabel(labels[t.lbl])
		case Call:
			op = .Call
			args = encodeLabel(labels[t.lbl])
		case Commit:
			op = .Commit
			args = encodeLabel(labels[t.lbl])
		case Return:
			op = .Return
		case Fail:
			op = .Fail
		case Set:
			op = .Set
			args = encodeU8(addSet(&code, t.chars^))
		case Any:
			op = .Any
			args = []byte{byte(t.n)}
		case PartialCommit:
			op = .PartialCommit
			args = encodeLabel(labels[t.lbl])
		case Span:
			op = .Span
			args = encodeU8(addSet(&code, t.chars^))
		case BackCommit:
			op = .BackCommit
			args = encodeLabel(labels[t.lbl])
		case FailTwice:
			op = .FailTwice
		case Empty:
			op = .Empty
			args = []byte{}
		case TestChar:
			op = .TestChar
			b := make([dynamic]byte, len(encodeLabel(labels[t.lbl])) + 1)
			append(&b, byte(t.byte))
			append(&b, ..encodeLabel(labels[t.lbl]))
			args = b[:]
		case TestCharNoChoice:
			op = .TestCharNoChoice
			b := make([dynamic]byte, len(encodeLabel(labels[t.lbl])) + 1)
			append(&b, byte(t.byte))
			append(&b, ..encodeLabel(labels[t.lbl]))
			args = b[:]
		case TestSet:
			op = .TestSet
			b := slice.to_dynamic(encodeU8(addSet(&code, t.chars)))
			append(&b, ..encodeLabel(labels[t.lbl]))
			args = b[:]
		case TestSetNoChoice:
			op = .TestSetNoChoice
			b := slice.to_dynamic(encodeU8(addSet(&code, t.chars)))
			append(&b, ..encodeLabel(labels[t.lbl]))
			args = b[:]
		case TestAny:
			op = .TestAny
			b := make([dynamic]byte, len(encodeLabel(labels[t.lbl])) + 1)
			append(&b, byte(t.n))
			append(&b, ..encodeLabel(labels[t.lbl]))

			args = b[:]
		case CaptureBegin:
			op = .CaptureBegin
			args = encodeI16(int(t.id))
		case CaptureEnd:
			op = .CaptureEnd
		case CaptureLate:
			op = .CaptureLate
			b := make([dynamic]byte, len(encodeI16(int(t.id))) + 1)
			append(&b, byte(t.back))
			append(&b, ..encodeI16(int(t.id)))

			args = b[:]
		case CaptureFull:
			op = .CaptureFull
			b := make([dynamic]byte, len(encodeI16(int(t.id))) + 1)
			append(&b, byte(t.back))
			append(&b, ..encodeI16(int(t.id)))

			args = b[:]
		case MemoOpen:
			op = .MemoOpen
			b := slice.to_dynamic(encodeLabel(labels[t.lbl]))
			append(&b, ..encodeI16(t.id))

			args = b[:]
		case MemoClose:
			op = .MemoClose
		case MemoTreeOpen:
			op = .MemoTreeOpen
			b := make(
				[dynamic]byte,
				len(encodeLabel(labels[t.lbl])) + len(encodeI16(t.id)),
			)
			append(&b, ..encodeLabel(labels[t.lbl]))
			append(&b, ..encodeI16(t.id))

			args = b[:]
		case MemoTreeInsert:
			op = .MemoTreeInsert
		case MemoTree:
			op = .MemoTree
		case MemoTreeClose:
			op = .MemoTreeClose
			args = encodeI16(int(t.id))
		case CheckBegin:
			op = .CheckBegin
			b := make(
				[dynamic]byte,
				len(encodeI16(t.flag)) + len(encodeI16(t.id)),
			)
			append(&b, ..encodeI16(t.flag))
			append(&b, ..encodeI16(t.id))

			args = b[:]
		case CheckEnd:
			op = .CheckEnd
			args = encodeU24(addChecker(&code, t.checker))
		case Error:
			op = .Error
			args = encodeU24(addError(&code, t.message))
		case End:
			op = .End
			args = encodeBool(t.fail)
		case:
			panic(
				fmt.sbprintf(
					&strings.Builder{},
					"invalid instruction during encoding: %v",
					t,
				),
			)
		}
		append(&code.insns, byte(op))

		// need padding to align the args if they are divisible by 16 bits
		if len(args) % 2 == 0 {
			append(&code.insns, 0)
		}

		append(&code.insns, ..args)
	}

	append(&code.insns, byte(Opcode.End), 0)

	return code
}

encodeU8 :: proc(x: uint) -> []byte {
	if x >= 256 {
		panic("U8 out of bounds")
	}

	b := make([]byte, 1)
	b[0] = byte(x)
	return b
}

encodeI8 :: proc(x: int) -> []byte {
	if x < -128 || x >= 128 {
		panic("I8 out of bounds")
	}

	b := make([]byte, 1)
	b[0] = byte(x)
	return b
}

encodeU16 :: proc(x: uint) -> []byte {
	if x >= (1 << 16) {
		panic("U16 out of bounds")
	}
	b := make([]byte, 2)
	b[0] = byte(u16(x))
	b[1] = byte(u16(x) >> 8)
	return b
}

encodeI16 :: proc(x: int) -> []byte {
	if x < -(1 << 15) || x >= (1 << 15) {
		panic("I16 out of bounds")
	}

	b := make([]byte, 2)
	b[0] = byte(u16(x))
	b[1] = byte(u16(x) >> 8)
	return b
}

encodeU24 :: proc(x: uint) -> []byte {
	if x >= (1 << 24) {
		panic("I24 out of bounds")
	}

	b := make([]byte, 4)
	i1 := u16((x >> 16) & 0xff)
	i2 := u16(x)
	b[0] = byte(i1 >> 8)
	b[1] = byte(i1)
	b[2] = byte(i2)
	b[3] = byte(i2 >> 8)

	return b[1:4]
}

encodeLabel :: proc(x: uint) -> []byte {
	return encodeU24(x)
}

encodeBool :: proc(x: bool) -> []byte {
	b := make([]byte, 1)
	if x {
		b[0] = 1
		return b
	}
	b[0] = 0
	return b
}

// Adds the set to the code's list of charsets, and returns the index it was
// added at. If there are duplicate charsets, this may not actually insert
// the new charset.
addSet :: proc(code: ^Code, cset: charset.Set) -> uint {
	for s, i in code.sets {
		if cset == s {
			return uint(i)
		}
	}

	append(&code.sets, cset)

	return uint(len(code.sets) - 1)
}

addError :: proc(code: ^Code, msg: string) -> uint {
	for s, i in code.errors {
		if msg == s {
			return uint(i)
		}
	}

	append(&code.errors, msg)

	return uint(len(code.errors) - 1)
}

addChecker :: proc(code: ^Code, checker: Checker) -> uint {
	append(&code.checkers, checker)

	return uint(len(code.checkers) - 1)
}

@(test)
test_json :: proc(t: ^testing.T) {
	p := grammar(
		"Expr",
		map[string]Pattern{
			"Expr" = concat(
				non_term("Factor"),
				star(
					concat(
						set(charset.new_charset([]byte{'+', '-'})),
						non_term("Factor"),
					),
				),
			),
			"Factor" = concat(
				non_term("Term"),
				star(
					concat(
						set(charset.new_charset([]byte{'*', '/'})),
						non_term("Term"),
					),
				),
			),
			"Term" = or(
				non_term("Number"),
				concat(concat(literal("("), non_term("Expr")), literal(")")),
			),
			"Number" = plus(set(charset.range('0', '9'))),
		},
	)

	code := encode(must_compile(p))
	b, err1 := json.marshal(code)
	testing.expect(t, err1 == nil, "Failed to parse to json the struct")

	json_code := new(Code)
	err2 := json.unmarshal(b, json_code)
	testing.expect(t, err2 == nil, "Failed to parse from json the bytes")

	testing.expect(
		t,
		size_of(json_code^) == size_of(code),
		"Saved and loaded code not equivalent",
	)

	for _, i in code.insns {
		testing.expect(
			t,
			json_code.insns[i] == code.insns[i],
			fmt.sbprintf(&strings.Builder{}, "Code byte %d does not match", i),
		)
	}
}
