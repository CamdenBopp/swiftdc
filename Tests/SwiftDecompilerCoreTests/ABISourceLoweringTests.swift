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
    #expect(callK.contains("return (EntryFootprints.W.k(self: arg0, arg1) + arg2)"), Comment(rawValue: callK))
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
    // Mix and Pt are laid out in full here, so what follows them is placed
    // (`aStructArgumentTakesItsFieldsRegistersIfPresent`): Mix takes x0, x1
    // and d0, so 2.0 is d1; Pt takes d0 and d1, so k is x0.
    #expect(try text("callMix").contains("return StructArgs.fMix(?, 2.0)"))
    #expect(try text("callPt").contains("return StructArgs.fPt(?, arg1)"))
    #expect(try text("callSIMD").contains("return StructArgs.fSIMD(?, ?)"))
    #expect(try text("callLead").contains("return StructArgs.fLead(arg0, ?)"))
    // A value type's method: its formal is unplaced, and `self`'s words,
    // which follow it, are not shown either.
    #expect(try text("callScaled").contains("return StructArgs.Pt.scaled(?)"))
    // The Mix ends at x1, and W is one integer word: `self`'s 9 in x2
    // follows the formal, as a value method's `self` does, and is its self.
    #expect(try text("callTake").contains("return StructArgs.W.take(self: 9, ?)\n"))
    // MD's self is an Int in x1 and a Double in d0: no part of it shows.
    #expect(try text("callMD").contains("return StructArgs.MD.f(3)\n"))
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
    #expect(text.contains(#"Swift._stringCompareWithSmolCheck(_:_:expecting:)(?, "A literal laid out 32 bytes later", 0)"#))
    #expect(!text.contains("_stringCompareWithSmolCheck(_:_:expecting:)(?, ?, "))
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

/// A specialization of a specialization keeps its original's registers only
/// when every clause does: an ownership change over a dropped parameter
/// takes the inner one's layout.
@Test func aNestedSpecializationKeepsItsLayoutOnlyIfEveryClauseDoes() {
    #expect(Disassembler.signatureSpecializationKeepsLayout(
        "function signature specialization <Arg[0] = Owned To Guaranteed> of M.f(Swift.Int, Swift.Int) -> Swift.Int"))
    #expect(!Disassembler.signatureSpecializationKeepsLayout(
        "function signature specialization <Arg[1] = Owned To Guaranteed> of function signature specialization <Arg[0] = Dead> of M.f(Swift.Int, Swift.Int) -> Swift.Int"))
    #expect(Disassembler.signatureSpecializationKeepsLayout(
        "function signature specialization <Arg[1] = Owned To Guaranteed> of function signature specialization <Arg[0] = Guaranteed To Owned> of M.f(Swift.Int, Swift.Int) -> Swift.Int"))
}

/// A closure-propagated specialization's name has an unclosed `[`; its
/// signature is still the one after `> of `, and a tail call to it for the
/// same result is a return (closprop.swift).
@Test func aClosurePropagatedSpecializationTailCallIsAReturnIfPresent() async throws {
    let path = "Fixtures/Sample/libClosProp.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    for name in ["noCapture", "captures", "capturesTwo"] {
        let text = try #require(functions.first { $0.displayName.hasPrefix("ClosProp.\(name)(") }).renderStructured()
        #expect(text.contains("    return function signature specialization <Arg[0] = [Closure Propagated"), Comment(rawValue: text))
    }
    let split = DisassembledFunction.splitSignature(
        "function signature specialization <Arg[0] = [Closure Propagated : $s1M1fyS2iFS2iXEfU_, Argument Types : [Swift.Int]> of M.apply((Swift.Int) -> Swift.Int, Swift.Int) -> Swift.Int")
    #expect(split?.result == "Swift.Int")
}

/// A generic parameter's metatype and a class's are one word; a metatype
/// slot shows only metadata (metatypeargs.swift).
@Test func aGenericOrClassMetatypeParameterIsOneWordIfPresent() async throws {
    let path = "Fixtures/Sample/libMetatypeArgs.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("MetatypeArgs.\(name)(") }).renderStructured()
    }
    // x0 still holds `k`: the callee ignores `t`, so nothing set it.
    #expect(try text("callDescribe").contains("MetatypeArgs.describe<A>(?, arg0)"))
    #expect(try text("callClassMeta").contains("MetatypeArgs.classMeta(type metadata accessor for MetatypeArgs.Base(), arg0)"))
    // A generic value-type method: `self` and then T's metadata follow the
    // formals, so nothing past them is shown. callPut's own `k` is seeded
    // after its Box (one Int word), so it reads arg1.
    #expect(try text("callPut").contains("MetatypeArgs.Box.put<A>(?, arg1)\n"))
    // A member's own parameter is named in the requirements only.
    let layout = Disassembler.swiftCallArgumentLayout(
        callee: "M.f<A where A1: Swift.Equatable>(A1.Type, Swift.Int) -> Swift.Int",
        enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex(), anyContext: false)
    #expect(layout?.slots.count == 2 && layout?.unplaced == 0)
}

