#+feature dynamic-literals
package pegasus

import "charset"
import "core:encoding/json"
import "core:fmt"
import "core:mem/virtual"
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
			buf: [1]byte = {byte(t.byte)}
			args = buf[:]
		case Jump:
			op = .Jump
			lbl := encodeLabel(labels[t.lbl])
			args = lbl[:]
		case Choice:
			op = .Choice
			lbl := encodeLabel(labels[t.lbl])
			args = lbl[:]
		case Call:
			op = .Call
			lbl := encodeLabel(labels[t.lbl])
			args = lbl[:]
		case Commit:
			op = .Commit
			lbl := encodeLabel(labels[t.lbl])
			args = lbl[:]
		case Return:
			op = .Return
		case Fail:
			op = .Fail
		case Set:
			op = .Set
			buf := encodeU8(addSet(&code, t.chars^))
			args = buf[:]
		case Any:
			op = .Any
			buf: [1]byte = {byte(t.n)}
			args = buf[:]
		case PartialCommit:
			op = .PartialCommit
			lbl := encodeLabel(labels[t.lbl])
			args = lbl[:]
		case Span:
			op = .Span
			buf := encodeU8(addSet(&code, t.chars^))
			args = buf[:]
		case BackCommit:
			op = .BackCommit
			lbl := encodeLabel(labels[t.lbl])
			args = lbl[:]
		case FailTwice:
			op = .FailTwice
		case Empty:
			op = .Empty
			buf: [1]byte = {u8(t.op)}
			args = buf[:]
		case TestChar:
			op = .TestChar
			lbl := encodeLabel(labels[t.lbl])
			buf: [4]byte = {byte(t.byte), lbl[0], lbl[1], lbl[2]}
			args = buf[:]
		case TestCharNoChoice:
			op = .TestCharNoChoice
			lbl := encodeLabel(labels[t.lbl])
			buf: [4]byte = {byte(t.byte), lbl[0], lbl[1], lbl[2]}
			args = buf[:]
		case TestSet:
			op = .TestSet
			set_buf := encodeU8(addSet(&code, t.chars))
			lbl := encodeLabel(labels[t.lbl])
			buf: [4]byte = {set_buf[0], lbl[0], lbl[1], lbl[2]}
			args = buf[:]
		case TestSetNoChoice:
			op = .TestSetNoChoice
			set_buf := encodeU8(addSet(&code, t.chars))
			lbl := encodeLabel(labels[t.lbl])
			buf: [4]byte = {set_buf[0], lbl[0], lbl[1], lbl[2]}
			args = buf[:]
		case TestAny:
			op = .TestAny
			lbl := encodeLabel(labels[t.lbl])
			buf: [4]byte = {byte(t.n), lbl[0], lbl[1], lbl[2]}
			args = buf[:]
		case CaptureBegin:
			op = .CaptureBegin
			buf := encodeI16(t.id)
			args = buf[:]
		case CaptureEnd:
			op = .CaptureEnd
		case CaptureLate:
			op = .CaptureLate
			id_buf := encodeI16(t.id)
			buf: [3]byte = {byte(t.back), id_buf[0], id_buf[1]}
			args = buf[:]
		case CaptureFull:
			op = .CaptureFull
			id_buf := encodeI16(int(t.id))
			buf: [3]byte = {byte(t.back), id_buf[0], id_buf[1]}
			args = buf[:]
		case MemoOpen:
			op = .MemoOpen
			lbl := encodeLabel(labels[t.lbl])
			id_buf := encodeI16(t.id)
			buf: [5]byte = {lbl[0], lbl[1], lbl[2], id_buf[0], id_buf[1]}
			args = buf[:]
		case MemoClose:
			op = .MemoClose
		case MemoTreeOpen:
			op = .MemoTreeOpen
			lbl := encodeLabel(labels[t.lbl])
			id_buf := encodeI16(t.id)
			buf: [5]byte = {lbl[0], lbl[1], lbl[2], id_buf[0], id_buf[1]}
			args = buf[:]
		case MemoTreeInsert:
			op = .MemoTreeInsert
		case MemoTree:
			op = .MemoTree
		case MemoTreeClose:
			op = .MemoTreeClose
			buf := encodeI16(int(t.id))
			args = buf[:]
		case CheckBegin:
			op = .CheckBegin
			flag_buf := encodeI16(t.flag)
			id_buf := encodeI16(t.id)
			buf: [4]byte = {flag_buf[0], flag_buf[1], id_buf[0], id_buf[1]}
			args = buf[:]
		case CheckEnd:
			op = .CheckEnd
			buf := encodeU24(addChecker(&code, t.checker))
			args = buf[:]
		case Error:
			op = .Error
			buf := encodeU24(addError(&code, t.message))
			args = buf[:]
		case End:
			op = .End
			buf := encodeBool(t.fail)
			args = buf[:]
		case:
			panic(
				fmt.tprintf("invalid instruction during encoding: %v", t),
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

encodeU8 :: proc(x: uint) -> [1]byte {
	if x >= 256 {
		panic("U8 out of bounds")
	}
	return [1]byte{byte(x)}
}

encodeI8 :: proc(x: int) -> [1]byte {
	if x < -128 || x >= 128 {
		panic("I8 out of bounds")
	}
	return [1]byte{byte(x)}
}

encodeU16 :: proc(x: uint) -> [2]byte {
	if x >= (1 << 16) {
		panic("U16 out of bounds")
	}
	return [2]byte{byte(u16(x)), byte(u16(x) >> 8)}
}

encodeI16 :: proc(x: int) -> [2]byte {
	if x < -(1 << 15) || x >= (1 << 15) {
		panic("I16 out of bounds")
	}
	return [2]byte{byte(u16(x)), byte(u16(x) >> 8)}
}

encodeU24 :: proc(x: uint) -> [3]byte {
	if x >= (1 << 24) {
		panic("I24 out of bounds")
	}
	i1 := u16((x >> 16) & 0xff)
	i2 := u16(x)
	return [3]byte{byte(i1), byte(i2), byte(i2 >> 8)}
}

encodeLabel :: proc(x: uint) -> [3]byte {
	return encodeU24(x)
}

encodeBool :: proc(x: bool) -> [1]byte {
	if x {
		return [1]byte{1}
	}
	return [1]byte{0}
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
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

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
			fmt.tprintf("Code byte %d does not match", i),
		)
	}
}

