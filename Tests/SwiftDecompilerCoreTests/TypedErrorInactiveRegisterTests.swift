import Demangling
import Foundation
import MachOKit
import SwiftLayout
import Testing
@testable import SwiftDecompilerCore

private let typedErrorFixtures: [(client: String, images: [String])] = [
    ("Fixtures/Sample/typed-error-inactive-Onone-oracle",
     ["Fixtures/Sample/libTypedErrorInactive0.Onone.dylib", "Fixtures/Sample/libTypedErrorInactive1.Onone.dylib"]),
    ("Fixtures/Sample/typed-error-inactive-O-oracle",
     ["Fixtures/Sample/libTypedErrorInactive0.O.dylib", "Fixtures/Sample/libTypedErrorInactive1.O.dylib"]),
    ("Fixtures/Sample/typed-error-inactive-Osize-oracle",
     ["Fixtures/Sample/libTypedErrorInactive0.Osize.dylib", "Fixtures/Sample/libTypedErrorInactive1.Osize.dylib"]),
]

private let wrapped = "$s15TypedErrorProbe12probeWrappedyAA8BigValueVSiAA11TinyFailureOYKF"
private let indirect = "$s15TypedErrorProbe13probeIndirectyAA8BigValueVSiAA11TinyFailureOYKF"
private let direct = "$s15TypedErrorProbe11probeDirectySd_s6UInt64VtSiAA11TinyFailureOYKF"
private let fourPrefix = "$s15TypedErrorProbe9probeFour"
private let gamma = "TypedErrorProbe.TinyFailure.gamma"

private let expectedNativeOutput = """
wrapped -1 beta
direct -1 2.75 7003
four -1 9013 9014 9015 9016
wrapped 0 gamma
direct 0 gamma
four 0 gamma
wrapped 1 8007 8008 8009 8010 8011
direct 1 2.75 7003
four 1 9013 9014 9015 9016

"""

private func rawSwiftSymbol(_ function: DisassembledFunction) -> String {
    function.symbol.hasPrefix("_") ? String(function.symbol.dropFirst()) : function.symbol
}

private func nativeTypedErrorOutput(client: String, image: String, directory: URL) throws -> String {
    let localClient = directory.appendingPathComponent("native")
    let localImage = directory.appendingPathComponent("libTypedErrorProbe.dylib")
    let fm = FileManager.default
    try fm.createDirectory(at: directory, withIntermediateDirectories: false)
    try fm.copyItem(at: URL(fileURLWithPath: client), to: localClient)
    try fm.copyItem(at: URL(fileURLWithPath: image), to: localImage)
    let task = Process()
    let pipe = Pipe()
    task.executableURL = localClient
    task.currentDirectoryURL = directory
    task.standardOutput = pipe
    task.environment = ProcessInfo.processInfo.environment.filter { key, _ in !key.hasPrefix("DYLD_") }
    try task.run()
    let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    try #require(task.terminationReason == .exit && task.terminationStatus == 0)
    return String(decoding: bytes, as: UTF8.self)
}

private struct TypedErrorVeneer: Equatable {
    let entry: UInt64
    let textAddress: UInt64
    let sectionBytes: Data
    let inactiveOffset: Int
}

private func typedErrorVeneer(
    path: String, functions: [DisassembledFunction], tag: Int, comment: Comment
) throws -> TypedErrorVeneer {
    let function = try #require(functions.first { rawSwiftSymbol($0) == wrapped }, comment)
    let target = try #require(functions.first { rawSwiftSymbol($0) == indirect }, comment)
    let code = function.instructions
    try #require(code.count == 10 && code.first?.address == function.startAddress, comment)
    try #require(code.map(\.address) == (0..<10).map { function.startAddress + 4 * UInt64($0) }, comment)
    let image = try BinaryLoader.load(path: path)
    let ranges = try #require(FileBackedRanges(standalone: image), comment)
    let text = try #require(image.sections64.first { $0.segmentName == "__TEXT" && $0.sectionName == "__text" }, comment)
    let textAddress = UInt64(text.address)
    let textRange = try #require(ranges.fileBytes(at: textAddress), comment)
    let size = try #require(Int(exactly: text.size), comment)
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    try #require(size >= 0 && size <= textRange.available && textRange.offset <= data.count - size, comment)
    let bytes = data.subdata(in: textRange.offset..<textRange.offset + size)
    try #require(function.startAddress >= textAddress, comment)
    let index = try #require(Int(exactly: function.startAddress - textAddress), comment)
    try #require(index >= 0 && index <= bytes.count - 40, comment)
    let words: [UInt32] = (0..<10).map { instruction in
        let offset = index + instruction * 4
        return bytes[offset..<offset + 4].enumerated().reduce(UInt32(0)) {
            $0 | (UInt32($1.element) << (8 * $1.offset))
        }
    }

    // Only SP, FP and saved frame memory change before forwarding to the
    // delegate. X8, X1 and the ordinary mode are untouched by this veneer.
    try #require(Array(words[0..<2]) == [0xa9bf_7bfd, 0x9100_03fd], comment)
    try #require(words[2] >> 26 == 0x25 && code[2].controlFlow == .call
                 && code[2].branchTarget == target.startAddress, comment)
    try #require(words[3] & 0xff00_001f == 0xb400_0015 && code[3].branchTarget == code[8].address, comment)
    try #require(words[4] == 0x5280_0035 && words[5] == (0x5280_0000 | UInt32(tag << 5)), comment)
    // The inactive W0 definition reaches the throw return unchanged.
    // Both native paths restore the caller's LR and use RET X30.
    try #require(Array(words[6...]) == [0xa8c1_7bfd, 0xd65f_03c0, 0xa8c1_7bfd, 0xd65f_03c0], comment)
    return TypedErrorVeneer(entry: function.startAddress, textAddress: textAddress,
                            sectionBytes: bytes, inactiveOffset: index + 20)
}

