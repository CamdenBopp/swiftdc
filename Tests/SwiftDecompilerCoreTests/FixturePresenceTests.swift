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
    /// Every artifact `Fixtures/Sample/build.sh` produces that a test reads:
    /// each complete `"Fixtures/Sample/…"` literal in this target's sources,
    /// found at run time, plus the paths a test builds by interpolation or
    /// through a helper. Deriving the list means a new fixture's test no
    /// longer edits this file too; a hand-kept list here was the third most
    /// conflicted file (115 commits from 2026-10-01 to 2026-11-02).
    /// Paths are repo-relative, matching how the fixture-gated tests resolve them
    /// (`swift test` runs with the package root as the working directory).
    static let requiredFixtures: [String] = Array(Set(literalFixturePaths + indirectFixtures)).sorted()

    /// Paths no literal spells out whole: `"Fixtures/Sample/lib\(module).dylib"`,
    /// `libConditions.\(level)`, `types("libLocalTypes.dylib")`. Add a fixture
    /// here only when its test names it this way.
    static let indirectFixtures = [
        "Fixtures/Sample/libAccessorShapes.O0.dylib",
        "Fixtures/Sample/libAccessorShapes.O1.dylib",
        "Fixtures/Sample/libAccessorShapes.Os.dylib",
        "Fixtures/Sample/libConditions.opt.dylib",
        "Fixtures/Sample/libConditions.osize.dylib",
        "Fixtures/Sample/libInterfaceFacts.dylib",
        "Fixtures/Sample/libInterfaceFacts.Onone.dylib",
        "Fixtures/Sample/libInterfaceFacts.noreflection.dylib",
        "Fixtures/Sample/libLocalTypes.dylib",
        "Fixtures/Sample/libResearchSize.dylib",
        "Fixtures/Sample/libScalarTailReturns.Onone.dylib",
        "Fixtures/Sample/libScalarTailReturns.Osize.dylib",
        "Fixtures/Sample/libVariadicFloat.O0.dylib",
        "Fixtures/Sample/libVariadicFloat.O2.dylib",
    ]

    /// The complete `"Fixtures/Sample/…"` string literals in the test sources
    /// beside this file. A literal that continues into an interpolation
    /// (`"Fixtures/Sample/lib\(module)…"`) does not match: the closing quote
    /// must follow the path, and the path is file-name characters only.
    static let literalFixturePaths: [String] = {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        var paths: Set<String> = []
        for file in files where file.pathExtension == "swift" {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for match in source.matches(of: #/"(Fixtures/Sample/[A-Za-z0-9_.+\-/]+)"/#) {
                paths.insert(String(match.1))
            }
        }
        return paths.sorted()
    }()

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

    /// The derived list must not come back empty or short: an empty scan
    /// (sources moved, `#filePath` remapped) would make the presence check
    /// pass while checking nothing.
    @Test func theFixtureListIsReadFromTheTestSources() throws {
        #expect(Self.literalFixturePaths.count >= 150)
        #expect(Self.literalFixturePaths.contains("Fixtures/Sample/sample.debug"))
        #expect(Self.literalFixturePaths.contains("Fixtures/Sample/libIntConvert.dylib"))
        #expect(!Self.literalFixturePaths.contains { $0.hasSuffix(".") || $0.hasSuffix("/lib") })
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
