#!/bin/bash
# Build several variants of the sample fixture for decompiler testing.
set -euo pipefail
cd "$(dirname "$0")"

SWIFTC="xcrun swiftc"
CLANG="xcrun clang"


echo "==> unknown operator operands keep declared arity (operator_arity.swift, all levels)"
$CLANG -arch arm64 -O2 -c operator_arity.c -o operator_arity.o
for level in Onone O Osize; do
    $SWIFTC -parse-as-library -$level -emit-library -module-name OperatorArity operator_arity.swift operator_arity.o -o libOperatorArity.$level.dylib
done


echo "==> storage shape is not an operator parameter ABI (resilient_operator.swift, all levels)"
python3 build-resilient-operator.py



echo "==> uniqueness results keep their original evaluation (uniqueness_result.swift, all levels)"
for level in Onone O Osize; do
    case "$level" in
        Onone) UNIQUE_RESULT_MODULE=UniquenessResultOnone ;;
        O) UNIQUE_RESULT_MODULE=UniquenessResult ;;
        Osize) UNIQUE_RESULT_MODULE=UniquenessResultSize ;;
    esac
    $SWIFTC -parse-as-library -$level -emit-library -module-name "$UNIQUE_RESULT_MODULE" uniqueness_result.swift -o libUniquenessResult.$level.dylib
done

echo "==> uniqueness object producers keep one evaluation (uniqueness_factory.swift, all levels)"
python3 build-uniqueness-factory.py

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

echo "==> sinks without a ret above a detached block: tail call, br, noreturn call, trap (tailcallsinks.c -O2, tailcallsinks.swift -O)"
xcrun clang -arch arm64 -O2 -dynamiclib -undefined dynamic_lookup tailcallsinks.c -o libTailCallSinks.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name TailCallSinks tailcallsinks.swift -o libTailCallSinks.opt.dylib

echo "==> C imports with no prototype: a stale result, a forwarded parameter, an entry value (importarity.c -O2, importarity.swift -O)"
xcrun clang -arch arm64 -O2 -dynamiclib -undefined dynamic_lookup importarity.c -o libImportArity.dylib
$SWIFTC -parse-as-library -O -emit-library -Xlinker -undefined -Xlinker dynamic_lookup -module-name ImportArity importarity.swift -o libImportArity.opt.dylib

echo "==> imported global addressors: no self, no arguments (importedaddressor.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -Xlinker -undefined -Xlinker dynamic_lookup -module-name ImportedAddressor importedaddressor.swift -o libImportedAddressor.opt.dylib

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

for level in Onone O; do
    echo "==> a setter reached through a vtable (setterarity.swift, -$level)"
    $SWIFTC -parse-as-library -$level -emit-library -module-name SetterArity setterarity.swift -o libSetterArity.$level.dylib
done

echo "==> guarded returns across CFG layouts (returnpaths.s)"
$CLANG -arch arm64 -dynamiclib returnpaths.s -o libReturnPaths.dylib

echo "==> scalar extract and immediate rotation (extract.s)"
$CLANG -arch arm64 -dynamiclib extract.s -o libExtract.dylib

echo "==> scalar byte reversal (bytereversal.s)"
$CLANG -arch arm64 -dynamiclib bytereversal.s -o libByteReversal.dylib

echo "==> bitfield moves, extends and negation (bitfield.s)"
$CLANG -arch arm64 -dynamiclib bitfield.s -o libBitfield.dylib
echo "==> memory writes the pseudocode must and must not show (memory_writes.s)"
$CLANG -arch arm64 -dynamiclib memory_writes.s -o libMemoryWrites.dylib
echo "==> narrow integer constants read at their declared type (narrow_constants.swift, -O)"
$SWIFTC -O -emit-library -module-name Narrow narrow_constants.swift -o libNarrowConstants.dylib

echo "==> writes that replace part of a value (partial_writes.s)"
$CLANG -arch arm64 -dynamiclib partial_writes.s -o libPartialWrites.dylib

echo "==> where call results render: bound before the calls they cross (render_order.s)"
$CLANG -arch arm64 -dynamiclib render_order.s -o libRenderOrder.dylib

echo "==> a call bound for its word reads names its self (boundself.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name BoundSelf boundself.swift -o libBoundSelf.opt.dylib

echo "==> fixpoint visiting order: blocks reached late or through unmodelled edges (fixpoint_order.s)"
$CLANG -arch arm64 -dynamiclib fixpoint_order.s -o libFixpointOrder.dylib

echo "==> callee-saved registers clobbered through nested and tail calls (preserve_calls.s)"
$CLANG -arch arm64 -dynamiclib preserve_calls.s -o libPreserveCalls.dylib

echo "==> an inlined outlined fragment that moves x29 before an x21 reload (outlined_frame.s)"
$CLANG -arch arm64 -dynamiclib -undefined dynamic_lookup outlined_frame.s -o libOutlinedFrame.dylib

echo "==> a String result's second word copied into x20 before a call (string_high_receiver.s)"
$CLANG -arch arm64 -dynamiclib string_high_receiver.s -o libStringHighReceiver.dylib -L"$(xcrun --show-sdk-path)/usr/lib/swift" -lswiftCore

echo "==> body-bounded calls whose callees leave some registers unread (body_reads.s)"
$CLANG -arch arm64 -dynamiclib body_reads.s -o libBodyReads.dylib

echo "==> a clobber inside a switch case, and a switch callee that takes nothing (switch_clobbers.s; switchsummary.c, -O2)"
$CLANG -arch arm64 -dynamiclib switch_clobbers.s -o libSwitchClobbers.dylib
$CLANG -O2 -dynamiclib switchsummary.c -o libSwitchSummary.dylib

echo "==> loops whose header learns a fact only over the back edge (loopescape.c, -O0)"
$CLANG -O0 -dynamiclib loopescape.c -o libLoopEscape.dylib

echo "==> a tail call through self's vtable that resolves into its own function (selftail.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name SelfTail selftail.swift -o libSelfTail.opt.dylib

echo "==> a general register replicated into two- and four-lane vectors (dup_lanes.c, -O2)"
$CLANG -O2 -dynamiclib dup_lanes.c -o libDupLanes.dylib

echo "==> calls through function pointers in writable and read-only-after-fixup data (writablepointer.c, -O2)"
$CLANG -arch arm64 -O2 -dynamiclib writablepointer.c -o libWritablePointer.dylib

echo "==> pointers bound in loader-owned sections of a writable __DATA (writable_tables.m, -O1, -no_data_const)"
$CLANG -arch arm64 -O1 -fobjc-arc -dynamiclib -framework Foundation -Wl,-no_data_const writable_tables.m -o libWritableTables.dylib

echo "==> known-arity calls whose operands are all untracked (untracked_args.c, -O0 and -O2)"
$CLANG -O0 -dynamiclib untracked_args.c -o libUntrackedArgs.dylib
$CLANG -O2 -dynamiclib untracked_args.c -o libUntrackedArgs.opt.dylib

echo "==> known C arities that disagreed with their headers, and entry points that take nothing (known_arity.c, -O0 and -O2; forcedtry.swift, -Onone and -O)"
$CLANG -O0 -dynamiclib -lobjc known_arity.c -o libKnownArity.dylib
$CLANG -O2 -dynamiclib -lobjc known_arity.c -o libKnownArity.opt.dylib
$SWIFTC -parse-as-library -Onone -emit-library -module-name ForcedTry forcedtry.swift -o libForcedTry.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name ForcedTry forcedtry.swift -o libForcedTry.opt.dylib

echo "==> string literals that read as notes once split at two spaces (notetext.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name NoteText notetext.swift -o libNoteText.opt.dylib

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

echo "==> frame fact storage controls: overlapping copies, metadata joins and component budget (frame_fact_store.s)"
$CLANG -arch arm64 -dynamiclib frame_fact_store.s -o libFrameFactStore.dylib

echo "==> register-frame facts: copies, pair offsets and pre/post writeback (frame_register_model.s)"
$CLANG -arch arm64 -dynamiclib frame_register_model.s -o libFrameRegisterModel.dylib

echo "==> frame layout aliases: an interior address does not bound an escaped write (frame_layout_alias.s)"
$CLANG -arch arm64 -dynamiclib frame_layout_alias.s -o libFrameLayoutAlias.dylib

echo "==> objc_retain_xN stubs (retainregister.swift, -O, arm64 iOS simulator)"
$SWIFTC -O -emit-library -module-name RetainRegister -target arm64-apple-ios17.0-simulator \
    -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" retainregister.swift -o libRetainRegister.sim.dylib

echo "==> a rethrow after a cleanup call (rethrowcleanup.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name RethrowCleanup rethrowcleanup.swift -o libRethrowCleanup.opt.dylib

echo "==> 32-bit flag, select and shift probes (widthflags.s, generated by widthflags.swift)"
$CLANG -arch arm64 -dynamiclib widthflags.s -o libWidthFlagProbes.dylib

echo "==> symbolic flag conditions at both widths (flagwidth.s, generated by flagwidth.swift)"
$CLANG -arch arm64 -dynamiclib flagwidth.s -o libFlagWidthProbes.dylib

echo "==> shifted ANDS destination/source overlap probes (andsoverlap.s, generated by andsoverlap.py)"
$CLANG -arch arm64 -dynamiclib andsoverlap.s -o libANDSOverlap.dylib

echo "==> callee-saved vector low-lane preservation (vectorcalleepreservation.s)"
$CLANG -arch arm64 -dynamiclib vectorcalleepreservation.s -o libVectorPreservation.dylib

