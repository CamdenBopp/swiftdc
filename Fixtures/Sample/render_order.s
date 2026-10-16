// Where a call's result renders. A result the pseudocode spells out at a
// later use reads as evaluated there; across another call that reorders
// the program, so such a result is bound (`let rN`) where it is computed.
.text
.p2align 2

// render_helper's result is kept in x19 across render_effect and handed to
// an indirect call the decompiler cannot resolve. True order: helper,
// effect, then the indirect call with helper's result.
.globl _$s11RenderOrder8indirectyyF
_$s11RenderOrder8indirectyyF:
  stp x29, x30, [sp, #-32]!
  str x19, [sp, #16]
  bl _render_helper
  mov x19, x0
  bl _render_effect
  adrp x8, _render_fn@PAGE
  ldr x8, [x8, _render_fn@PAGEOFF]
  mov x0, x19
  blr x8
  ldr x19, [sp, #16]
  ldp x29, x30, [sp], #32
  ret

// A Swift method's result used after another call is bound where it is
// computed; the binding is the call, so it names `self` as the statement
// would. True call: Widget.count.getter with self = the argument.
.globl _$s11RenderOrder9boundSelfyS2iF
_$s11RenderOrder9boundSelfyS2iF:
  stp x29, x30, [sp, #-32]!
  stp x20, x19, [sp, #16]
  mov x20, x0
  bl _$s11RenderOrder6WidgetC5countSivg
  mov x19, x0
  bl _render_effect
  mov x0, x19
  bl _render_sink
  mov x0, x19
  ldp x20, x19, [sp, #16]
  ldp x29, x30, [sp], #32
  ret

.globl _$s11RenderOrder6WidgetC5countSivg
_$s11RenderOrder6WidgetC5countSivg:
  ldr x0, [x20, #16]
  ret
.globl _render_sink
_render_sink:
  ret

// A static member of a struct receives a thin metatype, which no register
// carries, so x20 is the caller's scratch (here the argument), not self. A
// class's static member receives its metatype in x20: there it is self.
// True calls: Point.origin.getter with no self, then Widget.shared.getter
// with self = what the caller put in x20 (origin's result, also returned).
.globl _$s11RenderOrder10staticCallyS2iF
_$s11RenderOrder10staticCallyS2iF:
  stp x29, x30, [sp, #-32]!
  stp x20, x19, [sp, #16]
  mov x20, x0
  bl _$s11RenderOrder5PointV6originSivgZ
  mov x19, x0
  mov x20, x19
  bl _$s11RenderOrder6WidgetC6sharedACvgZ
  mov x0, x19
  ldp x20, x19, [sp, #16]
  ldp x29, x30, [sp], #32
  ret

.globl _$s11RenderOrder5PointV6originSivgZ
_$s11RenderOrder5PointV6originSivgZ:
  mov x0, #0
  ret
.globl _$s11RenderOrder6WidgetC6sharedACvgZ
_$s11RenderOrder6WidgetC6sharedACvgZ:
  mov x0, x20
  ret

.globl _render_helper
_render_helper:
  mov x0, #5
  ret
.globl _render_effect
_render_effect:
  ret
.data
.p2align 3
.globl _render_fn
_render_fn:
  .quad 0
