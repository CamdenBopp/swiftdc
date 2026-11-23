import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore

private let asyncInteriorFixture = "Fixtures/Sample/libAsyncInteriorReach.dylib"
private let interiorUnknown: UInt64 = 0x2000
private let interiorObserve: UInt64 = 0x3000

private func interiorBranch(from: UInt64, to: UInt64) -> UInt32 {
    0x94000000 | (UInt32(truncatingIfNeeded: (Int64(to) - Int64(from)) >> 2) & 0x03ff_ffff)
}

private func interiorBody(_ words: [UInt32], at address: UInt64 = 0x1000,
                          names: [UInt64: String] = [:]) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
    let decoded = engine.disassemble(Data(bytes), address: address)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: address == 0x1000 ? "_caller" : "_callee", demangledName: nil,
        startAddress: address, instructions: decoded.map { instruction in
            Instruction(address: instruction.address, text: instruction.text,
                annotation: instruction.branchTarget.flatMap { names[$0] },
                controlFlow: instruction.controlFlow, branchTarget: instruction.branchTarget,
                detail: instruction.detail)
        }, source: .address)
}

private func interiorAnalysis(_ words: [UInt32], names: [UInt64: String],
                              helpers: [UInt64: [UInt32]] = [:], typed: Set<UInt64> = []) throws
    -> (FunctionAnalysis, DisassembledFunction)
{
    let caller = try interiorBody(words, names: names)
    var tracer = ValueTracer()
    for (target, helperWords) in helpers {
        let helper = try interiorBody(helperWords, at: target)
        tracer.calleeMemoryEffects[target] = CalleeMemoryEffect.discover(in: helper)
        tracer.calleeUnwrittenResults[target] = [.x0]
    }
    for call in caller.instructions where call.controlFlow == .call {
        tracer.calleeConventions[call.address] = .direct
    }
    tracer.callResultBank = { name in
        typed.contains { names[$0] == name } ? .integer : .unknown
    }
    let entry = MethodEntryConvention.asyncFunclet(base: nil, seededRegisters: ["x22": .asyncContext])
    return (tracer.analyze(caller, entry: entry), caller)
}

private func interiorObserved(_ analysis: FunctionAnalysis, at address: UInt64) -> AbstractValue {
    analysis.callSites[address]?.arguments.first ?? .unknown
}

@Test func anInteriorWriteCannotPreserveTheParentHeaderButKeepsItsLoadedSnapshot() throws {
    let helper: [UInt32] = [0xf940000a, 0xd2800168, 0xf81e8008, 0xd65f03c0]
    let body = try interiorBody(helper, at: interiorUnknown)
    try #require(CalleeMemoryEffect.discover(in: body) == .unknown)
    // x0 = context + 32; the callee's STUR at -24 overwrites parent +8.
    let reload: [UInt32] = [0x910082c0,
        interiorBranch(from: 0x1004, to: interiorUnknown), 0xf94006c1, 0xd61f0020]
    let snapshot: [UInt32] = [0xf94006d3, 0x910082c0,
        interiorBranch(from: 0x1008, to: interiorUnknown), 0xd61f0260]
    let names = [interiorUnknown: "unknown_parent_writer"]
    let (reloaded, _) = try interiorAnalysis(reload, names: names, helpers: [interiorUnknown: helper])
    let (saved, _) = try interiorAnalysis(snapshot, names: names, helpers: [interiorUnknown: helper])
    #expect(reloaded.indirectControlFlowTargets[0x100c] != .asyncResumeParent)
    #expect(saved.indirectControlFlowTargets[0x100c] == .asyncResumeParent)
}

