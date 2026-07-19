#!/bin/bash
# Build several variants of the sample fixture for decompiler testing.
set -euo pipefail
cd "$(dirname "$0")"

SWIFTC="xcrun swiftc"
CLANG="xcrun clang"

echo "==> Objective-C fixture object"
$CLANG -fobjc-arc -O -c sample_objc.m -o sample_objc.o

echo "==> debug (-Onone -g)"
$SWIFTC -DSAMPLE_MAIN -parse-as-library -Onone -g sample.swift sample_objc.o -o sample.debug

echo "==> release (-O)"
$SWIFTC -DSAMPLE_MAIN -parse-as-library -O sample.swift sample_objc.o -o sample.release

echo "==> release, stripped"
cp sample.release sample.stripped
strip -x sample.stripped 2>/dev/null || strip sample.stripped

echo "==> resilient dylib (library evolution), stripped — models a framework"
$SWIFTC -parse-as-library -O -enable-library-evolution -emit-library -module-name Sample sample.swift sample_objc.o -o libSample.dylib
cp libSample.dylib libSample.stripped.dylib
strip -x libSample.stripped.dylib 2>/dev/null || strip libSample.stripped.dylib

echo "==> reconstruction fixture (-Onone -g dylib) — Swift-body recovery cases"
$SWIFTC -parse-as-library -Onone -g -emit-library -module-name Reconstruction reconstruction.swift -o libReconstruction.dylib

echo "==> reconstruction fixture (-O) — optimized/branchless lowerings"
$SWIFTC -parse-as-library -O -emit-library -module-name Reconstruction reconstruction.swift -o libReconstruction.opt.dylib
cp libReconstruction.opt.dylib libReconstruction.opt.stripped.dylib
strip -x libReconstruction.opt.stripped.dylib 2>/dev/null || strip libReconstruction.opt.stripped.dylib

echo "==> resilient reconstruction fixture (library evolution) — coroutine accessors"
# Library evolution forces opaque accessors, so a public stored property gets a
# synthesized `_modify`/`_read` yield_once coroutine (absent from a fragile build).
$SWIFTC -parse-as-library -Onone -g -enable-library-evolution -emit-library -module-name Reconstruction reconstruction.swift -o libReconstruction.resilient.dylib

echo "==> variants:"
ls -la sample.debug sample.release sample.stripped libSample.dylib libSample.stripped.dylib libReconstruction.dylib
file sample.release
