#!/bin/bash
# The one gate every change passes before it reaches origin/dev.
#
#   Tools/integration-gate.sh          check HEAD against origin/dev
#   Tools/integration-gate.sh --push   check, then push HEAD to dev
#
# One gate runs at a time on this host (a lock), so two agents never
# measure or push over each other. It checks the committed HEAD of the
# worktree it is called from, in a worktree of its own ($SWIFTDC_GATE_TREE,
# default <repo>-gate, created on first use and kept for its incremental
# builds), so the caller can keep editing and building while it runs.
# Never edit in the gate's tree: each run resets it to the commit under
# test. In order:
#
#   1. HEAD fast-forwards origin/dev (rebase first if it does not).
#   2. Fixtures come from the content-addressed cache (Tools/fixtures.sh).
#   3. The full enforcing suite, while the release build runs beside it
#      in .build-release.
#   4. Blast radius against origin/dev's release binary, all four views,
#      fixtures and the swift-syntax dylibs. Every changed line must be
#      explained in its commit; the gate prints the counts and the diffs'
#      paths, it cannot judge them.
#   5. With --push: git push origin HEAD:dev.
#
# Release binaries are kept per commit under $SWIFTDC_BINARY_CACHE, so the
# next gate's baseline is usually already built. A missing baseline is
# built once in a temporary worktree.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
push=0
case ${1:-} in --push) push=1 ;; "") ;; *) echo "usage: $0 [--push]" >&2; exit 2 ;; esac

bins=${SWIFTDC_BINARY_CACHE:-$HOME/Library/Caches/swiftdc-binaries}
lockdir=${SWIFTDC_GATE_LOCK:-$HOME/Library/Caches/swiftdc-gate.lock}
mkdir -p "$bins"
until mkdir "$lockdir" 2> /dev/null; do
  owner=$(cat "$lockdir/pid" 2> /dev/null || true)
  if [ -n "$owner" ] && ! kill -0 "$owner" 2> /dev/null; then rm -rf "$lockdir"; continue; fi
  echo "gate: waiting for pid ${owner:-?}" >&2
  sleep 10
done
echo $$ > "$lockdir/pid"
trap 'rm -rf "$lockdir"' EXIT

step() { echo "gate: [$((SECONDS))s] $*" >&2; }
fail() { echo "gate: FAILED: $*" >&2; exit 1; }

# 1. Shape of the change, then the gate's own tree at that commit.
git fetch -q origin dev
base=$(git rev-parse origin/dev)
head=$(git rev-parse HEAD)
git merge-base --is-ancestor "$base" "$head" || fail "HEAD does not fast-forward origin/dev; rebase onto it"
[ "$base" != "$head" ] || fail "nothing to integrate: HEAD is origin/dev"
tree=${SWIFTDC_GATE_TREE:-$repo-gate}
if ! git -C "$tree" rev-parse --git-dir > /dev/null 2>&1; then
  step "creating the gate tree $tree (its first build is cold)"
  git worktree add -q --detach "$tree" "$head"
fi
git -C "$tree" checkout -q --detach --force "$head"
git -C "$tree" clean -fdq
cd "$tree"
out=${SWIFTDC_GATE_OUT:-$tree/.build/gate}/$(git rev-parse --short HEAD)
rm -rf "$out"; mkdir -p "$out"
step "$(git rev-list --count "$base..$head") commit(s) over origin/dev, in $tree; output in $out"

release() { # release <sha> <scratch-path> <source-dir>
  (cd "$3" && swift build -c release --scratch-path "$2" > "$out/release-$1.log" 2>&1) ||
    return 1
  mkdir -p "$bins/$1"
  cp "$2/release/swiftdc" "$bins/$1/swiftdc.tmp" && mv "$bins/$1/swiftdc.tmp" "$bins/$1/swiftdc"
}

# 2. Fixtures.
step "fixtures"
Tools/fixtures.sh 2> "$out/fixtures.log" || fail "fixtures (see $out/fixtures.log)"

# 3. Suite, with the head's release build beside it.
step "release build of HEAD (background) and debug build"
release "$head" "$tree/.build-release" "$tree" &
rel=$!
swift build --build-tests > "$out/build.log" 2>&1 || fail "debug build (see $out/build.log)"
step "full enforcing suite"
if ! SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build > "$out/suite.log" 2>&1; then
  grep -E "✘|failed" "$out/suite.log" | head -20 >&2
  fail "suite (see $out/suite.log)"
fi
grep -E "Test run with" "$out/suite.log" >&2 || true
wait $rel || fail "release build (see $out/release-$head.log)"

# 4. Blast radius against origin/dev.
if [ ! -x "$bins/$base/swiftdc" ]; then
  step "building the baseline $base in a temporary worktree"
  wt=$(mktemp -d "${TMPDIR:-/tmp}/swiftdc-gate-base.XXXXXX")
  git worktree add -q --detach "$wt" "$base"
  release "$base" "$wt/.build-release" "$wt" || { git worktree remove --force "$wt"; fail "baseline build"; }
  git worktree remove --force "$wt"
fi
step "blast radius"
Tools/blast-radius.sh "$bins/$base/swiftdc" "$bins/$head/swiftdc" "$out/blast" --real | tee "$out/blast.txt" >&2
if grep -q '^+rc=13[0-9]' "$out/blast/"*.diff 2> /dev/null; then
  fail "a render that did not trap before traps now (grep rc=13 in $out/blast)"
fi

# 5. Push.
if [ $push = 1 ]; then
  step "pushing $head to origin/dev"
  git push origin "$head:refs/heads/dev"
fi
step "passed"
