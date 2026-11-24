import Foundation
import Testing
@testable import SwiftDecompilerCore

/// After a call to a synchronous `throws(E)` function the caller tests x21.
/// On the nonzero edge the callee produced no result: x0 is the typed error
/// where the result and the error are both direct, and undefined where
/// either is indirect (swift/lib/IRGen/GenCall.cpp,
/// `combineResultAndTypedErrorType` and `hasIndirectTypedErrorResultSlot`).
/// The call's result name therefore ends at that edge, in x0, in v0, and in
/// every register and frame slot the result was copied to before the test.
/// The zero edge keeps it. An untyped `throws` callee returns its error in
/// x21 and is left as it was.

private let typed = "M.pick(Swift.Int) throws(M.Fault) -> Swift.Int"
private let untyped = "M.pick(Swift.Int) throws -> Swift.Int"
private let generic = "M.pick<A where A: Swift.Error>(Swift.Int, A.Type) throws(A) -> Swift.Int"

private func traced(
    _ words: [UInt32], callee: String, preservesSwiftError: Bool = false
) throws -> (analysis: FunctionAnalysis, site: UInt64) {
    let engine = try #require(CapstoneEngine())
    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let decoded = engine.disassemble(bytes, address: 0x1000)
    try #require(decoded.count == words.count)
    let instructions = decoded.map { item in
        var facts = Instruction.Facts()
        facts.bodyPreservesSwiftError = preservesSwiftError && item.controlFlow == .call
        return Instruction(address: item.address, text: item.text, controlFlow: item.controlFlow,
            branchTarget: item.branchTarget, detail: item.detail,
            callee: .kept(item.controlFlow == .call ? callee : nil), facts: facts)
    }
    let site = try #require(instructions.first { $0.controlFlow == .call }?.address)
    let function = DisassembledFunction(symbol: "_caller", demangledName: "M.caller(Swift.Int) -> Swift.Int",
        startAddress: 0x1000, instructions: instructions, source: .symbol)
    return (ValueTracer().analyze(function), site)
}

/// Whether `value` is, or is computed from, the result of the call at `site`.
private func mentions(_ site: UInt64, _ value: AbstractValue?) -> Bool {
    switch value {
    case .callResult(site)?, .callResultHigh(site)?: return true
    case .unary(_, let operand)?, .loadedFrom(let operand, _)?: return mentions(site, operand)
    case .binary(_, let lhs, let rhs)?: return mentions(site, lhs) || mentions(site, rhs)
    case .select(let condition, let yes, let no)?:
        return mentions(site, condition) || mentions(site, yes) || mentions(site, no)
    case .aggregate(let values)?: return values.contains { mentions(site, $0) }
    default: return false
    }
}