echo "==> an awaited typed-throws callee (typedthrowsawait.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name TypedThrowsAwait typedthrowsawait.swift -o libTypedThrowsAwait.opt.dylib

echo "==> awaits whose result is not in x0 alone: generic, 5-word, String, Int?, Task.value, async let (awaitresults.swift, -O and -Onone)"
$SWIFTC -parse-as-library -O -emit-library -module-name AwaitResults awaitresults.swift -o libAwaitResults.opt.dylib
$SWIFTC -parse-as-library -Onone -emit-library -module-name AwaitResults awaitresults.swift -o libAwaitResults.onone.dylib

echo "==> throws(Never) specializations serialized by an -O library and emitted by an -Onone client (typedthrowsnever_lib.swift -O, typedthrowsnever.swift -Onone)"
$SWIFTC -parse-as-library -O -emit-library -emit-module -module-name TypedThrowsNeverLib typedthrowsnever_lib.swift -o libTypedThrowsNeverLib.dylib
$SWIFTC -parse-as-library -Onone -emit-library -module-name TypedThrowsNever typedthrowsnever.swift -I . -L . -lTypedThrowsNeverLib -o libTypedThrowsNever.dylib

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

echo "==> String and inout parameter footprints (stringarity.swift, -O): two registers for a String, one for inout"
$SWIFTC -parse-as-library -O -emit-library -module-name StringArity stringarity.swift -o libStringArity.dylib

echo "==> Optional scalar parameter footprints (optionalscalars.swift, -O): a payload and a tag byte"
$SWIFTC -parse-as-library -O -emit-library -module-name OptionalScalars optionalscalars.swift -o libOptionalScalars.dylib

echo "==> calls that take fewer arguments than the live registers: a metadata accessor and swift_getObjectType from @objc initializers (runtimearity.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name RuntimeArity runtimearity.swift -o libRuntimeArity.dylib

echo "==> stores that fill part of a field, or a two-word field with one stp or one q register (fieldwrites.swift, -O; objc_field_copy.m, -O2)"
$SWIFTC -parse-as-library -O -emit-library -module-name FieldWrites fieldwrites.swift -o libFieldWrites.dylib
$CLANG -fobjc-arc -O2 -dynamiclib -framework Foundation objc_field_copy.m -o libObjCFieldCopy.dylib
$CLANG -fobjc-arc -O0 -dynamiclib -framework Foundation objc_field_copy.m -o libObjCFieldCopy.O0.dylib

echo "==> an ARC factory that configures the object it returns through a tail objc_autoreleaseReturnValue (objc_factory_return.m, -O2 and -O0)"
$CLANG -fobjc-arc -O2 -dynamiclib -framework Foundation objc_factory_return.m -o libObjCFactoryReturn.dylib
$CLANG -fobjc-arc -O0 -dynamiclib -framework Foundation objc_factory_return.m -o libObjCFactoryReturn.O0.dylib

echo "==> paired stores covering two ivars, aligned or not with them (objc_pair_stores.m, -O2)"
$CLANG -fobjc-arc -O2 -dynamiclib -framework Foundation objc_pair_stores.m -o libObjCPairStores.dylib

echo "==> a struct-returning send's lanes passed on to a C call (objc_struct_lanes.m, -O2)"
$CLANG -fobjc-arc -O2 -dynamiclib -framework Foundation -framework CoreGraphics -framework OpenGL objc_struct_lanes.m -o libObjCStructLanes.dylib

echo "==> float constants inside float expressions (float_constants.c, -O2)"
$CLANG -O2 -dynamiclib -framework OpenGL -framework CoreFoundation float_constants.c -o libFloatConstants.dylib

echo "==> LSE and RCpc atomics on a plain arm64 slice (atomics.c, -O2)"
$CLANG -O2 -dynamiclib atomics.c -o libAtomics.dylib

echo "==> calls of SDK C functions laid out from their declarations (c_prototypes.c, -O2)"
$CLANG -O2 -dynamiclib -framework OpenGL -undefined dynamic_lookup c_prototypes.c -o libCPrototypes.dylib

echo "==> a Swift @objc getter thunk returning an untracked ivar (objc_thunk_return.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name ObjCThunkReturn objc_thunk_return.swift -o libObjCThunkReturn.dylib

echo "==> an autoreleased object used twice, without ARC (objc_autorelease.m, -O2)"
$CLANG -fno-objc-arc -O2 -dynamiclib -framework Foundation objc_autorelease.m -o libObjCAutorelease.dylib

echo "==> a call whose result only an argument an untyped send drops holds (objc_dropped_result.m, -O2)"
$CLANG -fobjc-arc -O2 -dynamiclib -framework Foundation objc_dropped_result.m -o libObjCDroppedResult.dylib

echo "==> a field of self held in a register across a call that writes it (field_aliases.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name FieldAliases field_aliases.swift -o libFieldAliases.dylib

echo "==> calls to generic specializations, laid out from their substitutions (specializations.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name Specializations specializations.swift -o libSpecializations.dylib

echo "==> a dropped metatype after a resilient typed-error SIL result (resilienttypederror*.swift, -O/-Osize, macOS 15)"
resilient_spec_sdk="$(xcrun --sdk macosx --show-sdk-path)"
$SWIFTC -sdk "$resilient_spec_sdk" -target arm64-apple-macosx15.0 -parse-as-library -O -enable-library-evolution -emit-module -emit-library -module-name RemoteErrors resilienttypederror_errors.swift -emit-module-path RemoteErrors.swiftmodule -Xlinker -install_name -Xlinker @rpath/libRemoteErrors.dylib -o libRemoteErrors.dylib
$SWIFTC -sdk "$resilient_spec_sdk" -target arm64-apple-macosx15.0 -parse-as-library -O -emit-library -module-name RemoteClient resilienttypederror.swift -I . -L . -lRemoteErrors -Xlinker -rpath -Xlinker @loader_path -o libResilientTypedError.dylib
$SWIFTC -sdk "$resilient_spec_sdk" -target arm64-apple-macosx15.0 -parse-as-library -Osize -emit-library -module-name RemoteClient resilienttypederror.swift -I . -L . -lRemoteErrors -Xlinker -rpath -Xlinker @loader_path -o libResilientTypedError.Osize.dylib

echo "==> conditions comparing against a literal holding a quote (quoted_conditions.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name QuotedConditions quoted_conditions.swift -o libQuotedConditions.dylib

echo "==> literals holding a quote or a backslash (literal_escapes.swift, -O and -Onone; literal_escapes.m, -O2)"
$SWIFTC -parse-as-library -O -emit-library -module-name LiteralEscapes literal_escapes.swift -o libLiteralEscapes.dylib
$SWIFTC -parse-as-library -Onone -emit-library -module-name LiteralEscapes literal_escapes.swift -o libLiteralEscapes.Onone.dylib
$CLANG -fobjc-arc -O2 -dynamiclib -framework Foundation literal_escapes.m -o libObjCLiteralEscapes.dylib

echo "==> an in-image function named like a libc entry of known arity (arity_twin.c, -O2)"
$CLANG -O2 -dynamiclib arity_twin.c -o libArityTwin.dylib

echo "==> in-image functions named like C library functions, with other bodies (libc_twins.c, -O2 -fno-builtin)"
$CLANG -O2 -fno-builtin -dynamiclib libc_twins.c -o libLibcTwins.dylib

echo "==> a class field of an imported C struct, read through its member (cstructfield.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name CStructField cstructfield.swift -o libCStructField.dylib

echo "==> a field tested after it was overwritten (fieldstore.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name FieldStore fieldstore.swift -o libFieldStore.dylib

echo "==> an inner loop's exit that leaves the outer loop too (loopexit.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name LoopExit loopexit.swift -o libLoopExit.dylib

echo "==> the same ObjC with opcode rebases and with chained fixups (opcodefixups.m, -O1)"
$CLANG -fobjc-arc -O1 -dynamiclib -framework Foundation -mmacosx-version-min=11.0 opcodefixups.m -o libOpcodeFixups.dylib
$CLANG -fobjc-arc -O1 -dynamiclib -framework Foundation -mmacosx-version-min=13.0 opcodefixups.m -o libOpcodeFixups.chained.dylib

echo "==> SDK sends returning an NSRange in x0 and x1 (objc_range_return.m, -O1)"
$CLANG -fobjc-arc -O1 -dynamiclib -framework Foundation -framework AppKit objc_range_return.m -o libObjCRangeReturn.dylib

echo "==> variadic SDK selectors outside the name suffixes (objc_variadic_selectors.m, -O1)"
$CLANG -fobjc-arc -O1 -dynamiclib -framework Foundation objc_variadic_selectors.m -o libObjCVariadicSelectors.dylib

echo "==> direct calls in a stripped executable with no function starts (mergedcalls.c, -O1)"
$CLANG -O1 mergedcalls.c -Wl,-no_function_starts -o mergedcalls.stripped
xcrun strip mergedcalls.stripped

echo "==> a receiver left in x20 across a call to another module (selfagain.swift, selfagainkit.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -emit-module -module-name SelfAgainKit selfagainkit.swift -o libSelfAgainKit.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name SelfAgain selfagain.swift -I . -L . -lSelfAgainKit -o libSelfAgain.dylib

echo "==> a protocol witness that tail-calls its member (witnesstail.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name WitnessTail witnesstail.swift -o libWitnessTail.dylib

