#!/bin/bash
# Build several variants of the sample fixture for decompiler testing.
set -euo pipefail
cd "$(dirname "$0")"

SWIFTC="xcrun swiftc"
CLANG="xcrun clang"

echo "==> Objective-C fixture object"
$CLANG -fobjc-arc -O -c sample_objc.m -o sample_objc.o

echo "==> debug (-Onone -g)"
$SWIFTC -DSAMPLE_MAIN -parse-as-library -Onone -g sample.swift sample_objc.o -o sample.debug

echo "==> release (-O)"
$SWIFTC -DSAMPLE_MAIN -parse-as-library -O sample.swift sample_objc.o -o sample.release

echo "==> release, stripped"
cp sample.release sample.stripped
strip -x sample.stripped 2>/dev/null || strip sample.stripped

echo "==> resilient dylib (library evolution), stripped — models a framework"
$SWIFTC -parse-as-library -O -enable-library-evolution -emit-library -module-name Sample sample.swift sample_objc.o -o libSample.dylib
cp libSample.dylib libSample.stripped.dylib
strip -x libSample.stripped.dylib 2>/dev/null || strip libSample.stripped.dylib

echo "==> reconstruction fixture (-Onone -g dylib) — Swift-body recovery cases"
$SWIFTC -parse-as-library -Onone -g -emit-library -module-name Reconstruction reconstruction.swift -o libReconstruction.dylib

echo "==> reconstruction fixture (-O) — optimized/branchless lowerings"
$SWIFTC -parse-as-library -O -emit-library -module-name Reconstruction reconstruction.swift -o libReconstruction.opt.dylib
cp libReconstruction.opt.dylib libReconstruction.opt.stripped.dylib
strip -x libReconstruction.opt.stripped.dylib 2>/dev/null || strip libReconstruction.opt.stripped.dylib
# -Osize turns on LLVM's machine outliner: `OUTLINED_FUNCTION_n` fragments,
# reached by `bl`, that read and write registers outside the calling
# convention. The stripped copy keeps only their LC_FUNCTION_STARTS entries.
$SWIFTC -parse-as-library -Osize -emit-library -module-name Reconstruction reconstruction.swift -o libReconstruction.osize.dylib
cp libReconstruction.osize.dylib libReconstruction.osize.stripped.dylib
strip -x libReconstruction.osize.stripped.dylib 2>/dev/null || strip libReconstruction.osize.stripped.dylib

echo "==> a throw merged into the normal epilogue (mergedthrow.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name MergedThrow mergedthrow.swift -o libMergedThrow.opt.dylib

echo "==> loops inside catch handlers (landingpadloop.cpp, -O1)"
xcrun clang++ -arch arm64 -O1 -dynamiclib -undefined dynamic_lookup landingpadloop.cpp -o libLandingPadLoop.dylib

echo "==> a loop the value tracer must converge on (gridsampler.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name GridSampler gridsampler.swift -o libGridSampler.opt.dylib

echo "==> escape markers a loop join derives must stay derived (markeroscillation.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name MarkerOscillation markeroscillation.swift -o libMarkerOscillation.opt.dylib

echo "==> branch conditions from ccmp/fcmp and unsigned range checks (conditions.swift, -O and -Osize)"
$SWIFTC -parse-as-library -O -emit-library -module-name Conditions conditions.swift -o libConditions.opt.dylib
$SWIFTC -parse-as-library -Osize -emit-library -module-name Conditions conditions.swift -o libConditions.osize.dylib

echo "==> Swift literals of 16 bytes or more (largestrings.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name LargeStrings largestrings.swift -o libLargeStrings.opt.dylib

echo "==> indirect tail calls and awaits (indirecttail.c -O2, indirectawait.swift -O)"
xcrun clang -arch arm64 -O2 -dynamiclib indirecttail.c -o libIndirectTail.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name IndirectAwait indirectawait.swift -o libIndirectAwait.opt.dylib

echo "==> audit semantic reductions (auditsemantics.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name AuditSemantics auditsemantics.swift -o libAuditSemantics.opt.dylib
$CLANG -arch arm64 -O1 -dynamiclib -framework Foundation auditvoid.m -o libAuditVoid.dylib
$CLANG -arch arm64 -dynamiclib conditionalflags.s -o libConditionalFlags.dylib

echo "==> symbolic addition flags at both widths (addflags.s)"
$CLANG -arch arm64 -dynamiclib addflags.s -o libAddFlags.dylib

for level in Onone O Osize; do
    echo "==> scalar tail-return forwarding (scalartailreturns.swift, -$level)"
    $SWIFTC -$level -emit-library -module-name ScalarTailReturns scalartailreturns.swift -o libScalarTailReturns.$level.dylib
done

echo "==> guarded returns across CFG layouts (returnpaths.s)"
$CLANG -arch arm64 -dynamiclib returnpaths.s -o libReturnPaths.dylib

echo "==> scalar extract and immediate rotation (extract.s)"
$CLANG -arch arm64 -dynamiclib extract.s -o libExtract.dylib