/// Each body calls 0x2000, tests x21 and returns x0 on both edges.
/// Each is (what, words, the `ret` reached with x21 zero, the `ret` reached
/// with it nonzero).
private let errorEdgeShapes: [(String, [UInt32], UInt64, UInt64)] = [
    // stp x29, x30, [sp, #-16]!; bl; cbnz x21, 1f; add x0, x0, #7; ldp; ret; 1: add x0, x0, #9; ldp; ret
    ("cbnz x21, the error at the target",
     [0xa9bf7bfd, 0x940003ff, 0xb5000095, 0x91001c00, 0xa8c17bfd, 0xd65f03c0,
                  0x91002400, 0xa8c17bfd, 0xd65f03c0],
     0x1014, 0x1020),
    // The same body with cbz: the error falls through.
    ("cbz x21, the error at the fallthrough",
     [0xa9bf7bfd, 0x940003ff, 0xb4000095, 0x91001c00, 0xa8c17bfd, 0xd65f03c0,
                  0x91002400, 0xa8c17bfd, 0xd65f03c0],
     0x1020, 0x1014),
    // sub sp, #32; stp x29, x30, [sp, #16]; bl; str x0, [sp, #8]; cbnz x21, 1f;
    // ldr x0, [sp, #8]; ldp; add sp; ret; 1: ldr x0, [sp, #8]; ldp; add sp; ret
    ("the result spilled before the test, as -Onone does",
     [0xd10083ff, 0xa9017bfd, 0x940003fe, 0xf90007e0, 0xb50000b5,
                  0xf94007e0, 0xa9417bfd, 0x910083ff, 0xd65f03c0,
                  0xf94007e0, 0xa9417bfd, 0x910083ff, 0xd65f03c0],
     0x1020, 0x1030),
    // stp; bl; mov x19, x0; cbnz x21, 1f; add x0, x19, #7; ldp; ret; 1: add x0, x19, #9; ldp; ret
    ("the result copied to a callee-saved register before the test",
     [0xa9bf7bfd, 0x940003ff, 0xaa0003f3, 0xb5000095, 0x91001e60, 0xa8c17bfd, 0xd65f03c0,
                  0x91002660, 0xa8c17bfd, 0xd65f03c0],
     0x1018, 0x1024),
    // stp; bl; add x19, x0, #7; cbnz x21, 1f; mov x0, x19; ldp; ret; 1: mov x0, x19; ldp; ret
    ("a value computed from the result before the test",
     [0xa9bf7bfd, 0x940003ff, 0x91001c13, 0xb5000095, 0xaa1303e0, 0xa8c17bfd, 0xd65f03c0,
                  0xaa1303e0, 0xa8c17bfd, 0xd65f03c0],
     0x1018, 0x1024),
]

@Test(arguments: errorEdgeShapes)
func theResultOfATypedThrowingCallEndsAtItsErrorEdge(
    what: String, words: [UInt32], success: UInt64, error: UInt64
) throws {
    for callee in [typed, generic] {
        let (analysis, site) = try traced(words, callee: callee)
        let comment = Comment(rawValue: "\(what), \(callee)")
        #expect(!mentions(site, analysis.exitValues[error]), comment)
        // The zero edge is the callee's normal return.
        #expect(mentions(site, analysis.exitValues[success]), comment)
    }
}

/// Plain `throws` returns the error in x21 and nothing says what x0 is:
/// the result's name is left as it was on both edges.
@Test(arguments: errorEdgeShapes)
func anUntypedThrowingCallKeepsItsResultNameOnBothEdges(
    what: String, words: [UInt32], success: UInt64, error: UInt64
) throws {
    let (analysis, site) = try traced(words, callee: untyped)
    #expect(mentions(site, analysis.exitValues[error]), Comment(rawValue: what))
    #expect(mentions(site, analysis.exitValues[success]), Comment(rawValue: what))
}

/// v0 on the error edge is no more the result than x0 is: a floating
/// result is not combined with the error, and the callee did not make one.
@Test func theFloatingResultOfATypedThrowingCallEndsAtItsErrorEdge() throws {
    // stp; bl; cbnz x21, 1f; ldp; ret; 1: ldp; ret
    let words: [UInt32] = [0xa9bf7bfd, 0x940003ff, 0xb5000075, 0xa8c17bfd, 0xd65f03c0, 0xa8c17bfd, 0xd65f03c0]
    let (success, error): (UInt64, UInt64) = (0x1010, 0x1018)
    let (analysis, site) = try traced(words, callee: "M.scale(Swift.Int) throws(M.Fault) -> Swift.Double")
    #expect(!mentions(site, analysis.exitFloatValues[error]))
    #expect(!mentions(site, analysis.exitValues[error]))
    // The same body after an untyped callee: both edges agree.
    let (control, controlSite) = try traced(words, callee: "M.scale(Swift.Int) throws -> Swift.Double")
    #expect(control.exitFloatValues[error] == control.exitFloatValues[success])
    #expect(mentions(controlSite, control.exitValues[error]))
}

