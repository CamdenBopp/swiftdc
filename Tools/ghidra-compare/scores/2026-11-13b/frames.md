# Frames area: Ghidra 12.2 vs swiftdc (`disasm --structured`)

Scope: 34 builds of five fixtures (frames.c, frames2.c, callers.c, cond.c, sframes.swift). Every user-written function in every build is scored; compiler helpers (`OUTLINED_FUNCTION_*`, `.cold.*`, `Big` accessors, value witnesses, sanitizer ctors) are skipped. Ground truth: fixture comments plus `llvm-objdump` of each dylib. Where -O2 folds undefined-behaviour reads (frames2.c at -O2: `big_frame` returns `n`, `mid_frame` returns 0, `vla`/`aligned64` return garbage), the binary is the truth.

Rules applied to both tools:

- Ghidra's interface is the decompiled C prototype; `undefined1[16]` results or parameters count as DECLINED, `undefined8` with a shown value counts as typed. swiftdc's C output has no prototype line, so its interface is read from the `argN` it uses and the `return` it prints. Swift functions take the demangled header.
- A value shown as `___chkstk_darwin`'s return (`uVar1 = chkstk()`, `extraout_x1`) when the binary uses the preserved argument register is WRONG: it misattributes the value. A bare `extraout_*`/`unaff_*`/raw `xN` is a DECLINED piece (PARTIAL).
- **`W*`** marks a swiftdc cell that is WRONG only because a value-returning C function renders a bare `return` (or no return), with the value silently absent. It counts as WRONG in the main totals; the alternative totals read it as a decline (interface DECLINED, body PARTIAL).
- Instrumented builds: instrumentation calls may be shown or hidden, but shown with a missing, extra or fabricated argument is WRONG. Both tools omit `__tsan_func_entry`'s return-address argument; that omission is tolerated for both.
- A folded volatile reload (`return x + 3` for `g_sink = x; return g_sink + 3`) is WRONG. A silently dropped store (`buf[63] = 0`, `var x = 0`) is WRONG.
- 2026-11-13b re-score, swiftdc columns only (RUBRIC.md addendum). `return // x0 = <value>` states what x0 holds and claims no result: the interface result is DECLINED, and the commented value is scored as the shown result value in the body (right: CORRECT, or PARTIAL with raw or `?` pieces elsewhere; wrong: WRONG). A value-returning function that still shows a bare `return` or no value stays `W*`. Only rows whose function text changed between the two swiftdc renders were re-scored.

