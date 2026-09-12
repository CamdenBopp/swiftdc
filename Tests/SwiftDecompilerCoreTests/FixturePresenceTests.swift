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
