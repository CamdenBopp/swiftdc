import Foundation
import Testing
@testable import SwiftDecompilerCore

// Recovered from the pre-merge stash (d921fc1, improve/source-findings).

private let abiSourceDebug = "Fixtures/Sample/libABISource.dylib"
private let abiSourceOptimized = "Fixtures/Sample/libABISource.opt.dylib"
private let abiSourceResilient = "Fixtures/Sample/libABISource.resilient.dylib"
private let abiSourceOracle = "Fixtures/Sample/abi-source-oracle"
private let abiSourceResilientOracle = "Fixtures/Sample/abi-source-resilient-oracle"

private func abiSourcePseudo(_ filter: String, in path: String) async throws -> String? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: filter)
    }
    return functions.map { $0.renderPseudo() }.joined(separator: "\n")
}

// Concurrent metadata scans crashed in MachOKit's chained-fixup page traversal
// on this host. Keep this fixture's disassemblies serial within the suite.
@Suite(.serialized)
struct ABISourceLoweringTests {
    @Test func nativeABISourceOracleIfPresent() throws {
        guard FileManager.default.fileExists(atPath: abiSourceOracle) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(abiSourceOracle)
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(text.split(whereSeparator: \.isNewline).map(String.init) == [
            "3.5", "13.0", "31.0", "15", "11", "BCDE", "sizes 8 16 40 32 32",
        ])
    }

    @Test func nativeResilientOneWordResultIfPresent() throws {
        guard FileManager.default.fileExists(atPath: abiSourceResilientOracle),
              FileManager.default.fileExists(atPath: abiSourceResilient) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(abiSourceResilientOracle)
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        // First call stores directly through x8; second copies x8 to x10 and
        // stores through the alias. Both execute against the resilient dylib.
        #expect(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == "27\n27\n")
    }

    @Test func resilientOneWordReturnUsesIncomingX8IfPresent() async throws {
        guard let pseudo = try await abiSourcePseudo("abiMakeOne", in: abiSourceResilient) else { return }
        // Native body: `add x9, x0, #17; str x9, [x8]; ret`. The complete
        // resilient result layout is one eight-byte `a` field at offset zero;
        // x0 still holds the seed and is not a return value.
        #expect(pseudo.contains("return ABISource.ABIOneWord(a: (arg0 + 17))"), "Pseudo: \(pseudo)")
        #expect(!pseudo.contains("return arg0"), "Pseudo: \(pseudo)")
    }

    @Test func x8ResultsRenderOnlyWhatTheStoresProveIfPresent() async throws {
        // The stash expected these to decline outright; HEAD's x8 tracking
        // (IndirectResults) proves more, and the native oracle agrees with it.
        // `abiMakeFive` stores four words as two SIMD pairs and one word as an
        // integer: only the integer field is proven.
        if let five = try await abiSourcePseudo("abiMakeFive", in: abiSourceResilient) {
            #expect(five.contains("return ABISource.ABIFiveWords(a: ?, b: ?, c: ?, d: ?, e: (arg0 + 5))"), "Pseudo: \(five)")
        }
        // `mov x10, x8; str x9, [x10]`: the alias is followed. The resilient
        // oracle above executes it and gets 27 for seed 10.
        if let alias = try await abiSourcePseudo("abiMakeAliasedOne", in: abiSourceResilient) {
            #expect(alias.contains("return ABISource.ABIOneWord(a: (arg0 + 17))"), "Pseudo: \(alias)")
        }
        // A SIMD-stored two-word result proves nothing it can render.
        if let two = try await abiSourcePseudo("abiMakeTwo", in: abiSourceResilient) {
            #expect(two.contains("return ?"), "Pseudo: \(two)")
            #expect(!two.contains("return ABISource."))
        }
        // The nonresilient one-word result is direct (`add x0, x0, #17; ret`),
        // but a nominal type's register class is not proven from its name, so
        // its x0 is not read as the result.
        if let direct = try await abiSourcePseudo("abiMakeOne", in: abiSourceOptimized) {
            #expect(direct.contains("return ?"), "Pseudo: \(direct)")
            #expect(!direct.contains("return (arg0"))
        }
    }