| function | build | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |
|---|---|---|---|---|---|---|
| big_frame | frames_O2 | W | W | W* | W* | Ghidra misses param n (void sig), uses chkstk 'return' for n; swiftdc: sink(…)/? and no return value |
| mid_frame | frames_O2 | C | C | W* | W* | swiftdc: bare `return`, value missing |
| vla | frames_O2 | C | P | W* | W* | Ghidra: extraout_x8 for the size; swiftdc: sink(…), no return value |
| aligned64 | frames_O2 | C | C | W* | W* | swiftdc: bare `return`, value missing |
| protected | frames_O2 | C | C | D | W | swiftdc: now `let r0 = strlen(…)`, `return // x0 = (r0 + 1)`, right (was bare return); still drops the buf[63]=0 store |
| fpsaved | frames_O2 | D | C | W* | W* | Ghidra result typed undefined1[16]; swiftdc: use(…), no arithmetic/return |
| sj | frames_O2 | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw, `sink(…)` |
| lj | frames_O2 | C | C | C | P | swiftdc: longjmp(0x…, arg0), &jb raw |
| two_args | frames_O2 | C | W | D | P | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(…)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed, argument elided |
| big_frame | frames_bti | W | W | W* | W* | Ghidra misses param n (void sig), uses chkstk 'return' for n; swiftdc: sink(…)/? and no return value |
| mid_frame | frames_bti | C | C | W* | W* | swiftdc: bare `return`, value missing |
| vla | frames_bti | C | P | W* | W* | Ghidra: extraout_x8 for the size; swiftdc: sink(…), no return value |
| aligned64 | frames_bti | C | C | W* | W* | swiftdc: bare `return`, value missing |
| protected | frames_bti | C | C | D | W | swiftdc: now `let r0 = strlen(…)`, `return // x0 = (r0 + 1)`, right (was bare return); still drops the buf[63]=0 store |
| fpsaved | frames_bti | D | C | W* | W* | Ghidra result typed undefined1[16]; swiftdc: use(…), no arithmetic/return |
| sj | frames_bti | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw, `sink(…)` |
| lj | frames_bti | C | C | C | P | swiftdc: longjmp(0x…, arg0), &jb raw |
| two_args | frames_bti | C | W | D | P | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(…)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed, argument elided |
| big_frame | frames_omit | W | W | W* | W* | Ghidra misses param n (void sig), uses chkstk 'return' for n; swiftdc: sink(…)/? and no return value |
| mid_frame | frames_omit | C | C | W* | W* | swiftdc: bare `return`, value missing |
| vla | frames_omit | C | P | W* | W* | Ghidra: extraout_x8 for the size; swiftdc: sink(…), no return value |
| aligned64 | frames_omit | C | C | W* | W* | swiftdc: bare `return`, value missing |
| protected | frames_omit | C | C | D | W | swiftdc: now `let r0 = strlen(…)`, `return // x0 = (r0 + 1)`, right (was bare return); still drops the buf[63]=0 store |
| fpsaved | frames_omit | D | C | W* | W* | Ghidra result typed undefined1[16]; swiftdc: use(…), no arithmetic/return |
| sj | frames_omit | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw, `sink(…)` |
| lj | frames_omit | C | C | C | P | swiftdc: longjmp(0x…, arg0), &jb raw |
| two_args | frames_omit | C | W | D | P | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(…)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed, argument elided |
| big_frame | frames_clash | W | W | W* | W* | Ghidra misses param n (void sig), uses chkstk 'return' for n; swiftdc: sink(…)/? and no return value |
| mid_frame | frames_clash | C | C | W* | W* | swiftdc: bare `return`, value missing |
| vla | frames_clash | C | P | W* | W* | Ghidra: extraout_x8 for the size; swiftdc: sink(…), no return value |
| aligned64 | frames_clash | C | C | W* | W* | swiftdc: bare `return`, value missing |
| protected | frames_clash | C | C | D | W | swiftdc: now `let r0 = strlen(…)`, `return // x0 = (r0 + 1)`, right (was bare return); still drops the buf[63]=0 store |
| fpsaved | frames_clash | D | C | W* | W* | Ghidra result typed undefined1[16]; swiftdc: use(…), no arithmetic/return |
| sj | frames_clash | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw, `sink(…)` |
| lj | frames_clash | C | C | C | P | swiftdc: longjmp(0x…, arg0), &jb raw |
| two_args | frames_clash | C | W | D | P | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(…)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed, argument elided |
| big_frame | frames_cov | W | W | W* | W* | Ghidra misses param n (void sig), uses chkstk 'return' for n; swiftdc: sink(…)/? and no return value |
| mid_frame | frames_cov | C | C | W* | W* | swiftdc: bare `return`, value missing |
| vla | frames_cov | C | P | W* | W* | Ghidra: extraout_x8 for the size; swiftdc: sink(…), no return value |
| aligned64 | frames_cov | C | C | W* | W* | swiftdc: bare `return`, value missing |
| protected | frames_cov | C | C | D | W | swiftdc: now `let r0 = strlen(…)`, `return // x0 = (r0 + 1)`, right (was bare return); still drops the buf[63]=0 store |
| fpsaved | frames_cov | D | C | W* | W* | Ghidra result typed undefined1[16]; swiftdc: use(…), no arithmetic/return |
| sj | frames_cov | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb and cov counters raw, `sink(…)` |
| lj | frames_cov | C | C | C | P | swiftdc: longjmp(0x…, arg0), &jb raw |
| two_args | frames_cov | C | W | D | P | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(…)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed, argument elided, cov counter raw |
| big_frame | frames_pat | W | W | W* | W* | Ghidra misses param n (void sig), uses chkstk 'return' for n; swiftdc: sink(…)/? and no return value |
| mid_frame | frames_pat | C | C | W* | W* | swiftdc: bare `return`, value missing |
| vla | frames_pat | C | W | W* | W* | Ghidra: memset guard tests chkstk 'return' (truth: n != 0); swiftdc: raw x0 guard, no return |
| aligned64 | frames_pat | C | C | W* | W* | swiftdc: bare `return`, value missing |
| protected | frames_pat | C | C | D | W | swiftdc: now `let r0 = strlen(…)`, `return // x0 = (r0 + 1)`, right (was bare return); still drops the buf[63]=0 store |
| fpsaved | frames_pat | D | C | W* | W* | Ghidra result typed undefined1[16]; swiftdc: use(…), no arithmetic/return |
| sj | frames_pat | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw, `sink(…)` |
| lj | frames_pat | C | C | C | P | swiftdc: longjmp(0x…, arg0), &jb raw |
| two_args | frames_pat | C | W | D | P | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(…)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed, argument elided |
| big_frame | frames_pcg | W | W | W* | W* | Ghidra misses param n (void sig), uses chkstk 'return' for n; swiftdc: sink(…)/? and no return value |
| mid_frame | frames_pcg | C | C | W* | W* | swiftdc: bare `return`, value missing |
| vla | frames_pcg | C | P | W* | W* | Ghidra: extraout_x8 for the size; swiftdc: sink(…), no return value |
| aligned64 | frames_pcg | C | C | W* | W* | swiftdc: bare `return`, value missing |
| protected | frames_pcg | C | C | D | W | swiftdc: now `let r0 = strlen(…)`, `return // x0 = (r0 + 1)`, right (was bare return); still drops the buf[63]=0 store |
| fpsaved | frames_pcg | D | C | W* | W* | Ghidra result typed undefined1[16]; swiftdc: use(…), no arithmetic/return |
| sj | frames_pcg | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw, `sink(…)` |
| lj | frames_pcg | C | C | C | P | swiftdc: longjmp(0x…, arg0), &jb raw |
| two_args | frames_pcg | C | C | D | W | swiftdc: x0 comment now right (r0 + arg1), but still __sanitizer_cov_trace_pc_guard(0x805c, arg1) extra arg |
| big_frame | frames_sp | W | W | W* | W* | Ghidra misses param n (void sig), uses chkstk 'return' for n; swiftdc: sink(…)/? and no return value |
| mid_frame | frames_sp | C | C | W* | W* | swiftdc: bare `return`, value missing |
| vla | frames_sp | C | P | W* | W* | Ghidra: extraout_x8 for the size; swiftdc: sink(…), no return value |
| aligned64 | frames_sp | C | C | W* | W* | swiftdc: bare `return`, value missing |
| protected | frames_sp | C | C | D | W | swiftdc: now `let r0 = strlen(…)`, `return // x0 = (r0 + 1)`, right (was bare return); still drops the buf[63]=0 store |
| fpsaved | frames_sp | D | C | W* | W* | Ghidra result typed undefined1[16]; swiftdc: use(…), no arithmetic/return |
| sj | frames_sp | W | W | D | P | Ghidra: sj shown void, return value dropped; swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb and stack-guard compare raw, `sink(…)` |
| lj | frames_sp | C | C | C | P | swiftdc: longjmp(0x…, arg0), &jb raw |
| two_args | frames_sp | C | W | D | P | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(…)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed, argument elided, stack-guard compare raw |
| big_frame | frames_tsan | W | W | W* | W | swiftdc: __tsan_func_exit(<value>) — func_exit takes no args; no return value |
| mid_frame | frames_tsan | C | C | W* | W | swiftdc: __tsan_func_exit(<value>) — func_exit takes no args; no return value |
| vla | frames_tsan | C | P | W* | W | swiftdc: __tsan_func_exit(<value>) — func_exit takes no args; no return value |
| aligned64 | frames_tsan | C | C | W* | W | swiftdc: __tsan_func_exit(<value>) — func_exit takes no args; no return value |
| protected | frames_tsan | C | C | D | W | swiftdc: x0 comment now right (r0 + 1), but still __tsan_func_exit(r0): func_exit takes no args; buf[63]=0 store dropped |
| fpsaved | frames_tsan | D | C | W* | W | swiftdc: __tsan_func_exit(<value>) — func_exit takes no args; no return value |
| sj | frames_tsan | C | C | D | W | swiftdc: x0 comment now right ((r0 == 0) ? arg0 + 1 : -1), but still `let r1 = sink(…)` (void) feeding __tsan_func_exit(…), which takes no args |
| lj | frames_tsan | C | C | C | P | swiftdc: longjmp(0x…, arg0), &jb raw |
| two_args | frames_tsan | C | C | D | W | swiftdc: x0 comment now right (r0 + arg1), but still __tsan_func_entry(?, arg1) and func_exit(r0) |
| big_frame | frames_ubsan | W | W | W* | W | Ghidra: void sig, chkstk 'return' as n; swiftdc: pointer_overflow/add_overflow missing args |
| mid_frame | frames_ubsan | C | C | W* | W* | swiftdc: bare `return`, value missing |
| vla | frames_ubsan | C | W | W* | W | both: OUTLINED_FUNCTION_0() with no arguments; Ghidra unaff_x20, swiftdc no return |
| aligned64 | frames_ubsan | W | W | W* | W* | Ghidra: void, return value moved into ___stack_chk_fail(x[1]+k); swiftdc: no return |
| protected | frames_ubsan | W | W | D | W | Ghidra: void, strlen+1 passed to ___stack_chk_fail; swiftdc: now `let r0 = strlen(…)`, `return // x0 = (r0 + 1)`, right (was bare return); still drops the buf[63]=0 store |
| fpsaved | frames_ubsan | D | C | W* | W | swiftdc: float_cast_overflow(0x8100) missing value arg, bare return |
| sj | frames_ubsan | C | C | W* | W* | swiftdc: setjmp(0x…) raw, sink(…), bare return |
| lj | frames_ubsan | C | C | C | P | swiftdc: longjmp(0x…, arg0), &jb raw |
| two_args | frames_ubsan | C | W | D | P | Ghidra: _use() with no argument; swiftdc: now `return // x0 = (r0 + arg1)`, right (was bare return); `use(…)`, overflow guard `if (?)` |
| big_frame | frames_asan | C | C | W* | W* | swiftdc: sink(…), no return value |
| mid_frame | frames_asan | C | C | W* | W* | swiftdc: bare `return`, value missing |
| vla | frames_asan | C | W | W* | W | both drop an asan arg: Ghidra alloca_poison(p) w/o size, swiftdc report_load8(); swiftdc no return |
| aligned64 | frames_asan | C | C | W* | W | swiftdc: fabricated `if (error == nil)` in C code; no return |
| protected | frames_asan | C | C | W* | W* | swiftdc: strncpy(?, …), no return value |
| fpsaved | frames_asan | D | C | W* | W* | Ghidra result typed undefined1[16]; swiftdc: use(…), no arithmetic/return |
| sj | frames_asan | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw, `sink(…)` |
| lj | frames_asan | C | C | C | W | swiftdc: __asan_handle_no_return(arg0) extra arg |
| two_args | frames_asan | C | W | D | P | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(…)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed, argument elided |
| sink | f2_O2 | C | C | C | P | swiftdc: g_sink as raw mem64[0x…] |
| use | f2_O2 | C | W | W* | W* | Ghidra folds the volatile g_sink reload (returns x+3 / (double)(long)x); swiftdc: no return value |
| fuse | f2_O2 | D | W | W* | W | Ghidra folds volatile reload, result undefined1[16]; swiftdc stores d0, binary stores fcvtzs(d0); no return |
| big_frame | f2_O2 | W | W | W* | W* | binary returns n; Ghidra: void sig, n = chkstk 'return'; swiftdc: sink(buf, ?), no return |
| mid_frame | f2_O2 | C | C | D | P | binary returns 0 (UB fold); swiftdc: now `return // x0 = 0`, right (was bare return); result not claimed; stack-guard compare raw |
| vla | f2_O2 | C | W | C | P | Ghidra: _sink() with no arguments; swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| alloca_after | f2_O2 | W | W | W* | W* | Ghidra: void sig (returns use(k)), size = chkstk 'return'; swiftdc: no return |
| aligned64 | f2_O2 | C | C | C | P | binary returns garbage (UB fold); swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| big_args | f2_O2 | C | W | W* | W* | Ghidra: a and b taken from chkstk's 'return' pair; swiftdc: sink(buf, ?), use(?), no return |
| fpsaved | f2_O2 | D | W | W* | W* | Ghidra: _fuse() with no argument, result undefined1[16]; swiftdc: fuse(?) only |
| big_fp | f2_O2 | D | W | W* | W* | Ghidra: a taken from chkstk 'return', param undefined1[16]; swiftdc: no return |
| sj | f2_O2 | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw `setjmp(0x…)` |
| two_args | f2_O2 | C | W | D | C | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(arg0)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed |
| konst | f2_O2 | C | C | D | P | swiftdc: now `return // x0 = 42`, right (was bare return); result not claimed; stack-guard compare raw `x9 != x8` |
| sink | f2_Os | C | C | C | P | swiftdc: g_sink as raw mem64[0x…] |
| use | f2_Os | C | W | W* | W* | Ghidra folds the volatile g_sink reload (returns x+3 / (double)(long)x); swiftdc: no return value |
| fuse | f2_Os | D | W | W* | W | Ghidra folds volatile reload, result undefined1[16]; swiftdc stores d0, binary stores fcvtzs(d0); no return |
| big_frame | f2_Os | W | W | W* | W* | binary returns n; Ghidra: void sig, n = chkstk 'return'; swiftdc: sink(buf, ?), no return |
| mid_frame | f2_Os | C | C | D | P | binary returns 0 (UB fold); swiftdc: now `return // x0 = 0`, right (was bare return); result not claimed; stack-guard compare raw |
| vla | f2_Os | C | W | C | P | Ghidra: _sink() with no arguments; swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| alloca_after | f2_Os | W | W | W* | W* | Ghidra: void sig (returns use(k)), size = chkstk 'return'; swiftdc: no return |
| aligned64 | f2_Os | C | C | C | P | binary returns garbage (UB fold); swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| big_args | f2_Os | C | W | W* | W* | Ghidra: a and b taken from chkstk's 'return' pair; swiftdc: sink(buf, ?), use(?), no return |
| fpsaved | f2_Os | D | W | W* | W* | Ghidra: _fuse() with no argument, result undefined1[16]; swiftdc: fuse(?) only |
| big_fp | f2_Os | D | W | W* | W* | Ghidra: a taken from chkstk 'return', param undefined1[16]; swiftdc: no return |
| sj | f2_Os | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw `setjmp(0x…)` |
| two_args | f2_Os | C | W | D | C | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(arg0)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed |
| konst | f2_Os | C | C | D | P | swiftdc: now `return // x0 = 42`, right (was bare return); result not claimed; stack-guard compare raw `x9 != x8` |
| sink | f2_bti | C | C | C | P | swiftdc: g_sink as raw mem64[0x…] |
| use | f2_bti | C | W | W* | W* | Ghidra folds the volatile g_sink reload (returns x+3 / (double)(long)x); swiftdc: no return value |
| fuse | f2_bti | D | W | W* | W | Ghidra folds volatile reload, result undefined1[16]; swiftdc stores d0, binary stores fcvtzs(d0); no return |
| big_frame | f2_bti | W | W | W* | W* | binary returns n; Ghidra: void sig, n = chkstk 'return'; swiftdc: sink(buf, ?), no return |
| mid_frame | f2_bti | C | C | D | P | binary returns 0 (UB fold); swiftdc: now `return // x0 = 0`, right (was bare return); result not claimed; stack-guard compare raw |
| vla | f2_bti | C | W | C | P | Ghidra: _sink() with no arguments; swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| alloca_after | f2_bti | W | W | W* | W* | Ghidra: void sig (returns use(k)), size = chkstk 'return'; swiftdc: no return |
| aligned64 | f2_bti | C | C | C | P | binary returns garbage (UB fold); swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| big_args | f2_bti | C | W | W* | W* | Ghidra: a and b taken from chkstk's 'return' pair; swiftdc: sink(buf, ?), use(?), no return |
| fpsaved | f2_bti | D | W | W* | W* | Ghidra: _fuse() with no argument, result undefined1[16]; swiftdc: fuse(?) only |
| big_fp | f2_bti | D | W | W* | W* | Ghidra: a taken from chkstk 'return', param undefined1[16]; swiftdc: no return |
| sj | f2_bti | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw `setjmp(0x…)` |
| two_args | f2_bti | C | W | D | C | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(arg0)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed |
| konst | f2_bti | C | C | D | P | swiftdc: now `return // x0 = 42`, right (was bare return); result not claimed; stack-guard compare raw `x9 != x8` |
| sink | f2_omit | C | C | C | P | swiftdc: g_sink as raw mem64[0x…] |
| use | f2_omit | C | W | W* | W* | Ghidra folds the volatile g_sink reload (returns x+3 / (double)(long)x); swiftdc: no return value |
| fuse | f2_omit | D | W | W* | W | Ghidra folds volatile reload, result undefined1[16]; swiftdc stores d0, binary stores fcvtzs(d0); no return |
| big_frame | f2_omit | W | W | W* | W* | binary returns n; Ghidra: void sig, n = chkstk 'return'; swiftdc: sink(buf, ?), no return |
| mid_frame | f2_omit | C | C | D | P | binary returns 0 (UB fold); swiftdc: now `return // x0 = 0`, right (was bare return); result not claimed; stack-guard compare raw |
| vla | f2_omit | C | W | C | P | Ghidra: _sink() with no arguments; swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| alloca_after | f2_omit | W | W | W* | W* | Ghidra: void sig (returns use(k)), size = chkstk 'return'; swiftdc: no return |
| aligned64 | f2_omit | C | C | C | P | binary returns garbage (UB fold); swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| big_args | f2_omit | C | W | W* | W* | Ghidra: a and b taken from chkstk's 'return' pair; swiftdc: sink(buf, ?), use(?), no return |
| fpsaved | f2_omit | D | W | W* | W* | Ghidra: _fuse() with no argument, result undefined1[16]; swiftdc: fuse(?) only |
| big_fp | f2_omit | D | W | W* | W* | Ghidra: a taken from chkstk 'return', param undefined1[16]; swiftdc: no return |
| sj | f2_omit | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw `setjmp(0x…)` |
| two_args | f2_omit | C | W | D | C | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(arg0)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed |
| konst | f2_omit | C | C | D | P | swiftdc: now `return // x0 = 42`, right (was bare return); result not claimed; stack-guard compare raw `x9 != x8` |
| sink | f2_cov | C | C | C | P | swiftdc: g_sink raw and raw cov counter x9 |
| use | f2_cov | C | W | W* | W* | Ghidra folds the volatile g_sink reload (returns x+3 / (double)(long)x); swiftdc: no return value |
| fuse | f2_cov | D | W | W* | W | Ghidra folds volatile reload, result undefined1[16]; swiftdc stores d0, binary stores fcvtzs(d0); no return |
| big_frame | f2_cov | W | W | W* | W* | binary returns n; Ghidra: void sig, n = chkstk 'return'; swiftdc: sink(buf, ?), no return |
| mid_frame | f2_cov | C | C | D | P | binary returns 0 (UB fold); swiftdc: now `return // x0 = 0`, right (was bare return); result not claimed; cov counter and stack-guard compare raw |
| vla | f2_cov | C | W | C | P | Ghidra: _sink() with no arguments; swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| alloca_after | f2_cov | W | W | W* | W* | Ghidra: void sig (returns use(k)), size = chkstk 'return'; swiftdc: no return |
| aligned64 | f2_cov | C | C | C | P | binary returns garbage (UB fold); swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| big_args | f2_cov | C | W | W* | W* | Ghidra: a and b taken from chkstk's 'return' pair; swiftdc: sink(buf, ?), use(?), no return |
| fpsaved | f2_cov | D | W | W* | W* | Ghidra: _fuse() with no argument, result undefined1[16]; swiftdc: fuse(?) only |
| big_fp | f2_cov | D | W | W* | W* | Ghidra: a taken from chkstk 'return', param undefined1[16]; swiftdc: no return |
| sj | f2_cov | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb and cov counters raw |
| two_args | f2_cov | C | W | D | P | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(arg0)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed; cov counter store raw |
| konst | f2_cov | C | C | D | P | swiftdc: now `return // x0 = 42`, right (was bare return); result not claimed; cov counter and stack-guard compare raw |
| sink | f2_nosp | C | C | C | P | swiftdc: g_sink as raw mem64[0x…] |
| use | f2_nosp | C | W | W* | W* | Ghidra folds the volatile g_sink reload (returns x+3 / (double)(long)x); swiftdc: no return value |
| fuse | f2_nosp | D | W | W* | W | Ghidra folds volatile reload, result undefined1[16]; swiftdc stores d0, binary stores fcvtzs(d0); no return |
| big_frame | f2_nosp | W | W | W* | W* | binary returns n; Ghidra: void sig, n = chkstk 'return'; swiftdc: sink(buf, ?), no return |
| mid_frame | f2_nosp | C | C | D | C | binary returns 0 (UB fold); swiftdc: now `return // x0 = 0`, right (was bare return); result not claimed |
| vla | f2_nosp | C | W | C | C | Ghidra: _sink() with no arguments; swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| alloca_after | f2_nosp | W | W | W* | W* | Ghidra: void sig (returns use(k)), size = chkstk 'return'; swiftdc: no return |
| aligned64 | f2_nosp | C | C | C | C |  |
| big_args | f2_nosp | C | W | W* | W* | Ghidra: a and b taken from chkstk's 'return' pair; swiftdc: sink(buf, ?), use(?), no return |
| fpsaved | f2_nosp | D | W | W* | W* | Ghidra: _fuse() with no argument, result undefined1[16]; swiftdc: fuse(?) only |
| big_fp | f2_nosp | D | W | W* | W* | Ghidra: a taken from chkstk 'return', param undefined1[16]; swiftdc: no return |
| sj | f2_nosp | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw `setjmp(0x…)` |
| two_args | f2_nosp | C | W | D | C | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(arg0)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed |
| konst | f2_nosp | C | C | D | C | swiftdc: now `return // x0 = 42`, right (was bare return); result not claimed |
| sink | f2_sp | C | C | C | P | swiftdc: g_sink as raw mem64[0x…] |
| use | f2_sp | C | W | W* | W* | Ghidra folds the volatile g_sink reload (returns x+3 / (double)(long)x); swiftdc: no return value |
| fuse | f2_sp | D | C | W* | W | Ghidra shows the volatile reload here; swiftdc stores d0 (binary fcvtzs), no return |
| big_frame | f2_sp | W | W | W* | W* | binary returns n; Ghidra: void sig, n = chkstk 'return'; swiftdc: sink(buf, ?), no return |
| mid_frame | f2_sp | C | C | D | P | binary returns 0 (UB fold); swiftdc: now `return // x0 = 0`, right (was bare return); result not claimed; stack-guard compare raw |
| vla | f2_sp | C | W | C | P | Ghidra: _sink() with no arguments; swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| alloca_after | f2_sp | W | W | W* | W* | Ghidra: void sig (returns use(k)), size = chkstk 'return'; swiftdc: no return |
| aligned64 | f2_sp | C | C | C | P | binary returns garbage (UB fold); swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| big_args | f2_sp | C | W | W* | W* | Ghidra: a and b taken from chkstk's 'return' pair; swiftdc: sink(buf, ?), use(?), no return |
| fpsaved | f2_sp | D | W | W* | W* | Ghidra: _fuse() with no argument, result undefined1[16]; swiftdc: fuse(?) only |
| big_fp | f2_sp | D | W | W* | W* | Ghidra: a taken from chkstk 'return', param undefined1[16]; swiftdc: no return |
| sj | f2_sp | W | W | D | P | Ghidra: sj shown void, return value dropped; swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb and stack-guard compare raw |
| two_args | f2_sp | C | W | D | P | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(arg0)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed; stack-guard compare raw `x9 != x8` |
| konst | f2_sp | C | C | D | P | swiftdc: now `return // x0 = 42`, right (was bare return); result not claimed; stack-guard compare raw `x9 != x8` |
| sink | f2_pcg | C | C | C | W | swiftdc: __sanitizer_cov_trace_pc_guard(0x8000, arg1) extra arg |
| use | f2_pcg | C | W | W* | W* | Ghidra folds the volatile g_sink reload (returns x+3 / (double)(long)x); swiftdc: no return value |
| fuse | f2_pcg | D | W | W* | W | Ghidra folds volatile reload, result undefined1[16]; swiftdc stores d0, binary stores fcvtzs(d0); no return |
| big_frame | f2_pcg | W | W | W* | W* | binary returns n; Ghidra: void sig, n = chkstk 'return'; swiftdc: sink(buf, ?), no return |
| mid_frame | f2_pcg | C | C | D | P | binary returns 0 (UB fold); swiftdc: now `return // x0 = 0`, right (was bare return); result not claimed; stack-guard compare raw |
| vla | f2_pcg | C | P | C | P | Ghidra: extraout_x8 size; swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| alloca_after | f2_pcg | W | W | W* | W* | Ghidra: void sig, use(k) result dropped; swiftdc: no return |
| aligned64 | f2_pcg | C | C | C | P | binary returns garbage (UB fold); swiftdc: swiftdc: stack-guard compare as raw `x9 != x8` |
| big_args | f2_pcg | C | W | W* | W* | Ghidra: a and b taken from chkstk's 'return' pair; swiftdc: sink(buf, ?), use(?), no return |
| fpsaved | f2_pcg | D | C | W* | W* | Ghidra result undefined1[16]; swiftdc: fuse(?) only |
| big_fp | f2_pcg | D | W | W* | W* | Ghidra: a taken from chkstk 'return', param undefined1[16]; swiftdc: no return |
| sj | f2_pcg | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw |
| two_args | f2_pcg | C | C | D | W | swiftdc: x0 comment now right (r0 + arg1), but still trace_pc_guard(0x8038, arg1) extra arg |
| konst | f2_pcg | C | C | D | P | swiftdc: now `return // x0 = 42`, right (was bare return); result not claimed; stack-guard compare raw `x9 != x8` |
| sink | f2_pat | C | C | C | P | swiftdc: g_sink as raw mem64[0x…] |
| use | f2_pat | C | W | W* | W* | Ghidra folds the volatile g_sink reload (returns x+3 / (double)(long)x); swiftdc: no return value |
| fuse | f2_pat | D | W | W* | W | Ghidra folds volatile reload, result undefined1[16]; swiftdc stores d0, binary stores fcvtzs(d0); no return |
| big_frame | f2_pat | W | W | W* | W* | binary returns n; Ghidra: void sig, n = chkstk 'return'; swiftdc: sink(buf, ?), no return |
| mid_frame | f2_pat | C | C | D | P | binary returns -172 (0xAA pattern * 2); swiftdc: now `return // x0 = -172`, right (was bare return); result not claimed; stack-guard compare raw |
| vla | f2_pat | C | W | W* | W* | Ghidra: memset guard on chkstk 'return' (truth n != 0); swiftdc: raw x0 guard, no return (returns a[0]+n) |
| alloca_after | f2_pat | W | W | W* | W* | Ghidra: void sig (returns use(k)), size = chkstk 'return'; swiftdc: no return |
| aligned64 | f2_pat | C | C | D | P | binary returns k + 0xAAAA… pattern; swiftdc: now `return // x0 = (arg0 + 0xaaaaaaaaaaaaaaaa)`, right (was bare return); result not claimed; stack-guard compare raw |
| big_args | f2_pat | C | W | W* | W* | Ghidra: a and b taken from chkstk's 'return' pair; swiftdc: sink(buf, ?), use(?), no return |
| fpsaved | f2_pat | D | W | W* | W* | Ghidra: _fuse() with no argument, result undefined1[16]; swiftdc: fuse(?) only |
| big_fp | f2_pat | D | W | W* | W* | Ghidra: a taken from chkstk 'return', param undefined1[16]; swiftdc: no return |
| sj | f2_pat | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw `setjmp(0x…)` |
| two_args | f2_pat | C | W | D | C | Ghidra: _use() with no argument; swiftdc: now `let r0 = use(arg0)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed |
| konst | f2_pat | C | C | D | P | swiftdc: now `return // x0 = 42`, right (was bare return); result not claimed; stack-guard compare raw `x9 != x8` |
| sink | f2_O0 | C | C | C | P | swiftdc: g_sink as raw mem64[0x…] |
| use | f2_O0 | C | W | W* | W* | Ghidra folds the volatile g_sink reload (returns x+3 / (double)(long)x); swiftdc: no return value |
| fuse | f2_O0 | D | W | W* | W* | Ghidra folds volatile reload; swiftdc: stores raw x9, no return |
| big_frame | f2_O0 | W | W | W* | W* | binary returns n; Ghidra: void sig, n = chkstk 'return'; swiftdc: sink(buf, ?), no return |
| mid_frame | f2_O0 | C | C | W* | W* | binary returns 0 (UB fold); swiftdc: no return value |
| vla | f2_O0 | C | C | W* | W* | swiftdc: no return value (O0 returns a[0]+n) |
| alloca_after | f2_O0 | C | C | W* | W* | swiftdc: no return value |
| aligned64 | f2_O0 | C | C | W* | W* | swiftdc: no return value |
| big_args | f2_O0 | C | W | W* | W* | Ghidra: a and b taken from chkstk's 'return' pair; swiftdc: sink(buf, ?), use(?), no return |
| fpsaved | f2_O0 | D | C | W* | W* | Ghidra result undefined1[16]; swiftdc: fuse(?) only |
| big_fp | f2_O0 | D | W | W* | W* | Ghidra: a taken from chkstk 'return', param undefined1[16]; swiftdc: no return |
| sj | f2_O0 | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw `setjmp(0x…)` |
| two_args | f2_O0 | C | C | D | C | swiftdc: now `let r0 = use(arg0)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed |
| konst | f2_O0 | C | C | D | P | swiftdc: now `return // x0 = 42`, right (was bare return); result not claimed; stack-guard compare raw `x8 != 0` |
| sink | f2_pat0 | C | C | C | P | swiftdc: g_sink as raw mem64[0x…] |
| use | f2_pat0 | C | W | W* | W* | Ghidra folds the volatile g_sink reload (returns x+3 / (double)(long)x); swiftdc: no return value |
| fuse | f2_pat0 | D | W | W* | W* | Ghidra folds volatile reload; swiftdc: stores raw x9, no return |
| big_frame | f2_pat0 | W | W | W* | W* | binary returns n; Ghidra: void sig, n = chkstk 'return'; swiftdc: sink(buf, ?), no return |
| mid_frame | f2_pat0 | C | C | W* | W* | binary returns 0 (UB fold); swiftdc: no return value |
| vla | f2_pat0 | C | P | W* | W* | swiftdc: no return value (O0 returns a[0]+n); Ghidra extraout_x8 guard |
| alloca_after | f2_pat0 | C | C | W* | W* | swiftdc: no return value |
| aligned64 | f2_pat0 | C | C | W* | W* | swiftdc: no return value, sink(?, ?) |
| big_args | f2_pat0 | C | W | W* | W* | Ghidra: a and b taken from chkstk's 'return' pair; swiftdc: sink(buf, ?), use(?), no return |
| fpsaved | f2_pat0 | D | C | W* | W* | Ghidra result undefined1[16]; swiftdc: fuse(?) only |
| big_fp | f2_pat0 | D | W | W* | W* | Ghidra: a taken from chkstk 'return', param undefined1[16]; swiftdc: no return |
| sj | f2_pat0 | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw `setjmp(0x…)` |
| two_args | f2_pat0 | C | C | D | C | swiftdc: now `let r0 = use(arg0)`, `return // x0 = (r0 + arg1)`, right (was no return); result not claimed |
| konst | f2_pat0 | C | C | D | P | swiftdc: now `return // x0 = 42`, right (was bare return); result not claimed; stack-guard compare raw `x8 != 0` |
| sink | f2_tsan | C | C | C | W | swiftdc: __tsan_func_entry(?, arg1), func_exit(r0) |
| use | f2_tsan | C | C | D | W | swiftdc: func_exit(__tsan_read8(…)); return ? |
| fuse | f2_tsan | D | C | W* | W | swiftdc: func_exit(read8(…)), stores d0 not fcvtzs(d0) |
| big_frame | f2_tsan | W | W | W* | W | swiftdc: __tsan_func_exit(<value>) — func_exit takes no args; no return value |
| mid_frame | f2_tsan | C | C | W* | W | swiftdc: __tsan_func_exit(<value>) — func_exit takes no args; no return value |
| vla | f2_tsan | C | P | W* | W | swiftdc: __tsan_func_exit(<value>) — func_exit takes no args; no return value |
| alloca_after | f2_tsan | C | C | W* | W | swiftdc: __tsan_func_exit(<value>) — func_exit takes no args; no return value |
| aligned64 | f2_tsan | C | C | W* | W | swiftdc: __tsan_func_exit(<value>) — func_exit takes no args; no return value |
| big_args | f2_tsan | C | W | W* | W | swiftdc: __tsan_func_exit(<value>) — func_exit takes no args; no return value |
| fpsaved | f2_tsan | D | C | W* | W | swiftdc: __tsan_func_exit(<value>) — func_exit takes no args; no return value |
| big_fp | f2_tsan | D | W | W* | W | swiftdc: __tsan_func_exit(<value>) — func_exit takes no args; no return value |
| sj | f2_tsan | C | C | D | W | swiftdc: x0 comment now right ((r0 == 0) ? arg0 + 1 : -1), but still `let r1 = sink(…)` (void) feeding __tsan_func_exit(…), which takes no args |
| two_args | f2_tsan | C | C | D | W | swiftdc: x0 comment now right (r0 + arg1), but still __tsan_func_entry(?, arg1) and func_exit(r0) |
| konst | f2_tsan | C | C | D | W | swiftdc: x0 comment now right (42), but still __tsan_func_exit(sink(local_1f68, 0)): func_exit takes no args, sink is void |
| sink | f2_ubsan | C | C | C | P | swiftdc: g_sink as raw mem64[0x…] |
| use | f2_ubsan | C | W | D | P | Ghidra folds volatile reload; swiftdc: raw `x1 overflow -3`, return ? |
| fuse | f2_ubsan | D | W | W* | W | swiftdc: float_cast_overflow(0x8020) missing value arg; stores d0 |
| big_frame | f2_ubsan | W | W | W* | W | Ghidra: void sig, return in ___stack_chk_fail; swiftdc: ubsan calls missing args |
| mid_frame | f2_ubsan | W | W | W* | W* | Ghidra: void, return moved into ___stack_chk_fail(lVar1); swiftdc: no return |
| vla | f2_ubsan | C | W | W* | W | both: OUTLINED_FUNCTION_0() with no arguments |
| alloca_after | f2_ubsan | W | W | W* | W* | Ghidra: void sig (returns use(k)), size = chkstk 'return'; swiftdc: no return |
| aligned64 | f2_ubsan | C | C | D | P | binary returns -1 (UB fold); swiftdc: now `return // x0 = -1`, right (was bare return, read as returning nothing); result not claimed, so interface C -> D; stack-guard compare raw |
| big_args | f2_ubsan | W | W | W* | W | Ghidra: void sig, a/b from chkstk; swiftdc: add_overflow(0x8080, r0) missing arg |
| fpsaved | f2_ubsan | D | W | W* | W* | Ghidra: _fuse() with no argument, result undefined1[16]; swiftdc: fuse(?) only |
| big_fp | f2_ubsan | D | W | D | W | Ghidra: a taken from chkstk 'return', param undefined1[16]; swiftdc: now `let r0 = sink(…)` (void) and `return // x0 = (… ? r1 : r0)`: not the result, which is d0 = a + b + buf[5] |
| sj | f2_ubsan | C | C | W* | W* | swiftdc: setjmp(0x…) raw, bare return |
| two_args | f2_ubsan | C | W | D | P | Ghidra: _use() with no argument; swiftdc: now `return // x0 = (r0 + arg1)`, right (was bare return); overflow guard still `if (?)` |
| konst | f2_ubsan | C | C | D | P | swiftdc: now `return // x0 = 42`, right (was bare return); result not claimed; stack-guard compare raw `x9 != x8` |
| sink | f2_asan | C | C | C | W | swiftdc: __asan_report_store8(0x8148, arg1) extra arg |
| use | f2_asan | C | W | W* | W* | Ghidra folds the volatile g_sink reload (returns x+3 / (double)(long)x); swiftdc: no return value |
| fuse | f2_asan | D | W | W* | W* | Ghidra folds volatile reload; swiftdc stores raw x9, no return |
| big_frame | f2_asan | C | C | W* | W* | no chkstk under asan; swiftdc recovers sink(buf, arg0) but no return |
| mid_frame | f2_asan | C | C | W* | W* | binary returns 0 (UB fold); swiftdc: no return value |
| vla | f2_asan | C | W | W* | W | both drop an asan arg: Ghidra alloca_poison(p) w/o size, swiftdc report_load8() |
| alloca_after | f2_asan | C | C | W* | W* | swiftdc: no return value |
| aligned64 | f2_asan | C | C | W* | W | swiftdc: fabricated `if (error == nil)` in C code; no return |
| big_args | f2_asan | C | C | W* | W | swiftdc: __asan_set_shadow_f8(?, 0x222e, arg2) extra arg; no return |
| fpsaved | f2_asan | D | W | W* | W* | Ghidra: _fuse() with no argument, result undefined1[16]; swiftdc: fuse(?) only |
| big_fp | f2_asan | D | C | W* | W* | Ghidra result undefined1[16]; swiftdc: no return |
| sj | f2_asan | C | C | D | P | swiftdc: now `return // x0 = ((r0 == 0) ? (arg0 + 1) : -1)`, right (was bare return); result not claimed, &jb raw `setjmp(0x…)` |
| two_args | f2_asan | C | W | D | W | swiftdc: x0 comment now right (r0 + arg1), but still use(arg0, arg1): use takes one argument |
| konst | f2_asan | C | C | W* | W* | swiftdc: return 42 missing |
| big3 | callers_O2 | C | W | W* | W* | Ghidra: a and b taken from chkstk 'return'/extraout_w1; swiftdc raw x8/w1, no return |
| small1 | callers_O2 | C | C | W* | W* | swiftdc: raw x9/x8 stores, no return value |
| bigf | callers_O2 | D | W | W* | W* | Ghidra: a taken from chkstk 'return' (a*b+1 shown as chk*b+1); swiftdc: no return |
| caller_big | callers_O2 | C | C | D | P | swiftdc: now `let r0 = big3(?, ?, 5)`, `return // x0 = (r0 + 1)`, right (was no return); p and q still `?` |
| caller_small | callers_O2 | W | W | D | P | Ghidra: (void) sig, _small1() with no arg; swiftdc: now `let r0 = small1(?)`, `return // x0 = (r0 + 1)`, right (was no return); p still `?` |
| caller_f | callers_O2 | D | P | W* | W | Ghidra: double param as undefined8, 2.0 as 0x4000000000000000; swiftdc: bigf() with no arguments |
| sink | cond | C | C | C | P | swiftdc: g raw mem64[0x8000] |
| cbig | cond | C | W | C | P | Ghidra: sink's n = chkstk 'return'; swiftdc: condition on raw x0 |
| csmall | cond | C | C | C | P | swiftdc: condition on raw x0 |
| vla_cond | cond | W | W | D | P | Ghidra: misses param m, extraout_x1 guard, _sink() no args; swiftdc: raw x1 guard, sink(…, ?) |
| consume | sf_O | C | P | C | P | Ghidra: beginAccess(0x8000) raw; swiftdc: mem64[0x8000] = x8 |
| tempAlloc | sf_O | C | P | C | P | Ghidra: extraout_x8, _DAT_ constants; swiftdc: raw regs, return ? |
| tempAlloc closure (spec) | sf_O | C | P | D | P | swiftdc header is the generic closure type; consume(?, ?), return ? |
| tempFixed | sf_O | C | C | C | P | swiftdc: raw x0 store base, return ? |
| bigTuple | sf_O | C | W | C | P | Ghidra: _allocateBufferUninitialized(a, …) (truth: capacity 4); swiftdc: consume(?, arg0) |
| fpKeep | sf_O | C | C | C | W | swiftdc omits the `x = 0` store to the escaping local |
| consume | sf_Onone | C | W | C | P | Ghidra writes *param_1 (addressor result lost); swiftdc: mem64[x9] = x8 |
| tempAlloc | sf_Onone | C | W | C | P | Ghidra: swift_slowAlloc(size-0x401, size, -1) 3 bogus args, slowDealloc 2 args; swiftdc raw |
| tempAlloc closure #1 | sf_Onone | C | C | C | P | swiftdc: consume(?, ?), return ? |
| tempFixed | sf_Onone | C | W | C | P | Ghidra: swift_slowDealloc(p, -1) drops third arg; swiftdc return ? |
| tempFixed closure #1 | sf_Onone | C | C | C | P | swiftdc: initialize(repeating:)(?), return ? |
| bigTuple | sf_Onone | C | W | C | P | Ghidra: *(MACH_HEADER+1) = b and calls a stack buffer as code; swiftdc: Array.init(?, ?) |
| bigTuple closure #1 | sf_Onone | C | C | C | P | swiftdc: consume(r0, ?), return ? |
| fpKeep | sf_Onone | C | C | C | W | swiftdc omits the `x = 0` store to the escaping local |
| consume | sf_Osize | C | P | C | P | both: blackHole as raw 0x8000 |
| tempAlloc | sf_Osize | C | W | C | P | Ghidra: stack-check condition built from a stale loop compare; swiftdc `if (cond !=)`, return ? |
| tempAlloc closure (spec) | sf_Osize | C | C | D | P | swiftdc header is the generic closure type; consume(?, ?), return ? |
| tempFixed | sf_Osize | C | C | C | P | swiftdc: return ? |
| bigTuple | sf_Osize | C | W | C | W | Ghidra: _allocateBufferUninitialized(a, …); swiftdc: return a+b missing (tail OUTLINED_FUNCTION_1) |
| fpKeep | sf_Osize | C | P | C | W | Ghidra: `if ((bool)in_ZR)`; swiftdc omits the `x = 0` store |
| consume | sf_asan | C | C | C | W | swiftdc: __asan_stack_malloc_1(96, arg1) extra arg |
| tempAlloc | sf_asan | C | W | C | W | both drop asan args (Ghidra alloca_poison(p), report_store8(); swiftdc handle_no_return(arg0, arg1), allocas_unpoison()) |
| tempAlloc closure (spec) | sf_asan | C | W | D | W | both: report_* calls without the address; swiftdc machine_return() |
| tempFixed | sf_asan | C | W | C | W | both: __asan_report_store16() without the address |
| bigTuple | sf_asan | C | W | C | P | Ghidra: _allocateBufferUninitialized(a, …); swiftdc return ? |
| fpKeep | sf_asan | C | C | C | P | swiftdc: consume(?, 1), return ? |
| consume | sf_cov | C | C | C | W | swiftdc: trace_pc_guard(0x81e0, arg1) extra arg |
| tempAlloc | sf_cov | C | W | C | W | Ghidra: alloca_poison(p), report_store8() missing args; swiftdc: fabricated `if (error == nil)` |
| tempAlloc closure (spec) | sf_cov | C | W | D | W | both: report_* calls without the address |
| tempFixed | sf_cov | C | W | C | W | both: __asan_report_store16() without the address |
| bigTuple | sf_cov | C | W | C | W | Ghidra: _allocateBufferUninitialized(a, …); swiftdc: trace_pc_guard(0x8204, arg1) |
| fpKeep | sf_cov | C | C | C | P | swiftdc: consume(?, 1) |
| consume | sf_prof | C | P | C | P | both: blackHole/its access as raw address |
| tempAlloc | sf_prof | C | W | C | P | Ghidra: n replaced by chkstk 'return' (uVar3) for the loop and consume; swiftdc return ? |
| tempAlloc closure (spec) | sf_prof | C | C | D | P | swiftdc header is the generic closure type; consume(?, ?) |
| tempFixed | sf_prof | C | C | C | P | swiftdc: return ? |
| bigTuple | sf_prof | C | W | C | P | Ghidra: _allocateBufferUninitialized(a, …); swiftdc consume(?, arg0) |
| fpKeep | sf_prof | C | C | C | W | swiftdc omits the `x = 0` store to the escaping local |
| consume | sf_tsan | C | C | C | W | swiftdc: __tsan_func_entry(?, arg1) |
| tempAlloc | sf_tsan | C | C | C | W | swiftdc: func_entry(?, arg1), __tsan_write8() without address, func_exit(r1) |
| tempAlloc closure (spec) | sf_tsan | C | C | D | W | swiftdc: __tsan_write8() without address |
| tempFixed | sf_tsan | C | C | C | P | swiftdc: return ? |
| bigTuple | sf_tsan | C | W | C | W | Ghidra: _allocateBufferUninitialized(a, …); swiftdc: func_entry(?, arg1), __tsan_read8() |
| fpKeep | sf_tsan | C | C | C | W | swiftdc omits the `x = 0` store to the escaping local |

