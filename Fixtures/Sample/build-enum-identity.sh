#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# These tests target descriptor identity; chained fixups are covered elsewhere.

xcrun swiftc -parse-as-library -Onone -g -emit-library -emit-module \
    -module-name EnumIdentityExternal enum_identity_external.swift \
    -Xlinker -no_fixup_chains \
    -o libEnumIdentityExternal.dylib
xcrun swiftc -parse-as-library -Onone -g -emit-library \
    -module-name EnumIdentityLocal enum_identity_local.swift \
    -I . -L . -lEnumIdentityExternal -Xlinker -no_fixup_chains \
    -o libEnumIdentityLocal.dylib
