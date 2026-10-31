// A Go program as Go's internal linker lays it out: no LC_FUNCTION_STARTS,
// and with -ldflags=-s no symbol table, so __gopclntab (the table the Go
// runtime reads to print a stack trace) is the only record of where its
// functions begin. True behaviour: main.main calls main.scale and main.mix;
// scale returns x * 3; mix returns a*7 - b.
package main

import "os"

//go:noinline
func scale(x int) int { return x * 3 }

//go:noinline
func mix(a, b int) int { return a*7 - b }

func main() { os.Exit(scale(len(os.Args)) + mix(len(os.Args), 2)) }