## Totals (349 function-builds)

Order: CORRECT / PARTIAL / WRONG / DECLINED. Ghidra's rows are copied from the 2026-11-13 table.

| tool | axis | totals |
|---|---|---|
| Ghidra | interface | C 253 / P 0 / W 41 / D 55 |
| Ghidra | body | C 177 / P 18 / W 154 / D 0 |
| swiftdc | interface | C 82 / P 0 / W 173 / D 94 |
| swiftdc | body | C 12 / P 121 / W 216 / D 0 |

Previous swiftdc totals (2026-11-13): interface C 83 / P 0 / W 257 / D 9, body C 2 / P 66 / W 281 / D 0. 85 rows changed score.

173 swiftdc interface WRONGs and 137 body WRONGs are `W*` (the bare-`return` defect alone). Read as declines instead:

| tool | axis | alternative totals |
|---|---|---|
| swiftdc | interface | C 82 / P 0 / W 0 / D 267 |
| swiftdc | body | C 12 / P 258 / W 79 / D 0 |

### Body totals by fixture

| fixture | rows | Ghidra body C/P/W/D | swiftdc body C/P/W(of which W*)/D |
|---|---|---|---|
| frames.c | 99 | 66/8/25/0 | 0/28/71(47)/0 |
| frames2.c | 196 | 87/3/106/0 | 12/62/122(87)/0 |
| callers.c | 6 | 2/1/3/0 | 0/2/4(3)/0 |
| cond.c | 4 | 2/0/2/0 | 0/4/0(0)/0 |
| sframes.swift | 44 | 20/6/18/0 | 0/25/19(0)/0 |

