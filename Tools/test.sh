#!/bin/bash
# Run one test tier (docs/PARALLEL-WORKFLOW.md, "Test classification").
#
#   Tools/test.sh file <NameTests>...   tier 1: those test files
#   Tools/test.sh <subsystem>...        tier 2: a subsystem's tests
#   Tools/test.sh affected             tier 3: mapped changes against origin/dev
#                                      and local changes, plus Determinism and
#                                      FixturePresence. Unknown sources run full.
#   Tools/test.sh full                  tier 4: the enforcing suite (the gate's)
#   Tools/test.sh quick                tier 4 except the dyld-cache memory
#                                      test. For iteration only.
#   Tools/test.sh go                   the Go tests, which no other tier runs
#                                      (SWIFTDC_GO_TESTS=1; the longest takes
#                                      28 minutes alone). Go is not a target.
#
# Subsystems: arm64 abi tracer cflow meta render audit. Every tier builds
# tests first and requires fixtures. Before a push, run Tools/test.sh full.
set -euo pipefail
cd "$(dirname "$0")/.."

filter_for() {
  case $1 in
    arm64) echo 'Semantics|Capstone|Alias|Magic|VectorLane|Fmov|FPImmediate|Conversion|IntConvert' ;;
    abi) echo 'ABI|Arity|CallArg|SwiftLowering|Signature|Specializ|Async|Indirect|ObjCArgument|CalleeRegister' ;;
    tracer) echo 'Tracer|Value|Exit|Condition|Fact|Signed32|Throw' ;;
    cflow) echo 'CFG|Struct|Switch|Loop|JumpTable|Branch' ;;
    meta) echo 'Field|Index|Metadata|MachO|Dyld|Fat|ObjC|Preflight|Layout|Enum' ;;
    render) echo 'Pseudo|Render|Reconstruction|Idiom|Placement|Declaration' ;;
    audit) echo 'Probe|Determinism|Differential|Research' ;;
    *) return 1 ;;
  esac
}

subsystem_of() { # path -> subsystem names
  case $1 in
    */Capstone*|*/MachineDetail*|*/AArch64AliasCanon*|*/InstructionSemantics*|*/LiteralScan*|*/MagicConstants*|*/MagicDivision*) echo arm64 ;;
    */SwiftLowering*|*/IndirectResults*|*/CalleeRegisterSummary*|*/ObjCArgumentABI*|*/SpecializedSignature*) echo abi ;;
    */ValueTracking*|*/TypeInference*|*/ProbeSnapshots*) echo tracer ;;
    */CFG*|*/Structurer*|*/JumpTables*) echo cflow ;;
    */FieldMap*|*Index.swift|*/MetadataSymbolizer*|*/BinaryLoader*|*/MachOPreflight*|*/CacheReader*) echo meta ;;
    */Pseudo*|*/SwiftIdioms*) echo render ;;
    */Probe*) echo audit ;;
    # The shared contract and the god file reach every subsystem.
    */Disassembler.swift|*/Instruction*.swift) echo arm64 abi tracer cflow meta render audit ;;
    *) return 1 ;;
  esac
}

if [ $# -eq 0 ] || [[ $1 == --help || $1 == -h ]]; then
  sed -n '/^# Run one test tier/,/^set /{ /^set /d; s/^# \{0,1\}//; p; }' "$0"
  if [ $# -gt 0 ]; then exit 0; fi
  exit 2
fi
args=()
case $1 in
  full) args=() ;;
  quick) args=(--skip 'streamingWholeImageMemoryStaysLow') ;;
  # The tests marked .goTier (GoTestTier.swift) report as skipped without
  # the variable, in every other tier and in the gate.
  go) export SWIFTDC_GO_TESTS=1
      args=(--filter 'GoFunctionTableTests\.swift|goX8|goStackGrowth') ;;
  file)
    shift; [ $# -ge 1 ] || { echo "test.sh file <NameTests>..." >&2; exit 2; }
    re=$(printf '%s\\.swift|' "$@"); args=(--filter "${re%|}") ;;
  affected)
    changed=$(mktemp)
    trap 'rm -f "$changed"' EXIT
    if ! git diff --no-renames --name-only -z origin/dev...HEAD > "$changed" ||
       ! git diff --no-renames --name-only -z HEAD >> "$changed" ||
       ! git ls-files --others --exclude-standard -z >> "$changed"; then
      echo "test.sh: cannot determine changed paths; run Tools/test.sh full" >&2
      exit 1
    fi
    re='Determinism|FixturePresence'
    subs=
    needs_full=false
    while IFS= read -r -d '' path; do
      case $path in
        Sources/*)
          if mapped=$(subsystem_of "$path"); then
            subs="$subs $mapped"
          else
            needs_full=true
            printf 'test.sh: unmapped source %q requires the full suite\n' "$path" >&2
          fi ;;
        Tests/*Tests.swift)
          name=${path##*/}
          name=$(printf '%s' "$name" | sed 's/[][\\.^$*+?(){}|]/\\&/g')
          re="$re|$name" ;;
        Tools/*.md) ;;
        Tests/*|Fixtures/*|Tools/*|.github/workflows/*|Package.swift|Package.resolved)
          needs_full=true
          printf 'test.sh: shared test/build input %q requires the full suite\n' "$path" >&2 ;;
      esac
    done < "$changed"
    if ! $needs_full; then
      subs=$(printf '%s\n' $subs | sort -u | tr '\n' ' ')
      for s in $subs; do re="$re|$(filter_for "$s")"; done
      display_subs=${subs% }
      echo "test.sh: affected subsystems: ${display_subs:-none}" >&2
      args=(--filter "$re")
    fi ;;
  *)
    re=
    for s in "$@"; do f=$(filter_for "$s") || { echo "unknown subsystem: $s" >&2; exit 2; }; re="$re|$f"; done
    args=(--filter "${re#|}") ;;
esac

case ${args[0]-} in
  --filter)
    printf 'test.sh: selecting test names and files matching %s; other tests are omitted\n' "${args[1]}" >&2 ;;
  --skip)
    echo "test.sh: skipping the dyld-cache memory test for iteration" >&2
    printf 'test.sh: exclusion regex %s\n' "${args[1]}" >&2 ;;
  *)
    echo "test.sh: running the full enforcing suite" >&2 ;;
esac
if [ -n "${args[0]-}" ]; then
  echo "test.sh: before a push, run Tools/test.sh full" >&2
fi
echo "test.sh: building tests; missing required fixtures fail the test step" >&2

if ! log=$(swift build --build-tests 2>&1); then
  echo "$log" | grep -E "error:" >&2 || echo "$log" | tail -20 >&2
  exit 1
fi
echo "$log" | grep -E "Build complete" >&2 || true
# `${args[@]+…}`: bash 3.2 treats an empty array as unset under `set -u`.
SWIFTDC_REQUIRE_FIXTURES=1 swift test --skip-build ${args[@]+"${args[@]}"}
