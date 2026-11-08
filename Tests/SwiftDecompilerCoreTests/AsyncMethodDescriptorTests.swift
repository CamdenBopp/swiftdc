import Testing
import Foundation
@testable import SwiftDecompilerCore
import MachOKit

/// Async class methods and async witnesses named from metadata, driven by
/// `Fixtures/Sample/libAsyncMethods.opt{,.stripped}.dylib` (asyncmethods.swift,
/// -O; build with `Fixtures/Sample/build.sh`).
///
/// An async method's descriptor, and an async requirement's witness table
/// slot, lead to an async function pointer record in `__TEXT,__const`, not
/// to code. The oracle is the unstripped build's symbol table: the entry
/// funclet `…YaF` and the record `…YaFTu` sit at different addresses, and the
/// stripped build must name the first and never the second.

private let unstrippedFixture = "Fixtures/Sample/libAsyncMethods.opt.dylib"
private let strippedFixture = "Fixtures/Sample/libAsyncMethods.opt.stripped.dylib"

/// Every symbol of the unstripped build, mangled name → address.
private func symbolAddresses(_ path: String) throws -> [String: UInt64]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let machO = try BinaryLoader.load(path: path)
    var byName: [String: UInt64] = [:]
    for symbol in machO.symbols where symbol.offset > 0 { byName[symbol.name] = UInt64(symbol.offset) }
    return byName
}

/// The methods under test, by mangled entry symbol, and the name metadata
/// gives the stripped entry. Each async one has an `…Tu` record beside it.
private let expectedNames: [(symbol: String, name: String, isAsync: Bool)] = [
    ("_$s12AsyncMethods6AnimalC5fetchSiyYaF", "AsyncMethods.Animal.method", true),
    ("_$s12AsyncMethods6AnimalC4restyS2iYaF", "AsyncMethods.Animal.method", true),
    ("_$s12AsyncMethods3DogC5fetchSiyYaF", "AsyncMethods.Dog.method", true),
    ("_$s12AsyncMethods3BoxVAA7FetcherA2aDP4pullyS2iYaFTW", "Box: Fetcher.method", true),
    // Synchronous controls: their descriptors name code directly.
    ("_$s12AsyncMethods6AnimalC4legsSiyF", "AsyncMethods.Animal.method", false),
    ("_$s12AsyncMethods3DogC4legsSiyF", "AsyncMethods.Dog.method", false),
    ("_$s12AsyncMethods3BoxVAA7FetcherA2aDP4sizeSiyFTW", "Box: Fetcher.method", false),
]

@Test func namesAsyncMethodEntriesNotTheirFunctionPointersIfPresent() async throws {
    guard let symbols = try symbolAddresses(unstrippedFixture),
          FileManager.default.fileExists(atPath: strippedFixture)
    else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: strippedFixture)
    }
    let byAddress = Dictionary(functions.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
    let machO = try BinaryLoader.load(path: strippedFixture)
    let metadata = MetadataSymbolizer().functionNames(in: machO)
    let selfIndex = SelfTypeIndex.build(in: machO)
    let vtables = VTableIndex.build(in: machO)
    let vtableTargets = Set(vtables.methodAddresses(type: "Animal") + vtables.methodAddresses(type: "Dog"))

    for expected in expectedNames {
        guard let entry = symbols[expected.symbol] else {
            Issue.record("the fixture has no \(expected.symbol)")
            continue
        }
        let function = byAddress[entry]
        #expect(function?.displayName == expected.name,
                "0x\(String(entry, radix: 16)) (\(expected.symbol)): \(function?.displayName ?? "missing")")
        #expect(function?.source == .metadata)
        guard expected.isAsync else { continue }
        // The record is data: no name, no folded candidates, no `self`, no
        // dispatch target.
        guard let record = symbols[expected.symbol + "Tu"] else {
            Issue.record("the fixture has no async function pointer for \(expected.symbol)")
            continue
        }
        #expect(record != entry)
        #expect(metadata.unique[record] == nil, "0x\(String(record, radix: 16)) named \(metadata.unique[record] ?? "")")
        #expect(metadata.folded[record] == nil)
        #expect(selfIndex.binding(for: record) == nil)
        #expect(!vtableTargets.contains(record))
        // Nor is the entry a dispatch target: an async dispatch loads the
        // record from the slot and the function from the record, so a `blr`
        // to the slot's value is not a call of it.
        #expect(!vtableTargets.contains(entry))
    }
    #expect(vtableTargets.contains(symbols["_$s12AsyncMethods6AnimalC4legsSiyF"] ?? 0))

    // `self` arrives in x20 at an async method's entry funclet, as at a
    // synchronous one: the entry is bound to its class. (The index reads a
    // class's own vtable entries, so `Dog.fetch`, an override, has none,
    // like the synchronous `Dog.legs`.)
    for (symbol, type) in [("_$s12AsyncMethods6AnimalC5fetchSiyYaF", "Animal"),
                           ("_$s12AsyncMethods6AnimalC4restyS2iYaF", "Animal")] {
        guard let entry = symbols[symbol] else { continue }
        #expect(selfIndex.binding(for: entry)?.selfTypeName == type)
    }
}