echo "==> a closure's captures passed after its formals (closurecapture.swift, -Onone)"
$SWIFTC -parse-as-library -Onone -emit-library -module-name ClosureCapture closurecapture.swift -o libClosureCapture.dylib

echo "==> a small struct's self words after its formals (valueselfwords.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name ValueSelfWords valueselfwords.swift -o libValueSelfWords.dylib

echo "==> the platform register across a call (platformregister.s)"
$CLANG -arch arm64 -dynamiclib -undefined dynamic_lookup platformregister.s -o libPlatformRegister.dylib

echo "==> direct Objective-C methods, no _cmd (objcdirect.m, -O0 and -O1)"
$CLANG -O0 -fobjc-arc -dynamiclib -framework Foundation objcdirect.m -o libObjCDirect.O0.dylib
$CLANG -O1 -fobjc-arc -dynamiclib -framework Foundation objcdirect.m -o libObjCDirect.dylib

echo "==> optional protocol properties, decided by the getter's list (objcoptionalprop.m, -O1)"
$CLANG -O1 -fobjc-arc -dynamiclib -framework Foundation objcoptionalprop.m -o libObjCOptionalProp.dylib

echo "==> a default argument's generator takes no parameters (defaultargument.swift, -Onone)"
xcrun swiftc -Onone -parse-as-library -emit-library defaultargument.swift -module-name DefaultArgument -o libDefaultArgument.dylib

echo "==> calls through a register to an in-image function (registercall.s)"
$CLANG -arch arm64 -dynamiclib registercall.s -o libRegisterCall.dylib

echo "==> a chained bind whose 64-bit import addend has the top bit set (bindaddend.s)"
$CLANG -arch arm64 -dynamiclib bindaddend.s -lobjc -o libBindAddend.dylib

echo "==> throwing getters whose storage type is a function type (throwinggetter.swift, -O)"
$SWIFTC -O -parse-as-library -emit-library -module-name TG throwinggetter.swift -o libThrowingGetter.dylib

echo "==> preconditions that branch to a trap on overflow or carry flags, beside real overflow checks (guardfold.swift, -O)"
$SWIFTC -O -parse-as-library -emit-library -module-name GF guardfold.swift -o libGuardFold.dylib

echo "==> when a tail branch to a C-named callee returns its result (tailprototype.swift + tailprototype_twin.c, -O)"
$CLANG -O2 -fno-builtin -c tailprototype_twin.c -o tailprototype_twin.o
xcrun swiftc -O -parse-as-library -emit-library tailprototype.swift tailprototype_twin.o -module-name TailPrototype -Xlinker -undefined -Xlinker dynamic_lookup -o libTailPrototype.dylib
rm -f tailprototype_twin.o

echo "==> objc_opt_new is a +new send (optnew.m, -O2)"
$CLANG -O2 -fobjc-arc -dynamiclib -framework Foundation optnew.m -o libOptNew.dylib

echo "==> runtime calls that are statements, not ARC noise (runtimestatements.m, -O2)"
$CLANG -O2 -fobjc-arc -dynamiclib -framework Foundation -undefined dynamic_lookup runtimestatements.m -o libRuntimeStatements.dylib

echo "==> constant NSStrings by their flags and length: UTF-16, NUL, empty (cfstrings.m, -O2)"
$CLANG -O2 -fobjc-arc -dynamiclib -framework Foundation cfstrings.m -o libCFStrings.dylib
$CLANG -arch arm64 -dynamiclib -framework Foundation cfstrings_short.s -o libCFStringsShort.dylib

echo "==> AnyObject.Type in one register (anyobjectmeta.swift, -O)"
xcrun swiftc -O -parse-as-library -emit-library anyobjectmeta.swift -module-name AnyObjectMeta -o libAnyObjectMeta.dylib

echo "==> tail branches to a getter and to runtime entry points (tailforward.swift, -O)"
xcrun swiftc -O -parse-as-library -emit-library tailforward.swift -module-name TailForward -o libTailForward.dylib

echo "==> signed orderings on unsigned operands, and UInt against Int (signedcompare.swift, -O)"
xcrun swiftc -O -parse-as-library -emit-library signedcompare.swift -module-name SignedCompare -o libSignedCompare.dylib

echo "==> what x0 holds at a C function's return, no signature (unprovenresult.c, -O2)"
$CLANG -O2 -dynamiclib -undefined dynamic_lookup unprovenresult.c -o libUnprovenResult.dylib

echo "==> value self from both register banks (mixedself.swift, -O)"
xcrun swiftc -O -parse-as-library -emit-library mixedself.swift -module-name MixedSelf -o libMixedSelf.dylib

echo "==> key path intrinsics with live registers past their arguments (keypathintrinsics.swift, -O)"
xcrun swiftc -O -parse-as-library -emit-library keypathintrinsics.swift -module-name KeyPathIntrinsics -o libKeyPathIntrinsics.dylib
$CLANG -arch arm64 -dynamiclib -undefined dynamic_lookup keypathintrinsics.s -o libKeyPathIntrinsicsAsm.dylib

echo "==> a signed conversion of an unsigned argument (signedfloat.swift, -O)"
xcrun swiftc -O -parse-as-library -emit-library signedfloat.swift -module-name SignedFloat -o libSignedFloat.dylib

echo "==> a compare that writes its own operand (writtenflags.c, -O1 and -O2)"
$CLANG -O1 -dynamiclib -undefined dynamic_lookup writtenflags.c -o libWrittenFlags.O1.dylib
$CLANG -O2 -dynamiclib -undefined dynamic_lookup writtenflags.c -o libWrittenFlags.dylib

echo "==> loops whose bodies end in an if/else that leaves on both arms (deadexit.s)"
$CLANG -arch arm64 -dynamiclib deadexit.s -o libDeadExit.dylib

echo "==> a loop counter held in a register (registerloop.swift, -O and -Osize)"
$SWIFTC -parse-as-library -O -emit-library -module-name RegisterLoop registerloop.swift -o libRegisterLoop.dylib
$SWIFTC -parse-as-library -Osize -emit-library -module-name RegisterLoop registerloop.swift -o libRegisterLoop.Osize.dylib

echo "==> an in-image callee that reads a stack argument, framed or not (stackargs.c, -O1, -O0 and -Oz)"
$CLANG -O1 -dynamiclib -undefined dynamic_lookup stackargs.c -o libStackArgs.dylib
$CLANG -O0 -dynamiclib -undefined dynamic_lookup stackargs.c -o libStackArgs.O0.dylib
$CLANG -Oz -dynamiclib -undefined dynamic_lookup stackargs.c -o libStackArgs.Oz.dylib

echo "==> SDK calls from their declarations: open, fcntl, ioctl, closedir, sysctl (variadic_calls.c, -O1)"
$CLANG -O1 -dynamiclib variadic_calls.c -o libVariadicCalls.dylib

echo "==> a call that only decides a branch whose arms render nothing (consumed_call.c, -O1)"
$CLANG -O1 -dynamiclib -undefined dynamic_lookup consumed_call.c -o libConsumedCall.dylib

echo "==> variadic ObjC fixture (-O1) — format arguments on the stack"
$CLANG -O1 -fobjc-arc -framework Foundation -dynamiclib variadic.m -o libVariadic.dylib

echo "==> vector-register lanes (vectorlane.m -O0/-O2, vectorlane.swift -Onone/-O): a d0 read after movi v0.2d, #0"
$CLANG -arch arm64 -O0 -fobjc-arc -framework Foundation -dynamiclib vectorlane.m -o libVectorLane.O0.dylib
$CLANG -arch arm64 -O2 -fobjc-arc -framework Foundation -dynamiclib vectorlane.m -o libVectorLane.O2.dylib
$SWIFTC -parse-as-library -Onone -emit-library -module-name VectorLane vectorlane.swift -o libVectorLaneSwift.Onone.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name VectorLane vectorlane.swift -o libVectorLaneSwift.O.dylib

echo "==> floating variadic slots (variadicfloat.m, -O0 and -O2): a double passed as its bits"
$CLANG -arch arm64 -O0 -fobjc-arc -framework Foundation -dynamiclib variadicfloat.m -o libVariadicFloat.O0.dylib
$CLANG -arch arm64 -O2 -fobjc-arc -framework Foundation -dynamiclib variadicfloat.m -o libVariadicFloat.O2.dylib

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

echo "==> encryptable dylib (-Onone, ld -encryptable): LC_ENCRYPTION_INFO_64, cryptid 0"
$SWIFTC -parse-as-library -emit-library -module-name Encryptable encryptable.swift -o libEncryptable.dylib -Xlinker -encryptable

echo "==> functions in __TEXT,__realtime and __TEXT,__text_cold (codesections.c, -O1)"
xcrun clang -arch arm64 -O1 -dynamiclib codesections.c -o libCodeSections.dylib

echo "==> absolute symbols, one of them -1 (absolutesymbols.s): constants, not addresses"
xcrun clang -arch arm64 -dynamiclib absolutesymbols.s -o libAbsoluteSymbols.dylib

echo "==> a negative symbol offset (negativeabsolute.s): N_ABS with bit 63 set, beside a folded address"
xcrun clang -arch arm64 -dynamiclib negativeabsolute.s -o libNegativeAbsolute.dylib

echo "==> bitfield ivars sharing an offset (objcbitfields.m, -O1): only the bit tells them apart"
xcrun clang -arch arm64 -O1 -dynamiclib -framework Foundation objcbitfields.m -o libObjCBitfields.dylib

