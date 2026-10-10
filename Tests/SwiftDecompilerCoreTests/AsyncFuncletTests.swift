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
    // nothing: 7 async functions, 5 await-return and 2 continuation funclets.
    #expect(expected.values.filter { $0.ordinal == 0 }.count == 7)
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
    #expect(stripped.count == 34)

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
    #expect(stripped.filter { $0.asyncFunclet != nil }.count == 14)
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
    #expect(leafEntries.count == 2)
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
