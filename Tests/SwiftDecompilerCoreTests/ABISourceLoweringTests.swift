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
        // A one-pointer collection is one integer register (SwiftLowering).
        "afterArray": "return (arg1 * 11)",
        "afterDictionary": "return (arg1 * 13)",
        "afterSet": "return (arg1 + (arg1 << 4))",
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

/// A one-case enum is zero-sized and takes no register. Counted as one,
/// `oneMid(_ a: Int, _ o: One, _ b: Int)` read `return ((7 * arg0) - arg1)`
/// with `arg1` the enum, and its caller `oneMid(arg0, arg1, ?)`
/// (`onecase.swift`, ABI review item 8).
@Test func aOneCaseEnumTakesNoRegisterIfPresent() async throws {
    let path = "Fixtures/Sample/libOneCase.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let callee = try #require(functions.first { $0.displayName.hasPrefix("OneCase.oneMid(") }).renderStructured()
    #expect(callee.contains("return ((7 * arg0) - arg2)"), Comment(rawValue: callee))
    let caller = try #require(functions.first { $0.displayName.hasPrefix("OneCase.callOneMid(") }).renderStructured()
    #expect(!caller.contains("oneMid(arg0, arg1, ?)"), Comment(rawValue: caller))
}

/// A callee whose body never reads the x20 it is handed takes no `self`
/// there, whatever the caller parked in the callee-saved register:
/// `freshEnum` keeps `v` in x20 across `md.weight(v)`, a by-value enum
/// method whose self is a trailing word, and read `Mode.weight(self: r0,
/// r0)` (`parkedself.swift`, ABI review item 2).
@Test func aCalleeThatNeverReadsX20TakesNoSelfIfPresent() async throws {
    let path = "Fixtures/Sample/libParkedSelf.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = try #require(functions.first { $0.displayName.hasPrefix("ParkedSelf.freshEnum(") }).renderStructured()
    #expect(text.contains("ParkedSelf.Mode.weight(r0)"), Comment(rawValue: text))
    #expect(!text.contains("self"), Comment(rawValue: text))
}

/// An async callee takes its formals as a synchronous one does when its
/// result travels in registers, and behind an indirect result's buffer in
/// x0 otherwise. Laid out by position, `bumpG()` read `bumpG(?)` (x0 the
/// callee context), `dbl(_: Double)` read `dbl(?)` with the Double in d0
/// dropped, and `bigRes(_: Int) -> Big5` read `bigRes(?, arg0)`
/// (`asynccalls.swift`, ABI review item 7).
@Test func anAsyncCallTakesItsDeclaredParametersIfPresent() async throws {
    let path = "Fixtures/Sample/libAsyncCalls.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    for line in ["await AsyncCalls.bumpG()\n", "await AsyncCalls.dbl(arg0)\n",
                 "await AsyncCalls.twoArgs(arg0, arg1)\n", "await AsyncCalls.bigRes(?)\n"] {
        #expect(text.contains(line), "\(line)")
    }
}

/// Inside an async function whose result may be indirect, x0 may be the
/// result's buffer, which comes before the formals: `bigRes(_ x: Int) async
/// -> Big5` read `mem64[arg0] = x1`, `arg0` naming the buffer
/// (`asynccalls.swift`, ABI review a7 #2). One with a direct result is
/// seeded as before.
@Test func anAsyncFunctionWithAnUnprovenResultIsNotSeededIfPresent() async throws {
    let path = "Fixtures/Sample/libAsyncCalls.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let big = try #require(functions.first { $0.displayName.hasPrefix("AsyncCalls.bigRes(") }).renderStructured()
    #expect(!big.contains("arg0"), Comment(rawValue: big))
    let two = try #require(functions.first { $0.displayName.hasPrefix("AsyncCalls.twoArgs(") }).renderStructured()
    #expect(two.contains("return ((arg1 - arg0) + (arg0 << 3))"), Comment(rawValue: two))
}

/// A generic function takes a generic value by address and its metadata
/// after the formals, and a tuple result with a generic element takes its
/// buffer first, from x0 (GenCall.cpp). By position `identity<A>(w)` read
/// `identity<A>(local_20, 0x4010)`, the metadata as an argument, and
/// `split<A>(w, n)` read `(local_18, local_20, ?, 0x4010)`, the buffer as
/// `x` (`genericcalls.swift`, ABI review item 11).
@Test func aGenericCallTakesItsDeclaredParametersIfPresent() async throws {
    let path = "Fixtures/Sample/libGenericCalls.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains("GenericCalls.identity<A>(local_20)\n"), Comment(rawValue: text))
    #expect(text.contains("GenericCalls.split<A>(?, ?)\n"), Comment(rawValue: text))
}

/// A `Tt` generic specialization drops the arguments its substitution made
/// trivial, here the metatype, but prints like the unspecialized
/// declaration: `tt<Double>` takes d in d0 and k in x0, and read against
/// the printed `(A.Type, A, Swift.Int)` it rendered `tt<…>(arg0)`, `k` as
/// the metatype and `d` gone (`droppedmeta.swift`, ABI review a8 #2).
@Test func aSpecializationThatDropsItsMetatypeTakesTheRestIfPresent() async throws {
    let path = "Fixtures/Sample/libDroppedMeta.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = try #require(functions.first { $0.displayName.hasPrefix("DroppedMeta.useTT(") }).renderStructured()
    #expect(text.contains("Swift.BinaryFloatingPoint>(arg1, arg0)"), Comment(rawValue: text))
}

/// `ins`/`umov` canonicalize to `mov` with a lane operand: `mov v0.d[1],
/// x2` writes one element, and modelled as a whole move `fmov d0, x1; mov
/// v0.d[1], x2; str q0, [x0]` stored `arg2` alone (`vectorlanes.s`, ABI
/// review a12 #1).
@Test func aVectorLaneMoveIsNoWholeMoveIfPresent() async throws {
    let path = "Fixtures/Sample/libVectorLanes.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = try #require(functions.first { $0.displayName == "_ins" }).renderStructured()
    #expect(!text.contains("= arg2"), Comment(rawValue: text))
}

/// An `fmov` immediate is encoded at its destination's precision and
/// shape: a vector one fills every lane (`fmov.2d v0, #3.0; str q0` read
/// as one Double, lane 1 zero), and an `h` register holds a Float16
/// (`fmov h1, #3.0` read as a Double's pattern rendered `0.0`)
/// (`fpimmediates.swift`, ABI review a2 #1 and #3).
@Test func anFmovImmediateIsEncodedAtItsDestinationsPrecisionIfPresent() async throws {
    let path = "Fixtures/Sample/libFPImmediates.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("FPImmediates.\(name)(") }).renderStructured()
    }
    #expect(!(try text("fill")).contains("0x4008000000000000"))
    #expect(!(try text("fillF")).contains("0x3ff8000000000000"))
    #expect(try text("half").contains("return ((arg0 * 3.0) + 0.5)"))
    #expect(try text("callHalf").contains("FPImmediates.half(1.5)"))
}

/// An integer-to-float conversion respects the source's width and
/// signedness: `scvtf d0, w0` converts the word sign-extended (read
/// zero-extended, Int32 -1 became 4294967295.0), and `ucvtf d0, x0`
/// rendered `Double(arg0)`, a signed conversion of an Int: an unsigned one
/// reads `Double(UInt(bitPattern: x))` unless x is a UInt or provably
/// non-negative (`intconvert.swift`, ABI review a2 #4).
@Test func anIntegerToFloatConversionKeepsItsSignednessIfPresent() async throws {
    let path = "Fixtures/Sample/libIntConvert.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("IntConvert.\(name)(") }).renderStructured()
    }
    #expect(try text("u2d").contains("return Double(UInt(bitPattern: arg0))"))
    #expect(try text("s32").contains("return Double((((arg0 & 0xffffffff) << 32) >>ˢ 32))"))
    #expect(try text("u32").contains("return Double((arg0 & 0xffffffff))"))
}

/// A struct, SIMD or closure parameter takes registers its type's name does
/// not give, so it and every parameter after it render `?`; the ones before
/// it keep their values (structargs.swift).
@Test func aStructParameterAndThoseAfterItAreUnplacedIfPresent() async throws {
    let path = "Fixtures/Sample/libStructArgs.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("StructArgs.\(name)(") }).renderStructured()
    }
    #expect(try text("callMix").contains("return StructArgs.fMix(?, ?)"))
    #expect(try text("callPt").contains("return StructArgs.fPt(?, ?)"))
    #expect(try text("callSIMD").contains("return StructArgs.fSIMD(?, ?)"))
    #expect(try text("callLead").contains("return StructArgs.fLead(arg0, ?)"))
    // A value type's method: its formal is unplaced, and `self`'s words,
    // which follow it, are not shown either.
    #expect(try text("callScaled").contains("return StructArgs.Pt.scaled(?)"))
    // `self`'s 9 in x2, after a Mix whose end is not known, is no argument.
    #expect(try text("callTake").contains("return StructArgs.W.take(?)\n"))
    // An Array, a Dictionary and a variadic parameter are one word each,
    // so what follows them is placed.
    #expect(try text("callArr").contains("return StructArgs.fArr(arg0, arg1)"))
    #expect(try text("callDict").contains("return StructArgs.fDict(arg0, arg1)"))
    #expect(try text("callVar").contains(", arg0)"))
}

/// `_stringCompareWithSmolCheck(_: _StringGuts, _: _StringGuts, expecting:)`
/// takes each `_StringGuts` as a String's two words and the expected result
/// as a one-byte enum: three arguments, not the five registers they fill.
@Test func aStringComparisonTakesTwoGutsAndAnExpectationIfPresent() async throws {
    let path = "Fixtures/Sample/libLargeStrings.opt.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains(#"Swift._stringCompareWithSmolCheck(?, "A literal laid out 32 bytes later", 0)"#))
    #expect(!text.contains("_stringCompareWithSmolCheck(?, ?, "))
}

/// A frozen standard-library struct's method takes `self` in x20 only as an
/// address (mutating): a scalar left there is not the view (stdself.swift).
@Test func aStandardLibraryValueMethodTakesOnlyAnAddressAsSelfIfPresent() async throws {
    let path = "Fixtures/Sample/libStdSelf.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("StdSelf.\(name)(") }).renderStructured()
    }
    let all = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(!all.contains("UTF16View.index(self:"), Comment(rawValue: all))
    #expect(!all.contains("_foreignIndex(self:"), Comment(rawValue: all))
    #expect(try text("mutate").contains("Swift.String.append(self: arg0, "))
    #expect(try text("local").contains("Swift.String.append(self: local_"))
}

/// Which standard-library methods take `self` by value (nil: not decided
/// here, x20 may be `self`; false: an instance method of a frozen struct;
/// true: static).
@Test func standardLibraryStructMethodsAreClassified() {
    #expect(Disassembler.standardLibraryStructMethod(
        "Swift.String.UTF16View.index(_: Swift.String.Index, offsetBy: Swift.Int) -> Swift.String.Index") == false)
    #expect(Disassembler.standardLibraryStructMethod("static Swift.String._fromSubstring(Swift.Substring) -> Swift.String") == true)
    #expect(Disassembler.standardLibraryStructMethod("Swift.Dictionary.init(_: Swift.Int) -> Swift.Dictionary<A, B>") == true)
    // Mutating: a declared mutating member, or a writing accessor.
    #expect(Disassembler.standardLibraryStructMethod("Swift.String.append(Swift.String) -> ()") == nil)
    #expect(Disassembler.standardLibraryStructMethod("Swift.Array.subscript.modify : (Swift.Int) -> A") == nil)
    // Hasher is passed by address: every method's x20 is `self`.
    #expect(Disassembler.standardLibraryStructMethod("Swift.Hasher._combine(Swift.UInt64) -> ()") == nil)
    // A protocol requirement and a stdlib class take `self` in x20.
    #expect(Disassembler.standardLibraryStructMethod("Swift.Collection.endIndex.getter : A.Index") == nil)
    #expect(Disassembler.standardLibraryStructMethod("Swift._DictionaryStorage.resize(original: Swift.__RawDictionaryStorage, capacity: Swift.Int, move: Swift.Bool) -> Swift._DictionaryStorage<A, B>") == nil)
}

/// A signatureless callee's floating-point argument reads count as
/// parameters: alone they are its arguments, in order and typed by the width
/// they are read at; beside integer reads the interleaving is unknown, so
/// every parameter is `?` (floatreads.c).
@Test func floatArgumentReadsCountAsParametersIfPresent() async throws {
    let path = "Fixtures/Sample/libFloatReads.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName == name }).renderStructured()
    }
    #expect(try text("_callf3").contains("takef3(?, 2.5, 4.0)"))
    #expect(try text("_callMixed").contains("mixed(?, ?, ?)"))
    #expect(try text("_callInts").contains("ints(?, 9)"))
    // d1 is written before it is read: one parameter.
    #expect(try text("_callAfterWrite").contains("afterWrite(?)\n"))
}

