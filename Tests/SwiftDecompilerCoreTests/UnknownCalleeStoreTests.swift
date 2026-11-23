import Foundation
import Testing
@testable import SwiftDecompilerCore
import Ccapstone

private let unknownStoreImages = [
    "Fixtures/Sample/libUnknownCalleeStore.O0.dylib", "Fixtures/Sample/libUnknownCalleeStore.O0.stripped.dylib",
    "Fixtures/Sample/libUnknownCalleeStore.O2.dylib", "Fixtures/Sample/libUnknownCalleeStore.O2.stripped.dylib",
    "Fixtures/Sample/libUnknownCalleeStore.Os.dylib", "Fixtures/Sample/libUnknownCalleeStore.Os.stripped.dylib",
]

private func unknownStoreBody(_ words: [UInt32], at start: UInt64) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let bytes = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } })
    let decoded = engine.disassemble(bytes, address: start)
    try #require(decoded.count == words.count)
    return DisassembledFunction(symbol: "unknown_store_probe", demangledName: nil, startAddress: start,
        instructions: decoded.map { Instruction(address: $0.address, text: $0.text,
            controlFlow: $0.controlFlow, branchTarget: $0.branchTarget, detail: $0.detail) }, source: .address)
}

@Test func failedCalleeTransfersNeedAFullPrivateWriteExtent() throws {
    typealias Case = (name: String, root: Int, base: AbstractValue?, offset: Int64, bytes: Int64, stores: Bool, disjoint: Bool)
    let cases: [Case] = [
        ("private-end", 10, .frame(-16), 8, 8, true, true),
        ("caller-frame", 10, .frame(0), 0, 8, true, false),
        ("crossing-end", 10, .frame(-8), 4, 8, true, false),
        ("offset-overflow", 10, .frame(Int64.max - 3), 8, 8, true, false),
        ("negative-overflow", 10, .frame(Int64.min + 4), -8, 8, true, false),
        ("wide-crossing-end", 10, .frame(-8), 0, 16, true, false),
        ("zero-width", 10, .frame(-16), 0, 0, true, false),
        ("negative-width", 10, .frame(-16), 0, -8, true, false),
        ("link-register-is-replaced", 30, .frame(-16), 8, 8, true, false),
        ("missing-root", 10, nil, 8, 8, true, false),
        ("unknown-root", 10, .unknown, 8, 8, true, false),
        ("no-memory-write", 10, nil, 0, 8, false, true),
    ]
    let caller = try unknownStoreBody([0xd28000e9, 0xf9000ac9, 0x940007fe,
        0xf9400ac0, 0xf94006c1, 0xd61f0020], at: 0x1000)
    for c in cases {
        for privatePrefix in [false, true] {
            let root = PhysReg(kind: .gpr, number: c.root, widthBits: 64)
            let source = PhysReg(kind: .gpr, number: 9, widthBits: 64)
            let untracked = PhysReg(kind: .gpr, number: 11, widthBits: 64)
            let output = PhysReg(kind: .gpr, number: 12, widthBits: 64)
            // An unknown non-address output rejects the entire MUST transaction.
            // Its store footprint still controls MAY invalidation independently.
            var writes: [CalleeMemoryEffect.LiteralStore] = c.stores
                ? [.init(base: root, offset: c.offset, bytes: c.bytes, value: 99, source: source)] : []
            let stack = PhysReg(kind: .stackPointer, number: 31, widthBits: 64)
            if privatePrefix && c.stores {
                writes.insert(.init(base: stack, offset: -16, bytes: 8, value: 17, source: source), at: 0)
            }
            var tracer = ValueTracer()
            tracer.calleeConventions[0x1008] = .direct
            tracer.calleeMemoryEffects[0x3000] = .literalStores(writes, inputs: [root, untracked, stack],
                outputs: [.init(destination: output, value: .input(untracked, 0))])
            var seeds: [String: AbstractValue] = ["x22": .asyncContext]
            if let base = c.base { seeds[root.key] = base }
            let analysis = tracer.analyze(caller, entry: .asyncFunclet(base: .swiftFunction(scalarArguments: [:]),
                seededRegisters: seeds))
            #expect(analysis.asyncUnboundedMemoryWrites == !c.disjoint, Comment(rawValue: c.name))
            #expect((analysis.exitValues[0x1014] == .immediate(7)) == c.disjoint, Comment(rawValue: c.name))
            #expect((analysis.indirectControlFlowTargets[0x1014] == .asyncResumeParent) == c.disjoint, Comment(rawValue: c.name))
        }
    }
}

