#!/bin/bash
# Render every fixture (and optionally the toolchain's swift-syntax dylibs)
# with two swiftdc binaries, diff the renders view by view, and hold the new
# binary to a cost budget against the old one.
#
#   Tools/blast-radius.sh <baseline-swiftdc> <new-swiftdc> <outdir> [--real] [--perf] [view...]
#
# Views default to structured, pseudo, listing and json. Renders are kept
# under $SWIFTDC_RENDER_CACHE, keyed by the binary's hash, the fixture key
# and the view, so a baseline is rendered once and every later change
# diffs against it. Copy each binary out of .build first: the key is its
# content, and a binary rebuilt in place is a different key.
#
# Writes <outdir>/<view>.diff (unified) and prints one line per view:
# files and lines changed. Every changed line belongs in the commit message.
#
# Cost budget. Every render runs under `/usr/bin/time -l`, and its
# instructions retired and peak memory footprint are cached beside the
# render. Instructions retired is the figure to trust on a shared host:
# two runs of one binary over every input agreed to 0.11% in total and
# 2.3% on the worst input above 2G, at load 15 to 30, where wall time
# moves by 8% or more. Peak footprint is noisier: 1.2% in total, but up
# to 25% on one input. --perf adds four large whole-image runs on the
# toolchain's libSwiftSyntax and libSwiftParser (`disasm --structured`
# and `xrefs --unreferenced`), each under Tools/audit/guard.sh. The
# report goes to <outdir>/perf.txt and <outdir>/perf.tsv. The run exits 3
# when the new binary is over budget, in percent over the base:
#
#   SWIFTDC_PERF_INSN_PCT             instructions, any large input (10)
#   SWIFTDC_PERF_INSN_TOTAL_PCT       instructions, all renders (3)
#   SWIFTDC_PERF_FOOTPRINT_PCT        footprint, any large input (50)
#   SWIFTDC_PERF_FOOTPRINT_TOTAL_PCT  footprint, summed over renders (10)
#   SWIFTDC_PERF_MIN_INSN             large: this many base instructions
#                                     (2000000000) for the instruction
#                                     check, or
#   SWIFTDC_PERF_MIN_FOOTPRINT        this many base footprint bytes
#                                     (67108864) for the footprint check
#   SWIFTDC_PERF_OVERRIDE             a reason: report, then exit 0
#   SWIFTDC_PERF_KILL_MB              guard limit for a --perf run (4000)
#
# Compare only binaries built the same way: counts depend on code
# generation. To fill the cache for one binary ahead of time, pass it as
# both <baseline> and <new>.
set -euo pipefail

usage() { echo "usage: $0 <baseline-swiftdc> <new-swiftdc> <outdir> [--real] [--perf] [view...]" >&2; exit 2; }
[ $# -ge 3 ] || usage
base=$1 new=$2 out=$3; shift 3
real=0 perf=0
views=()
for a in "$@"; do
  case $a in
    --real) real=1 ;;
    --perf) perf=1 ;;
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
started=$SECONDS