/// A struct this image lays out takes the registers the Swift calling
/// convention gives its fields, so the Int after it is placed (structlowering
/// .swift; the footprints are `swiftc -emit-ir`'s, docs/ABI-INVARIANTS.md).
@Test func aStructArgumentTakesItsFieldsRegistersIfPresent() async throws {
    let path = "Fixtures/Sample/libStructLowering.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let shapes = ["S1", "S2", "S32", "SID", "SD4", "SI4", "SI5", "SB", "S8", "SNest", "SOpt", "FF", "FI32",
                  "Mixed", "I32I64I32", "F4I", "WithEmpty"]
    for shape in shapes {
        let text = try #require(functions.first { $0.displayName.hasPrefix("StructLowering.pass_\(shape)(") }).renderStructured()
        #expect(text.contains("return StructLowering.take_\(shape)(?, 7)\n"), Comment(rawValue: text))
    }
    // An empty struct has no field map here, so its footprint is not proven.
    let empty = try #require(functions.first { $0.displayName.hasPrefix("StructLowering.pass_Empty(") }).renderStructured()
    #expect(empty.contains("return StructLowering.take_Empty(?, ?)\n"), Comment(rawValue: empty))
}

/// A value method's `self` follows its formals in the receiver's own
/// registers: two Doubles for ABIVec2, in d registers, so no x register
/// after the formals is `self` (abi_source.swift, the oracle executable).
@Test func aFloatReceiversSelfIsNoIntegerWordIfPresent() async throws {
    let path = "Fixtures/Sample/abi-source-oracle"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains("ABISource.ABIVec2.dot(?)\n"), Comment(rawValue: text.components(separatedBy: "\n").filter { $0.contains("dot(") }.joined(separator: "\n")))
    #expect(!text.contains("ABIVec2.dot(?, "))
}

/// A call through a pointer loaded through another pointer is named when the
/// image's read-only bytes fix both (a value-witness table slot), and not
/// when either lies in writable memory (staticwitness.s).
@Test func aCallThroughTwoFixedPointersIsNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libStaticWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func call(_ name: String) throws -> String {
        let function = try #require(functions.first { $0.displayName == name })
        return try #require(function.instructions.first { $0.text.hasPrefix("blr") }).annotation ?? ""
    }
    #expect(try call("_callThroughWitness").contains("→ slot5"))
    #expect(try !call("_callThroughWritable").contains("→"))
    #expect(try !call("_callSlotWritable").contains("→"))
    #expect(try !call("_callTableWritable").contains("→"))
    // The same shape on a call that is no metadata accessor.
    #expect(try !call("_callAfterPlainCall").contains("→"))
}

/// A call through slot k of the value-witness table of the metadata a type
/// metadata accessor returned is that type's witness (accessorwitness.swift).
@Test func aValueWitnessCallOnAnAccessorResultIsNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libAccessorWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains("initializeWithCopy value witness for Foundation.URL("), Comment(rawValue: text))
    #expect(text.contains("destroy value witness for Foundation.URL("))
    #expect(text.contains("assignWithCopy value witness for Foundation.URL("))
    #expect(!text.contains("unresolved call"))
}

/// An unspecialized generic function receives its type parameters' metadata
/// after its formals; a call through slot k of [metadata - 8] is that
/// parameter's value witness (genericwitness.swift).
@Test func aGenericParametersValueWitnessCallIsNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libGenericWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("GenericWitness.\(name)<") }).renderStructured()
    }
    #expect(try text("load").contains("initializeWithCopy value witness for A(&result, "))
    // A value of a type parameter arrives as its address: pick's a and b
    // are arg1 and arg2, and first's T metadata (x2) precedes its U's (x3).
    #expect(try text("pick").contains("initializeWithCopy value witness for A(&result, ((arg0 > 0) ? arg1 : arg2))"))
    #expect(try text("first").contains("initializeWithCopy value witness for A(&result, arg0)"))
    // A tuple result with a generic element takes x0 and x1 for its buffers:
    // nothing is seeded, so nothing is named.
    #expect(try !text("dup").contains("value witness for"))
    // x0 is a result buffer there, not its T.
    #expect(try !text("dup").contains("arg0"))
}

