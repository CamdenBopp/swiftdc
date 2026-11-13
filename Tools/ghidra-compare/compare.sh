#!/bin/zsh
# compare.sh <swiftdc> <outdir> <binary>...
#
# Renders each binary with Ghidra (headless, default analysis, then
# DumpDecomp.java: every function's prototype and decompiled C) and with
# swiftdc (`disasm --structured`), side by side in <outdir>:
#   <name>.ghidra.c   <name>.swiftdc.txt
# A Ghidra render is cached: delete it to redo it.
#
# Ghidra comes from GHIDRA_HOME, else Homebrew's. Swift names demangle only
# when GHIDRA_SWIFT_DEMANGLER names swift-demangle (Ghidra 12.1.4 and later),
# which this sets. Each Ghidra run gets 3 GB and 2 analysis threads and
# deletes its project afterwards; run binaries one or two at a time on a
# 16 GB host.
set -u
swiftdc=$1 out=$2; shift 2
here=${0:A:h}
ghidra=${GHIDRA_HOME:-$(brew --prefix ghidra 2>/dev/null)/libexec}
[[ -x $ghidra/support/analyzeHeadless ]] || { echo "no Ghidra at $ghidra (set GHIDRA_HOME)" >&2; exit 2; }
export GHIDRA_SWIFT_DEMANGLER=$(xcrun -f swift-demangle)
export GHIDRA_HEADLESS_MAXMEM=${GHIDRA_HEADLESS_MAXMEM:-3G}
mkdir -p $out/projects
for bin in "$@"; do
  name=$(basename $(dirname $bin)).$(basename $bin .dylib)
  if [[ ! -s $out/$name.ghidra.c ]]; then
    $ghidra/support/analyzeHeadless $out/projects p$$ -import "$bin" \
      -scriptPath $here -postScript DumpDecomp.java $out/$name.ghidra.c \
      -deleteProject -max-cpu 2 > $out/$name.ghidra.log 2>&1
  fi
  $swiftdc disasm "$bin" --structured > $out/$name.swiftdc.txt 2>&1
  echo "$name ghidra $(grep -c '^===' $out/$name.ghidra.c 2>/dev/null || echo 0) functions"
done
