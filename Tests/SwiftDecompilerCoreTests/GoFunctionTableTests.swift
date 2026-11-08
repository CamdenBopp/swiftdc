import Testing
import Foundation
@testable import SwiftDecompilerCore

/// `gofunctions/main.go`, built by Go's internal linker: no
/// LC_FUNCTION_STARTS, and the `.stripped` build has no symbol table either.
/// Before, `xrefs` listed "1 of 1 functions" for it, all of `__text`; on
/// github-mcp-server the one 7.4 MB function took 2.77 GB.
private let full = "Fixtures/Sample/goProgram"
private let stripped = "Fixtures/Sample/goProgram.stripped"

/// The unstripped build's function symbols, as `nm` reads them: the oracle.
/// `runtime.etext` marks the end of the text and `runtime.text` its start,
/// where the table lists `go:buildid`; the symbol table spells assembly
/// functions with `.abi0`, the table without.
private func symbols() -> [UInt64: String]? {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/nm")
    process.arguments = [full]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    var result: [UInt64: String] = [:]
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let fields = line.split(separator: " ", maxSplits: 2)
        guard fields.count == 3, fields[1] == "T" || fields[1] == "t", let address = UInt64(fields[0], radix: 16) else { continue }
        var name = String(fields[2].dropFirst())
        if name.hasSuffix(".abi0") { name.removeLast(5) }
        guard name != "runtime.etext" else { continue }
        result[address] = name == "runtime.text" ? "go:buildid" : name
    }
    return result.isEmpty ? nil : result
}

@Test func aStrippedGoImageTakesItsFunctionsFromTheGoTableIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: stripped) else { return }
    let oracle = try #require(symbols())
    let machO = try BinaryLoader.load(path: stripped)
    #expect(machO.functionStarts.map { Array($0).isEmpty } ?? true, "the internal linker writes no LC_FUNCTION_STARTS")
    let disassembler = Disassembler(preset: .default)
    let table = try #require(disassembler.goFunctions(in: machO))
    #expect(Dictionary(table.entries.map { ($0.address, $0.name) }, uniquingKeysWith: { a, _ in a }) == oracle)
    #expect(disassembler.declaredFunctionCount(in: machO) == oracle.count)

    let scale = try #require(oracle.first { $0.value == "main.scale" }?.key)
    let filtered = try await withStableDependencies {
        try await disassembler.disassemble(path: stripped, functionFilter: "main.main")
    }
    let main = try #require(filtered.first { $0.symbol == "_main.main" })
    #expect(main.instructions.contains { $0.controlFlow == .call && $0.branchTarget == scale && $0.callee == "main.scale" })
}

/// The streaming path (`xrefs`), where one 7.4 MB function took 2.77 GB.
@Test func aStrippedGoImageStreamsByTheGoTableIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: stripped) else { return }
    let oracle = try #require(symbols())
    let scale = try #require(oracle.first { $0.value == "main.scale" }?.key)
    let main = try #require(oracle.first { $0.value == "main.main" }?.key)
    let machO = try BinaryLoader.load(path: stripped)
    let sites = await withStableDependencies {
        await Disassembler(preset: .default).disassembleStreaming(machO: machO, transform: CallGraph.sites(of:))
    }
    let graph = CallGraph(functions: sites)
    #expect(graph.functionAddresses == Set(oracle.keys))
    #expect(graph.callers(of: scale).contains { $0.caller == main })
}

/// The objdump listing names functions from the table: objdump has no
/// symbol to print.
@Test func aStrippedGoImageListsTheGoTableNamesIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: stripped) else { return }
    let oracle = try #require(symbols())
    let listing = try await withStableDependencies { try await Disassembler(preset: .default).disassemble(path: stripped) }
    #expect(Set(listing.map(\.startAddress)) == Set(oracle.keys))
    let named = Dictionary(listing.map { ($0.startAddress, $0.symbol) }, uniquingKeysWith: { a, _ in a })
    #expect(oracle.allSatisfy { named[$0.key] == "_" + $0.value })
}

/// Each inconsistency declines the whole table, never part of it.
@Test func anInconsistentGoTableIsDeclinedIfPresent() throws {
    guard FileManager.default.fileExists(atPath: stripped) else { return }
    let machO = try BinaryLoader.load(path: stripped)
    let section = try #require(machO.sections.first { $0.sectionName == "__gopclntab" })
    let text = try #require(machO.sections.first { $0.sectionName == "__text" })
    let bytes = try #require(FileManager.default.contents(atPath: stripped))
    let offset = machO.resolveOffset(at: UInt64(section.address))
    let original = bytes[Int(offset) ..< Int(offset) + section.size]
    func parse(_ table: Data) -> GoFunctionTable? {
        GoFunctionTable.parse(Data(table), textAddress: UInt64(text.address), textSize: UInt64(text.size))
    }
    #expect(parse(original)?.entries.count ?? 0 > 1000)
    func u64(_ table: Data, _ at: Int) -> Int {
        table.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: at, as: UInt64.self)) }
    }
    let functions = u64(Data(original), 64)
    func mutated(_ edit: (inout Data) -> Void) -> Data { var copy = Data(original); edit(&copy); return copy }
    let cases: [(String, Data)] = [
        ("magic of Go 1.16", mutated { $0[0] = 0xfa }),
        ("pointer size 4", mutated { $0[7] = 4 }),
        ("textStart elsewhere", mutated { $0[24] = 0x40 }),
        ("entries out of order", mutated { $0.replaceSubrange(functions + 8 ..< functions + 12, with: [0, 0, 0, 0]) }),
        // Two whole (entry, func) pairs swapped: each `_func` still repeats
        // its entry, only the order is wrong.
        ("pairs swapped", mutated {
            let pair = Data($0[functions + 16 ..< functions + 24])
            $0.replaceSubrange(functions + 16 ..< functions + 24, with: $0[functions + 24 ..< functions + 32])
            $0.replaceSubrange(functions + 24 ..< functions + 32, with: pair)
        }),
        // In order, but the second entry's `_func` is the third's.
        ("a func for another entry", mutated {
            $0.replaceSubrange(functions + 20 ..< functions + 24, with: $0[functions + 28 ..< functions + 32])
        }),
        ("a name past the table", mutated {
            let funcOffset = $0.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: functions + 12, as: UInt32.self)) }
            $0.replaceSubrange(functions + funcOffset + 4 ..< functions + funcOffset + 8, with: [0xff, 0xff, 0xff, 0x7f])
        }),
        ("an end past the text", mutated {
            let count = u64(Data(original), 8)
            $0.replaceSubrange(functions + count * 8 ..< functions + count * 8 + 4, with: [0xff, 0xff, 0xff, 0x7f])
        }),
    ]
    for (what, table) in cases { #expect(parse(table) == nil, "\(what)") }
}