@Test func anInteriorContextPointerLetsAnUnknownCallReachEarlierSlots() throws {
    let words: [UInt32] = [
        0xd28000e8, 0xf9000ac8, 0x910082c0,
        interiorBranch(from: 0x100c, to: interiorUnknown),
        0xf9400ac0, interiorBranch(from: 0x1014, to: interiorObserve), 0xd65f03c0,
    ]
    let (analysis, _) = try interiorAnalysis(words,
        names: [interiorUnknown: "unknown_writer", interiorObserve: "M.observe(Swift.Int) -> Swift.Int"])
    #expect(interiorObserved(analysis, at: 0x1014) != .immediate(7))
}

@Test func anExportedInteriorContextPointerRemainsWholeContextReach() throws {
    let words: [UInt32] = [
        0x910082c9, 0xf000002a, 0xf9000149, // export context+32 to a global
        0xd28000e8, 0xf9000ac8,             // fresh slot16 = 7 after export
        0xd2800000, 0xd2800009, 0xd280000a,
        interiorBranch(from: 0x1020, to: interiorUnknown),
        0xf9400ac0, interiorBranch(from: 0x1028, to: interiorObserve), 0xd65f03c0,
    ]
    let (analysis, _) = try interiorAnalysis(words,
        names: [interiorUnknown: "global_writer", interiorObserve: "M.observe(Swift.Int) -> Swift.Int"])
    #expect(interiorObserved(analysis, at: 0x1028) != .immediate(7))
}

@Test func anUnknownInteriorWritePreservesAnAlreadyLoadedSnapshot() throws {
    let words: [UInt32] = [
        0xd28000e8, 0xf9000ac8, 0xf9400ad3, 0x910082c0,
        interiorBranch(from: 0x1010, to: interiorUnknown),
        0xaa1303e0, interiorBranch(from: 0x1018, to: interiorObserve), 0xd65f03c0,
    ]
    let (analysis, _) = try interiorAnalysis(words,
        names: [interiorUnknown: "unknown_writer", interiorObserve: "M.observe(Swift.Int) -> Swift.Int"])
    #expect(interiorObserved(analysis, at: 0x1018) == .immediate(7))
}

@Test func aCompleteNoncapturingBodyCanBorrowAnInteriorContextPointer() throws {
    let helper: [UInt32] = [0xd2800168, 0xf9000008, 0xd65f03c0]
    let words: [UInt32] = [
        0xd28000e8, 0xf9000ac8, 0x910082c0,
        interiorBranch(from: 0x100c, to: interiorUnknown),
        0xf9400ac0, interiorBranch(from: 0x1014, to: interiorObserve), 0xd65f03c0,
    ]
    let (analysis, _) = try interiorAnalysis(words,
        names: [interiorUnknown: "bounded_writer", interiorObserve: "M.observe(Swift.Int) -> Swift.Int"],
        helpers: [interiorUnknown: helper])
    #expect(interiorObserved(analysis, at: 0x1014) == .immediate(7))
}

@Test func aCompleteBorrowDoesNotApplyReachFromAnEarlierExternalEscape() throws {
    let helper: [UInt32] = [0xd2800168, 0xf9000008, 0xd65f03c0]
    let words: [UInt32] = [
        0x910082c9, 0xf000002a, 0xf9000149, // durable export of context+32
        0xd28000e8, 0xf9000ac8, 0x910082c0,
        interiorBranch(from: 0x1018, to: interiorUnknown),
        0xf9400ac0, interiorBranch(from: 0x1020, to: interiorObserve), 0xd65f03c0,
    ]
    let (analysis, _) = try interiorAnalysis(words,
        names: [interiorUnknown: "bounded_writer", interiorObserve: "M.observe(Swift.Int) -> Swift.Int"],
        helpers: [interiorUnknown: helper])
    #expect(interiorObserved(analysis, at: 0x1020) == .immediate(7))
}

