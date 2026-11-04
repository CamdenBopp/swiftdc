import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A store through a class parameter is a field assignment when it writes
/// exactly one field of that object. Anything else keeps its raw `memN[…]`,
/// which is still true.

private func structured(_ path: String) async throws -> [(name: String, text: String)]? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    return functions.map { ($0.displayName, $0.renderStructured()) }
}

private func body(_ rendered: [(name: String, text: String)], _ name: String) throws -> String {
    try #require(rendered.first { $0.name.hasPrefix("\(name)(") }, "\(name) missing").text
}

@Test func aStoreThroughAClassParameterAssignsItsFieldAtEveryLevelIfPresent() async throws {
    for path in ["Fixtures/Sample/libClassParamSmall.dylib", "Fixtures/Sample/libClassParamSmall.opt.dylib",
                 "Fixtures/Sample/libClassParamSmall.size.dylib"] {
        guard let rendered = try await structured(path) else { continue }
        let text = try body(rendered, "ClassParamSmall.writeHolder")
        #expect(text.contains("arg0.v = arg1"), Comment(rawValue: "\(path)\n\(text)"))
        #expect(!text.contains("mem64"), Comment(rawValue: "\(path)\n\(text)"))
    }
}

@Test func aStoreNamesAFieldOnlyWhenItWritesThatFieldIfPresent() async throws {
    for path in ["Fixtures/Sample/libClassParam.dylib", "Fixtures/Sample/libClassParam.opt.dylib"] {
        guard let rendered = try await structured(path) else { continue }
        for (name, expected) in [
            ("writeHolder", "arg0.v = arg1"), ("writeFlag", "arg0.flag = "), ("writeSmall", "arg0.small = "),
            ("writeDouble", "arg0.d = arg1"), ("copyField", "arg0.v = arg1.v"),
            ("quietWrite", "arg0.w = arg1"), ("quietCopy", "arg0.v = arg0.w"),
        ] {
            let text = try body(rendered, "ClassParam.\(name)")
            #expect(text.contains(expected), Comment(rawValue: "\(path)\n\(text)"))
        }
        // Each word of a two-word field is part of it.
        for name in ["writeString", "writePair"] {
            let text = try body(rendered, "ClassParam.\(name)")
            #expect(text.contains("mem64[") && !text.contains("arg0."), Comment(rawValue: "\(path)\n\(text)"))
        }
    }
}

@Test func aStoreThroughAnythingButTheParameterKeepsItsAddressIfPresent() async throws {
    for path in ["Fixtures/Sample/libClassParam.dylib", "Fixtures/Sample/libClassParam.opt.dylib",
                 "Fixtures/Sample/libClassParam.size.dylib"] {
        guard let rendered = try await structured(path) else { continue }
        for name in ["optionalWrite", "inoutWrite", "reassignedOnBranch", "reassignedFresh", "walk",
                     "writeBoxHead", "writeShared", "writeDup"] {
            let text = try body(rendered, "ClassParam.\(name)")
            #expect(text.contains("mem64["), Comment(rawValue: "\(path)\n\(text)"))
            #expect(!text.contains(".v = ") && !text.contains(".head = ") && !text.contains(".a = "),
                    Comment(rawValue: "\(path)\n\(text)"))
        }
    }
}

@Test func aStoreIntoAClassLaidOutElsewhereKeepsItsAddressIfPresent() async throws {
    if let kit = try await structured("Fixtures/Sample/libClassParamKit.dylib") {
        let text = try body(kit, "ClassParamKit.writeKit")
        #expect(text.contains("mem64[arg0 + 0x18] = arg1"), Comment(rawValue: text))
    }
    guard let client = try await structured("Fixtures/Sample/libClassParamClient.dylib") else { return }
    let over = try body(client, "ClassParamClient.writeOver")
    #expect(over.contains("mem64[") && !over.contains("arg0.x"), Comment(rawValue: over))
    let twin = try body(client, "ClassParamClient.writeForeignTwin")
    #expect(twin.contains("mem64[arg0 + 0x10] = arg1"), Comment(rawValue: twin))
}

@Test func aStoreTargetMustBeOneWholeFieldAtAConstantOffset() {
    let map = FieldMap(typeName: "H", instanceSize: 0x30, fields: [
        (offset: 0x10, bytes: 8, name: "v", typeEncoding: "Si"),
        (offset: 0x18, bytes: 16, name: "s", typeEncoding: "SS"),
    ])
    func target(base: AbstractValue = .argument(0), displacement: Int64 = 0x10, bytes: Int = 8,
                kind: String = "address", index: String? = nil, indexed: Bool = false) -> String? {
        let write = MemoryWrite(kind: kind, base: base, baseRegister: "x0", valueRegisters: ["x1"],
                                displacement: displacement, indexRegister: index, index: .unknown, indexShift: 0,
                                indexed: indexed, bytes: bytes, values: [.argument(1)])
        return Disassembler.classArgumentFieldTarget(of: write, offset: displacement, maps: [0: map])
    }
    #expect(target() == "arg0.v")
    #expect(target(base: .binary(.add, .argument(0), .immediate(8)), displacement: 8) == "arg0.v")
    #expect(target(bytes: 4) == nil)
    #expect(target(displacement: 0x18) == nil)
    #expect(target(displacement: 0x18, bytes: 16) == nil)
    #expect(target(displacement: 0x20) == nil)
    #expect(target(base: .argument(1)) == nil)
    #expect(target(base: .unknown) == nil)
    #expect(target(index: "x8") == nil)
    #expect(target(indexed: true) == nil)
    #expect(target(kind: "frame") == nil)
}
