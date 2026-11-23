import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A method was taken for `objc_direct`, with no `_cmd`, when its symbol
/// named a method of a class the image defines and no method list held
/// it. An ordinary IMP named the same way and installed with
/// `class_addMethod` has no list entry either and does take `_cmd`: its
/// arguments were read one register early, and `return a` rendered
/// `return // x0 = arg1`. A direct method is also branched to; the late
/// one is reached only as data. lateimp.m states each body's behaviour.
private func load(_ path: String) async throws -> (functions: [DisassembledFunction], index: ObjCMetadataIndex)? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let functions = try await withStableDependencies {
        try await Disassembler(preset: .default).disassemble(path: path)
    }
    return (functions, ObjCMetadataIndex.build(in: try BinaryLoader.load(path: path)))
}

@Test func anUnlistedImplementationNothingBranchesToIsNotDirectIfPresent() async throws {
    let path = "Fixtures/Sample/libLateIMP.dylib"
    guard let (functions, index) = try await load(path) else { return }
    // Filtered: the whole-file path does not name a local method symbol
    // (ObjCDirectTests works around the same open defect).
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "-[LICrate late:with:]")
    }
    let late = try #require(filtered.first { $0.displayName == "-[LICrate late:with:]" })
    // The premises the old rule had: named like a method, of a class this
    // image defines, in no method list.
    #expect(index.binding(for: late.startAddress) == nil)
    #expect(index.classObjectNames.values.contains("LICrate"))
    // The one it lacks.
    #expect(!index.isBranchedToDirectly(late.startAddress))
    #expect(!Disassembler.isDirectObjCMethod(late.symbol, at: late.startAddress, in: index))
    // With `_cmd` in x1, the first keyword argument is in x2 and the second
    // in x3: neither is spelled as the one after it.
    let analysis = ValueTracer().analyze(late, entry: .objectiveC(argumentCount: 2))
    let call = try #require(late.instructions.first { DisassembledFunction.calleeName(of: $0) == "lateimp_record" })
    #expect(analysis.callSites[call.address]?.arguments.prefix(2) == [.argument(0), .argument(1)])
    for text in [late.renderStructured(), late.renderPseudo()] {
        #expect(!text.contains("x0 = arg1"), Comment(rawValue: text))
    }
    // The listed method beside it is what it always was.
    let listed = try #require(functions.first { $0.displayName.contains("[LICrate listed:with:]") })
    #expect(listed.renderStructured().contains("    return arg0\n"))
}

/// The control: a real direct method is branched to by its callers, and is
/// still direct (objcdirect.m).
@Test(arguments: ["libObjCDirect.O0.dylib", "libObjCDirect.dylib"])
func aDirectMethodItsCallersBranchToIsStillDirectIfPresent(image: String) async throws {
    let path = "Fixtures/Sample/\(image)"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let machO = try BinaryLoader.load(path: path)
    let index = ObjCMetadataIndex.build(in: machO)
    let functions = try await withStableDependencies {
        try await Disassembler().disassemble(path: path, functionFilter: "-[DMBox mix:with:]")
    }
    let method = try #require(functions.first { $0.displayName == "-[DMBox mix:with:]" })
    #expect(index.isBranchedToDirectly(method.startAddress))
    #expect(Disassembler.isDirectObjCMethod(method.symbol, at: method.startAddress, in: index))
}

/// The scan itself: `b` and `bl`, forwards and backwards, and nothing else.
@Test func directBranchTargetsAreReadFromTheWords() {
    let base: UInt64 = 0x1000
    let words: [UInt32] = [
        0x9400_0004,   // bl  +16      -> 0x1010
        0x1400_0002,   // b   +8       -> 0x100c
        0x97FF_FFFE,   // bl  -8       -> 0x1000
        0x17FF_FFFF,   // b   -4       -> 0x1008
        0xD63F_0100,   // blr x8: through a register, no target
        0x5400_0040,   // b.eq +8: conditional, not a call or a tail call
        0xD65F_03C0,   // ret
        0x9000_0001,   // adrp x1: an address taken, not a branch
    ]
    let targets = ObjCMetadataIndex.DirectBranchTargets.targets(inWords: words, at: base)
    #expect(targets == [0x1010, 0x100c, 0x1000, 0x1008])
    // An index built without an image proves no branch.
    #expect(!ObjCMetadataIndex(methods: [:], fieldMaps: [:]).isBranchedToDirectly(0x1000))
}
