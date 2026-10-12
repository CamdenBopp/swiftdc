import Testing
import Foundation
@testable import SwiftDecompilerCore
import MachOKit

/// Async funclet recovery, driven by `Fixtures/Sample/libAsyncFns*.dylib`
/// (build with `Fixtures/Sample/build.sh`; these skip when absent, like every
/// other `…IfPresent` test).
///
/// The oracle is the **symbol table of the unstripped build**: the compiler
/// names each resume funclet `<parent>TQ<n>_` (await return) or `<parent>TY<n>_`
/// (executor-hop continuation), so the parent, the ordinal and the kind of
/// every funclet are known independently of anything swiftdc computes. The
/// stripped build has none of those symbols; the grouping there must match the
/// unstripped one address for address.

private let debugFixture = "Fixtures/Sample/libAsyncFns.dylib"
private let optFixture = "Fixtures/Sample/libAsyncFns.opt.dylib"
private let strippedFixture = "Fixtures/Sample/libAsyncFns.opt.stripped.dylib"

/// Every async funclet according to the symbol table, keyed by address:
/// the entry symbol it belongs to, its 1-based ordinal, and its kind
/// (nil for an entry funclet).
private struct SymbolFunclet: Equatable {
    let parentSymbol: String
    let ordinal: Int
    let kind: AsyncResumeKind?
}

private func symbolTableFunclets(_ path: String) throws -> [UInt64: SymbolFunclet]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let machO = try BinaryLoader.load(path: path)
    var byAddress: [UInt64: SymbolFunclet] = [:]
    var entryBySymbol: [String: UInt64] = [:]
    for symbol in machO.symbols where symbol.offset > 0 {
        let name = symbol.name
        // `…YaF` / `…YaKF`: an async (throwing) function's entry funclet.
        if name.hasSuffix("YaF") || name.hasSuffix("YaKF") {
            entryBySymbol[name] = UInt64(symbol.offset)
            byAddress[UInt64(symbol.offset)] = SymbolFunclet(parentSymbol: name, ordinal: 0, kind: nil)
        }
    }
    for symbol in machO.symbols where symbol.offset > 0 {
        let name = symbol.name
        guard let range = name.range(of: #"T([QY])(\d+)_$"#, options: .regularExpression) else { continue }
        let suffix = name[range]
        let parent = String(name[..<range.lowerBound])
        let kind: AsyncResumeKind = suffix.hasPrefix("TQ") ? .awaitReturn : .continuation
        let digits = suffix.dropFirst(2).dropLast()
        guard let index = Int(digits), entryBySymbol[parent] != nil else { continue }
        byAddress[UInt64(symbol.offset)] = SymbolFunclet(parentSymbol: parent, ordinal: index + 1, kind: kind)
    }
    return byAddress
}

private func disassemble(_ path: String, filter: String? = nil) async throws -> [DisassembledFunction]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    return try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path, functionFilter: filter)
    }
}

// MARK: - Grouping against the symbol-table oracle

@Test(arguments: [debugFixture, optFixture])
func groupsFuncletsAsTheSymbolTableDoesIfPresent(path: String) async throws {
    guard let expected = try symbolTableFunclets(path),
          let functions = try await disassemble(path)
    else { return }
    // The fixture must actually exhibit the shapes under test, or this proves
    // nothing: 8 async functions, 5 await-return and 2 continuation funclets.
    #expect(expected.values.filter { $0.ordinal == 0 }.count == 8)
    #expect(expected.values.filter { $0.kind == .awaitReturn }.count == 5)
    #expect(expected.values.filter { $0.kind == .continuation }.count == 2)

    let byAddress = Dictionary(functions.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
    let symbolOf = Dictionary(functions.map { ($0.startAddress, $0.symbol) }, uniquingKeysWith: { a, _ in a })
    for (address, oracle) in expected {
        let info = byAddress[address]?.asyncFunclet
        #expect(info != nil, "0x\(String(address, radix: 16)) (\(oracle.parentSymbol)) was not recognised as an async funclet")
        guard let info else { continue }
        #expect(info.ordinal == oracle.ordinal, "0x\(String(address, radix: 16)): ordinal \(info.ordinal), symbol says \(oracle.ordinal)")
        #expect(info.kind == oracle.kind, "0x\(String(address, radix: 16)): kind \(String(describing: info.kind)), symbol says \(String(describing: oracle.kind))")
        #expect(info.parent.flatMap { symbolOf[$0] } == oracle.parentSymbol,
                "0x\(String(address, radix: 16)): parent \(String(describing: info.parent)), symbol says \(oracle.parentSymbol)")
        // The chain lists every funclet of the parent, entry first, in order.
        let siblings = expected.filter { $0.value.parentSymbol == oracle.parentSymbol }
            .sorted { $0.value.ordinal < $1.value.ordinal }.map(\.key)
        #expect(info.chain == siblings)
    }
    // Nothing else is grouped: the synchronous controls and the enum's
    // synthesized conformances stay ordinary functions.
    let grouped = functions.filter { $0.asyncFunclet != nil }.map(\.startAddress)
    #expect(Set(grouped) == Set(expected.keys))
    #expect(functions.contains { $0.displayName.hasPrefix("AsyncFns.syncCaller") && $0.asyncFunclet == nil })
}

