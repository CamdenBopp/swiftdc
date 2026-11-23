import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The sprint fixtures say in comments what their code does, and several
/// are hand-written assembly. `sprint-native-oracle` (sprintnative.c) loads
/// each fixture image and runs it: whether a call returned, threw, trapped
/// or hung, and with what value. These tests hold swiftdc's render of each
/// function to that observation, so a claim is checked against what the
/// machine did and not against a reading of the source.
private struct Observation {
    let outcome: String
    let fields: [String: Int64]
    var result: Int64? { fields["result"] }
}

private let fixtures = "Fixtures/Sample"

/// Every observation by `<image> <case>`, or nil when the oracle is not
/// built. A run that does not end in its PASS line is a failure.
private func observations() throws -> [String: Observation]? {
    let oracle = "\(fixtures)/sprint-native-oracle"
    guard FileManager.default.fileExists(atPath: oracle) else { return nil }
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: oracle)
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    try #require(process.terminationStatus == 0, Comment(rawValue: output))
    var result: [String: Observation] = [:]
    for line in output.split(separator: "\n") where line.hasPrefix("OBS ") {
        let parts = line.split(separator: " ").map(String.init)
        try #require(parts.count >= 4, Comment(rawValue: String(line)))
        var fields: [String: Int64] = [:]
        for pair in parts.dropFirst(4) {
            let sides = pair.split(separator: "=")
            try #require(sides.count == 2, Comment(rawValue: String(line)))
            fields[String(sides[0])] = try #require(Int64(sides[1]), Comment(rawValue: String(line)))
        }
        result["\(parts[1]) \(parts[2])"] = Observation(outcome: parts[3], fields: fields)
    }
    try #require(output.split(separator: "\n").last == "PASS sprint native: \(result.count) observations",
                 Comment(rawValue: output))
    return result
}

private func functions(_ image: String, filter: String? = nil) async throws -> [DisassembledFunction] {
    try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: "\(fixtures)/\(image)", functionFilter: filter)
    }
}

