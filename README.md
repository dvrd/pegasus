# Pegasus

Pegasus is a PEG parser for Odin, it's meant to be very efficient for parsing DSLs or prototyping a language.

If you want to make use of it I recommend getting aquainted with `PEG` small grammar language
[here](https://www.gnu.org/software/guile/manual/html_node/PEG-Syntax-Reference.html).


Here is a simple example that you can find in `lib/main.odin`:
```odin
import "shared:pegasus" // I usually have a hardlink to the library in Odin's `shared` folder

main :: proc() {
	grammar := `
Expr   		<- Space SubOp 

SubOp			<- AddOp (Sub AddOp)* { Numeral }
AddOp			<- DivOp (Add DivOp)*
DivOp			<- MulOp (Div MulOp)*
MulOp			<- PowOp (Mul PowOp)*
PowOp			<- Term (Pow Term)*
Term   		<- Atom / OParen Expr CParen

Pow				<- '^' Space
Mul				<- '*' Space
Div				<- '/' Space
Add				<- '+' Space
Sub				<- '-' Space

OParen 		<- '(' Space
CParen 		<- ')' Space

Atom			<- Numeral

Numeral 	<- Number Space
Number  	<- [0-9]+
Space   	<- (' ' / '\t' / EndOfLine)*
EndOfLine <- '\r\n' / '\n' / '\r'
EndOfFile <- !.
	`
	subject := "23 + 2 +(1* 2) ^ 2"
	is_match, pos, captures, _ := match(grammar, subject)
	if is_match {
		log.success("matched til position", pos, "|", subject[:pos])
		log.info(captures)
	} else {
		log.error("matched til position", pos, "|", subject[:pos])
	}
}
```


### In Progress

**TODO:**
- [x] Implement Pattern logic
- [x] Implement Memoization Tree
- [x] Implement Input abstraction
- [x] Implement Charset abstraction
- [x] Implement VM
- [x] Fix encoding issues
- [x] Get regex based syntax for parsing `.peg`
- [ ] Improve Charset abstraction using Odin `bit_set`
- [x] Fix issue with re not compiling string grammars
- [ ] Create examples for the library
- [x] Add API to parse specific grammars
- [ ] Add a CLI to interface with the grammars to parse
- [ ] Figure out captures