    @Test func nominalFloatingResultDoesNotReuseStaleIntegerResultIfPresent() async throws {
        guard let pseudo = try await abiSourcePseudo("abiOneDoubleFromInt", in: abiSourceOptimized) else { return }
        // Native result: `bl abiAddOne; scvtf d0, x0; fadd d0, d0, #0.5; ret`.
        // x0 still holds abiAddOne's Int and is not the ABIOneDouble result.
        #expect(pseudo.contains("abiOneDoubleFromInt"))
        #expect(pseudo.contains("ABISource.abiAddOne(arg0)"), "Pseudo: \(pseudo)")
        #expect(!pseudo.contains("return ABISource.abiAddOne(arg0)"), "Pseudo: \(pseudo)")
    }

    @Test func valueSelfHFAGetsRegistersAfterFloatingArgumentIfPresent() async throws {
        for path in [abiSourceDebug, abiSourceOptimized] {
            guard let pseudo = try await abiSourcePseudo("ABIVec2.scaled", in: path) else { continue }
            // Native entry: d0=factor, d1=self.x, d2=self.y. At x=2, y=3,
            // factor=5 this expression yields 13; self.x*self.y+factor gives 11.
            #expect(pseudo.contains("ABIVec2.scaled"), "Pseudo: \(pseudo)")
            #expect(pseudo.contains("self.y)"), "Pseudo: \(pseudo)")
            #expect(pseudo.contains("arg0 * self.x") || pseudo.contains("self.x * arg0"), "Pseudo: \(pseudo)")
            #expect(!pseudo.contains("self.x * self.y") && !pseudo.contains("self.y * self.x"), "Pseudo: \(pseudo)")
        }
    }

    @Test func valueSelfHFAGetsRegistersAfterHFAArgumentIfPresent() async throws {
        for path in [abiSourceDebug, abiSourceOptimized] {
            guard let pseudo = try await abiSourcePseudo("ABIVec2.dot", in: path) else { continue }
            // Native entry: d0/d1=other.x/y, d2/d3=self.x/y. The fixture's
            // execution oracle checks dot((2,3), (5,7)) == 31.
            let expected = path == abiSourceDebug
                ? "return ((self.x * arg0.x) + (self.y * arg0.y))"
                : "return ((arg0.x * self.x) + (arg0.y * self.y))"
            #expect(pseudo.contains(expected), "Pseudo: \(pseudo)")
        }
    }

    @Test func unknownNominalResultHasNoAssumedIntegerReturnRegister() {
        let function = DisassembledFunction(
            symbol: "test",
            demangledName: "ABISource.abiOneDoubleFromInt(Swift.Int) -> ABISource.ABIOneDouble",
            startAddress: 0x1000, instructions: [], source: .symbol)
        #expect(Disassembler.swiftReturnRegister(of: function) == nil)
    }

    @Test func indirectResultCallDoesNotInheritTrailingCallerRegisterIfPresent() async throws {
        for path in [abiSourceOptimized, abiSourceResilient] {
            guard let pseudo = try await abiSourcePseudo("abiMaybeFive", in: path) else { continue }
            // Native `abiMaybeFive(seed, yes)` passes only x0=seed to
            // `abiMakeFive(seed)`. x1 still holds `yes`, but is not a formal
            // argument of that call; x8 supplies its result buffer.
            #expect(pseudo.contains("ABISource.abiMakeFive(arg0)"), "Pseudo: \(pseudo)")
            #expect(!pseudo.contains("ABISource.abiMakeFive(arg0, arg1)"), "Pseudo: \(pseudo)")
        }
    }

    /// The last ` -> ` names a function-typed result's own result, not the
    /// signature's: `f() -> (Swift.Int) -> Swift.Int` returns a two-word closure.
    @Test func functionTypedResultsHaveNoReturnRegister() {
        let register = Disassembler.swiftReturnRegister(forDemangledName:)
        #expect(register("m.f() -> (Swift.Int) -> Swift.Int") == nil)
        #expect(register("m.f() async -> (Swift.Int) -> Swift.Int") == nil)
        #expect(register("m.T.handler.getter : (Swift.Int) -> Swift.Int") == nil)
        #expect(register("m.f() -> Swift.Int") == .integer)
        #expect(register("m.T.count.getter : Swift.Int") == .integer)
        #expect(register("m.f() -> Swift.Double") == .floating)
    }
}

