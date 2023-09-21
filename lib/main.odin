package pegasus

import "log"

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
