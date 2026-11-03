#!/bin/bash
# Restore Fixtures/Sample's built products from a content-addressed cache,
# running build.sh only when no build exists for this exact input.
#
#   Tools/fixtures.sh            restore, building on a miss
#   Tools/fixtures.sh --key      print the key and exit
#   Tools/fixtures.sh --rebuild  build even on a hit, then restore
#
# The key hashes every tracked or untracked-but-not-ignored file under
# Fixtures/Sample (working-tree contents, so an uncommitted edit is a new
# key), the toolchain (swiftc, clang, both SDKs, the host OS, go) and a
# schema number. The build runs in a private copy of those files, so the
# worktree's own directory is never half-built, and the result lands in
# the cache by an atomic rename. Restoring is an APFS clone (cp -c), so
# every worktree shares one copy on disk.
#
# Products differ between two builds only in LC_UUID and debug stabs
# (45 of 243 files); every swiftdc view of them is identical
# (measured 2026-11-02), so a cached build stands in for a fresh one.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
fixtures=Fixtures/Sample
cache=${SWIFTDC_FIXTURE_CACHE:-$HOME/Library/Caches/swiftdc-fixtures}
schema=1
keep=8

inputs() {
  git -C "$repo" ls-files -z --cached --others --exclude-standard -- "$fixtures" |
    while IFS= read -r -d '' f; do [ -f "$repo/$f" ] && printf '%s\0' "$f"; done |
    sort -z
}

key() {
  {
    echo "schema $schema"
    (cd "$repo" && inputs | xargs -0 shasum -a 256)
    xcrun swiftc --version 2>&1
    xcrun clang --version 2>&1
    echo "macosx $(xcrun --sdk macosx --show-sdk-build-version)"
    echo "iphonesimulator $(xcrun --sdk iphonesimulator --show-sdk-build-version 2>/dev/null || echo none)"
    echo "host $(sw_vers -buildVersion)"
    if command -v go > /dev/null; then go version; else echo "no go"; fi
  } | shasum -a 256 | cut -c1-20
}

lock() {
  mkdir -p "$cache"
  while ! mkdir "$cache/$1.lock" 2> /dev/null; do
    owner=$(cat "$cache/$1.lock/pid" 2> /dev/null || true)
    if [ -n "$owner" ] && ! kill -0 "$owner" 2> /dev/null; then
      echo "fixtures: removing a stale lock left by pid $owner" >&2
      rm -rf "$cache/$1.lock"
      continue
    fi
    sleep 1
  done
  echo $$ > "$cache/$1.lock/pid"
  trap 'rm -rf "$cache/$k.lock"' EXIT
}

build() {
  local work
  work=$(mktemp -d "$cache/build.XXXXXX")
  (cd "$repo" && inputs | rsync -a --from0 --files-from=- ./ "$work/src/")
  echo "fixtures: building $1 in $work" >&2
  local start=$SECONDS
  if ! "$work/src/$fixtures/build.sh" > "$work/build.log" 2>&1; then
    echo "fixtures: build.sh failed; log at $work/build.log" >&2
    exit 1
  fi
  # Everything build.sh left beside the inputs is a product.
  (cd "$repo" && inputs | tr '\0' '\n') | sed "s|^|$work/src/|" > "$work/inputs"
  find "$work/src/$fixtures" -type f | grep -vxF -f "$work/inputs" > "$work/products" || true
  if [ ! -s "$work/products" ]; then
    echo "fixtures: build.sh produced nothing; log at $work/build.log" >&2
    exit 1
  fi
  mkdir -p "$work/out"
  (cd "$work/src/$fixtures" && sed "s|^$work/src/$fixtures/||" "$work/products" |
    rsync -a --files-from=- ./ "$work/out/")
  cp "$work/build.log" "$work/out/.build.log"
  rm -rf "$cache/$1"
  mv "$work/out" "$cache/$1"
  rm -rf "$work"
  echo "fixtures: built $1 ($(wc -l < "$cache/$1/.build.log" | tr -d ' ') log lines) in $((SECONDS - start)) s" >&2
  # Keep the most recently used builds.
  ls -1t "$cache" | grep -vE '\.lock$|^build\.' | tail -n +$((keep + 1)) |
    while read -r old; do rm -rf "${cache:?}/$old"; done
}

restore() {
  # Remove only git-ignored files: the products of whatever build was here.
  git -C "$repo" clean -fdqX -- "$fixtures"
  cp -c -R "$cache/$1/" "$repo/$fixtures/"
  rm -f "$repo/$fixtures/.build.log"
  touch "$cache/$1"
}

mode=${1:-}
k=$(key)
case $mode in
  --key) echo "$k"; exit 0 ;;
  --rebuild|"") ;;
  *) echo "usage: $0 [--key|--rebuild]" >&2; exit 2 ;;
esac

lock "$k"
if [ "$mode" = --rebuild ] || [ ! -d "$cache/$k" ]; then
  build "$k"
else
  echo "fixtures: cache hit $k" >&2
fi
restore "$k"