echo "==> SVE writes to z registers (sveregisters.s): no scalar model, and z0 aliases v0"
xcrun clang -arch arm64 -march=armv8-a+sve -dynamiclib sveregisters.s -o libSVERegisters.dylib

echo "==> Go program, stripped and not (gofunctions/): functions only in __gopclntab"
if command -v go >/dev/null; then
    (cd gofunctions && GOFLAGS=-mod=mod GOOS=darwin GOARCH=arm64 go build -trimpath -o ../goProgram .)
    (cd gofunctions && GOFLAGS=-mod=mod GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o ../goProgram.stripped .)
else
    echo "    go is not installed: goProgram and goProgram.stripped not built"
fi

echo "==> first function's symbol stripped (localfirst.s, strip -x): objdump's path line is no label"
xcrun clang -arch arm64 -dynamiclib localfirst.s -o libLocalFirst.stripped.dylib
strip -x libLocalFirst.stripped.dylib

echo "==> no LC_FUNCTION_STARTS (nofunctionstarts.c, -Wl,-no_function_starts): symbols bound a decode"
xcrun clang -arch arm64 -O1 -dynamiclib nofunctionstarts.c -o libNoFunctionStarts.dylib -Wl,-no_function_starts

echo "==> accessor extents past 6 KB, synthesized and custom (accessorextent*.m, -no_function_starts, strip -x)"
xcrun clang -arch arm64 -O1 -dynamiclib -framework Foundation accessorextent.m -o libAccessorExtent.dylib -Wl,-no_function_starts
strip -x libAccessorExtent.dylib
xcrun clang -arch arm64 -O1 -dynamiclib -framework Foundation accessorextentcustom.m -o libAccessorExtentCustom.dylib -Wl,-no_function_starts
strip -x libAccessorExtentCustom.dylib

echo "==> 100 and 800 classes of 14 accessors (gen-manyaccessors.sh, -O1, ARC): objc's memory against the accessor count"
for classes in 100 800; do
  ./gen-manyaccessors.sh $classes > manyaccessors$classes.m
  xcrun clang -arch arm64 -O1 -fobjc-arc -dynamiclib -framework Foundation manyaccessors$classes.m -o libManyAccessors$classes.dylib
  rm manyaccessors$classes.m
done

echo "==> one-block accessors, synthesized and computed (accessorshapes.m, -O0, -O1, -Os, ARC)"
for level in O0 O1 Os; do
  xcrun clang -arch arm64 -$level -fobjc-arc -dynamiclib -framework Foundation accessorshapes.m -o libAccessorShapes.$level.dylib
done

echo "==> ivars the encoding types only in part: bitfields, char against BOOL (objcivartypes.m, -O1)"
xcrun clang -arch arm64 -O1 -dynamiclib -framework Foundation objcivartypes.m -o libObjCIvarTypes.dylib

echo "==> accessors with no verdict: past the decode prefix, outside __text (accessordeclined.m, -O1, ARC)"
xcrun clang -arch arm64 -O1 -fobjc-arc -dynamiclib -framework Foundation accessordeclined.m -o libAccessorDeclined.dylib

echo "==> a getter that returns a constant (constantgetter.m): custom, not synthesized"
xcrun clang -arch arm64 -O1 -dynamiclib -framework Foundation constantgetter.m -o libConstantGetter.dylib

echo "==> local types and constrained existentials (localtypes.swift, -O; strip -x drops the type symbols)"
xcrun swiftc -O -parse-as-library -emit-library localtypes.swift -module-name LocalTypes -o libLocalTypes.dylib
cp libLocalTypes.dylib libLocalTypes.stripped.dylib
strip -x libLocalTypes.stripped.dylib
# Its own install name: MachOSwiftSection keys per-image caches by install
# name and LC_UUID, so tests reading the original and this copy in parallel
# would share them. libLocalTypesPair keeps the shared key on purpose.
install_name_tool -id libLocalTypes.stripped.dylib libLocalTypes.stripped.dylib

echo "==> declarations against what the binary proves (interfacefacts.swift: -O, -Onone, -O without reflection metadata)"
xcrun swiftc -O -parse-as-library -emit-library interfacefacts.swift -module-name InterfaceFacts -o libInterfaceFacts.dylib
xcrun swiftc -Onone -parse-as-library -emit-library interfacefacts.swift -module-name InterfaceFacts -o libInterfaceFacts.Onone.dylib
xcrun swiftc -O -disable-reflection-metadata -parse-as-library -emit-library interfacefacts.swift -module-name InterfaceFacts -o libInterfaceFacts.noreflection.dylib

echo "==> a stripped copy and its original under an install name no other test loads (localtypes.swift, -O; strip -x)"
xcrun swiftc -O -parse-as-library -emit-library localtypes.swift -module-name LocalTypes -o libLocalTypesPair.dylib
cp libLocalTypesPair.dylib libLocalTypesPair.stripped.dylib
strip -x libLocalTypesPair.stripped.dylib

echo "==> a protocol requirement whose right-hand side is a generic type (protocolrhs.swift, -O)"
xcrun swiftc -O -parse-as-library -emit-library protocolrhs.swift -module-name ProtocolRHS -o libProtocolRHS.dylib

echo "==> local types whose anonymous contexts keep their mangled names, as Apple's cache images do (localtypes.swift, -O; strip -x)"
xcrun swiftc -O -parse-as-library -emit-library localtypes.swift -module-name LocalTypes -Xfrontend -enable-anonymous-context-mangled-names -o libLocalTypesNamed.dylib
cp libLocalTypesNamed.dylib libLocalTypesNamed.stripped.dylib
strip -x libLocalTypesNamed.stripped.dylib

echo "==> a type no __swift5_types record lists (unrecordedtype.swift, -O -wmo; record removed by droptyperecord.py)"
xcrun swiftc -O -wmo -parse-as-library -emit-library unrecordedtype.swift -module-name UnrecordedType -o libUnrecordedType.dylib
python3 -I droptyperecord.py libUnrecordedType.dylib '_$s14UnrecordedType5InnerVMn'

echo "==> a class subscript getter's index argument (subscriptgetter.swift, -Onone)"
$SWIFTC -parse-as-library -Onone -emit-library -module-name SubscriptGetter subscriptgetter.swift -o libSubscriptGetter.dylib

echo "==> requirements called through dispatch thunks (gaugekit.swift -O resilient, gaugeclient.swift -O)"
$SWIFTC -parse-as-library -O -enable-library-evolution -emit-library -emit-module -module-name GaugeKit gaugekit.swift -o libGaugeKit.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name GaugeClient gaugeclient.swift -I . -L . -lGaugeKit -o libGaugeClient.dylib

echo "==> value-type method arguments: formal parameters, then self (valuemethod.swift, -O; strip -x leaves appendTwo unnamed)"
$SWIFTC -parse-as-library -O -emit-library -module-name ValueMethod valuemethod.swift -o libValueMethod.dylib
cp libValueMethod.dylib libValueMethod.stripped.dylib
strip -x libValueMethod.stripped.dylib

echo "==> a StaticString parameter's three words (statictext.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name StaticText statictext.swift -o libStaticText.dylib

echo "==> the mangled-name metadata helper and two look-alikes, stripped (mangledhelper.s)"
$CLANG -arch arm64 -dynamiclib mangledhelper.s -L"$(xcrun --show-sdk-path)/usr/lib/swift" -lswiftCore -o libMangledHelper.dylib
cp libMangledHelper.dylib libMangledHelper.stripped.dylib
strip -x libMangledHelper.stripped.dylib

echo "==> the two pre-V2 mangled-name metadata helpers, stripped (oldmangledhelper.s)"
$CLANG -arch arm64 -dynamiclib oldmangledhelper.s -L"$(xcrun --show-sdk-path)/usr/lib/swift" -lswiftCore -o libOldMangledHelper.dylib
cp libOldMangledHelper.dylib libOldMangledHelper.stripped.dylib
strip -x libOldMangledHelper.stripped.dylib

echo "==> a struct result buffer a runtime call overwrites through x8, or leaves (resultbuffer.swift + .s, -O)"
$CLANG -arch arm64 -c resultbuffer.s -o resultbuffer.o
$SWIFTC -parse-as-library -O -emit-library -module-name ResultBuffer resultbuffer.swift resultbuffer.o -o libResultBuffer.dylib
rm -f resultbuffer.o

echo "==> function signature specializations that drop a parameter (deadargs.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name DeadArgs deadargs.swift -o libDeadArgs.dylib

echo "==> an Int after parameters of fixed multi-word or unseeded footprint (entryfootprints.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name EntryFootprints entryfootprints.swift -o libEntryFootprints.dylib

echo "==> calls whose results span registers, one part used (multiresult.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name MultiResult multiresult.swift -o libMultiResult.dylib

echo "==> a one-case enum parameter, zero-sized (onecase.swift, -Onone)"
$SWIFTC -parse-as-library -Onone -emit-library -module-name OneCase onecase.swift -o libOneCase.dylib

echo "==> swift_dynamicCast's Bool result (dynamiccast.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name DynamicCast dynamiccast.swift -o libDynamicCast.dylib

echo "==> bridging from Objective-C in @objc thunks (objcbridge.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name ObjCBridge objcbridge.swift -o libObjCBridge.dylib

echo "==> a throw that shares the normal return's ret (throwselect.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name ThrowSelect throwselect.swift -o libThrowSelect.dylib

