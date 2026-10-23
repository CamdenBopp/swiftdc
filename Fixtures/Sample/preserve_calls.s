// Callee-saved registers through nested calls and tail calls. Each Swift
// caller keeps arg0 in x19 across one call to a fragment and returns x19.
// clobber_inner writes x19 = x1 (arg1) and does not restore it.
//
// True behaviour, with (1, 2): nested and tail return 2, because their
// fragment reaches clobber_inner through a call or a tail branch and never
// writes x19 itself; saved returns 1, because its fragment saves and
// restores x19 around the same call; guarded returns 1: its callee calls a
// function that saves x19, passes a stack address to another call (so its
// save slot is not provably intact) and restores x19; control returns 1.
//
// Outlined epilogues (LLVM's machine outliner, as in GoodLinks'
// `-[DDAbstractDatabaseLogger saveThreshold]` assertion path): a helper
// saves x19 and x20, lets setup_fragment rewrite them (`mov x19, x1;
// mov x20, x0`), and hands them back through a fragment that reloads them
// from the helper's frame. epilogue (tail branch to the reload) and
// reloaded (a `bl` to it) return 1, and so does direct, whose helper writes
// x19 itself before its outlined epilogue. The reload does not restore when
// the slot holds something else: forged saves arg1 where x19 belongs,
// scribbled's fragment overwrites half the slot first (on one path) and
// smudged's through an address it computes from sp; each returns 2.
//
// A callee can use the caller's frame pointer: x29_writer stores x1 at [x29].
// x29_fragment saves x19 at [sp], points x29 there and calls x29_writer, so
// its reload brings back arg1; x29relay reaches x29_writer through a tail
// branch from a fragment that does not touch x29 itself. Both return 2.
.text
.p2align 2
.macro caller name, fragment
.globl _$s8Preserve\name\()yS2i_SitF
_$s8Preserve\name\()yS2i_SitF:
 stp x19, x30, [sp, #-16]!
 mov x19, x0
 bl \fragment
 mov x0, x19
 ldp x19, x30, [sp], #16
 ret
.endm
caller 6nested, _nested_outer
caller 4tail, _tail_outer
caller 5saved, _saving_outer
caller 7guarded, _guarded_middle
caller 7control, _control_fragment
caller 8epilogue, _epilogue_helper
caller 6direct, _direct_helper
caller 3x29, _x29_fragment
caller 8x29relay, _x29_relayed_fragment
caller 8reloaded, _reloading_helper
caller 6forged, _forged_helper
caller 9scribbled, _scribbled_helper
caller 7smudged, _smudged_helper
.globl _clobber_inner
_clobber_inner:
 mov x19, x1
 ret
.globl _nested_outer
_nested_outer:
 stp x29, x30, [sp, #-16]!
 mov x29, sp
 bl _clobber_inner
 ldp x29, x30, [sp], #16
 ret
.globl _tail_outer
_tail_outer:
 b _clobber_inner
.globl _saving_outer
_saving_outer:
 stp x19, x30, [sp, #-16]!
 bl _clobber_inner
 ldp x19, x30, [sp], #16
 ret
.globl _stack_sink
_stack_sink:
 ret
.globl _escaping_saver
_escaping_saver:
 stp x19, x30, [sp, #-32]!
 mov x19, x1
 add x0, sp, #16
 bl _stack_sink
 ldp x19, x30, [sp], #32
 ret
.globl _guarded_middle
_guarded_middle:
 stp x29, x30, [sp, #-16]!
 mov x29, sp
 bl _escaping_saver
 ldp x29, x30, [sp], #16
 ret
.globl _control_fragment
_control_fragment:
 stp x29, x30, [sp, #-16]!
 mov x29, sp
 ldp x29, x30, [sp], #16
 ret
.globl _setup_fragment
_setup_fragment:
 mov x19, x1
 mov x20, x0
 ret
.globl _epilogue_fragment
_epilogue_fragment:
 ldp x20, x19, [sp], #0x20
 b _stack_sink
.globl _epilogue_helper
_epilogue_helper:
 stp x20, x19, [sp, #-0x20]!
 stp x29, x30, [sp, #0x10]
 add x29, sp, #0x10
 bl _setup_fragment
 ldp x29, x30, [sp, #0x10]
 b _epilogue_fragment
.globl _direct_helper
_direct_helper:
 stp x20, x19, [sp, #-0x20]!
 stp x29, x30, [sp, #0x10]
 add x29, sp, #0x10
 mov x19, x1
 ldp x29, x30, [sp, #0x10]
 b _epilogue_fragment
.globl _forged_helper
_forged_helper:
 stp x20, x1, [sp, #-0x20]!
 stp x29, x30, [sp, #0x10]
 add x29, sp, #0x10
 ldp x29, x30, [sp, #0x10]
 b _epilogue_fragment
.globl _reload_fragment
_reload_fragment:
 ldp x20, x19, [sp]
 ret
.globl _scribble_fragment
_scribble_fragment:
 cbz x1, 1f
 str w1, [sp, #8]
1:
 ldp x20, x19, [sp]
 ret
.globl _smudge_fragment
_smudge_fragment:
 mov x9, sp
 orr x9, x9, #8
 str x1, [x9]
 ldp x20, x19, [sp]
 ret
.macro reloader name, fragment
.globl \name
\name:
 stp x20, x19, [sp, #-0x20]!
 stp x29, x30, [sp, #0x10]
 add x29, sp, #0x10
 bl _setup_fragment
 bl \fragment
 ldp x29, x30, [sp, #0x10]
 add sp, sp, #0x20
 ret
.endm
reloader _reloading_helper, _reload_fragment
reloader _scribbled_helper, _scribble_fragment
reloader _smudged_helper, _smudge_fragment
.globl _x29_writer
_x29_writer:
 str x1, [x29]
 ret
.globl _x29_relay
_x29_relay:
 b _x29_writer
.macro x29saver name, callee
.globl \name
\name:
 sub sp, sp, #32
 stp x29, x30, [sp, #16]
 str x19, [sp]
 mov x29, sp
 mov x19, xzr
 bl \callee
 ldr x19, [sp]
 ldp x29, x30, [sp, #16]
 add sp, sp, #32
 ret
.endm
x29saver _x29_fragment, _x29_writer
x29saver _x29_relayed_fragment, _x29_relay
