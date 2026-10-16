import Testing
import Foundation

/// A tripwire against the suite's central fragility: the fixture binaries are
/// git-ignored and rebuilt by `Fixtures/Sample/build.sh`, and ~80 of the tests
/// guard on `fileExists` and silently `return` when their fixture is absent.
/// That is deliberate — it keeps `swift test` green on a clean checkout — but it
/// also means a run with no fixtures reports all-green while asserting nothing.
///
/// So: on an *authoritative* run — CI, or one that opts in with
/// `SWIFTDC_REQUIRE_FIXTURES` — a missing fixture is a hard failure naming what
/// to build, instead of a quiet skip. A plain local `swift test` (neither
/// variable set) still skips cleanly, so the clean-checkout convenience holds.
///
/// This is why the ~80 `…IfPresent` skips are safe under CI: if any fixture is
/// missing here, those tests are not merely skipping, and this test says so.
struct FixturePresenceTests {
    /// Every artifact `Fixtures/Sample/build.sh` produces that a test reads.
    /// Paths are repo-relative, matching how the fixture-gated tests resolve them
    /// (`swift test` runs with the package root as the working directory).
    static let requiredFixtures = [
        "Fixtures/Sample/sample.debug",
        "Fixtures/Sample/sample.release",
        "Fixtures/Sample/sample.stripped",
        "Fixtures/Sample/libSample.dylib",
        "Fixtures/Sample/libSample.stripped.dylib",
        "Fixtures/Sample/libReconstruction.dylib",
        "Fixtures/Sample/libReconstruction.opt.dylib",
        "Fixtures/Sample/libReconstruction.opt.stripped.dylib",
        "Fixtures/Sample/libReconstruction.resilient.dylib",
        "Fixtures/Sample/libSwiftErrorProbe.dylib",
        "Fixtures/Sample/libSwiftErrorProbe.stripped.dylib",
        "Fixtures/Sample/libIndirect.dylib",
        "Fixtures/Sample/libIndirect.opt.dylib",
        "Fixtures/Sample/libConversions.dylib",
        "Fixtures/Sample/libConversions.opt.dylib",
        "Fixtures/Sample/libRuntimeIvars.dylib",
        "Fixtures/Sample/libCow.dylib",
        "Fixtures/Sample/libSameName.dylib",
        "Fixtures/Sample/libAsyncInout.dylib",
        "Fixtures/Sample/libCompares.dylib",
        "Fixtures/Sample/libAsyncFns.dylib",
        "Fixtures/Sample/libAsyncFns.opt.dylib",
        "Fixtures/Sample/libAsyncFns.opt.stripped.dylib",
        "Fixtures/Sample/libIndirectTail.dylib",
        "Fixtures/Sample/libIndirectAwait.opt.dylib",
        "Fixtures/Sample/libAuditSemantics.opt.dylib",
        "Fixtures/Sample/libAuditVoid.dylib",
        "Fixtures/Sample/libConditionalFlags.dylib",
        "Fixtures/Sample/libLargeStrings.opt.dylib",
        "Fixtures/Sample/libRetainRegister.sim.dylib",
        "Fixtures/Sample/libRethrowCleanup.opt.dylib",
        "Fixtures/Sample/libWidthFlagProbes.dylib",
        "Fixtures/Sample/libTypedThrowsAwait.opt.dylib",
        "Fixtures/Sample/libStaleSlot.opt.dylib",
        "Fixtures/Sample/libImportedClassProbe.opt.dylib",
        "Fixtures/Sample/libScalarTailReturns.Onone.dylib",
        "Fixtures/Sample/libScalarTailReturns.O.dylib",
        "Fixtures/Sample/libScalarTailReturns.Osize.dylib",
        "Fixtures/Sample/libReturnPaths.dylib",
        "Fixtures/Sample/libExtract.dylib",
        "Fixtures/Sample/libByteReversal.dylib",
        "Fixtures/Sample/libUnknownReturn.dylib",
        "Fixtures/Sample/libABISavedSlots.dylib",
        "Fixtures/Sample/libABIEscapedSaves.dylib",
        "Fixtures/Sample/libABIFrameOwnership.dylib",
        "Fixtures/Sample/libAsyncAliasEscape.dylib",
        "Fixtures/Sample/libAsyncSlotChronology.dylib",
        "Fixtures/Sample/libAsyncMemoryEffects.dylib",
        "Fixtures/Sample/libErrorExitControls.dylib",
        "Fixtures/Sample/libAsyncCallEffects.dylib",
        "Fixtures/Sample/libFrameEscapeControls.dylib",
        "Fixtures/Sample/libMarkerOscillation.opt.dylib",
        "Fixtures/Sample/libPartialWrites.dylib",
        "Fixtures/Sample/libRenderOrder.dylib",
        "Fixtures/Sample/libBoundSelf.opt.dylib",
        "Fixtures/Sample/libStackCallEffects.dylib",
        "Fixtures/Sample/libStackCallEffects.opt.dylib",
        "Fixtures/Sample/libStackCallEffects.osize.dylib",
        "Fixtures/Sample/libJumpTableBounds.dylib",
        "Fixtures/Sample/libLoopSwitch.dylib",
        "Fixtures/Sample/libSelectFlow.dylib",
        "Fixtures/Sample/libResearchOnone.dylib",
        "Fixtures/Sample/libResearchOptimized.dylib",
        "Fixtures/Sample/libResearchSize.dylib",
    ]

    /// True on a run that must actually exercise the fixtures. `CI` is set by
    /// GitHub Actions and virtually every other CI system, so any CI enforces
    /// this with no extra wiring; `SWIFTDC_REQUIRE_FIXTURES` opts a local run in.
    static var enforcingFixturePresence: Bool {
        let env = ProcessInfo.processInfo.environment
        return isTruthy(env["CI"]) || isTruthy(env["SWIFTDC_REQUIRE_FIXTURES"])
    }

    private static func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.lowercased() {
        case "", "0", "false", "no", "off": return false
        default: return true
        }
    }

    @Test func fixturesArePresentWhenRequired() throws {
        guard Self.enforcingFixturePresence else { return }

        let missing = Self.requiredFixtures.filter {
            !FileManager.default.fileExists(atPath: $0)
        }
        #expect(
            missing.isEmpty,
            """
            Fixture binaries are missing, so the ~80 fixture-gated tests would \
            silently skip on this authoritative run. Build them first:

                Fixtures/Sample/build.sh

            Missing:
            \(missing.map { "  - \($0)" }.joined(separator: "\n"))

            (Unset CI and SWIFTDC_REQUIRE_FIXTURES to allow a fixture-free local run.)
            """
        )
    }
}