echo "==> a temporary parked in x20 before a callee with no self there (parkedself.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name ParkedSelf parkedself.swift -o libParkedSelf.dylib

echo "==> 32-bit signed comparisons and a w sign-bit test (signed32.c, -O2)"
$CLANG -arch arm64 -O2 -dynamiclib -undefined dynamic_lookup signed32.c -o libSigned32.dylib

echo "==> Objective-C returns in v0, d0-d3 and through x8 (objcreturns.m, -O2)"
$CLANG -arch arm64 -O2 -fobjc-arc -dynamiclib -framework Foundation objcreturns.m -o libObjCReturns.dylib

echo "==> Objective-C results outside x0 after a last call (objcvreturns.m, -O2 and -O0)"
$CLANG -arch arm64 -O2 -fobjc-arc -dynamiclib -framework Foundation objcvreturns.m -o libObjCVReturns.dylib
$CLANG -arch arm64 -O0 -fobjc-arc -dynamiclib -framework Foundation objcvreturns.m -o libObjCVReturnsO0.dylib

echo "==> calls to async functions, direct and indirect results (asynccalls.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name AsyncCalls asynccalls.swift -o libAsyncCalls.dylib

echo "==> calls to unspecialized generic functions (genericcalls.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name GenericCalls genericcalls.swift -o libGenericCalls.dylib

echo "==> a generic specialization that drops its metatype argument, Tt (droppedmeta.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name DroppedMeta droppedmeta.swift -o libDroppedMeta.dylib

echo "==> specializations that drop arguments or propagate closures (droppedargs.swift, -O, -Osize, -Onone)"
$SWIFTC -parse-as-library -O -emit-library -module-name DroppedArgs droppedargs.swift -o libDroppedArgs.dylib
$SWIFTC -parse-as-library -Osize -emit-library -module-name DroppedArgs droppedargs.swift -o libDroppedArgs.Osize.dylib
$SWIFTC -parse-as-library -Onone -emit-library -module-name DroppedArgs droppedargs.swift -o libDroppedArgs.Onone.dylib

echo "==> vector lane moves, ins and umov (vectorlanes.s)"
$CLANG -arch arm64 -dynamiclib vectorlanes.s -o libVectorLanes.dylib

echo "==> upper lanes of v8-v15 across calls, which AAPCS64 does not preserve (vectorcallclobber.s)"
$CLANG -arch arm64 -dynamiclib vectorcallclobber.s -o libVectorCallClobber.dylib

echo "==> a saved register's slot passed to a callback through d0 or v0.d[1] (fpaliascalls.s)"
$CLANG -arch arm64 -dynamiclib fpaliascalls.s -o libFPAlias.dylib

echo "==> Objective-C struct results read one field at a time (objc_send_results.m, -O2)"
$CLANG -arch arm64 -O2 -dynamiclib -lobjc objc_send_results.m -o libObjCSendResults.dylib

echo "==> packed SIMD forms of scalar opcodes (packedarithmetic.s)"
$CLANG -arch arm64 -dynamiclib packedarithmetic.s -o libPackedArithmetic.dylib

echo "==> explicit Void parameters, which take no register (voidarguments.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name VoidArguments voidarguments.swift -o libVoidArguments.dylib

echo "==> MOVI by arrangement and shift, LSL and MSL (vectorimmediates.s)"
$CLANG -arch arm64 -dynamiclib vectorimmediates.s -o libVectorImmediates.dylib

echo "==> selected vector lanes through calls and Q spills (selectedvectorlanes.s)"
$CLANG -arch arm64 -dynamiclib selectedvectorlanes.s -o libSelectedVectorLanes.dylib

echo "==> fmov immediates in vector and half-precision registers (fpimmediates.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name FPImmediates fpimmediates.swift -o libFPImmediates.dylib

echo "==> scvtf and ucvtf from word and doubleword registers (intconvert.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name IntConvert intconvert.swift -o libIntConvert.dylib

echo "==> struct, SIMD and closure parameters (structargs.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name StructArgs structargs.swift -o libStructArgs.dylib

echo "==> function-valued collection ABI, the > of -> in a generic argument (closurecollections.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name ClosureCollections closurecollections.swift -o libClosureCollections.dylib

echo "==> standard-library value methods' self in x20 (stdself.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name StdSelf stdself.swift -o libStdSelf.dylib

echo "==> float argument reads of signatureless C callees (floatreads.c, -O2)"
$CLANG -O2 -dynamiclib floatreads.c -o libFloatReads.dylib

echo "==> computed narrow integer results (narrowreturns.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name NarrowReturns narrowreturns.swift -o libNarrowReturns.dylib

echo "==> narrow C integer arguments read at their declared width (cnarrowargs.c, -O2)"
$CLANG -O2 -dynamiclib cnarrowargs.c -o libCNarrowArgs.dylib

echo "==> C format strings and printf arguments (cformat.c, -O2)"
$CLANG -O2 -dynamiclib cformat.c -o libCFormat.dylib

echo "==> closure-propagated call names and native controls (closprop.swift, -O/-Osize/-Onone, macOS 15)"
closure_render_sdk="$(xcrun --sdk macosx --show-sdk-path)"
$SWIFTC -sdk "$closure_render_sdk" -target arm64-apple-macosx15.0 -parse-as-library -O -emit-library -module-name ClosProp closprop.swift -o libClosProp.dylib
$SWIFTC -sdk "$closure_render_sdk" -target arm64-apple-macosx15.0 -parse-as-library -Osize -emit-library -module-name ClosProp closprop.swift -o libClosProp.Osize.dylib
$SWIFTC -sdk "$closure_render_sdk" -target arm64-apple-macosx15.0 -parse-as-library -Onone -emit-library -module-name ClosProp closprop.swift -o libClosProp.Onone.dylib

echo "==> generic and class metatype parameters (metatypeargs.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name MetatypeArgs metatypeargs.swift -o libMetatypeArgs.dylib

echo "==> structs passed in their fields' registers (structlowering.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name StructLowering structlowering.swift -o libStructLowering.dylib

echo "==> a call through two pointers the image fixes, read-only and writable (staticwitness.s)"
$CLANG -arch arm64 -dynamiclib staticwitness.s -o libStaticWitness.dylib

echo "==> value-witness calls on a metadata accessor's result (accessorwitness.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name AccessorWitness accessorwitness.swift -o libAccessorWitness.dylib

echo "==> unspecialized generic functions' metadata and witnesses (genericwitness.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name GenericWitness genericwitness.swift -o libGenericWitness.dylib

echo "==> value-witness calls on a demangling cache variable's metadata (codablewitness.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name CodableWitness codablewitness.swift -o libCodableWitness.dylib

echo "==> a value-witness call on metadata loaded from the GOT (gotwitness.s)"
$CLANG -arch arm64 -dynamiclib gotwitness.s -L"$(xcrun --show-sdk-path)/usr/lib/swift" -lswiftCore -o libGOTWitness.dylib

echo "==> a generic class's value witnesses through self's metadata (classwitness.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name ClassWitness classwitness.swift -o libClassWitness.dylib

echo "==> a generic class's isa kept across calls names its witnesses (spillwitness.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name SpillWitness spillwitness.swift -o libSpillWitness.dylib

echo "==> the stack probe keeps the frame across dynamic allocations (chkstkwitness.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name ChkstkWitness chkstkwitness.swift -o libChkstkWitness.dylib

echo "==> a system metadata accessor takes its key generic arguments only (accessorarity.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name AccessorArity accessorarity.swift -o libAccessorArity.dylib

echo "==> x20 is self for a resilient system value type, not a frozen one (frozenself.s)"
$CLANG -arch arm64 -dynamiclib frozenself.s -L"$(xcrun --show-sdk-path)/usr/lib/swift" -lswiftCore -framework Foundation -o libFrozenSelf.dylib

echo "==> a dynamic allocation of unknown size keeps the frame (unknownalloca.s)"
$CLANG -arch arm64 -dynamiclib unknownalloca.s -o libUnknownAlloca.dylib

echo "==> a stripped vtable accessor names no property (strippedaccessor.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name StrippedAccessor strippedaccessor.swift -o libStrippedAccessor.dylib
cp libStrippedAccessor.dylib libStrippedAccessor.stripped.dylib
strip -x libStrippedAccessor.stripped.dylib

echo "==> a setter dispatch folds to its value as its type travels (setterfold.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name SetterFold setterfold.swift -o libSetterFold.dylib

echo "==> a class inheriting from Objective-C reads its metadata through its masked isa (isamask.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name IsaMask isamask.swift -o libIsaMask.dylib

echo "==> a String return read from both of its words, x0 and x1 (stringreturns.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name StringReturns stringreturns.swift -o libStringReturns.dylib

echo "==> a generic class's protocol requirements through self's metadata (classprotowitness.swift, -O; resilient, and a fragile copy with no method descriptor symbols)"
$SWIFTC -parse-as-library -O -enable-library-evolution -emit-library -module-name ClassProtoWitness classprotowitness.swift -o libClassProtoWitness.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name ClassProtoWitness classprotowitness.swift -o libClassProtoWitness.fragile.dylib

echo "==> self's isa loaded before a loop and read after it (loopisa.swift, -O, resilient)"
$SWIFTC -parse-as-library -O -enable-library-evolution -emit-library -module-name LoopIsa loopisa.swift -o libLoopIsa.dylib

echo "==> a String picked by a condition, one csel per word (stringselects.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name StringSelects stringselects.swift -o libStringSelects.dylib

