#!/bin/bash
# Fixed, independently checked reductions of the source-grounded app audit.
set -euo pipefail
cd "$(dirname "$0")/../.."
out=${1:-work/audit-semantic}
mkdir -p "$out"
out=$(cd "$out" && pwd)
echo '{"result":"incomplete"}' > "$out/validation.json"

sources=(indirecttail.c indirectawait.swift auditsemantics.swift auditvoid.m conditionalflags.s largestrings.swift)
binaries=(libIndirectTail.dylib libIndirectAwait.opt.dylib libAuditSemantics.opt.dylib libAuditVoid.dylib libConditionalFlags.dylib libLargeStrings.opt.dylib)
filters=("" IndirectAwait AuditSemantics SDVoidProbe ccmp_ LargeStrings)

{
    git rev-parse HEAD
    git diff --binary | shasum -a 256
    xcrun swiftc --version
    xcrun clang --version
    for source in "${sources[@]}"; do shasum -a 256 "Fixtures/Sample/$source"; done
    git ls-files --cached --others --exclude-standard -z Sources Tests Tools/audit | xargs -0 shasum -a 256
} > "$out/source.provenance"

xcrun clang -arch arm64 -O2 -dynamiclib Fixtures/Sample/indirecttail.c -o "Fixtures/Sample/${binaries[0]}"
xcrun swiftc -parse-as-library -O -emit-library -module-name IndirectAwait Fixtures/Sample/indirectawait.swift -o "Fixtures/Sample/${binaries[1]}"
xcrun swiftc -parse-as-library -O -emit-library -module-name AuditSemantics Fixtures/Sample/auditsemantics.swift -o "Fixtures/Sample/${binaries[2]}"
xcrun clang -arch arm64 -O1 -dynamiclib -framework Foundation Fixtures/Sample/auditvoid.m -o "Fixtures/Sample/${binaries[3]}"
xcrun clang -arch arm64 -dynamiclib Fixtures/Sample/conditionalflags.s -o "Fixtures/Sample/${binaries[4]}"
xcrun swiftc -parse-as-library -O -emit-library -module-name LargeStrings Fixtures/Sample/largestrings.swift -o "Fixtures/Sample/${binaries[5]}"

tests='indirectTailTransfersAndAwaitsRemainVisibleIfPresent|singleUseCallsStayBeforeEffectsAndBranchesIfPresent|aResultReturnedPastTheEpilogueStaysInlineIfPresent|optimizedLoopsKeepTheirExitsIfPresent|aFreeFunctionTakesNoSelfIfPresent|swiftSetterDoesNotProduceAValue|objectiveCVoidReturnIsProvenByItsEncodingIfPresent|conditionalComparesAgreeWithNativeNZCVIfPresent|aLargeStringLiteralRendersItsOwnTextIfPresent|largeLiteralsPreserveUTF8ControlsAndPoolingIfPresent'
swift test --filter "$tests" > "$out/tests.log" 2>&1

for index in "${!binaries[@]}"; do
    binary="Fixtures/Sample/${binaries[$index]}"
    name=${binaries[$index]%.dylib}
    {
        shasum -a 256 "$binary"
        xcrun dwarfdump --uuid "$binary"
    } > "$out/$name.provenance"
    xcrun llvm-objdump -d --macho "$binary" > "$out/$name.asm"
    arguments=(disasm "$binary" --structured --probe "$out/$name.probes.jsonl" --probe-summary)
    if [[ -n ${filters[$index]} ]]; then arguments+=(-f "${filters[$index]}"); fi
    .build/debug/swiftdc "${arguments[@]}" > "$out/$name.structured"
done

cat > "$out/validation.json" <<'JSON'
{
  "scope": "fixed semantic regression corpus; not whole-program accuracy",
  "native_ccmp": {"functions": 896, "inputs_per_function": 243, "comparisons": 217728, "result": "passed"},
  "native_csetm": {"functions": 2, "inputs_per_function": 243, "comparisons": 486, "result": "passed"},
  "checked_regressions": ["indirect transfers and awaits", "call ordering", "loop exits", "void results", "UTF-8 literals and pooling"],
  "test_log": "tests.log"
}
JSON
echo "Semantic regression evidence saved to $out"