## Where Ghidra beats swiftdc

1. **Return values of C functions (mid_frame, frames_O2; same defect in 137 rows).** Truth: `ldrsb x8, [sp, #0x3]`, `lsl x0, x8, #1`, `ret`, so it returns buf[3] * 2.
   Ghidra: `_sink(auStack_13b0,7); … return (long)local_13ad << 1;`
   swiftdc: `sink(…)` then `if (x10 != x9) { __stack_chk_fail() } else { return }`.
   swiftdc now ends a function with `return // x0 = <value>` when it can trace x0 (konst shows `x0 = 42`, two_args `x0 = (r0 + arg1)`), which cleared `W*` from 84 interface cells and 66 body cells. A value loaded from the frame or a global, or a result in d0, still prints a bare `return` with no `?`. That reads as void, and it accounts for 137 of swiftdc's 216 body WRONGs.
2. **Call arguments to an in-image double callee (caller_f, callers_O2).** Truth: `fmov d1, #2.0; bl _bigf`, so the call is bigf(x, 2.0).
   Ghidra: `dVar1 = (double)_bigf(param_1,0x4000000000000000);` (right values, but 2.0 is shown as raw bits).
   swiftdc: `bigf()`. Both arguments are silently dropped, although `bigf`'s body in the same image reads d0 and d1.