echo "==> two selects that are no one String pick (string_selects.s)"
$CLANG -arch arm64 -dynamiclib string_selects.s -o libStringSelectsAsm.dylib

echo "==> a throwing function that hands on a throwing call's outcome (throwforward.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name ThrowForward throwforward.swift -o libThrowForward.dylib

echo "==> forwards and near-forwards of a throwing call, by hand (throw_forward.s)"
$CLANG -arch arm64 -dynamiclib throw_forward.s -o libThrowForwardAsm.dylib

echo "==> a generic function's witness-table arguments (funcprotowitness.swift, -O, resilient)"
$SWIFTC -parse-as-library -O -enable-library-evolution -emit-library -module-name FuncProtoWitness funcprotowitness.swift -o libFuncProtoWitness.dylib

echo "==> generic functions that pass fewer metadata arguments than parameters (metadatasource.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name MetadataSource metadatasource.swift -o libMetadataSource.dylib
echo "==> two selects on one load with memory written between them (selectstore.swift, select_store.s, -O)"
$CLANG -arch arm64 -c select_store.s -o select_store.o
$SWIFTC -parse-as-library -O -emit-library -module-name SelectStore selectstore.swift select_store.o -o libSelectStore.dylib
rm -f select_store.o

echo "==> a specialization that rewrites self's parameter takes no self in x20 (tfself.swift, tf_self.s, -O)"
$CLANG -arch arm64 -c tf_self.s -o tf_self.o
$SWIFTC -parse-as-library -O -emit-library -module-name TfSelf tfself.swift tf_self.o -o libTfSelf.dylib
rm -f tf_self.o

echo "==> a no-payload enum's self by address in x20 (resilientself.swift, resilient_self.s, -Onone, -O, -Osize, library evolution)"
$CLANG -arch arm64 -c resilient_self.s -o resilient_self.o
for level in Onone O Osize; do
    $SWIFTC -parse-as-library -$level -enable-library-evolution -emit-library -module-name ResilientSelf \
        resilientself.swift resilient_self.o -o libResilientSelf.$level.dylib
done
rm -f resilient_self.o

echo "==> a vtable call on self's class-typed field, and a same-named class from another module (fieldvtable.swift, fieldvtable_other.swift, -O, -Onone)"
for level in O Onone; do
    suffix=$([ $level = O ] && echo "" || echo ".Onone")
    rm -rf fvo_module && mkdir fvo_module
    $SWIFTC -parse-as-library -$level -emit-library -emit-module -module-name FieldVTableOther fieldvtable_other.swift \
        -emit-module-path fvo_module/FieldVTableOther.swiftmodule \
        -Xlinker -install_name -Xlinker @rpath/libFieldVTableOther$suffix.dylib -o libFieldVTableOther$suffix.dylib
    $SWIFTC -parse-as-library -$level -emit-library -module-name FieldVTable fieldvtable.swift -I fvo_module \
        -L . -lFieldVTableOther$suffix -Xlinker -rpath -Xlinker @loader_path -o libFieldVTable$suffix.dylib
done
rm -rf fvo_module