/// A symbol-named funclet keeps its own (demangled) name; grouping is only
/// attached, never used to overwrite a proven name.
@Test func keepsSymbolNamesOnUnstrippedFuncletsIfPresent() async throws {
    guard let functions = try await disassemble(optFixture) else { return }
    let resumes = functions.filter { $0.asyncFunclet?.isEntry == false }
    #expect(resumes.count == 7)
    for resume in resumes {
        #expect(resume.source == .symbol)
        #expect(resume.displayName.contains("resume partial function for"))
    }
}

// MARK: - Stripped: no symbols, same grouping

@Test func groupsStrippedFuncletsIdenticallyIfPresent() async throws {
    guard let oracle = try symbolTableFunclets(optFixture),
          let stripped = try await disassemble(strippedFixture)
    else { return }
    // Every function LC_FUNCTION_STARTS declares is still recovered (the
    // empty-result rule's oracle); grouping must not lose or merge any.
    let machO = try BinaryLoader.load(path: strippedFixture)
    #expect(stripped.count == Disassembler(preset: .default).declaredFunctionCount(in: machO))
    #expect(stripped.count == 35)

    let byAddress = Dictionary(stripped.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
    for (address, expected) in oracle where expected.ordinal > 0 {
        guard let function = byAddress[address] else {
            Issue.record("0x\(String(address, radix: 16)) missing from the stripped listing")
            continue
        }
        let info = function.asyncFunclet
        #expect(info?.ordinal == expected.ordinal)
        #expect(info?.kind == expected.kind)
        // `strip -x` keeps the exported entry symbols, so the parent is named and
        // the nameless resume funclet is titled after it.
        #expect(function.source == .asyncFunclet)
        #expect(function.displayName.hasPrefix("resume #\(expected.ordinal) of AsyncFns."),
                "\(function.displayName)")
    }
    // The synchronous functions are untouched.
    #expect(stripped.filter { $0.asyncFunclet != nil }.count == 15)
}

/// `--function` on a stripped binary brings the whole chain: the resume
/// funclets have no name of their own to match, but they are the function.
@Test func filterIncludesTheWholeChainIfPresent() async throws {
    guard let matched = try await disassemble(strippedFixture, filter: "twoAwaits") else { return }
    #expect(matched.map { $0.asyncFunclet?.ordinal } == [0, 1, 2])
    #expect(matched.map(\.displayName) == [
        "AsyncFns.twoAwaits(Swift.Int) async -> Swift.Int",
        "resume #1 of AsyncFns.twoAwaits(Swift.Int) async -> Swift.Int",
        "resume #2 of AsyncFns.twoAwaits(Swift.Int) async -> Swift.Int",
    ])
    // The title a nameless resume funclet is given is itself matchable, even
    // though no symbol or metadata name exists at that address.
    guard let byTitle = try await disassemble(strippedFixture, filter: "resume #2 of AsyncFns.twoAwaits") else { return }
    #expect(byTitle.map(\.startAddress) == [0xa98])
}