/// The metadata `__swift_instantiateConcreteTypeFromMangledName(cache)`
/// returns is the type its cache variable spells (relative name address,
/// negated length), so a value-witness call on it is that type's
/// (codablewitness.swift). A V2 name pair's positive length is no cache.
@Test func aValueWitnessCallOnACacheVariablesMetadataIsNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libCodableWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains("destroy value witness for Swift.KeyedEncodingContainer<CodableWitness.Point."), Comment(rawValue: text))
    #expect(text.contains("destroy value witness for Swift.KeyedDecodingContainer<CodableWitness.Point."))
    let pairs = "Fixtures/Sample/libMangledTypes.stripped.dylib"
    guard FileManager.default.fileExists(atPath: pairs) else { return }
    let machO = try BinaryLoader.load(path: pairs)
    #expect(MangledNamePair.typeName(at: 0x1830, in: machO) != nil)
    #expect(MangledNamePair.typeName(atCacheVariable: 0x1830, in: machO) == nil)
}

/// Metadata loaded from a slot the loader binds (a GOT entry for `type
/// metadata for Swift.Int`) names the value-witness call through it; the
/// same pointer in writable data does not (gotwitness.s).
@Test func aValueWitnessCallOnGOTLoadedMetadataIsNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libGOTWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func call(_ name: String) throws -> String {
        let function = try #require(functions.first { $0.displayName == name })
        return try #require(function.instructions.first { $0.text.hasPrefix("blr") }).annotation ?? ""
    }
    #expect(try call("_copyThroughGOT").contains("→ initializeWithCopy value witness for Swift.Int"))
    #expect(try !call("_copyThroughWritable").contains("→"))
}

/// A generic class's method reads its type parameters' metadata from self's
/// isa, at the descriptor's generic-argument offset; a value-witness call on
/// one is that parameter's (classwitness.swift).
@Test func aGenericClassParametersValueWitnessCallIsNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libClassWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("ClassWitness.Holder.\(name)(") }).renderStructured()
    }
    #expect(try text("setB").contains("assignWithCopy value witness for B("))
    #expect(try text("setA").contains("assignWithCopy value witness for A("))
    // A nested class's own parameter prints as A1: no positional name.
    let setU = try #require(functions.first { $0.displayName.contains("Inner.setU(") }).renderStructured()
    #expect(!setU.contains("value witness for B"), Comment(rawValue: setU))
}

/// A callee-saved isa register retains its proven B metadata. The separate
/// A witness is spilled across probed stack allocations whose new sp is
/// itself spilled to a frame slot before the move; the probe proof holds
/// across that store, so the spill survives and the copy of `k` is named.
@Test func anIsaKeptAcrossACallNamesItsGenericArgumentsWitnessesIfPresent() async throws {
    let path = "Fixtures/Sample/libSpillWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let put = try #require(functions.first { $0.displayName.hasPrefix("SpillWitness.Store.put(") }).renderStructured()
    #expect(put.contains("getEnumTagSinglePayload value witness for B("), Comment(rawValue: put))
    // `table[k] = v` copies k, an A (Store<K, V>: K is the first argument).
    #expect(put.contains("initializeWithCopy value witness for A("), Comment(rawValue: put))
    #expect(!put.contains("indirect_call("), Comment(rawValue: put))
}

/// The probe preserves its declared registers, but an unknown later sp
/// supplies no frame-lifetime proof for calls made after allocation. A
/// spilled table cannot be named from its earlier value (chkstkwitness.swift).
@Test func aStackProbeDoesNotProveALaterDynamicStackBoundaryIfPresent() async throws {
    let path = "Fixtures/Sample/libChkstkWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let decode = try #require(functions.first { $0.displayName.contains("of ChkstkWitness.Message.init(from:") }).renderStructured()
    #expect(!decode.contains("destroy value witness for Swift.KeyedDecodingContainer<ChkstkWitness.Message.(PingCodingKeys"),
            Comment(rawValue: decode))
    // The allocation's address is no source value.
    #expect(!decode.contains("& -16"), Comment(rawValue: decode))
    #expect(decode.contains("allKeys.getter(self: ?)"), Comment(rawValue: decode))
}

/// A result-buffer store is shown by the return that renders it; when no
/// return can, it is shown as itself. `staleAfterKeyPath` stores five 7s
/// that `swift_getAtKeyPath` then overwrites, and it read only
/// `swift_getAtKeyPath(); return ?` (resultbuffer.s).
@Test func aResultStoreNoReturnRendersIsShownIfPresent() async throws {
    let path = "Fixtures/Sample/libResultBuffer.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func structured(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.contains(name) }).renderStructured()
    }
    let stale = try structured("staleAfterKeyPath")
    let store = try #require(stale.range(of: "mem64[&result] = 7"), Comment(rawValue: stale))
    let call = try #require(stale.range(of: "swift_getAtKeyPath("), Comment(rawValue: stale))
    #expect(store.lowerBound < call.lowerBound, Comment(rawValue: stale))
    let kept = try structured("keptAfterRetain")
    #expect(!kept.contains("mem64[&result"), Comment(rawValue: kept))
}

