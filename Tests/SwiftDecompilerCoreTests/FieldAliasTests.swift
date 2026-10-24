import Testing
import Foundation
@testable import SwiftDecompilerCore

/// A register loaded from or stored to a field of self was known to equal
/// that field until the next store to a field, but a call may write the
/// field too: `field_aliases.swift` (-O) `let old = a; bumpA(); b = old`
/// rendered `bumpA(); self.b = self.a`, the incremented a, and
/// `let old = a; bumpA(); return old` rendered `return self.a`, the same
/// text as `bumpA(); return a`, which is right only there.
@Test func aFieldAliasDoesNotSurviveACallThatMayWriteItIfPresent() async throws {
    let path = "Fixtures/Sample/libFieldAliases.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    func pseudo(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("FieldAliases.Box.\(name)(") }).renderPseudo()
    }
    let stale = try pseudo("stale")
    #expect(stale.contains("self.b = ") && !stale.contains("self.b = self.a"), "\(stale)")
    // A stored argument stays the argument, which no call can change.
    let storeTwice = try pseudo("storeTwice")
    #expect(storeTwice.contains("self.b = arg0\n"), "\(storeTwice)")
    let staleReturn = try pseudo("staleReturn")
    #expect(!staleReturn.contains("return self.a"), "\(staleReturn)")
    // A load after the call is the field's current value.
    let fresh = try pseudo("fresh")
    #expect(fresh.contains("return self.a\n"), "\(fresh)")
}

/// Only a retain or an access marker leaves every field alone. A release
/// can run a deinit, which may write a field of anything it reaches, and an
/// in-image function that merely shares a runtime name proves nothing.
@Test func onlyRetainsAndAccessMarkersWriteNoFields() {
    for callee in ["swift_retain", "_swift_bridgeObjectRetain", "objc_retain", "objc_retain_x19", "swift_beginAccess",
                   "swift_endAccess"] {
        #expect(ValueTracer.CallFacts(callee: callee).writesNoFields, "\(callee)")
    }
    for callee in ["swift_release", "objc_release", "swift_bridgeObjectRelease", "Box.bumpA()", "memcpy"] {
        #expect(!ValueTracer.CallFacts(callee: callee).writesNoFields, "\(callee)")
    }
    #expect(!ValueTracer.CallFacts(callee: "swift_retain", knownArityApplies: false).writesNoFields)
}

/// -Osize outlines `swift_beginAccess` into `OUTLINED_FUNCTION_3`
/// (`mov x2, #0; mov x3, #0; b swift_beginAccess`), which writes no field
/// but is no runtime call by name: `Holder.total` loads `first` before it
/// and `second` after it, and `return (self.first + self.second)` read
/// `return ?` once calls forgot field names.
@Test func anOutlinedAccessMarkerKeepsFieldNamesIfPresent() async throws {
    let path = "Fixtures/Sample/libReconstruction.osize.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let total = try #require(functions.first { $0.displayName.hasPrefix("Reconstruction.BoxA.Holder.total.getter") })
        .renderPseudo()
    #expect(total.contains("return (self.first + self.second)"), "\(total)")
}

/// A body writes no field when it stores only through sp and calls only
/// runtime functions that write none, or bodies that write none.
@Test func onlyABodyThatStoresNothingAndCallsNothingThatWritesKeepsFields() throws {
    let engine = try #require(CapstoneEngine())
    let stub: UInt64 = 0x2000
    let bodies: [UInt64: [UInt32]] = [
        0x1000: [0xD280_0002, 0xD280_0003, 0x1400_03FE],  // mov x2, #0; mov x3, #0; b stub
        0x3000: [0xF900_0280, 0xD65F_03C0],               // str x0, [x20]; ret
        0x4000: [0x97FF_F400, 0xD65F_03C0],               // bl 0x1000; ret
        0x5000: [0xD63F_0100, 0xD65F_03C0],               // blr x8; ret
        0x6000: [0x9400_0400, 0xD65F_03C0],               // bl 0x7000; ret
        0x7000: [0x97FF_FC00, 0xD65F_03C0],               // bl 0x6000; ret
    ]
    var summaries: [UInt64: CalleeRegisterSummary] = [:]
    for (start, words) in bodies {
        let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: start)
        try #require(decoded.count == words.count)
        let function = DisassembledFunction(symbol: "_f\(start)", demangledName: nil, startAddress: start,
            instructions: decoded.map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                            branchTarget: $0.branchTarget, detail: $0.detail)
            }, source: .symbol)
        summaries[start] = try #require(CalleeRegisterSummary.of(function, isFunction: { bodies[$0] != nil }))
    }
    CalleeRegisterSummary.closeOverFieldWrites(&summaries) { $0 == stub ? "swift_beginAccess" : nil }
    #expect(summaries[0x1000]?.writesNoFields == true)
    #expect(summaries[0x4000]?.writesNoFields == true)
    // A store through another register, an indirect call and a cycle prove nothing.
    for start: UInt64 in [0x3000, 0x5000, 0x6000, 0x7000] {
        #expect(summaries[start]?.writesNoFields == false, "\(String(start, radix: 16))")
    }
}