/// `swift_getAtKeyPath` returns its generic `Value` through x8, so a
/// caller's result buffer forwarded to it is overwritten: the stores before
/// the call are not the result. Every `swift_` callee was taken to return
/// in registers, and `staleAfterKeyPath` rendered
/// `return ResultBuffer.Big(a: 7, b: 7, c: 7, d: 7, e: 7)`. The control,
/// `swift_retain`, does ignore x8 and keeps the stores (`resultbuffer.s`).
@Test func aRuntimeCallReturningThroughX8OverwritesTheResultBufferIfPresent() async throws {
    let path = "Fixtures/Sample/libResultBuffer.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.contains(name) }).renderStructured()
    }
    let stale = try structured("staleAfterKeyPath")
    #expect(!stale.contains("Big(a: 7"), Comment(rawValue: stale))
    #expect(stale.contains("return ?"), Comment(rawValue: stale))
    let kept = try structured("keptAfterRetain")
    #expect(kept.contains("return ResultBuffer.Big(a: 7, b: 7, c: 7, d: 7, e: 7)"), Comment(rawValue: kept))
    for name in ["swift_getAtKeyPath", "_swift_getAtKeyPath", "swift_reflectAny", "_swift_stdlib_operatingSystemVersion"] {
        #expect(!Disassembler.isKnownDirectReturnCallee(name), "\(name)")
    }
    #expect(Disassembler.isKnownDirectReturnCallee("swift_retain"))
}

/// A function signature specialization prints its original's signature,
/// but `Arg[0] = Dead` drops that parameter: `<Arg[0] = Dead> of
/// helperI(Swift.Int, Swift.Int)` takes `b` in x0, and seeded from the
/// printed signature its `b &* 23` read `return (arg0 * 23)`, crediting
/// the value to `a` (`deadargs.swift`). Only an ownership change keeps
/// the layout; anything else seeds nothing.
@Test func aSpecializationThatDropsAParameterIsNotSeededFromItsOriginalIfPresent() async throws {
    let path = "Fixtures/Sample/libDeadArgs.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let specialization = try #require(functions.first {
        $0.displayName.hasPrefix("function signature specialization <Arg[0] = Dead> of DeadArgs.helperI")
    })
    let text = specialization.renderStructured()
    #expect(!text.contains("arg0"), Comment(rawValue: text))
    #expect(Disassembler.signatureSpecializationKeepsLayout(
        "function signature specialization <Arg[0] = Owned To Guaranteed, Arg[1] = Guaranteed To Owned> of M.f(Swift.Int, Swift.Int) -> Swift.Int"))
    #expect(Disassembler.signatureSpecializationKeepsLayout("M.f(Swift.Int) -> Swift.Int"))
    for name in [
        "function signature specialization <Arg[0] = Dead> of M.f(Swift.Int, Swift.Int) -> Swift.Int",
        "function signature specialization <Arg[0] = Dead and Owned To Guaranteed> of M.f(Swift.Int) -> Swift.Int",
        "function signature specialization <Arg[0] = Exploded> of M.f(M.S) -> Swift.Int",
        "merged function signature specialization <Arg[0] = Owned To Guaranteed> of M.f(Swift.Int) -> Swift.Int",
    ] {
        #expect(!Disassembler.signatureSpecializationKeepsLayout(name), "\(name)")
    }
}

/// A specialization of a free function has no `self`, whatever its caller
/// keeps in x20: `callI` saves its first result there across the second
/// call, which read `helperI(self: r0, arg0)` (`deadargs.swift`).
@Test func aFreeFunctionsSpecializationTakesNoSelfIfPresent() async throws {
    let path = "Fixtures/Sample/libDeadArgs.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    for name in ["DeadArgs.callI", "DeadArgs.callS"] {
        let text = try #require(functions.first { $0.displayName.hasPrefix(name) }).renderStructured()
        #expect(!text.contains("self"), Comment(rawValue: text))
        #expect(text.contains("Dead> of DeadArgs.helper"), Comment(rawValue: text))
    }
    #expect(Disassembler.withoutSpecializationClauses(
        "function signature specialization <Arg[0] = Dead> of generic specialization <Swift.Int> of M.f<A>(A) -> ()")
        == "M.f<A>(A) -> ()")
    #expect(Disassembler.withoutSpecializationClauses("M.T.f() -> ()") == "M.T.f() -> ()")
}

/// A call to a specialization that drops a parameter takes what the
/// specialization's body reads, since the signature its name prints is its
/// original's: `<Arg[0] = Dead> of helperI(Swift.Int, Swift.Int)` reads x0
/// alone, and laid out positionally `callI`'s first call read
/// `helperI(arg1, arg1)`, x1 still holding `arg1` (`deadargs.swift`).
@Test func aCallToASpecializationThatDropsAParameterTakesWhatItReadsIfPresent() async throws {
    let path = "Fixtures/Sample/libDeadArgs.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = try #require(functions.first { $0.displayName.hasPrefix("DeadArgs.callI") }).renderStructured()
    #expect(text.contains("let r0 = function signature specialization <Arg[0] = Dead> of DeadArgs.helperI(arg1)\n"),
            Comment(rawValue: text))
}