/// A value witness has its ABI signature whatever the type it serves
/// (swift/include/swift/ABI/ValueWitness.def): initializeWithCopy is `(dest,
/// src, Self)`. Laid out positionally, `pick`'s tail call through it read a
/// stale fourth argument, the metadata left in x3 (genericwitness.swift).
@Test func aValueWitnessCallTakesItsABIParametersIfPresent() async throws {
    let path = "Fixtures/Sample/libGenericWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let pick = try #require(functions.first { $0.displayName.hasPrefix("GenericWitness.pick") })
    let call = try #require(pick.instructions.first { ($0.annotation ?? "").contains("initializeWithCopy value witness for A") })
    let note = call.annotation ?? ""
    let start = try #require(note.range(of: "args("))
    #expect(String(note[start.lowerBound...]) == "args(&result, ((arg0 > 0) ? arg1 : arg2), type metadata for A)", Comment(rawValue: note))
    let arity = DisassembledFunction.valueWitnessArity
    #expect(arity["destroy"] == 2 && arity["initializeWithCopy"] == 3 && arity["storeEnumTagSinglePayload"] == 4)
    #expect(arity["getEnumTag"] == 2 && arity["destructiveInjectEnumTag"] == 3)
    #expect(DisassembledFunction.knownCArity(of: "destroy value witness for Swift.Optional") == 2)
    #expect(DisassembledFunction.knownCArity(of: "getEnumTagSinglePayload value witness for B") == 3)
}

/// A generic class that inherits from Objective-C masks its isa with
/// swift_isaMask before reading its metadata; the masked isa is its class
/// metadata, so a witness call on its generic argument is named
/// (isamask.swift).
@Test func aMaskedIsaIsTheClassMetadataIfPresent() async throws {
    let path = "Fixtures/Sample/libIsaMask.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let set = try #require(functions.first { $0.displayName.hasPrefix("IsaMask.Box.set(") }).renderStructured()
    #expect(set.contains("assignWithCopy value witness for A("), Comment(rawValue: set))
}

/// A generic class's method calls a requirement of its parameter's
/// conformance through the witness table among self's generic arguments:
/// word N+1 of the table is requirement N, named by its method descriptor
/// symbol (classprotowitness.swift). The call takes the requirement's
/// dispatch-thunk layout, so x0 and x1 (Self's metadata and the table) are
/// no arguments. Declined: a table reached through a base-protocol slot, a
/// protocol from another image, and a fragile build with no method
/// descriptor symbols.
@Test func aProtocolWitnessCallOnAClassParameterIsNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libClassProtoWitness.dylib"
    let fragilePath = "Fixtures/Sample/libClassProtoWitness.fragile.dylib"
    guard FileManager.default.fileExists(atPath: path), FileManager.default.fileExists(atPath: fragilePath) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("ClassProtoWitness.\(name)(") }).renderStructured()
    }
    let reading = try text("Gauge.reading")
    #expect(reading.contains("ClassProtoWitness.Meter.reading() witness for A()"), Comment(rawValue: reading))
    let scaled = try text("Gauge.scaled")
    #expect(scaled.contains("ClassProtoWitness.Meter.scaled(by:) witness for A(arg0)"), Comment(rawValue: scaled))
    let label = try text("Gauge.label")
    #expect(label.contains("ClassProtoWitness.Meter.label.getter witness for A()"), Comment(rawValue: label))
    // `m.level += 1` calls level.modify, a coroutine, through word 7.
    let bump = try text("Gauge.bump")
    #expect(!namesARequirementWitness(bump), Comment(rawValue: bump))
    // A requirement whose parameters are not placed reads none by position.
    let split = try text("Gauge.split")
    #expect(split.contains("ClassProtoWitness.Meter.split(_:) witness for A(…)"), Comment(rawValue: split))
    // B's table follows A's and B's metadata.
    let pair = try text("Pair.reading")
    #expect(pair.contains("ClassProtoWitness.Meter.reading() witness for B()"), Comment(rawValue: pair))
    // Precise's requirement 1 (requirement 0 is its base protocol).
    let error = try text("Lab.error")
    #expect(error.contains("ClassProtoWitness.Precise.error() witness for A()"), Comment(rawValue: error))
    // Meter's requirement reached through Precise's base-protocol slot.
    let labReading = try text("Lab.reading")
    #expect(!namesARequirementWitness(labReading), Comment(rawValue: labReading))
    // Hashable lives in another image.
    let hash = try text("Keyed.hash")
    #expect(!namesARequirementWitness(hash), Comment(rawValue: hash))
    let fragile = try await withStableDependencies { try await Disassembler().disassemble(path: fragilePath) }
    let fragileReading = try #require(fragile.first { $0.displayName.hasPrefix("ClassProtoWitness.Gauge.reading(") })
        .renderStructured()
    #expect(!namesARequirementWitness(fragileReading), Comment(rawValue: fragileReading))
}

