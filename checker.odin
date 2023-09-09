package pegasus

import "core:io"

// A Checker is used so the user can perform additional custom validation of
// parse results. For example, you might want to parse only 8-bit integers by
// matching [0-9]+ and then using a checker to ensure the matched integer is in
// the range 0-256.

MapChecker :: map[string]struct {}

new_map_checker :: proc(strs: []string) -> MapChecker {
	m := make(map[string]struct {})
	for s in strs {
		m[s] = struct {}{}
	}
	return m
}

map_checker_check :: proc(m: ^MapChecker, b: []byte, src: ^Input, id: int, flag: RefKind) -> int {
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

back_reference_new :: proc() -> BackReference {
	return BackReference{make(map[int]string)}
}

back_reference_check :: proc(
	r: ^BackReference,
	b: []byte,
	src: ^Input,
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
		n, _ := io.read_at(src.r, buf, i64(input_pos(src)))
		if n == len(buf) && string(buf) == back {
			return n
		}
		return -1
	}
	return 0
}