/// A parameter whose footprint the ABI fixes but no one register holds (a
/// String's two words, an `Int?`'s payload and tag, an `inout` address, a
/// StaticString's three words) stopped every parameter from being seeded,
/// so the Int after it read `return ?`. It is now skipped by its word
/// count: `afterString(_:_:)` takes its Int in x2 (`entryfootprints.swift`).
@Test func anIntAfterAFixedFootprintParameterIsSeededIfPresent() async throws {
    let path = "Fixtures/Sample/libEntryFootprints.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let expected = [
        "afterString": "return (arg1 + (arg1 << 1))",
        "afterOptional": "return (arg1 + (arg1 << 2))",
        "afterInout": "return ((arg1 << 3) - arg1)",
        "afterStaticString": "return (arg1 + (arg1 << 3))",
    ]
    for (name, line) in expected.sorted(by: { $0.key < $1.key }) {
        let text = try #require(functions.first { $0.displayName.hasPrefix("EntryFootprints.\(name)(") }).renderStructured()
        #expect(text.contains(line), Comment(rawValue: text))
    }
}

/// Seeded, a register a caller never touched still holds its own entry
/// value at a call, and laid out by position it read as one more argument:
/// `W.k(arg1, arg0, arg2)` for a one-word struct's `k(_:)` (its y and
/// self's word, then callK's z, `entryfootprints.swift`), and
/// `String.utf8.getter(?, ?, arg1)` for the String's two words and
/// takeTwo's Int (`stringarity.swift`). After a value method's formals a
/// trailing run of such registers is dropped, and a String's getter takes
/// exactly its two words.
@Test func aRegisterLeftFromEntryIsNoTrailingArgumentIfPresent() async throws {
    let footprints = "Fixtures/Sample/libEntryFootprints.dylib", strings = "Fixtures/Sample/libStringArity.dylib"
    guard FileManager.default.fileExists(atPath: footprints), FileManager.default.fileExists(atPath: strings) else { return }
    let k = try await withStableDependencies { try await Disassembler().disassemble(path: footprints) }
    let callK = try #require(k.first { $0.displayName.hasPrefix("EntryFootprints.callK(") }).renderStructured()
    #expect(callK.contains("return (EntryFootprints.W.k(arg1, arg0) + arg2)"), Comment(rawValue: callK))
    let s = try await withStableDependencies { try await Disassembler().disassemble(path: strings) }
    let takeTwo = try #require(s.first { $0.displayName.hasPrefix("StringArity.takeTwo(") }).renderStructured()
    // A String's getter takes its two words and nothing after them.
    #expect(takeTwo.contains("Swift.String.utf8.getter(?, ?))"), Comment(rawValue: takeTwo))
}

/// A call whose result spans registers is not its first register: Pair
/// returns in x0 and x1, Mix in x0 and d0, PE as a payload and a tag, and
/// a caller using one part read the whole call (`(mkPair((arg0 + 4)) +
/// 2)`, `takeInt(r0)` for PE's payload; `multiresult.swift`). A
/// one-register result still is the call, and so are a multi-word
/// result's words passed on together (`count.getter(utf8.getter(…))`).
@Test func onePartOfAMultiRegisterResultIsNotTheCallIfPresent() async throws {
    let path = "Fixtures/Sample/libMultiResult.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("MultiResult.\(name)(") }).renderStructured()
    }
    // The call stays a statement; the part it hands on is `?`.
    for (name, call) in [("pairA", "mkPair((arg0 + 4))"), ("mixI", "mkMix((arg0 + 17))"), ("mixD", "mkMix((arg0 + 19))")] {
        let body = try text(name)
        #expect(body.contains("    MultiResult.\(call)\n"), Comment(rawValue: body))
        #expect(!body.contains("\(call) +"), Comment(rawValue: body))
    }
    let pe = try text("peOn")
    #expect(!pe.contains("takeInt(r0)"), Comment(rawValue: pe))
    #expect(try text("intCall").contains("return (MultiResult.takeInt((arg0 + 3)) + 1)"))
}