/// The rendered headers place each funclet in its chain, in every renderer.
@Test func rendersChainHeadersIfPresent() async throws {
    guard let matched = try await disassemble(strippedFixture, filter: "onMainAwait") else { return }
    #expect(matched.count == 3)
    guard matched.count == 3 else { return }
    let pseudo = matched.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(pseudo.contains("// async function: 2 resume funclet(s): resume #1 @0xd74, resume #2 @0xde0"))
    #expect(pseudo.contains("// resume #1 of the async function @0xd10: entered when the await in 0xd10 returns"))
    #expect(pseudo.contains("// resume #2 of the async function @0xd10: entered after the executor hop in 0xd74"))
    let asm = matched[1].render()
    #expect(asm.contains("[titled from its async parent; boundary from LC_FUNCTION_STARTS]"))
    let structured = matched[2].renderStructured()
    #expect(structured.contains("entered after the executor hop in 0xd74"))
    let json = matched.jsonString()
    #expect(json.contains("\"source\" : \"async-funclet\""))
    #expect(json.contains("\"kind\" : \"continuation\""))
}

// MARK: - The code-only fallback (no hint sections)

/// Without `__swift_as_*` sections the index must still recover the same chains
/// from the resume-pointer stores alone, and must not group anything else.
@Test func fallbackMatchesTheHintSectionsIfPresent() async throws {
    guard let oracle = try symbolTableFunclets(optFixture),
          let functions = try await disassemble(optFixture)
    else { return }
    let byStart = Dictionary(functions.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
    let index = AsyncFuncletIndex.build(
        hints: nil,
        functionStarts: Set(functions.map(\.startAddress)),
        instructions: { byStart[$0]?.instructions ?? [] },
        nameOf: { address in
            byStart[address]?.displayName
                ?? functions.lazy.flatMap(\.instructions)
                    .first { $0.branchTarget == address }
                    .flatMap { DisassembledFunction.calleeName(of: $0) }
        }
    )
    #expect(!index.hintSectionsPresent)
    // An async function with no suspension point leaves no trace in code (no
    // resume pointer, no context allocation), so the fallback cannot know it is
    // async. Everything with a chain must be recovered exactly.
    let leafEntries = Set(oracle.filter { entry in
        entry.value.ordinal == 0 && !oracle.values.contains { $0.ordinal > 0 && $0.parentSymbol == entry.value.parentSymbol }
    }.keys)
    #expect(leafEntries.count == 3)
    #expect(Set(index.funclets.keys) == Set(oracle.keys).subtracting(leafEntries))
    for (address, expected) in oracle where !leafEntries.contains(address) {
        let funclet = index.funclets[address]
        #expect(funclet?.ordinal == expected.ordinal, "0x\(String(address, radix: 16))")
        #expect(funclet?.kind == expected.kind, "0x\(String(address, radix: 16))")
    }
    #expect(index.orphans.isEmpty)
}

/// A declared resume funclet that nothing materialises is reported as an
/// orphan: grouped under no parent, never attached by guesswork.
@Test func declaredFuncletWithoutAPredecessorIsAnOrphanIfPresent() async throws {
    guard let functions = try await disassemble(optFixture) else { return }
    let byStart = Dictionary(functions.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
    guard let sync = functions.first(where: { $0.displayName.hasPrefix("AsyncFns.syncNeighbour") }),
          let entry = functions.first(where: { $0.displayName.hasPrefix("AsyncFns.oneAwait") })
    else { return }
    var hints = AsyncFuncletIndex.HintSections()
    hints.entries = [entry.startAddress]
    hints.awaitReturns = [sync.startAddress]   // declared, but no funclet stores its address
    let index = AsyncFuncletIndex.build(
        hints: hints, functionStarts: Set(byStart.keys),
        instructions: { byStart[$0]?.instructions ?? [] },
        nameOf: { byStart[$0]?.displayName }
    )
    #expect(index.orphans == [sync.startAddress])
    #expect(index.funclets[sync.startAddress]?.parent == nil)
    #expect(index.chains[entry.startAddress] == [entry.startAddress])
}

// MARK: - Callee names: effect specifiers are not part of the name

@Test func stripsEffectSpecifiersFromCalleeNames() {
    #expect(DisassembledFunction.strippedCallee("AsyncFns.fetchValue(Swift.Int) async -> Swift.Int") == "AsyncFns.fetchValue")
    #expect(DisassembledFunction.strippedCallee("AsyncFns.fetchOrThrow(Swift.Int) async throws -> Swift.Int") == "AsyncFns.fetchOrThrow")
    #expect(DisassembledFunction.strippedCallee("main.mayThrow(Swift.Int) throws -> Swift.Int") == "main.mayThrow")
    #expect(DisassembledFunction.strippedCallee("m.f(Swift.Int) throws(m.E) -> Swift.Int") == "m.f")
    // Unchanged shapes: a plain function, and a name with no parameter list.
    #expect(DisassembledFunction.strippedCallee("m.g(Swift.Int) -> Swift.Int") == "m.g")
    #expect(DisassembledFunction.strippedCallee("swift_task_alloc") == "swift_task_alloc")
    // A function-typed parameter's arrow is not the signature's (measured in
    // libswift_Concurrency: 3 calls rendered with a cut-off parameter list).
    #expect(DisassembledFunction.strippedCallee(
        "merged Swift.AsyncCompactMapSequence.Iterator.init(_: A.AsyncIterator, transform: "
            + "(A.Element) async -> Swift.Optional<B>) -> Swift.AsyncCompactMapSequence<A, B>.Iterator")
        == "merged ….init")  // a merged body names no one type (MergedCallNameTests)
    #expect(DisassembledFunction.strippedCallee("m.apply(_: (Swift.Int) -> Swift.Int) -> ()") == "m.apply")
}

