package instructions

import "core:strings"
import "pegasus:input"

// A Checker is used so the user can perform additional custom validation of
// parse results. For example, you might want to parse only 8-bit integers by
// matching [0-9]+ and then using a checker to ensure the matched integer is in
// the range 0-256.
Checker :: union {
	BackReference,
	MapChecker,
}

MapChecker :: map[string]struct {}

new_map_checker :: proc(strs: []string) -> MapChecker {
	m := make(map[string]struct {})
	for s in strs {
		m[s] = struct {}{}
	}
	return m
}

check_map_checker :: proc(
	m: ^MapChecker,
	b: []byte,
	src: ^input.Input,
	id: int,
	flag: RefKind,
) -> int {
	_, ok := m[string(b)];if ok {
		return 0
	}
	return -1
}

BackReference :: struct {
	symbols: map[int]string,
}

RefKind :: enum {
	RefDef,
	RefUse,
	RefBlock,
}

new_back_reference :: proc() -> BackReference {
	return BackReference{make(map[int]string)}
}

check_back_reference :: proc(
	r: ^BackReference,
	b: []byte,
	src: ^input.Input,
	id: int,
	flag: RefKind,
) -> int {
	#partial switch flag {
	case .RefDef:
		r.symbols[id] = string(b)
		return 0
	case .RefUse:
		back := r.symbols[id]
		buf := make([]byte, len(back))
		n, _ := strings.reader_read_at(&src.r, buf, i64(input.pos(src)))
		if n == len(buf) && string(buf) == back {
			return n
		}
		return -1
	}
	return 0
}

new_checker :: proc {
	new_map_checker,
	new_back_reference,
}

check :: proc {
	check_map_checker,
	check_back_reference,
}
