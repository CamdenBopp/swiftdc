// Instructions a Cortex-A72 does not have and Apple code uses. Each
// function returns a value only a CPU that implements them reaches.
//
// _emu_cpu_lse(a, b)    -> a + b: `ldaddal` adds b to a stack word holding a
//                          and loads the old value; the result is reloaded.
// _emu_cpu_pac(a)       -> a: `paciza` then `autiza` on the same value.
// _emu_cpu_jcvt()       -> 7: `fjcvtzs` of 7.0.
// _emu_cpu_brk()        traps: a `brk #1` the program wrote.
// _emu_cpu_unallocated() is one unallocated encoding that is no `udf`: the
//                          emulator reports it as unsupported, not a trap.
.text
.p2align 2
.globl _emu_cpu_lse
_emu_cpu_lse:
  sub sp, sp, #16
  str x0, [sp, #8]
  add x9, sp, #8
  ldaddal x1, x10, [x9]
  ldr x0, [sp, #8]
  add sp, sp, #16
  ret

.p2align 2
.globl _emu_cpu_pac
_emu_cpu_pac:
  paciza x0
  autiza x0
  ret

.p2align 2
.globl _emu_cpu_jcvt
_emu_cpu_jcvt:
  fmov d0, #7.0
  fjcvtzs w0, d0
  ret

.p2align 2
.globl _emu_cpu_brk
_emu_cpu_brk:
  brk #1

.p2align 2
.globl _emu_cpu_unallocated
_emu_cpu_unallocated:
  .long 0x00010000
.subsections_via_symbols
