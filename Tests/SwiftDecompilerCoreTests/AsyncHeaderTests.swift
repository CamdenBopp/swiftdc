import Foundation
import Testing
@testable import SwiftDecompilerCore

/// A store into a new callee async context's header is async-call
/// bookkeeping, not a statement. At -Onone the compiler moves the
/// `swift_task_alloc` block into x22 and stores the ResumeParent alone,
/// and it rendered `mem64[x22 + 0x8] = (1) await resume partial function
/// for AH.twice(…)` before each await (`asyncheader.swift`).
@Test func aCalleeContextHeaderStoreIsNotAStatementIfPresent() async throws {
    let path = "Fixtures/Sample/libAsyncHeader.Onone.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
    let text = functions.filter { $0.displayName.contains("AH.") }.map { $0.renderStructured() }.joined(separator: "\n")
    #expect(text.contains("let awaited1 = await AH.work(arg0)"), Comment(rawValue: text))
    #expect(!text.contains("= (1) await resume") && !text.contains("= (2) await resume"), Comment(rawValue: text))
}

/// Only the header's 16 bytes: a store past it into the same block is
/// still shown.
@Test func onlyTheContextHeaderIsBookkeepingIfPresent() throws {
    let path = "Fixtures/Sample/libAsyncHeader.Onone.dylib"
    guard FileManager.default.fileExists(atPath: path) else { return }
    //   bl  swift_task_alloc
    //   mov x9, #5
    //   str x9, [x0, #8]       the ResumeParent: hidden
    //   str x9, [x0, #0x18]    past the header: shown
    //   ret
    let words: [UInt32] = [0x94000005, 0xd28000a9, 0xf9000409, 0xf9000c09, 0xd65f03c0]
    let engine = try #require(CapstoneEngine())
    let instructions = engine.disassemble(words.withUnsafeBytes { Data($0) }, address: 0x1000).map {
        Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                    branchTarget: $0.branchTarget, detail: $0.detail)
    }
    try #require(instructions.count == words.count)
    let machO = try BinaryLoader.load(path: path)
    func rendered(allocator: String) -> String {
        let resolver = Disassembler.ReferenceResolver(names: [0x1014: allocator],
            stringRanges: [], machO: machO, demangleSymbol: { _ in nil })
        let context = Disassembler.PerFunctionContext(resolver: resolver, swiftTargets: [],
            objcIndex: ObjCMetadataIndex(methods: [:], fieldMaps: [:]), fieldMaps: [:],
            selfIndex: SelfTypeIndex(bindings: [:]), vtableIndex: VTableIndex(),
            enumCaseIndex: EnumCaseIndex(), payloadEnumIndex: PayloadEnumCaseIndex(),
            classTypeIndex: ClassTypeIndex(), classParameterFields: ClassParameterFieldIndex(),
            asyncIndex: .empty, asyncChainSlots: [:])
        let function = DisassembledFunction(symbol: "_header", demangledName: nil, startAddress: 0x1000,
                                            instructions: instructions, source: .symbol)
        return Disassembler().analyzeFunction(function, context: context).renderStructured()
    }
    let context = rendered(allocator: "swift_task_alloc")
    #expect(!context.contains("+ 0x8] = 5"), Comment(rawValue: context))
    #expect(context.contains("+ 0x18] = 5"), Comment(rawValue: context))
    // Any other block's first words are ordinary memory.
    let other = rendered(allocator: "malloc")
    #expect(other.contains("+ 0x8] = 5") && other.contains("+ 0x18] = 5"), Comment(rawValue: other))
}
