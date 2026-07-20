# swiftdc — working agreement

A Swift-aware Mach-O decompiler. The goal is a **production** decompiler, not a
demo: something whose output can be trusted without cross-checking it by hand.

## Authority hierarchy

When sources disagree, believe them in this order. Lower ranks do not override
higher ones — they are hypotheses about them.

1. **Current source and tests** — what the code does at HEAD.
2. **Git history** — what changed, when, and why. `git log -S<symbol>` finds when
   a behavior appeared; commit messages carry the reasoning.
3. **Reproducible measurements** — a command anyone can re-run against a fixture.
4. **Research documentation** (`docs/research/`) — a record of what was true when
   written. Frequently stale. Verify before acting on it.
5. **Conversation memory** — the weakest source. A compacted conversation can
   preserve a "next task" that already shipped.

Docs are stale by default. Before acting on a documented claim, check it against
HEAD — and when it turns out stale, **fix the doc in the same change**. A
"CONFIRMED DEFECT" in `docs/research/` had already been fixed for many commits;
the trail is worth keeping, but its status header must be honest.

## The empty-result rule

**Never treat an empty or unusually small result as valid until it has been
cross-checked against independent binary evidence** — `LC_FUNCTION_STARTS`, the
symbol table, the export trie, or a raw `llvm-objdump` run.

This is not advice; it is a defect class that has already shipped. A parser that
failed on right-aligned address columns reported `// No functions matched.` on
every low-based dylib — 0 functions where the binary had 446. It read as a normal
answer, and no test caught it because every test passed a `--function` filter and
took a different code path.

Two consequences, both permanent:

- **In code**: an empty result must consult an oracle before being returned.
  `Disassembler.disassemble(path:)` throws `DisassembleError.parsedNothing` when
  objdump produced output, nothing parsed, and `LC_FUNCTION_STARTS` disagrees.
  Extend this pattern to any new recovery path.
- **In diagnostics**: never emit one message for several causes. "No function
  matched `<filter>`" and "this binary contains no recoverable functions" are
  different facts and must read differently. An analysis *failure* must never be
  spelled the same way as an empty *result*.

When a measurement looks surprisingly good or surprisingly bad, that is a
hypothesis to test, not a result to report.

## Priority ordering

Work on whatever most limits production readiness, in roughly this order.
Track state in [docs/PRODUCTION-READINESS.md](docs/PRODUCTION-READINESS.md).

1. **Soundness** — fabricated or misattributed semantics. A wrong render outranks
   an unnamed one. The project's core rule is *decline rather than guess*: an
   unprovable value renders `?`.
2. **Completeness** — silently omitted code or metadata (the class above).
3. **Robustness** — crashes, malformed input, unusual binaries, optimization levels.
4. **Determinism** — same input, same output.
5. **Correctness across optimization levels** — `-Onone` and `-O` lower differently;
   a fix proven at one level is not proven at the other.
6. **Test coverage for every CLI path** — including the unfiltered/whole-binary
   paths, which are the historically under-tested ones.
7. **Diagnostics** — distinguishing "nothing exists" from "analysis failed".
8. **Performance and memory** on large frameworks.
9. **Reconstruction quality** — readability, source-likeness. Real, but last.

Prettier output on a tool that silently under-recovers is worth nothing.

## Verification discipline

- **Prove a test catches the bug.** Break the fix, watch the test fail, restore
  it. A regression test never seen red is an assumption.
- **Measure, don't assert.** Numbers in docs get a reproducible command next to them.
- **Check the previously-working path** after any shared-code change.
- Fixture-based tests self-skip when the fixture is unbuilt (`…IfPresent`), so
  `swift test` stays green on a clean checkout. Build fixtures with
  `Fixtures/Sample/build.sh`.

## Build

```bash
swift build            # → .build/debug/swiftdc
swift test             # 111 tests
```

Requires Apple Silicon, Xcode 26 / Swift 6.3, `brew install capstone`
(and `openssl@3` for the device commands only).
