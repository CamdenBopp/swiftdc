# Source-grounded app audit

The audit checks swiftdc's claims about real apps against evidence that
doesn't come from swiftdc: the apps' own source at a known revision, a
matching build, the machine code, DWARF, and the compiler's IR. It found the
2026-10-12 entries in
[PRODUCTION-READINESS.md](../../docs/PRODUCTION-READINESS.md).

## 1. Build with provenance

```bash
cp Tools/audit/apps.conf.example Tools/audit/apps.conf   # git-ignored; list your apps
Tools/audit/build-apps.sh Tools/audit/apps.conf /path/to/audit/builds
```

Each app is built at Debug (-Onone) and Release (-O) for the arm64
simulator, into the output directory. Nothing is written into the app
repositories and nothing is signed.

`<App>-<Config>.provenance` records:

- the revision and a hash of any uncommitted diff;
- a hash of the Swift source tree, for an app that isn't in git;
- the toolchain;
- the optimization settings the build actually used;
- the LC_UUID of each product.

Don't audit a binary whose provenance you can't state. In a Debug build
with `ENABLE_DEBUG_DYLIB`, the code is in `<App>.debug.dylib`; the
executable is a stub.

## 2. Run swiftdc under a memory guard

```bash
Tools/audit/guard.sh out/ 2000 -- swiftdc disasm <bin> -f <function> --structured
```

The guard logs the footprint and kills the run past the limit. An
unfiltered `disasm` or `analyze` holds about 1 KB per instruction, so
filter on a large app. `xrefs` streams.

## 3. Check every claim against an independent oracle

| Claim | Oracle |
|---|---|
| A call, its arguments, its order | `xcrun llvm-objdump -d --macho` of the same function: the registers set before the `bl`, the call order |
| A condition | The flag-setting instruction that actually precedes the branch, and its condition code's signedness |
| A field name at an offset | DWARF member offsets in the dSYM (`dwarfdump --debug-info`); the `Wvd` field-offset symbols |
| A string literal | `__cstring` at the address the code computes, and the length word |
| An async parent or order | The compiler's funclet symbols, and the DWARF line table |
| Function identity | The symbol table, DWARF `DW_AT_name`, LC_FUNCTION_STARTS |
| What the compiler lowered | `swiftc -emit-sil` / `-emit-ir` / `-S` on a reduced copy |
| Behaviour | Run the reduced program |

Textual similarity to the source isn't evidence. Optimized code differs
from source for legitimate reasons (inlining, specialization, merged
functions, outlining). The question is always whether swiftdc's claim is
true of the machine code.

`--probe` makes some claims machine-checkable (`types.field-named`), and
`ProbeRecorder(validators:)` takes an oracle as a closure. See
[INSTRUMENTATION.md](../../docs/INSTRUMENTATION.md).

## 4. Classify each difference

Every difference gets exactly one class:

- **semantic-error**: swiftdc claims something false, and an oracle shows it;
- **incomplete**: a decline where the evidence exists (completeness, never
  soundness);
- **ambiguous**: the binary doesn't decide it;
- **correct-lowering**: swiftdc is right, and the source just reads
  differently;
- **hypothesis**: suspected but not shown, along with what would show it.

## 5. Reduce, then fix

1. Reduce each confirmed error to a minimal program you write yourself.
   Never commit the app's code.
2. Prove the reduction reproduces with the swiftdc build that was audited.
3. Add the reduction as a fixture, with a test that fails before the fix
   (mutation-checked).
4. Re-run the app to show the fix generalizes. A probe count, such as
   `structure.unreadable-flags`, is a cheap way to measure that.

Reports that quote an app's code stay outside this repository.

## 6. Re-run the fixed semantic regression corpus

```bash
Tools/audit/semantic-regressions.sh work/audit-semantic
```

This builds the authored reductions and verifies indirect transfers/awaits,
call ordering, void results, array-loop exits, and long literals with Unicode,
combining marks, embedded NUL/control characters and pooling. The CCMP oracle
executes 896 native ARM64 functions over 243 inputs each (217,728 comparisons),
covering all fallback NZCV patterns and all fourteen condition codes in both
register widths, including signed-overflow boundaries.
Two additional native consumers verify CSETM masks and the zero-extension of
a 32-bit destination over 486 inputs.

The output includes source/toolchain provenance, binary hashes and UUIDs,
independent objdump listings, structured renders, probe summaries and the test
log. An assertion failure exits nonzero before writing a passing validation
record. These measurements cover the stated reductions; representative app
accuracy still requires the source-grounded app protocol above. Probe counts
alone do not validate a claim.