@Test func failedCalleeStoresForgetTheirFrameExtentWithoutInstallingAPrefix() throws {
    let helper = try unknownStoreBody([0xaa0b03ec, 0xd2800c69, 0xf81f8149, 0xd65f03c0], at: 0x3000)
    for loadStoredWord in [false, true] {
        // The private frame has adjacent words: guard=17 and an input word.
        // x10 points above the overwritten input word, so upward escape
        // reach alone cannot forget it. The unknown x11 output rejects MUST.
        let words: [UInt32] = [0xd10083ff, 0xd2800229, 0xf90003e9, 0xf90007e0,
            0x910043ea, 0x940007fb, loadStoredWord ? 0xf94007e0 : 0xf94003e0,
            0x910083ff, 0xd65f03c0]
        let caller = try unknownStoreBody(words, at: 0x1000)
        var tracer = ValueTracer()
        tracer.calleeConventions[0x1014] = .direct
        tracer.calleeMemoryEffects[0x3000] = CalleeMemoryEffect.discover(in: helper)
        let analysis = tracer.analyze(caller, entry: .swiftFunction(scalarArguments: ["x0": 0]))
        let value = analysis.exitValues[0x1020] ?? .unknown
        #expect(value == (loadStoredWord ? .unknown : .immediate(17)))
        // The literal is known in the body, but no prefix of a failed
        // complete transaction may install it as a recovered value.
        #expect(value != .immediate(99))
    }
}

@Test func failedCalleeStoresKeepOnlyProvedAsyncContextCoordinates() throws {
    let base = PhysReg(kind: .gpr, number: 10, widthBits: 64)
    let source = PhysReg(kind: .gpr, number: 9, widthBits: 64)
    let untracked = PhysReg(kind: .gpr, number: 11, widthBits: 64)
    let output = PhysReg(kind: .gpr, number: 12, widthBits: 64)
    let caller = try unknownStoreBody([0xd28000e9, 0xf9000ac9, 0x940007fe,
        0xf9400ac0, 0xf94006c1, 0xd61f0020], at: 0x1000)
    let own = AbstractValue.binary(.add, .asyncContext, .immediate(16))
    let callee = AbstractValue.binary(.add, .asyncCalleeContext, .immediate(16))
    // The failed transaction installs no literal, but its complete store
    // footprints still prove which existing words were not overwritten.
    // Register transport may retain MAY reach for a later unproved call.
    let cases: [(AbstractValue, Int64, Int64, Bool, AbstractValue)] = [
        (own, 0, 8, true, .unknown), (own, 8, 8, true, .immediate(7)),
        (own, -8, 8, false, .immediate(7)), (own, -9, 2, false, .immediate(7)),
        (own, Int64.max, 8, false, .unknown), (own, 0, Int64.max, false, .unknown),
        (callee, 0, 8, false, .unknown),
    ]
    for (input, offset, bytes, parentSurvives, expectedValue) in cases {
        var tracer = ValueTracer()
        tracer.calleeConventions[0x1008] = .direct
        tracer.calleeMemoryEffects[0x3000] = .literalStores([
            .init(base: base, offset: offset, bytes: bytes, value: 99, source: source)
        ], inputs: [base, untracked], outputs: [.init(destination: output, value: .input(untracked, 0))])
        let analysis = tracer.analyze(caller, entry: .asyncFunclet(base: .swiftFunction(scalarArguments: [:]),
            seededRegisters: ["x22": .asyncContext, "x10": input]))
        let exitValue = analysis.exitValues[0x1014] ?? .unknown
        #expect(exitValue == expectedValue)
        #expect(exitValue != .immediate(99))
        #expect((analysis.indirectControlFlowTargets[0x1014] == .asyncResumeParent) == parentSurvives)
    }
    // An unrelated argument-relative pointer cannot borrow the callee
    // context's identity and leave its cached parent pointer alive.
    let child = try unknownStoreBody([0x94000800, 0xf94002c0, 0xd65f03c0], at: 0x1000)
    var tracer = ValueTracer()
    tracer.calleeConventions[0x1000] = .direct
    tracer.calleeMemoryEffects[0x3000] = .literalStores([
        .init(base: base, offset: 16, bytes: 8, value: 99, source: source)
    ], inputs: [base, untracked], outputs: [.init(destination: output, value: .input(untracked, 0))])
    let analysis = tracer.analyze(child, entry: .asyncFunclet(base: .swiftFunction(scalarArguments: [:]),
        seededRegisters: ["x22": .asyncCalleeContext, "x10": .binary(.add, .argument(0), .immediate(16))]))
    #expect(analysis.exitValues[0x1008] != .asyncContext)
}

