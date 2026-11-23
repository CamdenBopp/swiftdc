#!/bin/zsh
# Rebuilds the decompiler comparison corpus: build.sh <outdir>
#
# Every dylib lands in <outdir>/<area>/<name>. MANIFEST.tsv beside this script
# holds the sha256 of each original's __TEXT,__text bytes, so a rebuild can be
# checked (see the header line there for the exact extraction command).
#
# Each compile runs from the area's source directory with relative source
# paths, and every link passes the original relative install name. Both are
# on purpose: the install name's length moves __text, and -Onone Swift embeds
# the source path as given.
#
# Requires the Xcode toolchain (xcrun swiftc, xcrun clang, xcrun strip).
# Serial on purpose: the host shares 16 GB with other jobs.

if [[ $# -ne 1 ]]; then
  echo "usage: build.sh <outdir>" >&2
  exit 2
fi

SRC=${0:A:h}
mkdir -p "$1" || exit 2
OUT=${1:A}
failures=0

# run <area> <command...>: runs the command from the area's source directory.
run() {
  local area=$1; shift
  mkdir -p "$OUT/$area"
  ( cd "$SRC/$area" && "$@" )
  local rc=$?
  if (( rc != 0 )); then
    echo "FAILED ($rc): $*" >&2
    (( failures += 1 ))
  fi
  return $rc
}

# sw <area> <name> <module> <level> <sources and extra swiftc flags...>
# Swift library at one optimization level (-Onone, -O, -Osize).
sw() {
  local area=$1 name=$2 module=$3 level=$4; shift 4
  echo "==> $area/$name"
  run $area xcrun swiftc -parse-as-library -emit-library $level \
    -module-name $module "$@" \
    -Xlinker -install_name -Xlinker $name -o "$OUT/$area/$name"
}

# cc <area> <name> <level> <sources and extra clang flags...>
# C, Objective-C or assembly dylib at one optimization level (-O0, -O2, -Os).
cc() {
  local area=$1 name=$2 level=$3; shift 3
  echo "==> $area/$name"
  run $area xcrun clang -dynamiclib $level "$@" \
    -install_name $name -o "$OUT/$area/$name"
}

# stripped <area> <name> <from> <strip flag>
# A copy of an already built dylib with symbols stripped. It keeps the
# install name of the dylib it was copied from, as the original does.
stripped() {
  local area=$1 name=$2 from=$3 flag=$4
  echo "==> $area/$name"
  run $area cp "$OUT/$area/$from" "$OUT/$area/$name" &&
    run $area xcrun strip $flag "$OUT/$area/$name"
}

# ---------------------------------------------------------------- actors
sw actors act1_O.dylib     Act1 -O     act1.swift
sw actors act1_Onone.dylib Act1 -Onone act1.swift
sw actors act1_Osize.dylib Act1 -Osize act1.swift
sw actors act2_O.dylib     Act2 -O     act2.swift
sw actors act2_Onone.dylib Act2 -Onone act2.swift
sw actors act3_O.dylib     Act3 -O     act3.swift
sw actors act4_O.dylib     Act4 -O     act4.swift
sw actors act5_O.dylib     Act5 -O     act5.swift
sw actors act6_O.dylib     Act6 -O     act6.swift
sw actors act7_O.dylib     Act7 -O     act7.swift
sw actors act7_Onone.dylib Act7 -Onone act7.swift

# ----------------------------------------------------------- collections
# The module name carries the level here, so each level mangles differently.
sw collections coll-O.dylib      collO     -O     coll.swift
sw collections coll-Onone.dylib  collOnone -Onone coll.swift
sw collections coll-Osize.dylib  collOsize -Osize coll.swift
sw collections coll2-O.dylib     c2O       -O     coll2.swift
sw collections coll2-Onone.dylib c2Onone   -Onone coll2.swift
sw collections coll2-Osize.dylib c2Osize   -Osize coll2.swift
sw collections coll3-O.dylib     c3O       -O     coll3.swift
sw collections coll3-Osize.dylib c3Osize   -Osize coll3.swift
sw collections mut-Osize.dylib   mutOs     -Osize mut.swift
sw collections ovf-O.dylib       ovfO      -O     ovf.swift

# ---------------------------------------------------------------- frames
cc frames callers_O2.dylib -O2 callers.c -fno-stack-protector
cc frames cond.dylib       -O2 cond.c    -fno-stack-protector

# The address and thread sanitizer builds are -O1: frames2.c matches at no
# other level. frames.c matches at -O1 and -O2 alike and follows suit.
cc frames f2_O0.dylib    -O0 frames2.c
cc frames f2_O2.dylib    -O2 frames2.c
cc frames f2_Os.dylib    -Os frames2.c
cc frames f2_asan.dylib  -O1 frames2.c -fsanitize=address
cc frames f2_bti.dylib   -O2 frames2.c -mbranch-protection=standard
cc frames f2_cov.dylib   -O2 frames2.c -fprofile-instr-generate -fcoverage-mapping
cc frames f2_nosp.dylib  -O2 frames2.c -fno-stack-protector
cc frames f2_omit.dylib  -O2 frames2.c -fomit-frame-pointer
cc frames f2_pat.dylib   -O2 frames2.c -ftrivial-auto-var-init=pattern
cc frames f2_pat0.dylib  -O0 frames2.c -ftrivial-auto-var-init=pattern
cc frames f2_pcg.dylib   -O2 frames2.c -fsanitize-coverage=trace-pc-guard
cc frames f2_sp.dylib    -O2 frames2.c -fstack-protector-all
cc frames f2_tsan.dylib  -O1 frames2.c -fsanitize=thread
cc frames f2_ubsan.dylib -O2 frames2.c -fsanitize=undefined

# frames.c calls sink and use, which no image defines.
FRAMES=(frames.c -undefined dynamic_lookup)
cc frames frames_O2.dylib    -O2 $FRAMES
cc frames frames_asan.dylib  -O1 $FRAMES -fsanitize=address
cc frames frames_bti.dylib   -O2 $FRAMES -mbranch-protection=standard
cc frames frames_clash.dylib -O2 $FRAMES
cc frames frames_cov.dylib   -O2 $FRAMES -fprofile-instr-generate -fcoverage-mapping
cc frames frames_omit.dylib  -O2 $FRAMES -fomit-frame-pointer
cc frames frames_pat.dylib   -O2 $FRAMES -ftrivial-auto-var-init=pattern
cc frames frames_pcg.dylib   -O2 $FRAMES -fsanitize-coverage=trace-pc-guard
cc frames frames_sp.dylib    -O2 $FRAMES -fstack-protector-all
cc frames frames_tsan.dylib  -O1 $FRAMES -fsanitize=thread
cc frames frames_ubsan.dylib -O2 $FRAMES -fsanitize=undefined

sw frames sf_O.dylib     SF -O     sframes.swift
sw frames sf_Onone.dylib SF -Onone sframes.swift
sw frames sf_Osize.dylib SF -Osize sframes.swift
sw frames sf_asan.dylib  SF -O     sframes.swift -sanitize=address
sw frames sf_cov.dylib   SF -O     sframes.swift -sanitize=address -sanitize-coverage=func
sw frames sf_prof.dylib  SF -O     sframes.swift -profile-generate -profile-coverage-mapping
sw frames sf_tsan.dylib  SF -O     sframes.swift -sanitize=thread

# --------------------------------------------------------------- globals
# cglob.c reads weakExt and cglob2.c calls mutate; neither is linked in.
cc globals cglob_O0.dylib  -O0 cglob.c -undefined dynamic_lookup
cc globals cglob_O2.dylib  -O2 cglob.c -undefined dynamic_lookup
cc globals cglob_Os.dylib  -Os cglob.c -undefined dynamic_lookup
cc globals cglob2_O0.dylib -O0 cglob2.c -undefined dynamic_lookup
cc globals cglob2_O2.dylib -O2 cglob2.c -undefined dynamic_lookup
cc globals cglob2_Os.dylib -Os cglob2.c -undefined dynamic_lookup

# libext defines the extern globals cglob3 binds through the GOT.
cc globals libext.dylib    -O2 extdef.c
CGLOB3=(cglob3.m -fobjc-arc -framework Foundation "$OUT/globals/libext.dylib")
cc globals cglob3_O0.dylib -O0 $CGLOB3
cc globals cglob3_O2.dylib -O2 $CGLOB3
cc globals cglob3_Os.dylib -Os $CGLOB3

sw globals sglob_O.dylib     SG -O     sglob.swift
sw globals sglob_Onone.dylib SG -Onone sglob.swift
sw globals sglob_Osize.dylib SG -Osize sglob.swift

# --------------------------------------------------------------- intmath
# cm.c calls sink, which no image defines.
cc intmath cm_O0.dylib -O0 cm.c -undefined dynamic_lookup
cc intmath cm_O2.dylib -O2 cm.c -undefined dynamic_lookup
cc intmath cm_Os.dylib -Os cm.c -undefined dynamic_lookup

sw intmath im_O.dylib     imO     -O     im.swift
sw intmath im_Onone.dylib imOnone -Onone im.swift
sw intmath im_Osize.dylib imOsize -Osize im.swift
sw intmath jm_O.dylib     jmO     -O     im2.swift
sw intmath jm_Onone.dylib jmOnone -Onone im2.swift
sw intmath jm_Osize.dylib jmOsize -Osize im2.swift
sw intmath km_O.dylib     km      -O     im3.swift
sw intmath lm_O.dylib     lm      -O     im4.swift

# ---------------------------------------------------------------- linker
cc linker regcall.dylib -O2 regcall.s
cc linker alias.dylib   -O2 regcall.s -Wl,-alias,_one_arg,_alias_one
cc linker cold.dylib    -O2 cold.c -mllvm -hot-cold-split=true -undefined dynamic_lookup
cc linker icf.dylib     -O2 icf.c -Wl,-deduplicate
cc linker outl.dylib    -Oz outl.c -mllvm -enable-machine-outliner=always

cc linker shapes.dylib      -O2 shapes.s
cc linker shapes2.dylib     -O2 shapes2.s
cc linker shapes_nofs.dylib -O2 shapes.s -Wl,-no_function_starts
stripped linker shapes_x.dylib      shapes.dylib      -x
stripped linker shapes_nofs_x.dylib shapes_nofs.dylib -x

sw linker fso.dylib    FSO  -O fso.swift
sw linker merge.dylib  Mg   -O merge.swift  -Xllvm -enable-merge-functions
sw linker merge2.dylib Mg2  -O merge2.swift
sw linker spec.dylib   Spec -O spec.swift

# ----------------------------------------------------------- noncopyable
sw noncopyable ctl_O.dylib     CT  -O     ctl.swift
# nc.swift uses @_lifetime on a ~Escapable initializer.
LIFETIMES=(-enable-experimental-feature Lifetimes)
sw noncopyable nc_O.dylib      NC  -O     nc.swift $LIFETIMES
sw noncopyable nc_Onone.dylib  NC  -Onone nc.swift $LIFETIMES
sw noncopyable nc_Osize.dylib  NC  -Osize nc.swift $LIFETIMES
sw noncopyable nc2_O.dylib     NC2 -O     nc2.swift
sw noncopyable nc2_Onone.dylib NC2 -Onone nc2.swift
sw noncopyable nc2_Osize.dylib NC2 -Osize nc2.swift
sw noncopyable rp.dylib        RPM -O     rp.swift

# ---------------------------------------------------------------- objcrt
# The "c" variants send through objc_msgSend directly, with no selector stubs.
OBJC=(-fobjc-arc -framework Foundation)
NOSTUBS=(-fno-objc-msgsend-selector-stubs)
for level in O0 O2 Os; do
  cc objcrt rt1-$level.dylib  -$level rt1.m $OBJC
  cc objcrt rt1c-$level.dylib -$level rt1.m $OBJC $NOSTUBS
  cc objcrt rt2-$level.dylib  -$level rt2.m $OBJC
  cc objcrt rt2c-$level.dylib -$level rt2.m $OBJC $NOSTUBS
done
cc objcrt rt3-O0.dylib -O0 rt3.m $OBJC
cc objcrt rt3-O2.dylib -O2 rt3.m $OBJC
cc objcrt rt4-O2.dylib -O2 rt4.m $OBJC
cc objcrt rt5-O0.dylib -O0 rt5.m $OBJC
cc objcrt rt5-O2.dylib -O2 rt5.m $OBJC

# ----------------------------------------------------------------- packs
sw packs g_O.dylib     G  -O     g.swift
sw packs g_Onone.dylib G  -Onone g.swift
sw packs g_Osize.dylib G  -Osize g.swift
sw packs g2_O.dylib    G2 -O     g2.swift
sw packs s3_O.dylib     S3 -O     s3.swift
sw packs s3_Onone.dylib S3 -Onone s3.swift
sw packs s3_Osize.dylib S3 -Osize s3.swift
sw packs t_O.dylib      T  -O     t.swift
sw packs t2_O.dylib     T2 -O     t2.swift
sw packs t2_Onone.dylib T2 -Onone t2.swift

# Library evolution builds. These also wrote the .swiftinterface files.
sw packs f_evo.dylib  F  -O f.swift  -enable-library-evolution
sw packs g_evo.dylib  G  -O g.swift  -enable-library-evolution -swift-version 5
sw packs g2_evo.dylib G2 -O g2.swift -enable-library-evolution

# Helper modules the clients below import: mod/libG (g.swift) and
# modh/libH (h.swift). They are not corpus entries themselves.
echo "==> packs/mod/libG.dylib (helper)"
mkdir -p "$OUT/packs/mod" "$OUT/packs/modh"
run packs xcrun swiftc -parse-as-library -emit-library -O -module-name G g.swift \
  -enable-library-evolution -swift-version 5 \
  -emit-module -emit-module-path "$OUT/packs/mod/G.swiftmodule" \
  -Xlinker -install_name -Xlinker mod/libG.dylib -o "$OUT/packs/mod/libG.dylib"
echo "==> packs/modh/libH.dylib (helper)"
run packs xcrun swiftc -parse-as-library -emit-library -O -module-name H h.swift \
  -enable-library-evolution \
  -emit-module -emit-module-path "$OUT/packs/modh/H.swiftmodule" \
  -Xlinker -install_name -Xlinker modh/libH.dylib -o "$OUT/packs/modh/libH.dylib"

sw packs c_O.dylib     C  -O     c.swift  -I "$OUT/packs/mod"  -L "$OUT/packs/mod"  -lG
sw packs c_Onone.dylib C  -Onone c.swift  -I "$OUT/packs/mod"  -L "$OUT/packs/mod"  -lG
sw packs hc_O.dylib    HC -O     hc.swift -I "$OUT/packs/modh" -L "$OUT/packs/modh" -lH

# --------------------------------------------------------------- strings
# s1..s5: the module name is the upper-cased stem plus the level.
# s3.swift declares ext_pair by @_silgen_name and nothing defines it.
for n in 1 2 3 4 5; do
  extra=()
  [[ $n == 3 ]] && extra=(-Xlinker -undefined -Xlinker dynamic_lookup)
  sw strings s$n-O.dylib     S${n}O     -O     s$n.swift $extra
  sw strings s$n-Onone.dylib S${n}Onone -Onone s$n.swift $extra
  sw strings s$n-Osize.dylib S${n}Osize -Osize s$n.swift $extra
done

# ---------------------------------------------------------------- switch
# The C switches call case bodies (e0, e1, ...) that no image defines.
for stem in csw csw2 csw3; do
  cc switch ${stem}_O0.dylib -O0 $stem.c -undefined dynamic_lookup
  cc switch ${stem}_O2.dylib -O2 $stem.c -undefined dynamic_lookup
  cc switch ${stem}_Os.dylib -Os $stem.c -undefined dynamic_lookup
done
for stem in ssw ssw2; do
  sw switch ${stem}_O.dylib     $stem -O     $stem.swift
  sw switch ${stem}_Onone.dylib $stem -Onone $stem.swift
  sw switch ${stem}_Osize.dylib $stem -Osize $stem.swift
done

# -------------------------------------------------------------- wrappers
sw wrappers nest_O.dylib      nest  -O     nest.swift
sw wrappers obs_O.dylib       obs   -O     obs.swift
sw wrappers obs_Onone.dylib   obs   -Onone obs.swift
sw wrappers obs_Osize.dylib   obs   -Osize obs.swift
sw wrappers order_O.dylib     order -O     order.swift
sw wrappers order_Osize.dylib order -Osize order.swift
sw wrappers pw_O.dylib        pw    -O     pw.swift
sw wrappers pw_Onone.dylib    pw    -Onone pw.swift
sw wrappers pw_Osize.dylib    pw    -Osize pw.swift

if (( failures > 0 )); then
  echo "build.sh: $failures command(s) failed" >&2
  exit 1
fi
echo "build.sh: all built into $OUT"