@Test func rendersAsyncCalleesWithoutTheSpecifierIfPresent() async throws {
    guard let functions = try await disassemble(optFixture, filter: "oneAwait") else { return }
    let pseudo = functions.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(pseudo.contains("AsyncFns.fetchValue(arg0)"))
    #expect(!pseudo.contains("async("))
}

// MARK: - Async context bookkeeping is lowering, not source

@Test func hidesAsyncContextBookkeepingIfPresent() async throws {
    guard let functions = try await disassemble(strippedFixture) else { return }
    // The fixture must contain the calls for the test to mean anything.
    let calls = functions.flatMap(\.instructions).compactMap { DisassembledFunction.calleeName(of: $0) }
    #expect(calls.filter { $0 == "swift_task_alloc" }.count == 5)
    #expect(calls.filter { $0 == "swift_task_dealloc" }.count == 5)
    let pseudo = functions.map { $0.renderPseudo() }.joined(separator: "\n")
    #expect(!pseudo.contains("swift_task_alloc"))
    #expect(!pseudo.contains("swift_task_dealloc"))
    // Hidden only under `hideRuntime`, like the ARC calls.
    let raw = functions.map { $0.renderPseudo(hideRuntime: false) }.joined(separator: "\n")
    #expect(raw.contains("swift_task_alloc"))
}

// MARK: - Awaits, async returns, and context slots (exact output, -O stripped)

private func structured(_ path: String, _ filter: String) async throws -> String? {
    guard let functions = try await disassemble(path, filter: filter) else { return nil }
    return functions.map { $0.renderStructured() }.joined(separator: "\n")
}

