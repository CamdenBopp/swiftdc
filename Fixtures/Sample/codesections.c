// Functions outside __TEXT,__text. The linker keeps any section that is
// declared pure_instructions as code, and LC_FUNCTION_STARTS lists its
// functions: auvaltool and audiomxd put real-time callbacks in
// __TEXT,__realtime, and gcc's cold splitting emits __TEXT,__text_cold.
// True behaviour: `rt_scale` (in __realtime) returns x * 3 and is called by
// `drive`; `cold_fail` (in __text_cold) returns -1 or -2 and is reached from
// `drive` only when x < 0; `drive` itself is in __text. `rt_mix` (in
// __realtime) reads both of its arguments, so `mix` passes it two.
// `_rt_twin_a` and `_rt_twin_b` name one address in __realtime, as an
// identical-code fold does: neither name is the function's alone.
// `_rt_clobber` (in __realtime, hand-written) overwrites callee-saved x19,
// so `_keep`, which sets x19 to 42 before calling it and returns x19, does
// not return 42: only the callee's body says so.
__attribute__((noinline, section("__TEXT,__realtime,regular,pure_instructions")))
int rt_scale(int x) { return x * 3; }

__attribute__((noinline, section("__TEXT,__realtime,regular,pure_instructions")))
int rt_mix(int a, int b) { return a * 7 - b; }

__asm__(".section __TEXT,__realtime,regular,pure_instructions\n"
        ".globl _rt_twin_a\n.globl _rt_twin_b\n.p2align 2\n"
        "_rt_twin_a:\n_rt_twin_b:\n    mov w0, #9\n    ret\n");

__asm__(".section __TEXT,__realtime,regular,pure_instructions\n"
        ".globl _rt_clobber\n.p2align 2\n_rt_clobber:\n    mov x19, #0\n    ret\n"
        ".text\n.globl _keep\n.p2align 2\n_keep:\n"
        "    stp x19, x30, [sp, #-16]!\n    mov x19, #42\n    bl _rt_clobber\n"
        "    mov x0, x19\n    ldp x19, x30, [sp], #16\n    ret\n");

__attribute__((noinline, cold, section("__TEXT,__text_cold,regular,pure_instructions")))
int cold_fail(int x) { return x < -100 ? -2 : -1; }

int drive(int x) {
    if (x < 0) return cold_fail(x);
    return rt_scale(x) + 1;
}

int mix(int x) { return rt_mix(x + 5, x * 2) + 1; }