echo "==> scalar byte reversal (bytereversal.s)"
$CLANG -arch arm64 -dynamiclib bytereversal.s -o libByteReversal.dylib

echo "==> a pure unmodelled scalar return (unknownreturn.swift, -O)"
$SWIFTC -O -emit-library -module-name UnknownReturn unknownreturn.swift -o libUnknownReturn.dylib

echo "==> callee-save stack-byte overlap (abi_saved_slots.s)"
$CLANG -arch arm64 -dynamiclib abi_saved_slots.s -o libABISavedSlots.dylib -Wl,-install_name,@rpath/libABISavedSlots.dylib

echo "==> escaped save-area pointer aliases (abi_escaped_saves.s)"
$CLANG -arch arm64 -dynamiclib abi_escaped_saves.s -o libABIEscapedSaves.dylib

echo "==> caller-owned save slots and straddling writes (abi_frame_ownership.s)"
$CLANG -arch arm64 -dynamiclib abi_frame_ownership.s -o libABIFrameOwnership.dylib

echo "==> async pointer aliases and unaccounted memory writes (async_alias_escape.s)"
$CLANG -arch arm64 -dynamiclib async_alias_escape.s -o libAsyncAliasEscape.dylib

echo "==> async context load/store chronology (async_slot_chronology.s)"
$CLANG -arch arm64 -dynamiclib async_slot_chronology.s -o libAsyncSlotChronology.dylib

echo "==> async context writes through unknown aliases (async_memory_effects.s)"
$CLANG -arch arm64 -dynamiclib async_memory_effects.s -o libAsyncMemoryEffects.dylib

echo "==> explicit Swift error/value exit proofs (error_exit_controls.s)"
$CLANG -arch arm64 -dynamiclib error_exit_controls.s -o libErrorExitControls.dylib

echo "==> async context slots across calls (async_call_effects.s) — escaped and interior context pointers"
$CLANG -arch arm64 -dynamiclib async_call_effects.s -o libAsyncCallEffects.dylib

echo "==> frame slots reachable through escaped addresses (frame_escape_controls.s)"
$CLANG -arch arm64 -dynamiclib frame_escape_controls.s -o libFrameEscapeControls.dylib

echo "==> a stack address exported to a global, then written by a call (stackcalleffects.swift, -Onone/-O/-Osize)"
$SWIFTC -parse-as-library -Onone -g -emit-library -module-name StackCallEffects stackcalleffects.swift -o libStackCallEffects.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name StackCallEffects stackcalleffects.swift -o libStackCallEffects.opt.dylib
$SWIFTC -parse-as-library -Osize -emit-library -module-name StackCallEffects stackcalleffects.swift -o libStackCallEffects.osize.dylib

echo "==> hardened jump-table bounds (jump_table_bounds.s) — index widths and call-clobbered NZCV"
$CLANG -arch arm64 -dynamiclib jump_table_bounds.s -o libJumpTableBounds.dylib

echo "==> a switch case exits its enclosing loop (loopswitch.s)"
$CLANG -arch arm64 -dynamiclib loopswitch.s -o libLoopSwitch.dylib

echo "==> dependent select flow and non-address-order layout (selectflow.s)"
$CLANG -arch arm64 -dynamiclib selectflow.s -o libSelectFlow.dylib

echo "==> objc_retain_xN stubs (retainregister.swift, -O, arm64 iOS simulator)"
$SWIFTC -O -emit-library -module-name RetainRegister -target arm64-apple-ios17.0-simulator \
    -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" retainregister.swift -o libRetainRegister.sim.dylib

echo "==> a rethrow after a cleanup call (rethrowcleanup.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name RethrowCleanup rethrowcleanup.swift -o libRethrowCleanup.opt.dylib

echo "==> 32-bit flag, select and shift probes (widthflags.s, generated by widthflags.swift)"
$CLANG -arch arm64 -dynamiclib widthflags.s -o libWidthFlagProbes.dylib

echo "==> an awaited typed-throws callee (typedthrowsawait.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name TypedThrowsAwait typedthrowsawait.swift -o libTypedThrowsAwait.opt.dylib

echo "==> a context slot escaping through a reloaded context pointer (staleslot.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name StaleSlot staleslot.swift -o libStaleSlot.opt.dylib

echo "==> C callees without signatures (callreads.c, -O0 and -O1)"
for level in O0 O1; do
    xcrun clang -arch arm64 -$level -dynamiclib callreads.c -o libCallReads.$level.dylib
done

echo "==> codegen fixture (-O), plus a stripped copy — compiler idioms in an image of their own"
$SWIFTC -parse-as-library -O -emit-library -module-name Codegen codegen.swift -o libCodegen.opt.dylib
cp libCodegen.opt.dylib libCodegen.opt.stripped.dylib
strip -x libCodegen.opt.stripped.dylib 2>/dev/null || strip libCodegen.opt.stripped.dylib

echo "==> call-arity fixture (-Onone and -O) — arguments laid out from the callee's signature"
$SWIFTC -parse-as-library -Onone -emit-library -module-name CallArity callarity.swift -o libCallArity.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name CallArity callarity.swift -o libCallArity.opt.dylib

