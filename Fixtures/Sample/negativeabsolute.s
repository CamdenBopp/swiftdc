// A negative symbol offset. `_immortal` is N_ABS with bit 63 set, like
// `_swiftImmortalRefCount` in libswiftCore, so MachOKit's `Symbol.offset` is
// negative. `_first` and `_second` share an address, which is what sends a
// disassembly through `witnessTables`.
.section __TEXT,__text,regular,pure_instructions
.globl _first
.globl _second
.p2align 2
_first:
_second:
  mov w0, #7
  ret
.globl _immortal
_immortal = 0x8000000000000000
// A constant named as a witness table, so that loop meets a negative offset too.
.globl "_$sSiSHsWP"
"_$sSiSHsWP" = 0x8000000000000001
