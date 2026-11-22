# Continuous integration

CI runs one thing: the enforcing test suite, on every push to `dev` and
every pull request. "Enforcing" means a missing fixture fails the run
instead of skipping its test.

The Build step keeps Swift's real exit status while logging through `tee`.
A nonzero build fails the step even without an `error:` message, so the
suite cannot run an older test binary after that failure. The `suite-log`
artifact retains `build.log` and any `suite.log` produced by the run.

The latest verified published result is
[run 44998598514 at `1fc51d3`](https://github.com/CamdenBopp/swiftdc/actions/runs/44998598514):
**2,069 fixture-enforced tests / 43 suites (1,893.323 s)**. The
exit-status fix `f25575f` passed 2,075 local tests and its shell failure
controls and was published in `72c9879` through the original release gate.
Its [hosted run 45012625048](https://github.com/CamdenBopp/swiftdc/actions/runs/45012625048)
is still in progress; hosted verification remains pending.
See [current status](STATUS.md#current-status) for later qualifications.
The older job notes below are historical, including their pending labels.

The suite needs Swift 6.4 or newer because its fixtures are compiled from
source. The hosted workflow requests GitHub's documented `xcode-27` ARM64
preview image and selects `/Applications/Xcode_27.1.app`, the locally tested
Xcode version. The image also includes newer Xcodes, so selecting the highest
installed version would change the compiler that builds the fixtures.
See the [image inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
and [supported runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
The preview is provided as available; a documented image is not proof that
this repository has acquired a runner or passed its suite.

A repository can instead use its own Apple Silicon Mac by setting
`SWIFTDC_SELF_HOSTED=true` after setup below. That route keeps the selected
local Xcode and runs the same Toolchain, Fixtures, Build and Enforcing suite
steps. Each fork chooses and configures its own runner.

The previous hosted fallback, `macos-15`, selected Xcode 26.3 / Swift 6.2.4
and failed Toolchain before any fixtures, build or tests ran. The completed
[run 44400919902 at published 6c40aea](https://github.com/CamdenBopp/swiftdc/actions/runs/44400919902)
confirms this in its job logs. The original local integration gate passed
all 1,993 tests / 43 suites before that push; it is not a hosted CI pass.
An earlier `macos-26` job remained queued without a runner for 50 minutes
on 2026-11-13. The new
[run 44411756483 at published d69fff8](https://github.com/CamdenBopp/swiftdc/actions/runs/44411756483)
completed successfully. The decoded job logs confirm an `xcode-27` runner
with Xcode 27.1 / Swift 6.4, arm64 macOS 27.0.1, Go 1.27.4, 7 GB memory and
36 GB free disk. Toolchain, Fixtures and Build passed, followed by the full
fixture-enforced **1,993 tests / 43 suites (2,253.679 s)**. Both the terminal
job state and the logs were checked. The original local gate independently
passed the same suite before pushing, with unchanged fixture/SDK outputs and
all 2,896 paired cost rows. This hosted result covers published `d69fff8`;
later revisions require their own run results.

Published `a841357` passed its independent local gate and then
[hosted run 44423167838](https://github.com/CamdenBopp/swiftdc/actions/runs/44423167838):
**2,000 tests / 43 suites (2,384.404 s)** with fixture presence enforced.
Toolchain, Fixtures, Build and Enforcing suite completed successfully. The
terminal job status and decoded logs were checked. This covers code
`3385323`. The argument-view change (`8a15928`) was subsequently published
at `5c5ab71` through the original gate, which independently passed **2,005
tests / 43 suites (946.199 s)** and every default output/cost check. New
[hosted run 44448308320](https://github.com/CamdenBopp/swiftdc/actions/runs/44448308320)
completed successfully. Terminal job state and decoded logs confirm
fixture-enforced **2,005 tests / 43 suites (1,938.195 s)**, with Toolchain,
Fixtures, Build and Enforcing suite all passing. This hosted result covers
published code `8a15928`. The receiver-alignment change `dbbdc83` then
passed **2,007 tests / 43 suites (911.246 s)** locally and the original
integration gate independently passed **2,007 / 43 (967.051 s)**, all
reviewed outputs and all **3,052 default cost rows**, publishing `83443a5`.
New [hosted run 44456365627](https://github.com/CamdenBopp/swiftdc/actions/runs/44456365627)
is in progress at that head. Its terminal job/logs still require observation;
the local and gate results are not a hosted 2,007-test result.

## The environment

| | Tested with | Required |
|---|---|---|
| Machine | Apple Silicon | Apple Silicon |
| Swift | 6.4 (Xcode 27.1) | 6.4 or newer; 6.2.4 fails, 6.3 is untried |
| Go | 1.27 | any, on the `PATH` (for the Go fixtures) |
| Free disk | | 15 GB |

Check a machine, and print exactly what it has:

```bash
Tools/ci/environment.sh
```

It exits non-zero and says what to fix when the suite cannot pass there.
Every CI run starts with it, so the log of a run records the toolchain
that produced it. When two runs disagree, compare those lines first: a
fixture can lower differently under another compiler.

Dependencies are pinned by `Package.resolved`, and the fixtures are built
by `Tools/fixtures.sh`. Its cache key includes every fixture input, the
Swift and Clang versions, both SDK builds, the host OS build, and the Go
version. A change to those recorded versions changes the key, and a cache
miss triggers a build; clearing the cache after an Xcode change is unnecessary.

## Running the suite by hand

The same commands CI runs:

```bash
Tools/ci/environment.sh
```

```bash
Tools/fixtures.sh
```

```bash
swift build --build-tests
```

```bash
SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build
```

## Setting up a runner

One script walks through it and asks before each step:

```bash
Tools/ci/setup-runner.sh
```

It needs the GitHub CLI, signed in (`gh auth login`), and it acts on the
repository `gh repo view` reports, so run it inside your own clone. It:

1. checks the machine with `Tools/ci/environment.sh`;
2. explains who will be able to run code on it, and for a public
   repository offers to tighten the approval policy (below);
3. downloads GitHub's runner and verifies its SHA-256 against the one
   GitHub publishes for that release;
4. registers the Mac to the repository with the label `swiftdc`;
5. sets the repository variable `SWIFTDC_SELF_HOSTED` to `true`, which
   is what makes the workflow use the runner;
6. tells you how to start it.

By default you start the runner yourself when you want CI to run
(`./run.sh` in its directory) and a push made while it is stopped waits.
For one that is always on:

```bash
Tools/ci/setup-runner.sh --service
```

To undo everything it registered:

```bash
Tools/ci/setup-runner.sh --remove
```

## Who can run code on the runner

A self-hosted runner executes what a workflow run tells it to, as your
user. Two cases:

- **Your own pushes** run at once. Only people with write access can
  push, and nothing asks for approval.
- **A pull request from a fork** can change the workflow it runs. GitHub
  holds the run until someone with write access approves it. On a public
  repository set the policy to "Require approval for all external
  contributors" (Settings, Actions, General), which the setup script
  offers to do. The default only holds first-time contributors, so
  someone with one merged pull request could run code on your Mac
  unasked.

Approving a fork's run means running its code on your machine. Read its
changes to `.github/` and `Tools/` first.

## What CI does not run

The local gate, `Tools/integration-gate.sh`, also builds a release
binary, renders every fixture with it and with the previous commit's
binary, and checks the cost budget. That needs the previous binary and
is not repeated in CI. A push to `dev` goes through the gate first; CI is
the independent second run of the suite.