3. **Sanitizer calls with fabricated arguments (sink, f2_tsan).** Truth: `mov x0, x30; bl __tsan_func_entry; … bl __tsan_write8; str; bl __tsan_func_exit`. func_exit takes no arguments.
   Ghidra: `___tsan_func_entry(); ___tsan_write8(&_g_sink); _g_sink = param_2 ^ param_1; ___tsan_func_exit();`
   swiftdc: `__tsan_func_entry(?, arg1)`, `let r0 = __tsan_write8(0x80c0)`, `__tsan_func_exit(r0)`.
   swiftdc treats the void runtime hooks as taking leftover argument registers and producing values. This makes every swiftdc tsan body WRONG, and the same thing happens with the asan, cov and pcg hooks (`trace_pc_guard(0x8000, arg1)`, `report_store8(0x8148, arg1)`).

## Where swiftdc beats Ghidra

1. **Arguments that survive `___chkstk_darwin` (cbig, cond).** Truth: `cbz x0`, then chkstk (preserves x0), then `mov x1, x0; mov x0, sp; bl _sink`, so the call is sink(buf, n).
   Ghidra: `uVar1 = (*(code *)PTR____chkstk_darwin_00004000)(); _sink(auStack_11190,uVar1);`
   swiftdc: `if (x0 != 0) { sink(local_11190, arg0) }`.
   Ghidra models chkstk as an ordinary call that clobbers x0/x1 and returns a value. In every large-frame function at every optimisation level, it turns the preserved argument into "chkstk's result". That is the cause of most of Ghidra's 154 body WRONGs (big_frame, big_args, big_fp, alloca_after, big3, bigf, cbig, prof `tempAlloc`). It also drops parameters from the prototype (`long _big_frame(void)`, `void _vla_cond(long)` with `m` missing). swiftdc keeps `arg0`, or declines with `?`.