@Test func aCompleteNegativeFootprintInvalidatesOnlyTheWrittenContextSlot() throws {
    let helper: [UInt32] = [0xd2800168, 0xf81f0008, 0xd65f03c0]
    let words: [UInt32] = [
        0xd28000e8, 0xf9000ac8, 0x910082c0,
        interiorBranch(from: 0x100c, to: interiorUnknown),
        0xf9400ac0, interiorBranch(from: 0x1014, to: interiorObserve),
        0xf94006c1, 0xd61f0020,
    ]
    let (analysis, caller) = try interiorAnalysis(words,
        names: [interiorUnknown: "bounded_negative_writer", interiorObserve: "M.observe(Swift.Int) -> Swift.Int"],
        helpers: [interiorUnknown: helper])
    #expect(interiorObserved(analysis, at: 0x1014) != .immediate(7))
    let exit = try #require(caller.instructions.last?.address)
    #expect(analysis.indirectControlFlowTargets[exit] == .asyncResumeParent)
}

@Test func aTypedResultCannotHideAStillLiveInteriorContextPointer() throws {
    let borrow: UInt64 = 0x2000, unknown: UInt64 = 0x3000, observe: UInt64 = 0x4000
    let helper: [UInt32] = [0xd2800168, 0xf9000008, 0xd65f03c0]
    let words: [UInt32] = [
        0xd28000e8, 0xf9000ac8, 0x910082c0,
        interiorBranch(from: 0x100c, to: borrow),
        interiorBranch(from: 0x1010, to: unknown),
        0xf9400ac0, interiorBranch(from: 0x1018, to: observe), 0xd65f03c0,
    ]
    let names = [borrow: "M.borrow(Swift.Int) -> Swift.Int", unknown: "unknown_writer",
                 observe: "M.observe(Swift.Int) -> Swift.Int"]
    let (analysis, _) = try interiorAnalysis(words, names: names, helpers: [borrow: helper], typed: [borrow])
    #expect(interiorObserved(analysis, at: 0x1018) != .immediate(7))
}

@Test func aBodyThatTransportsThePointerCannotClaimANoncapturingBorrow() throws {
    let transport: UInt64 = 0x2000, unknown: UInt64 = 0x3000, observe: UInt64 = 0x4000
    let helper: [UInt32] = [0xaa0003f3, 0xd2800168, 0xf9000008, 0xd65f03c0] // mov x19,x0; store11
    let words: [UInt32] = [
        0xd28000e8, 0xf9000ac8, 0x910082c0,
        interiorBranch(from: 0x100c, to: transport),
        0xd2800000, interiorBranch(from: 0x1014, to: unknown),
        0xf9400ac0, interiorBranch(from: 0x101c, to: observe), 0xd65f03c0,
    ]
    let names = [transport: "transport_pointer", unknown: "unknown_writer",
                 observe: "M.observe(Swift.Int) -> Swift.Int"]
    let (analysis, _) = try interiorAnalysis(words, names: names, helpers: [transport: helper])
    #expect(interiorObserved(analysis, at: 0x101c) != .immediate(7))
}

@Test func nativeInteriorContextReachMatchesTheFourDocumentedCasesIfPresent() throws {
    guard FileManager.default.fileExists(atPath: asyncInteriorFixture) else { return }
    let library = try #require(dlopen(asyncInteriorFixture, RTLD_NOW | RTLD_LOCAL))
    defer { dlclose(library) }
    typealias Adapter = @convention(c) (UnsafeMutablePointer<UInt64>) -> UInt64
    let cases: [(String, UInt64, UInt64)] = [
        ("negative", 11, 99), ("snapshot", 7, 99), ("global", 11, 99), ("typed", 11, 11),
    ]
    for (name, expected, expected32) in cases {
        let function = unsafeBitCast(try #require(dlsym(library, "async_interior_" + name)), to: Adapter.self)
        var context: [UInt64] = [0, 0, 3, 77, 99, 123, 0, 0]
        let result = context.withUnsafeMutableBufferPointer { function($0.baseAddress!) }
        #expect(result == expected, Comment(rawValue: name))
        #expect(context[2] == 11 && context[4] == expected32, Comment(rawValue: "\(name): \(context)"))
        #expect(context[0] == 0 && context[1] != 0 && context[3] == 77 && context[5] == 123,
                Comment(rawValue: "\(name): \(context)"))
    }
}