/// The two authored veneers differ only in an inactive return word. The
/// independently compiled caller reads the true typed payload from storage.
@Test func inactiveX0CannotNameAnIndirectTypedErrorIfPresent() async throws {
    let fm = FileManager.default
    let temporary = fm.temporaryDirectory.appendingPathComponent("swiftdc-typed-error-\(UUID())")
    try fm.createDirectory(at: temporary, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: temporary) }

    for (mode, fixture) in typedErrorFixtures.enumerated() {
        let missing = (fixture.images + [fixture.client]).filter { !fm.fileExists(atPath: $0) }
        guard missing.isEmpty else {
            #expect(!FixturePresenceTests.enforcingFixturePresence, "Build \(missing) before testing.")
            continue
        }

        var veneers: [TypedErrorVeneer] = []
        for (tag, path) in fixture.images.enumerated() {
            let comment = Comment(rawValue: path)
            let directory = temporary.appendingPathComponent("\(mode)-\(tag)")
            let native = try nativeTypedErrorOutput(client: fixture.client, image: path, directory: directory)
            try #require(native == expectedNativeOutput, comment)
            let image = try BinaryLoader.load(path: path)
            let layouts = try FieldMapBuilder.build(in: image)
            for (name, count) in [("BigValue", 5), ("FourValue", 4)] {
                let layout = try #require(layouts["TypedErrorProbe.\(name)"], comment)
                try #require(layout.isStruct == true && layout.isGeneric == false &&
                             layout.instanceSize == count * 8 && layout.trustedOffsetLimit == count * 8 &&
                             layout.trustLimitReason == nil, comment)
                try #require(layout.fields.map(\.offset) == (0..<count).map { $0 * 8 }, comment)
                try #require(layout.fields.allSatisfy { field in
                    field.bytes == 8 && ["s6UInt64V", "Swift.UInt64"].contains(FieldMap.printableTypeName(
                        mangled: field.typeMangledName, resolved: layout.fieldTypeNames[field.name]))
                }, comment)
            }
            let filtered = try await withStableDependencies {
                try await Disassembler().disassemble(path: path, functionFilter: "TypedErrorProbe.probe")
            }
            let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
            let streaming = await withStableDependencies {
                await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
            }
            veneers.append(try typedErrorVeneer(path: path, functions: array, tag: tag, comment: comment))
            for (route, functions) in [("filtered", filtered), ("array", array), ("streaming", streaming)] {
                let routeComment = Comment(rawValue: path + " " + route)
                let wraps = functions.filter { rawSwiftSymbol($0) == wrapped }
                try #require(wraps.count == 1, routeComment)
                let wrapper = wraps[0]
                try #require(wrapper.startAddress == veneers[tag].entry &&
                             wrapper.source == .symbol && wrapper.instructions.count == 10, routeComment)
                let throwEdge = wrapper.instructions[7]
                let successEdge = wrapper.instructions[9]
                try #require(throwEdge.controlFlow == .return && successEdge.controlFlow == .return, routeComment)
                #expect(throwEdge.exit == .throw("?"), routeComment)
                if case .normal? = successEdge.exit {} else { Issue.record(routeComment) }
                for view in [wrapper.renderPseudo(), wrapper.renderStructured()] {
                    let throwLines = view.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { $0.hasPrefix("throw ") }
                    #expect(throwLines == ["throw ?"], routeComment)
                }
                for expected in [direct, fourPrefix] {
                    let controls = functions.filter {
                        expected == direct ? rawSwiftSymbol($0) == expected
                            : rawSwiftSymbol($0).hasPrefix(expected) && rawSwiftSymbol($0).hasSuffix("YKF")
                    }
                    try #require(controls.count == 1, routeComment)
                    let control = controls[0]
                    try #require(control.source == .symbol, routeComment)
                    #expect(control.instructions.contains { $0.controlFlow == .return && $0.exit == .throw(gamma) },
                            routeComment)
                    for view in [control.renderPseudo(), control.renderStructured()] {
                        #expect(view.contains("throw \(gamma)"), routeComment)
                    }
                }
            }
        }
        try #require(veneers.count == 2)
        let first = veneers[0], second = veneers[1]
        try #require(first.entry == second.entry && first.textAddress == second.textAddress &&
                     first.inactiveOffset == second.inactiveOffset && first.sectionBytes.count == second.sectionBytes.count)
        var expected = first.sectionBytes
        expected[first.inactiveOffset] ^= 0x20
        #expect(expected == second.sectionBytes)
    }
}

