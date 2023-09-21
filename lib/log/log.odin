package log

import "core:fmt"
import "core:strings"

RED :: "\e[1;31m%v\e[0m"
GREEN :: "\e[1;32m%v\e[0m"
YELLOW :: "\e[1;33m%v\e[0m"
BLUE :: "\e[1;34m%v\e[0m"

LogLevel :: enum {
	Error,
	Info,
	Success,
	Warning,
}

format := map[LogLevel]string {
	.Error   = RED,
	.Success = GREEN,
	.Warning = YELLOW,
	.Info    = BLUE,
}

color :: proc(msg: string, lvl: LogLevel) -> string {
	return fmt.sbprintf(&strings.Builder{}, format[lvl], msg)
}

info :: proc(args: ..any) {
	fmt.print(color("INFO: ", .Info))
	fmt.println(..args)
}

success :: proc(args: ..any) {
	fmt.print(color("SUCCESS: ", .Success))
	fmt.println(..args)
}

error :: proc(args: ..any) {
	fmt.print(color("ERROR: ", .Error))
	fmt.println(..args)
}

warning :: proc(args: ..any) {
	fmt.print(color("WARNING: ", .Warning))
	fmt.println(..args)
}