/// The edge is the error's only where x21 at the test is the flag that
/// call set. Each of these is some other test, and keeps the name.
@Test(arguments: [
    // stp; bl; mov x21, x19; cbnz x21, 1f; add x0, x0, #7; ldp; ret; 1: add x0, x0, #9; ldp; ret
    ("x21 written between the call and the test", false,
     [0xa9bf7bfd, 0x940003ff, 0xaa1303f5, 0xb5000095, 0x91001c00, 0xa8c17bfd, 0xd65f03c0,
      0x91002400, 0xa8c17bfd, 0xd65f03c0], 0x1018, 0x1024),
    // stp; bl; cbnz x20, 1f; add x0, x0, #7; ldp; ret; 1: add x0, x0, #9; ldp; ret
    ("a test of another register", false,
     [0xa9bf7bfd, 0x940003ff, 0xb5000094, 0x91001c00, 0xa8c17bfd, 0xd65f03c0,
      0x91002400, 0xa8c17bfd, 0xd65f03c0], 0x1014, 0x1020),
    // stp; bl; cbnz w21, 1f; …: the low word alone is not the flag's test
    ("a test of w21", false,
     [0xa9bf7bfd, 0x940003ff, 0x35000095, 0x91001c00, 0xa8c17bfd, 0xd65f03c0,
      0x91002400, 0xa8c17bfd, 0xd65f03c0], 0x1014, 0x1020),
    // The first body again, the callee's body proven to hand x21 back.
    ("a callee proven not to throw", true,
     [0xa9bf7bfd, 0x940003ff, 0xb5000095, 0x91001c00, 0xa8c17bfd, 0xd65f03c0,
      0x91002400, 0xa8c17bfd, 0xd65f03c0], 0x1014, 0x1020),
] as [(String, Bool, [UInt32], UInt64, UInt64)])
func aTestThatIsNotTheCallsErrorFlagKeepsTheResult(
    what: String, preserves: Bool, words: [UInt32], zero: UInt64, nonzero: UInt64
) throws {
    let (analysis, site) = try traced(words, callee: typed, preservesSwiftError: preserves)
    #expect(mentions(site, analysis.exitValues[nonzero]), Comment(rawValue: what))
    #expect(mentions(site, analysis.exitValues[zero]), Comment(rawValue: what))
}

@Test func aSignatureThrowsATypedErrorOnlyWithAThrownType() {
    #expect(ValueTracer.CallFacts(callee: typed).throwsTypedError)
    #expect(ValueTracer.CallFacts(callee: generic).throwsTypedError)
    #expect(!ValueTracer.CallFacts(callee: untyped).throwsTypedError)
    #expect(!ValueTracer.CallFacts(callee: "M.pick(Swift.Int) -> Swift.Int").throwsTypedError)
    #expect(!ValueTracer.CallFacts(callee: "M.pick(Swift.Int) throws(any Swift.Error) -> Swift.Int").throwsTypedError)
    #expect(!ValueTracer.CallFacts(callee: "_objc_msgSend").throwsTypedError)
}

// MARK: - typedcatch.swift

private let typedCatchLevels = [
    ("-Onone", "Fixtures/Sample/libTypedCatch.Onone.dylib"),
    ("-O", "Fixtures/Sample/libTypedCatch.O.dylib"),
]

/// The structured and flat views of `TypedCatch.<name>(`, from the whole
/// image and from a filtered run. No function of the fixture is expected
/// to be absent at either level: every body has its own constants, so
/// none folds onto another.
private func typedCatchViews(_ name: String, in path: String) async throws -> [String]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let prefix = "TypedCatch.\(name)("
    let whole = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    let filtered = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: prefix)
    }
    var views: [String] = []
    for functions in [whole, filtered] {
        let function = try #require(functions.first { $0.displayName.hasPrefix(prefix) },
                                    Comment(rawValue: "\(path): \(name)"))
        views += [function.renderStructured(), function.renderPseudo()]
    }
    return views
}

private func trimmedLines(_ text: String) -> [String] {
    text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
}

