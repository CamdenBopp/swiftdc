# Contributing to swiftdc

Thanks for helping. swiftdc is trying to be a decompiler whose output you can
trust without checking it by hand, and most of what follows exists to protect
that.

## Start here

Try the [Swift fixture walkthrough](README.md#what-the-output-looks-like) on
`dev`. For a wrong result, compare a single rendered function with its fixture
source or annotated disassembly. Capture the exact command and a short,
shareable excerpt using the [bug report fields](.github/ISSUE_TEMPLATE/bug.yml).

For a smaller check without a Swift build, run
`bash Tools/test-tier-contract.sh` with Bash, Git and Python 3. It checks test
selection in a temporary Git repository. A focused correction to a documented
command or fixture example is also welcome.

Browse the [open issues](https://github.com/CamdenBopp/swiftdc/issues) for
work tagged `good first issue` or `help wanted`. Comment on an issue before
starting so contributors can coordinate.

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

The fixture-enforced suite requires an Apple Silicon Mac, Swift 6.4 or
newer, Go on `PATH`, Unicorn where `pkg-config` finds it, and at least 15 GB of free disk. The tested toolchain
is Xcode 27.1 with Swift 6.4. Check your selected toolchain before
building. [CI environment and toolchain](docs/CI.md#the-environment)

```bash
Tools/ci/environment.sh
```

Install Go and Unicorn if needed.

```bash
brew install go unicorn pkgconf
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
git clone --branch dev https://github.com/CamdenBopp/swiftdc.git
cd swiftdc
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

`Tools/fixtures.sh` restores a content-addressed fixture build. It runs
`Fixtures/Sample/build.sh` on a cache miss or with `--rebuild`.

See [dependency maintenance](docs/CI.md#dependency-maintenance) before changing a package pin.

## Running tests

```bash
Tools/test.sh affected
```

Affected mode selects mapped subsystems, changed test files, Determinism
and FixturePresence. It checks branch changes against origin/dev as well as
staged, unstaged and untracked changes. Unmapped source and shared test/build
inputs trigger the full suite.

| Command | Runs |
|---|---|
| `Tools/test.sh file <NameTests>` | One test file |
| `Tools/test.sh <subsystem>` | One of `arm64 abi tracer cflow meta render audit` |
| `Tools/test.sh quick` | The suite with the dyld-cache memory and selected Go tests skipped for iteration |
| `Tools/test.sh full` | The enforcing suite. Run this before you open a pull request |

Most tests need fixtures, and they skip quietly when the fixtures are missing,
so a plain `swift test` on a fresh clone is green but proves little. Every
`Tools/test.sh` tier sets `SWIFTDC_REQUIRE_FIXTURES=1`, which turns a missing
fixture into a failure.

Run `bash Tools/test-tier-contract.sh` to check test selection and fallback
behavior with a Swift stub in an isolated Git repository. This self-test
requires Bash, Git and Python 3. It runs without decompiler tests or fixtures.

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

**Check all three Swift optimization levels.** Test `-Onone`, `-O` and
`-Osize` for ABI changes. The same source can lower differently at each level.

**Explain every changed line of output.** `Tools/blast-radius.sh` renders
every fixture with two swiftdc binaries and diffs the results:

```bash
Tools/blast-radius.sh <old-swiftdc> <new-swiftdc> <outdir>
```

Build releases with `--scratch-path .build-release` and copy both binaries
out before running the comparison. Every line that changes
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
- GitHub Actions runs the fixture-enforced suite on pull requests and
  pushes to `dev`. Fork pull requests can require a maintainer's approval
  before running. Run `Tools/test.sh full` locally before opening a pull
  request. [CI workflow and runner setup](docs/CI.md)
- Include what you ran: the test tier, and the blast-radius counts if output
  changed.
- Before merging, the maintainer runs `Tools/integration-gate.sh`: the full
  suite, plus a blast-radius check and a performance budget against the
  current `dev`. You can run it yourself without `--push`. It's slow, and you
  don't have to.
- If your change deliberately costs speed or memory, say why in a
  `Perf-cost: <reason>` line in the commit message.

## Reporting a bug

Use the [bug report fields](.github/ISSUE_TEMPLATE/bug.yml) to collect the
command, revision and evidence when [opening an issue](https://github.com/CamdenBopp/swiftdc/issues/new).
Unknown environment details are accepted; a shareable binary upload is optional.
The guided form becomes available on GitHub when it reaches the default branch.

For a wrong body, see [Debug a wrong pseudocode render](docs/DEBUGGING-PSEUDOCODE.md)
for a fixture walkthrough and a focused regression test.

Include the binary or the source that produces it, how you built it (compiler
version and optimization level), the exact swiftdc command, what it printed,
and what you expected. Most bugs get fixed by first adding a small fixture
under `Fixtures/Sample/` that reproduces them, so a minimal Swift or
Objective-C source file is the most useful thing you can attach.

Don't attach binaries you aren't allowed to share, such as App Store apps.
Describe the pattern instead, or rebuild it from your own source.

## Questions

Open an issue. If you aren't sure whether something is a bug, ask anyway.