/// A witness-table word names a requirement only when the descriptor's own
/// bytes and its symbols agree: Meter's requirements are reading, scaled,
/// label.getter, fetch (async), level.getter, level.setter, level.modify, split,
/// words 1-8 (classprotowitness.swift). Each guard is checked against a
/// symbol that would otherwise pass: an async requirement or a coroutine
/// given a plain method's name, a word past the count, a requirement of
/// another protocol, two symbols at one address.
@Test func aProtocolRequirementIsReadFromItsDescriptorIfPresent() throws {
    let path = "Fixtures/Sample/libClassProtoWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let protocolSymbol = try #require(machO.symbols.first { $0.name == "_$s17ClassProtoWitness5MeterMp" })
    let meter = UInt64(protocolSymbol.offset)
    func word(_ n: UInt64) -> UInt64 { meter + 24 + 8 * (n - 1) }
    let owner = "protocol descriptor for ClassProtoWitness.Meter"
    let method = "method descriptor for ClassProtoWitness.Meter."
    func resolver(_ symbols: [UInt64: [String]]) -> Disassembler.ReferenceResolver {
        var resolver = Disassembler.ReferenceResolver(names: [:], stringRanges: [], machO: machO, demangleSymbol: { _ in nil })
        resolver.protocolDescriptorSymbols = symbols.merging([meter: [owner]]) { $1 }
        return resolver
    }
    let real = resolver([word(1): [method + "reading() -> Swift.Int"], word(3): [method + "label.getter : Swift.Int"]])
    #expect(real.protocolRequirement(descriptor: meter, word: 1)?.name == "ClassProtoWitness.Meter.reading()")
    #expect(real.protocolRequirement(descriptor: meter, word: 1)?.signature == "ClassProtoWitness.Meter.reading() -> Swift.Int")
    #expect(real.protocolRequirement(descriptor: meter, word: 3)?.name == "ClassProtoWitness.Meter.label.getter")
    // A word with no symbol.
    #expect(real.protocolRequirement(descriptor: meter, word: 2) == nil)
    // fetch is async (flags 0x20), level.modify a coroutine (kind 6).
    let plain = resolver([word(4): [method + "fetch() -> Swift.Int"], word(7): [method + "level.getter : Swift.Int"]])
    #expect(plain.protocolRequirement(descriptor: meter, word: 4) == nil)
    #expect(plain.protocolRequirement(descriptor: meter, word: 7) == nil)
    // Past NumRequirements (8): word 9 is Precise's descriptor, whose flags (0x...43) read as a getter.
    let precise = try #require(machO.symbols.first { $0.name == "_$s17ClassProtoWitness7PreciseMp" })
    #expect(word(9) == UInt64(precise.offset))
    let past = resolver([word(9): [method + "reading() -> Swift.Int"]])
    #expect(past.protocolRequirement(descriptor: meter, word: 9) == nil)
    // Another protocol's requirement, and two symbols at one address.
    let other = resolver([word(1): ["method descriptor for ClassProtoWitness.Precise.error() -> Swift.Int"]])
    #expect(other.protocolRequirement(descriptor: meter, word: 1) == nil)
    let two = resolver([word(1): [method + "reading() -> Swift.Int", method + "scaled(by: Swift.Int) -> Swift.Int"]])
    #expect(two.protocolRequirement(descriptor: meter, word: 1) == nil)
    // Word 0 is the conformance descriptor.
    #expect(real.protocolRequirement(descriptor: meter, word: 0) == nil)
}