/// Text that names the result of the call spelled `call` (`M.f(`): the
/// call nested in it, or a bound result (`r0`).
private func namesResult(_ text: String, of call: String) -> Bool {
    text.contains(call) || text.range(of: #"\br[0-9]+\b"#, options: .regularExpression) != nil
}

/// What follows `TypedCatch.<function>(` on each line that calls it: its
/// argument list onward. The call's own result may be bound to a name
/// before it; only what it is passed is of interest.
private func argumentTexts(of function: String, in text: String) -> [String] {
    trimmedLines(text).compactMap { line in
        line.range(of: "TypedCatch.\(function)(").map { String(line[$0.upperBound...]) }
    }
}

/// The catch hands the error to `handler`. Its argument is the error the
/// callee threw, never what the callee returned: `caught(-2)` is
/// `report(Fault(code: -6))`, and `pick` returned nothing.
@Test(arguments: [
    ("caught", "pick", "report"), ("caughtKind", "grade", "tally"),
    ("caughtScale", "scale", "weigh"), ("caughtNote", "note", "audit"),
])
func aCaughtTypedErrorIsNotTheCalleesResultIfPresent(caller: String, callee: String, handler: String) async throws {
    for (level, path) in typedCatchLevels {
        guard let views = try await typedCatchViews(caller, in: path) else { continue }
        for text in views {
            let comment = Comment(rawValue: "\(level): \(text)")
            let handed = argumentTexts(of: handler, in: text)
            try #require(!handed.isEmpty, comment)
            #expect(!handed.contains { namesResult($0, of: "TypedCatch.\(callee)(") }, comment)
            #expect(text.contains("TypedCatch.\(callee)("), comment)
        }
    }
}

/// The zero edge is the callee's normal return and keeps the result's
/// name: the normal path passes it on. The last two are controls the
/// change must not move at all: an untyped `throws` callee, whose error is
/// in x21, and a `throws(Never)` function, which has no error edge.
@Test(arguments: [
    ("caught", "pick", "keep"), ("caughtKind", "grade", "hold"),
    ("caughtLoose", "loose", "carry"), ("useSure", "sure", "mark"),
])
func theNormalPathAfterAThrowingCallKeepsItsResultIfPresent(caller: String, callee: String, user: String) async throws {
    for (level, path) in typedCatchLevels {
        guard let views = try await typedCatchViews(caller, in: path) else { continue }
        for text in views {
            let comment = Comment(rawValue: "\(level): \(text)")
            let passed = argumentTexts(of: user, in: text)
            try #require(!passed.isEmpty, comment)
            #expect(passed.contains { namesResult($0, of: "TypedCatch.\(callee)(") }, comment)
        }
    }
}

/// reconstruction.swift's `typedForward` at -Onone spills x0 twice before
/// `cbz x21`: the error path reloads one slot as the error's tag, the
/// normal path the other as the result. The tracer's x0 at the throwing
/// `ret` was `typedPick`'s result masked to a byte.
@Test func aForwardedTypedErrorIsNotTheCalleesResultAtItsExitIfPresent() async throws {
    let path = "Fixtures/Sample/libReconstruction.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: "Reconstruction.typedForward(")
    }
    let function = try #require(functions.first { $0.displayName.hasPrefix("Reconstruction.typedForward(") })
    let analysis = ValueTracer().analyze(function)
    let site = try #require(function.instructions.first { $0.controlFlow == .call }?.address)
    let exits = function.instructions.filter { $0.controlFlow == .return }.map(\.address)
    try #require(exits.count == 2)
    // The first `ret` is the normal return, `typedPick(n) + 1`.
    #expect(mentions(site, analysis.exitValues[exits[0]]))
    #expect(!mentions(site, analysis.exitValues[exits[1]]))
    let text = function.renderStructured()
    #expect(text.contains("throw ?"), Comment(rawValue: text))
    #expect(trimmedLines(text).contains { $0.hasPrefix("return ") && namesResult($0, of: "Reconstruction.typedPick(") },
            Comment(rawValue: text))
}
