# Contributing to swiftdc

Thanks for helping. swiftdc is trying to be a decompiler whose output you can
trust without checking it by hand, and most of what follows exists to protect
that.

If you want somewhere to start, take an issue labelled
[good first issue](https://github.com/CamdenBopp/swiftdc/labels/good%20first%20issue).
Each one says what's wrong, how to see it, and what done looks like.
[help wanted](https://github.com/CamdenBopp/swiftdc/labels/help%20wanted)
issues are bigger. Comment on an issue before you start, so two people don't
do the same work.

By contributing, you agree your work is released under the [MIT license](LICENSE)
and that you'll follow the [code of conduct](CODE_OF_CONDUCT.md).

## The rule: decline rather than guess

If swiftdc can't prove a value, it prints `?`. It never prints a plausible
name, argument or condition that metadata or data flow didn't justify. A wrong
render is worse than an unnamed one, because a reader has no way to tell it's
wrong.

In practice:

- When a change makes more output appear, show why each new piece is proven.
- A change that turns a correct `?` into a guess will be turned down, however
  readable the guess is.
- An empty or unexpectedly small result is a claim to check, not an answer.
  Cross-check it against the binary itself (`LC_FUNCTION_STARTS`, the symbol
  table, the export trie, or `llvm-objdump`). swiftdc once reported zero
  functions in a dylib that had 446, and nothing caught it.
- "Nothing matched" and "analysis failed" must read differently in output and
  diagnostics.

When priorities conflict, use this order: soundness, completeness,
robustness, determinism, then readability. [CLAUDE.md](CLAUDE.md) has the
full version. It's written as instructions for the AI agents that work on
this repository, so parts of it (the host's memory limits, who may push
where) are about the maintainer's machine, not yours. The rules about
soundness and verification apply to everyone.

## Setup

You need an Apple Silicon Mac, Xcode 26 (Swift 6.3) and Go:

```bash
brew install go
```

swiftdc itself needs only Xcode: SwiftPM builds Capstone from source, so
there's no Homebrew Capstone to install. Go builds the Go fixtures, which the
enforcing test run requires. `openssl@3` is needed only for the `devices`
and `apps` commands.

Clone this repository, not your fork, and work from `dev`. `master` is a
snapshot that doesn't share dev's history, so a branch cut from it carries
snapshot commits that dev doesn't have. `Tools/test.sh affected` also compares your work
against `origin/dev`, so `origin` should point here:

```bash
git clone https://github.com/CamdenBopp/swiftdc.git
```

```bash
cd swiftdc
```

```bash
git switch dev
```

Then fork on GitHub and add the fork as a second remote, which is where
you'll push your branch:

```bash
git remote add fork https://github.com/YOUR-NAME/swiftdc.git
```

Build the test fixtures once, then build swiftdc:

```bash
Tools/fixtures.sh
```

```bash
swift build
```

The first run of each fetches and compiles everything from scratch, so
expect it to take a while.

`Tools/fixtures.sh` caches fixture builds by content, so it only runs
`Fixtures/Sample/build.sh` when the fixture sources or toolchain have
changed. Calling `build.sh` directly also works.

## Running tests

```bash
Tools/test.sh affected
```

That runs the tests for the subsystems your change touches. The other tiers:

| Command | Runs |
|---|---|
| `Tools/test.sh file <NameTests>` | One test file |
| `Tools/test.sh <subsystem>` | One of `arm64 abi tracer cflow meta render audit` |
| `Tools/test.sh quick` | Nearly everything, in about 100 seconds |
| `Tools/test.sh full` | The enforcing suite. Run this before you open a pull request |

Most tests need fixtures, and they skip quietly when the fixtures are missing,
so a plain `swift test` on a fresh clone is green but proves little. Every
`Tools/test.sh` tier sets `SWIFTDC_REQUIRE_FIXTURES=1`, which turns a missing
fixture into a failure.

## Making a change

**One behaviour per change.** A fix and a cleanup are two pull requests. A
refactor that only prepares later work lands on its own, labelled as one.

**Prove the test catches the bug.** Add a test, break your fix, watch the test
fail, then restore it. A regression test nobody has seen fail is an
assumption. Say in the commit message that you did this.

**Check every entry point.** swiftdc has many subcommands (`disasm`, `dump`,
`layout`, `interface`, `objc` and more), and several of them share code. A fix
proven through one subcommand isn't proven for the others. Some reach the
binary through `llvm-objdump` and some go straight to the parser, so they
fail differently.

**Check both optimization levels.** `-Onone` and `-O` compile the same source
very differently. Fixtures are usually built at both, and a fix proven at one
level is untested at the other.

**Explain every changed line of output.** `Tools/blast-radius.sh` renders
every fixture with two swiftdc binaries and diffs the results:

```bash
Tools/blast-radius.sh <old-swiftdc> <new-swiftdc> <outdir>
```

Copy each binary out of `.build` before running it. Every line that changes
belongs in your commit message, whether you meant to change it or not.

**Fix stale docs in the same change.** `docs/PRODUCTION-READINESS.md` tracks
what's open and fixed. When your change fixes an entry, mark it there. When
you find an entry that's wrong, correct it, even if your change didn't cause
the problem.

## Commit messages

The subject says what changed and names the axis it serves in parentheses:
`soundness`, `completeness`, `robustness`, `correctness`, `speed`, `refactor`
or `docs`.

The body is an engineering record. Write it for someone running `git log -S`
a year from now. A real example, slightly trimmed:

```text
Treat swift_willThrow as returning nothing (soundness)

Symptom: ThrowSelect.plainThrow (throwselect.swift, -O) throws E(code:
x) when x < 0 and returns x * 3 otherwise; the throw falls into the
normal epilogue and shares its `ret`. It read `let r1 =
swift_willThrow(r0)` ... `return ((arg0 < 0) ? r1 : (arg0 + (arg0 <<
1)))`: the throwing path's x0 as a result.

Mechanism: the tracer marks a call void only from a Swift signature or
an ObjC selector, so swift_willThrow's x0 was `.callResult`.

Change: voidRuntimeCalls (swift_willThrow, swift_willThrowTypedImpl,
swift_job_run, all `void`) feed returnsVoidByName. The call renders as
a statement and the exit as `return ?`.

Blast radius (--structured, against 0488667): fixtures, the two
plainThrow lines above; swift-syntax byte-identical.

Verified: aThrowingPathsX0IsNoResultIfPresent red with the set removed
(2 issues); enforcing suite 970 tests green.
```

Not every change needs all five parts. Every change needs `Verified:`.

When a change that should have helped didn't, write that down too: in the
pull request, or in `docs/research/`. A recorded dead end saves the next
person from retrying it.

## Pull requests

- Push your branch to your fork and open the pull request against `dev`.
  That's where development happens; `master` is a periodic snapshot of it.
- There's no CI yet, so nothing checks a pull request automatically. Run
  `Tools/test.sh full` yourself before you open one.
- Include what you ran: the test tier, and the blast-radius counts if output
  changed.
- Before merging, the maintainer runs `Tools/integration-gate.sh`: the full
  suite, plus a blast-radius check and a performance budget against the
  current `dev`. You can run it yourself without `--push`. It's slow, and you
  don't have to.
- If your change deliberately costs speed or memory, say why in a
  `Perf-cost: <reason>` line in the commit message.

## Reporting a bug

Include the binary or the source that produces it, how you built it (compiler
version and optimization level), the exact swiftdc command, what it printed,
and what you expected. Most bugs get fixed by first adding a small fixture
under `Fixtures/Sample/` that reproduces them, so a minimal Swift or
Objective-C source file is the most useful thing you can attach.

Don't attach binaries you aren't allowed to share, such as App Store apps.
Describe the pattern instead, or rebuild it from your own source.

## Questions

Open an issue. If you aren't sure whether something is a bug, ask anyway.
