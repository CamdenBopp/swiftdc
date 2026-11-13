#!/bin/zsh
# compare.sh <swiftdc> <outdir> [binary…]
#
# Renders each binary with Ghidra (headless, default analysis, then
# DumpDecomp.java: every function's prototype and decompiled C) and with
# swiftdc (`disasm --structured`), side by side in <outdir>:
#   <area>.<name>.ghidra.c   <area>.<name>.swiftdc.txt
# With no binaries, builds the pinned corpus (corpus/build.sh) into
# <outdir>/corpus, checks every dylib's code against corpus/MANIFEST.tsv,
# and renders all of it.
#
# <outdir>/RUN.tsv records what was compared: the swiftdc binary's hash and
# the repository revision it was run from (and whether the tree was dirty),
# Ghidra's version, the toolchain, and each input's hash. A score is only
# as good as that record: quote it with the numbers.
#
# A Ghidra render is cached by the input's hash and Ghidra's version, never
# by name, so a rebuilt input or a new Ghidra is rendered afresh.
#
# Ghidra comes from GHIDRA_HOME, else Homebrew's. Swift names demangle only
# when GHIDRA_SWIFT_DEMANGLER names swift-demangle (Ghidra 12.1.4 and later),
# which this sets. Each Ghidra run gets 3 GB and 2 analysis threads and
# deletes its project afterwards; this runs one binary at a time.
set -u
swiftdc=$1 out=$2; shift 2
here=${0:A:h}
ghidra=${GHIDRA_HOME:-$(brew --prefix ghidra 2>/dev/null)/libexec}
[[ -x $ghidra/support/analyzeHeadless ]] || { echo "no Ghidra at $ghidra (set GHIDRA_HOME)" >&2; exit 2; }
[[ -x $swiftdc ]] || { echo "no swiftdc at $swiftdc" >&2; exit 2; }
export GHIDRA_SWIFT_DEMANGLER=$(xcrun -f swift-demangle)
export GHIDRA_HEADLESS_MAXMEM=${GHIDRA_HEADLESS_MAXMEM:-3G}
mkdir -p $out/projects $out/ghidra-cache
sha() { shasum -a 256 "$1" | cut -d' ' -f1 }

if (( $# == 0 )); then
  $here/corpus/build.sh $out/corpus > $out/corpus-build.log 2>&1 || { echo "corpus build failed: $out/corpus-build.log" >&2; exit 1; }
  $here/corpus/check.sh $out/corpus || exit 1
  set -- $out/corpus/*/*.dylib(N)
fi

ghidra_version=$(sed -n 's/^application.version=//p' $ghidra/Ghidra/application.properties)
revision=$(git -C $here rev-parse HEAD 2>/dev/null || echo unknown)
[[ -n $(git -C $here status --porcelain --untracked-files=no 2>/dev/null) ]] && revision="$revision-dirty"
{
  print "swiftdc\t$(sha $swiftdc)\t$swiftdc"
  print "revision\t$revision"
  print "ghidra\t$ghidra_version"
  print "swift\t$(xcrun swiftc --version 2>&1 | head -1)"
  print "clang\t$(xcrun clang --version 2>&1 | head -1)"
} > $out/RUN.tsv

failed=0
for bin in "$@"; do
  name=$(basename $(dirname $bin)).$(basename $bin .dylib)
  key=$(sha $bin)-$ghidra_version
  print "input\t$name\t$(sha $bin)" >> $out/RUN.tsv
  if [[ ! -s $out/ghidra-cache/$key.c ]]; then
    $ghidra/support/analyzeHeadless $out/projects p$$ -import "$bin" \
      -scriptPath $here -postScript DumpDecomp.java $out/ghidra-cache/$key.c \
      -deleteProject -max-cpu 2 > $out/$name.ghidra.log 2>&1
  fi
  if [[ -s $out/ghidra-cache/$key.c ]]; then
    cp $out/ghidra-cache/$key.c $out/$name.ghidra.c
  else
    echo "$name: Ghidra produced nothing ($out/$name.ghidra.log)" >&2; failed=$((failed + 1))
  fi
  if ! $swiftdc disasm "$bin" --structured > $out/$name.swiftdc.txt 2> $out/$name.swiftdc.err; then
    echo "$name: swiftdc exited nonzero ($out/$name.swiftdc.err)" >&2; failed=$((failed + 1))
  fi
done
echo "$# inputs, $failed failures; record in $out/RUN.tsv"
(( failed == 0 ))