echo "==> variadic ObjC fixture (-O1) — format arguments on the stack"
$CLANG -O1 -fobjc-arc -framework Foundation -dynamiclib variadic.m -o libVariadic.dylib

echo "==> jump-table fixture (C, -O1) — compressed byte and halfword tables"
$CLANG -O1 -dynamiclib switches.c -o libSwitches.dylib
# arm64e lowers the same switches to the hardened form (csel clamp, ldrsw entries).
$CLANG -arch arm64e -O1 -dynamiclib switches.c -o libSwitches.arm64e.dylib

echo "==> ABI-source fixtures and native oracles (result and value-self registers)"
./build-abi-source.sh

echo "==> Objective-C outgoing-send fixtures (mixed x/v argument banks)"
./build-outgoing-objc.sh
./build-objc-nonself-outgoing.sh

echo "==> two-module identity fixtures (enum and class named in another module)"
./build-enum-identity.sh
./build-class-identity.sh
./build-field-identity.sh

echo "==> resilient reconstruction fixture (library evolution) — coroutine accessors"
# Library evolution forces opaque accessors, so a public stored property gets a
# synthesized `_modify`/`_read` yield_once coroutine (absent from a fragile build).
$SWIFTC -parse-as-library -Onone -g -enable-library-evolution -emit-library -module-name Reconstruction reconstruction.swift -o libReconstruction.resilient.dylib

echo "==> indirect-result fixture (-Onone -g, and -O) — x8 result buffers"
$SWIFTC -parse-as-library -Onone -g -emit-library -module-name Indirect indirect.swift -o libIndirect.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name Indirect indirect.swift -o libIndirect.opt.dylib

echo "==> conversions fixture (-Onone -g dylib, and -O) — int/float conversions"
$SWIFTC -parse-as-library -Onone -g -emit-library -module-name Conversions conversions.swift -o libConversions.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name Conversions conversions.swift -o libConversions.opt.dylib

echo "==> runtime ivar fixture (-O) — ivar offsets computed at load time"
$SWIFTC -parse-as-library -O -emit-library -module-name RuntimeIvars runtimeivars.swift -o libRuntimeIvars.dylib

echo "==> copy-on-write fixture (-O) — the uniqueness check is a Bool"
$SWIFTC -parse-as-library -O -emit-library -module-name Cow cow.swift -o libCow.dylib

echo "==> same-name classes fixture (-O) — vtable dispatch must not cross classes"
$SWIFTC -parse-as-library -O -emit-library -module-name SameName samename.swift -o libSameName.dylib

echo "==> async inout fixture (-O) — a context slot whose address escapes"
$SWIFTC -parse-as-library -O -emit-library -module-name AsyncInout asyncinout.swift -o libAsyncInout.dylib

echo "==> Imported class signatures without class-symbol references"
$SWIFTC -parse-as-library -O -emit-library -module-name ImportedClassProbe importedclasses.swift -o libImportedClassProbe.opt.dylib

echo "==> native scalar research corpus with complement/shift/selection cases (researchinteger.swift, -Onone/-O/-Osize)"
for research_configuration in 'ResearchOnone -Onone' 'ResearchOptimized -O' 'ResearchSize -Osize'; do
    read -r research_module research_optimization <<< "$research_configuration"
    $SWIFTC -parse-as-library "$research_optimization" -emit-library -module-name "$research_module" researchinteger.swift -o "lib${research_module}.dylib"
done

echo "==> loop entry constants and nested resets (loopentry.swift, -Onone)"
$SWIFTC -parse-as-library -Onone -emit-library -module-name LoopEntry loopentry.swift -o libLoopEntry.dylib

echo "==> compares fixture (-O) — cmn compares with the negated operand"
$SWIFTC -parse-as-library -O -emit-library -module-name Compares compares.swift -o libCompares.dylib

echo "==> swifterror probe (-O, and stripped) — callees with no name to say they throw"
$SWIFTC -parse-as-library -O -emit-library -module-name SwiftErrorProbe swifterror.swift -o libSwiftErrorProbe.dylib
cp libSwiftErrorProbe.dylib libSwiftErrorProbe.stripped.dylib
strip -x libSwiftErrorProbe.stripped.dylib 2>/dev/null || strip libSwiftErrorProbe.stripped.dylib

echo "==> async fixture (-Onone -g dylib) — entry + resume funclets"
$SWIFTC -parse-as-library -Onone -g -emit-library -module-name AsyncFns asyncfns.swift -o libAsyncFns.dylib

echo "==> async fixture (-O), plus a stripped copy — funclets only in LC_FUNCTION_STARTS"
$SWIFTC -parse-as-library -O -emit-library -module-name AsyncFns asyncfns.swift -o libAsyncFns.opt.dylib
cp libAsyncFns.opt.dylib libAsyncFns.opt.stripped.dylib
strip -x libAsyncFns.opt.stripped.dylib 2>/dev/null || strip libAsyncFns.opt.stripped.dylib

echo "==> variants:"
ls -la sample.debug sample.release sample.stripped libSample.dylib libSample.stripped.dylib libReconstruction.dylib
file sample.release
