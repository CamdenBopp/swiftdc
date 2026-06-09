#!/bin/bash
# Build several variants of the sample fixture for decompiler testing.
set -euo pipefail
cd "$(dirname "$0")"

SWIFTC="xcrun swiftc"

echo "==> debug (-Onone -g)"
$SWIFTC -DSAMPLE_MAIN -parse-as-library -Onone -g sample.swift -o sample.debug

echo "==> release (-O)"
$SWIFTC -DSAMPLE_MAIN -parse-as-library -O sample.swift -o sample.release

echo "==> release, stripped"
cp sample.release sample.stripped
strip -x sample.stripped 2>/dev/null || strip sample.stripped

echo "==> resilient dylib (library evolution), stripped — models a framework"
$SWIFTC -parse-as-library -O -enable-library-evolution -emit-library -module-name Sample sample.swift -o libSample.dylib
cp libSample.dylib libSample.stripped.dylib
strip -x libSample.stripped.dylib 2>/dev/null || strip libSample.stripped.dylib

echo "==> variants:"
ls -la sample.debug sample.release sample.stripped libSample.dylib libSample.stripped.dylib
file sample.release
