#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# These tests target descriptor identity; chained fixups are covered elsewhere.

xcrun swiftc -parse-as-library -O -emit-library -emit-module \
    -module-name ClassIdentityExternal class_identity_external.swift \
    -Xlinker -no_fixup_chains \
    -o libClassIdentityExternal.dylib
xcrun swiftc -parse-as-library -O -emit-library \
    -module-name ClassIdentityLocal class_identity_local.swift \
    -I . -L . -lClassIdentityExternal -Xlinker -no_fixup_chains \
    -o libClassIdentityLocal.dylib