/// A generic class's key witness tables follow its parameters' metadata,
/// one per key conformance requirement, each for the parameter its
/// requirement names (classprotowitness.swift). A conformance to a protocol
/// in another image is reached through a bind (the relative pointer's
/// indirect bit) and has no in-image descriptor.
@Test func aGenericClassesKeyWitnessTablesAreIndexedIfPresent() throws {
    let path = "Fixtures/Sample/libClassProtoWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let meter = try #require(machO.symbols.first { $0.name == "_$s17ClassProtoWitness5MeterMp" })
    let index = VTableIndex.build(in: machO)
    // Gauge<A: Meter>: A at 0x50, A's Meter table at 0x58.
    #expect(index.genericParameter(type: "Gauge", offset: 0x50) == "A")
    let gauge = try #require(index.witnessTable(type: "Gauge", offset: 0x58))
    #expect(gauge.parameter == "A" && gauge.protocolDescriptor == UInt64(meter.offset))
    #expect(index.witnessTable(type: "Gauge", offset: 0x50) == nil)
    #expect(index.witnessTable(type: "Gauge", offset: 0x60) == nil)
    // Pair<A, B: Meter>: the table at 0x60 is B's.
    let pair = try #require(index.witnessTable(type: "Pair", offset: 0x60))
    #expect(pair.parameter == "B" && pair.protocolDescriptor == UInt64(meter.offset))
    // Keyed<A: Swift.Hashable>: indexed, but its table's protocol is not here.
    #expect(index.genericParameter(type: "Keyed", offset: 0x50) == "A")
    #expect(index.witnessTable(type: "Keyed", offset: 0x58) == nil)
}

/// Whether a render names a call through a protocol witness table (a value
/// witness's name also ends `witness for A`).
private func namesARequirementWitness(_ text: String) -> Bool {
    text.split(separator: "\n").contains { $0.contains(" witness for ") && !$0.contains(" value witness for ") }
}

/// A requirement's name keeps its argument labels and drops its types.
@Test func aProtocolRequirementNameKeepsOnlyItsLabels() {
    typealias R = Disassembler.ReferenceResolver
    #expect(R.requirementName("M.P.scaled(by: Swift.Int) -> Swift.Int") == "M.P.scaled(by:)")
    #expect(R.requirementName("M.P.reading() -> Swift.Int") == "M.P.reading()")
    #expect(R.requirementName("M.P.add(Swift.Int, to: [Swift.String : Swift.Int]) -> ()") == "M.P.add(_:to:)")
    #expect(R.requirementName("M.P.send<A where A1: Swift.Encodable>(A1) throws -> ()") == "M.P.send(_:)")
    #expect(R.requirementName("M.P.label.getter : Swift.Int") == "M.P.label.getter")
    #expect(R.requirementName("M.P.subscript.getter : (Swift.Int) -> Swift.Int") == nil)
    #expect(R.requirementName("M.P.label.modify : Swift.Int") == nil)
}