echo "==> requirement calls through an opaque existential argument's witness table (existentialwitness.swift, existential_unpassed.s, -O, -Onone, library evolution)"
$CLANG -arch arm64 -c existential_unpassed.s -o existential_unpassed.o
for variant in "O:" "Onone:.Onone" "O -enable-library-evolution:.resilient"; do
    flags=${variant%%:*}; suffix=${variant#*:}
    rm -rf ew_module && mkdir ew_module
    $SWIFTC -parse-as-library -$flags -emit-library -emit-module -module-name ExistentialWitness existentialwitness.swift existential_unpassed.o \
        -emit-module-path ew_module/ExistentialWitness.swiftmodule \
        -Xlinker -install_name -Xlinker @rpath/libExistentialWitness$suffix.dylib -o libExistentialWitness$suffix.dylib
    $SWIFTC -parse-as-library -$flags -emit-library -module-name ExistentialWitnessOracle existentialwitness_oracle.swift \
        -I ew_module -L . -lExistentialWitness$suffix -Xlinker -rpath -Xlinker @loader_path \
        -o libExistentialWitnessOracle$suffix.dylib
done
rm -rf ew_module existential_unpassed.o

echo "==> types fetched by mangled name, unstripped and stripped (mangledtypes.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name MangledTypes mangledtypes.swift -o libMangledTypes.dylib
cp libMangledTypes.dylib libMangledTypes.stripped.dylib
strip -x libMangledTypes.stripped.dylib

echo "==> imported C enum and option set parameters (importedenum.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name ImportedEnum importedenum.swift -o libImportedEnum.dylib

echo "==> tables in __text that LC_FUNCTION_STARTS marks (datastarts.s, stripped)"
$CLANG -arch arm64 -dynamiclib datastarts.s -o libDataStarts.dylib
strip -x libDataStarts.dylib

echo "==> value witnesses IRGen fills with shared helpers (sharedwitness.swift, -O; strip -x copy)"
$SWIFTC -parse-as-library -O -emit-library -module-name SharedWitness sharedwitness.swift -o libSharedWitness.dylib
cp libSharedWitness.dylib libSharedWitness.stripped.dylib
strip -x libSharedWitness.stripped.dylib

echo "==> async class methods and an async witness: descriptors lead to async function pointers (asyncmethods.swift, -O; strip -x copy)"
$SWIFTC -parse-as-library -O -emit-library -module-name AsyncMethods asyncmethods.swift -o libAsyncMethods.opt.dylib
cp libAsyncMethods.opt.dylib libAsyncMethods.opt.stripped.dylib
strip -x libAsyncMethods.opt.stripped.dylib

echo "==> yielding accessors and witnesses: descriptors lead to coroutine function pointers (coroaccessors.swift, -O, CoroutineAccessors; strip -x copy)"
$SWIFTC -parse-as-library -O -emit-library -module-name CoroAccessors -enable-experimental-feature CoroutineAccessors \
    coroaccessors.swift -o libCoroAccessors.opt.dylib
cp libCoroAccessors.opt.dylib libCoroAccessors.opt.stripped.dylib
strip -x libCoroAccessors.opt.stripped.dylib

echo "==> calls into a body the linker folds under two signatures (foldedcalls.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name FoldedCalls foldedcalls.swift -o libFoldedCalls.dylib

echo "==> a call into a function whose address also carries linker marker symbols, as TinyCC emits (markersymbols.s)"
$CLANG -arch arm64 -dynamiclib markersymbols.s -o libMarkerSymbols.dylib

echo "==> a float's bit pattern compared as an integer (floatbits.swift, -O and -Onone): fmov x8, d0 reinterprets"
$SWIFTC -parse-as-library -O -emit-library -module-name FloatBits floatbits.swift -o libFloatBits.opt.dylib
$SWIFTC -parse-as-library -Onone -emit-library -module-name FloatBits floatbits.swift -o libFloatBits.dylib
echo "==> bits reinterpreted between register files, with and without fmov (floatreinterpret.swift, -O and -Onone)"
$SWIFTC -parse-as-library -O -emit-library -module-name FloatReinterpret floatreinterpret.swift -o libFloatReinterpret.opt.dylib
$SWIFTC -parse-as-library -Onone -emit-library -module-name FloatReinterpret floatreinterpret.swift -o libFloatReinterpret.dylib
echo "==> a Float's bits read at its own and at a wider width (floatbitswidth.s): fmov w0, s0 and fmov x0, d0"
$CLANG -arch arm64 -dynamiclib floatbitswidth.s -o libFloatBitsWidth.dylib

echo "==> async witness of another image's protocol: the resilient witness leads to a function pointer record (asyncwitness.swift, -O; strip -x copy)"
$SWIFTC -parse-as-library -O -emit-library -module-name AsyncWitness asyncwitness.swift -o libAsyncWitness.dylib
cp libAsyncWitness.dylib libAsyncWitness.stripped.dylib
strip -x libAsyncWitness.stripped.dylib

echo "==> private types' witnesses of another image's protocol, two under one name (privatewitness.swift, -O; strip -x copy)"
$SWIFTC -parse-as-library -O -emit-library -module-name PrivateWitness privatewitness.swift -o libPrivateWitness.dylib
cp libPrivateWitness.dylib libPrivateWitness.stripped.dylib
strip -x libPrivateWitness.stripped.dylib

echo "==> witnesses metadata reads but must not name: a generic type's, and bodies folded with a private type's (witnessnaming.swift, -O; strip -x copy)"
$SWIFTC -parse-as-library -O -emit-library -module-name WitnessNaming witnessnaming.swift -o libWitnessNaming.dylib
cp libWitnessNaming.dylib libWitnessNaming.stripped.dylib
strip -x libWitnessNaming.stripped.dylib

echo "==> a class parameter's fields in a free function (classparam.swift, classparamsmall.swift, -Onone, -O and -Osize)"
$SWIFTC -parse-as-library -Onone -emit-library -module-name ClassParam classparam.swift -o libClassParam.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name ClassParam classparam.swift -o libClassParam.opt.dylib
$SWIFTC -parse-as-library -Osize -emit-library -module-name ClassParam classparam.swift -o libClassParam.size.dylib
$SWIFTC -parse-as-library -Onone -emit-library -module-name ClassParamSmall classparamsmall.swift -o libClassParamSmall.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name ClassParamSmall classparamsmall.swift -o libClassParamSmall.opt.dylib
$SWIFTC -parse-as-library -Osize -emit-library -module-name ClassParamSmall classparamsmall.swift -o libClassParamSmall.size.dylib
echo "==> class parameters whose layout another module owns (classparamkit, classparamtwin, classparamclient, -O)"
$SWIFTC -parse-as-library -O -enable-library-evolution -emit-library -emit-module -module-name ClassParamKit classparamkit.swift -o libClassParamKit.dylib
$SWIFTC -parse-as-library -O -emit-library -emit-module -module-name ClassParamTwin classparamtwin.swift -o libClassParamTwin.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name ClassParamClient classparamclient.swift -I . -L . -lClassParamKit -lClassParamTwin -o libClassParamClient.dylib

echo "==> segments at different VM-to-file slides: zero fill ends __DATA, slid segments follow (slidsegments.swift, -O, executable; slidsegments_c.c)"
$CLANG -arch arm64 -c slidsegments_zerofill.s -o slidsegments_zerofill.o
$CLANG -arch arm64 -c slidsegments_tail.s -o slidsegments_tail.o
$CLANG -arch arm64 -O1 -dynamiclib slidsegments_c.c slidsegments_zerofill.o -o slidsegments_c \
    -Wl,-rename_section,__DATA,__data,__DATA_DIRTY,__data -Wl,-sectcreate,__FONT_DATA,__blob,slidsegments_zerofill.s
$SWIFTC -O -module-name SlidSegments slidsegments.swift slidsegments_zerofill.o slidsegments_tail.o -o slidsegments \
    -Xlinker -rename_section -Xlinker __DATA -Xlinker __data -Xlinker __DATA_DIRTY -Xlinker __data \
    -Xlinker -rename_section -Xlinker __DATA -Xlinker __objc_selrefs -Xlinker __DATA_DIRTY -Xlinker __objc_selrefs \
    -Xlinker -rename_section -Xlinker __DATA_CONST -Xlinker __got -Xlinker __DATA_DIRTY -Xlinker __got \
    -Xlinker -rename_section -Xlinker __TEXT -Xlinker __swift5_fieldmd -Xlinker __SWIFT_FIELDS -Xlinker __swift5_fieldmd \
    -Xlinker -rename_section -Xlinker __TEXT -Xlinker __constg_swiftt -Xlinker __SWIFT_FIELDS -Xlinker __constg_swiftt \
    -Xlinker -rename_section -Xlinker __TEXT -Xlinker __const -Xlinker __SWIFT_FIELDS -Xlinker __const
echo "==> the same two linked alike without the zero fill: one slide, the oracle for the renders above (slidsegments_flat, slidsegments_c_flat)"
$CLANG -arch arm64 -O1 -dynamiclib slidsegments_c.c -DSLIDSEGMENTS_FLAT -o slidsegments_c_flat \
    -Wl,-rename_section,__DATA,__data,__DATA_DIRTY,__data -Wl,-sectcreate,__FONT_DATA,__blob,slidsegments_zerofill.s
$SWIFTC -O -module-name SlidSegments slidsegments.swift -o slidsegments_flat \
    -Xlinker -rename_section -Xlinker __DATA -Xlinker __data -Xlinker __DATA_DIRTY -Xlinker __data \
    -Xlinker -rename_section -Xlinker __DATA -Xlinker __objc_selrefs -Xlinker __DATA_DIRTY -Xlinker __objc_selrefs \
    -Xlinker -rename_section -Xlinker __DATA_CONST -Xlinker __got -Xlinker __DATA_DIRTY -Xlinker __got \
    -Xlinker -rename_section -Xlinker __TEXT -Xlinker __swift5_fieldmd -Xlinker __SWIFT_FIELDS -Xlinker __swift5_fieldmd \
    -Xlinker -rename_section -Xlinker __TEXT -Xlinker __constg_swiftt -Xlinker __SWIFT_FIELDS -Xlinker __constg_swiftt \
    -Xlinker -rename_section -Xlinker __TEXT -Xlinker __const -Xlinker __SWIFT_FIELDS -Xlinker __const
echo "==> both stripped: names then come from metadata, through the pointers the slide moves (slidsegments_stripped, slidsegments_flat_stripped)"
cp slidsegments slidsegments_stripped
strip -x slidsegments_stripped 2>/dev/null || strip slidsegments_stripped
cp slidsegments_flat slidsegments_flat_stripped
strip -x slidsegments_flat_stripped 2>/dev/null || strip slidsegments_flat_stripped

echo "==> which register holds each parameter at entry (entryseedkit, entryseed, -Onone, -O and -Osize)"
$SWIFTC -parse-as-library -O -emit-library -emit-module -module-name EntrySeedKit entryseedkit.swift -o libEntrySeedKit.dylib
$SWIFTC -parse-as-library -Onone -emit-library -module-name EntrySeed entryseed.swift -I . -L . -lEntrySeedKit -o libEntrySeed.dylib
$SWIFTC -parse-as-library -O -emit-library -module-name EntrySeed entryseed.swift -I . -L . -lEntrySeedKit -o libEntrySeed.opt.dylib
$SWIFTC -parse-as-library -Osize -emit-library -module-name EntrySeed entryseed.swift -I . -L . -lEntrySeedKit -o libEntrySeed.size.dylib

echo "==> folds strip hides (strippedfold.swift, -O, and a strip -x copy): one surviving name over a body others share"
$SWIFTC -parse-as-library -O -emit-library -module-name StrippedFold strippedfold.swift -o libStrippedFold.dylib
cp libStrippedFold.dylib libStrippedFold.stripped.dylib
strip -x libStrippedFold.stripped.dylib 2>/dev/null || strip libStrippedFold.stripped.dylib

echo "==> input shapes: x86_64, universal, relocatable objects, no LC_FUNCTION_STARTS, no code (inputshape*, -O and -O1)"
# Not .dylib: the suites that decode every fixture read .dylib files, and these are refused.
$SWIFTC -O -emit-library -target x86_64-apple-macos13 -module-name InputShape inputshape.swift -o inputshape_x86_64.shape
$SWIFTC -O -emit-library -target arm64-apple-macos13 -module-name InputShape inputshape.swift -o libInputShape.arm64.dylib
lipo -create libInputShape.arm64.dylib inputshape_x86_64.shape -output inputshape_universal.shape
$SWIFTC -O -c -parse-as-library -module-name InputShape inputshape.swift -o inputshape_swift.o
$CLANG -arch arm64 -O1 -c inputshape_c.c -o inputshape_c.o
$CLANG -arch arm64 -O1 -dynamiclib inputshape_c.c -o libInputShapeNoStarts.dylib -Wl,-no_function_starts
cp libInputShapeNoStarts.dylib libInputShapeNoStarts.stripped.dylib
strip -x libInputShapeNoStarts.stripped.dylib
$CLANG -arch arm64 -dynamiclib inputshape_empty.c -o inputshape_empty.shape

echo "==> variants:"
ls -la sample.debug sample.release sample.stripped libSample.dylib libSample.stripped.dylib libReconstruction.dylib
file sample.release

echo "==> recursive entry call effects and real stack reloads (summary_recursive_effects.s)"
$CLANG -arch arm64 -mmacosx-version-min=15.0 -dynamiclib summary_recursive_effects.s -o libRecursiveSummaryEffects.dylib

echo "==> conditional external tail effects, both paths and frame aliases (conditional_tail_effects.s)"
$CLANG -arch arm64 -mmacosx-version-min=15.0 -dynamiclib conditional_tail_effects.s -o libConditionalTailEffects.dylib

echo "==> a dylib with data and no code: LC_FUNCTION_STARTS is only zero padding (nocode.c, -O1)"
xcrun clang -arch arm64 -O1 -dynamiclib nocode.c -o libNoCode.dylib

echo "==> dup of a general register into a vector register, returned as a Double (dup_bits.s)"
$CLANG -arch arm64 -mmacosx-version-min=15.0 -dynamiclib dup_bits.s -o libDupBits.dylib

echo "==> tail branches to bodies that never write x0: a lone ret, a store, an add (passthrough_tail.s)"
$CLANG -arch arm64 -mmacosx-version-min=15.0 -dynamiclib passthrough_tail.s -o libPassthroughTail.dylib

echo "==> a non-local label inside a function, listed as a function start (label_split.s)"
$CLANG -arch arm64 -mmacosx-version-min=15.0 -dynamiclib label_split.s -o libLabelSplit.dylib

echo "==> a scalar in a callee-saved vector register across a call, stored whole (vector_preserve.s)"
$CLANG -arch arm64 -mmacosx-version-min=15.0 -dynamiclib vector_preserve.s -o libVectorPreserve.dylib

echo "==> calls through a register with arguments still in their entry registers (indirect_args.c, -O2)"
$CLANG -arch arm64 -O2 -dynamiclib indirect_args.c -o libIndirectArgs.dylib

echo "==> a struct's self after a method's formals and as a getter's words (valueself.swift, -O)"
$SWIFTC -parse-as-library -O -emit-library -module-name ValueSelf valueself.swift -o libValueSelf.dylib

echo "==> functions with no signature whose callers prove (or do not prove) their result (caller_proven.s)"
$CLANG -arch arm64 -mmacosx-version-min=15.0 -dynamiclib caller_proven.s -o libCallerProven.dylib

echo "==> value-witness calls through metadata a stripped generic function receives as an argument (argument_witness.swift, -O; strip -x)"
$SWIFTC -parse-as-library -O -emit-library -module-name ArgumentWitness argument_witness.swift -o libArgumentWitness.dylib
cp libArgumentWitness.dylib libArgumentWitness.stripped.dylib
strip -x libArgumentWitness.stripped.dylib

echo "==> a void value witness followed by a call that reads x0 (void_witness.s; links libswiftCore for the metadata bind)"
$CLANG -arch arm64 -mmacosx-version-min=15.0 -dynamiclib void_witness.s -L"$(xcrun --show-sdk-path)/usr/lib/swift" -lswiftCore -o libVoidWitness.dylib

echo "==> value-witness loads whose call does or does not pass the metadata back (value_witness_args.s)"
$CLANG -arch arm64 -mmacosx-version-min=15.0 -dynamiclib value_witness_args.s -o libValueWitnessArgs.dylib

echo "==> value witnesses of an associated type's metadata in an unspecialized generic (associated_witness.swift, -O; strip -x)"
$SWIFTC -parse-as-library -O -emit-library -module-name AssociatedWitness associated_witness.swift -o libAssociatedWitness.dylib
cp libAssociatedWitness.dylib libAssociatedWitness.stripped.dylib
strip -x libAssociatedWitness.stripped.dylib

echo "==> protocol witness calls through a table swift_conformsToProtocol returned (protocol_witness.swift, -O; stripped; library evolution for method descriptors)"
$SWIFTC -parse-as-library -O -emit-library -module-name ProtocolWitness protocol_witness.swift -o libProtocolWitness.dylib
cp libProtocolWitness.dylib libProtocolWitness.stripped.dylib
strip -x libProtocolWitness.stripped.dylib
$SWIFTC -parse-as-library -O -enable-library-evolution -emit-library -module-name ProtocolWitness protocol_witness.swift -o libProtocolWitness.resilient.dylib

echo "==> protocol witness calls through a hand-built descriptor, with and without (T, table) passed last (protocol_witness_args.s)"
$CLANG -arch arm64 -mmacosx-version-min=15.0 -dynamiclib protocol_witness_args.s -L"$(xcrun --show-sdk-path)/usr/lib/swift" -lswiftCore -o libProtocolWitnessArgs.dylib

echo "==> possible frame reach after lost frame-pointer preservation (frame_may.s)"
$CLANG -arch arm64 -dynamiclib frame_may.s -o libFrameMay.dylib

echo "==> callee stack reuse invalidates facts below call-time sp (stack_lifetime.s)"
$CLANG -arch arm64 -mmacosx-version-min=15.0 -dynamiclib stack_lifetime.s -o libStackLifetime.dylib

echo "==> ARC identity requires its real provider (arc_identity_origin, -Onone/-O/-Osize)"
python3 build-arc-origin.py

echo "==> retain the original call result once with real objects (result_identity, -Onone/-O/-Osize)"
python3 build-result-identity.py
python3 build-result-identity.py --legacy-bindings
python3 build-result-identity.py --indirect-calls
python3 build-result-identity.py --legacy-bindings --indirect-calls

echo "==> an entry-register spill inside an escaped local is not an object boundary (frame_preserve_alias.s)"
$CLANG -arch arm64 -mmacosx-version-min=15.0 -dynamiclib frame_preserve_alias.s -o libFramePreserveAlias.dylib

echo "==> value self and direct/forwarded context self use different registers (self_register_role.swift + self_register_role.s, -O)"
SELF_REGISTER_ROLE_TMP=$(mktemp -d)
$CLANG -arch arm64 -mmacosx-version-min=15.0 -c self_register_role.s -o "$SELF_REGISTER_ROLE_TMP/entry.o"
$SWIFTC -O -parse-as-library -emit-library -module-name SelfRole self_register_role.swift "$SELF_REGISTER_ROLE_TMP/entry.o" -o libSelfRegisterRole.dylib
rm -rf "$SELF_REGISTER_ROLE_TMP"

echo "==> signature-only receiver proofs without Swift mangling or metadata (entry_role_consumers.s)"
$CLANG -arch arm64 -mmacosx-version-min=15.0 -dynamiclib entry_role_consumers.s -o libEntryRoleConsumers.dylib

echo "==> preserve whole indirect-result producer order across effects (indirect_result_order.swift + .s, -Onone, -O and -Osize)"
INDIRECT_RESULT_ORDER_TMP=$(mktemp -d)
$CLANG -arch arm64 -mmacosx-version-min=15.0 -c indirect_result_order.s -o "$INDIRECT_RESULT_ORDER_TMP/entry.o"
$SWIFTC -Onone -parse-as-library -emit-library -module-name IndirectOrder indirect_result_order.swift "$INDIRECT_RESULT_ORDER_TMP/entry.o" -o libIndirectResultOrder.dylib
$SWIFTC -O -parse-as-library -emit-library -module-name IndirectOrder indirect_result_order.swift "$INDIRECT_RESULT_ORDER_TMP/entry.o" -o libIndirectResultOrder.opt.dylib
$SWIFTC -Osize -parse-as-library -emit-library -module-name IndirectOrder indirect_result_order.swift "$INDIRECT_RESULT_ORDER_TMP/entry.o" -o libIndirectResultOrder.size.dylib
rm -rf "$INDIRECT_RESULT_ORDER_TMP"


echo "==> context receivers preserve one producer and its order (context_result_use.swift + .s, -Onone, -O and -Osize)"
CONTEXT_RESULT_USE_TMP=$(mktemp -d)
$CLANG -arch arm64 -mmacosx-version-min=15.0 -c context_result_use.s -o "$CONTEXT_RESULT_USE_TMP/entry.o"
$SWIFTC -Onone -parse-as-library -emit-library -module-name SelfUse context_result_use.swift "$CONTEXT_RESULT_USE_TMP/entry.o" -o libContextResultUse.dylib
$SWIFTC -O -parse-as-library -emit-library -module-name SelfUse context_result_use.swift "$CONTEXT_RESULT_USE_TMP/entry.o" -o libContextResultUse.opt.dylib
$SWIFTC -Osize -parse-as-library -emit-library -module-name SelfUse context_result_use.swift "$CONTEXT_RESULT_USE_TMP/entry.o" -o libContextResultUse.size.dylib
rm -rf "$CONTEXT_RESULT_USE_TMP"


echo "==> complete body register outputs and caller-owned result aliases (callee_body_transfer.swift + .s, -Onone, -O and -Osize)"
CALLEE_BODY_TRANSFER_TMP=$(mktemp -d)
$CLANG -arch arm64 -mmacosx-version-min=15.0 -c callee_body_transfer.s -o "$CALLEE_BODY_TRANSFER_TMP/entry.o"
$SWIFTC -Onone -parse-as-library -emit-library -module-name PlanAlias callee_body_transfer.swift "$CALLEE_BODY_TRANSFER_TMP/entry.o" -o libCalleeBodyTransfer.dylib
$SWIFTC -O -parse-as-library -emit-library -module-name PlanAlias callee_body_transfer.swift "$CALLEE_BODY_TRANSFER_TMP/entry.o" -o libCalleeBodyTransfer.opt.dylib
$SWIFTC -Osize -parse-as-library -emit-library -module-name PlanAlias callee_body_transfer.swift "$CALLEE_BODY_TRANSFER_TMP/entry.o" -o libCalleeBodyTransfer.size.dylib
rm -rf "$CALLEE_BODY_TRANSFER_TMP"


echo "==> caller-owned value-self can alias positive frame coordinates (caller_frame_alias.swift + .s, -Onone, -O and -Osize)"
CALLER_FRAME_ALIAS_TMP=$(mktemp -d)
$CLANG -arch arm64 -mmacosx-version-min=15.0 -c caller_frame_alias.s -o "$CALLER_FRAME_ALIAS_TMP/entry.o"
$SWIFTC -Onone -parse-as-library -emit-library -module-name FrameSelf caller_frame_alias.swift "$CALLER_FRAME_ALIAS_TMP/entry.o" -o libCallerFrameAlias.dylib
$SWIFTC -O -parse-as-library -emit-library -module-name FrameSelf caller_frame_alias.swift "$CALLER_FRAME_ALIAS_TMP/entry.o" -o libCallerFrameAlias.opt.dylib
$SWIFTC -Osize -parse-as-library -emit-library -module-name FrameSelf caller_frame_alias.swift "$CALLER_FRAME_ALIAS_TMP/entry.o" -o libCallerFrameAlias.size.dylib
rm -rf "$CALLER_FRAME_ALIAS_TMP"

echo "==> Imported receiver ABI and unchanged ordinary self (imported_receiver.swift/.s, -Onone/-O/-Osize)"
IMPORTED_RECEIVER_TMP=$(mktemp -d)
$CLANG -arch arm64 -mmacosx-version-min=15.0 -c imported_receiver.s -o "$IMPORTED_RECEIVER_TMP/entry.o"
$SWIFTC -Onone -parse-as-library -emit-library -module-name ImportedSelf imported_receiver.swift "$IMPORTED_RECEIVER_TMP/entry.o" -o libImportedReceiver.dylib
$SWIFTC -O -parse-as-library -emit-library -module-name ImportedSelf imported_receiver.swift "$IMPORTED_RECEIVER_TMP/entry.o" -o libImportedReceiver.opt.dylib
$SWIFTC -Osize -parse-as-library -emit-library -module-name ImportedSelf imported_receiver.swift "$IMPORTED_RECEIVER_TMP/entry.o" -o libImportedReceiver.size.dylib
rm -rf "$IMPORTED_RECEIVER_TMP"