/// A computed narrow integer result is its register's low bits at its
/// type's signedness (narrowreturns.swift).
@Test func aComputedNarrowResultIsItsTypesLowBitsIfPresent() async throws {
    let path = "Fixtures/Sample/libNarrowReturns.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("NarrowReturns.\(name)(") }).renderStructured()
    }
    #expect(try text("add16").contains("return (((arg0 & 0xffffffff) + 72) & 0xffff)\n"))
    #expect(try text("add8").contains("return ((((arg0 & 0xffffffff) + 100) << 56) >>ˢ 56)\n"))
    #expect(try text("mul32").contains("<< 32) >>ˢ 32)\n"))
    #expect(try text("shl16").contains("return (((arg0 & 0xffffffff) << 3) & 0xffff)\n"))
    // An Int result keeps the conversion the code makes.
    #expect(try text("widen").contains("return (((arg0 & 0xffffffff) + 72) & 0xffff)\n"))
}

/// A narrow C integer argument reads at the width and signedness its SDK
/// declaration gives it (cnarrowargs.c).
@Test func aNarrowCIntegerArgumentReadsAtItsDeclaredWidthIfPresent() async throws {
    let path = "Fixtures/Sample/libCNarrowArgs.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains("close(-1)"), Comment(rawValue: text))
    #expect(text.contains("usleep(0xee6b2800)"), Comment(rawValue: text))
    #expect(text.contains("lseek(?, -5, 2)"), Comment(rawValue: text))
    #expect(DisassembledFunction.cPrototype(of: "close")?.parameters == ["w"])
}

/// A C string literal with a tab, newline or carriage return reads as the
/// literal, escaped, not as its address (cformat.c).
@Test func aCStringWithWhitespaceEscapesIsALiteralIfPresent() async throws {
    let path = "Fixtures/Sample/libCFormat.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains(#"printf("%d %hd %hhd %u %ld %c\n", "#), Comment(rawValue: text))
    #expect(text.contains(#"puts("a\tb\r\n")"#), Comment(rawValue: text))
}

/// A printf integer argument reads at the width and signedness its
/// conversion gives it (cformat.c).
@Test func aPrintfIntegerArgumentReadsAtItsConversionIfPresent() async throws {
    let path = "Fixtures/Sample/libCFormat.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains(#"printf("%d %hd %hhd %u %ld %c\n", -1, -2, -3, 0xee6b2800, -4, 65)"#), Comment(rawValue: text))
    #expect(DisassembledFunction.MessageSend.formatIntegerTypes(#""%5.2f %lu %x %s %hhu""#)
            == ["", "Swift.UInt", "Swift.UInt32", "", "Swift.UInt8"])
}