/// Self's isa loaded before a loop whose body calls is still self's isa
/// after it: the loop header joins the field read (entry) with its snapshot
/// (back edge), and self stays in x20 on both (loopisa.swift).
@Test func selfsIsaSurvivesALoopHeaderIfPresent() async throws {
    let path = "Fixtures/Sample/libLoopIsa.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let run = try #require(functions.first { $0.displayName.hasPrefix("LoopIsa.Listener.run(") }).renderStructured()
    // The witness call may decline when the loop's calls may clobber x29
    // and the frame escapes; it never names another witness.
    #expect(!run.contains("witness for A()") || run.contains("LoopIsa.Link.close() witness for A()"), Comment(rawValue: run))
}

/// The same join, as machine code: `ldr x22, [x20]; loop: bl; mov x?, x0;
/// cbnz w0, loop; ldr x1, [x22, #0x58]; ldr x9, [x1, #8]; blr x9`.
/// - x19 written in the body: self stays in x20, and x22 is its isa at the
///   call.
/// - x20 written: self is not the same on both paths into the header, and
///   the join claims nothing about x22.
/// - x22 written: the back edge brings a call's result, not the isa.
/// - x20 written after self was spilled (`sub sp, sp, #0x10; str x20,
///   [sp]`): the frame slot holds self on both paths, so x22 is its isa.
@Test func aLoopHeaderKeepsSelfsIsaOnlyWhileSelfIsUnchanged() throws {
    let engine = try #require(CapstoneEngine())
    let isaTable = AbstractValue.loadedFrom(.selfVTableMethod(offset: 0x58), offset: 8)
    func target(_ words: [UInt32], call: UInt64) -> AbstractValue? {
        let bytes = words.flatMap { word in (0 ..< 4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
        let decoded = engine.disassemble(Data(bytes), address: 0x1000)
        let function = DisassembledFunction(
            symbol: "loop", demangledName: nil, startAddress: 0x1000,
            instructions: decoded.map { insn in
                Instruction(address: insn.address, text: insn.text, annotation: nil, controlFlow: insn.controlFlow,
                            branchTarget: insn.controlFlow == .call ? nil : insn.branchTarget, detail: insn.detail)
            }, source: .address)
        return ValueTracer().analyze(function, entry: .swiftInstance(scalarArguments: [:]))
            .indirectControlFlowTargets[call]
    }
    func loop(writing register: UInt32) -> AbstractValue? {
        target([0xF940_0296, 0x9400_003F, 0xAA00_03E0 | register, 0x35FF_FFC0,
                0xF940_2EC1, 0xF940_0429, 0xD63F_0120, 0xD65F_03C0], call: 0x1018)
    }
    #expect(loop(writing: 19) == isaTable)
    #expect(loop(writing: 20) != isaTable)
    // `ldr x22, [x20]; L: bl; cbz w0, exit; mov x?, x0; b L; exit: …`: the
    // loop leaves from its header, whose x22 joins the entry's isa with
    // what the back edge brings.
    func exitLoop(writing register: UInt32) -> AbstractValue? {
        target([0xF940_0296, 0x9400_003F, 0x3400_0060, 0xAA00_03E0 | register, 0x17FF_FFFD,
                0xF940_2EC1, 0xF940_0429, 0xD63F_0120, 0xD65F_03C0], call: 0x101C)
    }
    #expect(exitLoop(writing: 19) == isaTable)
    #expect(exitLoop(writing: 22) != isaTable)
    let spilled = target([0xD100_43FF, 0xF900_03F4, 0xF940_0296, 0x9400_003D, 0xAA00_03F4, 0x35FF_FFC0,
                          0xF940_2EC1, 0xF940_0429, 0xD63F_0120, 0x9100_43FF, 0xD65F_03C0], call: 0x1020)
    #expect(spilled == isaTable)
}

/// A generic function receives each type parameter's metadata and then one
/// witness table per protocol requirement, after its formals; a call
/// through word k+1 of one is requirement k of its protocol
/// (funcprotowitness.swift). Declined: a table after an @objc protocol's
/// requirement, which takes none, so the count does not place it.
@Test func aGenericFunctionsWitnessTableCallIsNamedIfPresent() async throws {
    let path = "Fixtures/Sample/libFuncProtoWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func text(_ name: String) throws -> String {
        try #require(functions.first { $0.displayName.hasPrefix("FuncProtoWitness.\(name)<") }).renderStructured()
    }
    let feed = try text("feed")
    #expect(feed.contains("FuncProtoWitness.Sink.put(_:) witness for A(arg1)"), Comment(rawValue: feed))
    #expect(feed.contains("return FuncProtoWitness.Sink.level.getter witness for A()"), Comment(rawValue: feed))
    let pair = try text("pair")
    #expect(pair.contains("FuncProtoWitness.Sink.put(_:) witness for A(1)")
            && pair.contains("FuncProtoWitness.Sink.put(_:) witness for B(2)"), Comment(rawValue: pair))
    let both = try text("both")
    #expect(both.contains("FuncProtoWitness.Tap.tap() witness for A()")
            && both.contains("FuncProtoWitness.Sink.put(_:) witness for A(3)"), Comment(rawValue: both))
    let unit = try text("unitOf")
    #expect(unit.contains("static FuncProtoWitness.Sink.unit.getter witness for A()"), Comment(rawValue: unit))
    let hashed = try text("hashed")
    #expect(hashed.contains("FuncProtoWitness.Sink.put(_:) witness for A(4)"), Comment(rawValue: hashed))
    let anyObject = try text("anyObject")
    #expect(anyObject.contains("FuncProtoWitness.Sink.put(_:) witness for A(8)"), Comment(rawValue: anyObject))
    // A.Item's Sink table is not a parameter's.
    let deep = try text("deep")
    #expect(deep.contains("FuncProtoWitness.Holder.item.getter witness for A()")
            && !deep.contains("Sink.put"), Comment(rawValue: deep))
    for name in ["mixed", "mixedTap", "feedBox", "based"] {
        let declined = try text(name)
        #expect(!namesARequirementWitness(declined), Comment(rawValue: declined))
    }
}

