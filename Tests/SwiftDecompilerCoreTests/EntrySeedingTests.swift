import Foundation
import Testing
@testable import SwiftDecompilerCore

/// The rendered body of `name` in an EntrySeed build.
private func entrySeed(_ name: String, in fixture: String) async throws -> String {
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: fixture, functionFilter: "EntrySeed.\(name)(")
    }
    return functions.map { $0.renderStructured() }.joined(separator: "\n")
}

private let entrySeedBuilds = ["libEntrySeed.dylib", "libEntrySeed.opt.dylib", "libEntrySeed.size.dylib"]
    .map { "Fixtures/Sample/\($0)" }

/// `inout` of a struct this image lays out is its address, one register.
/// `a3(_ p: inout P3, _ k: Int, _ j: Int, _ l: Int)` is `(ptr, i64, i64, i64)`:
/// counted as P3's three registers, `l`'s x3 read as `k`.
@Test func anInoutStructIsOneAddressAtEntryIfPresent() async throws {
    for fixture in entrySeedBuilds where FileManager.default.fileExists(atPath: fixture) {
        for (name, parameter) in [("a2", "arg2"), ("a3", "arg3"), ("a4", "arg2"), ("aUnit", "arg2")] {
            let body = try await entrySeed(name, in: fixture)
            #expect(body.contains(parameter), "\(fixture) \(name): \(body)")
            #expect(!body.contains("arg1"), "\(fixture) \(name): \(body)")
        }
        // Its address is the parameter: the store goes through `p`, not `k`.
        let store = try await entrySeed("aStore", in: fixture)
        #expect(!store.contains("mem64[arg1]"), "\(fixture): \(store)")
        // A value of the same struct does take its registers.
        let byValue = try await entrySeed("byValue", in: fixture)
        #expect(byValue.contains("arg1"), "\(fixture): \(byValue)")
    }
}

/// `foreignData(_ d: Foundation.Data, _ k: Int, _ j: Int)` is `(i64, i64, i64,
/// i64)`: `k` is x2. A local `Data` of one word lent the foreign type its
/// layout, so x2 read as `j`. A local `Data` keeps its own.
@Test func aForeignTypeTakesNoLayoutFromALocalNamesakeIfPresent() async throws {
    for fixture in entrySeedBuilds where FileManager.default.fileExists(atPath: fixture) {
        for name in ["foreignData", "foreignDuration"] {
            let body = try await entrySeed(name, in: fixture)
            #expect(!body.contains("arg2"), "\(fixture) \(name): \(body)")
        }
        let local = try await entrySeed("localData", in: fixture)
        #expect(local.contains("arg1"), "\(fixture): \(local)")
    }
}

/// The result side reads the same layouts. A foreign `Rec`'s words took the
/// local `Rec`'s field names, in a call's result and in a result built here.
@Test func aForeignResultTakesNoFieldNamesFromALocalNamesakeIfPresent() async throws {
    for fixture in entrySeedBuilds where FileManager.default.fileExists(atPath: fixture) {
        let read = try await entrySeed("readForeign", in: fixture)
        #expect(!read.contains("wrong"), "\(fixture): \(read)")
        let made = try await entrySeed("makeForeign", in: fixture)
        #expect(!made.contains("wrong"), "\(fixture): \(made)")
    }
    let optimized = "Fixtures/Sample/libEntrySeed.opt.dylib"
    guard FileManager.default.fileExists(atPath: optimized) else { return }
    let local = try await entrySeed("makeLocal", in: optimized)
    #expect(local.contains("wrongFirst: arg0"), "\(local)")
}

/// A call lays its arguments out by the same answer: 42 is `k`, in x2, and
/// with the local one-word `Duration` it took `j`'s position.
@Test func aCallToAForeignParameterPlacesNoArgumentByALocalNamesakeIfPresent() async throws {
    let fixture = "Fixtures/Sample/libEntrySeed.dylib"
    guard FileManager.default.fileExists(atPath: fixture) else { return }
    let body = try await entrySeed("callsForeign", in: fixture)
    #expect(!body.contains("foreignDuration(?, ?, 42)"), "\(body)")
}

/// The lookup itself: only a type's own key answers.
@Test func aCompleteValueLayoutNeedsItsOwnKey() {
    let map = FieldMap(typeName: "Data", instanceSize: 8, fields: [(offset: 0, bytes: 8, name: "a", typeEncoding: "Si")])
    let maps = ["Data": map, "M.Data": map]
    let index = ClassTypeIndex()
    #expect(Disassembler.completeValueLayout(of: "Data", fieldMaps: maps, classTypeIndex: index) != nil)
    #expect(Disassembler.completeValueLayout(of: "M.Data", fieldMaps: maps, classTypeIndex: index) != nil)
    #expect(Disassembler.completeValueLayout(of: "Foundation.Data", fieldMaps: maps, classTypeIndex: index) == nil)
    #expect(Disassembler.completeValueLayout(of: "inout M.Data", fieldMaps: maps, classTypeIndex: index) == nil)
}
