import Darwin
import Foundation
import Testing
@testable import SwiftDecompilerCore
import Ccapstone

private let bodyTransferFixtures = [
    "Fixtures/Sample/libCalleeBodyTransfer.dylib",
    "Fixtures/Sample/libCalleeBodyTransfer.opt.dylib",
    "Fixtures/Sample/libCalleeBodyTransfer.size.dylib",
]

@Test func completeBodyTransfersHaveNativeOraclesIfPresent() throws {
    for path in bodyTransferFixtures where FileManager.default.fileExists(atPath: path) {
        let library = try #require(dlopen(path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(library) }
        typealias Entry = @convention(c) () -> Int64
        for (name, expected) in [
            ("negative_plan_caller_frame_oracle", Int64(199)),
            ("negative_plan_transport_oracle", Int64(199)),
            ("complete_body_own_alias_oracle", Int64(199)),
            ("complete_body_nonstandard_oracle", Int64(199)),
            ("complete_body_escape_oracle", Int64(199)),
            ("complete_body_captured_oracle", Int64(199)),
            ("complete_body_fallback_oracle", Int64(199)),
            ("complete_body_swap_oracle", Int64(1)),
            ("complete_body_order_oracle", Int64(1)),
            ("complete_body_vector_oracle", Int64(45)),
            ("complete_body_reciprocal_oracle", Int64(122)),
            ("complete_body_global_alias_oracle", Int64(199)),
            ("complete_body_stale_field_oracle", Int64(299)),
            ("complete_body_readonly_field_oracle", Int64(202)),
            ("complete_body_async_own_oracle", Int64(99)),
            ("complete_body_async_private_oracle", Int64(7)),
            ("complete_body_memset_caller_oracle", Int64(100)),
            ("complete_body_q_narrow_oracle", Int64(9)),
        ] {
            let entry = try #require(dlsym(library, name))
            #expect(unsafeBitCast(entry, to: Entry.self)() == expected, "\(path): \(name)")
        }
    }
}

@Test func completeBodyAliasesCannotReturnTheUnmodifiedProducerIfPresent() async throws {
    for path in bodyTransferFixtures where FileManager.default.fileExists(atPath: path) {
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "PlanAlias.")
        }
        let streamed = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        for functions in [listing, array, filtered, streamed, Array(each.values)] {
            for name in ["callerStore", "transportAddress", "ownAlias", "nonstandardAlias", "escapeAddress", "escapedCapture", "fallbackInput", "globalAddressAlias", "memsetCallerStore"] {
                let function = try #require(functions.first { $0.displayName.hasPrefix("PlanAlias.\(name)(") })
                let exit = try #require(function.instructions.last { $0.controlFlow == .return })
                #expect(exit.exit?.statement == "return ?", "\(path): \(name)")
            }
        }
    }
}

@Test func resultWritesInvalidateCallerOwnedFrameSnapshotsIfPresent() async throws {
    for path in bodyTransferFixtures where FileManager.default.fileExists(atPath: path) {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let function = try #require(functions.first { $0.displayName.hasPrefix("PlanAlias.reciprocalFrameRead(") })
        let analysis = tracerForBodyTransfers(functions, in: function).analyze(function)
        let exit = try #require(function.instructions.last { $0.controlFlow == .return })
        let result = try #require(analysis.exitIndirectResults[exit.address])
        #expect(result.stores[16]?.value == .unknown, "\(path): native c=2; pre-call frame snapshot7 is stale")
        for text in [function.renderStructured(), function.renderPseudo()] {
            #expect(!text.contains("c: 7"), Comment(rawValue: text))
        }
    }
}

@Test func completeBodyFieldCopiesKeepOnlyCurrentFieldNamesIfPresent() async throws {
    for path in bodyTransferFixtures where FileManager.default.fileExists(atPath: path) {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        for (member, expected): (String, AbstractValue) in [("staleCopy", .unknown), ("readOnlyCopy", .selfFieldValue(offset: 24))] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("PlanAlias.FieldBox.\(member)(") })
            let analysis = tracerForBodyTransfers(functions, in: function).analyze(function, entry: .swiftInstance(scalarArguments: [:]))
            let observer = try #require(function.instructions.first { DisassembledFunction.calleeName(of: $0) == "complete_body_observe_old_field" })
            #expect((analysis.callSites[observer.address]?.arguments.first ?? .unknown) == expected, "\(path): \(member)")
        }
    }
}

