package pegasus

import "core:flags"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:terminal"
import "memo"
import log "log"

Args :: struct {
	grammar: string `args:"pos=0,required" usage:"Path to .peg grammar file."`,
	input:   string `args:"pos=1" usage:"Input string to parse."`,
	file:    string `args:"name=file" usage:"Read input from file."`,
	quiet:   bool   `args:"name=quiet" usage:"Suppress output, only set exit code."`,
}

main :: proc() {
	args: Args
	flags.parse_or_exit(&args, os.args, .Unix)

	// Read grammar file.
	gram_bytes, gram_err := os.read_entire_file_from_path(args.grammar, context.allocator)
	if gram_err != nil {
		fmt.eprintfln("cannot read grammar file: %s", args.grammar)
		os.exit(2)
	}
	gram := string(gram_bytes)

	// Resolve input: positional arg > --file flag > stdin pipe.
	input: string
	if args.input != "" {
		input = args.input
	} else if args.file != "" {
		in_bytes, in_err := os.read_entire_file_from_path(args.file, context.allocator)
		if in_err != nil {
			fmt.eprintfln("cannot read input file: %s", args.file)
			os.exit(2)
		}
		input = string(in_bytes)
	} else if !terminal.is_terminal(os.stdin) {
		input = read_stdin()
	} else {
		fmt.eprintfln("no input provided (pass as argument, --file, or pipe to stdin)")
		os.exit(2)
	}

	// Run the parser.
	ok, pos, capt, errs := match(gram, input)
	names := get_capture_names()

	if len(errs) > 0 {
		if !args.quiet {
			for e in errs {
				fmt.eprintfln("grammar error: %s", e.message)
			}
		}
		os.exit(2)
	}

	total := len(input)
	if ok {
		if !args.quiet {
			log.success(fmt.tprintf("matched %d/%d characters", pos, total))
			print_captures(capt, input, names)
		}
		os.exit(0)
	} else {
		if !args.quiet {
			log.error(fmt.tprintf("no match — consumed %d/%d characters", pos, total))
		}
		os.exit(1)
	}
}

// print_captures prints the capture tree as an indented visualization.
// Dummy nodes are skipped — their children are promoted to the parent level.
print_captures :: proc(root: ^memo.Capture, subject: string, names: map[int]string) {
	if root == nil {
		return
	}

	// Collect logical children (flattening Dummies).
	children := collect_children(root)
	if len(children) == 0 {
		return
	}

	fmt.println()
	fmt.println("Capture Tree:")
	for child, i in children {
		last := i == len(children) - 1
		print_node(child, subject, "", last, names)
	}
}

// print_node recursively prints a capture node with tree-drawing characters.
// Single-child chains with the same span are collapsed to reduce noise.
// If the capture ID is found in names, the rule name is prepended.
print_node :: proc(c: ^memo.Capture, subject: string, prefix: string, last: bool, names: map[int]string) {
	if c == nil {
		return
	}

	// Collapse single-child chains with the same span.
	node := c
	for {
		children := collect_children(node)
		if len(children) != 1 {
			break
		}
		child := children[0]
		if memo.capture_start(child) != memo.capture_start(node) || memo.capture_end(child) != memo.capture_end(node) {
			break
		}
		node = child
	}

	// Tree connector.
	connector := last ? "└── " : "├── "

	start := memo.capture_start(node)
	end := memo.capture_end(node)

	// Extract matched text, truncate if too long.
	text := ""
	if start >= 0 && end <= len(subject) && start < end {
		raw := subject[start:end]
		if len(raw) > 60 {
			text = fmt.tprintf("\"%.57s...\"", raw)
		} else {
			// Escape newlines/tabs for display.
			text = fmt.tprintf("\"%s\"", escape_for_display(raw))
		}
	}

	// Look up rule name for this capture ID.
	label := ""
	name, has_name := names[int(node.id)]
	if has_name {
		label = fmt.tprintf("%s ", name)
	}

	fmt.printfln("%s%s%s[%d:%d] %s", prefix, connector, label, start, end, text)

	// Recurse into children.
	children := collect_children(node)
	child_prefix := last ? fmt.tprintf("%s    ", prefix) : fmt.tprintf("%s│   ", prefix)
	for child, i in children {
		child_last := i == len(children) - 1
		print_node(child, subject, child_prefix, child_last, names)
	}
}

// collect_children returns the logical children of a capture, flattening Dummy nodes.
collect_children :: proc(c: ^memo.Capture) -> []^memo.Capture {
	if c == nil || len(c.children) == 0 {
		return nil
	}

	result: [dynamic]^memo.Capture
	for child in c.children {
		if child.typ == .Dummy {
			// Flatten: promote dummy's children.
			inner := collect_children(child)
			append(&result, ..inner)
		} else {
			append(&result, child)
		}
	}
	return result[:]
}

// escape_for_display replaces control characters with visible representations.
escape_for_display :: proc(s: string) -> string {
	buf := strings.builder_make()
	for ch in s {
		switch ch {
		case '\n':
			strings.write_string(&buf, "\\n")
		case '\r':
			strings.write_string(&buf, "\\r")
		case '\t':
			strings.write_string(&buf, "\\t")
		case:
			strings.write_rune(&buf, ch)
		}
	}
	return strings.to_string(buf)
}

// read_stdin reads all bytes from stdin using chunked reads.
// os.read_entire_file won't work for pipes (no file_size).
read_stdin :: proc() -> string {
	buf: [dynamic]u8
	chunk: [4096]u8
	for {
		n, err := os.read(os.stdin, chunk[:])
		if n > 0 {
			append(&buf, ..chunk[:n])
		}
		if err != nil || n == 0 {
			break
		}
	}
	return string(buf[:])
}