@Test func anUnknownCompleteCalleeStorePoisonsAnExistingResultBuffer() throws {
    let target: UInt64 = 0x3000
    let helper = try unknownStoreBody([0xd2800c69, 0xf9000549, 0xd65f03c0], at: target)
    for privateFrame in [false, true] {
        var words: [UInt32] = privateFrame ? [0xd10083ff, 0x910043ea] : []
        // Initialize all five words through the entry's genuine result pointer.
        words += [0xd28000e0, 0xf9000100, 0xf9000500, 0xf9000900, 0xf9000d00, 0xf9001100]
        let call = UInt64(0x1000 + 4 * words.count)
        words.append(0x94000000 | UInt32((target - call) / 4))
        if privateFrame { words.append(0x910083ff) }
        words.append(0xd65f03c0)
        let caller = try unknownStoreBody(words, at: 0x1000)
        var tracer = ValueTracer()
        tracer.calleeConventions[call] = .direct
        tracer.calleeMemoryEffects[target] = CalleeMemoryEffect.discover(in: helper)
        let analysis = tracer.analyze(caller)
        let exit = try #require(caller.instructions.last?.address)
        let result = try #require(analysis.exitIndirectResults[exit])
        #expect(result.poisoned == !privateFrame)
        if privateFrame {
            #expect(result.stores.count == 5)
            #expect(result.stores[0]?.value == .immediate(7))
        }
    }
}

@Test func unknownCalleeStoresDeclineContextProofsInEveryPipelineIfPresent() async throws {
    for path in unknownStoreImages {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let image = try BinaryLoader.load(path: path)
        let listed = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        for stage in 0..<5 {
            let recorder = ProbeRecorder()
            let functions = try await Probe.recording(recorder) {
                try await withStableDependencies {
                    switch stage {
                    case 0: return try await Disassembler().disassemble(path: path)
                    case 1: return await Disassembler().disassemble(machO: image)
                    case 2: return try await Disassembler().disassemble(path: path, functionFilter: "UnknownStore.")
                    case 3: return await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
                    default:
                        let each = await Disassembler().analyzeEachFunction(at: Set(listed.map(\.startAddress)), in: image, transform: { $0 })
                        return Array(each.values)
                    }
                }
            }
            let frame = try #require(functions.first { $0.displayName.hasPrefix("UnknownStore.frameWord(") })
            for text in [frame.renderStructured(), frame.renderPseudo()] {
                #expect(text.contains("return ?"), Comment(rawValue: text))
                #expect(!text.contains("return arg0"), Comment(rawValue: text))
                #expect(text.components(separatedBy: "unknown_store_negative_literal(").count == 2, Comment(rawValue: text))
            }
            for (name, privateFrame) in [("unknown", false), ("privateFrame", true), ("crossing", false)] {
                let function = try #require(functions.first { $0.displayName.hasPrefix("UnknownStore." + name + "(") })
                let exit = try #require(function.instructions.last { $0.detail?.id == AARCH64_INS_BR })
                let records = recorder.records.filter { $0.event.id == ProbeEvent.exitRegisters.id
                    && $0.function?.start == function.startAddress && $0.address == exit.address }
                // analyzeEach omits the async chain context. Its existing
                // decline is retained; replay below checks the known ABI.
                if stage == 4 {
                    #expect(records.isEmpty)
                    #expect(exit.controlFlow == .branch)
                } else if privateFrame {
                    let record = try #require(records.first)
                    #expect(record["x0"] == ProbeValue.abstractValue(.immediate(7)))
                    #expect(exit.controlFlow == .return)
                } else {
                    #expect(records.isEmpty, Comment(rawValue: path + " stage " + String(stage)))
                    #expect(exit.controlFlow == .branch)
                }
                let raw = DisassembledFunction(symbol: function.symbol, demangledName: function.demangledName,
                    startAddress: function.startAddress, instructions: function.instructions.map {
                        $0.detail?.id == AARCH64_INS_BR
                            ? Instruction(address: $0.address, text: $0.text, controlFlow: .branch,
                                branchTarget: $0.branchTarget, detail: $0.detail) : $0
                    }, source: function.source)
                var tracer = ValueTracer()
                for call in raw.instructions where call.controlFlow == .call {
                    let target = try #require(call.branchTarget)
                    let helper = try #require(listed.first { $0.startAddress == target })
                    tracer.calleeMemoryEffects[target] = CalleeMemoryEffect.discover(in: helper)
                    tracer.calleeConventions[call.address] = .direct
                }
                let analysis = tracer.analyze(raw, entry: .asyncFunclet(base: .swiftFunction(scalarArguments: [:]),
                    seededRegisters: ["x22": .asyncContext]))
                #expect(analysis.asyncUnboundedMemoryWrites == !privateFrame)
                #expect((analysis.exitValues[exit.address] == .immediate(7)) == privateFrame)
                #expect((analysis.indirectControlFlowTargets[exit.address] == .asyncResumeParent) == privateFrame)
            }
        }
    }
}