@Test func anX8ReadDoesNotOverrideADirectResultContractIfPresent() async throws {
    for path in bodyTransferFixtures where FileManager.default.fileExists(atPath: path) {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let function = try #require(functions.first { $0.displayName.hasPrefix("PlanAlias.FieldBox.staleCopy(") })
        let call = try #require(function.instructions.first {
            DisassembledFunction.calleeName(of: $0) == "complete_body_mutate_and_copy_field"
        })
        let observer = try #require(function.instructions.first {
            DisassembledFunction.calleeName(of: $0) == "complete_body_observe_old_field"
        })
        var tracer = tracerForBodyTransfers(functions, in: function)
        // The native oracle proves this leaf returns the old scalar in x0.
        // A body-derived x8-read classification cannot replace that known
        // direct return with physical outputs of an indirect-result adapter.
        tracer.calleeConventions[call.address] = .indirect(sizeBytes: nil)
        tracer.callResultBank = { $0 == "complete_body_mutate_and_copy_field" ? .integer : .unknown }
        let analysis = tracer.analyze(function, entry: .swiftInstance(scalarArguments: [:]))
        #expect(analysis.callSites[observer.address]?.arguments.first == .callResult(call.address))
    }
}

@Test func completeBodyStoresUseTheAsyncMemoryOwnerIfPresent() async throws {
    for path in bodyTransferFixtures where FileManager.default.fileExists(atPath: path) {
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "PlanAlias.async")
        }
        let streamed = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        for (route, functions) in [listing, array, filtered, streamed, Array(each.values)].enumerated() {
            for (member, aliasesContext) in [("asyncOwnWrite", true), ("asyncPrivateWrite", false)] {
                let function = try #require(functions.first { $0.displayName.hasPrefix("PlanAlias.\(member)(") })
                // analyzeEachFunction intentionally omits async grouping.
                if route < 4 { #expect(function.asyncFunclet?.isEntry == true) }
                // Enrichment can classify a proven BR as a return. Replay the
                // decoded BR for this independent raw-state assertion.
                let raw = DisassembledFunction(symbol: function.symbol, demangledName: function.demangledName,
                    startAddress: function.startAddress, instructions: function.instructions.map {
                        $0.detail?.id == AARCH64_INS_BR
                            ? Instruction(address: $0.address, text: $0.text, controlFlow: .branch,
                                branchTarget: $0.branchTarget, detail: $0.detail, callee: .kept($0.callee)) : $0
                    }, source: function.source)
                let tracer = tracerForBodyTransfers(array, in: raw)
                let entry = MethodEntryConvention.asyncFunclet(base: .swiftFunction(scalarArguments: [:]),
                    seededRegisters: ["x22": .asyncContext])
                let analysis = tracer.analyze(raw, entry: entry)
                let branch = try #require(raw.instructions.last { $0.controlFlow == .branch })
                #expect(analysis.asyncUnboundedMemoryWrites == aliasesContext)
                if aliasesContext {
                    #expect(analysis.exitValues[branch.address] != .immediate(7))
                    #expect(analysis.indirectControlFlowTargets[branch.address] != .asyncResumeParent)
                } else {
                    #expect(analysis.exitValues[branch.address] == .immediate(7))
                    #expect(analysis.indirectControlFlowTargets[branch.address] == .asyncResumeParent)
                }
            }
        }
    }
}

private func tracerForBodyTransfers(_ functions: [DisassembledFunction], in caller: DisassembledFunction) -> ValueTracer {
    var tracer = ValueTracer()
    let targets = Dictionary(functions.map { ($0.startAddress, $0) }, uniquingKeysWith: { a, _ in a })
    for function in functions {
        // The ordinary compiler maker can be treated as an unmodeled body.
        // Its independent LLVM/native contract still proves40-byte sret.
        if function.symbol != "_negative_may_make_packet" {
            tracer.calleeMemoryEffects[function.startAddress] = CalleeMemoryEffect.discover(in: function)
        }
    }
    for instruction in caller.instructions where instruction.controlFlow == .call {
        let target = instruction.branchTarget.flatMap { targets[$0] }
        tracer.calleeConventions[instruction.address] =
            target?.symbol == "_negative_may_make_packet" || target?.displayName.hasPrefix("PlanAlias.literalProducer(") == true
            ? .indirect(sizeBytes: 40) : .direct
    }
    return tracer
}

