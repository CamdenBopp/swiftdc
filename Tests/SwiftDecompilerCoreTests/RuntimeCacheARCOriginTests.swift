import Foundation
import MachOKit
import Testing
@testable import SwiftDecompilerCore

@Test func cacheARCExportsRejectForeignImagesFlagsAndWrappedOffsetsIfPresent() throws {
    let path = "Fixtures/Sample/libResultIdentity.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let image = try BinaryLoader.load(path: path)
    var exported = try #require(image.exportedSymbols.first { $0.name == "_result_identity_make" })
    exported.name = "_swift_retain"
    exported.offset = 32
    exported.flags = ExportSymbolFlags(rawValue: 0)
    let provider = "/usr/lib/swift/libswiftCore.dylib"
    func table(_ symbol: ExportedSymbol, imagePath: String = "/usr/lib/swift/libswiftCore.dylib",
               base: UInt64 = 0x1000, text: Range<UInt64> = 0x1000..<0x2000) -> [UInt64: Set<String>] {
        CacheSymbolResolver.arcExports([symbol], imagePath: imagePath, base: base, text: text)
    }
    #expect(table(exported)[0x1020] == Set(["swift_retain"]))
    #expect(table(exported, imagePath: "@rpath/libFalseARC.dylib").isEmpty)
    #expect(table(exported, imagePath: "/usr/lib/libobjc.A.dylib").isEmpty)
    for raw in [Int32(1), 2, ExportSymbolFlags.weak_definition.rawValue, ExportSymbolFlags.reexport.rawValue,
                ExportSymbolFlags.stub_and_resolver.rawValue, ExportSymbolFlags.static_resolver.rawValue,
                ExportSymbolFlags.function_variant.rawValue, 0x4000_0000] {
        var changed = exported
        changed.flags = ExportSymbolFlags(rawValue: raw)
        #expect(table(changed).isEmpty, Comment(rawValue: "export flags \(raw)"))
    }
    let offsets: [Int?] = [nil, -1, 0x2000, Int.max]
    for offset in offsets {
        var changed = exported
        changed.offset = offset
        #expect(table(changed).isEmpty)
    }
    #expect(table(exported, base: UInt64.max - 15, text: 0..<64).isEmpty)
    var namedLikeAQuery = exported
    namedLikeAQuery.name = "_swift_retainReturningCount"
    #expect(table(namedLikeAQuery, imagePath: provider).isEmpty)
}