/// Where the tables are, from the signature and the formals. Each assumes a
/// table for every protocol requirement before it (the naming proves that
/// by descriptor). A class instance built from a parameter is a metadata
/// source, and a superclass requirement is declined.
@Test func aGenericFunctionsWitnessTableRegistersFollowItsMetadataIfPresent() async throws {
    let path = "Fixtures/Sample/libFuncProtoWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func tables(_ name: String) throws -> [String: Int] {
        let function = try #require(functions.first { $0.displayName.hasPrefix("FuncProtoWitness.\(name)<") })
        let metadata = Disassembler.genericMetadataRegisters(
            of: function, enumCaseIndex: EnumCaseIndex(), classTypeIndex: ClassTypeIndex(), fieldMaps: [:])
        return Disassembler.genericWitnessTableRegisters(of: function, metadata: metadata)
    }
    #expect(try tables("feed") == ["x3": 0])
    #expect(try tables("pair") == ["x4": 0, "x5": 1])
    #expect(try tables("both") == ["x2": 0, "x3": 1])
    #expect(try tables("unitOf") == ["x2": 0])
    #expect(try tables("hashed") == ["x2": 0, "x3": 1])
    #expect(try tables("mixedTap") == ["x2": 0, "x3": 1, "x4": 2])
    #expect(try tables("based") == [:])
    #expect(try tables("anyObject") == ["x2": 0])
    #expect(try tables("deep") == ["x2": 0, "x3": 1])
    // feedBox's Box<A> is laid out as one word, so its metadata map is
    // complete; the formal is a source and declines it.
    let feedBox = try #require(functions.first { $0.displayName.hasPrefix("FuncProtoWitness.feedBox<") })
    let metadata = ["x1": "A"]
    #expect(Disassembler.genericWitnessTableRegisters(of: feedBox, metadata: metadata) == [:])
    // Metadata not in consecutive registers proves no place.
    let pair = try #require(functions.first { $0.displayName.hasPrefix("FuncProtoWitness.pair<") })
    #expect(Disassembler.genericWitnessTableRegisters(of: pair, metadata: ["x2": "A", "x4": "B"]) == [:])
}

/// A generic function passes one metadata argument per parameter only when
/// no formal or requirement supplies or removes one. Counting parameters
/// otherwise names the wrong one: `keep<A, B>(Box<A>, B)` has B's metadata
/// in x2, and copying its `u` read `initializeWithCopy value witness for A`
/// (metadatasource.swift, each register read from the listing).
@Test func aGenericFunctionsMetadataIsNotCountedPastASourceIfPresent() async throws {
    let path = "Fixtures/Sample/libMetadataSource.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    func function(_ name: String) throws -> DisassembledFunction {
        try #require(functions.first { $0.displayName.hasPrefix("MetadataSource.\(name)<") })
    }
    // Nothing is missing: the name is the parameter's.
    for (name, parameter) in [("plain", "B"), ("optional", "B"), ("inoutBox", "B"), ("array", "B"),
                              ("plainBound", "B"), ("sameMember", "C")] {
        let text = try function(name).renderStructured()
        #expect(text.contains("initializeWithCopy value witness for \(parameter)("), Comment(rawValue: text))
    }
    // A parameter's metadata is not passed: no name by position.
    for name in ["keep", "nested", "owned", "bound", "sameParam", "sameConcrete"] {
        let text = try function(name).renderStructured()
        #expect(!text.contains(" value witness for "), Comment(rawValue: text))
    }
    // Declined by the layout today, and by the signature whatever it does.
    for name in ["classType", "tupled"] {
        #expect(try !Disassembler.passesEveryGenericMetadata(symbol: function(name).symbol), Comment(rawValue: name))
    }
    // A closure, escaping or not, supplies nothing.
    for name in ["closure", "escaping"] {
        #expect(try Disassembler.passesEveryGenericMetadata(symbol: function(name).symbol), Comment(rawValue: name))
    }
}

/// A protocol descriptor's name is a direct relative pointer to a C string,
/// which may start at an odd address; only its parent field is indirectable.
/// ExistentialWitness.Shape's name offset is odd, and reading every field as
/// indirectable gave its requirements no shape at all.
@Test func aRequirementShapeReadsAnOddNameOffsetIfPresent() throws {
    let path = "Fixtures/Sample/libExistentialWitness.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let symbol = try #require(machO.symbols.first { $0.name == "_$s18ExistentialWitness5ShapeMp" })
    let shape = UInt64(symbol.offset)
    let base = try #require(machO.fileOffset(of: shape).map(Int.init))
    let nameOffset = try #require(UnrecordedTypes.read(base + 8, as: Int32.self, in: machO))
    #expect(nameOffset & 1 == 1, "the fixture no longer exercises an odd name offset")
    var resolver = Disassembler.ReferenceResolver(names: [:], stringRanges: [], machO: machO, demangleSymbol: { _ in nil })
    resolver.protocolDescriptorSymbols = [shape: ["protocol descriptor for ExistentialWitness.Shape"]]
    let area = try #require(resolver.protocolRequirementShape(descriptor: shape, word: 1))
    #expect(area.protocolName == "ExistentialWitness.Shape" && area.index == 0 && area.kind == "method")
    let scale = try #require(resolver.protocolRequirementShape(descriptor: shape, word: 2))
    #expect(scale.index == 1 && scale.kind == "method")
}
