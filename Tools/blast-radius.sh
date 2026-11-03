#!/bin/bash
# Render every fixture (and optionally the toolchain's swift-syntax dylibs)
# with two swiftdc binaries and diff the renders, view by view.
#
#   Tools/blast-radius.sh <baseline-swiftdc> <new-swiftdc> <outdir> [--real] [view...]
#
# Views default to structured, pseudo, listing and json. Renders are kept
# under $SWIFTDC_RENDER_CACHE, keyed by the binary's hash, the fixture key
# and the view, so a baseline is rendered once and every later change
# diffs against it. Copy each binary out of .build first: the key is its
# content, and a binary rebuilt in place is a different key.
#
# Writes <outdir>/<view>.diff (unified) and prints one line per view:
# files and lines changed. Every changed line belongs in the commit message.
set -euo pipefail

usage() { echo "usage: $0 <baseline-swiftdc> <new-swiftdc> <outdir> [--real] [view...]" >&2; exit 2; }
[ $# -ge 3 ] || usage
base=$1 new=$2 out=$3; shift 3
real=0
views=()
for a in "$@"; do
  case $a in
    --real) real=1 ;;
    structured|pseudo|listing|json) views+=("$a") ;;
    *) usage ;;
  esac
done
[ ${#views[@]} -gt 0 ] || views=(structured pseudo listing json)

repo=$(cd "$(dirname "$0")/.." && pwd)
cache=${SWIFTDC_RENDER_CACHE:-$HOME/Library/Caches/swiftdc-renders}
jobs=${SWIFTDC_BLAST_JOBS:-6}
mkdir -p "$out" "$cache"
out=$(cd "$out" && pwd)

# Inputs: every Mach-O product of build.sh, then the real dylibs.
list=$out/inputs.txt
git -C "$repo" ls-files -z --others --ignored --exclude-standard -- Fixtures/Sample |
  while IFS= read -r -d '' f; do
    case $f in *.dSYM/*) continue ;; esac
    magic=$(head -c 4 "$repo/$f" | xxd -p)
    case $magic in cffaedfe|cafebabe) echo "$repo/$f" ;; esac
  done | sort > "$list"
if [ $real = 1 ]; then
  host=$(dirname "$(xcrun --find swiftc)")/../lib/swift/host
  mkdir -p "$out/real"
  for d in libSwiftOperators libSwiftIfConfig libSwiftParserDiagnostics libSwiftCompilerPluginMessageHandling; do
    [ -f "$host/$d.dylib" ] || { echo "blast-radius: missing $host/$d.dylib" >&2; exit 1; }
    cp "$host/$d.dylib" "$out/real/$d.dylib"
    cp "$host/$d.dylib" "$out/real/$d.stripped.dylib"
    strip -x "$out/real/$d.stripped.dylib" 2> /dev/null
    echo "$out/real/$d.dylib"
    echo "$out/real/$d.stripped.dylib"
  done >> "$list"
fi
[ -s "$list" ] || { echo "blast-radius: no inputs; run Tools/fixtures.sh" >&2; exit 1; }
# Key the inputs by content and basename, not path: <outdir>/real moves.
inputs=$(while read -r f; do echo "$(shasum -a 256 < "$f" | cut -c1-64) $(basename "$f")"; done < "$list" |
  shasum -a 256 | cut -c1-16)

render() { # render <binary> <view> -> prints the render directory
  local bin=$1 view=$2 dir
  dir=$cache/v2-$(shasum -a 256 "$bin" | cut -c1-16)-$inputs-$view
  if [ ! -f "$dir/.done" ]; then
    rm -rf "$dir"; mkdir -p "$dir"
    local flag=--$view; [ "$view" = listing ] && flag=
    # A message that names its input names it by a placeholder, so renders
    # from two worktrees (the gate's and the caller's) compare equal.
    tr '\n' '\0' < "$list" | xargs -0 -P "$jobs" -I{} sh -c \
      '{ "$1" disasm "$2" $3 2>&1; echo "rc=$?"; } | sed -e "s|$5/|<repo>/|g" -e "s|$6/|<out>/|g" > "$4/$(basename "$2")"' \
      _ "$bin" {} "$flag" "$dir" "$repo" "$out"
    touch "$dir/.done"
  fi
  echo "$dir"
}

for view in "${views[@]}"; do
  start=$SECONDS
  b=$(render "$base" "$view")
  n=$(render "$new" "$view")
  # git's histogram diff: `diff -r` took over 25 minutes on JSON renders
  # whose lines all shifted, git 0.9 s on the same pair.
  git diff --no-index --no-color --diff-algorithm=histogram "$b" "$n" > "$out/$view.diff" || true
  files=$(grep -c '^diff --git ' "$out/$view.diff" || true)
  lines=$(grep -E '^[-+]' "$out/$view.diff" | grep -cvE '^(\+\+\+|---) ' || true)
  printf '%-10s %4d files %7d lines changed  (%d s)  %s\n' "$view" "$files" "$lines" $((SECONDS - start)) "$out/$view.diff"
done
# Drop render directories untouched for two weeks.
find "$cache" -maxdepth 1 -mindepth 1 -type d -mtime +14 -exec rm -rf {} + 2> /dev/null || true