@(test)
test_encode_decode_round_trip :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Test encodeU8 / decodeU8
	buf_u8 := encodeU8(42)
	testing.expect(t, decodeU8(buf_u8[:]) == 42, fmt.tprintf("U8 round-trip failed: got %d", decodeU8(buf_u8[:])))

	buf_u8_zero := encodeU8(0)
	testing.expect(t, decodeU8(buf_u8_zero[:]) == 0, "U8 round-trip for 0 failed")

	buf_u8_max := encodeU8(255)
	testing.expect(t, decodeU8(buf_u8_max[:]) == 255, "U8 round-trip for 255 failed")

	// Test encodeI16 / decodeI16
	buf_i16 := encodeI16(1234)
	testing.expect(t, decodeI16(buf_i16[:]) == 1234, fmt.tprintf("I16 round-trip failed: got %d", decodeI16(buf_i16[:])))

	buf_i16_neg := encodeI16(-100)
	testing.expect(t, decodeI16(buf_i16_neg[:]) == -100, fmt.tprintf("I16 negative round-trip failed: got %d", decodeI16(buf_i16_neg[:])))

	buf_i16_zero := encodeI16(0)
	testing.expect(t, decodeI16(buf_i16_zero[:]) == 0, "I16 round-trip for 0 failed")

	// Test encodeU24 / decodeU24
	buf_u24 := encodeU24(100000)
	testing.expect(t, decodeU24(buf_u24[:]) == 100000, fmt.tprintf("U24 round-trip failed: got %d", decodeU24(buf_u24[:])))

	buf_u24_zero := encodeU24(0)
	testing.expect(t, decodeU24(buf_u24_zero[:]) == 0, "U24 round-trip for 0 failed")

	buf_u24_small := encodeU24(1)
	testing.expect(t, decodeU24(buf_u24_small[:]) == 1, "U24 round-trip for 1 failed")
}

@(test)
test_encode_full_program :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Compile a simple pattern and encode it
	p := literal("hello")
	prog := must_compile(p)
	code := encode(prog)

	// code_size should match actual byte length
	sz := code_size(&code)
	testing.expect(t, sz == len(code.insns), fmt.tprintf("code_size() = %d but len(insns) = %d", sz, len(code.insns)))

	// Should have at least some bytes (5 Char instructions + End + padding)
	testing.expect(t, sz > 0, "encoded program should have non-zero size")

	// First byte should be a valid opcode (Char = 0)
	testing.expect(t, code.insns[0] == byte(Opcode.Char), fmt.tprintf("first instruction should be Char (0), got %d", code.insns[0]))

	// Last two bytes should be End opcode + padding
	testing.expect(t, code.insns[sz - 2] == byte(Opcode.End), fmt.tprintf("second-to-last byte should be End opcode, got %d", code.insns[sz - 2]))
}
