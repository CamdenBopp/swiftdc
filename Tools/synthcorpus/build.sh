#!/bin/zsh
# Build every corpus source at each optimization level it is meant for.
#   Tools/synthcorpus/build.sh [outdir] [area ...]
# Sources live in src/<area>/; products go to <outdir>/<area>/<name>.<level>.dylib
# (default outdir: Tools/synthcorpus/out, git-ignored). A source picks its
# levels with a `// LEVELS: O Osize Onone` line (Swift) or `// LEVELS: O0 O2`
# (C, Objective-C); the defaults are below. Assembly builds once.
set -u
here=${0:A:h}
out=${1:-$here/out}
shift $(( $# > 0 ? 1 : 0 ))
areas=("$@")
(( ${#areas} )) || areas=($here/src/*(/N:t))
SWIFTC="xcrun swiftc"; CLANG="xcrun clang"
fail=0
for area in $areas; do
  mkdir -p $out/$area
  for src in $here/src/$area/*.(swift|c|m|s)(N); do
    name=${src:t:r}; ext=${src:e}
    levels=$(sed -n 's#^// LEVELS: *##p' $src | head -1)
    case $ext in
      swift) levels=${levels:-O Osize Onone};;
      c|m)   levels=${levels:-O0 O1 O2 Os};;
      s)     levels=asm;;
    esac
    for level in ${=levels}; do
      dst=$out/$area/$name.$level.dylib
      [[ -f $dst && $dst -nt $src ]] && continue
      case $ext in
        swift) ${=SWIFTC} -parse-as-library -$level -emit-library -module-name ${(C)name//[^A-Za-z0-9]/} $src -o $dst ;;
        c)     ${=CLANG} -$level -dynamiclib -undefined dynamic_lookup $src -o $dst ;;
        m)     ${=CLANG} -$level -fobjc-arc -dynamiclib -framework Foundation -undefined dynamic_lookup $src -o $dst ;;
        s)     ${=CLANG} -arch arm64 -dynamiclib -undefined dynamic_lookup $src -o $dst ;;
      esac 2> $out/$area/$name.$level.log || { echo "build failed: $src ($level), see $out/$area/$name.$level.log"; fail=1; }
      # A stripped twin of each optimized build: names come only from metadata.
      if [[ -f $dst && $level != Onone && $level != O0 && $ext != s ]]; then
        cp $dst ${dst:r}.stripped.dylib && strip -x ${dst:r}.stripped.dylib 2>/dev/null
      fi
    done
  done
done
exit $fail