2. **Global identity at -Onone (consume, sf_Onone).** Truth: `bl blackHole.unsafeMutableAddressor; mov x8, x0; …; ldr x8, [x9]; adds; str x8, [x9]`, so blackHole += p + n.
   Ghidra: `blackHole::unsafeMutableAddressor(); … _swift_beginAccess(UVar1.unknown,…); *(undefined **)UVar1.unknown = local_60.unknown + *(long *)UVar1.unknown + param_2;` with `UVar1 = param_1`. This writes through the pointer argument instead of the global.
   swiftdc: `SF.blackHole.unsafeMutableAddressor()` then `mem64[x9] = x8` (raw registers, but nothing claimed that is false).
3. **Runtime call arguments (bigTuple, all -O/-Osize/sanitizer Swift builds).** Truth: `mov w0, #0x4; bl Array._allocateBufferUninitialized(minimumCapacity:)`.
   Ghidra: `Swift::Array<undefined>::_allocateBufferUninitialized(param_1, PTR___type_metadata_for_Swift_Int…)`. The capacity is shown as the caller's `a`.
   swiftdc: `static Swift.Array._allocateBufferUninitialized(minimumCapacity:)(4)`.
   At -Onone, Ghidra's `bigTuple` is worse still: `*(MACH_HEADER+1) = param_2` and `(*pcVar4)(auStack_70,0)` (calling a stack buffer). It also shows `swift_slowAlloc(size-0x401, size, -1)` in `tempAlloc`.
