# Continuous integration

CI runs one thing: the enforcing test suite, on every push to `dev` and
every pull request. "Enforcing" means a missing fixture fails the run
instead of skipping its test.

The suite needs a recent Swift, because the fixtures are compiled from
source and some use new language features. GitHub's hosted macOS images
are behind: `macos-15` carries Swift 6.2.4, which cannot build the
fixtures, and `macos-26` jobs were never given a runner when tried
(2026-11-13). So a repository that wants a passing run uses its own Mac
as the runner. That applies to a fork as much as to the main
repository: each copy sets up its own.

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
by `Tools/fixtures.sh`, which caches by the content of each source and
its build line. A cached fixture built by another compiler is not
rebuilt, so after changing Xcode clear `~/Library/Caches/swiftdc-fixtures`.

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