@Test func completeBodyOutputsRetainTheirAddressSpacesIfPresent() async throws {
    for path in bodyTransferFixtures where FileManager.default.fileExists(atPath: path) {
        let functions = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        for name in ["transportAddress", "ownAlias", "nonstandardAlias", "fallbackInput", "escapeAddress", "escapedCapture", "memsetCallerStore"] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("PlanAlias.\(name)(") })
            let analysis = tracerForBodyTransfers(functions, in: function).analyze(function)
            let ret = try #require(function.instructions.last { $0.controlFlow == .return })
            let result = try #require(analysis.exitIndirectResults[ret.address])
            #expect(result.poisoned, "\(path): \(name)")
            if name == "transportAddress" || name == "ownAlias" {
                let write = try #require(analysis.memoryWrites.values.first {
                    $0.baseRegister == "x0" && $0.displacement == 8 && $0.values == [.immediate(99)]
                })
                #expect(write.base == (name == "transportAddress" ? .frame(64) : .indirectResultPointer))
                #expect(write.kind == (name == "transportAddress" ? "frame" : "result"))
            }
            if name == "nonstandardAlias" { #expect(result.stores[8]?.value == .immediate(99)) }
            if name == "fallbackInput" {
                // x1 is absent after the unmodeled compiler maker. No prefix
                // of the failed transaction may enter the result buffer.
                #expect(result.stores.isEmpty)
            }
        }
    }
}

private func transferBody(_ words: [UInt32], at address: UInt64) throws -> DisassembledFunction {
    let engine = try #require(CapstoneEngine())
    let data = Data(words.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (8 * $0)) } })
    let instructions = engine.disassemble(data, address: address)
    try #require(instructions.count == words.count)
    return DisassembledFunction(symbol: "_transfer_control", demangledName: nil,
        startAddress: address, instructions: instructions.map {
            Instruction(address: $0.address, text: $0.text, controlFlow: $0.controlFlow,
                branchTarget: $0.branchTarget, detail: $0.detail)
        }, source: .address)
}

@Test func completeBodyRegisterOutputsUseTheSameEntrySnapshot() throws {
    // The native swap oracle independently executes the same three moves.
    let callee = try transferBody([0xaa0003e9, 0xaa0103e0, 0xaa0903e1, 0xd65f03c0], at: 0x2000)
    let caller = try transferBody([0xd28000e0, 0xd2800161, 0x940003fe, 0x940007fd, 0xd65f03c0], at: 0x1000)
    var tracer = ValueTracer()
    tracer.calleeMemoryEffects[0x2000] = CalleeMemoryEffect.discover(in: callee)
    let analysis = tracer.analyze(caller)
    let arguments = try #require(analysis.callSites[0x100c]?.arguments)
    #expect(Array(arguments.prefix(2)) == [.immediate(11), .immediate(7)])
}

@Test func partialIndirectCoverageDoesNotInventAWholeResult() throws {
    // mov x9,9;dup v0.2d,x9;stp q0,q0,[x8];ret: only32 of40 bytes.
    let callee = try transferBody([0xd2800129, 0x4e080d20, 0xad000100, 0xd65f03c0], at: 0x2000)
    // bl 0x2000;ldr x0,[x8,32];ret. The fifth word is the pre-call5.
    let caller = try transferBody([0x94000400, 0xf9401100, 0xd65f03c0], at: 0x1000)
    var tracer = ValueTracer(calleeConventions: [0x1000: .indirect(sizeBytes: 40)])
    tracer.calleeMemoryEffects[0x2000] = CalleeMemoryEffect.discover(in: callee)
    let entry = MethodEntryConvention.swiftValueInstance(seededRegisters: [
        "sp": .frame(-64), "x8": .frame(-56), "stack@-24": .immediate(5),
    ])
    #expect(tracer.analyze(caller, entry: entry).exitValues[0x1008] == .immediate(5))
}

@Test func completeBodyQStoresKeepBitsAcrossNarrowVectorReadsIfPresent() async throws {
    for path in bodyTransferFixtures where FileManager.default.fileExists(atPath: path) {
        let image = try BinaryLoader.load(path: path)
        let listing = try await withStableDependencies { try await Disassembler().disassemble(path: path) }
        let array = await withStableDependencies { await Disassembler().disassemble(machO: image) }
        let filtered = try await withStableDependencies {
            try await Disassembler().disassemble(path: path, functionFilter: "PlanAlias.qNarrowRead")
        }
        let streamed = await withStableDependencies {
            await Disassembler().disassembleStreaming(machO: image, transform: { $0 })
        }
        let each = await withStableDependencies {
            await Disassembler().analyzeEachFunction(at: Set(array.map(\.startAddress)), in: image, transform: { $0 })
        }
        for functions in [listing, array, filtered, streamed, Array(each.values)] {
            let function = try #require(functions.first { $0.displayName.hasPrefix("PlanAlias.qNarrowRead(") })
            let ret = try #require(function.instructions.last { $0.controlFlow == .return })
            #expect(ret.exit?.statement == "return 9", "\(path)")
            let analysis = tracerForBodyTransfers(array, in: function).analyze(function)
            #expect(analysis.exitValues[ret.address] == .immediate(9), "\(path)")
        }
    }
}