/// These symbols come from the typed-error fixture or archived compiler IR.
@Test func indirectTypedErrorNeedsAnExactClosedNativeResultLayout() throws {
    let big = "TypedErrorProbe.BigValue"
    let word = StaticTypeLayout(size: 8, stride: 8, alignmentMask: 7,
                                extraInhabitantCount: 0, isBitwiseTakable: true)
    let fields = ["a", "b", "c", "d", "e"].enumerated().map { index, name in
        FieldLayoutEntry(fieldName: name, offset: index * 8, typeMangledName: "s6UInt64V",
                         layout: word, resolution: .computed)
    }
    func map(_ layout: [FieldLayoutEntry], size: Int = 40) -> FieldMap {
        var result = FieldMap(typeName: "BigValue", layout: AggregateFieldLayout(
            fields: layout, size: size, stride: size, alignment: 8, extraInhabitantCount: 0))
        result.isStruct = true
        result.isGeneric = false
        return result
    }
    func proves(_ symbol: String, _ maps: [String: FieldMap],
                source: RecoverySource = .symbol) -> Bool {
        let entry = DisassembledFunction(symbol: symbol, demangledName: nil, startAddress: 0x1000,
                                         instructions: [], source: source)
        return Disassembler.hasIndirectFiveWordTypedThrowResult(entry, fieldMaps: maps)
    }

    let full = map(fields)
    let exact = [big: full]
    try #require(proves(indirect, exact))
    #expect(proves("_" + wrapped, exact))
    #expect(!proves(indirect, ["Foreign.BigValue": full, "BigValue": full]))
    #expect(!proves(indirect, exact, source: .metadata))
    #expect(!proves(indirect, [big: map(Array(fields.dropLast()), size: 32)]))
    #expect(!proves(indirect, [big: map(Array(fields.dropLast()))]))

    // The first five words are present; the trailing field is unproved.
    let opaque = FieldLayoutEntry(fieldName: "tail", offset: 40, typeMangledName: "Foreign",
                                  layout: nil, resolution: .unknown(reason: .resilientFieldUnresolved))
    let open = map(fields + [opaque])
    try #require(open.fields.count == 5 && open.trustedOffsetLimit == 40 && open.trustLimitReason != nil)
    #expect(!proves(indirect, [big: open]))

    // Five independently addressable words are essential. A shifted final
    // offset or a same-sized field from a different bank cannot prove this.
    let shifted = FieldLayoutEntry(fieldName: "e", offset: 31, typeMangledName: "s6UInt64V",
                                   layout: word, resolution: .computed)
    let floating = FieldLayoutEntry(fieldName: "e", offset: 32, typeMangledName: "Sd",
                                    layout: word, resolution: .computed)
    for last in [shifted, floating] {
        #expect(!proves(indirect, [big: map(Array(fields.dropLast()) + [last])]))
    }

    let async = "$s15TypedErrorProbe10probeAsyncyAA8BigValueVSiYaAA11TinyFailureOYKF"
    let resume = async + "TY0_"
    #expect((try demangleAsNode(async).print(using: .default)).contains("async throws"))
    #expect((try demangleAsNode(resume)).contains { $0.kind == .asyncSuspendResumePartialFunction })
    #expect(!proves(async, exact))
    #expect(!proves(resume, exact))
    #expect(!proves(direct, exact))

    // The resilient two-module fixture emits this actual specialized entry.
    let specialized = "$s12RemoteClient9keepValueyxx_Sit0A6Errors0A5ErrorOYKlFSd_Tg5"
    #expect((try demangleAsNode(specialized).print(using: .default)).contains("specialization"))
    #expect(!proves(specialized, exact))
}
