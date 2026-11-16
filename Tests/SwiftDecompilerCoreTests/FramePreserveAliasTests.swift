import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let framePreserveAliasFixture = "Fixtures/Sample/libFramePreserveAlias.dylib"

@Test func entryRegisterSpillAliasHasANativeOracleIfPresent() throws {
    guard FileManager.default.fileExists(atPath: framePreserveAliasFixture) else { return }
    let library = try #require(dlopen(framePreserveAliasFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Oracle = @convention(c) () -> Int64
    for (name, expected): (String, Int64) in [("changed", 11), ("untouched", 7)] {
        let symbol = "$s18FramePreserveAlias\(name.count)\(name)SiyF"
        let address = try #require(dlsym(library, symbol))
        #expect(unsafeBitCast(address, to: Oracle.self)() == expected)
    }
}

/// A pointer to the first word can reach the second word that holds entry
/// x19. Preserving that slot across an unknown writer would falsely preserve
/// the fragment's x19 and make its caller return 7 rather than native 11.
@Test func anEntryRegisterSpillDoesNotProveAnObjectBoundaryIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: framePreserveAliasFixture) else { return }
    let full = try await withStableDependencies {
        try await Disassembler().disassemble(path: framePreserveAliasFixture)
    }
    let filtered = try await withStableDependencies {
        try await Disassembler().disassemble(path: framePreserveAliasFixture, functionFilter: "FramePreserveAlias.")
    }
    let streamed = try await withStableDependencies {
        let image = try BinaryLoader.load(path: framePreserveAliasFixture)
        return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
    }
    for functions in [full, filtered, streamed] {
        let changed = try #require(functions.first { $0.displayName.hasPrefix("FramePreserveAlias.changed(") })
        let control = try #require(functions.first { $0.displayName.hasPrefix("FramePreserveAlias.untouched(") })
        for structured in [false, true] {
            let text = structured ? changed.renderStructured() : changed.renderPseudo()
            #expect(!text.contains("return 7"), Comment(rawValue: text))
            #expect(text.contains("return ?") || text.contains("return 11"), Comment(rawValue: text))
            let kept = structured ? control.renderStructured() : control.renderPseudo()
            #expect(!kept.contains("return 11"), Comment(rawValue: kept))
        }
    }
}

@Test func anEntrySpillCannotBoundUnknownWritesButKnownWritesKeepTheirExtent() {
    let initial = Preservation.State(registers: ["sp": .stack(-64), "x0": .stack(-56)],
        slots: [-48: .entry("x19"), -8: .entry("x29")], stackAliases: ["sp", "x0"])
    var unknown = initial
    Preservation.applyCall(CalleeEffect(), inputs: ["x0"], to: &unknown, clobbersMayAliasStack: false)
    #expect(unknown.load(at: -48) == .unknown)
    #expect(unknown.load(at: -8) == .unknown)
    var noPointer = initial
    Preservation.applyCall(CalleeEffect(), inputs: [], to: &noPointer, clobbersMayAliasStack: false)
    #expect(noPointer.load(at: -48) == .entry("x19"))
    #expect(noPointer.load(at: -8) == .entry("x29"))
    let x0 = PhysReg(kind: .gpr, number: 0, widthBits: 64)
    let x9 = PhysReg(kind: .gpr, number: 9, widthBits: 64)
    let effect = CalleeEffect(memoryEffect: .literalStores([
        .init(base: x0, offset: 0, bytes: 8, value: 11, source: x9),
    ], inputs: [x0]))
    var known = initial
    Preservation.applyCall(effect, inputs: ["x0"], to: &known, clobbersMayAliasStack: false)
    #expect(known.load(at: -48) == .entry("x19"))
    #expect(known.load(at: -8) == .entry("x29"))
    Preservation.applyCall(CalleeEffect(), inputs: [], to: &known, clobbersMayAliasStack: false)
    #expect(known.load(at: -48) == .unknown) // the earlier escape persists
}

@Test func anEscapedLowerWordMayReadTheEntrySelfSpilledAboveIt() throws {
    // sub sp,sp,#32; str x20,[sp,#8]; mov x20,xzr; mov x0,sp
    // bl 0x2000; add sp,sp,#32; ret. Analysis-only body, not native ABI code.
    let words: [UInt32] = [0xd10083ff, 0xf90007f4, 0xaa1f03f4, 0x910003e0,
        0x940003fc, 0x910083ff, 0xd65f03c0]
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) } }
    let decoded = engine.disassemble(Data(bytes), address: 0x1000)
    try #require(decoded.count == words.count)
    let function = DisassembledFunction(symbol: "_entry_self_alias", demangledName: nil,
        startAddress: 0x1000, instructions: decoded.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .address)
    let flow = try #require(Preservation.selfRegisterFlow(blocks: function.basicBlocks(), entry: 0x1000,
        addresses: Set(function.instructions.map(\.address)), callEffect: { _ in CalleeEffect() },
        callInputs: { _ in ["x0"] }, forwards: { _ in false }))
    #expect(flow.reads)
}
