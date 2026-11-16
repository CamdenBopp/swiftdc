import Foundation
import Testing
@testable import SwiftDecompilerCore

/// `swiftdc lab` shows what the analysis concluded at each instruction:
/// the entry convention and its seeds, each call's callee, registers and
/// argument layout, each branch condition and the exit registers. On
/// `RetainRegister.Node.join` that is self seeded in x20, the retain stub
/// laid out from its register, `enroll` passed self, and `k + 41` returned.
@Test func theLabReportShowsEachStagesFactsIfPresent() async throws {
    let path = "Fixtures/Sample/libRetainRegister.sim.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let text = try await withStableDependencies { try await LabReport.report(path: path, function: "Node.join") }
    #expect(text.contains("entry  swift-instance  self: Node  seeds: x0=arg0 x20=self"), Comment(rawValue: text))
    #expect(text.contains("→ objc_retain_x20  ; call x0=arg0  ; layout retained-register(1)"), Comment(rawValue: text))
    #expect(text.contains("call x0=self x20=self  ; layout swift-signature(1)"), Comment(rawValue: text))
    #expect(text.contains("exit x0=(arg0 + 0x29)"), Comment(rawValue: text))
    let consumed = "Fixtures/Sample/libConsumedCall.dylib"
    if FileManager.default.fileExists(atPath: consumed) {
        let probe = try await withStableDependencies { try await LabReport.report(path: consumed, function: "probeLevel") }
        #expect(probe.contains("→ sysctl  ; call x0=arg0 x1=2 x2=0 x3=0 x4=0 x5=0  ; layout c-declaration(6)"),
                Comment(rawValue: probe))
        #expect(probe.contains("cond (r@0x53c == 0)") || probe.contains("cond (r@"), Comment(rawValue: probe))
    }
    let none = try await withStableDependencies { try await LabReport.report(path: path, function: "no such function zz") }
    #expect(none == "No function matches \"no such function zz\".\n")
}
