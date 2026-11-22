# Debug a wrong pseudocode render

Start with the exact binary, command, and function. Record the compiler and
optimization level. Start from current `dev` and keep intermediate logs
and binaries under ignored `work/`. Follow the [contributor setup](../CONTRIBUTING.md)
and [current toolchain requirements](CI.md) before building.

## Reproduce a known case

The fixture [throwselect.swift](../Fixtures/Sample/throwselect.swift) builds
a small optimized library. Its `plainThrow` throws for negative input and
otherwise returns `x &* 3`. The historical bug was an invented assignment
`let r1 = swift_willThrow(r0)` followed by a return that used `r1` on the
throwing path.

```bash
Tools/fixtures.sh
swift build --build-tests
dc=.build/debug/swiftdc
fixture=Fixtures/Sample/libThrowSelect.dylib
"$dc" disasm "$fixture" -f plainThrow --structured
"$dc" disasm "$fixture" -f plainThrow --pseudo
"$dc" lab "$fixture" -f plainThrow
otool -tvV "$fixture"
```

The structured result includes `throw ?` and the successful path's
`return (arg0 + (arg0 << 1))`. In the independent `otool` listing, follow
`tbnz x0, #0x3f`. The nonnegative path computes the triple in x0. The
negative path allocates an error, calls `_swift_willThrow`, and sets x21
from the saved error before the shared `ret`. The runtime declaration has
a `void` return. Even though the paths share an epilogue, only the
nonnegative path returns the integer. Addresses can change with the build.
[Swift runtime declaration](https://github.com/swiftlang/swift/blob/83eb12448e4323abbf81b0153dced2faff02d22f/include/swift/Runtime/Error.h#L68-L74)

## Find the first disagreement

- **Wrong declaration or name.** Compare `interface` (Swift) or `objc`
  (Objective-C) with the source or metadata. Inspect
  [InterfaceReconstructor.swift](../Sources/SwiftDecompilerCore/InterfaceReconstructor.swift)
  for Swift declarations and
  [ObjCMetadataIndex.swift](../Sources/SwiftDecompilerCore/ObjCMetadataIndex.swift)
  for Objective-C methods and owners.
- **Missing function.** Retry `disasm` with the raw symbol or `-f 0xADDRESS`,
  using an address from `nm -n` or `otool`. Check the selected Mach-O slice,
  symbols, and `LC_FUNCTION_STARTS` before concluding the function is absent.
  Start with `BinaryLoader` and `Disassembler.linkerFunctionStarts`.
- **Wrong body.** Use `disasm --cfg` for edges and `lab` for call snapshots
  and exit facts. When the decoded instruction and control flow agree with
  `otool`, look for the first incorrect value in
  `ValueTracer.transfer` or `Disassembler.enrichCallArguments`. Here
  `ValueTracer.CallFacts` supplies the void-call fact and the enrichment pass
  separates throwing predecessors from ordinary return values. When the
  analysis facts agree with the binary, compare `renderStructured` in
  [Structurer.swift](../Sources/SwiftDecompilerCore/Structurer.swift) and
  `renderPseudo` in [Pseudo.swift](../Sources/SwiftDecompilerCore/Pseudo.swift).
  For per-address JSON, see [Instrumentation](INSTRUMENTATION.md).

## Keep a regression test

```bash
SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build \
  --filter 'fixturesArePresentWhenRequired|aThrowingPathsX0IsNoResultIfPresent|aMergedThrowsExitReturnsTheNormalPathsValueIfPresent'
```

The presence test prevents missing fixtures from passing the filtered run.
The two body tests cover the absent invented result and the preserved
successful value. For the original fix, removing the new void-runtime rule
made `aThrowingPathsX0IsNoResultIfPresent` report two issues. That is
historical mutation evidence, and later analysis changes can affect which
mutation isolates the bug. For a new fix, rebuild with a small temporary
reversion, confirm the expected assertion fails, restore, rebuild, and
confirm it passes. Run the fixture at every optimization level it builds
(e.g. `-Onone`, `-O`, or `-Osize`). `ThrowSelect` builds at `-O` only.
Report the changed output lines in the pull request.
[Original fix and test evidence](https://github.com/CamdenBopp/swiftdc/commit/e2ecce17d8f4caed6619d53b4840e93086f8b0f2)