/// The statements of a function's body, both views, trimmed.
private func statements(_ function: DisassembledFunction) -> [[String]] {
    [function.renderStructured(), function.renderPseudo()].map { text in
        text.components(separatedBy: "\n").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private func throwsInBody(_ lines: [String]) -> Bool { lines.contains { $0.hasPrefix("throw") } }
private let unresolved = DisassembledFunction.unresolvedSwiftExitStatement

/// The oracle runs, and saw what the fixture comments say.
@Test func theSprintFixturesBehaveNativelyAsTheyStateIfPresent() throws {
    guard let seen = try observations() else { return }
    func outcome(_ key: String) -> String? { seen[key]?.outcome }
    func result(_ key: String) -> Int64? { seen[key]?.result }
    // errorlookalike.s: every body returns its constant, with no error.
    #expect(result("ErrorLookalike viaAllocLog") == 5 && outcome("ErrorLookalike viaAllocLog") == "returned")
    #expect(result("ErrorLookalike viaLocalAlloc") == 7 && outcome("ErrorLookalike viaLocalAlloc") == "returned")
    #expect(result("ErrorLookalike viaWillThrowLog") == 6 && outcome("ErrorLookalike viaWillThrowLog") == "returned")
    // hookpath.s: without the hook, the argument decides.
    for function in ["either", "merged"] {
        #expect(outcome("HookPath \(function)-hook-nonzero") == "threw")
        #expect(outcome("HookPath \(function)-nohook-nonzero") == "threw")
        #expect(outcome("HookPath \(function)-nohook-zero") == "returned" && result("HookPath \(function)-nohook-zero") == 7)
    }
    #expect(outcome("HookPath always-nonzero") == "threw")
    // traptail.swift: the same with and without symbols.
    for image in ["TrapTail", "TrapTail.stripped"] {
        #expect(result("\(image) wrapNonZero-5") == 5 && outcome("\(image) wrapNonZero-0") == "trapped")
        #expect(result("\(image) wrapAboveThree-5-9") == 5 && outcome("\(image) wrapAboveThree-5-2") == "trapped")
        #expect(result("\(image) wrapUnlessNine-5") == 5 && outcome("\(image) wrapUnlessNine-9") == "hung")
        #expect(result("\(image) wrapSame-5") == 5)
    }
    // accesstwin.swift: n was 5, the twin wrote 23.
    #expect(result("AccessTwin acrossEnd") == 18 && seen["AccessTwin acrossEnd"]?.fields["n"] == 23)
    // deferthrow.swift: the deferred store happens on both exits.
    #expect(outcome("DeferThrow storeThenExit-3") == "threw" && seen["DeferThrow storeThenExit-3"]?.fields["entries"] == 99)
    #expect(outcome("DeferThrow storeThenExit-4") == "returned" && seen["DeferThrow storeThenExit-4"]?.fields["entries"] == 99)
    #expect(result("DeferThrow storeThenExit-4-last") == 4)
    #expect(outcome("DeferThrow plainExit-3") == "threw" && outcome("DeferThrow plainExit-4") == "returned")
    // lateimp.m: sent as a message, both methods return their first keyword.
    #expect(result("LateIMP late-5-9") == 5 && result("LateIMP listed-5-9") == 5)
    // selectorstubshape.s: the "send" adds 7 to its argument.
    #expect(result("SelectorStubShape calls_branching_stub-5") == 12)
}

/// A function the oracle saw return is not rendered as throwing, and one
/// whose outcome depends on its input is rendered as neither.
@Test func rendersOfThrowingExitsAgreeWithNativeOutcomesIfPresent() async throws {
    guard let seen = try observations() else { return }
    let lookalike = try await functions("libErrorLookalike.dylib")
    for name in ["viaAllocLog", "viaLocalAlloc", "viaWillThrowLog"] {
        try #require(seen["ErrorLookalike \(name)"]?.outcome == "returned")
        let function = try #require(lookalike.first { $0.displayName.hasPrefix("Lookalike.\(name)(") })
        for lines in statements(function) { #expect(!throwsInBody(lines), "\(name): \(lines)") }
    }
    let hook = try await functions("libHookPath.dylib")
    for name in ["either", "merged"] {
        // Same path, two inputs, two outcomes: no one exit statement is true.
        try #require(seen["HookPath \(name)-nohook-zero"]?.outcome == "returned")
        try #require(seen["HookPath \(name)-nohook-nonzero"]?.outcome == "threw")
        try #require(seen["HookPath \(name)-hook-nonzero"]?.outcome == "threw")
        let function = try #require(hook.first { $0.displayName.hasPrefix("HookPath.\(name)(") })
        let lines = statements(function)[0]
        #expect(lines.filter { $0 == unresolved }.count == 1, "\(name): \(lines)")
        // The path through the hook always threw, and says so, once.
        let call = try #require(lines.firstIndex(of: "swift_willThrow(arg1)"), "\(lines)")
        #expect(lines[call + 1].hasPrefix("throw"), "\(name): \(lines)")
        #expect(lines.filter { $0.hasPrefix("throw") }.count == 1, "\(name): \(lines)")
    }
    try #require(seen["HookPath always-nonzero"]?.outcome == "threw")
    let always = try #require(hook.first { $0.displayName.hasPrefix("HookPath.always(") })
    for lines in statements(always) { #expect(lines.contains("throw arg1") && !lines.contains(unresolved), "\(lines)") }

    let deferred = try await functions("libDeferThrow.dylib")
    // It threw with the store done: the store is not printed after a throw.
    try #require(seen["DeferThrow storeThenExit-3"]?.fields["entries"] == 99)
    let store = try #require(deferred.first { $0.displayName.hasPrefix("DeferThrow.storeThenExit(") })
    for lines in statements(store) {
        let at = try #require(lines.firstIndex(of: "arg0.entries = 99"), "\(lines)")
        #expect(!lines[..<at].contains { $0.hasPrefix("throw") }, "\(lines)")
    }
}

/// A wrapper the oracle saw trap or hang is not rendered as a plain return
/// of its argument; one that returned its argument for every input is.
@Test func rendersOfTailsAgreeWithNativeOutcomesIfPresent() async throws {
    guard let seen = try observations() else { return }
    let stripped = try await functions("libTrapTail.stripped.dylib")
    func wrapper(_ name: String) throws -> DisassembledFunction {
        try #require(stripped.first { $0.displayName.hasPrefix("TrapTail.\(name)(") })
    }
    for (name, bad) in [("wrapNonZero", "wrapNonZero-0"), ("wrapAboveThree", "wrapAboveThree-5-2"),
                        ("wrapUnlessNine", "wrapUnlessNine-9")] {
        try #require(["trapped", "hung"].contains(seen["TrapTail.stripped \(bad)"]?.outcome ?? ""))
        for lines in statements(try wrapper(name)) { #expect(!lines.contains("return arg0"), "\(name): \(lines)") }
    }
    try #require(seen["TrapTail.stripped wrapSame-5"]?.result == 5)
    for lines in statements(try wrapper("wrapSame")) { #expect(lines.contains("return arg0"), "\(lines)") }
}

/// The value swiftdc recovers for a scalar function, evaluated on the
/// inputs the oracle used, is the value the machine returned.
@Test func recoveredScalarValuesEqualNativeResultsIfPresent() async throws {
    guard let seen = try observations() else { return }
    // (image, function prefix, registers as arguments, inputs, observation, mask)
    let cases: [(String, String, [String: Int], [UInt64], String, UInt64)] = [
        ("libInt64Fields.dylib", "Int64Fields.wideCombine(", ["x0": 0, "x1": 1, "x2": 2], [100, 7, 3],
         "Int64Fields wideCombine-100-7-3", .max),
        ("libInt64Fields.dylib", "Int64Fields.signedLess(", ["x0": 0, "x1": 1], [UInt64(bitPattern: -1), 2],
         "Int64Fields signedLess-neg1-2", 1),
        ("libInt64Fields.dylib", "Int64Fields.signedLess(", ["x0": 0, "x1": 1], [2, UInt64(bitPattern: -1)],
         "Int64Fields signedLess-2-neg1", 1),
        ("libInt64Fields.dylib", "Int64Fields.flagsUnion(", ["x0": 0, "x1": 1], [5, 10],
         "Int64Fields flagsUnion-5-10", .max),
        // `bics xzr, need, have; cset eq`.
        ("libOptionSubset.dylib", "OptionSubset.allows(", ["x0": 0, "x1": 1], [7, 5], "OptionSubset allows-7-5", 1),
        ("libOptionSubset.dylib", "OptionSubset.allows(", ["x0": 0, "x1": 1], [5, 7], "OptionSubset allows-5-7", 1),
    ]
    var loaded: [String: [DisassembledFunction]] = [:]
    for (image, prefix, registers, inputs, key, mask) in cases {
        if loaded[image] == nil { loaded[image] = try await functions(image) }
        let function = try #require(loaded[image]?.first { $0.displayName.hasPrefix(prefix) }, "\(prefix)")
        let analysis = ValueTracer().analyze(function, entry: .swiftFunction(scalarArguments: registers))
        let exit = try #require(function.instructions.last { $0.controlFlow == .return })
        let value = try #require(analysis.exitValues[exit.address], "\(prefix)")
        try #require(value != .unknown, "\(prefix) recovers no value")
        let predicted = try ProbeValue.abstractValue(value).evaluateInteger(arguments: inputs) & mask
        let native = UInt64(bitPattern: try #require(seen[key]?.result, "\(key)")) & mask
        #expect(predicted == native, "\(key): recovered \(predicted), native \(native)")
    }
}

/// The late implementation takes `_cmd`: sent as a message with keywords 5
/// and 9 it returned 5. Read with its entry convention, its exit value is
/// its first keyword argument, and evaluates to what it returned.
@Test func theLateImplementationsEntryAgreesWithItsNativeResultIfPresent() async throws {
    guard let seen = try observations() else { return }
    let native = try #require(seen["LateIMP late-5-9"]?.result)
    let image = "\(fixtures)/libLateIMP.dylib"
    let late = try #require(try await functions("libLateIMP.dylib", filter: "-[LICrate late:with:]")
        .first { $0.displayName == "-[LICrate late:with:]" })
    let index = ObjCMetadataIndex.build(in: try BinaryLoader.load(path: image))
    // What swiftdc decides: direct takes its keywords from x1, ordinary from x2.
    let direct = Disassembler.isDirectObjCMethod(late.symbol, at: late.startAddress, in: index)
    let keywords = direct ? ["x1": 0, "x2": 1] : ["x2": 0, "x3": 1]
    let analysis = ValueTracer().analyze(late, entry: .objectiveC(argumentCount: 2, scalarArguments: keywords))
    let exit = try #require(late.instructions.last { $0.controlFlow == .return })
    let value = try #require(analysis.exitValues[exit.address])
    try #require(value != .unknown)
    let predicted = try ProbeValue.abstractValue(value).evaluateInteger(arguments: [5, 9])
    #expect(Int64(bitPattern: predicted) == native, "direct=\(direct): recovered \(predicted), native \(native)")
}

/// The call the shaped stub's caller makes returned its argument plus 7,
/// which no message send of `take:` with 7 says: it is not rendered as one.
@Test func theShapedStubsCallerIsNotASendOfWhatItNativelyAddsIfPresent() async throws {
    guard let seen = try observations() else { return }
    try #require(seen["SelectorStubShape calls_branching_stub-5"]?.result == 12)
    let caller = try #require(try await functions("libSelectorStubShape.dylib").first { $0.symbol == "_calls_branching_stub" })
    for lines in statements(caller) { #expect(!lines.contains { $0.contains("take:") }, "\(lines)") }
}

/// Two reads of `n` with the twin between them differed natively by 18:
/// the render does not subtract the field from itself.
@Test func theTwinsFieldReadsAreNotOneValueNativelyIfPresent() async throws {
    guard let seen = try observations() else { return }
    try #require(seen["AccessTwin acrossEnd"]?.result == 18)
    let function = try #require(try await functions("libAccessTwin.dylib").first { $0.displayName.hasPrefix("AccessTwin.acrossEnd(") })
    for lines in statements(function) { #expect(!lines.contains { $0.contains("arg0.n - arg0.n") }, "\(lines)") }
}