/// The resume funclets of a newly named entry are titled after it, and their
/// chain is the one the symbol table gives.
@Test func titlesAsyncMethodResumeFuncletsAfterTheEntryIfPresent() async throws {
    guard let symbols = try symbolAddresses(unstrippedFixture),
          FileManager.default.fileExists(atPath: strippedFixture),
          let entry = symbols["_$s12AsyncMethods3DogC5fetchSiyYaF"]
    else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: strippedFixture)
    }
    let byAddress = Dictionary(functions.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
    // `Dog.fetch` suspends three times: one executor hop (`TY0_`) and two
    // awaits (`TQ1_`, `TQ2_`).
    let resumes = ["TY0_", "TQ1_", "TQ2_"].compactMap { symbols["_$s12AsyncMethods3DogC5fetchSiyYaF" + $0] }
    #expect(resumes.count == 3)
    #expect(byAddress[entry]?.asyncFunclet?.chain == [entry] + resumes)
    for (index, address) in resumes.enumerated() {
        let function = byAddress[address]
        #expect(function?.asyncFunclet?.parent == entry)
        #expect(function?.displayName == "resume #\(index + 1) of AsyncMethods.Dog.method",
                "0x\(String(address, radix: 16)): \(function?.displayName ?? "missing")")
    }
}

/// A callee-allocated coroutine (`yielding borrow` / `yielding mutate`) is
/// the same shape with a coroutine function pointer record (`…Twc`):
/// `libCoroAccessors.opt{,.stripped}.dylib` (coroaccessors.swift).
@Test func namesYieldingAccessorsNotTheirFunctionPointersIfPresent() async throws {
    let stripped = "Fixtures/Sample/libCoroAccessors.opt.stripped.dylib"
    guard let symbols = try symbolAddresses("Fixtures/Sample/libCoroAccessors.opt.dylib"),
          FileManager.default.fileExists(atPath: stripped)
    else { return }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: stripped)
    }
    let byAddress = Dictionary(functions.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
    let machO = try BinaryLoader.load(path: stripped)
    let metadata = MetadataSymbolizer().functionNames(in: machO)
    let selfIndex = SelfTypeIndex.build(in: machO)
    let expected = [
        ("_$s13CoroAccessors3BoxC5valueSivy", "CoroAccessors.Box.read"),
        ("_$s13CoroAccessors3BoxC5valueSivx", "CoroAccessors.Box.modify"),
        ("_$s13CoroAccessors4ItemVAA4SlotA2aDP1vSivyTW", "Item: Slot.read"),
        ("_$s13CoroAccessors4ItemVAA4SlotA2aDP1vSivxTW", "Item: Slot.modify"),
    ]
    for (symbol, name) in expected {
        guard let entry = symbols[symbol], let record = symbols[symbol + "Twc"] else {
            Issue.record("the fixture has no \(symbol) or its record")
            continue
        }
        #expect(byAddress[entry]?.displayName == name,
                "0x\(String(entry, radix: 16)) (\(symbol)): \(byAddress[entry]?.displayName ?? "missing")")
        #expect(metadata.unique[record] == nil && metadata.folded[record] == nil)
        #expect(selfIndex.binding(for: record) == nil)
    }
    if let read = symbols["_$s13CoroAccessors3BoxC5valueSivy"] {
        #expect(selfIndex.binding(for: read)?.selfTypeName == "Box")
    }
}

/// A function pointer record is followed only when it is read as the runtime
/// reads it: the record in data, its function in code. Anything else
/// declines rather than name a guess.
@Test func followsAFunctionPointerRecordOnlyFromDataIntoCodeIfPresent() throws {
    guard let symbols = try symbolAddresses(unstrippedFixture),
          let entry = symbols["_$s12AsyncMethods6AnimalC5fetchSiyYaF"],
          let record = symbols["_$s12AsyncMethods6AnimalC5fetchSiyYaFTu"]
    else { return }
    let implementations = MethodImplementation(try BinaryLoader.load(path: unstrippedFixture))
    #expect(implementations.code(at: record, isData: true) == entry)
    // The record is data, so read as code it names nothing.
    #expect(implementations.code(at: record, isData: false) == nil)
    // Code read as a record: its first word is an instruction, not a
    // relative pointer.
    #expect(implementations.code(at: entry, isData: true) == nil)
    #expect(implementations.code(at: entry, isData: false) == entry)
    // Metadata read as a record: a method descriptor's first word is its
    // flags (0x10, an instance method), which as a relative offset leads to
    // the next descriptor, data, not code.
    if let descriptor = symbols["_$s12AsyncMethods6AnimalC4legsSiyFTq"] {
        #expect(implementations.code(at: descriptor, isData: true) == nil)
    }
}