/// This reads actual cache exports, islands and rebases; it never executes SDK
/// code. A private report makes an unavailable host distinguishable from an
/// observed run when qualifying the change on a machine with a cache.
@Test func cacheARCContractsUseActualRuntimeExportsAndIslandsIfAvailable() async throws {
    let reportPath = ProcessInfo.processInfo.environment["SWIFTDC_ARC_CACHE_REPORT"]
    func report(_ value: [String: Any]) throws {
        guard let reportPath else { return }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: reportPath))
    }
    let core: MachOFile
    do { core = try BinaryLoader.loadFromDyldCache(cachePath: nil, selector: .path("/usr/lib/swift/libswiftCore.dylib")) }
    catch { try report(["status": "unavailable", "reason": String(describing: error)]); return }
    let full = try #require(core.fullCache)
    let resolver = try #require(CacheSymbolResolver(machO: core))
    let reader = CacheReader(full: full)
    let wanted = Set(["/usr/lib/libobjc.A.dylib",
                      "/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation",
                      "/System/Library/Frameworks/UserNotifications.framework/Versions/A/UserNotifications"])
    var images = [core.imagePath: core]
    for image in full.machOFiles() where wanted.contains(image.imagePath) { images[image.imagePath] = image }
    let objc = try #require(images["/usr/lib/libobjc.A.dylib"])
    let consumer = try #require(images["/System/Library/Frameworks/UserNotifications.framework/Versions/A/UserNotifications"])
    let foreign = try #require(images["/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation"])
    func address(_ symbol: String, in image: MachOFile) throws -> UInt64 {
        let text = try #require(image.loadCommands.infos(of: LoadCommand.segment64).first { $0.segmentName == "__TEXT" })
        let exported = try #require(image.exportedSymbols.first { $0.name == symbol })
        let offset = try #require(exported.offset)
        try #require(offset >= 0 && exported.flags.rawValue == 0)
        return UInt64(text.vmaddr) + UInt64(offset)
    }
    var exports: [[String: Any]] = []
    for (image, name) in [(core, "swift_retain"), (core, "swift_bridgeObjectRetain"), (objc, "objc_retain")] {
        let target = try address("_" + name, in: image)
        #expect(resolver.arcIdentityContract(forCallTarget: target, named: name))
        #expect(!resolver.arcIdentityContract(forCallTarget: target + 1, named: name))
        let wrongFamily = name.hasPrefix("swift_") ? "objc_retain" : "swift_retain"
        #expect(!resolver.arcIdentityContract(forCallTarget: target, named: wrongFamily))
        exports.append(["image": image.imagePath, "name": name, "address": String(target, radix: 16)])
    }
    let foreignTarget = try address("_CFRetain", in: foreign)
    #expect(!resolver.arcIdentityContract(forCallTarget: foreignTarget, named: "objc_retain"))
    let disassembler = Disassembler()
    let boundaries = disassembler.functionStarts(of: consumer).sorted()
    var seen = Set<UInt64>()
    var sites: [[String: Any]] = []
    for address in boundaries.prefix(256) {
        let instructions = await withStableDependencies {
            disassembler.decodeFunction(at: address, boundaries: boundaries, in: consumer)
        }
        for instruction in instructions where instruction.controlFlow == .call || instruction.controlFlow == .branch {
            guard let target = instruction.branchTarget, !seen.contains(target),
                  let raw = resolver.name(forCallTarget: target) else { continue }
            let name = raw.hasPrefix("_") ? String(raw.dropFirst()) : raw
            guard DisassembledFunction.isARCReferenceHelper(name) else { continue }
            seen.insert(target)
            let bytes = try #require(reader.bytes(at: target, count: 16))
            let engine = try #require(CapstoneEngine())
            let code = engine.disassemble(bytes, address: target).map {
                Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                            branchTarget: $0.branchTarget, detail: $0.detail)
            }
            let branch = try #require(code.firstIndex { $0.controlFlow == .branch })
            let island = Array(code[...branch])
            let slot = try #require(RuntimeFunctionReference.pointerSlot(in: island, startingAt: target))
            let pointee = try #require(reader.pointer(at: slot))
            let mapping = try #require(full.mappingAndSlideInfo(for: slot))
            #expect(resolver.arcIdentityContract(forCallTarget: target, named: name))
            #expect(reader.fixedPointer(at: slot) == pointee)
            #expect(!resolver.arcIdentityContract(forCallTarget: target, named: "swift_retainReturningCount"))
            sites.append(["caller": String(instruction.address, radix: 16), "island": String(target, radix: 16),
                          "callee": name, "slot": String(slot, radix: 16), "pointee": String(pointee, radix: 16),
                          "mapping_flags": String(describing: mapping.flags), "code": island.map(\.text)])
        }
        if sites.count >= 12 { break }
    }
    #expect(!sites.isEmpty)
    var mutable: [String: Any]?
    search: for image in [core, objc, consumer] {
        for section in image.sections where ["__DATA", "__DATA_DIRTY", "__AUTH"].contains(section.segmentName)
            && section.address >= 0 && section.size >= 8 {
            for offset in stride(from: 0, to: min(section.size, 1024), by: 8) {
                let slot = UInt64(section.address) + UInt64(offset)
                guard let mapping = full.mappingAndSlideInfo(for: slot),
                      mapping.flags.isDisjoint(with: [.constData, .readOnlyData, .constTproData]),
                      let pointee = reader.pointer(at: slot), pointee != 0 else { continue }
                #expect(reader.fixedPointer(at: slot) == nil)
                mutable = ["image": image.imagePath, "slot": String(slot, radix: 16),
                           "pointee": String(pointee, radix: 16), "mapping_flags": String(describing: mapping.flags)]
                break search
            }
        }
    }
    #expect(mutable != nil)
    try report(["status": "observed", "consumer": consumer.imagePath,
                "cache_image_file": core.url.path, "exports": exports, "sites": sites,
                "mutable_slot": mutable ?? [:]])
}
