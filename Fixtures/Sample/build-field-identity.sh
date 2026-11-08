#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

xcrun swiftc -parse-as-library -Onone -g -emit-library -emit-module \
    -module-name FieldIdentityExternal field_identity_external.swift \
    -Xlinker -no_fixup_chains \
    -Xlinker -install_name -Xlinker @loader_path/libFieldIdentityExternal.dylib \
    -o libFieldIdentityExternal.dylib
xcrun swiftc -parse-as-library -Onone -g -emit-library \
    -module-name FieldIdentityLocal field_identity_local.swift \
    -I . -L . -lFieldIdentityExternal -Xlinker -no_fixup_chains \
    -o libFieldIdentityLocal.dylib

# Both linked images below deliberately claim FieldIdentityExternal.Vec. The
# offline resolver must decline that qualified name rather than take the first.
xcrun swiftc -parse-as-library -Onone -g -emit-library \
    -module-name FieldIdentityExternal field_identity_external.swift \
    -Xlinker -no_fixup_chains \
    -Xlinker -install_name -Xlinker @loader_path/libFieldIdentityDuplicate.dylib \
    -o libFieldIdentityDuplicate.dylib
xcrun swiftc -parse-as-library -Onone -g -emit-library \
    -module-name FieldIdentityDuplicateLocal field_identity_local.swift \
    -I . -L . -lFieldIdentityExternal -lFieldIdentityDuplicate \
    -Xlinker -no_fixup_chains \
    -o libFieldIdentityDuplicateLocal.dylib