#if arch(arm64)
@Test func unknownCalleeStoreNativeControlsIfPresent() throws {
    for path in ["Fixtures/Sample/unknown-store-O0-oracle", "Fixtures/Sample/unknown-store-O2-oracle", "Fixtures/Sample/unknown-store-Os-oracle"] {
        guard FileManager.default.fileExists(atPath: path) else { continue }
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path); process.standardOutput = pipe; process.standardError = pipe
        try process.run(); let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, Comment(rawValue: output))
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "PASS 35 native unknown-store context/buffer/frame observations")
    }
}
#endif

@Test func anUnknownCompleteCalleeStoreCannotProveAnAsyncContextUnchanged() throws {
    let target: UInt64 = 0x3000
    // Unknown x11 prevents a complete register-output transaction even
    // when the store's x10 base is a known private-frame coordinate.
    let helper = try unknownStoreBody([0xaa0b03ec, 0xd2800c69, 0xf9000549, 0xd65f03c0], at: target)
    for privateFrame in [false, true] {
        for explicitUnknown in [false, true] {
            var words: [UInt32] = privateFrame ? [0xd10083ff, 0x910043ea] : []
            // Own context slot 16 starts at 7; a disjoint private frame is safe.
            words += [0xd28000e9, 0xf9000ac9]
            let call = UInt64(0x1000 + 4 * words.count)
            words.append(0x94000000 | UInt32((target - call) / 4))
            words += [0xf9400ac0, 0xf94006c1]
            if privateFrame { words.append(0x910083ff) }
            words.append(0xd61f0020)
            let caller = try unknownStoreBody(words, at: 0x1000)
            var tracer = ValueTracer()
            tracer.calleeConventions[call] = .direct
            tracer.calleeMemoryEffects[target] = CalleeMemoryEffect.discover(in: helper)
            var seeds: [String: AbstractValue] = ["x22": .asyncContext]
            if explicitUnknown { seeds["x10"] = .unknown }
            let entry = MethodEntryConvention.asyncFunclet(base: .swiftFunction(scalarArguments: [:]),
                seededRegisters: seeds)
            let analysis = tracer.analyze(caller, entry: entry)
            let exit = try #require(caller.instructions.last?.address)
            if privateFrame {
                #expect(!analysis.asyncUnboundedMemoryWrites)
                #expect(analysis.exitValues[exit] == .immediate(7))
                #expect(analysis.indirectControlFlowTargets[exit] == .asyncResumeParent)
            } else {
                #expect(analysis.asyncUnboundedMemoryWrites)
                #expect(analysis.exitValues[exit] != .immediate(7))
                #expect(analysis.indirectControlFlowTargets[exit] != .asyncResumeParent)
            }
        }
    }
}
