#!/bin/bash
# Build the arm64 ABI probes and a native execution oracle.
set -euo pipefail
cd "$(dirname "$0")"

# Match Package.swift's deployment floor; an explicit target also avoids
# selecting a host SDK version newer than the toolchain's Swift stdlib.
# ABI tests do not exercise dyld rebasing, so keep chained fixups out of this
# fixture's metadata-read path while independent fixup tests cover that format.
TARGET="arm64-apple-macosx15.0"
xcrun swiftc -target "$TARGET" -parse-as-library -Onone -g -emit-library \
    -module-name ABISource abi_source.swift -Xlinker -no_fixup_chains \
    -o libABISource.dylib
xcrun swiftc -target "$TARGET" -parse-as-library -O -emit-library \
    -module-name ABISource abi_source.swift -Xlinker -no_fixup_chains \
    -o libABISource.opt.dylib
xcrun clang -target "$TARGET" -c abi_source_aliased.s -o abi_source_aliased.o
xcrun swiftc -target "$TARGET" -parse-as-library -O -enable-library-evolution \
    -emit-library -emit-module -emit-module-path ABISource.swiftmodule \
    -module-name ABISource abi_source.swift abi_source_aliased.o -Xlinker -no_fixup_chains \
    -Xlinker -install_name -Xlinker @rpath/libABISource.resilient.dylib \
    -o libABISource.resilient.dylib
xcrun swiftc -target "$TARGET" -parse-as-library -O \
    -module-name ABISource abi_source.swift abi_source_main.swift -o abi-source-oracle
xcrun swiftc -target "$TARGET" -parse-as-library -O \
    -module-name ABISourceResilientOracle -I . -L . -lABISource.resilient \
    -Xlinker -rpath -Xlinker @executable_path \
    abi_source_resilient_main.swift -o abi-source-resilient-oracle