/// The whole chain of `twoAwaits` on the stripped -O build, verbatim: the
/// await binds its result, the second await consumes it, the async return
/// (a `br` through the context's ResumeParent) is a `return`, and `awaited1`
/// crosses the second suspension through a context slot whose single store
/// and load are both proven.
@Test func rendersAwaitChainVerbatimIfPresent() async throws {
    guard let text = try await structured(strippedFixture, "twoAwaits") else { return }
    #expect(text == """
        AsyncFns.twoAwaits(Swift.Int) async -> Swift.Int {
            // async function: 2 resume funclet(s): resume #1 @0xa34, resume #2 @0xa98
            let awaited1 = await AsyncFns.fetchValue(arg0)
        }
        resume #1 of AsyncFns.twoAwaits(Swift.Int) async -> Swift.Int {
            // resume #1 of the async function @0x9e8: entered when the await in 0x9e8 returns
            let awaited2 = await AsyncFns.fetchOther(awaited1)
        }
        resume #2 of AsyncFns.twoAwaits(Swift.Int) async -> Swift.Int {
            // resume #2 of the async function @0x9e8: entered when the await in 0xa34 returns
            return (awaited1 + awaited2)
        }
        """)
}

/// A suspension-free async function returns through the same ResumeParent
/// branch; its value is recovered like a synchronous leaf's.
@Test func rendersAsyncLeafReturnIfPresent() async throws {
    guard let text = try await structured(strippedFixture, "fetchOther") else { return }
    #expect(text.contains("return (arg0 + 7)"))
}

/// An async `Int?` returns its payload in x0 and its nil tag in x1, so x0 at
/// the return branch is not the result. Read as one, `nil` rendered as `0`:
/// `return ((arg0 == 0) ? 0 : (arg0 + 1))`.
@Test func declinesTwoRegisterAsyncReturnIfPresent() async throws {
    guard let text = try await structured(strippedFixture, "maybeNext") else { return }
    #expect(text.contains("maybeNext"))
    #expect(!text.contains("return ("), Comment(rawValue: text))
}

/// An executor hop is named only when both executor operands prove it
/// (`generic` for the null executor); otherwise it declines with `?`. The
/// continuation reads the parameter back from the context slot the entry
/// funclet spilled it to, so the throw condition names `arg0`.
@Test func rendersExecutorHopsAndSpilledParametersIfPresent() async throws {
    guard let throwing = try await structured(strippedFixture, "fetchOrThrow") else { return }
    #expect(throwing.contains("await hop_to_executor(generic)"))
    #expect(throwing.contains("if (arg0 < 0) {"))
    #expect(throwing.contains("return arg0"))
    guard let main = try await structured(strippedFixture, "onMainAwait") else { return }
    #expect(main.contains("await hop_to_executor(?)"))
    #expect(main.contains("return (awaited1 + 1)"))
}

/// Negative: at -Onone the funclets reload the context through stack spills
/// the chain pass does not follow, so neither the async return's value nor a
/// slot is claimed; a resume funclet renders no `return <value>` at all.
@Test func declinesUnprovenAsyncReturnsAtOnoneIfPresent() async throws {
    guard let functions = try await disassemble(debugFixture, filter: "twoAwaits") else { return }
    let resumes = functions.filter { $0.asyncFunclet?.isEntry == false }
    #expect(resumes.count == 2)
    for resume in resumes {
        let text = resume.renderStructured()
        #expect(!text.contains("return ("), Comment(rawValue: text))
        #expect(!text.contains("awaited1 +"), Comment(rawValue: text))
    }
    // The await itself is still provable there: the resume pointer store and
    // the direct tail call do not depend on the stack.
    guard let entry = functions.first(where: { $0.asyncFunclet?.isEntry == true }) else { return }
    #expect(entry.renderPseudo().contains("let awaited1 = await AsyncFns.fetchValue(arg0)"))
}

/// Negative: the awaited result is seeded only from a callee whose signature
/// proves a single-register result. A void callee, an unnamed one, and a
/// String-returning one seed nothing; a Double seeds v0.
@Test func seedsAwaitedResultOnlyFromAProvenSignatureIfPresent() async throws {
    guard let functions = try await disassemble(optFixture) else { return }
    let byStart = Dictionary(functions.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
    guard let entry = functions.first(where: { $0.displayName.hasPrefix("AsyncFns.oneAwait") }),
          let resume = entry.asyncFunclet?.chain.dropFirst().first,
          let callee = functions.first(where: { $0.displayName.hasPrefix("AsyncFns.fetchValue") })
    else { return }
    let hints = AsyncFuncletIndex.hintSections(in: try BinaryLoader.load(path: optFixture)) { address, size in
        Disassembler(preset: .default).sectionBytesForTesting(address: address, size: size, path: optFixture)
    }
    func register(calleeName: String?) -> String? {
        let index = AsyncFuncletIndex.build(
            hints: hints, functionStarts: Set(byStart.keys),
            instructions: { byStart[$0]?.instructions ?? [] },
            nameOf: { $0 == callee.startAddress ? calleeName : byStart[$0]?.displayName }
        )
        return Disassembler.awaitedResultRegister(into: resume, index: index)
    }
    #expect(register(calleeName: "AsyncFns.fetchValue(Swift.Int) async -> Swift.Int") == "x0")
    #expect(register(calleeName: "AsyncFns.fetchValue(Swift.Int) async -> Swift.Double") == "v0")
    #expect(register(calleeName: "AsyncFns.fetchValue(Swift.Int) async -> ()") == nil)
    #expect(register(calleeName: "AsyncFns.fetchValue(Swift.Int) async -> Swift.String") == nil)
    #expect(register(calleeName: nil) == nil)
}

// MARK: - Soundness: a resume funclet's registers are not the parameters

/// x0 at a resume funclet's entry is the awaited callee's result, not the
/// parent's first parameter. The funclet's symbol demangles to the parent's
/// full signature, which used to seed `arg0` from it, so the second await of
/// `twoAwaits` rendered `fetchOther(arg0)` (the source passes `a`, the result
/// of the first await). The parameters are not in any register here.
@Test(arguments: [debugFixture, optFixture])
func resumeFuncletsDoNotInheritTheSignatureArgumentsIfPresent(path: String) async throws {
    guard let functions = try await disassemble(path, filter: "twoAwaits") else { return }
    let resumes = functions.filter { $0.asyncFunclet?.isEntry == false }
    #expect(resumes.count == 2)
    for resume in resumes {
        let pseudo = resume.renderPseudo()
        #expect(!pseudo.contains("arg0"), Comment(rawValue: pseudo))
        #expect(!pseudo.contains("self"), Comment(rawValue: pseudo))
    }
    // The entry funclet keeps its arguments: they really are in x0 there.
    guard let entry = functions.first(where: { $0.asyncFunclet?.isEntry == true }) else { return }
    #expect(entry.renderPseudo().contains("(arg0)"))
}

/// A slot whose address goes to a callee (`inout`) can be written by it, so a
/// single store in the chain no longer proves its value. Read as proven, the
/// final resume of `inoutSync` rendered `return (arg0 + (arg0 << 1))`: the
/// value before `syncBump(&n)` added 11.
@Test func declinesAnEscapedContextSlotIfPresent() async throws {
    let path = "Fixtures/Sample/libAsyncInout.dylib"
    for name in ["inoutSync", "inoutAcross"] {
        guard let text = try await structured(path, name) else { return }
        #expect(text.contains(name), Comment(rawValue: text))
        #expect(!text.contains("return (arg0"), Comment(rawValue: text))
    }
}

/// An async throwing function returns through ResumeParent with its error in
/// x20, zero for none. `swift_allocError` then `mov x20, x0; br x0` is a throw,
/// and so is a resume that passes on the error it received in x20 (reached
/// only through `cbz x20`'s non-zero edge). Both rendered a bare `return`.
@Test func asyncThrowsRenderAsThrowsIfPresent() async throws {
    let fixture = "Fixtures/Sample/libAsyncFns.opt.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    func structured(_ filter: String) async throws -> String {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: filter)
        }
        return functions.map { $0.renderStructured() }.joined(separator: "\n")
    }
    let thrower = try await structured("fetchOrThrow")
    #expect(thrower.contains("throw ?"), Comment(rawValue: thrower))
    #expect(thrower.contains("return arg0"), Comment(rawValue: thrower))
    let rethrower = try await structured("awaitThrowing")
    #expect(rethrower.contains("return (awaited1 << 1)"), Comment(rawValue: rethrower))
    #expect(rethrower.contains("} else {\n        throw ?"), Comment(rawValue: rethrower))
    #expect(!rethrower.contains("} else {\n        return\n"), Comment(rawValue: rethrower))
}

/// At -Onone a resume funclet stores its context into a slot of itself and
/// reaches ResumeParent through that slot at each exit. Forwarding the store
/// to the load proves those exits async returns: the result and the throw
/// both rendered nothing.
@Test func ononeAsyncExitsAreProvenThroughTheContextSlotIfPresent() async throws {
    let fixture = "Fixtures/Sample/libAsyncFns.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    func structured(_ filter: String) async throws -> String {
        let functions = try await withStableDependencies {
            try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: filter)
        }
        return functions.map { $0.renderStructured() }.joined(separator: "\n")
    }
    let oneAwait = try await structured("oneAwait")
    #expect(oneAwait.contains("return (awaited1 + 1)"), Comment(rawValue: oneAwait))
    let thrower = try await structured("fetchOrThrow")
    #expect(thrower.contains("throw ?"), Comment(rawValue: thrower))
}
