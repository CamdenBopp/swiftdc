# ABI audit reproductions

These sources were written for the audit. They are prospective regression fixtures, outside the fixture build until the relevant implementation slice adds its required tests. Compile into ignored `work` so generated binaries do not enter the public report.

## Compiler and SDK

Record both toolchains; they differ on this host:

```sh
/Library/Developer/CommandLineTools/usr/bin/swiftc --version
xcrun swiftc --version
xcrun clang --version
xcrun --sdk macosx --show-sdk-path
```

Use the explicit command-line Swift 6.4.2 executable for the aggregate probe and the second generic-pack IR oracle. The first generic-pack probe used Xcode Swift 6.4.0. Both showed A metadata at byte offset 88 for this specific optimized fixture. Commands below target arm64 macOS 15 and use the selected Xcode SDK. Record the actual version and SDK when repeating them.

## Ordinary super message in an initializer

```sh
mkdir -p work/abi-gap-audit-repro
xcrun clang -arch arm64 -mmacosx-version-min=15.0 \
  -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
  -O2 -fobjc-arc -dynamiclib -framework Foundation \
  docs/research/abi-audit-2026-11-22/probes/SuperInitializerProbe.m \
  -o work/abi-gap-audit-repro/libSuperInitializerProbe.dylib
xcrun llvm-objdump --macho --disassemble \
  work/abi-gap-audit-repro/libSuperInitializerProbe.dylib
```

Run a recorded baseline `swiftdc disasm <dylib> --structured`. The audited frozen binary incorrectly prints `self = [super description]` before the actual `self = [super init]`. The first super call is an ordinary message result. Independent disassembly identifies its `description` selector and the later `init` selector using the same messenger stub. Exact addresses are build-specific. The fix must remove the false assignment while retaining the call and the true initializer result.

## Aggregate pieces separated by an FP component

```sh
/Library/Developer/CommandLineTools/usr/bin/swiftc \
  -target arm64-apple-macosx15.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -O -parse-as-library -module-name ABIGapBarrier -emit-ir \
  docs/research/abi-audit-2026-11-22/probes/AggregateBarrierProbe.swift \
  -o work/abi-gap-audit-repro/AggregateBarrierProbe.ll
```

The `after` signature is `(i16, half, i16, i64)`. Two integer components separated by a half-precision component remain distinct, including the following integer formal. Compile an analogous `-emit-library` output to compare the decompiler. The audited binary prints unknown arguments; this probe confirms a schema mismatch without reproducing a wrong rendered value. A direct/indirect threshold test and a consumer exercising the inference are still required.

## Generic class pack metadata

```sh
/Library/Developer/CommandLineTools/usr/bin/swiftc \
  -target arm64-apple-macosx15.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -O -parse-as-library -module-name ABIGapProbe -emit-ir \
  docs/research/abi-audit-2026-11-22/probes/GenericPackProbe.swift \
  -o work/abi-gap-audit-repro/GenericPackProbe.ll
```

The emitted `typeOfA` and `identityA` bodies load A metadata at class metadata offset 88 in this fixture. Compare descriptor key arguments and shape fields before assigning generic parameter names to offsets. The audited `typeOfA` render is `return ?`; no wrong generic metadata name was observed. The index admission and actual witness consumer need separate tests.
