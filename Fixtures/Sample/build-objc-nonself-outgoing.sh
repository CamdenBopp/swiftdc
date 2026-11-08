#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

xcrun clang -fobjc-arc -O2 -g -dynamiclib -framework Foundation \
    objc_nonself_outgoing.m -o libObjCNonselfOutgoing.dylib
cp libObjCNonselfOutgoing.dylib libObjCNonselfOutgoing.stripped.dylib
strip -x -S libObjCNonselfOutgoing.stripped.dylib 2>/dev/null \
    || strip -x libObjCNonselfOutgoing.stripped.dylib