# Inputs: every Mach-O product of build.sh, then the real dylibs.
list=$out/inputs.txt
git -C "$repo" ls-files -z --others --ignored --exclude-standard -- Fixtures/Sample |
  while IFS= read -r -d '' f; do
    case $f in *.dSYM/*) continue ;; esac
    magic=$(head -c 4 "$repo/$f" | xxd -p)
    case $magic in cffaedfe|cafebabe) echo "$repo/$f" ;; esac
  done | sort > "$list"
host=$(dirname "$(xcrun --find swiftc)")/../lib/swift/host
if [ $real = 1 ]; then
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
binkey() { shasum -a 256 "$1" | cut -c1-16; }

render() { # render <binary> <view> -> prints the render directory
  local bin=$1 view=$2 dir
  dir=$cache/v3-$(binkey "$bin")-$inputs-$view
  if [ ! -f "$dir/.done" ]; then
    # The counts live beside the render, not in it, so they never diff.
    rm -rf "$dir" "$dir.time"; mkdir -p "$dir" "$dir.time"
    local flag=--$view; [ "$view" = listing ] && flag=
    # A message that names its input names it by a placeholder, so renders
    # from two worktrees (the gate's and the caller's) compare equal.
    tr '\n' '\0' < "$list" | xargs -0 -P "$jobs" -I{} sh -c \
      '{ /usr/bin/time -l -o "$4.time/$(basename "$2")" "$1" disasm "$2" $3 2>&1; echo "rc=$?"; } | sed -e "s|$5/|<repo>/|g" -e "s|$6/|<out>/|g" > "$4/$(basename "$2")"' \
      _ "$bin" {} "$flag" "$dir" "$repo" "$out"
    touch "$dir/.done"
  fi
  echo "$dir"
}

# The large workloads: name, command, input.
workloads=(
  "syntax-structured disasm libSwiftSyntax --structured"
  "syntax-xrefs xrefs libSwiftSyntax --unreferenced"
  "parser-structured disasm libSwiftParser --structured"
  "parser-xrefs xrefs libSwiftParser --unreferenced"
)
measure() { # measure <binary> <name> <command> <dylib> <flag> -> the run's cache directory
  local bin=$1 name=$2 cmd=$3 lib=$host/$4.dylib flag=$5 dir rc
  [ -f "$lib" ] || { echo "blast-radius: missing $lib" >&2; return 1; }
  dir=$cache/perf1-$(binkey "$bin")-$name-$(binkey "$lib")
  if [ ! -f "$dir/.done" ]; then
    rm -rf "$dir"; mkdir -p "$dir"
    rc=0
    "$repo/Tools/audit/guard.sh" "$dir/run" "${SWIFTDC_PERF_KILL_MB:-4000}" -- \
      /usr/bin/time -l -o "$dir/time.txt" "$bin" "$cmd" "$lib" "$flag" || rc=$?
    grep -q '^KILLED' "$dir/run/mem.log" && rc=killed
    echo "$rc" > "$dir/rc"
    shasum -a 256 < "$dir/run/stdout" | cut -c1-64 > "$dir/sha"
    rm -f "$dir/run/stdout"
    touch "$dir/.done"
  fi
  echo "$dir"
}
perfpid=
if [ $perf = 1 ]; then
  # Each workload runs base then new, the four side by side with the
  # renders. A cached baseline costs nothing.
  mkdir -p "$out/perf"
  for w in "${workloads[@]}"; do
    set -- $w
    { measure "$base" "$@" > "$out/perf/$1.base" && measure "$new" "$@" > "$out/perf/$1.new"; } \
      2> "$out/perf/$1.log" &
    perfpid="$perfpid $!"
  done
fi

# counts <time file> -> "instructions footprint", or "- -" when absent.
counts() {
  awk '/instructions retired/ { i = $1 } /peak memory footprint/ { f = $1 }
       END { if (i == "" || f == "") print "- -"; else print i, f }' "$1" 2> /dev/null || echo "- -"
}

: > "$out/perf.tsv"
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
  # One awk for every input of the view: a process per file cost 10 s.
  sed 's|.*/||' "$list" | awk -v view="$view" -v b="$b.time" -v n="$n.time" '
    function counts(file,   line, i, f, w) {
      i = ""; f = ""
      while ((getline line < file) > 0) {
        split(line, w, " ")
        if (line ~ /instructions retired/) i = w[1]
        if (line ~ /peak memory footprint/) f = w[1]
      }
      close(file)
      return (i == "" || f == "") ? "-\t-" : i "\t" f
    }
    { print view "\t" $0 "\t" counts(b "/" $0) "\t" counts(n "/" $0) }' >> "$out/perf.tsv"
done

if [ -n "$perfpid" ]; then
  for p in $perfpid; do wait "$p" || true; done
  for w in "${workloads[@]}"; do
    set -- $w
    bd=$(cat "$out/perf/$1.base" 2> /dev/null || true)
    nd=$(cat "$out/perf/$1.new" 2> /dev/null || true)
    if [ -z "$bd" ] || [ -z "$nd" ]; then
      echo "blast-radius: perf run $1 failed (see $out/perf/$1.log)" >&2
      cat "$out/perf/$1.log" >&2
      exit 1
    fi
    # A run that failed or was killed under the new binary but not the
    # base is a regression; any other failure invalidates its counts.
    if [ "$(cat "$bd/rc")" != "$(cat "$nd/rc")" ]; then
      echo "blast-radius: $1 exited $(cat "$bd/rc") with the base binary and $(cat "$nd/rc") with the new one ($nd)" >&2
      exit 3
    fi
    same=same; cmp -s "$bd/sha" "$nd/sha" || same=differs
    printf '%s\t%s\t%s\t%s\t%s\n' "perf" "$1" "$(counts "$bd/time.txt")" "$(counts "$nd/time.txt")" "$same" | tr ' ' '\t'
  done >> "$out/perf.tsv"
