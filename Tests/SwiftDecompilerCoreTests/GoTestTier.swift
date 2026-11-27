import Foundation
import Testing

/// Go is not a target of this decompiler. The tests that analyse the Go
/// fixtures stay as a guard on what was built for them, and they are the
/// longest in the suite (one takes 28 minutes alone), so they run only
/// when asked for: `SWIFTDC_GO_TESTS=1`, or `Tools/test.sh go`. Without
/// it each reports as skipped, with this reason, and never as passed.
let goTestsRequested = ProcessInfo.processInfo.environment["SWIFTDC_GO_TESTS"] == "1"

extension Trait where Self == ConditionTrait {
    static var goTier: Self {
        .enabled(if: goTestsRequested, "Go tests run with SWIFTDC_GO_TESTS=1 (Tools/test.sh go)")
    }
}
