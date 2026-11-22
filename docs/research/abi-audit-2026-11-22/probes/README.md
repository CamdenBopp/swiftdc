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

The emitted `typeOfA` and `identityA` bodies load A metadata at byte offset 88. The descriptor's immediate members start at byte 80, occupied here by the pack length. In `identityA` the compiler reads the VWT at A metadata −8 and selects the `initializeWithCopy` witness at table +16. To exercise this production consumer, repeat the compiler command above with `-emit-library` in place of `-emit-ir`, outputting `work/abi-gap-audit-repro/libGenericPackProbe.dylib`. Run the recorded baseline on the result.

```sh
swiftdc disasm work/abi-gap-audit-repro/libGenericPackProbe.dylib --structured --function=identityA
```

The published gate binary incorrectly labels the copy witness B on the original Xcode Swift 6.4.0 probe and the command-line Swift 6.4.2 paired fixture. The latter also includes the same noinline `identityA` method in an ordinary `PlainBox<A, B>`, whose copy witness is correctly named A. The distinct `typeOfA` probe has no witness call and still renders `return ?`. The narrow G07 fix must remove the false B label, preserve the ordinary A label, and decline the scalar metadata index when the descriptor's pack/value header or parameter kind prevents proof.

Captured artifacts are under ignored `work/abi-gap-audit`. `g07-GenericClassPacks.swift` is the paired source, `libGenericClassPacks.clt.dylib` its 6.4.2 build, and `g07-paired-clt-baseline.txt` its render. `g07-identityA-baseline.txt` and `g07-identityA-disassembly.txt` are the original 6.4.0 render and raw disassembly. `g07.patch` drafts the guard and paired regression for a separate implementation commit.