fi

# The budget. Rows: kind, input, base insn, base footprint, new insn, new
# footprint[, output same/differs].
rc=0
awk -F'\t' -v ipct="${SWIFTDC_PERF_INSN_PCT:-10}" -v itot="${SWIFTDC_PERF_INSN_TOTAL_PCT:-3}" \
    -v fpct="${SWIFTDC_PERF_FOOTPRINT_PCT:-50}" -v ftot="${SWIFTDC_PERF_FOOTPRINT_TOTAL_PCT:-10}" \
    -v mini="${SWIFTDC_PERF_MIN_INSN:-2000000000}" -v minf="${SWIFTDC_PERF_MIN_FOOTPRINT:-67108864}" '
  function pct(a, b) { return b > 0 ? 100 * (a - b) / b : 0 }
  function g(x) { return sprintf("%.1fG", x / 1e9) }
  function mb(x) { return sprintf("%.0fMB", x / 1048576) }
  $3 == "-" || $5 == "-" { missing++; print "cost: no counts for " $1 " " $2; next }
  {
    rows++; bi += $3; ni += $5; bf += $4; nf += $6
    di = pct($5, $3); df = pct($6, $4)
    over = ""
    if ($3 >= mini && di > ipct) over = over " insn"
    if ($4 >= minf && df > fpct) over = over " footprint"
    if (over != "") { bad++; flag = "OVER" over } else flag = ""
    if ($1 == "perf" || flag != "" || ($3 >= mini && (di > 3 || di < -3)))
      lines[++n] = sprintf("%-10s %-44s %9s -> %9s %+7.1f%%   %6s -> %6s %+6.1f%%  %s %s",
        $1, $2, g($3), g($5), di, mb($4), mb($6), df, $7, flag)
  }
  END {
    print "cost: listed are the --perf runs, large inputs that moved more than 3%, and every input over budget"
    for (i = 1; i <= n; i++) print "cost: " lines[i]
    ti = pct(ni, bi); tf = pct(nf, bf)
    printf "cost: total over %d renders: instructions %s -> %s (%+.2f%%), footprint %s -> %s (%+.2f%%)\n",
      rows, g(bi), g(ni), ti, mb(bf), mb(nf), tf
    if (ti > itot) { bad++; printf "cost: OVER: total instructions %+.2f%% > %s%%\n", ti, itot }
    if (tf > ftot) { bad++; printf "cost: OVER: total footprint %+.2f%% > %s%%\n", tf, ftot }
    limits = sprintf("+%s%% instructions on an input from %s, +%s%% in total; +%s%% footprint on an input from %s, +%s%% in total",
      ipct, g(mini), itot, fpct, mb(minf), ftot)
    # An unmeasured render is not a cheap one.
    if (missing || !rows) { printf "cost: UNKNOWN: %d renders without counts, %d with\n", missing, rows; exit 4 }
    if (bad) { print "cost: over budget (" limits ")"; exit 3 }
    print "cost: within budget (" limits ")"
  }' "$out/perf.tsv" > "$out/perf.txt" || rc=$?
# The terminal gets at most 12 per-render lines; perf.txt has them all.
awk -v all="$out/perf.txt" '
  $2 ~ /^(structured|pseudo|listing|json)$/ { if (++n > 12) next; print; next }
  n > 12 && !said { said = 1; printf "cost: ... and %d more render lines in %s\n", n - 12, all }
  { print }' "$out/perf.txt"
echo "blast-radius: $((SECONDS - started)) s"
# Drop render directories untouched for two weeks.
find "$cache" -maxdepth 1 -mindepth 1 -type d -mtime +14 -exec rm -rf {} + 2> /dev/null || true
if [ $rc = 3 ]; then
  if [ -n "${SWIFTDC_PERF_OVERRIDE:-}" ]; then
    echo "cost: over budget, accepted: $SWIFTDC_PERF_OVERRIDE"
    exit 0
  fi
  exit 3
fi
[ $rc = 0 ] || exit $rc
