# Scoring rubric (shared by every scorer; apply it identically to both tools)

Root: <scratch> (call it $S)

Inputs
- Fixture sources and dylibs: $S/abi2/<area>/ . Source comments state the true behaviour. Dylib names encode the opt level.
- Ghidra 12.2: $S/ghidra/cmp/<area>.<dylib-basename>.ghidra.c (per function: `=== addr name`, `// signature:` line, decompiled C).
- swiftdc: $S/ghidra/cmp/<area>.<dylib-basename>.swiftdc.txt (`disasm --structured`).
- Ground truth: source + comments, and `xcrun llvm-objdump -d --no-show-raw-insn <dylib>` (add `--disassemble-symbols=<mangled>` to narrow), `xcrun swift-demangle`, `xcrun llvm-objdump --section=__TEXT,__cstring -s` / `__swift5_reflstr` etc. for literal bytes. When unsure, READ THE ASM.
- Read-only: never edit or build anything in the swiftdc checkout. Write only under $S/ghidra/scores/parts/.

Which functions
- Score every public, user-written function, in every build assigned to you. Include user `init()` (if only `__allocating_init` survives, score that), user methods, user computed properties (e.g. `unownedExecutor` getter), user top-level functions including `@inline(never)` sinks.
- Also score user-written closure bodies emitted as their own function (e.g. `closure #1 in groupSum`, `implicit closure #1 in asyncLetMul`, `closure #1 in spawn`) as separate rows named `closure #N in f`.
- Skip: stored-property getters/setters/modify accessors, value witnesses, metadata accessors, outlined copies/destroys, `__swift_*` helpers, protocol witness thunks, partial-apply forwarders, reabstraction thunks, one-time initializers, `variable initialization expression`, deinit, memberwise inits, Error witness getters.
- Async functions: score the function as a whole across all its funclets (`.resume.N`, `TQ0_`/`TY0_` pieces, Ghidra's separate `sub_`/funclet entries). A wrong statement in any funclet makes the body WRONG.
- If a function is absent from a tool's output entirely (not emitted at that level, e.g. inlined away), it is absent for both: omit the row. If present in the binary but missing from one tool's output, score that tool DECLINED/DECLINED and note it.

Axis 1, interface (parameters and result)
- What counts as the tool's interface claim: for Ghidra, the C prototype (`// signature:` line and the function's declaration line); the `/* demangled */` comment is just symbol text and does not rescue a wrong prototype. For swiftdc, its header line (the demangled signature) plus any parameter/return registers its body shows.
- CORRECT: parameter count, which values/registers, self, and the result type/arity all match the binary.
- WRONG: shows a parameter the code does not take, misses one it reads, puts a value in the wrong register, or claims a wrong result type/arity (e.g. `void` for a function returning Int, a String result split wrong).
- DECLINED: shows unknowns: `?`, raw `in_x0`/`unaff_x20`/`x20`-style registers standing in for a parameter or self or the async context. Raw registers count as DECLINED for that value, not WRONG.
- Precedence: any WRONG piece -> WRONG; else any DECLINED piece -> DECLINED; else CORRECT.
- Swift calling convention facts: self in x20 (methods, actors); async context in x22; error out in x21; String = 2 regs (x0,x1); async functions return via the continuation (result in x0.. at the resume call). An extra hidden parameter shown with a correct role is fine; an extra parameter that the code does not read is WRONG.

Axis 2, body
- CORRECT: every statement and the returned value are semantically right. Names may differ. Raw offsets are fine if right. A string literal must be byte-exact (escapes must denote the right bytes).
- WRONG: any statement, value, condition, callee, argument, or string contradicted by the binary, or user-visible code silently missing (e.g. a call dropped, an argument dropped, the return value missing or wrong, a branch missing).
- PARTIAL: right, but with some `?`/unresolved pieces (raw registers, `DAT_`/`_UNK_` loads of a constant, undecoded raw string bits that are numerically correct) and nothing wrong.
- DECLINED: essentially nothing recovered (empty body, only `?`, or only raw noise for a function that does real work).
- Specific conventions (apply to both tools):
  - A string literal shown only as its correct raw immediate bits (e.g. `0xe500000000000000`) = unresolved -> at best PARTIAL.
  - A constant rendered as the address of an unrelated symbol (e.g. `&MACH_HEADER.cpusubtype + 2`, `&segment_command_00000020` for an integer/discriminator) is a false claim -> WRONG.
  - A call whose argument list drops an argument the callee takes (e.g. `print(items, separator)` with the terminator missing) -> WRONG.
  - Runtime retain/release noise may be shown or hidden; neither is wrong.
  - Ghidra `halt_baddata()` / `UNRECOVERED_JUMPTABLE` / warnings that truncate the body: whatever follows is missing -> WRONG if user code is lost, DECLINED if nothing was recovered.
  - For async: tail-calling the continuation with the result counts as "return value"; the result must be identifiable and correct. An await of a callee must name the right callee.
  - Isolation hops (swift_task_switch to an executor) are part of the body; a missing or misattributed hop that the binary performs is WRONG only if the tool claims something contradictory (e.g. names the wrong executor); omitting pure runtime plumbing is fine.
- Be strict and symmetric. A plausible-looking guess that is wrong is WRONG.

Output (per chunk): $S/ghidra/scores/parts/<area>-<chunk>.md containing
1. A markdown table with exactly these columns:
   `| function | level | Ghidra interface | Ghidra body | swiftdc interface | swiftdc body | note |`
   values from {CORRECT, PARTIAL, WRONG, DECLINED} (PARTIAL only for body). Note only when not all four CORRECT: one line naming the concrete reason, e.g. `G drops print terminator; S shows x20/x19 for s`.
2. Totals per tool per axis for your chunk.
3. "Candidate examples": up to 3 where Ghidra beats swiftdc and up to 3 where swiftdc beats Ghidra, each quoting both outputs briefly (a line or two) and the truth (asm or source), with function+level.

Addendum for the 2026-11-13b re-score (swiftdc columns only)
- swiftdc now ends a function it has no signature for with `return // x0 = <value>`: a comment stating what x0 holds at the return, explicitly not a claim that the function returns it. Score it as follows, and no more generously:
  - Interface: it shows no result claim, so the result is DECLINED (not WRONG, and not CORRECT). Parameters are scored as before.
  - Body: the commented value counts as the shown result value. If it equals the true returned value and everything else is right: CORRECT. If the value is wrong: WRONG. If it contains `?` pieces: PARTIAL.
  - A value-returning function that still ends in a bare `return` or shows no value at all is unchanged: WRONG on both axes, as before.
- `let rN = call(…)` followed by a use of `rN` is one call, spelled once.
- Ghidra's columns are not re-scored: copy them unchanged from the previous table. Ghidra's renders are unchanged.