@Test func interiorContextReachDeclinesStaleValuesAcrossDisassemblyAPIsIfPresent() async throws {
    guard FileManager.default.fileExists(atPath: asyncInteriorFixture) else { return }
    let image = try BinaryLoader.load(path: asyncInteriorFixture)
    let first = try await withStableDependencies {
        try await Disassembler().disassemble(path: asyncInteriorFixture)
    }
    let members = ["negative", "snapshot", "global", "typed"]
    let selected = first.filter { function in
        members.contains { function.displayName.contains("AsyncInterior.\($0)(") }
    }
    try #require(selected.count == 4)
    let addresses = Set(selected.map(\.startAddress))
    for stage in 0..<4 {
        let functions: [DisassembledFunction] = try await withStableDependencies {
            switch stage {
            case 0: return try await Disassembler().disassemble(path: asyncInteriorFixture)
            case 1: return await Disassembler().disassemble(machO: image)
            case 2: return try await Disassembler().disassemble(path: asyncInteriorFixture,
                                                                  functionFilter: "AsyncInterior.")
            default:
                let streamed: [DisassembledFunction?] = await Disassembler().disassembleStreaming(
                    machO: image, transform: { addresses.contains($0.startAddress) ? $0 : nil })
                return streamed.compactMap { $0 }
            }
        }
        for member in members {
            let function = try #require(functions.first {
                addresses.contains($0.startAddress) && $0.displayName.contains("AsyncInterior.\(member)(")
            }, "stage \(stage): \(member)")
            #expect(function.asyncFunclet?.isEntry == true, "stage \(stage): \(member)")
            for text in [function.renderStructured(), function.renderPseudo()] {
                if member == "snapshot" {
                    #expect(text.contains("AsyncInterior.observe(7)"), Comment(rawValue: text))
                } else {
                    #expect(text.contains("AsyncInterior.observe(?)"), Comment(rawValue: text))
                    #expect(!text.contains("AsyncInterior.observe(7)"), Comment(rawValue: text))
                }
            }
        }
    }
}

@Test(arguments: [2, 3, 7, 9, 17, 18])
func aCompleteBorrowCannotHideOtherPhysicallyUnwrittenContextRegisters(register: Int) throws {
    let borrow: UInt64 = 0x2000, unknown: UInt64 = 0x3000, observe: UInt64 = 0x4000
    let r = UInt32(register)
    // A complete leaf stores 11 at the borrowed interior pointer, leaving
    // that pointer physically live in the selected caller-saved register.
    let helper: [UInt32] = [0xd2800168, 0xf9000008 | (r << 5), 0xd65f03c0]
    let words: [UInt32] = [
        0xd28000e8, 0xf9000ac8, 0x910082c0 | r,
        interiorBranch(from: 0x100c, to: borrow),
        interiorBranch(from: 0x1010, to: unknown),
        0xf9400ac0, interiorBranch(from: 0x1018, to: observe), 0xd65f03c0,
    ]
    let names = [borrow: "bounded_writer", unknown: "unknown_writer",
                 observe: "M.observe(Swift.Int) -> Swift.Int"]
    let (analysis, _) = try interiorAnalysis(words, names: names, helpers: [borrow: helper])
    #expect(interiorObserved(analysis, at: 0x1018) != .immediate(7))

    // A proved literal overwrite removes the physical alias, so a later
    // call must not erase the untouched slot just because the pointer once
    // occupied this register.
    let overwritten = Array(helper.dropLast()) + [0xd2800000 | r, 0xd65f03c0]
    let (control, _) = try interiorAnalysis(words, names: names, helpers: [borrow: overwritten])
    #expect(interiorObserved(control, at: 0x1018) == .immediate(7))
}
